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

export type RiepilogoAzienda = {
  sentinel: StatoSentinel;
  anomalie: { aperte: number; p0: number; p1: number; p2: number; p3: number };
  task: { da_approvare: number; in_attesa: number; assegnati: number; falliti: number };
  agenti: { registrati: number; accesi: number };
  catalogo: Riepilogo;
  ai: {
    configurato: boolean;
    richieste_giorno: number | null;
    richieste_mese: number | null;
    interruttore_aperto_fino_a: string | null;
    oggi: { consentite: number; rifiutate_budget: number; guasti_fornitore: number };
    mese: { consentite: number };
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
