"""Settings read from environment variables. Secrets never have defaults."""

from __future__ import annotations

import os
from collections.abc import Mapping
from dataclasses import dataclass

PROVIDERS = ("anthropic", "openai", "mock")


class ConfigError(RuntimeError):
    """Raised at startup when the environment is incomplete or invalid."""


@dataclass(frozen=True)
class Settings:
    ai_provider: str = "anthropic"
    anthropic_api_key: str | None = None
    anthropic_model: str = "claude-opus-5-5"
    openai_api_key: str | None = None
    openai_model: str = "gpt-5.4-mini"
    ai_timeout_seconds: float = 90.0

    # Device tokens are HMAC-signed with this secret (at least 32 characters).
    auth_secret: str = ""
    token_ttl_days: int = 30

    # Decoded JPEG size limit. The app uploads ~1280 px photos, typically 150–400 KB.
    max_image_bytes: int = 3_000_000

    analyze_per_hour: int = 30
    analyze_per_day: int = 150
    recipes_per_hour: int = 20
    register_per_hour_per_ip: int = 10

    # Behind Caddy the real client address is the last X-Forwarded-For entry.
    trust_proxy_headers: bool = True

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> "Settings":
        env = os.environ if env is None else env
        defaults = cls()

        def get(name: str, default: str | None = None) -> str | None:
            value = env.get(name)
            return value.strip() if value and value.strip() else default

        def get_int(name: str, default: int) -> int:
            raw = get(name)
            try:
                return int(raw) if raw is not None else default
            except ValueError as exc:
                raise ConfigError(f"{name} must be an integer") from exc

        def get_float(name: str, default: float) -> float:
            raw = get(name)
            try:
                return float(raw) if raw is not None else default
            except ValueError as exc:
                raise ConfigError(f"{name} must be a number") from exc

        settings = cls(
            ai_provider=(get("AI_PROVIDER", defaults.ai_provider) or "").lower(),
            anthropic_api_key=get("ANTHROPIC_API_KEY"),
            anthropic_model=get("ANTHROPIC_MODEL", defaults.anthropic_model) or defaults.anthropic_model,
            openai_api_key=get("OPENAI_API_KEY"),
            openai_model=get("OPENAI_MODEL", defaults.openai_model) or defaults.openai_model,
            ai_timeout_seconds=get_float("AI_TIMEOUT_SECONDS", defaults.ai_timeout_seconds),
            auth_secret=get("AUTH_SECRET", "") or "",
            token_ttl_days=get_int("TOKEN_TTL_DAYS", defaults.token_ttl_days),
            max_image_bytes=get_int("MAX_IMAGE_BYTES", defaults.max_image_bytes),
            analyze_per_hour=get_int("ANALYZE_PER_HOUR", defaults.analyze_per_hour),
            analyze_per_day=get_int("ANALYZE_PER_DAY", defaults.analyze_per_day),
            recipes_per_hour=get_int("RECIPES_PER_HOUR", defaults.recipes_per_hour),
            register_per_hour_per_ip=get_int("REGISTER_PER_HOUR_PER_IP", defaults.register_per_hour_per_ip),
            trust_proxy_headers=(get("TRUST_PROXY_HEADERS", "true") or "true").lower() in ("1", "true", "yes"),
        )
        settings.validate()
        return settings

    def validate(self) -> None:
        if self.ai_provider not in PROVIDERS:
            raise ConfigError(f"AI_PROVIDER must be one of {', '.join(PROVIDERS)}")
        if self.ai_provider == "anthropic" and not self.anthropic_api_key:
            raise ConfigError("ANTHROPIC_API_KEY is required when AI_PROVIDER=anthropic")
        if self.ai_provider == "openai" and not self.openai_api_key:
            raise ConfigError("OPENAI_API_KEY is required when AI_PROVIDER=openai")
        if len(self.auth_secret) < 32:
            raise ConfigError("AUTH_SECRET must be at least 32 characters (try: openssl rand -hex 32)")
        for name in ("token_ttl_days", "max_image_bytes", "analyze_per_hour", "analyze_per_day",
                     "recipes_per_hour", "register_per_hour_per_ip"):
            if getattr(self, name) <= 0:
                raise ConfigError(f"{name.upper()} must be positive")
