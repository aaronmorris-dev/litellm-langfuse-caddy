#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

echo "Stopping LiteLLM / Langfuse..."
docker compose down

echo "LiteLLM / Langfuse stopped."
