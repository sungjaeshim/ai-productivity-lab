#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sqlite3
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path('/root/.openclaw/workspace')
MEMORY_MD = ROOT / 'MEMORY.md'
MEMORY_DIR = ROOT / 'memory'
DB_PATH = ROOT / 'data' / 'memory_mirror.db'
STATE_PATH = ROOT / '.state' / 'memory_mirror_last.json'

BULLET_META_RE = re.compile(r"^-\s+(.*?)\s+_\(src:\s*([^,]+),\s*score:\s*([0-9.]+)\)_\s*$")


def normalize(s: str) -> str:
    s = s.strip().lower()
    s = re.sub(r"\s+", " ", s)
    s = re.sub(r"[^\w\s가-힣#:+/.-]", "", s)
    return s


def extract_section(text: str, heading: str) -> str:
    p = re.compile(rf"^##\s+{re.escape(heading)}\s*$", re.M)
    m = p.search(text)
    if not m:
        return ""
    start = m.end()
    nxt = re.search(r"^##\s+", text[start:], re.M)
    end = start + nxt.start() if nxt else len(text)
    return text[start:end].strip()


def bullet_lines(block: str) -> list[str]:
    out = []
    for ln in block.splitlines():
        m = re.match(r"^\s*[-*]\s+(.*)$", ln)
        if m:
            t = m.group(1).strip()
            if t:
                out.append(t)
    return out


def parse_memory_md() -> list[dict]:
    if not MEMORY_MD.exists():
        return []
    txt = MEMORY_MD.read_text(encoding='utf-8', errors='ignore')
    sections = [
        'User Preferences (durable)',
        'Confirmed Decisions (recent)',
        'Operating Rules',
        'Active Context (short horizon)',
    ]
    rows: list[dict] = []
    for sec in sections:
        blk = extract_section(txt, sec)
        for ln in blk.splitlines():
            m = BULLET_META_RE.match(ln.strip())
            if m:
                text = m.group(1).strip()
                src = m.group(2).strip()
                score = float(m.group(3))
                rows.append(
                    {
                        'source_file': 'MEMORY.md',
                        'section': sec,
                        'text': text,
                        'norm_key': normalize(text),
                        'score': score,
                        'origin': src,
                    }
                )
    return rows


def parse_daily_file(path: Path) -> list[dict]:
    if not path.exists():
        return []
    txt = path.read_text(encoding='utf-8', errors='ignore')
    rows: list[dict] = []
    section_titles = ['Decisions', 'Blockers', 'Active Tasks / WIP']
    for title in section_titles:
        p = re.compile(rf"^###\s+{re.escape(title)}\s*$", re.M)
        m = p.search(txt)
        if not m:
            continue
        start = m.end()
        nxt = re.search(r"^###\s+", txt[start:], re.M)
        end = start + nxt.start() if nxt else len(txt)
        blk = txt[start:end]
        for b in bullet_lines(blk):
            rows.append(
                {
                    'source_file': str(path.relative_to(ROOT)),
                    'section': title,
                    'text': b,
                    'norm_key': normalize(b),
                    'score': 0.65,
                    'origin': str(path.relative_to(ROOT)),
                }
            )
    return rows


def ensure_schema(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS memory_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            norm_key TEXT NOT NULL UNIQUE,
            text TEXT NOT NULL,
            section TEXT,
            source_file TEXT,
            origin TEXT,
            score REAL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS maintenance_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts TEXT NOT NULL,
            total_items INTEGER NOT NULL,
            inserted INTEGER NOT NULL,
            updated INTEGER NOT NULL,
            deduped INTEGER NOT NULL,
            notes TEXT
        )
        """
    )
    conn.execute("CREATE INDEX IF NOT EXISTS idx_memory_items_section ON memory_items(section)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_memory_items_score ON memory_items(score)")


def upsert_items(conn: sqlite3.Connection, items: list[dict]) -> tuple[int, int, int]:
    inserted = 0
    updated = 0
    deduped = 0
    now = datetime.now().isoformat(timespec='seconds')

    for it in items:
        if not it['norm_key']:
            continue
        cur = conn.execute(
            "SELECT id, text, section, source_file, score FROM memory_items WHERE norm_key=?",
            (it['norm_key'],),
        ).fetchone()
        if cur is None:
            conn.execute(
                """
                INSERT INTO memory_items(norm_key,text,section,source_file,origin,score,created_at,updated_at)
                VALUES(?,?,?,?,?,?,?,?)
                """,
                (
                    it['norm_key'],
                    it['text'],
                    it['section'],
                    it['source_file'],
                    it['origin'],
                    it['score'],
                    now,
                    now,
                ),
            )
            inserted += 1
        else:
            _, old_text, old_section, old_src, old_score = cur
            if (
                old_text != it['text']
                or old_section != it['section']
                or old_src != it['source_file']
                or float(old_score) != float(it['score'])
            ):
                conn.execute(
                    """
                    UPDATE memory_items
                    SET text=?, section=?, source_file=?, origin=?, score=?, updated_at=?
                    WHERE norm_key=?
                    """,
                    (
                        it['text'],
                        it['section'],
                        it['source_file'],
                        it['origin'],
                        it['score'],
                        now,
                        it['norm_key'],
                    ),
                )
                updated += 1
            else:
                deduped += 1

    return inserted, updated, deduped


def main() -> int:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)

    items = parse_memory_md()

    today = datetime.now().date()
    yday = today - timedelta(days=1)
    items.extend(parse_daily_file(MEMORY_DIR / f"{today:%Y-%m-%d}.md"))
    items.extend(parse_daily_file(MEMORY_DIR / f"{yday:%Y-%m-%d}.md"))

    conn = sqlite3.connect(DB_PATH)
    try:
        ensure_schema(conn)
        inserted, updated, deduped = upsert_items(conn, items)
        total = conn.execute("SELECT COUNT(*) FROM memory_items").fetchone()[0]

        ts = datetime.now().isoformat(timespec='seconds')
        conn.execute(
            "INSERT INTO maintenance_runs(ts,total_items,inserted,updated,deduped,notes) VALUES(?,?,?,?,?,?)",
            (ts, int(total), int(inserted), int(updated), int(deduped), 'nightly-mirror-sync'),
        )
        conn.commit()

        # Lightweight maintenance.
        conn.execute("ANALYZE")
        conn.execute("VACUUM")
        conn.commit()

        out = {
            'timestamp': ts,
            'db': str(DB_PATH),
            'total_items': int(total),
            'inserted': int(inserted),
            'updated': int(updated),
            'deduped': int(deduped),
            'status': 'PASS',
        }
        STATE_PATH.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding='utf-8')
        print(json.dumps(out, ensure_ascii=False))
        return 0
    finally:
        conn.close()


if __name__ == '__main__':
    raise SystemExit(main())
