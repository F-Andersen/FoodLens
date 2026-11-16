"""Anonymous per-install device tokens.

The app registers once with a random install id and receives a token signed with HMAC-SHA256.
Every AI request must carry it, so quotas apply per install and the server is not an open proxy
to the AI provider. Tokens are stateless: rotating AUTH_SECRET revokes all of them at once.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import time
from collections.abc import Callable
from dataclasses import dataclass


class InvalidToken(Exception):
    pass


def _b64encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _b64decode(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


@dataclass(frozen=True)
class TokenSigner:
    secret: str
    ttl_seconds: int
    clock: Callable[[], float] = time.time

    def issue(self, subject: str) -> tuple[str, int]:
        now = int(self.clock())
        expires = now + self.ttl_seconds
        payload = _b64encode(json.dumps({"v": 1, "sub": subject, "iat": now, "exp": expires},
                                        separators=(",", ":")).encode())
        return f"{payload}.{self._sign(payload)}", expires

    def verify(self, token: str) -> str:
        """Returns the subject (install id) or raises InvalidToken."""
        try:
            payload, signature = token.split(".", 1)
        except ValueError as exc:
            raise InvalidToken("malformed") from exc
        if not hmac.compare_digest(signature, self._sign(payload)):
            raise InvalidToken("bad signature")
        try:
            claims = json.loads(_b64decode(payload))
        except (ValueError, UnicodeDecodeError) as exc:
            raise InvalidToken("bad payload") from exc
        if claims.get("v") != 1 or not isinstance(claims.get("sub"), str):
            raise InvalidToken("bad claims")
        if int(claims.get("exp", 0)) <= self.clock():
            raise InvalidToken("expired")
        return claims["sub"]

    def _sign(self, payload: str) -> str:
        return _b64encode(hmac.new(self.secret.encode(), payload.encode(), hashlib.sha256).digest())
