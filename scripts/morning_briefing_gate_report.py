#!/usr/bin/env python3
import json
from datetime import datetime
from pathlib import Path
import re

ROOT = Path('/root/.openclaw/workspace')
DATA_DIR = ROOT / 'data'
STATE_DIR = ROOT / '.state'
MIN_SAMPLES = 5
DATE_RE = re.compile(r'morning-context-(\d{4}-\d{2}-\d{2})\.json$')


def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except Exception:
        return None


def load_runs():
    runs_path = STATE_DIR / 'morning-briefing-runs.jsonl'
    runs_by_date = {}
    if not runs_path.exists():
        return runs_by_date

    for line in runs_path.read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except Exception:
            continue
        date_kst = row.get('date_kst')
        if not date_kst:
            continue
        runs_by_date[date_kst] = row
    return runs_by_date


def source_exists(source_name: str):
    if not source_name:
        return False
    return (DATA_DIR / source_name).exists()


def summarize_sample(path: Path, payload: dict, runs_by_date: dict):
    m = DATE_RE.search(path.name)
    if not m:
        return None
    date_kst = m.group(1)

    try:
        weekday_by_name = datetime.strptime(date_kst, '%Y-%m-%d').weekday() < 5
    except ValueError:
        weekday_by_name = False

    is_weekday = bool(payload.get('is_weekday', weekday_by_name))
    if not is_weekday:
        return None

    weather_status = (payload.get('weather') or {}).get('status')
    tasks = payload.get('tasks') or {}
    tasks_status = tasks.get('status')
    task_count = tasks.get('total_count')
    source_name = payload.get('intelligence_source')
    source_ok = source_exists(source_name)
    collector_ok = (
        weather_status in {'ok', 'partial'}
        and tasks_status == 'ok'
        and isinstance(task_count, int)
        and task_count >= 1
        and source_ok
    )

    run = runs_by_date.get(date_kst)
    delivery_ok = bool(payload.get('briefing_sent')) or bool(run and run.get('status') == 'success')
    delivery_evidence_present = bool(payload.get('briefing_sent')) or run is not None

    return {
        'date_kst': date_kst,
        'collector_ok': collector_ok,
        'delivery_ok': delivery_ok,
        'delivery_evidence_present': delivery_evidence_present,
        'weather_status': weather_status,
        'tasks_status': tasks_status,
        'task_count': task_count,
        'source_name': source_name,
        'source_ok': source_ok,
        'briefing_sent': payload.get('briefing_sent'),
        'briefing_sent_at': payload.get('briefing_sent_at'),
        'generated_at': payload.get('generated_at'),
    }


def main():
    runs_by_date = load_runs()
    samples = []

    for path in sorted(DATA_DIR.glob('morning-context-*.json')):
        payload = load_json(path)
        if not isinstance(payload, dict):
            continue
        sample = summarize_sample(path, payload, runs_by_date)
        if sample:
            samples.append(sample)

    samples.sort(key=lambda x: x['date_kst'])
    recent = samples[-MIN_SAMPLES:]

    if not recent:
        print('NO_DATA')
        return

    n = len(recent)
    collector_ok_count = sum(1 for row in recent if row['collector_ok'])
    delivery_ok_count = sum(1 for row in recent if row['delivery_ok'])
    delivery_evidence_count = sum(1 for row in recent if row['delivery_evidence_present'])

    collector_gate_ready = n >= MIN_SAMPLES and collector_ok_count == n
    delivery_gate_ready = n >= MIN_SAMPLES and delivery_ok_count == n
    gate_ready = collector_gate_ready and delivery_gate_ready

    if n < MIN_SAMPLES:
        gate_reason = 'need_more_samples'
    elif collector_ok_count != n:
        gate_reason = 'collector_failures'
    elif delivery_evidence_count != n:
        gate_reason = 'delivery_evidence_missing'
    elif delivery_ok_count != n:
        gate_reason = 'delivery_failures'
    else:
        gate_reason = 'ready_for_hybrid_split'

    last_bad = None
    for row in reversed(recent):
        if not row['collector_ok'] or not row['delivery_ok']:
            last_bad = row
            break

    print(json.dumps({
        'sample_type': 'latest_weekday_morning_contexts',
        'samples': n,
        'gate_min_samples': MIN_SAMPLES,
        'gate_remaining_samples': max(0, MIN_SAMPLES - n),
        'collector_ok_count': collector_ok_count,
        'collector_ok_rate_pct': round(collector_ok_count / n * 100, 2),
        'delivery_ok_count': delivery_ok_count,
        'delivery_ok_rate_pct': round(delivery_ok_count / n * 100, 2),
        'delivery_evidence_count': delivery_evidence_count,
        'collector_gate_ready': collector_gate_ready,
        'delivery_gate_ready': delivery_gate_ready,
        'gate_ready': gate_ready,
        'gate_reason': gate_reason,
        'last_bad': last_bad,
        'last': recent[-1],
        'dates': [row['date_kst'] for row in recent],
    }, ensure_ascii=False))


if __name__ == '__main__':
    main()
