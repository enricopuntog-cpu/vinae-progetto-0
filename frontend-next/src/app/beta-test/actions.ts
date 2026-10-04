"use server";

import { marketValidationAbilitataServer } from "@/config/features";
import { parseMarketValidationParticipantCode } from "@/lib/market-validation/contract";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { createMarketValidationService } from "@/services/market-validation-service";
import type { MarketValidationSession, Result } from "@/services/types";

const NON_DISPONIBILE = "Il test non è disponibile in questo momento.";
const CODICE_NON_VALIDO = "Inserisci un codice da V001 a V999.";

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
