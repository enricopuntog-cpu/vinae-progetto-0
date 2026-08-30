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

export type AdminLookupResults = {
  users: AdminUserResult[];
  listings: AdminListingResult[];
  orders: AdminOrderResult[];
};

export const EMPTY_ADMIN_LOOKUP: AdminLookupResults = {
  users: [],
  listings: [],
  orders: [],
};

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
    users: Array.isArray(result.users) ? result.users : [],
    listings: Array.isArray(result.listings) ? result.listings : [],
    orders: Array.isArray(result.orders) ? result.orders : [],
  };
};
