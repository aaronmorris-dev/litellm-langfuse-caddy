#!/usr/bin/env bash
# Gateway Doctor — Automated diagnostic cascade
# Outputs structured results for Claude (or a human) to interpret.
#
# Usage: bash diagnose.sh
#
# Environment:
#   AI_GATEWAY_DIR   Project root (default: auto-detect via git, or current directory)
#   LITELLM_URL      Proxy URL (default: http://localhost:4000)
#   LANGFUSE_URL     Dashboard URL (default: http://localhost:5002)

set -euo pipefail

# Auto-detect project root: git root → AI_GATEWAY_DIR → current directory
if [[ -n "${AI_GATEWAY_DIR:-}" ]]; then
  GW_DIR="$AI_GATEWAY_DIR"
elif git rev-parse --show-toplevel &>/dev/null 2>&1; then
  GW_DIR="$(git rev-parse --show-toplevel)"
else
  GW_DIR="$(pwd)"
fi

LITELLM_URL="${LITELLM_URL:-http://localhost:4000}"
LANGFUSE_URL="${LANGFUSE_URL:-http://localhost:5002}"
GW_ENV="${GW_DIR}/scripts/gateway-env.sh"

# Counters
PASS=0; FAIL=0; WARN=0

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

pass() { PASS=$((PASS + 1)); echo -e "  ${GREEN}OK${NC}  $1"; }
fail() { FAIL=$((FAIL + 1)); echo -e "  ${RED}FAIL${NC}  $1"; }
warn() { WARN=$((WARN + 1)); echo -e "  ${YELLOW}WARN${NC}  $1"; }
section() { echo -e "\n${CYAN}--- $1 ---${NC}"; }

echo ""
echo "========================================="
echo "  Gateway Doctor — Diagnostic Report"
echo "========================================="
echo "  Project: ${GW_DIR}"
echo "  Time:    $(date '+%Y-%m-%d %H:%M:%S')"

# -- 1. Docker Runtime -------------------------------------------------------
section "Docker Runtime"

if ! command -v docker &>/dev/null; then
  fail "Docker CLI not installed"
  echo "       Install OrbStack (recommended) or Docker Desktop"
  echo ""; echo "=== Cannot continue without Docker ==="; exit 2
fi

if ! docker info &>/dev/null 2>&1; then
  fail "Docker daemon is not running"
  echo "       Start OrbStack or Docker Desktop"
  echo ""; echo "=== Cannot continue without Docker ==="; exit 2
fi
pass "Docker daemon running"

DOCKER_CONTEXT=$(docker context show 2>/dev/null || echo "unknown")
if [[ "$DOCKER_CONTEXT" == *"orbstack"* ]]; then
  pass "OrbStack context active"
else
  pass "Docker context: ${DOCKER_CONTEXT}"
fi

# -- 2. Project Files ---------------------------------------------------------
section "Project Files"

for f in docker-compose.yaml .env Caddyfile; do
  if [[ -f "${GW_DIR}/${f}" ]]; then
    pass "${f} exists"
  else
    fail "${f} missing at ${GW_DIR}/${f}"
  fi
done

if [[ -f "${GW_DIR}/litellm/config.yaml" ]]; then
  pass "litellm/config.yaml exists"
else
  fail "litellm/config.yaml missing (copy from litellm/config.example.yaml)"
fi

# -- 3. Containers ------------------------------------------------------------
section "Containers"

EXPECTED_SERVICES=(postgres redis clickhouse minio litellm langfuse langfuse-worker caddy)

for svc in "${EXPECTED_SERVICES[@]}"; do
  container="gateway-${svc}"
  status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "missing")
  health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container" 2>/dev/null || echo "unknown")

  if [[ "$status" == "running" && "$health" == "healthy" ]]; then
    pass "${container}: running (healthy)"
  elif [[ "$status" == "running" && "$health" == "starting" ]]; then
    warn "${container}: running (health check starting — may need a moment)"
  elif [[ "$status" == "running" ]]; then
    warn "${container}: running (health: ${health})"
  elif [[ "$status" == "missing" ]]; then
    fail "${container}: not found — run 'docker compose up -d' from ${GW_DIR}"
  else
    fail "${container}: ${status} (health: ${health})"
  fi
done

# -- 4. API Endpoints ---------------------------------------------------------
section "API Endpoints"

if curl -sf "${LITELLM_URL}/health/liveliness" -o /dev/null --max-time 5 2>/dev/null; then
  pass "LiteLLM health: reachable (${LITELLM_URL})"
else
  fail "LiteLLM health: unreachable (${LITELLM_URL}/health/liveliness)"
fi

MODEL_OUTPUT=$(curl -sf "${LITELLM_URL}/v1/models" --max-time 5 2>/dev/null || echo "")
if [[ -n "$MODEL_OUTPUT" ]]; then
  MODEL_COUNT=$(echo "$MODEL_OUTPUT" | jq -r '.data | length' 2>/dev/null || echo "0")
  if [[ "$MODEL_COUNT" -gt 0 ]]; then
    pass "LiteLLM models: ${MODEL_COUNT} available"
    echo "$MODEL_OUTPUT" | jq -r '.data[].id' 2>/dev/null | sort | while read -r model; do
      echo "         - ${model}"
    done
  else
    warn "LiteLLM models: API reachable but 0 models listed — check litellm/config.yaml"
  fi
else
  fail "LiteLLM /v1/models: no response"
fi

if curl -sf "${LANGFUSE_URL}" -o /dev/null --max-time 5 2>/dev/null; then
  pass "Langfuse UI: reachable (${LANGFUSE_URL})"
else
  fail "Langfuse UI: unreachable (${LANGFUSE_URL})"
fi

# -- 5. Provider Credentials ---------------------------------------------------
section "Provider Credentials"

if command -v aws &>/dev/null; then
  if aws sts get-caller-identity &>/dev/null 2>&1; then
    ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "?")
    pass "AWS SSO: authenticated (account ${ACCOUNT})"
  else
    fail "AWS SSO: expired or not configured — run 'aws sso login'"
  fi
else
  warn "AWS CLI: not installed (Bedrock models unavailable)"
fi

ADC_PATH="${GOOGLE_APPLICATION_CREDENTIALS:-$HOME/.config/gcloud/application_default_credentials.json}"
if [[ -f "$ADC_PATH" ]]; then
  if command -v gcloud &>/dev/null; then
    if gcloud auth application-default print-access-token &>/dev/null 2>&1; then
      pass "GCloud ADC: valid"
    else
      fail "GCloud ADC: expired — run 'gcloud auth application-default login'"
    fi
  else
    warn "gcloud CLI not installed — ADC file exists but can't verify"
  fi
else
  warn "GCloud ADC: not found at ${ADC_PATH}"
fi

CHATGPT_DIR="${CHATGPT_TOKEN_DIR:-$HOME/.config/litellm/chatgpt}"
CHATGPT_TOKEN="${CHATGPT_DIR}/auth.json"
if [[ -f "$CHATGPT_TOKEN" ]]; then
  EXPIRY=$(jq -r '.expires_at // .expires // 0' "$CHATGPT_TOKEN" 2>/dev/null || echo "0")
  NOW=$(date +%s)
  if [[ "$EXPIRY" =~ ^[0-9]+$ ]] && [[ "$EXPIRY" -gt "$NOW" ]]; then
    REMAINING=$(( (EXPIRY - NOW) / 3600 ))
    pass "ChatGPT OAuth: valid (${REMAINING}h remaining)"
  else
    fail "ChatGPT OAuth: expired — re-authenticate via device flow"
  fi
else
  warn "ChatGPT OAuth: no token at ${CHATGPT_TOKEN}"
fi

# -- 6. Shell Environment -----------------------------------------------------
section "Shell Environment"

if [[ -f "$GW_ENV" ]]; then
  pass "gateway-env.sh exists (${GW_ENV})"
  # shellcheck disable=SC1090
  source "$GW_ENV" 2>/dev/null || warn "gateway-env.sh failed to source"
else
  fail "gateway-env.sh missing — tools won't route through gateway"
fi

check_env() {
  local var="$1" expected="${2:-}"
  local actual="${!var:-}"
  if [[ -z "$actual" ]]; then
    fail "${var}: not set"
  elif [[ -n "$expected" && "$actual" != "$expected" ]]; then
    warn "${var}: '${actual}' (expected '${expected}')"
  else
    pass "${var}: set"
  fi
}

check_env LITELLM_KEY
check_env ANTHROPIC_BASE_URL "http://localhost:4000"
check_env ANTHROPIC_API_KEY
check_env OPENAI_BASE_URL "http://localhost:4000/v1"
check_env OPENAI_API_KEY
check_env OPENROUTER_BASE_URL "http://localhost:4000/v1"
check_env OPENROUTER_API_KEY

SHELL_PROFILE="$HOME/.zshrc"
if [[ -f "$SHELL_PROFILE" ]] && grep -q "gateway-env.sh" "$SHELL_PROFILE" 2>/dev/null; then
  pass "gateway-env.sh sourced in .zshrc"
else
  warn "gateway-env.sh not found in .zshrc — env vars may not persist across sessions"
fi

# -- 7. Recent Errors ----------------------------------------------------------
section "Recent LiteLLM Errors (last 50 log lines)"

if docker ps -q --filter "name=gateway-litellm" &>/dev/null 2>&1; then
  ERROR_LOG=$(docker logs gateway-litellm --tail 50 2>&1 | grep -i -E '"levelname":\s*"ERROR"|"error"|exception|traceback|failed' | tail -10 || true)
  if [[ -n "$ERROR_LOG" ]]; then
    warn "Found errors in gateway-litellm logs:"
    echo "$ERROR_LOG" | while IFS= read -r line; do
      echo "       ${line}"
    done
  else
    pass "No recent errors in gateway-litellm logs"
  fi
else
  warn "gateway-litellm container not running — cannot check logs"
fi

# -- 8. Resource Usage ---------------------------------------------------------
section "Resource Usage"

RUNNING_CONTAINERS=$(docker ps -q --filter "name=gateway-" 2>/dev/null | head -1)
if [[ -n "$RUNNING_CONTAINERS" ]]; then
  docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" \
    $(docker ps -q --filter "name=gateway-") 2>/dev/null || warn "Could not fetch container stats"
else
  warn "No gateway containers running"
fi

# -- Summary -------------------------------------------------------------------
echo ""
echo "========================================="
echo "  Summary: ${PASS} passed, ${FAIL} failed, ${WARN} warnings"
echo "========================================="

if [[ "$FAIL" -eq 0 && "$WARN" -eq 0 ]]; then
  echo -e "  ${GREEN}Gateway is fully healthy.${NC}"
elif [[ "$FAIL" -eq 0 ]]; then
  echo -e "  ${YELLOW}Gateway is operational with warnings.${NC}"
else
  echo -e "  ${RED}Gateway has issues that need attention.${NC}"
  echo "  Fix failures from top to bottom — upstream fixes often resolve downstream issues."
fi

echo ""
exit "$FAIL"
