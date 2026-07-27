"""Provider-independent authentication and authorization primitives."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Protocol

import jwt
from fastapi import HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from config import Settings


@dataclass(frozen=True, slots=True)
class AuthenticatedUser:
    id: str
    roles: frozenset[str]

    def has_role(self, role: str) -> bool:
        return role in self.roles


class TokenVerifier(Protocol):
    async def verify(self, token: str) -> AuthenticatedUser: ...


class JwtTokenVerifier:
    """JWT adapter that can be replaced by Supabase/Auth0/Cognito verification."""

    def __init__(self, settings: Settings):
        self._key = settings.auth_signing_key
        self._algorithm = settings.auth_algorithm
        self._issuer = settings.auth_issuer
        self._audience = settings.auth_audience
        self._roles_claim = settings.auth_roles_claim

    async def verify(self, token: str) -> AuthenticatedUser:
        if not self._key:
            raise HTTPException(503, "Autenticazione non configurata")
        options = {"require": ["sub", "exp"]}
        kwargs: dict[str, Any] = {
            "algorithms": [self._algorithm],
            "options": options,
        }
        if self._issuer:
            kwargs["issuer"] = self._issuer
        if self._audience:
            kwargs["audience"] = self._audience
        else:
            kwargs["options"] = {**options, "verify_aud": False}
        try:
            claims = jwt.decode(token, self._key, **kwargs)
        except jwt.PyJWTError as exc:
            raise HTTPException(401, "Token non valido", headers={"WWW-Authenticate": "Bearer"}) from exc

        raw_roles = claims.get(self._roles_claim, [])
        if isinstance(raw_roles, str):
            roles = frozenset(value for value in raw_roles.replace(",", " ").split() if value)
        elif isinstance(raw_roles, list):
            roles = frozenset(str(value) for value in raw_roles)
        else:
            roles = frozenset()
        return AuthenticatedUser(id=str(claims["sub"]), roles=roles)


bearer = HTTPBearer(auto_error=False)


async def current_user(request: Request) -> AuthenticatedUser:
    credentials: HTTPAuthorizationCredentials | None = await bearer(request)
    if not credentials or credentials.scheme.lower() != "bearer":
        raise HTTPException(401, "Autenticazione richiesta", headers={"WWW-Authenticate": "Bearer"})
    verifier: TokenVerifier = request.app.state.services.token_verifier
    return await verifier.verify(credentials.credentials)


def require_owner_or_admin(user: AuthenticatedUser, owner_id: str) -> None:
    if user.id != owner_id and not user.has_role("admin"):
        raise HTTPException(403, "Non sei autorizzato ad accedere a questa risorsa")
