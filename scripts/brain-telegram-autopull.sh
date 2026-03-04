#!/usr/bin/env bash
# brain-telegram-autopull.sh
# Telegram user messages에서 URL을 추출해 brain-link-ingest 파이프라인에 자동 투입
# Usage: brain-telegram-autopull.sh [--dry-run] [--init-now]

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
SESS_DIR="$HOME/.openclaw/agents/main/sessions"
CHECKPOINT_FILE="$WORKSPACE/memory/second-brain/.brain-autopull-checkpoint.json"
TMP_URLS="$(mktemp)"

# 기본 채널 ID (env로 override 가능)
export BRAIN_INBOX_CHANNEL_ID="${BRAIN_INBOX_CHANNEL_ID:-1477462557941039124}"
export BRAIN_OPS_CHANNEL_ID="${BRAIN_OPS_CHANNEL_ID:-1477462730435858674}"

mkdir -p "$(dirname "$CHECKPOINT_FILE")"

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

python3 - <<'PY' "$SESS_DIR" "$LAST_TS" "$TMP_URLS"
import os,sys,json,re,glob,datetime
sess_dir,last_ts,out=sys.argv[1:4]
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
]

def is_system_url(url):
    """Filter out system/internal/example URLs"""
    url_lower = url.lower()
    for pattern in SYSTEM_PATTERNS:
        if re.search(pattern, url_lower):
            return True
    return False

def parse_ts(s):
    try:
        return datetime.datetime.fromisoformat(s.replace('Z','+00:00'))
    except Exception:
        return datetime.datetime.fromtimestamp(0, tz=datetime.timezone.utc)

last=parse_ts(last_ts)
rows=[]
for p in glob.glob(os.path.join(sess_dir,'*.jsonl')):
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
                urls=url_re.findall(text)
                for u in urls:
                    # Filter out system URLs
                    if is_system_url(u):
                        continue
                    rows.append((ts.isoformat().replace('+00:00','Z'),u))
    except Exception:
        continue

# 중복 URL 제거(입력 순서 유지)
seen=set()
out_rows=[]
for ts,u in sorted(rows,key=lambda x:x[0]):
    if u in seen:
        continue
    seen.add(u)
    out_rows.append((ts,u))

with open(out,'w') as w:
    for ts,u in out_rows:
        w.write(f"{ts}\t{u}\n")
PY

COUNT=$(wc -l < "$TMP_URLS" | tr -d ' ')
echo "brain-autopull: found $COUNT new url(s) since $LAST_TS"

# Safety guard: max URLs per run to prevent flood
MAX_URLS_PER_RUN=50
if [[ "$COUNT" -gt "$MAX_URLS_PER_RUN" ]]; then
  echo "WARN: Too many URLs ($COUNT > $MAX_URLS_PER_RUN). Processing only first $MAX_URLS_PER_RUN"
  head -n "$MAX_URLS_PER_RUN" "$TMP_URLS" > "${TMP_URLS}.limited"
  mv "${TMP_URLS}.limited" "$TMP_URLS"
  COUNT="$MAX_URLS_PER_RUN"
fi

if [[ "$COUNT" -eq 0 ]]; then
  echo "brain-autopull: no new URLs to process"
  rm -f "$TMP_URLS"
  echo "HEARTBEAT_OK"
  exit 0
fi

# Process each URL individually with clear dry-run output
MAX_TS="$LAST_TS"
URL_NUM=0
while IFS=$'\t' read -r TS URL; do
  [[ -z "${URL:-}" ]] && continue
  MAX_TS="$TS"
  URL_NUM=$((URL_NUM + 1))
  TITLE="$(echo "$URL" | sed -E 's|^https?://([^/]+).*|\1|' | sed 's/^www\.//')"
  
  if $DRY_RUN; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[DRY-RUN] Entry #$URL_NUM of $COUNT"
    echo "  URL:    $URL"
    echo "  Title:  $TITLE"
    echo "  Time:   $TS"
    echo "  Action: Would call brain-link-ingest.sh"
    echo "          (will be INCOMPLETE - missing summary/my-opinion)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  else
    echo "[$URL_NUM/$COUNT] Processing: $URL"
    "$SCRIPT_DIR/brain-link-ingest.sh" --url "$URL" --title "$TITLE" --summary "Auto-captured from Telegram" || true
  fi
done < "$TMP_URLS"

if ! $DRY_RUN; then
  python3 - <<'PY' "$CHECKPOINT_FILE" "$MAX_TS"
import json,sys,datetime
p,ts=sys.argv[1],sys.argv[2]
obj={
  'last_ts': ts,
  'updated_at': datetime.datetime.utcnow().isoformat()+'Z'
}
with open(p,'w') as f:
  json.dump(obj,f,ensure_ascii=False,indent=2)
print(f"checkpoint updated: {ts}")
PY
fi

rm -f "$TMP_URLS"
echo "HEARTBEAT_OK"
