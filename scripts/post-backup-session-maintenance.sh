#!/usr/bin/env bash
set -euo pipefail

export HOME=/root
export PATH="/root/.local/bin:/root/.npm-global/bin:/root/bin:/root/.volta/bin:/root/.asdf/shims:/root/.bun/bin:/root/.nvm/current/bin:/root/.fnm/current/bin:/root/.local/share/pnpm:/usr/local/bin:/usr/bin:/bin"

LOG_FILE="${LOG_FILE:-/tmp/post-backup-session-maintenance.log}"
SESS_DIR="${SESS_DIR:-/root/.openclaw/agents/main/sessions}"
SESS_INDEX="${SESS_INDEX:-$SESS_DIR/sessions.json}"
RESET_PCT="${RESET_PCT:-70}"
MAX_RESETS="${MAX_RESETS:-5}"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$*" | tee -a "$LOG_FILE"
}

systemctl_user() {
  XDG_RUNTIME_DIR=/run/user/0 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/0/bus \
  systemctl --user "$@"
}

main() {
  log "[START] post-backup maintenance"

  if [[ ! -f "$SESS_INDEX" ]]; then
    log "[WARN] sessions index not found: $SESS_INDEX"
    systemctl_user restart openclaw-gateway.service || true
    log "[DONE] restarted gateway only (missing sessions index)"
    exit 0
  fi

  # 1) Cleanup session store.
  if openclaw sessions cleanup --enforce --fix-missing --json >>"$LOG_FILE" 2>&1; then
    log "[OK] sessions cleanup --enforce --fix-missing"
  else
    log "[WARN] sessions cleanup failed; continuing"
  fi

  ids_file="$(mktemp)"
  jq --argjson reset_pct "$RESET_PCT" --argjson max_resets "$MAX_RESETS" -r '
    to_entries
    | map(.value)
    | map(
        select(
          (.sessionId | type) == "string"
          and (.totalTokens | type) == "number"
          and (.contextTokens | type) == "number"
          and .contextTokens > 0
        )
        | . + {pct: (.totalTokens / .contextTokens * 100)}
      )
    | map(select(.pct >= $reset_pct))
    | sort_by(.pct)
    | reverse
    | unique_by(.sessionId)
    | .[:$max_resets]
    | .[].sessionId
  ' "$SESS_INDEX" >"$ids_file" || true

  mapfile -t reset_ids <"$ids_file"
  rm -f "$ids_file"

  if ((${#reset_ids[@]} == 0)); then
    log "[INFO] no high-token sessions over ${RESET_PCT}%"
    # 3) Restart gateway once during low-load window.
    systemctl_user restart openclaw-gateway.service || true
    log "[DONE] gateway restarted (no session reset candidates)"
    exit 0
  fi

  ts="$(date +%Y%m%d-%H%M%S)"
  archive_dir="$SESS_DIR/archive-auto-reset-$ts"
  mkdir -p "$archive_dir"
  cp "$SESS_INDEX" "$archive_dir/sessions.json.bak"

  log "[INFO] high-token sessions to reset: ${#reset_ids[@]} (pct >= ${RESET_PCT})"

  # 2) Reset high-token sessions safely with gateway stopped.
  systemctl_user stop openclaw-gateway.service || true

  for sid in "${reset_ids[@]}"; do
    [[ -z "$sid" ]] && continue

    session_file="$(
      jq -r --arg sid "$sid" '
        to_entries[]
        | select((.value.sessionId // "") == $sid)
        | (.value.sessionFile // empty)
      ' "$SESS_INDEX" | head -n 1
    )"

    if [[ -z "$session_file" ]]; then
      session_file="$SESS_DIR/$sid.jsonl"
    fi

    if [[ -f "$session_file" ]]; then
      mv "$session_file" "$archive_dir/" || true
    fi
    if [[ -f "${session_file}.lock" ]]; then
      mv "${session_file}.lock" "$archive_dir/" || true
    fi
  done

  target_ids_file="$(mktemp)"
  printf '%s\n' "${reset_ids[@]}" >"$target_ids_file"

  jq --rawfile ids "$target_ids_file" '
    ($ids | split("\n") | map(select(length > 0))) as $targets
    | with_entries(
        select(
          ((.value.sessionId // "") as $sid | ($targets | index($sid)) | not)
        )
      )
  ' "$SESS_INDEX" >"$SESS_INDEX.tmp"
  mv "$SESS_INDEX.tmp" "$SESS_INDEX"
  chmod 600 "$SESS_INDEX" || true
  rm -f "$target_ids_file"

  # 3) Restart gateway once during low-load window (stop/start cycle).
  systemctl_user start openclaw-gateway.service || true

  log "[DONE] reset applied; archive=$archive_dir"
}

main "$@"
