#!/usr/bin/env bash
# quality-gate.sh - 라우팅 품질 게이트 (A안: SKIP + PRINCIPLE 승격 + 지표)
# Usage: source lib/quality-gate.sh

# source 시 set -u로 인한 미정의 변수 오류 방지
set -o pipefail

# WORKSPACE_DIR 기본값 보장 (source 시점 미정의 대비)
WORKSPACE_DIR="${WORKSPACE_DIR:-/root/.openclaw/workspace}"

# 품질 게이트 설정
QUALITY_SKIP_THRESHOLD="${QUALITY_SKIP_THRESHOLD:-0.3}"  # SKIP 판정 기준 (신뢰도 하한)
QUALITY_PROMOTE_THRESHOLD="${QUALITY_PROMOTE_THRESHOLD:-0.7}"  # PRINCIPLE 승격 기준
QUALITY_MIN_LENGTH="${QUALITY_MIN_LENGTH:-15}"  # 최소 텍스트 길이
QUALITY_METRICS_FILE="${QUALITY_METRICS_FILE:-${WORKSPACE_DIR}/data/quality-metrics.jsonl}"

# SKIP 규칙 (자동 거부)
# 1. 로그/메타데이터 노이즈
# 2. 중복/동일 내용
# 3. 너무 짧거나 의미 없는 텍스트
# 4. 시스템 자동 생성 메시지

quality_skip_reason() {
  local text="$1"
  local low
  low="$(echo "$text" | tr '[:upper:]' '[:lower:]')"
  
  # 규칙 1: 메타데이터 노이즈
  if echo "$low" | grep -Eq 'conversation info \(untrusted metadata\)|sender \(untrusted metadata\)|openclaw runtime context|session_key:|timestamp:.*gmt|message_id:|reply_to_id:'; then
    echo "metadata_noise"
    return 0
  fi
  
  # 규칙 2: 로그성 텍스트 (길이 > 200 + 키워드)
  if [[ "${#text}" -gt 200 ]] && echo "$low" | grep -Eq 'error|warn|fail|timeout|retry|trace|debug'; then
    echo "log_like_text"
    return 0
  fi
  
  # 규칙 3: 너무 짧음 (의미 부족)
  if [[ "${#text}" -lt "$QUALITY_MIN_LENGTH" ]]; then
    echo "too_short"
    return 0
  fi
  
  # 규칙 4: 시스템 메시지
  if echo "$low" | grep -Eq '^(skip:|error:|heartbeat_ok|no_reply|system:|auto:|cron:)'; then
    echo "system_message"
    return 0
  fi
  
  # 규칙 5: 반복적 패턴 (체크/로그성)
  if echo "$low" | grep -Eq '^(ok|done|pass|passing|healthy|success|completed|finished)[:\s]*$'; then
    echo "status_only"
    return 0
  fi
  
  # 규칙 6: URL만 있는 경우 (링크 덩어리)
  if [[ "$text" =~ ^https?://[^\s]+$ ]] && [[ "${#text}" -gt 100 ]]; then
    echo "url_only"
    return 0
  fi
  
  echo ""
}

# PRINCIPLE 승격 판정 (실제 적용 기준)
# - 구체적인 행동 지시
# - 명확한 의사결정
# - 반복 가능한 규칙
# - 검증 가능한 기준

quality_can_promote() {
  local text="$1"
  local tag="$2"
  local low
  low="$(echo "$text" | tr '[:upper:]' '[:lower:]')"
  
  # 승격 조건 체크
  local score=0.0
  
  # +0.2: 구체적 행동 동사
  if echo "$low" | grep -Eq '(적용|변경|수정|추가|삭제|설정|구현|실행|진행|완료|adopt|apply|change|modify|add|remove|set|implement|execute|proceed)'; then
    score=$(awk "BEGIN {printf \"%.1f\", $score + 0.2}")
  fi
  
  # +0.2: 명확한 기준/숫자
  if echo "$low" | grep -Eq '[0-9]+[%일개]|[0-9]+\s*(분|시간|일|주|개월)|threshold|limit|기준|목표|kpi|metric'; then
    score=$(awk "BEGIN {printf \"%.1f\", $score + 0.2}")
  fi
  
  # +0.2: 의사결정 키워드
  if echo "$low" | grep -Eq '(결정|선택|확정|승인|동의|반려|decision|choice|confirm|approve|agree|reject)'; then
    score=$(awk "BEGIN {printf \"%.1f\", $score + 0.2}")
  fi
  
  # +0.2: 규칙/원칙 키워드
  if echo "$low" | grep -Eq '(규칙|원칙|정책|기준|가이드|rule|principle|policy|standard|guide)'; then
    score=$(awk "BEGIN {printf \"%.1f\", $score + 0.2}")
  fi
  
  # +0.1: #decision 태그는 가산점
  if [[ "$tag" == "decision" ]]; then
    score=$(awk "BEGIN {printf \"%.1f\", $score + 0.1}")
  fi
  
  # +0.1: 충분한 길이 (50자 이상)
  if [[ "${#text}" -ge 50 ]]; then
    score=$(awk "BEGIN {printf \"%.1f\", $score + 0.1}")
  fi
  
  # 결과 반환
  if awk -v s="$score" -v t="$QUALITY_PROMOTE_THRESHOLD" 'BEGIN{exit !(s >= t)}'; then
    echo "promote:$score"
    return 0
  else
    echo "keep:$score"
    return 1
  fi
}

# 지표 수집 (raw → kept → routed → applied)
quality_record_metric() {
  local stage="$1"  # raw, kept, routed, applied
  local tag="$2"
  local source="${3:-unknown}"
  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  
  local entry
  entry=$(jq -n \
    --arg stage "$stage" \
    --arg tag "$tag" \
    --arg source "$source" \
    --arg timestamp "$timestamp" \
    '{stage:$stage,tag:$tag,source:$source,timestamp:$timestamp}')
  
  # 파일에 추가
  local metrics_dir
  metrics_dir="$(dirname "$QUALITY_METRICS_FILE")"
  mkdir -p "$metrics_dir" 2>/dev/null || true
  
  echo "$entry" >> "$QUALITY_METRICS_FILE"
}

# 일일 지표 요약
quality_daily_summary() {
  local date="${1:-$(date +%Y-%m-%d)}"
  
  if [[ ! -f "$QUALITY_METRICS_FILE" ]]; then
    echo "No metrics file found"
    return 1
  fi
  
  local raw kept routed applied
  raw=$(grep "\"stage\":\"raw\"" "$QUALITY_METRICS_FILE" | grep "$date" | wc -l)
  kept=$(grep "\"stage\":\"kept\"" "$QUALITY_METRICS_FILE" | grep "$date" | wc -l)
  routed=$(grep "\"stage\":\"routed\"" "$QUALITY_METRICS_FILE" | grep "$date" | wc -l)
  applied=$(grep "\"stage\":\"applied\"" "$QUALITY_METRICS_FILE" | grep "$date" | wc -l)
  
  local skip_rate=0 apply_rate=0
  if [[ "$raw" -gt 0 ]]; then
    skip_rate=$(awk -v r="$raw" -v k="$kept" 'BEGIN{printf "%.1f", (r - k) / r * 100}')
    apply_rate=$(awk -v r="$raw" -v a="$applied" 'BEGIN{printf "%.1f", a / r * 100}')
  fi
  
  echo "📊 Quality Metrics ($date)"
  echo "  Raw: $raw"
  echo "  Kept: $kept (skip rate: ${skip_rate}%)"
  echo "  Routed: $routed"
  echo "  Applied: $applied (apply rate: ${apply_rate}%)"
  echo ""
  echo "🎯 Target: SKIP↑ + Apply↑"
  echo "  Current: SKIP=${skip_rate}% | Apply=${apply_rate}%"
}

# 7일 추세 분석
quality_weekly_trend() {
  local end_date="${1:-$(date +%Y-%m-%d)}"
  local start_date
  start_date=$(date -d "$end_date - 6 days" +%Y-%m-%d)
  
  if [[ ! -f "$QUALITY_METRICS_FILE" ]]; then
    echo "No metrics data available"
    return 1
  fi
  
  echo "📈 7-Day Quality Trend ($start_date ~ $end_date)"
  echo ""
  
  local total_raw=0 total_kept=0 total_applied=0
  local day_count=0
  
  for i in {6..0}; do
    local d
    d=$(date -d "$end_date - $i days" +%Y-%m-%d)
    
    local raw kept applied
    raw=$(grep "\"stage\":\"raw\"" "$QUALITY_METRICS_FILE" | grep "$d" | wc -l)
    kept=$(grep "\"stage\":\"kept\"" "$QUALITY_METRICS_FILE" | grep "$d" | wc -l)
    applied=$(grep "\"stage\":\"applied\"" "$QUALITY_METRICS_FILE" | grep "$d" | wc -l)
    
    total_raw=$((total_raw + raw))
    total_kept=$((total_kept + kept))
    total_applied=$((total_applied + applied))
    
    if [[ "$raw" -gt 0 ]]; then
      local skip_rate apply_rate
      skip_rate=$(awk -v r="$raw" -v k="$kept" 'BEGIN{printf "%.0f", (r - k) / r * 100}')
      apply_rate=$(awk -v r="$raw" -v a="$applied" 'BEGIN{printf "%.0f", a / r * 100}')
      echo "  $d: raw=$raw kept=$kept (${skip_rate}% skip) applied=$applied (${apply_rate}% apply)"
      day_count=$((day_count + 1))
    fi
  done
  
  if [[ "$day_count" -eq 0 ]]; then
    echo "  No data for the past 7 days"
    return 0
  fi
  
  echo ""
  
  local avg_skip avg_apply
  if [[ "$total_raw" -gt 0 ]]; then
    avg_skip=$(awk -v r="$total_raw" -v k="$total_kept" 'BEGIN{printf "%.1f", (r - k) / r * 100}')
    avg_apply=$(awk -v r="$total_raw" -v a="$total_applied" 'BEGIN{printf "%.1f", a / r * 100}')
    echo "  7-day average: SKIP=${avg_skip}% | Apply=${avg_apply}%"
  fi
  
  echo ""
  echo "✅ Success criteria:"
  echo "  SKIP rate increasing (noise reduction)"
  echo "  Apply rate increasing (actionable items)"
}
