#!/usr/bin/env bash
set -euo pipefail

# GitHub repo scanner (stars >= N) for weekly maintenance
# Output: markdown report + compact stdout summary

MIN_STARS="10"
PER_QUERY_LIMIT="30"
TOP_N="20"
OUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --min-stars) MIN_STARS="${2:-10}"; shift 2 ;;
    --limit) PER_QUERY_LIMIT="${2:-30}"; shift 2 ;;
    --top) TOP_N="${2:-20}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

DATE_KST="$(TZ=Asia/Seoul date +%F)"
NOW_KST="$(TZ=Asia/Seoul date '+%F %T %Z')"
OUT_DIR="/root/.openclaw/workspace/memory/github-scan"
mkdir -p "$OUT_DIR"
if [[ -z "$OUT" ]]; then
  OUT="$OUT_DIR/$DATE_KST.md"
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "BLOCKER: AUTH (gh CLI not installed)"
  echo "resume: install gh, then run: bash /root/.openclaw/workspace/scripts/github-repo-scanner.sh"
  exit 2
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "BLOCKER: AUTH (gh auth missing)"
  echo "resume: gh auth login && bash /root/.openclaw/workspace/scripts/github-repo-scanner.sh"
  exit 2
fi

TMP_JSONL="$(mktemp)"
trap 'rm -f "$TMP_JSONL"' EXIT

queries=(
  "topic:ai agent framework"
  "topic:automation productivity"
  "topic:trading quant"
  "topic:developer-tools cli"
)

for q in "${queries[@]}"; do
  gh search repos "$q stars:>=${MIN_STARS} archived:false fork:false" \
    --limit "$PER_QUERY_LIMIT" \
    --json fullName,url,description,stargazersCount,updatedAt,language \
    --jq '.[] | {full_name:.fullName, html_url:.url, description, stargazers_count:.stargazersCount, updated_at:.updatedAt, language, query: "'"$q"'"}' \
    | jq -c . >> "$TMP_JSONL" || true
done

python3 - "$TMP_JSONL" "$OUT" "$NOW_KST" "$TOP_N" <<'PY'
import json, sys, datetime
from pathlib import Path

inp, out_path, now_kst, top_n = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])

items = []
with open(inp, 'r', encoding='utf-8') as f:
    for line in f:
        line=line.strip()
        if not line:
            continue
        try:
            items.append(json.loads(line))
        except Exception:
            pass

by_repo = {}
for it in items:
    key = it.get('full_name')
    if not key:
        continue
    cur = by_repo.get(key)
    if cur is None or int(it.get('stargazers_count') or 0) > int(cur.get('stargazers_count') or 0):
        by_repo[key] = it

repos = list(by_repo.values())

# Rank by stars desc, then updated_at desc
repos.sort(key=lambda x: (int(x.get('stargazers_count') or 0), x.get('updated_at') or ''), reverse=True)
repos = repos[:top_n]

lines = []
lines.append(f"# GitHub Repo Scan — {now_kst}")
lines.append("")
lines.append(f"- unique_repos: {len(by_repo)}")
lines.append(f"- selected_top: {len(repos)}")
lines.append("")

if not repos:
    lines.append("No repositories found for current filters.")
else:
    for i, r in enumerate(repos, 1):
        name = r.get('full_name', 'unknown')
        url = r.get('html_url', '')
        desc = (r.get('description') or '').replace('\n', ' ').strip()
        stars = r.get('stargazers_count', 0)
        lang = r.get('language') or '-'
        updated = r.get('updated_at') or '-'
        q = r.get('query') or '-'
        lines.append(f"## {i}. {name}")
        lines.append(f"- stars: {stars} | lang: {lang} | updated: {updated}")
        lines.append(f"- source_query: `{q}`")
        if desc:
            lines.append(f"- desc: {desc}")
        if url:
            lines.append(f"- url: {url}")
        lines.append("")

Path(out_path).parent.mkdir(parents=True, exist_ok=True)
Path(out_path).write_text("\n".join(lines).rstrip()+"\n", encoding='utf-8')

print(f"SCAN_OK unique={len(by_repo)} selected={len(repos)} out={out_path}")
if repos:
    print(f"TOP1 {repos[0].get('full_name')} stars={repos[0].get('stargazers_count',0)}")
PY

echo "DONE github-repo-scanner"
