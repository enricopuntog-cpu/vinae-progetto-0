import type { SupabaseClient } from "@supabase/supabase-js";
import { noClient, serviceError } from "@/services/phase7/shared";
import type { OrderReviewRecord, ReviewService } from "@/services/types";

const COLONNE_RECENSIONE =
  "id,order_id,autore_id,destinatario_id,voto,conformita,imballaggio,comunicazione,testo,created_at";

/**
 * Recensione dell'ordine, una sola per ordine e solo dal compratore.
 *
 * La lettura è ristretta alle parti: in `frontend/` la recensione si vede
 * soltanto nella pagina dell'ordine e non alimenta alcuna reputazione visibile
 * a terzi. Una vista pubblica per la reputazione del venditore sarebbe prodotto
 * nuovo oltre la deviazione già autorizzata, e richiederebbe comunque una vista
 * `security_invoker = off` a colonne chiuse.
 */
export const createReviewService = (client: SupabaseClient | null): ReviewService => ({
  invia: async ({ orderId, voto, conformita, imballaggio, comunicazione, testo }) => {
    if (!client) return noClient();
    const { data, error } = await client.rpc("ordine_recensisci", {
      p_order_id: orderId,
      p_voto: voto,
      p_conformita: conformita,
      p_imballaggio: imballaggio,
      p_comunicazione: comunicazione,
      p_testo: testo ?? null,
    });
    return error
      ? serviceError("ordine_recensisci", error)
      : { ok: true, data: data as OrderReviewRecord };
  },

  perOrdine: async (orderId) => {
    if (!client) return noClient();
    const { data, error } = await client
      .from("order_reviews")
      .select(COLONNE_RECENSIONE)
      .eq("order_id", orderId)
      .maybeSingle();
    return error
      ? serviceError("order_reviews.select", error)
      : { ok: true, data: data as OrderReviewRecord | null };
  },
});
