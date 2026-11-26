// WI-008 — scelta PERSONALE di una scheda del catalogo per un vino della propria Cantina.
//
// Qui non c'è autorità: il database verifica possesso e codice (`cellar_catalogo_scegli`) e la scelta resta privata,
// reversibile e non verificata da un curatore. Non è il collegamento canonico (`catalog.wine_links`), che resta del
// curatore. Fail-closed: qualunque errore in lettura vale «nessun catalogo, nessuna scelta» e la Cantina non cambia.

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Result } from "@/services/types";
import { codiceErrore } from "@/lib/errore-per-log";
import { eCodiceScheda } from "@/lib/wine-intelligence/codice-scheda";

export type SelezioniCatalogo = {
  /** Il catalogo è consultabile: solo allora si propone di collegare una scheda. */
  disponibile: boolean;
  /** slug del vino → codice della scheda scelta dall'utente (LWIN-7, oppure UUID se la scheda non ha LWIN). */
  scelte: Record<string, string>;
};

export const NESSUNA_SELEZIONE: SelezioniCatalogo = Object.freeze({ disponibile: false, scelte: {} });

const ERRORE_SCELTA = "Non è stato possibile collegare la scheda del catalogo. Riprova tra poco.";
const ERRORE_RIMOZIONE = "Non è stato possibile rimuovere il collegamento. Riprova tra poco.";

export async function leggiSelezioniCatalogo(client: SupabaseClient | null): Promise<SelezioniCatalogo> {
  if (!client) return { disponibile: false, scelte: {} };
  try {
    const [stato, righe] = await Promise.all([
      client.rpc("catalogo_canonico_disponibile"),
      client.from("wine_catalog_selections").select("lwin7, catalog_wine_id, wines!inner(slug)"),
    ]);
    const scelte: Record<string, string> = {};
    const lette = (righe.error ? [] : (righe.data ?? [])) as unknown as {
      lwin7?: unknown;
      catalog_wine_id?: unknown;
      wines?: unknown;
    }[];
    for (const riga of lette) {
      const vino = (Array.isArray(riga.wines) ? riga.wines[0] : riga.wines) as { slug?: unknown } | null | undefined;
      const codice = riga.lwin7 ?? riga.catalog_wine_id;
      if (typeof vino?.slug === "string" && eCodiceScheda(codice)) scelte[vino.slug] = codice;
    }
    return { disponibile: !stato.error && stato.data === true, scelte };
  } catch (errore) {
    console.error("[catalogo-cantina] lettura non riuscita:", codiceErrore(errore));
    return { disponibile: false, scelte: {} };
  }
}

/** Restituisce il codice salvato dal server (un codice Combined torna come il vino di destinazione). */
export async function scegliSchedaCatalogo(client: SupabaseClient, wineSlug: string, codice: string): Promise<Result<string>> {
  try {
    // Il parametro conserva il nome storico `p_lwin7` (PostgREST chiama per nome) e accetta il codice della scheda.
    const { data, error } = await client.rpc("cellar_catalogo_scegli", { p_wine_slug: wineSlug, p_lwin7: codice });
    if (error || !eCodiceScheda(data)) return { ok: false, error: ERRORE_SCELTA };
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
