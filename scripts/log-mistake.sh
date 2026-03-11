#!/usr/bin/env bash
# log-mistake.sh
# Append mistake/reliability events to memory/mistake-ledger.jsonl

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LEDGER_FILE="${WORKSPACE_DIR}/memory/mistake-ledger.jsonl"

TYPE=""
SOURCE=""
DETAIL=""
ACTION=""
SEVERITY="low"
RULE=""
META_JSON="{}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type) TYPE="$2"; shift 2 ;;
    --source) SOURCE="$2"; shift 2 ;;
    --detail) DETAIL="$2"; shift 2 ;;
    --action) ACTION="$2"; shift 2 ;;
    --severity) SEVERITY="$2"; shift 2 ;;
    --rule) RULE="$2"; shift 2 ;;
    --meta-json) META_JSON="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$TYPE" || -z "$SOURCE" ]]; then
  echo "Usage: $0 --type <type> --source <source> [--detail ...] [--action ...] [--severity low|medium|high] [--rule ...] [--meta-json '{...}']" >&2
  exit 1
fi

mkdir -p "$(dirname "$LEDGER_FILE")"
touch "$LEDGER_FILE"

NOW_ISO="$(date -Iseconds)"

jq -cn \
  --arg ts "$NOW_ISO" \
  --arg type "$TYPE" \
  --arg source "$SOURCE" \
  --arg detail "$DETAIL" \
  --arg action "$ACTION" \
  --arg severity "$SEVERITY" \
  --arg rule "$RULE" \
  --argjson meta "$META_JSON" \
  '{timestamp:$ts,type:$type,source:$source,detail:$detail,action:$action,severity:$severity,rule:$rule,meta:$meta}' \
  >> "$LEDGER_FILE"

echo "LOGGED:$TYPE:$SOURCE"
