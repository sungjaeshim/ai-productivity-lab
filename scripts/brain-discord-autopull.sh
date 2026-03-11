#!/usr/bin/env bash
# brain-discord-autopull.sh
# Discord user messages -> brain ingest pipeline with the same routing criteria as Telegram autopull
# Usage: brain-discord-autopull.sh [--dry-run] [--init-now]

set -euo pipefail

DRY_RUN=false
INIT_NOW=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --init-now) INIT_NOW=true ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$(cd "${SCRIPT_DIR}/.." && pwd)"
set +u
source "${SCRIPT_DIR}/env-loader.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/message-guard.sh" 2>/dev/null || true
set -u

SECOND_BRAIN_DIR="${SECOND_BRAIN_DIR:-${WORKSPACE}/memory/second-brain}"
CHECKPOINT_FILE="${WORKSPACE}/memory/second-brain/.brain-discord-autopull-checkpoint.json"
ROUTE_RETRY_QUEUE="${SECOND_BRAIN_DIR}/.pending-route-queue.jsonl"
ROUTE_RETRY_LOCK="${SECOND_BRAIN_DIR}/.pending-route-queue.lock"
STAGE0_DIR="${WORKSPACE}/feedback"
STAGE0_FILE="${STAGE0_DIR}/ralph-stage0-routing.jsonl"
STAGE0_LOCK_FILE="${STAGE0_DIR}/ralph-stage0-routing.lock"
ROUTE_RETRY_DELAY_SEC="${BRAIN_ROUTE_RETRY_DELAY_SEC:-300}"
DISCORD_READ_LIMIT="${BRAIN_DISCORD_READ_LIMIT:-50}"
ACK_DISCORD="${BRAIN_ROUTER_ACK_DISCORD:-true}"
AUTO_LEARN_ENABLED="${BRAIN_AUTO_LEARN_ENABLED:-true}"
AUTO_LEARN_SCRIPT="${SCRIPT_DIR}/brain-auto-route-learn.sh"
AUTO_KEYWORDS_FILE="${SECOND_BRAIN_DIR}/.auto-route-keywords.json"

TMP_URLS="$(mktemp)"
TMP_MEMOS="$(mktemp)"
TMP_CHANNELS="$(mktemp)"
TMP_LAST_IDS="$(mktemp)"

cleanup() {
  rm -f "$TMP_URLS" "$TMP_MEMOS" "$TMP_CHANNELS" "$TMP_LAST_IDS"
}
trap cleanup EXIT

mkdir -p "$(dirname "$CHECKPOINT_FILE")" "$SECOND_BRAIN_DIR" "$STAGE0_DIR"
touch "$STAGE0_FILE"

is_truthy() {
  local v
  v="$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')"
  [[ "$v" == "1" || "$v" == "true" || "$v" == "yes" || "$v" == "on" ]]
}

normalize_channels() {
  local raw="$1"
  printf '%s\n' "$raw" \
    | tr ',; ' '\n\n\n' \
    | sed '/^$/d' \
    | sed 's/^channel://I' \
    | awk '{gsub(/^[[:space:]]+|[[:space:]]+$/,""); if(length($0)>0) print $0}' \
    | awk '!seen[$0]++'
}

send_discord_ack() {
  local channel_id="$1"
  local msg="$2"
  if ! is_truthy "$ACK_DISCORD"; then
    return 0
  fi

  # Validate channel and target before sending
  if ! MESSAGE_GUARD_DRY_RUN="$DRY_RUN" validate_message_params --channel discord --target "$channel_id"; then
    echo "[WARN] Discord ack skipped: validation failed" >&2
    return 1
  fi

  if $DRY_RUN; then
    echo "[DRY-RUN][ACK][discord:${channel_id}] ${msg}"
    return 0
  fi
  openclaw message send --channel discord --target "$channel_id" --message "$msg" --silent >/dev/null 2>&1 || true
}

append_stage0_queue_event() {
  local retry_id="$1"
  local route_type="$2"
  local source_ts="$3"
  local raw="$4"
  local routed_raw="$5"
  local reason="$6"
  local last_error="$7"
  local created_at stage0_id entry

  created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  stage0_id="$(python3 - <<'PY' "$retry_id" "$route_type" "$source_ts" "$created_at"
import hashlib
import sys
retry_id, route_type, source_ts, created_at = sys.argv[1:5]
finger = f"route_retry_queued|{retry_id}|{route_type}|{source_ts}|{created_at}"
print(hashlib.sha1(finger.encode("utf-8")).hexdigest()[:20])
PY
)"
  entry="$(jq -cn \
    --arg stage0_id "$stage0_id" \
    --arg event_type "route_retry_queued" \
    --arg status "pending" \
    --arg retry_id "$retry_id" \
    --arg route_type "$route_type" \
    --arg source_ts "$source_ts" \
    --arg raw "$raw" \
    --arg routed_raw "$routed_raw" \
    --arg reason "$reason" \
    --arg last_error "$last_error" \
    --arg worker "brain-discord-autopull" \
    --arg created_at "$created_at" \
    --argjson attempts 0 \
    '{stage0_id:$stage0_id,event_type:$event_type,status:$status,retry_id:$retry_id,route_type:$route_type,source_ts:$source_ts,raw:$raw,routed_raw:$routed_raw,reason:$reason,last_error:$last_error,attempts:$attempts,worker:$worker,created_at:$created_at}')"

  if $DRY_RUN; then
    echo "[DRY-RUN][stage0] $entry"
    return 0
  fi

  {
    flock -x 202
    printf '%s\n' "$entry" >> "$STAGE0_FILE"
  } 202>"$STAGE0_LOCK_FILE"
}

fallback_note_ingest() {
  local title="$1"
  local text="$2"
  "$SCRIPT_DIR/brain-note-ingest.sh" \
    --title "$title" \
    --text "$text" \
    --summary "Auto-captured memo from Discord" \
    --my-opinion "자동 메모 수집 항목 (후속 검토 필요)" || true
}

run_auto_learn() {
  if ! is_truthy "$AUTO_LEARN_ENABLED"; then
    return 0
  fi
  if [[ ! -x "$AUTO_LEARN_SCRIPT" ]]; then
    return 0
  fi
  "$AUTO_LEARN_SCRIPT" "$@" >/dev/null 2>&1 || true
}

classify_auto_message() {
  python3 - <<'PY' "$1" "$AUTO_KEYWORDS_FILE"
import json,re,sys
raw=sys.argv[1].strip()
keywords_path=sys.argv[2].strip()
text=' '.join(raw.split())
if not text:
    print(json.dumps({"ok":False,"error":"empty"}))
    raise SystemExit(0)

low=text.lower()
skip_exact={
    "ok","okay","yes","no","응","네","ㅇㅋ","완료","보냄","전송","확인","테스트",
    "done","sent","checked","확인함","테스트완료"
}
if low in skip_exact or len(text) < 5:
    print(json.dumps({"ok":False,"error":"too_short_or_ack"}))
    raise SystemExit(0)

sys_kw=["#sys","시스템","서버","cpu","ram","disk","업타임","uptime","health","장애","에러율","메모리"]
todo_kw=["할일","todo","체크","확인","정리","검토","수정","업데이트","작성","보내","공유","리마인드","준비","미팅","전화","follow up","follow-up","해야","해줘","해줄","바꿔","고쳐","할까"]
ops_todo_kw=["inbox","today","라우팅","route","routing","autopull","cron","스케줄","필터","분류","동작","작동","안와","안 와","누락","완화"]
trade_kw=["nq","es","long","short","진입","청산","손절","익절","포지션","트레이딩","선물","매수","매도","리스크"]
decision_kw=["결정","결론","의사결정","원칙","정책","기준","rule","policy","앞으로","금지","허용"]

def load_keywords(path):
    base={"todo":{},"idea":{},"decision":{},"trade":{},"sys":{}}
    if not path:
        return base
    try:
        with open(path,'r',encoding='utf-8') as f:
            obj=json.load(f)
        if isinstance(obj,dict):
            for k in base.keys():
                if isinstance(obj.get(k),dict):
                    base[k]=obj.get(k)
    except Exception:
        pass
    return base

def learned_scores(low_text):
    data=load_keywords(keywords_path)
    scores={k:0 for k in data.keys()}
    for label,kw_map in data.items():
        for kw,w in kw_map.items():
            if not kw:
                continue
            try:
                weight=int(w)
            except Exception:
                continue
            if weight <= 0:
                continue
            key=kw.lower()
            if key in low_text:
                scores[label]+=weight
    return scores

todo_hint=(
    "|" in text
    or re.search(r'\bp[1-4]\b', low) is not None
    or re.search(r'\b(today|tomorrow)\b', low) is not None
    or re.search(r'\b\d{4}-\d{2}-\d{2}\b', low) is not None
    or any(k in low for k in todo_kw)
    or any(k in low for k in ops_todo_kw)
)
sys_hint=any(k in low for k in sys_kw)
trade_hint=any(k in low for k in trade_kw)
explicit_trade = re.match(r'^\s*#trade\b', low) is not None
decision_hint=any(k in low for k in decision_kw)
scores=learned_scores(low)

route_type="tag"
tag="idea"
reason="default_idea"

if sys_hint or scores.get("sys",0) >= 3:
    tag="sys"
    reason="sys_keywords_or_learned"
elif todo_hint or scores.get("todo",0) >= 3:
    route_type="todo"
    reason="todo_keywords_due_or_learned"
elif explicit_trade:
    tag="trade"
    reason="trade_explicit_tag_only"
elif decision_hint or scores.get("decision",0) >= 3:
    tag="decision"
    reason="decision_keywords_or_learned"
elif scores.get("idea",0) >= 3:
    tag="idea"
    reason="idea_learned"
else:
    top_label=max(scores.keys(), key=lambda k:scores[k]) if scores else "idea"
    if scores.get(top_label,0) >= 2 and top_label != "trade":
      if top_label == "todo":
          route_type="todo"
      else:
          route_type="tag"
          tag=top_label
      reason=f"soft_learned:{top_label}"

if route_type == "todo":
    routed_raw=f"#todo {text}"
else:
    routed_raw=f"#{tag} {text}"

print(json.dumps({
    "ok":True,
    "route_type":route_type,
    "tag":tag,
    "reason":reason,
    "routed_raw":routed_raw,
    "raw":text
}, ensure_ascii=False))
PY
}

queue_route_retry() {
  local route_type="$1"
  local source_ts="$2"
  local raw="$3"
  local routed_raw="$4"
  local reason="$5"
  local last_error="${6:-unknown}"
  local retry_id now_epoch now_iso entry next_retry
  retry_id="$(python3 - <<'PY' "$route_type" "$source_ts" "$routed_raw"
import hashlib,sys
route_type,source_ts,routed_raw=sys.argv[1:4]
finger=f"{route_type}|{source_ts}|{routed_raw}"
print(hashlib.sha1(finger.encode('utf-8')).hexdigest()[:20])
PY
)"
  now_epoch="$(date +%s)"
  now_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  next_retry=$((now_epoch + ROUTE_RETRY_DELAY_SEC))
  entry="$(jq -cn \
    --arg retry_id "$retry_id" \
    --arg route_type "$route_type" \
    --arg source_ts "$source_ts" \
    --arg raw "$raw" \
    --arg routed_raw "$routed_raw" \
    --arg reason "$reason" \
    --arg last_error "$last_error" \
    --arg queued_at "$now_iso" \
    --argjson next_retry_at_epoch "$next_retry" \
    '{retry_id:$retry_id,route_type:$route_type,source_ts:$source_ts,raw:$raw,routed_raw:$routed_raw,reason:$reason,attempts:0,next_retry_at_epoch:$next_retry_at_epoch,last_error:$last_error,queued_at:$queued_at}')"

  if $DRY_RUN; then
    echo "[DRY-RUN] Would queue route retry: ${retry_id}"
    return 0
  fi

  {
    flock -x 201
    touch "$ROUTE_RETRY_QUEUE"
    if rg -F -q "\"retry_id\":\"${retry_id}\"" "$ROUTE_RETRY_QUEUE"; then
      echo "SKIP: route retry already queued (${retry_id})"
    else
      printf '%s\n' "$entry" >> "$ROUTE_RETRY_QUEUE"
      echo "QUEUED: route retry (${retry_id})"
      append_stage0_queue_event "$retry_id" "$route_type" "$source_ts" "$raw" "$routed_raw" "$reason" "$last_error"
    fi
  } 201>"$ROUTE_RETRY_LOCK"
}

route_and_ack() {
  local route_type="$1"
  local routed_raw="$2"
  local source_ts="$3"
  local original_raw="$4"
  local reason="$5"
  local title="$6"
  local source_channel="$7"
  local route_script out err_preview route_label

  if [[ "$route_type" == "todo" ]]; then
    route_script="$SCRIPT_DIR/brain-todo-route.sh"
    route_label="#todo"
  else
    route_script="$SCRIPT_DIR/brain-tag-route.sh"
    route_label="$(echo "$routed_raw" | awk '{print $1}')"
  fi

  if $DRY_RUN; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[DRY-RUN][DISCORD_ROUTE] ${route_label} ($route_type)"
    echo "  Raw:     $original_raw"
    echo "  Routed:  $routed_raw"
    echo "  Time:    $source_ts"
    echo "  Channel: $source_channel"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    return 0
  fi

  if out="$("$route_script" --raw "$routed_raw" --source-ts "$source_ts" 2>&1)"; then
    echo "$out"
    send_discord_ack "$source_channel" "✅ 자동처리 ${route_label} | ${original_raw:0:28}"
    return 0
  fi

  echo "$out" >&2
  err_preview="$(echo "$out" | tail -n 2 | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-220)"
  queue_route_retry "$route_type" "$source_ts" "$original_raw" "$routed_raw" "$reason" "$err_preview"
  send_discord_ack "$source_channel" "⚠️ 자동처리 실패→재시도 ${route_label}"
  echo "WARN: route failed, queued retry, fallback to memo ingest" >&2
  fallback_note_ingest "$title" "$original_raw"
  return 0
}

get_checkpoint_last_id() {
  local channel_id="$1"
  if [[ ! -f "$CHECKPOINT_FILE" ]]; then
    echo ""
    return 0
  fi
  jq -r --arg c "$channel_id" '.channels[$c].last_id // .channels[$c] // empty' "$CHECKPOINT_FILE" 2>/dev/null || true
}

save_checkpoint() {
  if $DRY_RUN; then
    return 0
  fi

  if [[ ! -s "$TMP_LAST_IDS" ]]; then
    return 0
  fi

  python3 - <<'PY' "$CHECKPOINT_FILE" "$TMP_LAST_IDS"
import json,sys,datetime
checkpoint_path,last_ids_path=sys.argv[1:3]
obj={"channels":{},"updated_at":None}
try:
    with open(checkpoint_path,'r',encoding='utf-8') as f:
        cur=json.load(f)
    if isinstance(cur,dict):
        obj.update(cur)
except Exception:
    pass
if not isinstance(obj.get("channels"),dict):
    obj["channels"]={}
with open(last_ids_path,'r',encoding='utf-8') as f:
    for line in f:
        line=line.strip()
        if not line:
            continue
        parts=line.split('\t')
        if len(parts)<2:
            continue
        ch,last_id=parts[0].strip(),parts[1].strip()
        if not ch or not last_id:
            continue
        cur=obj["channels"].get(ch)
        if isinstance(cur,dict):
            cur["last_id"]=last_id
            cur["updated_at"]=datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
            obj["channels"][ch]=cur
        else:
            obj["channels"][ch]={
                "last_id":last_id,
                "updated_at":datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
            }
obj["updated_at"]=datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
with open(checkpoint_path,'w',encoding='utf-8') as f:
    json.dump(obj,f,ensure_ascii=False,indent=2)
print(f"checkpoint updated: {checkpoint_path}")
PY
}

# Build default channel candidates. Can be overridden with BRAIN_DISCORD_INPUT_CHANNELS.
# 기본값은 today 채널을 제외해 일반 대화의 과라우팅을 줄임.
INCLUDE_TODAY="${BRAIN_DISCORD_INCLUDE_TODAY:-false}"
TODAY_CANDIDATE=""
if [[ "${INCLUDE_TODAY,,}" == "true" || "${INCLUDE_TODAY,,}" == "1" ]]; then
  TODAY_CANDIDATE="${DISCORD_TODAY:-}"
fi
DEFAULT_CHANNELS_RAW="$(printf '%s\n' \
  "${DISCORD_INBOX:-}" \
  "$TODAY_CANDIDATE" \
  "${DISCORD_PROJ_TRADING_NQ:-${DISCORD_TRADING_NQ:-}}" \
  "${DISCORD_DECISION_LOG:-}" \
  "${DISCORD_SYSTEM_HEALTH:-}" \
  "${DISCORD_PROJ_GROWTH_CENTER:-}" \
  "${DISCORD_PROJ_SECOND_BRAIN:-}" \
  "${DISCORD_PROJ_CEO_AI:-}" \
  | sed '/^$/d')"
CHANNELS_RAW="${BRAIN_DISCORD_INPUT_CHANNELS:-$DEFAULT_CHANNELS_RAW}"
normalize_channels "$CHANNELS_RAW" > "$TMP_CHANNELS"

if [[ ! -s "$TMP_CHANNELS" ]]; then
  echo "brain-discord-autopull: no input channels configured"
  echo "HEARTBEAT_OK"
  exit 0
fi

if $INIT_NOW; then
  while IFS= read -r channel_id; do
    [[ -z "$channel_id" ]] && continue
    read_json="$(openclaw message read --channel discord --target "$channel_id" --limit 1 --json 2>/dev/null || true)"
    latest_id="$(echo "$read_json" | jq -r '.payload.messages[0].id // empty' 2>/dev/null || true)"
    if [[ -n "$latest_id" ]]; then
      printf '%s\t%s\n' "$channel_id" "$latest_id" >> "$TMP_LAST_IDS"
    fi
  done < "$TMP_CHANNELS"
  save_checkpoint
  echo "checkpoint initialized for Discord channels"
  echo "HEARTBEAT_OK"
  exit 0
fi

TOTAL_READ=0
TOTAL_USER=0
TOTAL_URL=0
TOTAL_MEMO=0

while IFS= read -r channel_id; do
  [[ -z "$channel_id" ]] && continue

  last_id="$(get_checkpoint_last_id "$channel_id")"
  cmd=(openclaw message read --channel discord --target "$channel_id" --limit "$DISCORD_READ_LIMIT" --json)
  if [[ -n "$last_id" ]]; then
    cmd+=(--after "$last_id")
  fi

  if ! read_out="$("${cmd[@]}" 2>&1)"; then
    echo "WARN: discord read failed for channel ${channel_id}" >&2
    echo "$read_out" >&2
    continue
  fi

  read_file="$(mktemp)"
  printf '%s\n' "$read_out" > "$read_file"

  parse_summary="$(python3 - <<'PY' "$read_file" "$channel_id" "$last_id" "$TMP_URLS" "$TMP_MEMOS"
import json,re,sys,base64
read_file,channel_id,last_id,out_urls,out_memos=sys.argv[1:6]

url_re=re.compile(r'https?://[^\s)\]>"\']+')
SYSTEM_PATTERNS = [
    r'scanner\.tradingview\.com',
    r'example\.com',
    r'example\.org',
    r'discord\.com/api/webhooks',
    r'discordapp\.com/api/webhooks',
    r'sentry\.io/api',
    r'ingest\.sentry\.io',
    r'localhost',
    r'127\.0\.0\.1',
    r'0\.0\.0\.0',
    r'\.internal\.',
    r'\.local',
    r'ngrok\.io',
    r'cloudflare\.com/cdn-cgi',
    r'api\.openai\.com',
    r'api\.anthropic\.com',
    r'generativelanguage\.googleapis\.com',
    r'api\.github\.com',
]

memo_prefix_re = re.compile(r'^(?:#?(?:memo|note)|메모)\s*[:：-]\s*(.+)$', re.IGNORECASE)
memo_hash_re = re.compile(r'^#((?:memo|note|메모|todo|idea|decision|trade|sys)\b.*)$', re.IGNORECASE)
auto_skip_exact = {
    "ok","okay","yes","no","응","네","ㅇㅋ","완료","보냄","전송","확인","테스트",
    "done","sent","checked","확인함","테스트완료"
}


def is_system_url(url):
    low=url.lower()
    return any(re.search(p, low) for p in SYSTEM_PATTERNS)


def is_noise_text(text):
    noise_markers = [
        '[cron:',
        '[System Message]',
        'System: [',
        'Exec completed',
    ]
    return any(marker in text for marker in noise_markers)


def strip_fenced_blocks(text):
    return re.sub(r'```[\s\S]*?```', '', text)


def clean_url(url):
    u=url.split('\\n',1)[0].split('\n',1)[0]
    return u.rstrip('`.,;:!?"\'')


def normalize_auto_text(text):
    lines=[]
    for raw in text.splitlines():
        line=raw.strip()
        if not line:
            continue
        if re.fullmatch(r'https?://\S+', line):
            continue
        lines.append(line)
    if not lines:
        return ''
    return re.sub(r'\s+', ' ', ' '.join(lines)).strip()


def extract_memos(text):
    memos=[]
    found_explicit=False
    for raw in text.splitlines():
        line=raw.strip()
        if not line:
            continue
        m=memo_prefix_re.match(line)
        if m:
            memo=m.group(1).strip()
            if memo:
                memos.append(memo)
                found_explicit=True
            continue
        m=memo_hash_re.match(line)
        if m:
            tagged=f"#{m.group(1).strip()}"
            lowered=tagged.lower()
            if lowered.startswith("#memo ") or lowered.startswith("#note ") or tagged.startswith("#메모 "):
                memo=tagged.split(" ",1)[1].strip()
                if memo:
                    memos.append(memo)
                    found_explicit=True
            else:
                memos.append(tagged)
                found_explicit=True
    if found_explicit:
        return memos

    auto_text=normalize_auto_text(text)
    if not auto_text:
        return []
    if len(auto_text) < 5:
        return []
    if auto_text.lower() in auto_skip_exact:
        return []
    return [f"#auto {auto_text}"]

try:
    data=json.load(open(read_file,'r',encoding='utf-8'))
except Exception:
    print(json.dumps({"ok":False,"error":"invalid_json"}))
    raise SystemExit(0)

msgs=((data.get('payload') or {}).get('messages') or [])
try:
    last_i=int(last_id) if last_id else 0
except Exception:
    last_i=0
max_i=last_i

url_rows=[]
memo_rows=[]
user_count=0

for msg in msgs:
    mid=str(msg.get('id') or '').strip()
    if not mid:
        continue
    try:
        mid_i=int(mid)
    except Exception:
        continue

    if mid_i > max_i:
        max_i=mid_i
    if last_i and mid_i <= last_i:
        continue

    author=msg.get('author') or {}
    if bool(author.get('bot')):
        continue

    user_count += 1

    ts=(msg.get('timestampUtc') or msg.get('timestamp') or '')
    content=msg.get('content') or ''
    if not isinstance(content,str):
        content=str(content)
    cleaned=strip_fenced_blocks(content)
    if is_noise_text(cleaned):
        continue

    urls=[]
    for u in url_re.findall(cleaned):
        c=clean_url(u)
        if not c:
            continue
        urls.append(c)

    for att in (msg.get('attachments') or []):
        u=(att or {}).get('url')
        if isinstance(u,str) and u:
            urls.append(clean_url(u))

    for emb in (msg.get('embeds') or []):
        u=(emb or {}).get('url')
        if isinstance(u,str) and u:
            urls.append(clean_url(u))

    seen=set()
    urls_unique=[]
    for u in urls:
        if not u or u in seen:
            continue
        seen.add(u)
        if is_system_url(u):
            continue
        urls_unique.append(u)

    ctx=normalize_auto_text(cleaned)
    ctx_b64=base64.b64encode(ctx.encode('utf-8')).decode('ascii') if ctx else ''
    for u in urls_unique:
        url_rows.append((ts,mid,channel_id,u,ctx_b64))

    memos=extract_memos(cleaned)
    for memo in memos:
        b64=base64.b64encode(memo.encode('utf-8')).decode('ascii')
        memo_rows.append((ts,mid,channel_id,b64))

url_rows.sort(key=lambda x:(x[0],x[1]))
memo_rows.sort(key=lambda x:(x[0],x[1]))

with open(out_urls,'a',encoding='utf-8') as f:
    for row in url_rows:
        f.write('\t'.join(row) + '\n')

with open(out_memos,'a',encoding='utf-8') as f:
    for row in memo_rows:
        f.write('\t'.join(row) + '\n')

print(json.dumps({
    "ok":True,
    "read_count":len(msgs),
    "user_count":user_count,
    "url_count":len(url_rows),
    "memo_count":len(memo_rows),
    "max_id":str(max_i) if max_i else ""
}, ensure_ascii=False))
PY
)"

  rm -f "$read_file"

  if [[ "$(echo "$parse_summary" | jq -r '.ok // false')" != "true" ]]; then
    echo "WARN: parse failed for channel ${channel_id}: $parse_summary" >&2
    continue
  fi

  read_count="$(echo "$parse_summary" | jq -r '.read_count // 0')"
  user_count="$(echo "$parse_summary" | jq -r '.user_count // 0')"
  url_count="$(echo "$parse_summary" | jq -r '.url_count // 0')"
  memo_count="$(echo "$parse_summary" | jq -r '.memo_count // 0')"
  max_id="$(echo "$parse_summary" | jq -r '.max_id // empty')"

  TOTAL_READ=$((TOTAL_READ + read_count))
  TOTAL_USER=$((TOTAL_USER + user_count))
  TOTAL_URL=$((TOTAL_URL + url_count))
  TOTAL_MEMO=$((TOTAL_MEMO + memo_count))

  if [[ -n "$max_id" ]]; then
    printf '%s\t%s\n' "$channel_id" "$max_id" >> "$TMP_LAST_IDS"
  fi
done < "$TMP_CHANNELS"

if [[ -s "$TMP_URLS" ]]; then
  sort -t $'\t' -k1,1 -k2,2 "$TMP_URLS" -o "$TMP_URLS"
fi
if [[ -s "$TMP_MEMOS" ]]; then
  sort -t $'\t' -k1,1 -k2,2 "$TMP_MEMOS" -o "$TMP_MEMOS"
fi

echo "brain-discord-autopull: scanned ${TOTAL_READ} msg(s), user ${TOTAL_USER}, url ${TOTAL_URL}, memo ${TOTAL_MEMO}"

URL_NUM=0
PROCESSED_URL_NUM=0
SKIPPED_GROUPED=0
PREV_KEY=""
while IFS=$'\t' read -r TS MSG_ID CHANNEL_ID URL CONTEXT_B64; do
  [[ -z "${URL:-}" ]] && continue
  URL_NUM=$((URL_NUM + 1))

  key="${CHANNEL_ID}:${MSG_ID}"
  if [[ "$key" == "$PREV_KEY" ]]; then
    SKIPPED_GROUPED=$((SKIPPED_GROUPED + 1))
    echo "[GROUPED] Skip extra URL from same Discord message: $URL"
    continue
  fi
  PREV_KEY="$key"

  PROCESSED_URL_NUM=$((PROCESSED_URL_NUM + 1))
  TITLE="$(echo "$URL" | sed -E 's|^https?://([^/]+).*|\1|' | sed 's/^www\.//')"

  if $DRY_RUN; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[DRY-RUN][DISCORD_URL] Entry #$PROCESSED_URL_NUM (raw #$URL_NUM)"
    echo "  URL:     $URL"
    echo "  Title:   $TITLE"
    echo "  Time:    $TS"
    echo "  Channel: $CHANNEL_ID"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  else
    echo "[URL $PROCESSED_URL_NUM] Processing: $URL"
    SUMMARY_TEXT="Auto-captured from Discord"
    if [[ -n "${CONTEXT_B64:-}" ]]; then
      DECODED_CTX="$(python3 - <<'PY' "$CONTEXT_B64"
import base64,sys
s=sys.argv[1] if len(sys.argv)>1 else ''
try:
    t=base64.b64decode(s).decode('utf-8','ignore').strip()
except Exception:
    t=''
print(t[:220])
PY
)"
      if [[ -n "$DECODED_CTX" ]]; then
        SUMMARY_TEXT="$DECODED_CTX"
      fi
    fi
    "$SCRIPT_DIR/brain-link-ingest.sh" \
      --url "$URL" \
      --title "$TITLE" \
      --summary "$SUMMARY_TEXT" \
      --my-opinion "자동 수집 항목 (후속 검토 필요)" || true
    send_discord_ack "$CHANNEL_ID" "✅ 링크 수집 완료 | ${URL:0:36}"
  fi
done < "$TMP_URLS"

echo "brain-discord-autopull: processed $PROCESSED_URL_NUM grouped url(s), skipped $SKIPPED_GROUPED extra url(s)"

MEMO_NUM=0
while IFS=$'\t' read -r TS MSG_ID CHANNEL_ID MEMO_B64; do
  [[ -z "${MEMO_B64:-}" ]] && continue
  MEMO="$(printf '%s' "$MEMO_B64" | base64 -d 2>/dev/null || true)"
  [[ -z "${MEMO:-}" ]] && continue
  MEMO_NUM=$((MEMO_NUM + 1))

  TITLE="$(python3 - <<'PY' "$MEMO"
import sys
t=sys.argv[1].strip()
if not t:
    print("Discord Memo")
else:
    first=t.splitlines()[0].strip()
    print(first[:60] if first else "Discord Memo")
PY
)"

  if [[ "$MEMO" =~ ^#[Tt][Oo][Dd][Oo]([[:space:]]|$) ]]; then
    echo "[TODO $MEMO_NUM/$TOTAL_MEMO] Routing: $MEMO"
    run_auto_learn learn --source-ts "$TS" --explicit-raw "$MEMO"
    route_and_ack "todo" "$MEMO" "$TS" "$MEMO" "tagged_todo" "$TITLE" "$CHANNEL_ID" || true
  elif [[ "$MEMO" =~ ^#([Ii][Dd][Ee][Aa]|[Dd][Ee][Cc][Ii][Ss][Ii][Oo][Nn]|[Tt][Rr][Aa][Dd][Ee]|[Ss][Yy][Ss])([[:space:]]|$) ]]; then
    echo "[TAG $MEMO_NUM/$TOTAL_MEMO] Routing: $MEMO"
    run_auto_learn learn --source-ts "$TS" --explicit-raw "$MEMO"
    route_and_ack "tag" "$MEMO" "$TS" "$MEMO" "tagged_route" "$TITLE" "$CHANNEL_ID" || true
  elif [[ "$MEMO" =~ ^#[Aa][Uu][Tt][Oo]([[:space:]]|$) ]]; then
    AUTO_RAW="$(echo "$MEMO" | sed -E 's/^#[Aa][Uu][Tt][Oo][[:space:]]+//')"
    CLASSIFIED_JSON="$(classify_auto_message "$AUTO_RAW")"
    if [[ "$(echo "$CLASSIFIED_JSON" | jq -r '.ok // false')" == "true" ]]; then
      ROUTE_TYPE="$(echo "$CLASSIFIED_JSON" | jq -r '.route_type')"
      ROUTED_RAW="$(echo "$CLASSIFIED_JSON" | jq -r '.routed_raw')"
      REASON="$(echo "$CLASSIFIED_JSON" | jq -r '.reason')"
      PRED_LABEL="$(echo "$CLASSIFIED_JSON" | jq -r '.tag // empty')"
      if [[ "$ROUTE_TYPE" == "todo" ]]; then
        PRED_LABEL="todo"
      fi
      run_auto_learn record --source-ts "$TS" --raw "$AUTO_RAW" --pred-label "$PRED_LABEL"
      echo "[AUTO $MEMO_NUM/$TOTAL_MEMO] Classified -> ${ROUTE_TYPE}: ${ROUTED_RAW}"
      route_and_ack "$ROUTE_TYPE" "$ROUTED_RAW" "$TS" "$AUTO_RAW" "auto:${REASON}" "$TITLE" "$CHANNEL_ID" || true
    else
      ERR="$(echo "$CLASSIFIED_JSON" | jq -r '.error // "classify_failed"')"
      echo "SKIP: auto classify skipped ($ERR)"
      if ! $DRY_RUN; then
        fallback_note_ingest "$TITLE" "$AUTO_RAW"
        send_discord_ack "$CHANNEL_ID" "✅ 메모 수집 완료"
      fi
    fi
  else
    if $DRY_RUN; then
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "[DRY-RUN][DISCORD_MEMO] Entry #$MEMO_NUM"
      echo "  Title:   $TITLE"
      echo "  Memo:    $MEMO"
      echo "  Time:    $TS"
      echo "  Channel: $CHANNEL_ID"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    else
      echo "[MEMO $MEMO_NUM/$TOTAL_MEMO] Processing: $TITLE"
      fallback_note_ingest "$TITLE" "$MEMO"
      send_discord_ack "$CHANNEL_ID" "✅ 메모 수집 완료"
    fi
  fi
done < "$TMP_MEMOS"

save_checkpoint

echo "HEARTBEAT_OK"
