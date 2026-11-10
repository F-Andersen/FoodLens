from __future__ import annotations

import asyncio
import json
from types import SimpleNamespace

import anthropic
import httpx
import pytest

from app.providers import ProviderBadOutput, ProviderError, ProviderRefused, ProviderUnavailable
from app.providers.anthropic_provider import FALLBACK_BETA, AnthropicProvider
from app.providers.gemini_provider import API_REVISION, GeminiProvider
from app.providers.openai_provider import OpenAIProvider
from app.schemas import RecipeRequest

MEAL_JSON = {
    "dish": "Борщ", "estimatedGrams": 400, "caloriesPer100g": 55, "protein": 12, "carbs": 24, "fat": 9,
    "fiber": 6, "confidence": 1.4,
    "ingredients": [{"name": "буряк", "grams": 120, "calories": 50, "protein": 2, "carbs": 11, "fat": 0,
                     "fiber": -1}],
}
RECIPES_JSON = {
    "message": "Добре!",
    "recipes": [{"title": "Омлет", "mealType": "breakfast", "minutes": 10.4,
                 "ingredients": [{"name": "яйця", "grams": 180, "calories": 260}],
                 "steps": ["Збийте яйця.", "Смажте 5 хвилин."], "calories": 260, "protein": 22, "carbs": 2,
                 "fat": 18}],
    "shoppingList": [],
}


def run(coro):
    return asyncio.run(coro)


# ---------- Anthropic ----------

class FakeAnthropicMessages:
    def __init__(self, response=None, error: Exception | None = None):
        self.response, self.error, self.calls = response, error, []

    async def create(self, **kwargs):
        self.calls.append(kwargs)
        if self.error:
            raise self.error
        return self.response


def anthropic_provider(response=None, error=None):
    messages = FakeAnthropicMessages(response, error)
    client = SimpleNamespace(beta=SimpleNamespace(messages=messages))
    return AnthropicProvider("key", "claude-opus-5-5", 30, client=client), messages


def text_response(payload, stop_reason="end_turn"):
    return SimpleNamespace(stop_reason=stop_reason, stop_details=None,
                           content=[SimpleNamespace(type="thinking", thinking=""),
                                    SimpleNamespace(type="text", text=json.dumps(payload))])


def test_anthropic_analyze_sends_image_schema_and_fallback():
    provider, messages = anthropic_provider(text_response(MEAL_JSON))
    result = run(provider.analyze_meal("QUJD"))

    call = messages.calls[0]
    assert call["model"] == "claude-opus-5-5"
    assert call["output_config"]["format"]["type"] == "json_schema"
    assert call["output_config"]["format"]["schema"]["required"][0] == "dish"
    assert call["betas"] == [FALLBACK_BETA] and call["fallbacks"] == "default"
    image = call["messages"][0]["content"][0]
    assert image == {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": "QUJD"}}
    assert "thinking" not in call and "temperature" not in call

    # Out-of-range values are clamped by validation.
    assert result.confidence == 1.0
    assert result.ingredients[0].fiber == 0.0


def test_anthropic_recipes_parse():
    provider, messages = anthropic_provider(text_response(RECIPES_JSON))
    result = run(provider.suggest_recipes(RecipeRequest(pantry=["яйця"], caloriesLeft=500, proteinLeft=40)))
    assert result.recipes[0].minutes == 10
    assert "яйця" in messages.calls[0]["messages"][0]["content"][0]["text"]


def test_anthropic_refusal():
    response = SimpleNamespace(stop_reason="refusal", stop_details=SimpleNamespace(category="bio"), content=[])
    provider, _ = anthropic_provider(response)
    with pytest.raises(ProviderRefused):
        run(provider.analyze_meal("QUJD"))


@pytest.mark.parametrize("response", [
    SimpleNamespace(stop_reason="max_tokens", stop_details=None, content=[]),
    SimpleNamespace(stop_reason="end_turn", stop_details=None, content=[SimpleNamespace(type="text", text="{oops")]),
    SimpleNamespace(stop_reason="end_turn", stop_details=None, content=[]),
])
def test_anthropic_bad_output(response):
    provider, _ = anthropic_provider(response)
    with pytest.raises(ProviderBadOutput):
        run(provider.analyze_meal("QUJD"))


def _status_error(cls, status):
    request = httpx.Request("POST", "https://api.anthropic.com/v1/messages")
    return cls("boom", response=httpx.Response(status, request=request), body=None)


@pytest.mark.parametrize("error,expected", [
    (_status_error(anthropic.RateLimitError, 429), ProviderUnavailable),
    (_status_error(anthropic.InternalServerError, 529), ProviderUnavailable),
    (_status_error(anthropic.AuthenticationError, 401), ProviderError),
    (anthropic.APIConnectionError(request=httpx.Request("POST", "https://api.anthropic.com")), ProviderUnavailable),
])
def test_anthropic_errors(error, expected):
    provider, _ = anthropic_provider(error=error)
    with pytest.raises(expected) as info:
        run(provider.analyze_meal("QUJD"))
    if expected is ProviderError:
        assert not isinstance(info.value, ProviderUnavailable)


# ---------- OpenAI ----------

def openai_provider(handler):
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return OpenAIProvider("key", "gpt-5.4-mini", 30, client=client)


def openai_output(payload):
    return {"output": [{"type": "message", "content": [{"type": "output_text", "text": json.dumps(payload)}]}]}


def test_openai_analyze_sends_strict_schema():
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["body"] = json.loads(request.content)
        return httpx.Response(200, json=openai_output(MEAL_JSON))

    result = run(openai_provider(handler).analyze_meal("QUJD"))
    fmt = seen["body"]["text"]["format"]
    assert fmt["strict"] is True and fmt["name"] == "meal_analysis"
    assert seen["body"]["input"][0]["content"][1]["image_url"] == "data:image/jpeg;base64,QUJD"
    assert result.dish == "Борщ"


def test_openai_refusal():
    def handler(request):
        return httpx.Response(200, json={"output": [{"content": [{"type": "refusal", "refusal": "no"}]}]})

    with pytest.raises(ProviderRefused):
        run(openai_provider(handler).suggest_recipes(RecipeRequest(pantry=["a"], caloriesLeft=1, proteinLeft=1)))


@pytest.mark.parametrize("status,expected", [(429, ProviderUnavailable), (503, ProviderUnavailable),
                                             (400, ProviderError)])
def test_openai_status_errors(status, expected):
    with pytest.raises(expected):
        run(openai_provider(lambda r: httpx.Response(status, json={})).analyze_meal("QUJD"))


def test_openai_timeout_is_unavailable():
    def handler(request):
        raise httpx.ReadTimeout("slow", request=request)

    with pytest.raises(ProviderUnavailable):
        run(openai_provider(handler).analyze_meal("QUJD"))


# ---------- Gemini ----------

def gemini_provider(handler):
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler), headers={"Api-Revision": API_REVISION})
    return GeminiProvider("key", "gemini-3.8-flash", 30, client=client)


def gemini_output(payload):
    return {
        "status": "completed",
        "steps": [
            {"type": "thought", "content": [{"type": "text", "text": "thinking"}]},
            {"type": "model_output", "content": [{"type": "text", "text": json.dumps(payload)}]},
        ],
    }


def test_gemini_analyze_sends_image_schema_and_no_storage():
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["url"] = str(request.url)
        seen["revision"] = request.headers["Api-Revision"]
        seen["body"] = json.loads(request.content)
        return httpx.Response(200, json=gemini_output(MEAL_JSON))

    result = run(gemini_provider(handler).analyze_meal("QUJD"))
    body = seen["body"]
    assert seen["url"].endswith("/v1beta/interactions") and seen["revision"] == API_REVISION
    assert body["model"] == "gemini-3.8-flash" and body["store"] is False
    assert body["response_format"]["mime_type"] == "application/json"
    assert body["response_format"]["schema"]["required"][0] == "dish"
    assert body["input"][1] == {"type": "image", "data": "QUJD", "mime_type": "image/jpeg"}
    assert "Ukrainian" in body["system_instruction"]
    assert result.dish == "Борщ" and result.confidence == 1.0


def test_gemini_recipes_parse():
    provider = gemini_provider(lambda r: httpx.Response(200, json=gemini_output(RECIPES_JSON)))
    result = run(provider.suggest_recipes(RecipeRequest(pantry=["яйця"], caloriesLeft=500, proteinLeft=40)))
    assert result.recipes[0].title == "Омлет"


def test_gemini_joins_text_parts():
    text = json.dumps(MEAL_JSON)
    body = {"status": "completed", "steps": [{"type": "model_output", "content": [
        {"type": "text", "text": text[:20]}, {"type": "text", "text": text[20:]}]}]}
    assert run(gemini_provider(lambda r: httpx.Response(200, json=body)).analyze_meal("QUJD")).dish == "Борщ"


@pytest.mark.parametrize("body,expected", [
    ({"status": "failed", "errors": [{"code": "safety_blocked", "message": "x"}]}, ProviderRefused),
    ({"status": "failed", "errors": [{"code": "internal", "message": "x"}]}, ProviderError),
    ({"status": "incomplete", "steps": []}, ProviderBadOutput),
    ({"status": "completed", "steps": []}, ProviderBadOutput),
    ({"status": "completed", "steps": [{"type": "model_output", "content": [{"type": "text", "text": "{oops"}]}]},
     ProviderBadOutput),
])
def test_gemini_bad_results(body, expected):
    with pytest.raises(expected):
        run(gemini_provider(lambda r: httpx.Response(200, json=body)).analyze_meal("QUJD"))


@pytest.mark.parametrize("status,expected", [(429, ProviderUnavailable), (503, ProviderUnavailable),
                                             (400, ProviderError), (403, ProviderError)])
def test_gemini_status_errors(status, expected):
    with pytest.raises(expected):
        run(gemini_provider(lambda r: httpx.Response(status, json={})).analyze_meal("QUJD"))


def test_gemini_timeout_is_unavailable():
    def handler(request):
        raise httpx.ReadTimeout("slow", request=request)

    with pytest.raises(ProviderUnavailable):
        run(gemini_provider(handler).analyze_meal("QUJD"))
