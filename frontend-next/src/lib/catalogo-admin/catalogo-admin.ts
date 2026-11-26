// WI-012 — lettura e gestione del catalogo dal sito. Questo modulo chiama SOLO le porte `catalogo_admin_*`: il ruolo
// `admin` è verificato nel database a ogni chiamata, le liste sono paginate sul server e ogni scrittura lascia il suo
// evento nello storico del catalogo. Nessuna lettura diretta di tabelle.

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Result } from "@/services/types";
import { codiceErrore } from "@/lib/errore-per-log";

const GENERICO = "Operazione non riuscita. Riprova.";
/** Codici sollevati dalle porte con un messaggio scritto per l'amministratore. */
const CODICI_PARLANTI = new Set(["22023", "23505", "P0001", "P0002", "55000", "0A000"]);

export function messaggioCatalogo(errore: { code?: string; message?: string }): string {
  if (errore.code === "42501") return "Operazione non autorizzata.";
  const testo = errore.message ?? "";
  // Un messaggio di vincolo di PostgreSQL contiene nomi interni: si sostituisce.
  if (/duplicate key/i.test(testo)) return "Esiste già un elemento uguale.";
  if (/violates|constraint|syntax|relation|column/i.test(testo)) return "I dati non rispettano le regole del catalogo.";
  if (!errore.code || !CODICI_PARLANTI.has(errore.code) || !testo) return GENERICO;
  const pulito = testo.replace(/^catalog:\s*/i, "");
  return pulito.charAt(0).toUpperCase() + pulito.slice(1);
}

export async function chiamaCatalogoAdmin<T>(
  client: SupabaseClient,
  funzione: string,
  argomenti?: Record<string, unknown>,
): Promise<Result<T>> {
  try {
    const { data, error } = await client.rpc(funzione, argomenti);
    if (error) return { ok: false, error: messaggioCatalogo(error) };
    return { ok: true, data: data as T };
  } catch (errore) {
    console.error("[catalogo-admin] chiamata non riuscita:", codiceErrore(errore));
    return { ok: false, error: GENERICO };
  }
}

export type Riepilogo = {
  vini: { canonici: number; attivi: number; nativi: number; nativi_pubblicati: number; senza_lwin: number };
  produttori: number;
  proposte: { aperte: number; aperte_identita_nuove: number; aperte_ambigue: number; totali: number };
  da_decidere: { duplicati: number; attributi: number; collegamenti: number };
  fonte: {
    record: number;
    ultima_importazione: { stato: string; iniziata: string; conclusa: string | null; righe: number } | null;
    rilievi_import: number;
  };
  interruttori: Record<string, boolean | string | null>;
};

export type VinoRiga = {
  id: string;
  lwin7: string | null;
  nome: string;
  produttore: string;
  origine: "promotion" | "manual";
  stato: string;
  pubblicato: boolean;
};

export type PaginaVini = { totale: number; oltre: boolean; righe: VinoRiga[] };

export type SchedaAdmin = {
  id: string;
  nome: string;
  lwin7: string | null;
  origine: "promotion" | "manual";
  stato: string;
  denominazione: string | null;
  tipo: string | null;
  colore: string | null;
  nota_provenienza: string | null;
  pubblicato_il: string | null;
  territorio: { nome: string; tipo: string } | null;
  fonte: { nome: string; autorizzazione: string } | null;
  produttore: { id: string; nome: string };
  annate: { id: string; anno: number | null; non_millesimato: boolean; formati: { id: string; ml: number; pezzi: number }[] }[];
  attributi: { id: number; attributo: string; valore: unknown; stato: string; evidenza: string | null; fonte: string }[];
  alias: { alias: string; tipo: string }[];
  collegamenti: { id: number; vino_app: string; stato: string }[];
  storico: { id: number; azione: string; esecutore: string; quando: string }[];
};

export type Candidato = {
  wine_id?: string;
  source_record_id?: number;
  lwin7?: string;
  lwin7_attuale?: string | null;
  motivo: string;
  produttore?: string;
  nome?: string;
};

export type PropostaAdmin = {
  id: number;
  dati: Record<string, string | number | boolean>;
  origine: string;
  affidabilita: string;
  corrispondenza: string;
  mancanti: string[];
  stato: string;
  invii: number;
  nota: string | null;
  candidati: Candidato[];
};

export type Code = {
  duplicati: { id: number; motivo: string; tipo: string; primo: string; secondo: string }[];
  duplicati_totale: number;
  attributi: { id: number; attributo: string; valore: unknown; valore_attuale: unknown; evidenza: string | null; fonte: string; vino_id: string | null }[];
  attributi_totale: number;
  collegamenti: { id: number; vino_app: string; descrizione_app: string | null; produttore: string; nome: string; anno: number | null }[];
  collegamenti_totale: number;
};

export type Fonti = {
  fonti: { codice: string; nome: string; licenza: string | null; autorizzazione: string; verificata_il: string | null }[];
  importazioni: { seq: number; stato: string; iniziata: string; righe: number; file: string; impronta_file: string }[];
  conflitti_lwin_nativi: { wine_id: string; produttore: string; nome: string; lwin7: string }[];
};

export type Evento = { id: number; azione: string; entita: string; riferimento: string | null; esecutore: string; quando: string };

export type Territorio = { id: number; nome: string; tipo: string };

export type RecordFonte = {
  source_record_id: number;
  lwin7: string;
  produttore: string;
  nome: string;
  paese: string | null;
  stato: string;
  canonico: string | null;
};

export type Decisione = "rifiuta" | "duplicata" | "collega" | "crea";

export const PER_PAGINA = 20;

export function serviziCatalogoAdmin(client: SupabaseClient) {
  const chiama = <T>(f: string, a?: Record<string, unknown>) => chiamaCatalogoAdmin<T>(client, f, a);
  return {
    riepilogo: () => chiama<Riepilogo>("catalogo_admin_riepilogo"),
    vini: (f: { testo: string; stato: string; origine: string; pagina: number }) =>
      chiama<PaginaVini>("catalogo_admin_vini", {
        p_testo: f.testo,
        p_stato: f.stato || null,
        p_origine: f.origine || null,
        p_pagina: f.pagina,
        p_per_pagina: PER_PAGINA,
      }),
    vino: (id: string) => chiama<SchedaAdmin | null>("catalogo_admin_vino", { p_id: id }),
    proposte: (stato: string, pagina: number) =>
      chiama<{ totale: number; righe: PropostaAdmin[] }>("catalogo_admin_proposte", {
        p_stato: stato,
        p_pagina: pagina,
        p_per_pagina: PER_PAGINA,
      }),
    code: (pagina: number) => chiama<Code>("catalogo_admin_code", { p_pagina: pagina, p_per_pagina: PER_PAGINA }),
    storico: (pagina: number) => chiama<Evento[]>("catalogo_admin_storico", { p_pagina: pagina, p_per_pagina: 30 }),
    fonti: () => chiama<Fonti>("catalogo_admin_fonti"),
    territori: (testo: string) => chiama<Territorio[]>("catalogo_admin_territori", { p_testo: testo }),
    cercaFonte: (testo: string) => chiama<RecordFonte[]>("catalogo_admin_cerca_fonte", { p_testo: testo }),
    decidiProposta: (id: number, decisione: Decisione, dati: Record<string, unknown>, nota: string) =>
      chiama<{ stato: string; wine_id: string | null }>("catalogo_admin_proposta_decidi", {
        p_id: id,
        p_decisione: decisione,
        p_dati: dati,
        p_nota: nota || null,
      }),
    azione: (azione: string, dati: Record<string, unknown>, nota: string) =>
      chiama<Record<string, unknown>>("catalogo_admin_azione", { p_azione: azione, p_dati: dati, p_nota: nota || null }),
  };
}

export type ServiziCatalogoAdmin = ReturnType<typeof serviziCatalogoAdmin>;
