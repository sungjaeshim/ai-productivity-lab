#!/usr/bin/env bash
# send-guard-observe.sh
# Lightweight 24h observation report for send guard + mistake ledger

set -euo pipefail

WORKSPACE_DIR="/root/.openclaw/workspace"
LEDGER_FILE="${WORKSPACE_DIR}/memory/mistake-ledger.jsonl"
STATE_GUARD_DIR="${WORKSPACE_DIR}/.state/send-guard"
ROUTER_STATE_FILE="${WORKSPACE_DIR}/.state/brain-router-monitor-state.json"
QUEUE_STATE_FILE="${WORKSPACE_DIR}/.state/brain-queue-autoclean-state.json"

CHANNEL="telegram"
TARGET="62403941"
SINCE_HOURS="24"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel) CHANNEL="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --since-hours) SINCE_HOURS="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

readarray -t METRICS < <(python3 - <<'PY' "$LEDGER_FILE" "$SINCE_HOURS"
import json,sys,datetime
from collections import Counter

ledger=sys.argv[1]
since_hours=int(sys.argv[2])
now=datetime.datetime.now(datetime.timezone.utc)
cutoff=now-datetime.timedelta(hours=since_hours)

counter=Counter()
recent=0
last_ts="-"

try:
    with open(ledger,encoding='utf-8') as f:
        for line in f:
            line=line.strip()
            if not line:
                continue
            try:
                o=json.loads(line)
            except Exception:
                continue
            ts=o.get('timestamp')
            if not ts:
                continue
            try:
                dt=datetime.datetime.fromisoformat(ts.replace('Z','+00:00'))
            except Exception:
                continue
            if dt.tzinfo is None:
                dt=dt.replace(tzinfo=datetime.timezone.utc)
            if dt >= cutoff:
                recent += 1
                typ=o.get('type','unknown')
                counter[typ]+=1
                if last_ts == "-" or dt.isoformat() > last_ts:
                    last_ts=dt.isoformat()
except FileNotFoundError:
    pass

print(recent)
print(counter.get('empty_payload_block',0))
print(counter.get('duplicate_message_block',0))
print(counter.get('length_split_applied',0))
print(counter.get('send_failure',0))
print(last_ts)
PY
)

RECENT_TOTAL="${METRICS[0]:-0}"
EMPTY_BLOCKS="${METRICS[1]:-0}"
DUP_BLOCKS="${METRICS[2]:-0}"
SPLIT_APPLIED="${METRICS[3]:-0}"
SEND_FAILS="${METRICS[4]:-0}"
LAST_EVENT_TS="${METRICS[5]:--}"

ROUTER_LEVEL="unknown"
ROUTER_MEM_FAIL_STREAK="0"
if [[ -f "$ROUTER_STATE_FILE" ]]; then
  ROUTER_LEVEL="$(jq -r '.level // "unknown"' "$ROUTER_STATE_FILE" 2>/dev/null || echo unknown)"
  ROUTER_MEM_FAIL_STREAK="$(jq -r '.memory_fail_streak // 0' "$ROUTER_STATE_FILE" 2>/dev/null || echo 0)"
fi

QUEUE_REMAIN="0"
QUEUE_CONSEC_FAIL="0"
if [[ -f "$QUEUE_STATE_FILE" ]]; then
  QUEUE_REMAIN="$(jq -r '.remaining_total // 0' "$QUEUE_STATE_FILE" 2>/dev/null || echo 0)"
  QUEUE_CONSEC_FAIL="$(jq -r '.consecutive_fail_runs // 0' "$QUEUE_STATE_FILE" 2>/dev/null || echo 0)"
fi

GUARD_STATE_FILES="0"
if [[ -d "$STATE_GUARD_DIR" ]]; then
  GUARD_STATE_FILES="$(find "$STATE_GUARD_DIR" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
fi

if [[ "$SEND_FAILS" =~ ^[0-9]+$ ]] && (( SEND_FAILS > 0 )); then
  CONCLUSION="추가 튜닝 필요 (send_failure 감지)"
elif [[ "$ROUTER_LEVEL" != "ok" || "$QUEUE_REMAIN" != "0" ]]; then
  CONCLUSION="관찰 유지 필요 (router/queue 비정상 신호)"
else
  CONCLUSION="안정 운영 유지"
fi

MSG=$(cat <<EOF
🔎 Send-Guard 24h 관측 (저부하)
기간: 최근 ${SINCE_HOURS}시간
이벤트: total ${RECENT_TOTAL} | empty ${EMPTY_BLOCKS} | duplicate ${DUP_BLOCKS} | split ${SPLIT_APPLIED} | send_fail ${SEND_FAILS}
Router/Queue: level ${ROUTER_LEVEL}, mem_fail_streak ${ROUTER_MEM_FAIL_STREAK}, remain ${QUEUE_REMAIN}, consec_fail ${QUEUE_CONSEC_FAIL}
Guard state files: ${GUARD_STATE_FILES} | last_event: ${LAST_EVENT_TS}
결론: ${CONCLUSION}
EOF
)

if $DRY_RUN; then
  echo "$MSG"
  exit 0
fi

/root/.openclaw/workspace/scripts/send-guarded-message.sh \
  --channel "$CHANNEL" \
  --target "$TARGET" \
  --message "$MSG" \
  --context send-guard-observe >/dev/null

echo "HEARTBEAT_OK"
