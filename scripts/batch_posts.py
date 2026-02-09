#!/usr/bin/env python3
"""10개 블로그 글 배치 생성 + Unsplash 이미지 자동 삽입"""

import json
import os
import sys
import urllib.request
import urllib.parse
import time

UNSPLASH_KEY = os.environ.get('UNSPLASH_ACCESS_KEY', '9BhmO8-OZoRSAqx5yG0-cPh2ULxiOsB1XShYcTaa808')
BLOG_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'src', 'content', 'blog')

def search_unsplash(query):
    params = urllib.parse.urlencode({'query': query, 'per_page': 1, 'orientation': 'landscape'})
    url = f"https://api.unsplash.com/search/photos?{params}"
    req = urllib.request.Request(url, headers={'Authorization': f'Client-ID {UNSPLASH_KEY}'})
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read())
            if data.get('results'):
                img = data['results'][0]
                # trigger download
                dl_req = urllib.request.Request(img['links']['download_location'], 
                    headers={'Authorization': f'Client-ID {UNSPLASH_KEY}'})
                try: urllib.request.urlopen(dl_req)
                except: pass
                return {
                    'url': img['urls']['regular'],
                    'alt': img.get('alt_description', query),
                    'author': img['user']['name'],
                    'author_url': img['user']['links']['html'],
                }
    except Exception as e:
        print(f"  Unsplash error for '{query}': {e}", file=sys.stderr)
    return None

posts = [
    {
        "slug": "google-notebooklm-guide",
        "search": "Google NotebookLM AI research",
        "title": "Google NotebookLM 완전 가이드 — AI로 논문·보고서 10배 빠르게 분석하기",
        "description": "Google NotebookLM으로 PDF, 논문, 보고서를 AI가 자동 분석하고 요약해줍니다. 무료 사용법과 활용 팁을 정리했습니다.",
        "date": "Feb 06 2026",
        "tags": ["AI 도구", "Google", "리서치"],
        "content": """## Google NotebookLM이란?

Google이 만든 AI 기반 연구 보조 도구입니다. PDF, 웹 페이지, 유튜브 영상 등을 업로드하면 AI가 내용을 분석하고, 질문에 답하고, 요약해줍니다.

## 왜 써야 하나?

- **무료:** Google 계정만 있으면 무료
- **소스 기반 답변:** 업로드한 문서에서만 답변 → 환각(hallucination) 최소화
- **오디오 변환:** 문서 내용을 팟캐스트 형식으로 변환 가능

## 활용 사례 5가지

### 1. 논문 빠르게 읽기
PDF 논문을 업로드하고 "핵심 결론 3줄로 요약해줘"라고 질문하면 됩니다.

### 2. 회의록 분석
녹음 파일이나 텍스트를 올려 "액션 아이템 뽑아줘"라고 요청합니다.

### 3. 경쟁사 리포트 비교
여러 리포트를 올리고 "A사와 B사의 매출 성장률 차이"를 물어봅니다.

### 4. 학습 도우미
교과서나 강의 자료를 올려 대화형으로 학습할 수 있습니다.

### 5. 콘텐츠 기획
블로그 글 초안이나 아이디어 메모를 올려 구조화를 요청합니다.

## 사용법 (3단계)

1. **접속:** notebooklm.google.com
2. **노트북 생성:** "New Notebook" 클릭
3. **소스 추가:** PDF, URL, 텍스트 붙여넣기
4. **질문하기:** 채팅창에 질문 입력

## 자주 묻는 질문

### 한국어 지원하나요?
네, 한국어 문서를 올리면 한국어로 답변합니다. 다만 영어 문서의 분석 정확도가 더 높습니다.

### ChatGPT와 뭐가 다른가요?
ChatGPT는 일반 지식 기반, NotebookLM은 **내가 올린 문서 기반**으로 답변합니다. 환각이 적고, 출처를 명확하게 표시해줍니다."""
    },
    {
        "slug": "ai-seo-content-strategy",
        "search": "SEO content strategy AI writing",
        "title": "AI로 SEO 최적화된 블로그 글 쓰는 5단계 전략",
        "description": "AI 도구를 활용해 검색엔진 상위 노출되는 블로그 글을 효율적으로 작성하는 방법. 키워드 리서치부터 발행까지.",
        "date": "Feb 05 2026",
        "tags": ["SEO", "AI 글쓰기", "콘텐츠"],
        "content": """## AI + SEO = 최강 조합

AI가 글을 대신 써주는 시대입니다. 하지만 아무렇게나 쓰면 검색엔진에 노출되지 않습니다. AI의 속도와 SEO의 전략을 결합하는 방법을 알려드립니다.

## 5단계 전략

### Step 1: 황금 키워드 찾기

황금 키워드란 **검색량은 있지만 경쟁이 낮은** 키워드입니다.

**도구:**
- Google Keyword Planner (무료)
- Ubersuggest (무료 3회/일)
- Ahrefs (유료, KD 0-10 필터)

**팁:** "최고의 AI 도구" 같은 대형 키워드 대신, "맥북 AI 메모 앱 추천 2026" 같은 롱테일 키워드를 노리세요.

### Step 2: 검색 의도 파악

같은 키워드라도 검색 의도가 다릅니다:
- **정보형:** "AI란 무엇인가" → 설명 글
- **비교형:** "ChatGPT vs Claude" → 비교표
- **해결형:** "맥북 발열 해결" → How-to 가이드

구글에 키워드를 검색해서 상위 5개 결과의 형식을 확인하세요. 그 형식을 따라가야 합니다.

### Step 3: AI로 초안 작성

Claude나 ChatGPT에게 이렇게 요청합니다:

```
"[키워드]에 대해 2000자 블로그 글을 써줘.
- H2/H3 구조로
- 비교표 1개 포함
- FAQ 3개 포함
- 한국어, 구어체"
```

### Step 4: 인간의 손길 추가

AI 글을 그대로 올리면 안 됩니다:
- 개인 경험 추가 (EEAT의 Experience)
- 구체적 숫자와 사례 삽입
- 한국 상황에 맞게 수정
- AI 특유의 문장 패턴 제거

### Step 5: SEO 메타데이터 최적화

- **제목:** 키워드 포함 + 숫자 + 연도 (예: "2026년 AI 이미지 생성 도구 5선")
- **메타 설명:** 155자 이내, 행동 유도
- **URL:** 영어 슬러그, 하이픈 구분

## 자주 묻는 질문

### AI로 쓴 글도 검색엔진에 노출되나요?
네. 구글은 AI 생성 콘텐츠를 차별하지 않습니다. 중요한 건 콘텐츠의 **품질**입니다.

### 하루에 몇 개까지 써도 되나요?
품질이 유지된다면 제한 없습니다. 다만 하루 1-2개가 현실적입니다. 양보다 질이 중요합니다.

### 어떤 AI 도구가 SEO 글쓰기에 좋나요?
**Claude**가 한국어 글쓰기 품질이 가장 좋고, **ChatGPT**는 SEO 플러그인 연동이 편합니다."""
    },
    {
        "slug": "ai-workflow-automation-zapier-make",
        "search": "workflow automation Zapier Make AI",
        "title": "Zapier vs Make 완전 비교 — AI 시대의 업무 자동화 플랫폼",
        "description": "Zapier와 Make(구 Integromat)의 가격, 기능, 사용성을 비교합니다. AI 통합 자동화 워크플로우 구축 가이드.",
        "date": "Feb 04 2026",
        "tags": ["자동화", "Zapier", "Make", "노코드"],
        "content": """## 업무 자동화 플랫폼이란?

여러 앱과 서비스를 연결해서 반복 작업을 자동으로 처리해주는 도구입니다. 예를 들어 "이메일에 첨부파일이 오면 → Google Drive에 저장 → 슬랙에 알림"을 코딩 없이 설정할 수 있습니다.

## Zapier vs Make 핵심 비교

| | Zapier | Make |
|--|--------|------|
| **가격** | 무료 100작업/월 | 무료 1,000작업/월 |
| **유료** | $19.99/월~ | $9/월~ |
| **사용 난이도** | 쉬움 | 중간 |
| **앱 연동 수** | 7,000+ | 1,800+ |
| **AI 통합** | ✅ (AI by Zapier) | ✅ (OpenAI 모듈) |
| **복잡한 로직** | 제한적 | 강력 |
| **시각적 편집** | 리스트형 | 플로우차트형 |

## 추천 가이드

### Zapier를 쓸 사람
- 빠르게 시작하고 싶은 초보자
- 단순한 "A→B→C" 자동화
- 미국 서비스 위주 사용

### Make를 쓸 사람
- 복잡한 조건 분기가 필요한 경우
- 가성비를 중시하는 경우
- 데이터 변환이 많은 경우

## AI 활용 자동화 예시 5가지

### 1. 이메일 자동 분류 & 답장
들어오는 이메일 → AI가 내용 분석 → 카테고리 분류 → 템플릿 답장 생성

### 2. SNS 콘텐츠 자동 생성
블로그 글 발행 → AI가 요약 → 트위터/링크드인용 포스트 자동 생성

### 3. 고객 문의 자동 응답
웹사이트 문의 접수 → AI가 답변 초안 생성 → 검토 후 발송

### 4. 경쟁사 모니터링
경쟁사 웹사이트 변경 감지 → AI가 분석 요약 → 슬랙 알림

### 5. 주간 보고서 자동 생성
여러 소스 데이터 수집 → AI가 종합 분석 → 보고서 PDF 생성

## 자주 묻는 질문

### 둘 다 무료로 써도 되나요?
네. Zapier는 월 100작업, Make는 월 1,000작업까지 무료입니다. 개인용으로는 충분합니다.

### 코딩을 전혀 몰라도 되나요?
네. 둘 다 노코드 플랫폼입니다. 다만 Make는 JSON 구조를 이해하면 더 강력하게 쓸 수 있습니다."""
    },
    {
        "slug": "cursor-ai-code-editor-guide",
        "search": "Cursor AI code editor programming",
        "title": "Cursor AI 에디터 완벽 가이드 — 코딩 초보도 AI로 개발하는 법",
        "description": "Cursor AI 코드 에디터 사용법. 코딩을 모르는 사람도 AI와 대화하며 웹사이트, 앱을 만들 수 있습니다.",
        "date": "Feb 03 2026",
        "tags": ["AI 도구", "코딩", "Cursor", "개발"],
        "content": """## Cursor란?

VS Code 기반의 AI 코드 에디터입니다. 코드를 직접 쓰는 대신, AI에게 자연어로 설명하면 코드를 생성해줍니다.

## 왜 Cursor인가?

- **VS Code 호환:** 기존 확장 프로그램 모두 사용 가능
- **AI 내장:** Claude, GPT-4 등 최신 AI 모델 통합
- **Composer:** 여러 파일을 한 번에 수정하는 기능
- **코드베이스 이해:** 프로젝트 전체를 분석해서 문맥에 맞는 코드 생성

## 가격

| 플랜 | 가격 | AI 사용량 |
|------|------|----------|
| Hobby | 무료 | 월 2,000회 자동완성 |
| Pro | $20/월 | 무제한 자동완성 + 500회 프리미엄 |
| Business | $40/월 | 팀 기능 추가 |

## 핵심 기능 3가지

### 1. Tab 자동완성
코드를 쓰다가 Tab을 누르면 AI가 다음 코드를 예측해서 완성합니다. GitHub Copilot과 비슷하지만, 프로젝트 전체 문맥을 더 잘 이해합니다.

### 2. ⌘+K (인라인 편집)
코드 블록을 선택하고 ⌘+K를 누른 후 "이 함수에 에러 처리 추가해줘"라고 입력하면 AI가 바로 수정합니다.

### 3. Composer (다중 파일 편집)
"로그인 페이지를 만들어줘"라고 요청하면, HTML, CSS, JavaScript 파일을 동시에 생성합니다. 대화형으로 수정도 가능합니다.

## 코딩 초보자 활용법

### 웹사이트 만들기
1. Cursor 설치 후 새 폴더 열기
2. Composer에 "반응형 포트폴리오 웹사이트를 만들어줘. 다크 모드, 프로젝트 갤러리 포함"
3. AI가 파일 전체 생성
4. 미리보기로 확인, 수정 사항은 대화로 요청

### 자동화 스크립트
"매일 아침 네이버 뉴스 헤드라인을 크롤링해서 텔레그램으로 보내는 파이썬 스크립트"를 요청하면 실행 가능한 코드를 만들어줍니다.

## 자주 묻는 질문

### VS Code에서 옮겨야 하나요?
Cursor가 VS Code 기반이라 설정, 확장 프로그램 모두 가져올 수 있습니다. 전환 비용이 거의 없습니다.

### GitHub Copilot이랑 뭐가 다른가요?
Copilot은 자동완성 중심, Cursor는 대화형 코드 생성과 다중 파일 편집이 핵심 차별점입니다."""
    },
    {
        "slug": "perplexity-ai-search-guide",
        "search": "Perplexity AI search engine",
        "title": "Perplexity AI — 구글 검색을 대체할 AI 검색 엔진 사용법",
        "description": "Perplexity AI 사용법과 활용 팁. 구글 검색보다 빠르고 정확한 AI 기반 검색 엔진을 소개합니다.",
        "date": "Feb 02 2026",
        "tags": ["AI 도구", "검색", "Perplexity"],
        "content": """## Perplexity AI란?

AI 기반 검색 엔진입니다. 구글처럼 링크 목록을 보여주는 대신, 질문에 대한 **답변**을 직접 작성하고 출처를 함께 표시합니다.

## 구글 vs Perplexity

| | 구글 | Perplexity |
|--|------|-----------|
| **결과 형태** | 링크 목록 | 요약된 답변 + 출처 |
| **후속 질문** | 새로 검색 | 대화형 이어가기 |
| **광고** | 있음 | 없음 |
| **최신 정보** | ✅ | ✅ (실시간 검색) |
| **가격** | 무료 | 무료 (Pro $20/월) |

## 핵심 기능

### 1. Focus 모드
검색 범위를 한정할 수 있습니다:
- **All:** 전체 웹 검색
- **Academic:** 학술 논문만
- **YouTube:** 유튜브 영상만
- **Reddit:** 레딧 토론만

### 2. Collections
검색 결과를 주제별로 모아 정리할 수 있습니다. 리서치 프로젝트에 유용합니다.

### 3. Pro Search
복잡한 질문에 대해 여러 단계로 검색하고 종합적인 답변을 제공합니다.

## 활용 사례

### 시장 조사
"2026년 한국 AI 시장 규모와 주요 기업"을 물어보면 최신 데이터와 출처를 포함한 요약을 받을 수 있습니다.

### 기술 문제 해결
"React useEffect에서 무한 루프가 발생하는 원인"처럼 기술 질문을 하면 코드 예시와 함께 답변합니다.

### 여행 계획
"3월 도쿄 3박 4일 예산 100만원 여행 계획"을 물어보면 구체적인 일정과 비용을 계산해줍니다.

## 자주 묻는 질문

### 구글을 완전히 대체할 수 있나요?
아직은 아닙니다. 지도, 쇼핑, 이미지 검색 등은 구글이 강합니다. 하지만 정보 검색과 리서치에서는 Perplexity가 더 효율적입니다.

### 무료로 충분한가요?
일반 사용은 무료로 충분합니다. Pro Search를 자주 쓰거나 파일 업로드가 필요하면 Pro($20/월)를 고려하세요."""
    },
    {
        "slug": "ai-presentation-tools-2026",
        "search": "AI presentation slides design",
        "title": "AI로 프레젠테이션 10분 만에 만드는 법 — 최고의 AI PPT 도구 4선",
        "description": "Gamma, Beautiful.ai, Tome, Canva AI 등 AI 프레젠테이션 도구 비교. 텍스트만 입력하면 슬라이드가 완성됩니다.",
        "date": "Feb 01 2026",
        "tags": ["AI 도구", "프레젠테이션", "생산성"],
        "content": """## AI PPT 도구란?

텍스트 설명이나 문서를 입력하면 AI가 슬라이드 디자인, 레이아웃, 이미지까지 자동으로 만들어주는 도구입니다.

## 2026년 최고의 AI PPT 도구 4선

### 1. Gamma

- **특징:** 텍스트 입력 → 프레젠테이션 자동 생성
- **무료:** 10개 AI 크레딧
- **장점:** 디자인이 가장 세련됨, 웹 기반 공유 최적
- **단점:** PPT 파일 export 시 레이아웃 깨짐

### 2. Beautiful.ai

- **특징:** 스마트 템플릿 + AI 레이아웃
- **가격:** $12/월
- **장점:** 레이아웃이 자동 정렬, 일관된 디자인
- **단점:** 무료 플랜 없음

### 3. Tome

- **특징:** 스토리텔링 중심 프레젠테이션
- **무료:** 500 AI 크레딧
- **장점:** 내러티브 구조에 강함, AI 이미지 생성 내장
- **단점:** 전통적 PPT 형식과 다름

### 4. Canva AI (Magic Design)

- **특징:** 기존 Canva에 AI 기능 추가
- **무료:** 기본 기능 무료
- **장점:** 한국어 지원, 다양한 템플릿, PPT 호환
- **단점:** AI 자동 생성 품질이 다른 도구보다 낮음

## 비교 표

| 도구 | 무료 | 디자인 | AI 품질 | PPT 호환 | 한국어 |
|------|------|-------|---------|---------|-------|
| Gamma | △ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | △ | ✅ |
| Beautiful.ai | ❌ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ✅ | △ |
| Tome | △ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | △ | ✅ |
| Canva | ✅ | ⭐⭐⭐ | ⭐⭐⭐ | ✅ | ✅ |

## 실전 팁

### 보고서 → 발표 자료 변환
1. 보고서 텍스트를 Gamma에 붙여넣기
2. "Professional" 스타일 선택
3. AI가 5-10장 슬라이드 자동 생성
4. 세부 수정 후 공유 링크 발송

소요 시간: **10분** (기존 2시간 → 83% 절감)

## 자주 묻는 질문

### 회사에서 써도 되나요?
네. 모든 도구가 상업적 사용을 허용합니다. 다만 AI 생성 이미지의 저작권은 각 서비스 약관을 확인하세요.

### 파워포인트를 완전히 대체하나요?
아직은 아닙니다. 복잡한 애니메이션이나 정밀한 레이아웃은 파워포인트가 낫습니다. 빠른 초안 생성 → 파워포인트에서 마무리하는 방식이 효율적입니다."""
    },
    {
        "slug": "ai-meeting-notes-automation",
        "search": "AI meeting notes transcription",
        "title": "회의록 AI로 자동화하기 — Otter, Clova Note, Fireflies 비교",
        "description": "AI 회의록 도구 3종 비교. 녹음하면 자동으로 텍스트 변환, 요약, 액션 아이템 추출까지 해줍니다.",
        "date": "Jan 31 2026",
        "tags": ["AI 도구", "회의록", "자동화", "생산성"],
        "content": """## AI 회의록 도구란?

회의를 녹음하면 AI가 자동으로 텍스트로 변환(STT)하고, 핵심 내용을 요약하고, 액션 아이템까지 추출해주는 도구입니다.

## 3대 AI 회의록 도구 비교

| | Otter.ai | Clova Note | Fireflies.ai |
|--|---------|------------|-------------|
| **한국어** | △ | ✅✅ | ✅ |
| **무료** | 월 300분 | 월 300분 | 월 800분 |
| **요약** | ✅ | ✅ | ✅ |
| **액션 아이템** | ✅ | △ | ✅ |
| **Zoom 연동** | ✅ | ❌ | ✅ |
| **가격** | $8.33/월 | 무료 | $10/월 |

## 추천 가이드

### 한국어 회의가 많다면 → Clova Note
네이버가 만든 서비스라 한국어 인식 정확도가 가장 높습니다. 무료이고 앱도 있어서 접근성이 좋습니다.

### 영어 회의 + Zoom → Otter.ai
Zoom, Google Meet에 자동 참여해서 실시간으로 텍스트를 생성합니다. 영어 인식률이 99%에 달합니다.

### 팀 협업 중심 → Fireflies.ai
CRM 연동, 자동 액션 아이템 배정 등 팀 기능이 강합니다.

## 실전 워크플로우

### Before (기존)
```
회의 → 수기 메모 → 정리 (30분) → 공유 → 누락 발생
```

### After (AI 도입 후)
```
회의 → AI 자동 녹음·변환 → AI 요약 → 액션 아이템 자동 추출 → 슬랙 자동 공유
```

**절감 효과:** 회의당 30분 → 5분 (리뷰만)

## 자주 묻는 질문

### 녹음 동의는 어떻게 받나요?
대부분의 도구에서 "이 회의는 녹음됩니다"라는 안내를 자동으로 보여줍니다. 회의 시작 시 참석자에게 고지하는 것이 좋습니다.

### 보안은 안전한가요?
Otter, Fireflies 모두 SOC 2 인증을 받았습니다. Clova Note는 네이버 클라우드 보안 정책을 따릅니다. 민감한 회의는 로컬 녹음 후 업로드를 권장합니다."""
    },
    {
        "slug": "free-ai-tools-2026-top10",
        "search": "free AI tools productivity 2026",
        "title": "2026년 무료 AI 도구 TOP 10 — 돈 안 들이고 생산성 높이기",
        "description": "완전 무료로 사용 가능한 AI 도구 10개를 엄선했습니다. 글쓰기, 이미지, 코딩, 검색, 자동화까지.",
        "date": "Jan 30 2026",
        "tags": ["AI 도구", "무료", "생산성", "추천"],
        "content": """## 무료 AI 도구만으로 충분할까?

충분합니다. 2026년 현재, 대부분의 AI 도구가 무료 티어를 제공하고, 개인 사용에는 무료로도 부족함이 없습니다.

## 무료 AI 도구 TOP 10

### 1. Claude (글쓰기·분석)
- **무료 한도:** Sonnet 모델 무제한 대화
- **최고 용도:** 한국어 글쓰기, 문서 분석, 코딩

### 2. ChatGPT (범용)
- **무료 한도:** GPT-4o mini 무제한
- **최고 용도:** 일상 질문, 아이디어 브레인스토밍

### 3. Google Gemini (검색·분석)
- **무료 한도:** Flash 모델 무제한
- **최고 용도:** 최신 정보 검색, 유튜브 요약

### 4. Perplexity (리서치)
- **무료 한도:** 일반 검색 무제한, Pro Search 일 3회
- **최고 용도:** 심층 리서치, 출처 포함 답변

### 5. Canva (디자인)
- **무료 한도:** 기본 기능 전체
- **최고 용도:** SNS 이미지, 프레젠테이션

### 6. NotebookLM (리서치)
- **무료 한도:** 완전 무료
- **최고 용도:** PDF 분석, 논문 요약

### 7. Microsoft Copilot (이미지 생성)
- **무료 한도:** 일 15회 이미지 생성
- **최고 용도:** 블로그 이미지, 썸네일 제작

### 8. Gamma (프레젠테이션)
- **무료 한도:** 10 크레딧
- **최고 용도:** 빠른 슬라이드 제작

### 9. Otter.ai (회의록)
- **무료 한도:** 월 300분
- **최고 용도:** 영어 회의 자동 기록

### 10. Coda AI (문서·프로젝트)
- **무료 한도:** 기본 AI 기능
- **최고 용도:** 프로젝트 관리, 데이터 분석

## 조합 추천

### 프리랜서/1인 사업자
Claude + Canva + Perplexity + Gamma = **월 $0**

### 개발자
Claude + Cursor(무료) + Perplexity + NotebookLM = **월 $0**

### 마케터
ChatGPT + Canva + Copilot + Otter = **월 $0**

## 자주 묻는 질문

### 무료인데 품질이 떨어지지 않나요?
2026년 기준, 무료 AI 모델의 성능이 2024년 유료 모델을 넘어섰습니다. 일반 업무에는 무료로 충분합니다.

### 유료로 넘어가야 하는 시점은?
하루 사용량이 무료 한도를 넘거나, 팀 협업 기능이 필요할 때입니다."""
    },
    {
        "slug": "ai-email-productivity-tips",
        "search": "AI email management productivity",
        "title": "AI로 이메일 처리 시간 80% 줄이는 5가지 방법",
        "description": "하루 1시간 이메일에 쓰는 시간을 AI로 15분으로 줄이는 방법. Gmail + AI 자동 분류, 답장 생성, 요약 팁.",
        "date": "Jan 29 2026",
        "tags": ["AI 도구", "이메일", "생산성", "Gmail"],
        "content": """## 이메일, 왜 이렇게 시간이 걸리나

평균 직장인이 하루 이메일에 쓰는 시간은 **2.5시간**입니다. 읽고, 분류하고, 답장 쓰고, 후속 조치 하는 데 대부분의 시간이 소모됩니다.

## AI로 이메일 시간 80% 줄이는 5가지 방법

### 1. Gmail AI 요약 기능 활용

Gmail에 내장된 "요약" 버튼을 누르면 긴 이메일 스레드를 3줄로 요약해줍니다.

- **사용법:** 이메일 상단 "요약" 아이콘 클릭
- **절감:** 긴 스레드 읽기 10분 → 30초

### 2. AI 답장 생성

"Help me write" 기능으로 답장 초안을 자동 생성합니다.

- **사용법:** 답장 작성 시 "Help me write" 클릭 → 톤 선택
- **절감:** 답장 작성 5분 → 1분

### 3. 라벨 & 필터 자동화

반복되는 이메일 유형을 자동 분류합니다.

설정 방법:
1. Settings → Filters → Create new filter
2. 조건 설정 (발신자, 키워드 등)
3. 동작 설정 (라벨, 보관, 전달)

### 4. 뉴스레터 정리

Unroll.me나 Clean Email로 구독 메일을 한 곳에 모아봅니다.

- 불필요한 뉴스레터 일괄 구독 취소
- 남길 것만 다이제스트로 하루 1회 수신

### 5. Superhuman + AI (유료)

이메일 전용 AI 클라이언트입니다. 모든 이메일을 AI가 분석하고 우선순위를 매기고 답장까지 생성합니다.

- **가격:** $30/월
- **효과:** 이메일 시간 50% → 80% 절감

## 자주 묻는 질문

### Gmail 무료 기능만으로 충분한가요?
기본적인 요약과 답장 생성은 무료로 가능합니다. 대량 이메일 처리가 필요하면 유료 도구를 고려하세요.

### 회사 이메일에도 적용 가능한가요?
Google Workspace를 쓰는 회사라면 같은 기능을 사용할 수 있습니다. Outlook 사용자는 Microsoft Copilot이 비슷한 기능을 제공합니다."""
    },
    {
        "slug": "claude-tips-10-advanced",
        "search": "Claude AI advanced tips tricks",
        "title": "Claude를 10배 잘 쓰는 고급 프롬프트 팁 10가지",
        "description": "Claude AI를 제대로 활용하는 고급 팁. 시스템 프롬프트, 역할 지정, 체인 프롬프팅 등 프로 유저 기법을 소개합니다.",
        "date": "Jan 28 2026",
        "tags": ["Claude", "프롬프트", "AI 활용", "고급"],
        "content": """## Claude, 제대로 쓰고 있나요?

대부분의 사람들이 Claude를 ChatGPT처럼 단순 질의응답으로만 씁니다. 하지만 프롬프트를 잘 설계하면 10배 이상의 결과물을 얻을 수 있습니다.

## 고급 프롬프트 팁 10가지

### 1. 역할 부여하기

```
당신은 10년 경력의 SEO 전문가입니다.
다음 블로그 글의 SEO 점수를 평가하고 개선점을 제시하세요.
```

역할을 구체적으로 줄수록 전문적인 답변을 받습니다.

### 2. 출력 형식 지정하기

```
아래 형식으로 답변해주세요:
## 요약 (3줄)
## 핵심 포인트 (불릿)
## 실행 가이드 (단계별)
```

원하는 형식을 먼저 보여주면 정확히 그 형식으로 답합니다.

### 3. 예시 제공하기 (Few-shot)

```
이메일 제목을 매력적으로 바꿔주세요.

예시:
- Before: "회의 일정 안내" → After: "🗓️ 내일 10시 마케팅 전략 회의 — 필독 안건 3개"
- Before: "보고서 제출" → After: "📊 Q4 실적 보고서 — 매출 23% 성장 하이라이트"

Now: "프로젝트 업데이트"
```

### 4. 단계별 사고 요청

```
이 문제를 단계별로 생각해주세요:
1. 먼저 문제를 정의하고
2. 가능한 해결책을 3개 나열하고
3. 각 해결책의 장단점을 분석하고
4. 최종 추천을 해주세요
```

### 5. 제약 조건 설정

```
다음 조건을 지켜서 답변해주세요:
- 500자 이내
- 전문 용어 사용 금지
- 초등학생도 이해할 수 있는 수준
```

### 6. 비교 프레임 활용

```
A와 B를 다음 기준으로 비교해주세요:
| 기준 | A | B |
|------|---|---|
| 가격 | | |
| 성능 | | |
| 사용성 | | |
```

### 7. 반대 의견 요청

```
이 전략의 반대 입장에서 비판해주세요.
어떤 리스크가 있고, 왜 실패할 수 있나요?
```

### 8. 페르소나 시뮬레이션

```
당신은 이 제품을 처음 본 60대 어머니입니다.
이 사용 설명서를 읽고 어떤 부분이 이해가 안 되는지 말해주세요.
```

### 9. 메타 프롬프트

```
내가 [목표]를 달성하기 위한 최적의 프롬프트를 작성해주세요.
```

AI에게 프롬프트를 만들어달라고 요청하는 기법입니다.

### 10. 아티팩트 활용

Claude의 아티팩트 기능으로 코드, 문서, 다이어그램을 별도 창에서 생성·수정할 수 있습니다. 대화와 결과물을 분리해서 관리하면 효율적입니다.

## 자주 묻는 질문

### 프롬프트가 길면 비용이 더 나가나요?
무료 티어에서는 횟수 제한이므로 길이는 상관없습니다. 유료(API)에서는 토큰 기반 과금이므로 효율적인 프롬프트가 비용을 절감합니다.

### ChatGPT에도 같은 팁이 통하나요?
대부분 통합니다. 다만 Claude가 긴 문맥과 구조화된 출력에서 더 강점이 있습니다."""
    },
]

if __name__ == '__main__':
    os.makedirs(BLOG_DIR, exist_ok=True)
    
    for i, post in enumerate(posts, 1):
        print(f"[{i}/10] {post['slug']}")
        
        # Unsplash 이미지 검색
        img = search_unsplash(post['search'])
        time.sleep(0.5)  # rate limit
        
        # frontmatter
        hero_image = img['url'] if img else ''
        hero_alt = img['alt'] if img else post['title']
        hero_credit = f'Photo by <a href="{img["author_url"]}">{img["author"]}</a> on <a href="https://unsplash.com">Unsplash</a>' if img else ''
        
        tags_str = json.dumps(post['tags'], ensure_ascii=False)
        
        md = f"""---
title: "{post['title']}"
description: "{post['description']}"
pubDate: "{post['date']}"
heroImage: "{hero_image}"
heroImageAlt: "{hero_alt}"
heroImageCredit: '{hero_credit}'
tags: {tags_str}
---

{post['content']}
"""
        
        filepath = os.path.join(BLOG_DIR, f"{post['slug']}.md")
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(md)
        
        status = "✅" if img else "⚠️ (no image)"
        print(f"  {status} → {filepath}")
    
    print(f"\n✅ {len(posts)}개 글 생성 완료!")
