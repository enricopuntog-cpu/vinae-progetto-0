"""Rate-limit abstraction with local and MongoDB-backed implementations."""
from __future__ import annotations

import asyncio
import time
from collections import defaultdict, deque
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Protocol

from pymongo import ReturnDocument


@dataclass(frozen=True, slots=True)
class RateLimitResult:
    allowed: bool
    retry_after: int = 0


class RateLimiter(Protocol):
    async def check(self, key: str, limit: int, window_seconds: int) -> RateLimitResult: ...


class InMemoryRateLimiter:
    def __init__(self) -> None:
        self._events: dict[str, deque[float]] = defaultdict(deque)
        self._lock = asyncio.Lock()

    async def check(self, key: str, limit: int, window_seconds: int) -> RateLimitResult:
        now = time.monotonic()
        cutoff = now - window_seconds
        async with self._lock:
            events = self._events[key]
            while events and events[0] <= cutoff:
                events.popleft()
            if len(events) >= limit:
                return RateLimitResult(False, max(1, int(window_seconds - (now - events[0]))))
            events.append(now)
            return RateLimitResult(True)


class MongoRateLimiter:
    """Cross-instance fixed-window limiter using an async Mongo collection."""

    def __init__(self, collection) -> None:
        self._collection = collection

    async def ensure_indexes(self) -> None:
        await self._collection.create_index("expires_at", expireAfterSeconds=0)
        await self._collection.create_index("bucket_key", unique=True)

    async def check(self, key: str, limit: int, window_seconds: int) -> RateLimitResult:
        now = datetime.now(timezone.utc)
        bucket = int(now.timestamp()) // window_seconds
        bucket_key = f"{key}:{bucket}"
        record = await self._collection.find_one_and_update(
            {"bucket_key": bucket_key},
            {
                "$inc": {"count": 1},
                "$setOnInsert": {
                    "bucket_key": bucket_key,
                    "expires_at": now + timedelta(seconds=window_seconds * 2),
                },
            },
            upsert=True,
            return_document=ReturnDocument.AFTER,
        )
        count = int(record.get("count", 0))
        retry_after = window_seconds - (int(now.timestamp()) % window_seconds)
        return RateLimitResult(count <= limit, 0 if count <= limit else max(1, retry_after))
