import type { SupabaseClient } from "@supabase/supabase-js";
import type { MarketValidationParticipantFilter } from "@/lib/market-validation/admin-analytics";
import {
  QV2_EXPORT_PAGE_SIZE,
  QV2_MAX_PARTICIPANTS,
  parseQv2AdminParticipantsPage,
  parseQv2AdminSummary,
  parseQv2Distributions,
  parseQv2ParticipantDetail,
  type Qv2AdminParticipant,
  type Qv2AdminParticipantsPage,
  type Qv2AdminSummary,
  type Qv2CohortFilter,
  type Qv2Distributions,
  type Qv2ParticipantDetail,
} from "@/lib/market-validation/questionnaire-admin";
import type { MarketValidationParticipantCode } from "@/services/types";
import { MarketValidationAdminError } from "@/services/market-validation-admin-service";

// Adapter delle quattro porte admin QV2 read-only. Il ruolo admin è
// ricontrollato dal database: qui non si legge alcuna tabella.

const requireClient = (client: SupabaseClient | null): SupabaseClient => {
  if (!client) throw new MarketValidationAdminError("client", { code: "P0001" });
  return client;
};

export async function loadQv2AdminSummary(client: SupabaseClient | null): Promise<Qv2AdminSummary> {
  const { data, error } = await requireClient(client).rpc("beta_validation_qv2_admin_summary");
  if (error) throw new MarketValidationAdminError("beta_validation_qv2_admin_summary", error);
  return parseQv2AdminSummary(data);
}

export async function loadQv2AdminDistributions(
  client: SupabaseClient | null,
): Promise<Qv2Distributions> {
  const { data, error } = await requireClient(client).rpc("beta_validation_qv2_admin_distributions");
  if (error) throw new MarketValidationAdminError("beta_validation_qv2_admin_distributions", error);
  return parseQv2Distributions(data);
}

export async function loadQv2AdminParticipants(
  client: SupabaseClient | null,
  options: {
    participantCode: MarketValidationParticipantFilter;
    cohort: Qv2CohortFilter;
    limit: number;
    offset: number;
  },
): Promise<Qv2AdminParticipantsPage> {
  const { data, error } = await requireClient(client).rpc(
    "beta_validation_qv2_admin_participants",
    {
      p_participant_code: options.participantCode,
      p_cohort: options.cohort,
      p_limit: options.limit,
      p_offset: options.offset,
    },
  );
  if (error) throw new MarketValidationAdminError("beta_validation_qv2_admin_participants", error);
  return parseQv2AdminParticipantsPage(data);
}

// Recupera tutte le pagine; se le righe ottenute non coincidono con il totale
// dichiarato dal database l'export fallisce invece di troncare in silenzio.
export async function loadAllQv2AdminParticipants(
  client: SupabaseClient | null,
  filters: { participantCode: MarketValidationParticipantFilter; cohort: Qv2CohortFilter },
): Promise<Qv2AdminParticipant[]> {
  const participants: Qv2AdminParticipant[] = [];
  let total = 0;
  for (let offset = 0; offset < QV2_MAX_PARTICIPANTS; offset += QV2_EXPORT_PAGE_SIZE) {
    const page = await loadQv2AdminParticipants(client, {
      ...filters,
      limit: QV2_EXPORT_PAGE_SIZE,
      offset,
    });
    participants.push(...page.participants);
    total = Math.max(total, page.total);
    if (page.participants.length < QV2_EXPORT_PAGE_SIZE || participants.length >= total) break;
  }
  const codes = new Set(participants.map((participant) => participant.participantCode));
  if (participants.length !== total || codes.size !== participants.length) {
    throw new MarketValidationAdminError("export", {
      code: "22023",
      message: `Esportazione incompleta: ${participants.length} righe su ${total}. Riprova.`,
    });
  }
  return participants;
}

export async function loadQv2ParticipantDetail(
  client: SupabaseClient | null,
  participantCode: MarketValidationParticipantCode,
): Promise<Qv2ParticipantDetail | null> {
  const { data, error } = await requireClient(client).rpc(
    "beta_validation_qv2_admin_participant_detail",
    { p_participant_code: participantCode },
  );
  if (error) {
    throw new MarketValidationAdminError("beta_validation_qv2_admin_participant_detail", error);
  }
  return parseQv2ParticipantDetail(data);
}
