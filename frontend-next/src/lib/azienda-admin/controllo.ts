// WI-016 — Founder Control Center: legge e comanda SOLO attraverso le porte `azienda_admin_*` / `catalogo_admin_*`
// (ruolo admin verificato nel database; ripristino e soglie richiedono anche una conferma recente dell'identità).
// Dal sito si può sospendere tutto e togliere una sospensione: non si accende nulla che il proprietario non abbia già
// acceso. Nessun indicatore è calcolato qui su dati non letti.

import type { SupabaseClient } from "@supabase/supabase-js";
import { chiamaCatalogoAdmin } from "@/lib/catalogo-admin/catalogo-admin";
import { raccogliOsservazioni } from "@/lib/prezzi/acquisizione";
import { valutaPrezzo, type SoggettoValutazione, type Valutazione } from "@/lib/prezzi/valutazione";
import type { Result } from "@/services/types";

export type TipoSospensione = "globale" | "ai" | "agente" | "lavoro" | "fonte" | "catalogo";

export type StatoControllo = {
  sospensioni: { tipo: TipoSospensione; chiave: string; motivo: string; da: string; dal: string }[];
  storico_sospensioni: { tipo: string; chiave: string; dal: string; al: string; motivo_ripristino: string }[];
  funzioni_ai: {
    funzione: string;
    max_tentativi: number;
    modello_riserva: string | null;
    max_input_caratteri: number;
    concorrenza_utente: number;
    concorrenza_globale: number;
    quota_account_nuovo: number;
    sospesa: boolean;
    in_corso: number;
  }[];
  segnali_sicurezza_ai_24h: { tipo: string; conteggio: number }[];
  interruttori: Record<string, boolean | string | null>;
  consenso: { in_sospeso: number; esaurite: number; quarantena: number };
  qualita: { codice: string; severita: string; conteggio: number }[];
  mercato: { aperte: number; soglie: Record<string, number | string | null>; ultima_scansione: string | null };
  esecutori: { chiave: string; acceso: boolean; sospeso: boolean; ultima_richiesta: string | null; ultima_presa: string | null; tipi_derivabili: string[] }[];
  orchestrazione: Record<string, number>;
  lavori: { chiave: string; acceso: boolean; sospeso: boolean }[];
  fonti: { chiave: string; accesa: boolean; sospesa: boolean }[];
};

export type Bersaglio = { tipo: TipoSospensione; chiave: string; etichetta: string; sospeso: boolean };

const FUNZIONI_AI: Record<string, string> = { "ai:chat": "Sommelier", "ai:pairing": "Abbinamenti", "ai:catalogo": "Catalogazione AI" };

/** Tutto ciò che si può fermare, con l'interruttore generale per primo. */
export function bersagliSospendibili(s: StatoControllo): Bersaglio[] {
  const sospeso = (tipo: TipoSospensione, chiave: string) => s.sospensioni.some((x) => x.tipo === tipo && x.chiave === chiave);
  const voce = (tipo: TipoSospensione, chiave: string, etichetta: string): Bersaglio => ({ tipo, chiave, etichetta, sospeso: sospeso(tipo, chiave) });
  return [
    voce("globale", "tutto", "Interruttore generale (tutto ciò che agisce)"),
    ...s.funzioni_ai.map((f) => voce("ai", f.funzione, `AI: ${FUNZIONI_AI[f.funzione] ?? f.funzione}`)),
    voce("catalogo", "proposte", "Proposte al catalogo degli utenti"),
    voce("catalogo", "acquisizione", "Acquisizione dagli annunci"),
    ...s.esecutori.map((a) => voce("agente", a.chiave, `Agente: ${a.chiave}`)),
    ...s.lavori.map((j) => voce("lavoro", j.chiave, `Lavoro pianificato: ${j.chiave}`)),
    ...s.fonti.map((f) => voce("fonte", f.chiave, `Fonte di monitoraggio: ${f.chiave}`)),
  ];
}

export type RevisioneMercato = {
  id: number;
  tipo: string;
  stato: string;
  evidenza: Record<string, unknown>;
  prima: string;
  ultima: string;
  nota: string | null;
  utente: string | null;
  annunci: string[];
};

const REVISIONI: Record<string, string> = {
  annunci_duplicati: "Annunci identici attivi dello stesso venditore",
  pubblicazione_massiva: "Molte pubblicazioni in 24 ore",
  dati_incoerenti: "Dati dell'annuncio incoerenti",
  prezzo_anomalo: "Prezzo richiesto lontano dagli altri annunci dello stesso vino",
  ripubblicazione_ripetuta: "Stesso vino pubblicato molte volte in 30 giorni",
  ordini_stessa_coppia: "Molti ordini fra le stesse due persone",
  annullamenti_ripetuti: "Molte prenotazioni annullate in 7 giorni",
  soglia_vendite: "Soglia di vendita superata: da rivedere (non è una classificazione fiscale)",
};
export const etichettaRevisione = (tipo: string): string => REVISIONI[tipo] ?? "Da rivedere";

export const SOGLIE_MERCATO = [
  ["annunci_24h", "Annunci in 24 ore"],
  ["fattore_prezzo_anomalo", "Fattore di prezzo anomalo"],
  ["comparabili_minimi", "Comparabili minimi per il prezzo"],
  ["ripubblicazioni_30g", "Pubblicazioni dello stesso vino in 30 giorni"],
  ["ordini_stessa_coppia_30g", "Ordini fra le stesse persone in 30 giorni"],
  ["annullamenti_7g", "Annullamenti in 7 giorni"],
  ["vendite_revisione_365g", "Vendite concluse in 365 giorni (vuoto = spento)"],
  ["incasso_revisione_365g_cents", "Totale venduto in centesimi in 365 giorni (vuoto = spento)"],
] as const;

const OPZIONALI = new Set(["vendite_revisione_365g", "incasso_revisione_365g_cents"]);

/** Dal modulo alla porta: solo le chiavi note, numeri; vuoto ammesso solo per le soglie di vendita (= spente). */
export function soglieDaCampi(campi: Record<string, string>): Result<Record<string, number | null>> {
  const uscita: Record<string, number | null> = {};
  for (const [chiave, testo] of Object.entries(campi)) {
    if (!SOGLIE_MERCATO.some(([k]) => k === chiave)) return { ok: false, error: "Soglia sconosciuta." };
    const t = testo.trim().replace(",", ".");
    if (t === "") {
      if (!OPZIONALI.has(chiave)) return { ok: false, error: "Questa soglia non può restare vuota." };
      uscita[chiave] = null;
      continue;
    }
    const n = Number(t);
    if (!Number.isFinite(n) || (chiave !== "fattore_prezzo_anomalo" && !Number.isInteger(n))) {
      return { ok: false, error: "Le soglie sono numeri." };
    }
    uscita[chiave] = n;
  }
  return { ok: true, data: uscita };
}

const CAMPI_RICERCA = ["fonte", "soggetto", "soggetto_id", "attributo", "valore", "riferimento", "acquisita", "attendibilita"];

/** Wine Research: un elemento o un elenco (massimo 20) di informazioni da una fonte autorizzata, campi chiusi. */
export function leggiRicercaIncollata(testo: string): Result<Record<string, unknown>[]> {
  let letto: unknown;
  try {
    letto = JSON.parse(testo);
  } catch {
    return { ok: false, error: "Serve un JSON valido." };
  }
  const elementi = Array.isArray(letto) ? letto : [letto];
  if (elementi.length === 0 || elementi.length > 20) return { ok: false, error: "Da 1 a 20 informazioni per volta." };
  for (const e of elementi) {
    if (!e || typeof e !== "object" || Array.isArray(e)) return { ok: false, error: "Ogni elemento è un oggetto." };
    const chiavi = Object.keys(e);
    if (chiavi.some((k) => !CAMPI_RICERCA.includes(k)) || CAMPI_RICERCA.some((k) => !chiavi.includes(k))) {
      return { ok: false, error: `Servono esattamente i campi: ${CAMPI_RICERCA.join(", ")}.` };
    }
  }
  return { ok: true, data: elementi as Record<string, unknown>[] };
}

export type PortaPrezzi =
  | { abilitata: false }
  | { abilitata: true; soggetto: SoggettoValutazione; osservazioni: unknown[]; vino?: { produttore: string; nome: string } };

export type EsitoValutazione =
  | { stato: "spenta" }
  | { stato: "valutata"; valutazione: Valutazione; richiesti: number; realizzati: number; scartate: number };

/**
 * Adattatore WI-014 sullo storico già minimizzato: il contratto di acquisizione (campi chiusi, fonte autorizzata e con
 * finalità) filtra le righe prima della stima. Acquisizione accesa solo se la porta del database lo dice.
 */
export async function valutaVinoDaPorta(porta: PortaPrezzi, adesso: Date): Promise<EsitoValutazione> {
  if (!porta.abilitata) return { stato: "spenta" };
  const raccolta = await raccogliOsservazioni(
    [
      {
        nome: "vinea_interno",
        autorizzata: true,
        finalita: "valutazione interna del founder sui prezzi osservati nel marketplace Vinea",
        leggi: async () => porta.osservazioni,
      },
    ],
    { attiva: porta.abilitata },
  );
  if (raccolta.esito !== "raccolte") return { stato: "spenta" };
  const valutazione = valutaPrezzo(porta.soggetto, raccolta.osservazioni, adesso);
  return {
    stato: "valutata",
    valutazione,
    richiesti: raccolta.osservazioni.filter((o) => o.tipo === "richiesto").length,
    realizzati: raccolta.osservazioni.filter((o) => o.tipo === "realizzato").length,
    scartate: raccolta.scartate,
  };
}

export type RichiestaAutenticita = {
  id: string;
  anomalie: string[];
  stato: string;
  creata: string;
  aggiornata: string;
  nota: string | null;
  produttore: string;
  nome: string;
  annata: number | null;
};

export type SegnaliCorrelati = {
  in_escalation: { codice: string; severita: string; dal: string }[];
  peggiorate: { codice: string; severita: string; all_apertura: number; ora: number }[];
  gruppi: { dal: string; anomalie: string[] }[];
};

export function serviziControllo(client: SupabaseClient) {
  const chiama = <T>(f: string, a?: Record<string, unknown>) => chiamaCatalogoAdmin<T>(client, f, a);
  return {
    stato: () => chiama<StatoControllo>("azienda_admin_controllo"),
    sospendi: (tipo: TipoSospensione, chiave: string, motivo: string) =>
      chiama<number>("azienda_admin_sospendi", { p_tipo: tipo, p_chiave: chiave, p_motivo: motivo }),
    ripristina: (tipo: TipoSospensione, chiave: string, motivo: string) =>
      chiama<boolean>("azienda_admin_ripristina", { p_tipo: tipo, p_chiave: chiave, p_motivo: motivo }),
    mercato: (aperte: boolean, pagina: number) => chiama<RevisioneMercato[]>("azienda_admin_mercato", { p_aperte: aperte, p_pagina: pagina }),
    decidiRevisione: (id: number, azione: "prendi_in_carico" | "chiudi_senza_azione" | "chiudi_segnalata", nota: string) =>
      chiama<string>("azienda_admin_mercato_decidi", { p_id: id, p_azione: azione, p_nota: nota }),
    scansionaMercato: () => chiama<{ esito: string; rilievi?: number; nuove_revisioni?: number; non_eseguiti?: number }>("azienda_admin_mercato_scansione"),
    salvaSoglie: (soglie: Record<string, number | null>) => chiama<Record<string, unknown>>("azienda_admin_mercato_soglie", { p_soglie: soglie }),
    correlati: () => chiama<SegnaliCorrelati>("azienda_admin_segnali_correlati"),
    autenticita: (pagina: number) => chiama<RichiestaAutenticita[]>("azienda_admin_autenticita", { p_pagina: pagina }),
    decidiAutenticita: (id: string, azione: "avvia_verifica" | "richiedi_documenti" | "chiudi", nota: string) =>
      chiama<string>("azienda_admin_autenticita_decidi", { p_id: id, p_azione: azione, p_nota: nota }),
    prezzi: (slug: string) => chiama<PortaPrezzi>("prezzi_admin_osservazioni", { p_wine_slug: slug }),
    operazione: (taskId: string) =>
      chiama<{ radice: string; task: { id: string; tipo: string; stato: string; profondita: number; titolo: string }[]; eventi: { tipo: string; fonte: string; quando: string }[] }>(
        "azienda_admin_operazione",
        { p_task_id: taskId },
      ),
    annullaOperazione: (taskId: string, motivo: string) => chiama<number>("azienda_admin_operazione_annulla", { p_task_id: taskId, p_motivo: motivo }),
  };
}

export type ServiziControllo = ReturnType<typeof serviziControllo>;
