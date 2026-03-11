#!/usr/bin/env bash
set -euo pipefail

set +u
source "$(dirname "$0")/env-loader.sh" 2>/dev/null || true
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECOND_BRAIN_DIR="${SECOND_BRAIN_DIR:-${WORKSPACE_ROOT}/memory/second-brain}"
IDEAS_FILE="${BRAIN_IDEAS_FILE:-${SECOND_BRAIN_DIR}/ideas.md}"
REPO_MATCH_SCRIPT="${BRAIN_REPO_MATCH_SCRIPT:-${SCRIPT_DIR}/brain-idea-repo-match.sh}"
PARSER_MODULE="${BRAIN_IDEAS_PARSER_MODULE:-/root/Projects/growth-center/utils/ideas-parser.js}"
OUT_FILE="${BRAIN_REPO_MATCHES_PATH:-${SECOND_BRAIN_DIR}/repo-matches.jsonl}"

LIMIT=0
DRY_RUN=false
FORCE=false
INCLUDE_COMPLETED=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) LIMIT="${2:-0}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --force) FORCE=true; shift ;;
    --include-completed) INCLUDE_COMPLETED=true; shift ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$IDEAS_FILE" ]]; then
  echo "{\"ok\":false,\"error\":\"ideas file missing: $IDEAS_FILE\"}"
  exit 1
fi

if [[ ! -x "$REPO_MATCH_SCRIPT" ]]; then
  echo "{\"ok\":false,\"error\":\"repo match script missing or not executable: $REPO_MATCH_SCRIPT\"}"
  exit 1
fi

if [[ ! -f "$PARSER_MODULE" ]]; then
  echo "{\"ok\":false,\"error\":\"ideas parser missing: $PARSER_MODULE\"}"
  exit 1
fi

PARSED_ITEMS_JSON="$(node - <<'NODE' "$IDEAS_FILE" "$PARSER_MODULE" "$INCLUDE_COMPLETED"
const fs = require('fs');
const crypto = require('crypto');

const ideasFile = process.argv[2];
const parserModule = process.argv[3];
const includeCompleted = process.argv[4] === 'true';

const { parseIdeasMarkdown } = require(parserModule);
const content = fs.readFileSync(ideasFile, 'utf8');
const items = parseIdeasMarkdown(content)
  .filter((item) => item && item.title)
  .filter((item) => includeCompleted || !['전달 완료', '완료'].includes(String(item.status || '').trim()))
  .map((item) => {
    const summary = String(item.summary || item.description || item.title || '').trim();
    const description = String(item.description || summary).trim();
    const key = `${item.date || ''}|${item.title || ''}|${summary}`;
    const hash = `idea-backfill-${crypto.createHash('sha1').update(key).digest('hex').slice(0, 16)}`;
    return {
      hash,
      title: String(item.title || '').trim(),
      summary: summary.slice(0, 280),
      description: description.slice(0, 600),
      date: item.date || '',
      status: item.status || '',
      url: Array.isArray(item.urls) && item.urls.length > 0 ? item.urls[0] : '',
      sourceKind: item.sourceKind || ''
    };
  });

console.log(JSON.stringify(items));
NODE
)"

if [[ -z "$PARSED_ITEMS_JSON" || "$PARSED_ITEMS_JSON" == "[]" ]]; then
  echo "{\"ok\":true,\"processed\":0,\"matched\":0,\"skipped\":0,\"reason\":\"no parsed ideas\"}"
  exit 0
fi

TOTAL_ITEMS="$(echo "$PARSED_ITEMS_JSON" | jq 'length')"
PROCESSED=0
MATCHED=0
SKIPPED=0
ERRORS=0

while IFS= read -r item; do
  [[ -z "$item" ]] && continue
  if [[ "$LIMIT" -gt 0 && "$PROCESSED" -ge "$LIMIT" ]]; then
    break
  fi

  hash="$(echo "$item" | jq -r '.hash')"
  title="$(echo "$item" | jq -r '.title')"
  summary="$(echo "$item" | jq -r '.summary')"
  description="$(echo "$item" | jq -r '.description')"
  url="$(echo "$item" | jq -r '.url')"

  if [[ -f "$OUT_FILE" ]] && grep -q "\"hash\":\"$hash\"" "$OUT_FILE" && [[ "$FORCE" != "true" ]]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  CMD=(
    "$REPO_MATCH_SCRIPT"
    --hash "$hash"
    --title "$title"
    --summary "$summary"
    --my-opinion "$description"
    --category "idea"
  )
  if [[ -n "$url" ]]; then
    CMD+=(--url "$url")
  fi
  if [[ "$FORCE" == "true" ]]; then
    CMD+=(--force)
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    CMD+=(--dry-run)
  fi

  RESULT="$("${CMD[@]}" 2>/dev/null || true)"
  STATUS="$(echo "$RESULT" | jq -r '.status // "error"' 2>/dev/null || echo error)"
  if [[ "$STATUS" == "matched" ]]; then
    MATCHED=$((MATCHED + 1))
  elif [[ "$STATUS" == "error" ]]; then
    ERRORS=$((ERRORS + 1))
  else
    SKIPPED=$((SKIPPED + 1))
  fi

  PROCESSED=$((PROCESSED + 1))
done < <(echo "$PARSED_ITEMS_JSON" | jq -c '.[]')

jq -cn \
  --arg ok "true" \
  --arg ideas_file "$IDEAS_FILE" \
  --arg out_file "$OUT_FILE" \
  --arg total_items "$TOTAL_ITEMS" \
  --arg processed "$PROCESSED" \
  --arg matched "$MATCHED" \
  --arg skipped "$SKIPPED" \
  --arg errors "$ERRORS" \
  '{
    ok: ($ok == "true"),
    ideas_file: $ideas_file,
    out_file: $out_file,
    total_items: ($total_items | tonumber),
    processed: ($processed | tonumber),
    matched: ($matched | tonumber),
    skipped: ($skipped | tonumber),
    errors: ($errors | tonumber)
  }'
