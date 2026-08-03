import type { SupabaseClient } from "@supabase/supabase-js";
import { noClient, serviceError } from "@/services/phase7/shared";
import type { MarketplaceConfigPubblica, MarketplaceConfigService } from "@/services/types";

/**
 * Legge la configurazione corrente dalla vista `public_marketplace_config`, non
 * dalla tabella: la tabella non ha alcun `GRANT` verso i ruoli client, e la
 * vista espone due sole colonne della sola riga aperta. Una colonna aggiunta
 * domani alla configurazione resta privata finché qualcuno non la elenca nella
 * vista di proposito.
 *
 * Serve a mostrare la commissione **prima** che un ordine esista. Per un ordine
 * già creato la fonte è la riga dell'ordine, dove la percentuale è congelata:
 * usare questa al suo posto è esattamente il bug che
 * `scomposizioneOrdine` esiste per rendere difficile.
 */
export const createMarketplaceConfigService = (
  client: SupabaseClient | null,
): MarketplaceConfigService => ({
  corrente: async () => {
    if (!client) return noClient();
    const { data, error } = await client
      .from("public_marketplace_config")
      .select("commissione_bps,auto_rilascio_giorni")
      .maybeSingle();
    return error
      ? serviceError("public_marketplace_config.select", error)
      : { ok: true, data: data as MarketplaceConfigPubblica | null };
  },
});
