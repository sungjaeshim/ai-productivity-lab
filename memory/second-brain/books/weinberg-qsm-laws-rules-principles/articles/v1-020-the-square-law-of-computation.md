# V1-020 — The Square Law of Computation

## Meta
- Volume: 1 (Systems Thinking)
- Original: **The Square Law of Computation**
- Statement: "Computation grows at least as fast as the square of the number of equations." (p.130)
- KR 제목: **계산의 제곱 법칙: 문제 규모가 커지면 계산비용은 제곱 이상으로 증가한다**
- Confidence: High
- Tags: #computation #complexity #scaling #square-law

## 1) 정밀 번역
단순화가 없는 한, 방정식 집합을 풀기 위한 계산량은 방정식 수의 제곱 이상으로 증가한다.

## 2) 핵심 정의 3줄
1. 문제 규모 증가가 계산비용 폭증을 만든다.
2. 단순화/분해/근사 없이는 확장이 곧 병목이 된다.
3. 복잡도 관리는 성능 최적화 이전의 구조 설계 문제다.

## 3) 왜 중요한가
- 분석/시뮬레이션/스케줄링에서 규모 증가 시 급격한 성능저하를 설명한다.

## 4) 실무 적용 체크리스트
- [ ] 계산 대상의 차원 축소/분해 전략이 있는가?
- [ ] 정확도와 계산비용의 트레이드오프를 정의했는가?

## 5) 오해/한계
- 오해: “하드웨어만 늘리면 해결.”
- 한계: 알고리즘/모델 구조를 바꾸지 않으면 비용증가를 못 따라간다.

## 6) 연결 개념
- V1-016 The Scaling Fallacy
- V1-024 The Natural Software Dynamic

## 7) Action Card
- 현재 계산 집약 작업 1개에 대해 근사화/분해 옵션 2개 설계

## 8) Search Keys
- KR: 제곱 법칙, 계산복잡도, 스케일 비용
- EN: square law of computation, computational complexity, scaling cost
