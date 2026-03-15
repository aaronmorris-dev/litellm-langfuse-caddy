---
name: gateway
description: >-
  Diagnose, repair, and install the local AI Gateway stack (LiteLLM + Langfuse + Docker Compose).
  Use this skill whenever the user mentions: gateway problems, LiteLLM errors, proxy not working,
  AI tools timing out or failing through the gateway, Docker containers unhealthy or not starting,
  credential expiry (AWS SSO, GCloud ADC, ChatGPT OAuth), Langfuse not showing traces, environment
  variable misconfiguration, setting up or installing the gateway from scratch, adding models to
  LiteLLM, OpenRouter/OpenAI/Anthropic routing problems, or any issue with the local LLM proxy
  at localhost:4000. Also trigger when someone wants to understand how the gateway stack works
  or what services are running.
argument-hint: install | diagnose | fix <issue>
---

# Gateway

Diagnose, repair, and install the AI Gateway — a local LiteLLM + Langfuse stack that routes
LLM traffic from any tool (Claude Code, Codex, Gemini CLI, etc.) through a single proxy with
full observability.

## Project Layout

```
litellm-langfuse-caddy/
  docker-compose.yaml          # 8-service Docker Compose stack
  Caddyfile                    # Reverse proxy (SSE-optimized, JSON logging)
  .env.example                 # Template — copy to .env and fill in
  litellm/
    config.example.yaml        # Model config template — copy to config.yaml
    langfuse_enrich.py         # Trace enrichment hook (auto-loaded by LiteLLM)
  scripts/
    start.sh                   # Startup with validation
    stop.sh                    # Graceful shutdown
    gateway-env.sh             # Source to route CLI tools through the proxy
    refresh-credentials.sh     # Check/refresh provider credentials
    prune-postgres.sh          # Data retention maintenance
    eval-session.py            # LLM-as-judge session evaluation
  examples/
    transparent-routing.md     # Guide: redirect any tool through the gateway
    .claude/settings.json      # Claude Code proxy config example
    .codex/config.yaml         # Codex CLI proxy config example
```

## Detect Mode

Figure out what the user needs based on their message:

| Signal                                                             | Mode                 |
| ------------------------------------------------------------------ | -------------------- |
| "install", "set up", "get started", no .env or litellm/config.yaml | **Install**          |
| "broken", "failing", "not working", "timeout", "error", "down"     | **Diagnose**         |
| "status", "health", "check"                                        | **Diagnose** (quick) |
| "add model", "new provider", "configure"                           | **Configure**        |
| Specific error message or log output                               | **Fix** (targeted)   |

When in doubt, run the diagnostic script first — it takes seconds and gives you the full picture.

## Install Mode

For fresh installations or rebuilding the stack from scratch.

### Prerequisites

```bash
# Required
docker --version          # Docker or OrbStack (recommended for macOS)
jq --version              # JSON processing
curl --version            # HTTP client

# For providers (check which the user needs)
aws --version             # AWS Bedrock
gcloud --version          # Google Vertex AI
```

### Step-by-Step Installation

**1. Clone and enter the project**

```bash
git clone https://github.com/aaronmorris-dev/litellm-langfuse-caddy.git
cd litellm-langfuse-caddy
```

**2. Create config files from templates**

```bash
cp .env.example .env
cp litellm/config.example.yaml litellm/config.yaml
```

**3. Generate .env secrets**

Replace placeholders with secure random values:

```bash
# Passwords (16 hex chars)
openssl rand -hex 16    # POSTGRES_PASSWORD, CLICKHOUSE_PASSWORD, MINIO_ROOT_PASSWORD

# Secrets (32 hex chars)
openssl rand -hex 32    # SALT, ENCRYPTION_KEY, NEXTAUTH_SECRET

# LiteLLM master key (prefix with sk-)
echo "sk-$(openssl rand -hex 16)"  # LITELLM_MASTER_KEY
```

Update DATABASE_URL to match the new POSTGRES_PASSWORD. Leave LANGFUSE_PUBLIC_KEY and
LANGFUSE_SECRET_KEY as placeholders — they're created after first launch.

**4. Configure models**

Edit `litellm/config.yaml`. Uncomment the model blocks for the providers you want:

- **AWS Bedrock** (Claude): Uncomment `~/.aws` volume mount in docker-compose.yaml, set `AWS_PROFILE` in .env
- **Vertex AI** (Gemini): Uncomment `~/.config/gcloud` volume mount, set `GOOGLE_APPLICATION_CREDENTIALS` in .env
- **Gemini API**: Set `GEMINI_API_KEY` in .env (simplest setup)
- **OpenAI / Anthropic**: Set the relevant API key in .env

**5. Start the stack**

```bash
./scripts/start.sh
```

Wait for all containers to become healthy (30-60 seconds):

```bash
docker compose ps    # All should show "healthy"
```

**6. Create Langfuse API keys**

Open http://localhost:5002, sign up, create an org and project, then go to
Settings > API Keys and create a key pair. Update .env:

```
LANGFUSE_PUBLIC_KEY=pk-lf-...
LANGFUSE_SECRET_KEY=sk-lf-...
```

Restart to pick up the keys: `docker compose restart gateway-litellm`

**7. Create virtual keys**

Virtual keys enable per-tool attribution in Langfuse. Create them via the API:

```bash
MASTER_KEY="your-litellm-master-key"

for tool in claude codex gemini; do
  curl -s http://localhost:4000/key/generate \
    -H "Authorization: Bearer ${MASTER_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"key_alias\": \"${tool}\", \"user_id\": \"$(whoami)\", \"metadata\": {\"tags\": [\"${tool}\"]}}" \
    | jq '{tool: .key_alias, key: .key}'
done
```

**8. Shell integration**

Add to `~/.zshrc` or `~/.bashrc`:

```bash
# AI Gateway — route tools through LiteLLM
[[ -f /path/to/litellm-langfuse-caddy/scripts/gateway-env.sh ]] && \
  source /path/to/litellm-langfuse-caddy/scripts/gateway-env.sh
```

Replace `/path/to/litellm-langfuse-caddy` with your actual clone path.

**9. Verify**

Run the diagnostic script to confirm everything works (see Diagnose Mode below).

## Diagnose Mode

The diagnostic script cascades through every layer — Docker, containers, endpoints,
credentials, env vars, and logs — and outputs a structured report.

### Run the diagnostic

```bash
bash <skill-path>/scripts/diagnose.sh
```

The script auto-detects the project root via git. Override with `AI_GATEWAY_DIR` if needed.

### Interpret the results

Work through failures **in dependency order** — fix the highest-level failure first:

```
Docker runtime        If Docker is down, nothing else matters.
  |
  v
Containers            If Postgres is down, LiteLLM and Langfuse won't start.
  |                   If Redis is down, caching fails but requests may still work.
  v
API endpoints         If LiteLLM health fails, check container logs.
  |                   If models list is empty, check litellm/config.yaml.
  v
Credentials           If AWS SSO expired, Bedrock models fail.
  |                   If GCloud ADC expired, Vertex models fail.
  v
Environment vars      If BASE_URL vars aren't set, tools bypass the gateway.
  |
  v
Recent errors         Look for patterns — auth failures, timeouts, OOM kills.
```

After each fix, rerun `diagnose.sh` to confirm and check for remaining issues.

## Common Failure Patterns

Read `references/topology.md` for the full service map and known issues.

### Docker / Containers

| Symptom                | Cause                          | Fix                                         |
| ---------------------- | ------------------------------ | ------------------------------------------- |
| All containers missing | Docker/OrbStack not running    | Start OrbStack app or `colima start`        |
| Container "unhealthy"  | Service failed health check    | `docker logs gateway-<name>` for details    |
| Postgres won't start   | Port conflict or corrupt data  | Check `docker logs gateway-postgres`        |
| LiteLLM restarts       | Bad config.yaml or missing env | `docker logs gateway-litellm --tail 50`     |
| ClickHouse OOM         | Memory limit too low           | Increase `mem_limit` in docker-compose.yaml |

### Credentials

| Symptom                         | Cause                 | Fix                                     |
| ------------------------------- | --------------------- | --------------------------------------- |
| Bedrock models return 403       | AWS SSO token expired | `aws sso login`                         |
| Vertex models return auth error | GCloud ADC expired    | `gcloud auth application-default login` |
| ChatGPT models fail             | OAuth token expired   | Re-authenticate via device flow         |
| "LITELLM_MASTER_KEY is not set" | .env not loaded       | Check .env exists and Docker reads it   |

### Routing / Env Vars

| Symptom                         | Cause                       | Fix                                                   |
| ------------------------------- | --------------------------- | ----------------------------------------------------- |
| Tool hits real API, not gateway | BASE_URL not set            | `source scripts/gateway-env.sh`                       |
| "Invalid API key" from gateway  | Wrong virtual key           | Check key in LiteLLM Admin UI (localhost:4000/ui)     |
| Requests bypass Caddy           | Hitting :4001 directly      | Use :4000 (Caddy port), not LiteLLM's internal port   |
| Traces missing in Langfuse      | OTEL callback misconfigured | Check LANGFUSE_PUBLIC_KEY/SECRET_KEY in container env |

### Env Var Precedence Trap

Docker Compose reads `.env` automatically, but shell environment variables **override** `.env`.
If you previously exported a variable (e.g., `LITELLM_MASTER_KEY`), the shell value wins even
if .env has a different value. Fix: `unset` the variable before `docker compose up`.

## Configure Mode

### Add a model

1. Edit `litellm/config.yaml` — add a new entry under `model_list:`
2. Follow the format from `litellm/config.example.yaml` for the provider
3. Restart LiteLLM: `docker compose restart gateway-litellm`
4. Verify: `curl -s http://localhost:4000/v1/models | jq '.data[].id'`

### Add a virtual key

```bash
curl -s http://localhost:4000/key/generate \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"key_alias": "tool-name", "user_id": "username", "metadata": {"tags": ["tool-name"]}}'
```

### Refresh credentials

```bash
./scripts/refresh-credentials.sh
```

## Verification

After any install or fix, verify end-to-end:

```bash
# 1. Run diagnostics
bash <skill-path>/scripts/diagnose.sh

# 2. Test a real request through the proxy
curl -s http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer ${LITELLM_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model": "fast-model", "messages": [{"role": "user", "content": "ping"}], "max_tokens": 5}' \
  | jq '.choices[0].message.content'

# 3. Check Langfuse for the trace
open http://localhost:5002
```

## Reference

For the complete service topology, port mappings, health check details, dependency graph,
and full catalog of known issues, read `references/topology.md`.
