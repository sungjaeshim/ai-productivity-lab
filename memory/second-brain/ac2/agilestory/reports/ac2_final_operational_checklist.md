# AC2 최종 운영 체크리스트 (1페이지)

- 작성 시각: 2026-03-03 11:00 KST
- 상태: **DONE ✅ (운영 후속 0건)**
- 범위: AC2 AgileStory 데이터 파이프라인 Phase2~Phase3

## 1) 종료 게이트 (필수)
- [x] Phase2 감사 완료 (`phase2_audit_report.json`)
- [x] 태그 품질 확보 (`posts_without_tags = 0`)
- [x] `general` 태그 0건 마감 (`phase2_general_finalize_report.json`)
- [x] 샘플 QA 20건 PASS (`phase2_sample_qa_20.json`)
- [x] 기준본 잠금 문서/해시 존재 (`phase2_tag_lock.md`)

## 2) 검색 운영성 (Phase3)
- [x] SQLite FTS5 인덱스 생성 (`manifests/ac2_search.db`)
- [x] 문서 JSONL 생성 (`manifests/ac2_docs.jsonl`)
- [x] 검색 CLI 동작 (`scripts/phase3_search.py`)
- [x] 성능 기준 충족 (avg < 1ms, p95 < 1ms)

## 3) 산출물 인덱싱/문서화
- [x] 통합 마감 보고서 작성 (`phase2_phase3_closing_report.md`)
- [x] Phase3 리포트 작성 (`phase3_index_report.md/.json`)
- [x] 제2의 뇌 AC2 README 반영 (`/memory/second-brain/ac2/README.md`)

## 4) 운영 리스크 점검
- [x] 텔레그램 이미지 수신 E2E 완료 — chat_id 62403941, message_id 24532, 이미지 수신 확인됨
- [x] SOFR/금리 프록시(`^IRX`) 표기 정규화 완료 — `nq_macd_multi.py`에 `_fetch_rate_proxy()` 및 정규화 로직 추가, `source` 필드 노출

## 5) 재실행 표준 명령
```bash
# 태그 재감사
cd /root/.openclaw/workspace/memory/second-brain/ac2/agilestory
python3 scripts/ac2_phase2_audit.py

# Phase3 인덱스 재빌드
python3 scripts/phase3_build_index.py

# 검색 스모크 테스트
python3 scripts/phase3_search.py AC2 5
```

## 6) 운영 선언
- AC2 AgileStory는 현재 **운영 종료 패키지(DONE ✅)** 상태.
- 운영 후속(이미지 E2E/금리표기 정규화)까지 모두 완료되어 잔여 액션은 없다.
