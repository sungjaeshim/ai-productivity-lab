#!/bin/bash
# 블로그 자동 포스팅 스크립트 - 매일 저녁 9시 실행
# AI 생산성/테크 관련 글 2개를 자동 생성하고 GitHub push

set -e

BLOG_DIR="/root/.openclaw/workspace/projects/ai-blog"
CONTENT_DIR="$BLOG_DIR/src/content/blog"
# 환경변수에서 읽기 (.env 파일 또는 시스템 환경변수)
source /root/.openclaw/workspace/.env 2>/dev/null || true
GITHUB_TOKEN="${GITHUB_TOKEN}"
UNSPLASH_KEY="${UNSPLASH_ACCESS_KEY}"
BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
CHAT_ID="${TELEGRAM_CHAT_ID:-62403941}"
LOG="/root/.openclaw/workspace/projects/ai-blog/logs/auto_post.log"

mkdir -p "$(dirname $LOG)"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Auto post started" >> "$LOG"

# 텔레그램 알림 함수
send_telegram() {
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d "text=$1" > /dev/null 2>&1
}

# 기존 글 목록 (중복 방지용)
EXISTING=$(ls "$CONTENT_DIR"/*.md 2>/dev/null | xargs -I{} basename {} .md | tr '\n' ',')

cd "$BLOG_DIR"

# GLM sub-agent 또는 Opus가 이 스크립트를 실행할 때
# 실제 글 작성은 Python 스크립트로 위임
python3 scripts/daily_post_generator.py 2>> "$LOG"

if [ $? -eq 0 ]; then
    # 빌드 테스트
    npm run build >> "$LOG" 2>&1
    
    if [ $? -eq 0 ]; then
        # Git push
        cd "$BLOG_DIR"
        git add -A
        git commit -m "📝 auto: 일일 자동 포스팅 $(date '+%Y-%m-%d')" 2>> "$LOG"
        git remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@github.com/sungjaeshim/ai-productivity-lab.git"
        git push origin main >> "$LOG" 2>&1
        
        # 알림
        NEW_COUNT=$(git diff --name-only HEAD~1 HEAD -- src/content/blog/ | wc -l)
        send_telegram "📝 블로그 자동 포스팅 완료! 새 글 ${NEW_COUNT}개 추가. 총 $(ls $CONTENT_DIR/*.md | wc -l)개 글."
        
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Success: ${NEW_COUNT} posts added" >> "$LOG"
    else
        send_telegram "❌ 블로그 빌드 실패! 로그 확인 필요."
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Build failed" >> "$LOG"
    fi
else
    send_telegram "❌ 글 생성 실패!"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Post generation failed" >> "$LOG"
fi
