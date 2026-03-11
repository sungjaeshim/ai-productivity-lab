#!/usr/bin/env python3
"""Finalize remaining ['general'] tags to zero via conservative title-based mapping."""

from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path

BASE = Path(__file__).parent.parent
META_DIR = BASE / "meta"
REPORT = BASE / "reports" / "phase2_general_finalize_report.json"

# ordered rules
RULES = [
    ("ac2", ["ac2", "intensive"]),
    ("agile", ["애자일", "agile"]),
    ("management", ["관리자", "manager", "management", "프로젝트"]),
    ("programming", ["소프트웨어", "버그", "oop", "oopsla", "프로그래밍"]),
    ("design", ["design", "디자인", "프로토타이핑", "contextual"]),
    ("education", ["캠프", "특강", "배우기", "과정", "학습", "수학"]),
    ("community", ["트위터", "g메일", "계정", "모집", "대화"]),
    ("psychology", ["mbti", "이너 게임", "감정", "사고"]),
    ("career", ["년 차", "경력", "차?"]),
    ("event", ["2006", "특강", "캠프", "모집"]),
    ("personal", ["vcr", "드립니다"]),
]


def infer_from_title(title: str) -> list[str]:
    t = (title or "").lower()
    tags = []
    for tag, keys in RULES:
        if any(k.lower() in t for k in keys):
            tags.append(tag)
    # dedupe preserve order
    out = []
    seen = set()
    for x in tags:
        if x not in seen:
            seen.add(x)
            out.append(x)
    if not out:
        out = ["misc"]
    return out


def main() -> int:
    changed = 0
    unresolved = 0
    touched = []

    for mf in sorted(META_DIR.glob("*.json")):
        m = json.loads(mf.read_text(encoding="utf-8"))
        if m.get("tags") != ["general"]:
            continue

        title = m.get("title", "")
        new_tags = infer_from_title(title)
        if new_tags == ["general"]:
            unresolved += 1
            continue

        m["tags"] = new_tags
        m["tag_source"] = "general_finalize_v1"
        m["tags_updated_at"] = datetime.now().isoformat()
        mf.write_text(json.dumps(m, ensure_ascii=False, indent=2), encoding="utf-8")

        changed += 1
        touched.append({"post_id": mf.stem, "title": title, "tags": new_tags})

    remaining_general = 0
    for mf in sorted(META_DIR.glob("*.json")):
        m = json.loads(mf.read_text(encoding="utf-8"))
        if m.get("tags") == ["general"]:
            remaining_general += 1

    payload = {
        "generated_at": datetime.now().isoformat(),
        "changed_count": changed,
        "remaining_general": remaining_general,
        "unresolved": unresolved,
        "touched": touched,
        "version": "general_finalize_v1",
    }
    REPORT.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"changed_count": changed, "remaining_general": remaining_general}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
