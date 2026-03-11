# 인간 삶 핵심 원리 지도 로드맵

## 목표
이 프로젝트는 단순 시각 자료가 아니라, 사용자가 단어 하나를 출발점으로 AI와 사고를 확장할 수 있는 탐색형 지식 인터페이스를 만드는 것을 목표로 한다.

## 현재 산출물
- 데이터 원본: `core_map_nodes.json`
- SVG 시안:
  - `output/core-map/core-map-radial.svg`
  - `output/core-map/core-map-network.svg`
- HTML 탐색판:
  - `output/core-map/core_map_explorer.html`
- 렌더 스크립트:
  - `coding-lab-poc/scripts/render_core_map.py`
  - `coding-lab-poc/scripts/generate_core_map.sh`

## 권장 운영 구조
- 원본 데이터는 `core_map_nodes.json` 하나를 기준으로 유지한다.
- 시각화 결과물(HTML/SVG)은 이 파일에서 파생 생성한다.
- 외부 공개는 `second-brain.html`에서 링크만 연결하고, 실제 탐색판은 별도 페이지(`core-map.html`)로 유지한다.
- 텔레그램은 기획/수정 요청 채널로 사용하고, 실제 변경사항은 파일에 누적한다.

## 다음 우선순위
### 1. 보기 개선
- 선택 노드 강조 강화
- 연결선 active/inactive 상태 구분
- 우측 패널을 더 카드형으로 정리
- "AI에게 이렇게 물어보세요" 영역 추가
- 모바일 레이아웃 보강

### 2. second-brain 연결
- `growth-center/public/second-brain.html`에 카드형 링크 추가
- 배포 경로를 `core-map.html`로 분리
- second-brain에서는 소개 + 링크만 제공

### 3. 콘텐츠 확장
각 중심 단어에 아래 필드 확장 검토:
- `misunderstanding`: 흔한 오해
- `examples`: 개인/관계/조직 예시 3종
- `compare_with`: 자주 헷갈리는 단어
- `ask_templates`: AI에게 바로 던질 질문 템플릿
- `cluster`: 인지/적응/사회/판단 등 군집 정보

### 4. 텔레그램 탐색기
- 중심 단어 10개 버튼형 시작 화면
- 선택 단어 상세 카드
- 관련 단어 점프 버튼
- 처음으로/추천 탐색 경로 버튼

## 수정 요청 방법
텔레그램에서 아래 형식처럼 요청하면 된다.
- "보기 더 좋게 다듬어줘"
- "의미/신뢰/권력 쪽 콘텐츠 확장해줘"
- "second-brain에 링크 붙여줘"
- "모바일에서 더 잘 보이게 해줘"
- "텔레그램 버튼형 탐색기로 이어줘"

## 운영 원칙
- 대화는 요청 창구, 파일은 공식 자산
- 원본 데이터 수정 후 HTML/SVG 재생성
- second-brain 본체는 최소 수정, 탐색판은 별도 페이지 유지
- 초기에는 빠른 개선, 중기부터는 구조/버전 관리 강화

## 버전 메모
- v1: 중심 단어 10개 + 파생 3개 + 핵심 연결선 + 우측 설명 패널
- v2 후보: 검색, 추천 경로, 예시 확장, active link 강조, second-brain 연결
