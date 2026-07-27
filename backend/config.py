"""Environment-backed configuration for the Vinea API."""
from __future__ import annotations

import os
from dataclasses import dataclass
from urllib.parse import urlsplit

from dotenv import load_dotenv


def _csv(name: str, default: str = "") -> tuple[str, ...]:
    return tuple(value.strip().rstrip("/") for value in os.getenv(name, default).split(",") if value.strip())


def _int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except ValueError as exc:
        raise RuntimeError(f"{name} deve essere un numero intero") from exc


@dataclass(frozen=True, slots=True)
class Settings:
    environment: str
    mongo_url: str
    db_name: str
    cors_origins: tuple[str, ...]
    redirect_origins: tuple[str, ...]
    payment_redirect_origin: str
    allow_http_local_redirects: bool
    stripe_secret_key: str
    stripe_webhook_secret: str
    stripe_mode: str
    auth_algorithm: str
    auth_signing_key: str
    auth_issuer: str | None
    auth_audience: str | None
    auth_roles_claim: str
    ai_provider: str
    openai_api_key: str
    openai_model: str
    ai_timeout_seconds: int
    ai_max_output_tokens: int
    sommelier_history_ttl_days: int
    sommelier_max_messages: int
    sommelier_context_messages: int
    sommelier_max_response_chars: int
    payments_rate_limit: int
    payments_rate_window_seconds: int
    webhook_rate_limit: int
    webhook_rate_window_seconds: int
    ai_rate_limit: int
    ai_rate_window_seconds: int

    @classmethod
    def from_env(cls) -> "Settings":
        load_dotenv()
        settings = cls(
            environment=os.getenv("APP_ENV", "development").lower(),
            mongo_url=os.getenv("MONGO_URL", "mongodb://localhost:27017"),
            db_name=os.getenv("DB_NAME", "vinea_demo"),
            cors_origins=_csv("CORS_ALLOWED_ORIGINS", "http://localhost:3000,http://localhost:5173"),
            redirect_origins=_csv("PAYMENT_REDIRECT_ALLOWED_ORIGINS", "http://localhost:3000,http://localhost:5173"),
            payment_redirect_origin=os.getenv("PAYMENT_REDIRECT_ORIGIN", "http://localhost:3000").rstrip("/"),
            allow_http_local_redirects=os.getenv("ALLOW_HTTP_LOCAL_REDIRECTS", "true").lower() == "true",
            stripe_secret_key=os.getenv("STRIPE_SECRET_KEY", ""),
            stripe_webhook_secret=os.getenv("STRIPE_WEBHOOK_SECRET", ""),
            stripe_mode=os.getenv("STRIPE_MODE", "test"),
            auth_algorithm=os.getenv("AUTH_JWT_ALGORITHM", "HS256"),
            auth_signing_key=os.getenv("AUTH_JWT_SIGNING_KEY", ""),
            auth_issuer=os.getenv("AUTH_JWT_ISSUER") or None,
            auth_audience=os.getenv("AUTH_JWT_AUDIENCE") or None,
            auth_roles_claim=os.getenv("AUTH_ROLES_CLAIM", "roles"),
            ai_provider=os.getenv("AI_PROVIDER", "disabled").lower(),
            openai_api_key=os.getenv("OPENAI_API_KEY", ""),
            openai_model=os.getenv("OPENAI_MODEL", "gpt-4.1-mini"),
            ai_timeout_seconds=_int("AI_TIMEOUT_SECONDS", 30),
            ai_max_output_tokens=_int("AI_MAX_OUTPUT_TOKENS", 800),
            sommelier_history_ttl_days=_int("SOMMELIER_HISTORY_TTL_DAYS", 30),
            sommelier_max_messages=_int("SOMMELIER_MAX_MESSAGES", 100),
            sommelier_context_messages=_int("SOMMELIER_CONTEXT_MESSAGES", 12),
            sommelier_max_response_chars=_int("SOMMELIER_MAX_RESPONSE_CHARS", 8_000),
            payments_rate_limit=_int("PAYMENTS_RATE_LIMIT", 20),
            payments_rate_window_seconds=_int("PAYMENTS_RATE_WINDOW_SECONDS", 60),
            webhook_rate_limit=_int("WEBHOOK_RATE_LIMIT", 600),
            webhook_rate_window_seconds=_int("WEBHOOK_RATE_WINDOW_SECONDS", 60),
            ai_rate_limit=_int("AI_RATE_LIMIT", 20),
            ai_rate_window_seconds=_int("AI_RATE_WINDOW_SECONDS", 60),
        )
        settings.validate()
        return settings

    def validate(self) -> None:
        if self.environment == "production":
            if not self.cors_origins or "*" in self.cors_origins:
                raise RuntimeError("CORS_ALLOWED_ORIGINS deve contenere origini esplicite in produzione")
            if not self.redirect_origins:
                raise RuntimeError("PAYMENT_REDIRECT_ALLOWED_ORIGINS è obbligatoria in produzione")
            required = {
                "STRIPE_SECRET_KEY": self.stripe_secret_key,
                "STRIPE_WEBHOOK_SECRET": self.stripe_webhook_secret,
                "AUTH_JWT_SIGNING_KEY": self.auth_signing_key,
            }
            missing = [name for name, value in required.items() if not value]
            if missing:
                raise RuntimeError(f"Configurazione di produzione incompleta: {', '.join(missing)}")
            if self.allow_http_local_redirects:
                raise RuntimeError("ALLOW_HTTP_LOCAL_REDIRECTS deve essere false in produzione")
        allowed_algorithms = {
            "HS256",
            "HS384",
            "HS512",
            "RS256",
            "RS384",
            "RS512",
            "ES256",
            "ES384",
            "ES512",
            "EdDSA",
        }
        if self.auth_algorithm not in allowed_algorithms:
            raise RuntimeError("AUTH_JWT_ALGORITHM non è consentito")
        if (
            self.environment == "production"
            and self.auth_algorithm.startswith("HS")
            and len(self.auth_signing_key.encode("utf-8")) < 32
        ):
            raise RuntimeError("AUTH_JWT_SIGNING_KEY deve avere almeno 32 byte con algoritmi HMAC")
        for origin in (*self.cors_origins, *self.redirect_origins):
            parsed = urlsplit(origin)
            if parsed.scheme not in {"http", "https"} or not parsed.netloc or parsed.path not in {"", "/"}:
                raise RuntimeError(f"Origine non valida nella configurazione: {origin}")
            is_local = (parsed.hostname or "").lower() in {"localhost", "127.0.0.1", "::1"}
            if parsed.scheme == "http" and not (self.allow_http_local_redirects and is_local):
                raise RuntimeError(f"HTTP è consentito soltanto per origini locali esplicitamente abilitate: {origin}")
        if self.payment_redirect_origin not in self.redirect_origins:
            raise RuntimeError("PAYMENT_REDIRECT_ORIGIN deve essere inclusa in PAYMENT_REDIRECT_ALLOWED_ORIGINS")
        if self.sommelier_context_messages > self.sommelier_max_messages:
            raise RuntimeError("SOMMELIER_CONTEXT_MESSAGES non può superare SOMMELIER_MAX_MESSAGES")
        for value in (
            self.sommelier_history_ttl_days,
            self.sommelier_max_messages,
            self.sommelier_context_messages,
            self.sommelier_max_response_chars,
            self.ai_timeout_seconds,
            self.ai_max_output_tokens,
            self.payments_rate_limit,
            self.payments_rate_window_seconds,
            self.webhook_rate_limit,
            self.webhook_rate_window_seconds,
            self.ai_rate_limit,
            self.ai_rate_window_seconds,
        ):
            if value <= 0:
                raise RuntimeError("Limiti e finestre temporali devono essere maggiori di zero")
