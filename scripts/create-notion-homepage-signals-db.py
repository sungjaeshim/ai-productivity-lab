#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
import urllib.request
from pathlib import Path
from typing import Any

WORKSPACE_DIR = Path(__file__).resolve().parent.parent
ENV_FILES = [
    Path(os.environ.get("OPENCLAW_ENV_FILE", "/root/.openclaw/.env")).expanduser(),
    WORKSPACE_DIR / ".env",
]
NOTION_VERSION = "2025-09-03"


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


def rich_text(value: str) -> list[dict[str, Any]]:
    return [{"type": "text", "text": {"content": value}}]


def main() -> None:
    load_env_files()
    token = resolve_token()
    source_db = os.environ.get("NOTION_KNOWLEDGE_CARDS_DB", "").strip()
    if not source_db:
        fail("NOTION_KNOWLEDGE_CARDS_DB is not set.")

    source = notion_request(token, f"https://api.notion.com/v1/databases/{source_db}")
    parent = source.get("parent") or {}
    page_id = parent.get("page_id")
    if not page_id:
        fail("Could not resolve parent page_id from the existing Knowledge Cards database.")

    payload = {
        "parent": {"type": "page_id", "page_id": page_id},
        "title": rich_text("Homepage Signals"),
        "description": rich_text("Curated homepage signal cards for AI Snowball."),
        "icon": {"type": "emoji", "emoji": "📡"},
        "initial_data_source": {
            "title": rich_text("Homepage Signals"),
            "properties": {
                "Title": {"title": {}},
                "Summary": {"rich_text": {}},
                "Href": {"url": {}},
                "Category": {
                    "select": {
                        "options": [
                            {"name": "Platform", "color": "blue"},
                            {"name": "Brand", "color": "orange"},
                            {"name": "Guide", "color": "green"},
                            {"name": "Update", "color": "purple"},
                        ]
                    }
                },
                "State": {
                    "select": {
                        "options": [
                            {"name": "Draft", "color": "gray"},
                            {"name": "Published", "color": "green"},
                            {"name": "Archived", "color": "red"},
                        ]
                    }
                },
                "Updated_At": {"date": {}},
                "Sort": {"number": {"format": "number"}},
            },
        },
    }

    created = notion_request(token, "https://api.notion.com/v1/databases", method="POST", payload=payload)
    data_sources = created.get("data_sources") or []
    print(
        json.dumps(
            {
                "database_id": created.get("id", ""),
                "data_source_id": data_sources[0].get("id", "") if data_sources else "",
                "url": created.get("url", ""),
                "parent_page_id": page_id,
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
