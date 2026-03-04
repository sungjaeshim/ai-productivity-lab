#!/bin/bash
# brain-thread-manage.sh - Manage brain-ops with thread-based status tracking
# Usage:
#   brain-thread-manage.sh --init --title "..." --url "..."         # Create new thread
#   brain-thread-manage.sh --status <STATUS> --thread-id "..." [...]  # Update status in thread
# Status: TODO | DOING | DONE | BLOCKED
# Env: BRAIN_OPS_CHANNEL_ID
#
# Thread-based model:
# - Main channel: Only initial entry message (thread parent)
# - Thread replies: All status updates (TODO → DOING → DONE/BLOCKED)
# - This keeps ops channel clean while maintaining full history in threads

set -eo pipefail

# === Load env ===
set +u
source "$(dirname "$0")/env-loader.sh" 2>/dev/null || true
set -u

# === Config ===
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OPS_CHANNEL="${BRAIN_OPS_CHANNEL_ID:-}"
SECOND_BRAIN_DIR="${SECOND_BRAIN_DIR:-${WORKSPACE_ROOT}/memory/second-brain}"
LINKS_FILE="${SECOND_BRAIN_DIR}/links.md"
THREAD_REGISTRY="${SECOND_BRAIN_DIR}/.thread-registry.jsonl"
MAX_RETRIES=1

# === Valid statuses ===
VALID_STATUSES=("TODO" "DOING" "DONE" "BLOCKED")
STATUS_EMOJIS=("📋" "🔄" "✅" "🚫")

# === Args ===
MODE=""
STATUS=""
URL=""
TITLE=""
THREAD_ID=""
NOTE=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --init) MODE="init"; shift ;;
        --status) STATUS="$2"; MODE="update"; shift 2 ;;
        --url) URL="$2"; shift 2 ;;
        --title) TITLE="$2"; shift 2 ;;
        --thread-id) THREAD_ID="$2"; shift 2 ;;
        --note) NOTE="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

# === Validate ===
if [[ -z "$MODE" ]]; then
    echo "ERROR: --init or --status required" >&2
    echo "Usage:" >&2
    echo "  --init --title '...' --url '...'           # Create new thread" >&2
    echo "  --status <STATUS> --thread-id '...' [--url '...' --note '...']  # Update" >&2
    exit 1
fi

if [[ -z "$OPS_CHANNEL" ]]; then
    echo "ERROR: BRAIN_OPS_CHANNEL_ID must be set" >&2
    exit 1
fi

# === Timestamp ===
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# === Functions ===
send_to_discord() {
    local channel="$1"
    local message="$2"
    local thread_id="${3:-}"
    local attempt=1
    
    while [[ $attempt -le $((MAX_RETRIES + 1)) ]]; do
        if $DRY_RUN; then
            echo "[DRY-RUN] Would send to channel $channel${thread_id:+ (thread: $thread_id)}:"
            echo "$message" | head -5
            return 0
        fi
        
        local cmd="openclaw message send --channel discord --target $channel --message"
        if [[ -n "$thread_id" ]]; then
            # Reply to thread (create thread reply)
            # Note: openclaw message send doesn't have native thread support
            # We use thread_id as part of the message context
            cmd="openclaw message send --channel discord --target $channel --reply-to $thread_id --message"
        fi
        
        if $cmd "$message" --silent 2>/dev/null; then
            return 0
        fi
        
        echo "WARN: Discord send failed (attempt $attempt), retrying..." >&2
        sleep 1
        ((attempt++))
    done
    
    echo "ERROR: Failed to send to Discord after $MAX_RETRIES retries" >&2
    return 1
}

register_thread() {
    local thread_id="$1"
    local url="$2"
    local title="$3"
    local entry="{\"thread_id\":\"$thread_id\",\"url\":\"$url\",\"title\":\"$title\",\"created_at\":\"$TIMESTAMP\",\"status\":\"TODO\"}"
    
    if $DRY_RUN; then
        echo "[DRY-RUN] Would register thread: $entry"
        return 0
    fi
    
    mkdir -p "$SECOND_BRAIN_DIR"
    echo "$entry" >> "$THREAD_REGISTRY"
    echo "REGISTERED: Thread $thread_id for $url"
}

update_second_brain() {
    local url="$1"
    local status="$2"
    local note="${3:-}"
    
    if [[ ! -f "$LINKS_FILE" ]]; then
        echo "WARN: $LINKS_FILE not found" >&2
        return 1
    fi
    
    if $DRY_RUN; then
        echo "[DRY-RUN] Would update status for $url to $status in $LINKS_FILE"
        return 0
    fi
    
    # Create backup
    cp "$LINKS_FILE" "${LINKS_FILE}.bak"
    
    # Update status for matching URL
    local escaped_url=$(echo "$url" | sed 's/[\/&]/\\&/g')
    
    if grep -q "$escaped_url" "$LINKS_FILE"; then
        awk -v url="$url" -v status="$status" -v note="$note" -v ts="$TIMESTAMP" '
        $0 ~ "- URL: " url {
            found = 1
        }
        found && /^- Status:/ {
            sub(/^- Status: .*/, "- Status: " status)
            found = 0
            if (note != "") {
                print
                print "- Note: " note " (" ts ")"
                next
            }
        }
        { print }
        ' "$LINKS_FILE" > "${LINKS_FILE}.tmp"
        
        mv "${LINKS_FILE}.tmp" "$LINKS_FILE"
        echo "OK: Updated status for $url → $status"
    else
        echo "WARN: URL not found in $LINKS_FILE" >&2
        return 1
    fi
}

update_thread_status() {
    local thread_id="$1"
    local status="$2"
    
    if [[ ! -f "$THREAD_REGISTRY" ]]; then
        return 1
    fi
    
    # Update status in thread registry
    local temp_file=$(mktemp)
    awk -v tid="$thread_id" -v status="$status" -v ts="$TIMESTAMP" '
    {
        if ($0 ~ "\"thread_id\":\"" tid "\"") {
            sub(/"status":"[^"]*"/, "\"status\":\"" status "\"")
            sub(/"updated_at":"[^"]*"/, "\"updated_at\":\"" ts "\"")
        }
        print
    }
    ' "$THREAD_REGISTRY" > "$temp_file"
    mv "$temp_file" "$THREAD_REGISTRY"
}

# === Main ===

if [[ "$MODE" == "init" ]]; then
    # === CREATE NEW THREAD ===
    if [[ -z "$TITLE" ]]; then
        echo "ERROR: --title required for --init" >&2
        exit 1
    fi
    if [[ -z "$URL" ]]; then
        echo "ERROR: --url required for --init" >&2
        exit 1
    fi
    
    # URL hash for dedup
    URL_HASH=$(echo -n "$URL" | sha256sum | cut -c1-16)
    
    # Initial message (this becomes the thread parent)
    INIT_MSG="🧵 **$TITLE**

**URL:** <$URL>
**Hash:** \`$URL_HASH\`
**Status:** 📋 TODO
**Created:** $TIMESTAMP

---
_This is a thread entry. All status updates will be posted as replies._

_React or reply: ✅=DONE / 🔄=DOING / 🚫=BLOCKED_"

    if $DRY_RUN; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "[DRY-RUN] Would create thread entry:"
        echo "  Channel: $OPS_CHANNEL"
        echo "  Title:   $TITLE"
        echo "  URL:     $URL"
        echo "  Message:"
        echo "$INIT_MSG" | head -10
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "THREAD_ID: [dry-run-mock-thread-id]"
    else
        # Send main message
        if openclaw message send --channel discord --target "$OPS_CHANNEL" --message "$INIT_MSG" --silent 2>/dev/null; then
            # Note: Getting message_id from send requires openclaw to return it
            # For now, we use URL hash as pseudo thread-id for tracking
            THREAD_ID="brain-$URL_HASH"
            register_thread "$THREAD_ID" "$URL" "$TITLE"
            echo "OK: Thread created with ID $THREAD_ID"
        else
            echo "ERROR: Failed to create thread message" >&2
            exit 1
        fi
    fi

elif [[ "$MODE" == "update" ]]; then
    # === UPDATE STATUS ===
    if [[ -z "$STATUS" ]]; then
        echo "ERROR: --status required" >&2
        echo "Valid statuses: ${VALID_STATUSES[*]}" >&2
        exit 1
    fi
    if [[ -z "$THREAD_ID" ]]; then
        echo "ERROR: --thread-id required for status update" >&2
        exit 1
    fi
    
    # Normalize status
    STATUS=$(echo "$STATUS" | tr '[:lower:]' '[:upper:]')
    
    # Check valid status
    valid=false
    for i in "${!VALID_STATUSES[@]}"; do
        if [[ "${VALID_STATUSES[$i]}" == "$STATUS" ]]; then
            EMOJI="${STATUS_EMOJIS[$i]}"
            valid=true
            break
        fi
    done
    
    if ! $valid; then
        echo "ERROR: Invalid status '$STATUS'" >&2
        echo "Valid statuses: ${VALID_STATUSES[*]}" >&2
        exit 1
    fi
    
    # Build status update message (goes to thread)
    STATUS_MSG="$EMOJI **Status: $STATUS**
**Time:** $TIMESTAMP
${NOTE:+**Note:** $NOTE}
${URL:+**URL:** <$URL>}"

    if $DRY_RUN; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "[DRY-RUN] Would post status update to thread:"
        echo "  Thread:  $THREAD_ID"
        echo "  Status:  $STATUS"
        echo "  Message:"
        echo "$STATUS_MSG"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    else
        # Send as reply to thread
        if ! send_to_discord "$OPS_CHANNEL" "$STATUS_MSG" "$THREAD_ID"; then
            echo "WARN: Thread reply failed, posting to main channel" >&2
            send_to_discord "$OPS_CHANNEL" "$STATUS_MSG" || true
        fi
        
        # Update local tracking
        update_thread_status "$THREAD_ID" "$STATUS"
    fi
    
    # Update second-brain if URL provided
    if [[ -n "$URL" ]]; then
        update_second_brain "$URL" "$STATUS" "$NOTE"
    fi
    
    echo "OK: Status updated to $STATUS in thread $THREAD_ID"
fi
