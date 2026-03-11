#!/usr/bin/env python3
from __future__ import annotations

from datetime import datetime, timedelta
from pathlib import Path
import re
import json

ROOT = Path('/root/.openclaw/workspace')
MEMORY_DIR = ROOT / 'memory'
LONG_TERM = ROOT / 'MEMORY.md'

SECTIONS = ['Decisions', 'Blockers', 'Active Tasks / WIP']


def section_block(text: str, title: str) -> str:
    # Accept both "### Title" and "## Title" styles.
    p = re.compile(rf"^(?:###|##)\s+{re.escape(title)}\s*$", re.M)
    m = p.search(text)
    if not m:
        return ''
    start = m.end()
    n = re.search(r"^(?:###|##)\s+", text[start:], re.M)
    end = start + n.start() if n else len(text)
    return text[start:end]


def bullet_count(block: str) -> int:
    return len(re.findall(r"^\s*[-*]\s+", block, re.M))


def load_day(day: datetime) -> tuple[Path, str]:
    p = MEMORY_DIR / f"{day:%Y-%m-%d}.md"
    if not p.exists():
        return p, ''
    return p, p.read_text(encoding='utf-8', errors='ignore')


def main() -> None:
    now = datetime.now()
    today_path, today_text = load_day(now)
    y_path, y_text = load_day(now - timedelta(days=1))

    sec_counts = {s: bullet_count(section_block(today_text, s)) for s in SECTIONS}

    # restore-readiness: quick heuristic
    readiness = 0
    readiness += 40 if today_path.exists() else 0
    readiness += 20 if LONG_TERM.exists() else 0
    readiness += 20 if sec_counts.get('Decisions', 0) > 0 else 0
    readiness += 20 if sec_counts.get('Active Tasks / WIP', 0) > 0 else 0

    out = {
        'timestamp': now.isoformat(timespec='seconds'),
        'today_file': str(today_path),
        'today_exists': today_path.exists(),
        'yesterday_exists': y_path.exists(),
        'sections_today': sec_counts,
        'restore_readiness_score': readiness,
        'target_restore_seconds': 30,
        'status': 'PASS' if readiness >= 80 else 'WARN',
        'next_action': 'Fill Decisions/Blockers/Active Tasks in today memory' if readiness < 80 else 'Keep daily cadence',
    }

    state_dir = ROOT / '.state'
    state_dir.mkdir(parents=True, exist_ok=True)
    (state_dir / 'recall_status.json').write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(out, ensure_ascii=False))


if __name__ == '__main__':
    main()
