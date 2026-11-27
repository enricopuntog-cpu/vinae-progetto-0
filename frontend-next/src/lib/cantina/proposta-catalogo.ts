// WI-011 — «Proponi al catalogo Vinea»: un gesto ESPLICITO, con consenso per quella richiesta. Aggiungere una
// bottiglia alla Cantina o scegliere una scheda non propone nulla. Il client manda solo dati enologici; il database
// ricontrolla ogni cosa (interruttore, possesso, elenco chiuso di campi, limiti) e nessuna proposta entra nel catalogo
// senza revisione. Fail-closed: con le proposte spente il comando non compare.

import type { SupabaseClient } from "@supabase/supabase-js";
import type { EsitoConsensoCatalogo, Result } from "@/services/types";
import { codiceErrore } from "@/lib/errore-per-log";

export type VinoPerProposta = {
  produttore: string;
  nome: string;
  annata: number | null;
  regione: string;
  denominazione: string;
  tipo: string;
  formato: string;
};

export type CampiProposta = { produttore: string; nome: string; annata: string; regione: string; denominazione: string };

export type Proposta = { origine: "cantina" | "correzione" | "manuale" | "ocr"; dati: Record<string, string | number> };

const ERRORE_GENERICO = "Non è stato possibile inviare la proposta. Riprova più tardi.";
const ERRORE_LETTURA = "Non è stato possibile leggere le tue proposte. Riprova più tardi.";

/** «0,75 L» → 750. Un formato non riconosciuto resta assente: non si indovina. */
export function formatoInMl(testo: string): number | null {
  const m = /^([0-9]{1,5})(?:[.,]([0-9]{1,3}))?\s*(ml|cl|l)$/.exec(testo.trim().toLowerCase());
  if (!m) return null;
  const ml = Number(`${m[1]}.${m[2] ?? "0"}`) * (m[3] === "l" ? 1000 : m[3] === "cl" ? 10 : 1);
  return Number.isInteger(ml) && ml >= 50 && ml <= 30000 ? ml : null;
}

const compatta = (t: string): string => t.replace(/\s+/g, " ").trim();

export function preparaProposta(vino: VinoPerProposta, campi: CampiProposta): Result<Proposta> {
  const produttore = compatta(campi.produttore);
  const nome = compatta(campi.nome);
  if (!produttore || !nome) return { ok: false, error: "Produttore e nome del vino sono necessari." };
  const testoAnnata = campi.annata.trim();
  let annata: number | null = null;
  if (testoAnnata) {
    annata = Number(testoAnnata);
    if (!/^[0-9]{4}$/.test(testoAnnata) || annata < 1800 || annata > new Date().getFullYear() + 1) {
      return { ok: false, error: "L'annata non è valida. Lasciala vuota se non la conosci." };
    }
  }
  const regione = compatta(campi.regione);
  const denominazione = compatta(campi.denominazione);
  const modificato =
    produttore !== compatta(vino.produttore) ||
    nome !== compatta(vino.nome) ||
    annata !== (vino.annata ?? null) ||
    regione !== compatta(vino.regione) ||
    denominazione !== compatta(vino.denominazione);
  const ml = formatoInMl(vino.formato);
  const dati: Record<string, string | number> = { produttore, nome };
  if (annata !== null) dati.annata = annata;
  if (regione) dati.regione = regione;
  if (denominazione) dati.denominazione = denominazione;
  if (compatta(vino.tipo)) dati.tipo = compatta(vino.tipo);
  if (ml !== null) dati.formato_ml = ml;
  return { ok: true, data: { origine: modificato ? "correzione" : "cantina", dati } };
}

/**
 * Nel wizard: si chiede solo con una sessione (la porta non è eseguibile da `anon`, che riceverebbe un 401) e solo per un
 * vino NUOVO; da una bottiglia già in Cantina la proposta parte dalla Cantina.
 */
export async function proposteDisponibiliPerNuovoVino(
  client: SupabaseClient | null,
  { autenticato, daCantina }: { autenticato: boolean; daCantina: boolean },
): Promise<boolean> {
  if (!autenticato || daCantina) return false;
  return proposteDisponibili(client);
}

export async function proposteDisponibili(client: SupabaseClient | null): Promise<boolean> {
  if (!client) return false;
  try {
    const { data, error } = await client.rpc("catalogo_proposte_disponibili");
    return !error && data === true;
  } catch (errore) {
    console.error("[catalogo-proposte] disponibilità non letta:", codiceErrore(errore));
    return false;
  }
}

export async function inviaPropostaCatalogo(client: SupabaseClient, wineSlug: string, proposta: Proposta): Promise<Result<void>> {
  try {
    const { data, error } = await client.rpc("catalogo_proponi", {
      p_origine: proposta.origine,
      p_dati: proposta.dati,
      p_consenso: true,
      p_wine_slug: wineSlug,
    });
    if (error || data !== "ricevuta") {
      // `non_valida` (WI-015): i dati non descrivono un vino. La porta non solleva, così la quota giornaliera conta.
      return {
        ok: false,
        error:
          data === "non_valida" || error?.code === "22023"
            ? "Controlla i dati inseriti: qualcosa non è un'informazione sul vino."
            : ERRORE_GENERICO,
      };
    }
    return { ok: true, data: undefined };
  } catch (errore) {
    console.error("[catalogo-proposte] invio non riuscito:", codiceErrore(errore));
    return { ok: false, error: ERRORE_GENERICO };
  }
}

// ---------------------------------------------------------------------------
// WI-016 — il consenso del wizard viaggia nella STESSA chiamata che crea la bottiglia (persistente nella stessa
// transazione): una pagina chiusa non perde più la proposta, quindi il client non la invia e non la ripete.
// ---------------------------------------------------------------------------

/** `ocr` solo quando l'utente ha CONFERMATO i dati letti dall'etichetta; altrimenti `manuale`. */
export const origineConsenso = (daEtichettaConfermata: boolean): "manuale" | "ocr" => (daEtichettaConfermata ? "ocr" : "manuale");

/**
 * Messaggio per l'utente; `null` quando non serve aggiungere nulla. La bottiglia è comunque in Cantina.
 * `richiesta`: il consenso è partito con QUESTA creazione; `ripetuta`: il server ha riconosciuto un nuovo tentativo
 * (replay), per il quale non restituisce più l'esito. Un consenso senza esito non si presenta come riuscito.
 */
export function messaggioEsitoProposta(
  esito: EsitoConsensoCatalogo | undefined,
  { richiesta = false, ripetuta = false }: { richiesta?: boolean; ripetuta?: boolean } = {},
): string | null {
  switch (esito) {
    case undefined:
      if (!richiesta) return null;
      return ripetuta
        ? "La bottiglia era già stata aggiunta: controlla in Cantina, «Le tue proposte al catalogo», se la proposta risulta registrata."
        : "La bottiglia è in Cantina, ma non abbiamo conferma della proposta al catalogo: controlla «Le tue proposte al catalogo».";
    case "ricevuta":
      return null;
    case "in_sospeso":
      return "La proposta al catalogo è registrata: verrà inviata più tardi. Puoi ritirarla dalla Cantina.";
    case "limite":
      return "La bottiglia è in Cantina. Hai raggiunto il limite giornaliero di proposte al catalogo.";
    case "non_attiva":
      return "La bottiglia è in Cantina. Le proposte al catalogo non sono attive in questo momento: la proposta non è stata inviata.";
    case "non_valida":
      return "La bottiglia è in Cantina. I dati indicati non bastano per una proposta al catalogo: la proposta non è stata registrata.";
    default:
      return "La bottiglia è in Cantina; la proposta al catalogo non è stata registrata. Se il comando è disponibile, puoi inviarla dalla Cantina.";
  }
}

export type PropostaMia = {
  id: number;
  produttore: string;
  nome: string;
  annata: number | null;
  stato: string;
  inviataIl: string;
  /** Si ritira solo ciò che nessuno ha ancora deciso. */
  ritirabile: boolean;
};

const RITIRABILI = new Set(["in_revisione", "in_attesa_di_invio", "non_inviata"]);

export async function leggiProposteMie(client: SupabaseClient): Promise<Result<PropostaMia[]>> {
  try {
    const { data, error } = await client.rpc("catalogo_proposte_mie");
    if (error || !Array.isArray(data)) return { ok: false, error: ERRORE_LETTURA };
    return {
      ok: true,
      data: (data as Record<string, unknown>[]).flatMap((r) =>
        Number.isInteger(r.id) && typeof r.produttore === "string" && typeof r.nome === "string" && typeof r.stato === "string"
          ? [
              {
                id: r.id as number,
                produttore: r.produttore,
                nome: r.nome,
                annata: Number.isInteger(r.annata) ? (r.annata as number) : null,
                stato: r.stato,
                inviataIl: typeof r.inviata_il === "string" ? r.inviata_il : "",
                ritirabile: RITIRABILI.has(r.stato),
              },
            ]
          : [],
      ),
    };
  } catch (errore) {
    console.error("[catalogo-proposte] elenco non letto:", codiceErrore(errore));
    return { ok: false, error: ERRORE_LETTURA };
  }
}

/** Revoca del consenso. Un id negativo è un'intenzione non ancora inviata: la porta è la stessa. */
export async function ritiraProposta(client: SupabaseClient, id: number): Promise<Result<void>> {
  try {
    const { data, error } = await client.rpc("catalogo_proposta_ritira", { p_id: id });
    if (error || data !== true) {
      return { ok: false, error: "Non è più possibile ritirare questa proposta. Ricarica l'elenco." };
    }
    return { ok: true, data: undefined };
  } catch (errore) {
    console.error("[catalogo-proposte] ritiro non riuscito:", codiceErrore(errore));
    return { ok: false, error: ERRORE_GENERICO };
  }
}
