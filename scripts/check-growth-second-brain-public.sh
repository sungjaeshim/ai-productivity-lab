#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-https://growth.aisnowball.work}"

DASH=$(curl -sS "$BASE_URL/api/second-brain/dashboard")
CAP=$(curl -sS "$BASE_URL/api/captures?limit=200")

RECENT_LEN=$(echo "$DASH" | jq -r '.data.recent | length')
TOP_DATE=$(echo "$DASH" | jq -r '.data.recent[0].date // ""')
CAP_TOTAL=$(echo "$CAP" | jq -r '.data.total // 0')
IMG_COUNT=$(echo "$CAP" | jq -r '[.data.captures[]? | select((.imagePath//"")!="")] | length')

if [[ "$RECENT_LEN" -lt 1 ]]; then
  echo "CHECK_FAIL recent_len=0"
  exit 1
fi

if [[ "$CAP_TOTAL" -lt 1 ]]; then
  echo "CHECK_FAIL capture_total=0"
  exit 1
fi

echo "CHECK_OK top_date=$TOP_DATE recent_len=$RECENT_LEN captures=$CAP_TOTAL images=$IMG_COUNT"
