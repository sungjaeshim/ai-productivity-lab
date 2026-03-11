#!/usr/bin/env bash
set -euo pipefail

ROOT="/root/.openclaw/workspace/tmp/discrawl"
STATE_DIR="/root/.openclaw/workspace/.state"
LOG_JSONL="$STATE_DIR/discrawl-sync-runs.jsonl"

mkdir -p "$STATE_DIR"

start_iso=$(date -Is)
start_epoch=$(date +%s)

set +e
raw_out=$(cd "$ROOT" && /usr/bin/time -f 'ELAPSED=%E MAXRSS_KB=%M' ./bin/discrawl sync --full 2>&1)
exit_code=$?
set -e

end_iso=$(date -Is)
end_epoch=$(date +%s)
duration_sec=$((end_epoch - start_epoch))

# compact single-line preview for quick scans
preview=$(printf '%s' "$raw_out" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-1200)

python3 - <<'PY' "$LOG_JSONL" "$start_iso" "$end_iso" "$duration_sec" "$exit_code" "$preview"
import json, sys
path, start_iso, end_iso, duration_sec, exit_code, preview = sys.argv[1:]
row = {
  "start": start_iso,
  "end": end_iso,
  "duration_sec": int(duration_sec),
  "exit_code": int(exit_code),
  "preview": preview,
}
with open(path, "a", encoding="utf-8") as f:
  f.write(json.dumps(row, ensure_ascii=False) + "\n")
print("SYNC_OK" if int(exit_code) == 0 else "SYNC_FAIL")
PY

exit "$exit_code"
