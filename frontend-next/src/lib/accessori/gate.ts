import type { SupabaseClient } from "@supabase/supabase-js";
import { valoreFlagEsattamenteTrue } from "@/config/features";
import { eAdminReale } from "@/lib/auth/role";

/**
 * Gate delle route Accessori (VPM-015A).
 *
 * Tre chiavi, tutte da superare per mostrare qualcosa al PUBBLICO:
 *
 * 1. `NEXT_PUBLIC_ACCESSORI_ENABLED` — solo la navigazione; è nel bundle del
 *    browser e non autorizza niente;
 * 2. `ACCESSORI_ENABLED` — questo gate server, letto qui. Come i Club, si apre
 *    solo se anche la variabile pubblica è la stringa esatta `true`;
 * 3. `private.accessori_impostazioni.visibilita_pubblica` — l'interruttore nel
 *    database, spento di default: con esso spento le letture pubbliche
 *    restituiscono comunque vuoto.
 *
 * L'ANTEPRIMA è un'altra cosa: la vede soltanto un admin reale (ruolo in
 * `public.user_roles`, mai il selettore demo), anche con le flag spente, e il
 * database la riconosce da sé (`p_anteprima` richiede il ruolo admin). Così la
 * Beta si verifica in produzione senza accendere nulla al pubblico.
 *
 * Qualsiasi dubbio chiude: senza client Supabase, o con un errore nella lettura
 * dei ruoli, non si apre niente.
 */

export type ModalitaAccessori = "pubblica" | "anteprima";

export const accessoriPubbliciAbilitatiServer = (): boolean =>
  valoreFlagEsattamenteTrue(process.env.ACCESSORI_ENABLED) &&
  valoreFlagEsattamenteTrue(process.env.NEXT_PUBLIC_ACCESSORI_ENABLED);

/** La decisione, senza I/O: l'admin reale ha l'anteprima, gli altri il pubblico se acceso. */
export function decidiModalitaAccessori(input: {
  pubbliciAbilitati: boolean;
  adminReale: boolean;
}): ModalitaAccessori | null {
  if (input.adminReale) return "anteprima";
  return input.pubbliciAbilitati ? "pubblica" : null;
}

/** `null` significa «non c'è nulla da vedere»: la pagina risponde 404. */
export async function risolviModalitaAccessori(
  client: SupabaseClient | null,
  pubbliciAbilitati: boolean = accessoriPubbliciAbilitatiServer(),
): Promise<ModalitaAccessori | null> {
  if (!client) return null;

  let adminReale = false;
  try {
    const { data: sessione } = await client.auth.getUser();
    const utente = sessione.user;
    if (utente) {
      const { data, error } = await client
        .from("user_roles")
        .select("role")
        .eq("user_id", utente.id);
      const ruoli = error
        ? []
        : (data ?? [])
            .map((riga) => (riga as { role: unknown }).role)
            .filter((ruolo): ruolo is string => typeof ruolo === "string");
      adminReale = eAdminReale(ruoli);
    }
  } catch {
    // Un guasto non apre l'anteprima: si cade sul solo gate pubblico.
    adminReale = false;
  }

  return decidiModalitaAccessori({ pubbliciAbilitati, adminReale });
}
