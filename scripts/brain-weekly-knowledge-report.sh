#!/usr/bin/env bash
# brain-weekly-knowledge-report.sh
# Generate weekly knowledge report and route:
# - Full report: Discord #decision-log + Telegram
# - Actionable 3 lines: Discord #today
#
# Usage:
#   brain-weekly-knowledge-report.sh [--dry-run] [--force] [--date YYYY-MM-DD]

set -euo pipefail

DRY_RUN=false
FORCE=false
REF_DATE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --force) FORCE=true; shift ;;
    --date) REF_DATE="${2:-}"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/message-guard.sh" 2>/dev/null || true
WORKSPACE="${WORKSPACE_ROOT:-}"
if [[ -z "$WORKSPACE" ]]; then
  if [[ "$SCRIPT_DIR" == */workspace/scripts ]]; then
    WORKSPACE="$(cd "${SCRIPT_DIR}/.." && pwd)"
  else
    WORKSPACE="/root/.openclaw/workspace"
  fi
fi
set +u
source "${SCRIPT_DIR}/env-loader.sh" 2>/dev/null || true
set -u

SECOND_BRAIN_DIR="${SECOND_BRAIN_DIR:-${WORKSPACE}/memory/second-brain}"
CAPTURE_LOG="${WORKSPACE}/data/capture-log.jsonl"
TODO_REGISTRY="${SECOND_BRAIN_DIR}/.todo-router-registry.jsonl"
TAG_REGISTRY="${SECOND_BRAIN_DIR}/.tag-router-registry.jsonl"
WEEKLY_CANDIDATE_FILE="${SECOND_BRAIN_DIR}/.weekly-memory-candidates.jsonl"
MEMORY_PROMOTION_LOG="${SECOND_BRAIN_DIR}/.memory-promotion-decisions.jsonl"
REPORT_DIR="${WORKSPACE}/memory/knowledge-reports"
STATE_DIR="${WORKSPACE}/.state"
STATE_FILE="${STATE_DIR}/weekly-knowledge-last-week.txt"
AUTO_LEARN_SCRIPT="${SCRIPT_DIR}/brain-auto-route-learn.sh"

DISCORD_DECISION_CHANNEL="${DISCORD_DECISION_LOG:-1477310567906672750}"
DISCORD_TODAY_CHANNEL="${DISCORD_TODAY:-1478250773228814357}"
TELEGRAM_TARGET="${TELEGRAM_TARGET:-${TELEGRAM_CHAT_ID:-62403941}}"

mkdir -p "$REPORT_DIR" "$STATE_DIR" "$SECOND_BRAIN_DIR"

if [[ -n "$REF_DATE" ]]; then
  if ! date -d "$REF_DATE" +%F >/dev/null 2>&1; then
    echo "ERROR: invalid --date format (expected YYYY-MM-DD): $REF_DATE" >&2
    exit 1
  fi
fi

if [[ ! -f "$CAPTURE_LOG" ]]; then
  echo "ERROR: capture log not found: $CAPTURE_LOG" >&2
  exit 1
fi

ANALYSIS_JSON="$(python3 - <<'PY' "$CAPTURE_LOG" "$TODO_REGISTRY" "$TAG_REGISTRY" "$REF_DATE"
import json
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse

capture_path, todo_path, tag_path, ref_date = sys.argv[1:5]
kst = timezone(timedelta(hours=9))

stopwords = {
    "the","and","for","with","this","that","from","into","http","https","www","com",
    "auto","captured","status","today","tomorrow","none","todo","idea","decision","trade",
    "링크","정리","자동","수집","항목","검토","필요","후속","관련","요청","공유","기록","확인"
}

cat_weight = {
    "system": 3,
    "investment": 3,
    "work": 3,
    "idea": 2,
    "forward": 2,
    "bookmark": 2,
    "memo": 2,
    "running": 1,
}

cat_tag = {
    "system": "#sys",
    "investment": "#trade",
    "work": "#todo",
    "idea": "#idea",
    "forward": "#idea",
    "bookmark": "#idea",
    "memo": "#idea",
    "running": "#idea",
}


def parse_dt(raw):
    if not raw:
      return None
    s = str(raw).strip()
    if not s:
      return None
    try:
      if s.endswith('Z'):
        return datetime.fromisoformat(s.replace('Z', '+00:00'))
      return datetime.fromisoformat(s)
    except Exception:
      pass
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
      try:
        return datetime.strptime(s, fmt).replace(tzinfo=kst).astimezone(timezone.utc)
      except Exception:
        continue
    return None


def to_kst_date(dt):
    return dt.astimezone(kst).date()


def norm_text(s, limit=56):
    if not s:
      return "(제목 없음)"
    t = re.sub(r"\s+", " ", str(s)).strip()
    if len(t) > limit:
      t = t[: limit - 1] + "…"
    return t


def tokenize(*texts):
    merged = " ".join([t for t in texts if t])
    toks = re.findall(r"[a-zA-Z][a-zA-Z0-9_-]{1,}|[가-힣]{2,}", merged.lower())
    out = set()
    for tok in toks:
      if tok in stopwords:
        continue
      if len(tok) < 2:
        continue
      out.add(tok)
    return out

now_kst = datetime.now(kst).date()
anchor_date = now_kst
if ref_date:
    anchor_date = datetime.strptime(ref_date, "%Y-%m-%d").date()
start_date = anchor_date - timedelta(days=6)
week_key = f"{start_date.isoformat()}~{anchor_date.isoformat()}"

# collect action text tokens from weekly todo/tag registries
action_texts = []
for path, field in ((todo_path, "content"), (tag_path, "content")):
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                dt = parse_dt(obj.get("created_at") or obj.get("source_ts"))
                if not dt:
                    continue
                d = to_kst_date(dt)
                if d < start_date or d > anchor_date:
                    continue
                val = obj.get(field)
                if isinstance(val, str) and val.strip():
                    action_texts.append(val)
    except FileNotFoundError:
        pass

action_tokens = tokenize(" ".join(action_texts))

items = {}
weekly_events = 0
category_counter = Counter()

with open(capture_path, "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            ev = json.loads(line)
        except Exception:
            continue
        dt = parse_dt(ev.get("timestamp"))
        if not dt:
            continue
        d = to_kst_date(dt)
        if d < start_date or d > anchor_date:
            continue

        category = str(ev.get("category") or "bookmark").lower()
        if category == "personal":
            continue

        summary = (ev.get("summary") or ev.get("raw") or "").strip()
        urls = ev.get("urls") if isinstance(ev.get("urls"), list) else []
        first_url = urls[0] if urls else ""
        h = str(ev.get("hash") or "").strip()

        weekly_events += 1
        category_counter[category] += 1

        key = h or first_url or re.sub(r"\s+", " ", summary.lower())[:120]
        if not key:
            continue

        if key not in items:
            items[key] = {
                "key": key,
                "summary": summary,
                "url": first_url,
                "hash": h,
                "category": category,
                "count": 0,
                "first_dt": dt,
                "last_dt": dt,
                "token_set": set(),
            }
        it = items[key]
        it["count"] += 1
        if dt < it["first_dt"]:
            it["first_dt"] = dt
        if dt > it["last_dt"]:
            it["last_dt"] = dt
        if not it["summary"] and summary:
            it["summary"] = summary
        if not it["url"] and first_url:
            it["url"] = first_url
        if category in ("system", "investment", "work"):
            it["category"] = category
        it["token_set"] |= tokenize(summary, first_url)

item_list = list(items.values())
if not item_list:
    print(json.dumps({
      "ok": True,
      "week_key": week_key,
      "start_date": start_date.isoformat(),
      "end_date": anchor_date.isoformat(),
      "weekly_events": 0,
      "unique_items": 0,
      "reused_items": 0,
      "reuse_rate": 0.0,
      "top_items": [],
      "candidates": [],
      "today_actions": [
        "이번 주 신규 지식이 없어 복습 큐 생성 없음",
        "기존 장기기억 후보 1개만 유지/폐기 결정",
        "다음 주 입력 태그 품질(#todo/#idea) 점검"
      ],
      "category_top": []
    }, ensure_ascii=False))
    raise SystemExit(0)

for it in item_list:
    overlap = len(it["token_set"] & action_tokens)
    dup_reuse = it["count"] > 1
    it["reused"] = bool(dup_reuse or overlap > 0)
    it["overlap_count"] = overlap
    it["domain"] = ""
    if it["url"]:
        try:
            it["domain"] = (urlparse(it["url"]).netloc or "").replace("www.", "")
        except Exception:
            it["domain"] = ""
    recency_bonus = 1 if to_kst_date(it["last_dt"]) >= (anchor_date - timedelta(days=1)) else 0
    it["score"] = cat_weight.get(it["category"], 1) + (3 if it["reused"] else 0) + min(it["count"], 3) + recency_bonus

unique_items = len(item_list)
reused_items = sum(1 for it in item_list if it["reused"])
reuse_rate = round((reused_items / unique_items) * 100.0, 1) if unique_items else 0.0

item_list.sort(key=lambda x: (x["score"], x["last_dt"]), reverse=True)
top_items = []
for it in item_list[:5]:
    short = norm_text(it["summary"] or it["domain"] or it["url"])
    tag = cat_tag.get(it["category"], "#idea")
    reused_mark = "재사용" if it["reused"] else "신규"
    top_items.append(f"{short} ({tag}, {reused_mark})")

cand_sorted = sorted(
    item_list,
    key=lambda x: (
        1 if x["reused"] else 0,
        cat_weight.get(x["category"], 1),
        x["score"],
        x["last_dt"],
    ),
    reverse=True,
)

candidates = []
for it in cand_sorted[:3]:
    short = norm_text(it["summary"] or it["domain"] or it["url"])
    if it["reused"] and it["count"] > 1 and it["overlap_count"] > 0:
        reason = "반복 유입 + 실행 태스크 연계"
    elif it["reused"] and it["overlap_count"] > 0:
        reason = "이번 주 실행/결정에서 재사용"
    elif it["reused"]:
        reason = "반복 유입으로 지속 가치 확인"
    else:
        reason = "전략/운영 영향 카테고리"
    tag = cat_tag.get(it["category"], "#idea")
    candidates.append({
        "title": short,
        "reason": reason,
        "tag": tag,
    })

while len(candidates) < 3:
    candidates.append({
        "title": "후보 데이터 부족",
        "reason": "이번 주 신규 지식량 부족",
        "tag": "#idea",
    })

actions = [
    f"{candidates[0]['title']} → MEMORY 승격(keep/drop) 결정",
    f"{candidates[1]['title']} → Todoist 실행 태스크 1개 생성",
    f"{candidates[2]['title']} → 다음 주 재검토 태그 고정",
]

cat_top = [f"{k}:{v}" for k, v in category_counter.most_common(3)]

focus_category = "none"
focus_count = 0
focus_ratio = 0.0
if category_counter:
    focus_category, focus_count = category_counter.most_common(1)[0]
    if weekly_events > 0:
        focus_ratio = round((focus_count / weekly_events) * 100.0, 1)

if reuse_rate >= 40:
    reuse_signal = "GOOD"
elif reuse_rate >= 25:
    reuse_signal = "MID"
else:
    reuse_signal = "LOW"

if focus_ratio >= 45:
    focus_signal = "HIGH"
elif focus_ratio >= 30:
    focus_signal = "MID"
else:
    focus_signal = "LOW"

if reused_items == 0:
    weekly_story = "입력은 있었지만 실행 재사용으로 이어진 항목이 거의 없음. 다음 주는 실행 연결을 우선."
elif reuse_rate < 25:
    weekly_story = "지식 수집은 활발했지만 재사용률이 낮음. 저장보다 실행 연결 비중을 높여야 함."
elif focus_signal == "HIGH":
    weekly_story = f"{focus_category} 카테고리 쏠림이 높음. 편중 완화와 재사용 확대를 함께 관리해야 함."
else:
    weekly_story = "재사용 흐름이 형성되고 있음. 장기기억 승격 후보를 실행 태스크와 함께 확정하는 주간."

reminders = [
    f"이번 주 핵심 후보: {candidates[0]['title']} ({candidates[0]['tag']})",
    f"재사용률 {reuse_rate}% ({reuse_signal}) - 다음 주 목표는 30% 이상 유지",
    f"카테고리 집중도 {focus_category}:{focus_ratio}% ({focus_signal}) - 편중이면 보완 입력 필요",
]

print(json.dumps({
    "ok": True,
    "week_key": week_key,
    "start_date": start_date.isoformat(),
    "end_date": anchor_date.isoformat(),
    "weekly_events": weekly_events,
    "unique_items": unique_items,
    "reused_items": reused_items,
    "reuse_rate": reuse_rate,
    "top_items": top_items,
    "candidates": candidates,
    "today_actions": actions,
    "category_top": cat_top,
    "focus_category": focus_category,
    "focus_count": focus_count,
    "focus_ratio": focus_ratio,
    "reuse_signal": reuse_signal,
    "focus_signal": focus_signal,
    "weekly_story": weekly_story,
    "reminders": reminders,
}, ensure_ascii=False))
PY
)"

if [[ "$(echo "$ANALYSIS_JSON" | jq -r '.ok // false')" != "true" ]]; then
  echo "ERROR: analysis failed" >&2
  echo "$ANALYSIS_JSON" >&2
  exit 1
fi

WEEK_KEY="$(echo "$ANALYSIS_JSON" | jq -r '.week_key')"
START_DATE="$(echo "$ANALYSIS_JSON" | jq -r '.start_date')"
END_DATE="$(echo "$ANALYSIS_JSON" | jq -r '.end_date')"
REPORT_FILE="${REPORT_DIR}/weekly-${END_DATE}.md"
NOW_ISO="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
WEEK_EVENT_ID="$(python3 - <<'PY' "$WEEK_KEY"
import hashlib
import sys
week_key = sys.argv[1]
print(f"weekly-{hashlib.sha1(week_key.encode('utf-8')).hexdigest()[:16]}")
PY
)"

if [[ -f "$STATE_FILE" && "$(cat "$STATE_FILE" 2>/dev/null || true)" == "$WEEK_KEY" ]] && ! $FORCE; then
  echo "SKIP: weekly knowledge report already sent for ${WEEK_KEY}"
  echo "HEARTBEAT_OK"
  exit 0
fi

TOP_LINES="$(echo "$ANALYSIS_JSON" | jq -r '.top_items[]' | nl -w1 -s'. ' 2>/dev/null || true)"
if [[ -z "$TOP_LINES" ]]; then
  TOP_LINES="1. 데이터 없음"
fi

ACTION_LINES="$(echo "$ANALYSIS_JSON" | jq -r '.today_actions[]' | nl -w1 -s'. ' 2>/dev/null || true)"
if [[ -z "$ACTION_LINES" ]]; then
  ACTION_LINES="1. 실행 항목 없음"
fi

WEEKLY_EVENTS="$(echo "$ANALYSIS_JSON" | jq -r '.weekly_events')"
UNIQUE_ITEMS="$(echo "$ANALYSIS_JSON" | jq -r '.unique_items')"
REUSED_ITEMS="$(echo "$ANALYSIS_JSON" | jq -r '.reused_items')"
REUSE_RATE="$(echo "$ANALYSIS_JSON" | jq -r '.reuse_rate')"
CAT_TOP="$(echo "$ANALYSIS_JSON" | jq -r '.category_top | join(", ")')"
FOCUS_CATEGORY="$(echo "$ANALYSIS_JSON" | jq -r '.focus_category // "none"')"
FOCUS_RATIO="$(echo "$ANALYSIS_JSON" | jq -r '.focus_ratio // 0')"
REUSE_SIGNAL="$(echo "$ANALYSIS_JSON" | jq -r '.reuse_signal // "LOW"')"
FOCUS_SIGNAL="$(echo "$ANALYSIS_JSON" | jq -r '.focus_signal // "LOW"')"
WEEKLY_STORY="$(echo "$ANALYSIS_JSON" | jq -r '.weekly_story // "이번 주 핵심 포인트를 점검하세요."')"

REM_1="$(echo "$ANALYSIS_JSON" | jq -r '.reminders[0] // "이번 주 핵심 후보 점검"')"
REM_2="$(echo "$ANALYSIS_JSON" | jq -r '.reminders[1] // "재사용률 점검"')"
REM_3="$(echo "$ANALYSIS_JSON" | jq -r '.reminders[2] // "카테고리 편중 점검"')"

C1_TITLE="$(echo "$ANALYSIS_JSON" | jq -r '.candidates[0].title // "후보 없음"')"
C1_REASON="$(echo "$ANALYSIS_JSON" | jq -r '.candidates[0].reason // "데이터 부족"')"
C1_TAG="$(echo "$ANALYSIS_JSON" | jq -r '.candidates[0].tag // "#idea"')"
C2_TITLE="$(echo "$ANALYSIS_JSON" | jq -r '.candidates[1].title // "후보 없음"')"
C2_REASON="$(echo "$ANALYSIS_JSON" | jq -r '.candidates[1].reason // "데이터 부족"')"
C2_TAG="$(echo "$ANALYSIS_JSON" | jq -r '.candidates[1].tag // "#idea"')"
C3_TITLE="$(echo "$ANALYSIS_JSON" | jq -r '.candidates[2].title // "후보 없음"')"
C3_REASON="$(echo "$ANALYSIS_JSON" | jq -r '.candidates[2].reason // "데이터 부족"')"
C3_TAG="$(echo "$ANALYSIS_JSON" | jq -r '.candidates[2].tag // "#idea"')"

decide_keep_drop() {
  local reason="$1"
  local low
  low="$(echo "$reason" | tr '[:upper:]' '[:lower:]')"
  if [[ "$low" == *"반복"* || "$low" == *"재사용"* || "$low" == *"지속 가치"* ]]; then
    echo "keep"
  else
    echo "drop"
  fi
}

tag_to_label() {
  local tag="${1,,}"
  case "$tag" in
    "#todo") echo "todo" ;;
    "#decision") echo "decision" ;;
    "#trade") echo "trade" ;;
    "#sys") echo "sys" ;;
    *) echo "idea" ;;
  esac
}

append_unique_jsonl() {
  local file="$1"
  local key="$2"
  local json_line="$3"
  if [[ -f "$file" ]] && rg -F -q "\"feedback_id\":\"${key}\"" "$file"; then
    return 0
  fi
  printf '%s\n' "$json_line" >> "$file"
}

record_weekly_candidate_feedback() {
  local idx="$1"
  local title="$2"
  local reason="$3"
  local tag="$4"
  local decision="$5"
  local label="$6"
  local feedback_id="${WEEK_EVENT_ID}-c${idx}"
  local payload
  local promotion
  local feedback_text

  payload="$(jq -cn \
    --arg event_id "$WEEK_EVENT_ID" \
    --arg week_key "$WEEK_KEY" \
    --arg generated_at "$NOW_ISO" \
    --argjson candidate_index "$idx" \
    --arg feedback_id "$feedback_id" \
    --arg title "$title" \
    --arg reason "$reason" \
    --arg tag "$tag" \
    --arg label "$label" \
    --arg decision "$decision" \
    '{event_id:$event_id,week_key:$week_key,candidate_index:$candidate_index,feedback_id:$feedback_id,title:$title,reason:$reason,tag:$tag,label:$label,decision:$decision,source:"weekly_report",generated_at:$generated_at}')"

  promotion="$(jq -cn \
    --arg event_id "$WEEK_EVENT_ID" \
    --arg week_key "$WEEK_KEY" \
    --arg created_at "$NOW_ISO" \
    --argjson candidate_index "$idx" \
    --arg feedback_id "$feedback_id" \
    --arg title "$title" \
    --arg decision "$decision" \
    '{event_id:$event_id,week_key:$week_key,candidate_index:$candidate_index,feedback_id:$feedback_id,title:$title,decision:$decision,status:"weekly_decision_logged",created_at:$created_at}')"

  if $DRY_RUN; then
    echo "[DRY-RUN][weekly-candidate] $payload"
    echo "[DRY-RUN][memory-promotion] $promotion"
  else
    append_unique_jsonl "$WEEKLY_CANDIDATE_FILE" "$feedback_id" "$payload"
    append_unique_jsonl "$MEMORY_PROMOTION_LOG" "$feedback_id" "$promotion"
  fi

  if [[ -x "$AUTO_LEARN_SCRIPT" ]]; then
    feedback_text="${title} ${reason}"
    if $DRY_RUN; then
      echo "[DRY-RUN][auto-learn] feedback_id=${feedback_id} label=${label} decision=${decision}"
    else
      "$AUTO_LEARN_SCRIPT" feedback \
        --feedback-id "$feedback_id" \
        --event-id "$WEEK_EVENT_ID" \
        --label "$label" \
        --decision "$decision" \
        --text "$feedback_text" >/dev/null 2>&1 || true
    fi
  fi
}

C1_DECISION="$(decide_keep_drop "$C1_REASON")"
C2_DECISION="$(decide_keep_drop "$C2_REASON")"
C3_DECISION="$(decide_keep_drop "$C3_REASON")"
C1_LABEL="$(tag_to_label "$C1_TAG")"
C2_LABEL="$(tag_to_label "$C2_TAG")"
C3_LABEL="$(tag_to_label "$C3_TAG")"

make_bar() {
  local value="${1:-0}"
  local max="${2:-100}"
  local width="${3:-12}"
  local filled
  filled="$(awk -v v="$value" -v m="$max" -v w="$width" 'BEGIN { if (m<=0) {print 0; exit} n=int((v/m)*w + 0.5); if (n<0) n=0; if (n>w) n=w; print n }')"
  local empty=$((width - filled))
  printf '[%s%s]' "$(printf '%*s' "$filled" '' | tr ' ' '#')" "$(printf '%*s' "$empty" '' | tr ' ' '-')"
}

REUSE_BAR="$(make_bar "$REUSE_RATE" 100 12)"
FOCUS_BAR="$(make_bar "$FOCUS_RATIO" 100 12)"

REPORT_MSG="주간 지식 리마인드 (${START_DATE}~${END_DATE})

event_id: ${WEEK_EVENT_ID}

한 줄 결론
- ${WEEKLY_STORY}

지표 대시보드
- 재사용률: ${REUSE_RATE}% ${REUSE_BAR} (${REUSE_SIGNAL})
- 실행연결 지식: ${REUSED_ITEMS}/${UNIQUE_ITEMS}
- 집중 카테고리: ${FOCUS_CATEGORY} ${FOCUS_RATIO}% ${FOCUS_BAR} (${FOCUS_SIGNAL})
- 수집 이벤트: ${WEEKLY_EVENTS} | 카테고리 TOP: ${CAT_TOP:-none}

이번 주 리마인드 3줄
1. ${REM_1}
2. ${REM_2}
3. ${REM_3}

장기기억 후보 3개 (keep/drop 판단)
1) ${C1_TITLE} | ${C1_REASON} | ${C1_TAG} | ${C1_DECISION}
2) ${C2_TITLE} | ${C2_REASON} | ${C2_TAG} | ${C2_DECISION}
3) ${C3_TITLE} | ${C3_REASON} | ${C3_TAG} | ${C3_DECISION}

빠른 선택
- 1: 후보1 MEMORY 승격
- 2: 후보2 Todoist 실행
- 3: 후보3 다음 주 보류

회신 가이드: 숫자 1/2/3 만 보내도 됨"

TODAY_MSG="이번 주 지식 실행 3개 (${START_DATE}~${END_DATE})
${ACTION_LINES}

리마인드: 원문은 #decision-log, 실행은 #today에서 처리"

REPORT_MD="## 주간 지식 리마인드 (${START_DATE}~${END_DATE})

- event_id: ${WEEK_EVENT_ID}

### 한 줄 결론
- ${WEEKLY_STORY}

### 지표 대시보드
- 재사용률: ${REUSE_RATE}% ${REUSE_BAR} (${REUSE_SIGNAL})
- 실행연결 지식: ${REUSED_ITEMS}/${UNIQUE_ITEMS}
- 집중 카테고리: ${FOCUS_CATEGORY} ${FOCUS_RATIO}% ${FOCUS_BAR} (${FOCUS_SIGNAL})
- 수집 이벤트: ${WEEKLY_EVENTS}
- 카테고리 TOP: ${CAT_TOP:-none}

### 이번 주 리마인드 3줄
1. ${REM_1}
2. ${REM_2}
3. ${REM_3}

### 장기기억 후보 3개
1) ${C1_TITLE} | ${C1_REASON} | ${C1_TAG} | decision:${C1_DECISION}
2) ${C2_TITLE} | ${C2_REASON} | ${C2_TAG} | decision:${C2_DECISION}
3) ${C3_TITLE} | ${C3_REASON} | ${C3_TAG} | decision:${C3_DECISION}

### Top5 원문
${TOP_LINES}

### 다음 실행 3개 (#today)
${ACTION_LINES}
"

send_msg() {
  local channel="$1"
  local target="$2"
  local message="$3"

  # Validate channel and target before sending
  if ! MESSAGE_GUARD_DRY_RUN="$DRY_RUN" validate_message_params --channel "$channel" --target "$target"; then
    echo "[ERROR] message validation failed: channel=$channel, target=$target" >&2
    return 1
  fi

  if $DRY_RUN; then
    echo "[DRY-RUN][$channel:$target]"
    printf '%s\n' "$message"
    echo "---"
    return 0
  fi
  openclaw message send --channel "$channel" --target "$target" --message "$message" --silent >/dev/null
}

record_weekly_candidate_feedback 1 "$C1_TITLE" "$C1_REASON" "$C1_TAG" "$C1_DECISION" "$C1_LABEL"
record_weekly_candidate_feedback 2 "$C2_TITLE" "$C2_REASON" "$C2_TAG" "$C2_DECISION" "$C2_LABEL"
record_weekly_candidate_feedback 3 "$C3_TITLE" "$C3_REASON" "$C3_TAG" "$C3_DECISION" "$C3_LABEL"

if $DRY_RUN; then
  echo "$REPORT_MD" > "$REPORT_FILE.dryrun"
else
  echo "$REPORT_MD" > "$REPORT_FILE"
fi

# Full report -> #decision-log + Telegram
send_msg discord "$DISCORD_DECISION_CHANNEL" "$REPORT_MSG" || true
send_msg telegram "$TELEGRAM_TARGET" "$REPORT_MSG" || true

# Actionable 3 -> #today
send_msg discord "$DISCORD_TODAY_CHANNEL" "$TODAY_MSG" || true

if ! $DRY_RUN; then
  printf '%s' "$WEEK_KEY" > "$STATE_FILE"
fi

echo "HEARTBEAT_OK"
