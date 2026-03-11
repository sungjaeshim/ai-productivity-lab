#!/usr/bin/env python3
import json
import re
from pathlib import Path

ROOT = Path('/root/.openclaw/workspace')
STATE_DIR = ROOT / '.state'
MIN_DAYS = 7
PASS_RESTORE_READINESS = 80


def load_history():
    history_path = STATE_DIR / 'nightly-maintenance-history.jsonl'
    rows = []
    if history_path.exists():
        for line in history_path.read_text(encoding='utf-8').splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except Exception:
                continue
    return rows


def load_from_log():
    log_path = STATE_DIR / 'nightly-maintenance.log'
    if not log_path.exists():
        return []

    rows = []
    pattern = re.compile(
        r'^\[(?P<ts>[^\]]+)\] status=(?P<status>\w+) '
        r'restore_readiness=(?P<restore>\d+) '
        r'memory_quality=(?P<quality>[0-9.]+) sqlite=(?P<sqlite>\w+)'
    )

    for line in log_path.read_text(encoding='utf-8').splitlines():
        m = pattern.match(line.strip())
        if not m:
            continue
        rows.append({
            'timestamp': m.group('ts'),
            'status': m.group('status'),
            'restore_readiness_score': int(m.group('restore')),
            'memory_quality_score': float(m.group('quality')),
            'recall_status': 'PASS' if int(m.group('restore')) >= PASS_RESTORE_READINESS else 'WARN',
            'sqlite': {
                'status': m.group('sqlite'),
            },
        })
    return rows


def latest_per_day(rows):
    by_date = {}
    for row in rows:
        ts = row.get('timestamp') or ''
        date_key = ts[:10]
        if not date_key:
            continue
        prev = by_date.get(date_key)
        if not prev or ts >= (prev.get('timestamp') or ''):
            by_date[date_key] = row
    return [by_date[key] for key in sorted(by_date)]


def is_pass(row):
    sqlite_status = ((row.get('sqlite') or {}).get('status'))
    restore = row.get('restore_readiness_score', 0)
    status = row.get('status')
    return status == 'PASS' and sqlite_status == 'PASS' and restore >= PASS_RESTORE_READINESS


def main():
    rows = load_history()
    source = 'history'
    if not rows:
        rows = load_from_log()
        source = 'log_fallback'

    rows = latest_per_day(rows)
    recent = rows[-MIN_DAYS:]

    if not recent:
        print('NO_DATA')
        return

    n = len(recent)
    pass_count = sum(1 for row in recent if is_pass(row))
    gate_ready = n >= MIN_DAYS and pass_count == n

    if n < MIN_DAYS:
        gate_reason = 'need_more_days'
    elif pass_count != n:
        gate_reason = 'pass_failures'
    else:
        gate_reason = 'ready_for_memory_ops_split'

    last_bad = None
    for row in reversed(recent):
        if not is_pass(row):
            last_bad = {
                'timestamp': row.get('timestamp'),
                'status': row.get('status'),
                'restore_readiness_score': row.get('restore_readiness_score'),
                'sqlite_status': (row.get('sqlite') or {}).get('status'),
                'recall_status': row.get('recall_status'),
            }
            break

    print(json.dumps({
        'sample_type': 'latest_distinct_nightly_runs',
        'history_source': source,
        'samples': n,
        'gate_min_days': MIN_DAYS,
        'gate_remaining_days': max(0, MIN_DAYS - n),
        'pass_count': pass_count,
        'pass_rate_pct': round(pass_count / n * 100, 2),
        'pass_restore_readiness_threshold': PASS_RESTORE_READINESS,
        'gate_ready': gate_ready,
        'gate_reason': gate_reason,
        'last_bad': last_bad,
        'last': recent[-1],
        'dates': [(row.get('timestamp') or '')[:10] for row in recent],
    }, ensure_ascii=False))


if __name__ == '__main__':
    main()
