#!/usr/bin/env bash
# Source this file to set up shell environment for gateway access.
# Usage: source scripts/gateway-env.sh
#
# Sets ANTHROPIC_BASE_URL, OPENAI_BASE_URL, OPENROUTER_BASE_URL, and API keys
# so that CLI tools (Claude Code, OpenAI SDK, OpenRouter, etc.) route through LiteLLM.

_GW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load infrastructure secrets from .env
if [[ -f "${_GW_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  set -a
  source "${_GW_DIR}/.env"
  set +a
fi

if [[ -z "${LITELLM_MASTER_KEY:-}" ]]; then
  echo "Warning: LITELLM_MASTER_KEY is not set. Check .env." >&2
fi

# Fall back to master key if no virtual key is set
export LITELLM_KEY="${LITELLM_KEY:-${LITELLM_MASTER_KEY:-}}"
export ANTHROPIC_BASE_URL="http://localhost:4000"
export ANTHROPIC_API_KEY="${LITELLM_KEY}"
export OPENAI_BASE_URL="http://localhost:4000/v1"
export OPENAI_API_KEY="${LITELLM_KEY}"
export OPENROUTER_BASE_URL="http://localhost:4000/v1"
export OPENROUTER_API_KEY="${LITELLM_KEY}"

unset _GW_DIR
