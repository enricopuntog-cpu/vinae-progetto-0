"""Credential-free tests for the provider-independent AI routes."""
from __future__ import annotations

from datetime import datetime, timezone

from conftest import settings_factory


def _chat(harness, user: str, message: str, session_id: str = "session-001"):
    return harness.client.post(
        "/api/ai/sommelier/chat",
        json={"session_id": session_id, "message": message},
        headers=harness.auth(user),
    )


def test_ai_routes_require_auth(make_harness):
    harness = make_harness()
    response = harness.client.post(
        "/api/ai/pairing",
        json={"query": "brasato", "catalog": [{"id": "wine-1", "label": "Barolo"}]},
    )
    assert response.status_code == 401


def test_sommelier_stream_persists_bounded_owned_history(make_harness):
    harness = make_harness()
    for index in range(3):
        response = _chat(harness, "user-a", f"Messaggio {index}")
        assert response.status_code == 200
        assert '"done": true' in response.text

    history = harness.client.get(
        "/api/ai/sommelier/history/session-001",
        headers=harness.auth("user-a"),
    )
    messages = history.json()["messages"]
    assert len(messages) == 4
    assert messages[-2]["content"] == "Messaggio 2"

    other_owner = harness.client.get(
        "/api/ai/sommelier/history/session-001",
        headers=harness.auth("user-b"),
    )
    assert other_owner.status_code == 200
    assert other_owner.json()["messages"] == []

    record = harness.services.repositories.chats.records[("user-a", "session-001")]
    assert record["expires_at"] > datetime.now(timezone.utc)


def test_sommelier_response_is_capped_before_streaming_and_storage(make_harness):
    harness = make_harness(settings=settings_factory(sommelier_max_response_chars=10))

    async def long_stream(*, system: str, prompt: str, request_id: str):
        del system, prompt, request_id
        yield "x" * 25

    harness.services.ai.stream_text = long_stream
    response = _chat(harness, "user-a", "Risposta breve")
    assert response.status_code == 200
    assert "x" * 10 in response.text
    assert "x" * 11 not in response.text
    messages = harness.services.repositories.chats.records[("user-a", "session-001")]["messages"]
    assert messages[-1]["content"] == "x" * 10


def test_sommelier_reset_deletes_only_current_owner_history(make_harness):
    harness = make_harness()
    _chat(harness, "user-a", "Barolo")
    _chat(harness, "user-b", "Champagne")
    response = harness.client.delete(
        "/api/ai/sommelier/history/session-001",
        headers=harness.auth("user-a"),
    )
    assert response.json() == {"ok": True}
    assert ("user-a", "session-001") not in harness.services.repositories.chats.records
    assert ("user-b", "session-001") in harness.services.repositories.chats.records


def test_pairing_validates_catalog_ids(make_harness):
    harness = make_harness()
    response = harness.client.post(
        "/api/ai/pairing",
        json={"query": "brasato", "catalog": [{"id": "wine-1", "label": "Barolo"}]},
        headers=harness.auth(),
    )
    assert response.status_code == 200
    assert response.json()["picks"][0]["wine_id"] == "wine-1"


def test_pairing_rejects_too_few_unique_picks(make_harness):
    harness = make_harness()
    response = harness.client.post(
        "/api/ai/pairing",
        json={
            "query": "brasato",
            "catalog": [
                {"id": "wine-1", "label": "Barolo"},
                {"id": "wine-2", "label": "Brunello"},
                {"id": "wine-3", "label": "Amarone"},
            ],
        },
        headers=harness.auth(),
    )
    assert response.status_code == 502
    assert "numero richiesto" in response.json()["detail"]


def test_listing_suggestion_requires_input(make_harness):
    harness = make_harness()
    response = harness.client.post(
        "/api/ai/listing-suggestion",
        json={},
        headers=harness.auth(),
    )
    assert response.status_code == 400


def test_ai_rate_limit_returns_retry_after(make_harness):
    harness = make_harness(settings=settings_factory(ai_rate_limit=1))
    first = harness.client.get(
        "/api/ai/sommelier/history/session-001",
        headers=harness.auth(),
    )
    second = harness.client.get(
        "/api/ai/sommelier/history/session-001",
        headers=harness.auth(),
    )
    assert first.status_code == 200
    assert second.status_code == 429
    assert int(second.headers["Retry-After"]) >= 1


def test_invalid_session_identifier_is_rejected(make_harness):
    harness = make_harness()
    response = harness.client.post(
        "/api/ai/sommelier/chat",
        json={"session_id": "../../victim", "message": "Ciao"},
        headers=harness.auth(),
    )
    assert response.status_code == 422


def test_invalid_history_session_identifier_is_rejected(make_harness):
    harness = make_harness()
    headers = harness.auth()
    assert harness.client.get("/api/ai/sommelier/history/bad%21", headers=headers).status_code == 422
    assert harness.client.delete("/api/ai/sommelier/history/bad%21", headers=headers).status_code == 422
