#!/usr/bin/env python3
"""
Recall Router - Intelligent routing for memory retrieval.

Routes queries to appropriate search strategies (lexical/semantic/hybrid)
based on query intent, with mode support (temporal/topic/graph).
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import time
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Literal

ROOT = Path('/root/.openclaw/workspace')
MEMORY_DIR = ROOT / 'memory'
STATE_DIR = ROOT / '.state'
LOG_FILE = STATE_DIR / 'recall_router.log.jsonl'

# Route types
Route = Literal['lexical', 'semantic', 'hybrid']
Mode = Literal['temporal', 'topic', 'graph']

# Temporal keywords trigger lexical search
TEMPORAL_KEYWORDS = ['어제', '오늘', '내일', '지난', '최근', '이번', '작년', '올해', '주간', '월간', '연간',
                     'yesterday', 'today', 'tomorrow', 'last', 'recent', 'this week', 'this month']

# Topic keywords trigger semantic search
TOPIC_KEYWORDS = ['정책', '설계', '아키텍처', '개념', '원칙', '패턴', '전략', '방법론', '프레임워크',
                  'policy', 'design', 'architecture', 'concept', 'principle', 'pattern', 'strategy',
                  'framework', 'methodology']

# Graph keywords trigger hybrid search
GRAPH_KEYWORDS = ['관계', '연결', '링크', '참조', '관련', '연관', '의존', '의존성',
                  'relation', 'connection', 'link', 'reference', 'related', 'dependency']

# Generic stopwords for lightweight semantic scoring
STOPWORDS = {
    'the', 'and', 'for', 'with', 'this', 'that', 'from', 'have', 'been', 'are', 'was', 'were',
    '있다', '한다', '으로', '에서', '까지', '대한', '관련', '정리', '내용', '최근', '이번', '지난'
}


@dataclass
class RouteDecision:
    route: Route
    confidence: float
    reasoning: str


@dataclass
class RecallResult:
    query: str
    mode: Mode
    route: Route
    confidence: float
    results: list[dict]
    latency_ms: float
    result_count: int


class RecallRouter:
    """Routes memory queries based on intent and mode."""

    def __init__(self, workspace: Path = ROOT):
        self.workspace = workspace
        self.memory_dir = workspace / 'memory'
        self.second_brain = self.memory_dir / 'second-brain'

    def _query_terms(self, query: str) -> list[str]:
        """Extract and expand multilingual terms for semantic scoring."""
        raw_terms = re.findall(r"[\w가-힣]+", query.lower())
        terms = [t for t in raw_terms if len(t) >= 2 and t not in STOPWORDS]

        # Lightweight bilingual expansion for recall-heavy intents.
        synonyms: dict[str, list[str]] = {
            '결정': ['decisions', 'decision'],
            '할일': ['todo', 'tasks', 'task', 'wip'],
            '작업': ['task', 'tasks', 'work'],
            '정책': ['policy', 'policies', 'rule', 'rules'],
            '원칙': ['principle', 'principles'],
            '전략': ['strategy', 'strategies'],
            '설계': ['design', 'architecture'],
            '아키텍처': ['architecture', 'design'],
            '회고': ['retrospective', 'review'],
            'blocker': ['blocked', 'blockers'],
            'blocked': ['blocker', 'stuck'],
            'wip': ['doing', 'in-progress'],
            'todo': ['할일', '작업'],
            'memory': ['기억', '메모리'],
            '링크': ['link', 'links', 'url'],
            '관련': ['related', 'relation', 'reference'],
        }

        expanded: list[str] = []
        seen: set[str] = set()
        for term in terms:
            if term not in seen:
                expanded.append(term)
                seen.add(term)

            # Base stem for simple Korean particles (운영적인 경량 규칙)
            for suffix in ('은', '는', '이', '가', '을', '를', '에', '의', '와', '과'):
                if term.endswith(suffix) and len(term) >= 3:
                    stem = term[:-1]
                    if stem not in seen and stem not in STOPWORDS:
                        expanded.append(stem)
                        seen.add(stem)

            for s in synonyms.get(term, []):
                if s not in seen and s not in STOPWORDS:
                    expanded.append(s)
                    seen.add(s)

        return expanded

    def _candidate_files(self) -> list[Path]:
        """Return bounded candidate files for fast semantic scan."""
        files: list[Path] = []

        # Curated memory first
        memory_md = self.workspace / 'MEMORY.md'
        if memory_md.exists():
            files.append(memory_md)

        # Recent daily memories (bounded)
        daily = sorted(
            [p for p in self.memory_dir.glob('20*.md') if p.is_file()],
            key=lambda p: p.name,
            reverse=True,
        )[:21]
        files.extend(daily)

        # High-signal second-brain files
        second_brain_candidates = [
            self.second_brain / 'insights.md',
            self.second_brain / 'ideas.md',
            self.second_brain / 'work-memos.md',
            self.second_brain / 'curated-reads.md',
            self.second_brain / 'links.md',
        ]
        files.extend([p for p in second_brain_candidates if p.exists()])

        # Remove duplicates while preserving order
        seen: set[str] = set()
        unique_files: list[Path] = []
        for p in files:
            key = str(p)
            if key not in seen:
                seen.add(key)
                unique_files.append(p)
        return unique_files

    def _semantic_scan_files(self, query: str, limit: int = 10) -> list[dict]:
        """Lightweight semantic-ish retrieval via term coverage + recency bias."""
        terms = self._query_terms(query)
        if not terms:
            return []

        scored: list[dict] = []
        now = datetime.now()
        query_lower = query.lower()

        for path in self._candidate_files():
            try:
                # Skip very large files for latency safety
                if path.stat().st_size > 1_500_000:
                    continue
                text = path.read_text(encoding='utf-8', errors='ignore')
            except Exception:
                continue

            if not text.strip():
                continue

            low_text = text.lower()
            if not any(t in low_text for t in terms):
                continue

            lines = text.splitlines()
            if not lines:
                continue

            # Latency guard: avoid full-file O(n) scan on very large markdown logs.
            max_lines = 1200
            if len(lines) > max_lines:
                lines = lines[:max_lines]

            # Evaluate short windows around likely hit lines only.
            window = 3
            candidate_idx: list[int] = []
            for i, line in enumerate(lines):
                low_line = line.lower()
                if any(t in low_line for t in terms):
                    candidate_idx.append(i)

            per_file_hits = 0
            for i in candidate_idx:
                start = max(0, i - 1)
                end = min(len(lines), i + window)
                snippet = '\n'.join(lines[start:end]).strip()
                if not snippet:
                    continue

                low = snippet.lower()
                hit_terms = [t for t in terms if t in low]
                token_hits = len(hit_terms)
                if token_hits == 0:
                    continue

                unique_hits = len(set(hit_terms))
                coverage = unique_hits / max(len(set(terms)), 1)

                score = (unique_hits * 1.0) + (coverage * 3.0)
                if query_lower in low:
                    score += 2.5

                # Emphasize dense matches in section headers / bullets.
                first_line = lines[i].strip().lower() if i < len(lines) else ''
                if first_line.startswith('##') or first_line.startswith('###'):
                    score += 0.4
                if first_line.startswith('- ') or first_line.startswith('* '):
                    score += 0.2

                # Simple recency boost for daily memory files
                m = re.search(r"(20\d{2}-\d{2}-\d{2})", path.name)
                if m:
                    try:
                        day = datetime.strptime(m.group(1), "%Y-%m-%d")
                        age_days = max((now - day).days, 0)
                        score += max(0.0, 1.5 - (age_days / 30.0))
                    except Exception:
                        pass

                scored.append({
                    'id': f"{path.name}:{i}",
                    'content': snippet[:420],
                    'source': str(path),
                    'score': round(score, 3),
                    'route': 'semantic'
                })
                per_file_hits += 1
                if per_file_hits >= 120:
                    break

        scored.sort(key=lambda x: x.get('score', 0.0), reverse=True)

        deduped: list[dict] = []
        seen_snippets: set[str] = set()
        for item in scored:
            key = f"{item['source']}::{item['content'][:120]}"
            if key in seen_snippets:
                continue
            seen_snippets.add(key)
            deduped.append(item)
            if len(deduped) >= limit:
                break

        return deduped

    def _classify_route(self, query: str, mode: Mode) -> RouteDecision:
        """
        Classify route based on query keywords and mode.

        Priority:
        1. Mode-specific override (graph -> hybrid)
        2. Temporal keywords -> lexical
        3. Topic keywords -> semantic
        4. Graph keywords -> hybrid
        5. Default -> hybrid
        """
        query_lower = query.lower()

        # Graph mode always routes to hybrid
        if mode == 'graph':
            return RouteDecision(
                route='hybrid',
                confidence=0.9,
                reasoning='Graph mode specified, using hybrid route'
            )

        # Temporal mode prefers lexical
        if mode == 'temporal':
            for kw in TEMPORAL_KEYWORDS:
                if kw in query_lower:
                    return RouteDecision(
                        route='lexical',
                        confidence=0.85,
                        reasoning='Temporal keyword detected in temporal mode'
                    )
            return RouteDecision(
                route='lexical',
                confidence=0.7,
                reasoning='Temporal mode default (no keyword detected)'
            )

        # Topic mode prefers semantic
        if mode == 'topic':
            for kw in TOPIC_KEYWORDS:
                if kw in query_lower:
                    return RouteDecision(
                        route='semantic',
                        confidence=0.85,
                        reasoning='Topic keyword detected in topic mode'
                    )
            return RouteDecision(
                route='semantic',
                confidence=0.7,
                reasoning='Topic mode default (no keyword detected)'
            )

        # Fallback: check keywords without mode
        for kw in TEMPORAL_KEYWORDS:
            if kw in query_lower:
                return RouteDecision(
                    route='lexical',
                    confidence=0.75,
                    reasoning='Temporal keyword detected (default mode)'
                )

        for kw in TOPIC_KEYWORDS:
            if kw in query_lower:
                return RouteDecision(
                    route='semantic',
                    confidence=0.75,
                    reasoning='Topic keyword detected (default mode)'
                )

        for kw in GRAPH_KEYWORDS:
            if kw in query_lower:
                return RouteDecision(
                    route='hybrid',
                    confidence=0.75,
                    reasoning='Graph keyword detected (default mode)'
                )

        # Default to hybrid for general queries
        return RouteDecision(
            route='hybrid',
            confidence=0.5,
            reasoning='Default route (no specific intent detected)'
        )

    def _search_lexical(self, query: str, limit: int = 10) -> list[dict]:
        """Lexical search using SQLite FTS."""
        results = []

        # Try memory_mirror.db first
        mirror_db = ROOT / 'data' / 'memory_mirror.db'
        if mirror_db.exists():
            try:
                con = sqlite3.connect(mirror_db)
                cur = con.cursor()
                cur.execute(
                    "SELECT id, content, source, timestamp FROM memory WHERE content MATCH ? ORDER BY rowid LIMIT ?",
                    (query, limit)
                )
                rows = cur.fetchall()
                results.extend([
                    {
                        'id': r[0],
                        'content': r[1][:200] + '...' if len(r[1]) > 200 else r[1],
                        'source': r[2],
                        'timestamp': r[3],
                        'route': 'lexical'
                    }
                    for r in rows
                ])
                con.close()
            except Exception as e:
                # Degrade gracefully
                pass

        # Fallback to recent daily files + MEMORY.md with phrase OR token matching
        query_lower = query.lower()
        terms = self._query_terms(query)
        candidates: list[Path] = [self.workspace / 'MEMORY.md']

        today = datetime.now()
        for days_ago in range(0, 14):
            day = today - timedelta(days=days_ago)
            candidates.append(self.memory_dir / f"{day:%Y-%m-%d}.md")

        for path in candidates:
            if len(results) >= limit:
                break
            if not path.exists():
                continue

            try:
                content = path.read_text(encoding='utf-8', errors='ignore')
            except Exception:
                continue

            lines = content.split('\n')
            for i, line in enumerate(lines):
                low = line.lower()
                phrase_hit = query_lower in low
                token_hit = any(t in low for t in terms) if terms else False
                if not phrase_hit and not token_hit:
                    continue

                start = max(0, i - 1)
                end = min(len(lines), i + 2)
                snippet = '\n'.join(lines[start:end]).strip()
                results.append({
                    'id': f"{path.name}:{i}",
                    'content': snippet[:350],
                    'source': str(path),
                    'timestamp': datetime.now().isoformat(),
                    'route': 'lexical'
                })
                if len(results) >= limit:
                    break

        # Temporal context backfill: if strict keyword match is sparse, return recent structured snippets.
        if len(results) < min(3, limit):
            backfill_headers = ('### decisions', '### blockers', '### active tasks / wip')
            seen_ids = {r.get('id') for r in results}

            for path in candidates[1:]:  # skip MEMORY.md, prioritize dated daily notes
                if len(results) >= min(3, limit):
                    break
                if not path.exists():
                    continue

                try:
                    lines = path.read_text(encoding='utf-8', errors='ignore').split('\n')
                except Exception:
                    continue

                for i, line in enumerate(lines):
                    low = line.strip().lower()
                    if not any(low.startswith(h) for h in backfill_headers):
                        continue

                    start = i
                    end = min(len(lines), i + 4)
                    snippet = '\n'.join(lines[start:end]).strip()
                    if not snippet:
                        continue

                    rid = f"{path.name}:fallback:{i}"
                    if rid in seen_ids:
                        continue

                    results.append({
                        'id': rid,
                        'content': snippet[:350],
                        'source': str(path),
                        'timestamp': datetime.now().isoformat(),
                        'route': 'lexical'
                    })
                    seen_ids.add(rid)

                    if len(results) >= min(3, limit):
                        break

        return results[:limit]

    def _search_semantic(self, query: str, limit: int = 10) -> list[dict]:
        """Semantic search via bounded file-scan scoring + optional AC2 FTS."""
        results = self._semantic_scan_files(query, limit)

        # Optional AC2 FTS enrichment (only when query likely targets AC2 corpus)
        query_lower = query.lower()
        ac2_markers = ('ac2', 'agile', '김창준', '세컨드브레인', 'second brain', 'agilestory')
        use_ac2 = any(m in query_lower for m in ac2_markers)

        ac2_db = self.second_brain / 'ac2' / 'agilestory' / 'manifests' / 'ac2_search.db'
        if use_ac2 and ac2_db.exists() and len(results) < limit:
            try:
                con = sqlite3.connect(ac2_db)
                cur = con.cursor()
                cur.execute(
                    "SELECT post_id, title, tags, url, bm25(docs) as score FROM docs WHERE docs MATCH ? ORDER BY score LIMIT ?",
                    (query, max(1, limit - len(results)))
                )
                rows = cur.fetchall()
                results.extend([
                    {
                        'id': r[0],
                        'title': r[1],
                        'tags': r[2],
                        'content': f"{r[1]} - {r[2]}",
                        'source': r[3],
                        'score': float(abs(r[4])) if r[4] is not None else 0.0,
                        'route': 'semantic'
                    }
                    for r in rows
                ])
                con.close()
            except Exception:
                pass

        # Backstop fallback
        if len(results) < min(3, limit):
            fallback = self._search_lexical(query, limit)
            for r in fallback:
                r['route'] = 'semantic'
                results.append(r)
                if len(results) >= limit:
                    break

        return results[:limit]

    def _search_hybrid(self, query: str, limit: int = 10) -> list[dict]:
        """Hybrid search combining lexical and semantic."""
        # Keep hybrid latency predictable by capping branch fan-out.
        lexical_limit = max(3, min(limit, (limit // 2) + 1))
        semantic_limit = max(3, min(limit, limit // 2))

        ql = query.lower()
        # Graph-like prompts tend to be broad; reduce semantic branch width slightly.
        if any(k in ql for k in ('링크', 'related', 'connection', 'dependency', '참조', '연결')):
            semantic_limit = max(3, semantic_limit - 1)

        lexical_results = self._search_lexical(query, lexical_limit)
        semantic_results = self._search_semantic(query, semantic_limit)

        # Deduplicate by ID
        seen_ids = set()
        results = []

        for r in lexical_results + semantic_results:
            if r['id'] not in seen_ids:
                seen_ids.add(r['id'])
                results.append(r)
                r['route'] = 'hybrid'
                if len(results) >= limit:
                    break

        return results[:limit]

    def search(self, query: str, mode: Mode = 'hybrid', limit: int = 10) -> RecallResult:
        """Execute search with routing and logging."""
        start_time = time.time()

        # Classify route
        decision = self._classify_route(query, mode)

        # Execute search based on route
        if decision.route == 'lexical':
            results = self._search_lexical(query, limit)
        elif decision.route == 'semantic':
            results = self._search_semantic(query, limit)
        else:  # hybrid
            results = self._search_hybrid(query, limit)

        latency_ms = (time.time() - start_time) * 1000

        # Build result
        result = RecallResult(
            query=query,
            mode=mode,
            route=decision.route,
            confidence=decision.confidence,
            results=results,
            latency_ms=latency_ms,
            result_count=len(results)
        )

        # Log to JSONL
        self._log_result(result)

        return result

    def _log_result(self, result: RecallResult) -> None:
        """Log search result to JSONL file."""
        STATE_DIR.mkdir(parents=True, exist_ok=True)

        log_entry = {
            'ts': datetime.now().isoformat(timespec='milliseconds'),
            'query': result.query,
            'mode': result.mode,
            'route': result.route,
            'latency_ms': round(result.latency_ms, 2),
            'result_count': result.result_count
        }

        with open(LOG_FILE, 'a', encoding='utf-8') as f:
            f.write(json.dumps(log_entry, ensure_ascii=False) + '\n')


def main():
    parser = argparse.ArgumentParser(description='Recall Router - Intelligent memory retrieval')
    parser.add_argument('--query', type=str, required=True, help='Search query')
    parser.add_argument('--mode', type=str, choices=['temporal', 'topic', 'graph', 'hybrid'],
                        default='hybrid', help='Search mode (temporal/topic/graph/hybrid)')
    parser.add_argument('--limit', type=int, default=10, help='Result limit')
    parser.add_argument('--json', action='store_true', help='Output JSON format')

    args = parser.parse_args()

    router = RecallRouter()
    result = router.search(args.query, args.mode, args.limit)

    if args.json:
        output = {
            'query': result.query,
            'mode': result.mode,
            'route': result.route,
            'confidence': result.confidence,
            'latency_ms': result.latency_ms,
            'result_count': result.result_count,
            'results': result.results
        }
        print(json.dumps(output, ensure_ascii=False, indent=2))
    else:
        print(f"Query: {result.query}")
        print(f"Mode: {result.mode} | Route: {result.route} (confidence: {result.confidence:.2f})")
        print(f"Latency: {result.latency_ms:.2f}ms | Results: {result.result_count}")
        print()
        for i, r in enumerate(result.results, 1):
            content = r.get('content', r.get('title', ''))
            source = r.get('source', 'unknown')
            print(f"[{i}] {content[:100]}...")
            print(f"    Source: {source}")
            print()


if __name__ == '__main__':
    main()
