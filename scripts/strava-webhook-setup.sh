#!/bin/bash
# Strava Webhook 자동 재등록 스크립트
# cloudflared 재시작 후 새 URL로 Strava 구독 갱신

set -e
source /root/.openclaw/.env

# cloudflared 로그에서 터널 URL 추출 (최대 30초 대기)
echo "Waiting for cloudflared tunnel URL..."
for i in $(seq 1 30); do
  URL=$(journalctl -u cloudflared-strava.service --no-pager -n 50 2>/dev/null | grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1)
  if [ -n "$URL" ]; then
    break
  fi
  sleep 1
done

if [ -z "$URL" ]; then
  echo "ERROR: Could not find tunnel URL"
  exit 1
fi

echo "Tunnel URL: $URL"

# 기존 구독 삭제
echo "Deleting existing subscriptions..."
SUBS=$(curl -s "https://www.strava.com/api/v3/push_subscriptions?client_id=${STRAVA_CLIENT_ID}&client_secret=${STRAVA_CLIENT_SECRET}")
SUB_ID=$(echo "$SUBS" | grep -oP '"id":\s*\K[0-9]+' | head -1)

if [ -n "$SUB_ID" ]; then
  curl -s -X DELETE "https://www.strava.com/api/v3/push_subscriptions/${SUB_ID}?client_id=${STRAVA_CLIENT_ID}&client_secret=${STRAVA_CLIENT_SECRET}"
  echo "Deleted subscription $SUB_ID"
fi

# 새 구독 등록
echo "Registering new subscription..."
RESULT=$(curl -s -X POST "https://www.strava.com/api/v3/push_subscriptions" \
  -F "client_id=${STRAVA_CLIENT_ID}" \
  -F "client_secret=${STRAVA_CLIENT_SECRET}" \
  -F "callback_url=${URL}/webhook" \
  -F "verify_token=jarvis-strava-2026")

echo "Result: $RESULT"
NEW_ID=$(echo "$RESULT" | grep -oP '"id":\s*\K[0-9]+')

if [ -n "$NEW_ID" ]; then
  echo "✅ Strava webhook registered (ID: $NEW_ID) at $URL"
else
  echo "❌ Registration failed"
  exit 1
fi
