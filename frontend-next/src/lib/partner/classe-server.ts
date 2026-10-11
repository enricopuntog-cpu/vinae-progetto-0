import type { SupabaseClient } from "@supabase/supabase-js";
import { classeCommerciale } from "@/lib/partner/vetrina";
import { creaPartnerService } from "@/services/partner-service";
import type { Partner } from "@/services/types";

/**
 * Il Partner del chiamante, soltanto se lo rende un venditore professionale
 * (attivo o sospeso), letto dal SERVER con la sua sessione.
 *
 * È il punto in cui `/cantina`, la degustazione e `/vendi` decidono quale
 * interfaccia mostrare: la decisione viene da `partner_me()`, cioè dalla riga
 * di `private.partners`, mai da un dato del client o dalle qualifiche
 * personali.
 *
 * Fail-open verso l'interfaccia di oggi: senza sessione, senza Partner o con
 * una lettura fallita risponde `null` e il privato non vede nulla di diverso.
 * Non è un'autorità sul denaro — quella restano i gate del database su ordini
 * e proposte — quindi l'errore non chiude nulla di commerciale.
 */
export async function partnerCommercialeDelChiamante(
  client: SupabaseClient | null,
): Promise<{ partner: Partner; titolareId: string } | null> {
  if (!client) return null;
  const {
    data: { user },
  } = await client.auth.getUser();
  if (!user) return null;
  const esito = await creaPartnerService(client).mio();
  if (!esito.ok || !esito.data) return null;
  return classeCommerciale(esito.data.stato) ? { partner: esito.data, titolareId: user.id } : null;
}
