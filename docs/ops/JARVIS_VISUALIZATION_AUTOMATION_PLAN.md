# JARVIS_VISUALIZATION_AUTOMATION_PLAN

작성일: 2026-03-11  
상태: active

## 왜 이것이 필요한가

이 자동화는 시각화 결과물을 "코드 조각"이 아니라 "배포 가능한 패키지"로 고정하기 위해 만든다.

이미 수동 경로에서 검증된 사실은 다음과 같다.

- Mermaid CLI 렌더는 동작한다.
- root 환경에서는 Puppeteer `--no-sandbox` 설정이 필요하다.
- Notion API와 Knowledge Cards DB 발행은 동작한다.
- 수동 흐름은 성공했지만 반복 작업에는 일관된 엔트리포인트가 부족했다.

따라서 이번 MVP의 목적은 새로운 AI 다이어그램 생성기가 아니라,
이미 작성된 `.mmd`를 안정적으로 렌더하고 보관/배포하는 운영 파이프라인을 만드는 것이다.

## 워크플로우

기본 흐름은 아래 순서를 따른다.

1. `.mmd` 파일 준비
2. `visual-render.sh`로 `png`, `pdf`, `svg` 렌더
3. `meta.json`과 함께 `visual-notion-publish.py`로 Knowledge Cards DB 페이지 생성
4. 필요하면 `visual-flow.sh review`로 산출물 존재 여부와 기본 상태 확인
5. 필요하면 `visual-flow.sh review-send`로 Telegram 검수 채널에 PNG 전송

실무에서는 `all --send-review`가 가장 빠른 운영 경로다.
렌더와 Notion 발행이 성공한 뒤, 같은 산출물 PNG를 Telegram 검수 채널로 바로 보낸다.
이때 `meta.json`이 있으면 Telegram 캡션도 title / subtitle / purpose / example question 기반으로 자동 구성한다.

이 설계에서 중요한 점은 실패를 한 덩어리로 숨기지 않는 것이다.

- 렌더 실패는 렌더 단계에서 바로 멈춘다.
- Notion 발행 실패는 렌더와 분리되어 보고된다.
- 리뷰 실패는 누락 산출물 확인용으로 분리된다.

## 스크립트 역할

### `scripts/visual-render.sh`

- 입력: `.mmd`
- 출력: `out/<name>.png`, `out/<name>.pdf`, `out/<name>.svg`
- 역할:
  - Mermaid CLI 실행 경로 탐색
  - root 환경용 Puppeteer no-sandbox 설정 적용
  - 출력 디렉터리 생성
  - 포맷별 오류를 명확하게 표면화

### `scripts/visual-notion-publish.py`

- 입력: `.mmd`, `meta.json`
- 역할:
  - 기존 워크스페이스 Notion 인증 패턴 재사용
  - Knowledge Cards DB 또는 지정 DB에 페이지 생성
  - database -> data_source fallback 패턴 재사용
  - 제목, 목적, 사용법, 질문 예시, Mermaid 원본, 산출물 정보를 페이지에 기록
  - 성공 시 페이지 URL 출력

### `scripts/visual-flow.sh`

- 역할:
  - `render`, `publish`, `all`, `review` 서브커맨드 제공
  - `review-send`로 Telegram 검수 전송 제공
  - `all --send-review`로 패키징 직후 Telegram 검수본까지 연결
  - 운영자가 별도 스크립트 경로를 기억하지 않아도 되게 하는 얇은 진입점
  - `all` 실행 시 render / publish 실패 코드를 분리

### `visuals/templates/meta.example.json`

- 목적:
  - 새 시각화 자산을 발행할 때 필요한 메타데이터 형식을 고정
  - title / subtitle / purpose / usage / questions / notionDatabase / tags 입력 예시 제공

## 사용법

렌더만 실행:

```bash
scripts/visual-flow.sh render final_life_map_compact.mmd
```

Notion 발행만 실행:

```bash
scripts/visual-flow.sh publish final_life_map_compact.mmd visuals/templates/meta.example.json
```

전체 패키징 실행:

```bash
scripts/visual-flow.sh all final_life_map_compact.mmd visuals/templates/meta.example.json
```

전체 패키징 + Telegram 검수 전송:

```bash
scripts/visual-flow.sh all final_life_map_compact.mmd visuals/templates/meta.example.json --send-review
```

다른 출력 경로를 쓰는 경우:

```bash
scripts/visual-flow.sh render final_life_map_compact.mmd --out-dir output/visuals
```

특정 Notion DB를 강제로 지정하는 경우:

```bash
scripts/visual-flow.sh publish final_life_map_compact.mmd visuals/templates/meta.example.json --database <notion-db-id>
```

산출물 확인:

```bash
scripts/visual-flow.sh review final_life_map_compact.mmd
```

Telegram 검수본 전송:

```bash
scripts/visual-flow.sh review-send final_life_map_compact.mmd --target <telegram-chat-id>
```

메타 기반 검수 캡션 전송:

```bash
scripts/visual-flow.sh review-send final_life_map_compact.mmd --meta visuals/templates/meta.example.json --target <telegram-chat-id>
```

Telegram 포럼 topic 검수 전송:

```bash
scripts/visual-flow.sh review-send final_life_map_compact.mmd --target <telegram-chat-id> --thread-id <topic-id>
```

## 실패 복구

### 1. Mermaid CLI를 찾지 못함

- `MMDC_BIN`으로 명시 경로를 지정한다.
- 또는 기존에 동작하던 `mmdc` 실행 파일 경로를 PATH에 둔다.

### 2. root 환경에서 Puppeteer가 막힘

- 기본값은 `puppeteer-mermaid.json`을 사용한다.
- 파일이 없으면 스크립트가 임시 no-sandbox 설정을 만든다.

### 3. 렌더는 되었지만 Notion 발행이 실패함

- 산출물은 이미 `out/`에 남아 있으므로 다시 렌더할 필요는 없다.
- 인증 파일, `NOTION_KNOWLEDGE_CARDS_DB`, 또는 `meta.json`의 `notionDatabase`를 확인한 뒤 `publish`만 재실행한다.

### 4. Knowledge Cards DB가 multi data source 구조임

- publisher는 기존 워크스페이스 패턴대로 `database_id` 조회 후 필요 시 `data_source_id`로 전환한다.
- 따라서 DB 구조가 그 형태여도 별도 수동 변경 없이 재시도 가능하다.

### 5. review 실패

- 대개 특정 포맷 산출물이 빠진 상태다.
- `render`를 다시 실행한 뒤 `review`만 재실행하면 된다.

### 6. Telegram review 전송 실패

- `TELEGRAM_TARGET` 또는 `--target` 값이 비어 있지 않은지 확인한다.
- topic 검수라면 `--thread-id` 또는 `VISUAL_REVIEW_TELEGRAM_THREAD_ID`를 확인한다.
- PNG가 없으면 전송하지 못하므로 `render`를 먼저 다시 실행한다.
- `all --send-review`에서 실패하면 render/publish 산출물은 이미 남아 있으므로 `review-send`만 재실행하면 된다.

## 한계

- 이 MVP는 로컬 파일 경로를 Notion 페이지 본문에 텍스트로 기록한다. 파일 업로드까지는 하지 않는다.
- `review`는 시각적 품질 평가가 아니라 산출물 존재 여부와 기본 상태 확인용이다.
- `review-send`는 현재 PNG 한 장 기준의 Telegram 검수본 전송에 집중한다.
- Telegram 검수 캡션은 `meta.json`이 있으면 그 내용을 요약해 쓰고, 없으면 파일명 중심 기본 메시지로 내려간다.
- 다이어그램 생성, 구조 개선, AI 기반 레이아웃 최적화는 범위 밖이다.

## 향후 확장

- Telegram 검수본 자동 전송 연결
- 산출물 해시/버전 기록
- SVG 또는 PNG 업로드를 포함한 richer Notion packaging
- 시각화 유형별 meta preset 추가
- CI/cron에서 사용할 수 있는 batch 모드 추가
