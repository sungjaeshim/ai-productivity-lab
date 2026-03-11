#!/usr/bin/env bash
# brain-todo-route.sh - Route #todo messages to Todoist + Discord #today
# Usage: brain-todo-route.sh --raw "#todo task | today | p1" [--source-ts ISO] [--dry-run]
# Extra tokens supported: project(queue|active|waiting|inbox), status(TODO|DOING|DONE|BLOCKED)

set -euo pipefail

set +u
source "$(dirname "$0")/env-loader.sh" 2>/dev/null || true
source "$(dirname "$0")/lib/message-guard.sh" 2>/dev/null || true
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECOND_BRAIN_DIR="${SECOND_BRAIN_DIR:-${WORKSPACE_DIR}/memory/second-brain}"
REGISTRY_FILE="${SECOND_BRAIN_DIR}/.todo-router-registry.jsonl"
TODAY_CHANNEL="${DISCORD_TODAY:-${BRAIN_OPS_CHANNEL_ID:-1478250773228814357}}"
CREDENTIALS_DIR="$HOME/.openclaw/credentials"
TODOIST_TOKEN_FILE="$CREDENTIALS_DIR/todoist"
TODOIST_PROJECTS_FILE="$CREDENTIALS_DIR/todoist-projects.json"

DRY_RUN=false
RAW=""
SOURCE_TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

usage() {
  cat <<USAGE
Usage: $(basename "$0") --raw "#todo task | due | p1" [--source-ts ISO] [--dry-run]
USAGE
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

PARSED_JSON="$(python3 - <<'PY' "$RAW" "$SOURCE_TS"
import sys,re,hashlib,datetime,json
raw=sys.argv[1].strip()
source_ts=sys.argv[2].strip()

if not re.match(r'^\s*#todo\b', raw, re.IGNORECASE):
    print(json.dumps({"ok":False,"error":"not_todo"}, ensure_ascii=False))
    raise SystemExit(0)

body=re.sub(r'^\s*#todo\b','',raw,flags=re.IGNORECASE).strip()
metadata_detected=bool(re.search(r'\[media attached:|conversation info \(untrusted metadata\)|sender \(untrusted metadata\):', body, flags=re.IGNORECASE))
# Sanitize forwarded metadata/noise that can break parser or exceed API limits
body=re.sub(r'\[media attached:[^\]]+\]','',body,flags=re.IGNORECASE)
body=re.sub(r'to send an image back, prefer the message tool.*?keep caption in the text body\.?','',body,flags=re.IGNORECASE|re.DOTALL)
# If wrapped metadata exists, keep only the actual sender text tail
m=re.search(r'sender \(untrusted metadata\):\s*(.*)$', body, flags=re.IGNORECASE|re.DOTALL)
if m:
    body=m.group(1).strip()
else:
    body=re.sub(r'conversation info \(untrusted metadata\):.*','',body,flags=re.IGNORECASE|re.DOTALL)
body=re.sub(r'\s+',' ',body).strip()
parts=[p.strip() for p in body.split('|')]
parts=[p for p in parts if p!='']

if not parts:
    print(json.dumps({"ok":False,"error":"missing_content"}, ensure_ascii=False))
    raise SystemExit(0)

content=parts[0]
due_expr=''
prio='p2'
project_override=''
status_hint=''

PROJECT_TOKENS={'queue','active','waiting','inbox'}
STATUS_TOKENS={
    'todo':'TODO','대기':'TODO',
    'doing':'DOING','진행':'DOING',
    'done':'DONE','완료':'DONE',
    'blocked':'BLOCKED','보류':'BLOCKED','막힘':'BLOCKED'
}

def is_project_token(token:str)->bool:
    t=(token or '').strip().lower()
    return t in PROJECT_TOKENS

def is_status_token(token:str)->bool:
    t=(token or '').strip().lower()
    return t in STATUS_TOKENS

def is_due_token(token:str)->bool:
    if metadata_detected:
        return False
    t=(token or '').strip().lower()
    if not t:
        return False
    if is_project_token(t) or is_status_token(t) or re.fullmatch(r'p[1-4]', t, re.IGNORECASE):
        return False
    if t in ('today','tomorrow','오늘','내일'):
        return True
    if re.fullmatch(r'\d{4}-\d{2}-\d{2}', t):
        return True
    # Allow short natural-language due strings only (Todoist limit + noise guard)
    if len(t) <= 40 and not any(x in t for x in ['[media attached', 'conversation info', 'sender (untrusted metadata)', 'http://', 'https://']):
        return True
    return False

# Parse all pipe-separated tokens robustly:
# - priority tokens => prio
# - project tokens => explicit project override
# - status tokens => status hint (for project inference)
# - valid due token => due_expr (first one wins)
# - everything else folds back into content to avoid malformed due_string errors
for idx, token in enumerate(parts[1:], start=1):
    t=token.strip()
    tl=t.lower()
    if re.fullmatch(r'p[1-4]', t, re.IGNORECASE):
        prio=tl
        continue
    if is_project_token(t):
        project_override=tl
        continue
    if is_status_token(t):
        status_hint=STATUS_TOKENS[tl]
        continue
    if (not due_expr) and is_due_token(t):
        due_expr=t
        continue
    content=f"{content} | {t}" if content else t

prio_map={'p1':4,'p2':3,'p3':2,'p4':1}
todoist_priority=prio_map.get(prio,3)

due_date=''
due_string=''
if due_expr:
    d=due_expr.strip().lower()
    today=datetime.date.today()
    if d in ('today','오늘'):
        due_date=today.isoformat()
    elif d in ('tomorrow','내일'):
        due_date=(today+datetime.timedelta(days=1)).isoformat()
    elif re.fullmatch(r'\d{4}-\d{2}-\d{2}', d):
        # Validate YYYY-MM-DD format
        try:
            datetime.date.fromisoformat(d)
            due_date=d
        except ValueError:
            # Invalid date, fall through to due_string
            due_string=due_expr.strip()[:150]
    else:
        # Extra guard for Todoist due_string length limit(<=150)
        # Also strip common noise patterns
        due_string=due_expr.strip()[:150]
        # Remove any remaining suspicious patterns that might cause API rejection
        for noise in ['http://', 'https://', 'www.', '.com', '[media', 'conversation', 'untrusted']:
            if noise in due_string.lower():
                due_string = due_string.replace(noise, '')[:150]

# Hard cap content length to avoid API edge-cases and noisy payloads
if len(content) > 400:
    content = content[:397].rstrip() + '...'

if project_override:
    project=project_override
elif status_hint=='DOING':
    project='active'
elif status_hint=='BLOCKED':
    project='waiting'
elif status_hint=='TODO':
    project='queue'
elif status_hint=='DONE':
    project='active'
else:
    project='active' if (prio=='p1' or (due_expr.strip().lower() in ('today','오늘'))) else 'queue'

fingerprint=f"{source_ts}|{raw}"
event_id=f"todo-{hashlib.sha1(fingerprint.encode('utf-8')).hexdigest()[:16]}"

print(json.dumps({
    "ok":True,
    "content":content,
    "due_expr":due_expr,
    "due_date":due_date,
    "due_string":due_string,
    "priority_tag":prio,
    "priority":todoist_priority,
    "project":project,
    "project_override":project_override,
    "status_hint":status_hint,
    "event_id":event_id,
    "source_ts":source_ts
}, ensure_ascii=False))
PY
)"

if [[ "$(echo "$PARSED_JSON" | jq -r '.ok')" != "true" ]]; then
  echo "SKIP: not a valid #todo format ($(echo "$PARSED_JSON" | jq -r '.error'))"
  exit 0
fi

EVENT_ID="$(echo "$PARSED_JSON" | jq -r '.event_id')"
CONTENT="$(echo "$PARSED_JSON" | jq -r '.content')"
PROJECT_NAME="$(echo "$PARSED_JSON" | jq -r '.project')"
PRIORITY_TAG="$(echo "$PARSED_JSON" | jq -r '.priority_tag')"
PRIORITY="$(echo "$PARSED_JSON" | jq -r '.priority')"
DUE_DATE="$(echo "$PARSED_JSON" | jq -r '.due_date')"
DUE_STRING="$(echo "$PARSED_JSON" | jq -r '.due_string')"

if [[ -f "$REGISTRY_FILE" ]] && rg -q "\"event_id\":\"$EVENT_ID\"" "$REGISTRY_FILE"; then
  echo "SKIP: duplicate #todo event ($EVENT_ID)"
  exit 0
fi

if [[ ! -f "$TODOIST_TOKEN_FILE" ]]; then
  echo "ERROR: Todoist token not found: $TODOIST_TOKEN_FILE" >&2
  exit 3
fi
if [[ ! -f "$TODOIST_PROJECTS_FILE" ]]; then
  echo "ERROR: Todoist projects file not found: $TODOIST_PROJECTS_FILE" >&2
  exit 3
fi

TODOIST_TOKEN="$(cat "$TODOIST_TOKEN_FILE")"
PROJECT_ID="$(jq -r --arg p "$PROJECT_NAME" '.[$p] // empty' "$TODOIST_PROJECTS_FILE")"
if [[ -z "$PROJECT_ID" ]]; then
  echo "ERROR: Todoist project id not found for '$PROJECT_NAME'" >&2
  exit 4
fi

TASK_PAYLOAD="$(jq -n \
  --arg content "$CONTENT" \
  --arg project_id "$PROJECT_ID" \
  --arg description "event_id:$EVENT_ID | source:telegram" \
  --argjson priority "$PRIORITY" \
  '{content:$content,project_id:$project_id,priority:$priority,description:$description}')"

if [[ -n "$DUE_DATE" ]]; then
  TASK_PAYLOAD="$(echo "$TASK_PAYLOAD" | jq --arg due_date "$DUE_DATE" '. + {due_date:$due_date}')"
elif [[ -n "$DUE_STRING" ]]; then
  TASK_PAYLOAD="$(echo "$TASK_PAYLOAD" | jq --arg due_string "$DUE_STRING" '. + {due_string:$due_string}')"
fi

if $DRY_RUN; then
  echo "[DRY-RUN] #todo parsed: $CONTENT | $(echo "$PARSED_JSON" | jq -r '.due_expr // empty') | $PRIORITY_TAG"
  echo "[DRY-RUN] Would create Todoist task in project '$PROJECT_NAME' ($PROJECT_ID)"
  echo "[DRY-RUN] Payload: $TASK_PAYLOAD"
  echo "[DRY-RUN] Would notify Discord #today channel: $TODAY_CHANNEL"
  exit 0
fi

RESP="$(curl -s -w "\n%{http_code}" -X POST "https://api.todoist.com/api/v1/tasks" \
  -H "Authorization: Bearer $TODOIST_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$TASK_PAYLOAD")"
HTTP_CODE="$(echo "$RESP" | tail -1)"
BODY="$(echo "$RESP" | head -n -1)"

if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "201" ]]; then
  # Fallback: if due field is rejected (length/format), retry once without due
  if echo "$BODY" | rg -q '"argument":"due"|due_string|due_date|String should have at most 150 char'; then
    echo "WARN: Todoist due field rejected (DUE_DATE='${DUE_DATE}', DUE_STRING='${DUE_STRING}'); retrying without due" >&2
    FALLBACK_PAYLOAD="$(echo "$TASK_PAYLOAD" | jq 'del(.due_date, .due_string)')"
    RESP="$(curl -s -w "\n%{http_code}" -X POST "https://api.todoist.com/api/v1/tasks" \
      -H "Authorization: Bearer $TODOIST_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$FALLBACK_PAYLOAD")"
    HTTP_CODE="$(echo "$RESP" | tail -1)"
    BODY="$(echo "$RESP" | head -n -1)"
  fi
fi

if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "201" ]]; then
  echo "ERROR: Todoist API failed (HTTP $HTTP_CODE)" >&2
  echo "$BODY" >&2
  exit 4
fi

TODOIST_ID="$(echo "$BODY" | jq -r '.id // empty')"
TASK_URL="$(echo "$BODY" | jq -r '.url // empty')"

DISCORD_MSG="✅ #todo 라우팅 완료\n- task: $CONTENT\n- due: ${DUE_DATE:-${DUE_STRING:-none}}\n- priority: $PRIORITY_TAG\n- project: $PROJECT_NAME\n- todoist_id: ${TODOIST_ID:-unknown}\n- event_id: $EVENT_ID"
if validate_message_params --channel discord --target "$TODAY_CHANNEL"; then
  openclaw message send --channel discord --target "$TODAY_CHANNEL" --message "$DISCORD_MSG" --silent 2>/dev/null || true
else
  echo "[WARN] Discord send skipped: validation failed for #todo" >&2
fi

mkdir -p "$SECOND_BRAIN_DIR"
jq -cn \
  --arg event_id "$EVENT_ID" \
  --arg source_ts "$SOURCE_TS" \
  --arg content "$CONTENT" \
  --arg due "${DUE_DATE:-$DUE_STRING}" \
  --arg priority_tag "$PRIORITY_TAG" \
  --arg project "$PROJECT_NAME" \
  --arg todoist_id "$TODOIST_ID" \
  --arg task_url "$TASK_URL" \
  --arg created_at "$(date -Iseconds)" \
  '{event_id:$event_id,source_ts:$source_ts,content:$content,due:$due,priority_tag:$priority_tag,project:$project,todoist_id:$todoist_id,task_url:$task_url,created_at:$created_at}' \
  >> "$REGISTRY_FILE"

echo "OK: #todo routed (event_id: $EVENT_ID, todoist_id: ${TODOIST_ID:-unknown})"
