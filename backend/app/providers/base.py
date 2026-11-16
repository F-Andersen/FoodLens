"""Provider interface shared by the Anthropic, OpenAI and mock implementations."""

from __future__ import annotations

from typing import Protocol

from ..schemas import MealAnalysisOutput, RecipeRequest, RecipeSuggestions


class ProviderError(Exception):
    """The provider failed in a way the client cannot fix (misconfiguration, bad output)."""


class ProviderUnavailable(ProviderError):
    """Temporary: rate limited, overloaded, timed out or unreachable. Worth retrying later."""


class ProviderRefused(ProviderError):
    """The model declined the request (for example, the photo is not food or violates policy)."""


class ProviderBadOutput(ProviderError):
    """The model answered, but not with valid structured output."""


class AIProvider(Protocol):
    name: str

    async def analyze_meal(self, jpeg_base64: str, hint: str | None = None) -> MealAnalysisOutput: ...

    async def suggest_recipes(self, request: RecipeRequest) -> RecipeSuggestions: ...

    async def aclose(self) -> None: ...
