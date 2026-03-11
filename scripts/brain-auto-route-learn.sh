#!/usr/bin/env bash
# brain-auto-route-learn.sh
# Maintain lightweight auto-route learning state from correction patterns.
#
# Usage:
#   brain-auto-route-learn.sh record --source-ts ISO --raw "..." --pred-label todo|idea|decision|trade|sys
#   brain-auto-route-learn.sh learn    --source-ts ISO --explicit-raw "#todo ... | due | p1"
#   brain-auto-route-learn.sh feedback --feedback-id ID --event-id EVT --label idea --decision keep|drop --text "..."

set -euo pipefail

set +u
source "$(dirname "$0")/env-loader.sh" 2>/dev/null || true
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECOND_BRAIN_DIR="${SECOND_BRAIN_DIR:-${WORKSPACE_DIR}/memory/second-brain}"

HISTORY_FILE="${SECOND_BRAIN_DIR}/.auto-route-history.jsonl"
CONSUMED_FILE="${SECOND_BRAIN_DIR}/.auto-route-consumed.jsonl"
KEYWORDS_FILE="${SECOND_BRAIN_DIR}/.auto-route-keywords.json"
LEARN_LOG_FILE="${SECOND_BRAIN_DIR}/.auto-route-learn-log.jsonl"
LOCK_FILE="${SECOND_BRAIN_DIR}/.auto-route-learn.lock"

SIM_THRESHOLD="${BRAIN_AUTO_LEARN_SIM_THRESHOLD:-0.40}"
WINDOW_SEC="${BRAIN_AUTO_LEARN_WINDOW_SEC:-21600}"
MAX_SCAN_LINES="${BRAIN_AUTO_LEARN_MAX_SCAN_LINES:-300}"
MAX_KEYWORDS="${BRAIN_AUTO_LEARN_MAX_KEYWORDS:-6}"
MAX_WEIGHT="${BRAIN_AUTO_LEARN_MAX_WEIGHT:-7}"

if [[ $# -lt 1 ]]; then
  echo "ERROR: command required (record|learn|feedback)" >&2
  exit 1
fi

CMD="$1"
shift

SOURCE_TS=""
RAW=""
EXPLICIT_RAW=""
PRED_LABEL=""
FEEDBACK_ID=""
EVENT_ID=""
FEEDBACK_LABEL=""
FEEDBACK_DECISION=""
FEEDBACK_TEXT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-ts) SOURCE_TS="${2:-}"; shift 2 ;;
    --raw) RAW="${2:-}"; shift 2 ;;
    --explicit-raw) EXPLICIT_RAW="${2:-}"; shift 2 ;;
    --pred-label) PRED_LABEL="${2:-}"; shift 2 ;;
    --feedback-id) FEEDBACK_ID="${2:-}"; shift 2 ;;
    --event-id) EVENT_ID="${2:-}"; shift 2 ;;
    --label) FEEDBACK_LABEL="${2:-}"; shift 2 ;;
    --decision) FEEDBACK_DECISION="${2:-}"; shift 2 ;;
    --text) FEEDBACK_TEXT="${2:-}"; shift 2 ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

mkdir -p "$SECOND_BRAIN_DIR"
touch "$HISTORY_FILE" "$CONSUMED_FILE" "$LEARN_LOG_FILE"
if [[ ! -f "$KEYWORDS_FILE" ]]; then
  printf '{"todo":{},"idea":{},"decision":{},"trade":{},"sys":{}}\n' > "$KEYWORDS_FILE"
fi

exec 201>"$LOCK_FILE"
flock -x 201

python3 - <<'PY' \
  "$CMD" "$SOURCE_TS" "$RAW" "$EXPLICIT_RAW" "$PRED_LABEL" \
  "$FEEDBACK_ID" "$EVENT_ID" "$FEEDBACK_LABEL" "$FEEDBACK_DECISION" "$FEEDBACK_TEXT" \
  "$HISTORY_FILE" "$CONSUMED_FILE" "$KEYWORDS_FILE" "$LEARN_LOG_FILE" \
  "$SIM_THRESHOLD" "$WINDOW_SEC" "$MAX_SCAN_LINES" "$MAX_KEYWORDS" "$MAX_WEIGHT"
import datetime as dt
import hashlib
import json
import os
import re
import sys

(
    cmd,
    source_ts,
    raw,
    explicit_raw,
    pred_label,
    feedback_id,
    event_id,
    feedback_label,
    feedback_decision,
    feedback_text,
    history_file,
    consumed_file,
    keywords_file,
    learn_log_file,
    sim_threshold_s,
    window_sec_s,
    max_scan_lines_s,
    max_keywords_s,
    max_weight_s,
) = sys.argv[1:20]

SIM_THRESHOLD = float(sim_threshold_s)
WINDOW_SEC = int(window_sec_s)
MAX_SCAN_LINES = int(max_scan_lines_s)
MAX_KEYWORDS = int(max_keywords_s)
MAX_WEIGHT = int(max_weight_s)
VALID_LABELS = {"todo", "idea", "decision", "trade", "sys"}
VALID_DECISIONS = {"keep", "drop"}

STOPWORDS = {
    "the","and","for","with","from","that","this","have","will","into","after","before","then",
    "오늘","내일","지금","그냥","진짜","관련","확인","정리","처리","진행","작업","내용","부분",
    "그리고","하거나","해서","하는","하기","있음","없음","요청","메시지","기록","자동","수동",
    "please","check","update","todo","idea","decision","trade","sys"
}

def now_iso():
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

def parse_iso(ts: str):
    if not ts:
        return None
    try:
        return dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except Exception:
        return None

def normalize_text(text: str) -> str:
    text = " ".join((text or "").split()).strip()
    return text

def extract_tokens(text: str):
    out = []
    for tok in re.findall(r"[A-Za-z][A-Za-z0-9_-]{1,}|[가-힣]{2,}", text.lower()):
        if tok in STOPWORDS:
            continue
        out.append(tok)
    return out

def similarity(a: str, b: str) -> float:
    a_n = normalize_text(a).lower()
    b_n = normalize_text(b).lower()
    if not a_n or not b_n:
        return 0.0
    short, long_ = (a_n, b_n) if len(a_n) <= len(b_n) else (b_n, a_n)
    if len(short) >= 8 and short in long_:
        return 0.85
    ta = set(extract_tokens(a_n))
    tb = set(extract_tokens(b_n))
    if not ta or not tb:
        return 0.0
    inter = len(ta & tb)
    union = len(ta | tb)
    if union == 0:
        return 0.0
    return inter / union

def read_jsonl(path: str):
    rows = []
    if not os.path.isfile(path):
        return rows
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except Exception:
                continue
    return rows

def append_jsonl(path: str, obj: dict):
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(obj, ensure_ascii=False) + "\n")

def ensure_keyword_shape(data: dict):
    for label in VALID_LABELS:
        if not isinstance(data.get(label), dict):
            data[label] = {}
    return data

def load_keywords(path: str):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        data = {}
    return ensure_keyword_shape(data)

def save_keywords(path: str, data: dict):
    data = ensure_keyword_shape(data)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)

def parse_explicit(raw_line: str):
    m = re.match(r"^\s*#(todo|idea|decision|trade|sys)\b\s*(.*)$", raw_line.strip(), re.IGNORECASE)
    if not m:
        return None, ""
    label = m.group(1).lower()
    body = m.group(2).strip()
    if label == "todo":
        parts = [p.strip() for p in body.split("|")]
        content = parts[0] if parts else body
    else:
        parts = [p.strip() for p in body.split("|")]
        content = parts[0] if parts else body
    return label, normalize_text(content)

def record_event():
    if not source_ts:
        print("SKIP:record:no_source_ts")
        return 0
    label = (pred_label or "").strip().lower()
    if label not in VALID_LABELS:
        print("SKIP:record:invalid_pred_label")
        return 0
    norm = normalize_text(raw)
    if not norm:
        print("SKIP:record:empty_raw")
        return 0
    auto_id = hashlib.sha1(f"{source_ts}|{label}|{norm}".encode("utf-8")).hexdigest()[:20]
    # Dedup by scanning recent tail.
    rows = read_jsonl(history_file)
    for row in rows[-120:]:
        if row.get("auto_id") == auto_id:
            print("SKIP:record:duplicate")
            return 0
    append_jsonl(history_file, {
        "auto_id": auto_id,
        "source_ts": source_ts,
        "raw": norm,
        "predicted": label,
        "created_at": now_iso(),
    })
    print(f"RECORDED:{auto_id}")
    return 0

def learn_from_explicit():
    if not source_ts:
        print("SKIP:learn:no_source_ts")
        return 0
    explicit_label, explicit_content = parse_explicit(explicit_raw)
    if explicit_label not in VALID_LABELS or not explicit_content:
        print("SKIP:learn:not_explicit")
        return 0

    base_ts = parse_iso(source_ts)
    if base_ts is None:
        print("SKIP:learn:bad_source_ts")
        return 0

    consumed_ids = {r.get("auto_id") for r in read_jsonl(consumed_file) if r.get("auto_id")}
    history = read_jsonl(history_file)[-MAX_SCAN_LINES:]

    best = None
    best_score = 0.0
    for row in history:
        auto_id = row.get("auto_id")
        if not auto_id or auto_id in consumed_ids:
            continue
        pred = row.get("predicted")
        if pred not in VALID_LABELS:
            continue
        hts = parse_iso(str(row.get("source_ts", "")))
        if hts is None:
            continue
        delta = (base_ts - hts).total_seconds()
        if delta < 0 or delta > WINDOW_SEC:
            continue
        score = similarity(explicit_content, str(row.get("raw", "")))
        if score > best_score:
            best_score = score
            best = row

    if best is None or best_score < SIM_THRESHOLD:
        print("SKIP:learn:no_match")
        return 0

    auto_id = best.get("auto_id")
    predicted = best.get("predicted")
    append_jsonl(consumed_file, {
        "auto_id": auto_id,
        "consumed_at": now_iso(),
        "source_ts": source_ts,
        "reason": "explicit_match",
    })

    if predicted == explicit_label:
        append_jsonl(learn_log_file, {
            "auto_id": auto_id,
            "matched_score": round(best_score, 4),
            "predicted": predicted,
            "corrected": explicit_label,
            "status": "same_prediction",
            "at": now_iso(),
        })
        print("SKIP:learn:same_prediction")
        return 0

    tokens = []
    seen = set()
    for tok in extract_tokens(explicit_content):
        if tok in seen:
            continue
        seen.add(tok)
        tokens.append(tok)
        if len(tokens) >= MAX_KEYWORDS:
            break

    if not tokens:
        append_jsonl(learn_log_file, {
            "auto_id": auto_id,
            "matched_score": round(best_score, 4),
            "predicted": predicted,
            "corrected": explicit_label,
            "status": "no_keywords",
            "at": now_iso(),
        })
        print("SKIP:learn:no_keywords")
        return 0

    data = load_keywords(keywords_file)
    for tok in tokens:
        cur = int(data[explicit_label].get(tok, 0))
        data[explicit_label][tok] = min(MAX_WEIGHT, cur + 1)
        if predicted in VALID_LABELS:
            prev = int(data[predicted].get(tok, 0))
            if prev <= 1:
                data[predicted].pop(tok, None)
            else:
                data[predicted][tok] = prev - 1
    save_keywords(keywords_file, data)

    append_jsonl(learn_log_file, {
        "auto_id": auto_id,
        "matched_score": round(best_score, 4),
        "predicted": predicted,
        "corrected": explicit_label,
        "keywords": tokens,
        "status": "learned",
        "at": now_iso(),
    })
    print(f"LEARNED:{predicted}->{explicit_label}:{','.join(tokens)}")
    return 0

def learn_from_weekly_feedback():
    label = (feedback_label or "").strip().lower()
    decision = (feedback_decision or "").strip().lower()
    body = normalize_text(feedback_text)
    fid = normalize_text(feedback_id)
    evt = normalize_text(event_id)

    if label not in VALID_LABELS:
        print("SKIP:feedback:invalid_label")
        return 0
    if decision not in VALID_DECISIONS:
        print("SKIP:feedback:invalid_decision")
        return 0
    if not body:
        print("SKIP:feedback:empty_text")
        return 0

    if fid:
        for row in read_jsonl(learn_log_file)[-500:]:
            if row.get("feedback_id") == fid and str(row.get("status", "")).startswith("weekly_feedback"):
                print("SKIP:feedback:duplicate")
                return 0

    tokens = []
    seen = set()
    for tok in extract_tokens(body):
        if tok in seen:
            continue
        seen.add(tok)
        tokens.append(tok)
        if len(tokens) >= MAX_KEYWORDS:
            break

    if not tokens:
        print("SKIP:feedback:no_keywords")
        return 0

    data = load_keywords(keywords_file)
    changed = 0
    for tok in tokens:
        cur = int(data[label].get(tok, 0))
        if decision == "keep":
            nxt = min(MAX_WEIGHT, cur + 1)
            data[label][tok] = nxt
            if nxt != cur:
                changed += 1
        else:
            if cur <= 1:
                if tok in data[label]:
                    data[label].pop(tok, None)
                    changed += 1
            else:
                data[label][tok] = cur - 1
                changed += 1

    save_keywords(keywords_file, data)
    append_jsonl(learn_log_file, {
        "feedback_id": fid,
        "event_id": evt,
        "label": label,
        "decision": decision,
        "keywords": tokens,
        "changed": changed,
        "status": "weekly_feedback_applied",
        "at": now_iso(),
    })
    print(f"FEEDBACK_APPLIED:{label}:{decision}:{','.join(tokens)}")
    return 0

if cmd == "record":
    sys.exit(record_event())
if cmd == "learn":
    sys.exit(learn_from_explicit())
if cmd == "feedback":
    sys.exit(learn_from_weekly_feedback())

print("ERROR:unsupported_command")
sys.exit(1)
PY
