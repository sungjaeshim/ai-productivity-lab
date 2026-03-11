#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/.." && pwd)"
BLOG_DIR="/root/.openclaw/workspace/ai-productivity-lab"
BLOG_CONTENT="$BLOG_DIR/src/content/blog"
TODAY_KST="$(TZ=Asia/Seoul date +%F)"
SEND_SCRIPT="$SCRIPT_DIR/send-briefing.sh"

if [[ ! -d "$BLOG_CONTENT" ]]; then
  echo "BLOG_REPORT_ERROR: missing blog content dir: $BLOG_CONTENT"
  exit 1
fi

if [[ ! -x "$SEND_SCRIPT" ]]; then
  echo "BLOG_REPORT_ERROR: send script is not executable: $SEND_SCRIPT"
  exit 1
fi

POST_COUNT="$(find "$BLOG_CONTENT" -maxdepth 1 -type f -name "*.md" | wc -l | tr -d ' ')"
RECENT_7D="$(find "$BLOG_CONTENT" -maxdepth 1 -type f -name "*.md" -mtime -7 | wc -l | tr -d ' ')"
LATEST="$(ls -1t "$BLOG_CONTENT"/*.md 2>/dev/null | head -3 | xargs -I{} basename {} .md || true)"

TODAY_BY_PUBDATE=0
for f in "$BLOG_CONTENT"/*.md; do
  [[ -f "$f" ]] || continue
  raw="$(grep -m1 '^pubDate:' "$f" | sed -E 's/^pubDate:[[:space:]]*"?([^"]+)"?$/\1/' || true)"
  [[ -n "$raw" ]] || continue
  iso="$(date -d "$raw" +%F 2>/dev/null || true)"
  if [[ "$iso" == "$TODAY_KST" ]]; then
    TODAY_BY_PUBDATE=$((TODAY_BY_PUBDATE + 1))
  fi
done

LAST_COMMIT="$(git -C "$BLOG_DIR" log -1 --format="%h %s (%cr)" 2>/dev/null || echo "N/A")"
UNPUSHED="$(git -C "$BLOG_DIR" log origin/main..HEAD --oneline 2>/dev/null | wc -l | tr -d ' ')"

PUSH_LINE="• 미푸시 커밋: $UNPUSHED개 ✅"
if [[ "${UNPUSHED:-0}" -gt 0 ]]; then
  if git -C "$BLOG_DIR" push >/tmp/blog-report-push.log 2>&1; then
    PUSH_LINE="• 미푸시 커밋: $UNPUSHED개 → push 완료 ✅"
    UNPUSHED=0
  else
    PUSH_ERR="$(tail -1 /tmp/blog-report-push.log 2>/dev/null || echo 'push failed')"
    PUSH_LINE="• 미푸시 커밋: $UNPUSHED개 → push 실패 ⚠️ ($PUSH_ERR)"
  fi
fi

BROKEN_LINKS="$(python3 - <<'PY'
from pathlib import Path
import re
root = Path('/root/.openclaw/workspace/ai-productivity-lab/src/content/blog')
pattern = re.compile(r'\[[^\]]*\]\(([^)]+)\)')
broken = 0
for md in root.glob('*.md'):
    text = md.read_text(encoding='utf-8', errors='ignore')
    for href in pattern.findall(text):
        href = href.strip()
        if not href or href.startswith(('http://','https://','mailto:','#','tel:')):
            continue
        if href.startswith('/'):  # site absolute path, skip strict check
            continue
        href = href.split('#',1)[0].split('?',1)[0]
        target = (md.parent / href).resolve()
        if target.exists():
            continue
        # try markdown extension fallback
        if not target.suffix and target.with_suffix('.md').exists():
            continue
        broken += 1
print(broken)
PY
)"

if [[ "${BROKEN_LINKS:-0}" -gt 0 ]]; then
  LINK_LINE="• 내부 링크 경고: $BROKEN_LINKS개 ⚠️"
else
  LINK_LINE="• 내부 링크 경고: 0개 ✅"
fi

LATEST_BLOCK=""
if [[ -n "$LATEST" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && LATEST_BLOCK+="• $line"$'\n'
  done <<< "$LATEST"
else
  LATEST_BLOCK="• (none)"
fi

REPORT_FILE="$(mktemp)"
cat > "$REPORT_FILE" <<EOF
📊 블로그 데일리 리포트 ($TODAY_KST)

━━━━━━━━━━━━━━━━━

📈 통계
• 전체 게시물: $POST_COUNT개
• 최근 7일: $RECENT_7D개
• 오늘 pubDate: $TODAY_BY_PUBDATE개
$PUSH_LINE
$LINK_LINE

📝 최신 게시물
${LATEST_BLOCK%$'\n'}

🔧 마지막 커밋
$LAST_COMMIT

━━━━━━━━━━━━━━━━━
EOF

"$SEND_SCRIPT" --message-file "$REPORT_FILE"
rm -f "$REPORT_FILE"

echo "HEARTBEAT_OK"
