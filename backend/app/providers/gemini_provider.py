"""Google Gemini via the Interactions API over HTTPX, with JSON Schema output."""

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

logger = logging.getLogger("foodlens.gemini")

INTERACTIONS_URL = "https://generativelanguage.googleapis.com/v1beta/interactions"
API_REVISION = "2026-05-20"


class GeminiProvider:
    name = "gemini"

    def __init__(self, api_key: str, model: str, timeout: float, client: httpx.AsyncClient | None = None) -> None:
        self._model = model
        self._client = client or httpx.AsyncClient(
            timeout=timeout, headers={"x-goog-api-key": api_key, "Api-Revision": API_REVISION}
        )

    async def analyze_meal(self, jpeg_base64: str) -> MealAnalysisOutput:
        content = [
            {"type": "text", "text": prompts.MEAL_INSTRUCTIONS},
            {"type": "image", "data": jpeg_base64, "mime_type": "image/jpeg"},
        ]
        return await self._structured(prompts.MEAL_SYSTEM, content, MEAL_ANALYSIS_SCHEMA, MealAnalysisOutput)

    async def suggest_recipes(self, request: RecipeRequest) -> RecipeSuggestions:
        content = [{"type": "text", "text": prompts.recipes_prompt(request)}]
        return await self._structured(prompts.RECIPES_SYSTEM, content, RECIPE_SUGGESTIONS_SCHEMA, RecipeSuggestions)

    async def aclose(self) -> None:
        await self._client.aclose()

    async def _structured(self, system: str, content: list[dict], schema: dict, model_type: type[BaseModel]) -> Any:
        payload = {
            "model": self._model,
            "system_instruction": system,
            "input": content,
            "response_format": {"type": "text", "mime_type": "application/json", "schema": schema},
            "generation_config": {"max_output_tokens": 16000},
            "store": False,  # meal photos must not be kept for later retrieval
        }
        try:
            response = await self._client.post(INTERACTIONS_URL, json=payload)
        except httpx.TransportError as exc:  # timeouts and connection errors
            logger.warning("Gemini unreachable: %s", type(exc).__name__)
            raise ProviderUnavailable("connection") from exc

        if response.status_code == 429 or response.status_code >= 500:
            logger.warning("Gemini status %s: %s", response.status_code, response.text[:500])
            raise ProviderUnavailable(f"status {response.status_code}")
        if response.is_error:
            logger.warning("Gemini status %s: %s", response.status_code, response.text[:500])
            raise ProviderError(f"status {response.status_code}")

        try:
            body = response.json()
        except ValueError as exc:
            raise ProviderBadOutput("non-json response") from exc

        status = body.get("status")
        if status == "failed":
            errors = body.get("errors") or [{}]
            code = str(errors[0].get("code", ""))
            logger.warning("Gemini interaction failed: %s", code)
            if any(word in code.lower() for word in ("safety", "block", "prohibited")):
                raise ProviderRefused(code)
            raise ProviderError(f"failed {code}")
        if status != "completed":
            raise ProviderBadOutput(f"status {status}")

        text = self._output_text(body)
        if not text:
            raise ProviderBadOutput("no text output")
        try:
            return model_type.model_validate(json.loads(text))
        except (json.JSONDecodeError, ValidationError) as exc:
            logger.warning("Gemini output failed validation: %s", exc)
            raise ProviderBadOutput("invalid json") from exc

    @staticmethod
    def _output_text(body: dict) -> str:
        """Joins the text parts of the last model_output step; thought steps are skipped."""
        outputs = [step for step in body.get("steps", []) if step.get("type") == "model_output"]
        if not outputs:
            return ""
        return "".join(part.get("text", "") for part in outputs[-1].get("content", []) if part.get("type") == "text")
