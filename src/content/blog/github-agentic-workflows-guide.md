---
title: "GitHub Agentic Workflows — 마크다운으로 AI 자동화를 만드는 시대"
description: "GitHub이 공개한 Agentic Workflows를 알아봅니다. 자연어 마크다운으로 CI/CD를 넘어서는 AI 자동화를 구축하는 방법과 실전 활용법을 소개합니다."
pubDate: Feb 10 2026
heroImage: "https://images.unsplash.com/photo-1618401471353-b98afee0b2eb?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=1080"
heroImageAlt: "GitHub Agentic Workflows — 마크다운으로 AI 자동화를 만드는 시대"
heroImageCredit: "Photo by <a href='https://unsplash.com/@riaborozenets'>Roman Synkevych</a> on <a href='https://unsplash.com'>Unsplash</a>"
tags: ["GitHub", "AI자동화", "에이전트", "CI/CD", "개발자도구"]
---

## CI/CD의 한계, 그리고 새로운 시대

CI/CD는 소프트웨어 개발의 혁명이었습니다. 테스트 자동화, 빌드, 배포 — 규칙으로 정의할 수 있는 모든 것을 자동화했죠.

하지만 개발 업무의 상당 부분은 **규칙으로 정의할 수 없는 판단 영역**에 있습니다.

- 이슈가 들어왔는데, 이건 버그인가 기능 요청인가?
- 문서가 코드와 안 맞는데, 어디를 고쳐야 하나?
- PR 코드 품질이 괜찮은가?
- 테스트 커버리지가 부족한 곳은 어디인가?

이런 **판단이 필요한 작업**을 자동화하기 위해 GitHub이 내놓은 답이 바로 **Agentic Workflows**입니다.

## GitHub Agentic Workflows란?

GitHub Next와 Microsoft Research가 함께 만든 새로운 자동화 패턴입니다. 핵심을 한 문장으로 요약하면:

> **마크다운에 자연어로 "해줘"라고 쓰면, AI가 GitHub Actions에서 실행한다.**

기존 CI/CD가 YAML로 규칙을 정의했다면, Agentic Workflows는 **마크다운으로 의도를 설명**합니다.

### 실제 예시: 매일 이슈 리포트

```markdown
---
on:
  schedule: daily
permissions:
  contents: read
  issues: read
  pull-requests: read
safe-outputs:
  create-issue:
    title-prefix: "[team-status] "
    labels: [report, daily-status]
    close-older-issues: true
---

## Daily Issues Report
Create an upbeat daily status report for the team as a GitHub issue.
```

이게 전부입니다. YAML 수백 줄 대신 **자연어 한 문장**으로 매일 아침 팀 상태 리포트가 이슈로 생성됩니다.

## 핵심 특징 4가지

### 1. 자연어 = 코드

복잡한 YAML 문법을 배울 필요가 없습니다. "이슈를 분류해줘", "문서를 업데이트해줘"라고 쓰면 AI가 해석하고 실행합니다.

### 2. AI 에이전트 선택 가능

GitHub Copilot, Claude (Anthropic), OpenAI Codex 중 원하는 에이전트를 선택할 수 있습니다. 작업 특성에 맞는 AI를 골라 쓰는 거죠.

### 3. 보안이 기본값

- **읽기 전용이 기본** — 쓰기 작업은 명시적 허용 필요
- **Safe Outputs** — 사전 승인된 GitHub 작업만 실행 가능
- **샌드박스 실행** — 네트워크 격리, 도구 허용 목록 적용

AI가 레포를 망가뜨릴 걱정 없이 안전하게 실행됩니다.

### 4. Continuous AI라는 새 개념

GitHub은 이걸 **"Continuous AI"**라고 부릅니다.

| | CI (Continuous Integration) | Continuous AI |
|--|---|---|
| **처리 대상** | 규칙 기반 작업 | 판단 기반 작업 |
| **정의 방법** | YAML | 자연어 마크다운 |
| **실행 주체** | 스크립트 | AI 에이전트 |
| **결과** | 결정적 (pass/fail) | 비결정적 (판단) |

CI/CD를 **대체**하는 게 아니라 **보완**하는 거죠. 빌드/테스트는 기존 CI, 판단이 필요한 작업은 Continuous AI.

## 실전 활용 시나리오

### 📋 이슈 자동 분류
새 이슈가 올라오면 AI가 내용을 읽고 자동으로 라벨링, 우선순위 지정, 담당자 배정.

### 📝 문서 자동 유지보수
코드가 변경될 때마다 관련 문서가 최신인지 AI가 확인하고, 업데이트가 필요하면 PR을 생성.

### 🔍 코드 리뷰 보조
PR이 올라오면 AI가 먼저 리뷰해서 개선점, 잠재적 버그, 스타일 이슈를 코멘트.

### 🧹 DailyOps (매일 조금씩 개선)
매일 코드베이스에서 개선할 수 있는 작은 부분을 찾아 PR로 제안. 리팩토링, 중복 코드 제거, 테스트 추가 등.

### 🔒 보안 & 컴플라이언스
보안 스캔 결과를 AI가 분석해서 우선순위를 매기고, 해결 방법을 제안.

## 시작하는 방법

1. **CLI 설치**
```bash
gh extension install github/gh-aw
```

2. **워크플로우 추가**
```bash
gh aw add-wizard githubnext/agentics/daily-repo-status
```

3. **커스텀 워크플로우 작성**
`.github/workflows/` 폴더에 마크다운 파일을 만들고 자연어로 작성하면 끝.

## 왜 주목해야 하는가?

이건 단순한 도구 출시가 아닙니다. **소프트웨어 개발 방식의 패러다임 전환**입니다.

지금까지는:
- 규칙으로 정의 가능 → 자동화 ✅
- 판단이 필요 → 사람이 직접 ❌

앞으로는:
- 규칙 → CI/CD ✅
- 판단 → **AI 에이전트** ✅

GitHub의 Idan Gazit(GitHub Next 총괄)은 이렇게 말합니다:

> "AI 코딩의 첫 번째 시대는 코드 생성이었다. 두 번째 시대는 **인지적으로 무거운 잡무를 개발자에게서 덜어주는 것**이다."

## 한계와 주의점

- **아직 프로토타입 단계** — GitHub Next의 연구 프로젝트
- **AI 결과는 비결정적** — 같은 입력에 다른 결과가 나올 수 있음
- **핵심 빌드/배포에는 부적합** — 판단 기반 보조 작업에 최적화
- **GitHub Actions 분 단위 과금** — 사용량에 따른 비용 발생

## 마무리: 코드를 짜는 시대에서 의도를 쓰는 시대로

마크다운 한 장으로 AI가 매일 아침 레포를 분석하고, 이슈를 정리하고, 문서를 업데이트하는 시대가 왔습니다.

지금은 프로토타입이지만, **CI/CD → CI/CD + Continuous AI**라는 흐름은 이미 시작됐습니다.

개발자도, 비개발자도 주목할 만한 변화입니다. "무엇을 만들지"보다 **"무엇을 원하는지"를 잘 설명하는 능력**이 점점 더 중요해지고 있으니까요.

---

**참고 링크:**
- [GitHub Agentic Workflows 공식 문서](https://github.github.io/gh-aw/)
- [GitHub 블로그: Continuous AI in Practice](https://github.blog/ai-and-ml/generative-ai/continuous-ai-in-practice-what-developers-can-automate-today-with-agentic-ci/)
- [GitHub Next: Agentic Workflows](https://githubnext.com/projects/agentic-workflows/)
