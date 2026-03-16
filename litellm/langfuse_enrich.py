"""
LiteLLM pre-call hook that auto-enriches Langfuse trace metadata
from virtual key attributes — no client-side changes needed.

Propagates to Langfuse (via langfuse_otel OTEL callback):
  - trace_user_id  ← key user_id   (shows as Langfuse userId)
  - trace_name     ← key alias     (names traces by tool, not "litellm-acompletion")
  - session_id     ← key alias + date (groups traces into daily per-tool sessions)
  - tags           ← key metadata tags (filterable in Langfuse)
"""

from datetime import datetime, timezone

from litellm.integrations.custom_logger import CustomLogger
from litellm.proxy._types import UserAPIKeyAuth


class LangfuseEnrichHook(CustomLogger):
    async def async_pre_call_hook(
        self,
        user_api_key_dict: UserAPIKeyAuth,
        cache,
        data: dict,
        call_type: str,
    ) -> Exception | None:
        metadata = data.setdefault("metadata", {})

        alias = getattr(user_api_key_dict, "key_alias", None)

        # Skip enrichment for requests without a virtual key (e.g. health checks)
        if not alias:
            return None

        key_meta = getattr(user_api_key_dict, "metadata", None) or {}

        # Map key user_id → Langfuse userId (top-level, then metadata fallback)
        if not metadata.get("trace_user_id"):
            uid = getattr(user_api_key_dict, "user_id", None) or key_meta.get("user_id")
            if uid:
                metadata["trace_user_id"] = uid

        # Map key alias → Langfuse trace name
        if not metadata.get("trace_name"):
            metadata["trace_name"] = alias

        # Auto-generate session_id: <tool>-YYYY-MM-DD
        # Client can override via langfuse_session_id header (LiteLLM maps it
        # to metadata["session_id"] before this hook runs).
        if not metadata.get("session_id"):
            today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
            metadata["session_id"] = f"{alias}-{today}"

        # Propagate tags (explicit from key metadata, or auto-generate from alias)
        key_tags = key_meta.get("tags") or [alias]
        existing = metadata.get("tags", [])
        metadata["tags"] = list({*existing, *key_tags})

        return None


proxy_handler_instance = LangfuseEnrichHook()
