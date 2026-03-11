#!/usr/bin/env python3
"""
AC2 Phase3: Build searchable index (SQLite FTS5) and benchmark query latency.
"""

from __future__ import annotations

import json
import sqlite3
import time
from datetime import datetime
from pathlib import Path

BASE = Path(__file__).parent.parent
META_DIR = BASE / "meta"
CLEAN_DIR = BASE / "cleaned"
REPORTS = BASE / "reports"
REPORTS.mkdir(parents=True, exist_ok=True)

DB_PATH = BASE / "manifests" / "ac2_search.db"
DOCS_JSONL = BASE / "manifests" / "ac2_docs.jsonl"
REPORT_JSON = REPORTS / "phase3_index_report.json"
REPORT_MD = REPORTS / "phase3_index_report.md"

TEST_QUERIES = [
    "애자일",
    "코칭",
    "스크럼",
    "개발자",
    "피드백",
    "리팩토링",
    "협업",
    "book",
    "event",
    "research",
]


def load_docs():
    docs = []
    for mf in sorted(META_DIR.glob("*.json")):
        meta = json.loads(mf.read_text(encoding="utf-8"))
        pid = mf.stem
        cf = CLEAN_DIR / f"{pid}.md"
        content = cf.read_text(encoding="utf-8", errors="ignore") if cf.exists() else ""
        docs.append(
            {
                "post_id": pid,
                "title": meta.get("title", ""),
                "content": content,
                "tags": ",".join(meta.get("tags") or []),
                "url": meta.get("url", ""),
            }
        )
    return docs


def build_index(docs):
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(DB_PATH)
    cur = con.cursor()

    cur.execute("DROP TABLE IF EXISTS docs")
    cur.execute(
        "CREATE VIRTUAL TABLE docs USING fts5(post_id UNINDEXED, title, content, tags, url UNINDEXED, tokenize='unicode61')"
    )

    cur.executemany(
        "INSERT INTO docs(post_id,title,content,tags,url) VALUES (?,?,?,?,?)",
        [(d["post_id"], d["title"], d["content"], d["tags"], d["url"]) for d in docs],
    )
    con.commit()

    # simple optimize command for FTS
    cur.execute("INSERT INTO docs(docs) VALUES ('optimize')")
    con.commit()
    con.close()


def benchmark():
    con = sqlite3.connect(DB_PATH)
    cur = con.cursor()

    results = {}
    times = []
    for q in TEST_QUERIES:
        t0 = time.perf_counter()
        cur.execute(
            "SELECT post_id, title, bm25(docs) as score FROM docs WHERE docs MATCH ? ORDER BY score LIMIT 5",
            (q,),
        )
        rows = cur.fetchall()
        ms = (time.perf_counter() - t0) * 1000
        times.append(ms)
        results[q] = {
            "match_count_top5": len(rows),
            "latency_ms": round(ms, 3),
            "top": [{"post_id": r[0], "title": r[1], "score": r[2]} for r in rows],
        }

    con.close()
    return {
        "avg_latency_ms": round(sum(times) / len(times), 3) if times else 0,
        "p95_latency_ms": round(sorted(times)[int(len(times) * 0.95) - 1], 3) if times else 0,
        "queries": results,
    }


def write_docs_jsonl(docs):
    with open(DOCS_JSONL, "w", encoding="utf-8") as f:
        for d in docs:
            f.write(json.dumps(d, ensure_ascii=False) + "\n")


def main() -> int:
    docs = load_docs()
    write_docs_jsonl(docs)
    build_index(docs)
    bench = benchmark()

    payload = {
        "generated_at": datetime.now().isoformat(),
        "doc_count": len(docs),
        "db_path": str(DB_PATH),
        "docs_jsonl": str(DOCS_JSONL),
        "benchmark": bench,
        "status": "ok",
    }

    REPORT_JSON.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    md = []
    md.append("# AC2 Phase3 Index Report\n")
    md.append(f"- Generated: {payload['generated_at']}")
    md.append(f"- Doc count: {payload['doc_count']}")
    md.append(f"- DB: `{payload['db_path']}`")
    md.append(f"- JSONL: `{payload['docs_jsonl']}`")
    md.append(f"- Avg latency: {bench['avg_latency_ms']}ms")
    md.append(f"- P95 latency: {bench['p95_latency_ms']}ms\n")
    md.append("## Query Bench")
    md.append("|query|top5|latency_ms|")
    md.append("|---|---:|---:|")
    for q, v in bench["queries"].items():
        md.append(f"|{q}|{v['match_count_top5']}|{v['latency_ms']}|")
    REPORT_MD.write_text("\n".join(md) + "\n", encoding="utf-8")

    print(json.dumps({"status": "ok", "doc_count": len(docs), "avg_ms": bench["avg_latency_ms"], "p95_ms": bench["p95_latency_ms"]}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
