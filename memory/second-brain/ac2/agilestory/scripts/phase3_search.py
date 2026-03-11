#!/usr/bin/env python3
"""Query AC2 Phase3 FTS index with TM-aware routing.

Default routing is now TM-first (operational switch):
1) search TM
2) if no TM hit, fallback to AC2 docs FTS

Options:
  --tm-only    : search TM only
  --no-tm      : disable TM usage (docs-only)
  --docs-first : legacy behavior (docs first, TM fallback)
"""

from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path

from tm_store import TMStore

BASE = Path(__file__).parent.parent
DB_PATH = BASE / "manifests" / "ac2_search.db"


def _usage() -> str:
    return (
        "Usage: phase3_search.py [--tm-only] [--no-tm] [--docs-first] "
        "<query> [limit] [src_lang] [tgt_lang] [domain]"
    )


def _parse_args(argv: list[str]) -> tuple[str, int, str, str, str, bool, bool, bool]:
    tm_only = False
    no_tm = False
    docs_first = False
    positional: list[str] = []

    for arg in argv:
        if arg == "--tm-only":
            tm_only = True
        elif arg == "--no-tm":
            no_tm = True
        elif arg == "--docs-first":
            docs_first = True
        else:
            positional.append(arg)

    if tm_only and no_tm:
        raise ValueError("--tm-only and --no-tm cannot be used together")
    if tm_only and docs_first:
        raise ValueError("--tm-only and --docs-first cannot be used together")

    if len(positional) < 1:
        raise ValueError(_usage())

    query = positional[0]
    limit = int(positional[1]) if len(positional) >= 2 else 10
    src_lang = positional[2] if len(positional) >= 3 else "en"
    tgt_lang = positional[3] if len(positional) >= 4 else "ko"
    domain = positional[4] if len(positional) >= 5 else "agilestory"
    return query, limit, src_lang, tgt_lang, domain, tm_only, no_tm, docs_first


def _search_docs(query: str, limit: int) -> list[tuple]:
    if not DB_PATH.exists():
        return []
    con = sqlite3.connect(DB_PATH)
    cur = con.cursor()
    cur.execute(
        "SELECT post_id,title,tags,url,bm25(docs) as score FROM docs WHERE docs MATCH ? ORDER BY score LIMIT ?",
        (query, limit),
    )
    rows = cur.fetchall()
    con.close()
    return rows


def _search_tm(src_lang: str, tgt_lang: str, domain: str, query: str, limit: int) -> list[dict]:
    tm_store = TMStore()
    return tm_store.search(
        src_lang=src_lang,
        tgt_lang=tgt_lang,
        domain=domain,
        query=query,
        limit=limit,
    )


def main() -> int:
    try:
        query, limit, src_lang, tgt_lang, domain, tm_only, no_tm, docs_first = _parse_args(sys.argv[1:])
    except ValueError as e:
        print(str(e))
        return 1

    rows: list[tuple] = []
    tm_results: list[dict] = []
    tm_used = False

    if tm_only:
        tm_used = True
        tm_results = _search_tm(src_lang, tgt_lang, domain, query, limit)
    elif no_tm:
        rows = _search_docs(query, limit)
    elif docs_first:
        rows = _search_docs(query, limit)
        if not rows:
            tm_used = True
            tm_results = _search_tm(src_lang, tgt_lang, domain, query, limit)
    else:
        # default: TM-first (operational route switch)
        tm_used = True
        tm_results = _search_tm(src_lang, tgt_lang, domain, query, limit)
        if not tm_results:
            rows = _search_docs(query, limit)

    mode = "tm_only" if tm_only else ("disabled" if no_tm else ("docs_first" if docs_first else "tm_first"))

    out = {
        "status": "ok",
        "query": query,
        "count": len(rows),
        "results": [
            {"post_id": r[0], "title": r[1], "tags": r[2], "url": r[3], "score": r[4]} for r in rows
        ],
        "tm_fallback": {
            "used": tm_used,
            "mode": mode,
            "src_lang": src_lang,
            "tgt_lang": tgt_lang,
            "domain": domain,
            "count": len(tm_results),
            "results": tm_results,
        },
    }
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
