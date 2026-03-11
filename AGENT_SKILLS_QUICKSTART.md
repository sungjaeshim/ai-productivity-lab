# Agent Skills Quickstart (ai-productivity-lab)

> Auto-generated for this project.
> Repo: `sungjaeshim/ai-productivity-lab`
> Branch: `main`
> App type: Astro blog

## 1) gh-fix-ci (CI 실패 원인 분석)

```text
Use skill: gh-fix-ci

Project: ai-productivity-lab
Repo path: /root/.openclaw/workspace/ai-productivity-lab
PR: (현재 브랜치 PR 자동 탐색; 없으면 최근 실패 run 기준으로 분석)

목표:
- 실패한 GitHub Actions 체크 원인 파악
- 로그 핵심 10줄 요약
- 수정안 A/B 제시 (코드 수정은 승인 후)

출력:
1) failing check 이름
2) root cause 1줄
3) evidence log (max 10줄)
4) fix plan A/B + 리스크
5) 승인질문: A or B
```

## 2) playwright-interactive (블로그 핵심 플로우)

```text
Use skill: playwright-interactive

Project: ai-productivity-lab
URL: http://127.0.0.1:4321  (astro dev 실행 후)

시나리오:
1) 홈 진입
2) 최신 글 카드 클릭
3) 본문 렌더/메타(제목, 날짜) 확인
4) 404 링크 없는지 기본 탐색

반복:
- 동일 시나리오 3회 실행

출력:
- run별 PASS/FAIL
- 실패 스크린샷 경로
- 콘솔 에러 top 5
- 재현율 (예: 2/3)
- 평균 소요시간(초)
```

## 3) notion-knowledge-capture (편집/배포 기록)

```text
Use skill: notion-knowledge-capture

Workspace/DB: (기존 콘텐츠 운영 DB)
Title: [ai-productivity-lab] CI/UI 캡처 - <YYYY-MM-DD>

입력 소스:
- gh-fix-ci 결과
- playwright-interactive 결과

페이지 구조:
1) Summary (3줄)
2) Context
3) Decision (선택안 A/B와 이유)
4) Evidence (로그/스크린샷/링크)
5) Action items (owner, due date)
6) Tags (#ci #ui #blog)
```

## 운영 KPI (권장)
- CI 원인 파악 리드타임(분)
- UI 재현 성공률(%)
- 게시 후 회귀 이슈 비율(%)
