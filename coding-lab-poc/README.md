# Coding Lab PoC

## Goal
하나의 입력 파일(`input/lab-profile.yaml`)을 기반으로 다음 3종 산출물을 생성하는 PoC:

1. Draw.io diagram
2. LibreOffice document / PDF
3. Inkscape visual asset

## Structure
- `input/` : 공통 입력
- `templates/` : 툴별 생성 템플릿
- `scripts/` : 실행 스크립트
- `output/` : 최종 산출물
- `tmp/` : 중간 생성물

## Run
```bash
bash scripts/run_all.sh
```

## Visual Regression Test
`render_visual.py` 변경 후에는 아래 회귀 검사를 함께 돌리는 것을 권장:

```bash
bash scripts/test_render_visual_regression.sh
```

검사 범위:
- 기본 입력 `lab-profile.yaml`
- 긴 한국어 입력
- 긴 영어 입력
- KR/EN mixed + emoji 스트레스 입력

검증 내용:
- SVG 생성 성공
- SVG 기본 구조 존재 (`<svg>`, `<rect>`, `<text>`, `font-family`)
- PNG 변환 성공
- 산출물 비어있지 않음

## Success Criteria
- `output/diagram/` 에 다이어그램 생성
- `output/docs/` 에 문서/PDF 생성
- `output/assets/` 에 시각물 생성
- `scripts/test_render_visual_regression.sh` 4개 케이스 통과

## Notes
초기 목표는 완성도보다 재현성이다.
현재 visual 파이프라인은 스냅샷 diff까지는 아니지만, 회귀 입력 기반의 빠른 안정성 검증은 가능하다.
