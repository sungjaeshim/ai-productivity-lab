#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

SEOUL = timezone(timedelta(hours=9))
DATA_DIR = Path("/root/.openclaw/workspace/data")


def kst_today() -> str:
    return datetime.now(SEOUL).strftime("%Y-%m-%d")


def choose_title(item: dict[str, Any]) -> str:
    title = str(item.get("title", "")).strip()
    if title:
        return title
    summary = str(item.get("summary", "")).strip()
    return summary or "제목 없음"


def compress_title(title: str, max_len: int = 88) -> str:
    return title if len(title) <= max_len else title[: max_len - 1] + "…"


def niche_label(niche: str) -> str:
    return {
        "trading": "시장",
        "ai_tech": "AI",
        "marketing": "마케팅",
    }.get(niche, niche or "기타")


def bucket_signal(score: int) -> str:
    if score >= 78:
        return "high"
    if score >= 68:
        return "mid"
    return "low"


def extract_lines(items: list[dict[str, Any]], count: int) -> list[str]:
    lines: list[str] = []
    for item in items[:count]:
        title = compress_title(choose_title(item), 96)
        niche = niche_label(str((item.get("niches") or [""])[0]))
        score = int(item.get("importance_score", 0) or 0)
        lines.append(f"[{niche}] {title} ({score})")
    return lines


def build_payload(raw: dict[str, Any], date_kst: str) -> dict[str, Any]:
    top_headlines = list(raw.get("top_headlines") or [])
    signals = list((raw.get("signal_noise") or {}).get("signals") or [])
    by_niche = dict(raw.get("by_niche") or {})

    trading_items = list(by_niche.get("trading") or [])
    ai_items = list(by_niche.get("ai_tech") or [])
    marketing_items = list(by_niche.get("marketing") or [])

    dominant_signal = "low"
    if signals:
        dominant_signal = bucket_signal(
            max(int(item.get("importance_score", 0) or 0) for item in signals)
        )

    market_lines = extract_lines(trading_items or top_headlines, 3)
    ai_lines = extract_lines(ai_items, 2)
    marketing_lines = extract_lines(marketing_items, 2)

    brief_lines = [
        f"📡 Daily Intelligence Source | {date_kst}",
        f"- headlines={len(top_headlines)} signals={len(signals)} dominant_signal={dominant_signal}",
    ]
    brief_lines.extend(f"- {line}" for line in market_lines[:2])

    return {
        "generated_at": datetime.now(SEOUL).isoformat(timespec="seconds"),
        "date_kst": date_kst,
        "status": "ok",
        "source_file": str(DATA_DIR / f"intelligence-{date_kst}.json"),
        "purpose": "morning-briefing-source",
        "should_send": False,
        "send_reason": "source-only",
        "headline_count": len(top_headlines),
        "signal_count": len(signals),
        "dominant_signal": dominant_signal,
        "market_lines": market_lines,
        "ai_lines": ai_lines,
        "marketing_lines": marketing_lines,
        "top_signal_titles": extract_lines(signals, 5),
        "brief_text": "\n".join(brief_lines),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--date", default=kst_today())
    args = parser.parse_args()

    date_kst = args.date
    source_path = DATA_DIR / f"intelligence-{date_kst}.json"
    out_path = DATA_DIR / f"daily-intelligence-payload-{date_kst}.json"

    if not source_path.exists():
        raise SystemExit(f"DAILY_INTEL_PAYLOAD_ERROR: missing source file: {source_path}")

    raw = json.loads(source_path.read_text(encoding="utf-8"))
    payload = build_payload(raw, date_kst)
    out_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(str(out_path))
    print(f"DAILY_INTEL_PAYLOAD_OK {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
