#!/usr/bin/env bash
set -euo pipefail

LOG_JSONL="/root/.openclaw/workspace/.state/discrawl-sync-runs.jsonl"

python3 - <<'PY' "$LOG_JSONL"
import json, sys, datetime as dt, re
path = sys.argv[1]
now = dt.datetime.now(dt.timezone.utc)
cutoff = now - dt.timedelta(hours=24)

rows = []
try:
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            try:
                ts = dt.datetime.fromisoformat(r.get('start'))
                if ts.tzinfo is None:
                    ts = ts.replace(tzinfo=dt.timezone.utc)
            except Exception:
                continue
            if ts >= cutoff:
                rows.append(r)
except FileNotFoundError:
    print('discrawl 24h report: no log file yet')
    raise SystemExit(0)

if not rows:
    print('discrawl 24h report: no runs in last 24h')
    raise SystemExit(0)

n = len(rows)
fail = sum(1 for r in rows if int(r.get('exit_code', 1)) != 0)
ok = n - fail
avg_dur = sum(int(r.get('duration_sec', 0)) for r in rows) / n

rss_vals = []
msg_vals = []
members_vals = []
for r in rows:
    p = r.get('preview', '')
    m = re.search(r'MAXRSS_KB=(\d+)', p)
    if m:
        rss_vals.append(int(m.group(1)))
    m2 = re.search(r'messages=(\d+)', p)
    if m2:
        msg_vals.append(int(m2.group(1)))
    m3 = re.search(r'members=(\d+)', p)
    if m3:
        members_vals.append(int(m3.group(1)))

max_rss = max(rss_vals) if rss_vals else None
last = rows[-1]

print('📊 discrawl 24h sync report')
print(f'- runs: {n} | ok: {ok} | fail: {fail} | success_rate: {ok/n*100:.1f}%')
print(f'- avg_duration_sec: {avg_dur:.1f}')
if max_rss is not None:
    print(f'- max_rss_mb: {max_rss/1024:.1f}')
if msg_vals:
    print(f'- last_messages_processed: {msg_vals[-1]}')
if members_vals:
    print(f'- last_members_processed: {members_vals[-1]}')
print(f"- last_run: {last.get('start')} exit={last.get('exit_code')}")
PY
