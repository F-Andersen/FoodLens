"""In-memory sliding-window rate limiter.

Good for a single API process on one VPS. With several replicas, move the counters to Redis.
"""

from __future__ import annotations

import time
from collections import deque
from collections.abc import Callable


class RateLimiter:
    def __init__(self, clock: Callable[[], float] = time.monotonic, max_keys: int = 50_000) -> None:
        self._clock = clock
        self._max_keys = max_keys
        self._hits: dict[str, deque[float]] = {}

    def hit(self, key: str, limit: int, window_seconds: float) -> float | None:
        """Records a hit. Returns None if allowed, or seconds until the next allowed hit."""
        now = self._clock()
        hits = self._hits.setdefault(key, deque())
        while hits and hits[0] <= now - window_seconds:
            hits.popleft()
        if len(hits) >= limit:
            return max(1.0, hits[0] + window_seconds - now)
        hits.append(now)
        if len(self._hits) > self._max_keys:
            self._prune(now)
        return None

    def _prune(self, now: float, horizon: float = 86_400) -> None:
        for key in [k for k, v in self._hits.items() if not v or v[-1] <= now - horizon]:
            del self._hits[key]
