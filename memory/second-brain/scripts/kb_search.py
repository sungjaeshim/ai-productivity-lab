#!/usr/bin/env python3
"""Unified search across AC2 + Wooridle FTS indexes."""

from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent

AC2_DB = BASE / "ac2" / "agilestory" / "manifests" / "ac2_search.db"
WOORIDLE_DB = BASE / "manifests" / "wooridle_search.db"


def search_ac2(query: str, limit: int) -> list[dict]:
    if not AC2_DB.exists():
        return []
    con = sqlite3.connect(AC2_DB)
    cur = con.cursor()
    cur.execute(
        "SELECT post_id,title,tags,url,bm25(docs) as score FROM docs WHERE docs MATCH ? ORDER BY score LIMIT ?",
        (query, limit),
    )
    rows = cur.fetchall()
    con.close()
    return [
        {
            "source_set": "ac2",
            "id": r[0],
            "title": r[1],
            "tags": r[2],
            "path_or_url": r[3],
            "score": r[4],
        }
        for r in rows
    ]


def search_wooridle(query: str, limit: int) -> list[dict]:
    if not WOORIDLE_DB.exists():
        return []
    con = sqlite3.connect(WOORIDLE_DB)
    cur = con.cursor()
    cur.execute(
        "SELECT doc_id,title,tags,path,bm25(docs) as score FROM docs WHERE docs MATCH ? ORDER BY score LIMIT ?",
        (query, limit),
    )
    rows = cur.fetchall()
    con.close()
    return [
        {
            "source_set": "wooridle",
            "id": r[0],
            "title": r[1],
            "tags": r[2],
            "path_or_url": r[3],
            "score": r[4],
        }
        for r in rows
    ]


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: kb_search.py <query> [limit_each]")
        return 1

    query = sys.argv[1]
    limit_each = int(sys.argv[2]) if len(sys.argv) > 2 else 5

    ac2 = search_ac2(query, limit_each)
    wooridle = search_wooridle(query, limit_each)

    merged = sorted(ac2 + wooridle, key=lambda x: x["score"])[: limit_each * 2]

    out = {
        "status": "ok",
        "query": query,
        "counts": {"ac2": len(ac2), "wooridle": len(wooridle), "merged": len(merged)},
        "results": merged,
    }
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
