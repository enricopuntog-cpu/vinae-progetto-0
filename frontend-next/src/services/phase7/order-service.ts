import type { SupabaseClient } from "@supabase/supabase-js";
import { noClient, serviceError } from "@/services/phase7/shared";
import type { OrderRecord, OrderService, Result } from "@/services/types";

const list = async (
  client: SupabaseClient,
  column: "buyer_id" | "seller_id",
): Promise<Result<OrderRecord[]>> => {
  const { data: auth } = await client.auth.getUser();
  if (!auth.user) return { ok: false, error: "Autenticazione richiesta." };
  const { data, error } = await client
    .from("orders")
    .select("*")
    .eq(column, auth.user.id)
    .order("created_at", { ascending: false });
  return error ? serviceError("orders.select", error) : { ok: true, data: data as OrderRecord[] };
};

export const createOrderService = (client: SupabaseClient | null): OrderService => ({
  acquisti: () => (client ? list(client, "buyer_id") : Promise.resolve(noClient())),
  vendite: () => (client ? list(client, "seller_id") : Promise.resolve(noClient())),
  get: async (id) => {
    if (!client) return noClient();
    const { data, error } = await client.from("orders").select("*").eq("id", id).maybeSingle();
    return error
      ? serviceError("orders.get", error)
      : { ok: true, data: data as OrderRecord | null };
  },
});
