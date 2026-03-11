#!/usr/bin/env bash
# Shared env loader for OpenClaw workspace scripts.
# - Loads /root/.openclaw/.env (or OPENCLAW_ENV_FILE override)
# - Loads workspace .env when present
# - Exports compatibility aliases for legacy brain pipeline keys

__script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__workspace_root="$(cd "${__script_dir}/.." && pwd)"
__global_env="${OPENCLAW_ENV_FILE:-/root/.openclaw/.env}"
__workspace_env="${__workspace_root}/.env"

_openclaw_source_env() {
  local env_file="$1"
  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
  fi
}

_openclaw_source_env "$__global_env"
if [[ "$__workspace_env" != "$__global_env" ]]; then
  _openclaw_source_env "$__workspace_env"
fi

# Compatibility aliases
if [[ -z "${BRAIN_INBOX_CHANNEL_ID:-}" && -n "${DISCORD_INBOX:-}" ]]; then
  export BRAIN_INBOX_CHANNEL_ID="$DISCORD_INBOX"
fi
if [[ -z "${BRAIN_OPS_CHANNEL_ID:-}" && -n "${DISCORD_TODAY:-}" ]]; then
  export BRAIN_OPS_CHANNEL_ID="$DISCORD_TODAY"
fi
if [[ -z "${BRAIN_REVIEW_CHANNEL_ID:-}" && -n "${DISCORD_DECISION_LOG:-}" ]]; then
  export BRAIN_REVIEW_CHANNEL_ID="$DISCORD_DECISION_LOG"
fi
if [[ -z "${TELEGRAM_TARGET:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
  export TELEGRAM_TARGET="$TELEGRAM_CHAT_ID"
fi

# Normalize mixed-case project channel keys if older names are present.
if [[ -z "${DISCORD_PROJ_TRADING_NQ:-}" && -n "${DISCORD_proj_TRADING_NQ:-}" ]]; then
  export DISCORD_PROJ_TRADING_NQ="$DISCORD_proj_TRADING_NQ"
fi
if [[ -z "${DISCORD_PROJ_GROWTH_CENTER:-}" && -n "${DISCORD_proj_growth_center:-}" ]]; then
  export DISCORD_PROJ_GROWTH_CENTER="$DISCORD_proj_growth_center"
fi
if [[ -z "${DISCORD_PROJ_SECOND_BRAIN:-}" && -n "${DISCORD_proj_second_brain:-}" ]]; then
  export DISCORD_PROJ_SECOND_BRAIN="$DISCORD_proj_second_brain"
fi
if [[ -z "${DISCORD_PROJ_CEO_AI:-}" && -n "${DISCORD_proj_ceo_ai:-}" ]]; then
  export DISCORD_PROJ_CEO_AI="$DISCORD_proj_ceo_ai"
fi

unset -f _openclaw_source_env
unset __script_dir __workspace_root __global_env __workspace_env
