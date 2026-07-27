"""Non-blocking MongoDB lifecycle for the Vinea API."""
from __future__ import annotations

from dataclasses import dataclass

from config import Settings
from rate_limit import MongoRateLimiter
from repositories import Repositories, mongo_repositories


@dataclass(slots=True)
class DatabaseResources:
    client: object
    repositories: Repositories
    rate_limiter: MongoRateLimiter

    async def initialize(self) -> None:
        await self.repositories.ensure_indexes()
        await self.rate_limiter.ensure_indexes()

    def close(self) -> None:
        self.client.close()


def create_database_resources(settings: Settings) -> DatabaseResources:
    # Import lazily so unit tests can use in-memory repositories without MongoDB.
    from motor.motor_asyncio import AsyncIOMotorClient

    client = AsyncIOMotorClient(
        settings.mongo_url,
        serverSelectionTimeoutMS=5_000,
        uuidRepresentation="standard",
    )
    database = client[settings.db_name]
    return DatabaseResources(
        client=client,
        repositories=mongo_repositories(database),
        rate_limiter=MongoRateLimiter(database["rate_limit_buckets"]),
    )
