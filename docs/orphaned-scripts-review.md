# Orphaned Scripts Review

Generated against inventory snapshot `2026-03-06T05:00:12Z`.

현재 이 문서는 `registry.yaml`의 `overrides`에 반영한 `keep`/`candidate`/`hold` 결정 이력을 설명한다.
즉, 아래에 남긴 항목은 더 이상 "무주인 orphaned"로 두지 않고 상태를 명시적으로 관리한다.

## Attic Now

이 그룹은 현재 참조가 없고, git dirt도 없고, 지금 구조에서 다시 쓸 entrypoint도 보이지 않아 attic로 이동했다.

| Script | Decision | Reason |
|---|---|---|
| `fetch_unsplash.py` | moved to attic | 블로그 이미지 보조 스크립트지만 현재 callers가 없고 독립 owner도 없다. |
| `memory-grep-search.sh` | moved to attic | 메모리 grep fallback 유틸이지만 현재 docs/caller 연결이 전혀 없다. |
| `cron-daily-diff-report.py` | moved to attic | cron 분석 리포트지만 caller와 canonical 진입점이 끝내 생기지 않았다. |
| `notion_log.py` | moved to attic | 독립 Notion 로거지만 현재 연결된 호출 경로가 없었다. |
| `usdkrw_alert.py` | moved to attic | 시장 알림 유틸이지만 활성 스케줄러나 owner가 없었다. |

## Hold: User-Touched

이 그룹은 최근 수동 작업이 섞여 있어 자동 정리 대상에서 제외한다.

| Script | Git state | Reason |
|---|---|---|
| `local-rescue-model-eval.sh` | `??` | 오늘 생성된 실험성 로컬 rescue 평가 스크립트다. |
| `telegram-egress-monitor.sh` | `M` | 오늘 수정된 모니터링 스크립트라 자동 attic 금지다. |
| `test-send-guard.sh` | `??` | 오늘 생성된 send guard 검증 스크립트다. |

## Keep

caller는 없지만 수동 운영 유틸이거나 시스템 영향이 있어 `keep` override로 유지한다.

| Script | Why it stays |
|---|---|
| `auto-blog-post.sh` | `ai-productivity-lab` 경로가 실제로 존재하고, 수동 실행 유틸일 가능성이 높다. |
| `blog-report.sh` | 블로그 레포를 읽는 수동 리포트 성격이라 우선 유지한다. |
| `check-growth-second-brain-public.sh` | 외부 dashboard healthcheck 성격이라 수동 검증 도구로 남긴다. |
| `enforce-dns-fallback.sh` | 시스템 DNS를 건드리는 스크립트라 정리보다 owner 확인이 먼저다. |
| `full-backup.sh` | 수동 백업 도구라 직접 replacement 없이 attic로 보내지 않는다. |
| `git-ai-note.sh` | git notes 기반 수동 도구라 orphaned여도 utility value가 있다. |

## Next Attic Candidate

현재는 남겨두지만 다음 정리에서 가장 먼저 attic 여부를 다시 판단할 그룹이다.

| Script | Why it is next |
|---|---|
| `sync-growth-site-second-brain.sh` | export 대상 경로는 있지만 자동/수동 caller 신호가 전혀 없다. |

## Next Sweep

다음 정리 때는 아래 순서로 보면 된다.

1. `Hold: User-Touched`가 실제 운영으로 편입됐는지 확인
2. `Next Attic Candidate`가 계속 caller 없이 남으면 attic 이동
3. `brain-*` orphan가 다시 나오면 `brainctl.sh` subcommand로 흡수 가능한지 먼저 확인
