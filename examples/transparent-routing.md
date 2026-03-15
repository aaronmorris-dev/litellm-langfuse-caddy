# Transparent Routing: OpenRouter → LiteLLM

Redirect tools that normally call [OpenRouter](https://openrouter.ai) to your local LiteLLM proxy instead.

## Why

OpenRouter and LiteLLM serve the same role: a unified API that routes LLM requests to multiple providers (Anthropic, Google, OpenAI, etc.) through a single endpoint. LiteLLM runs locally with full observability via Langfuse — so any tool configured for OpenRouter can be transparently redirected to LiteLLM by overriding the environment variables it checks.

## Environment Variable Mapping

| Variable              | OpenRouter Default             | LiteLLM Replacement        |
| --------------------- | ------------------------------ | -------------------------- |
| `OPENROUTER_BASE_URL` | `https://openrouter.ai/api/v1` | `http://localhost:4000/v1` |
| `OPENROUTER_API_KEY`  | OpenRouter API key             | LiteLLM virtual key        |
| `OPENAI_BASE_URL`     | `https://api.openai.com/v1`    | `http://localhost:4000/v1` |
| `OPENAI_API_KEY`      | OpenAI API key                 | LiteLLM virtual key        |
| `ANTHROPIC_BASE_URL`  | `https://api.anthropic.com`    | `http://localhost:4000`    |
| `ANTHROPIC_API_KEY`   | Anthropic API key              | LiteLLM virtual key        |

Most tools that talk to OpenRouter use the OpenAI SDK under the hood, so setting `OPENAI_BASE_URL` + `OPENAI_API_KEY` is often sufficient. The `OPENROUTER_*` vars cover tools that check for OpenRouter-specific configuration first.

## Quick Setup

Source the gateway environment script:

```bash
source scripts/gateway-env.sh
```

This sets all six variables above, pointing them at your local LiteLLM instance with a virtual key derived from `LITELLM_KEY` (or `LITELLM_MASTER_KEY` as fallback).

## Permanent Shell Profile Setup

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
# LiteLLM Gateway — redirect OpenRouter, OpenAI, and Anthropic traffic
export OPENROUTER_BASE_URL="http://localhost:4000/v1"
export OPENROUTER_API_KEY="sk-your-litellm-virtual-key"
export OPENAI_BASE_URL="http://localhost:4000/v1"
export OPENAI_API_KEY="sk-your-litellm-virtual-key"
export ANTHROPIC_BASE_URL="http://localhost:4000"
export ANTHROPIC_API_KEY="sk-your-litellm-virtual-key"
```

Or auto-source the gateway script:

```bash
# LiteLLM Gateway (auto-source)
[[ -f ~/.config/ai-gateway/scripts/gateway-env.sh ]] && \
  source ~/.config/ai-gateway/scripts/gateway-env.sh
```

## Per-Tool Virtual Keys

For per-tool attribution in Langfuse, create separate virtual keys in the [LiteLLM Admin UI](http://localhost:4000/ui) and assign each tool its own key:

```bash
# Claude Code
export ANTHROPIC_BASE_URL="http://localhost:4000"
export ANTHROPIC_API_KEY="sk-claude-code-key"

# Codex / OpenAI SDK tools
export OPENAI_BASE_URL="http://localhost:4000/v1"
export OPENAI_API_KEY="sk-codex-key"

# OpenRouter-compatible tools
export OPENROUTER_BASE_URL="http://localhost:4000/v1"
export OPENROUTER_API_KEY="sk-openrouter-tool-key"
```

Each virtual key should have a descriptive alias (e.g., `claude-code`, `codex`, `openrouter`) so the trace enrichment hook automatically names traces and creates daily sessions in Langfuse.

## How It Works

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

The tool thinks it's talking to OpenRouter (or OpenAI/Anthropic) directly. LiteLLM translates the request to whichever provider is actually configured (Bedrock, Vertex AI, etc.) and Langfuse captures the full trace.

## Verification

Confirm traffic is flowing through the gateway:

```bash
# Check env vars are set correctly
echo $OPENROUTER_BASE_URL   # should be http://localhost:4000/v1
echo $OPENAI_BASE_URL       # should be http://localhost:4000/v1
echo $ANTHROPIC_BASE_URL    # should be http://localhost:4000

# Watch LiteLLM logs for incoming requests
docker compose logs -f gateway-litellm

# Check Langfuse for traces
open http://localhost:5002
```

If a tool still hits OpenRouter directly, check whether it hardcodes the base URL or reads from a config file rather than environment variables — some tools require explicit config overrides.
