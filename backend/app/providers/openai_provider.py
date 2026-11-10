"""OpenAI Responses API over HTTPX, with strict JSON Schema output."""

from __future__ import annotations

import json
import logging
from typing import Any

import httpx
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

logger = logging.getLogger("foodlens.openai")

RESPONSES_URL = "https://api.openai.com/v1/responses"


class OpenAIProvider:
    name = "openai"

    def __init__(self, api_key: str, model: str, timeout: float, client: httpx.AsyncClient | None = None) -> None:
        self._model = model
        self._client = client or httpx.AsyncClient(
            timeout=timeout, headers={"Authorization": f"Bearer {api_key}"}
        )

    async def analyze_meal(self, jpeg_base64: str, hint: str | None = None) -> MealAnalysisOutput:
        content = [
            {"type": "input_text", "text": prompts.meal_instructions(hint)},
            {"type": "input_image", "image_url": f"data:image/jpeg;base64,{jpeg_base64}", "detail": "high"},
        ]
        return await self._structured(prompts.MEAL_SYSTEM, content, "meal_analysis", MEAL_ANALYSIS_SCHEMA, MealAnalysisOutput)

    async def suggest_recipes(self, request: RecipeRequest) -> RecipeSuggestions:
        content = [{"type": "input_text", "text": prompts.recipes_prompt(request)}]
        return await self._structured(
            prompts.RECIPES_SYSTEM, content, "recipe_suggestions", RECIPE_SUGGESTIONS_SCHEMA, RecipeSuggestions
        )

    async def aclose(self) -> None:
        await self._client.aclose()

    async def _structured(self, system: str, content: list[dict], name: str, schema: dict,
                          model_type: type[BaseModel]) -> Any:
        payload = {
            "model": self._model,
            "instructions": system,
            "input": [{"role": "user", "content": content}],
            "text": {"format": {"type": "json_schema", "name": name, "strict": True, "schema": schema}},
        }
        try:
            response = await self._client.post(RESPONSES_URL, json=payload)
        except httpx.TransportError as exc:  # timeouts and connection errors
            logger.warning("OpenAI unreachable: %s", exc)
            raise ProviderUnavailable("connection") from exc

        if response.status_code == 429 or response.status_code >= 500:
            raise ProviderUnavailable(f"status {response.status_code}")
        if response.is_error:
            logger.warning("OpenAI status %s: %s", response.status_code, response.text[:500])
            raise ProviderError(f"status {response.status_code}")

        try:
            body = response.json()
        except ValueError as exc:
            raise ProviderBadOutput("non-json response") from exc

        for item in body.get("output", []):
            for part in item.get("content", []) or []:
                if part.get("type") == "refusal":
                    raise ProviderRefused(part.get("refusal", ""))
                if part.get("type") == "output_text":
                    try:
                        return model_type.model_validate(json.loads(part["text"]))
                    except (json.JSONDecodeError, ValidationError, KeyError) as exc:
                        logger.warning("OpenAI output failed validation: %s", exc)
                        raise ProviderBadOutput("invalid json") from exc
        raise ProviderBadOutput("no output_text")
