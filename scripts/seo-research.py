#!/usr/bin/env python3
"""seo-research.py

MVP SEO research preprocessor for blog generation.

Purpose:
- Turn a category + keyword into a structured JSON research brief
- Provide stable context for downstream LLM blog writing
- Work offline first (no external API dependency)

Example:
  python3 scripts/seo-research.py --category ai-tools --keyword "ai agents productivity"
  python3 scripts/seo-research.py --category trading --keyword "NQ futures trading strategy" --pretty
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

CATEGORY_DEFAULTS: dict[str, dict[str, Any]] = {
    "ai-tools": {
        "search_intent": "informational",
        "angle_template": "Practical 2026 workflow angle for {keyword}",
        "outline": [
            "Introduction",
            "What it is",
            "Why it matters in 2026",
            "Practical workflows and examples",
            "Best tools or stack choices",
            "Common mistakes",
            "Implementation checklist",
            "Conclusion",
        ],
        "faq_templates": [
            "What is {keyword}?",
            "How do you use {keyword} in real workflows?",
            "What are the best tools for {keyword}?",
            "What mistakes should beginners avoid with {keyword}?",
        ],
        "eeat_templates": [
            "Use hands-on workflow examples instead of generic tool summaries.",
            "Differentiate hype vs practical adoption with concrete criteria.",
            "Mention trade-offs: cost, setup complexity, and maintenance burden.",
        ],
        "cta_template": "Pick one workflow from this guide and test it for a week with {keyword} as the core variable.",
    },
    "trading": {
        "search_intent": "commercial_investigational",
        "angle_template": "Retail trader risk-managed angle for {keyword}",
        "outline": [
            "Introduction",
            "Market context and assumptions",
            "Core setup or strategy logic",
            "Entry and exit conditions",
            "Risk management rules",
            "Common failure modes",
            "Backtesting / validation ideas",
            "Conclusion",
        ],
        "faq_templates": [
            "Is {keyword} suitable for retail traders?",
            "What indicators are commonly paired with {keyword}?",
            "How should traders manage risk with {keyword}?",
            "What are common mistakes when using {keyword}?",
        ],
        "eeat_templates": [
            "Include explicit risk disclaimers and scenario boundaries.",
            "Separate setup logic from execution discipline and sizing rules.",
            "Explain where the setup fails, not just where it works.",
        ],
        "cta_template": "Before live trading, paper-test one rule set derived from {keyword} for at least 20 samples.",
    },
    "tech-tutorial": {
        "search_intent": "informational",
        "angle_template": "Step-by-step implementation angle for {keyword}",
        "outline": [
            "Introduction",
            "Prerequisites",
            "How it works",
            "Step-by-step implementation",
            "Testing and validation",
            "Troubleshooting",
            "Optimization tips",
            "Conclusion",
        ],
        "faq_templates": [
            "What do you need before starting with {keyword}?",
            "How long does it take to implement {keyword}?",
            "What are common errors in {keyword}?",
            "How do you validate {keyword} after setup?",
        ],
        "eeat_templates": [
            "Show exact prerequisites and expected outputs at each step.",
            "Include troubleshooting notes from realistic failure cases.",
            "Prefer reproducible commands and validation steps over abstract explanation.",
        ],
        "cta_template": "Implement the smallest working version of {keyword} first, then validate it with one real example.",
    },
}

GENERIC_INTERNAL_LINKS = {
    "ai-tools": [
        "Related AI workflow article",
        "Automation implementation guide",
        "Tool comparison post",
    ],
    "trading": [
        "Risk management guide",
        "Indicator comparison post",
        "Execution checklist article",
    ],
    "tech-tutorial": [
        "Setup prerequisite guide",
        "Troubleshooting article",
        "Implementation checklist post",
    ],
}

STOPWORDS = {
    "a", "an", "the", "for", "and", "or", "to", "of", "in", "on", "with",
    "how", "what", "why", "guide", "strategy", "complete", "best",
}


CATEGORY_SUFFIXES = {
    "ai-tools": ["workflow", "tools", "automation", "examples", "use cases"],
    "trading": ["risk management", "entry exit rules", "backtest", "indicators", "retail trader guide"],
    "tech-tutorial": ["tutorial", "setup", "example", "troubleshooting", "implementation"],
}


def slugify(text: str) -> str:
    text = text.strip().lower()
    text = re.sub(r"[^a-z0-9가-힣\s-]", "", text)
    text = re.sub(r"\s+", "-", text)
    text = re.sub(r"-+", "-", text)
    return text.strip("-")


def title_case_keyword(keyword: str) -> str:
    words = keyword.split()
    return " ".join(w.upper() if w.lower() in {"ai", "nq", "vwap", "macd", "orb"} else w.capitalize() for w in words)


def unique_keep_order(items: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for item in items:
        key = item.strip().lower()
        if not key or key in seen:
            continue
        seen.add(key)
        out.append(item.strip())
    return out


def extract_related_keywords(keyword: str, category: str) -> list[str]:
    base = [w for w in re.split(r"\s+", keyword.strip()) if w and w.lower() not in STOPWORDS]
    joined = " ".join(base) if base else keyword.strip()
    joined_lower = joined.lower()

    expansions: list[str] = [joined]
    for suffix in CATEGORY_SUFFIXES.get(category, []):
        suffix_lower = suffix.lower()
        if suffix_lower in joined_lower:
            continue
        expansions.append(f"{joined} {suffix}")

    return unique_keep_order(expansions)


def build_title_candidates(keyword: str, category: str) -> list[str]:
    k = title_case_keyword(keyword)
    if category == "ai-tools":
        return [
            f"{k}: A Practical 2026 Guide",
            f"How {k} Improves Real Workflows in 2026",
            f"{k} for Teams: Use Cases, Tools, and Pitfalls",
        ]
    if category == "trading":
        return [
            f"{k}: A Risk-Managed 2026 Guide for Retail Traders",
            f"How to Use {k} Without Blowing Up Your Risk Plan",
            f"{k} Explained: Setup Logic, Entries, Exits, and Mistakes",
        ]
    return [
        f"{k}: Step-by-Step Implementation Guide",
        f"How to Build {k} from Scratch",
        f"{k} Tutorial: Setup, Validation, and Troubleshooting",
    ]


def build_outline(keyword: str, category: str) -> list[str]:
    defaults = CATEGORY_DEFAULTS[category]["outline"]
    first = defaults[0]
    return [first] + [item.replace("{keyword}", keyword) for item in defaults[1:]]


def build_faq(keyword: str, category: str) -> list[str]:
    return [q.format(keyword=keyword) for q in CATEGORY_DEFAULTS[category]["faq_templates"]]


def build_eeat(category: str) -> list[str]:
    return list(CATEGORY_DEFAULTS[category]["eeat_templates"])


def build_notes_for_writer(keyword: str, category: str, audience: str) -> list[str]:
    notes = [
        f"Keep the article centered on the primary keyword: {keyword}.",
        "Prefer concrete examples and checklists over abstract explanation.",
        "Use a scannable structure suitable for downstream markdown publication.",
    ]
    if audience:
        notes.append(f"Target audience focus: {audience}.")
    if category == "trading":
        notes.append("Include a clear educational disclaimer; avoid promising returns.")
    if category == "ai-tools":
        notes.append("Differentiate automation hype from real operational fit.")
    if category == "tech-tutorial":
        notes.append("Include validation steps after the implementation section.")
    return notes


def make_brief(category: str, keyword: str, audience: str = "", lang: str = "en") -> dict[str, Any]:
    cfg = CATEGORY_DEFAULTS[category]
    related = extract_related_keywords(keyword, category)
    return {
        "keyword": keyword,
        "slug": slugify(keyword),
        "category": category,
        "language": lang,
        "audience": audience or None,
        "search_intent": cfg["search_intent"],
        "angle": cfg["angle_template"].format(keyword=keyword),
        "title_candidates": build_title_candidates(keyword, category),
        "related_keywords": related,
        "outline": build_outline(keyword, category),
        "faq_candidates": build_faq(keyword, category),
        "eeat_points": build_eeat(category),
        "internal_link_candidates": GENERIC_INTERNAL_LINKS.get(category, []),
        "cta": cfg["cta_template"].format(keyword=keyword),
        "notes_for_writer": build_notes_for_writer(keyword, category, audience),
    }


def build_writer_brief(brief: dict[str, Any]) -> str:
    lines = [
        f"Primary keyword: {brief['keyword']}",
        f"Category: {brief['category']}",
        f"Language: {brief['language']}",
        f"Search intent: {brief['search_intent']}",
        f"Recommended angle: {brief['angle']}",
        "",
        "Title candidates:",
    ]
    lines.extend(f"- {item}" for item in brief["title_candidates"])
    lines.append("")
    lines.append("Related keywords:")
    lines.extend(f"- {item}" for item in brief["related_keywords"])
    lines.append("")
    lines.append("Suggested outline:")
    lines.extend(f"- {item}" for item in brief["outline"])
    lines.append("")
    lines.append("FAQ candidates:")
    lines.extend(f"- {item}" for item in brief["faq_candidates"])
    lines.append("")
    lines.append("E-E-A-T points:")
    lines.extend(f"- {item}" for item in brief["eeat_points"])
    lines.append("")
    lines.append("Internal link candidates:")
    lines.extend(f"- {item}" for item in brief["internal_link_candidates"])
    lines.append("")
    lines.append(f"CTA: {brief['cta']}")
    lines.append("")
    lines.append("Writer notes:")
    lines.extend(f"- {item}" for item in brief["notes_for_writer"])
    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate an MVP SEO research brief JSON for blog writing.")
    parser.add_argument("--category", choices=sorted(CATEGORY_DEFAULTS.keys()), required=True)
    parser.add_argument("--keyword", required=True)
    parser.add_argument("--audience", default="")
    parser.add_argument("--lang", default="en")
    parser.add_argument("--out", default="")
    parser.add_argument("--brief-out", default="")
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    brief = make_brief(
        category=args.category,
        keyword=args.keyword.strip(),
        audience=args.audience.strip(),
        lang=args.lang.strip() or "en",
    )

    output = json.dumps(brief, ensure_ascii=False, indent=2 if args.pretty or args.out else None)

    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(output + "\n", encoding="utf-8")
    else:
        print(output)

    if args.brief_out:
        brief_path = Path(args.brief_out)
        brief_path.parent.mkdir(parents=True, exist_ok=True)
        brief_path.write_text(build_writer_brief(brief), encoding="utf-8")


if __name__ == "__main__":
    main()
