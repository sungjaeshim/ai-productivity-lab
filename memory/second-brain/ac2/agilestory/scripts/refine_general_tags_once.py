#!/usr/bin/env python3
"""
One-pass refinement for posts currently tagged as ['general'].
Adds broader but meaningful topical tags from title+content using conservative rules.
"""

from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path

BASE = Path(__file__).parent.parent
META_DIR = BASE / "meta"
CLEAN_DIR = BASE / "cleaned"
REPORT = BASE / "reports" / "phase2_general_refine_report.json"

RULES = {
    "event": ["행사", "축제", "모임", "컨퍼런스", "conference", "meetup", "워크숍", "세미나"],
    "community": ["커뮤니티", "모임", "독자", "블로그", "방명록", "club", "클럽"],
    "career": ["입사", "구인", "채용", "불합격", "이력서", "career", "job"],
    "book": ["책", "서평", "독서", "book"],
    "creativity": ["창의성", "아이디어", "발명", "creative"],
    "education": ["교육", "공부", "학습", "study"],
    "research": ["연구", "연구원", "science", "bio"],
    "programming": ["프로그래밍", "개발", "코드", "software", "programming"],
    "language": ["언어", "language", "python", "java", "j 언어"],
    "web": ["웹", "web", "yahoo pipes", "웹디자이너", "web 2.0"],
    "leadership": ["리더", "조직", "팀장", "management", "강자의 논리"],
    "personal": ["사진", "음반", "인생", "고뇌", "special", "특별한"],
}


def infer_tags(title: str, text: str) -> list[str]:
    blob = f"{title}\n{text}".lower()
    out = []
    for tag, keys in RULES.items():
        if any(k.lower() in blob for k in keys):
            out.append(tag)
    return out


def main() -> int:
    meta_files = sorted(META_DIR.glob("*.json"))

    candidates = []
    for mf in meta_files:
        m = json.loads(mf.read_text(encoding="utf-8"))
        if m.get("tags") == ["general"]:
            candidates.append((mf, m))

    refined = 0
    still_general = 0
    applied = {}

    for mf, m in candidates:
        pid = mf.stem
        text = ""
        cf = CLEAN_DIR / f"{pid}.md"
        if cf.exists():
            text = cf.read_text(encoding="utf-8", errors="ignore")

        tags = infer_tags(m.get("title", ""), text)
        if tags:
            m["tags"] = tags
            m["tag_source"] = "rule_based_v2_general_refine"
            refined += 1
            for t in tags:
                applied[t] = applied.get(t, 0) + 1
        else:
            still_general += 1

        m["tags_updated_at"] = datetime.now().isoformat()
        mf.write_text(json.dumps(m, ensure_ascii=False, indent=2), encoding="utf-8")

    payload = {
        "generated_at": datetime.now().isoformat(),
        "total_general_candidates": len(candidates),
        "refined_count": refined,
        "still_general_count": still_general,
        "applied_tag_frequency": dict(sorted(applied.items(), key=lambda x: -x[1])),
        "version": "general_refine_once_v1",
    }
    REPORT.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(payload, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
