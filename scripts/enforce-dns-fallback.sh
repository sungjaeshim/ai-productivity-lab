#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${LOG_FILE:-/tmp/enforce-dns-fallback.log}"
BACKUP_DIR="${BACKUP_DIR:-/root/.openclaw/backups/network}"
LOCK_FILE="${LOCK_FILE:-/tmp/enforce-dns-fallback.lock}"
RESOLV_FILE="${RESOLV_FILE:-/etc/resolv.conf}"

TARGET_CONTENT=$'# managed by OpenClaw ops (dns fallback guard)\nnameserver 108.61.10.10\nnameserver 1.1.1.1\nnameserver 8.8.8.8\noptions timeout:2 attempts:2\n'

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$*" >>"$LOG_FILE"
}

need_update() {
  local tmp_file="$1"
  [[ ! -f "$RESOLV_FILE" ]] && return 0
  grep -q '100.100.100.100' "$RESOLV_FILE" && return 0
  cmp -s "$tmp_file" "$RESOLV_FILE" || return 0
  return 1
}

main() {
  mkdir -p "$(dirname "$LOG_FILE")" "$BACKUP_DIR"

  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    exit 0
  fi

  local tmp_file
  tmp_file="$(mktemp)"
  trap 'rm -f "${tmp_file:-}"' EXIT
  printf '%s' "$TARGET_CONTENT" >"$tmp_file"

  if ! need_update "$tmp_file"; then
    log "[OK] dns already healthy"
    exit 0
  fi

  local ts backup_path
  ts="$(date +%Y%m%d-%H%M%S)"
  backup_path="$BACKUP_DIR/resolv.conf.$ts.bak"
  if [[ -f "$RESOLV_FILE" ]]; then
    cp "$RESOLV_FILE" "$backup_path" || true
  fi

  cp "$tmp_file" "$RESOLV_FILE"
  chmod 644 "$RESOLV_FILE" || true

  if command -v resolvectl >/dev/null 2>&1; then
    resolvectl flush-caches >/dev/null 2>&1 || true
  fi

  log "[FIXED] dns fallback applied backup=$backup_path"
}

main "$@"
