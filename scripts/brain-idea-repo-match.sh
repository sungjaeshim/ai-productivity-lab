#!/usr/bin/env bash
set -euo pipefail

set +u
source "$(dirname "$0")/env-loader.sh" 2>/dev/null || true
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECOND_BRAIN_DIR="${SECOND_BRAIN_DIR:-${WORKSPACE_ROOT}/memory/second-brain}"
OUT_FILE="${BRAIN_REPO_MATCHES_PATH:-${SECOND_BRAIN_DIR}/repo-matches.jsonl}"
SKILL_SCRIPT="${BRAIN_REPO_MATCH_SKILL_SCRIPT:-/root/.codex/skills/gh-find-similar-repos/scripts/find_similar_repos.py}"
TOP_N="${BRAIN_REPO_MATCH_TOP_N:-5}"
PER_QUERY_LIMIT="${BRAIN_REPO_MATCH_QUERY_LIMIT:-12}"
DRY_RUN=false
FORCE=false

URL=""
TITLE=""
SUMMARY=""
MY_OPINION=""
HASH=""
CATEGORY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) URL="${2:-}"; shift 2 ;;
    --title) TITLE="${2:-}"; shift 2 ;;
    --summary) SUMMARY="${2:-}"; shift 2 ;;
    --my-opinion) MY_OPINION="${2:-}"; shift 2 ;;
    --hash) HASH="${2:-}"; shift 2 ;;
    --category) CATEGORY="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --force) FORCE=true; shift ;;
    *)
      echo "{\"status\":\"error\",\"reason\":\"unknown arg: $1\"}"
      exit 0
      ;;
  esac
done

META_JSON="$(python3 - <<'PY' "$TITLE" "$SUMMARY" "$MY_OPINION" "$URL" "$CATEGORY"
import json
import re
import sys
from urllib.parse import urlparse

title, summary, opinion, url, category = sys.argv[1:6]
source = " ".join(x for x in [title, summary, opinion, url, category] if x).strip()
lower = source.lower()
domain = ""
if url:
    try:
        domain = (urlparse(url).netloc or "").lower()
    except Exception:
        domain = ""

trigger_terms = {
    "github", "repo", "repository", "open source", "opensource", "fork", "clone",
    "starter", "template", "boilerplate", "mcp", "automation", "workflow",
    "playwright", "browser", "chrome", "google docs", "extension", "agent",
    "dashboard", "saas", "scaffold"
}

should_run = False
reason = "insufficient builder/repo signals"
if "github.com" in lower or domain == "github.com":
    should_run = True
    reason = "github link detected"
elif any(term in lower for term in trigger_terms):
    should_run = True
    reason = "idea contains builder/repo signals"
elif category.lower() in {"idea", "work"} and sum(term in lower for term in trigger_terms) >= 2:
    should_run = True
    reason = "idea/work item with multiple builder signals"

tokens = re.findall(r"[a-z0-9][a-z0-9+-]{1,}", lower)
stop = {
    "about", "after", "allow", "allows", "an", "and", "app", "article", "build", "can",
    "captures", "dated", "extracts", "for", "from", "how", "idea", "into", "logs", "notes",
    "record", "records", "report", "service", "site", "sites", "that", "the", "this",
    "tool", "uses", "using", "web", "with", "writes", "your"
}
keywords = []
for token in tokens:
    if token in stop or token in keywords:
        continue
    keywords.append(token)
    if len(keywords) >= 6:
        break

queries = []
def add(query):
    query = query.strip()
    if query and query not in queries:
        queries.append(query)

if "google docs" in lower or ("google" in lower and "docs" in lower):
    add("google docs mcp")
if any(term in lower for term in ("playwright", "browser", "login", "screenshot", "capture", "website")):
    add("playwright mcp")
if "chrome" in lower:
    add("chrome automation ai")
if any(term in lower for term in ("automation", "workflow", "agent", "mcp")):
    add("browser automation mcp")
if any(term in lower for term in ("repo", "repository", "fork", "clone", "template", "starter", "boilerplate")):
    add("open source project finder")
if "extension" in lower:
    add("chrome extension ai")

if len(queries) < 2 and keywords:
    add(" ".join(keywords[:2]))
if len(queries) < 3 and len(keywords) >= 3:
    add(" ".join(keywords[:3]))

idea = " ".join(part for part in [title.strip(), summary.strip(), opinion.strip()] if part).strip()
if not idea:
    idea = title.strip() or summary.strip() or opinion.strip() or url.strip()
idea = re.sub(r"\s+", " ", idea).strip()

payload = {
    "should_run": should_run,
    "reason": reason,
    "queries": queries[:4],
    "idea": idea[:400],
}
print(json.dumps(payload, ensure_ascii=False))
PY
)"

SHOULD_RUN="$(echo "$META_JSON" | jq -r '.should_run // false' 2>/dev/null || echo false)"
META_REASON="$(echo "$META_JSON" | jq -r '.reason // empty' 2>/dev/null || true)"
IDEA_TEXT="$(echo "$META_JSON" | jq -r '.idea // empty' 2>/dev/null || true)"

if [[ "$SHOULD_RUN" != "true" && "$FORCE" != "true" ]]; then
  jq -cn \
    --arg status "skipped" \
    --arg reason "$META_REASON" \
    --arg title "$TITLE" \
    --arg url "$URL" \
    --arg category "$CATEGORY" \
    --argjson queries "$(echo "$META_JSON" | jq -c '.queries // []')" \
    '{status:$status, reason:$reason, title:$title, url:$url, category:$category, queries:$queries}'
  exit 0
fi

QUERIES=()
while IFS= read -r query; do
  [[ -n "$query" ]] && QUERIES+=("$query")
done < <(echo "$META_JSON" | jq -r '.queries[]?')

if [[ ${#QUERIES[@]} -eq 0 ]]; then
  QUERIES+=("$IDEA_TEXT")
fi

if $DRY_RUN; then
  jq -cn \
    --arg status "dry-run" \
    --arg reason "$META_REASON" \
    --arg idea "$IDEA_TEXT" \
    --arg title "$TITLE" \
    --arg url "$URL" \
    --arg category "$CATEGORY" \
    --argjson queries "$(printf '%s\n' "${QUERIES[@]}" | jq -R . | jq -s .)" \
    '{status:$status, reason:$reason, idea:$idea, title:$title, url:$url, category:$category, queries:$queries}'
  exit 0
fi

if [[ ! -f "$SKILL_SCRIPT" ]]; then
  jq -cn --arg status "error" --arg reason "skill script missing: $SKILL_SCRIPT" '{status:$status, reason:$reason}'
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  jq -cn --arg status "error" --arg reason "gh CLI not installed" '{status:$status, reason:$reason}'
  exit 0
fi

if ! gh auth status >/dev/null 2>&1; then
  jq -cn --arg status "error" --arg reason "gh auth missing" '{status:$status, reason:$reason}'
  exit 0
fi

CMD=(python3 "$SKILL_SCRIPT" --idea "$IDEA_TEXT" --json --top "$TOP_N" --limit "$PER_QUERY_LIMIT")
for query in "${QUERIES[@]}"; do
  CMD+=(--query "$query")
done

SEARCH_ERR="$(mktemp)"
SEARCH_JSON="$("${CMD[@]}" 2>"$SEARCH_ERR" || true)"
SEARCH_ERROR="$(tr '\n' ' ' < "$SEARCH_ERR" | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//')"
rm -f "$SEARCH_ERR"

if [[ -z "$SEARCH_JSON" ]]; then
  jq -cn \
    --arg status "error" \
    --arg reason "${SEARCH_ERROR:-repo search returned empty result}" \
    --arg idea "$IDEA_TEXT" \
    --argjson queries "$(printf '%s\n' "${QUERIES[@]}" | jq -R . | jq -s .)" \
    '{status:$status, reason:$reason, idea:$idea, queries:$queries}'
  exit 0
fi

FINAL_JSON="$(python3 - <<'PY' "$SEARCH_JSON" "$META_JSON" "$TITLE" "$URL" "$HASH" "$CATEGORY"
import json
import sys
from datetime import datetime, timezone

search_json, meta_json, title, url, item_hash, category = sys.argv[1:7]
search = json.loads(search_json)
meta = json.loads(meta_json)
results = list(search.get("results") or [])
idea = meta.get("idea") or ""
lower = idea.lower()

def is_browser_repo(item):
    blob = f"{item.get('fullName','')} {item.get('description','')}".lower()
    return any(term in blob for term in ("playwright", "browser", "chrome", "automation"))

def is_docs_repo(item):
    blob = f"{item.get('fullName','')} {item.get('description','')}".lower()
    return ("google" in blob and "docs" in blob) or "drive" in blob or "sheets" in blob

browser_results = [item for item in results if is_browser_repo(item)]
docs_results = [item for item in results if is_docs_repo(item)]
needs_browser = any(term in lower for term in ("login", "browser", "screenshot", "capture", "site", "website", "playwright", "chrome"))
needs_docs = any(term in lower for term in ("google docs", "google", "docs", "document", "report"))

recommended_mode = "single"
recommended_base = results[0] if results else None
recommended_companion = None
reason = "single best match"

if needs_browser and needs_docs and browser_results and docs_results:
    recommended_mode = "compose"
    recommended_base = browser_results[0]
    recommended_companion = docs_results[0]
    reason = "compose browser automation with google docs writer"
elif recommended_base is not None and is_docs_repo(recommended_base) and browser_results and needs_browser:
    recommended_mode = "compose"
    recommended_base = browser_results[0]
    recommended_companion = docs_results[0] if docs_results else None
    reason = "browser repo is a better execution base than docs-only repo"

payload = {
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "status": "matched" if results else "skipped",
    "reason": reason if results else "no similar repos found",
    "title": title,
    "url": url,
    "hash": item_hash,
    "category": category,
    "idea": idea,
    "queries": meta.get("queries") or [],
    "recommended_mode": recommended_mode if results else "none",
    "recommended_base": (recommended_base or {}).get("fullName", ""),
    "recommended_base_url": (recommended_base or {}).get("url", ""),
    "recommended_companion": (recommended_companion or {}).get("fullName", ""),
    "recommended_companion_url": (recommended_companion or {}).get("url", ""),
    "results": results[:5],
}
print(json.dumps(payload, ensure_ascii=False))
PY
)"

if [[ "$(echo "$FINAL_JSON" | jq -r '.status // empty' 2>/dev/null)" == "matched" ]]; then
  mkdir -p "$(dirname "$OUT_FILE")"
  printf '%s\n' "$FINAL_JSON" >> "$OUT_FILE"
fi

printf '%s\n' "$FINAL_JSON"
