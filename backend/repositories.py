"""Async persistence adapters and in-memory test implementations."""
from __future__ import annotations

import copy
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Protocol

from pymongo import ReturnDocument
from pymongo.errors import DuplicateKeyError


class PaymentRepository(Protocol):
    async def create(self, record: dict[str, Any]) -> None: ...
    async def get(self, session_id: str) -> dict[str, Any] | None: ...
    async def get_by_idempotency(self, owner_id: str, idempotency_key: str) -> dict[str, Any] | None: ...
    async def mark_paid(self, session_id: str, values: dict[str, Any]) -> None: ...
    async def update_unless_paid(self, session_id: str, values: dict[str, Any]) -> None: ...
    async def record_refund(
        self,
        payment_intent_id: str | None,
        *,
        amount_refunded: int,
        fully_refunded: bool,
        values: dict[str, Any],
    ) -> None: ...


class WebhookRepository(Protocol):
    async def begin(self, event_id: str, event_type: str) -> bool: ...
    async def complete(self, event_id: str) -> None: ...
    async def abort(self, event_id: str) -> None: ...


class ChatRepository(Protocol):
    async def get_messages(self, owner_id: str, session_id: str) -> list[dict[str, Any]]: ...
    async def append_exchange(
        self,
        owner_id: str,
        session_id: str,
        user_message: str,
        assistant_message: str,
        *,
        max_messages: int,
        ttl_days: int,
    ) -> None: ...
    async def delete(self, owner_id: str, session_id: str) -> None: ...


@dataclass(slots=True)
class Repositories:
    payments: PaymentRepository
    webhooks: WebhookRepository
    chats: ChatRepository

    async def ensure_indexes(self) -> None:
        for repository in (self.payments, self.webhooks, self.chats):
            ensure = getattr(repository, "ensure_indexes", None)
            if ensure:
                await ensure()


class MongoPaymentRepository:
    def __init__(self, collection) -> None:
        self._collection = collection

    async def ensure_indexes(self) -> None:
        await self._collection.create_index("session_id", unique=True)
        await self._collection.create_index("user_id")
        await self._collection.create_index("stripe_payment_intent_id", sparse=True)
        await self._collection.create_index(
            [("user_id", 1), ("idempotency_key", 1)],
            unique=True,
            partialFilterExpression={"idempotency_key": {"$type": "string"}},
        )

    async def create(self, record: dict[str, Any]) -> None:
        await self._collection.update_one(
            {
                "user_id": record["user_id"],
                "idempotency_key": record["idempotency_key"],
            },
            {"$setOnInsert": record},
            upsert=True,
        )

    async def get(self, session_id: str) -> dict[str, Any] | None:
        return await self._collection.find_one({"session_id": session_id}, {"_id": 0})

    async def get_by_idempotency(self, owner_id: str, idempotency_key: str) -> dict[str, Any] | None:
        return await self._collection.find_one(
            {"user_id": owner_id, "idempotency_key": idempotency_key},
            {"_id": 0},
        )

    async def mark_paid(self, session_id: str, values: dict[str, Any]) -> None:
        await self._collection.update_one(
            {"session_id": session_id, "payment_status": {"$nin": ["refunded", "partially_refunded"]}},
            {"$set": {**values, "status": "completed", "payment_status": "paid"}},
        )

    async def update_unless_paid(self, session_id: str, values: dict[str, Any]) -> None:
        await self._collection.update_one(
            {
                "session_id": session_id,
                "payment_status": {"$nin": ["paid", "partially_refunded", "refunded"]},
            },
            {"$set": values},
        )

    async def record_refund(
        self,
        payment_intent_id: str | None,
        *,
        amount_refunded: int,
        fully_refunded: bool,
        values: dict[str, Any],
    ) -> None:
        if payment_intent_id:
            refund_status = "refunded" if fully_refunded else "partially_refunded"
            await self._collection.update_one(
                {"stripe_payment_intent_id": payment_intent_id},
                {
                    "$set": {
                        **values,
                        "amount_refunded": amount_refunded,
                        "status": refund_status,
                        "payment_status": refund_status,
                    }
                },
            )


class MongoWebhookRepository:
    _lease_duration = timedelta(minutes=5)

    def __init__(self, collection) -> None:
        self._collection = collection

    async def ensure_indexes(self) -> None:
        await self._collection.create_index("event_id", unique=True)
        await self._collection.create_index("created_at")

    async def begin(self, event_id: str, event_type: str) -> bool:
        now = datetime.now(timezone.utc)
        try:
            record = await self._collection.find_one_and_update(
                {
                    "event_id": event_id,
                    "$or": [
                        {"status": "failed"},
                        {"status": "processing", "lease_expires_at": {"$lte": now}},
                        {"status": "processing", "lease_expires_at": {"$exists": False}},
                    ],
                },
                {
                    "$setOnInsert": {"event_id": event_id, "created_at": now},
                    "$set": {
                        "event_type": event_type,
                        "status": "processing",
                        "lease_expires_at": now + self._lease_duration,
                        "updated_at": now,
                    },
                    "$inc": {"attempts": 1},
                },
                upsert=True,
                return_document=ReturnDocument.AFTER,
            )
            return record is not None
        except DuplicateKeyError:
            # A processed event, or one with an active lease, intentionally
            # does not match the acquisition query and collides on event_id.
            return False

    async def complete(self, event_id: str) -> None:
        await self._collection.update_one(
            {"event_id": event_id, "status": "processing"},
            {
                "$set": {"status": "processed", "processed_at": datetime.now(timezone.utc)},
                "$unset": {"lease_expires_at": ""},
            },
        )

    async def abort(self, event_id: str) -> None:
        # A failed handler must be retryable by Stripe.
        await self._collection.delete_one({"event_id": event_id, "status": "processing"})


class MongoChatRepository:
    def __init__(self, collection) -> None:
        self._collection = collection

    async def ensure_indexes(self) -> None:
        await self._collection.create_index([("owner_id", 1), ("session_id", 1)], unique=True)
        await self._collection.create_index("expires_at", expireAfterSeconds=0)

    async def get_messages(self, owner_id: str, session_id: str) -> list[dict[str, Any]]:
        doc = await self._collection.find_one(
            {"owner_id": owner_id, "session_id": session_id},
            {"_id": 0, "messages": 1},
        )
        return list((doc or {}).get("messages", []))

    async def append_exchange(
        self,
        owner_id: str,
        session_id: str,
        user_message: str,
        assistant_message: str,
        *,
        max_messages: int,
        ttl_days: int,
    ) -> None:
        now = datetime.now(timezone.utc)
        messages = [
            {"role": "user", "content": user_message, "at": now},
            {"role": "assistant", "content": assistant_message, "at": now},
        ]
        await self._collection.update_one(
            {"owner_id": owner_id, "session_id": session_id},
            {
                "$setOnInsert": {"owner_id": owner_id, "session_id": session_id, "created_at": now},
                "$push": {"messages": {"$each": messages, "$slice": -max_messages}},
                "$set": {"updated_at": now, "expires_at": now + timedelta(days=ttl_days)},
            },
            upsert=True,
        )

    async def delete(self, owner_id: str, session_id: str) -> None:
        await self._collection.delete_one({"owner_id": owner_id, "session_id": session_id})


class InMemoryPaymentRepository:
    def __init__(self) -> None:
        self.records: dict[str, dict[str, Any]] = {}

    async def create(self, record: dict[str, Any]) -> None:
        self.records[record["session_id"]] = copy.deepcopy(record)

    async def get(self, session_id: str) -> dict[str, Any] | None:
        record = self.records.get(session_id)
        return copy.deepcopy(record) if record else None

    async def get_by_idempotency(self, owner_id: str, idempotency_key: str) -> dict[str, Any] | None:
        for record in self.records.values():
            if record.get("user_id") == owner_id and record.get("idempotency_key") == idempotency_key:
                return copy.deepcopy(record)
        return None

    async def mark_paid(self, session_id: str, values: dict[str, Any]) -> None:
        record = self.records.get(session_id)
        if record and record.get("payment_status") not in {"refunded", "partially_refunded"}:
            record.update(values, status="completed", payment_status="paid")

    async def update_unless_paid(self, session_id: str, values: dict[str, Any]) -> None:
        record = self.records.get(session_id)
        if record and record.get("payment_status") not in {"paid", "partially_refunded", "refunded"}:
            record.update(values)

    async def record_refund(
        self,
        payment_intent_id: str | None,
        *,
        amount_refunded: int,
        fully_refunded: bool,
        values: dict[str, Any],
    ) -> None:
        for record in self.records.values():
            if payment_intent_id and record.get("stripe_payment_intent_id") == payment_intent_id:
                refund_status = "refunded" if fully_refunded else "partially_refunded"
                record.update(
                    values,
                    amount_refunded=amount_refunded,
                    status=refund_status,
                    payment_status=refund_status,
                )


class InMemoryWebhookRepository:
    _lease_duration = timedelta(minutes=5)

    def __init__(self) -> None:
        self.events: dict[str, dict[str, Any]] = {}

    async def begin(self, event_id: str, event_type: str) -> bool:
        now = datetime.now(timezone.utc)
        existing = self.events.get(event_id)
        if existing:
            lease_expires_at = existing.get("lease_expires_at")
            lease_expired = lease_expires_at is None or lease_expires_at <= now
            if existing.get("status") != "failed" and not (
                existing.get("status") == "processing" and lease_expired
            ):
                return False
        self.events[event_id] = {
            "event_type": event_type,
            "status": "processing",
            "lease_expires_at": now + self._lease_duration,
            "attempts": int((existing or {}).get("attempts", 0)) + 1,
        }
        return True

    async def complete(self, event_id: str) -> None:
        self.events[event_id]["status"] = "processed"
        self.events[event_id].pop("lease_expires_at", None)

    async def abort(self, event_id: str) -> None:
        if self.events.get(event_id, {}).get("status") == "processing":
            self.events.pop(event_id, None)


class InMemoryChatRepository:
    def __init__(self) -> None:
        self.records: dict[tuple[str, str], dict[str, Any]] = {}

    async def get_messages(self, owner_id: str, session_id: str) -> list[dict[str, Any]]:
        return copy.deepcopy(self.records.get((owner_id, session_id), {}).get("messages", []))

    async def append_exchange(
        self,
        owner_id: str,
        session_id: str,
        user_message: str,
        assistant_message: str,
        *,
        max_messages: int,
        ttl_days: int,
    ) -> None:
        key = (owner_id, session_id)
        now = datetime.now(timezone.utc)
        record = self.records.setdefault(key, {"messages": []})
        record["messages"].extend(
            [
                {"role": "user", "content": user_message, "at": now},
                {"role": "assistant", "content": assistant_message, "at": now},
            ]
        )
        record["messages"] = record["messages"][-max_messages:]
        record["expires_at"] = now + timedelta(days=ttl_days)

    async def delete(self, owner_id: str, session_id: str) -> None:
        self.records.pop((owner_id, session_id), None)


def in_memory_repositories() -> Repositories:
    return Repositories(
        payments=InMemoryPaymentRepository(),
        webhooks=InMemoryWebhookRepository(),
        chats=InMemoryChatRepository(),
    )


def mongo_repositories(database) -> Repositories:
    return Repositories(
        payments=MongoPaymentRepository(database["payment_transactions"]),
        webhooks=MongoWebhookRepository(database["stripe_webhook_events"]),
        chats=MongoChatRepository(database["ai_chat_sessions"]),
    )
