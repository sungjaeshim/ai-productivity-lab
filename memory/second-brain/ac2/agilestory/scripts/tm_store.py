#!/usr/bin/env python3
"""TM v1 SQLite helper for AC2 AgileStory.

Uses the shared DB: workspace/memory/second-brain.db
Schema reference: workspace/sql/tm_v1_schema.sql
"""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence


HERE = Path(__file__).resolve()


def _find_workspace_root(start: Path) -> Path:
    for p in [start, *start.parents]:
        if (p / "sql" / "tm_v1_schema.sql").exists():
            return p
    raise RuntimeError("workspace root not found (sql/tm_v1_schema.sql missing)")


WORKSPACE = _find_workspace_root(HERE)
DEFAULT_DB_PATH = WORKSPACE / "memory" / "second-brain.db"


@dataclass(frozen=True)
class TMEntry:
    src_lang: str
    tgt_lang: str
    domain: str
    source_text: str
    target_text: str
    quality_score: int = 0
    status: str = "approved"
    source_hash: str | None = None
    target_hash: str | None = None


class TMStore:
    def __init__(self, db_path: str | Path | None = None) -> None:
        self.db_path = Path(db_path) if db_path else DEFAULT_DB_PATH

    def _connect(self) -> sqlite3.Connection:
        con = sqlite3.connect(self.db_path)
        con.row_factory = sqlite3.Row
        con.execute("PRAGMA foreign_keys=ON")
        return con

    def upsert_entry(self, entry: TMEntry) -> int:
        sql = """
        INSERT INTO tm_entries (
          src_lang, tgt_lang, domain,
          source_text, target_text,
          quality_score, status,
          source_hash, target_hash
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (src_lang, tgt_lang, domain, source_text) DO UPDATE SET
          target_text   = excluded.target_text,
          quality_score = excluded.quality_score,
          status        = excluded.status,
          source_hash   = excluded.source_hash,
          target_hash   = excluded.target_hash,
          updated_at    = strftime('%Y-%m-%dT%H:%M:%fZ','now')
        """
        with self._connect() as con:
            con.execute(
                sql,
                (
                    entry.src_lang,
                    entry.tgt_lang,
                    entry.domain,
                    entry.source_text,
                    entry.target_text,
                    entry.quality_score,
                    entry.status,
                    entry.source_hash,
                    entry.target_hash,
                ),
            )
            row = con.execute(
                """
                SELECT entry_id
                FROM tm_entries
                WHERE src_lang=? AND tgt_lang=? AND domain=? AND source_text=?
                """,
                (entry.src_lang, entry.tgt_lang, entry.domain, entry.source_text),
            ).fetchone()
            return int(row["entry_id"])

    def lookup_exact(self, src_lang: str, tgt_lang: str, domain: str, source_text: str) -> dict | None:
        with self._connect() as con:
            row = con.execute(
                """
                SELECT entry_id, source_text, target_text, quality_score, updated_at
                FROM tm_entries
                WHERE src_lang=? AND tgt_lang=? AND domain=? AND source_text=? AND status='approved'
                """,
                (src_lang, tgt_lang, domain, source_text),
            ).fetchone()
            return dict(row) if row else None

    def search(self, src_lang: str, tgt_lang: str, domain: str, query: str, limit: int = 20) -> list[dict]:
        with self._connect() as con:
            try:
                rows = con.execute(
                    """
                    SELECT e.entry_id, e.source_text, e.target_text, e.domain, e.quality_score
                    FROM tm_entries_fts
                    JOIN tm_entries e ON e.entry_id = tm_entries_fts.rowid
                    WHERE tm_entries_fts MATCH ?
                      AND e.src_lang = ?
                      AND e.tgt_lang = ?
                      AND e.domain = ?
                      AND e.status = 'approved'
                    ORDER BY bm25(tm_entries_fts) ASC, e.quality_score DESC
                    LIMIT ?
                    """,
                    (query, src_lang, tgt_lang, domain, limit),
                ).fetchall()
            except sqlite3.OperationalError:
                kw = f"%{query}%"
                rows = con.execute(
                    """
                    SELECT entry_id, source_text, target_text, domain, quality_score
                    FROM tm_entries
                    WHERE src_lang=? AND tgt_lang=? AND domain=? AND status='approved'
                      AND (source_text LIKE ? OR target_text LIKE ?)
                    ORDER BY quality_score DESC, updated_at DESC
                    LIMIT ?
                    """,
                    (src_lang, tgt_lang, domain, kw, kw, limit),
                ).fetchall()
            return [dict(r) for r in rows]

    def upsert_term(
        self,
        *,
        src_lang: str,
        tgt_lang: str,
        domain: str,
        source_term: str,
        target_term: str,
        pos: str | None = None,
        forbidden: int = 0,
        priority: int = 3,
        note: str | None = None,
        status: str = "active",
    ) -> int:
        with self._connect() as con:
            con.execute(
                """
                INSERT INTO terms (
                  src_lang, tgt_lang, domain,
                  source_term, target_term, pos,
                  forbidden, priority, note, status
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (src_lang, tgt_lang, domain, source_term) DO UPDATE SET
                  target_term = excluded.target_term,
                  pos = excluded.pos,
                  forbidden = excluded.forbidden,
                  priority = excluded.priority,
                  note = excluded.note,
                  status = excluded.status,
                  updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
                """,
                (src_lang, tgt_lang, domain, source_term, target_term, pos, forbidden, priority, note, status),
            )
            row = con.execute(
                """
                SELECT term_id
                FROM terms
                WHERE src_lang=? AND tgt_lang=? AND domain=? AND source_term=?
                """,
                (src_lang, tgt_lang, domain, source_term),
            ).fetchone()
            return int(row["term_id"])

    def get_active_terms(self, src_lang: str, tgt_lang: str, domains: Sequence[str] = ("general", "ui")) -> list[dict]:
        if not domains:
            return []
        placeholders = ",".join("?" for _ in domains)
        sql = f"""
        SELECT term_id, source_term, target_term, pos, forbidden, priority, note
        FROM terms
        WHERE src_lang=? AND tgt_lang=?
          AND domain IN ({placeholders})
          AND status='active'
        ORDER BY forbidden DESC, priority DESC, source_term ASC
        """
        with self._connect() as con:
            rows = con.execute(sql, (src_lang, tgt_lang, *domains)).fetchall()
            return [dict(r) for r in rows]

    def log_tm_action(
        self,
        *,
        entry_id: int,
        action: str,
        reviewer: str,
        before_text: str | None = None,
        after_text: str | None = None,
        comment: str | None = None,
    ) -> int:
        with self._connect() as con:
            cur = con.execute(
                """
                INSERT INTO review_logs (tm_entry_id, action, reviewer, before_text, after_text, comment)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (entry_id, action, reviewer, before_text, after_text, comment),
            )
            return int(cur.lastrowid)

    def log_term_action(
        self,
        *,
        term_id: int,
        action: str,
        reviewer: str,
        before_text: str | None = None,
        after_text: str | None = None,
        comment: str | None = None,
    ) -> int:
        with self._connect() as con:
            cur = con.execute(
                """
                INSERT INTO review_logs (term_id, action, reviewer, before_text, after_text, comment)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (term_id, action, reviewer, before_text, after_text, comment),
            )
            return int(cur.lastrowid)
