#!/usr/bin/env python3
import json
from pathlib import Path
from statistics import mean

p = Path('/root/.openclaw/workspace/.state/macd-shadow/runs.jsonl')
MIN_SAMPLES = 10

if not p.exists():
    print('NO_DATA')
    raise SystemExit(0)

rows = []
for line in p.read_text(encoding='utf-8').splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        rows.append(json.loads(line))
    except Exception:
        pass

if not rows:
    print('NO_DATA')
    raise SystemExit(0)

n = len(rows)
ok = sum(1 for r in rows if r.get('exit_code') == 0)
fmt = sum(1 for r in rows if r.get('format_ok') is True)
clean = sum(1 for r in rows if r.get('exit_code') == 0 and r.get('format_ok') is True)
dur = [r.get('duration_ms', 0) for r in rows if isinstance(r.get('duration_ms'), int)]
remaining = max(0, MIN_SAMPLES - n)
gate_ready = n >= MIN_SAMPLES and clean == n

recent_clean_streak = 0
for row in reversed(rows):
    if row.get('exit_code') == 0 and row.get('format_ok') is True:
        recent_clean_streak += 1
    else:
        break

last_bad = None
for row in reversed(rows):
    if row.get('exit_code') != 0 or row.get('format_ok') is not True:
        last_bad = {
            'ts_kst': row.get('ts_kst'),
            'exit_code': row.get('exit_code'),
            'format_ok': row.get('format_ok'),
            'signal_type': row.get('signal_type'),
        }
        break

if gate_ready:
    gate_reason = 'ready_for_split_review'
elif remaining > 0:
    gate_reason = 'need_more_samples'
else:
    gate_reason = 'detected_failures'

print(json.dumps({
    'samples': n,
    'clean_samples': clean,
    'success_rate_pct': round(ok / n * 100, 2),
    'format_ok_rate_pct': round(fmt / n * 100, 2),
    'avg_duration_ms': round(mean(dur), 1) if dur else None,
    'max_duration_ms': max(dur) if dur else None,
    'gate_min_samples': MIN_SAMPLES,
    'gate_remaining_samples': remaining,
    'gate_recent_clean_streak': recent_clean_streak,
    'gate_ready': gate_ready,
    'gate_reason': gate_reason,
    'last_bad': last_bad,
    'last': rows[-1],
}, ensure_ascii=False))
