#!/usr/bin/env bash
# Re-evaluate recent links and promote candidates to today+Todoist once.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LINKS_FILE="${SECOND_BRAIN_DIR:-$WORKSPACE_DIR/memory/second-brain}/links.md"
ANALYZER="$SCRIPT_DIR/brain-content-analyze.sh"
TODO_ROUTE="$SCRIPT_DIR/brain-todo-route.sh"

DAYS="3"
THRESHOLD="65"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days) DAYS="${2:-3}"; shift 2 ;;
    --threshold) THRESHOLD="${2:-65}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ ! -f "$LINKS_FILE" ]]; then
  echo "ERROR: links.md not found: $LINKS_FILE" >&2
  exit 1
fi

export BRAIN_OPS_SCORE_THRESHOLD="$THRESHOLD"

python3 - <<'PY' "$LINKS_FILE" "$DAYS" "$ANALYZER" "$TODO_ROUTE" "$DRY_RUN"
import sys,re,datetime,subprocess,json
from pathlib import Path

links_file,days,analyzer,todo_route,dry_run=sys.argv[1:6]
days=int(days)
dry_run=(dry_run.lower()=="true")

text=Path(links_file).read_text(encoding='utf-8',errors='ignore')
blocks=re.split(r'(?m)^##\s+', text)
now=datetime.date.today()
cut=now-datetime.timedelta(days=days)

processed=0
promoted=0
skipped=0

for b in blocks[1:]:
    lines=b.splitlines()
    if not lines:
        continue
    header=lines[0].strip()
    title=header
    m=re.search(r'\]\s*(.+)$', header)
    if m:
        title=m.group(1).strip()

    url=''; added=''; summary=''; opinion=''; status=''
    for ln in lines:
        if ln.startswith('- URL: '): url=ln[len('- URL: '):].strip()
        elif ln.startswith('- Added: '): added=ln[len('- Added: '):].strip()
        elif ln.startswith('- Summary: '): summary=ln[len('- Summary: '):].strip()
        elif ln.startswith('- My Opinion: '): opinion=ln[len('- My Opinion: '):].strip()
        elif ln.startswith('- Status: '): status=ln[len('- Status: '):].strip()

    if not url or not added:
        continue
    try:
        ad=datetime.date.fromisoformat(added)
    except Exception:
        continue
    if ad < cut:
        continue

    processed += 1

    analyze_text=(summary+" "+opinion).strip()
    out=subprocess.check_output([
        'bash',analyzer,'--mode','link','--title',title,'--url',url,'--text',analyze_text
    ], text=True)
    a=json.loads(out)

    score=int(a.get('ops_score',0) or 0)
    should=bool(a.get('should_ops',False))
    action=(a.get('our_apply') or a.get('next_action') or '링크 검토 후 실행여부 결정').replace('|','-').strip()
    if len(action) > 120:
        action=action[:117]+'...'

    if should:
        raw=f"#todo [링크] {title} — {action} | queue | p2"
        source_ts=f"{added}T00:00:00Z"
        cmd=['bash',todo_route,'--raw',raw,'--source-ts',source_ts]
        if dry_run:
            cmd.append('--dry-run')
        try:
            subprocess.check_output(cmd,text=True,stderr=subprocess.STDOUT)
            promoted += 1
            print(f"PROMOTE score={score} title={title[:50]} url={url}")
        except subprocess.CalledProcessError as e:
            skipped += 1
            print(f"SKIP_FAIL score={score} title={title[:50]} err={(e.output or '').splitlines()[-1] if e.output else 'unknown'}")
    else:
        skipped += 1

print(f"SUMMARY processed={processed} promoted={promoted} skipped={skipped} days={days}")
PY
