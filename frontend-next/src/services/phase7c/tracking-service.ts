import type { SupabaseClient } from "@supabase/supabase-js";
import { noClient, serviceError } from "@/services/phase7/shared";
import type { TrackingEventRecord, TrackingService } from "@/services/types";

/**
 * La timeline che l'utente legge, da `public.tracking_events`.
 *
 * Sola lettura, e non per pigrizia: la tabella non ha alcun `GRANT` di
 * scrittura verso i ruoli client. Le righe nascono dalle RPC di dominio e da un
 * trigger su `orders` — un client che potesse inserire scriverebbe
 * «Consegnato» su un ordine mai partito.
 *
 * Qui il `select` di tabella intera è corretto: la policy limita
 * `authenticated` alle sole righe dei propri ordini, e ogni colonna esiste per
 * essere letta da quelle due persone. È il caso opposto a `orders`, che ha
 * colonne raggiungibili per riga ma non leggibili per colonna.
 */
export const createTrackingService = (client: SupabaseClient | null): TrackingService => ({
  perOrdine: async (orderId) => {
    if (!client) return noClient();
    const { data, error } = await client
      .from("tracking_events")
      .select("id,order_id,tipo,titolo,descrizione,luogo,created_at")
      .eq("order_id", orderId)
      .order("created_at", { ascending: true })
      .order("id", { ascending: true });
    return error
      ? serviceError("tracking_events.select", error)
      : { ok: true, data: (data ?? []) as TrackingEventRecord[] };
  },
});
