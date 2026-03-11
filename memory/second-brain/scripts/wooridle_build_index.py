#!/usr/bin/env python3
"""Build Wooridle searchable index (SQLite FTS5) from insights markdown files."""

from __future__ import annotations

import json
import re
import sqlite3
import time
from datetime import datetime
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
INSIGHTS_DIR = BASE / "insights"
MANIFESTS = BASE / "manifests"
REPORTS = BASE / "reports"

DB_PATH = MANIFESTS / "wooridle_search.db"
DOCS_JSONL = MANIFESTS / "wooridle_docs.jsonl"
REPORT_JSON = REPORTS / "wooridle_index_report.json"
REPORT_MD = REPORTS / "wooridle_index_report.md"

TEST_QUERIES = [
    "코칭",
    "애자일",
    "리더십",
    "학습",
    "의사결정",
    "ORID",
    "ADKAR",
    "퍼실리테이션",
]


def parse_doc(path: Path) -> dict:
    text = path.read_text(encoding="utf-8", errors="ignore")
    lines = text.splitlines()

    title = ""
    source = ""
    category = ""
    tags = ""

    for ln in lines[:30]:
        if ln.startswith("# ") and not title:
            title = ln[2:].strip()
        elif ln.startswith("> 출처:") and not source:
            source = ln.split(":", 1)[1].strip()
        elif ln.startswith("> 카테고리:") and not category:
            category = ln.split(":", 1)[1].strip()
        elif ln.startswith("> 태그:") and not tags:
            tags = ln.split(":", 1)[1].strip()

    if not title:
        title = path.stem

    # drop noisy metadata fences and separators from content body
    content = re.sub(r"^---\s*$", "", text, flags=re.MULTILINE).strip()

    return {
        "doc_id": path.stem,
        "title": title,
        "category": category,
        "tags": tags,
        "source": source,
        "path": str(path),
        "content": content,
    }


def load_docs() -> list[dict]:
    docs: list[dict] = []

    for p in sorted(INSIGHTS_DIR.glob("2026-02-24-wooridle-*.md")):
        docs.append(parse_doc(p))

    # include 2 base corpora files as references
    for base_name in ["wooridle-full.md", "wooridle-library.md"]:
        p = BASE / base_name
        if p.exists():
            docs.append(
                {
                    "doc_id": p.stem,
                    "title": p.stem,
                    "category": "reference",
                    "tags": "#wooridle #reference",
                    "source": "local",
                    "path": str(p),
                    "content": p.read_text(encoding="utf-8", errors="ignore"),
                }
            )

    return docs


def write_docs_jsonl(docs: list[dict]) -> None:
    MANIFESTS.mkdir(parents=True, exist_ok=True)
    with DOCS_JSONL.open("w", encoding="utf-8") as f:
        for d in docs:
            f.write(json.dumps(d, ensure_ascii=False) + "\n")


def build_index(docs: list[dict]) -> None:
    MANIFESTS.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(DB_PATH)
    cur = con.cursor()

    cur.execute("DROP TABLE IF EXISTS docs")
    cur.execute(
        "CREATE VIRTUAL TABLE docs USING fts5(doc_id UNINDEXED, title, category, tags, source, path UNINDEXED, content, tokenize='unicode61')"
    )

    cur.executemany(
        "INSERT INTO docs(doc_id,title,category,tags,source,path,content) VALUES (?,?,?,?,?,?,?)",
        [
            (
                d["doc_id"],
                d["title"],
                d["category"],
                d["tags"],
                d["source"],
                d["path"],
                d["content"],
            )
            for d in docs
        ],
    )
    con.commit()
    cur.execute("INSERT INTO docs(docs) VALUES ('optimize')")
    con.commit()
    con.close()


def benchmark() -> dict:
    con = sqlite3.connect(DB_PATH)
    cur = con.cursor()

    times: list[float] = []
    queries: dict = {}

    for q in TEST_QUERIES:
        t0 = time.perf_counter()
        cur.execute(
            "SELECT doc_id,title,bm25(docs) AS score FROM docs WHERE docs MATCH ? ORDER BY score LIMIT 5",
            (q,),
        )
        rows = cur.fetchall()
        ms = (time.perf_counter() - t0) * 1000
        times.append(ms)
        queries[q] = {
            "match_count_top5": len(rows),
            "latency_ms": round(ms, 3),
            "top": [{"doc_id": r[0], "title": r[1], "score": r[2]} for r in rows],
        }

    con.close()
    times_sorted = sorted(times)
    p95_idx = max(0, int(len(times_sorted) * 0.95) - 1)

    return {
        "avg_latency_ms": round(sum(times) / len(times), 3) if times else 0,
        "p95_latency_ms": round(times_sorted[p95_idx], 3) if times else 0,
        "queries": queries,
    }


def write_reports(doc_count: int, bench: dict) -> None:
    REPORTS.mkdir(parents=True, exist_ok=True)

    payload = {
        "generated_at": datetime.now().isoformat(),
        "doc_count": doc_count,
        "db_path": str(DB_PATH),
        "docs_jsonl": str(DOCS_JSONL),
        "benchmark": bench,
        "status": "ok",
    }
    REPORT_JSON.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    lines = [
        "# Wooridle Index Report",
        "",
        f"- Generated: {payload['generated_at']}",
        f"- Doc count: {doc_count}",
        f"- DB: `{DB_PATH}`",
        f"- JSONL: `{DOCS_JSONL}`",
        f"- Avg latency: {bench['avg_latency_ms']}ms",
        f"- P95 latency: {bench['p95_latency_ms']}ms",
        "",
        "## Query Bench",
        "|query|top5|latency_ms|",
        "|---|---:|---:|",
    ]
    for q, v in bench["queries"].items():
        lines.append(f"|{q}|{v['match_count_top5']}|{v['latency_ms']}|")

    REPORT_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    docs = load_docs()
    write_docs_jsonl(docs)
    build_index(docs)
    bench = benchmark()
    write_reports(len(docs), bench)

    print(
        json.dumps(
            {
                "status": "ok",
                "doc_count": len(docs),
                "db": str(DB_PATH),
                "avg_ms": bench["avg_latency_ms"],
                "p95_ms": bench["p95_latency_ms"],
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
