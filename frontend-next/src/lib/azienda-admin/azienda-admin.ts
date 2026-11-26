// WI-013 — cruscotto del founder: legge SOLO le porte `azienda_admin_*` (ruolo admin verificato nel database).
// Nessun indicatore calcolato dal client su dati non letti: ciò che non è collegato arriva dichiarato dal database.

import type { SupabaseClient } from "@supabase/supabase-js";
import { chiamaCatalogoAdmin, type Riepilogo } from "@/lib/catalogo-admin/catalogo-admin";

export type StatoSentinel = {
  pianificato: boolean;
  intervallo_atteso_minuti: number;
  stato: "mai_eseguito" | "in_ritardo" | "recente";
  ultima_esecuzione: { conclusa: string; avviata_da: string; controlli: number; non_eseguiti: number; problemi: number } | null;
};

export type StatoScheduler = {
  pg_cron_installato: boolean;
  job_cron_attivo: boolean;
  ultimo_giro: string | null;
  ultimo_giro_da: string | null;
  stato: "mai_eseguito" | "in_ritardo" | "recente";
  lavori: {
    chiave: string;
    descrizione: string;
    acceso: boolean;
    intervallo_minuti: number;
    ultimo: string | null;
    esito: "ok" | "errore" | "sospeso" | null;
    errore: string | null;
    guasti_consecutivi: number;
    prossimo: string | null;
  }[];
};

export type FonteMonitor = {
  chiave: string;
  descrizione: string;
  ultimo: string | null;
  ultimo_stato: string | null;
  riferimento: string | null;
  stato: string;
};

export type RapportoAzienda = {
  giorni: number;
  generato_il: string;
  anomalie_aperte: { severita: string; categoria: string; conteggio: number; codici: string[] }[];
  nel_periodo: { aperte: number; risolte: number; decisioni: number; chiusure_per_regola: number; esecuzioni_sentinel: number };
  segnali: { totali: number; guasti: number; degradati: number };
  lavori_con_problemi: { chiave: string; esito: string; errore: string | null }[];
  ai_richieste: number;
};

const FONTI: Record<string, string> = {
  disponibile: "Disponibile",
  degradata: "Degradata",
  errore: "Errore",
  in_ritardo: "In ritardo",
  disattivata: "Disattivata",
  non_verificata: "Non verificata",
};
export const etichettaFonte = (stato: string): string => FONTI[stato] ?? "Non verificata";

const AGENTI: Record<string, string> = {
  operativo: "Operativo (presa nelle ultime 24 ore)",
  acceso_senza_attivita: "Acceso, nessuna attività nelle ultime 24 ore",
  credenziale_scaduta: "Credenziale scaduta",
  spento: "Spento",
};
export const etichettaAgente = (stato: string): string => AGENTI[stato] ?? "Non verificato";

/** «Pianificato» richiede un job di pg_cron attivo: un giro lanciato a mano non basta. */
export function etichettaScheduler(s: Pick<StatoScheduler, "stato" | "pg_cron_installato" | "job_cron_attivo">): string {
  if (!s.pg_cron_installato || !s.job_cron_attivo) return "Non pianificato (nessun giro automatico)";
  return s.stato === "recente" ? "Pianificato e recente" : "Pianificato ma in ritardo";
}

export type RiepilogoAzienda = {
  sentinel: StatoSentinel;
  anomalie: { aperte: number; p0: number; p1: number; p2: number; p3: number };
  task: { da_approvare: number; approvati: number; in_attesa: number; assegnati: number; bloccati: number; falliti: number };
  agenti: {
    registrati: number;
    accesi: number;
    /** Acceso, con credenziale e con almeno una presa nelle ultime 24 ore: non basta essere registrato. */
    operativi: number;
    elenco: { chiave: string; descrizione: string; tipi: string[]; ultima_presa: string | null; stato: string; task_in_corso: number }[];
  };
  scheduler: StatoScheduler;
  evidenze: number;
  coda_catalogo: { proposte_senza_task: number; acquisizioni_fallite: number };
  fonti: FonteMonitor[];
  catalogo: Riepilogo;
  ai: {
    configurato: boolean;
    richieste_giorno: number | null;
    richieste_mese: number | null;
    interruttore_aperto_fino_a: string | null;
    oggi: { consentite: number; rifiutate_budget: number; guasti_fornitore: number };
    mese: { consentite: number };
    spesa: {
      limite_giorno_usd: number | null;
      limite_mese_usd: number | null;
      stimata_oggi_usd: number;
      riservata_aperta_oggi_usd: number;
      stimata_mese_usd: number;
      effettiva_mese_usd: number | null;
      chiamate_senza_tariffa_mese: number;
      per_funzione: { funzione: string; modello: string; chiamate: number; token_input: number; token_output: number; stimato_usd: number }[];
    };
    tariffe_registrate: number;
  };
  sorgenti_non_collegate: string[];
};

export type Anomalia = {
  id: number;
  codice: string;
  fonte: string;
  categoria: string;
  severita: "P0" | "P1" | "P2" | "P3";
  titolo: string;
  evidenza: Record<string, unknown>;
  correlazione: string;
  stato: "aperta" | "presa_in_carico" | "risolta" | "ignorata";
  prima: string;
  ultima: string;
  ricorrenze: number;
  responsabile: string | null;
  azione_proposta: string;
  richiede_approvazione: boolean;
  nota: string | null;
  /** WI-015: l'«ignora» è sempre temporaneo; torna visibile alla scadenza o se la gravità sale. */
  ignorata_fino_al: string | null;
};

export type TaskAzienda = {
  id: string;
  tipo: string;
  titolo: string;
  priorita: number;
  stato: string;
  richiede_approvazione: boolean;
  proposta: Record<string, unknown> | null;
  tentativi: number;
  agente: string | null;
  evidenze: number;
  creato: string;
};

/** Etichetta onesta: senza scheduler Sentinel non è mai «attivo», qualunque sia l'ultima esecuzione. */
export function etichettaSentinel(s: StatoSentinel): string {
  const esecuzione =
    s.stato === "mai_eseguito" ? "mai eseguito" : s.stato === "in_ritardo" ? "in ritardo sull'intervallo atteso" : "eseguito di recente";
  return `${s.pianificato ? "Pianificato" : "Non pianificato (solo esecuzione manuale)"} · ${esecuzione}`;
}

export function serviziAziendaAdmin(client: SupabaseClient) {
  const chiama = <T>(f: string, a?: Record<string, unknown>) => chiamaCatalogoAdmin<T>(client, f, a);
  return {
    riepilogo: () => chiama<RiepilogoAzienda>("azienda_admin_riepilogo"),
    rapporto: (giorni: number) => chiama<RapportoAzienda>("azienda_admin_rapporto", { p_giorni: giorni }),
    anomalie: (aperte: boolean, pagina: number) => chiama<Anomalia[]>("azienda_admin_anomalie", { p_aperte: aperte, p_pagina: pagina }),
    aggiornaAnomalia: (id: number, azione: "prendi_in_carico" | "ignora" | "riapri" | "risolvi", nota: string, ore?: number) =>
      chiama<string>("azienda_admin_anomalia_aggiorna", { p_id: id, p_azione: azione, p_nota: nota || null, p_ore: ore ?? null }),
    eseguiSentinel: () =>
      chiama<{ esito: string; controlli?: number; non_eseguiti?: number; problemi?: number }>("azienda_admin_sentinel_esegui"),
    task: (pagina: number) => chiama<TaskAzienda[]>("azienda_admin_task", { p_pagina: pagina }),
    decidiTask: (id: string, decisione: "approva" | "respingi" | "annulla" | "conferma_eseguito", nota: string) =>
      chiama<string>("azienda_admin_task_decidi", { p_id: id, p_decisione: decisione, p_nota: nota }),
  };
}
