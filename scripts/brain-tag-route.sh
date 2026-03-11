#!/usr/bin/env bash
# brain-tag-route.sh - Route #idea/#decision/#trade/#sys/#ac2 to SoT targets
# Usage: brain-tag-route.sh --raw "#idea ..." [--source-ts ISO] [--dry-run]

set -euo pipefail

set +u
source "$(dirname "$0")/env-loader.sh" 2>/dev/null || true
source "$(dirname "$0")/lib/message-guard.sh" 2>/dev/null || true
source "$(dirname "$0")/lib/quality-gate.sh" 2>/dev/null || true
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECOND_BRAIN_DIR="${SECOND_BRAIN_DIR:-${WORKSPACE_DIR}/memory/second-brain}"
REGISTRY_FILE="${SECOND_BRAIN_DIR}/.tag-router-registry.jsonl"
NOTION_API_KEY_FILE="${NOTION_API_KEY_FILE:-$HOME/.config/notion/api_key}"

DISCORD_DECISION_CHANNEL="${DISCORD_DECISION_LOG:-1477310567906672750}"
DISCORD_TRADE_CHANNEL="${DISCORD_PROJ_TRADING_NQ:-${DISCORD_TRADING_NQ:-1477315856533819514}}"
DISCORD_SYS_CHANNEL="${DISCORD_SYSTEM_HEALTH:-1477310512680276080}"

SYS_MEM_WARN="${SYS_MEM_WARN:-80}"
SYS_DISK_WARN="${SYS_DISK_WARN:-85}"
SYS_LOAD_WARN="${SYS_LOAD_WARN:-2.0}"
BRAIN_NOTION_LOG_GUARD="${BRAIN_NOTION_LOG_GUARD:-true}"

DRY_RUN=false
RAW=""
SOURCE_TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

usage() {
  cat <<USAGE
Usage: $(basename "$0") --raw "#idea text | meta1 | meta2" [--source-ts ISO] [--dry-run]
USAGE
}

is_truthy() {
  local v
  v="$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')"
  [[ "$v" == "1" || "$v" == "true" || "$v" == "yes" || "$v" == "on" ]]
}

notion_guard_reason() {
  local text="$1"
  local low
  low="$(echo "$text" | tr '[:upper:]' '[:lower:]')"

  if echo "$low" | grep -Eq 'conversation info \(untrusted metadata\)|sender \(untrusted metadata\):|openclaw runtime context \(internal\)|\[media attached:|internal task completion event|queued messages while agent was busy|source: cron session_key:|source: subagent session_key:'; then
    echo "metadata_noise"
    return 0
  fi

  if [[ "${#text}" -gt 280 ]] && echo "$low" | grep -Eq 'runtime|session_key|timestamp|untrusted metadata'; then
    echo "log_like_long_text"
    return 0
  fi

  echo ""
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --raw) RAW="${2:-}"; shift 2 ;;
    --source-ts) SOURCE_TS="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$RAW" ]]; then
  echo "ERROR: --raw required" >&2
  exit 1
fi

# 사전 필터: 시스템/메타데이터 노이즈는 파싱 전에 스킵
RAW_LOWER="$(echo "$RAW" | tr '[:upper:]' '[:lower:]')"
if echo "$RAW_LOWER" | grep -Eq 'a new session was started|execute your session startup|/new or /reset|conversation info \(untrusted metadata\)|sender \(untrusted metadata\)|source: cron|source: subagent|internal task completion|queued messages while agent was busy'; then
  echo "SKIP: pre-filter metadata_noise (before parse)"
  exit 0
fi

PARSED_JSON="$(python3 - <<'PY' "$RAW" "$SOURCE_TS"
import sys,re,hashlib,json
raw=sys.argv[1].strip()
source_ts=sys.argv[2].strip()

m = re.match(r'^\s*#(idea|decision|trade|sys|ac2)\b\s*(.*)$', raw, re.IGNORECASE)
if not m:
    print(json.dumps({"ok":False,"error":"not_supported_tag"}, ensure_ascii=False))
    raise SystemExit(0)

tag = m.group(1).lower()
body = m.group(2).strip()
parts = [p.strip() for p in body.split('|')]
parts = [p for p in parts if p != '']

content = parts[0] if parts else ''
field2 = parts[1] if len(parts) > 1 else ''
field3 = parts[2] if len(parts) > 2 else ''

if not content:
    print(json.dumps({"ok":False,"error":"missing_content","tag":tag}, ensure_ascii=False))
    raise SystemExit(0)

fingerprint=f"{source_ts}|{raw}"
event_id=f"{tag}-{hashlib.sha1(fingerprint.encode('utf-8')).hexdigest()[:16]}"

print(json.dumps({
    "ok": True,
    "tag": tag,
    "content": content,
    "field2": field2,
    "field3": field3,
    "event_id": event_id,
    "source_ts": source_ts,
    "raw": raw
}, ensure_ascii=False))
PY
)"

if [[ "$(echo "$PARSED_JSON" | jq -r '.ok')" != "true" ]]; then
  echo "SKIP: unsupported input ($(echo "$PARSED_JSON" | jq -r '.error'))"
  exit 0
fi

TAG="$(echo "$PARSED_JSON" | jq -r '.tag')"
CONTENT="$(echo "$PARSED_JSON" | jq -r '.content')"
FIELD2="$(echo "$PARSED_JSON" | jq -r '.field2')"
FIELD3="$(echo "$PARSED_JSON" | jq -r '.field3')"
EVENT_ID="$(echo "$PARSED_JSON" | jq -r '.event_id')"
RAW_TEXT="$(echo "$PARSED_JSON" | jq -r '.raw')"

SHOULD_MIRROR_AC2=false
if [[ "$TAG" == "idea" ]]; then
  if echo "$RAW_TEXT" | tr '[:upper:]' '[:lower:]' | grep -Eq '(^|[^a-z0-9])ac2([^a-z0-9]|$)|세컨드브레인|second[ -]?brain|제2의[[:space:]]*뇌'; then
    SHOULD_MIRROR_AC2=true
  fi
fi

# 품질 게이트: 지표 수집 (raw)
quality_record_metric "raw" "$TAG" "tag-route" 2>/dev/null || true

# 품질 게이트: SKIP 체크
NOTION_SKIP_REASON=""
if is_truthy "$BRAIN_NOTION_LOG_GUARD"; then
  NOTION_SKIP_REASON="$(notion_guard_reason "$RAW_TEXT")"
fi

# 품질 게이트: 새로운 SKIP 규칙 적용
QUALITY_SKIP=""
if command -v quality_skip_reason >/dev/null 2>&1; then
  QUALITY_SKIP="$(quality_skip_reason "$RAW_TEXT")"
fi

# SKIP 결정 (기존 + 품질 게이트)
if [[ -n "$NOTION_SKIP_REASON" ]]; then
  echo "SKIP: Notion guard blocked (${NOTION_SKIP_REASON}) for #${TAG} (event_id=${EVENT_ID})"
  exit 0
fi

if [[ -n "$QUALITY_SKIP" ]]; then
  echo "SKIP: Quality gate blocked (${QUALITY_SKIP}) for #${TAG} (event_id=${EVENT_ID})"
  exit 0
fi

# 중복 체크
if [[ -f "$REGISTRY_FILE" ]] && rg -q "\"event_id\":\"$EVENT_ID\"" "$REGISTRY_FILE"; then
  echo "SKIP: duplicate tag event ($EVENT_ID)"
  exit 0
fi

# 품질 게이트: 통과 → kept 기록
quality_record_metric "kept" "$TAG" "tag-route" 2>/dev/null || true

NOTION_DB=""
DISCORD_CHANNEL=""
SB_FILE=""
MSG_PREFIX=""

case "$TAG" in
  idea)
    NOTION_DB="${NOTION_KNOWLEDGE_CARDS_DB:-}"
    SB_FILE="${SECOND_BRAIN_DIR}/ideas.md"
    MSG_PREFIX="💡 #idea"
    ;;
  decision)
    NOTION_DB="${NOTION_DECISION_LOG_DB:-}"
    DISCORD_CHANNEL="$DISCORD_DECISION_CHANNEL"
    SB_FILE="${SECOND_BRAIN_DIR}/decisions.md"
    MSG_PREFIX="📌 #decision"
    ;;
  trade)
    NOTION_DB="${NOTION_TRADE_JOURNAL_DB:-}"
    DISCORD_CHANNEL="$DISCORD_TRADE_CHANNEL"
    SB_FILE="${SECOND_BRAIN_DIR}/trades.md"
    MSG_PREFIX="📈 #trade"
    ;;
  sys)
    NOTION_DB=""
    DISCORD_CHANNEL="$DISCORD_SYS_CHANNEL"
    SB_FILE="${SECOND_BRAIN_DIR}/system-health.md"
    MSG_PREFIX="🛠️ #sys"
    ;;
  ac2)
    NOTION_DB="${NOTION_KNOWLEDGE_CARDS_DB:-}"
    SB_FILE="${SECOND_BRAIN_DIR}/ac2/13-inbox.md"
    MSG_PREFIX="🧠 #ac2"
    ;;
  *)
    echo "SKIP: unsupported tag $TAG"
    exit 0
    ;;
esac

SYS_SNAPSHOT=""
SYS_SEVERITY="info"
if [[ "$TAG" == "sys" ]]; then
  MEM_PCT=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')
  DISK_PCT=$(df / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
  LOAD1=$(awk '{print $1}' /proc/loadavg)
  UPTIME_STR=$(uptime -p 2>/dev/null || true)

  if (( MEM_PCT >= SYS_MEM_WARN )) || (( DISK_PCT >= SYS_DISK_WARN )) || awk -v l="$LOAD1" -v t="$SYS_LOAD_WARN" 'BEGIN{exit !(l>t)}'; then
    SYS_SEVERITY="warn"
  fi

  SYS_SNAPSHOT="mem=${MEM_PCT}% | disk=${DISK_PCT}% | load1=${LOAD1} | uptime=${UPTIME_STR}"
fi

NOW_LOCAL="$(date '+%Y-%m-%d %H:%M:%S')"
SB_ENTRY="## [${NOW_LOCAL}] #${TAG} ${CONTENT}
- event_id: ${EVENT_ID}
- source_ts: ${SOURCE_TS}
- field2: ${FIELD2:-none}
- field3: ${FIELD3:-none}
- raw: ${RAW_TEXT}
"
if [[ -n "$SYS_SNAPSHOT" ]]; then
  SB_ENTRY+="- snapshot: ${SYS_SNAPSHOT}
- severity: ${SYS_SEVERITY}
"
fi
SB_ENTRY+="
"

DISCORD_MSG_ID=""
if [[ -n "$DISCORD_CHANNEL" ]]; then
  DISCORD_MSG="${MSG_PREFIX} 라우팅\n- content: ${CONTENT}\n- field2: ${FIELD2:-none}\n- field3: ${FIELD3:-none}\n"
  if [[ -n "$SYS_SNAPSHOT" ]]; then
    DISCORD_MSG+="- snapshot: ${SYS_SNAPSHOT}\n- severity: ${SYS_SEVERITY}\n"
  fi
  DISCORD_MSG+="- event_id: ${EVENT_ID}"

  if $DRY_RUN; then
    echo "[DRY-RUN] Would send Discord to ${DISCORD_CHANNEL}: ${MSG_PREFIX}"
  else
    if validate_message_params --channel discord --target "$DISCORD_CHANNEL"; then
      if DISCORD_OUT=$(openclaw message send --channel discord --target "$DISCORD_CHANNEL" --message "$DISCORD_MSG" 2>&1); then
        echo "$DISCORD_OUT"
        DISCORD_MSG_ID="$(echo "$DISCORD_OUT" | sed -n 's/.*Message ID: \([0-9][0-9]*\).*/\1/p' | tail -1)"
      else
        echo "WARN: Discord send failed for #${TAG}" >&2
        echo "$DISCORD_OUT" >&2
      fi
    else
      echo "[WARN] Discord send skipped: validation failed for #${TAG}" >&2
    fi
  fi
fi

NOTION_PAGE_ID=""
if [[ -n "$NOTION_DB" ]]; then
  if [[ -n "$NOTION_SKIP_REASON" ]]; then
    echo "SKIP: Notion upsert blocked (${NOTION_SKIP_REASON}) for #${TAG} (event_id=${EVENT_ID})"
  elif $DRY_RUN; then
    echo "[DRY-RUN] Would upsert Notion DB ${NOTION_DB} for #${TAG} (event_id=${EVENT_ID})"
  else
    NOTION_RESULT="$(python3 - <<'PY' "$NOTION_DB" "$NOTION_API_KEY_FILE" "$TAG" "$CONTENT" "$FIELD2" "$FIELD3" "$EVENT_ID" "$SOURCE_TS"
import json,sys,os,urllib.request,urllib.error,datetime

db_id,key_file,tag,content,field2,field3,event_id,source_ts = sys.argv[1:9]

if not db_id:
    print(json.dumps({"ok":False,"skip":"no_db"}, ensure_ascii=False))
    raise SystemExit(0)
if not os.path.isfile(key_file):
    print(json.dumps({"ok":False,"skip":"no_key_file"}, ensure_ascii=False))
    raise SystemExit(0)

token=open(key_file,'r',encoding='utf-8').read().strip()
if not token:
    print(json.dumps({"ok":False,"skip":"empty_key"}, ensure_ascii=False))
    raise SystemExit(0)

headers={
    "Authorization": f"Bearer {token}",
    "Notion-Version": "2025-09-03",
    "Content-Type": "application/json",
}

def req(url, method="GET", payload=None):
    data = None
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode('utf-8')
    r = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(r, timeout=20) as resp:
        return json.loads(resp.read().decode('utf-8'))

try:
    db = req(f"https://api.notion.com/v1/databases/{db_id}")
except Exception as e:
    print(json.dumps({"ok":False,"error":"db_fetch_failed","detail":str(e)}, ensure_ascii=False))
    raise SystemExit(0)

# Notion 2025-09 API: database can point to one or more data_sources.
props = db.get("properties", {}) or {}
query_url = f"https://api.notion.com/v1/databases/{db_id}/query"
parent_obj = {"database_id": db_id}
source_type = "database"
source_id = db_id

if not props:
    ds_list = db.get("data_sources") or []
    if ds_list:
        ds_id = ds_list[0].get("id")
        if ds_id:
            try:
                ds = req(f"https://api.notion.com/v1/data_sources/{ds_id}")
                props = ds.get("properties", {}) or {}
                query_url = f"https://api.notion.com/v1/data_sources/{ds_id}/query"
                parent_obj = {"data_source_id": ds_id}
                source_type = "data_source"
                source_id = ds_id
            except Exception as e:
                print(json.dumps({"ok":False,"error":"data_source_fetch_failed","detail":str(e)}, ensure_ascii=False))
                raise SystemExit(0)

title_prop = None
for name, meta in props.items():
    if meta.get("type") == "title":
        title_prop = name
        break
if not title_prop:
    print(json.dumps({"ok":False,"error":"no_title_property","source_type":source_type,"source_id":source_id}, ensure_ascii=False))
    raise SystemExit(0)

def find_prop(names, ptype=None):
    lowered = {k.lower(): k for k in props.keys()}
    for n in names:
        key = lowered.get(n.lower())
        if key is None:
            continue
        if ptype and props[key].get("type") != ptype:
            continue
        return key
    return None

event_prop = find_prop(["Event_ID","event_id","Event Id"], "rich_text")
if event_prop:
    try:
        q = req(
            query_url,
            method="POST",
            payload={"page_size":1,"filter":{"property":event_prop,"rich_text":{"equals":event_id}}},
        )
        results = q.get("results", [])
        if results:
            page_id = results[0].get("id", "")
            print(json.dumps({"ok":True,"created":False,"page_id":page_id}, ensure_ascii=False))
            raise SystemExit(0)
    except SystemExit:
        raise
    except Exception:
        pass

properties = {
    title_prop: {"title":[{"text":{"content": content[:1800]}}]}
}

for cand, val in [
    (["Event_ID","event_id","Event Id"], event_id),
    (["Local_ID","local_id","Local Id"], event_id),
    (["Source_Ref","source_ref","Source Ref"], source_ts),
    (["Tag","tag"], tag),
    (["Meta_1","meta_1","Meta 1"], field2),
    (["Meta_2","meta_2","Meta 2"], field3),
]:
    if not val:
        continue
    p = find_prop(cand, "rich_text")
    if p:
        properties[p] = {"rich_text":[{"text":{"content": val[:1800]}}]}

updated_prop = find_prop(["Updated_At","updated_at","Updated At"], "date")
if updated_prop:
    properties[updated_prop] = {"date": {"start": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00","Z")}}

try:
    page = req(
        "https://api.notion.com/v1/pages",
        method="POST",
        payload={"parent":parent_obj,"properties":properties},
    )
    print(json.dumps({"ok":True,"created":True,"page_id":page.get("id",""),"url":page.get("url","")}, ensure_ascii=False))
except Exception as e:
    print(json.dumps({"ok":False,"error":"create_failed","detail":str(e)}, ensure_ascii=False))
PY
)"
    echo "Notion: $NOTION_RESULT"
    NOTION_PAGE_ID="$(echo "$NOTION_RESULT" | jq -r '.page_id // empty' 2>/dev/null || true)"
  fi
fi

if $DRY_RUN; then
  echo "[DRY-RUN] Would append second-brain file: $SB_FILE"
else
  mkdir -p "$SECOND_BRAIN_DIR"
  touch "$SB_FILE"
  printf '%s' "$SB_ENTRY" >> "$SB_FILE"
fi

if $SHOULD_MIRROR_AC2; then
  AC2_MIRROR_FILE="${SECOND_BRAIN_DIR}/ac2/13-inbox.md"
  AC2_MIRROR_ENTRY="## [${NOW_LOCAL}] #ac2 (auto-mirror from #idea) ${CONTENT}
- event_id: ${EVENT_ID}
- source_ts: ${SOURCE_TS}
- source_tag: idea
- field2: ${FIELD2:-none}
- field3: ${FIELD3:-none}
- raw: ${RAW_TEXT}

"

  if $DRY_RUN; then
    echo "[DRY-RUN] Would mirror #idea to AC2 file: $AC2_MIRROR_FILE"
  else
    mkdir -p "$(dirname "$AC2_MIRROR_FILE")"
    touch "$AC2_MIRROR_FILE"
    printf '%s' "$AC2_MIRROR_ENTRY" >> "$AC2_MIRROR_FILE"
  fi
fi

if $DRY_RUN; then
  echo "[DRY-RUN] Would register event in $REGISTRY_FILE"
  exit 0
fi

mkdir -p "$SECOND_BRAIN_DIR"
jq -cn \
  --arg event_id "$EVENT_ID" \
  --arg tag "$TAG" \
  --arg source_ts "$SOURCE_TS" \
  --arg content "$CONTENT" \
  --arg field2 "$FIELD2" \
  --arg field3 "$FIELD3" \
  --arg notion_page_id "$NOTION_PAGE_ID" \
  --arg discord_message_id "$DISCORD_MSG_ID" \
  --arg created_at "$(date -Iseconds)" \
  '{event_id:$event_id,tag:$tag,source_ts:$source_ts,content:$content,field2:$field2,field3:$field3,notion_page_id:$notion_page_id,discord_message_id:$discord_message_id,created_at:$created_at}' \
  >> "$REGISTRY_FILE"

# 품질 게이트: routed 기록
quality_record_metric "routed" "$TAG" "tag-route" 2>/dev/null || true

# 품질 게이트: PRINCIPLE 승격 체크 (#decision만 applied로 카운트)
if [[ "$TAG" == "decision" ]]; then
  PROMOTE_RESULT="$(quality_can_promote "$RAW_TEXT" "$TAG" 2>/dev/null || true)"
  if [[ "$PROMOTE_RESULT" =~ ^promote: ]]; then
    quality_record_metric "applied" "$TAG" "tag-route" 2>/dev/null || true
    echo "OK: #${TAG} routed & promoted to PRINCIPLE (event_id: ${EVENT_ID}, score: ${PROMOTE_RESULT#promote:})"
  else
    echo "OK: #${TAG} routed (kept as REFERENCE, event_id: ${EVENT_ID}, score: ${PROMOTE_RESULT#keep:})"
  fi
else
  echo "OK: #${TAG} routed (event_id: ${EVENT_ID})"
fi
