# PROMPTS.md

재사용 프롬프트 모음 (system operations)

## 1) Automation-First Gate (Manual handoff 금지)

```text
Before asking the user to do anything manually, check whether the task can be completed via CLI, MCP/API, or browser automation (in that order).

If automation is possible, execute it and report: commands/actions run, result, and verification.

If automation is not possible, return one blocker code only:
AUTH (permissions/login),
2FA (OTP/captcha),
LEGAL (terms/payment/legal consent),
PHYSICAL (device/hardware required),
UI_LOCK (non-automatable UI).

Then provide the minimum manual steps (max 3), and include an exact resume command/message for continuing automation right after user completion.

Do not say “you must do this manually” without running this gate.
```

## 2) Product Delivery Gate (RFE → RFT → FUT)

```text
RFE Gate (must pass all 5):
1) Exact pain/problem being solved now
2) North Star + Guardrail + Kill Metric
3) Edge cases (offline/timeout/retry/refund)
4) Legal/privacy/compliance check
5) Rollback + observability readiness

RFT Gate (must pass all 3):
A) Feature Flag immediate off
B) Canary/gradual rollout plan with stop condition
C) One-command rollback + owner/on-call assigned

FUT Decision:
- FL if North Star improves and Guardrails remain healthy
- FNL if Kill metric triggers or Guardrails degrade

Post-mortem:
Blame system gaps, not people. Track alert latency, rollback time, missing tests, prevention action items.
```

## 3) Agentic Engineering 실행 체크리스트 (10줄)

```text
1) Problem: 지금 해결할 문제를 한 문장으로 고정한다.
2) Decompose: 작업을 3~7개 단위 태스크로 분해한다.
3) Context: 필요한 파일/로그/레퍼런스만 최소 컨텍스트로 묶는다.
4) DoD: Must Have / Must Not Have / Test / Rollback을 먼저 적는다.
5) Execute: 에이전트에게 태스크 + DoD를 함께 전달한다.
6) Observe: 로그/출력/변경파일을 즉시 확인해 이상 징후를 잡는다.
7) Classify Fail: 실패를 컨텍스트 부족/방향 오류/구조 충돌로 분류한다.
8) Recover: 분류별 처방(컨텍스트 보강/목표 재정의/구조 수정)으로 재시도한다.
9) Memory: 세션 종료 시 결정/교훈/미해결 3줄을 기록한다.
10) Parallel: 동시 작업 수 상한을 지키고, 우선순위 높은 흐름부터 완료한다.
```

### 실행 명령형 프롬프트 (복붙용)

```text
다음 작업을 Agentic Engineering 10줄 체크리스트로 수행해라.
- 작업 목표: <한 줄>
- DoD(Must Have / Must Not Have / Test / Rollback): <작성>
- 실패 시 3분류(컨텍스트/방향/구조)로 원인과 재시도 전략을 보고해라.
- 완료 시 핵심결과 3줄 + 남은 액션을 출력해라.
```

## 4) Evidence-First 운영 규칙 (상태 보고/완료 판정)

```text
원칙:
- "증거 없으면 미실행"으로 간주한다.
- "완료"보다 "검증 가능한 완료"를 우선한다.
- 거짓 완료는 지연보다 더 나쁘다.

상태 보고 포맷(3줄 고정):
1) 상태: TODO | DOING | DONE | BLOCKED
2) 증거: PID/RunID/파일경로/URL/메시지ID/명령출력 중 최소 1개 이상
3) 다음단계: 다음 액션 1개 + ETA

문구 게이트:
- 완료/진행중/실패 문구는 증거 없으면 금지
- 실패 보고 시: 오류요약 + 재시도 여부 + 마지막 로그 1줄 필수

DONE 판정 예시 (MACD):
- cron run id 확인
- 스크립트 stdout 확인
- Telegram message id(또는 not-delivered 근거) 확인
→ 3개 중 필요한 증거가 충족될 때만 DONE
```

### 실행 명령형 프롬프트 (복붙용: Evidence-First)

```text
아래 규칙으로만 보고해라.
- 출력은 반드시 3줄: [상태] / [증거] / [다음단계]
- 증거가 없으면 DONE/DOING/FAILED를 쓰지 말고 BLOCKED로 보고해라.
- 각 완료 주장마다 RunID, 파일경로, URL, messageId 중 최소 1개를 포함해라.
- 실패 시 "오류요약 | 재시도여부 | 마지막로그1줄"을 한 줄에 포함해라.
```

## 5) Telegram 가독성 포맷 규칙 (마크다운 최소화)

```text
목표: 인지부하 최소화. 화면에서 한 번에 읽히는 형식만 사용.

규칙:
- **, __, ``, # 헤더, 표(table) 사용 금지
- 굵게 대신 라벨+콜론 사용 (예: 요약:, 핵심:, 다음:)
- 문단은 1~2줄 단위로 짧게
- 리스트는 숫자/점(-)만 사용, 이모지는 최대 1~2개
- 기본 출력 순서: 요약 → 핵심 3줄 → 선택지 A/B → 다음 액션 1줄
- 동일 내용 중복 전송 금지 (한 턴 1회)

권장 템플릿:
요약: <한 줄>
핵심:
1) <한 줄>
2) <한 줄>
3) <한 줄>
선택지:
- A) <옵션>
- B) <옵션>
다음 액션: <한 줄>
```

### 실행 명령형 프롬프트 (복붙용: Telegram 가독성)

```text
아래 규칙으로 응답해라.
- 마크다운 강조(**, __, ``, #) 금지
- 표 금지, 짧은 리스트만 사용
- 출력 순서: 요약 1줄 → 핵심 3줄 → 선택지 A/B → 다음 액션 1줄
- 한 턴당 동일 문안 중복 전송 금지
```

## 6) OpenClaw v2026.3.2 운영 고정 체크 (A안)

```text
목표: 안정성/노이즈 개선을 기본 운영 절차로 고정.

체크리스트:
1) Config 변경 전/후 반드시 실행
   - openclaw config validate --json
   - valid=true 확인 후에만 restart/apply 진행

2) Telegram 스트리밍 기본값 유지
   - channels.telegram.streaming = partial
   - blockStreaming = false

3) Cron 노이즈 억제 규칙
   - 정상 루틴은 사용자 전송 금지(quiet)
   - HEARTBEAT_OK는 내부 ack 용도, 사용자 메시지 본문으로 보내지 않음
   - 알림은 오류/이상징후/사용자 요청 상황에만 전송
```

## 7) Subagent timeout/retry 운영 고정 (RCA 반영)

```text
목표: 간헐 subagent timeout(10s) 재발 억제.

기본값:
- sessions_spawn 호출 시 timeoutSeconds는 30 이상 사용
- runTimeoutSeconds는 120 이상 사용
- 긴 본문/로그는 요약 후 전달(대형 원문 붙여넣기 금지)

재시도 규칙:
- timeout 발생 시 1회만 재시도
- 재시도 전 컨텍스트 compact(핵심 지시 3~6줄로 축약)
- 2회 연속 timeout이면 추가 자동재시도 금지, 원인/증거 보고로 전환
```

## 8) NOO 응답 변환 프롬프트 (추상→실행)

```text
입력된 개념/철학 설명을 아래 순서로 변환해라.

1) 핵심 한 줄
2) 구체 예시 2개 (상황 → 행동 → 결과)
3) 지금 바로 할 수 있는 작은 실행 1개
4) before vs after 측정방법 1개

제약:
- 추상 설명만으로 끝내지 말 것
- 원칙 설명은 3줄 이내로 제한할 것
- 실행 단계는 1~3개 이내로 제한할 것
```
