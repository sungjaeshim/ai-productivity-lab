#!/usr/bin/env python3
"""
Naver domestic news brief generator.
- Reads NAVER credentials from /root/.openclaw/secrets/providers.json
- Fetches latest news by keyword from Naver Search News API
- Deduplicates and scores importance
- Prints compact briefing text (Korean)
"""

from __future__ import annotations

import argparse
import datetime as dt
import email.utils
import hashlib
import json
import os
import re
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

SEOUL = dt.timezone(dt.timedelta(hours=9))
SECRETS_PATH = Path('/root/.openclaw/secrets/providers.json')
STATE_PATH = Path('/root/.openclaw/workspace/.state/naver-news-last-hash.txt')

DEFAULT_KEYWORDS = [
    '한국 경제',
    '코스피 코스닥',
    '반도체 AI',
    '금리 물가 환율',
    '정책 규제',
]

HIGH_IMPACT_TOKENS = {
    '속보': 20,
    '긴급': 20,
    '발표': 12,
    '인상': 10,
    '인하': 10,
    '급등': 10,
    '급락': 10,
    '파업': 9,
    '규제': 9,
    '환율': 9,
    '금리': 9,
    '물가': 8,
    '실적': 8,
    '수출': 8,
    '관세': 8,
    '반도체': 8,
    'ai': 7,
    '코스피': 7,
    '코스닥': 7,
    '삼성전자': 7,
    'sk하이닉스': 7,
}


@dataclass
class NewsItem:
    title: str
    description: str
    link: str
    source: str
    pub_date: dt.datetime
    keyword: str
    score: int = 0


def strip_html(text: str) -> str:
    text = re.sub(r'<[^>]+>', '', text or '')
    return re.sub(r'\s+', ' ', text).strip()


def load_keys() -> tuple[str, str]:
    if not SECRETS_PATH.exists():
        raise FileNotFoundError(f'secrets file missing: {SECRETS_PATH}')
    data = json.loads(SECRETS_PATH.read_text(encoding='utf-8'))
    cid = data.get('naver_client_id', '').strip()
    csec = data.get('naver_client_secret', '').strip()
    if not cid or not csec:
        raise ValueError('naver_client_id / naver_client_secret missing in secrets file')
    return cid, csec


def fetch_news(keyword: str, client_id: str, client_secret: str, display: int = 20) -> list[NewsItem]:
    q = urllib.parse.quote(keyword)
    url = f'https://openapi.naver.com/v1/search/news.json?query={q}&display={display}&sort=date'
    req = urllib.request.Request(
        url,
        headers={
            'X-Naver-Client-Id': client_id,
            'X-Naver-Client-Secret': client_secret,
            'User-Agent': 'openclaw-naver-news-brief/1.0',
        },
    )
    with urllib.request.urlopen(req, timeout=12) as resp:
        payload = json.loads(resp.read().decode('utf-8', errors='ignore'))

    out: list[NewsItem] = []
    for raw in payload.get('items', []):
        title = strip_html(raw.get('title', ''))
        desc = strip_html(raw.get('description', ''))
        link = (raw.get('originallink') or raw.get('link') or '').strip()
        if not title or not link:
            continue
        source = urllib.parse.urlparse(link).netloc or 'unknown'
        pub_raw = raw.get('pubDate', '')
        try:
            pub_dt = email.utils.parsedate_to_datetime(pub_raw)
            if pub_dt.tzinfo is None:
                pub_dt = pub_dt.replace(tzinfo=dt.timezone.utc)
            pub_dt = pub_dt.astimezone(SEOUL)
        except Exception:
            pub_dt = dt.datetime.now(tz=SEOUL)
        out.append(
            NewsItem(
                title=title,
                description=desc,
                link=link,
                source=source,
                pub_date=pub_dt,
                keyword=keyword,
            )
        )
    return out


def dedupe(items: Iterable[NewsItem]) -> list[NewsItem]:
    seen: set[str] = set()
    out: list[NewsItem] = []
    for it in items:
        norm_title = re.sub(r'[^0-9a-zA-Z가-힣]+', '', it.title).lower()
        key = f"{norm_title}|{it.link.split('?')[0]}"
        if key in seen:
            continue
        seen.add(key)
        out.append(it)
    return out


def score_item(it: NewsItem, now: dt.datetime) -> int:
    age_hours = max(0.0, (now - it.pub_date).total_seconds() / 3600.0)
    recency = max(0, int(40 - age_hours * 4))  # 10h 지나면 0 근접

    text = f"{it.title} {it.description}".lower()
    impact = 0
    for token, w in HIGH_IMPACT_TOKENS.items():
        if token in text:
            impact += w

    diversity = 6 if len(it.keyword) > 0 else 0
    return recency + impact + diversity


def make_digest(items: list[NewsItem]) -> str:
    s = '\n'.join(f"{x.title}|{x.link.split('?')[0]}" for x in items)
    return hashlib.sha1(s.encode('utf-8')).hexdigest()


def format_brief(items: list[NewsItem], now: dt.datetime) -> str:
    def level(avg: int) -> str:
        if avg >= 78:
            return '🔥 높음'
        if avg >= 64:
            return '⚖️ 보통'
        return '🧊 낮음'

    def signal(score: int) -> str:
        if score >= 78:
            return '🔴'
        if score >= 68:
            return '🟡'
        return '🟢'

    def trim(title: str, max_len: int = 56) -> str:
        return title if len(title) <= max_len else title[: max_len - 1] + '…'

    def compact_link(raw: str) -> str:
        try:
            p = urllib.parse.urlparse(raw)
            q = urllib.parse.parse_qs(p.query, keep_blank_values=False)
            keep_keys = ('id', 'idxno', 'news_id', 'article', 'aid', 'sid1', 'sid2')
            kept = []
            for k in keep_keys:
                if k in q and q[k]:
                    kept.append((k, q[k][0]))
            new_query = urllib.parse.urlencode(kept)
            return urllib.parse.urlunparse((p.scheme, p.netloc, p.path, '', new_query, ''))
        except Exception:
            return raw

    def impact_action(it: NewsItem) -> tuple[str, str]:
        txt = f"{it.title} {it.description}".lower()
        if any(k in txt for k in ['유가', '중동', '전쟁', '지정학']):
            return ('NQ 변동성↑ · 원자재↑', '레버리지 축소 / 관망')
        if any(k in txt for k in ['환율', '달러', 'usd', '원화']):
            return ('USDKRW 변동성↑', '환노출 점검 / 분할 대응')
        if any(k in txt for k in ['금리', '물가', '인상', '인하']):
            return ('성장주 변동성↑', '엔트리 보수화')
        if any(k in txt for k in ['반도체', 'ai', '실적']):
            return ('테크 섹터 민감도↑', '핵심주 추세확인 후 대응')
        return ('시장 심리 영향 가능', '무리한 추격 금지')

    lines: list[str] = []
    lines.append(f"🗞️ 국내 뉴스 [NAVER] | {now.strftime('%m/%d %H:%M')}")

    if not items:
        lines.append('• 수집 결과 없음')
        return '\n'.join(lines)

    avg_score = int(sum(i.score for i in items) / len(items))
    hot = [i for i in items if i.score >= avg_score + 10]
    lines.append(f"🎯 {len(items)}건 · 고중요 {len(hot)} · 평균 {avg_score}점 · {level(avg_score)}")
    lines.append('')

    top = items[:5]
    for idx, it in enumerate(top, 1):
        impact, action = impact_action(it)
        url = compact_link(it.link)
        lines.append(f"{idx}️⃣ {signal(it.score)} [경제] {trim(it.title)}")
        lines.append(f"   영향/행동: {impact} | {action}")
        lines.append(f"   🔗 [link]({url})")

    return '\n'.join(lines).rstrip()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--keywords', default='|'.join(DEFAULT_KEYWORDS), help='키워드를 | 로 구분')
    ap.add_argument('--top', type=int, default=8)
    ap.add_argument('--no-dedupe-check', action='store_true', help='이전 해시 비교 스킵')
    args = ap.parse_args()

    now = dt.datetime.now(tz=SEOUL)
    keywords = [k.strip() for k in args.keywords.split('|') if k.strip()]
    if not keywords:
        keywords = DEFAULT_KEYWORDS

    cid, csec = load_keys()

    all_items: list[NewsItem] = []
    for kw in keywords:
        all_items.extend(fetch_news(kw, cid, csec, display=20))

    items = dedupe(all_items)
    for it in items:
        it.score = score_item(it, now)
    items.sort(key=lambda x: (x.score, x.pub_date), reverse=True)
    items = items[: max(args.top, 1)]

    digest = make_digest(items)
    if not args.no_dedupe_check:
        prev = STATE_PATH.read_text(encoding='utf-8').strip() if STATE_PATH.exists() else ''
        if prev == digest:
            print('NO_CHANGE')
            return 0

    brief = format_brief(items, now)
    print(brief)

    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(digest, encoding='utf-8')
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as e:
        print(f'ERROR: {e}')
        raise
