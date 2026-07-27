"""Dependencies shared by API routers and replaceable in tests."""
from __future__ import annotations

from dataclasses import dataclass

from ai_provider import AIProvider
from auth import TokenVerifier
from config import Settings
from rate_limit import RateLimiter
from repositories import Repositories
from stripe_service import StripeGatewayProtocol


@dataclass(slots=True)
class AppServices:
    settings: Settings
    repositories: Repositories
    stripe: StripeGatewayProtocol
    ai: AIProvider
    token_verifier: TokenVerifier
    rate_limiter: RateLimiter
    database_resources: object | None = None

    async def initialize(self) -> None:
        if self.database_resources:
            await self.database_resources.initialize()

    def close(self) -> None:
        if self.database_resources:
            self.database_resources.close()
