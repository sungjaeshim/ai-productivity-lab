#!/usr/bin/env bash
set -euo pipefail

ROOT="/root/.openclaw/workspace"
STATE_DIR="$ROOT/.state"
STATE_FILE="$STATE_DIR/nightly-maintenance.json"
HISTORY_FILE="$STATE_DIR/nightly-maintenance-history.jsonl"
LOG_FILE="$STATE_DIR/nightly-maintenance.log"

mkdir -p "$STATE_DIR"

now_kst() {
  TZ=Asia/Seoul date '+%Y-%m-%dT%H:%M:%S%z'
}

log() {
  echo "[$(now_kst)] $*" | tee -a "$LOG_FILE"
}

status="PASS"
sqlite_enabled=0
sqlite_status="SKIP"
sqlite_total_items=0
sqlite_inserted=0
sqlite_updated=0
sqlite_deduped=0

log "START nightly-memory-hygiene"

promote_out="$(python3 "$ROOT/scripts/memory_promote.py")"
recall_out="$(python3 "$ROOT/scripts/recall_quick_check.py")"

# parse key=value from memory_promote output
get_kv() {
  local key="$1"
  echo "$promote_out" | awk -F'=' -v k="$key" '$1==k {print $2}' | tail -n1
}

updated_sections="$(get_kv updated_sections)"
duplicates_removed_estimate="$(get_kv duplicates_removed_estimate)"
reconfirm_weekly_status="$(get_kv reconfirm_weekly_status)"
soft_warn_streak_days="$(get_kv soft_warn_streak_days)"
reconfirm_reminder_due="$(get_kv reconfirm_reminder_due)"
memory_quality_score_raw="$(get_kv memory_quality_score)"
memory_quality_score="${memory_quality_score_raw%/10}"

restore_readiness_score="$(echo "$recall_out" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("restore_readiness_score",0))')"
recall_status="$(echo "$recall_out" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("status","WARN"))')"

if command -v sqlite3 >/dev/null 2>&1; then
  sqlite_enabled=1
  if sqlite_out="$(python3 "$ROOT/scripts/memory_sqlite_mirror.py")"; then
    sqlite_status="PASS"
    sqlite_total_items="$(echo "$sqlite_out" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("total_items",0))')"
    sqlite_inserted="$(echo "$sqlite_out" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("inserted",0))')"
    sqlite_updated="$(echo "$sqlite_out" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("updated",0))')"
    sqlite_deduped="$(echo "$sqlite_out" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("deduped",0))')"
  else
    sqlite_status="FAIL"
    status="WARN"
  fi
fi

if [[ "${recall_status}" != "PASS" ]]; then
  status="WARN"
fi

cat > "$STATE_FILE" <<JSON
{
  "timestamp": "$(now_kst)",
  "status": "${status}",
  "updated_sections": ${updated_sections:-0},
  "duplicates_removed_estimate": ${duplicates_removed_estimate:-0},
  "memory_quality_score": ${memory_quality_score:-0},
  "restore_readiness_score": ${restore_readiness_score:-0},
  "recall_status": "${recall_status}",
  "reconfirm_weekly_status": "${reconfirm_weekly_status:-unknown}",
  "soft_warn_streak_days": ${soft_warn_streak_days:-0},
  "reconfirm_reminder_due": ${reconfirm_reminder_due:-0},
  "sqlite": {
    "enabled": ${sqlite_enabled},
    "status": "${sqlite_status}",
    "total_items": ${sqlite_total_items},
    "inserted": ${sqlite_inserted},
    "updated": ${sqlite_updated},
    "deduped": ${sqlite_deduped}
  }
}
JSON

python3 - "$STATE_FILE" "$HISTORY_FILE" <<'PY'
import json
import sys
from pathlib import Path

state_path = Path(sys.argv[1])
history_path = Path(sys.argv[2])
payload = json.loads(state_path.read_text(encoding='utf-8'))
with history_path.open('a', encoding='utf-8') as f:
    f.write(json.dumps(payload, ensure_ascii=False) + '\n')
PY

log "status=${status} restore_readiness=${restore_readiness_score} memory_quality=${memory_quality_score} sqlite=${sqlite_status}"

# Alert only on warning/failure (silent on PASS)
if [[ "${status}" != "PASS" ]]; then
  ALERT_CHANNEL="${ALERT_CHANNEL:-telegram}"
  ALERT_TARGET="${ALERT_TARGET:-62403941}"
  ALERT_STATE_FILE="$STATE_DIR/nightly-maintenance-alert-last.txt"
  alert_key="$(TZ=Asia/Seoul date +%F)|${status}|${restore_readiness_score}|${sqlite_status}"

  if [[ ! -f "$ALERT_STATE_FILE" ]] || [[ "$(cat "$ALERT_STATE_FILE" 2>/dev/null || true)" != "$alert_key" ]]; then
    alert_msg="⚠️ Nightly 메모리 유지보수 경고\nstatus=${status}\nrestore_readiness_score=${restore_readiness_score}\nmemory_quality_score=${memory_quality_score}\nsqlite=${sqlite_status}"
    if command -v openclaw >/dev/null 2>&1; then
      openclaw message send --channel "$ALERT_CHANNEL" --target "$ALERT_TARGET" --message "$alert_msg" >/dev/null 2>&1 || true
    fi
    echo "$alert_key" > "$ALERT_STATE_FILE"
    log "alert_sent channel=${ALERT_CHANNEL} target=${ALERT_TARGET}"
  else
    log "alert_skipped_duplicate key=${alert_key}"
  fi
fi

log "DONE nightly-memory-hygiene"

echo "NIGHTLY_MAINTENANCE status=${status} restore=${restore_readiness_score} quality=${memory_quality_score} sqlite=${sqlite_status}"
