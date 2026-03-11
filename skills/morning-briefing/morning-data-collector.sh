#!/usr/bin/env bash
set -euo pipefail

DATE_KST="$(TZ=Asia/Seoul date +%Y-%m-%d)"
DATA_DIR="/root/.openclaw/workspace/data"
INTEL_FILE="${DATA_DIR}/intelligence-${DATE_KST}.json"
OUT_FILE="${DATA_DIR}/morning-context-${DATE_KST}.json"
mkdir -p "${DATA_DIR}"

python3 - <<'PY'
import json
import os
import re
import ssl
import subprocess
import urllib.parse
import urllib.request
from datetime import datetime, timedelta
from pathlib import Path

kst_now = datetime.now().astimezone()
date_kst = kst_now.strftime('%Y-%m-%d')
openclaw_root = Path('/root/.openclaw')
workspace = Path('/root/.openclaw/workspace')
data_dir = workspace / 'data'
intel_file = data_dir / f'intelligence-{date_kst}.json'
out_file = data_dir / f'morning-context-{date_kst}.json'
yesterday_date = (kst_now - timedelta(days=1)).strftime('%Y-%m-%d')
yesterday_memory_path = workspace / 'memory' / f'{yesterday_date}.md'
brain_todoist_registry = workspace / 'memory' / 'second-brain' / '.brain-todoist-registry.jsonl'
todo_router_registry = workspace / 'memory' / 'second-brain' / '.todo-router-registry.jsonl'
todoist_projects_candidates = [
    openclaw_root / 'credentials' / 'todoist-projects.json',
    workspace / 'credentials' / 'todoist-projects.json',
]
todoist_token_candidates = [
    os.environ.get('TODOIST_TOKEN_PATH'),
    str(openclaw_root / 'credentials' / 'todoist'),
    str(workspace / 'credentials' / 'todoist'),
]

weather = {"temp": None, "feel": None, "condition": "unknown", "high": None, "low": None, "source": None}


def _to_int(v):
    s = str(v or '').strip()
    return int(s) if s.lstrip('-').isdigit() else None


def read_first_existing(candidates):
    for candidate in candidates:
        if not candidate:
            continue
        path = Path(candidate)
        if path.exists():
            return path.read_text(encoding='utf-8').strip()
    return None


def clean_task_text(text):
    text = str(text or '').strip()
    if not text:
        return ''
    if ' // ' in text:
        text = text.split(' // ', 1)[1].strip()
    text = re.sub(r'^<@[^>]+>\s*', '', text)
    text = re.sub(r'^\[링크\]\s*[^—-]+[—-]\s*', '', text)
    text = re.sub(r'^[A-Za-z0-9.-]+\.[A-Za-z]{2,}\s*[—-]\s*', '', text)
    text = re.sub(r'^\[[^\]]+\]\s*', '', text)
    text = re.sub(r'^#todo\s*', '', text, flags=re.IGNORECASE)
    text = re.sub(r'https?://\S+', '', text)
    text = re.sub(r'\s+', ' ', text).strip()
    text = text.replace('3 일간', '3일간')
    text = re.sub(r'^[aA]\s*로하고', 'A안으로 진행하고', text)
    text = text.replace('봐줘서 리포팅해줘', '다시 보고 리포팅하기')
    text = text.replace('다시 다시 보고', '다시 보고')
    text = text.replace('조취', '조치')
    return text[:80]


def is_noise_task(text):
    lowered = text.lower()
    noise_patterns = [
        'a new session was started',
        'execute your session startup sequence',
        'openclaw runtime context',
        'subagent context',
        'reply with exactly',
        'return exactly',
        'conversation info',
        'queued messages while agent was busy',
        'to send an image back',
        'results auto-announce',
        'busy-poll',
        'probe_ok',
        'e2e-check',
        '라우팅 검증',
        '이건 확인햇나',
        '이건 확인했나',
        '꼭 해줘',
        '원인 확인 조취필요',
        '원인 확인 조치필요',
        'inbox 에서',
        'inbox > today',
    ]
    return any(pattern in lowered for pattern in noise_patterns)


def load_projects():
    raw = read_first_existing(todoist_projects_candidates)
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except Exception:
        return {}


def todoist_request(path):
    token = read_first_existing(todoist_token_candidates)
    if not token:
        raise RuntimeError('todoist token missing')
    req = urllib.request.Request(
        f'https://api.todoist.com/api/v1{path}',
        headers={
            'Authorization': f'Bearer {token}',
            'Content-Type': 'application/json',
        },
    )
    with urllib.request.urlopen(req, timeout=12, context=ssl.create_default_context()) as resp:
        return json.loads(resp.read().decode('utf-8', errors='ignore'))


def extract_tasks(response):
    if isinstance(response, list):
        return response
    if isinstance(response, dict):
        for key in ('results', 'tasks', 'items', 'data'):
            value = response.get(key)
            if isinstance(value, list):
                return value
    return []


def parse_due_weight(task):
    due = task.get('due') or {}
    due_date = str(due.get('date') or '').strip()
    if due_date == date_kst:
        return 80
    if due_date and due_date < date_kst:
        return 70
    if due_date:
        return 20
    return 0


def project_rank(project_name):
    return {
        'active': 40,
        'queue': 25,
        'waiting': 10,
        'inbox': 0,
        'other': 0,
    }.get(project_name, 0)


def clean_summary_text(text, max_len=96):
    text = str(text or '').strip()
    replacements = [
        (r'^Added `## Task Operations` to `AGENTS\.md`.*', 'AGENTS.md에 Task Operations 기본 규칙 추가'),
        (r'^Added Task Operations to AGENTS\.md.*', 'AGENTS.md에 Task Operations 기본 규칙 추가'),
        (r'^Added `## Task Ops Quick Checklist` to `TOOLS\.md`.*', 'TOOLS.md에 Task Ops Quick Checklist 추가'),
        (r'^Added Task Ops Quick Checklist to TOOLS\.md.*', 'TOOLS.md에 Task Ops Quick Checklist 추가'),
        (r'^Created/kept reference docs.*', '운영 패턴 관련 참조 문서 정리'),
        (r'^Discord role hardening is only partially complete.*', 'Discord role hardening은 아직 일부 미완료'),
        (r'^OpenClaw update items .* were not yet applied.*', 'OpenClaw update 후속 항목 일부는 아직 미적용'),
        (r'^Verified OpenClaw gateway auth.*', 'OpenClaw gateway auth 상태는 기준 충족'),
    ]
    for pattern, repl in replacements:
        if re.match(pattern, text):
            text = repl
            break
    text = re.sub(r'[`*_#]+', '', text)
    text = re.sub(r'<@[^>]+>', '', text)
    text = re.sub(r'\([^)]*score:[^)]+\)', '', text)
    text = re.sub(r'\s+', ' ', text).strip()
    if len(text) > max_len:
        return text[: max_len - 1] + '…'
    return text


def polish_summary_fact(text):
    text = clean_summary_text(text, max_len=120)
    replacements = [
        ('AGENTS.md에 Task Operations 기본 규칙 추가', 'Task Operations 기본 규칙 정리'),
        ('TOOLS.md에 Task Ops Quick Checklist 추가', 'Task Ops Quick Checklist 정리'),
        ('운영 패턴 관련 참조 문서 정리', '운영 패턴 참조 문서 정리'),
        ('Discord role hardening은 아직 일부 미완료', 'Discord role hardening은 아직 일부 미완료'),
        ('OpenClaw update 후속 항목 일부는 아직 미적용', 'OpenClaw update 후속 항목 일부는 아직 미적용'),
        ('OpenClaw gateway auth 상태는 기준 충족', 'OpenClaw gateway auth 상태는 기준 충족'),
    ]
    for src, dst in replacements:
        if text == src:
            return dst
    return text


def load_markdown_sections(path):
    if not path.exists():
        return {}
    sections = {}
    current = None
    for raw_line in path.read_text(encoding='utf-8').splitlines():
        line = raw_line.rstrip()
        if line.startswith('## '):
            current = line[3:].strip()
            sections.setdefault(current, [])
            continue
        if current is not None:
            sections[current].append(line)
    return sections


def first_bullet(sections, name):
    for line in sections.get(name, []):
        stripped = line.strip()
        if stripped.startswith('- '):
            return clean_summary_text(stripped[2:])
    return ''


def extract_yesterday_summary():
    sections = load_markdown_sections(yesterday_memory_path)
    if not sections:
        return {
            'data': '어제 메모 파일 연결 전, 전날 핵심 요약을 불러오지 못함',
            'facts': [],
            'sentence': '어제 핵심 요약은 아직 연결되지 않았습니다.',
            'status': 'fallback',
            'source': 'default-yesterday-template',
        }

    state_change = first_bullet(sections, 'State Changes')
    blocker = first_bullet(sections, 'Blockers')
    decision = first_bullet(sections, 'Decisions')
    active = first_bullet(sections, 'Active Tasks / WIP')
    lesson = first_bullet(sections, 'Lessons')

    parts = []
    if state_change:
        parts.append(polish_summary_fact(state_change))
    if blocker:
        parts.append(f"미해결: {polish_summary_fact(blocker)}")

    if not parts and decision:
        parts.append(polish_summary_fact(decision))
    if not parts and active:
        parts.append(polish_summary_fact(active))
    if not parts and lesson:
        parts.append(polish_summary_fact(lesson))

    if not parts:
        return {
            'data': f'{yesterday_date} 메모는 있지만 요약 가능한 bullet을 찾지 못함',
            'facts': [],
            'sentence': '어제 메모는 있었지만 브리핑용 핵심 요약을 뽑지 못했습니다.',
            'status': 'partial',
            'source': str(yesterday_memory_path),
        }

    sentence = parts[0]
    if len(parts) >= 2:
        second = parts[1]
        if second.startswith('미해결: '):
            unresolved = second.replace('미해결: ', '')
            unresolved = unresolved.replace('은 아직 일부 미완료', '은 아직 마무리되지 않았습니다')
            unresolved = unresolved.replace('는 아직 일부 미완료', '는 아직 마무리되지 않았습니다')
            if unresolved.endswith('아직 미적용'):
                unresolved = unresolved.replace('아직 미적용', '아직 적용되지 않았습니다')
            first = parts[0]
            if first.endswith('정리'):
                sentence = f"어제는 {first}를 마쳤고, {unresolved}"
            else:
                sentence = f"어제는 {first}를 정리했고, {unresolved}"
        else:
            first = parts[0]
            if first.endswith('정리'):
                sentence = f"어제는 {first}를 마쳤고, 이어서 {second}까지 확인했습니다."
            else:
                sentence = f"어제는 {first}를 정리했고, 이어서 {second}까지 확인했습니다."
    elif sentence.startswith('미해결: '):
        unresolved = sentence.replace('미해결: ', '')
        sentence = f"어제 기준으로 {unresolved} 상태입니다."
    else:
        if sentence.endswith('정리'):
            sentence = f"어제는 {sentence}를 마쳤습니다."
        else:
            sentence = f"어제는 {sentence}를 정리했습니다."

    return {
        'data': ' / '.join(parts[:2]),
        'facts': parts[:2],
        'sentence': clean_summary_text(sentence, max_len=120),
        'status': 'ok',
        'source': str(yesterday_memory_path),
    }


def annotate_tasks(tasks, source, projects_map):
    id_to_name = {value: key for key, value in projects_map.items() if isinstance(value, str)}
    normalized = []
    for raw in tasks:
        content = clean_task_text(raw.get('content', ''))
        if not content or is_noise_task(content):
            continue
        priority = int(raw.get('priority') or 1)
        project = id_to_name.get(raw.get('project_id'), 'other')
        due = raw.get('due') or {}
        score = (priority * 100) + project_rank(project) + parse_due_weight(raw)
        normalized.append({
            'task': content,
            'source': source,
            'priority': priority,
            'project': project,
            'due': due.get('date'),
            'sort_key': score,
        })
    normalized.sort(key=lambda item: (-item['sort_key'], item['task']))
    return normalized


def todoist_snapshot_tasks():
    projects_map = load_projects()
    attempts = [
        ('/tasks?filter=today', 'todoist-api:today'),
        (f"/tasks?filter={urllib.parse.quote('today | overdue')}", 'todoist-api:today-overdue'),
        ('/tasks', 'todoist-api:all-open'),
    ]
    warnings = []
    for api_path, source in attempts:
        try:
            tasks = extract_tasks(todoist_request(api_path))
        except Exception as exc:
            warnings.append(f'{source}:{exc}')
            continue
        normalized = annotate_tasks(tasks, source, projects_map)
        if normalized:
            return {
                'items': normalized[:3],
                'status': 'ok',
                'source': source,
                'warning': warnings[0] if warnings else None,
                'total_count': len(normalized),
            }
    return {
        'items': [],
        'status': 'unavailable',
        'source': 'todoist-api',
        'warning': warnings[0] if warnings else 'todoist unavailable',
        'total_count': 0,
    }


def load_brain_todoist_tasks(path):
    items = []
    if not path.exists():
        return items
    for raw in path.read_text(encoding='utf-8').splitlines():
        raw = raw.strip()
        if not raw:
            continue
        try:
            entry = json.loads(raw)
        except Exception:
            continue
        if str(entry.get('status', '')).upper() != 'TODO':
            continue
        title = clean_task_text(entry.get('title', ''))
        if not title or is_noise_task(title):
            continue
        items.append({
            'task': title,
            'source': 'brain-todoist-registry',
            'priority': 1,
            'project': 'other',
            'due': None,
            'sort_key': entry.get('synced_at', ''),
        })
    items.sort(key=lambda item: item['sort_key'], reverse=True)
    return items


def load_router_tasks(path):
    items = []
    if not path.exists():
        return items
    for raw in reversed(path.read_text(encoding='utf-8').splitlines()):
        raw = raw.strip()
        if not raw:
            continue
        try:
            entry = json.loads(raw)
        except Exception:
            continue
        text = clean_task_text(entry.get('content', ''))
        if not text or is_noise_task(text):
            continue
        priority_tag = str(entry.get('priority_tag', '')).lower()
        project = str(entry.get('project', '')).lower() or 'other'
        due = str(entry.get('due', '')).lower()
        score = 1
        if project == 'active':
            score += 4
        elif project == 'queue':
            score += 2
        if priority_tag == 'p1':
            score += 3
        elif priority_tag == 'p2':
            score += 1
        if 'today' in due or '오늘' in due:
            score += 2
        items.append({
            'task': text,
            'source': 'todo-router-registry',
            'priority': score,
            'project': project,
            'due': due or None,
            'sort_key': entry.get('created_at', ''),
        })
    items.sort(key=lambda item: (item['priority'], item['sort_key']), reverse=True)
    return items


def fallback_registry_tasks():
    picked = []
    seen = set()
    for candidate in load_brain_todoist_tasks(brain_todoist_registry) + load_router_tasks(todo_router_registry):
        key = candidate['task'].lower()
        if key in seen:
            continue
        seen.add(key)
        picked.append(candidate)
        if len(picked) == 3:
            break
    return picked


try:
    r = subprocess.run(['curl', '-sS', 'https://wttr.in/Seoul?format=j1'], capture_output=True, text=True, timeout=10)
    if r.returncode == 0 and r.stdout.strip():
        w = json.loads(r.stdout)
        cur = (w.get('current_condition') or [{}])[0]
        today = (w.get('weather') or [{}])[0]
        weather = {
            'temp': _to_int(cur.get('temp_C')),
            'feel': _to_int(cur.get('FeelsLikeC')),
            'condition': ((cur.get('weatherDesc') or [{}])[0].get('value') or 'unknown'),
            'high': _to_int(today.get('maxtempC')),
            'low': _to_int(today.get('mintempC')),
            'source': 'wttr.in'
        }
except Exception:
    pass

if weather.get('condition') == 'unknown':
    try:
        url = (
            'https://api.open-meteo.com/v1/forecast?latitude=37.5665&longitude=126.9780'
            '&current=temperature_2m,apparent_temperature,weather_code'
            '&daily=temperature_2m_max,temperature_2m_min&timezone=Asia%2FSeoul&forecast_days=1'
        )
        with urllib.request.urlopen(url, timeout=10) as resp:
            om = json.loads(resp.read().decode('utf-8', errors='ignore'))

        code_map = {
            0: 'Clear', 1: 'Mainly clear', 2: 'Partly cloudy', 3: 'Overcast',
            45: 'Fog', 48: 'Rime fog', 51: 'Light drizzle', 53: 'Drizzle', 55: 'Dense drizzle',
            56: 'Freezing drizzle', 57: 'Freezing drizzle', 61: 'Rain', 63: 'Rain', 65: 'Heavy rain',
            66: 'Freezing rain', 67: 'Freezing rain', 71: 'Snow', 73: 'Snow', 75: 'Heavy snow',
            77: 'Snow grains', 80: 'Rain showers', 81: 'Rain showers', 82: 'Violent rain showers',
            85: 'Snow showers', 86: 'Snow showers', 95: 'Thunderstorm', 96: 'Thunderstorm hail', 99: 'Thunderstorm hail'
        }
        cur = om.get('current', {})
        daily = om.get('daily', {})
        code = cur.get('weather_code')
        weather = {
            'temp': _to_int(round(cur.get('temperature_2m'))) if cur.get('temperature_2m') is not None else None,
            'feel': _to_int(round(cur.get('apparent_temperature'))) if cur.get('apparent_temperature') is not None else None,
            'condition': code_map.get(code, f'code:{code}') if code is not None else 'unknown',
            'high': _to_int(round((daily.get('temperature_2m_max') or [None])[0])) if (daily.get('temperature_2m_max') or [None])[0] is not None else None,
            'low': _to_int(round((daily.get('temperature_2m_min') or [None])[0])) if (daily.get('temperature_2m_min') or [None])[0] is not None else None,
            'source': 'open-meteo'
        }
    except Exception:
        pass

intelligence_source = f'intelligence-{date_kst}.json' if intel_file.exists() else 'missing'
task_snapshot = todoist_snapshot_tasks()
top_tasks = task_snapshot.get('items') or []

if not top_tasks:
    top_tasks = fallback_registry_tasks()
    if top_tasks:
        task_snapshot = {
            'items': top_tasks,
            'status': 'stale-local',
            'source': 'brain-todoist-registry+todo-router-registry',
            'warning': task_snapshot.get('warning'),
            'total_count': len(top_tasks),
        }

if not top_tasks:
    top_tasks = [
        {'priority': 1, 'task': '오늘 최우선 1건 먼저 정하기', 'source': 'fallback', 'project': 'other', 'due': None},
        {'priority': 1, 'task': '어제 열린 루프 1건 정리하기', 'source': 'fallback', 'project': 'other', 'due': None},
        {'priority': 1, 'task': '시장/프로젝트 리스크 1건만 먼저 확인하기', 'source': 'fallback', 'project': 'other', 'due': None},
    ]
    task_snapshot = {
        'items': top_tasks,
        'status': 'fallback',
        'source': 'default-morning-template',
        'warning': task_snapshot.get('warning'),
        'total_count': 3,
    }

payload = {
    'generated_at': kst_now.isoformat(),
    'is_weekday': kst_now.weekday() < 5,
    'briefing_sent': False,
    'briefing_sent_at': None,
    'nq': {'data': None, 'status': 'pending', 'note': 'NQ signal check by cron'},
    'weather': {'data': weather, 'status': 'ok' if weather['condition'] != 'unknown' else 'partial'},
    'tasks': {
        'data': [
            {
                'priority': int(task.get('priority') or idx + 1),
                'task': task.get('task'),
                'project': task.get('project'),
                'due': task.get('due'),
                'source': task.get('source'),
            }
            for idx, task in enumerate(top_tasks[:3])
        ],
        'status': task_snapshot.get('status'),
        'source': task_snapshot.get('source'),
        'warning': task_snapshot.get('warning'),
        'total_count': len(top_tasks[:3]),
    },
    'active_count': len(top_tasks[:3]),
    'yesterday_summary': extract_yesterday_summary(),
    'intelligence_source': intelligence_source,
}
out_file.write_text(json.dumps(payload, ensure_ascii=False, indent=2))
print(str(out_file))
PY

echo "MORNING_OK ${OUT_FILE}"
