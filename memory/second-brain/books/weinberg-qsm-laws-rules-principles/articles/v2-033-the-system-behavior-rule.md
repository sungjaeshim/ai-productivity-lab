# V2-033 — The System Behavior Rule

## Meta
- Volume: 2 (First-Order Measurement)
- Original: **The System Behavior Rule**
- Statement: "Behavior depends on both state and input." (p.321)
- KR 제목: **시스템 행동 규칙: 행동은 상태와 입력에 함께 의존한다**
- Confidence: High
- Tags: #system-behavior #state #input

## 1) 정밀 번역
행동은 상태와 입력 모두에 의존한다.

## 2) 핵심 정의 3줄
1. 동일 입력이라도 상태가 다르면 결과가 달라진다.
2. 제어는 입력 조정 + 상태 관리의 결합 문제다.
3. 상태 관측 없이는 안정 운영이 어렵다.

## 3) 왜 중요한가
- 운영 장애/성능 이슈 재현의 핵심 프레임이다.

## 4) 실무 적용 체크리스트
- [ ] 상태 변수와 입력 이벤트를 함께 기록하는가?
- [ ] 상태 기반 제어 규칙(임계치/완충)을 운영하는가?

## 5) 오해/한계
- 오해: "원인 이벤트만 찾으면 된다."
- 한계: 상태 모델 정의가 부실하면 분석 정확도가 낮다.

## 6) 연결 개념
- V1-012 Formular for a System’s Behavior
- V2-007 Cybernetic Rule

## 7) Action Card
- 최근 이슈 1건을 상태·입력 분리 분석표로 재작성

## 8) Search Keys
- KR: 시스템 행동 규칙, 상태 입력, 재현 분석
- EN: system behavior rule, state and input, incident reproduction
