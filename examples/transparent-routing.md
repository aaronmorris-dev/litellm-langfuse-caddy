# Transparent LLM Routing

Route any OpenAI or Anthropic SDK-compatible tool through the LiteLLM gateway without modifying the tool itself.

## Quick Setup

Source the gateway environment script in your terminal:

```bash
source scripts/gateway-env.sh
```

This sets:

| Variable             | Value                      | Used By                    |
| -------------------- | -------------------------- | -------------------------- |
| `ANTHROPIC_BASE_URL` | `http://localhost:4000`    | Claude Code, Anthropic SDK |
| `ANTHROPIC_API_KEY`  | Your LiteLLM virtual key   | Claude Code, Anthropic SDK |
| `OPENAI_BASE_URL`    | `http://localhost:4000/v1` | Codex, OpenAI SDK, Cursor  |
| `OPENAI_API_KEY`     | Your LiteLLM virtual key   | Codex, OpenAI SDK, Cursor  |

## Permanent Setup

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
# LiteLLM Gateway
export ANTHROPIC_BASE_URL="http://localhost:4000"
export ANTHROPIC_API_KEY="sk-your-litellm-virtual-key"
export OPENAI_BASE_URL="http://localhost:4000/v1"
export OPENAI_API_KEY="sk-your-litellm-virtual-key"
```

Or source the gateway script automatically:

```bash
# LiteLLM Gateway (auto-source)
[[ -f ~/path/to/litellm-langfuse-caddy/scripts/gateway-env.sh ]] && \
  source ~/path/to/litellm-langfuse-caddy/scripts/gateway-env.sh
```

## Per-Tool Virtual Keys

For per-tool attribution in Langfuse, create separate virtual keys in the [LiteLLM Admin UI](http://localhost:4000/ui) and assign each tool its own key:

```bash
# Claude Code
export ANTHROPIC_BASE_URL="http://localhost:4000"
export ANTHROPIC_API_KEY="sk-claude-code-key"

# Codex
export OPENAI_BASE_URL="http://localhost:4000/v1"
export OPENAI_API_KEY="sk-codex-key"
```

Each virtual key should have a descriptive alias (e.g., `claude-code`, `codex`) so the trace enrichment hook automatically names traces and creates daily sessions in Langfuse.

## How It Works

Most AI CLI tools and SDKs respect the `*_BASE_URL` and `*_API_KEY` environment variables:

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  CLI Tool    │────>│  Caddy       │────>│  LiteLLM     │────>│  Provider    │
│  (any)       │     │  :4000       │     │  Proxy       │     │  (Bedrock,   │
│              │     │              │     │              │     │   Vertex,..) │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
                                               │
                                               ▼
                                          ┌──────────────┐
                                          │  Langfuse    │
                                          │  Traces      │
                                          └──────────────┘
```

The tool thinks it's talking to OpenAI or Anthropic directly. LiteLLM translates the request to whichever provider is actually configured (Bedrock, Vertex AI, etc.) and Langfuse captures the full trace.

## Tool-Specific Notes

### Claude Code

Claude Code uses the Anthropic SDK. Set `ANTHROPIC_BASE_URL` and `ANTHROPIC_API_KEY`, or copy `examples/.claude/settings.json` to `~/.claude/settings.json`.

### Codex (OpenAI CLI)

Codex uses the OpenAI SDK. Set `OPENAI_BASE_URL` and `OPENAI_API_KEY`, or copy `examples/.codex/config.yaml` to `~/.codex/config.yaml`.

### Any OpenAI-Compatible Tool

Any tool that uses the OpenAI SDK (Cursor, Continue, Aider, etc.) will route through the gateway when `OPENAI_BASE_URL` and `OPENAI_API_KEY` are set.

### Python / Node.js SDKs

```python
# Python — automatically picks up env vars
from anthropic import Anthropic
client = Anthropic()  # uses ANTHROPIC_BASE_URL + ANTHROPIC_API_KEY

from openai import OpenAI
client = OpenAI()  # uses OPENAI_BASE_URL + OPENAI_API_KEY
```

```typescript
// Node.js — automatically picks up env vars
import Anthropic from "@anthropic-ai/sdk";
const client = new Anthropic(); // uses ANTHROPIC_BASE_URL + ANTHROPIC_API_KEY

import OpenAI from "openai";
const client = new OpenAI(); // uses OPENAI_BASE_URL + OPENAI_API_KEY
```

## Verifying the Route

Confirm traffic is flowing through the gateway:

```bash
# Check LiteLLM is receiving requests
docker compose logs -f gateway-litellm

# Check Langfuse for traces
open http://localhost:5002
```
