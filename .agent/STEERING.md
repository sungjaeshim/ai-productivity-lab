# GWS 전환 A안 Steering (Ralph Loop)

## Mission
`gog` 운영 안정성을 유지한 채 `gws`를 병행 검증하여, 안전하게 점진 전환한다.

## Hard Rules
1. 운영 기본 경로는 항상 `gog` (`primary=gog`) 유지
2. `gws`는 Loop 1~2 동안 읽기/초안 중심으로만 사용
3. 쓰기 작업(메일 발송/일정 확정)은 인간 승인 없이는 금지
4. 실패 시 즉시 롤백 명령 실행 후 원인 기록

## Rollback Command (One-liner)
```bash
jq '.primary="gog" | .canaryEnabled=false | .phase="rollback" | .lastRollbackAt=now' data/gws-rollout-state.json > /tmp/gws-state.json && mv /tmp/gws-state.json data/gws-rollout-state.json
```

## Success Criteria (전체)
- Loop 1: 읽기 3시나리오 성공률 99%+
- Loop 2: 초안/제안 작업 오류 0건
- Loop 3: 핵심 루틴 2개 전환 후 5영업일 안정
