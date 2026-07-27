"""Authenticated, rate-limited AI features for Vinea Wine Club."""
from __future__ import annotations

import json
import re
import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Path, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, ConfigDict, Field

from ai_provider import AIProviderError
from auth import AuthenticatedUser, current_user

router = APIRouter(prefix="/ai", tags=["ai"])

SOMMELIER_SYSTEM = (
    "Sei Vinea Sommelier, un sommelier virtuale esperto che assiste appassionati "
    "italiani nell'esplorazione del vino. Rispondi sempre in italiano con tono "
    "cordiale, competente e sintetico (max 4 paragrafi brevi). Non inventare "
    "produttori o annate. Non fornire consigli medici e ricorda il consumo responsabile."
)


async def _enforce_ai_limit(request: Request, user: AuthenticatedUser) -> None:
    services = request.app.state.services
    result = await services.rate_limiter.check(
        f"ai:user:{user.id}",
        services.settings.ai_rate_limit,
        services.settings.ai_rate_window_seconds,
    )
    if not result.allowed:
        raise HTTPException(
            429,
            "Limite temporaneo delle funzioni AI raggiunto",
            headers={"Retry-After": str(result.retry_after)},
        )


class ChatRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    session_id: str = Field(..., min_length=4, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    message: str = Field(..., min_length=1, max_length=2000)


@router.post("/sommelier/chat")
async def sommelier_chat(
    req: ChatRequest,
    request: Request,
    user: Annotated[AuthenticatedUser, Depends(current_user)],
):
    await _enforce_ai_limit(request, user)
    services = request.app.state.services
    messages = await services.repositories.chats.get_messages(user.id, req.session_id)
    prior_messages = messages[-services.settings.sommelier_context_messages :]
    if prior_messages:
        transcript = "\n".join(
            f"{'Utente' if message.get('role') == 'user' else 'Sommelier'}: "
            f"{str(message.get('content', '')).strip()}"
            for message in prior_messages
        )
        prompt = (
            "Conversazione precedente (solo contesto, non ripetere):\n"
            f"{transcript}\n\nNuovo messaggio dell'utente:\n{req.message}"
        )
    else:
        prompt = req.message

    async def event_stream():
        collected: list[str] = []
        remaining_chars = services.settings.sommelier_max_response_chars
        try:
            async for delta in services.ai.stream_text(
                system=SOMMELIER_SYSTEM,
                prompt=prompt,
                request_id=f"sommelier:{user.id}:{req.session_id}",
            ):
                if remaining_chars <= 0:
                    break
                safe_delta = delta[:remaining_chars]
                if safe_delta:
                    collected.append(safe_delta)
                    remaining_chars -= len(safe_delta)
                    yield f"data: {json.dumps({'delta': safe_delta}, ensure_ascii=False)}\n\n"
                if len(safe_delta) < len(delta):
                    break
        except AIProviderError:
            yield f"data: {json.dumps({'error': 'Il Sommelier non è al momento disponibile.'}, ensure_ascii=False)}\n\n"
            return

        full_response = "".join(collected).strip()
        if full_response:
            await services.repositories.chats.append_exchange(
                user.id,
                req.session_id,
                req.message,
                full_response,
                max_messages=services.settings.sommelier_max_messages,
                ttl_days=services.settings.sommelier_history_ttl_days,
            )
        yield f"data: {json.dumps({'done': True})}\n\n"

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@router.get("/sommelier/history/{session_id}")
async def sommelier_history(
    session_id: Annotated[
        str,
        Path(min_length=4, max_length=64, pattern=r"^[A-Za-z0-9_-]+$"),
    ],
    request: Request,
    user: Annotated[AuthenticatedUser, Depends(current_user)],
):
    await _enforce_ai_limit(request, user)
    messages = await request.app.state.services.repositories.chats.get_messages(user.id, session_id)
    return {"messages": messages}


@router.delete("/sommelier/history/{session_id}")
async def sommelier_reset(
    session_id: Annotated[
        str,
        Path(min_length=4, max_length=64, pattern=r"^[A-Za-z0-9_-]+$"),
    ],
    request: Request,
    user: Annotated[AuthenticatedUser, Depends(current_user)],
):
    await _enforce_ai_limit(request, user)
    await request.app.state.services.repositories.chats.delete(user.id, session_id)
    return {"ok": True}


class CatalogWine(BaseModel):
    model_config = ConfigDict(extra="forbid")
    id: str = Field(..., min_length=1, max_length=100)
    label: str = Field(..., min_length=1, max_length=300)


class PairingRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    query: str = Field(..., min_length=2, max_length=400)
    catalog: list[CatalogWine] = Field(..., min_length=1, max_length=60)


class PairingPick(BaseModel):
    wine_id: str
    reasoning: str


class PairingResponse(BaseModel):
    picks: list[PairingPick]
    intro: str


PAIRING_SYSTEM = (
    "Sei un sommelier italiano. Rispondi esclusivamente con JSON valido: "
    '{"intro":"...", "picks":[{"wine_id":"...", "reasoning":"..."}]}. '
    "Scegli esattamente 3 vini presenti nel catalogo, oppure tutti se il catalogo ne contiene meno."
)


def _extract_json(raw: str) -> dict:
    text = raw.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*|\s*```$", "", text, flags=re.IGNORECASE | re.MULTILINE)
    try:
        return json.loads(text)
    except json.JSONDecodeError as error:
        match = re.search(r"\{[\s\S]*\}", text)
        if not match:
            raise ValueError("nessun oggetto JSON") from error
        return json.loads(match.group(0))


@router.post("/pairing", response_model=PairingResponse)
async def pairing(
    req: PairingRequest,
    request: Request,
    user: Annotated[AuthenticatedUser, Depends(current_user)],
):
    await _enforce_ai_limit(request, user)
    catalog_text = "\n".join(f"- {wine.id}: {wine.label}" for wine in req.catalog)
    prompt = f"Piatto o occasione: {req.query.strip()}\n\nCatalogo:\n{catalog_text}"
    try:
        raw = await request.app.state.services.ai.complete_text(
            system=PAIRING_SYSTEM,
            prompt=prompt,
            request_id=f"pairing:{user.id}:{uuid.uuid4()}",
        )
        parsed = _extract_json(raw)
    except AIProviderError as exc:
        raise HTTPException(503, "Il servizio AI non è al momento disponibile") from exc
    except (ValueError, json.JSONDecodeError) as exc:
        raise HTTPException(502, "Il provider AI ha restituito un formato non valido") from exc

    valid_ids = {wine.id for wine in req.catalog}
    picks: list[PairingPick] = []
    seen_ids: set[str] = set()
    expected_count = min(3, len(req.catalog))
    for pick in parsed.get("picks", []):
        if not isinstance(pick, dict):
            continue
        wine_id = str(pick.get("wine_id", ""))
        if wine_id not in valid_ids or wine_id in seen_ids:
            continue
        seen_ids.add(wine_id)
        picks.append(
            PairingPick(
                wine_id=wine_id,
                reasoning=str(pick.get("reasoning", "")).strip()[:400],
            )
        )
        if len(picks) == expected_count:
            break
    if len(picks) != expected_count:
        raise HTTPException(502, "Il provider AI non ha restituito il numero richiesto di vini validi")
    return PairingResponse(intro=str(parsed.get("intro", "")).strip()[:300], picks=picks)


class ListingRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    ocr_text: str | None = Field(None, max_length=2000)
    hint: str | None = Field(None, max_length=500)


class ListingResponse(BaseModel):
    nome: str = ""
    produttore: str = ""
    annata: int | None = None
    denominazione: str = ""
    regione: str = ""
    tipologia: str = ""
    note_degustazione: str = ""
    condizioni_suggerite: str = ""
    confidence: float = Field(0.0, ge=0, le=1)


LISTING_SYSTEM = (
    "Sei un catalogatore di vini italiano. Rispondi esclusivamente con JSON con i campi "
    "nome, produttore, annata, denominazione, regione, tipologia, note_degustazione, "
    "condizioni_suggerite e confidence. Non inventare dati non deducibili."
)


@router.post("/listing-suggestion", response_model=ListingResponse)
async def listing_suggestion(
    req: ListingRequest,
    request: Request,
    user: Annotated[AuthenticatedUser, Depends(current_user)],
):
    await _enforce_ai_limit(request, user)
    if not req.ocr_text and not req.hint:
        raise HTTPException(400, "Fornire 'ocr_text' o 'hint'")
    parts = []
    if req.ocr_text:
        parts.append(f"OCR etichetta:\n{req.ocr_text.strip()}")
    if req.hint:
        parts.append(f"Indicazione utente: {req.hint.strip()}")
    try:
        raw = await request.app.state.services.ai.complete_text(
            system=LISTING_SYSTEM,
            prompt="\n\n".join(parts),
            request_id=f"listing:{user.id}:{uuid.uuid4()}",
        )
        parsed = _extract_json(raw)
        values = {key: parsed.get(key, field.default) for key, field in ListingResponse.model_fields.items()}
        return ListingResponse(**values)
    except AIProviderError as exc:
        raise HTTPException(503, "Il servizio AI non è al momento disponibile") from exc
    except (ValueError, json.JSONDecodeError) as exc:
        raise HTTPException(502, "Il provider AI ha restituito un formato non valido") from exc
    except Exception as exc:
        raise HTTPException(502, "I dati proposti dall'AI non rispettano lo schema atteso") from exc
