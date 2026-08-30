import type { SupabaseClient } from "@supabase/supabase-js";
import { noPhase9Client, phase9Throw } from "@/services/phase9/shared";

export const ADMIN_LOOKUP_MIN_LENGTH = 2;
export const ADMIN_LOOKUP_LIMIT = 10;

export type AdminUserResult = {
  id: string;
  username: string;
  createdAt: string | null;
  status: string | null;
  role: string;
  listingCount: number;
  openReportCount: number;
};

export type AdminListingResult = {
  id: string;
  slug: string | null;
  title: string;
  sellerId: string;
  sellerUsername: string;
  status: string | null;
  priceCents: number | null;
  createdAt: string | null;
  updatedAt: string | null;
  openReportCount: number;
};

export type AdminOrderResult = {
  id: string;
  buyerId: string;
  buyerUsername: string;
  sellerId: string;
  sellerUsername: string;
  status: string | null;
  totalCents: number | null;
  payoutStatus: string | null;
  createdAt: string | null;
  updatedAt: string | null;
  openDispute: boolean;
};

export type AdminClubResult = {
  slug: string;
  nome: string;
  ownerId: string | null;
  ownerUsername: string | null;
  createdAt: string | null;
  postingMode: string | null;
  openReportCount: number;
};

export type AdminLookupResults = {
  users: AdminUserResult[];
  listings: AdminListingResult[];
  orders: AdminOrderResult[];
  clubs: AdminClubResult[];
};

export const EMPTY_ADMIN_LOOKUP: AdminLookupResults = {
  users: [],
  listings: [],
  orders: [],
  clubs: [],
};

// Le quattro sezioni operative condividono una sola ricerca. Lo scope decide
// quale gruppo si mostra e quale dettaglio si apre; il backend resta una porta
// sola, cosi non ci sono quattro cancelli da tenere allineati.
export type AdminScope = "utente" | "annuncio" | "ordine" | "club";

export type AdminOverview = {
  openReports: number;
  highPriorityReports: number;
  infoRequestedReports: number;
  openDisputes: number;
  listingsInReview: number;
  listingsSuspended: number;
};

export const EMPTY_ADMIN_OVERVIEW: AdminOverview = {
  openReports: 0,
  highPriorityReports: 0,
  infoRequestedReports: 0,
  openDisputes: 0,
  listingsInReview: 0,
  listingsSuspended: 0,
};

export type AdminRelatedReport = {
  id: string;
  codice: string;
  targetType: string;
  targetLabel: string;
  motivo: string;
  stato: string;
  priorita: string;
  createdAt: string | null;
};

export type AdminUserDetail = AdminUserResult & {
  orderCountAsBuyer: number;
  orderCountAsSeller: number;
  recentListings: Array<{
    id: string;
    slug: string | null;
    title: string;
    status: string | null;
    updatedAt: string | null;
  }>;
};

export type AdminOrderDetail = AdminOrderResult & {
  disputeId: string | null;
  disputeStatus: string | null;
};

export type AdminDetail =
  | { tipo: "utente"; entity: AdminUserDetail | null; reports: AdminRelatedReport[] }
  | { tipo: "annuncio"; entity: AdminListingResult | null; reports: AdminRelatedReport[] }
  | { tipo: "ordine"; entity: AdminOrderDetail | null; reports: AdminRelatedReport[] }
  | { tipo: "club"; entity: AdminClubResult | null; reports: AdminRelatedReport[] };

const asArray = <T,>(value: unknown): T[] => (Array.isArray(value) ? (value as T[]) : []);
const asCount = (value: unknown): number => (typeof value === "number" ? value : 0);

export const adminOperationsLookup = async (
  client: SupabaseClient | null,
  query: string,
): Promise<AdminLookupResults> => {
  if (!client) return noPhase9Client("adminOperationsLookup");
  const normalized = query.trim();
  if (normalized.length < ADMIN_LOOKUP_MIN_LENGTH) {
    throw new Error("Inserisci almeno 2 caratteri.");
  }

  const { data, error } = await client.rpc("admin_operations_lookup", {
    p_query: normalized,
    p_limit: ADMIN_LOOKUP_LIMIT,
  });
  if (error) return phase9Throw("admin_operations_lookup", error);

  const result = (data ?? {}) as Partial<AdminLookupResults>;
  return {
    users: asArray<AdminUserResult>(result.users),
    listings: asArray<AdminListingResult>(result.listings),
    orders: asArray<AdminOrderResult>(result.orders),
    clubs: asArray<AdminClubResult>(result.clubs),
  };
};

export const adminOperationsOverview = async (
  client: SupabaseClient | null,
): Promise<AdminOverview> => {
  if (!client) return noPhase9Client("adminOperationsOverview");
  const { data, error } = await client.rpc("admin_operations_overview");
  if (error) return phase9Throw("admin_operations_overview", error);

  const result = (data ?? {}) as Partial<AdminOverview>;
  return {
    openReports: asCount(result.openReports),
    highPriorityReports: asCount(result.highPriorityReports),
    infoRequestedReports: asCount(result.infoRequestedReports),
    openDisputes: asCount(result.openDisputes),
    listingsInReview: asCount(result.listingsInReview),
    listingsSuspended: asCount(result.listingsSuspended),
  };
};

export const adminOperationsDetail = async (
  client: SupabaseClient | null,
  tipo: AdminScope,
  identificatore: string,
): Promise<AdminDetail> => {
  if (!client) return noPhase9Client("adminOperationsDetail");
  const normalized = identificatore.trim();
  if (normalized.length < ADMIN_LOOKUP_MIN_LENGTH) {
    throw new Error("Identificatore non valido.");
  }

  const { data, error } = await client.rpc("admin_operations_detail", {
    p_tipo: tipo,
    p_identificatore: normalized,
  });
  if (error) return phase9Throw("admin_operations_detail", error);

  const result = (data ?? {}) as { entity?: unknown; reports?: unknown };
  return {
    tipo,
    entity: (result.entity ?? null) as never,
    reports: asArray<AdminRelatedReport>(result.reports),
  };
};
