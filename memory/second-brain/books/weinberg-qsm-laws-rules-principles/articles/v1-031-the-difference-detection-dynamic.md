# V1-031 — The Difference Detection Dynamic

## Meta
- Volume: 1 (Systems Thinking)
- Original: **The Difference Detection Dynamic**
- Statement: "A small amount of test time finds easy problems early; most easy problems are found early in the cycle." (p.202)
- KR 제목: **차이 탐지 동학: 테스트 초반에 쉬운 결함이 집중 발견된다**
- Confidence: High
- Tags: #testing #defect-discovery #dynamics

## 1) 정밀 번역
테스트 시간의 작은 일부가 쉬운 문제에 쓰이고, 쉬운 문제 대부분은 테스트 사이클 초기에 발견된다.

## 2) 핵심 정의 3줄
1. 결함 발견 속도는 시간에 따라 비선형이다.
2. 초반 성과(많은 버그 발견)는 이후에도 유지되지 않는다.
3. 테스트 전략은 단계별 탐지 난이도를 고려해야 한다.

## 3) 왜 중요한가
- 테스트 초반 발견량을 전체 속도로 오해하면 후반 품질 예측이 틀어진다.

## 4) 실무 적용 체크리스트
- [ ] 초반/중반/후반 테스트 목표를 분리했는가?
- [ ] 탐지율 하락 구간에 다른 기법(탐색/회귀/성능)을 투입하는가?

## 5) 오해/한계
- 오해: “초반에 많이 잡았으니 끝까지 비슷하게 잡힌다.”
- 한계: 제품/도메인에 따라 곡선 형태는 달라질 수 있다.

## 6) 연결 개념
- V1-032 Failure Detection Curve (Bad News)
- V1-033 Failure Detection Curve (Good News)

## 7) Action Card
- 테스트 리포트에 단계별 탐지율 그래프를 추가

## 8) Search Keys
- KR: 결함탐지 동학, 테스트 초반 효과, 탐지율 곡선
- EN: difference detection dynamic, defect discovery curve, testing phases
