#!/usr/bin/env python3
"""Archived on 2026-03-06: standalone Notion logger kept for recovery."""
"""
자비스 작업 로그를 노션에 기록하는 스크립트

기본 사용:
  python notion_log.py "제목" "대분류" "중분류" "요약" [--aha]

옵션:
  --db ops|decision|knowledge|trade
    - 미지정 시 자동 라우팅
"""

import argparse
import json
import copy
import urllib.request
import urllib.error
import uuid
from datetime import datetime
from pathlib import Path

# 노션 설정
NOTION_KEY = Path("~/.config/notion/api_key").expanduser().read_text().strip()
# 2025-09-03+ required for databases with multiple data sources
NOTION_VERSION = "2025-09-03"

DBS = {
    "ops": {
        "id": "3189d657-66da-8178-ae76-cc92dd0720b8",
        "title_prop": "Task",
        "name": "Daily Ops",
    },
    "decision": {
        "id": "3189d657-66da-817b-ab1d-d5e455ef9add",
        "title_prop": "Decision",
        "name": "Decision Log",
    },
    "knowledge": {
        "id": "3189d657-66da-81e7-b36c-f83cd045bc29",
        "title_prop": "Title",
        "name": "Knowledge Cards",
    },
    "trade": {
        "id": "3189d657-66da-813d-bc8b-ed1dc324a2a4",
        "title_prop": "Trade",
        "name": "Trade Journal",
    },
}

# 대분류 매핑
CATEGORIES = {
    "연구": "Research", "research": "Research",
    "개발": "Development", "development": "Development", "dev": "Development",
    "학습": "Learning", "learning": "Learning",
    "인사이트": "Insight", "insight": "Insight",
    "시스템": "System", "system": "System",
}

# 중분류 매핑
SUBCATEGORIES = {
    "자동매매": "Trading", "trading": "Trading",
    "수동소득": "Passive Income", "passive": "Passive Income",
    "스킬": "Skills", "skills": "Skills", "스킬습득": "Skills",
    "제2의뇌": "Second Brain", "brain": "Second Brain", "뇌": "Second Brain",
    "아이디어정원": "Idea Garden", "idea": "Idea Garden", "아이디어": "Idea Garden",
    "최적화": "Optimization", "opt": "Optimization",
    "기타": "Other", "other": "Other",
}


def _request(url: str, payload: dict):
    def _do_post(post_payload: dict):
        req = urllib.request.Request(
            url,
            data=json.dumps(post_payload).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {NOTION_KEY}",
                "Notion-Version": NOTION_VERSION,
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode("utf-8"))

    try:
        return _do_post(payload)
    except urllib.error.HTTPError as e:
        body = ""
        body_json = None
        try:
            body = e.read().decode("utf-8", errors="ignore")
            if body:
                body_json = json.loads(body)
        except Exception:
            body_json = None

        # Notion multi data-source DB fallback:
        # retry with parent.data_source_id if API returns child_data_source_ids
        try:
            err_type = (body_json or {}).get("additional_data", {}).get("error_type")
            child_ids = (body_json or {}).get("additional_data", {}).get("child_data_source_ids") or []
            has_db_parent = isinstance(payload.get("parent"), dict) and "database_id" in payload.get("parent", {})
            if e.code == 400 and err_type == "multiple_data_sources_for_database" and child_ids and has_db_parent:
                retry_payload = copy.deepcopy(payload)
                retry_payload["parent"] = {"data_source_id": child_ids[0]}
                return _do_post(retry_payload)
        except Exception:
            pass

        msg = f"Notion API HTTP {e.code}: {e.reason}"
        if body:
            msg += f" | body={body}"
        raise RuntimeError(msg) from e


def choose_db(category: str, subcategory: str, title: str, summary: str, override: str | None = None) -> str:
    """자동 라우팅 규칙: trade > decision > knowledge > ops"""
    if override:
        return override

    c = (category or "").lower()
    s = (subcategory or "").lower()
    t = (title or "").lower()
    y = (summary or "").lower()
    text = f"{t} {y}"

    # 1) Trade Journal
    trade_keywords = ["nq", "trade", "trading", "진입", "청산", "손절", "익절", "포지션", "매매", "futures"]
    if s in {"자동매매", "trading"} or any(k in text for k in trade_keywords):
        return "trade"

    # 2) Decision Log
    decision_keywords = ["결정", "decision", "판단", "선택", "승인", "가결", "보류"]
    if any(k in text for k in decision_keywords):
        return "decision"

    # 3) Knowledge Cards
    knowledge_keywords = ["insight", "인사이트", "아이디어", "idea", "패턴", "교훈", "학습", "레슨", "lesson"]
    if c in {"인사이트", "insight", "연구", "research", "학습", "learning"}:
        return "knowledge"
    if s in {"제2의뇌", "brain", "뇌", "아이디어정원", "idea", "아이디어", "스킬", "skills", "스킬습득"}:
        return "knowledge"
    if any(k in text for k in knowledge_keywords):
        return "knowledge"

    # 4) default
    return "ops"


def add_log(title: str, category: str, subcategory: str, summary: str, is_aha: bool = False, db_override: str | None = None):
    """노션에 작업 로그 추가"""

    # 카테고리 매핑(본문용)
    cat = CATEGORIES.get(category.lower(), category)
    subcat = SUBCATEGORIES.get(subcategory.lower(), subcategory)

    db_key = choose_db(category, subcategory, title, summary, db_override)
    db_conf = DBS[db_key]

    now = datetime.now()
    event_id = f"evt_{now.strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:8]}"
    local_id = f"loc_{uuid.uuid4().hex[:12]}"

    data = {
        "parent": {"database_id": db_conf["id"]},
        "properties": {
            db_conf["title_prop"]: {"title": [{"text": {"content": title}}]},
            "Local_ID": {"rich_text": [{"text": {"content": local_id}}]},
            "Event_ID": {"rich_text": [{"text": {"content": event_id}}]},
            "State": {"select": {"name": "Inbox"}},
            "Updated_At": {"date": {"start": now.isoformat()}},
            "Source_Ref": {"rich_text": [{"text": {"content": "scripts/notion_log.py"}}]},
        },
    }

    # 페이지 내용으로 상세 정보 추가
    children = [
        {
            "object": "block",
            "type": "heading_2",
            "heading_2": {"rich_text": [{"text": {"content": "📋 요약"}}]},
        },
        {
            "object": "block",
            "type": "paragraph",
            "paragraph": {"rich_text": [{"text": {"content": summary}}]},
        },
        {
            "object": "block",
            "type": "heading_2",
            "heading_2": {"rich_text": [{"text": {"content": "🏷️ 분류"}}]},
        },
        {
            "object": "block",
            "type": "bulleted_list_item",
            "bulleted_list_item": {"rich_text": [{"text": {"content": f"대분류: {cat}"}}]},
        },
        {
            "object": "block",
            "type": "bulleted_list_item",
            "bulleted_list_item": {"rich_text": [{"text": {"content": f"중분류: {subcat}"}}]},
        },
        {
            "object": "block",
            "type": "bulleted_list_item",
            "bulleted_list_item": {"rich_text": [{"text": {"content": f"날짜: {now.strftime('%Y-%m-%d %H:%M')}"}}]},
        },
        {
            "object": "block",
            "type": "bulleted_list_item",
            "bulleted_list_item": {"rich_text": [{"text": {"content": f"라우팅 DB: {db_conf['name']}"}}]},
        },
    ]

    if is_aha:
        children.insert(
            0,
            {
                "object": "block",
                "type": "callout",
                "callout": {
                    "icon": {"emoji": "💡"},
                    "rich_text": [{"text": {"content": "아하 포인트!"}}],
                },
            },
        )

    data["children"] = children

    result = _request("https://api.notion.com/v1/pages", data)
    print(f"✅ 노션 기록 완료: {result['url']}")
    print(f"   DB: {db_conf['name']} ({db_key})")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="자비스 작업 로그를 노션에 기록")
    parser.add_argument("title")
    parser.add_argument("category")
    parser.add_argument("subcategory")
    parser.add_argument("summary")
    parser.add_argument("--aha", action="store_true", help="아하 포인트 콜아웃 추가")
    parser.add_argument(
        "--db",
        choices=["ops", "decision", "knowledge", "trade"],
        help="라우팅 DB 강제 지정 (기본: 자동)",
    )
    args = parser.parse_args()

    add_log(
        title=args.title,
        category=args.category,
        subcategory=args.subcategory,
        summary=args.summary,
        is_aha=args.aha,
        db_override=args.db,
    )
