# MEMORY_WEEKLY_TEMPLATE.md

## Purpose

This document standardizes the weekly memory review format.
The weekly review should evaluate **memory efficacy**, not only collection volume.

It should answer:

- What was newly learned?
- What memory was actually reused?
- What deserves promotion?
- What can be forgotten?
- What should update identity or preference layers?

---

## Standard Structure

```md
## 주간 기억 리뷰 (YYYY-MM-DD~YYYY-MM-DD)

### 한 줄 결론
- 이번 주 기억 시스템의 핵심 상태를 한 줄로 정리

### 핵심 3줄
1. 이번 주 새로 배운 가장 중요한 것
2. 실제로 반복 재사용된 기억
3. 다음 주 보강할 기억 운영 포인트

### 지표 대시보드
- 재사용된 기억 수: N
- Promotion Candidates: N
- Recall Misses: N
- Demotion Candidates: N
- Identity/Preference Update Candidates: N

### 1) 이번 주 새로 배운 것
- 신규 패턴 / 신규 교훈 / 신규 운영 인사이트

### 2) 이번 주 실제로 재사용한 기억
- 어떤 기억이 실제 응답/행동/의사결정에 사용되었는지
- 가능하면 적용 사례와 함께 기록

### 3) 장기기억 후보
- 장기기억으로 승격할 가치가 있는 항목
- 근거와 category 포함 권장

### 4) 잊어도 되는 기억
- 일회성 / 만료된 컨텍스트 / 더 이상 가치가 낮은 정보

### 5) 정체성/선호 업데이트 후보
- Identity / Relationship Invariants
- User Preferences
- Operating Rules
중 어디에 반영할지 검토할 후보

### 다음 주 실험 / 보강 포인트
- recall routing 보강
- daily logging 습관 보강
- promotion/demotion 정리
```

---

## Section Guidance

### 1) 이번 주 새로 배운 것
Include only lessons that changed understanding or future operation.
Not every event belongs here.

Good examples:

- A new failure mode was identified.
- A repeated user preference became explicit.
- A better execution pattern emerged.

### 2) 이번 주 실제로 재사용한 기억
This is the most important section.
Only include memory that actually changed behavior.

Preferred format:

- 기억:
  - 어디에 적용:
  - 효과:
  - 재사용 강도: low | mid | high

### 3) 장기기억 후보
A candidate should be here because it is reusable, durable, or identity-shaping.

Preferred format:

- 후보 문장:
  - 근거:
  - confidence:
  - category: preference | decision | rule | identity | rationale

### 4) 잊어도 되는 기억
Do not treat forgetting as failure.
This section keeps the system lean.

Examples:

- One-off active context
- Temporary blocker now resolved
- Low-value observational note

### 5) 정체성/선호 업데이트 후보
Use this section when the weekly review suggests updating:

- `MEMORY.md -> Identity / Relationship Invariants`
- `MEMORY.md -> User Preferences`
- `MEMORY.md -> Operating Rules`

---

## Suggested Metrics

Recommended weekly metrics:

- reused memory count
- promotion candidate count
- recall miss count
- demotion candidate count
- identity/preference candidate count

Optional derived metrics:

- memory reuse ratio
- recall miss ratio
- promotion acceptance ratio

---

## Lightweight Writing Rule

Keep the report compact.
Do not turn weekly review into a burden.

Rule of thumb:

- 1 line for conclusion
- 3 lines for key summary
- 2~5 bullets per section

---

## Example Skeleton

```md
## 주간 기억 리뷰 (2026-03-09~2026-03-15)

### 한 줄 결론
- 저장보다 재사용과 행동 변화 추적이 이번 주 핵심 진전이었다.

### 핵심 3줄
1. 구조화 응답 선호가 여러 답변에 실제 적용되었다.
2. 비사소한 작업 taskization 규칙이 안정적으로 재사용되었다.
3. recall miss는 상태추적 누락과 연결되는 경우가 있었다.

### 지표 대시보드
- 재사용된 기억 수: 4
- Promotion Candidates: 2
- Recall Misses: 1
- Demotion Candidates: 0
- Identity/Preference Update Candidates: 1

### 1) 이번 주 새로 배운 것
- 기억 효력 로그가 응답 품질 개선에 실제 도움이 되었다.

### 2) 이번 주 실제로 재사용한 기억
- 기억:
  - 구조화된 요약형 응답 선호
  - 어디에 적용:
    - 장문 설계안, 실행 보고
  - 효과:
    - 가독성 향상
  - 재사용 강도:
    - high

### 3) 장기기억 후보
- 후보 문장:
  - 기억의 가치는 응답과 행동 변화 기준으로 평가한다.
  - 근거:
    - 이번 주 여러 작업에서 기준으로 작동
  - confidence:
    - 0.86
  - category:
    - identity

### 4) 잊어도 되는 기억
- 일회성 설계 초안의 중간 문장들

### 5) 정체성/선호 업데이트 후보
- 비사소한 작업은 설계 승인 후 실행하는 흐름을 invariant 수준으로 유지 검토

### 다음 주 실험 / 보강 포인트
- recall intent routing 적용 사례를 3건 이상 확보
```

---

## One-Line Summary

A weekly memory review is useful when it shows not what was stored, but what was reused and why it mattered.
