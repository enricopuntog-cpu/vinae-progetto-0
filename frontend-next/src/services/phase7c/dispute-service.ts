import type { SupabaseClient } from "@supabase/supabase-js";
import { noClient, serviceError } from "@/services/phase7/shared";
import type { DisputeRecord, DisputeService, OrderRecord } from "@/services/types";

/**
 * Le colonne del fascicolo leggibili dalle parti. `risolta_da` non c'è, e
 * l'assenza è la ragione per cui questo elenco è esplicito: la colonna esiste,
 * il venditore raggiunge la riga, ma chi ha deciso la pratica è dato di
 * moderazione e resta fuori dal `GRANT`.
 */
const COLONNE_DISPUTE =
  "id,order_id,aperta_da,motivo,descrizione,foto,stato,esito_nota,apertura_at,chiusura_at";

/**
 * Apertura e lettura di una contestazione.
 *
 * **Nessun metodo di risoluzione, ed è il punto.** In `frontend/` il pannello
 * mostrava a entrambe le parti tre bottoni che chiudevano la pratica, sotto la
 * scritta «Azioni demo — simula l'esito». Era impalcatura da demo, non un
 * modello di permessi: portarla alla lettera lascerebbe a una parte in causa il
 * potere di decidere la propria controversia, e a un venditore quello di
 * respingere la contestazione che blocca i suoi stessi fondi.
 *
 * `ordine_contestazione_risolvi` esiste nella migrazione ma non ha alcun
 * `GRANT` verso `authenticated`: è back-office, e non è chiamabile da qui
 * nemmeno scrivendone il nome.
 */
export const createDisputeService = (client: SupabaseClient | null): DisputeService => ({
  apri: async ({ orderId, motivo, descrizione, foto }) => {
    if (!client) return noClient();
    const { data, error } = await client.rpc("ordine_contestazione_apri", {
      p_order_id: orderId,
      p_motivo: motivo,
      p_descrizione: descrizione,
      p_foto: foto ?? [],
    });
    return error
      ? serviceError("ordine_contestazione_apri", error)
      : { ok: true, data: data as OrderRecord };
  },

  perOrdine: async (orderId) => {
    if (!client) return noClient();
    const { data, error } = await client
      .from("disputes")
      .select(COLONNE_DISPUTE)
      .eq("order_id", orderId)
      .maybeSingle();
    return error
      ? serviceError("disputes.select", error)
      : { ok: true, data: data as DisputeRecord | null };
  },
});
