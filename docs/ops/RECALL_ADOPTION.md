# Recall Adoption (OpenClaw)

## Goal
Session restart 후 **30초 내** 이전 결정/할일 복원.

## Minimal Operating Rules
1. Daily memory(`memory/YYYY-MM-DD.md`)에 아래 3섹션을 유지한다.
   - `### Decisions`
   - `### Blockers`
   - `### Active Tasks / WIP`
2. 과거 맥락 질문 시작 시:
   - `memory_search` → `memory_get` 순서로 필요한 줄만 조회
   - 또는 `recall_router` 활용 (추천)
3. 매일 점검:
   - `python3 scripts/memory_promote.py`
   - `python3 scripts/recall_quick_check.py`

## Recall Router (New)

### Overview
Recall Router는 쿼리 의도를 분석하여 적절한 검색 전략(lexical/semantic/hybrid)으로 자동 라우팅합니다.

### Routes
- **lexical**: 키워드 기반 검색 (SQLite FTS, daily memory 파일)
  - 시간 관련 쿼리에 적합: "어제 결정", "지난주 회의"
- **semantic**: 의미 기반 검색 (second-brain knowledge base)
  - 개념/설계 관련 쿼리에 적합: "정책", "아키텍처", "패턴"
- **hybrid**: lexical + semantic 결합
  - 일반 쿼리, 관계성 탐색에 적합

### Modes
- **temporal**: 시간 기반 검색 (lexical 선호)
- **topic**: 주제 기반 검색 (semantic 선호)
- **graph**: 관계/연결 기반 검색 (hybrid 강제)
- **hybrid**: 자동 라우팅 (default)

### Usage Examples

Basic search:
```bash
python3 scripts/recall_router.py --query "어제 결정"
python3 scripts/recall_router.py --query "memory_search fallback 정책"
```

Mode-specific search:
```bash
python3 scripts/recall_router.py --query "어제 결정" --mode temporal
python3 scripts/recall_router.py --query "memory_search fallback 정책" --mode topic
python3 scripts/recall_router.py --query "관련된 링크" --mode graph
```

JSON output (integration):
```bash
python3 scripts/recall_router.py --query "아키텍처" --json
```

Custom limit:
```bash
python3 scripts/recall_router.py --query "최근 변경" --limit 20
```

### Evaluator
Router 성능 평가:
```bash
python3 scripts/recall_router_eval.py
python3 scripts/recall_router_eval.py --verbose  # 쿼리별 상세 정보
python3 scripts/recall_router_eval.py --json  # JSON 출력
```

Metrics (Visibility + Measurability)
- `restore_readiness_score` (0~100)
- `status` (PASS/WARN)
- `sections_today.Decisions/Blockers/Active Tasks / WIP`
- `route_p95` (95th percentile latency per route)
- `fallback_rate_estimate` (semantic-to-lexical fallback rate)
- `top3_hit_rate` (queries with >=3 results)

## Status Files
- `.state/recall_status.json` - 기본 상태
- `.state/recall_router.log.jsonl` - 라우터 쿼리 로그
- `.state/recall_router_eval_metrics.json` - 평가 메트릭

## PASS 기준
- today memory 파일 존재
- MEMORY.md 존재
- today Decisions 1개 이상
- today Active Tasks 1개 이상
- `restore_readiness_score >= 80`
- `route_p95.hybrid < 500ms` (optional)
- `top3_hit_rate >= 70%` (optional)

## Quick Commands
```bash
# 기본 상태 점검
python3 /root/.openclaw/workspace/scripts/recall_quick_check.py
cat /root/.openclaw/workspace/.state/recall_status.json

# 라우터 검색
python3 /root/.openclaw/workspace/scripts/recall_router.py --query "어제 결정" --mode temporal

# 라우터 평가
python3 /root/.openclaw/workspace/scripts/recall_router_eval.py
```
