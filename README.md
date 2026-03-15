<div align="center">

<h1>litellm-langfuse-caddy</h1>

<p><strong>Local AI gateway with full observability</strong></p>

<p>Route all your LLM traffic through a single proxy with automatic tracing,<br>per-tool attribution, and session evaluation.</p>

<p>
  <img src="https://img.shields.io/badge/Docker_Compose-8_Services-2496ED?style=for-the-badge&logo=docker&logoColor=white" alt="Docker Compose">
  <img src="https://img.shields.io/badge/LiteLLM-v1.81-black?style=for-the-badge" alt="LiteLLM">
  <img src="https://img.shields.io/badge/Langfuse-v3-4B32C3?style=for-the-badge" alt="Langfuse">
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="MIT License">
</p>

<p>
  <a href="#quick-start">Quick Start</a> ·
  <a href="#features">Features</a> ·
  <a href="#architecture">Architecture</a> ·
  <a href="#provider-setup">Providers</a> ·
  <a href="#maintenance">Maintenance</a>
</p>

</div>

<br>

## Quick Start

```bash
git clone https://github.com/aaronmorris-dev/litellm-langfuse-caddy.git
cd litellm-langfuse-caddy

cp .env.example .env
cp litellm/config.example.yaml litellm/config.yaml

# Generate secrets and edit .env:
openssl rand -hex 32   # → SALT, ENCRYPTION_KEY, NEXTAUTH_SECRET
openssl rand -hex 16   # → LITELLM_MASTER_KEY

# Uncomment your providers in litellm/config.yaml, then:
chmod +x scripts/*.sh
./scripts/start.sh
```

<table>
  <tr>
    <td><strong>LiteLLM Proxy</strong></td>
    <td><a href="http://localhost:4000">localhost:4000</a></td>
  </tr>
  <tr>
    <td><strong>LiteLLM Admin</strong></td>
    <td><a href="http://localhost:4000/ui">localhost:4000/ui</a></td>
  </tr>
  <tr>
    <td><strong>Langfuse</strong></td>
    <td><a href="http://localhost:5002">localhost:5002</a></td>
  </tr>
  <tr>
    <td><strong>MinIO Console</strong></td>
    <td><a href="http://localhost:9091">localhost:9091</a></td>
  </tr>
</table>

<br>

## First-Time Setup

After `./scripts/start.sh` completes:

<table>
  <tr>
    <td><strong>1</strong></td>
    <td>Go to <a href="http://localhost:5002">localhost:5002</a> — sign up, create an org and project</td>
  </tr>
  <tr>
    <td><strong>2</strong></td>
    <td>Settings → API Keys → Create. Copy <code>pk-lf-...</code> and <code>sk-lf-...</code> into <code>.env</code></td>
  </tr>
  <tr>
    <td><strong>3</strong></td>
    <td>Run <code>docker compose up -d</code> to pick up the new keys</td>
  </tr>
  <tr>
    <td><strong>4</strong></td>
    <td>Go to <a href="http://localhost:4000/ui">localhost:4000/ui</a> → Virtual Keys → create per-tool keys with descriptive aliases</td>
  </tr>
</table>

<br>

## Architecture

```mermaid
flowchart TD
    CLI["🖥️ CLI Tools\nClaude Code · Gemini CLI · OpenAI SDK"]

    CLI -->|":4000 · :5002"| Caddy

    subgraph compose[" Docker Compose Stack "]
        Caddy["🔀 Caddy\nReverse Proxy · SSE"]

        Caddy --> LiteLLM["⚙️ LiteLLM\nUnified LLM Proxy"]
        Caddy --> Langfuse["📊 Langfuse\nObservability"]

        LiteLLM -.->|"traces"| Langfuse
        Worker["⚙️ Langfuse Worker"]

        LiteLLM --> PG & Redis
        Langfuse & Worker --> PG & CH & Redis & MinIO

        PG[("PostgreSQL 17")]
        CH[("ClickHouse 26")]
        Redis[("Redis 7.4")]
        MinIO[("MinIO")]
        PG ~~~ CH ~~~ Redis ~~~ MinIO
    end

    LiteLLM --> Providers["☁️ Bedrock · Vertex AI · Gemini · OpenAI · Anthropic"]
```

<br>

## Features

- **Multi-provider routing** — Bedrock, Vertex AI, Gemini, OpenAI, and Anthropic behind one endpoint. Switch models without changing your code.
- **Per-tool tracking** — Give each tool its own virtual key. Every request is automatically tagged to its source in Langfuse.
- **Automatic trace enrichment** — `langfuse_enrich.py` maps virtual keys to trace names, daily sessions, and tags. No client changes needed.
- **Session evaluation** — An LLM-as-judge script scores sessions on task completion, approach, and communication.
- **Zero-buffered streaming** — Caddy delivers tokens instantly with 10-minute response timeouts.
- **Hardened by default** — Memory limits, health checks, log rotation, and privilege lockdown on every service.

### Services

<table>
  <thead>
    <tr>
      <th>Service</th>
      <th>Image</th>
      <th>What it does</th>
      <th>Port</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><strong>Caddy</strong></td>
      <td><code>caddy:2-alpine</code></td>
      <td>Routes traffic to LiteLLM and Langfuse with zero-buffered streaming</td>
      <td><code>:4000</code> <code>:5002</code></td>
    </tr>
    <tr>
      <td><strong>LiteLLM</strong></td>
      <td><code>ghcr.io/berriai/litellm:main-v1.81.14-stable</code></td>
      <td>Sends requests to any provider through one API — routing, keys, and caching</td>
      <td>—</td>
    </tr>
    <tr>
      <td><strong>Langfuse</strong></td>
      <td><code>langfuse/langfuse:3</code></td>
      <td>Dashboard for traces, sessions, scores, and usage analytics</td>
      <td>—</td>
    </tr>
    <tr>
      <td><strong>Langfuse Worker</strong></td>
      <td><code>langfuse/langfuse-worker:3</code></td>
      <td>Processes incoming traces in the background</td>
      <td>—</td>
    </tr>
    <tr>
      <td><strong>PostgreSQL</strong></td>
      <td><code>postgres:17-alpine</code></td>
      <td>Stores keys, spend logs, projects, and user data</td>
      <td>—</td>
    </tr>
    <tr>
      <td><strong>ClickHouse</strong></td>
      <td><code>clickhouse/clickhouse-server:26.2</code></td>
      <td>Fast analytics storage for traces and observations</td>
      <td>—</td>
    </tr>
    <tr>
      <td><strong>Redis</strong></td>
      <td><code>redis:7.4-alpine</code></td>
      <td>Response cache and background job queue</td>
      <td>—</td>
    </tr>
    <tr>
      <td><strong>MinIO</strong></td>
      <td><code>cgr.dev/chainguard/minio</code></td>
      <td>Object storage for event logs and media uploads</td>
      <td><code>:9090</code> <code>:9091</code></td>
    </tr>
  </tbody>
</table>

<br>

## Provider Setup

<details>
<summary><strong>AWS Bedrock</strong> — Claude via AWS SSO</summary>
<br>

```bash
# 1. Configure SSO profile
aws configure sso --profile your-profile-name

# 2. Login
aws sso login --profile your-profile-name
```

Add to `.env`:

```
AWS_PROFILE=your-profile-name
```

Uncomment in `docker-compose.yaml` under litellm volumes:

```yaml
- ~/.aws:/root/.aws # writable — SSO needs token cache
```

Uncomment models in `litellm/config.yaml`:

```yaml
- model_name: claude-sonnet-4-6
  litellm_params:
    model: bedrock/us.anthropic.claude-sonnet-4-6
```

> **Note**: The `~/.aws` mount must NOT be `:ro` — AWS SSO writes token cache files during credential refresh.

</details>

<details>
<summary><strong>Google Vertex AI</strong> — Gemini via Application Default Credentials</summary>
<br>

```bash
gcloud auth application-default login
```

Add to `.env`:

```
GOOGLE_APPLICATION_CREDENTIALS=/root/.config/gcloud/application_default_credentials.json
```

Uncomment in `docker-compose.yaml` under litellm volumes:

```yaml
- ~/.config/gcloud:/root/.config/gcloud:ro
```

Add models to `litellm/config.yaml`:

```yaml
- model_name: gemini-2.5-flash
  litellm_params:
    model: vertex_ai/gemini-2.5-flash
    vertex_project: your-gcp-project
    vertex_location: us-central1
```

</details>

<details>
<summary><strong>Gemini API</strong> — Key-based (no GCP project needed)</summary>
<br>

Get a key from [Google AI Studio](https://aistudio.google.com/apikey), then add to `.env`:

```
GEMINI_API_KEY=your-key
```

Add to `litellm/config.yaml`:

```yaml
- model_name: gemini-2.5-flash
  litellm_params:
    model: gemini/gemini-2.5-flash
```

</details>

<details>
<summary><strong>OpenAI / Anthropic</strong> — Direct API keys</summary>
<br>

Add the env var to the litellm service in `docker-compose.yaml`:

```yaml
- OPENAI_API_KEY=${OPENAI_API_KEY}
# or
- ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
```

Add to `litellm/config.yaml`:

```yaml
- model_name: gpt-4o
  litellm_params:
    model: openai/gpt-4o

- model_name: claude-sonnet-4-6
  litellm_params:
    model: anthropic/claude-sonnet-4-6
```

</details>

<br>

## Using the Gateway

### Claude Code skill (built-in)

This repo includes a [Claude Code skill](https://docs.anthropic.com/en/docs/claude-code/skills) at `.claude/commands/llm-ops/gateway/`. Open the project in Claude Code and run `/llm-ops:gateway` to diagnose, install, or configure the stack conversationally. The bundled diagnostic checks Docker, containers, API health, credentials, and environment variables in one pass.

### Route CLI tools through the proxy

```bash
source scripts/gateway-env.sh

# Tools that use the OpenAI or Anthropic SDK now route through LiteLLM:
# ANTHROPIC_BASE_URL=http://localhost:4000
# OPENAI_BASE_URL=http://localhost:4000/v1
```

See [`examples/transparent-routing.md`](examples/transparent-routing.md) for permanent shell setup, per-tool virtual keys, and SDK examples. Tool-specific config examples are in [`examples/.claude/`](examples/.claude/) and [`examples/.codex/`](examples/.codex/).

### How trace enrichment works

```mermaid
flowchart LR
    Key["🔑 Virtual Key\nalias · tags · user_id"] --> Enrich["langfuse_enrich.py\nRuns on every request"]
    Enrich --> Name["Trace Name\nclaude"]
    Enrich --> Session["Daily Session\nclaude-2026-03-14"]
    Enrich --> Tags["Tags\n[claude]"]
```

Create virtual keys in [LiteLLM Admin](http://localhost:4000/ui):

| What you set  | Example                | What shows in Langfuse |
| ------------- | ---------------------- | ---------------------- |
| Key Alias     | `claude`               | Trace name: `claude`   |
| User ID       | `alice`                | User: `alice`          |
| Metadata tags | `{"tags": ["claude"]}` | Tags: `["claude"]`     |

The enrichment hook automatically groups traces into **daily sessions** (e.g., `claude-2026-03-14`) — one per tool per day.

<br>

## Maintenance

<details>
<summary><strong>Prune old data</strong></summary>
<br>

```bash
# Deletes: spend logs (30d), error logs (14d), traces (30d), scores (60d)
./scripts/prune-postgres.sh
```

This cleans both PostgreSQL (LiteLLM spend/error logs) and ClickHouse (Langfuse traces/observations).

</details>

<details>
<summary><strong>Evaluate a session</strong></summary>
<br>

Uses LLM-as-judge to score sessions on 4 dimensions (0.0–1.0), then posts scores back to Langfuse.

```bash
# Requires: uv (https://docs.astral.sh/uv/)
uv run --script scripts/eval-session.py --today claude
uv run --script scripts/eval-session.py claude-2026-03-14
uv run --script scripts/eval-session.py claude-2026-03-14 --dry-run --verbose
```

| Dimension          | Weight | What it measures                             |
| ------------------ | ------ | -------------------------------------------- |
| `task_completion`  | 50%    | Did the assistant complete the user's goals? |
| `approach_quality` | 30%    | Engineering soundness and efficiency         |
| `communication`    | 20%    | Clarity, concision, appropriateness          |
| `overall`          | —      | Weighted composite of the above              |

</details>

<details>
<summary><strong>Check provider credentials</strong></summary>
<br>

```bash
./scripts/refresh-credentials.sh
```

Checks AWS SSO session and GCloud ADC token, refreshing expired credentials interactively.

</details>

<details>
<summary><strong>Stop / restart / logs</strong></summary>
<br>

```bash
./scripts/start.sh         # Start all services (with validation)
./scripts/stop.sh          # Stop all services
docker compose logs -f     # Follow all logs
docker compose ps          # Check service status
```

</details>

<br>

## Hardening Details

Every service is locked down by default:

| What                 | Where                                             | Why                                                          |
| -------------------- | ------------------------------------------------- | ------------------------------------------------------------ |
| Memory limits        | All 8 services                                    | Each service capped (128 MB – 1.5 GB) to prevent runaway use |
| Privilege lockdown   | All 8 services                                    | Containers cannot escalate permissions                       |
| Read-only filesystem | Caddy                                             | Root filesystem is immutable; temp storage for runtime data  |
| Process management   | LiteLLM, Langfuse, Worker, MinIO                  | Clean signal handling via tini                               |
| UTC everywhere       | PostgreSQL, ClickHouse                            | All timestamps in UTC — no timezone surprises                |
| Log rotation         | All 8 services                                    | 5–20 MB per log file, 3–5 files kept                         |
| Health checks        | 6 of 8 services                                   | Automatic probes with retries and startup grace periods      |
| Graceful shutdown    | LiteLLM (30s), Langfuse (15s), PG (30s), CH (15s) | Services finish in-flight work before stopping               |
| Localhost only       | Caddy, MinIO                                      | Exposed ports bound to 127.0.0.1 — not reachable externally  |

<br>

## Prerequisites

- [OrbStack](https://orbstack.dev/) (recommended) or any Docker-compatible runtime — OrbStack uses less memory and starts faster, which helps with an 8-service stack
- ~4 GB RAM available for containers
- Credentials for at least one LLM provider

<br>

## File Structure

```
.
├── .claude/commands/llm-ops/gateway/  # Claude Code skill (diagnose, install, configure)
│   ├── SKILL.md                       # Skill definition and instructions
│   ├── scripts/diagnose.sh            # Automated diagnostic cascade
│   └── references/topology.md         # Service topology and known issues
├── docker-compose.yaml                # 8-service stack definition
├── Caddyfile                          # Reverse proxy config (SSE, timeouts, logging)
├── .env.example                       # All required environment variables
├── litellm/
│   ├── config.example.yaml            # LiteLLM model config template
│   └── langfuse_enrich.py             # Trace enrichment hook (auto-loaded by LiteLLM)
├── examples/
│   ├── .claude/settings.json          # Claude Code proxy config
│   ├── .codex/config.yaml             # Codex CLI proxy config
│   └── transparent-routing.md         # Guide: route any tool through the gateway
└── scripts/
    ├── start.sh                       # Startup with validation
    ├── stop.sh                        # Graceful shutdown
    ├── gateway-env.sh                 # Source to route tools through the proxy
    ├── refresh-credentials.sh         # Check/refresh provider credentials
    ├── prune-postgres.sh              # Data retention maintenance
    ├── prune-postgres.sql             # PostgreSQL pruning policy
    └── eval-session.py                # LLM-as-judge session evaluation
```

<br>

<div align="center">
  <sub>MIT License · Built for developers who want observability without the overhead.</sub>
</div>
