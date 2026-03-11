#!/bin/bash
# 자동 블로그 포스팅 스크립트
# 사용법: ./auto-blog-post.sh [카테고리] [키워드]
# 카테고리: ai-tools, trading, tech-tutorial
# 예시: ./auto-blog-post.sh ai-tools "ai agents productivity"
#
# 이 스크립트는 OpenClaw 에이전트가 실행합니다.
# 실제 글 생성은 에이전트의 LLM이 담당하며,
# 이 스크립트는 파일 생성 + git push 파이프라인입니다.

set -e

REPO_DIR="/root/.openclaw/workspace/ai-productivity-lab"
CATEGORY="${1:-ai-tools}"
KEYWORD="${2:-ai tools}"
DATE=$(date +%Y-%m-%d)
PUB_DATE=$(date +'%b %d %Y')  # "Feb 14 2026" 형식
SLUG=$(echo "$KEYWORD" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')

cd "$REPO_DIR"

BLOG_DIR="src/content/blog"
FILENAME="${SLUG}.md"
FILEPATH="${BLOG_DIR}/${FILENAME}"

if [ -f "$FILEPATH" ]; then
    echo "ERROR: $FILEPATH already exists"
    exit 1
fi

echo "=== Auto Blog Post Pipeline ==="
echo "Category: $CATEGORY"
echo "Keyword: $KEYWORD"
echo "Slug: $SLUG"
echo "File: $FILEPATH"
echo "Date: $PUB_DATE"
echo ""
echo ">> 파일 경로 준비 완료. 에이전트가 콘텐츠를 생성합니다."
echo "FILEPATH=$FILEPATH"
echo "PUB_DATE=$PUB_DATE"
echo "SLUG=$SLUG"
