#!/usr/bin/env bash
# brain-inbox-resend-clean.sh - second-brain/links.md의 정리된 항목을 Discord brain-inbox에 "개별 메시지"로 재전송
# Usage: brain-inbox-resend-clean.sh [--dry-run]
# Env: BRAIN_INBOX_CHANNEL_ID (기본값: 1477462557941039124)

set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$(cd "${SCRIPT_DIR}/.." && pwd)"
set +u
source "${SCRIPT_DIR}/env-loader.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/message-guard.sh" 2>/dev/null || true
set -u

LINKS_FILE="${WORKSPACE}/memory/second-brain/links.md"
CHANNEL="${BRAIN_INBOX_CHANNEL_ID:-${DISCORD_INBOX:-1478250668052713647}}"

if [[ ! -f "$LINKS_FILE" ]]; then
  echo "ERROR: links.md not found at $LINKS_FILE" >&2
  exit 1
fi

TMP_ENTRIES="$(mktemp)"
awk '
BEGIN { title=""; url=""; summary=""; op="" }
/^## \[/ {
  if (title != "" && url != "") {
    print title "\t" url "\t" summary "\t" op
  }
  title=$0; sub(/^## \[[^\]]+\] /, "", title)
  url=""; summary=""; op=""
}
/^- URL: / { url=$0; sub(/^- URL: /, "", url) }
/^- Summary: / { summary=$0; sub(/^- Summary: /, "", summary) }
/^- My Opinion: / { op=$0; sub(/^- My Opinion: /, "", op) }
END { if (title != "" && url != "") print title "\t" url "\t" summary "\t" op }
' "$LINKS_FILE" > "$TMP_ENTRIES"

TOTAL=$(wc -l < "$TMP_ENTRIES" | tr -d ' ')
if [[ "$TOTAL" -eq 0 ]]; then
  echo "No entries found in $LINKS_FILE"
  rm -f "$TMP_ENTRIES"
  exit 0
fi

send() {
  local idx="$1"; shift
  local total="$1"; shift
  local title="$1"; shift
  local url="$1"; shift
  local summary="${1:-요약 없음}"; shift
  local op="${1:-의견 없음}"
  local msg

  # Validate channel and target before sending
  if ! MESSAGE_GUARD_DRY_RUN="$DRY_RUN" validate_message_params --channel discord --target "channel:$CHANNEL"; then
    echo "[ERROR] message validation failed for entry: $title" >&2
    return 1
  fi

  msg=$(printf '📌 [%d/%d] %s\n🔗 %s\n📝 %s\n💭 %s' "$idx" "$total" "$title" "$url" "$summary" "$op")
  if $DRY_RUN; then
    echo "[DRY-RUN][discord:$CHANNEL] $msg"
    return 0
  fi
  openclaw message send --channel discord --target "channel:$CHANNEL" --message "$msg" --silent 2>/dev/null || {
    echo "WARN: send failed for $url" >&2
    return 1
  }
}

echo "Resending $TOTAL entries to Discord brain-inbox (channel: $CHANNEL)"
i=0
while IFS=$'\t' read -r title url summary op; do
  ((i++)) || true
  send "$i" "$TOTAL" "$title" "$url" "$summary" "$op" || true
  sleep 0.3
done < "$TMP_ENTRIES"

rm -f "$TMP_ENTRIES"
echo "Done."
