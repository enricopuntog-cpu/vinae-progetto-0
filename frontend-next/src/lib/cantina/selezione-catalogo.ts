// WI-008 — scelta PERSONALE di una scheda del catalogo per un vino della propria Cantina.
//
// Qui non c'è autorità: il database verifica possesso e codice (`cellar_catalogo_scegli`) e la scelta resta privata,
// reversibile e non verificata da un curatore. Non è il collegamento canonico (`catalog.wine_links`), che resta del
// curatore. Fail-closed: qualunque errore in lettura vale «nessun catalogo, nessuna scelta» e la Cantina non cambia.

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Result } from "@/services/types";
import { codiceErrore } from "@/lib/errore-per-log";

export type SelezioniCatalogo = {
  /** Il catalogo è consultabile: solo allora si propone di collegare una scheda. */
  disponibile: boolean;
  /** slug del vino → LWIN-7 scelto dall'utente. */
  scelte: Record<string, string>;
};

export const NESSUNA_SELEZIONE: SelezioniCatalogo = Object.freeze({ disponibile: false, scelte: {} });

const LWIN7 = /^[0-9]{7}$/;
const ERRORE_SCELTA = "Non è stato possibile collegare la scheda del catalogo. Riprova tra poco.";
const ERRORE_RIMOZIONE = "Non è stato possibile rimuovere il collegamento. Riprova tra poco.";

export async function leggiSelezioniCatalogo(client: SupabaseClient | null): Promise<SelezioniCatalogo> {
  if (!client) return { disponibile: false, scelte: {} };
  try {
    const [stato, righe] = await Promise.all([
      client.rpc("catalogo_canonico_disponibile"),
      client.from("wine_catalog_selections").select("lwin7, wines!inner(slug)"),
    ]);
    const scelte: Record<string, string> = {};
    for (const riga of (righe.error ? [] : (righe.data ?? [])) as unknown as { lwin7?: unknown; wines?: unknown }[]) {
      const vino = (Array.isArray(riga.wines) ? riga.wines[0] : riga.wines) as { slug?: unknown } | null | undefined;
      if (typeof vino?.slug === "string" && typeof riga.lwin7 === "string" && LWIN7.test(riga.lwin7)) {
        scelte[vino.slug] = riga.lwin7;
      }
    }
    return { disponibile: !stato.error && stato.data === true, scelte };
  } catch (errore) {
    console.error("[catalogo-cantina] lettura non riuscita:", codiceErrore(errore));
    return { disponibile: false, scelte: {} };
  }
}

/** Restituisce il codice salvato dal server (un codice Combined torna come il vino di destinazione). */
export async function scegliSchedaCatalogo(client: SupabaseClient, wineSlug: string, lwin7: string): Promise<Result<string>> {
  try {
    const { data, error } = await client.rpc("cellar_catalogo_scegli", { p_wine_slug: wineSlug, p_lwin7: lwin7 });
    if (error || typeof data !== "string" || !LWIN7.test(data)) return { ok: false, error: ERRORE_SCELTA };
    return { ok: true, data };
  } catch (errore) {
    console.error("[catalogo-cantina] scelta non riuscita:", codiceErrore(errore));
    return { ok: false, error: ERRORE_SCELTA };
  }
}

export async function rimuoviSchedaCatalogo(client: SupabaseClient, wineSlug: string): Promise<Result<void>> {
  try {
    const { error } = await client.rpc("cellar_catalogo_rimuovi", { p_wine_slug: wineSlug });
    return error ? { ok: false, error: ERRORE_RIMOZIONE } : { ok: true, data: undefined };
  } catch (errore) {
    console.error("[catalogo-cantina] rimozione non riuscita:", codiceErrore(errore));
    return { ok: false, error: ERRORE_RIMOZIONE };
  }
}
