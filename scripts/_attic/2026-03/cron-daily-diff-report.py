#!/usr/bin/env python3
"""Archived on 2026-03-06: unreferenced cron diff report kept for recovery."""
from __future__ import annotations

import argparse
import datetime as dt
import json
from collections import Counter, defaultdict
from pathlib import Path
from statistics import mean
from typing import Dict, Iterable, List, Tuple
from zoneinfo import ZoneInfo

RUNS_DIR = Path("/root/.openclaw/cron/runs")
JOBS_PATH = Path("/root/.openclaw/cron/jobs.json")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare cron run metrics between before/after windows."
    )
    parser.add_argument("--tz", default="Asia/Seoul")
    parser.add_argument("--base-date", default=None, help="YYYY-MM-DD (before)")
    parser.add_argument("--after-date", default=None, help="YYYY-MM-DD (after)")
    parser.add_argument("--cutoff", default=None, help="HH:MM cutoff (local tz)")
    parser.add_argument(
        "--all-jobs",
        action="store_true",
        help="Include disabled/legacy jobs too (default: enabled-only).",
    )
    return parser.parse_args()


def load_jobs() -> Tuple[Dict[str, str], set[str], int]:
    with JOBS_PATH.open("r", encoding="utf-8") as f:
        payload = json.load(f)
    jobs = payload.get("jobs", [])
    name_by_id = {job.get("id"): job.get("name", job.get("id", "?")) for job in jobs}
    enabled_ids = {job.get("id") for job in jobs if job.get("enabled") is True}
    return name_by_id, enabled_ids, len(enabled_ids)


def resolve_windows(
    tz: ZoneInfo, base_date: str | None, after_date: str | None, cutoff: str | None
) -> Tuple[Tuple[int, int, str], Tuple[int, int, str]]:
    now = dt.datetime.now(tz)
    if cutoff:
        h, m = cutoff.split(":")
        cutoff_time = dt.time(hour=int(h), minute=int(m))
    else:
        cutoff_time = dt.time(hour=now.hour, minute=now.minute)

    after_local_date = (
        dt.date.fromisoformat(after_date) if after_date else now.date()
    )
    base_local_date = (
        dt.date.fromisoformat(base_date)
        if base_date
        else (after_local_date - dt.timedelta(days=2))
    )

    before_start_local = dt.datetime.combine(base_local_date, dt.time(0, 0), tz)
    before_end_local = dt.datetime.combine(base_local_date, cutoff_time, tz)

    after_start_local = dt.datetime.combine(after_local_date, dt.time(0, 0), tz)
    after_end_local = dt.datetime.combine(after_local_date, cutoff_time, tz)

    return (
        int(before_start_local.timestamp() * 1000),
        int(after_start_local.timestamp() * 1000),
        cutoff_time.strftime("%H:%M"),
    ), (
        int(before_end_local.timestamp() * 1000),
        int(after_end_local.timestamp() * 1000),
        cutoff_time.strftime("%H:%M"),
    )


def scan_runs(
    start_ms: int,
    end_ms: int,
    name_by_id: Dict[str, str],
    enabled_ids: set[str],
    enabled_only: bool,
    tz: ZoneInfo,
) -> dict:
    total = 0
    errors = 0
    durations: List[int] = []
    minute_counts: Counter[str] = Counter()
    minute_names: defaultdict[str, set[str]] = defaultdict(set)

    for path in RUNS_DIR.glob("*.jsonl"):
        with path.open("r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError:
                    continue

                if rec.get("action") != "finished":
                    continue
                run_at_ms = rec.get("runAtMs")
                job_id = rec.get("jobId")
                if not isinstance(run_at_ms, int) or not isinstance(job_id, str):
                    continue
                if enabled_only and job_id not in enabled_ids:
                    continue
                if run_at_ms < start_ms or run_at_ms >= end_ms:
                    continue

                total += 1
                if rec.get("status") == "error":
                    errors += 1
                duration_ms = rec.get("durationMs")
                if isinstance(duration_ms, int) and duration_ms >= 0:
                    durations.append(duration_ms)

                d = dt.datetime.fromtimestamp(
                    run_at_ms / 1000, tz=dt.timezone.utc
                ).astimezone(tz)
                minute_key = d.strftime("%H:%M")
                minute_counts[minute_key] += 1
                minute_names[minute_key].add(name_by_id.get(job_id, job_id))

    ge2 = sum(1 for c in minute_counts.values() if c >= 2)
    ge3 = sum(1 for c in minute_counts.values() if c >= 3)
    peak = max(minute_counts.values()) if minute_counts else 0

    top_collisions = sorted(
        ((minute, cnt, sorted(minute_names[minute])) for minute, cnt in minute_counts.items()),
        key=lambda x: (-x[1], x[0]),
    )[:5]

    return {
        "total": total,
        "errors": errors,
        "error_rate": (errors / total * 100.0) if total else 0.0,
        "avg_duration_ms": int(mean(durations)) if durations else 0,
        "peak": peak,
        "ge2": ge2,
        "ge3": ge3,
        "top_collisions": top_collisions,
    }


def fmt_delta(before: float, after: float, suffix: str = "") -> str:
    delta = after - before
    sign = "+" if delta >= 0 else "-"
    return f"{sign}{abs(delta):.2f}{suffix}"


def main() -> int:
    args = parse_args()
    tz = ZoneInfo(args.tz)

    (before_start_ms, after_start_ms, cutoff_hhmm), (
        before_end_ms,
        after_end_ms,
        _,
    ) = resolve_windows(tz, args.base_date, args.after_date, args.cutoff)

    name_by_id, enabled_ids, enabled_count = load_jobs()
    enabled_only = not args.all_jobs

    before = scan_runs(
        before_start_ms, before_end_ms, name_by_id, enabled_ids, enabled_only, tz
    )
    after = scan_runs(
        after_start_ms, after_end_ms, name_by_id, enabled_ids, enabled_only, tz
    )

    base_date = dt.datetime.fromtimestamp(before_start_ms / 1000, tz).date().isoformat()
    after_date = dt.datetime.fromtimestamp(after_start_ms / 1000, tz).date().isoformat()
    scope = (
        f"현재 enabled 잡 기준({enabled_count}개)"
        if enabled_only
        else "전체 잡 기준(legacy 포함)"
    )

    lines = [
        f"📊 전/후 지표 1회 점검 ({after_date} {cutoff_hhmm} KST)",
        f"- 비교구간: {base_date} 00:00~{cutoff_hhmm} vs {after_date} 00:00~{cutoff_hhmm}",
        f"- 대상: {scope}",
        f"- 실행건수: {before['total']} -> {after['total']} ({fmt_delta(before['total'], after['total'])})",
        (
            f"- 에러율: {before['error_rate']:.2f}% ({before['errors']}/{before['total']})"
            f" -> {after['error_rate']:.2f}% ({after['errors']}/{after['total']})"
            f" ({fmt_delta(before['error_rate'], after['error_rate'], '%')})"
        ),
        (
            f"- 평균 실행시간: {before['avg_duration_ms']/1000:.1f}s"
            f" -> {after['avg_duration_ms']/1000:.1f}s"
            f" ({fmt_delta(before['avg_duration_ms']/1000, after['avg_duration_ms']/1000, 's')})"
        ),
        (
            f"- 동시실행 분포: peak {before['peak']} -> {after['peak']}, "
            f">=2분 {before['ge2']} -> {after['ge2']}, >=3분 {before['ge3']} -> {after['ge3']}"
        ),
    ]

    if after["top_collisions"]:
        tops = []
        for minute, count, names in after["top_collisions"][:3]:
            tops.append(f"{minute}({count}): " + ", ".join(names[:3]))
        lines.append("- 오늘 동시실행 top: " + " | ".join(tops))

    if after["error_rate"] < before["error_rate"]:
        verdict = "개선"
    elif after["error_rate"] > before["error_rate"]:
        verdict = "악화"
    else:
        verdict = "유사"
    lines.append(f"- 결론: {verdict}")

    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
