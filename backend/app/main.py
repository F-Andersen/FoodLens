"""FoodLens API.

Endpoints:
  GET  /health              liveness, no auth
  POST /v1/auth/register    install id -> device token (rate limited per IP)
  POST /v1/analyze          meal photo -> nutrition estimate (device token, per-install quota)
  POST /v1/recipes          pantry + remaining goals -> recipes (device token, per-install quota)

Errors are always {"error": {"code": ..., "message": ...}} with a Ukrainian message for the app.
"""

from __future__ import annotations

import base64
import binascii
import logging
import time
from collections.abc import AsyncIterator, Callable
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from . import __version__
from .auth import InvalidToken, TokenSigner
from .config import Settings
from .providers import (
    AIProvider,
    ProviderBadOutput,
    ProviderError,
    ProviderRefused,
    ProviderUnavailable,
    make_provider,
)
from .ratelimit import RateLimiter
from .schemas import (
    AnalyzeRequest,
    MealAnalysisResponse,
    RecipeRequest,
    RecipeSuggestions,
    RegisterRequest,
    TokenResponse,
)

logger = logging.getLogger("foodlens.api")

HOUR = 3600
DAY = 86_400


class APIError(Exception):
    def __init__(self, status: int, code: str, message: str, retry_after: float | None = None) -> None:
        self.status, self.code, self.message, self.retry_after = status, code, message, retry_after


def create_app(
    settings: Settings | None = None,
    provider: AIProvider | None = None,
    clock: Callable[[], float] = time.time,
) -> FastAPI:
    settings = settings or Settings.from_env()
    signer = TokenSigner(settings.auth_secret, settings.token_ttl_days * DAY, clock=clock)
    limiter = RateLimiter(clock=clock)

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        app.state.provider = provider or make_provider(settings)
        logger.info("FoodLens API %s started with provider=%s", __version__, app.state.provider.name)
        try:
            yield
        finally:
            await app.state.provider.aclose()

    app = FastAPI(title="FoodLens API", version=__version__, lifespan=lifespan,
                  docs_url=None, redoc_url=None, openapi_url=None)

    # ---------- helpers ----------

    def client_ip(request: Request) -> str:
        if settings.trust_proxy_headers:
            forwarded = request.headers.get("x-forwarded-for")
            if forwarded:
                # The reverse proxy appends the real peer address last; earlier entries are client-controlled.
                return forwarded.split(",")[-1].strip()
        return request.client.host if request.client else "unknown"

    def limit(key: str, max_hits: int, window: float, message: str) -> None:
        retry_after = limiter.hit(key, max_hits, window)
        if retry_after is not None:
            raise APIError(429, "rate_limited", message, retry_after)

    def require_device(request: Request) -> str:
        header = request.headers.get("authorization", "")
        scheme, _, token = header.partition(" ")
        if scheme.lower() != "bearer" or not token:
            raise APIError(401, "unauthorized", "Потрібна авторизація застосунку.")
        try:
            return signer.verify(token.strip())
        except InvalidToken:
            raise APIError(401, "unauthorized", "Сесія застаріла. Застосунок оновить її автоматично.") from None

    async def run_provider(call):
        try:
            return await call
        except ProviderRefused:
            raise APIError(422, "refused", "Не вдалося проаналізувати цей запит. Спробуйте інше фото або опис.") from None
        except ProviderUnavailable:
            raise APIError(503, "ai_unavailable", "AI-сервіс тимчасово недоступний. Спробуйте за хвилину.",
                           retry_after=30) from None
        except ProviderBadOutput:
            raise APIError(502, "ai_bad_output", "AI повернув некоректну відповідь. Спробуйте ще раз.") from None
        except ProviderError:
            logger.exception("Provider error")
            raise APIError(502, "ai_error", "Помилка AI-сервісу.") from None

    # ---------- error handlers ----------

    @app.exception_handler(APIError)
    async def api_error_handler(_: Request, exc: APIError) -> JSONResponse:
        headers = {"Retry-After": str(int(exc.retry_after))} if exc.retry_after else None
        return JSONResponse({"error": {"code": exc.code, "message": exc.message}}, status_code=exc.status,
                            headers=headers)

    @app.exception_handler(RequestValidationError)
    async def validation_handler(_: Request, exc: RequestValidationError) -> JSONResponse:
        logger.info("Invalid request: %s", exc.errors()[:3])
        return JSONResponse({"error": {"code": "invalid_request", "message": "Некоректний запит."}},
                            status_code=400)

    # Reject oversized bodies before reading them (base64 adds ~33%).
    max_body = int(settings.max_image_bytes * 1.4) + 16_384

    @app.middleware("http")
    async def body_size_guard(request: Request, call_next):
        length = request.headers.get("content-length")
        if length and length.isdigit() and int(length) > max_body:
            return JSONResponse({"error": {"code": "too_large", "message": "Фото завелике."}}, status_code=413)
        return await call_next(request)

    # ---------- routes ----------

    @app.get("/health")
    async def health() -> dict:
        return {"status": "ok", "version": __version__}

    @app.post("/v1/auth/register", response_model=TokenResponse)
    async def register(body: RegisterRequest, request: Request) -> TokenResponse:
        limit(f"register:{client_ip(request)}", settings.register_per_hour_per_ip, HOUR,
              "Забагато спроб. Спробуйте пізніше.")
        token, expires = signer.issue(str(body.installId))
        return TokenResponse(token=token, expiresAt=expires)

    @app.post("/v1/analyze", response_model=MealAnalysisResponse)
    async def analyze(body: AnalyzeRequest, request: Request, device: str = Depends(require_device)):
        try:
            image = base64.b64decode(body.image_base64, validate=True)
        except (binascii.Error, ValueError):
            raise APIError(400, "invalid_image", "Не вдалося прочитати фото.") from None
        if len(image) > settings.max_image_bytes:
            raise APIError(413, "too_large", "Фото завелике.")
        if not image.startswith(b"\xff\xd8\xff"):
            raise APIError(400, "invalid_image", "Підтримуються лише фото у форматі JPEG.")

        message = "Ліміт аналізу фото вичерпано. Спробуйте пізніше."
        limit(f"analyze:h:{device}", settings.analyze_per_hour, HOUR, message)
        limit(f"analyze:d:{device}", settings.analyze_per_day, DAY, message)

        output = await run_provider(request.app.state.provider.analyze_meal(body.image_base64))
        return MealAnalysisResponse.from_output(output)

    @app.post("/v1/recipes", response_model=RecipeSuggestions)
    async def recipes(body: RecipeRequest, request: Request, device: str = Depends(require_device)):
        limit(f"recipes:h:{device}", settings.recipes_per_hour, HOUR, "Ліміт підбору рецептів вичерпано. Спробуйте пізніше.")
        return await run_provider(request.app.state.provider.suggest_recipes(body))

    return app


def _configure_logging() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")


def app_factory() -> FastAPI:
    """Entry point for uvicorn: `uvicorn app.main:app_factory --factory`."""
    _configure_logging()
    return create_app()
