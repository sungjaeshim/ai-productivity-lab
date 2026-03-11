#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

LEARNING_DUE_SCRIPT = Path("/root/.openclaw/workspace/scripts/learning/get-due-reviews.js")

SEOUL = timezone(timedelta(hours=9))
ROOT = Path("/root/.openclaw/workspace")
DATA_DIR = ROOT / "data"
MEMORY_DIR = ROOT / "memory"

TELEGRAM_TARGET = "62403941"
DISCORD_TARGET = "1477462915509387314"
NAVER_SCRIPT = ROOT / "scripts" / "naver_news_brief.py"

WEEKDAYS_KO = ["월", "화", "수", "목", "금", "토", "일"]


def kst_today() -> str:
    return datetime.now(SEOUL).strftime("%Y-%m-%d")


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def trim(text: str, max_len: int = 72) -> str:
    text = re.sub(r"\s+", " ", text).strip()
    return text if len(text) <= max_len else text[: max_len - 1] + "…"


def summarize_failure_text(text: str) -> str:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines:
        return "unknown error"
    for line in reversed(lines):
        lowered = line.lower()
        if "temporary failure in name resolution" in lowered:
            return "network dns failure"
        if "name or service not known" in lowered:
            return "network dns failure"
        if "failed to establish a new connection" in lowered:
            return "network connection failed"
        if "connection timed out" in lowered or "timed out" in lowered:
            return "network timeout"
        if "error" in lowered or "failed" in lowered or "exception" in lowered:
            return trim(line, 48)
    return trim(lines[-1], 48)


def top_insights(date_kst: str) -> list[str]:
    insights_path = MEMORY_DIR / "insights.json"
    if not insights_path.exists():
        return [
            "오늘 추출된 인사이트 없음",
            "추가 인사이트 없음",
            "추가 인사이트 없음",
        ]

    data = json.loads(insights_path.read_text(encoding="utf-8"))
    matched = next((entry for entry in data if entry.get("date") == date_kst), None)
    raw_items = list((matched or {}).get("insights") or [])
    raw_items.sort(key=lambda item: float(item.get("importance", 0) or 0), reverse=True)

    picked: list[str] = []
    seen: set[str] = set()
    for item in raw_items:
        insight = trim(str(item.get("insight", "")).strip(), 80)
        if not insight:
            continue
        key = insight.lower()
        if key in seen:
            continue
        seen.add(key)
        picked.append(insight)
        if len(picked) == 3:
            break

    if not picked:
        picked.append("오늘 추출된 인사이트 없음")

    while len(picked) < 3:
        picked.append("추가 인사이트 없음")
    return picked[:3]


def run_naver_top3() -> list[str]:
    if not NAVER_SCRIPT.exists():
        return ["[NAVER] 국내뉴스 스크립트 없음"]

    try:
        proc = subprocess.run(
            ["python3", str(NAVER_SCRIPT), "--top", "6", "--no-dedupe-check"],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
    except Exception as exc:
        return [f"[NAVER] 수집 실패: {trim(str(exc), 48)}"]

    if proc.returncode != 0:
        raw = proc.stderr.strip() or proc.stdout.strip() or f"exit={proc.returncode}"
        return [f"[NAVER] 수집 실패: {summarize_failure_text(raw)}"]

    lines: list[str] = []
    for raw in proc.stdout.splitlines():
        stripped = raw.strip()
        if not stripped:
            continue
        if not stripped[0].isdigit():
            continue
        title = re.sub(r"^[0-9]+[^\s]*\s*", "", stripped)
        lines.append(f"[NAVER] {trim(title, 84)}")
        if len(lines) == 3:
            break

    return lines or ["[NAVER] 국내뉴스 없음"]


def safe_get_title(line: str, fallback: str) -> str:
    if line:
        return trim(line, 96)
    return fallback


def get_learning_review(date_kst: str) -> dict[str, Any]:
    if not LEARNING_DUE_SCRIPT.exists():
        return {"count": 0, "items": [], "briefing": "", "status": "script-missing"}

    now_kst = datetime.now(SEOUL).isoformat(timespec="seconds")
    try:
        proc = subprocess.run(
            [
                "node",
                str(LEARNING_DUE_SCRIPT),
                "--limit",
                "3",
                "--now",
                now_kst,
            ],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
    except Exception as exc:
        return {"count": 0, "items": [], "briefing": f"Learning Review 조회 실패: {trim(str(exc), 64)}", "status": "error"}

    if proc.returncode != 0:
        raw = proc.stderr.strip() or proc.stdout.strip() or f"exit={proc.returncode}"
        return {"count": 0, "items": [], "briefing": f"Learning Review 조회 실패: {summarize_failure_text(raw)}", "status": "error"}

    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {"count": 0, "items": [], "briefing": "Learning Review 조회 실패: invalid json", "status": "error"}

    items = list(payload.get("items") or [])[:3]
    return {
        "count": len(items),
        "items": items,
        "briefing": str(payload.get("briefing") or "").strip(),
        "status": "ok",
    }


def display_value(value: Any, suffix: str = "") -> str:
    if value is None:
        return "N/A"
    text = str(value).strip()
    if not text or text.lower() == "none":
        return "N/A"
    return f"{text}{suffix}"


def build_sections(
    date_kst: str,
    context: dict[str, Any],
    intel_payload: dict[str, Any],
    naver_lines: list[str],
    insights: list[str],
    learning_review: dict[str, Any],
) -> dict[str, Any]:
    now = datetime.now(SEOUL)
    weekday = WEEKDAYS_KO[now.weekday()]
    weather = dict((context.get("weather") or {}).get("data") or {})
    tasks = list((context.get("tasks") or {}).get("data") or [])
    task_status = str((context.get("tasks") or {}).get("status", "unknown"))
    yesterday_summary = dict(context.get("yesterday_summary") or {})

    market_lines = list(intel_payload.get("market_lines") or [])
    top_signal_titles = list(intel_payload.get("top_signal_titles") or [])

    top_task_lines = [trim(str(item.get("task", "")).strip(), 60) for item in tasks[:3]]
    while len(top_task_lines) < 3:
        top_task_lines.append("추가 작업 없음")

    summary_line = top_task_lines[0]
    yesterday_facts = [trim(str(item).strip(), 88) for item in list(yesterday_summary.get("facts") or []) if str(item).strip()]
    yesterday_sentence = trim(str(yesterday_summary.get("sentence", "")).strip(), 120)
    yesterday = yesterday_sentence or trim(str(yesterday_summary.get("data", "")).strip(), 96)
    nq_status = str((context.get("nq") or {}).get("status", "pending"))
    nq_note = trim(str((context.get("nq") or {}).get("note", "NQ signal check by cron")), 44)

    market_1 = safe_get_title(market_lines[0] if len(market_lines) > 0 else "", "시장 헤드라인 부족")
    market_2 = safe_get_title(market_lines[1] if len(market_lines) > 1 else "", "추가 시장 시그널 없음")
    market_3 = safe_get_title(
        top_signal_titles[0] if len(top_signal_titles) > 0 else "",
        "중요도 상위 시그널 없음",
    )

    risk_lines = []
    if naver_lines and "수집 실패" in naver_lines[0]:
        risk_lines.append(f"• Mid: {naver_lines[0]} | 조치: fallback 유지")
    risk_lines.append("• Low: NQ 카드 값은 별도 MACD cron 의존 | 조치: pending 표기 유지")
    risk_lines.append("• Low: Daily Intelligence는 source-only 운영 | 조치: 모닝 브리핑에서 통합 사용")

    task_section_title = "📋 오늘 할 일 (3건)"
    if task_status == "fallback":
        task_section_title = "📋 오늘 체크포인트 (3건)"

    learning_items = list(learning_review.get("items") or [])[:3]
    learning_lines = []
    for item in learning_items:
        review_type = str(item.get("review_type", "?")).upper()
        mode = str(item.get("mode", "review"))
        title = trim(str(item.get("title", item.get("card_id", "(untitled)"))), 72)
        summary = trim(str(item.get("summary", "")).strip(), 88)
        line = f"[{review_type}][{mode}] {title}"
        if summary:
            line += f" | {summary}"
        learning_lines.append(line)

    return {
        "headline": f"🌅 모닝 브리핑 | {date_kst} ({weekday}) {now.strftime('%H:%M')} KST",
        "summary_line": f"오늘 1순위는 {summary_line}",
        "weather_title": "🌤️ 오늘 날씨",
        "weather_lines": [
            f"• 현재: {display_value(weather.get('temp'), '°C')} (체감 {display_value(weather.get('feel'), '°C')}) | {display_value(weather.get('condition'))}",
            f"• 최고: {display_value(weather.get('high'), '°C')} / 최저: {display_value(weather.get('low'), '°C')}",
        ],
        "task_section_title": task_section_title,
        "task_status": task_status,
        "tasks": top_task_lines,
        "daily_title": "📡 Daily Intelligence 핵심",
        "daily_lines": [market_1, market_2, market_3],
        "insight_title": "🧠 오늘 인사이트 Top3",
        "insight_lines": insights,
        "learning_review_title": "🧠 Learning Review",
        "learning_review_count": learning_review.get("count", 0),
        "learning_review_status": learning_review.get("status", "unknown"),
        "learning_review_lines": learning_lines,
        "hq_cards": [
            {
                "title": "시장/시그널",
                "bullets": [
                    f"NQ: {nq_status} | {nq_note}",
                    f"매크로: {market_1}",
                    f"중요 뉴스: {market_2}",
                    *naver_lines[:3],
                ],
            },
            {
                "title": "프로젝트 헬스",
                "bullets": [
                    "Growth: 모닝/데일리 payload 분리 구조 반영 단계",
                    "SecondBrain: insights.json 기반 Top3 공급 가능",
                    "CEO: 자동화 구조 정리 진행",
                    "MACD: shadow 관측 유지, 전환 전 검증 모드",
                ],
            },
            {
                "title": "리스크/장애",
                "bullets": [line[2:] if line.startswith("• ") else line for line in risk_lines],
            },
            {
                "title": "오늘 의사결정 필요",
                "bullets": [
                    "오늘 1순위 집중 대상 | A. 핵심 1건 먼저 (권장) / B. 여러 건 분산 착수",
                    "Daily Intelligence 직접 발송 여부 | A. source-only 유지 (권장) / B. 별도 브리핑 발송",
                    "NQ 카드 데이터 연결 수준 | A. pending 유지 (권장) / B. MACD 결과 직접 주입",
                ],
            },
            {
                "title": "오늘 단일 핵심 액션",
                "bullets": [
                    f"{summary_line}부터 처리하고, 끝나면 MACD shadow 결과까지 이어서 확인하기",
                ],
            },
        ],
        "yesterday_summary": yesterday or "요약 없음",
        "yesterday_summary_facts": yesterday_facts,
    }


def build_body(sections: dict[str, Any]) -> str:
    body_lines = [
        sections["headline"],
        "",
        f"한 줄 요약: {sections['summary_line']}",
        "",
        "━━━━━━━━━━━━━━━━━━",
        sections["weather_title"],
        *sections["weather_lines"],
        "",
        "━━━━━━━━━━━━━━━━━━",
        sections["task_section_title"],
        f"1. {sections['tasks'][0]}",
        f"2. {sections['tasks'][1]}",
        f"3. {sections['tasks'][2]}",
        "",
        "━━━━━━━━━━━━━━━━━━",
        sections["daily_title"],
        f"• {sections['daily_lines'][0]}",
        f"• {sections['daily_lines'][1]}",
        f"• {sections['daily_lines'][2]}",
        "",
        "━━━━━━━━━━━━━━━━━━",
        sections["insight_title"],
        f"1. {sections['insight_lines'][0]}",
        f"2. {sections['insight_lines'][1]}",
        f"3. {sections['insight_lines'][2]}",
        "",
        "━━━━━━━━━━━━━━━━━━",
        sections["learning_review_title"],
    ]

    if sections.get("learning_review_lines"):
        body_lines.extend(f"• {line}" for line in sections["learning_review_lines"])
    else:
        body_lines.append("• 오늘 due review 없음")

    body_lines.extend(
        [
            "",
            "━━━━━━━━━━━━━━━━━━",
            "🏢 HQ 카드",
            "",
        ]
    )
    for card in sections["hq_cards"]:
        body_lines.append(f"[Card] {card['title']}")
        body_lines.extend(f"• {bullet}" for bullet in card["bullets"])
        body_lines.append("")

    body_lines.extend(
        [
            "━━━━━━━━━━━━━━━━━━",
            f"어제 요약: {sections['yesterday_summary']}",
        ]
    )
    return "\n".join(body_lines).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--date", default=kst_today())
    args = parser.parse_args()

    date_kst = args.date
    context_path = DATA_DIR / f"morning-context-{date_kst}.json"
    intel_payload_path = DATA_DIR / f"daily-intelligence-payload-{date_kst}.json"
    out_json = DATA_DIR / f"morning-briefing-payload-{date_kst}.json"
    out_body = DATA_DIR / f"morning-briefing-body-{date_kst}.txt"

    if not context_path.exists():
        raise SystemExit(f"MORNING_BRIEFING_PAYLOAD_ERROR: missing source file: {context_path}")
    if not intel_payload_path.exists():
        raise SystemExit(f"MORNING_BRIEFING_PAYLOAD_ERROR: missing source file: {intel_payload_path}")

    context = load_json(context_path)
    intel_payload = load_json(intel_payload_path)
    naver_lines = run_naver_top3()
    insights = top_insights(date_kst)
    learning_review = get_learning_review(date_kst)
    sections = build_sections(date_kst, context, intel_payload, naver_lines, insights, learning_review)
    body = build_body(sections)

    out_body.write_text(body, encoding="utf-8")
    payload = {
        "generated_at": datetime.now(SEOUL).isoformat(timespec="seconds"),
        "date_kst": date_kst,
        "status": "ok",
        "style_mode": "hybrid-agent-final",
        "voice_constraints": [
            "결론과 핵심을 먼저 말할 것",
            "자연스러운 한국어로 연결감을 줄 것",
            "과한 개발/운영 용어는 사용자 가치가 있을 때만 남길 것",
            "payload에 없는 사실은 추가하지 말 것",
            "카드 구조는 유지하되 문장은 덜 기계적으로 다듬을 것",
        ],
        "source_files": {
            "morning_context": str(context_path),
            "daily_intelligence_payload": str(intel_payload_path),
            "insights": str(MEMORY_DIR / "insights.json"),
        },
        "targets": {
            "telegram": TELEGRAM_TARGET,
            "discord": DISCORD_TARGET,
        },
        "naver_lines": naver_lines,
        "insight_lines": insights,
        "learning_review": learning_review,
        "sections": sections,
        "draft_body_path": str(out_body),
        "draft_body": body,
        "body_path": str(out_body),
        "body": body,
    }
    out_json.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(str(out_json))
    print(f"MORNING_BRIEFING_PAYLOAD_OK {out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
