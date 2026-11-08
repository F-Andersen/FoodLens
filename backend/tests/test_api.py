from __future__ import annotations

import base64

import pytest

from app.providers import ProviderBadOutput, ProviderError, ProviderRefused, ProviderUnavailable
from app.providers.mock_provider import MockProvider

from .conftest import JPEG, auth, make_client, register

RECIPE_BODY = {"pantry": ["курка", "гречка"], "mealType": "lunch", "caloriesLeft": 900, "proteinLeft": 60}


def test_health_needs_no_auth(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_docs_are_not_exposed(client):
    assert client.get("/docs").status_code == 404
    assert client.get("/openapi.json").status_code == 404


# ---------- auth ----------

def test_register_returns_token_with_expiry(client, clock):
    response = client.post("/v1/auth/register", json={"installId": "7c9e6679-7425-40de-944b-e07fc1f90ae7"})
    body = response.json()
    assert response.status_code == 200
    assert body["token"].count(".") == 1
    assert body["expiresAt"] == int(clock.now) + 30 * 86_400


def test_register_rejects_non_uuid(client):
    response = client.post("/v1/auth/register", json={"installId": "not-a-uuid"})
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "invalid_request"


@pytest.mark.parametrize("headers", [{}, {"Authorization": "Bearer nope"}, {"Authorization": "Basic abc"}])
def test_analyze_requires_valid_token(client, headers):
    response = client.post("/v1/analyze", json={"image_base64": JPEG}, headers=headers)
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"


def test_tampered_token_is_rejected(client):
    token = register(client)
    payload, signature = token.split(".")
    forged = payload[:-2] + ("AA" if payload[-2:] != "AA" else "BB") + "." + signature
    assert client.post("/v1/analyze", json={"image_base64": JPEG}, headers=auth(forged)).status_code == 401


def test_expired_token_is_rejected(settings, clock):
    with make_client(settings, clock=clock) as client:
        token = register(client)
        clock.now += 31 * 86_400
        response = client.post("/v1/analyze", json={"image_base64": JPEG}, headers=auth(token))
    assert response.status_code == 401


def test_token_from_other_secret_is_rejected(settings, clock):
    with make_client(settings, clock=clock) as first:
        token = register(first)
    with make_client(settings, clock=clock, auth_secret="x" * 40) as second:
        assert second.post("/v1/analyze", json={"image_base64": JPEG}, headers=auth(token)).status_code == 401


def test_register_is_rate_limited_per_ip(settings, clock):
    with make_client(settings, clock=clock, register_per_hour_per_ip=2) as client:
        register(client)
        register(client)
        response = client.post("/v1/auth/register", json={"installId": "7c9e6679-7425-40de-944b-e07fc1f90ae7"})
        assert response.status_code == 429
        assert int(response.headers["Retry-After"]) > 0
        # A different client behind the proxy has its own budget.
        other = client.post("/v1/auth/register", json={"installId": "7c9e6679-7425-40de-944b-e07fc1f90ae7"},
                            headers={"X-Forwarded-For": "203.0.113.9"})
        assert other.status_code == 200
        clock.now += 3601
        register(client)


def test_spoofed_forwarded_prefix_does_not_bypass_limit(settings, clock):
    with make_client(settings, clock=clock, register_per_hour_per_ip=1) as client:
        headers = {"X-Forwarded-For": "1.1.1.1, 198.51.100.7"}
        assert client.post("/v1/auth/register", json={"installId": "7c9e6679-7425-40de-944b-e07fc1f90ae7"},
                           headers=headers).status_code == 200
        spoofed = {"X-Forwarded-For": "9.9.9.9, 198.51.100.7"}
        assert client.post("/v1/auth/register", json={"installId": "7c9e6679-7425-40de-944b-e07fc1f90ae7"},
                           headers=spoofed).status_code == 429


# ---------- analyze ----------

def test_analyze_returns_ingredients_with_ids(client):
    token = register(client)
    response = client.post("/v1/analyze", json={"image_base64": JPEG}, headers=auth(token))
    assert response.status_code == 200
    body = response.json()
    assert body["dish"] == "Гречка з куркою"
    assert set(body) == {"dish", "estimatedGrams", "caloriesPer100g", "protein", "carbs", "fat", "fiber",
                         "confidence", "ingredients"}
    ids = [item["id"] for item in body["ingredients"]]
    assert len(ids) == 2 and len(set(ids)) == 2


def test_analyze_rejects_invalid_base64(client):
    token = register(client)
    response = client.post("/v1/analyze", json={"image_base64": "!!!not base64!!!"}, headers=auth(token))
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "invalid_image"


def test_analyze_rejects_non_jpeg(client):
    token = register(client)
    png = base64.b64encode(b"\x89PNG\r\n\x1a\n" + b"\x00" * 64).decode()
    response = client.post("/v1/analyze", json={"image_base64": png}, headers=auth(token))
    assert response.status_code == 400


def test_analyze_rejects_large_image(settings, clock):
    with make_client(settings, clock=clock, max_image_bytes=1000) as client:
        token = register(client)
        big = base64.b64encode(b"\xff\xd8\xff" + b"\x00" * 1000).decode()
        response = client.post("/v1/analyze", json={"image_base64": big}, headers=auth(token))
        assert response.status_code == 413


def test_body_size_guard_rejects_before_parsing(settings, clock):
    with make_client(settings, clock=clock, max_image_bytes=1000) as client:
        token = register(client)
        response = client.post("/v1/analyze", content=b"x" * 20_000,
                               headers={**auth(token), "Content-Type": "application/json"})
        assert response.status_code == 413


def test_analyze_quota_is_per_install(settings, clock):
    with make_client(settings, clock=clock, analyze_per_hour=2) as client:
        first, second = register(client), register(client)
        for _ in range(2):
            assert client.post("/v1/analyze", json={"image_base64": JPEG}, headers=auth(first)).status_code == 200
        limited = client.post("/v1/analyze", json={"image_base64": JPEG}, headers=auth(first))
        assert limited.status_code == 429
        assert limited.json()["error"]["code"] == "rate_limited"
        assert client.post("/v1/analyze", json={"image_base64": JPEG}, headers=auth(second)).status_code == 200


def test_analyze_daily_quota(settings, clock):
    with make_client(settings, clock=clock, analyze_per_hour=100, analyze_per_day=3) as client:
        token = register(client)
        for _ in range(3):
            assert client.post("/v1/analyze", json={"image_base64": JPEG}, headers=auth(token)).status_code == 200
            clock.now += 3601
        assert client.post("/v1/analyze", json={"image_base64": JPEG}, headers=auth(token)).status_code == 429


# ---------- recipes ----------

def test_recipes_returns_suggestions(client):
    token = register(client)
    response = client.post("/v1/recipes", json=RECIPE_BODY, headers=auth(token))
    assert response.status_code == 200
    body = response.json()
    assert body["recipes"][0]["mealType"] == "lunch"
    assert body["shoppingList"] == ["зелень"]


@pytest.mark.parametrize("change", [
    {"pantry": []},
    {"caloriesLeft": -5},
    {"mealType": "brunch"},
    {"diet": "keto"},
    {"pantry": ["x"] * 51},
])
def test_recipes_validates_input(client, change):
    token = register(client)
    response = client.post("/v1/recipes", json={**RECIPE_BODY, **change}, headers=auth(token))
    assert response.status_code == 400


def test_recipes_requires_token(client):
    assert client.post("/v1/recipes", json=RECIPE_BODY).status_code == 401


# ---------- provider failures ----------

class FailingProvider(MockProvider):
    def __init__(self, error: Exception) -> None:
        self.error = error

    async def analyze_meal(self, jpeg_base64):
        raise self.error

    async def suggest_recipes(self, request):
        raise self.error


@pytest.mark.parametrize("error,status,code", [
    (ProviderRefused("cyber"), 422, "refused"),
    (ProviderUnavailable("429"), 503, "ai_unavailable"),
    (ProviderBadOutput("json"), 502, "ai_bad_output"),
    (ProviderError("401"), 502, "ai_error"),
])
def test_provider_errors_are_mapped_without_leaking_details(settings, clock, error, status, code):
    with make_client(settings, provider=FailingProvider(error), clock=clock) as client:
        token = register(client)
        for path, body in (("/v1/analyze", {"image_base64": JPEG}), ("/v1/recipes", RECIPE_BODY)):
            response = client.post(path, json=body, headers=auth(token))
            assert response.status_code == status
            assert response.json()["error"]["code"] == code
            assert str(error) not in response.json()["error"]["message"]
