#!/usr/bin/env bash
# send-guarded-message.sh
# Pre-send guard wrapper for OpenClaw message send:
# 1) empty payload block
# 2) near-duplicate block
# 3) over-length auto split

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
STATE_DIR="${WORKSPACE_DIR}/.state/send-guard"
LOG_MISTAKE_SCRIPT="${SCRIPT_DIR}/log-mistake.sh"

CHANNEL=""
TARGET=""
MESSAGE=""
CONTEXT="default"
DRY_RUN=false
SIMILARITY_THRESHOLD="${SEND_GUARD_SIM_THRESHOLD:-0.92}"
DEDUP_WINDOW_MIN="${SEND_GUARD_DEDUP_WINDOW_MIN:-30}"

usage() {
  cat <<EOF
Usage: $0 --channel <telegram|discord|...> --target <id> --message <text> [--context <key>] [--dry-run]

Exit codes:
  0 success
  20 blocked: empty payload
  21 blocked: duplicate/near-duplicate
  22 send failure
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel) CHANNEL="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --message) MESSAGE="$2"; shift 2 ;;
    --context) CONTEXT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$CHANNEL" || -z "$TARGET" ]]; then
  usage
  exit 1
fi

mkdir -p "$STATE_DIR"

TRIMMED="$(printf '%s' "$MESSAGE" | sed 's/^[[:space:]]\+//; s/[[:space:]]\+$//')"
if [[ -z "$TRIMMED" ]]; then
  "$LOG_MISTAKE_SCRIPT" \
    --type "empty_payload_block" \
    --source "send-guarded-message" \
    --detail "Blocked empty outbound payload" \
    --action "drop" \
    --severity "medium" \
    --rule "pre-send-empty-payload-block" \
    --meta-json "{\"channel\":\"$CHANNEL\",\"target\":\"$TARGET\",\"context\":\"$CONTEXT\"}" >/dev/null || true
  echo "BLOCKED:empty_payload"
  exit 20
fi

# Choose max length by channel (safe margin)
if [[ "$CHANNEL" == "telegram" ]]; then
  MAX_LEN="${SEND_GUARD_MAX_LEN_TELEGRAM:-3500}"
elif [[ "$CHANNEL" == "discord" ]]; then
  MAX_LEN="${SEND_GUARD_MAX_LEN_DISCORD:-1800}"
else
  MAX_LEN="${SEND_GUARD_MAX_LEN_DEFAULT:-2000}"
fi

KEY_HASH="$(python3 - <<'PY' "$CHANNEL" "$TARGET" "$CONTEXT"
import hashlib,sys
k='|'.join(sys.argv[1:4])
print(hashlib.sha1(k.encode('utf-8')).hexdigest())
PY
)"
STATE_FILE="${STATE_DIR}/${KEY_HASH}.json"

# Duplicate/near-duplicate check
DUPLICATE_BLOCKED=false
SIM_SCORE="0"
if [[ -f "$STATE_FILE" ]]; then
  read -r SIM_SCORE LAST_AGE_MIN <<<"$(python3 - <<'PY' "$STATE_FILE" "$TRIMMED"
import json,sys,re,difflib,time
state_path,new_msg=sys.argv[1],sys.argv[2]
try:
    s=json.load(open(state_path,encoding='utf-8'))
except Exception:
    print('0 999999')
    raise SystemExit

old=s.get('last_message','')
last_ts=float(s.get('last_ts_epoch',0) or 0)
now=time.time()
age_min=(now-last_ts)/60 if last_ts else 999999

def norm(x):
    x=x.lower()
    x=re.sub(r'\s+',' ',x).strip()
    x=re.sub(r'[^\w\s가-힣]','',x)
    return x

score=difflib.SequenceMatcher(None,norm(old),norm(new_msg)).ratio() if old else 0.0
print(f"{score:.6f} {age_min:.2f}")
PY
)"

  rc=0
  if python3 - <<'PY' "$SIM_SCORE" "$LAST_AGE_MIN" "$SIMILARITY_THRESHOLD" "$DEDUP_WINDOW_MIN"
import sys
score=float(sys.argv[1]); age=float(sys.argv[2]); th=float(sys.argv[3]); win=float(sys.argv[4])
if score >= th and age <= win:
    print("DUPLICATE")
    raise SystemExit(0)
raise SystemExit(1)
PY
  then
    DUPLICATE_BLOCKED=true
  fi
  if [[ $rc -eq 10 ]]; then
    DUPLICATE_BLOCKED=true
  fi
fi

if $DUPLICATE_BLOCKED; then
  "$LOG_MISTAKE_SCRIPT" \
    --type "duplicate_message_block" \
    --source "send-guarded-message" \
    --detail "Blocked near-duplicate outbound message" \
    --action "drop" \
    --severity "low" \
    --rule "pre-send-near-duplicate-block" \
    --meta-json "{\"channel\":\"$CHANNEL\",\"target\":\"$TARGET\",\"context\":\"$CONTEXT\",\"similarity\":$SIM_SCORE}" >/dev/null || true
  echo "BLOCKED:duplicate similarity=${SIM_SCORE}"
  exit 21
fi

split_message() {
  python3 - <<'PY' "$TRIMMED" "$MAX_LEN"
import sys
msg=sys.argv[1]
max_len=int(sys.argv[2])
parts=[]
while len(msg) > max_len:
    cut=msg.rfind('\n',0,max_len)
    if cut < int(max_len*0.5):
        cut=msg.rfind(' ',0,max_len)
    if cut < int(max_len*0.5):
        cut=max_len
    parts.append(msg[:cut].rstrip())
    msg=msg[cut:].lstrip()
parts.append(msg)
for p in parts:
    print(p)
    print('<<<PART_BREAK>>>')
PY
}

mapfile -t RAW_PARTS < <(split_message)
PARTS=()
CUR=""
for line in "${RAW_PARTS[@]}"; do
  if [[ "$line" == "<<<PART_BREAK>>>" ]]; then
    PARTS+=("$CUR")
    CUR=""
  else
    if [[ -z "$CUR" ]]; then
      CUR="$line"
    else
      CUR+=$'\n'"$line"
    fi
  fi
done

if [[ ${#PARTS[@]} -eq 0 ]]; then
  PARTS=("$TRIMMED")
fi

if $DRY_RUN; then
  echo "DRY_RUN: channel=$CHANNEL target=$TARGET context=$CONTEXT parts=${#PARTS[@]}"
  idx=1
  for p in "${PARTS[@]}"; do
    echo "PART[$idx] len=${#p}"
    idx=$((idx+1))
  done
else
  idx=1
  for p in "${PARTS[@]}"; do
    send_text="$p"
    if [[ ${#PARTS[@]} -gt 1 ]]; then
      send_text="[$idx/${#PARTS[@]}]\n${p}"
    fi
    if ! openclaw message send --channel "$CHANNEL" --target "$TARGET" --message "$send_text" --silent >/dev/null 2>&1; then
      "$LOG_MISTAKE_SCRIPT" \
        --type "send_failure" \
        --source "send-guarded-message" \
        --detail "openclaw message send failed" \
        --action "abort" \
        --severity "high" \
        --rule "pre-send-guarded-send" \
        --meta-json "{\"channel\":\"$CHANNEL\",\"target\":\"$TARGET\",\"context\":\"$CONTEXT\",\"part\":$idx,\"total\":${#PARTS[@]}}" >/dev/null || true
      echo "ERROR:send_failed part=${idx}/${#PARTS[@]}"
      exit 22
    fi
    idx=$((idx+1))
  done
fi

python3 - <<'PY' "$STATE_FILE" "$TRIMMED" "$SIM_SCORE" "$CHANNEL" "$TARGET" "$CONTEXT" "${#PARTS[@]}"
import json,sys,time
state_file,msg,sim,channel,target,context,parts=sys.argv[1:8]
obj={
  'updated_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
  'last_ts_epoch': time.time(),
  'last_message': msg,
  'last_similarity': float(sim),
  'channel': channel,
  'target': target,
  'context': context,
  'last_parts': int(parts),
}
with open(state_file,'w',encoding='utf-8') as f:
  json.dump(obj,f,ensure_ascii=False)
PY

if [[ ${#PARTS[@]} -gt 1 ]]; then
  "$LOG_MISTAKE_SCRIPT" \
    --type "length_split_applied" \
    --source "send-guarded-message" \
    --detail "Outbound message auto-split due to length" \
    --action "split_send" \
    --severity "low" \
    --rule "pre-send-length-split" \
    --meta-json "{\"channel\":\"$CHANNEL\",\"target\":\"$TARGET\",\"context\":\"$CONTEXT\",\"parts\":${#PARTS[@]},\"max_len\":$MAX_LEN}" >/dev/null || true
fi

echo "SENT:parts=${#PARTS[@]}"
exit 0
