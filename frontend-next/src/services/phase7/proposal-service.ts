import type { SupabaseClient } from "@supabase/supabase-js";
import { noClient, serviceError } from "@/services/phase7/shared";
import type { ProposalRecord, ProposalService, Result } from "@/services/types";

const callProposal = async (
  client: SupabaseClient,
  operation: string,
  parameters: Record<string, unknown>,
): Promise<Result<ProposalRecord>> => {
  const { data, error } = await client.rpc(operation, parameters);
  if (error) return serviceError(operation, error);
  return { ok: true, data: data as ProposalRecord };
};

export const createProposalService = (client: SupabaseClient | null): ProposalService => ({
  invia: (listingId, prezzoCents) =>
    client
      ? callProposal(client, "proposal_invia", {
          p_listing_id: listingId,
          p_prezzo_cents: prezzoCents,
        })
      : Promise.resolve(noClient()),
  controproposta: (id, prezzoCents) =>
    client
      ? callProposal(client, "proposal_controproponi", {
          p_proposal_id: id,
          p_prezzo_cents: prezzoCents,
        })
      : Promise.resolve(noClient()),
  accetta: (id) =>
    client
      ? callProposal(client, "proposal_accetta", { p_proposal_id: id })
      : Promise.resolve(noClient()),
  rifiuta: async (id) => {
    if (!client) return noClient();
    const { error } = await client.rpc("proposal_rifiuta", { p_proposal_id: id });
    return error ? serviceError("proposal_rifiuta", error) : { ok: true, data: undefined };
  },
  mie: async () => {
    if (!client) return noClient();
    const { data, error } = await client.from("proposals").select("*").order("created_at", {
      ascending: false,
    });
    return error
      ? serviceError("proposals.select", error)
      : { ok: true, data: data as ProposalRecord[] };
  },
});
