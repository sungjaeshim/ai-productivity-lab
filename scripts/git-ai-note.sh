#!/usr/bin/env bash
set -euo pipefail

REF="${AI_NOTES_REF:-refs/notes/ai-session}"

usage() {
  cat <<'EOF'
git-ai-note.sh — attach AI session context to git commits via git notes

Usage:
  git-ai-note.sh add [options]
  git-ai-note.sh show [--commit <sha>]
  git-ai-note.sh sync-push [remote]
  git-ai-note.sh sync-fetch [remote]

Commands:
  add         Add/append AI context note to a commit (default: HEAD)
  show        Show AI note for a commit (default: HEAD)
  sync-push   Push notes ref to remote (default: origin)
  sync-fetch  Fetch notes ref from remote (default: origin)

Options for add:
  --commit <sha>       Target commit (default: HEAD)
  --session <id>       Session id/key
  --model <name>       Model name
  --agent <name>       Agent name
  --source <url/text>  Source link or context label
  --summary <text>     Summary text
  --file <path>        Read summary from file
  --stdin              Read summary from stdin

Environment:
  AI_NOTES_REF         Git notes ref (default: refs/notes/ai-session)

Examples:
  scripts/git-ai-note.sh add --session agent:main:... --model codex --summary "fix: retry dedupe"
  scripts/git-ai-note.sh show
  scripts/git-ai-note.sh sync-push
EOF
}

cmd="${1:-}"
[[ -n "$cmd" ]] || { usage; exit 1; }
shift || true

case "$cmd" in
  add)
    commit="HEAD"
    session=""
    model=""
    agent=""
    source=""
    summary=""
    from_stdin="0"
    file_path=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --commit) commit="$2"; shift 2 ;;
        --session) session="$2"; shift 2 ;;
        --model) model="$2"; shift 2 ;;
        --agent) agent="$2"; shift 2 ;;
        --source) source="$2"; shift 2 ;;
        --summary) summary="$2"; shift 2 ;;
        --file) file_path="$2"; shift 2 ;;
        --stdin) from_stdin="1"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
      esac
    done

    if [[ -n "$file_path" ]]; then
      [[ -f "$file_path" ]] || { echo "File not found: $file_path" >&2; exit 1; }
      summary="$(cat "$file_path")"
    fi

    if [[ "$from_stdin" == "1" ]]; then
      summary="$(cat)"
    fi

    if [[ -z "$summary" ]]; then
      echo "add requires summary text (--summary, --file, or --stdin)" >&2
      exit 1
    fi

    commit="$(git rev-parse --verify "$commit")"
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    block="AI-SESSION-NOTE v1
- time: ${ts}
- session: ${session:-n/a}
- model: ${model:-n/a}
- agent: ${agent:-n/a}
- source: ${source:-n/a}

Summary:
${summary}
"

    existing=""
    if existing="$(git notes --ref "$REF" show "$commit" 2>/dev/null)"; then
      note="$existing

---
$block"
    else
      note="$block"
    fi

    git notes --ref "$REF" add -f -m "$note" "$commit"

    echo "✅ AI note saved"
    echo "   commit: $commit"
    echo "   ref:    $REF"
    echo "Tip: sync notes with remote"
    echo "  git push origin $REF"
    echo "  git fetch origin $REF:$REF"
    ;;

  show)
    commit="HEAD"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --commit) commit="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
      esac
    done
    commit="$(git rev-parse --verify "$commit")"
    git notes --ref "$REF" show "$commit"
    ;;

  sync-push)
    remote="${1:-origin}"
    git push "$remote" "$REF"
    ;;

  sync-fetch)
    remote="${1:-origin}"
    git fetch "$remote" "$REF:$REF"
    ;;

  -h|--help)
    usage
    ;;

  *)
    echo "Unknown command: $cmd" >&2
    usage
    exit 1
    ;;
esac
