"""Tests for the concrete JWT adapter behind the provider-independent interface."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import jwt
import pytest
from conftest import settings_factory
from fastapi import HTTPException

from auth import JwtTokenVerifier


@pytest.mark.asyncio
async def test_jwt_verifier_extracts_server_trusted_subject_and_roles():
    settings = settings_factory()
    verifier = JwtTokenVerifier(settings)
    token = jwt.encode(
        {
            "sub": "user-123",
            "roles": ["user", "moderator"],
            "exp": datetime.now(timezone.utc) + timedelta(minutes=5),
        },
        settings.auth_signing_key,
        algorithm=settings.auth_algorithm,
    )
    user = await verifier.verify(token)
    assert user.id == "user-123"
    assert user.roles == frozenset({"user", "moderator"})


@pytest.mark.asyncio
async def test_jwt_verifier_rejects_expired_token():
    settings = settings_factory()
    verifier = JwtTokenVerifier(settings)
    token = jwt.encode(
        {
            "sub": "user-123",
            "roles": ["admin"],
            "exp": datetime.now(timezone.utc) - timedelta(minutes=1),
        },
        settings.auth_signing_key,
        algorithm=settings.auth_algorithm,
    )
    with pytest.raises(HTTPException) as error:
        await verifier.verify(token)
    assert error.value.status_code == 401
