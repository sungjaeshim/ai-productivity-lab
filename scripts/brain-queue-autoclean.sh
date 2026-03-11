#!/usr/bin/env bash
# brain-queue-autoclean.sh
# Auto-drain brain pending queues (url/note/route) safely.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
set +u
source "${SCRIPT_DIR}/env-loader.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/message-guard.sh" 2>/dev/null || true
set -u
SECOND_BRAIN_DIR="${SECOND_BRAIN_DIR:-${WORKSPACE_DIR}/memory/second-brain}"
LOCK_FILE="${SECOND_BRAIN_DIR}/.brain-queue-autoclean.lock"

URL_QUEUE="${SECOND_BRAIN_DIR}/.pending-queue.jsonl"
NOTE_QUEUE="${SECOND_BRAIN_DIR}/.pending-note-queue.jsonl"
ROUTE_QUEUE="${SECOND_BRAIN_DIR}/.pending-route-queue.jsonl"

URL_ARCHIVE="${SECOND_BRAIN_DIR}/.pending-queue.archive.jsonl"
NOTE_ARCHIVE="${SECOND_BRAIN_DIR}/.pending-note-queue.archive.jsonl"
STATE_FILE="${WORKSPACE_DIR}/.state/brain-queue-autoclean-state.json"
ALERT_THRESHOLD="${BRAIN_QUEUE_ALERT_CONSEC_FAILS:-3}"
ALERT_CHANNEL="${DISCORD_SYSTEM_HEALTH:-1477310512680276080}"
RECOVERY_NOTIFY="${BRAIN_QUEUE_RECOVERY_NOTIFY:-false}"

mkdir -p "$SECOND_BRAIN_DIR" "$(dirname "$STATE_FILE")"
touch "$URL_QUEUE" "$NOTE_QUEUE" "$ROUTE_QUEUE"

exec 210>"$LOCK_FILE"
if ! flock -n 210; then
  echo "HEARTBEAT_OK: queue-autoclean already running"
  exit 0
fi

count_lines() {
  wc -l < "$1" | tr -d ' '
}

is_truthy() {
  local v
  v="$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')"
  [[ "$v" == "1" || "$v" == "true" || "$v" == "yes" || "$v" == "on" ]]
}

URL_BEFORE=$(count_lines "$URL_QUEUE")
NOTE_BEFORE=$(count_lines "$NOTE_QUEUE")
ROUTE_BEFORE=$(count_lines "$ROUTE_QUEUE")

URL_OK=0
URL_FAIL=0
NOTE_OK=0
NOTE_FAIL=0

if (( URL_BEFORE > 0 )); then
python3 - <<'PY'
import json,subprocess,datetime
from pathlib import Path
q=Path('/root/.openclaw/workspace/memory/second-brain/.pending-queue.jsonl')
arch=Path('/root/.openclaw/workspace/memory/second-brain/.pending-queue.archive.jsonl')
lines=[ln for ln in q.read_text(encoding='utf-8').splitlines() if ln.strip()]
ok=[]; fail=[]
for ln in lines:
    try:
        o=json.loads(ln)
    except Exception as e:
        fail.append((ln,f'json:{e}'))
        continue
    url=(o.get('url') or '').strip()
    title=(o.get('title') or '').strip() or 'Captured link'
    summary=(o.get('summary') or '').strip() or '큐 적재 항목 재처리'
    opinion=(o.get('my_opinion') or '').strip() or '후속 검토 후보'
    if not url:
        fail.append((ln,'missing_url')); continue
    cmd=['bash','/root/.openclaw/workspace/scripts/brain-link-ingest.sh','--url',url,'--title',title,'--summary',summary,'--my-opinion',opinion,'--force']
    p=subprocess.run(cmd,capture_output=True,text=True)
    if p.returncode==0:
        ok.append({'url':url,'code':0})
    else:
        err=(p.stdout+'\n'+p.stderr).strip()[-300:]
        fail.append((ln,f'exit:{p.returncode}:{err}'))

# rewrite queue with failures only
q.write_text(('\n'.join([f[0] for f in fail])+'\n') if fail else '',encoding='utf-8')
if ok:
    now=datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
    with arch.open('a',encoding='utf-8') as w:
        for r in ok:
            w.write(json.dumps({'processed_at':now,**r},ensure_ascii=False)+'\n')
print(f"URL_OK={len(ok)} URL_FAIL={len(fail)}")
PY
fi

if (( NOTE_BEFORE > 0 )); then
python3 - <<'PY'
import json,subprocess,datetime
from pathlib import Path
q=Path('/root/.openclaw/workspace/memory/second-brain/.pending-note-queue.jsonl')
arch=Path('/root/.openclaw/workspace/memory/second-brain/.pending-note-queue.archive.jsonl')
lines=[ln for ln in q.read_text(encoding='utf-8').splitlines() if ln.strip()]
ok=[]; fail=[]
for ln in lines:
    try:
        o=json.loads(ln)
    except Exception as e:
        fail.append((ln,f'json:{e}'))
        continue
    text=(o.get('text') or '').strip()
    title=(o.get('title') or '').strip() or 'Captured memo'
    summary=(o.get('summary') or '').strip() or '큐 적재 메모 재처리'
    opinion=(o.get('my_opinion') or '').strip() or '후속 검토 후보'
    if not text:
        fail.append((ln,'missing_text')); continue
    cmd=['bash','/root/.openclaw/workspace/scripts/brain-note-ingest.sh','--text',text,'--title',title,'--summary',summary,'--my-opinion',opinion,'--force']
    p=subprocess.run(cmd,capture_output=True,text=True)
    if p.returncode==0:
        ok.append({'title':title,'code':0})
    else:
        err=(p.stdout+'\n'+p.stderr).strip()[-300:]
        fail.append((ln,f'exit:{p.returncode}:{err}'))

q.write_text(('\n'.join([f[0] for f in fail])+'\n') if fail else '',encoding='utf-8')
if ok:
    now=datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
    with arch.open('a',encoding='utf-8') as w:
        for r in ok:
            w.write(json.dumps({'processed_at':now,**r},ensure_ascii=False)+'\n')
print(f"NOTE_OK={len(ok)} NOTE_FAIL={len(fail)}")
PY
fi

ROUTE_OUT="$(bash "$SCRIPT_DIR/brain-route-retry.sh" 2>&1 || true)"

URL_AFTER=$(count_lines "$URL_QUEUE")
NOTE_AFTER=$(count_lines "$NOTE_QUEUE")
ROUTE_AFTER=$(count_lines "$ROUTE_QUEUE")
REMAINING_TOTAL=$((URL_AFTER + NOTE_AFTER + ROUTE_AFTER))

PREV_CONSEC=0
if [[ -f "$STATE_FILE" ]]; then
  PREV_CONSEC="$(jq -r '.consecutive_fail_runs // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
fi

if (( REMAINING_TOTAL > 0 )); then
  CONSEC_FAIL=$((PREV_CONSEC + 1))
else
  CONSEC_FAIL=0
fi

NOW_ISO="$(date -Iseconds)"
jq -cn \
  --argjson consecutive_fail_runs "$CONSEC_FAIL" \
  --argjson remaining_total "$REMAINING_TOTAL" \
  --argjson url_after "$URL_AFTER" \
  --argjson note_after "$NOTE_AFTER" \
  --argjson route_after "$ROUTE_AFTER" \
  --arg updated_at "$NOW_ISO" \
  '{consecutive_fail_runs:$consecutive_fail_runs,remaining_total:$remaining_total,url_after:$url_after,note_after:$note_after,route_after:$route_after,updated_at:$updated_at}' \
  > "$STATE_FILE"

if (( PREV_CONSEC < ALERT_THRESHOLD && CONSEC_FAIL >= ALERT_THRESHOLD )); then
  ALERT_MSG="⚠️ brain 큐 자동정리 경고\n- 연속 실패: ${CONSEC_FAIL}회\n- 잔여 큐: ${REMAINING_TOTAL} (url:${URL_AFTER}, note:${NOTE_AFTER}, route:${ROUTE_AFTER})\n- action: queue payload/권한/외부 API 오류 점검 필요"
  if validate_message_params --channel discord --target "$ALERT_CHANNEL"; then
    "$SCRIPT_DIR/send-guarded-message.sh" \
      --channel discord \
      --target "$ALERT_CHANNEL" \
      --message "$ALERT_MSG" \
      --context brain-queue-autoclean >/dev/null 2>&1 || true
  else
    echo "[WARN] Alert skipped: validation failed" >&2
  fi
elif is_truthy "$RECOVERY_NOTIFY" && (( PREV_CONSEC >= ALERT_THRESHOLD && CONSEC_FAIL == 0 )); then
  REC_MSG="✅ brain 큐 자동정리 복구\n- 연속 실패 해소\n- 잔여 큐: 0 (url:0, note:0, route:0)"
  if validate_message_params --channel discord --target "$ALERT_CHANNEL"; then
    "$SCRIPT_DIR/send-guarded-message.sh" \
      --channel discord \
      --target "$ALERT_CHANNEL" \
      --message "$REC_MSG" \
      --context brain-queue-autoclean >/dev/null 2>&1 || true
  else
    echo "[WARN] Recovery notify skipped: validation failed" >&2
  fi
fi

echo "HEARTBEAT_OK: autoclean url ${URL_BEFORE}->${URL_AFTER}, note ${NOTE_BEFORE}->${NOTE_AFTER}, route ${ROUTE_BEFORE}->${ROUTE_AFTER}, consec_fail=${CONSEC_FAIL}"
if [[ -n "$ROUTE_OUT" ]]; then
  echo "$ROUTE_OUT" | tail -n 1
fi
