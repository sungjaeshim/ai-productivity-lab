# 📚 Curated Reads — 성재님이 공유한 좋은 글/콘텐츠

> 성재님이 채팅에서 공유하거나 언급한 가치 있는 콘텐츠 모음.
> 자동 수집: 링크/글 공유 시 자비스가 요약 + 태그와 함께 저장.

---

## 사용법
- 검색: `memory_search "curated reads 주제"` 
- 태그: #투자 #생산성 #철학 #러닝 #AI #사업 #글쓰기

---

## 📖 Entries

### [2026-02-22] 땅따먹기: AI 에이전트 표준 전쟁의 시작
- **출처**: 성재님 직접 작성
- **태그**: #AI #표준화 #아이덴티티 #블록체인 #전략 #기술패권
- **요약**: 2026년 2월 NIST AI 에이전트 표준화 발표 → 1994년 HTTP 표준화와 유사한 역사적 순간. OSI vs TCP/IP 교훈. 에이전트 아이덴티티 표준이 금융 인프라가 됨.
- **핵심**:
  - TCP/IP의 "누가 보냈는지" 생략 → 30년 보안 부채
  - 에이전트 표준 = "누가 이 세계의 시민인지 결정하는 경계선"
  - 표준이 온체인 아이덴티티와 결합하면 그 체인이 결제 레이어 장악
  - 한국: 반도체서 배운 교훈 (기술력 ≠ 표준) AI 레이어에서 반복 위험
  - "자발적 표준이 강제가 되는 임계점" — 영어, 미터법, TCP/IP처럼
- **액션 아이디어**:
  - MCP, ERC-8004, .agent TLD 등 후보 표준 모니터링
  - 한국의 표준 논의 참여 현황 확인
  - 에이전트 경제의 네트워크 이펙트 기반 찾기

### [2026-02-22] AI 시대 성장 방법: 답은 평등한데 격차는 커진다
- **출처**: 성재님 직접 작성
- **태그**: #AI #성장 #학습 #의도적연습 #피드백
- **요약**: 퍼스트브레인 멘탈모델 + 바둑 AI 다큐 분석. AI가 답을 주는데 왜 성장 격차는 커지는가.
- **핵심**:
  - 성장의 본질 = 의도적 연습 (어려운 과제 → 실행 → 피드백 → 수정 → 재실행)
  - 초보자 실패 패턴: 쉬운 과제만 + 혼자 + 단순 반복
  - AI 아이러니: 기회는 평등, 결과는 불평등. 실력 높을수록 AI 해법을 더 잘 해석/흡수
  - 바둑 AI 후: 상위-하위 격차 확대, but 성별/훈련환경 격차는 축소
  - 성패: AI 쓰느냐 X, AI를 피드백 장치로 설계해 의도적 연습 루프 안에서 굴리느냐
- **액션 아이디어**:
  - AI를 "답 제공자"가 아니라 "피드백 장치"로 설계
  - 의도적 연습 루프 구축: 도전 → 피드백 → 재실행
  - AI 해석 능력 키우기 — 단순 수용 X, 왜 그 답인지 이해하려 노력

*(새 항목이 여기에 추가됩니다)*

---



## [2026-02-24] shuru — macOS AI 코딩 에이전트 샌드박스
- **링크**: https://news.hada.io/topic?id=26934 | https://github.com/superhq-ai/shuru
- **한줄**: macOS에서 Claude Code 실행할 때 VM 샌드박스로 호스트 격리
- **설치**: `curl -fsSL https://shuru.run/install.sh | sh`
- **핵심**:
  - Docker 없음, Apple Virtualization.framework (ARM64 네이티브)
  - Ephemeral 기본 — 끝나면 자동 초기화
  - Checkpoint — Git처럼 환경 스냅샷 저장/분기
- **활용 패턴**:
  ```bash
  # 환경 스냅샷 저장
  shuru checkpoint create mynode --allow-net -- sh -c 'apk add nodejs npm'
  # 재사용
  shuru run --from mynode -- node script.js
  ```
- **태그**: #claude-code #sandbox #macos #ai-agent #dev-tools

## [2026-02-25] https://github.com/codexu/note-gen 참고할 만한 노트앱
- https://github.com/codexu/note-gen 참고할 만한 노트앱
- 🔗 https://github.com/codexu/note-gen

## [2026-02-25] https://x.com/alisvolatprop12/status/2026330689424212157 다리오 인터뷰 번역 꼭 읽기
- https://x.com/alisvolatprop12/status/2026330689424212157 다리오 인터뷰 번역 꼭 읽기
- 🔗 https://x.com/alisvolatprop12/status/2026330689424212157

## [2026-02-25] 🔗 github.com — 좋은 레포
- https://github.com/abc123def456789012345678901234567890/repo 좋은 레포
- 🔗 https://github.com/abc123def456789012345678901234567890/repo

## [2026-02-25] 🔗 github.com — 참고할만한 노트앱
- https://github.com/codexu/note-gen 참고할만한 노트앱
- 🔗 https://github.com/codexu/note-gen

## [2026-02-25] 🔗 x.com — 다리오 인터뷰 번역 꼭 읽기
- https://x.com/alisvolatprop12/status/2026330689424212157 다리오 인터뷰 번역 꼭 읽기
- 🔗 https://x.com/alisvolatprop12/status/2026330689424212157

## [2026-02-25] 🔗 github.com — 노트앱
- https://github.com/codexu/note-gen 노트앱
- 🔗 https://github.com/codexu/note-gen

## [2026-02-25] 🔗 x.com
- https://x.com/wickedguro/status/2025967492359913862?s=46
- 🔗 https://x.com/wickedguro/status/2025967492359913862

## [2026-02-25] 📨 @esprecchiato: 모건 하우절 돈의 심리학 핵심: 부=눈에 보이는 소비가 아닌 아직 쓰지 않은 선택권/자유.
- 모건 하우절 돈의 심리학 핵심: 부=눈에 보이는 소비가 아닌 아직 쓰지 않은 선택권/자유. 복리의 핵심=오랫동안 살아남는 것. 돈의 최고 배당금=내가 원하는 것을 원할 때 원하는 사람과 할 수 있는 능력. 비대칭적 리스크=단 한 번의 파산이 모든 성공을 앗아감. 낙관주의(부자 되기)+편집증적 검소함(부자 유지) 균형.
- 🔗 https://x.com/esprecchiato/status/2026462154271109613
- 📨 출처: @esprecchiato

## [2026-02-25] 📨 @d4m1n: Ralph Loop 공식 설정 가이드: npx @pageai/ralph-loop 원커맨드 
- Ralph Loop 공식 설정 가이드: npx @pageai/ralph-loop 원커맨드 설치. .agent/디렉토리(PROMPT/SUMMARY/STEERING/tasks/skills). PRD→태스크 자동분해. Docker 샌드박스. ./ralph.sh -n 2 → n 30 → 야간. STEERING.md로 실행중 방향전환. 핵심원리: 컨텍스트 초기화 p
- 🔗 https://x.com/d4m1n/status/2026274161933287849
- 📨 출처: @d4m1n

## [2026-02-25] 📨 GeekNews: 호기심은 문제 해결 첫걸음. 경력 후반 모호한 문제 증가→틀리는 것 방지보다 틀렸을 때 비
- 호기심은 문제 해결 첫걸음. 경력 후반 모호한 문제 증가→틀리는 것 방지보다 틀렸을 때 비용을 줄이는 게 핵심. Bad/Good/Best 3단계 패턴. 호기심=자신이 중요한 정보를 놓치고 있을 가능성을 열어두는 것. 채용/팬데믹/데이터로컬리티 사례.
- 🔗 https://news.hada.io/topic?id=26968
- 📨 출처: GeekNews

## [2026-02-25] 📨 @techwith_ram: MIT 최적화 알고리즘 교재 무료 PDF. Algorithms for Optimizatio
- MIT 최적화 알고리즘 교재 무료 PDF. Algorithms for Optimization - MIT 공식 교재. 최적화 이론, 그래디언트, 메타휴리스틱, 강화학습 기초 포함.
- 🔗 https://drive.google.com/file/d/1Rx7MAekKZbyNVc5B2MNfR0HXXIEJCksp/view
- 📨 출처: @techwith_ram

## [2026-02-25] 📨 @AndrewCurran_: Anthropic Cowork 금융 플러그인 확장: Financial analysis, I
- Anthropic Cowork 금융 플러그인 확장: Financial analysis, Investment banking, Equity research, Private equity, Wealth management. Claude Enterprise용. financial-services-plugins repo 공식 확장판.
- 🔗 https://x.com/AndrewCurran_/status/2026310580190269675
- 📨 출처: @AndrewCurran_

## [2026-02-25] 📨 [삼성 이영진] 글로벌 AI/SW: 앤스로픽 The Briefing Enterprise Agents 발표. GSI Partne
- 앤스로픽 The Briefing Enterprise Agents 발표. GSI Partners: Accenture BCG Deloitte Infosys KPMG PwC. SI Partners: Tribe AI Turing Slalom 등 8개. 오늘 런칭: Plugin usability 개선, Admin controls for MCP, New connect
- 📨 출처: [삼성 이영진] 글로벌 AI/SW

## [2026-02-25] 📨 [삼성 이영진] 글로벌 AI/SW: Anthropic The Briefing 신규 커넥터: Apollo Clay Docusig
- Anthropic The Briefing 신규 커넥터: Apollo Clay Docusign Factset Gmail Google Drive Google Calendar Harvey LegalZoom MSCI Outreach Similarweb WordPress. 신규 플러그인: HR Design Engineering Operations Financial 
- 📨 출처: [삼성 이영진] 글로벌 AI/SW

## [2026-02-27] 🔗 x.com
- https://x.com/openclaw/status/2027174278257336542?s=46
- 🔗 https://x.com/openclaw/status/2027174278257336542?s=46

## [2026-02-27] 🔗 x.com
- https://x.com/markminervini/status/2027091252689109475?s=46
- 🔗 https://x.com/markminervini/status/2027091252689109475?s=46

## [2026-02-27] 🔗 x.com
- https://x.com/tom_doerr/status/2027028869685928178?s=46
- 🔗 https://x.com/tom_doerr/status/2027028869685928178?s=46

## [2026-02-27] 🔗 x.com
- https://x.com/github/status/2027082225796456790?s=46
- 🔗 https://x.com/github/status/2027082225796456790?s=46

## [2026-02-27] 🔗 x.com
- https://x.com/learnerbr/status/2027124255604064404?s=46
- 🔗 https://x.com/learnerbr/status/2027124255604064404?s=46

## [2026-02-27] 🔗 x.com
- https://x.com/geeknewshada/status/2027195994119803147?s=46
- 🔗 https://x.com/geeknewshada/status/2027195994119803147?s=46

## [2026-02-27] 🔗 x.com
- https://x.com/jacobsklug/status/2027040417544286325?s=46
- 🔗 https://x.com/jacobsklug/status/2027040417544286325?s=46

## [2026-02-27] 🔗 example.com — 자동캡쳐 점검 테스트 메시지
- 자동캡쳐 점검 테스트 메시지
- 🔗 https://example.com/test

## [2026-02-27] 🔗 example.com — 오토캡쳐 알림 점검
- 오토캡쳐 알림 점검
- 🔗 https://example.com/ok

## [2026-02-27] 🔗 x.com
- https://x.com/geeknewshada/status/2027215369136648354?s=46
- 🔗 https://x.com/geeknewshada/status/2027215369136648354?s=46

## [2026-02-27] 🔗 x.com
- https://x.com/geeknewshada/status/2027192973902151766?s=46
- 🔗 https://x.com/geeknewshada/status/2027192973902151766?s=46

## [2026-02-27] 🔗 x.com
- https://x.com/mad20130301/status/2027284314400944533?s=46
- 🔗 https://x.com/mad20130301/status/2027284314400944533?s=46

## [2026-02-27] 🔗 x.com
- https://x.com/mahler83/status/2027286074079514840?s=46
- 🔗 https://x.com/mahler83/status/2027286074079514840?s=46

## [2026-03-07] Christopher Alexander / The Nature of Order — KR RAG 컬렉션
- **출처**: Wikipedia 4개 문서 수집 후 한국어 변환
- **링크**:
  - https://en.wikipedia.org/wiki/Christopher_Alexander
  - https://en.wikipedia.org/wiki/The_Nature_of_Order
  - https://en.wikipedia.org/wiki/A_Pattern_Language
  - https://en.wikipedia.org/wiki/The_Timeless_Way_of_Building
- **핵심 요약**:
  - 알렉산더는 인간 중심 설계 이론으로 건축·도시·소프트웨어(패턴 언어, 위키)에 영향
  - NOO는 패턴만으로는 부족하며 센터와 구조보존변환을 통한 ‘생명감’ 생성 과정을 제시
  - A Pattern Language는 253개 패턴을 문제-해결 언어로 구성해 일반인의 공동 설계를 지원
  - Timeless Way는 "quality without a name"으로 패턴 언어의 철학적 기반을 설명
- **RAG 문서 경로**: `memory/2026-03-07-christopher-alexander-nature-of-order-ko.md`
- **태그**: #ChristopherAlexander #NatureOfOrder #PatternLanguage #건축 #소프트웨어설계 #RAG
