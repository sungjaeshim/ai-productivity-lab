# OpenClaw Monitoring Matrix (2026-03-04)

## Purpose
운영 감시 경로를 명확히 분리해서 중복 체크/중복 알림을 줄인다.

## Active Layers

| Layer | Mechanism | Frequency | Owner | Scope |
|---|---|---|---|---|
| L1 | `openclaw-guard.timer` | 2m | systemd user | 게이트웨이/핵심 서비스 생존 감시 |
| L2 | `openclaw-watchdog-health.timer` | 5m | systemd user | `/health`, `/ready` 헬스체크 + 자동 재시작 |
| L3 | `openclaw-watchdog-sessions.timer` | 2h | systemd user | 세션 누적/상태 정리 |
| L4 | root cron `openclaw-watchdog-cron-sanitize.sh` | 30m | root cron | 잘못된 cron sessionKey 정리 |
| L5 | root cron `post-backup-session-maintenance.sh` | daily 05:23 KST | root cron | 백업 직후 세션 정리 + gateway 1회 재시작 |
| L6 | OpenClaw cron (`brain` jobs) | job별 상이 | OpenClaw scheduler | 라우팅/인입/재시도 워크로드 |

## Disabled/Removed Redundancy

- Legacy compatibility restored:
  - `/root/.openclaw/workspace/scripts/system-monitor.sh`
  - 역할: 과거 cron/callme 문서 호환용 wrapper
  - canonical flow: `callme-v1-dispatch.sh`
- Legacy compatibility restored:
  - `/root/.openclaw/workspace/scripts/todoist-monitor.sh`
  - 역할: 과거 Todoist monitor 호출 호환용 wrapper
  - canonical flow: `brain-todoist-stale-check.sh --hours 24`

시스템/헬스 감시의 실제 운영 책임은 여전히 L1-L3에 있고, 위 두 파일은 이름 호환과 문서 드리프트 방지용으로만 유지한다.

## Operating Rule

1. 서비스 생존/재시작은 systemd timer(L1-L3) 우선.
2. cron 데이터 위생은 L4에서만 처리.
3. 백업 직후 무거운 세션 정리는 L5에서만 처리.
4. OpenClaw cron은 업무성 job만 유지하고 모니터링 책임은 위 레이어와 분리한다.
