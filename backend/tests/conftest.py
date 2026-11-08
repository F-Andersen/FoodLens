from __future__ import annotations

import base64
import uuid
from dataclasses import replace

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.providers.mock_provider import MockProvider

SECRET = "s" * 40
JPEG = base64.b64encode(b"\xff\xd8\xff\xe0" + b"\x00" * 64).decode()


class Clock:
    def __init__(self, now: float = 1_800_000_000.0) -> None:
        self.now = now

    def __call__(self) -> float:
        return self.now


@pytest.fixture
def settings() -> Settings:
    return Settings(ai_provider="mock", auth_secret=SECRET)


@pytest.fixture
def clock() -> Clock:
    return Clock()


def make_client(settings: Settings, provider=None, clock=None, **overrides) -> TestClient:
    app = create_app(replace(settings, **overrides), provider=provider or MockProvider(), clock=clock or Clock())
    return TestClient(app)


@pytest.fixture
def client(settings, clock):
    with make_client(settings, clock=clock) as c:
        yield c


def register(client: TestClient, install_id: str | None = None) -> str:
    response = client.post("/v1/auth/register", json={"installId": install_id or str(uuid.uuid4())})
    assert response.status_code == 200, response.text
    return response.json()["token"]


def auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}
