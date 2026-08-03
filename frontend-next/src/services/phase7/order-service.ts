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

/**
 * Ogni transizione è una RPC dedicata: il chiamante non sceglie lo stato di
 * arrivo, e non esiste un metodo che rilasci i fondi. Il rilascio è una
 * conseguenza della conferma, eseguita dal job server-side.
 */
const transizione = async (
  client: SupabaseClient | null,
  rpc: string,
  args: Record<string, unknown>,
): Promise<Result<OrderRecord>> => {
  if (!client) return noClient();
  const { data, error } = await client.rpc(rpc, args);
  return error ? serviceError(rpc, error) : { ok: true, data: data as OrderRecord };
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
  segnaConsegnato: (id) =>
    transizione(client, "ordine_segna_consegnato", { p_order_id: id }),
  confermaRicezione: (id) => transizione(client, "conferma_ricezione", { p_order_id: id }),
  contesta: (id, motivo) =>
    transizione(client, "ordine_contesta", { p_order_id: id, p_motivo: motivo }),
});
