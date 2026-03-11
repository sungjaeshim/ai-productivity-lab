#!/usr/bin/env python3
import json
import re
import subprocess
from datetime import datetime, timezone, timedelta
from pathlib import Path

KST = timezone(timedelta(hours=9))
ROOT = Path('/root/.openclaw/workspace')
OUT_DIR = ROOT / '.state' / 'macd-shadow'
OUT_DIR.mkdir(parents=True, exist_ok=True)

RAW_PATH = OUT_DIR / 'latest_raw.txt'
JSONL_PATH = OUT_DIR / 'runs.jsonl'

CMD = ['python3', '/root/.openclaw/scripts/nq_macd_multi.py', '--force-live', '--no-send']


def pick(pattern: str, text: str):
    m = re.search(pattern, text, flags=re.MULTILINE)
    if not m:
        return None
    if m.lastindex:
        return m.group(1).strip()
    return m.group(0).strip()


def main():
    ts = datetime.now(KST)
    started = datetime.now(timezone.utc)
    p = subprocess.run(CMD, capture_output=True, text=True)
    ended = datetime.now(timezone.utc)
    dur_ms = int((ended - started).total_seconds() * 1000)

    out = (p.stdout or '').strip()
    err = (p.stderr or '').strip()
    RAW_PATH.write_text(out + ('\n' + err if err else '') + '\n', encoding='utf-8')

    rec = {
        'ts_kst': ts.isoformat(timespec='seconds'),
        'exit_code': p.returncode,
        'duration_ms': dur_ms,
        'sent': False,
        'signal_type': 'none',
        'price_line': None,
        'score': None,
        'tf_line': None,
        'format_ok': False,
        'raw_path': str(RAW_PATH),
    }

    text = out
    if '골든크로스 발생' in text:
        rec['signal_type'] = 'golden'
    elif '데드크로스 발생' in text:
        rec['signal_type'] = 'dead'
    elif '시장급변 감지' in text:
        rec['signal_type'] = 'spike'

    rec['price_line'] = pick(r'^• NQ\s+\$[^\n]+', text)
    rec['tf_line'] = pick(r'^• 멀티TF 정렬:\s*([^\n]+)', text)
    rec['score'] = pick(r'^• ST:\s*[^\n]*Composite:\s*(\d+/100)', text)

    # basic full-format guard (v2 card format)
    required = [
        '【1) 가격 액션】',
        '【2) 이벤트】',
        '【3) 모멘텀/오실레이터】',
        '【4) 액션 가이드】',
        '【5) 매크로/리스크】',
        '【6) 종합 결론】',
    ]
    rec['format_ok'] = all(k in text for k in required)

    with JSONL_PATH.open('a', encoding='utf-8') as f:
        f.write(json.dumps(rec, ensure_ascii=False) + '\n')

    print(json.dumps(rec, ensure_ascii=False))


if __name__ == '__main__':
    main()
