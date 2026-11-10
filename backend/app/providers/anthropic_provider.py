"""Claude via the official Anthropic SDK, with schema-constrained JSON output."""

from __future__ import annotations

import json
import logging
from typing import Any

import anthropic
from pydantic import BaseModel, ValidationError

from ..schemas import (
    MEAL_ANALYSIS_SCHEMA,
    RECIPE_SUGGESTIONS_SCHEMA,
    MealAnalysisOutput,
    RecipeRequest,
    RecipeSuggestions,
)
from . import prompts
from .base import ProviderBadOutput, ProviderError, ProviderRefused, ProviderUnavailable

logger = logging.getLogger("foodlens.anthropic")

# On a safety-classifier decline the API re-runs the request on Anthropic's recommended fallback model.
FALLBACK_BETA = "server-side-fallback-2026-07-01"


def supports_server_fallback(model: str) -> bool:
    """Haiku models have no server-side fallback, so the parameter would do nothing for them."""
    return not model.startswith("claude-haiku")


class AnthropicProvider:
    name = "anthropic"

    def __init__(self, api_key: str, model: str, timeout: float, client: Any | None = None) -> None:
        self._model = model
        self._client = client or anthropic.AsyncAnthropic(api_key=api_key, timeout=timeout, max_retries=2)

    async def analyze_meal(self, jpeg_base64: str, hint: str | None = None) -> MealAnalysisOutput:
        content = [
            {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": jpeg_base64}},
            {"type": "text", "text": prompts.meal_instructions(hint)},
        ]
        return await self._structured(
            system=prompts.MEAL_SYSTEM, content=content, schema=MEAL_ANALYSIS_SCHEMA, model_type=MealAnalysisOutput
        )

    async def suggest_recipes(self, request: RecipeRequest) -> RecipeSuggestions:
        return await self._structured(
            system=prompts.RECIPES_SYSTEM,
            content=[{"type": "text", "text": prompts.recipes_prompt(request)}],
            schema=RECIPE_SUGGESTIONS_SCHEMA,
            model_type=RecipeSuggestions,
        )

    async def aclose(self) -> None:
        await self._client.close()

    async def _structured(self, *, system: str, content: list[dict], schema: dict, model_type: type[BaseModel]) -> Any:
        try:
            fallback = {"betas": [FALLBACK_BETA], "fallbacks": "default"} if supports_server_fallback(self._model) else {}
            response = await self._client.beta.messages.create(
                model=self._model,
                max_tokens=16000,
                system=system,
                messages=[{"role": "user", "content": content}],
                output_config={"effort": "medium", "format": {"type": "json_schema", "schema": schema}},
                **fallback,
            )
        except anthropic.APIConnectionError as exc:  # includes timeouts
            logger.warning("Anthropic unreachable: %s", exc)
            raise ProviderUnavailable("connection") from exc
        except anthropic.APIStatusError as exc:
            logger.warning("Anthropic status %s: %s", exc.status_code, exc.message)
            if exc.status_code == 429 or exc.status_code >= 500:
                raise ProviderUnavailable(f"status {exc.status_code}") from exc
            raise ProviderError(f"status {exc.status_code}") from exc

        if response.stop_reason == "refusal":
            category = getattr(getattr(response, "stop_details", None), "category", None)
            logger.info("Anthropic refusal, category=%s", category)
            raise ProviderRefused(str(category))
        if response.stop_reason == "max_tokens":
            raise ProviderBadOutput("max_tokens")

        text = next((block.text for block in response.content if block.type == "text"), None)
        if text is None:
            raise ProviderBadOutput("no text block")
        try:
            return model_type.model_validate(json.loads(text))
        except (json.JSONDecodeError, ValidationError) as exc:
            logger.warning("Anthropic output failed validation: %s", exc)
            raise ProviderBadOutput("invalid json") from exc
