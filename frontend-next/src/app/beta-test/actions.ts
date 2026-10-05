"use server";

import { marketValidationAbilitataServer } from "@/config/features";
import { parseMarketValidationParticipantCode } from "@/lib/market-validation/contract";
import { marketValidationShippingFeeCents } from "@/lib/market-validation/config";
import {
  parseMarketValidationEventMetadata,
  parseMarketValidationRecordableEvent,
  parseMarketValidationSession,
} from "@/lib/market-validation/event-validation";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { createMarketValidationService } from "@/services/market-validation-service";
import type { MarketValidationSession, Result } from "@/services/types";

const NON_DISPONIBILE = "Il test non è disponibile in questo momento.";
const CODICE_NON_VALIDO = "Inserisci un codice da V001 a V999.";
const EVENTO_NON_VALIDO = "Non è stato possibile registrare questo passaggio.";

/**
 * Porta server MV1. La flag pubblica non viene letta: non autorizza scritture.
 * Il database ricontrolla formato, capability, ownership anonima e rate limit.
 */
export async function startMarketValidationSession(
  participantCode: string,
  capability: string,
): Promise<Result<MarketValidationSession>> {
  if (!marketValidationAbilitataServer()) {
    return { ok: false, error: NON_DISPONIBILE };
  }

  const canonical = parseMarketValidationParticipantCode(participantCode);
  if (!canonical) return { ok: false, error: CODICE_NON_VALIDO };

  const client = await getSupabaseServerClient();
  return createMarketValidationService(client).startOrResume(canonical, capability);
}

/**
 * Porta MV2: ogni argomento arriva dal browser e viene ricontrollato prima
 * dell'adapter. Il database resta l'ultima autorità su capability e sessione.
 */
export async function recordMarketValidationEvent(
  sessionInput: unknown,
  eventInput: unknown,
  metadataInput: unknown,
): Promise<Result<{ eventId: string }>> {
  if (!marketValidationAbilitataServer()) {
    return { ok: false, error: NON_DISPONIBILE };
  }

  const session = parseMarketValidationSession(sessionInput);
  const eventName = parseMarketValidationRecordableEvent(eventInput);
  if (!session || !eventName) {
    return { ok: false, error: EVENTO_NON_VALIDO };
  }

  const metadata = parseMarketValidationEventMetadata(
    eventName,
    metadataInput,
  );
  if (!metadata) return { ok: false, error: EVENTO_NON_VALIDO };
  if (
    eventName === "shipping_cost_viewed" &&
    metadata.price_cents !== marketValidationShippingFeeCents()
  ) {
    return { ok: false, error: EVENTO_NON_VALIDO };
  }

  const client = await getSupabaseServerClient();
  return createMarketValidationService(client).recordEvent(
    session,
    eventName,
    metadata,
  );
}
