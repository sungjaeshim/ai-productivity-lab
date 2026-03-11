#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
GUARD_SCRIPT="${SCRIPT_DIR}/send-guarded-message.sh"
LEDGER_FILE="${WORKSPACE_DIR}/memory/mistake-ledger.jsonl"
STATE_DIR="${WORKSPACE_DIR}/.state/send-guard"

mkdir -p "$STATE_DIR" "$(dirname "$LEDGER_FILE")"

# Reset deterministic test contexts
for ctx in test-empty test-dup test-split; do
  key_hash="$(python3 - <<'PY' "telegram" "62403941" "$ctx"
import hashlib,sys
print(hashlib.sha1('|'.join(sys.argv[1:4]).encode('utf-8')).hexdigest())
PY
)"
  rm -f "${STATE_DIR}/${key_hash}.json"
done

echo "[1/3] empty payload block"
set +e
"$GUARD_SCRIPT" --channel telegram --target 62403941 --message "   " --context test-empty --dry-run >/tmp/test-send-guard-empty.log 2>&1
rc=$?
set -e
if [[ $rc -ne 20 ]]; then
  echo "FAIL: expected exit 20 for empty payload, got $rc"
  cat /tmp/test-send-guard-empty.log
  exit 1
fi

echo "[2/3] duplicate block"
set +e
"$GUARD_SCRIPT" --channel telegram --target 62403941 --message "중복 테스트 메시지" --context test-dup --dry-run >/tmp/test-send-guard-dup1.log 2>&1
"$GUARD_SCRIPT" --channel telegram --target 62403941 --message "중복 테스트 메시지" --context test-dup --dry-run >/tmp/test-send-guard-dup2.log 2>&1
rc=$?
set -e
if [[ $rc -ne 21 ]]; then
  echo "FAIL: expected exit 21 for duplicate payload, got $rc"
  cat /tmp/test-send-guard-dup2.log
  exit 1
fi

echo "[3/3] long message split"
LONG_MSG="$(python3 - <<'PY'
print('A'*4100)
PY
)"
"$GUARD_SCRIPT" --channel telegram --target 62403941 --message "$LONG_MSG" --context test-split --dry-run >/tmp/test-send-guard-split.log 2>&1
if ! grep -q "parts=2" /tmp/test-send-guard-split.log; then
  echo "FAIL: expected parts=2 in split output"
  cat /tmp/test-send-guard-split.log
  exit 1
fi

echo "PASS: send guard tests all green"
