#!/usr/bin/env python3
"""Generate a live/dormant/orphaned inventory for workspace scripts."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

WORKSPACE = Path("/root/.openclaw/workspace")
SCRIPTS_DIR = WORKSPACE / "scripts"
ATTIC_DIR = SCRIPTS_DIR / "_attic"
REGISTRY_PATH = SCRIPTS_DIR / "registry.yaml"
REPORT_JSON = WORKSPACE / "reports" / "script-inventory.json"
REPORT_MD = WORKSPACE / "docs" / "script-inventory.md"
SYSTEMD_DIR = Path("/root/.config/systemd/user")
HOOKS_DIR = Path("/root/.openclaw/hooks")
OPENCLAW_CONFIG = Path("/root/.openclaw/openclaw.json")
PAM_DIR = Path("/etc/pam.d")
CRON_DIR = Path("/etc/cron.d")
SYSTEM_CRON_FILES = [
    Path("/etc/crontab"),
    Path("/var/spool/cron/crontabs/root"),
]
TEXT_SUFFIXES = {
    ".md",
    ".json",
    ".jsonl",
    ".service",
    ".timer",
    ".sh",
    ".py",
    ".js",
    ".ts",
    ".yaml",
    ".yml",
}
SCRIPT_SUFFIXES = {".sh", ".py", ".js", ".ts"}
IGNORED_REFERENCE_FILES = {REGISTRY_PATH, REPORT_JSON, REPORT_MD}
IGNORED_REFERENCE_FILES.add(WORKSPACE / "docs" / "orphaned-scripts-review.md")


def load_registry() -> dict:
    if not REGISTRY_PATH.exists():
        return {"version": 1, "families": {}, "aliases": [], "known_missing_refs": []}
    return json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))


def iter_text_files(base: Path, recursive: bool = True, include_suffixless: bool = False) -> list[Path]:
    if not base.exists():
        return []
    iterator = base.rglob("*") if recursive else base.glob("*")
    files = []
    for path in iterator:
        if not path.is_file():
            continue
        if ATTIC_DIR in path.parents:
            continue
        if path in IGNORED_REFERENCE_FILES:
            continue
        if path.suffix.lower() in TEXT_SUFFIXES or path.name.endswith(".md") or (include_suffixless and not path.suffix):
            files.append(path)
    return sorted(files)


def discover_top_level_scripts() -> list[Path]:
    scripts = []
    for path in sorted(SCRIPTS_DIR.iterdir()):
        if not path.is_file():
            continue
        if path.name == "registry.yaml":
            continue
        if path.suffix.lower() in SCRIPT_SUFFIXES:
            scripts.append(path)
    return scripts


def build_family_maps(registry: dict) -> tuple[dict[str, str], dict[str, str]]:
    family_by_name: dict[str, str] = {}
    canonical_by_family: dict[str, str] = {}
    for family, meta in registry.get("families", {}).items():
        canonical = meta["canonical_entrypoint"]
        canonical_by_family[family] = canonical
        family_by_name[canonical] = family
        for member in meta.get("members", []):
            family_by_name[member] = family
    return family_by_name, canonical_by_family


def resolve_canonical(name: str, registry: dict, family_by_name: dict[str, str], canonical_by_family: dict[str, str]) -> str:
    family = family_by_name.get(name)
    if family:
        return canonical_by_family[family]
    for item in registry.get("aliases", []):
        if item["name"] == name:
            return item.get("canonical") or name
    return name


def build_override_lookup(registry: dict) -> dict[str, dict]:
    return {item["name"]: item for item in registry.get("overrides", [])}


def scan_mentions(names: set[str], files: list[Path]) -> dict[str, list[str]]:
    mentions = {name: [] for name in names}
    if not names or not files:
        return mentions
    pattern = re.compile("|".join(re.escape(name) for name in sorted(names, key=len, reverse=True)))
    for path in files:
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        found = {match.group(0) for match in pattern.finditer(text)}
        if not found:
            continue
        for name in found:
            mentions[name].append(str(path))
    return mentions


def scan_mentions_in_text(names: set[str], text: str, label: str) -> dict[str, list[str]]:
    mentions = {name: [] for name in names}
    if not names or not text:
        return mentions
    pattern = re.compile("|".join(re.escape(name) for name in sorted(names, key=len, reverse=True)))
    found = {match.group(0) for match in pattern.finditer(text)}
    for name in found:
        mentions[name].append(label)
    return mentions


def load_openclaw_cron_payloads(names: set[str]) -> tuple[str, dict[str, list[str]], dict[str, list[str]]]:
    mentions_all: dict[str, list[str]] = {}
    mentions_enabled: dict[str, list[str]] = {}
    try:
        proc = subprocess.run(
            ["openclaw", "cron", "list", "--json", "--all"],
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
    except (OSError, subprocess.TimeoutExpired):
        return "", mentions_all, mentions_enabled
    stdout = proc.stdout or ""
    try:
        payload = json.loads(stdout)
    except json.JSONDecodeError:
        return stdout, mentions_all, mentions_enabled
    jobs = payload.get("jobs", [])
    raw_parts = []
    for job in jobs:
        job_label = f"{job.get('name', job.get('id', 'cron-job'))} [{job.get('id', 'unknown')}]"
        job_text = json.dumps(job, ensure_ascii=False)
        raw_parts.append(job_text)
        target = mentions_enabled if job.get("enabled") else None
        for name in names:
            if name not in job_text:
                continue
            mentions_all.setdefault(name, []).append(job_label)
            if target is not None:
                target.setdefault(name, []).append(job_label)
    return "\n".join(raw_parts), mentions_all, mentions_enabled


def load_command_output(command: list[str], timeout: int = 15) -> str:
    try:
        proc = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return proc.stdout or ""


def mention_in_text(name: str, text: str, script_path: Path) -> bool:
    return name in text or str(script_path) in text


def status_for(
    name: str,
    is_canonical: bool,
    alias_status: str | None,
    override_status: str | None,
    active_refs: dict[str, list[str]],
    passive_refs: dict[str, list[str]],
) -> str:
    if alias_status == "compat":
        return "compat"
    if any(active_refs.values()):
        return "live"
    if override_status:
        return override_status
    if is_canonical:
        return "canonical"
    if any(passive_refs.values()):
        return "dormant"
    return "orphaned"


def to_markdown(report: dict) -> str:
    lines = [
        "# Script Inventory",
        "",
        f"Generated: `{report['generated_at']}`",
        "",
        "## Summary",
        "",
    ]
    for key, value in report["summary"].items():
        lines.append(f"- `{key}`: {value}")
    lines.extend(["", "## Canonical Entrypoints", ""])
    for family, meta in report["registry"]["families"].items():
        lines.append(f"- `{family}`: `{meta['canonical_entrypoint']}`")
    for section_name, desired_status in [
        ("Live", "live"),
        ("Canonical", "canonical"),
        ("Compat", "compat"),
        ("Keep", "keep"),
        ("Attic Candidate", "candidate"),
        ("Hold", "hold"),
        ("Dormant", "dormant"),
        ("Orphaned", "orphaned"),
    ]:
        entries = [entry for entry in report["scripts"] if entry["status"] == desired_status]
        lines.extend(["", f"## {section_name}", ""])
        if not entries:
            lines.append("_None_")
            continue
        lines.append("| Script | Family | Canonical | Signals |")
        lines.append("|---|---|---|---|")
        for entry in entries:
            signals = []
            if entry["active_refs"]["systemd"]:
                signals.append("systemd")
            if entry["active_refs"]["cron"]:
                signals.append("cron")
            if entry["active_refs"]["hooks"]:
                signals.append("hooks")
            if entry["active_refs"]["system"]:
                signals.append("system")
            if not signals:
                if entry["passive_refs"]["docs"]:
                    signals.append("docs")
                if entry["passive_refs"]["internal"]:
                    signals.append("internal")
            lines.append(
                f"| `{entry['name']}` | `{entry['family'] or '-'}` | `{entry['canonical']}` | {', '.join(signals) or '-'} |"
            )
    lines.extend(["", "## Retired Aliases", ""])
    if report["retired_aliases"]:
        lines.append("| Alias | Replacement | Attic | Mentioned |")
        lines.append("|---|---|---|---|")
        for item in report["retired_aliases"]:
            mentioned = len(item.get("mentioned_in", []))
            lines.append(
                f"| `{item['name']}` | `{item.get('canonical') or '-'}` | `{item.get('attic') or '-'}` | {mentioned} |"
            )
    else:
        lines.append("_None_")
    lines.extend(["", "## Known Missing Refs", ""])
    if report["known_missing_refs"]:
        lines.append("| Missing Name | Replacement | Mentioned | Notes |")
        lines.append("|---|---|---|---|")
        for item in report["known_missing_refs"]:
            lines.append(
                f"| `{item['name']}` | `{item.get('canonical') or '-'}` | {len(item.get('mentioned_in', []))} | {item.get('notes', '-')} |"
            )
    else:
        lines.append("_None_")
    return "\n".join(lines) + "\n"


def build_report() -> dict:
    registry = load_registry()
    scripts = discover_top_level_scripts()
    family_by_name, canonical_by_family = build_family_maps(registry)
    tracked_names = {path.name for path in scripts}
    tracked_names.update(item["name"] for item in registry.get("aliases", []))
    tracked_names.update(item["name"] for item in registry.get("known_missing_refs", []))

    docs_files = iter_text_files(WORKSPACE / "docs")
    docs_files.extend(path for path in WORKSPACE.glob("*.md") if path.is_file())
    memory_files = iter_text_files(WORKSPACE / "memory")
    systemd_files = iter_text_files(SYSTEMD_DIR, recursive=False)
    hook_files = iter_text_files(HOOKS_DIR)
    if OPENCLAW_CONFIG.exists():
        hook_files.append(OPENCLAW_CONFIG)
    system_files = iter_text_files(PAM_DIR, recursive=False, include_suffixless=True)
    system_files.extend(iter_text_files(CRON_DIR, recursive=False, include_suffixless=True))
    system_files.extend(path for path in SYSTEM_CRON_FILES if path.exists())
    internal_files = iter_text_files(SCRIPTS_DIR)

    doc_mentions = scan_mentions(tracked_names, docs_files)
    memory_mentions = scan_mentions(tracked_names, memory_files)
    systemd_mentions = scan_mentions(tracked_names, systemd_files)
    hook_mentions = scan_mentions(tracked_names, hook_files)
    system_mentions = scan_mentions(tracked_names, system_files)
    internal_mentions = scan_mentions(tracked_names, internal_files)
    cron_output, cron_all_mentions, cron_enabled_mentions = load_openclaw_cron_payloads(tracked_names)
    user_crontab_output = load_command_output(["crontab", "-l"])
    user_crontab_mentions = scan_mentions_in_text(tracked_names, user_crontab_output, "crontab -l")

    alias_lookup = {item["name"]: item for item in registry.get("aliases", [])}
    override_lookup = build_override_lookup(registry)

    entries = []
    for path in scripts:
        name = path.name
        canonical = resolve_canonical(name, registry, family_by_name, canonical_by_family)
        family = family_by_name.get(name)
        active_refs = {
            "systemd": sorted(systemd_mentions.get(name, [])),
            "cron": sorted(cron_enabled_mentions.get(name, [])),
            "hooks": sorted(hook_mentions.get(name, [])),
            "system": sorted(set(system_mentions.get(name, [])) | set(user_crontab_mentions.get(name, []))),
        }
        passive_refs = {
            "docs": sorted(set(doc_mentions.get(name, [])) | set(memory_mentions.get(name, []))),
            "internal": sorted(p for p in internal_mentions.get(name, []) if p != str(path)),
        }
        alias_status = alias_lookup.get(name, {}).get("status")
        override_status = override_lookup.get(name, {}).get("status")
        is_canonical = family is not None and canonical == name
        entries.append(
            {
                "name": name,
                "path": str(path),
                "modified_at": datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc).isoformat(),
                "family": family,
                "canonical": canonical,
                "status": status_for(name, is_canonical, alias_status, override_status, active_refs, passive_refs),
                "active_refs": active_refs,
                "passive_refs": passive_refs,
                "notes": override_lookup.get(name, {}).get("notes") or alias_lookup.get(name, {}).get("notes"),
            }
        )

    retired_aliases = []
    for item in registry.get("aliases", []):
        if item.get("status") != "retired":
            continue
        item_copy = dict(item)
        name = item["name"]
        mentioned = set(doc_mentions.get(name, []))
        mentioned.update(memory_mentions.get(name, []))
        mentioned.update(systemd_mentions.get(name, []))
        mentioned.update(cron_all_mentions.get(name, []))
        mentioned.update(system_mentions.get(name, []))
        mentioned.update(user_crontab_mentions.get(name, []))
        item_copy["mentioned_in"] = sorted(mentioned)
        retired_aliases.append(item_copy)

    missing_refs = []
    for item in registry.get("known_missing_refs", []):
        item_copy = dict(item)
        name = item["name"]
        mentioned = set(doc_mentions.get(name, []))
        mentioned.update(memory_mentions.get(name, []))
        mentioned.update(systemd_mentions.get(name, []))
        mentioned.update(hook_mentions.get(name, []))
        mentioned.update(cron_all_mentions.get(name, []))
        mentioned.update(system_mentions.get(name, []))
        mentioned.update(user_crontab_mentions.get(name, []))
        item_copy["mentioned_in"] = sorted(mentioned)
        missing_refs.append(item_copy)

    summary = Counter(entry["status"] for entry in entries)
    summary["top_level_scripts"] = len(entries)
    summary["retired_aliases"] = len(retired_aliases)
    summary["known_missing_refs"] = len(missing_refs)

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "summary": dict(summary),
        "registry": registry,
        "scripts": sorted(entries, key=lambda item: (item["status"], item["name"])),
        "retired_aliases": retired_aliases,
        "known_missing_refs": missing_refs,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="write markdown/json reports to workspace")
    parser.add_argument("--format", choices=("json", "markdown"), default="markdown", help="stdout format")
    args = parser.parse_args()

    report = build_report()
    if args.write:
        REPORT_JSON.parent.mkdir(parents=True, exist_ok=True)
        REPORT_MD.parent.mkdir(parents=True, exist_ok=True)
        REPORT_JSON.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        REPORT_MD.write_text(to_markdown(report), encoding="utf-8")

    if args.format == "json":
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        print(to_markdown(report), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
