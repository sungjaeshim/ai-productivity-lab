# NOTION_HOMEPAGE_SIGNALS_SOURCE

작성일: 2026-03-11  
상태: active

## 결론

현재 `NOTION_KNOWLEDGE_CARDS_DB`는 홈페이지 live signal 소스로 그대로 쓰기엔 부적합하다.

이유:

- `Title` 속성은 있지만 `Tags` 속성이 없다.
- `State`는 일부 카드만 `Inbox`이고, 많은 항목은 비어 있다.
- 최근 카드에 운영 메시지, 요청 문구, 임시 잡음이 섞여 있다.

따라서 현재 DB 기준으로는 `태그 규칙`보다 **전용 DB 방식**이 더 맞다.

## 추천안

홈 전용 Notion DB를 하나 따로 만든다.

추천 이름:

- `Homepage Signals`

추천 속성:

1. `Title`
   - 타입: `title`
   - 홈 카드 제목

2. `Summary`
   - 타입: `rich_text`
   - 카드 본문 요약

3. `Href`
   - 타입: `url`
   - 클릭 시 이동할 URL

4. `Category`
   - 타입: `select`
   - 예: `Platform`, `Brand`, `Guide`, `Update`

5. `State`
   - 타입: `select`
   - 추천 값: `Draft`, `Published`, `Archived`

6. `Updated_At`
   - 타입: `date`
   - 카드 갱신일

7. `Sort`
   - 타입: `number`
   - 홈 노출 순서 수동 제어용

## 왜 전용 DB가 맞는가

- 카드 품질을 홈 기준으로 큐레이션할 수 있다.
- 운영성 잡음이 섞인 Knowledge Cards DB와 역할이 분리된다.
- `LIVE_SIGNALS_NOTION_STATE=Published`만 걸어도 안전해진다.
- `Sort` 속성으로 홈 노출 순서를 직접 통제할 수 있다.

## 차선책

현재 Knowledge Cards DB를 계속 쓰고 싶다면 먼저 아래를 추가해야 한다.

1. `Tags` (`multi_select`)
2. `State` (`select`)를 전 카드에 일관되게 채우기

그 뒤에 아래 규칙을 쓴다.

- `LIVE_SIGNALS_NOTION_TAG=Homepage`
- `LIVE_SIGNALS_NOTION_STATE=Published`

하지만 지금 DB 상태를 보면 이 방식은 데이터 정리 비용이 더 크다.

## 현재 코드가 기대하는 매핑

export 스크립트는 아래 이름들을 유연하게 찾는다.

- 제목: `Title` 또는 title property
- 요약: `Summary`, `Description`, `Purpose`, `Subtitle`
- 링크: `Href`, `URL`, `Link`
- 분류: `Category`, `Type`, `Tag`
- 상태: `State`, `Status`
- 정렬: `Sort`, `Order`
- 날짜: `Updated_At`, `Updated`, `Published`

즉 위 추천 스키마대로 만들면 추가 코드 수정 없이 바로 붙는다.

## 권장 환경 변수

```bash
LIVE_SIGNALS_SOURCE_MODE=notion
LIVE_SIGNALS_NOTION_DB=<homepage-signals-db-id>
LIVE_SIGNALS_NOTION_STATE=Published
LIVE_SIGNALS_NOTION_LIMIT=6
```

필요하면 수동 정렬까지 사용한다.

- `Sort`가 있으면 오름차순 우선
- 그다음 `Updated_At` 내림차순

## 실제 운영 흐름

1. Notion `Homepage Signals` DB에서 카드 작성
2. `Published` 상태로 전환
3. `npm run build:live-signals`
4. `npm run build`

## 한 줄 판단

**현재 DB 기준으로는 태그 규칙보다 전용 DB가 더 안전하고 관리 비용도 낮다.**
