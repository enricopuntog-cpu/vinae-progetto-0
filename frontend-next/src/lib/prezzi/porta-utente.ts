// WI-016 — stima per la scheda del vino e per la Cantina. La porta del database (`prezzi_vino_osservazioni`) è SPENTA
// per difetto e legge solo lo storico già pubblico; la stima è quella del motore WI-014: solo vendite concluse
// comparabili, «dati insufficienti» sotto la soglia, nessun prezzo inventato.

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Result } from "@/services/types";
import { codiceErrore } from "@/lib/errore-per-log";
import { raccogliOsservazioni } from "./acquisizione";
import { valutaPrezzo, type SoggettoValutazione, type Valutazione } from "./valutazione";

export type EsitoStimaUtente = { stato: "spenta" } | { stato: "valutata"; valutazione: Valutazione };

const ERRORE = "La stima non è disponibile in questo momento.";
/** Soggetto impossibile: senza un vino e un formato riconosciuti il motore risponde «dati insufficienti». */
const SENZA_SOGGETTO: SoggettoValutazione = { vinoId: "", annata: null, formatoMl: null, valuta: "eur" };

type Porta = { abilitata?: unknown; soggetto?: SoggettoValutazione | null; osservazioni?: unknown[] };

const leggiPorta = async (client: SupabaseClient, slug: string, formato: string) =>
  client.rpc("prezzi_vino_osservazioni", { p_wine_slug: slug, p_formato: formato });

/** Una sola domanda per sapere se mostrare il comando. Qualunque dubbio vale «no». */
export async function stimaUtenteDisponibile(client: SupabaseClient | null): Promise<boolean> {
  if (!client) return false;
  try {
    const { data, error } = await leggiPorta(client, "", "");
    return !error && (data as Porta | null)?.abilitata === true;
  } catch (errore) {
    console.error("[stima-prezzo] disponibilità non letta:", codiceErrore(errore));
    return false;
  }
}

export async function leggiStimaUtente(
  client: SupabaseClient,
  wineSlug: string,
  formato: string,
  adesso: Date,
): Promise<Result<EsitoStimaUtente>> {
  try {
    const { data, error } = await leggiPorta(client, wineSlug, formato);
    if (error || !data) return { ok: false, error: ERRORE };
    const porta = data as Porta;
    if (porta.abilitata !== true) return { ok: true, data: { stato: "spenta" } };
    const raccolta = await raccogliOsservazioni(
      [
        {
          nome: "vinea_interno",
          autorizzata: true,
          finalita: "riferimento di mercato mostrato all'utente sui prezzi già pubblici del marketplace Vinea",
          leggi: async () => porta.osservazioni ?? [],
        },
      ],
      { attiva: true },
    );
    if (raccolta.esito !== "raccolte") return { ok: true, data: { stato: "spenta" } };
    return {
      ok: true,
      data: { stato: "valutata", valutazione: valutaPrezzo(porta.soggetto ?? SENZA_SOGGETTO, raccolta.osservazioni, adesso) },
    };
  } catch (errore) {
    console.error("[stima-prezzo] stima non letta:", codiceErrore(errore));
    return { ok: false, error: ERRORE };
  }
}
