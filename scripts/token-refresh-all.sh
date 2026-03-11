#!/bin/bash
# 모든 API 토큰 자동 갱신
# 매일 06시 백업 크론에서 실행 or 독립 크론
set -euo pipefail

echo "🔑 토큰 갱신 시작..."
ERRORS=0
WARNINGS=0

# 1. OneDrive
echo -n "  OneDrive: "
python3 << 'PYEOF' 2>/dev/null && echo "✅" || { echo "❌"; ERRORS=$((ERRORS+1)); }
import json, requests
config = json.load(open("/root/.openclaw/workspace/credentials/onedrive_config.json"))
token = json.load(open("/root/.openclaw/workspace/credentials/onedrive_token.json"))
resp = requests.post(
    f"https://login.microsoftonline.com/{config['tenant_id']}/oauth2/v2.0/token",
    data={'client_id': config['client_id'], 'grant_type': 'refresh_token',
          'refresh_token': token['refresh_token'], 'scope': ' '.join(config['scopes'])})
data = resp.json()
if 'access_token' not in data: raise Exception(data.get('error_description','failed'))
token['access_token'] = data['access_token']
if 'refresh_token' in data: token['refresh_token'] = data['refresh_token']
json.dump(token, open("/root/.openclaw/workspace/credentials/onedrive_token.json", 'w'), indent=2)
PYEOF

# 2. Strava
echo -n "  Strava: "
# shellcheck disable=SC1091
source /root/.openclaw/workspace/.env 2>/dev/null || true
STRAVA_ID="${STRAVA_CLIENT_ID:-}"
STRAVA_SECRET="${STRAVA_CLIENT_SECRET:-}"

if [ -z "$STRAVA_ID" ] || [ -z "$STRAVA_SECRET" ]; then
    echo "⚠️ (skip: missing STRAVA_CLIENT_ID/SECRET)"
    WARNINGS=$((WARNINGS+1))
else
    python3 - "$STRAVA_ID" "$STRAVA_SECRET" << 'PYEOF' 2>/dev/null && echo "✅" || { echo "❌"; ERRORS=$((ERRORS+1)); }
import json, requests, time, sys
client_id, client_secret = sys.argv[1], sys.argv[2]
token = json.load(open("/root/.openclaw/workspace/credentials/strava_token.json"))
if token.get('expires_at', 0) > time.time() + 3600:
    pass  # still valid
else:
    resp = requests.post("https://www.strava.com/oauth/token", data={
        'client_id': client_id, 'client_secret': client_secret,
        'grant_type': 'refresh_token', 'refresh_token': token['refresh_token']})
    data = resp.json()
    if 'access_token' not in data: raise Exception('refresh failed')
    token.update({k: data[k] for k in ['access_token','refresh_token','expires_at'] if k in data})
    json.dump(token, open("/root/.openclaw/workspace/credentials/strava_token.json", 'w'), indent=2)
PYEOF
fi

# 3. KakaoTalk
echo -n "  Kakao: "
python3 << 'PYEOF' 2>/dev/null && echo "✅" || { echo "❌ (갱신 필요)"; ERRORS=$((ERRORS+1)); }
import json, requests
cred = json.load(open("/root/.openclaw/workspace/credentials/kakao_credentials.json"))
if not cred.get('refresh_token'): raise Exception('no refresh token')
client_id = cred.get('client_id') or cred.get('rest_api_key')
if not client_id: raise Exception('no client_id or rest_api_key')
resp = requests.post("https://kauth.kakao.com/oauth/token", data={
    'grant_type': 'refresh_token', 'client_id': client_id,
    'refresh_token': cred['refresh_token']})
data = resp.json()
if 'access_token' in data:
    cred['access_token'] = data['access_token']
    if 'refresh_token' in data: cred['refresh_token'] = data['refresh_token']
    json.dump(cred, open("/root/.openclaw/workspace/credentials/kakao_credentials.json", 'w'), indent=2)
else:
    raise Exception(data.get('error_description','failed'))
PYEOF

echo ""
if [ "$ERRORS" -eq 0 ]; then
    echo "🔑 전체 갱신 완료 ✅"
else
    echo "⚠️ ${ERRORS}건 실패"
fi

if [ "$WARNINGS" -gt 0 ]; then
    echo "⚠️ ${WARNINGS}건 경고(스킵)"
fi

exit $ERRORS

# ── IPv6 autoSelectFamily 검증 ──
AUTOFAMILY=$(python3 -c "
import json
try:
    c=json.load(open('/root/.openclaw/openclaw.json'))
    v=c.get('channels',{}).get('telegram',{}).get('network',{}).get('autoSelectFamily','MISSING')
    print(v)
except: print('ERROR')
" 2>/dev/null)

if [[ "$AUTOFAMILY" != "false" ]]; then
  echo "⚠️ autoSelectFamily 설정 누락! 텔레그램 연결 실패 가능. 복구 중..."
  openclaw config patch '{"channels":{"telegram":{"network":{"autoSelectFamily":false}}}}' 2>/dev/null
  echo "✅ autoSelectFamily=false 복구 완료"
else
  echo "✅ autoSelectFamily=false 확인"
fi
