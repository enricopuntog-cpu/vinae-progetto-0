"""Credential-free contract tests for payments, auth and Stripe webhooks."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest

from config import Settings
from stripe_service import validate_redirect_origin


def _checkout(harness, *, user="user-a", key="request-key-0001"):
    return harness.client.post(
        "/api/payments/checkout",
        json={"lookup_key": "wine_tignanello-2019", "quantity": 1},
        headers=harness.checkout_headers(user, key),
    )


def _set_secure_production_env(monkeypatch) -> None:
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "https://app.vinea.test")
    monkeypatch.setenv("PAYMENT_REDIRECT_ALLOWED_ORIGINS", "https://app.vinea.test")
    monkeypatch.setenv("PAYMENT_REDIRECT_ORIGIN", "https://app.vinea.test")
    monkeypatch.setenv("ALLOW_HTTP_LOCAL_REDIRECTS", "false")
    monkeypatch.setenv("STRIPE_SECRET_KEY", "test-secret")
    monkeypatch.setenv("STRIPE_WEBHOOK_SECRET", "test-webhook-secret")
    monkeypatch.setenv("AUTH_JWT_SIGNING_KEY", "test-secret-at-least-32-bytes-long-value")


def test_health_is_public(make_harness):
    harness = make_harness()
    response = harness.client.get("/api/health")
    assert response.status_code == 200
    assert response.json()["ok"] is True


def test_cors_allows_only_configured_origin(make_harness):
    harness = make_harness()
    response = harness.client.get(
        "/api/health",
        headers={"Origin": "https://app.vinea.test"},
    )
    assert response.headers["access-control-allow-origin"] == "https://app.vinea.test"
    assert "access-control-allow-credentials" not in response.headers


def test_checkout_requires_auth_and_idempotency_key(make_harness):
    harness = make_harness()
    no_auth = harness.client.post(
        "/api/payments/checkout",
        json={"lookup_key": "wine_tignanello-2019", "quantity": 1},
        headers={"Idempotency-Key": "request-key-0001"},
    )
    assert no_auth.status_code == 401

    no_idempotency = harness.client.post(
        "/api/payments/checkout",
        json={"lookup_key": "wine_tignanello-2019", "quantity": 1},
        headers=harness.auth(),
    )
    assert no_idempotency.status_code == 422


def test_checkout_rejects_client_identity_and_redirect(make_harness):
    harness = make_harness()
    response = harness.client.post(
        "/api/payments/checkout",
        json={
            "lookup_key": "wine_tignanello-2019",
            "quantity": 1,
            "user_id": "victim",
            "origin_url": "https://evil.example",
            "order_id": "victim-order",
        },
        headers=harness.checkout_headers(),
    )
    assert response.status_code == 422


def test_checkout_idempotency_is_scoped_to_owner(make_harness):
    harness = make_harness()
    first = _checkout(harness, key="same-request")
    retry = _checkout(harness, key="same-request")
    assert first.status_code == retry.status_code == 200
    assert first.json() == retry.json()
    assert first.json()["order_id"].startswith("ord_")
    assert len(harness.stripe.create_calls) == 1
    assert harness.stripe.create_calls[0]["idempotency_key"] == "checkout:user-a:same-request"

    other_user = _checkout(harness, user="user-b", key="same-request")
    assert other_user.status_code == 200
    assert other_user.json()["session_id"] != first.json()["session_id"]
    assert len(harness.stripe.create_calls) == 2


def test_server_uses_only_allowlisted_redirect(make_harness):
    harness = make_harness()
    response = _checkout(harness)
    assert response.status_code == 200
    call = harness.stripe.create_calls[0]
    assert call["success_url"].startswith("https://app.vinea.test/payment/success")
    assert call["cancel_url"] == "https://app.vinea.test/payment/cancel"


def test_non_allowlisted_redirect_is_rejected():
    with pytest.raises(ValueError, match="non autorizzata"):
        validate_redirect_origin(
            "https://evil.example",
            ("https://app.vinea.test",),
            allow_http_local=False,
        )


def test_lookup_key_not_found_is_404(make_harness):
    harness = make_harness()
    response = harness.client.post(
        "/api/payments/checkout",
        json={"lookup_key": "wine_missing", "quantity": 1},
        headers=harness.checkout_headers(),
    )
    assert response.status_code == 404


def test_checkout_rejects_lookup_keys_outside_vinea_namespace(make_harness):
    harness = make_harness()
    response = harness.client.post(
        "/api/payments/checkout",
        json={"lookup_key": "subscription_internal", "quantity": 1},
        headers=harness.checkout_headers(),
    )
    assert response.status_code == 422


def test_checkout_rejects_recurring_prices(make_harness):
    harness = make_harness()
    harness.stripe.price = SimpleNamespace(
        id="price_subscription",
        recurring={"interval": "month"},
        unit_amount=12_500,
        currency="eur",
    )
    response = _checkout(harness)
    assert response.status_code == 400
    assert "una tantum" in response.json()["detail"]


def test_checkout_sanitizes_catalog_provider_errors(make_harness):
    harness = make_harness()
    harness.stripe.find_price_error = True
    response = _checkout(harness)
    assert response.status_code == 502
    assert response.json()["detail"] == "Il catalogo Stripe non è disponibile"


def test_complete_but_unpaid_session_is_not_marked_paid(make_harness):
    harness = make_harness()
    checkout = _checkout(harness)
    session_id = checkout.json()["session_id"]
    harness.stripe.retrieved[session_id] = SimpleNamespace(
        id=session_id,
        status="complete",
        payment_status="unpaid",
        subscription=None,
        payment_intent="pi_unpaid",
    )
    response = harness.client.get(
        f"/api/payments/status/{session_id}",
        headers=harness.auth(),
    )
    assert response.status_code == 200
    assert response.json() == {
        "session_id": session_id,
        "status": "processing",
        "payment_status": "unpaid",
        "order_id": checkout.json()["order_id"],
    }


def test_status_marks_paid_only_from_stripe_payment_status(make_harness):
    harness = make_harness()
    session_id = _checkout(harness).json()["session_id"]
    harness.stripe.retrieved[session_id] = SimpleNamespace(
        id=session_id,
        status="complete",
        payment_status="paid",
        subscription=None,
        payment_intent="pi_paid",
    )
    response = harness.client.get(f"/api/payments/status/{session_id}", headers=harness.auth())
    assert response.json()["payment_status"] == "paid"
    assert response.json()["status"] == "completed"


def test_payment_status_enforces_owner_or_admin(make_harness):
    harness = make_harness()
    session_id = _checkout(harness).json()["session_id"]
    forbidden = harness.client.get(f"/api/payments/status/{session_id}", headers=harness.auth("user-b"))
    assert forbidden.status_code == 403
    allowed = harness.client.get(f"/api/payments/status/{session_id}", headers=harness.auth("admin"))
    assert allowed.status_code == 200


def test_webhook_requires_valid_signature(make_harness):
    harness = make_harness()
    response = harness.client.post("/api/stripe/webhook", content=b"{}", headers={"Stripe-Signature": "bad"})
    assert response.status_code == 400


def test_signed_webhook_is_idempotent(make_harness):
    harness = make_harness()
    session_id = _checkout(harness).json()["session_id"]
    harness.stripe.event = {
        "id": "evt_paid_1",
        "type": "checkout.session.completed",
        "data": {
            "object": {
                "id": session_id,
                "payment_status": "paid",
                "payment_intent": "pi_paid",
                "subscription": None,
            }
        },
    }
    headers = {"Stripe-Signature": "valid"}
    first = harness.client.post("/api/stripe/webhook", content=b"payload", headers=headers)
    duplicate = harness.client.post("/api/stripe/webhook", content=b"payload", headers=headers)
    assert first.json() == {"status": "ok"}
    assert duplicate.json() == {"status": "duplicate"}
    status = harness.client.get(f"/api/payments/status/{session_id}", headers=harness.auth())
    assert status.json()["payment_status"] == "paid"


def test_stale_processing_webhook_can_be_reacquired(make_harness):
    harness = make_harness()
    session_id = _checkout(harness).json()["session_id"]
    harness.services.repositories.webhooks.events["evt_stale"] = {
        "event_type": "checkout.session.completed",
        "status": "processing",
        "lease_expires_at": datetime.now(timezone.utc) - timedelta(seconds=1),
        "attempts": 1,
    }
    harness.stripe.event = {
        "id": "evt_stale",
        "type": "checkout.session.completed",
        "data": {"object": {"id": session_id, "payment_status": "paid"}},
    }
    response = harness.client.post(
        "/api/stripe/webhook",
        content=b"payload",
        headers={"Stripe-Signature": "valid"},
    )
    assert response.json() == {"status": "ok"}
    event = harness.services.repositories.webhooks.events["evt_stale"]
    assert event["status"] == "processed"
    assert event["attempts"] == 2


def test_completed_webhook_does_not_promote_unpaid_session(make_harness):
    harness = make_harness()
    session_id = _checkout(harness).json()["session_id"]
    harness.stripe.event = {
        "id": "evt_unpaid_1",
        "type": "checkout.session.completed",
        "data": {"object": {"id": session_id, "payment_status": "unpaid"}},
    }
    response = harness.client.post(
        "/api/stripe/webhook",
        content=b"payload",
        headers={"Stripe-Signature": "valid"},
    )
    assert response.status_code == 200
    record = harness.services.repositories.payments.records[session_id]
    assert record["payment_status"] == "unpaid"
    assert record["status"] == "processing"


def test_refund_webhooks_distinguish_partial_and_full_refunds(make_harness):
    harness = make_harness()
    session_id = _checkout(harness).json()["session_id"]
    headers = {"Stripe-Signature": "valid"}

    harness.stripe.event = {
        "id": "evt_paid_for_refund",
        "type": "checkout.session.completed",
        "data": {
            "object": {
                "id": session_id,
                "payment_status": "paid",
                "payment_intent": "pi_refund",
            }
        },
    }
    assert harness.client.post("/api/stripe/webhook", content=b"payload", headers=headers).status_code == 200

    harness.stripe.event = {
        "id": "evt_partial_refund",
        "type": "charge.refunded",
        "data": {
            "object": {
                "payment_intent": "pi_refund",
                "amount": 12_500,
                "amount_refunded": 5_000,
                "refunded": False,
            }
        },
    }
    assert harness.client.post("/api/stripe/webhook", content=b"payload", headers=headers).status_code == 200
    record = harness.services.repositories.payments.records[session_id]
    assert record["payment_status"] == "partially_refunded"
    assert record["amount_refunded"] == 5_000

    harness.stripe.event = {
        "id": "evt_full_refund",
        "type": "charge.refunded",
        "data": {
            "object": {
                "payment_intent": "pi_refund",
                "amount": 12_500,
                "amount_refunded": 12_500,
                "refunded": True,
            }
        },
    }
    assert harness.client.post("/api/stripe/webhook", content=b"payload", headers=headers).status_code == 200
    record = harness.services.repositories.payments.records[session_id]
    assert record["payment_status"] == "refunded"
    assert record["amount_refunded"] == 12_500


def test_production_configuration_requires_security_secrets(monkeypatch):
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "https://app.vinea.test")
    monkeypatch.setenv("PAYMENT_REDIRECT_ALLOWED_ORIGINS", "https://app.vinea.test")
    monkeypatch.setenv("PAYMENT_REDIRECT_ORIGIN", "https://app.vinea.test")
    monkeypatch.setenv("ALLOW_HTTP_LOCAL_REDIRECTS", "false")
    monkeypatch.setenv("STRIPE_SECRET_KEY", "")
    monkeypatch.setenv("STRIPE_WEBHOOK_SECRET", "")
    monkeypatch.setenv("AUTH_JWT_SIGNING_KEY", "")
    with pytest.raises(RuntimeError, match="STRIPE_SECRET_KEY"):
        Settings.from_env()


def test_production_rejects_wildcard_cors(monkeypatch):
    _set_secure_production_env(monkeypatch)
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "*")
    with pytest.raises(RuntimeError, match="origini esplicite"):
        Settings.from_env()


def test_production_rejects_http_local_override(monkeypatch):
    _set_secure_production_env(monkeypatch)
    monkeypatch.setenv("ALLOW_HTTP_LOCAL_REDIRECTS", "true")
    with pytest.raises(RuntimeError, match="deve essere false"):
        Settings.from_env()


def test_auth_algorithm_none_is_rejected(monkeypatch):
    monkeypatch.setenv("AUTH_JWT_ALGORITHM", "none")
    with pytest.raises(RuntimeError, match="non è consentito"):
        Settings.from_env()
