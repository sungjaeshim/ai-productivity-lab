# Telegram → Discord → Todoist MCP → second-brain + Notion 운영 블루프린트 v1.1 (실행 전 검토용 Draft)

- **문서 버전**: v1.1
- **작성일**: 2026-03-01 (KST)
- **문서 상태**: Draft (검토 전용 / 설정 변경·실행 미적용)
- **대상 운영자**: 성재
- **합의된 최종 구조(고정)**

| 레이어 | 역할 | 운영 기준 |
|---|---|---|
| Telegram | 입력 채널 | 아이디어/링크/메모 유입 전용 |
| Discord (`brain-inbox`, `brain-ops`, `brain-review`) | 실행/상태 관리 | 운영 커뮤니케이션 및 승인 게이트 |
| Todoist MCP | 실행 엔진 (SoT) | 작업 상태의 단일 기준 |
| second-brain + Notion | 누적 지식/인덱스 | 결과 자산화(second-brain) + 검색/대시보드(Notion) |

> 본 문서는 **실행 전 검토용 설계안**이다. 현재 단계에서는 설정 변경, 자동화 실행, 권한 변경을 수행하지 않는다.

---

## 1) 목적/범위 (자동화 vs 수동 승인)

### 1.1 목적

| 항목 | 목적 |
|---|---|
| 입력 표준화 | Telegram 입력을 동일한 작업 단위(`item_id`)로 정규화 |
| 실행 일원화 | Todoist MCP를 기준으로 상태를 관리해 혼선 제거 |
| 운영 가시화 | Discord 채널별 역할 분리로 진행/장애/승인을 즉시 파악 |
| 지식 누적 | 완료 결과를 second-brain + Notion에 축적해 재사용성 확보 |

### 1.2 범위 정의

| 구분 | 자동화 범위 | 수동 승인 범위 |
|---|---|---|
| 입력 수집 | Telegram 원문 파싱, URL 정규화, `item_id` 발급 | 의미가 모호한 항목의 분류 확정 |
| 실행 연계 | Todoist 작업 생성/갱신, 상태 동기화 | 우선순위 급변경, 대량 수정, 재오픈 승인 |
| 상태 운영 | 24h 정체 감지, DONE 요약 생성 | BLOCKED 해제, 예외 처리 최종 결정 |
| 지식 기록 | second-brain 기록, Notion 인덱싱 | 인덱스 스키마 변경, 수동 보정 |
| 리포팅 | 일일 KPI 집계/초안 생성 | 최종 리뷰/배포 |

### 1.3 비범위

| 항목 | 비고 |
|---|---|
| 인프라 신규 구축 상세 | 별도 실행 문서에서 정의 |
| 토큰 신규 발급 절차 | 보안 운영 문서에서 별도 관리 |
| 코드 구현 세부 | 스크립트/리포지토리 단위 문서로 분리 |

---

## 2) 아키텍처 (입력 → 처리 → 실행 → 기록)

### 2.1 End-to-End 흐름

| 단계 | 주체 | 핵심 처리 | 산출물 |
|---|---|---|---|
| 입력 | Telegram | 원문 수신, `source_ref` 생성 | Raw 이벤트 |
| 처리 | Normalizer/Triage | 정규화, 필터, 중복 검사, `item_id` 매핑 | 표준 item (`TODO`) |
| 실행 | Todoist MCP | 작업 생성/갱신, 상태 전이(SoT) | Task 상태 이벤트 |
| 운영 | Discord | `brain-inbox/ops/review` 채널별 로그·승인·경고 | 운영 로그/승인 이력 |
| 기록 | second-brain + Notion | 완료 결과 저장 + 인덱싱 | 지식 자산/조회 인덱스 |

### 2.2 채널별 데이터 흐름

```text
Telegram 입력
  → 정규화/필터/중복검사
  → Discord brain-inbox 등록
  → Todoist MCP 생성/상태 갱신(SoT)
  → Discord brain-ops 상태 브로드캐스트
  → Discord brain-review 요약/승인
  → second-brain 기록
  → Notion 인덱싱
```

### 2.3 Cross-context 제약 및 현재 우회 표준(CLI)

| 항목 | 내용 |
|---|---|
| 제약 | Telegram 바인딩 세션에서 Discord 직접 전송 시 `cross-context denied` 발생 가능 |
| 영향 | Discord 상태 로그 누락/지연 가능 |
| 현재 우회 표준 | **호스트 CLI 릴레이**를 사용해 Discord 전송 수행 |
| 우회 표준 예시 | `openclaw message send --channel discord --target <discord_channel_or_user> --message "<payload>"` |
| 운영 원칙 | direct 전송 실패는 예외가 아니라 정상 경로로 간주하고 outbox 큐로 전환 |
| Draft 제약 | 본 문서 단계에서는 실제 릴레이 실행/설정 변경 없음 |
| [TODO] | outbox JSONL 스키마, 재시도 횟수, ACK 기록 형식 확정 |

---

## 3) 상태머신 (TODO / DOING / DONE / BLOCKED)

### 3.1 상태 정의

| 상태 | 정의 | 필수 메타 |
|---|---|---|
| TODO | 실행 대기 | `created_at`, `priority`, `source_ref` |
| DOING | 실행 중 | `started_at`, `owner` |
| DONE | 완료 | `completed_at`, `done_summary_3lines` |
| BLOCKED | 외부 의존/장애로 중단 | `block_reason`, `next_review_at` |

### 3.2 전이 규칙

| 현재 | 이벤트 | 다음 | 강제 조건 |
|---|---|---|---|
| 없음 | `ingest_valid` | TODO | 필터·중복 통과 |
| TODO | `start_work` | DOING | 담당/시작시각 기록 |
| TODO | `mark_blocked` | BLOCKED | 차단 사유 필수 |
| DOING | `complete_work` | DONE | DONE 3줄 요약 필수 |
| DOING | `mark_blocked` | BLOCKED | 차단 사유 + 해제조건 필수 |
| BLOCKED | `unblock` | TODO 또는 DOING | 재개 계획 필수 |
| DONE | `reopen` | TODO | 재오픈 사유 필수 |

### 3.3 상태 운영 원칙

| 원칙 | 내용 |
|---|---|
| SoT 우선 | 상태의 최종 기준은 Todoist MCP |
| 이력 보존 | 모든 상태 변경에 `updated_at`, `updated_by`, `event_id` 기록 |
| 무단 전이 금지 | 조건 없는 DONE/BLOCKED 전이 금지 |

---

## 4) 채널/도구 책임 분리표

| 시스템 | 역할 | 입력 | 출력 | 비고 |
|---|---|---|---|---|
| Telegram | 입력 게이트 | 원문 메시지/링크 | 표준 item 생성 요청 | 실행 제어 채널 아님 |
| Discord `brain-inbox` | 접수/선별 | 신규 item | triage 결과, 우선순위 제안 | 운영 시작점 |
| Discord `brain-ops` | 상태 운영 | 상태 이벤트 | 경고/진행 로그 | 일상 운영 채널 |
| Discord `brain-review` | 승인/리뷰 | KPI, 예외, 완료 요약 | 승인/보류 결정 | 사람 승인 게이트 |
| Todoist MCP | 실행 엔진(SoT) | item 메타, due, priority | 작업 상태 | 단일 상태 기준 |
| second-brain | 지식 원본 저장 | DONE 요약, 인사이트 | 장기 지식 자산 | 원문 서술 저장소 |
| Notion | 인덱스/조회 | `item_id` 기반 구조화 데이터 | 대시보드/검색 | 인덱스 역할 |

---

## 5) `item_id` 추적 규격

### 5.1 키 규격

| 키 | 포맷 | 예시 |
|---|---|---|
| `item_id` | `BRN-<ULID>` | `BRN-01HT7Y5X8P4M3N2K1Q9R6V0D2A` |
| `fingerprint` | `fp_<sha256_16>` | `fp_5d9ac2f18b7e4c31` |
| `source_ref` | `tg:<chat_id>:<message_id>` | `tg:62403941:128944` |

### 5.2 생성/재사용 규칙

| 순서 | 규칙 |
|---|---|
| 1 | canonical URL/normalized text 생성 |
| 2 | fingerprint 계산 |
| 3 | 동일 fingerprint 존재 시 기존 `item_id` 재사용 |
| 4 | 미존재 시 신규 `item_id` 발급 |
| 5 | 모든 시스템에 동일 `item_id` 저장 |

### 5.3 시스템별 저장 위치

| 시스템 | 저장 위치 | 필수 필드 |
|---|---|---|
| Discord | 메시지 본문 또는 구조화 블록 | `item_id`, `state`, `source_ref` |
| Todoist MCP | task description/metadata | `item_id`, `state`, `priority`, `due` |
| second-brain | 문서 헤더(frontmatter/상단 메타) | `item_id`, `fingerprint`, `state` |
| Notion | DB 속성(`Local_ID` 등) | `Local_ID=item_id`, `Fingerprint`, `State` |

### 5.4 최소 공통 메타 스키마

```json
{
  "item_id": "BRN-01HT7Y5X8P4M3N2K1Q9R6V0D2A",
  "fingerprint": "fp_5d9ac2f18b7e4c31",
  "source": "telegram",
  "source_ref": "tg:62403941:128944",
  "state": "TODO",
  "created_at": "2026-03-01T10:50:00+09:00",
  "updated_at": "2026-03-01T10:50:00+09:00"
}
```

---

## 6) 자동화 규칙 (필터 / 중복 / 24h 정체 / DONE 3줄)

### 6.1 규칙 표

| 규칙 | 트리거 | 처리 | 결과 |
|---|---|---|---|
| 링크 필터 | 신규 URL 입력 | 추적 파라미터 제거 + 잡링크 패턴 검사 | 유효/폐기 판정 |
| 중복 방지 | fingerprint 생성 | 기존 항목 재사용, 신규 생성 차단 | 중복률 감소 |
| 24h 정체 경고 | TODO/DOING 무변경 24h | `brain-ops` 경고 + `brain-review` 에스컬레이션 | 정체 해소 유도 |
| DONE 3줄 | DONE 전이 | 자동 초안 생성(완료/근거/다음액션) | 회고 품질 표준화 |

### 6.2 필터 기준

| 항목 | 기준 |
|---|---|
| 제거 파라미터 | `utm_*`, `fbclid`, `gclid`, `mc_cid`, `mc_eid` |
| 저품질 패턴 | `doubleclick`, `googlesyndication`, `adservice`, `promo`, `sponsor` |
| canonical 처리 | scheme/host 소문자화, trailing slash 정리, tracking query 제거 |

### 6.3 정체 경고 기준

| 경과 시간 | 레벨 | 조치 |
|---|---|---|
| 24시간 | WARN | 담당자 확인 요청 |
| 48시간 | ALERT | BLOCKED 전환 또는 계획 재설정 검토 |

### 6.4 DONE 3줄 표준

| 줄 | 내용 |
|---|---|
| 1 | 무엇을 완료했는가 |
| 2 | 왜 유효한 결과인가(근거/산출물) |
| 3 | 다음 액션 1개 |

---

## 7) 예외/장애 처리

### 7.1 시나리오 대응표

| 시나리오 | 탐지 신호 | 자동 대응 | 수동 개입 기준 |
|---|---|---|---|
| cross-context 차단 | `cross-context denied` | outbox 적재 + CLI 릴레이 대기 | 동일 item 2회 연속 실패 |
| Discord 전송 실패 | timeout / 4xx / 5xx | 백오프 재시도(1m→5m→15m) | 3회 실패 시 review 보고 |
| Todoist 반영 실패 | create/update 실패 | `sync_pending` 마킹 + 재시도 큐 | 1시간 초과 시 수동 등록 |
| Notion 인덱싱 실패 | upsert/스키마 오류 | second-brain 우선 저장 | 일일 점검에서 일괄 복구 |

### 7.2 우선순위 원칙

| 우선순위 | 원칙 |
|---|---|
| 1 | 실행 상태 보존(Todoist MCP) |
| 2 | 운영 가시성 보존(Discord 로그) |
| 3 | 지식 인덱스 보존(Notion) |

---

## 8) 보안/권한 원칙

### 8.1 보안 원칙

| 원칙 | 적용 |
|---|---|
| 최소 권한 | 채널/도구별 토큰 권한 분리 |
| 비밀정보 비노출 | 토큰은 `credentials/.env` 보관, 문서/로그 마스킹 |
| 승인 게이트 | 삭제/외부발송/권한변경/대량수정은 승인 필수 |
| 감사 가능성 | 상태 전이/우회 송신/복구 이력 기록 |

### 8.2 권한 레벨

| 레벨 | 작업 | 승인 |
|---|---|---|
| L1 (저위험) | TODO 생성, 상태 업데이트, 요약 작성 | 불필요 |
| L2 (중위험) | 대량 재동기화, 우선순위 일괄 조정 | 필요 |
| L3 (고위험) | 삭제, 권한 변경, 외부 전송 정책 변경 | 필수 |

---

## 9) KPI 수치 목표

| KPI | 정의 | 목표 |
|---|---|---|
| 접수 처리시간 | Telegram 입력→TODO 등록 | P50 ≤ 10분 / P90 ≤ 30분 |
| 누락률 | 입력 대비 `item_id` 미생성 비율 | ≤ 1.0% |
| 중복 등록률 | 동일 fingerprint 중복 생성 비율 | ≤ 2.0% |
| 상태 반영 지연 | Todoist 변경→Discord 반영 지연 | ≤ 5분 |
| 완료율 | 생성 대비 DONE 비율(주간) | ≥ 70% |
| 리드타임 | TODO→DONE 소요 시간 | P50 ≤ 72h / P90 ≤ 7일 |
| 기록 성공률 | DONE 중 기록 성공률 | second-brain 100% / Notion ≥ 98% |

> 초기 2주: 기준선(baseline) 측정 기간으로 운영하고 목표는 주간 리뷰에서 조정한다.

---

## 10) Phase 0~3 롤아웃

| Phase | 목적 | 자동화 범위 | 진입/종료 기준 |
|---|---|---|---|
| Phase 0 | 문서 합의 | 없음 | 본 문서 승인 시 종료 |
| Phase 1 | Dry-run 검증 | 실제 반영 없이 로그 시뮬레이션 | 누락/중복 추적 체계 안정 |
| Phase 2 | 반자동 운영 | 입력/분류/생성 자동, 위험작업 수동 승인 | KPI 안정 + 장애 대응 검증 |
| Phase 3 | 규칙 기반 자동 운영 | 상태전이/리포트 자동 + 예외만 승인 | 2주 연속 KPI 달성 |

### 10.1 현재 단계

| 항목 | 값 |
|---|---|
| 현재 상태 | **Phase 0 (문서 검토 중)** |
| 실행 여부 | 미실행 |
| 설정 변경 여부 | 미변경 |

---

## 11) 롤백/점검 체크리스트

### 11.1 롤백 트리거

| 트리거 | 기준 |
|---|---|
| 누락 급증 | 일일 누락률 > 3% |
| 중복 급증 | 중복 등록률 > 5% |
| 동기화 장애 장기화 | 핵심 연동 실패 1시간 이상 지속 |
| 상태 불일치 | 일 5건 초과 |

### 11.2 롤백 절차

| 단계 | 조치 |
|---|---|
| 1 | 자동 전이 중지, 신규 항목 TODO 적재만 유지 |
| 2 | outbox/registry 기준 최근 변경분 대조 복구 |
| 3 | 이전 안정 Phase로 복귀 |
| 4 | 원인 분석 후 재진입 조건 충족 시 재개 |

### 11.3 운영 점검 체크리스트

| 주기 | 점검 항목 | 체크 |
|---|---|---|
| 일일 | 24h 정체 경고 처리 여부 확인 | [ ] |
| 일일 | DONE 3줄 누락 0건 확인 | [ ] |
| 일일 | Discord↔Todoist 상태 불일치 점검 | [ ] |
| 주간 | KPI 임계치 초과 항목 보정 | [ ] |
| 주간 | 중복/누락 샘플 감사(최소 20건) | [ ] |
| 주간 | Notion 실패 backlog 정리 | [ ] |

---

## 12) 메시지 템플릿 5개

### 템플릿 1) Telegram 접수 확인

```text
[접수] BRN-01HT7Y5X8P4M3N2K1Q9R6V0D2A
- 입력 유형: 링크 1건
- 상태: TODO 후보 생성
- 다음 단계: brain-inbox 등록 대기
```

### 템플릿 2) Discord `brain-inbox` 신규 등록

```text
🧠 신규 항목
item_id: BRN-01HT7Y5X8P4M3N2K1Q9R6V0D2A
title: [리서치] 운영 자동화 규칙 정리
source_ref: tg:62403941:128944
state: TODO
```

### 템플릿 3) Discord `brain-ops` 24h 정체 경고

```text
⚠️ 정체 24h 감지
item_id: BRN-01HT7Y5X8P4M3N2K1Q9R6V0D2A
state: DOING
last_update: 2026-03-01 09:10 KST
제안: BLOCKED 전환 검토 또는 하위 태스크 분할
```

### 템플릿 4) DONE 3줄 요약

```text
✅ DONE | BRN-01HT7Y5X8P4M3N2K1Q9R6V0D2A
1) 완료: 상태 전이 규칙과 KPI 기준을 확정함
2) 근거: 문서/체크리스트/템플릿 3종 갱신
3) 다음: Phase 1 dry-run 승인 요청
```

### 템플릿 5) Discord `brain-review` 일일 리포트

```text
📊 Daily Ops Report (2026-03-01)
- 입력 28건 / TODO 생성 27건 / 누락률 0.0%
- 중복 차단 6건 / 중복 등록률 0.0%
- DONE 11건 / 리드타임 P50 41h
- 이슈: cross-context 2건 (CLI 릴레이 대기)
```

---

## 13) 승인 후 실행 항목

| 순번 | 실행 항목 | 상태 |
|---|---|---|
| 1 | Phase 0 승인(본 문서 v1.1 확정) | [ ] |
| 2 | Phase 1 dry-run 로그 포맷 적용 | [ ] |
| 3 | outbox→CLI 릴레이 표준 운영 적용 | [ ] |
| 4 | Phase 1 결과 리뷰 후 Phase 2 진입 결정 | [ ] |
| 5 | KPI 2주 안정화 후 Phase 3 전환 승인 | [ ] |

---

## 14) 구현 미완 항목 [TODO]

| [TODO] 항목 | 설명 |
|---|---|
| outbox 표준 스키마 확정 | `item_id`, payload, retry_count, ack_at 필드 동결 필요 |
| CLI 릴레이 실행 주체 확정 | 수동 실행/크론 실행/서비스 실행 중 운영안 확정 필요 |
| Todoist 메타 저장 위치 동결 | description vs label vs comment 정책 확정 필요 |
| Notion 속성명 동결 | `Local_ID`, `Fingerprint`, `State`, `Updated_At` 확정 필요 |
| KPI 수집 로그 규격 확정 | JSONL 필드와 집계 스크립트 인터페이스 확정 필요 |

> 이 문서는 검토용 Draft이며, 승인 전까지 어떤 설정/권한/자동화도 적용하지 않는다.
