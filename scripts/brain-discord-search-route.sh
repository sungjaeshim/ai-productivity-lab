#!/usr/bin/env bash
# brain-discord-search-route.sh
# Discord 검색 결과를 링크 라우팅 파이프라인으로 연결
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INGEST_SCRIPT="$SCRIPT_DIR/brain-link-ingest.sh"

QUERY=""
LIMIT="40"
GUILD_ID="${DISCORD_GUILD_ID:-1477310010395725826}"
CHANNEL_IDS_RAW="${BRAIN_SEARCH_ROUTE_CHANNEL_IDS:-${DISCORD_INBOX:-1478250668052713647}}"
DRY_RUN=false

usage() {
  cat <<USAGE
Usage: $(basename "$0") --query "text" [--limit 40] [--guild-id <id>] [--channel-ids "id1,id2"] [--dry-run]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --query) QUERY="${2:-}"; shift 2 ;;
    --limit) LIMIT="${2:-40}"; shift 2 ;;
    --guild-id) GUILD_ID="${2:-}"; shift 2 ;;
    --channel-ids) CHANNEL_IDS_RAW="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$QUERY" ]]; then
  echo "ERROR: --query required" >&2
  exit 1
fi

# 오늘 운영 테스트 기본값: 65
export BRAIN_OPS_SCORE_THRESHOLD="${BRAIN_OPS_SCORE_THRESHOLD:-65}"

TMP_JSON="$(mktemp)"
trap 'rm -f "$TMP_JSON"' EXIT

CMD=(openclaw message search --channel discord --guild-id "$GUILD_ID" --query "$QUERY" --limit "$LIMIT" --json)
if [[ -n "$CHANNEL_IDS_RAW" ]]; then
  IFS=',' read -r -a CH_ARR <<< "$CHANNEL_IDS_RAW"
  for ch in "${CH_ARR[@]}"; do
    ch_trim="$(echo "$ch" | xargs)"
    [[ -n "$ch_trim" ]] && CMD+=(--channel-ids "$ch_trim")
  done
fi

"${CMD[@]}" > "$TMP_JSON"

python3 - <<'PY' "$TMP_JSON" "$INGEST_SCRIPT" "$DRY_RUN"
import base64, json, re, subprocess, sys

json_path, ingest_script, dry = sys.argv[1:4]
dry = dry.lower() == 'true'

root = json.load(open(json_path, 'r', encoding='utf-8'))
msgs = (root.get('payload') or {}).get('messages') or []

url_re = re.compile(r'https?://\S+')

def clean(u: str) -> str:
    return u.rstrip('`.,;:!?"\'')

processed = 0
routed = 0
for m in msgs:
    content = (m.get('content') or '').strip()
    if not content:
        content = ''

    urls = set(clean(u) for u in url_re.findall(content))
    for att in (m.get('attachments') or []):
        u = (att or {}).get('url')
        if isinstance(u, str) and u:
            urls.add(clean(u))
    for emb in (m.get('embeds') or []):
        u = (emb or {}).get('url')
        if isinstance(u, str) and u:
            urls.add(clean(u))

    if not urls:
        continue

    summary = re.sub(r'\s+', ' ', content).strip()[:220] if content else 'Search hit from Discord'
    opinion = '검색 결과 기반 후보 (실행 가치 점수화 필요)'

    for url in sorted(urls):
        if not url.startswith('http'):
            continue
        processed += 1
        title = re.sub(r'^https?://', '', url).split('/')[0]
        cmd = ['bash', ingest_script, '--url', url, '--title', title, '--summary', summary, '--my-opinion', opinion]
        if dry:
            cmd.append('--dry-run')
        try:
            subprocess.check_output(cmd, text=True, stderr=subprocess.STDOUT)
            routed += 1
            print(f'ROUTED: {url}')
        except subprocess.CalledProcessError as e:
            out = (e.output or '').strip().splitlines()
            last = out[-1] if out else 'unknown error'
            print(f'SKIP: {url} ({last})')

print(f'SUMMARY processed={processed} routed={routed} hits={len(msgs)}')
PY
