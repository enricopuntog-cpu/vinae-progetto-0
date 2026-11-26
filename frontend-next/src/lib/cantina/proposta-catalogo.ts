// WI-011 — «Proponi al catalogo Vinea»: un gesto ESPLICITO, con consenso per quella richiesta. Aggiungere una
// bottiglia alla Cantina o scegliere una scheda non propone nulla. Il client manda solo dati enologici; il database
// ricontrolla ogni cosa (interruttore, possesso, elenco chiuso di campi, limiti) e nessuna proposta entra nel catalogo
// senza revisione. Fail-closed: con le proposte spente il comando non compare.

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Result } from "@/services/types";
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

export type Proposta = { origine: "cantina" | "correzione"; dati: Record<string, string | number> };

const ERRORE_GENERICO = "Non è stato possibile inviare la proposta. Riprova più tardi.";

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
      return {
        ok: false,
        error: error?.code === "22023" ? "Controlla i dati inseriti: qualcosa non è un'informazione sul vino." : ERRORE_GENERICO,
      };
    }
    return { ok: true, data: undefined };
  } catch (errore) {
    console.error("[catalogo-proposte] invio non riuscito:", codiceErrore(errore));
    return { ok: false, error: ERRORE_GENERICO };
  }
}
