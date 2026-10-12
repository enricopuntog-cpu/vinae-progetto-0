import type { SupabaseClient } from "@supabase/supabase-js";
import { noClient, serviceError } from "@/services/phase7/shared";
import type { MarketplaceConfigPubblica, MarketplaceConfigService } from "@/services/types";

/**
 * Legge la configurazione corrente di una classe dalla vista
 * `public_marketplace_config`, non dalla tabella: la tabella non ha alcun
 * `GRANT` verso i ruoli client, e la vista espone cinque colonne delle sole
 * righe aperte, una per classe di venditore (VP-D). Una colonna aggiunta
 * domani alla configurazione resta privata finché qualcuno non la elenca nella
 * vista di proposito.
 *
 * Serve a calcolare un preventivo **prima** che un ordine esista. Per un ordine
 * già creato la fonte è la riga dell'ordine, dove i parametri sono congelati:
 * usare questa al suo posto è esattamente il bug che
 * `scomposizioneOrdine` esiste per rendere difficile.
 */
export const createMarketplaceConfigService = (
  client: SupabaseClient | null,
): MarketplaceConfigService => ({
  corrente: async (classe) => {
    if (!client) return noClient();
    const { data, error } = await client
      .from("public_marketplace_config")
      .select(
        "margine_obiettivo_bps,riferimento_stripe_percentuale_bps," +
          "riferimento_stripe_fisso_cents,auto_rilascio_giorni,classe_venditore",
      )
      .eq("classe_venditore", classe)
      .maybeSingle();
    return error
      ? serviceError("public_marketplace_config.select", error)
      : { ok: true, data: data as MarketplaceConfigPubblica | null };
  },
});
