# V1-032 — The Failure Detection Curve (the Bad News)

## Meta
- Volume: 1 (Systems Thinking)
- Original: **The Failure Detection Curve (the Bad News)**
- Statement: "There is no testing technology that detects failures in a linear manner." (p.205)
- KR 제목: **실패 탐지 곡선(나쁜 소식): 결함 탐지는 선형으로 진행되지 않는다**
- Confidence: High
- Tags: #testing #failure-detection #nonlinear

## 1) 정밀 번역
실패를 선형적으로 탐지하는 테스트 기술은 존재하지 않는다.

## 2) 핵심 정의 3줄
1. 결함 탐지는 초반 고속, 후반 둔화가 일반적이다.
2. “남은 버그 수” 예측은 선형 가정에서 크게 빗나간다.
3. 테스트 일정은 곡선형 현실을 반영해야 한다.

## 3) 왜 중요한가
- 선형 계획 기반 테스트는 막판 품질 리스크를 키운다.

## 4) 실무 적용 체크리스트
- [ ] 테스트 계획에 비선형 탐지 가정을 반영했는가?
- [ ] 종료 기준을 단순 기간이 아닌 위험도 기반으로 설정했는가?

## 5) 오해/한계
- 오해: “매일 같은 수의 결함이 잡힌다.”
- 한계: 비선형 곡선도 도메인별로 차이가 있다.

## 6) 연결 개념
- V1-031 Difference Detection Dynamic
- V1-033 Failure Detection Curve (Good News)

## 7) Action Card
- 현재 테스트 계획의 선형 가정을 제거하고 위험 기반 종료 기준 재설계

## 8) Search Keys
- KR: 실패탐지 곡선, 비선형 테스트, 결함탐지 한계
- EN: failure detection curve, non-linear testing, defect detection limits
