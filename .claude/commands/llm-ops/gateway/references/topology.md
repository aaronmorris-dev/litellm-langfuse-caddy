# AI Gateway — Service Topology

## Service Dependency Graph

```
                    ┌─────────────────────────────────────┐
                    │           User / CLI Tool            │
                    │  (Claude Code, Codex, Gemini CLI)    │
                    └──────────────┬──────────────────────┘
                                   │ :4000 (LLM API)
                                   │ :5002 (Langfuse UI)
                    ┌──────────────▼──────────────────────┐
                    │         gateway-caddy                │
                    │   Reverse proxy (SSE-optimized)      │
                    │   :4000 → litellm, :5002 → langfuse  │
                    └──┬───────────────────────────┬──────┘
                       │                           │
          ┌────────────▼────────────┐   ┌──────────▼───────────┐
          │   gateway-litellm       │   │   gateway-langfuse    │
          │   LLM proxy + Admin UI  │   │   Tracing dashboard   │
          │   Depends: postgres,    │   │   Depends: postgres,  │
          │     redis               │   │     clickhouse, redis,│
          └──┬──────┬───────────┬──┘   │     minio             │
             │      │           │       └──┬────┬────┬────┬────┘
             │      │           │          │    │    │    │
    ┌────────▼──┐ ┌─▼────────┐ │   ┌──────▼┐ ┌─▼────▼─┐ │
    │ postgres  │ │  redis   │ │   │click- │ │ minio  │ │
    │ :5432     │ │  :6379   │ │   │house  │ │ :9090  │ │
    │ (internal)│ │(internal)│ │   │:8123  │ │ :9091  │ │
    └───────────┘ └──────────┘ │   │(int.) │ └────────┘ │
                               │   └───────┘            │
                    ┌──────────▼───────────┐  ┌─────────▼──────────┐
                    │   LLM Providers      │  │ gateway-langfuse-  │
                    │   - AWS Bedrock      │  │ worker             │
                    │   - Google Vertex AI  │  │ Background trace   │
                    │   - Gemini API       │  │ processing         │
                    │   - ChatGPT/OpenAI   │  └────────────────────┘
                    └──────────────────────┘
```

## Port Mapping

| Port | Service          | External?     | Purpose                          |
| ---- | ---------------- | ------------- | -------------------------------- |
| 4000 | Caddy → LiteLLM  | Yes           | LLM proxy API + Admin UI (`/ui`) |
| 5002 | Caddy → Langfuse | Yes           | Tracing dashboard                |
| 9090 | MinIO            | Yes           | S3-compatible API                |
| 9091 | MinIO            | Yes           | Web console                      |
| 5432 | PostgreSQL       | No (internal) | Metadata DB                      |
| 6379 | Redis            | No (internal) | Cache + job queue                |
| 8123 | ClickHouse       | No (internal) | Analytics columnar store         |

## Container Details

| Container               | Image                                        | Memory Limit | Health Check             |
| ----------------------- | -------------------------------------------- | ------------ | ------------------------ |
| gateway-caddy           | caddy:2-alpine                               | 128m         | `caddy validate`         |
| gateway-litellm         | ghcr.io/berriai/litellm:main-v1.81.14-stable | 1536m        | `GET /health/liveliness` |
| gateway-langfuse        | langfuse/langfuse:3                          | 1024m        | `GET /api/public/health` |
| gateway-langfuse-worker | langfuse/langfuse-worker:3                   | 512m         | Script-based             |
| gateway-postgres        | postgres:17-alpine                           | 512m         | `pg_isready`             |
| gateway-redis           | redis:7.4-alpine                             | 256m         | `redis-cli ping`         |
| gateway-clickhouse      | clickhouse/clickhouse-server:26.2            | 1024m        | `wget :8123/ping`        |
| gateway-minio           | cgr.dev/chainguard/minio                     | 512m         | `mc ready local`         |

**Total memory budget: ~5.5 GB**

## Volume Mounts (Key)

| Mount                        | Container | Mode           | Why                                       |
| ---------------------------- | --------- | -------------- | ----------------------------------------- |
| `~/.aws`                     | litellm   | **read-write** | AWS SSO writes token cache during refresh |
| `~/.config/gcloud`           | litellm   | read-only      | GCloud ADC credentials                    |
| `litellm/chatgpt/`           | litellm   | read-write     | ChatGPT OAuth token storage               |
| `litellm/config.yaml`        | litellm   | read-only      | Model routes                              |
| `litellm/langfuse_enrich.py` | litellm   | read-only      | Custom trace callback                     |

## Credential Flows

### AWS Bedrock (Claude)

- Auth: SSO via `~/.aws/` profile
- Token cache: `~/.aws/sso/cache/`
- Refresh: `aws sso login --profile <profile>`
- Health check: `aws sts get-caller-identity`
- Mount must be **writable** — SSO writes cache files during token refresh

### Google Vertex AI (Gemini)

- Auth: Application Default Credentials (ADC)
- Token: `~/.config/gcloud/application_default_credentials.json`
- Refresh: `gcloud auth application-default login`
- Health check: `gcloud auth application-default print-access-token`

### Google Gemini API

- Auth: API key (`GEMINI_API_KEY` in .env)
- No expiry — key-based auth

### ChatGPT / OpenAI

- Auth: OAuth device code flow
- Token: `litellm/chatgpt/auth.json`
- LiteLLM auto-refreshes via `refresh_token` until it expires
- Manual refresh: Re-authenticate via device flow
- Known issue: Health checks return "Input must be a list" — LiteLLM limitation with `mode: responses`, real requests work fine

## Known Issues & Workarounds

### Docker Compose env var precedence

**Problem:** Shell env vars override `.env` file values.
**Fix:** `unset LITELLM_MASTER_KEY` (or the offending var) before `docker compose up -d`.

### `~/.aws` mount must not be read-only

**Problem:** LiteLLM container fails to refresh AWS SSO tokens if `~/.aws` is mounted `:ro`.
**Fix:** Mount as read-write (no `:ro` suffix) in docker-compose.yaml.

### `default_vertex_config` not applied

**Problem:** LiteLLM v1.81.14 ignores `default_vertex_config` in litellm_settings.
**Fix:** Set `vertex_project` and `vertex_location` explicitly on each Vertex AI model in config.yaml.

### ChatGPT health check failures

**Problem:** Health checks for ChatGPT models return "Input must be a list" error.
**Impact:** Health check fails but real requests work fine. Ignore in diagnostics.

### Langfuse traces missing

**Causes:**

1. `LANGFUSE_PUBLIC_KEY` / `LANGFUSE_SECRET_KEY` incorrect in the LiteLLM container env
2. `proxy_batch_write_at: 10` means traces appear ~10 seconds after the request
3. The `langfuse_otel` callback requires correct keys — typos fail silently
   **Fix:** Verify keys match Langfuse Settings > API Keys. Restart after changing.

### Container restart loops

**Debug:** `docker logs gateway-<name> --tail 100`
**Common causes:**

- postgres: Port conflict, corrupt WAL, disk full
- litellm: Invalid config.yaml syntax, missing required env vars
- clickhouse: OOM killed (increase `mem_limit` in docker-compose.yaml)
- langfuse: Database migration failure (check postgres connectivity)

### Caddy streaming issues

**Problem:** SSE responses are buffered or truncated.
**Fix:** Caddyfile should have `flush_interval -1` on the LiteLLM upstream.

## Maintenance Scripts

| Script                           | Purpose                              | Frequency                  |
| -------------------------------- | ------------------------------------ | -------------------------- |
| `scripts/start.sh`               | Boot the stack                       | As needed                  |
| `scripts/stop.sh`                | Graceful shutdown                    | As needed                  |
| `scripts/refresh-credentials.sh` | Check/refresh provider credentials   | Weekly or on auth failures |
| `scripts/prune-postgres.sh`      | Clean old logs and traces            | Monthly                    |
| `scripts/eval-session.py`        | Score a coding session via LLM judge | Auto or manual             |
| `scripts/gateway-env.sh`         | Load env vars for shell tools        | Sourced in .zshrc          |

## Data Retention (Pruning Policy)

| Data               | Retention | Store      |
| ------------------ | --------- | ---------- |
| LiteLLM spend logs | 30 days   | PostgreSQL |
| LiteLLM error logs | 14 days   | PostgreSQL |
| Langfuse traces    | 30 days   | ClickHouse |
| Langfuse scores    | 60 days   | ClickHouse |
| Langfuse event log | 14 days   | ClickHouse |
