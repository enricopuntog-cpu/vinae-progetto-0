import type { SupabaseClient } from "@supabase/supabase-js";

export type ClubProposalAdmin = {
  slug: string;
  nome: string;
  descrizione: string;
  categoria: string;
  territorio: string | null;
  accessType: "aperto" | "chiuso";
  requirements: string | null;
  regole: string[];
  ownerUsername: string;
  approvalStatus: "in_attesa" | "approvato" | "rifiutato" | "sospeso";
  postingMode: "OPEN" | "OWNER_ONLY";
  externalLinks: Array<{ id: string; platform: string; url: string; label: string | null }>;
  createdAt: string;
};

export type ManagedClub = {
  slug: string;
  nome: string;
  descrizione: string;
  categoria: string | null;
  territorio: string | null;
  accessType: "aperto" | "chiuso";
  requirements: string | null;
  postingMode: "OPEN" | "OWNER_ONLY";
  approvalStatus: string;
  ownerId: string | null;
};

export type ClubMemberAdmin = {
  clubSlug: string;
  userId: string;
  username: string;
  role: "proprietario" | "moderatore" | "membro";
  createdAt: string;
};

export type ClubJoinRequestAdmin = {
  id: string;
  clubSlug: string;
  userId: string;
  username: string;
  message: string | null;
  createdAt: string;
};

export type ClubRuleVersionAdmin = {
  id: string;
  clubSlug: string;
  version: number;
  rules: string[];
  status: "in_attesa" | "approvata" | "rifiutata" | "superata";
  proposedByUsername: string | null;
  reviewNote: string | null;
  createdAt: string;
  reviewedAt: string | null;
};

export type ClubExternalLinkAdmin = {
  id: string;
  clubSlug: string;
  platform: "facebook" | "instagram" | "x" | "telegram" | "discord" | "sito" | "altro";
  url: string;
  label: string | null;
  status: "in_attesa" | "approvato" | "rifiutato";
  proposedByUsername: string | null;
  createdAt: string;
};

type DbError = { code?: string; message?: string };

const readable = new Set(["P0001", "42501", "22023", "23505", "PGRST"]);

const failure = (operation: string, error: DbError): never => {
  console.error(`[Club governance] ${operation}`, { code: error.code });
  throw new Error(
    error.code && readable.has(error.code) && error.message
      ? error.message
      : "Non è stato possibile completare l'operazione.",
  );
};

const required = (client: SupabaseClient | null): SupabaseClient => {
  if (!client) throw new Error("Servizio Club non disponibile.");
  return client;
};

const proposal = (row: Record<string, unknown>): ClubProposalAdmin => ({
  slug: String(row.slug),
  nome: String(row.nome),
  descrizione: String(row.descrizione),
  categoria: String(row.categoria),
  territorio: typeof row.territorio === "string" ? row.territorio : null,
  accessType: row.access_type === "chiuso" ? "chiuso" : "aperto",
  requirements: typeof row.requirements === "string" ? row.requirements : null,
  regole: Array.isArray(row.regole) ? row.regole.filter((v): v is string => typeof v === "string") : [],
  ownerUsername: String(row.owner_username),
  approvalStatus: String(row.approval_status) as ClubProposalAdmin["approvalStatus"],
  postingMode: row.posting_mode === "OWNER_ONLY" ? "OWNER_ONLY" : "OPEN",
  externalLinks: Array.isArray(row.external_links)
    ? row.external_links.flatMap((item) => {
        if (!item || typeof item !== "object") return [];
        const value = item as Record<string, unknown>;
        return [{
          id: String(value.id),
          platform: String(value.platform),
          url: String(value.url),
          label: typeof value.label === "string" ? value.label : null,
        }];
      })
    : [],
  createdAt: String(row.created_at),
});

export const createClubGovernanceService = (maybeClient: SupabaseClient | null) => {
  const client = required(maybeClient);

  const managedClubs = async (): Promise<ManagedClub[]> => {
    const { data, error } = await client.from("club_management_clubs").select("*").order("nome");
    if (error) failure("club_management_clubs", error);
    return (data ?? []).map((raw) => {
      const row = raw as Record<string, unknown>;
      return {
        slug: String(row.slug), nome: String(row.nome), descrizione: String(row.descrizione),
        categoria: typeof row.categoria === "string" ? row.categoria : null,
        territorio: typeof row.territorio === "string" ? row.territorio : null,
        accessType: row.access_type === "chiuso" ? "chiuso" : "aperto",
        requirements: typeof row.requirements === "string" ? row.requirements : null,
        postingMode: row.posting_mode === "OWNER_ONLY" ? "OWNER_ONLY" : "OPEN",
        approvalStatus: String(row.approval_status),
        ownerId: typeof row.owner_id === "string" ? row.owner_id : null,
      };
    });
  };

  const proposals = async (): Promise<ClubProposalAdmin[]> => {
    const { data, error } = await client.from("moderation_club_proposals").select("*").order("created_at");
    if (error) failure("moderation_club_proposals", error);
    return (data ?? []).map((row) => proposal(row as Record<string, unknown>));
  };

  const members = async (slug: string): Promise<ClubMemberAdmin[]> => {
    const { data, error } = await client.from("club_management_members").select("*")
      .eq("club_slug", slug).order("created_at");
    if (error) failure("club_management_members", error);
    return (data ?? []).map((raw) => {
      const row = raw as Record<string, unknown>;
      return { clubSlug: String(row.club_slug), userId: String(row.user_id),
        username: String(row.username), role: String(row.role) as ClubMemberAdmin["role"],
        createdAt: String(row.created_at) };
    });
  };

  const joinRequests = async (slug?: string): Promise<ClubJoinRequestAdmin[]> => {
    let query = client.from("club_membership_request_queue").select("*").order("created_at");
    if (slug) query = query.eq("club_slug", slug);
    const { data, error } = await query;
    if (error) failure("club_membership_request_queue", error);
    return (data ?? []).map((raw) => {
      const row = raw as Record<string, unknown>;
      return { id: String(row.id), clubSlug: String(row.club_slug), userId: String(row.user_id),
        username: String(row.username), message: typeof row.request_message === "string" ? row.request_message : null,
        createdAt: String(row.created_at) };
    });
  };

  const rules = async (slug?: string): Promise<ClubRuleVersionAdmin[]> => {
    let query = client.from("club_rule_versions_visible").select("*")
      .order("club_slug").order("version", { ascending: false });
    if (slug) query = query.eq("club_slug", slug);
    const { data, error } = await query;
    if (error) failure("club_rule_versions_visible", error);
    return (data ?? []).map((raw) => {
      const row = raw as Record<string, unknown>;
      return { id: String(row.id), clubSlug: String(row.club_slug), version: Number(row.version),
        rules: Array.isArray(row.rules) ? row.rules.filter((v): v is string => typeof v === "string") : [],
        status: String(row.status) as ClubRuleVersionAdmin["status"],
        proposedByUsername: typeof row.proposed_by_username === "string" ? row.proposed_by_username : null,
        reviewNote: typeof row.review_note === "string" ? row.review_note : null,
        createdAt: String(row.created_at), reviewedAt: typeof row.reviewed_at === "string" ? row.reviewed_at : null };
    });
  };

  const links = async (slug?: string): Promise<ClubExternalLinkAdmin[]> => {
    let query = client.from("club_external_links_visible").select("*").order("created_at");
    if (slug) query = query.eq("club_slug", slug);
    const { data, error } = await query;
    if (error) failure("club_external_links_visible", error);
    return (data ?? []).map((raw) => {
      const row = raw as Record<string, unknown>;
      return { id: String(row.id), clubSlug: String(row.club_slug),
        platform: String(row.platform) as ClubExternalLinkAdmin["platform"], url: String(row.url),
        label: typeof row.label === "string" ? row.label : null,
        status: String(row.status) as ClubExternalLinkAdmin["status"],
        proposedByUsername: typeof row.proposed_by_username === "string" ? row.proposed_by_username : null,
        createdAt: String(row.created_at) };
    });
  };

  const rpc = async (name: string, args: Record<string, unknown>) => {
    const { error } = await client.rpc(name, args);
    if (error) failure(name, error);
  };

  return {
    managedClubs, proposals, members, joinRequests, rules, links,
    reviewProposal: (slug: string, approve: boolean, note: string | null) =>
      rpc("club_proposta_revisiona", { p_club_slug: slug, p_approva: approve, p_nota: note }),
    reviewJoinRequest: (id: string, approve: boolean, note: string | null) =>
      rpc("club_ingresso_revisiona", { p_request_id: id, p_approva: approve, p_nota: note }),
    setModerator: (slug: string, userId: string, moderator: boolean) =>
      rpc("club_moderatore_imposta", { p_club_slug: slug, p_user_id: userId, p_moderatore: moderator }),
    proposeRules: (slug: string, values: string[]) =>
      rpc("club_regolamento_proponi", { p_club_slug: slug, p_regole: values }),
    reviewRules: (id: string, approve: boolean, note: string | null) =>
      rpc("club_regolamento_revisiona", { p_version_id: id, p_approva: approve, p_nota: note }),
    proposeLink: (slug: string, platform: ClubExternalLinkAdmin["platform"], url: string, label: string | null) =>
      rpc("club_link_proponi", { p_club_slug: slug, p_platform: platform, p_url: url, p_label: label }),
    reviewLink: (id: string, approve: boolean) =>
      rpc("club_link_revisiona", { p_link_id: id, p_approva: approve }),
    removeLink: (id: string) => rpc("club_link_rimuovi", { p_link_id: id }),
  };
};
