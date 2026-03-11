# Script Governance

## Goal

스크립트가 계속 늘어나도 `무엇이 live인지`, `무엇이 legacy인지`, `어디가 canonical entrypoint인지`를 한 번에 판단할 수 있게 한다.

## Canonical Entrypoints

- `scripts/brainctl.sh`
- `scripts/sendctl.sh`
- `scripts/system-monitor.sh` (legacy compatibility wrapper)
- `scripts/todoist-monitor.sh` (legacy compatibility wrapper)

새 top-level 스크립트를 바로 추가하지 말고, 먼저 기존 canonical entrypoint의 subcommand로 넣을 수 있는지 확인한다.

## Source Of Truth

1. `scripts/registry.yaml`
2. `scripts/script_inventory.py`
3. generated reports:
   - `reports/script-inventory.json`
   - `docs/script-inventory.md`

`script_inventory.py`는 현재 `systemd`, `openclaw cron`, `user crontab`, `/etc/pam.d`, workspace docs/internal refs를 같이 본다.

## Status Definitions

- `live`: systemd, openclaw cron, user crontab, `/etc/pam.d` hook 중 하나라도 현재 연결됨
- `canonical`: 앞으로의 표준 entrypoint지만 아직 callers 전환 중
- `compat`: 옛 이름을 받기 위한 호환 래퍼
- `keep`: 자동 호출은 없지만 계속 유지하기로 결정한 수동 실행 유틸
- `candidate`: 지금은 남겨두되 다음 attic sweep에서 우선 검토할 유틸
- `hold`: 최근 작업이 섞여 있어 보류 중인 스크립트
- `dormant`: 현재 live는 아니지만 docs/internal callers가 남아 있음
- `orphaned`: live/passive refs가 모두 없음
- `retired`: attic로 이동한 과거 entrypoint
- `missing`: 문서/비활성 cron에 이름은 남았지만 워크스페이스 구현은 없음

## Inventory Refresh

```bash
python3 /root/.openclaw/workspace/scripts/script_inventory.py --write
```

리포트를 갱신한 뒤 아래 순서로 정리한다.

1. `live` 확인
2. `canonical` adoption 확인
3. `compat` 유지 여부 확인
4. `keep`, `candidate`, `hold`가 registry override와 맞는지 확인
5. `dormant` 중 실제 필요 항목만 남김
6. `candidate`는 다음 attic sweep 우선순위로 검토
7. `orphaned`는 즉시 attic 후보로 검토

## Archive Rule

바로 삭제하지 않는다.

1. replacement가 명확해야 한다.
2. active systemd/openclaw cron caller가 없어야 한다.
3. attic로 먼저 이동한다.
4. inventory report에서 `retired`로 표시한다.

## Current Family Mapping

### Brain

- canonical: `brainctl.sh`
- examples:
  - `brainctl.sh autopull telegram`
  - `brainctl.sh ingest link`
  - `brainctl.sh todo stale`
  - `brainctl.sh ops queue-autoclean`
  - `brainctl.sh repair inbox-resend-clean`

### Send

- canonical: `sendctl.sh`
- examples:
  - `sendctl.sh guarded`
  - `sendctl.sh observe`
  - `sendctl.sh briefing`
