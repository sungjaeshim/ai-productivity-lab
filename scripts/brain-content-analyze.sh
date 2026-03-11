#!/usr/bin/env bash
# brain-content-analyze.sh
# Lightweight analyzer for brain inbox entries (link/memo).
#
# Usage:
#   brain-content-analyze.sh --mode link --title "..." --url "..." --text "..."
#   brain-content-analyze.sh --mode memo --title "..." --text "..."
#
# Output(JSON):
# {
#   "summary":"...",
#   "my_opinion":"...",
#   "next_action":"...",
#   "priority":"p1|p2|p3",
#   "category":"trading|system|work|idea|general",
#   "should_ops":true|false,
#   "essence_summary":"...",
#   "key_points":["...", "...", "..."],
#   "our_apply":"..."
# }

set -euo pipefail

MODE="memo"
TITLE=""
URL=""
TEXT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --title) TITLE="${2:-}"; shift 2 ;;
    --url) URL="${2:-}"; shift 2 ;;
    --text) TEXT="${2:-}"; shift 2 ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

python3 - <<'PY' "$MODE" "$TITLE" "$URL" "$TEXT"
import json
import re
import sys
from urllib.parse import urlparse

mode, title, url, text = sys.argv[1:5]
mode = (mode or "memo").lower()
title = (title or "").strip()
url = (url or "").strip()
text = (text or "").strip()

import os
ops_threshold = int(os.getenv("BRAIN_OPS_SCORE_THRESHOLD", "70"))

trade_kw = {
    "nq", "es", "futures", "market", "long", "short", "entry", "exit",
    "리스크", "진입", "청산", "손절", "익절", "트레이딩", "선물", "매수", "매도"
}
trade_strong_kw = {
    "#trade", "nq", "es", "btc", "futures", "trading", "트레이딩", "선물",
    "진입", "청산", "손절", "익절", "매수", "매도", "포지션"
}
sys_kw = {
    "cpu", "ram", "disk", "uptime", "latency", "error", "timeout",
    "시스템", "서버", "장애", "메모리", "디스크", "지연", "에러"
}
work_kw = {
    "todo", "task", "project", "notion", "todoist", "discord", "telegram",
    "작업", "프로젝트", "회의", "정리", "문서", "개발", "배포"
}
high_risk_kw = {
    "손절", "청산", "장애", "timeout", "에러", "긴급", "critical", "p1", "리스크"
}
# p3라도 실행 의도가 분명하면 today(ops)로 승격하기 위한 힌트 키워드
ops_hint_kw = {
    "todo", "to-do", "action", "execute", "run", "fix", "patch", "urgent", "today", "asap",
    "해야", "해줘", "해라", "바로", "즉시", "실행", "조치", "수정", "패치", "점검", "확인", "대응", "요청"
}
# 사용자/시스템 적합도 시그널 (링크성 콘텐츠의 실행 전환용)
fit_kw = {
    "openclaw", "agent", "agents", "automation", "workflow", "router", "routing", "autopull",
    "todoist", "notion", "discord", "telegram", "cron", "monitor", "ops", "ci", "github"
}
fit_domain_kw = {
    "github.com", "docs.openclaw.ai", "openclaw.ai", "notion.so"
}

source = " ".join([title, text, url]).lower()

def pick_category(src: str) -> str:
    # Trade detection should be strict to avoid false positives from generic words
    # like "리스크" appearing in quoted templates.
    trade_hits = sum(1 for k in trade_kw if k in src)
    trade_strong_hits = sum(1 for k in trade_strong_kw if k in src)
    explicit_trade = "#trade" in src

    if explicit_trade or trade_strong_hits >= 2 or (trade_strong_hits >= 1 and trade_hits >= 3):
        return "trading"
    if any(k in src for k in sys_kw):
        return "system"
    if any(k in src for k in work_kw):
        return "work"
    if "idea" in src or "아이디어" in src:
        return "idea"
    return "general"

def top_keywords(src: str):
    toks = re.findall(r"[a-zA-Z][a-zA-Z0-9_-]{1,}|[가-힣]{2,}", src)
    stop = {
        "with","from","this","that","have","will","auto","captured","telegram",
        "today","tomorrow","about","http","https","www","com","net","org",
        "그리고","관련","정리","확인","처리","작업","내용","이슈","링크","메모"
    }
    out = []
    seen = set()
    for t in toks:
        tl = t.lower()
        if tl in stop:
            continue
        if tl in seen:
            continue
        seen.add(tl)
        out.append(t)
        if len(out) >= 3:
            break
    return out

category = pick_category(source)
keywords = top_keywords(source)
domain = ""
if url:
    try:
        domain = (urlparse(url).netloc or "").replace("www.", "")
    except Exception:
        domain = ""

if mode == "link":
    if domain and keywords:
        summary = f"{domain} 링크 핵심: {', '.join(keywords)}"
    elif domain:
        summary = f"{domain} 링크 검토 필요"
    else:
        summary = (title or "링크 수집 항목")[:90]
else:
    first = text.splitlines()[0].strip() if text else title
    summary = (first or "메모 수집 항목")[:90]

if category == "trading":
    my_opinion = "트레이딩 리스크/진입 판단에 직접 영향 가능성이 높음."
    next_action = "시장 열리기 전 체크리스트에 추가하고 진입/청산 조건 확정."
elif category == "system":
    my_opinion = "운영 안정성에 영향 가능성이 있어 빠른 확인이 필요함."
    next_action = "시스템 헬스와 최근 에러 로그 확인 후 조치 항목 확정."
elif category == "work":
    my_opinion = "업무 실행 흐름에 바로 연결 가능한 항목."
    next_action = "Todoist 실행 태스크로 전환하고 담당/기한 고정."
elif category == "idea":
    my_opinion = "아이디어 자산으로 보관 가치가 있음."
    next_action = "핵심 가설 1줄로 정리 후 실험 가능 여부 판단."
else:
    my_opinion = "참고 가치가 있어 후속 검토 후보로 보관."
    next_action = "관련 맥락과 함께 주간 리뷰 목록에 추가."

if mode == "link":
    title_short = (title or "링크 항목").strip()
    if len(title_short) > 64:
        title_short = title_short[:61] + "..."
    category_desc = {
        "trading": "시장/리스크 판단",
        "system": "운영 안정성",
        "work": "실행 업무",
        "idea": "아이디어 자산",
        "general": "참고 정보",
    }.get(category, "참고 정보")
    source_desc = domain or "외부 소스"
    essence_summary = (
        f"이 링크는 {source_desc}의 '{title_short}' 관련 내용으로, "
        f"{category_desc} 관점에서 검토 가치가 있음."
    )
else:
    essence_summary = summary

if category == "trading":
    key_points = [
        "시장 방향/시그널 판단에 직접 영향 가능한 정보인지 먼저 확인.",
        "현재 포지션 규칙(진입/청산/손절)과 충돌 여부 점검.",
        "실행 전 체크리스트 항목 1개로 변환해 재검증.",
    ]
    our_apply = "핵심 조건 1개를 Todoist p2로 넣고 장 시작 전 1회 검증."
elif category == "system":
    key_points = [
        "장애/지연/리소스 위험과 연결되는 신호인지 식별.",
        "영향 범위(서비스/사용자/시간)부터 숫자로 고정.",
        "즉시 조치와 재발방지 액션을 분리해 처리.",
    ]
    our_apply = "재현-영향-완료조건 3칸으로 쪼개서 바로 실행 항목 생성."
elif category == "work":
    key_points = [
        "바로 실행 가능한 작업 단위로 분해 가능한지 확인.",
        "우선순위와 마감 기준을 먼저 고정.",
        "완료 정의(DoD) 1줄 없으면 착수 금지.",
    ]
    our_apply = "Todoist 실행 항목 1개 + 완료 정의 1줄로 고정."
elif category == "idea":
    key_points = [
        "아이디어 자체보다 검증 가능한 가설로 바꾸기.",
        "지금 목표와 연결되는지 1차 필터링.",
        "실험 단위를 작게 쪼개 빠르게 폐기/채택.",
    ]
    our_apply = "가설 1줄 + 실험 1개로 바꿔 24시간 내 검증."
else:
    key_points = [
        "현재 우선순위와 직접 연결되는 부분만 추출.",
        "즉시 실행 가능한 액션이 없으면 보관 처리.",
        "주간 리뷰에서 재판단할 태그를 붙여 유지.",
    ]
    our_apply = "지금 목표와 연결되는 행동 1개만 남기고 나머지는 보류."

priority = "p3"
if any(k in source for k in high_risk_kw):
    priority = "p1"
elif category in ("trading", "system"):
    priority = "p2"
elif category in ("work",):
    priority = "p3"

# TODAY(ops): scoring 기반 승격 (A-prime)
has_ops_hint = any(k in source for k in ops_hint_kw)
has_fit_kw = any(k in source for k in fit_kw)
has_fit_domain = any(k in source for k in fit_domain_kw)

ops_score = 0
ops_reasons = []

if category in ("trading", "system"):
    ops_score += 45
    ops_reasons.append(f"category:{category}")
if priority in ("p1", "p2"):
    ops_score += 35
    ops_reasons.append(f"priority:{priority}")
if has_ops_hint:
    ops_score += 30
    ops_reasons.append("intent_hint")
if has_fit_kw:
    ops_score += 20
    ops_reasons.append("fit_keyword")
if has_fit_domain:
    ops_score += 20
    ops_reasons.append("fit_domain")

# 링크가 완전 일반 정보성(예: x.com generic)인 경우 과승격 방지
if category == "general" and not has_ops_hint and not has_fit_kw and not has_fit_domain:
    ops_score -= 20
    ops_reasons.append("general_penalty")

ops_score = max(0, min(100, ops_score))
should_ops = ops_score >= ops_threshold

print(json.dumps({
    "summary": summary,
    "my_opinion": my_opinion,
    "next_action": next_action,
    "priority": priority,
    "category": category,
    "should_ops": should_ops,
    "ops_score": ops_score,
    "ops_reasons": ops_reasons,
    "essence_summary": essence_summary,
    "key_points": key_points[:3],
    "our_apply": our_apply,
}, ensure_ascii=False))
PY
