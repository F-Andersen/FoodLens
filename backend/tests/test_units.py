from __future__ import annotations

import pytest

from app.auth import InvalidToken, TokenSigner
from app.config import ConfigError, Settings
from app.ratelimit import RateLimiter
from app.schemas import (
    MEAL_ANALYSIS_SCHEMA,
    RECIPE_SUGGESTIONS_SCHEMA,
    MealAnalysisOutput,
    Recipe,
    RecipeRequest,
    RecipeSuggestions,
)

from .conftest import SECRET, Clock


# ---------- config ----------

def base_env(**extra):
    return {"AI_PROVIDER": "anthropic", "ANTHROPIC_API_KEY": "k", "AUTH_SECRET": SECRET, **extra}


def test_settings_from_env():
    settings = Settings.from_env(base_env(ANALYZE_PER_HOUR="5", TRUST_PROXY_HEADERS="false"))
    assert settings.anthropic_model == "claude-opus-5-5"
    assert settings.analyze_per_hour == 5
    assert settings.trust_proxy_headers is False


@pytest.mark.parametrize("env", [
    base_env(AI_PROVIDER="gemini"),
    base_env(ANTHROPIC_API_KEY=""),
    base_env(AI_PROVIDER="openai"),
    base_env(AUTH_SECRET="short"),
    base_env(ANALYZE_PER_HOUR="abc"),
    base_env(ANALYZE_PER_HOUR="0"),
])
def test_settings_reject_invalid_env(env):
    with pytest.raises(ConfigError):
        Settings.from_env(env)


def test_openai_provider_needs_only_openai_key():
    env = {"AI_PROVIDER": "OpenAI", "OPENAI_API_KEY": "k", "AUTH_SECRET": SECRET}
    assert Settings.from_env(env).ai_provider == "openai"


# ---------- tokens ----------

def test_token_round_trip_and_expiry():
    clock = Clock()
    signer = TokenSigner(SECRET, ttl_seconds=60, clock=clock)
    token, expires = signer.issue("install-1")
    assert signer.verify(token) == "install-1"
    assert expires == int(clock.now) + 60
    clock.now += 61
    with pytest.raises(InvalidToken):
        signer.verify(token)


@pytest.mark.parametrize("token", ["", "abc", "a.b.c", "e30.AAAA"])
def test_malformed_tokens(token):
    with pytest.raises(InvalidToken):
        TokenSigner(SECRET, 60).verify(token)


# ---------- rate limiter ----------

def test_sliding_window():
    clock = Clock(0)
    limiter = RateLimiter(clock=clock)
    assert limiter.hit("k", 2, 10) is None
    clock.now = 5
    assert limiter.hit("k", 2, 10) is None
    assert limiter.hit("k", 2, 10) == pytest.approx(5)
    clock.now = 10.5
    assert limiter.hit("k", 2, 10) is None


def test_limiter_prunes_stale_keys():
    clock = Clock(0)
    limiter = RateLimiter(clock=clock, max_keys=3)
    for i in range(3):
        limiter.hit(f"k{i}", 5, 10)
    clock.now = 100_000
    limiter.hit("fresh", 5, 10)
    assert set(limiter._hits) == {"fresh"}


# ---------- schemas ----------

def test_json_schemas_match_models():
    assert set(MEAL_ANALYSIS_SCHEMA["properties"]) == set(MealAnalysisOutput.model_fields)
    assert set(RECIPE_SUGGESTIONS_SCHEMA["properties"]) == set(RecipeSuggestions.model_fields)
    recipe_schema = RECIPE_SUGGESTIONS_SCHEMA["properties"]["recipes"]["items"]
    assert set(recipe_schema["properties"]) == set(Recipe.model_fields)


def _assert_strict(schema):
    if schema.get("type") == "object":
        assert schema["additionalProperties"] is False
        assert set(schema["required"]) == set(schema["properties"])
        for child in schema["properties"].values():
            _assert_strict(child)
    if schema.get("type") == "array":
        _assert_strict(schema["items"])


@pytest.mark.parametrize("schema", [MEAL_ANALYSIS_SCHEMA, RECIPE_SUGGESTIONS_SCHEMA])
def test_schemas_are_strict(schema):
    _assert_strict(schema)


def test_recipe_request_cleans_lists():
    request = RecipeRequest(pantry=[" курка ", "", "курка", "гречка"], caloriesLeft=10, proteinLeft=0)
    assert request.pantry == ["курка", "гречка"]
