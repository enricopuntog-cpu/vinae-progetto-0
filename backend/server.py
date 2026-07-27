"""Vinea Wine Club hardened FastAPI backend."""
from __future__ import annotations

from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Annotated, Any
from uuid import NAMESPACE_URL, uuid5

from fastapi import APIRouter, Depends, FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, ConfigDict, Field

from ai_provider import build_ai_provider
from ai_routes import router as ai_router
from app_services import AppServices
from auth import AuthenticatedUser, JwtTokenVerifier, current_user, require_owner_or_admin
from config import Settings
from database import create_database_resources
from stripe_service import (
    StripeGateway,
    StripeServiceError,
    StripeSignatureError,
    validate_redirect_origin,
    value,
)


def _now() -> datetime:
    return datetime.now(timezone.utc)


class CheckoutRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    lookup_key: str = Field(..., min_length=6, max_length=150, pattern=r"^wine_[A-Za-z0-9_-]+$")
    quantity: int = Field(1, ge=1, le=100)


class CheckoutResponse(BaseModel):
    checkout_url: str
    session_id: str
    order_id: str


class PaymentStatusResponse(BaseModel):
    session_id: str
    status: str
    payment_status: str
    order_id: str


async def _enforce_limit(request: Request, key: str, limit: int, window_seconds: int) -> None:
    result = await request.app.state.services.rate_limiter.check(key, limit, window_seconds)
    if not result.allowed:
        raise HTTPException(
            429,
            "Troppe richieste. Riprova più tardi.",
            headers={"Retry-After": str(result.retry_after)},
        )


def build_default_services(settings: Settings) -> AppServices:
    database_resources = create_database_resources(settings)
    return AppServices(
        settings=settings,
        repositories=database_resources.repositories,
        stripe=StripeGateway(settings.stripe_secret_key),
        ai=build_ai_provider(settings),
        token_verifier=JwtTokenVerifier(settings),
        rate_limiter=database_resources.rate_limiter,
        database_resources=database_resources,
    )


def create_app(
    *,
    settings: Settings | None = None,
    services: AppServices | None = None,
) -> FastAPI:
    resolved_settings = settings or (services.settings if services else Settings.from_env())
    resolved_services = services or build_default_services(resolved_settings)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        await app.state.services.initialize()
        try:
            yield
        finally:
            app.state.services.close()

    application = FastAPI(title="Vinea Wine Club API", lifespan=lifespan)
    application.state.services = resolved_services
    application.add_middleware(
        CORSMiddleware,
        allow_origins=list(resolved_settings.cors_origins),
        allow_credentials=False,
        allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "Idempotency-Key", "Stripe-Signature"],
    )

    api = APIRouter(prefix="/api")

    @api.get("/")
    async def root():
        return {"service": "vinea", "status": "ok"}

    @api.get("/health")
    async def health():
        return {
            "ok": True,
            "stripe_mode": resolved_settings.stripe_mode,
            "ai_provider": resolved_settings.ai_provider,
        }

    @api.post("/payments/checkout", response_model=CheckoutResponse)
    async def create_checkout(
        req: CheckoutRequest,
        request: Request,
        user: Annotated[AuthenticatedUser, Depends(current_user)],
        idempotency_key: Annotated[
            str,
            Header(alias="Idempotency-Key", min_length=8, max_length=128, pattern=r"^[A-Za-z0-9._:-]+$"),
        ],
    ):
        services = request.app.state.services
        await _enforce_limit(
            request,
            f"payments:user:{user.id}",
            services.settings.payments_rate_limit,
            services.settings.payments_rate_window_seconds,
        )
        existing = await services.repositories.payments.get_by_idempotency(user.id, idempotency_key)
        if existing:
            return CheckoutResponse(
                checkout_url=existing["checkout_url"],
                session_id=existing["session_id"],
                order_id=existing.get("order_id"),
            )

        # Deterministic per owner + idempotency key, so concurrent retries send
        # identical metadata to Stripe while the browser still cannot choose it.
        order_id = f"ord_{uuid5(NAMESPACE_URL, f'vinea:{user.id}:{idempotency_key}').hex}"
        redirect_origin = validate_redirect_origin(
            services.settings.payment_redirect_origin,
            services.settings.redirect_origins,
            allow_http_local=services.settings.allow_http_local_redirects,
        )
        try:
            price = await services.stripe.find_price(req.lookup_key)
        except StripeServiceError as exc:
            raise HTTPException(502, str(exc)) from exc
        if not price:
            raise HTTPException(404, f"Prezzo non trovato per lookup_key: {req.lookup_key}")
        if value(price, "recurring"):
            raise HTTPException(400, "Il checkout marketplace accetta soltanto prezzi una tantum")

        stripe_idempotency_key = f"checkout:{user.id}:{idempotency_key}"
        checkout_kwargs = {
            "line_items": [{"price": value(price, "id"), "quantity": req.quantity}],
            "mode": "payment",
            "success_url": f"{redirect_origin}/payment/success?session_id={{CHECKOUT_SESSION_ID}}",
            "cancel_url": f"{redirect_origin}/payment/cancel",
            "metadata": {
                "user_id": user.id,
                "lookup_key": req.lookup_key,
                "order_id": order_id,
            },
            "idempotency_key": stripe_idempotency_key,
        }
        try:
            session = await services.stripe.create_checkout(**checkout_kwargs)
        except StripeServiceError as exc:
            raise HTTPException(502, str(exc)) from exc

        session_id = str(value(session, "id"))
        checkout_url = str(value(session, "url"))
        await services.repositories.payments.create(
            {
                "session_id": session_id,
                "checkout_url": checkout_url,
                "user_id": user.id,
                "order_id": order_id,
                "lookup_key": req.lookup_key,
                "idempotency_key": idempotency_key,
                "amount": int(value(price, "unit_amount", 0) or 0) * req.quantity,
                "currency": str(value(price, "currency", "eur")),
                "status": "initiated",
                "payment_status": "pending",
                "created_at": _now(),
                "updated_at": _now(),
            }
        )
        return CheckoutResponse(checkout_url=checkout_url, session_id=session_id, order_id=order_id)

    @api.get("/payments/status/{session_id}", response_model=PaymentStatusResponse)
    async def get_status(
        session_id: str,
        request: Request,
        user: Annotated[AuthenticatedUser, Depends(current_user)],
    ):
        services = request.app.state.services
        await _enforce_limit(
            request,
            f"payments:user:{user.id}",
            services.settings.payments_rate_limit,
            services.settings.payments_rate_window_seconds,
        )
        record = await services.repositories.payments.get(session_id)
        if not record:
            raise HTTPException(404, "Transazione non trovata")
        require_owner_or_admin(user, str(record["user_id"]))

        if record.get("payment_status") not in {"paid", "refunded", "partially_refunded"}:
            try:
                stripe_session = await services.stripe.retrieve_checkout(session_id)
                stripe_payment_status = str(value(stripe_session, "payment_status", "pending"))
                if stripe_payment_status == "paid":
                    await services.repositories.payments.mark_paid(
                        session_id,
                        {
                            "stripe_subscription_id": value(stripe_session, "subscription"),
                            "stripe_payment_intent_id": value(stripe_session, "payment_intent"),
                            "updated_at": _now(),
                        },
                    )
                elif value(stripe_session, "status") == "complete":
                    await services.repositories.payments.update_unless_paid(
                        session_id,
                        {
                            "status": "processing",
                            "payment_status": stripe_payment_status,
                            "updated_at": _now(),
                        },
                    )
                record = await services.repositories.payments.get(session_id) or record
            except StripeServiceError:
                # Return last verified local state; a signed webhook remains authoritative.
                pass

        return PaymentStatusResponse(
            session_id=str(record["session_id"]),
            status=str(record["status"]),
            payment_status=str(record["payment_status"]),
            order_id=record.get("order_id"),
        )

    async def _apply_stripe_event(event_type: str, obj: dict[str, Any]) -> None:
        session_id = str(value(obj, "id", ""))
        common = {
            "stripe_subscription_id": value(obj, "subscription"),
            "stripe_payment_intent_id": value(obj, "payment_intent"),
            "updated_at": _now(),
        }
        if event_type == "checkout.session.completed":
            if value(obj, "payment_status") == "paid":
                await resolved_services.repositories.payments.mark_paid(session_id, common)
            else:
                await resolved_services.repositories.payments.update_unless_paid(
                    session_id,
                    {
                        **common,
                        "status": "processing",
                        "payment_status": str(value(obj, "payment_status", "pending")),
                    },
                )
        elif event_type == "checkout.session.async_payment_succeeded":
            await resolved_services.repositories.payments.mark_paid(session_id, common)
        elif event_type == "checkout.session.async_payment_failed":
            await resolved_services.repositories.payments.update_unless_paid(
                session_id,
                {**common, "status": "failed", "payment_status": "failed"},
            )
        elif event_type == "checkout.session.expired":
            await resolved_services.repositories.payments.update_unless_paid(
                session_id,
                {**common, "status": "expired", "payment_status": "expired"},
            )
        elif event_type == "charge.refunded":
            amount = int(value(obj, "amount", 0) or 0)
            amount_refunded = int(value(obj, "amount_refunded", 0) or 0)
            fully_refunded = bool(value(obj, "refunded", False)) or (
                amount > 0 and amount_refunded >= amount
            )
            if amount_refunded > 0:
                await resolved_services.repositories.payments.record_refund(
                    value(obj, "payment_intent"),
                    amount_refunded=amount_refunded,
                    fully_refunded=fully_refunded,
                    values={"updated_at": _now()},
                )

    @api.post("/stripe/webhook")
    async def stripe_webhook(request: Request):
        services = request.app.state.services
        payload = await request.body()
        signature = request.headers.get("stripe-signature", "")
        try:
            event = await services.stripe.construct_event(
                payload,
                signature,
                services.settings.stripe_webhook_secret,
            )
        except StripeSignatureError as exc:
            raise HTTPException(400, "Firma webhook non valida") from exc

        event_id = str(event.get("id", ""))
        event_type = str(event.get("type", ""))
        if not event_id or not event_type:
            raise HTTPException(400, "Evento Stripe non valido")
        # Only verified events consume the application bucket. Invalid traffic
        # must be filtered by the edge/WAF without starving legitimate Stripe
        # events behind a reverse proxy.
        await _enforce_limit(
            request,
            "stripe-webhook:verified",
            services.settings.webhook_rate_limit,
            services.settings.webhook_rate_window_seconds,
        )
        if not await services.repositories.webhooks.begin(event_id, event_type):
            return {"status": "duplicate"}

        try:
            event_object = event.get("data", {}).get("object", {})
            await _apply_stripe_event(event_type, event_object)
            await services.repositories.webhooks.complete(event_id)
        except Exception as exc:
            await services.repositories.webhooks.abort(event_id)
            raise HTTPException(500, "Errore temporaneo nella gestione del webhook") from exc
        return {"status": "ok"}

    api.include_router(ai_router)
    application.include_router(api)
    return application


app = create_app()
