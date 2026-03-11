# OpenClaw SOP — Symphony-style Execution v2 (with OpenClaw examples)

## 0. One-line rule
도구를 먼저 바꾸지 말고, **운영 단위(task)** 를 먼저 바꾼다.

---

## 1. 언제 task로 분리하나
다음 중 하나면 inline 대신 task/run으로 보낸다.
- 10분 이상 걸릴 가능성
- 코드/설정 변경 포함
- 검증 증거가 필요함
- 여러 파일/시스템을 건드림
- main chat을 지저분하게 만들 가능성

작은 일만 inline.
큰 일은 task + isolated run.

---

## 2. 시작 전 Task Envelope 4줄
비단순 작업은 시작 전에 아래 4줄을 먼저 고정한다.

```text
Task: <짧은 작업명>
Goal: <끝났을 때 달라져 있어야 하는 것>
Scope: <건드릴 범위 / 제외 범위>
Evidence: <반드시 가져올 증거>
```

예시:
```text
Task: KIS dry_run safety hardening
Goal: live 전환 전 unsafe path 차단
Scope: scripts/, tests/, docs/
Evidence: git diff, pytest output, changed files
```

---

## 3. OpenClaw 실행 매핑
### A. 메인 세션에서 할 일
- 요청 해석
- Task Envelope 확정
- A/B 선택
- 승인 받기
- 결과 압축 보고

### B. isolated run으로 보낼 일
- 코드 작성/수정
- 대규모 탐색
- 장시간 진단
- noisy workflow
- ACP harness 기반 작업

### C. cron으로 보낼 일
- 정시 점검
- 반복 검사
- reminder
- 조용한 maintenance

### D. message로 할 일
- 승인된 결과 전송
- 특정 채널 후속 전달
- proactive send

---

## 4. sessions_spawn 예시
### 4-1) 복잡한 코딩 작업 분리
```json
{
  "task": "Analyze the repo, patch the failing router logic, run tests, and return a proof bundle with changes/verification/result/risk.",
  "runtime": "subagent",
  "mode": "run",
  "cleanup": "delete",
  "timeoutSeconds": 1800,
  "streamTo": "parent"
}
```

### 4-2) ACP harness로 Codex/Claude Code thread 작업
```json
{
  "task": "Implement the requested feature in the target repo and report back with proof bundle.",
  "runtime": "acp",
  "agentId": "codex",
  "thread": true,
  "mode": "session",
  "timeoutSeconds": 1800,
  "streamTo": "parent"
}
```

사용 원칙:
- repo 탐색/구현/리팩토링은 main에서 오래 끌지 말고 spawn.
- 완료 보고는 반드시 proof bundle 형식.

---

## 5. Proof Bundle 고정 포맷
비단순 작업 완료 보고는 항상 이 4블록으로 끝낸다.

```text
변경:
- 무엇을 바꿨는지

검증:
- 무엇을 확인했는지

결과:
- 지금 무엇이 참이 되었는지

리스크/후속:
- 남은 불확실성 / 다음 액션
```

예시:
```text
변경:
- duplication gate script 추가
- CI workflow 추가

검증:
- baseline 0.29%
- PASS @0.50%
- FAIL @0.10% 확인

결과:
- 중복 방지 게이트 정상 동작

리스크/후속:
- threshold는 팀 기준에 맞춰 추후 조정 가능
```

---

## 6. cron 예시
### 6-1) reminder
```json
{
  "action": "add",
  "job": {
    "name": "KIS 재점검 reminder",
    "schedule": { "kind": "at", "at": "2026-03-09T00:30:00Z" },
    "payload": {
      "kind": "systemEvent",
      "text": "리마인더: 어제 미뤄둔 KIS 재점검 시간입니다. 목표는 dry_run 안전성/증거 확인입니다."
    },
    "sessionTarget": "main",
    "enabled": true
  }
}
```

### 6-2) 반복 점검은 isolated agentTurn
```json
{
  "action": "add",
  "job": {
    "name": "아침 low-load 재측정",
    "schedule": { "kind": "cron", "expr": "30 6 * * *", "tz": "Asia/Seoul" },
    "payload": {
      "kind": "agentTurn",
      "message": "Run the low-load recheck, collect evidence, and announce only concise proof bundle.",
      "timeoutSeconds": 1200
    },
    "sessionTarget": "isolated",
    "enabled": true
  }
}
```

원칙:
- 정확한 시각 필요 → cron
- 단순 알림 → systemEvent
- 실제 조사/점검 실행 → isolated agentTurn

---

## 7. message 예시
### 7-1) 승인된 결과를 특정 채널로 보내기
```json
{
  "action": "send",
  "channel": "discord",
  "target": "1477462915509387314",
  "message": "변경:\n- ...\n\n검증:\n- ...\n\n결과:\n- ...\n\n리스크/후속:\n- ..."
}
```

### 7-2) Telegram proactive send
```json
{
  "action": "send",
  "channel": "telegram",
  "target": "62403941",
  "message": "리마인더: low-load 재측정 결과는 PASS가 아니라 아직 observe 상태입니다."
}
```

원칙:
- 실행과 전송을 분리한다.
- cross-context 제약 가능성이 있으면 main에서 억지로 보내지 말고 isolated path 사용.

---

## 8. 승인 게이트
반드시 승인 받고 진행:
- 외부 전송
- config patch/apply
- gateway restart/update
- destructive action
- cron 활성화/수정으로 실제 부작용 발생 가능
- merge/deploy/publish/moderation

즉:
- 분석/조사/초안/검증은 먼저 해도 됨
- 적용/반영/송신/재시작은 승인 후

---

## 9. incident 운영 예시
문제 발생 시 inline 추측 대신 아래 흐름 고정:

```text
incident 발생
→ task 생성
→ 조사 run 분리
→ evidence 수집
→ RCA 압축 보고
→ 승인 후 mitigation 적용
```

보고 형식:
```text
증상:
- ...

증거:
- ...

원인 추정:
- ...

완화/제안:
- ...

남은 리스크:
- ...
```

---

## 10. 운영 Anti-pattern
하지 말 것:
- main chat에서 장시간 구현 계속하기
- "done"만 말하고 증거 없음
- 긴 실행 로그를 그대로 사용자에게 dump
- 승인 없이 restart/config/deploy 실행
- 전송 계획 없이 다채널로 바로 발사

---

## 11. 실전 판단 문장
헷갈리면 이 한 줄로 결정:

> 이 작업이 **격리 실행 + 증거 보고**를 하면 더 안전하고 깔끔해지는가?

- Yes → task/run
- No → inline
