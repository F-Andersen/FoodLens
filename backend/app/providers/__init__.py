"""AI provider selection. Switch with the AI_PROVIDER environment variable."""

from __future__ import annotations

from ..config import Settings
from .base import AIProvider, ProviderBadOutput, ProviderError, ProviderRefused, ProviderUnavailable

__all__ = [
    "AIProvider", "ProviderBadOutput", "ProviderError", "ProviderRefused", "ProviderUnavailable", "make_provider",
]


def make_provider(settings: Settings) -> AIProvider:
    if settings.ai_provider == "anthropic":
        from .anthropic_provider import AnthropicProvider

        return AnthropicProvider(settings.anthropic_api_key or "", settings.anthropic_model, settings.ai_timeout_seconds)
    if settings.ai_provider == "openai":
        from .openai_provider import OpenAIProvider

        return OpenAIProvider(settings.openai_api_key or "", settings.openai_model, settings.ai_timeout_seconds)
    if settings.ai_provider == "gemini":
        from .gemini_provider import GeminiProvider

        return GeminiProvider(settings.gemini_api_key or "", settings.gemini_model, settings.ai_timeout_seconds)
    from .mock_provider import MockProvider

    return MockProvider()
