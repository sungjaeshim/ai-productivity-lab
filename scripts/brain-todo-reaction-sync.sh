#!/usr/bin/env bash
# brain-todo-reaction-sync.sh
# Sync Discord #today reaction status (✅/🔄/🚫) to Todoist task status.
#
# Source message format expected (from brain-todo-route.sh):
# ✅ #todo 라우팅 완료
# - task: ...
# - project: queue|active|waiting|inbox
# - todoist_id: ...
# - event_id: todo-...
#
# Usage:
#   brain-todo-reaction-sync.sh [--channel-id ID] [--limit N] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
set +u
source "${SCRIPT_DIR}/env-loader.sh" 2>/dev/null || true
set -u

CHANNEL_ID=""
LIMIT="${BRAIN_TODO_REACTION_SYNC_LIMIT:-80}"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel-id) CHANNEL_ID="${2:-}"; shift 2 ;;
    --limit) LIMIT="${2:-80}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help)
      cat <<USAGE
Usage: $(basename "$0") [--channel-id ID] [--limit N] [--dry-run]
USAGE
      exit 0
      ;;
    *)
      # Backward compatible: first positional as channel id
      if [[ -z "$CHANNEL_ID" ]]; then
        CHANNEL_ID="$1"
        shift
      else
        echo "Unknown arg: $1" >&2
        exit 1
      fi
      ;;
  esac
done

CHANNEL_ID="${CHANNEL_ID:-${DISCORD_TODAY:-${BRAIN_OPS_CHANNEL_ID:-1478250773228814357}}}"
STATE_FILE="${WORKSPACE_DIR}/memory/second-brain/.todo-reaction-sync-state.json"
TMP_JSON="$(mktemp)"
TMP_ACTIONS="$(mktemp)"
trap 'rm -f "$TMP_JSON" "$TMP_ACTIONS"' EXIT

mkdir -p "$(dirname "$STATE_FILE")"
if [[ ! -f "$STATE_FILE" ]]; then
  printf '{"messages":{},"updated_at":null}\n' > "$STATE_FILE"
fi

if ! openclaw message read --channel discord --target "$CHANNEL_ID" --limit "$LIMIT" --json > "$TMP_JSON" 2>/dev/null; then
  echo "todo-reaction-sync: failed to read discord channel ${CHANNEL_ID}" >&2
  exit 1
fi

python3 - <<'PY' "$TMP_JSON" "$STATE_FILE" "$TMP_ACTIONS"
import json,re,sys,datetime
read_path,state_path,actions_path=sys.argv[1:4]

try:
    payload=json.load(open(read_path,'r',encoding='utf-8'))
except Exception:
    print('PARSE_ERROR')
    sys.exit(0)

msgs=((payload.get('payload') or {}).get('messages') or [])

try:
    state=json.load(open(state_path,'r',encoding='utf-8'))
except Exception:
    state={"messages":{}}

if not isinstance(state,dict):
    state={"messages":{}}
if not isinstance(state.get('messages'),dict):
    state['messages']={}

TODO_HEADER='✅ #todo 라우팅 완료'

# status precedence if multiple exist on same message
PRIO=[('🚫','BLOCKED'),('✅','DONE'),('🔄','DOING')]

actions=[]
for m in msgs:
    content=str(m.get('content') or '')
    if TODO_HEADER not in content:
        continue

    author=(m.get('author') or {})
    if not bool(author.get('bot')):
        continue

    mid=str(m.get('id') or '').strip()
    if not mid:
        continue

    task=''
    event_id=''
    project=''
    todoist_id=''

    for line in content.splitlines():
        s=line.strip()
        if s.startswith('- task:'):
            task=s.replace('- task:','',1).strip()
        elif s.startswith('- event_id:'):
            event_id=s.replace('- event_id:','',1).strip()
        elif s.startswith('- project:'):
            project=s.replace('- project:','',1).strip().lower()
        elif s.startswith('- todoist_id:'):
            todoist_id=s.replace('- todoist_id:','',1).strip()

    if not event_id:
        continue

    reacts=(m.get('reactions') or [])
    counts={'✅':0,'🔄':0,'🚫':0}
    for r in reacts:
        emoji=(r.get('emoji') or {}).get('name')
        try:
            c=int(r.get('count') or 0)
        except Exception:
            c=0
        if emoji in counts:
            counts[emoji]=max(counts[emoji],c)

    chosen=''
    status=''
    for emoji,st in PRIO:
        if counts.get(emoji,0) > 0:
            chosen=emoji
            status=st
            break

    if not status:
        continue

    signature=f"✅:{counts['✅']}|🔄:{counts['🔄']}|🚫:{counts['🚫']}"
    prev=(state['messages'].get(mid) or {})
    if prev.get('signature') == signature and prev.get('status') == status:
        continue

    actions.append({
        'message_id':mid,
        'event_id':event_id,
        'task':task,
        'project':project,
        'todoist_id':todoist_id,
        'emoji':chosen,
        'status':status,
        'signature':signature,
        'timestamp':str(m.get('timestampUtc') or m.get('timestamp') or '')
    })

# write actions
with open(actions_path,'w',encoding='utf-8') as f:
    for a in actions:
        f.write(json.dumps(a,ensure_ascii=False)+'\n')

print(f"ACTIONS:{len(actions)}")
PY

APPLIED=0
SKIPPED=0
FAILED=0

if [[ ! -s "$TMP_ACTIONS" ]]; then
  echo "todo-reaction-sync: no status reaction changes"
  exit 0
fi

while IFS= read -r line; do
  [[ -z "$line" ]] && continue

  MESSAGE_ID="$(echo "$line" | jq -r '.message_id')"
  EVENT_ID="$(echo "$line" | jq -r '.event_id')"
  TASK="$(echo "$line" | jq -r '.task // ""')"
  PROJECT="$(echo "$line" | jq -r '.project // "active"')"
  STATUS="$(echo "$line" | jq -r '.status')"
  EMOJI="$(echo "$line" | jq -r '.emoji')"
  SIGNATURE="$(echo "$line" | jq -r '.signature')"

  [[ -z "$EVENT_ID" || -z "$STATUS" ]] && { SKIPPED=$((SKIPPED+1)); continue; }

  CMD=("${SCRIPT_DIR}/brain-todoist-sync.sh" --item-id "$EVENT_ID" --status "$STATUS" --title "${TASK:-$EVENT_ID}" --project "$PROJECT")
  if [[ "$STATUS" == "BLOCKED" ]]; then
    CMD+=(--reason "Discord reaction ${EMOJI} from #today")
  fi
  if $DRY_RUN; then
    CMD+=(--dry-run)
  fi

  if "${CMD[@]}" >/tmp/brain-todo-reaction-sync.out 2>/tmp/brain-todo-reaction-sync.err; then
    APPLIED=$((APPLIED+1))

    python3 - <<'PY' "$STATE_FILE" "$MESSAGE_ID" "$STATUS" "$SIGNATURE" "$EVENT_ID"
import json,sys,datetime
p,mid,status,sig,eid=sys.argv[1:6]
try:
    st=json.load(open(p,'r',encoding='utf-8'))
except Exception:
    st={"messages":{}}
if not isinstance(st,dict):
    st={"messages":{}}
if not isinstance(st.get('messages'),dict):
    st['messages']={}
st['messages'][mid]={
    'status':status,
    'signature':sig,
    'event_id':eid,
    'synced_at':datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
}
st['updated_at']=datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
with open(p,'w',encoding='utf-8') as f:
    json.dump(st,f,ensure_ascii=False,indent=2)
PY

    echo "SYNCED: ${EVENT_ID} -> ${STATUS} (${EMOJI})"
  else
    FAILED=$((FAILED+1))
    echo "FAILED: ${EVENT_ID} -> ${STATUS}" >&2
    cat /tmp/brain-todo-reaction-sync.err >&2 || true
  fi
done < "$TMP_ACTIONS"

echo "todo-reaction-sync: applied=${APPLIED} skipped=${SKIPPED} failed=${FAILED}"
