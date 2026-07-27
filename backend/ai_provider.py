"""AI provider interface and OpenAI adapter."""
from __future__ import annotations

from collections.abc import AsyncIterator
from typing import Protocol

from config import Settings


class AIProviderError(RuntimeError):
    pass


class AIProvider(Protocol):
    async def stream_text(self, *, system: str, prompt: str, request_id: str) -> AsyncIterator[str]: ...
    async def complete_text(self, *, system: str, prompt: str, request_id: str) -> str: ...


class DisabledAIProvider:
    async def stream_text(self, *, system: str, prompt: str, request_id: str) -> AsyncIterator[str]:
        del system, prompt, request_id
        raise AIProviderError("Il servizio AI non è configurato")
        yield ""  # pragma: no cover

    async def complete_text(self, *, system: str, prompt: str, request_id: str) -> str:
        del system, prompt, request_id
        raise AIProviderError("Il servizio AI non è configurato")


class OpenAIProvider:
    def __init__(self, api_key: str, model: str, *, timeout_seconds: int, max_output_tokens: int) -> None:
        if not api_key:
            raise RuntimeError("OPENAI_API_KEY è richiesta quando AI_PROVIDER=openai")
        from openai import AsyncOpenAI

        self._client = AsyncOpenAI(api_key=api_key, timeout=timeout_seconds, max_retries=2)
        self._model = model
        self._max_output_tokens = max_output_tokens

    async def stream_text(self, *, system: str, prompt: str, request_id: str) -> AsyncIterator[str]:
        try:
            stream = await self._client.chat.completions.create(
                model=self._model,
                messages=[
                    {"role": "system", "content": system},
                    {"role": "user", "content": prompt},
                ],
                stream=True,
                user=request_id,
                max_tokens=self._max_output_tokens,
            )
            async for chunk in stream:
                text = chunk.choices[0].delta.content if chunk.choices else None
                if text:
                    yield text
        except Exception as exc:
            raise AIProviderError("Il provider AI non è al momento disponibile") from exc

    async def complete_text(self, *, system: str, prompt: str, request_id: str) -> str:
        try:
            response = await self._client.chat.completions.create(
                model=self._model,
                messages=[
                    {"role": "system", "content": system},
                    {"role": "user", "content": prompt},
                ],
                user=request_id,
                max_tokens=self._max_output_tokens,
            )
            return response.choices[0].message.content or ""
        except Exception as exc:
            raise AIProviderError("Il provider AI non è al momento disponibile") from exc


def build_ai_provider(settings: Settings) -> AIProvider:
    if settings.ai_provider == "openai":
        return OpenAIProvider(
            settings.openai_api_key,
            settings.openai_model,
            timeout_seconds=settings.ai_timeout_seconds,
            max_output_tokens=settings.ai_max_output_tokens,
        )
    if settings.ai_provider == "disabled":
        return DisabledAIProvider()
    raise RuntimeError(f"AI_PROVIDER non supportato: {settings.ai_provider}")
