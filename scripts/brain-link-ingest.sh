#!/bin/bash
# brain-link-ingest.sh - Process incoming links → brain-inbox + second-brain (ops is opt-in)
# Usage: brain-link-ingest.sh --url "..." [--title "..."] [--summary "..."] [--my-opinion "..."] [--dry-run] [--force] [--ops-init]
# Env: BRAIN_INBOX_CHANNEL_ID, BRAIN_OPS_CHANNEL_ID
#
# 4-Field Requirement:
# - A valid brain entry MUST have: URL, TITLE, SUMMARY, MY_OPINION
# - If any missing (and not --force), entry is queued for manual review
#
# Cross-context constraints handled:
# - Discord API unavailable: writes to local queue for later sync
# - Ops entry creation is explicit-only (--ops-init)

set -eo pipefail

# === Load env ===
set +u
source "$(dirname "$0")/env-loader.sh" 2>/dev/null || true
set -u

# === Config ===
INBOX_CHANNEL="${BRAIN_INBOX_CHANNEL_ID:-}"
OPS_CHANNEL="${BRAIN_OPS_CHANNEL_ID:-}"
SECOND_BRAIN_DIR="/root/.openclaw/workspace/memory/second-brain"
LINKS_FILE="${SECOND_BRAIN_DIR}/links.md"
URL_REGISTRY="${SECOND_BRAIN_DIR}/.url-registry.jsonl"
PENDING_QUEUE="${SECOND_BRAIN_DIR}/.pending-queue.jsonl"
MAX_RETRIES=1
FORCE=false
OPS_INIT=false

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
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

# === Timestamp ===
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
DATE_ID=$(date "+%Y%m%d%H%M%S")

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
        echo "[DRY-RUN] Would send to channel $channel:"
        echo "$message" | head -8
        echo "..."
        return 0
    fi
    
    # Check if channel configured
    if [[ -z "$channel" ]]; then
        echo "WARN: Channel ID not configured, queueing locally" >&2
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

# === Validate URL ===
if [[ -z "$URL" ]]; then
    echo "ERROR: --url required" >&2
    exit 1
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

# === Extract domain for title fallback ===
if [[ -z "$TITLE" ]]; then
    TITLE=$(echo "$URL" | sed -E 's|^https?://([^/]+).*|\1|' | cut -d'/' -f1)
fi

# === Main Pipeline ===
DISCORD_OK=true

# 1. Send to brain-inbox
INBOX_MSG="📥 **New Link**

**Title:** $TITLE
**URL:** $URL
**Summary:** ${SUMMARY:-_Auto-captured from Telegram_}
**My Opinion:** ${MY_OPINION:-_Not provided_}
**Time:** $TIMESTAMP

Status: TODO (ops thread starts only when you begin deep work)"

if ! send_to_discord "$INBOX_CHANNEL" "$INBOX_MSG"; then
    echo "WARN: Inbox send failed" >&2
    DISCORD_OK=false
fi

# 2. Create brain-ops entry only when explicitly requested (--ops-init)
if $OPS_INIT; then
    THREAD_MSG="🧵 **Link Processing Entry**

**Item:** $TITLE
**URL:** <$URL>
**Hash:** \`$URL_HASH\`
**Summary:** ${SUMMARY:-_N/A_}
**My Opinion:** ${MY_OPINION:-_N/A_}
**Status:** 📋 TODO

---
_React or reply: ✅=DONE / 🔄=DOING / 🚫=BLOCKED_"

    if ! send_to_discord "$OPS_CHANNEL" "$THREAD_MSG"; then
        echo "WARN: Ops message send failed" >&2
        DISCORD_OK=false
    fi
else
    echo "INFO: Ops entry skipped (use --ops-init when deep work starts)"
fi

# 3. Write to second-brain (always succeeds if disk available)
write_to_second_brain

# 4. Register URL hash for dedup
register_url

# 5. Queue for retry if Discord failed
if ! $DISCORD_OK && ! $DRY_RUN; then
    queue_for_later
    echo "OK: Pipeline complete (local-only mode, queued for sync)"
else
    echo "OK: Pipeline complete for $URL (hash: $URL_HASH)"
fi
