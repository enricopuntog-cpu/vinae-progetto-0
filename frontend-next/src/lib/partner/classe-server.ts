import { isAuthRetryableFetchError, type SupabaseClient } from "@supabase/supabase-js";
import { classeCommerciale } from "@/lib/partner/vetrina";
import { creaPartnerService } from "@/services/partner-service";
import type { Partner } from "@/services/types";

/**
 * La classe del chiamante, letta dal SERVER con la sua sessione.
 *
 * È il punto in cui `/cantina`, la degustazione, `/vendi` e la scheda annuncio
 * decidono quale interfaccia mostrare: la decisione viene da `partner_me()`,
 * cioè dalla riga di `private.partners`, mai da un dato del client o dalle
 * qualifiche personali.
 *
 * Tre risposte, non due. «Privato» e «non lo so» non sono la stessa cosa: se
 * la lettura del Partner fallisce, un titolare non deve vedersi offrire la
 * Cantina da collezionista o il wizard di vendita privata come se fosse un
 * privato. Ogni superficie decide da sé come mostrare `errore`; i veri privati
 * — e gli anonimi, che non possono essere Partner — vedono la pagina di
 * sempre.
 *
 * Non è un'autorità sul denaro: quella restano i gate del database su ordini e
 * proposte.
 */
export type ClasseChiamante =
  | { tipo: "privato" }
  | { tipo: "commerciale"; partner: Partner; titolareId: string }
  | { tipo: "errore" };

const PRIVATO: ClasseChiamante = { tipo: "privato" };
const ERRORE: ClasseChiamante = { tipo: "errore" };

export async function classeDelChiamante(client: SupabaseClient | null): Promise<ClasseChiamante> {
  // Senza Supabase configurato non esiste nessun Partner: è la modalità
  // dimostrativa, che resta quella di sempre.
  if (!client) return PRIVATO;
  const {
    data: { user },
    error,
  } = await client.auth.getUser();
  if (!user) {
    // Nessuna sessione è un anonimo. Un guasto di rete verso Auth no: non si
    // sa chi sia, quindi non lo si tratta come un privato.
    return error && isAuthRetryableFetchError(error) ? ERRORE : PRIVATO;
  }
  const esito = await creaPartnerService(client).mio();
  if (!esito.ok) return ERRORE;
  if (esito.data && classeCommerciale(esito.data.stato)) {
    return { tipo: "commerciale", partner: esito.data, titolareId: user.id };
  }
  return PRIVATO;
}
