import type { SupabaseClient } from "@supabase/supabase-js";
import { noClient, serviceError } from "@/services/phase7/shared";
import type { SellerPayoutAccount, SellerPayoutService } from "@/services/types";

/**
 * Adapter del dominio incassi del venditore.
 *
 * Non esiste un metodo che abiliti un venditore, e nessuna quantità di codice
 * qui potrebbe aggiungerlo: `charges_enabled` e `payouts_enabled` non sono nei
 * `GRANT` di scrittura di nessun ruolo client, e il ruolo `seller_enabled` è
 * derivato da un trigger. Da qui si può avviare l'onboarding e leggere ciò che
 * il fornitore ha già dichiarato.
 *
 * `provider_account_id` non compare fra le colonne selezionate perché non è
 * nemmeno leggibile: è l'identificativo con cui si muove denaro, e il `GRANT`
 * di colonna lo esclude. Chiederlo restituirebbe un errore, non una riga
 * parziale.
 */
export const createSellerPayoutService = (
  client: SupabaseClient | null,
): SellerPayoutService => ({
  avviaOnboarding: async () => {
    if (!client) return noClient();
    const { data, error } = await client.functions.invoke("connect-onboarding", { body: {} });
    if (error) return serviceError("connect-onboarding", error);
    const risposta = data as { onboardingUrl?: string; expiresAt?: string | null } | null;
    return risposta?.onboardingUrl
      ? { ok: true, data: { onboardingUrl: risposta.onboardingUrl, expiresAt: risposta.expiresAt ?? null } }
      : { ok: false, error: "L'onboarding non ha restituito un indirizzo valido." };
  },

  mioAccount: async () => {
    if (!client) return noClient();
    const { data: auth } = await client.auth.getUser();
    if (!auth.user) return { ok: false, error: "Autenticazione richiesta." };
    const { data, error } = await client
      .from("seller_payout_accounts")
      .select(
        "id,seller_id,provider,charges_enabled,payouts_enabled,details_submitted," +
          "requisiti_pendenti,disabled_reason,created_at,updated_at",
      )
      .eq("seller_id", auth.user.id)
      .maybeSingle();
    return error
      ? serviceError("seller_payout_accounts.select", error)
      : { ok: true, data: data as SellerPayoutAccount | null };
  },
});
