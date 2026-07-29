/**
 * Metadati di bevuta e abbinamenti letti da `wines` (Fase 6c-1) invece che da
 * `getWineMeta()` in src/data/cellar.ts.
 *
 * PERCHÉ IL MOCK RESTA COME RIPIEGO. `getWineMeta()` non restituisce "niente"
 * per un vino che non conosce: restituisce `DEFAULT_META`, cioè quattro
 * abbinamenti veri, 16–18 °C, calice universale e 30 minuti di decantazione.
 * È quello che il sito mostra oggi per il vino creato dal wizard in Fase 6b
 * (`ceretto-barolo-bricco-rocche-2016`), che nel database ha finestra
 * `unavailable`, abbinamenti vuoti e temperatura vuota. Collegare la lettura al
 * database senza questo ripiego farebbe sparire da quella scheda quattro
 * abbinamenti e tre statistiche su quattro: una regressione vera, causata dalla
 * migrazione. Quando la riga non porta informazione si torna quindi a
 * `getWineMeta(slug)`, che è esattamente il comportamento di oggi.
 */

import { getWineMeta, type FoodPairing, type WineVintageMeta } from "@/data/cellar";
import type { SupabaseClient } from "@supabase/supabase-js";

/** Colonne di `wines` che compongono un WineVintageMeta. */
export const COLONNE_META = [
  "slug",
  "finestra_inizio",
  "finestra_fine",
  "apice_inizio",
  "apice_fine",
  "finestra_fonte",
  "finestra_affidabilita",
  "finestra_aggiornata_at",
  "temperatura_servizio",
  "decantazione_minuti",
  "calice",
  "occasione",
  "abbinamenti",
].join(",");

export type RigaMetaVino = {
  slug: string;
  finestra_inizio: number | null;
  finestra_fine: number | null;
  apice_inizio: number | null;
  apice_fine: number | null;
  finestra_fonte: WineVintageMeta["source"];
  finestra_affidabilita: WineVintageMeta["confidence"] | null;
  finestra_aggiornata_at: string | null;
  temperatura_servizio: string;
  decantazione_minuti: number | null;
  calice: string;
  occasione: string;
  abbinamenti: FoodPairing[] | null;
};

/**
 * Una riga senza fonte, senza abbinamenti e senza temperatura non dice nulla
 * che l'interfaccia possa mostrare: è la traduzione di "questo id non è nella
 * tabella mock". Si controllano tutti e tre i campi e non solo la fonte, così
 * un vino con abbinamenti reali ma finestra ancora ignota conserva ciò che ha
 * invece di essere sostituito in blocco.
 */
function rigaVuota(riga: RigaMetaVino): boolean {
  return (
    riga.finestra_fonte === "unavailable" &&
    (riga.abbinamenti?.length ?? 0) === 0 &&
    riga.temperatura_servizio.trim() === ""
  );
}

export function rigaAMeta(riga: RigaMetaVino): WineVintageMeta {
  if (rigaVuota(riga)) return getWineMeta(riga.slug);

  const ripiego = getWineMeta(riga.slug);

  return {
    drinkWindowStart: riga.finestra_inizio ?? undefined,
    drinkWindowEnd: riga.finestra_fine ?? undefined,
    peakStart: riga.apice_inizio ?? undefined,
    peakEnd: riga.apice_fine ?? undefined,
    source: riga.finestra_fonte,
    confidence: riga.finestra_affidabilita ?? "bassa",
    foodPairings: riga.abbinamenti ?? [],
    // Le tre stringhe hanno `default ''` nello schema: vuoto significa "non
    // compilato", non "assente per scelta", quindi si ripiega sul valore che la
    // scheda mostrerebbe comunque invece di lasciare una statistica bianca.
    servingTemperature: riga.temperatura_servizio || ripiego.servingTemperature,
    decantingMinutes: riga.decantazione_minuti ?? undefined,
    glassType: riga.calice || ripiego.glassType,
    occasione: riga.occasione || undefined,
    lastUpdatedAt: riga.finestra_aggiornata_at ?? "",
  };
}

/**
 * Metadati per un elenco di slug. Ritorna una mappa vuota in caso di errore: i
 * componenti ripiegano da soli su `getWineMeta`, quindi una lettura fallita
 * degrada al comportamento di oggi invece di svuotare la pagina.
 */
export async function caricaMetaPerVino(
  client: SupabaseClient | null,
  slugs: string[],
): Promise<Record<string, WineVintageMeta>> {
  const richiesti = Array.from(new Set(slugs.filter(Boolean)));
  if (!client || richiesti.length === 0) return {};

  const { data, error } = await client
    .from("wines")
    .select(COLONNE_META)
    .in("slug", richiesti);

  if (error) {
    console.error("[wine-meta] lettura fallita:", error);
    return {};
  }

  const mappa: Record<string, WineVintageMeta> = {};
  for (const riga of data as unknown as RigaMetaVino[]) {
    mappa[riga.slug] = rigaAMeta(riga);
  }
  return mappa;
}
