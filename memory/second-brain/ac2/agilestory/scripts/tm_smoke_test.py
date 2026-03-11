#!/usr/bin/env python3
"""Smoke test for tm_store.py"""

from __future__ import annotations

import json

from tm_store import TMEntry, TMStore


def main() -> int:
    store = TMStore()

    entry_id = store.upsert_entry(
        TMEntry(
            src_lang="en",
            tgt_lang="ko",
            domain="agilestory",
            source_text="Agile retrospective",
            target_text="애자일 회고",
            quality_score=97,
            status="approved",
            source_hash="demo_src_hash",
            target_hash="demo_tgt_hash",
        )
    )

    exact = store.lookup_exact("en", "ko", "agilestory", "Agile retrospective")
    fuzzy = store.search("en", "ko", "agilestory", "Agile", limit=5)

    term_id = store.upsert_term(
        src_lang="en",
        tgt_lang="ko",
        domain="agilestory",
        source_term="Sprint",
        target_term="스프린트",
        pos="noun",
        forbidden=0,
        priority=5,
        note="스크럼 핵심 용어",
        status="active",
    )
    terms = store.get_active_terms("en", "ko", domains=("agilestory", "general"))

    log_id = store.log_tm_action(
        entry_id=entry_id,
        action="approve",
        reviewer="jarvis",
        before_text="Agile retrospective",
        after_text="애자일 회고",
        comment="tm_store smoke test",
    )

    print(
        json.dumps(
            {
                "status": "ok",
                "db": str(store.db_path),
                "entry_id": entry_id,
                "exact_found": exact is not None,
                "fts_count": len(fuzzy),
                "term_id": term_id,
                "terms_count": len(terms),
                "log_id": log_id,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
