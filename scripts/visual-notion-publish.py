#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import json
import os
import sys
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
import hashlib

NOTION_VERSION = "2025-09-03"
WORKSPACE_DIR = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT_DIR = WORKSPACE_DIR / "out"
DEFAULT_NOTION_KEY_FILE = Path(
    os.environ.get("NOTION_API_KEY_FILE", "~/.config/notion/api_key")
).expanduser()
ENV_FILES = [
    Path(os.environ.get("OPENCLAW_ENV_FILE", "/root/.openclaw/.env")).expanduser(),
    WORKSPACE_DIR / ".env",
]


def fail(message: str, code: int = 1) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(code)


def load_json_file(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"Meta file not found: {path}")
    except json.JSONDecodeError as exc:
        fail(f"Meta JSON parse failed at line {exc.lineno}, column {exc.colno}: {exc.msg}")

    if not isinstance(data, dict):
        fail("Meta file must contain a JSON object.")
    return data


def load_env_files() -> None:
    for env_path in ENV_FILES:
        try:
            raw = env_path.read_text(encoding="utf-8")
        except FileNotFoundError:
            continue

        for line in raw.splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            if stripped.startswith("export "):
                stripped = stripped[7:].strip()
            if "=" not in stripped:
                continue
            key, value = stripped.split("=", 1)
            key = key.strip()
            if not key or key in os.environ:
                continue
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
                value = value[1:-1]
            os.environ[key] = value


def require_string(meta: dict[str, Any], key: str) -> str:
    value = meta.get(key)
    if not isinstance(value, str) or not value.strip():
        fail(f"Meta field '{key}' must be a non-empty string.")
    return value.strip()


def require_string_list(meta: dict[str, Any], key: str) -> list[str]:
    value = meta.get(key)
    if not isinstance(value, list) or not value:
        fail(f"Meta field '{key}' must be a non-empty array of strings.")
    cleaned: list[str] = []
    for item in value:
        if not isinstance(item, str) or not item.strip():
            fail(f"Meta field '{key}' must contain only non-empty strings.")
        cleaned.append(item.strip())
    return cleaned


def optional_string_list(meta: dict[str, Any], key: str) -> list[str]:
    value = meta.get(key)
    if value is None:
        return []
    if not isinstance(value, list):
        fail(f"Meta field '{key}' must be an array of strings when provided.")
    cleaned: list[str] = []
    for item in value:
        if not isinstance(item, str) or not item.strip():
            fail(f"Meta field '{key}' must contain only non-empty strings.")
        cleaned.append(item.strip())
    return cleaned


def split_text(text: str, limit: int = 1800) -> list[str]:
    if not text:
        return [""]
    return [text[i : i + limit] for i in range(0, len(text), limit)]


def rich_text(text: str) -> list[dict[str, Any]]:
    return [{"type": "text", "text": {"content": chunk}} for chunk in split_text(text)]


def heading_block(text: str, level: int = 2) -> dict[str, Any]:
    key = f"heading_{level}"
    return {"object": "block", "type": key, key: {"rich_text": rich_text(text)}}


def paragraph_block(text: str) -> dict[str, Any]:
    return {"object": "block", "type": "paragraph", "paragraph": {"rich_text": rich_text(text)}}


def bullet_block(text: str) -> dict[str, Any]:
    return {
        "object": "block",
        "type": "bulleted_list_item",
        "bulleted_list_item": {"rich_text": rich_text(text)},
    }


def code_blocks(title: str, text: str) -> list[dict[str, Any]]:
    blocks = [heading_block(title)]
    for chunk in split_text(text):
        blocks.append(
            {
                "object": "block",
                "type": "code",
                "code": {"language": "plain text", "rich_text": rich_text(chunk)},
            }
        )
    return blocks


def callout_block(text: str) -> dict[str, Any]:
    return {
        "object": "block",
        "type": "callout",
        "callout": {"icon": {"emoji": "🗂️"}, "rich_text": rich_text(text)},
    }


def notion_request(
    url: str,
    token: str,
    *,
    method: str = "GET",
    payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    data = None
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")

    request = urllib.request.Request(
        url,
        data=data,
        headers={
            "Authorization": f"Bearer {token}",
            "Notion-Version": NOTION_VERSION,
            "Content-Type": "application/json",
        },
        method=method,
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def notion_create_page(token: str, payload: dict[str, Any]) -> dict[str, Any]:
    try:
        return notion_request("https://api.notion.com/v1/pages", token, method="POST", payload=payload)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="ignore")
        body_json: dict[str, Any] | None = None
        if body:
            try:
                body_json = json.loads(body)
            except json.JSONDecodeError:
                body_json = None

        try:
            error_type = (body_json or {}).get("additional_data", {}).get("error_type")
            child_ids = (body_json or {}).get("additional_data", {}).get("child_data_source_ids") or []
            has_db_parent = "database_id" in payload.get("parent", {})
            if (
                exc.code == 400
                and error_type == "multiple_data_sources_for_database"
                and child_ids
                and has_db_parent
            ):
                retry_payload = copy.deepcopy(payload)
                retry_payload["parent"] = {"data_source_id": child_ids[0]}
                return notion_request(
                    "https://api.notion.com/v1/pages",
                    token,
                    method="POST",
                    payload=retry_payload,
                )
        except Exception:
            pass

        detail = body.strip() if body else exc.reason
        fail(f"Notion page create failed: HTTP {exc.code} {detail}")


def resolve_token() -> str:
    if DEFAULT_NOTION_KEY_FILE.is_file():
        token = DEFAULT_NOTION_KEY_FILE.read_text(encoding="utf-8").strip()
        if token:
            return token
        fail(f"Notion API key file is empty: {DEFAULT_NOTION_KEY_FILE}")

    for env_name in ("NOTION_TOKEN", "NOTION_API_TOKEN", "NOTION_INTEGRATION_TOKEN"):
        token = os.environ.get(env_name, "").strip()
        if token:
            return token

    fail(
        "No Notion token found. Provide NOTION_API_KEY_FILE/ ~/.config/notion/api_key "
        "or set NOTION_TOKEN / NOTION_API_TOKEN / NOTION_INTEGRATION_TOKEN."
    )


def find_prop(
    props: dict[str, Any],
    candidates: list[str],
    expected_type: str | None = None,
) -> str | None:
    lowered = {name.lower(): name for name in props.keys()}
    for candidate in candidates:
        actual = lowered.get(candidate.lower())
        if actual is None:
            continue
        if expected_type and props[actual].get("type") != expected_type:
            continue
        return actual
    return None


def resolve_database_id(cli_value: str | None, meta_value: str | None) -> str:
    if cli_value:
        return cli_value

    if isinstance(meta_value, str) and meta_value.strip():
        candidate = meta_value.strip()
        if candidate.startswith("env:"):
            env_name = candidate[4:]
            env_value = os.environ.get(env_name, "").strip()
            if not env_value:
                fail(f"Meta notionDatabase points to missing env var: {env_name}")
            return env_value
        return candidate

    env_value = os.environ.get("NOTION_KNOWLEDGE_CARDS_DB", "").strip()
    if env_value:
        return env_value

    fail("No Notion database configured. Use --database, meta.notionDatabase, or NOTION_KNOWLEDGE_CARDS_DB.")


def resolve_parent_and_properties(token: str, database_id: str) -> tuple[dict[str, str], dict[str, Any]]:
    try:
        database = notion_request(f"https://api.notion.com/v1/databases/{database_id}", token)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="ignore")
        fail(f"Notion database fetch failed: HTTP {exc.code} {body or exc.reason}")
    except Exception as exc:
        fail(f"Notion database fetch failed: {exc}")

    props = database.get("properties") or {}
    if props:
        return {"database_id": database_id}, props

    data_sources = database.get("data_sources") or []
    if not data_sources:
        fail("Notion database has no properties and no data sources.")

    data_source_id = data_sources[0].get("id")
    if not data_source_id:
        fail("Notion data source id missing from database response.")

    try:
        data_source = notion_request(f"https://api.notion.com/v1/data_sources/{data_source_id}", token)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="ignore")
        fail(f"Notion data source fetch failed: HTTP {exc.code} {body or exc.reason}")
    except Exception as exc:
        fail(f"Notion data source fetch failed: {exc}")

    props = data_source.get("properties") or {}
    if not props:
        fail("Notion data source returned no properties.")

    return {"data_source_id": data_source_id}, props


def build_properties(
    props: dict[str, Any],
    title: str,
    subtitle: str,
    purpose: str,
    tags: list[str],
    source_ref: str,
    local_id: str,
    event_id: str,
) -> dict[str, Any]:
    properties: dict[str, Any] = {}

    title_prop = next((name for name, meta in props.items() if meta.get("type") == "title"), None)
    if not title_prop:
        fail("Notion target has no title property.")

    properties[title_prop] = {"title": [{"text": {"content": title[:1800]}}]}

    now_iso = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    rich_text_map = [
        (["Subtitle", "subtitle"], subtitle),
        (["Purpose", "purpose"], purpose),
        (["Local_ID", "local_id", "Local Id"], local_id),
        (["Event_ID", "event_id", "Event Id"], event_id),
        (["Source_Ref", "source_ref", "Source Ref"], source_ref),
    ]
    for candidates, value in rich_text_map:
        if not value:
            continue
        prop_name = find_prop(props, candidates, "rich_text")
        if prop_name:
            properties[prop_name] = {"rich_text": [{"text": {"content": value[:1800]}}]}

    updated_prop = find_prop(props, ["Updated_At", "updated_at", "Updated At"], "date")
    if updated_prop:
        properties[updated_prop] = {"date": {"start": now_iso}}

    state_prop = find_prop(props, ["State", "state"], "select")
    if state_prop:
        properties[state_prop] = {"select": {"name": "Inbox"}}

    type_prop = find_prop(props, ["Type", "type", "Kind", "kind"], "select")
    if type_prop:
        properties[type_prop] = {"select": {"name": "Visualization"}}

    tags_prop = find_prop(props, ["Tags", "tags"], "multi_select")
    if tags_prop and tags:
        properties[tags_prop] = {"multi_select": [{"name": tag[:100]} for tag in tags]}

    return properties


def find_existing_page(
    token: str,
    parent: dict[str, str],
    props: dict[str, Any],
    event_id: str,
) -> str | None:
    event_prop = find_prop(props, ["Event_ID", "event_id", "Event Id"], "rich_text")
    if not event_prop:
        return None

    if "data_source_id" in parent:
        query_url = f"https://api.notion.com/v1/data_sources/{parent['data_source_id']}/query"
    else:
        query_url = f"https://api.notion.com/v1/databases/{parent['database_id']}/query"

    try:
        result = notion_request(
            query_url,
            token,
            method="POST",
            payload={
                "page_size": 1,
                "filter": {
                    "property": event_prop,
                    "rich_text": {"equals": event_id},
                },
            },
        )
    except Exception:
        return None

    results = result.get("results") or []
    if not results:
        return None
    return results[0].get("url")


def artifact_info(mmd_path: Path, out_dir: Path) -> list[str]:
    items: list[str] = []
    for ext in ("png", "pdf", "svg"):
        artifact = out_dir / f"{mmd_path.stem}.{ext}"
        if artifact.exists():
            size = artifact.stat().st_size
            items.append(f"{ext.upper()}: {artifact} ({size} bytes)")
        else:
            items.append(f"{ext.upper()}: missing at {artifact}")
    return items


def build_children(
    meta: dict[str, Any],
    mmd_path: Path,
    source_text: str,
    out_dir: Path,
) -> list[dict[str, Any]]:
    children: list[dict[str, Any]] = []
    children.append(callout_block(meta["subtitle"]))
    children.append(heading_block("Purpose"))
    children.append(paragraph_block(meta["purpose"]))
    children.append(heading_block("Usage"))
    children.extend(bullet_block(item) for item in meta["usage"])
    children.append(heading_block("Example Questions"))
    children.extend(bullet_block(item) for item in meta["questions"])
    children.append(heading_block("Artifact Info"))
    children.append(bullet_block(f"Source file: {mmd_path}"))
    children.append(bullet_block(f"Output directory: {out_dir}"))
    children.extend(bullet_block(item) for item in artifact_info(mmd_path, out_dir))
    children.extend(code_blocks("Mermaid Source", source_text))
    return children


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Publish Mermaid visualization metadata and source into Notion."
    )
    parser.add_argument("mmd_file", help="Mermaid source file (.mmd)")
    parser.add_argument("meta_file", help="Visualization metadata JSON")
    parser.add_argument(
        "--database",
        help="Override target Notion database id",
    )
    parser.add_argument(
        "--out-dir",
        help=f"Artifact output directory (default: {DEFAULT_OUTPUT_DIR})",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    load_env_files()

    mmd_path = Path(args.mmd_file).expanduser().resolve()
    meta_path = Path(args.meta_file).expanduser().resolve()
    out_dir = Path(args.out_dir).expanduser().resolve() if args.out_dir else DEFAULT_OUTPUT_DIR.resolve()

    if not mmd_path.is_file():
        fail(f"Mermaid file not found: {mmd_path}")
    if not meta_path.is_file():
        fail(f"Meta file not found: {meta_path}")

    token = resolve_token()
    meta = load_json_file(meta_path)
    meta["title"] = require_string(meta, "title")
    meta["subtitle"] = require_string(meta, "subtitle")
    meta["purpose"] = require_string(meta, "purpose")
    meta["usage"] = require_string_list(meta, "usage")
    meta["questions"] = require_string_list(meta, "questions")
    meta["tags"] = optional_string_list(meta, "tags")

    notion_database = resolve_database_id(args.database, meta.get("notionDatabase"))
    parent, props = resolve_parent_and_properties(token, notion_database)
    source_text = mmd_path.read_text(encoding="utf-8")
    stable_seed = f"{mmd_path.resolve()}::{meta['title']}::{meta_path.resolve()}"
    stable_hash = hashlib.sha1(stable_seed.encode("utf-8")).hexdigest()[:12]
    local_id = f"visual_{stable_hash}"
    event_id = f"visual_{stable_hash}"

    existing_url = find_existing_page(token, parent, props, event_id)
    if existing_url:
        print(existing_url)
        return

    payload = {
        "parent": parent,
        "properties": build_properties(
            props,
            meta["title"],
            meta["subtitle"],
            meta["purpose"],
            meta["tags"],
            "scripts/visual-notion-publish.py",
            local_id,
            event_id,
        ),
        "children": build_children(meta, mmd_path, source_text, out_dir),
    }

    result = notion_create_page(token, payload)
    url = result.get("url")
    if not url:
        fail("Notion create succeeded but no page URL was returned.")
    print(url)


if __name__ == "__main__":
    main()
