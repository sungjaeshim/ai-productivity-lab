#!/usr/bin/env bash
# Canonical entrypoint for send-* workflows.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<EOF
Usage:
  $0 <guarded|observe|briefing> [args...]
EOF
}

cmd="${1:-}"
if [[ -z "$cmd" ]]; then
  usage >&2
  exit 1
fi
shift

case "$cmd" in
  guarded)
    exec "${SCRIPT_DIR}/send-guarded-message.sh" "$@"
    ;;
  observe)
    exec "${SCRIPT_DIR}/send-guard-observe.sh" "$@"
    ;;
  briefing)
    exec "${SCRIPT_DIR}/send-briefing.sh" "$@"
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
