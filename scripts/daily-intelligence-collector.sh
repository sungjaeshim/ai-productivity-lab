#!/usr/bin/env bash
set -euo pipefail

DATE_KST="$(TZ=Asia/Seoul date +%Y-%m-%d)"
OUT="/root/.openclaw/workspace/data/intelligence-${DATE_KST}.json"
mkdir -p /root/.openclaw/workspace/data

python3 - <<'PY'
import json, re, urllib.request, urllib.parse, xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path
from collections import defaultdict

out = Path('/root/.openclaw/workspace/data/intelligence-' + datetime.now().astimezone().strftime('%Y-%m-%d') + '.json')

FEEDS = [
    # Macro / markets
    ('https://news.google.com/rss/search?q=NASDAQ+futures+OR+S%26P+500+OR+US+Treasury+yields&hl=en-US&gl=US&ceid=US:en','Google News (Trading)','trading',60),
    ('https://news.google.com/rss/search?q=Middle+East+oil+Iran+markets&hl=en-US&gl=US&ceid=US:en','Google News (Macro Risk)','trading',60),
    # AI / tech
    ('https://news.google.com/rss/search?q=AI+agents+OR+LLM+OR+OpenAI+Anthropic+Google+AI&hl=en-US&gl=US&ceid=US:en','Google News (AI)','ai_tech',60),
    # Marketing / growth
    ('https://news.google.com/rss/search?q=marketing+strategy+digital+marketing+growth&hl=en-US&gl=US&ceid=US:en','Google News (Marketing)','marketing',60),
    # High-credibility RSS (best-effort)
    ('https://feeds.reuters.com/reuters/businessNews','Reuters Business','trading',85),
    ('https://feeds.reuters.com/Reuters/worldNews','Reuters World','trading',85),
]

IMPORTANT_KWS = {
    'trading': ['nasdaq', 'futures', 'yield', 'fed', 'inflation', 'oil', 'iran', 'vix', 'dollar'],
    'ai_tech': ['agent', 'llm', 'openai', 'anthropic', 'model', 'inference', 'gpu'],
    'marketing': ['growth', 'conversion', 'ads', 'seo', 'content', 'retention'],
}

UA = {'User-Agent':'Mozilla/5.0 (OpenClaw Daily Intelligence Collector)'}


def normalize_title(t: str) -> str:
    t = (t or '').strip().lower()
    t = re.sub(r'\s+', ' ', t)
    t = re.sub(r'[^\w\s]', '', t)
    return t[:140]


def safe_domain(link: str, title: str = '') -> str:
    # Google News RSS often uses news.google.com links; try to infer publisher from title suffix.
    t = (title or '').strip()
    if ' - ' in t:
        hint = t.rsplit(' - ', 1)[-1].strip().lower()
        hint = re.sub(r'\s+', '-', hint)
        hint = re.sub(r'[^a-z0-9.-]', '', hint)
        if hint and len(hint) > 2:
            return f'publisher:{hint}'
    try:
        return urllib.parse.urlparse(link).netloc.lower().replace('www.', '')
    except Exception:
        return ''


def score_item(title: str, niche: str, base: int) -> int:
    s = base
    lt = (title or '').lower()
    for kw in IMPORTANT_KWS.get(niche, []):
        if kw in lt:
            s += 3
    return max(40, min(98, s))


def parse_feed(url, source, niche, cred):
    req = urllib.request.Request(url, headers=UA)
    try:
        with urllib.request.urlopen(req, timeout=12) as r:
            data = r.read()
    except Exception:
        return []

    try:
        root = ET.fromstring(data)
    except Exception:
        return []

    items = []

    # RSS style
    for it in root.findall('.//item')[:12]:
        title = (it.findtext('title') or '').strip()
        link = (it.findtext('link') or '').strip()
        pub = (it.findtext('pubDate') or '').strip()
        desc = (it.findtext('description') or '').strip()
        desc = re.sub(r'<[^>]+>', '', desc)[:280]
        if not title:
            continue
        items.append({
            'source': source,
            'source_channel': 'RSS',
            'source_credibility': cred,
            'title': title,
            'link': link,
            'domain': safe_domain(link, title),
            'published': pub,
            'summary': desc,
            'niches': [niche],
            'importance_score': score_item(title, niche, cred),
        })

    # Atom fallback (if present)
    if not items:
        ns = {'a': 'http://www.w3.org/2005/Atom'}
        for e in root.findall('.//a:entry', ns)[:12]:
            title = (e.findtext('a:title', default='', namespaces=ns) or '').strip()
            pub = (e.findtext('a:updated', default='', namespaces=ns) or '').strip()
            link_el = e.find('a:link', ns)
            link = (link_el.get('href') if link_el is not None else '') or ''
            if not title:
                continue
            items.append({
                'source': source,
                'source_channel': 'RSS',
                'source_credibility': cred,
                'title': title,
                'link': link,
                'domain': safe_domain(link, title),
                'published': pub,
                'summary': '',
                'niches': [niche],
                'importance_score': score_item(title, niche, cred),
            })

    return items

all_items = []
for u, s, n, c in FEEDS:
    all_items.extend(parse_feed(u, s, n, c))

# Dedup by normalized title
seen = set()
dedup = []
for x in all_items:
    k = normalize_title(x['title'])
    if not k or k in seen:
        continue
    seen.add(k)
    dedup.append(x)

# Domain diversity cap: max 2 headlines/domain in final list
domain_count = defaultdict(int)
ranked = sorted(dedup, key=lambda x: x.get('importance_score', 0), reverse=True)
final_items = []
for it in ranked:
    d = it.get('domain', '')
    if d and domain_count[d] >= 2:
        continue
    final_items.append(it)
    if d:
        domain_count[d] += 1
    if len(final_items) >= 14:
        break

# fallback from previous file if empty
if not final_items:
    prev = sorted(Path('/root/.openclaw/workspace/data').glob('intelligence-*.json'))
    if prev:
        try:
            data = json.loads(prev[-1].read_text())
            final_items = data.get('top_headlines', [])[:8]
        except Exception:
            final_items = []

by_niche = defaultdict(list)
for it in final_items:
    for n in it.get('niches', []):
        by_niche[n].append(it)

payload = {
    'generated_at': datetime.now(timezone.utc).isoformat(),
    'top_headlines': final_items,
    'by_niche': {k: v[:6] for k, v in by_niche.items()},
    'signal_noise': {
        'signals': [x for x in final_items if x.get('importance_score', 0) >= 78][:8],
        'noise': [x for x in final_items if x.get('importance_score', 0) < 65][:8],
    },
    'quality': {
        'sources_used': sorted({x.get('source') for x in all_items}),
        'unique_domains': len({x.get('domain') for x in final_items if x.get('domain')}),
        'domain_cap': 2,
    },
    'total_collected': len(all_items),
    'total_relevant': len(final_items),
}

out.write_text(json.dumps(payload, ensure_ascii=False, indent=2))
print(str(out))
PY

echo "INTEL_OK ${OUT}"