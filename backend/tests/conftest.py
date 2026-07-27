from __future__ import annotations

import json
from dataclasses import dataclass, replace
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from ai_provider import AIProvider
from app_services import AppServices
from auth import AuthenticatedUser
from config import Settings
from rate_limit import InMemoryRateLimiter
from repositories import Repositories, in_memory_repositories
from server import create_app
from stripe_service import StripeServiceError, StripeSignatureError


class FakeTokenVerifier:
    async def verify(self, token: str) -> AuthenticatedUser:
        roles = frozenset({"admin"}) if token == "admin" else frozenset({"user"})
        return AuthenticatedUser(id=token, roles=roles)


class FakeAIProvider(AIProvider):
    def __init__(self) -> None:
        self.completed = json.dumps(
            {
                "intro": "Scelta dalla tua cantina.",
                "picks": [{"wine_id": "wine-1", "reasoning": "Acidità e struttura equilibrate."}],
            }
        )

    async def stream_text(self, *, system: str, prompt: str, request_id: str):
        del system, prompt, request_id
        for part in ("Un Barolo ", "può accompagnare il piatto."):
            yield part

    async def complete_text(self, *, system: str, prompt: str, request_id: str) -> str:
        del system, prompt, request_id
        return self.completed


class FakeStripeGateway:
    def __init__(self) -> None:
        self.price = SimpleNamespace(id="price_1", recurring=None, unit_amount=12_500, currency="eur")
        self.create_calls: list[dict] = []
        self.sessions_by_key: dict[str, SimpleNamespace] = {}
        self.retrieved: dict[str, SimpleNamespace] = {}
        self.event: dict = {}
        self.find_price_error = False

    async def find_price(self, lookup_key: str):
        if self.find_price_error:
            raise StripeServiceError("Il catalogo Stripe non è disponibile")
        return None if lookup_key == "wine_missing" else self.price

    async def create_checkout(self, **kwargs):
        self.create_calls.append(kwargs)
        key = kwargs["idempotency_key"]
        if key not in self.sessions_by_key:
            number = len(self.sessions_by_key) + 1
            self.sessions_by_key[key] = SimpleNamespace(
                id=f"cs_test_{number}",
                url=f"https://checkout.stripe.test/{number}",
            )
        return self.sessions_by_key[key]

    async def retrieve_checkout(self, session_id: str):
        return self.retrieved.get(
            session_id,
            SimpleNamespace(
                id=session_id,
                status="open",
                payment_status="pending",
                subscription=None,
                payment_intent=None,
            ),
        )

    async def construct_event(self, payload: bytes, signature: str, secret: str):
        del payload, secret
        if signature != "valid":
            raise StripeSignatureError("bad signature")
        return self.event


def settings_factory(**overrides) -> Settings:
    base = Settings(
        environment="test",
        mongo_url="mongodb://unused",
        db_name="vinea_test",
        cors_origins=("https://app.vinea.test",),
        redirect_origins=("https://app.vinea.test",),
        payment_redirect_origin="https://app.vinea.test",
        allow_http_local_redirects=False,
        stripe_secret_key="sk_test_fake",
        stripe_webhook_secret="whsec_fake",
        stripe_mode="test",
        auth_algorithm="HS256",
        auth_signing_key="test-secret-at-least-32-bytes-long-value",
        auth_issuer=None,
        auth_audience=None,
        auth_roles_claim="roles",
        ai_provider="openai",
        openai_api_key="test",
        openai_model="test-model",
        ai_timeout_seconds=30,
        ai_max_output_tokens=800,
        sommelier_history_ttl_days=30,
        sommelier_max_messages=4,
        sommelier_context_messages=4,
        sommelier_max_response_chars=8_000,
        payments_rate_limit=100,
        payments_rate_window_seconds=60,
        webhook_rate_limit=100,
        webhook_rate_window_seconds=60,
        ai_rate_limit=100,
        ai_rate_window_seconds=60,
    )
    return replace(base, **overrides)


@dataclass
class TestHarness:
    client: TestClient
    services: AppServices
    stripe: FakeStripeGateway

    def auth(self, user: str = "user-a") -> dict[str, str]:
        return {"Authorization": f"Bearer {user}"}

    def checkout_headers(self, user: str = "user-a", key: str = "request-key-0001") -> dict[str, str]:
        return {**self.auth(user), "Idempotency-Key": key}


@pytest.fixture
def make_harness():
    clients: list[TestClient] = []

    def factory(*, settings: Settings | None = None, repositories: Repositories | None = None) -> TestHarness:
        resolved_settings = settings or settings_factory()
        stripe = FakeStripeGateway()
        services = AppServices(
            settings=resolved_settings,
            repositories=repositories or in_memory_repositories(),
            stripe=stripe,
            ai=FakeAIProvider(),
            token_verifier=FakeTokenVerifier(),
            rate_limiter=InMemoryRateLimiter(),
        )
        client = TestClient(create_app(settings=resolved_settings, services=services))
        client.__enter__()
        clients.append(client)
        return TestHarness(client=client, services=services, stripe=stripe)

    yield factory
    for client in clients:
        client.__exit__(None, None, None)
