# V1-027 — The First Principle of Programming

## Meta
- Volume: 1 (Systems Thinking)
- Original: **The First Principle of Programming**
- Statement: "The best way to deal with errors is not to make them in the first place." (p.184)
- KR 제목: **프로그래밍 제1원리: 오류는 고치는 것보다 처음부터 만들지 않는 것이 최선**
- Confidence: High
- Tags: #programming #error-prevention #quality

## 1) 정밀 번역
오류를 다루는 가장 좋은 방법은, 애초에 오류를 만들지 않는 것이다.

## 2) 핵심 정의 3줄
1. 사후 수정보다 사전 예방이 가장 큰 품질 레버리지다.
2. 설계/리뷰/타입/테스트는 예방 장치다.
3. 디버깅 역량 못지않게 결함 예방 설계가 중요하다.

## 3) 왜 중요한가
- 결함이 늦게 발견될수록 비용과 파급 범위가 커진다.

## 4) 실무 적용 체크리스트
- [ ] 변경 전 체크리스트(요구/경계/예외)가 있는가?
- [ ] 자동검증(테스트/린트/타입체크)이 파이프라인에 포함됐는가?

## 5) 오해/한계
- 오해: “완전 예방 가능.”
- 한계: 결함 0은 불가능에 가깝고, 핵심은 발생 확률/영향 최소화다.

## 6) 연결 개념
- V1-007 Crosby’s Economics of Quality
- V1-028 The Absence of Error Fallacy

## 7) Action Card
- 다음 PR부터 ‘예방 체크 5항목’ 템플릿 강제 적용

## 8) Search Keys
- KR: 오류예방, 프로그래밍 원리, 결함 선제차단
- EN: error prevention, first principle of programming, defect prevention
