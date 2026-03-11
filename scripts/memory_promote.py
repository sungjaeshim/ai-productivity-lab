#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path('/root/.openclaw/workspace')
MEMORY_DIR = ROOT / 'memory'
OUT_FILE = ROOT / 'MEMORY.md'
USER_FILE = ROOT / 'USER.md'
RAW_MEMORY_FILE = MEMORY_DIR / 'MEMORY.md'
STATE_FILE = ROOT / '.state' / 'memory_promote_state.json'

SECTION_WEIGHTS = {
    'decisions': 0.90,
    'lessons': 0.75,
    'blockers': 0.65,
}

LIMITS = {
    'preferences': 10,
    'decisions': 12,
    'rules': 8,
    'active': 5,
}

ACTIVE_MAX_AGE_DAYS = 2
DECISION_STALE_DAYS = 14
RULE_STALE_DAYS = 14
DECAY_PER_WEEK = 0.06
MIN_DECAYED_SCORE = 0.55
RECONFIRM_LOOKBACK_FILES = 14
RECONFIRM_BOOST = 0.20
RECONFIRM_WEEKLY_MIN = 1  # soft check only (no hard fail)
SOFT_WARN_REMINDER_STREAK_DAYS = 14

DATE_FILE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}\.md$")
BULLET_META_RE = re.compile(r"^-\s+(.*?)\s+_\(src:\s*([^,]+),\s*score:\s*([0-9.]+)\)_\s*$")
RECONFIRM_RE = re.compile(r"^\s*(?:[-*]\s*)?(?:reconfirm|재확인)\s*:\s*(.+?)\s*$", re.I)


@dataclass
class Candidate:
    text: str
    source: str
    score: float


def normalize(s: str) -> str:
    s = s.strip().lower()
    s = re.sub(r"\s+", " ", s)
    s = re.sub(r"[^\w\s가-힣#:+/.-]", "", s)
    return s


def bullet_lines(block: str) -> list[str]:
    out = []
    for ln in block.splitlines():
        m = re.match(r"^\s*[-*]\s+(.*)$", ln)
        if m:
            txt = m.group(1).strip()
            if txt:
                out.append(txt)
    return out


def extract_section(text: str, heading: str) -> str:
    p = re.compile(rf"^##\s+{re.escape(heading)}\s*$", re.M)
    m = p.search(text)
    if not m:
        # fallback: ### heading
        p = re.compile(rf"^###\s+{re.escape(heading)}\s*$", re.M)
        m = p.search(text)
    if not m:
        return ""
    start = m.end()
    nxt = re.search(r"^##\s+|^###\s+", text[start:], re.M)
    end = start + nxt.start() if nxt else len(text)
    return text[start:end].strip()


def last_daily_files(n: int = 3) -> list[Path]:
    files = [p for p in MEMORY_DIR.iterdir() if p.is_file() and DATE_FILE_RE.match(p.name)]
    files.sort()
    return files[-n:]


def parse_existing_section_candidates(doc: str, heading: str) -> list[Candidate]:
    block = extract_section(doc, heading)
    out: list[Candidate] = []
    for ln in block.splitlines():
        m = BULLET_META_RE.match(ln.strip())
        if m:
            out.append(Candidate(text=m.group(1).strip(), source=m.group(2).strip(), score=float(m.group(3))))
    return out


def parse_source_date(source: str) -> datetime | None:
    m = re.search(r"(\d{4}-\d{2}-\d{2})\.md", source)
    if not m:
        return None
    try:
        return datetime.strptime(m.group(1), "%Y-%m-%d")
    except ValueError:
        return None


def load_preferences() -> list[Candidate]:
    if not USER_FILE.exists():
        return []
    txt = USER_FILE.read_text(encoding='utf-8', errors='ignore')

    lines = txt.splitlines()
    capture = False
    kept: list[str] = []
    for ln in lines:
        if ln.strip().startswith('- **Notes:**'):
            capture = True
            continue
        if capture and ln.startswith('## '):
            break
        if capture:
            kept.append(ln)

    res = []
    for b in bullet_lines('\n'.join(kept)):
        if len(b) < 8:
            continue
        res.append(Candidate(text=b, source='USER.md', score=1.0))
    return res


def load_recent_distills() -> dict[str, list[Candidate]]:
    buckets: dict[str, list[Candidate]] = defaultdict(list)
    for p in last_daily_files(3):
        txt = p.read_text(encoding='utf-8', errors='ignore')
        for section, weight in SECTION_WEIGHTS.items():
            block = extract_section(txt, section.capitalize())
            for b in bullet_lines(block):
                if len(b) < 8:
                    continue
                score = weight
                if any(k in b for k in ['요청', '선호', '확정', '고정', 'must', 'always', '결정']):
                    score += 0.08
                buckets[section].append(Candidate(text=b, source=f'memory/{p.name}', score=min(score, 1.0)))
    return buckets


def load_reconfirm_map() -> dict[str, Candidate]:
    out: dict[str, Candidate] = {}
    for p in last_daily_files(RECONFIRM_LOOKBACK_FILES):
        txt = p.read_text(encoding='utf-8', errors='ignore')
        for ln in txt.splitlines():
            m = RECONFIRM_RE.match(ln)
            if not m:
                continue
            text = m.group(1).strip()
            key = normalize(text)
            if len(key) < 8:
                continue
            out[key] = Candidate(text=text, source=f'memory/{p.name}', score=1.0)
    return out


def count_recent_reconfirm_lines(days: int = 7) -> int:
    now = datetime.now()
    count = 0
    for p in last_daily_files(RECONFIRM_LOOKBACK_FILES):
        d = parse_source_date(p.name)
        if not d:
            continue
        if (now - d).days > days:
            continue
        txt = p.read_text(encoding='utf-8', errors='ignore')
        for ln in txt.splitlines():
            if RECONFIRM_RE.match(ln):
                count += 1
    return count


def apply_reconfirm(items: list[Candidate], reconfirm_map: dict[str, Candidate]) -> tuple[list[Candidate], int]:
    if not reconfirm_map:
        return items, 0

    reconfirm_keys = list(reconfirm_map.keys())
    applied = 0
    boosted: list[Candidate] = []

    for c in items:
        key = normalize(c.text)
        matched_key = None
        if key in reconfirm_map:
            matched_key = key
        else:
            for rk in reconfirm_keys:
                if min(len(rk), len(key)) < 12:
                    continue
                if rk in key or key in rk:
                    matched_key = rk
                    break

        if matched_key:
            rc = reconfirm_map[matched_key]
            boosted.append(
                Candidate(
                    text=c.text,
                    source=f"{c.source};reconfirm:{rc.source}",
                    score=min(1.0, c.score + RECONFIRM_BOOST),
                )
            )
            applied += 1
        else:
            boosted.append(c)

    return boosted, applied


def apply_age_decay(c: Candidate, stale_days: int | None, now: datetime) -> Candidate:
    if not stale_days:
        return c
    d = parse_source_date(c.source)
    if not d:
        return c
    age_days = (now - d).days
    if age_days <= stale_days:
        return c
    overdue_days = age_days - stale_days
    decay_steps = max(1, overdue_days // 7)
    decayed = max(MIN_DECAYED_SCORE, c.score - decay_steps * DECAY_PER_WEEK)
    return Candidate(text=c.text, source=c.source, score=decayed)


def dedupe_rank(
    items: list[Candidate],
    limit: int,
    threshold: float = 0.72,
    stale_days: int | None = None,
    now: datetime | None = None,
) -> list[Candidate]:
    by_key: dict[str, Candidate] = {}
    counts: defaultdict[str, int] = defaultdict(int)
    now = now or datetime.now()

    for raw in items:
        c = apply_age_decay(raw, stale_days, now)
        key = normalize(c.text)
        if not key:
            continue
        counts[key] += 1
        prev = by_key.get(key)
        if prev is None or c.score > prev.score:
            by_key[key] = c

    ranked = []
    for key, c in by_key.items():
        bonus = min((counts[key] - 1) * 0.06, 0.18)
        score = min(c.score + bonus, 1.0)
        if score >= threshold:
            ranked.append(Candidate(text=c.text, source=c.source, score=score))

    ranked.sort(key=lambda x: x.score, reverse=True)
    return ranked[:limit]


def to_md_list(items: list[Candidate]) -> str:
    if not items:
        return '- (no stable items yet)'
    return '\n'.join(f"- {i.text} _(src: {i.source}, score: {i.score:.2f})_" for i in items)


def render(preferences: list[Candidate], decisions: list[Candidate], rules: list[Candidate], active: list[Candidate]) -> str:
    now = datetime.now().strftime('%Y-%m-%d %H:%M')
    return f"""# MEMORY.md

Curated long-term memory view (B-track normalized).
Last updated: {now}

## Promotion Rules
- Deduplicate by normalized sentence key.
- Keep only high-confidence facts (score >= 0.72).
- Cap each section to avoid memory bloat.
- Prefer user preference, explicit decisions, and durable operating rules.
- Auto-demote stale Active Context (> {ACTIVE_MAX_AGE_DAYS} days old) into Operating Rules.
- Age-decay Decisions/Rules when not reconfirmed for {DECISION_STALE_DAYS}+ days.
- Manual reconfirm supported from daily notes (`reconfirm: <item>` or `재확인: <item>`).

## User Preferences (durable)
{to_md_list(preferences)}

## Confirmed Decisions (recent)
{to_md_list(decisions)}

## Operating Rules
{to_md_list(rules)}

## Active Context (short horizon)
{to_md_list(active)}

## Notes
- Raw auto-capture remains in `memory/MEMORY.md`.
- Daily distills remain in `memory/YYYY-MM-DD.md`.
"""


def count_duplicate_keys(text: str) -> int:
    bullets = [m.group(1).strip() for m in re.finditer(r"^-\s+(.*)$", text, re.M)]
    keys = [normalize(b) for b in bullets if normalize(b)]
    c = Counter(keys)
    return sum(v - 1 for v in c.values() if v > 1)


def quality_score(doc: str) -> float:
    sections = {
        'pref': parse_existing_section_candidates(doc, 'User Preferences (durable)'),
        'dec': parse_existing_section_candidates(doc, 'Confirmed Decisions (recent)'),
        'rules': parse_existing_section_candidates(doc, 'Operating Rules'),
        'active': parse_existing_section_candidates(doc, 'Active Context (short horizon)'),
    }
    non_empty = sum(1 for v in sections.values() if v)

    dup = count_duplicate_keys(doc)
    bullets = len(re.findall(r"^-\s+", doc, re.M)) or 1
    dup_ratio = dup / bullets

    active_recent_ratio = 1.0
    if sections['active']:
        now = datetime.now()
        recent = 0
        for c in sections['active']:
            d = parse_source_date(c.source)
            if d and (now - d).days <= ACTIVE_MAX_AGE_DAYS:
                recent += 1
        active_recent_ratio = recent / len(sections['active'])

    traceable = len(re.findall(r"_\(src:[^)]+score:\s*[0-9.]+\)_", doc))
    trace_ratio = min(traceable / bullets, 1.0)

    score = 0.0
    score += 3.0 * (non_empty / 4.0)
    score += 3.0 * max(0.0, 1.0 - dup_ratio)
    score += 2.0 * active_recent_ratio
    score += 2.0 * trace_ratio
    return round(min(score, 10.0), 1)


def load_state() -> dict:
    if not STATE_FILE.exists():
        return {}
    try:
        return json.loads(STATE_FILE.read_text(encoding='utf-8'))
    except Exception:
        return {}


def save_state(state: dict) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding='utf-8')


def update_soft_warn_state(today: str, weekly_status: str) -> tuple[str, int, int]:
    state = load_state()
    streak = int(state.get('soft_warn_streak_days', 0))

    if state.get('last_date') == today:
        streak = int(state.get('soft_warn_streak_days', streak))
    elif weekly_status == 'soft_warn':
        streak += 1
    else:
        streak = 0

    reminder_due = 0
    last_reminder_streak = int(state.get('last_reminder_streak', 0))
    if weekly_status == 'soft_warn' and streak >= SOFT_WARN_REMINDER_STREAK_DAYS and last_reminder_streak < SOFT_WARN_REMINDER_STREAK_DAYS:
        reminder_due = 1
        last_reminder_streak = SOFT_WARN_REMINDER_STREAK_DAYS
    if weekly_status == 'ok':
        last_reminder_streak = 0

    state.update(
        {
            'last_date': today,
            'soft_warn_streak_days': streak,
            'last_reminder_streak': last_reminder_streak,
        }
    )
    save_state(state)
    reminder_status = 'due' if reminder_due else 'none'
    return reminder_status, reminder_due, streak


def main() -> int:
    old_doc = OUT_FILE.read_text(encoding='utf-8', errors='ignore') if OUT_FILE.exists() else ''
    now = datetime.now()

    prefs = dedupe_rank(load_preferences(), LIMITS['preferences'], threshold=0.75, now=now)
    buckets = load_recent_distills()

    prev_decisions = parse_existing_section_candidates(old_doc, 'Confirmed Decisions (recent)') if old_doc else []
    prev_rules = parse_existing_section_candidates(old_doc, 'Operating Rules') if old_doc else []

    # Keep continuity, then apply age decay for stale items.
    decision_pool = buckets.get('decisions', []) + prev_decisions
    rule_pool = buckets.get('lessons', []) + prev_rules

    reconfirm_map = load_reconfirm_map()
    decision_pool, rc_applied_dec = apply_reconfirm(decision_pool, reconfirm_map)
    rule_pool, rc_applied_rule = apply_reconfirm(rule_pool, reconfirm_map)

    decisions = dedupe_rank(
        decision_pool,
        LIMITS['decisions'],
        threshold=0.72,
        stale_days=DECISION_STALE_DAYS,
        now=now,
    )
    rules = dedupe_rank(
        rule_pool,
        LIMITS['rules'],
        threshold=0.70,
        stale_days=RULE_STALE_DAYS,
        now=now,
    )
    active = dedupe_rank(buckets.get('blockers', []), LIMITS['active'], threshold=0.65, now=now)

    # Auto-demote stale previous active items into rules.
    prev_active = parse_existing_section_candidates(old_doc, 'Active Context (short horizon)') if old_doc else []
    existing_active_keys = {normalize(c.text) for c in active}
    demoted: list[Candidate] = []
    for c in prev_active:
        d = parse_source_date(c.source)
        if d is None:
            continue
        if (now - d) > timedelta(days=ACTIVE_MAX_AGE_DAYS) and normalize(c.text) not in existing_active_keys:
            demoted.append(Candidate(text=c.text, source=c.source, score=max(0.72, c.score - 0.05)))

    if demoted:
        rules = dedupe_rank(rules + demoted, LIMITS['rules'], threshold=0.70, stale_days=RULE_STALE_DAYS, now=now)

    new_doc = render(prefs, decisions, rules, active)
    OUT_FILE.write_text(new_doc, encoding='utf-8')

    if not RAW_MEMORY_FILE.exists():
        RAW_MEMORY_FILE.write_text('# Auto memory capture queue\n', encoding='utf-8')

    old_dup = count_duplicate_keys(old_doc) if old_doc else 0
    new_dup = count_duplicate_keys(new_doc)
    dup_removed_est = max(0, old_dup - new_dup)

    updated_sections = sum(1 for s in [prefs, decisions, rules, active] if s)
    q = quality_score(new_doc)

    reconfirm_applied = rc_applied_dec + rc_applied_rule
    weekly_reconfirm_count = count_recent_reconfirm_lines(7)
    weekly_status = 'ok' if weekly_reconfirm_count >= RECONFIRM_WEEKLY_MIN else 'soft_warn'
    today = now.strftime('%Y-%m-%d')
    reminder_status, reminder_due, soft_warn_streak_days = update_soft_warn_state(today, weekly_status)

    print(f"updated_sections={updated_sections}")
    print(f"duplicates_removed_estimate={dup_removed_est}")
    print(f"reconfirm_applied={reconfirm_applied}")
    print(f"reconfirm_weekly_count={weekly_reconfirm_count}")
    print(f"reconfirm_weekly_status={weekly_status}")
    print(f"soft_warn_streak_days={soft_warn_streak_days}")
    print(f"reconfirm_reminder_status={reminder_status}")
    print(f"reconfirm_reminder_due={reminder_due}")
    print(f"memory_quality_score={q}/10")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
