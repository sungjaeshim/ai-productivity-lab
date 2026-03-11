#!/usr/bin/env bash
# brain-nightly-todo-sync.sh
# Nightly semi-automatic sync:
# 1) Apply explicit Discord reactions (✅/🔄/🚫) to Todoist
# 2) Generate stale-task BLOCKED candidates (no auto-apply)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
set +u
source "${SCRIPT_DIR}/env-loader.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/message-guard.sh" 2>/dev/null || true
set -u

TODAY_CHANNEL="${DISCORD_TODAY:-${BRAIN_OPS_CHANNEL_ID:-1478250773228814357}}"
STALE_HOURS="${BRAIN_NIGHTLY_STALE_HOURS:-24}"
REACTION_LIMIT="${BRAIN_NIGHTLY_REACTION_LIMIT:-150}"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --stale-hours) STALE_HOURS="${2:-24}"; shift 2 ;;
    --limit) REACTION_LIMIT="${2:-150}"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

run_or_echo() {
  if $DRY_RUN; then
    echo "[DRY-RUN] $*"
  else
    eval "$@"
  fi
}

log "nightly todo sync start"

# 1) Reaction-based status sync (explicit only)
if $DRY_RUN; then
  "${SCRIPT_DIR}/brain-todo-reaction-sync.sh" --dry-run --limit "$REACTION_LIMIT" || true
else
  "${SCRIPT_DIR}/brain-todo-reaction-sync.sh" --limit "$REACTION_LIMIT" || true
fi

# 2) Stale candidate generation (suggest only)
STALE_JSON="$("${SCRIPT_DIR}/brain-todoist-stale-check.sh" --hours "$STALE_HOURS" --output json 2>/dev/null || true)"

if [[ -z "$STALE_JSON" ]]; then
  log "stale check returned empty"
  exit 0
fi

CAND_COUNT="$(echo "$STALE_JSON" | jq -r '.stale_count // 0' 2>/dev/null || echo 0)"
THRESHOLD_TIME="$(echo "$STALE_JSON" | jq -r '.threshold_time // empty' 2>/dev/null || true)"

if [[ "$CAND_COUNT" =~ ^[0-9]+$ ]] && (( CAND_COUNT > 0 )); then
  TOP_LINES="$(echo "$STALE_JSON" | jq -r '.tasks[:10] | .[] | "- [\(.project)] \(.content) (\(.id))"' 2>/dev/null || true)"
  MSG="🌙 Nightly Todo Sync (반자동)
- reaction 동기화: 완료
- BLOCKED 후보: ${CAND_COUNT}개 (기준 ${STALE_HOURS}h, ${THRESHOLD_TIME})

후보 목록(상위 10):
${TOP_LINES}

가이드: 내일 확인 후 필요한 항목만 🚫 반응으로 BLOCKED 확정"
else
  MSG="🌙 Nightly Todo Sync (반자동)
- reaction 동기화: 완료
- BLOCKED 후보: 0개 (기준 ${STALE_HOURS}h)"
fi

if $DRY_RUN; then
  echo "[DRY-RUN] Would send summary to discord:${TODAY_CHANNEL}"
  echo "$MSG"
else
  if validate_message_params --channel discord --target "$TODAY_CHANNEL"; then
    openclaw message send --channel discord --target "$TODAY_CHANNEL" --message "$MSG" --silent >/dev/null 2>&1 || true
  else
    log "[WARN] Message skipped: validation failed" >&2
  fi
fi

log "nightly todo sync done"
