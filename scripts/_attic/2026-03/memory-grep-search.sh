#!/bin/bash
# Archived on 2026-03-06: unreferenced grep fallback kept for recovery.
# memory-grep-search.sh - 간단한 grep 기반 메모리 검색 (벡터 검색 실패 시 폴백)
# Usage: bash scripts/memory-grep-search.sh "쿼리" [max_results]

QUERY="$1"
MAX_RESULTS="${2:-10}"
WORKSPACE="/root/.openclaw/workspace"

if [ -z "$QUERY" ]; then
  echo '{"results":[],"error":"쿼리 필요"}'
  exit 1
fi

# 검색 대상 디렉토리
SEARCH_DIRS=(
  "$WORKSPACE/memory"
  "$WORKSPACE/second-brain"
  "$WORKSPACE/insights"
)

# grep 검색 (JSON 출력)
results=$(grep -rn --include="*.md" -i "$QUERY" "${SEARCH_DIRS[@]}" 2>/dev/null | \
  head -n "$MAX_RESULTS" | \
  jq -Rs 'split("\n") | map(select(length > 0)) | to_entries | map({
    score: (100 - .key * 5),
    path: (.value | split(":")[0] | sub("^.*/workspace/"; "")),
    line: (.value | split(":")[1] | tonumber),
    snippet: (.value | split(":") | .[2:] | join(":") | .[0:150])
  })')

if [ -z "$results" ] || [ "$results" = "null" ]; then
  echo '{"results":[],"query":"'"$QUERY"'"}'
else
  echo "{\"query\":\"$QUERY\",\"results\":$results}"
fi
