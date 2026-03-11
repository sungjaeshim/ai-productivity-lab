# V1-037 — The Ripple Effect

## Meta
- Volume: 1 (Systems Thinking)
- Original: **The Ripple Effect**
- Statement: "One fault resolution may require changes across many separate code areas." (p.237)
- KR 제목: **리플 효과: 단일 결함 수정이 다수 코드 영역 변경을 요구한다**
- Confidence: High
- Tags: #ripple-effect #change-impact #coupling

## 1) 정밀 번역
단일 결함을 해결하려면 여러 분리된 코드 영역을 함께 바꿔야 할 수 있다.

## 2) 핵심 정의 3줄
1. 결함 수정은 국소 작업이 아닐 수 있다.
2. 결합도가 높을수록 수정 파급 범위가 커진다.
3. 영향도 분석 없이 패치하면 2차 결함 위험이 커진다.

## 3) 왜 중요한가
- 작은 버그가 대규모 회귀를 부르는 구조적 이유를 보여준다.

## 4) 실무 적용 체크리스트
- [ ] 수정 전 영향도 맵(모듈/테스트)을 작성하는가?
- [ ] 변경된 영역 주변 회귀 테스트를 자동화했는가?

## 5) 오해/한계
- 오해: “버그 1개면 파일 1개만 고치면 됨.”
- 한계: 영향도 분석 비용이 증가하므로 위험 기반 우선순위 필요.

## 6) 연결 개념
- V1-038 The Modular Dynamic
- V4-031 Jones’s Law

## 7) Action Card
- 주요 결함 1건의 변경 파급 경로를 시각화해 문서화

## 8) Search Keys
- KR: 리플 효과, 변경 영향도, 결합도
- EN: ripple effect, change impact analysis, coupling
