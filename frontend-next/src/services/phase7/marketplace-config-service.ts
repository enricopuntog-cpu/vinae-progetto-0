import type { SupabaseClient } from "@supabase/supabase-js";
import { noClient, serviceError } from "@/services/phase7/shared";
import type { MarketplaceConfigPubblica, MarketplaceConfigService } from "@/services/types";

/**
 * Legge la configurazione corrente dalla vista `public_marketplace_config`, non
 * dalla tabella: la tabella non ha alcun `GRANT` verso i ruoli client, e la
 * vista espone quattro sole colonne della sola riga aperta. Una colonna
 * aggiunta domani alla configurazione resta privata finché qualcuno non la
 * elenca nella vista di proposito.
 *
 * Serve a calcolare un preventivo **prima** che un ordine esista. Per un ordine
 * già creato la fonte è la riga dell'ordine, dove i parametri sono congelati:
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
      .select(
        "margine_obiettivo_bps,riferimento_stripe_percentuale_bps," +
          "riferimento_stripe_fisso_cents,auto_rilascio_giorni",
      )
      .maybeSingle();
    return error
      ? serviceError("public_marketplace_config.select", error)
      : { ok: true, data: data as MarketplaceConfigPubblica | null };
  },
});
