import type { SupabaseClient } from "@supabase/supabase-js";
import {
  MARKET_VALIDATION_EXPORT_PAGE_SIZE,
  MARKET_VALIDATION_MAX_PARTICIPANTS,
  parseMarketValidationAdminParticipant,
  parseMarketValidationAdminSummary,
  type MarketValidationAdminParticipant,
  type MarketValidationAdminSummary,
  type MarketValidationParticipantFilter,
} from "@/lib/market-validation/admin-analytics";

export class MarketValidationAdminError extends Error {
  readonly code?: string;

  constructor(operation: string, error?: { code?: string; message?: string }) {
    const readable = error?.code === "22023" || error?.code === "42501";
    super(
      readable && error?.message
        ? error.message
        : operation === "client"
          ? "Connessione a Supabase non configurata."
          : "Non è stato possibile caricare le analytics. Riprova.",
    );
    this.name = "MarketValidationAdminError";
    this.code = error?.code;
    if (operation !== "client") {
      console.error(`[MarketValidation] ${operation} fallita`, { code: error?.code });
    }
  }
}

const requireClient = (client: SupabaseClient | null): SupabaseClient => {
  if (!client) throw new MarketValidationAdminError("client", { code: "P0001" });
  return client;
};

export async function loadMarketValidationAdminSummary(
  client: SupabaseClient | null,
): Promise<MarketValidationAdminSummary> {
  const { data, error } = await requireClient(client).rpc("beta_validation_admin_summary");
  if (error) throw new MarketValidationAdminError("beta_validation_admin_summary", error);
  return parseMarketValidationAdminSummary(data);
}

export async function loadMarketValidationAdminParticipants(
  client: SupabaseClient | null,
  options: {
    participantCode: MarketValidationParticipantFilter;
    limit: number;
    offset: number;
  },
): Promise<MarketValidationAdminParticipant[]> {
  const { data, error } = await requireClient(client).rpc(
    "beta_validation_admin_participants",
    {
      p_participant_code: options.participantCode,
      p_limit: options.limit,
      p_offset: options.offset,
    },
  );
  if (error) throw new MarketValidationAdminError("beta_validation_admin_participants", error);
  if (!Array.isArray(data)) return [];
  return data.flatMap((row) => {
    const participant = parseMarketValidationAdminParticipant(row);
    return participant ? [participant] : [];
  });
}

export async function loadAllMarketValidationAdminParticipants(
  client: SupabaseClient | null,
  participantCode: MarketValidationParticipantFilter,
): Promise<MarketValidationAdminParticipant[]> {
  const participants: MarketValidationAdminParticipant[] = [];
  for (
    let offset = 0;
    offset < MARKET_VALIDATION_MAX_PARTICIPANTS;
    offset += MARKET_VALIDATION_EXPORT_PAGE_SIZE
  ) {
    const remaining = MARKET_VALIDATION_MAX_PARTICIPANTS - offset;
    const limit = Math.min(MARKET_VALIDATION_EXPORT_PAGE_SIZE, remaining);
    const page = await loadMarketValidationAdminParticipants(client, {
      participantCode,
      limit,
      offset,
    });
    participants.push(...page);
    if (page.length < limit) break;
  }
  return participants;
}
