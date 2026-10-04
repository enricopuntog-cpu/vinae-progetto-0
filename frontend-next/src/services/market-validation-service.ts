import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  MarketValidationEventMetadata,
  MarketValidationParticipantCode,
  MarketValidationService,
  MarketValidationSession,
} from "@/services/types";

const RPC_START = "beta_validation_session_start";
const RPC_EVENT = "beta_validation_event_record";
const NON_CONFIGURATO = "Il test non è disponibile in questo momento.";
const AVVIO_FALLITO = "Non è stato possibile iniziare il test. Riprova.";
const EVENTO_FALLITO = "Non è stato possibile registrare questo passaggio.";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function row(value: unknown): Record<string, unknown> | null {
  if (Array.isArray(value)) value = value[0];
  return value && typeof value === "object" ? (value as Record<string, unknown>) : null;
}

function mapSession(
  value: unknown,
  capability: string,
): MarketValidationSession | null {
  const data = row(value);
  if (!data) return null;
  const sessionId = data.session_id;
  const participantCode = data.participant_code;
  const startedAt = data.started_at;
  const resumed = data.resumed;
  if (
    typeof sessionId !== "string" ||
    !UUID.test(sessionId) ||
    typeof participantCode !== "string" ||
    !/^V(00[1-9]|0[1-9][0-9]|[1-9][0-9]{2})$/.test(participantCode) ||
    typeof startedAt !== "string" ||
    Number.isNaN(Date.parse(startedAt)) ||
    typeof resumed !== "boolean"
  ) {
    return null;
  }
  return {
    sessionId,
    participantCode: participantCode as MarketValidationParticipantCode,
    capability,
    startedAt,
    resumed,
  };
}

function report(operation: string, error: unknown): void {
  console.error(`[MarketValidationService] ${operation}:`, error);
}

/**
 * Adapter anon/publishable-key del solo dominio MV. Non importa né espone
 * servizi di ordini, pagamenti, annunci, inventario, spedizioni o messaggistica.
 */
export function createMarketValidationService(
  client: SupabaseClient | null,
): MarketValidationService {
  return {
    async startOrResume(participantCode, capability) {
      if (!client) return { ok: false, error: NON_CONFIGURATO };
      if (!UUID.test(capability)) return { ok: false, error: AVVIO_FALLITO };

      const { data, error } = await client.rpc(RPC_START, {
        p_participant_code: participantCode,
        p_capability: capability,
      });
      if (error) {
        report("avvio sessione fallito", error);
        return { ok: false, error: AVVIO_FALLITO };
      }
      const session = mapSession(data, capability);
      if (!session) {
        report("risposta di avvio illeggibile", new Error("Payload RPC inatteso."));
        return { ok: false, error: AVVIO_FALLITO };
      }
      return { ok: true, data: session };
    },

    async recordEvent(session, eventName, metadata: MarketValidationEventMetadata = {}) {
      if (!client) return { ok: false, error: NON_CONFIGURATO };
      const { data, error } = await client.rpc(RPC_EVENT, {
        p_session_id: session.sessionId,
        p_participant_code: session.participantCode,
        p_capability: session.capability,
        p_event_name: eventName,
        p_metadata: metadata,
      });
      if (error || typeof data !== "string" || !UUID.test(data)) {
        report("registrazione evento fallita", error ?? new Error("Payload RPC inatteso."));
        return { ok: false, error: EVENTO_FALLITO };
      }
      return { ok: true, data: { eventId: data } };
    },
  };
}
