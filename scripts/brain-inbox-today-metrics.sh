#!/usr/bin/env bash
# brain-inbox-today-metrics.sh
# 3일 기준 inbox->today->(reaction) 전환 지표를 계산해 보고
set -euo pipefail

WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TODO_REGISTRY="${WORKSPACE_DIR}/memory/second-brain/.todo-router-registry.jsonl"
INBOX_CHANNEL="${BRAIN_INBOX_CHANNEL_ID:-${DISCORD_INBOX:-1478250668052713647}}"
TODAY_CHANNEL="${BRAIN_OPS_CHANNEL_ID:-${DISCORD_TODAY:-1478250773228814357}}"
WINDOW_DAYS="${1:-3}"

TMP_INBOX_JSON="$(mktemp)"
TMP_TODAY_JSON="$(mktemp)"
trap 'rm -f "$TMP_INBOX_JSON" "$TMP_TODAY_JSON"' EXIT

# 1) inbox 링크 총량 (최근 N일)
openclaw message read --channel discord --target "$INBOX_CHANNEL" --limit 500 --json > "$TMP_INBOX_JSON"

# 2) today 메시지 최근 스냅샷 (reactions 포함)
openclaw message read --channel discord --target "$TODAY_CHANNEL" --limit 500 --json > "$TMP_TODAY_JSON"

python3 - <<'PY' "$TMP_INBOX_JSON" "$TMP_TODAY_JSON" "$TODO_REGISTRY" "$WINDOW_DAYS"
import json,sys,datetime,re
from pathlib import Path

inbox_path,today_path,todo_registry,window_days=sys.argv[1:5]
window_days=int(window_days)
now=datetime.datetime.now(datetime.timezone.utc)
cut=now-datetime.timedelta(days=window_days)

def parse_dt(s):
    if not s: return None
    return datetime.datetime.fromisoformat(s.replace('Z','+00:00'))

inbox_root=json.load(open(inbox_path,'r',encoding='utf-8'))
inbox_msgs=((inbox_root.get('payload') or {}).get('messages') or [])

inbox_links=0
for m in inbox_msgs:
    dt=parse_dt(m.get('timestamp') or m.get('timestampUtc'))
    if not dt or dt < cut: continue
    c=m.get('content') or ''
    if '📥 **New Link**' in c:
        inbox_links += 1

promoted=0
if Path(todo_registry).exists():
    with open(todo_registry,'r',encoding='utf-8') as f:
        for line in f:
            line=line.strip()
            if not line: continue
            try:
                j=json.loads(line)
            except Exception:
                continue
            dt=parse_dt(j.get('created_at'))
            if not dt or dt < cut: continue
            content=(j.get('content') or '').strip()
            if content.startswith('[링크] '):
                promoted += 1

# reaction 기반 실행전환/잡음 근사
# 대상: "✅ #todo 라우팅 완료" + task가 [링크]
today_root=json.load(open(today_path,'r',encoding='utf-8'))
today_msgs=((today_root.get('payload') or {}).get('messages') or [])
link_todo_msgs=[]
for m in today_msgs:
    dt=parse_dt(m.get('timestamp') or m.get('timestampUtc'))
    if not dt or dt < cut: continue
    c=(m.get('content') or '')
    if c.startswith('✅ #todo 라우팅 완료') and '- task: [링크]' in c:
        link_todo_msgs.append(m)

done=0
blocked=0
for m in link_todo_msgs:
    for r in (m.get('reactions') or []):
        emo=((r.get('emoji') or {}).get('name') or '')
        if emo == '✅':
            done += int(r.get('count',0))
        if emo == '🚫':
            blocked += int(r.get('count',0))

promotion_rate = (promoted / inbox_links * 100.0) if inbox_links else 0.0
# 잡음률 근사: blocked / max(done+blocked,1)
denom=max(done+blocked,1)
noise_rate = (blocked / denom * 100.0) if (done+blocked)>0 else 0.0
# 실행전환 근사: done / promoted
exec_conv = (done / promoted * 100.0) if promoted else 0.0

print(f"📊 inbox→today 3일 리포트")
print(f"- inbox 링크: {inbox_links}")
print(f"- today 승격(링크): {promoted}")
print(f"- 승격률: {promotion_rate:.1f}%")
print(f"- 실행전환률(✅/승격): {exec_conv:.1f}%")
print(f"- 잡음률(🚫/(✅+🚫)): {noise_rate:.1f}%")
print(f"- 근거: reactions(done={done}, blocked={blocked})")
PY
