#!/usr/bin/env python3
"""Search Wooridle FTS index."""

from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
DB_PATH = BASE / "manifests" / "wooridle_search.db"


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: wooridle_search.py <query> [limit]")
        return 1

    query = sys.argv[1]
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 10

    if not DB_PATH.exists():
        print(json.dumps({"status": "error", "error": "index_not_found", "db": str(DB_PATH)}, ensure_ascii=False))
        return 1

    con = sqlite3.connect(DB_PATH)
    cur = con.cursor()
    cur.execute(
        "SELECT doc_id,title,category,tags,source,path,bm25(docs) AS score FROM docs WHERE docs MATCH ? ORDER BY score LIMIT ?",
        (query, limit),
    )
    rows = cur.fetchall()
    con.close()

    out = {
        "status": "ok",
        "query": query,
        "count": len(rows),
        "results": [
            {
                "doc_id": r[0],
                "title": r[1],
                "category": r[2],
                "tags": r[3],
                "source": r[4],
                "path": r[5],
                "score": r[6],
            }
            for r in rows
        ],
    }
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
