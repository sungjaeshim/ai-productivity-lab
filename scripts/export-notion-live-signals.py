#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any

WORKSPACE_DIR = Path(__file__).resolve().parent.parent
OUTPUT_SRC = WORKSPACE_DIR / "src/data/live-signals.json"
OUTPUT_PUBLIC = WORKSPACE_DIR / "public/data/live-signals-source.json"
NOTION_VERSION = "2025-09-03"
ENV_FILES = [
    Path(os.environ.get("OPENCLAW_ENV_FILE", "/root/.openclaw/.env")).expanduser(),
    WORKSPACE_DIR / ".env",
]


def fail(message: str, code: int = 1) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(code)


def load_env_files() -> None:
    for env_path in ENV_FILES:
        try:
            raw = env_path.read_text(encoding="utf-8")
        except FileNotFoundError:
            continue

        for line in raw.splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#") or "=" not in stripped:
                continue
            if stripped.startswith("export "):
                stripped = stripped[7:].strip()
            key, value = stripped.split("=", 1)
            key = key.strip()
            if not key or key in os.environ:
                continue
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
                value = value[1:-1]
            os.environ[key] = value


def resolve_token() -> str:
    key_file = Path(os.environ.get("NOTION_API_KEY_FILE", "~/.config/notion/api_key")).expanduser()
    if key_file.is_file():
        token = key_file.read_text(encoding="utf-8").strip()
        if token:
            return token
    for name in ("NOTION_TOKEN", "NOTION_API_TOKEN", "NOTION_INTEGRATION_TOKEN"):
        token = os.environ.get(name, "").strip()
        if token:
            return token
    fail("Notion token not found.")


def notion_request(
    token: str,
    url: str,
    *,
    method: str = "GET",
    payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    data = None
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Authorization": f"Bearer {token}",
            "Notion-Version": NOTION_VERSION,
            "Content-Type": "application/json",
        },
        method=method,
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def find_prop(props: dict[str, Any], names: list[str], ptype: str | None = None) -> str | None:
    lowered = {k.lower(): k for k in props.keys()}
    for name in names:
        actual = lowered.get(name.lower())
        if actual is None:
            continue
        if ptype and props[actual].get("type") != ptype:
            continue
        return actual
    return None


def resolve_database(token: str, database_id: str) -> tuple[dict[str, str], dict[str, Any], str]:
    db = notion_request(token, f"https://api.notion.com/v1/databases/{database_id}")
    props = db.get("properties") or {}
    if props:
        return {"database_id": database_id}, props, f"https://api.notion.com/v1/databases/{database_id}/query"

    data_sources = db.get("data_sources") or []
    if not data_sources:
        fail("Notion database has no properties and no data sources.")
    ds_id = data_sources[0].get("id")
    if not ds_id:
        fail("Notion database data source id missing.")
    ds = notion_request(token, f"https://api.notion.com/v1/data_sources/{ds_id}")
    props = ds.get("properties") or {}
    if not props:
        fail("Notion data source returned no properties.")
    return {"data_source_id": ds_id}, props, f"https://api.notion.com/v1/data_sources/{ds_id}/query"


def resolve_database_id() -> str:
    for key in ("LIVE_SIGNALS_NOTION_DB", "NOTION_KNOWLEDGE_CARDS_DB", "NOTION_DATABASE_ID"):
        value = os.environ.get(key, "").strip()
        if value:
            return value
    fail("Set LIVE_SIGNALS_NOTION_DB or NOTION_KNOWLEDGE_CARDS_DB.")


def rich_text_plain(value: list[dict[str, Any]] | None) -> str:
    if not value:
        return ""
    return "".join(item.get("plain_text", "") for item in value).strip()


def title_plain(prop: dict[str, Any]) -> str:
    return rich_text_plain(prop.get("title"))


def property_plain(prop: dict[str, Any]) -> str:
    ptype = prop.get("type")
    if ptype == "title":
        return title_plain(prop)
    if ptype == "rich_text":
        return rich_text_plain(prop.get("rich_text"))
    if ptype == "url":
        return str(prop.get("url") or "").strip()
    if ptype == "select":
        selected = prop.get("select") or {}
        return str(selected.get("name") or "").strip()
    if ptype == "multi_select":
        return ", ".join(str(item.get("name") or "").strip() for item in prop.get("multi_select") or [] if item.get("name"))
    if ptype == "date":
        date = prop.get("date") or {}
        return str(date.get("start") or "").strip()
    if ptype == "status":
        selected = prop.get("status") or {}
        return str(selected.get("name") or "").strip()
    if ptype == "formula":
        formula = prop.get("formula") or {}
        if formula.get("type") == "string":
            return str(formula.get("string") or "").strip()
    return ""


def normalize_date(value: str) -> str:
    value = (value or "").strip()
    if not value:
        return ""
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).date().isoformat()
    except Exception:
        return value[:10]


def include_page(properties: dict[str, Any], props_schema: dict[str, Any]) -> bool:
    state_prop = find_prop(props_schema, ["State", "state", "Status", "status"])
    state_value = property_plain(properties.get(state_prop, {})) if state_prop else ""
    allowed_state = os.environ.get("LIVE_SIGNALS_NOTION_STATE", "").strip()
    if allowed_state and state_value and state_value != allowed_state:
        return False

    tag_filter = os.environ.get("LIVE_SIGNALS_NOTION_TAG", "").strip()
    if tag_filter:
        tags_prop = find_prop(props_schema, ["Tags", "tags"])
        tags_value = property_plain(properties.get(tags_prop, {})) if tags_prop else ""
        tags = {part.strip() for part in tags_value.split(",") if part.strip()}
        if tag_filter not in tags:
            return False

    return True


def build_signal(page: dict[str, Any], props_schema: dict[str, Any]) -> dict[str, Any] | None:
    properties = page.get("properties") or {}
    if not include_page(properties, props_schema):
        return None

    title_prop = next((name for name, meta in props_schema.items() if meta.get("type") == "title"), None)
    title = title_plain(properties.get(title_prop, {})) if title_prop else ""
    if not title:
        return None

    summary_candidates = [
        ["Summary", "summary", "Description", "description"],
        ["Purpose", "purpose"],
        ["Subtitle", "subtitle"],
    ]
    summary = ""
    for candidates in summary_candidates:
        prop_name = find_prop(props_schema, candidates)
        summary = property_plain(properties.get(prop_name, {})) if prop_name else ""
        if summary:
            break
    if not summary:
        summary = title

    href_prop = find_prop(props_schema, ["Href", "href", "URL", "Url", "Link", "link"])
    href = property_plain(properties.get(href_prop, {})) if href_prop else ""
    if not href:
        href = str(page.get("url") or "/blog").strip()

    category_prop = find_prop(props_schema, ["Category", "category", "Type", "type", "Tag", "tag"])
    category = property_plain(properties.get(category_prop, {})) if category_prop else ""
    if not category:
        category = "Notion"

    sort_prop = find_prop(props_schema, ["Sort", "sort", "Order", "order"])
    sort_value = None
    if sort_prop:
        sort_prop_value = properties.get(sort_prop, {})
        if sort_prop_value.get("type") == "number":
            number = sort_prop_value.get("number")
            if isinstance(number, (int, float)):
                sort_value = int(number)
        elif sort_prop_value.get("type") == "formula":
            formula = sort_prop_value.get("formula") or {}
            if formula.get("type") == "number" and isinstance(formula.get("number"), (int, float)):
                sort_value = int(formula["number"])

    updated_prop = find_prop(props_schema, ["Updated_At", "updated_at", "Updated At", "Updated", "updated", "Published", "pubDate"])
    updated_at = normalize_date(property_plain(properties.get(updated_prop, {})) if updated_prop else "")
    if not updated_at:
        updated_at = normalize_date(page.get("last_edited_time", ""))

    page_id = str(page.get("id") or "").replace("-", "")

    return {
        "id": page_id or title.lower().replace(" ", "-"),
        "title": title,
        "summary": summary[:240],
        "href": href,
        "category": category,
        "updatedAt": updated_at,
        "sort": sort_value,
    }


def main() -> None:
    load_env_files()
    token = resolve_token()
    database_id = resolve_database_id()
    limit = int(os.environ.get("LIVE_SIGNALS_NOTION_LIMIT", "6"))

    _parent, props_schema, query_url = resolve_database(token, database_id)
    page_size = min(max(limit * 3, 10), 100)
    payload: dict[str, Any] = {"page_size": page_size}

    sorts: list[dict[str, str]] = []
    sort_prop = find_prop(props_schema, ["Sort", "sort", "Order", "order"])
    if sort_prop and props_schema.get(sort_prop, {}).get("type") in {"number", "formula"}:
        sorts.append({"property": sort_prop, "direction": "ascending"})
    updated_prop = find_prop(props_schema, ["Updated_At", "updated_at", "Updated At", "Updated", "updated"])
    if updated_prop:
        sorts.append({"property": updated_prop, "direction": "descending"})
    if sorts:
        payload["sorts"] = sorts

    result = notion_request(token, query_url, method="POST", payload=payload)
    pages = result.get("results") or []

    signals: list[dict[str, str]] = []
    for page in pages:
        signal = build_signal(page, props_schema)
        if signal:
            signals.append(signal)
        if len(signals) >= limit:
            break

    if not signals:
        fail("No live signals could be exported from Notion. Check DB schema or filters.")

    OUTPUT_SRC.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PUBLIC.parent.mkdir(parents=True, exist_ok=True)
    content = json.dumps(signals, ensure_ascii=False, indent=2) + "\n"
    OUTPUT_SRC.write_text(content, encoding="utf-8")
    OUTPUT_PUBLIC.write_text(content, encoding="utf-8")
    print(f"OK: exported {len(signals)} Notion live signals to {OUTPUT_SRC} and {OUTPUT_PUBLIC}")


if __name__ == "__main__":
    main()
