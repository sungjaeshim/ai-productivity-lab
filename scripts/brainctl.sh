#!/usr/bin/env bash
# Canonical entrypoint for brain-* workflows.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<EOF
Usage:
  $0 autopull <telegram|discord> [args...]
  $0 ingest <link|note> [args...]
  $0 route <retry|todo|tag> [args...]
  $0 todo <sync|stale|done-summary|reaction-sync|nightly-sync> [args...]
  $0 ops <queue-autoclean|router-health> [args...]
  $0 repair inbox-resend-clean [args...]
  $0 report <weekly|daily-done|done-broadcast> [args...]
  $0 analyze content [args...]
  $0 manage thread [args...]
EOF
}

dispatch() {
  local target="$1"
  shift
  exec "${SCRIPT_DIR}/${target}" "$@"
}

group="${1:-}"
action="${2:-}"
if [[ -z "$group" || -z "$action" ]]; then
  usage >&2
  exit 1
fi
shift 2

case "$group" in
  autopull)
    case "$action" in
      telegram) dispatch brain-telegram-autopull.sh "$@" ;;
      discord) dispatch brain-discord-autopull.sh "$@" ;;
      *) usage >&2; exit 1 ;;
    esac
    ;;
  ingest)
    case "$action" in
      link) dispatch brain-link-ingest.sh "$@" ;;
      note) dispatch brain-note-ingest.sh "$@" ;;
      *) usage >&2; exit 1 ;;
    esac
    ;;
  route)
    case "$action" in
      retry) dispatch brain-route-retry.sh "$@" ;;
      todo) dispatch brain-todo-route.sh "$@" ;;
      tag) dispatch brain-tag-route.sh "$@" ;;
      *) usage >&2; exit 1 ;;
    esac
    ;;
  todo)
    case "$action" in
      sync) dispatch brain-todoist-sync.sh "$@" ;;
      stale) dispatch brain-todoist-stale-check.sh "$@" ;;
      done-summary) dispatch brain-todoist-done-summary.sh "$@" ;;
      reaction-sync) dispatch brain-todo-reaction-sync.sh "$@" ;;
      nightly-sync) dispatch brain-nightly-todo-sync.sh "$@" ;;
      *) usage >&2; exit 1 ;;
    esac
    ;;
  ops)
    case "$action" in
      queue-autoclean) dispatch brain-queue-autoclean.sh "$@" ;;
      router-health) dispatch brain-router-health-monitor.sh "$@" ;;
      *) usage >&2; exit 1 ;;
    esac
    ;;
  repair)
    case "$action" in
      inbox-resend-clean) dispatch brain-inbox-resend-clean.sh "$@" ;;
      *) usage >&2; exit 1 ;;
    esac
    ;;
  report)
    case "$action" in
      weekly) dispatch brain-weekly-knowledge-report.sh "$@" ;;
      daily-done) dispatch brain-daily-done-summary.sh "$@" ;;
      done-broadcast) dispatch brain-done-broadcast.sh "$@" ;;
      *) usage >&2; exit 1 ;;
    esac
    ;;
  analyze)
    case "$action" in
      content) dispatch brain-content-analyze.sh "$@" ;;
      *) usage >&2; exit 1 ;;
    esac
    ;;
  manage)
    case "$action" in
      thread) dispatch brain-thread-manage.sh "$@" ;;
      *) usage >&2; exit 1 ;;
    esac
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
