"""Async Stripe adapter and payment safety helpers."""
from __future__ import annotations

import asyncio
from dataclasses import dataclass
from typing import Any, Protocol
from urllib.parse import urlsplit, urlunsplit


class StripeServiceError(RuntimeError):
    pass


class StripeSignatureError(StripeServiceError):
    pass


class StripeGatewayProtocol(Protocol):
    async def find_price(self, lookup_key: str) -> Any | None: ...
    async def create_checkout(self, **kwargs) -> Any: ...
    async def retrieve_checkout(self, session_id: str) -> Any: ...
    async def construct_event(self, payload: bytes, signature: str, secret: str) -> dict[str, Any]: ...


class StripeGateway:
    """Wrap the synchronous Stripe SDK so FastAPI's event loop is never blocked."""

    def __init__(self, secret_key: str) -> None:
        self._secret_key = secret_key

    def _stripe(self):
        import stripe

        stripe.api_key = self._secret_key
        return stripe

    async def find_price(self, lookup_key: str) -> Any | None:
        stripe = self._stripe()

        def run():
            prices = stripe.Price.list(lookup_keys=[lookup_key], active=True, limit=1).data
            return prices[0] if prices else None

        try:
            return await asyncio.to_thread(run)
        except stripe.error.StripeError as exc:
            raise StripeServiceError("Il catalogo Stripe non è disponibile") from exc

    async def create_checkout(self, **kwargs) -> Any:
        stripe = self._stripe()

        def run():
            return stripe.checkout.Session.create(
                **kwargs,
                automatic_tax={"enabled": True},
                billing_address_collection="required",
            )

        try:
            return await asyncio.to_thread(run)
        except stripe.error.StripeError as exc:
            raise StripeServiceError("Stripe Checkout non è disponibile") from exc

    async def retrieve_checkout(self, session_id: str) -> Any:
        stripe = self._stripe()
        try:
            return await asyncio.to_thread(stripe.checkout.Session.retrieve, session_id)
        except stripe.error.StripeError as exc:
            raise StripeServiceError("Impossibile verificare lo stato con Stripe") from exc

    async def construct_event(self, payload: bytes, signature: str, secret: str) -> dict[str, Any]:
        stripe = self._stripe()
        if not secret:
            raise StripeSignatureError("Webhook Stripe non configurato")
        try:
            event = await asyncio.to_thread(stripe.Webhook.construct_event, payload, signature, secret)
            return event.to_dict_recursive() if hasattr(event, "to_dict_recursive") else dict(event)
        except (ValueError, stripe.error.SignatureVerificationError) as exc:
            raise StripeSignatureError("Firma webhook non valida") from exc


def normalize_allowed_origin(origin: str, *, allow_http_local: bool) -> str:
    parsed = urlsplit(origin.strip())
    host = (parsed.hostname or "").lower()
    if (
        not parsed.scheme
        or not parsed.netloc
        or parsed.username
        or parsed.password
        or parsed.path not in {"", "/"}
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError("L'URL di ritorno deve essere una semplice origine")
    is_local = host in {"localhost", "127.0.0.1", "::1"}
    if parsed.scheme != "https" and not (allow_http_local and parsed.scheme == "http" and is_local):
        raise ValueError("L'URL di ritorno deve usare HTTPS")
    if parsed.port:
        netloc = f"[{host}]:{parsed.port}" if ":" in host else f"{host}:{parsed.port}"
    else:
        netloc = f"[{host}]" if ":" in host else host
    return urlunsplit((parsed.scheme.lower(), netloc, "", "", ""))


def validate_redirect_origin(origin: str, allowed: tuple[str, ...], *, allow_http_local: bool) -> str:
    normalized = normalize_allowed_origin(origin, allow_http_local=allow_http_local)
    normalized_allowed = {
        normalize_allowed_origin(candidate, allow_http_local=allow_http_local) for candidate in allowed
    }
    if normalized not in normalized_allowed:
        raise ValueError("Origine di ritorno non autorizzata")
    return normalized


def value(obj: Any, key: str, default: Any = None) -> Any:
    if isinstance(obj, dict):
        return obj.get(key, default)
    return getattr(obj, key, default)


@dataclass(frozen=True, slots=True)
class CheckoutResult:
    checkout_url: str
    session_id: str
