#!/bin/bash
# brain-note-ingest.sh - Process incoming memo text -> brain-inbox + second-brain notes
# Usage: brain-note-ingest.sh --text "..." [--title "..."] [--summary "..."] [--my-opinion "..."] [--dry-run] [--force] [--ops-init|--no-ops-init]
# Env: BRAIN_INBOX_CHANNEL_ID, BRAIN_OPS_CHANNEL_ID, TELEGRAM_TARGET

set -eo pipefail

# === Load env ===
set +u
source "$(dirname "$0")/env-loader.sh" 2>/dev/null || true
source "$(dirname "$0")/lib/quality-gate.sh" 2>/dev/null || true
set -u

# === Config ===
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INBOX_CHANNEL="${BRAIN_INBOX_CHANNEL_ID:-${DISCORD_INBOX:-1478250668052713647}}"
OPS_CHANNEL="${BRAIN_OPS_CHANNEL_ID:-${DISCORD_TODAY:-1478250773228814357}}"
TELEGRAM_TARGET="${TELEGRAM_TARGET:-${TELEGRAM_CHAT_ID:-62403941}}"
SECOND_BRAIN_DIR="${SECOND_BRAIN_DIR:-${WORKSPACE_ROOT}/memory/second-brain}"
NOTES_FILE="${SECOND_BRAIN_DIR}/notes.md"
NOTE_REGISTRY="${SECOND_BRAIN_DIR}/.note-registry.jsonl"
PENDING_QUEUE="${SECOND_BRAIN_DIR}/.pending-note-queue.jsonl"
CAPTURE_LOG="${WORKSPACE_ROOT}/data/capture-log.jsonl"
ANALYZER_SCRIPT="${SCRIPT_DIR}/brain-content-analyze.sh"
AUTO_ANALYZE="${BRAIN_INBOX_ANALYZE_AUTO:-true}"
AUTO_OPS_INIT="${BRAIN_OPS_AUTO_INIT:-true}"
MEMO_TELEGRAM_MIRROR="${BRAIN_MEMO_TELEGRAM_MIRROR:-${BRAIN_ROUTER_ACK_TELEGRAM:-false}}"
MAX_RETRIES=1
FORCE=false
DRY_RUN=false

# === Args ===
TEXT=""
TITLE=""
SUMMARY=""
MY_OPINION=""
OPS_INIT=false
NO_OPS_INIT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --text) TEXT="$2"; shift 2 ;;
        --title) TITLE="$2"; shift 2 ;;
        --summary) SUMMARY="$2"; shift 2 ;;
        --my-opinion) MY_OPINION="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --force) FORCE=true; shift ;;
        --ops-init) OPS_INIT=true; shift ;;
        --no-ops-init) NO_OPS_INIT=true; shift ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$TEXT" ]]; then
    echo "ERROR: --text required" >&2
    exit 1
fi

TEXT="$(python3 - <<'PY' "$TEXT"
import sys
t = sys.argv[1].replace('\r\n', '\n').replace('\r', '\n')
print(t.strip())
PY
)"

if [[ -z "$TEXT" ]]; then
    echo "ERROR: memo text is empty after trim" >&2
    exit 1
fi

if [[ -z "$TITLE" ]]; then
    TITLE="$(python3 - <<'PY' "$TEXT"
import sys
t = sys.argv[1].strip()
first = t.splitlines()[0].strip() if t else "Telegram Memo"
print(first[:60] if first else "Telegram Memo")
PY
)"
fi

is_truthy() {
    local v
    v="$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')"
    [[ "$v" == "1" || "$v" == "true" || "$v" == "yes" || "$v" == "on" ]]
}

is_placeholder_summary() {
    local s="${1:-}"
    [[ -z "$s" || "$s" == "Auto-captured memo from Telegram" || "$s" == "Auto-captured from Telegram" ]]
}

is_placeholder_opinion() {
    local s="${1:-}"
    [[ -z "$s" || "$s" == "자동 메모 수집 항목 (후속 검토 필요)" || "$s" == "Not provided" || "$s" == "_Not provided_" ]]
}

NEXT_ACTION="후속 검토"
PRIORITY_TAG="p3"
AUTO_SHOULD_OPS=false

if is_truthy "$AUTO_ANALYZE" && [[ -x "$ANALYZER_SCRIPT" ]]; then
    if is_placeholder_summary "$SUMMARY" || is_placeholder_opinion "$MY_OPINION"; then
        ANALYZE_JSON="$("$ANALYZER_SCRIPT" --mode memo --title "$TITLE" --text "$TEXT" 2>/dev/null || true)"
        if [[ -n "$ANALYZE_JSON" ]]; then
            parsed_summary="$(echo "$ANALYZE_JSON" | jq -r '.summary // empty' 2>/dev/null || true)"
            parsed_opinion="$(echo "$ANALYZE_JSON" | jq -r '.my_opinion // empty' 2>/dev/null || true)"
            parsed_action="$(echo "$ANALYZE_JSON" | jq -r '.next_action // empty' 2>/dev/null || true)"
            parsed_priority="$(echo "$ANALYZE_JSON" | jq -r '.priority // "p3"' 2>/dev/null || true)"
            parsed_should_ops="$(echo "$ANALYZE_JSON" | jq -r '.should_ops // false' 2>/dev/null || true)"
            [[ -n "$parsed_summary" ]] && SUMMARY="$parsed_summary"
            [[ -n "$parsed_opinion" ]] && MY_OPINION="$parsed_opinion"
            [[ -n "$parsed_action" ]] && NEXT_ACTION="$parsed_action"
            [[ -n "$parsed_priority" ]] && PRIORITY_TAG="$parsed_priority"
            [[ "$parsed_should_ops" == "true" ]] && AUTO_SHOULD_OPS=true
        fi
    fi
fi

[[ -z "$SUMMARY" ]] && SUMMARY="Auto-captured memo from Telegram"
[[ -z "$MY_OPINION" ]] && MY_OPINION="자동 메모 수집 항목 (후속 검토 필요)"

if [[ "$OPS_INIT" != "true" && "$NO_OPS_INIT" != "true" ]] && is_truthy "$AUTO_OPS_INIT"; then
    if [[ "$AUTO_SHOULD_OPS" == "true" ]]; then
        OPS_INIT=true
    fi
fi

TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

queue_for_later() {
    local esc_text esc_summary esc_opinion
    esc_text=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$TEXT")
    esc_summary=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$SUMMARY")
    esc_opinion=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$MY_OPINION")
    local entry
    entry=$(printf '{"timestamp":"%s","hash":"%s","title":"%s","text":%s,"summary":%s,"my_opinion":%s}\n' \
      "$TIMESTAMP" "${NOTE_HASH:-pending}" "$TITLE" "$esc_text" "$esc_summary" "$esc_opinion")

    if $DRY_RUN; then
        echo "[DRY-RUN] Would queue memo entry"
        return 0
    fi

    mkdir -p "$SECOND_BRAIN_DIR"
    printf '%s\n' "$entry" >> "$PENDING_QUEUE"
    echo "QUEUED: Memo entry queued for retry"
}

send_to_discord() {
    local channel="$1"
    local message="$2"

    if $DRY_RUN; then
        echo "[DRY-RUN] Would send to Discord channel $channel:"
        echo "$message" | head -10
        echo "..."
        return 0
    fi

    if [[ -z "$channel" ]]; then
        echo "WARN: Discord channel ID not configured, queueing locally" >&2
        return 1
    fi

    local attempt=1
    while [[ $attempt -le $((MAX_RETRIES + 1)) ]]; do
        if openclaw message send --channel discord --target "$channel" --message "$message" --silent 2>/dev/null; then
            return 0
        fi
        echo "WARN: Discord send failed (attempt $attempt)" >&2
        sleep 1
        ((attempt++))
    done

    return 1
}

send_to_telegram() {
    local target="$1"
    local message="$2"

    if $DRY_RUN; then
        echo "[DRY-RUN] Would send to Telegram target $target:"
        echo "$message" | head -10
        echo "..."
        return 0
    fi

    if [[ -z "$target" ]]; then
        echo "WARN: Telegram target not configured" >&2
        return 1
    fi

    local attempt=1
    while [[ $attempt -le $((MAX_RETRIES + 1)) ]]; do
        if openclaw message send --channel telegram --target "$target" --message "$message" --silent 2>/dev/null; then
            return 0
        fi
        echo "WARN: Telegram send failed (attempt $attempt)" >&2
        sleep 1
        ((attempt++))
    done

    return 1
}

check_duplicate() {
    local hash="$1"
    if [[ -f "$NOTE_REGISTRY" ]] && grep -q "\"hash\":\"$hash\"" "$NOTE_REGISTRY"; then
        return 0
    fi
    return 1
}

register_note() {
    local esc_title
    esc_title=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$TITLE")
    local entry
    entry=$(printf '{"hash":"%s","title":%s,"timestamp":"%s"}\n' "$NOTE_HASH" "$esc_title" "$TIMESTAMP")

    if $DRY_RUN; then
        echo "[DRY-RUN] Would register note hash: $NOTE_HASH"
        return 0
    fi

    mkdir -p "$SECOND_BRAIN_DIR"
    printf '%s\n' "$entry" >> "$NOTE_REGISTRY"
}

write_to_second_brain() {
    local memo_block
    memo_block="$(printf '%s\n' "$TEXT" | sed 's/^/> /')"
    local entry
    entry="## [$TIMESTAMP] $TITLE
- Type: memo
- Hash: ${NOTE_HASH:-pending}
- Status: TODO
- Added: $(date "+%Y-%m-%d")
- Summary: ${SUMMARY}
- My Opinion: ${MY_OPINION}
- Memo:
${memo_block}

"

    if $DRY_RUN; then
        echo "[DRY-RUN] Would write memo to $NOTES_FILE:"
        echo "$entry"
        return 0
    fi

    mkdir -p "$SECOND_BRAIN_DIR"
    touch "$NOTES_FILE"
    cp "$NOTES_FILE" "${NOTES_FILE}.bak" 2>/dev/null || true

    local temp_file
    temp_file=$(mktemp)
    { echo "$entry"; cat "$NOTES_FILE"; } > "$temp_file"
    mv "$temp_file" "$NOTES_FILE"
    echo "OK: Written to second-brain/notes.md"
}

append_capture_log() {
    if $DRY_RUN; then
        echo "[DRY-RUN] Would append capture-log entry (category: memo)"
        return 0
    fi

    mkdir -p "$(dirname "$CAPTURE_LOG")"

    local esc_summary esc_raw esc_image
    esc_summary=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$SUMMARY")
    esc_raw=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$TEXT")
    esc_image=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "")

    printf '{"timestamp":"%s","category":"memo","summary":%s,"raw":%s,"urls":[],"imagePath":%s,"source":"brain-note-ingest","hash":"%s"}\n' \
      "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$esc_summary" "$esc_raw" "$esc_image" "$NOTE_HASH" >> "$CAPTURE_LOG"
}

NOTE_HASH=$(printf '%s' "$TEXT" | sha256sum | cut -c1-16)

if ! $FORCE && check_duplicate "$NOTE_HASH"; then
    echo "SKIP: Duplicate memo detected (hash: $NOTE_HASH)"
    echo "Use --force to process anyway"
    exit 0
fi

PREVIEW="$(python3 - <<'PY' "$TEXT"
import sys
t = sys.argv[1]
limit = 700
print((t[:limit] + "\n...") if len(t) > limit else t)
PY
)"

DISCORD_OK=true

INBOX_MSG="📝 **New Memo**

**Title:** $TITLE
**Memo:** 
$PREVIEW
**Summary:** $SUMMARY
**My Opinion:** $MY_OPINION
**Next Action:** $NEXT_ACTION
**Priority:** $PRIORITY_TAG
**Time:** $TIMESTAMP

Status: TODO"

if ! send_to_discord "$INBOX_CHANNEL" "$INBOX_MSG"; then
    echo "WARN: Discord inbox send failed" >&2
    DISCORD_OK=false
fi

if is_truthy "$MEMO_TELEGRAM_MIRROR"; then
    if ! send_to_telegram "$TELEGRAM_TARGET" "$INBOX_MSG"; then
        echo "WARN: Telegram mirror send failed" >&2
        DISCORD_OK=false
    fi
else
    echo "INFO: Telegram memo mirror disabled (BRAIN_MEMO_TELEGRAM_MIRROR=false)"
fi

if [[ "$OPS_INIT" == "true" ]]; then
    OPS_MSG="🧵 **Memo Processing Entry**

**Item:** $TITLE
**Hash:** \`$NOTE_HASH\`
**Summary:** $SUMMARY
**My Opinion:** $MY_OPINION
**Next Action:** $NEXT_ACTION
**Priority:** $PRIORITY_TAG
**Status:** 📋 TODO"
    if ! send_to_discord "$OPS_CHANNEL" "$OPS_MSG"; then
        echo "WARN: Ops message send failed" >&2
        DISCORD_OK=false
    fi
fi

write_to_second_brain
append_capture_log
register_note

if ! $DISCORD_OK && ! $DRY_RUN; then
    queue_for_later
    echo "OK: Memo pipeline complete (local-only mode, queued for sync)"
else
    echo "OK: Memo pipeline complete (hash: $NOTE_HASH)"
fi
