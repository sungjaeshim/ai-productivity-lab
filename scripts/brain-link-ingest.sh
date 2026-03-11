#!/bin/bash
# brain-link-ingest.sh - Process incoming links → brain-inbox + second-brain (+ optional/auto ops entry)
# Usage: brain-link-ingest.sh --url "..." [--title "..."] [--summary "..."] [--my-opinion "..."] [--dry-run] [--force] [--ops-init|--no-ops-init]
# Env: BRAIN_INBOX_CHANNEL_ID, BRAIN_OPS_CHANNEL_ID, TELEGRAM_TARGET
#
# 4-Field Requirement:
# - A valid brain entry MUST have: URL, TITLE, SUMMARY, MY_OPINION
# - If any missing (and not --force), entry is queued for manual review
#
# Cross-context constraints handled:
# - Discord API unavailable: writes to local queue for later sync
# - Ops entry can be auto-enabled by analyzer (BRAIN_OPS_AUTO_INIT=true)

set -eo pipefail

# === Load env ===
set +u
source "$(dirname "$0")/env-loader.sh" 2>/dev/null || true
set -u

# === Config ===
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INBOX_CHANNEL="${BRAIN_INBOX_CHANNEL_ID:-${DISCORD_INBOX:-1478250668052713647}}"
OPS_CHANNEL="${BRAIN_OPS_CHANNEL_ID:-${DISCORD_TODAY:-1478250773228814357}}"
TELEGRAM_TARGET="${TELEGRAM_TARGET:-${TELEGRAM_CHAT_ID:-62403941}}"
SECOND_BRAIN_DIR="${SECOND_BRAIN_DIR:-${WORKSPACE_ROOT}/memory/second-brain}"
LINKS_FILE="${SECOND_BRAIN_DIR}/links.md"
URL_REGISTRY="${SECOND_BRAIN_DIR}/.url-registry.jsonl"
PENDING_QUEUE="${SECOND_BRAIN_DIR}/.pending-queue.jsonl"
CAPTURE_LOG="${WORKSPACE_ROOT}/data/capture-log.jsonl"
ANALYZER_SCRIPT="${ANALYZER_SCRIPT:-${SCRIPT_DIR}/brain-content-analyze.sh}"
REPO_MATCH_SCRIPT="${SCRIPT_DIR}/brain-idea-repo-match.sh"
AUTO_ANALYZE="${BRAIN_INBOX_ANALYZE_AUTO:-true}"
AUTO_REPO_MATCH="${BRAIN_REPO_MATCH_AUTO:-true}"
AUTO_OPS_INIT="${BRAIN_OPS_AUTO_INIT:-true}"
AUTO_OPS_PRIORITY_ONLY="${BRAIN_OPS_AUTO_PRIORITY_ONLY:-true}"
# today 승격 임계치 (오늘 테스트 기본 65)
OPS_SCORE_THRESHOLD="${BRAIN_OPS_SCORE_THRESHOLD:-65}"
export BRAIN_OPS_SCORE_THRESHOLD="$OPS_SCORE_THRESHOLD"
# OPS(today)로 승격된 링크는 Todoist까지 자동 태스크화(사용자 최종 실행 여부는 reaction으로 결정)
AUTO_TODO_ON_OPS="${BRAIN_LINK_AUTO_TODO_ON_OPS:-true}"
TODO_ROUTE_SCRIPT="${SCRIPT_DIR}/brain-todo-route.sh"
TELEGRAM_MIRROR_ENABLED="${BRAIN_ROUTER_ACK_TELEGRAM:-false}"
DISCORD_A2_BRIEF_ENABLED="${BRAIN_DISCORD_A2_BRIEF:-true}"
MAX_RETRIES=1
FORCE=false
OPS_INIT=false
NO_OPS_INIT=false

# === Args ===
URL=""
TITLE=""
SUMMARY=""
MY_OPINION=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --url) URL="$2"; shift 2 ;;
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

# === Timestamp ===
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
DATE_ID=$(date "+%Y%m%d%H%M%S")
NEXT_ACTION="후속 검토"
PRIORITY_TAG="p3"
ESSENCE_SUMMARY=""
KEY_POINT_1="핵심 포인트를 추출해 실행 가능 여부를 먼저 판단."
KEY_POINT_2="우선순위와 리스크 기준으로 바로 할 일/보류를 분리."
KEY_POINT_3="필요한 것만 남기고 운영 루틴에 연결."
OUR_APPLY="실행 항목 1개로 줄여 Todoist/Today에 연결."
OPS_SCORE="0"
OPS_REASONS=""
MATCH_CATEGORY=""
REPO_MATCH_STATUS="skipped"
REPO_MATCH_REASON=""
REPO_MATCH_MODE="none"
REPO_MATCH_BASE=""
REPO_MATCH_BASE_URL=""
REPO_MATCH_COMPANION=""
REPO_MATCH_COMPANION_URL=""
REPO_MATCH_QUERIES=""

# === Functions (must be defined before use) ===
queue_for_later() {
    local entry="{\"timestamp\":\"$TIMESTAMP\",\"hash\":\"${URL_HASH:-pending}\",\"url\":\"$URL\",\"title\":\"$TITLE\",\"summary\":\"${SUMMARY:-}\",\"my_opinion\":\"${MY_OPINION:-}\"}"
    
    if $DRY_RUN; then
        echo "[DRY-RUN] Would queue: $entry"
        return 0
    fi
    
    mkdir -p "$SECOND_BRAIN_DIR"
    echo "$entry" >> "$PENDING_QUEUE"
    echo "QUEUED: Entry pending completion"
}

send_to_discord() {
    local channel="$1"
    local message="$2"
    
    if $DRY_RUN; then
        echo "[DRY-RUN] Would send to Discord channel $channel:"
        echo "$message" | head -8
        echo "..."
        return 0
    fi
    
    # Check if channel configured
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
        echo "$message" | head -8
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

write_to_second_brain() {
    local entry="## [$TIMESTAMP] $TITLE
- URL: $URL
- Canonical: ${CANONICAL_URL:-$URL}
- Hash: ${URL_HASH:-pending}
- Status: TODO
- Added: $(date "+%Y-%m-%d")
- Summary: ${SUMMARY:-_No summary provided_}
- My Opinion: ${MY_OPINION:-_Not provided_}

"
    
    if $DRY_RUN; then
        echo "[DRY-RUN] Would write to $LINKS_FILE:"
        echo "$entry"
        return 0
    fi
    
    mkdir -p "$SECOND_BRAIN_DIR"
    touch "$LINKS_FILE"
    
    # Create backup
    [[ -f "$LINKS_FILE" ]] && cp "$LINKS_FILE" "${LINKS_FILE}.bak"
    
    # Prepend to file (newest first)
    local temp_file=$(mktemp)
    { echo "$entry"; cat "$LINKS_FILE"; } > "$temp_file"
    mv "$temp_file" "$LINKS_FILE"
    
    echo "OK: Written to second-brain/links.md"
}

register_url() {
    local entry="{\"hash\":\"$URL_HASH\",\"url\":\"$URL\",\"canonical\":\"$CANONICAL_URL\",\"timestamp\":\"$TIMESTAMP\"}"
    
    if $DRY_RUN; then
        echo "[DRY-RUN] Would register: $entry"
        return 0
    fi
    
    mkdir -p "$SECOND_BRAIN_DIR"
    echo "$entry" >> "$URL_REGISTRY"
}

check_duplicate() {
    local hash="$1"
    if [[ -f "$URL_REGISTRY" ]]; then
        if grep -q "\"hash\":\"$hash\"" "$URL_REGISTRY"; then
            return 0  # Duplicate found
        fi
    fi
    return 1  # Not a duplicate
}

is_junk_link() {
    local url="$1"
    local junk_patterns=(
        "utm_source"
        "utm_medium"
        "fbclid="
        "gclid="
        "ads\."
        "advertisement"
        "promo\."
        "sponsor"
        "click\."
        "tracker"
        "doubleclick"
        "googleadservices"
        "adservice"
        "googlesyndication"
    )
    
    for pattern in "${junk_patterns[@]}"; do
        if echo "$url" | grep -qiE "$pattern"; then
            return 0
        fi
    done
    return 1
}

infer_capture_category() {
    local url="$1"
    local title_lc="$(echo "$TITLE" | tr '[:upper:]' '[:lower:]')"
    if echo "$url" | grep -qiE 'x\.com|twitter\.com'; then
        echo "forward"
    elif echo "$url" | grep -qiE 'github\.com|docs\.|openclaw|arxiv|medium\.com'; then
        echo "work"
    elif echo "$title_lc" | grep -qiE 'run|러닝|workout|strava'; then
        echo "running"
    elif echo "$title_lc" | grep -qiE 'trade|market|nq|btc|invest|투자|트레이딩'; then
        echo "investment"
    else
        echo "bookmark"
    fi
}

append_capture_log() {
    local category="$(infer_capture_category "$URL")"

    if $DRY_RUN; then
        echo "[DRY-RUN] Would append capture-log entry (category: $category)"
        return 0
    fi

    mkdir -p "$(dirname "$CAPTURE_LOG")"

    local esc_summary esc_raw esc_url esc_image
    esc_summary=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "${SUMMARY:-Auto-captured from Telegram}")
    esc_raw=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "${MY_OPINION:-}")
    esc_url=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$URL")
    esc_image=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "")

    printf '{"timestamp":"%s","category":"%s","summary":%s,"raw":%s,"urls":[%s],"imagePath":%s,"source":"brain-link-ingest","hash":"%s"}\n' \
      "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$category" "$esc_summary" "$esc_raw" "$esc_url" "$esc_image" "${URL_HASH:-pending}" >> "$CAPTURE_LOG"
}

validate_required_fields() {
    local missing=()
    [[ -z "$URL" ]] && missing+=("url")
    [[ -z "$TITLE" ]] && missing+=("title")
    [[ -z "$SUMMARY" ]] && missing+=("summary")
    [[ -z "$MY_OPINION" ]] && missing+=("my-opinion")

    if [[ ${#missing[@]} -gt 0 ]] && ! $FORCE; then
        echo "INCOMPLETE: Missing fields: ${missing[*]}"
        echo "  Queueing for manual review instead of auto-send"
        return 1
    fi
    return 0
}

is_truthy() {
    local v
    v="$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')"
    [[ "$v" == "1" || "$v" == "true" || "$v" == "yes" || "$v" == "on" ]]
}

is_placeholder_summary() {
    local s="${1:-}"
    [[ -z "$s" \
       || "$s" == "Auto-captured from Telegram" || "$s" == "_Auto-captured from Telegram_" \
       || "$s" == "Auto-captured from Discord"  || "$s" == "_Auto-captured from Discord_" ]]
}

is_placeholder_opinion() {
    local s="${1:-}"
    [[ -z "$s" || "$s" == "자동 수집 항목 (후속 검토 필요)" || "$s" == "_Not provided_" || "$s" == "Not provided" ]]
}

# === Validate URL ===
if [[ -z "$URL" ]]; then
    echo "ERROR: --url required" >&2
    exit 1
fi

# === Extract domain for title fallback ===
if [[ -z "$TITLE" ]]; then
    TITLE=$(echo "$URL" | sed -E 's|^https?://([^/]+).*|\1|' | cut -d'/' -f1)
fi

# === Auto analysis for summary/opinion/action ===
if is_truthy "$AUTO_ANALYZE" && [[ -x "$ANALYZER_SCRIPT" ]]; then
    ANALYZE_INPUT_TEXT="$SUMMARY"

    # 요약 선행: 업스트림(특히 Telegram) 해석 요약/의견을 우선 컨텍스트로 사용
    if is_placeholder_summary "$SUMMARY"; then
        ANALYZE_INPUT_TEXT="$MY_OPINION"
        if is_placeholder_opinion "$MY_OPINION"; then
            ANALYZE_INPUT_TEXT=""
        fi
    else
        # summary가 유효하면 opinion도 결합해 액션성 판단 강화
        if ! is_placeholder_opinion "$MY_OPINION"; then
            ANALYZE_INPUT_TEXT="${SUMMARY} ${MY_OPINION}"
        fi
    fi

    ANALYZE_JSON="$("$ANALYZER_SCRIPT" --mode link --title "$TITLE" --url "$URL" --text "$ANALYZE_INPUT_TEXT" 2>/dev/null || true)"
    if [[ -n "$ANALYZE_JSON" ]]; then
            parsed_summary="$(echo "$ANALYZE_JSON" | jq -r '.summary // empty' 2>/dev/null || true)"
            parsed_opinion="$(echo "$ANALYZE_JSON" | jq -r '.my_opinion // empty' 2>/dev/null || true)"
            parsed_action="$(echo "$ANALYZE_JSON" | jq -r '.next_action // empty' 2>/dev/null || true)"
            parsed_priority="$(echo "$ANALYZE_JSON" | jq -r '.priority // "p3"' 2>/dev/null || true)"
            parsed_category="$(echo "$ANALYZE_JSON" | jq -r '.category // empty' 2>/dev/null || true)"
            parsed_should_ops="$(echo "$ANALYZE_JSON" | jq -r '.should_ops // false' 2>/dev/null || true)"
            parsed_ops_score="$(echo "$ANALYZE_JSON" | jq -r '.ops_score // 0' 2>/dev/null || true)"
            parsed_ops_reasons="$(echo "$ANALYZE_JSON" | jq -r '(.ops_reasons // []) | join(",")' 2>/dev/null || true)"
            parsed_essence="$(echo "$ANALYZE_JSON" | jq -r '.essence_summary // empty' 2>/dev/null || true)"
            parsed_k1="$(echo "$ANALYZE_JSON" | jq -r '.key_points[0] // empty' 2>/dev/null || true)"
            parsed_k2="$(echo "$ANALYZE_JSON" | jq -r '.key_points[1] // empty' 2>/dev/null || true)"
            parsed_k3="$(echo "$ANALYZE_JSON" | jq -r '.key_points[2] // empty' 2>/dev/null || true)"
            parsed_apply="$(echo "$ANALYZE_JSON" | jq -r '.our_apply // empty' 2>/dev/null || true)"

            [[ -n "$parsed_summary" ]] && SUMMARY="$parsed_summary"
            [[ -n "$parsed_opinion" ]] && MY_OPINION="$parsed_opinion"
            [[ -n "$parsed_action" ]] && NEXT_ACTION="$parsed_action"
            [[ -n "$parsed_priority" ]] && PRIORITY_TAG="$parsed_priority"
            [[ -n "$parsed_category" ]] && MATCH_CATEGORY="$parsed_category"
            [[ -n "$parsed_essence" ]] && ESSENCE_SUMMARY="$parsed_essence"
            [[ -n "$parsed_k1" ]] && KEY_POINT_1="$parsed_k1"
            [[ -n "$parsed_k2" ]] && KEY_POINT_2="$parsed_k2"
            [[ -n "$parsed_k3" ]] && KEY_POINT_3="$parsed_k3"
            [[ -n "$parsed_apply" ]] && OUR_APPLY="$parsed_apply"
            [[ -n "$parsed_ops_score" ]] && OPS_SCORE="$parsed_ops_score"
            [[ -n "$parsed_ops_reasons" ]] && OPS_REASONS="$parsed_ops_reasons"

            if [[ "$OPS_INIT" != "true" && "$NO_OPS_INIT" != "true" ]] && is_truthy "$AUTO_OPS_INIT"; then
                # Priority-first auto promotion rule (default): p1/p2 -> today(ops), p3 -> inbox wait
                if is_truthy "$AUTO_OPS_PRIORITY_ONLY"; then
                    # Priority-first + analyzer override(A/A-prime):
                    # p1/p2는 기본 승격, p3라도 parsed_should_ops=true면 승격 허용
                    case "${parsed_priority,,}" in
                        p1|p2) OPS_INIT=true ;;
                        *)
                            if [[ "$parsed_should_ops" == "true" ]]; then
                                OPS_INIT=true
                            else
                                OPS_INIT=false
                            fi
                            ;;
                    esac
                else
                    # Legacy behavior
                    [[ "$parsed_should_ops" == "true" ]] && OPS_INIT=true
                fi
            fi
        fi
    fi

# === 4-Field Validation ===
if ! validate_required_fields; then
    queue_for_later
    echo "ACTION: Run with --force or provide missing fields to complete"
    exit 0
fi

# === Canonicalize URL (remove tracking params for dedup) ===
CANONICAL_URL=$(echo "$URL" | sed -E 's/[?&](utm_[^&]*|fbclid|gclid|ref|source)=[^&]*//g' | sed 's/?.*$//' | sed 's|/$||')

# === URL Hash for deduplication ===
URL_HASH=$(echo -n "$CANONICAL_URL" | sha256sum | cut -c1-16)

# === Check for duplicates ===
if ! $FORCE && check_duplicate "$URL_HASH"; then
    echo "SKIP: Duplicate URL detected (hash: $URL_HASH)"
    echo "Use --force to process anyway"
    exit 0
fi

# === Ad/Junk Filter ===
if is_junk_link "$URL" && ! $FORCE; then
    echo "FILTERED: Ad/tracking link detected, skipping"
    exit 0
fi

# === Main Pipeline ===
DISCORD_OK=true

# Fallback essence block values if analyzer fields are missing
[[ -z "$ESSENCE_SUMMARY" ]] && ESSENCE_SUMMARY="${SUMMARY:-링크 핵심 내용 검토 필요}"
[[ -z "$OUR_APPLY" ]] && OUR_APPLY="${NEXT_ACTION:-후속 검토}"
[[ -z "$MATCH_CATEGORY" ]] && MATCH_CATEGORY="$(infer_capture_category "$URL")"

# Optional GitHub similar-repo matching for idea/work items
if is_truthy "$AUTO_REPO_MATCH" && [[ -x "$REPO_MATCH_SCRIPT" ]]; then
    REPO_MATCH_CMD=(
        "$REPO_MATCH_SCRIPT"
        --url "$URL"
        --title "$TITLE"
        --summary "$SUMMARY"
        --my-opinion "$MY_OPINION"
        --hash "$URL_HASH"
        --category "$MATCH_CATEGORY"
    )
    if $DRY_RUN; then
        REPO_MATCH_CMD+=(--dry-run)
    fi

    REPO_MATCH_JSON="$("${REPO_MATCH_CMD[@]}" 2>/dev/null || true)"
    if [[ -n "$REPO_MATCH_JSON" ]]; then
        parsed_repo_status="$(echo "$REPO_MATCH_JSON" | jq -r '.status // empty' 2>/dev/null || true)"
        parsed_repo_reason="$(echo "$REPO_MATCH_JSON" | jq -r '.reason // empty' 2>/dev/null || true)"
        parsed_repo_mode="$(echo "$REPO_MATCH_JSON" | jq -r '.recommended_mode // empty' 2>/dev/null || true)"
        parsed_repo_base="$(echo "$REPO_MATCH_JSON" | jq -r '.recommended_base // empty' 2>/dev/null || true)"
        parsed_repo_base_url="$(echo "$REPO_MATCH_JSON" | jq -r '.recommended_base_url // empty' 2>/dev/null || true)"
        parsed_repo_companion="$(echo "$REPO_MATCH_JSON" | jq -r '.recommended_companion // empty' 2>/dev/null || true)"
        parsed_repo_companion_url="$(echo "$REPO_MATCH_JSON" | jq -r '.recommended_companion_url // empty' 2>/dev/null || true)"
        parsed_repo_queries="$(echo "$REPO_MATCH_JSON" | jq -r '(.queries // []) | join(", ")' 2>/dev/null || true)"

        [[ -n "$parsed_repo_status" ]] && REPO_MATCH_STATUS="$parsed_repo_status"
        [[ -n "$parsed_repo_reason" ]] && REPO_MATCH_REASON="$parsed_repo_reason"
        [[ -n "$parsed_repo_mode" ]] && REPO_MATCH_MODE="$parsed_repo_mode"
        [[ -n "$parsed_repo_base" ]] && REPO_MATCH_BASE="$parsed_repo_base"
        [[ -n "$parsed_repo_base_url" ]] && REPO_MATCH_BASE_URL="$parsed_repo_base_url"
        [[ -n "$parsed_repo_companion" ]] && REPO_MATCH_COMPANION="$parsed_repo_companion"
        [[ -n "$parsed_repo_companion_url" ]] && REPO_MATCH_COMPANION_URL="$parsed_repo_companion_url"
        [[ -n "$parsed_repo_queries" ]] && REPO_MATCH_QUERIES="$parsed_repo_queries"
    fi
fi

REPO_MATCH_BLOCK=""
if [[ "$REPO_MATCH_STATUS" == "matched" && -n "$REPO_MATCH_BASE" ]]; then
    REPO_MATCH_BLOCK="Repo Match
- Mode: ${REPO_MATCH_MODE}
- Base: ${REPO_MATCH_BASE}${REPO_MATCH_BASE_URL:+ (${REPO_MATCH_BASE_URL})}
"
    if [[ -n "$REPO_MATCH_COMPANION" ]]; then
        REPO_MATCH_BLOCK="${REPO_MATCH_BLOCK}- Companion: ${REPO_MATCH_COMPANION}${REPO_MATCH_COMPANION_URL:+ (${REPO_MATCH_COMPANION_URL})}
"
    fi
    if [[ -n "$REPO_MATCH_QUERIES" ]]; then
        REPO_MATCH_BLOCK="${REPO_MATCH_BLOCK}- Queries: ${REPO_MATCH_QUERIES}
"
    fi
elif [[ "$REPO_MATCH_STATUS" == "error" && -n "$REPO_MATCH_REASON" ]]; then
    REPO_MATCH_BLOCK="Repo Match
- Status: error
- Reason: ${REPO_MATCH_REASON}
"
fi

REPO_MATCH_THREAD_BLOCK=""
if [[ -n "$REPO_MATCH_BLOCK" ]]; then
    REPO_MATCH_THREAD_BLOCK="**Repo Match:**
${REPO_MATCH_BLOCK}"
fi

# 1. Send to brain-inbox (Discord + Telegram)
INBOX_MSG="📥 **New Link**

**Title:** $TITLE
**URL:** $URL

에센스 요약 👇

요약
${ESSENCE_SUMMARY}

핵심 3줄
1. ${KEY_POINT_1}
2. ${KEY_POINT_2}
3. ${KEY_POINT_3}

우리식 적용 한 줄
• ${OUR_APPLY}

${REPO_MATCH_BLOCK}

메타
- Summary: ${SUMMARY:-_Auto-captured from Telegram_}
- My Opinion: ${MY_OPINION:-_Not provided_}
- Next Action: ${NEXT_ACTION}
- Priority: ${PRIORITY_TAG}
- Ops Score: ${OPS_SCORE}
- Ops Reasons: ${OPS_REASONS:-none}
**Time:** $TIMESTAMP

Status: TODO"

if ! send_to_discord "$INBOX_CHANNEL" "$INBOX_MSG"; then
    echo "WARN: Discord inbox send failed" >&2
    DISCORD_OK=false
fi

# Optional A2 follow-up brief (Discord only)
if is_truthy "$DISCORD_A2_BRIEF_ENABLED"; then
    A2_BRIEF_MSG="[분석완료 ✅]

핵심 1줄
${ESSENCE_SUMMARY}

핵심 요약
• ${KEY_POINT_1}
• ${KEY_POINT_2}
• ${KEY_POINT_3}

다음 행동(24h) 1줄
${OUR_APPLY}"

    if ! send_to_discord "$INBOX_CHANNEL" "$A2_BRIEF_MSG"; then
        echo "WARN: Discord A2 brief send failed" >&2
        DISCORD_OK=false
    fi
fi

if is_truthy "$TELEGRAM_MIRROR_ENABLED"; then
    if ! send_to_telegram "$TELEGRAM_TARGET" "$INBOX_MSG"; then
        echo "WARN: Telegram mirror send failed" >&2
        DISCORD_OK=false
    fi
else
    echo "INFO: Telegram mirror disabled (BRAIN_ROUTER_ACK_TELEGRAM=false)"
fi

# 2. Create brain-ops entry (explicit or auto-enabled)
if $OPS_INIT; then
    THREAD_MSG="🧵 **Link Processing Entry**

**Item:** $TITLE
**URL:** <$URL>
**Hash:** \`$URL_HASH\`
**Summary:** ${SUMMARY:-_N/A_}
**My Opinion:** ${MY_OPINION:-_N/A_}
**Next Action:** ${NEXT_ACTION}
**Priority:** ${PRIORITY_TAG}
**Ops Score:** ${OPS_SCORE}
**Trigger:** ${OPS_REASONS:-none}
${REPO_MATCH_THREAD_BLOCK}
**Status:** 📋 TODO

---
_React or reply: ✅=DONE / 🔄=DOING / 🚫=BLOCKED_"

    if ! send_to_discord "$OPS_CHANNEL" "$THREAD_MSG"; then
        echo "WARN: Ops message send failed" >&2
        DISCORD_OK=false
    fi

    # 2-1. today 승격 항목은 Todoist까지 자동 생성 (사용자는 이후 실행/보류만 결정)
    if is_truthy "$AUTO_TODO_ON_OPS" && [[ -x "$TODO_ROUTE_SCRIPT" ]]; then
        TODO_TITLE="${TITLE//|/-}"
        TODO_ACTION="${OUR_APPLY:-${NEXT_ACTION:-링크 검토 후 실행여부 결정}}"
        TODO_ACTION="${TODO_ACTION//|/-}"
        TODO_RAW="#todo [링크] ${TODO_TITLE} — ${TODO_ACTION} | queue | p2"
        TODO_CMD=("$TODO_ROUTE_SCRIPT" --raw "$TODO_RAW" --source-ts "$TIMESTAMP")
        if $DRY_RUN; then
            TODO_CMD+=(--dry-run)
        fi
        if ! "${TODO_CMD[@]}" >/dev/null 2>&1; then
            echo "WARN: Auto todo route failed for ops link" >&2
        fi
    fi
else
    echo "INFO: Ops entry skipped (auto 판단 제외 또는 --no-ops-init)"
fi

# 3. Write to second-brain (always succeeds if disk available)
write_to_second_brain

# 4. Append capture log for dashboard/captures tab
append_capture_log

# 5. Register URL hash for dedup
register_url

# 6. Queue for retry if Discord failed
if ! $DISCORD_OK && ! $DRY_RUN; then
    queue_for_later
    echo "OK: Pipeline complete (local-only mode, queued for sync)"
else
    echo "OK: Pipeline complete for $URL (hash: $URL_HASH)"
fi
