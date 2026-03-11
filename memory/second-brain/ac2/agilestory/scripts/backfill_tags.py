#!/usr/bin/env python3
"""
Backfill tags for AC2 metadata using rule-based keyword extraction
from title + cleaned content.
"""

from __future__ import annotations

import json
import re
from datetime import datetime
from pathlib import Path

BASE_DIR = Path(__file__).parent.parent
META_DIR = BASE_DIR / "meta"
CLEANED_DIR = BASE_DIR / "cleaned"
REPORTS_DIR = BASE_DIR / "reports"
REPORTS_DIR.mkdir(parents=True, exist_ok=True)

OUT_REPORT = REPORTS_DIR / "phase2_tag_backfill_report.json"

# rule-based taxonomy (Korean + English variants)
# NOTE: 'agile' is handled with stricter heuristics below to avoid over-tagging.
TAXONOMY = {
    "scrum": ["스크럼", "scrum"],
    "kanban": ["칸반", "kanban"],
    "xp": ["xp", "extreme programming"],
    "tdd": ["tdd", "테스트 주도", "test driven"],
    "refactoring": ["리팩토링", "refactoring"],
    "code-review": ["코드리뷰", "코드 리뷰", "code review"],
    "pair-programming": ["페어 프로그래밍", "pair programming"],
    "retrospective": ["회고", "retrospective"],
    "planning": ["계획", "플래닝", "planning"],
    "sprint": ["스프린트", "sprint"],
    "backlog": ["백로그", "backlog"],
    "product": ["프로덕트", "제품", "product"],
    "po": ["product owner", "po", "프로덕트 오너"],
    "pm": ["project manager", "pm", "프로젝트 매니저"],
    "leadership": ["리더십", "리더", "leadership"],
    "coaching": ["코칭", "coach", "coaching"],
    "feedback": ["피드백", "feedback"],
    "communication": ["커뮤니케이션", "소통", "communication"],
    "collaboration": ["협업", "협력", "collaboration"],
    "team": ["팀", "team"],
    "developer": ["개발자", "developer"],
    "testing": ["테스트", "testing", "qa"],
    "quality": ["품질", "quality"],
    "devops": ["devops", "데브옵스"],
}


def extract_tags(title: str, text: str) -> list[str]:
    blob = f"{title}\n{text}".lower()
    tags: list[str] = []

    # 1) regular taxonomy tags
    for tag, keys in TAXONOMY.items():
        if any(k.lower() in blob for k in keys):
            tags.append(tag)

    # 2) tuned 'agile' heuristic (v2): avoid site-brand boilerplate over-tagging
    # remove common boilerplate phrase and count substantive mentions
    body = text.lower().replace("애자일 이야기", " ")
    agile_mentions = body.count("애자일") + len(re.findall(r"\bagile\b", body))

    agile_related = {
        "scrum",
        "kanban",
        "xp",
        "tdd",
        "retrospective",
        "sprint",
        "backlog",
        "pair-programming",
        "refactoring",
    }

    # add agile only if strong explicit mention OR concrete agile-practice tags present
    if agile_mentions >= 3 or any(t in tags for t in agile_related):
        tags.append("agile")

    # dedupe while preserving order
    seen = set()
    deduped = []
    for t in tags:
        if t not in seen:
            seen.add(t)
            deduped.append(t)
    return deduped


def main() -> int:
    meta_files = sorted(META_DIR.glob("*.json"))
    total = len(meta_files)
    updated = 0
    fallback_general = 0
    still_empty = 0

    for meta_file in meta_files:
        with open(meta_file, "r", encoding="utf-8") as f:
            meta = json.load(f)

        post_id = meta_file.stem
        cleaned_file = CLEANED_DIR / f"{post_id}.md"
        text = ""
        if cleaned_file.exists():
            text = cleaned_file.read_text(encoding="utf-8", errors="ignore")

        title = meta.get("title", "")
        tags = extract_tags(title, text)

        if tags:
            meta["tags"] = tags
            meta["tag_source"] = "rule_based_v2_tuned"
            meta["tags_updated_at"] = datetime.now().isoformat()
            updated += 1
        else:
            # fallback to keep metadata searchable without re-inflating agile bias
            meta["tags"] = ["general"]
            meta["tag_source"] = "rule_based_v2_tuned_fallback"
            meta["tags_updated_at"] = datetime.now().isoformat()
            updated += 1
            fallback_general += 1

        with open(meta_file, "w", encoding="utf-8") as f:
            json.dump(meta, f, ensure_ascii=False, indent=2)

    agile_tagged_posts = 0
    empty_posts = 0
    general_fallback_posts = 0
    for meta_file in meta_files:
        d = json.load(open(meta_file, "r", encoding="utf-8"))
        tags = d.get("tags") or []
        if not tags:
            empty_posts += 1
        if "agile" in tags:
            agile_tagged_posts += 1
        if tags == ["general"]:
            general_fallback_posts += 1

    report = {
        "generated_at": datetime.now().isoformat(),
        "total_posts": total,
        "updated_posts": updated,
        "still_empty_posts": empty_posts,
        "general_fallback_posts": general_fallback_posts,
        "taxonomy_size": len(TAXONOMY),
        "agile_tagged_posts": agile_tagged_posts,
        "version": "rule_based_v2_tuned",
    }

    with open(OUT_REPORT, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)

    print(json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
