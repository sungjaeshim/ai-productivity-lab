#!/usr/bin/env bash
# brain-telegram-autopull.sh
# Telegram user messages에서 URL/메모를 추출해 brain ingest 파이프라인에 자동 투입
# Usage: brain-telegram-autopull.sh [--dry-run] [--init-now]

set -euo pipefail

# Load message guard
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/message-guard.sh" 2>/dev/null || true

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
set -u

SESS_DIR="$HOME/.openclaw/agents/main/sessions"
SESS_INDEX="$SESS_DIR/sessions.json"
CHECKPOINT_FILE="$WORKSPACE/memory/second-brain/.brain-autopull-checkpoint.json"
SECOND_BRAIN_DIR="${SECOND_BRAIN_DIR:-${WORKSPACE}/memory/second-brain}"
ROUTE_RETRY_QUEUE="${SECOND_BRAIN_DIR}/.pending-route-queue.jsonl"
ROUTE_RETRY_LOCK="${SECOND_BRAIN_DIR}/.pending-route-queue.lock"
STAGE0_DIR="${WORKSPACE}/feedback"
STAGE0_FILE="${STAGE0_DIR}/ralph-stage0-routing.jsonl"
STAGE0_LOCK_FILE="${STAGE0_DIR}/ralph-stage0-routing.lock"
ACK_TELEGRAM="${BRAIN_ROUTER_ACK_TELEGRAM:-false}"
ROUTE_RETRY_DELAY_SEC="${BRAIN_ROUTE_RETRY_DELAY_SEC:-300}"
AUTO_LEARN_ENABLED="${BRAIN_AUTO_LEARN_ENABLED:-true}"
AUTO_LEARN_SCRIPT="${SCRIPT_DIR}/brain-auto-route-learn.sh"
AUTO_KEYWORDS_FILE="${SECOND_BRAIN_DIR}/.auto-route-keywords.json"
TMP_URLS="$(mktemp)"
TMP_MEMOS="$(mktemp)"

# 기본 채널 ID (env로 override 가능)
export BRAIN_INBOX_CHANNEL_ID="${BRAIN_INBOX_CHANNEL_ID:-${DISCORD_INBOX:-1478250668052713647}}"
export BRAIN_OPS_CHANNEL_ID="${BRAIN_OPS_CHANNEL_ID:-${DISCORD_TODAY:-1478250773228814357}}"
export TELEGRAM_TARGET="${TELEGRAM_TARGET:-${TELEGRAM_CHAT_ID:-62403941}}"

mkdir -p "$(dirname "$CHECKPOINT_FILE")" "$SECOND_BRAIN_DIR" "$STAGE0_DIR"
touch "$STAGE0_FILE"

is_truthy() {
  local v
  v="$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')"
  [[ "$v" == "1" || "$v" == "true" || "$v" == "yes" || "$v" == "on" ]]
}

send_telegram_ack() {
  local msg="$1"
  if ! is_truthy "$ACK_TELEGRAM"; then
    return 0
  fi

  # Validate channel and target before sending
  if ! MESSAGE_GUARD_DRY_RUN="$DRY_RUN" validate_message_params --channel telegram --target "$TELEGRAM_TARGET"; then
    echo "[WARN] Telegram ack skipped: validation failed" >&2
    return 1
  fi

  if $DRY_RUN; then
    echo "[DRY-RUN][ACK] ${msg}"
    return 0
  fi
  openclaw message send --channel telegram --target "$TELEGRAM_TARGET" --message "$msg" --silent >/dev/null 2>&1 || true
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
    --arg worker "brain-telegram-autopull" \
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
    --summary "Auto-captured memo from Telegram" \
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

# Strip common transport/noise wrappers from chat exports
text=re.sub(r'^\[media attached:[^\]]*\]\s*','',text,flags=re.IGNORECASE)
text=re.sub(r'\bconversation info \(untrusted metadata\):.*$','',text,flags=re.IGNORECASE)
text=re.sub(r'\bsender \(untrusted metadata\):.*$','',text,flags=re.IGNORECASE)
text=' '.join(text.split()).strip()
if not text:
    print(json.dumps({"ok":False,"error":"noise_only"}))
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
todo_kw=["할일","todo","체크","확인","정리","검토","수정","업데이트","작성","보내","공유","리마인드","준비","미팅","전화","follow up","follow-up"]
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
    # If learned signals exist but below hard threshold, prefer highest non-zero score.
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
    echo "[DRY-RUN][ROUTE] ${route_label} ($route_type)"
    echo "  Raw:    $original_raw"
    echo "  Routed: $routed_raw"
    echo "  Time:   $source_ts"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    return 0
  fi

  if out="$("$route_script" --raw "$routed_raw" --source-ts "$source_ts" 2>&1)"; then
    echo "$out"
    send_telegram_ack "✅ 자동처리 ${route_label} | ${original_raw:0:28}"
    return 0
  fi

  echo "$out" >&2
  err_preview="$(echo "$out" | tail -n 2 | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-220)"
  queue_route_retry "$route_type" "$source_ts" "$original_raw" "$routed_raw" "$reason" "$err_preview"
  send_telegram_ack "⚠️ 자동처리 실패→재시도 ${route_label}"
  echo "WARN: route failed, queued retry, fallback to memo ingest" >&2
  fallback_note_ingest "$title" "$original_raw"
  return 0
}

if $INIT_NOW; then
  NOW_TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  if ! $DRY_RUN; then
    printf '{\n  "last_ts": "%s",\n  "updated_at": "%s"\n}\n' "$NOW_TS" "$NOW_TS" > "$CHECKPOINT_FILE"
  fi
  echo "checkpoint initialized to now: $NOW_TS"
  exit 0
fi

LAST_TS="1970-01-01T00:00:00Z"
if [[ -f "$CHECKPOINT_FILE" ]]; then
  LAST_TS="$(python3 - <<'PY' "$CHECKPOINT_FILE"
import json,sys
p=sys.argv[1]
try:
  d=json.load(open(p))
  print(d.get('last_ts','1970-01-01T00:00:00Z'))
except Exception:
  print('1970-01-01T00:00:00Z')
PY
)"
fi

python3 - <<'PY' "$SESS_DIR" "$SESS_INDEX" "$LAST_TS" "$TMP_URLS" "$TMP_MEMOS" "$TELEGRAM_TARGET"
import os,sys,json,re,glob,datetime,base64
sess_dir,sess_index,last_ts,out_urls,out_memos,target_chat=sys.argv[1:7]
url_re=re.compile(r'https?://[^\s)\]>"\']+')

# System/internal URL patterns to filter out
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

def is_system_url(url):
    """Filter out system/internal/example URLs"""
    url_lower = url.lower()
    for pattern in SYSTEM_PATTERNS:
        if re.search(pattern, url_lower):
            return True
    return False

def is_noise_text(text):
    noise_markers = [
        '[cron:',
        'Distill this session to memory/',
        '[System Message]',
        'System: [',
        'Exec completed',
    ]
    return any(marker in text for marker in noise_markers)

def strip_fenced_blocks(text):
    # Remove metadata/replied-message code blocks to avoid URL pollution.
    return re.sub(r'```[\s\S]*?```', '', text)

def clean_url(url):
    u = url.split('\\n', 1)[0].split('\n', 1)[0]
    u = u.rstrip('`.,;:!?"\'')
    return u

memo_prefix_re = re.compile(r'^(?:#?(?:memo|note)|메모)\s*[:：-]\s*(.+)$', re.IGNORECASE)
memo_hash_re = re.compile(r'^#((?:memo|note|메모|todo|idea|decision|trade|sys)\b.*)$', re.IGNORECASE)
auto_skip_exact = {
    "ok","okay","yes","no","응","네","ㅇㅋ","완료","보냄","전송","확인","테스트",
    "done","sent","checked","확인함","테스트완료"
}
auto_skip_contains = [
    "conversation info (untrusted metadata)",
    "sender (untrusted metadata)",
    "replied message (untrusted",
    "```json",
    "\"message_id\"",
    "\"sender_id\"",
]

def normalize_auto_text(text):
    lines = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        # Skip url-only lines; URL pipeline handles them separately.
        if re.fullmatch(r'https?://\S+', line):
            continue
        lines.append(line)
    if not lines:
        return ''
    normalized = re.sub(r'\s+', ' ', ' '.join(lines)).strip()
    return normalized

def extract_memos(text):
    memos = []
    found_explicit = False
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        m = memo_prefix_re.match(line)
        if m:
            memo = m.group(1).strip()
            if memo:
                memos.append(memo)
                found_explicit = True
            continue
        m = memo_hash_re.match(line)
        if m:
            tagged = f"#{m.group(1).strip()}"
            lowered = tagged.lower()
            if lowered.startswith("#memo ") or lowered.startswith("#note ") or tagged.startswith("#메모 "):
                memo = tagged.split(" ", 1)[1].strip()
                if memo:
                    memos.append(memo)
                    found_explicit = True
            else:
                memos.append(tagged)
                found_explicit = True
    if found_explicit:
        return memos

    auto_text = normalize_auto_text(text)
    if not auto_text:
        return []
    if len(auto_text) < 5:
        return []
    auto_text_lc = auto_text.lower()
    if auto_text_lc in auto_skip_exact:
        return []
    if any(marker in auto_text_lc for marker in auto_skip_contains):
        return []
    return [f"#auto {auto_text}"]

def parse_ts(s):
    try:
        return datetime.datetime.fromisoformat(s.replace('Z','+00:00'))
    except Exception:
        return datetime.datetime.fromtimestamp(0, tz=datetime.timezone.utc)

last=parse_ts(last_ts)
url_rows=[]
memo_rows=[]
# Prefer the actual Telegram direct session transcript for the current target user.
transcripts = []
if os.path.isfile(sess_index):
    try:
        data = json.load(open(sess_index, 'r', encoding='utf-8'))
        key = f"agent:main:telegram:direct:{target_chat}"
        sess = data.get(key) or {}
        sid = sess.get('sessionId')
        if sid:
            p = os.path.join(sess_dir, f'{sid}.jsonl')
            if os.path.isfile(p):
                transcripts.append(p)
    except Exception:
        pass

if not transcripts:
    transcripts = glob.glob(os.path.join(sess_dir, '*.jsonl'))

for p in transcripts:
    try:
        with open(p,'r',errors='ignore') as f:
            for line in f:
                line=line.strip()
                if not line:
                    continue
                try:
                    obj=json.loads(line)
                except Exception:
                    continue
                if obj.get('type')!='message':
                    continue
                msg=obj.get('message',{})
                if msg.get('role')!='user':
                    continue
                ts=parse_ts(obj.get('timestamp','1970-01-01T00:00:00Z'))
                if ts<=last:
                    continue
                content=msg.get('content',[])
                texts=[]
                if isinstance(content,str):
                    texts=[content]
                elif isinstance(content,list):
                    for c in content:
                        if isinstance(c,dict) and c.get('type')=='text':
                            texts.append(c.get('text',''))
                text='\n'.join(texts)
                cleaned_text = strip_fenced_blocks(text)
                if is_noise_text(cleaned_text):
                    continue
                urls=url_re.findall(cleaned_text)
                for u in urls:
                    u = clean_url(u)
                    if not u:
                        continue
                    # Filter out system URLs
                    if is_system_url(u):
                        continue
                    url_rows.append((ts.isoformat().replace('+00:00','Z'),u))
                for memo in extract_memos(cleaned_text):
                    memo_rows.append((ts.isoformat().replace('+00:00','Z'),memo))
    except Exception:
        continue

# 중복 URL 제거(입력 순서 유지)
seen=set()
out_url_rows=[]
for ts,u in sorted(url_rows,key=lambda x:x[0]):
    if u in seen:
        continue
    seen.add(u)
    out_url_rows.append((ts,u))

seen_memo=set()
out_memo_rows=[]
for ts,memo in sorted(memo_rows,key=lambda x:x[0]):
    if memo in seen_memo:
        continue
    seen_memo.add(memo)
    out_memo_rows.append((ts,memo))

with open(out_urls,'w') as w:
    for ts,u in out_url_rows:
        w.write(f"{ts}\t{u}\n")
with open(out_memos,'w') as w:
    for ts,memo in out_memo_rows:
        b64 = base64.b64encode(memo.encode('utf-8')).decode('ascii')
        w.write(f"{ts}\t{b64}\n")
PY

COUNT_URL=$(wc -l < "$TMP_URLS" | tr -d ' ')
COUNT_MEMO=$(wc -l < "$TMP_MEMOS" | tr -d ' ')
echo "brain-autopull: found $COUNT_URL new url(s), $COUNT_MEMO new memo(s) since $LAST_TS"

# Safety guard: max URLs per run to prevent flood
MAX_URLS_PER_RUN=50
if [[ "$COUNT_URL" -gt "$MAX_URLS_PER_RUN" ]]; then
  echo "WARN: Too many URLs ($COUNT_URL > $MAX_URLS_PER_RUN). Processing only first $MAX_URLS_PER_RUN"
  head -n "$MAX_URLS_PER_RUN" "$TMP_URLS" > "${TMP_URLS}.limited"
  mv "${TMP_URLS}.limited" "$TMP_URLS"
  COUNT_URL="$MAX_URLS_PER_RUN"
fi

# Safety guard: max memos per run to prevent flood
MAX_MEMOS_PER_RUN=30
if [[ "$COUNT_MEMO" -gt "$MAX_MEMOS_PER_RUN" ]]; then
  echo "WARN: Too many memos ($COUNT_MEMO > $MAX_MEMOS_PER_RUN). Processing only first $MAX_MEMOS_PER_RUN"
  head -n "$MAX_MEMOS_PER_RUN" "$TMP_MEMOS" > "${TMP_MEMOS}.limited"
  mv "${TMP_MEMOS}.limited" "$TMP_MEMOS"
  COUNT_MEMO="$MAX_MEMOS_PER_RUN"
fi

if [[ "$COUNT_URL" -eq 0 && "$COUNT_MEMO" -eq 0 ]]; then
  if ! $DRY_RUN; then
    NOW_TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    python3 - <<'PY' "$CHECKPOINT_FILE" "$NOW_TS"
import json,sys,datetime
p,ts=sys.argv[1],sys.argv[2]
obj={
  'last_ts': ts,
  'updated_at': datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
}
with open(p,'w') as f:
  json.dump(obj,f,ensure_ascii=False,indent=2)
print(f"checkpoint updated: {ts}")
PY
  fi
  echo "brain-autopull: no new URLs/memos to process"
  rm -f "$TMP_URLS" "$TMP_MEMOS"
  echo "HEARTBEAT_OK"
  exit 0
fi

# Process URLs with per-message grouping (same TS => one ingest) to avoid duplicate notifications
MAX_TS="$LAST_TS"
URL_NUM=0
PROCESSED_URL_NUM=0
SKIPPED_GROUPED=0
PREV_TS=""
while IFS=$'\t' read -r TS URL; do
  [[ -z "${URL:-}" ]] && continue
  MAX_TS="$TS"
  URL_NUM=$((URL_NUM + 1))

  # A-mode: one notification per source message
  if [[ -n "$PREV_TS" && "$TS" == "$PREV_TS" ]]; then
    SKIPPED_GROUPED=$((SKIPPED_GROUPED + 1))
    echo "[GROUPED] Skip extra URL from same message: $URL"
    continue
  fi
  PREV_TS="$TS"

  PROCESSED_URL_NUM=$((PROCESSED_URL_NUM + 1))
  TITLE="$(echo "$URL" | sed -E 's|^https?://([^/]+).*|\1|' | sed 's/^www\.//')"

  if $DRY_RUN; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[DRY-RUN][URL] Entry #$PROCESSED_URL_NUM (raw #$URL_NUM of $COUNT_URL)"
    echo "  URL:    $URL"
    echo "  Title:  $TITLE"
    echo "  Time:   $TS"
    echo "  Action: Would call brain-link-ingest.sh (grouped per message)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  else
    echo "[URL $PROCESSED_URL_NUM] Processing: $URL"
    "$SCRIPT_DIR/brain-link-ingest.sh" \
      --url "$URL" \
      --title "$TITLE" \
      --summary "Auto-captured from Telegram" \
      --my-opinion "자동 수집 항목 (후속 검토 필요)" || true
  fi
done < "$TMP_URLS"

echo "brain-autopull: processed $PROCESSED_URL_NUM grouped url(s), skipped $SKIPPED_GROUPED extra url(s) from same-message groups"

MEMO_NUM=0
while IFS=$'\t' read -r TS MEMO_B64; do
  [[ -z "${MEMO_B64:-}" ]] && continue
  MAX_TS="$TS"
  MEMO="$(printf '%s' "$MEMO_B64" | base64 -d 2>/dev/null || true)"
  [[ -z "${MEMO:-}" ]] && continue
  MEMO_NUM=$((MEMO_NUM + 1))
  TITLE="$(python3 - <<'PY' "$MEMO"
import sys
t=sys.argv[1].strip()
if not t:
    print("Telegram Memo")
else:
    first=t.splitlines()[0].strip()
    print(first[:60] if first else "Telegram Memo")
PY
)"

  if [[ "$MEMO" =~ ^#[Tt][Oo][Dd][Oo]([[:space:]]|$) ]]; then
    echo "[TODO $MEMO_NUM/$COUNT_MEMO] Routing: $MEMO"
    run_auto_learn learn --source-ts "$TS" --explicit-raw "$MEMO"
    route_and_ack "todo" "$MEMO" "$TS" "$MEMO" "tagged_todo" "$TITLE" || true
  elif [[ "$MEMO" =~ ^#([Ii][Dd][Ee][Aa]|[Dd][Ee][Cc][Ii][Ss][Ii][Oo][Nn]|[Tt][Rr][Aa][Dd][Ee]|[Ss][Yy][Ss])([[:space:]]|$) ]]; then
    echo "[TAG $MEMO_NUM/$COUNT_MEMO] Routing: $MEMO"
    run_auto_learn learn --source-ts "$TS" --explicit-raw "$MEMO"
    route_and_ack "tag" "$MEMO" "$TS" "$MEMO" "tagged_route" "$TITLE" || true
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
      echo "[AUTO $MEMO_NUM/$COUNT_MEMO] Classified -> ${ROUTE_TYPE}: ${ROUTED_RAW}"
      route_and_ack "$ROUTE_TYPE" "$ROUTED_RAW" "$TS" "$AUTO_RAW" "auto:${REASON}" "$TITLE" || true
    else
      ERR="$(echo "$CLASSIFIED_JSON" | jq -r '.error // "classify_failed"')"
      echo "SKIP: auto classify skipped ($ERR)"
      if ! $DRY_RUN; then
        fallback_note_ingest "$TITLE" "$AUTO_RAW"
      fi
    fi
  else
    if $DRY_RUN; then
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "[DRY-RUN][MEMO] Entry #$MEMO_NUM of $COUNT_MEMO"
      echo "  Title:  $TITLE"
      echo "  Memo:   $MEMO"
      echo "  Time:   $TS"
      echo "  Action: Would call brain-note-ingest.sh"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    else
      echo "[MEMO $MEMO_NUM/$COUNT_MEMO] Processing: $TITLE"
      fallback_note_ingest "$TITLE" "$MEMO"
    fi
  fi
done < "$TMP_MEMOS"

if ! $DRY_RUN; then
  python3 - <<'PY' "$CHECKPOINT_FILE" "$MAX_TS"
import json,sys,datetime
p,ts=sys.argv[1],sys.argv[2]
obj={
  'last_ts': ts,
  'updated_at': datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
}
with open(p,'w') as f:
  json.dump(obj,f,ensure_ascii=False,indent=2)
print(f"checkpoint updated: {ts}")
PY
fi

rm -f "$TMP_URLS" "$TMP_MEMOS"
echo "HEARTBEAT_OK"
