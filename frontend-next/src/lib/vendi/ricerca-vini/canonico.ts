// WI-007 — sorgente di candidati sul catalogo canonico (LWIN), dietro `SorgenteCandidati`.
//
// Interroga SOLO la RPC `public.vini_canonici_cerca`: la proiezione pubblica dei vini promossi e
// approvati. `catalog.*` non è raggiungibile dal client (nessun privilegio ai ruoli API) e questa
// sorgente non ha altra via. Finché l'interruttore di proiezione è spento (default) la RPC risponde
// con zero righe: la ricerca di prodotto non cambia.
//
// Il catalogo canonico AGGIUNGE candidati, non sostituisce il motore WI-006B: un suo errore non fa
// fallire la ricerca (vedi `sorgenteConCanonico`), perché «non lo so» da una fonte facoltativa non
// deve nascondere ciò che il motore ha trovato. Nessun dato inventato: annata e formato restano
// `null` (LWIN-7 non li fornisce), nessun prezzo.

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Result } from "@/services/types";
import type {
  CandidatoVino,
  DomandaCandidati,
  SorgenteCandidati,
} from "@/lib/vendi/foto-etichetta/candidati";
import { codiceErrore } from "@/lib/errore-per-log";
import { livelliDiRicerca } from "./filtri";
import { MESSAGGIO_RICERCA_NON_DISPONIBILE } from "./sorgenti";

export const FUNZIONE_RICERCA_CANONICA = "vini_canonici_cerca";
export const CODICE_FONTE_CANONICA = "catalogo_canonico";
export const LIMITE_RISULTATI_CANONICI = 10;

export type ClienteRpcCanonico = Pick<SupabaseClient, "rpc">;

const LIVELLI = ["identificativo", "esatto", "prefisso", "testo", "simile"] as const;

const testo = (v: unknown): string => (typeof v === "string" ? v : "");
const testoOnull = (v: unknown): string | null => testo(v).trim() || null;
const LWIN7 = /^[0-9]{7}$/;

/** Una riga della RPC → candidato; `null` se manca l'identità (riga scartata, mai completata a caso). */
export function candidatoDaRigaCanonica(riga: unknown): CandidatoVino | null {
  if (typeof riga !== "object" || riga === null) return null;
  const r = riga as Record<string, unknown>;
  const produttore = testo(r.produttore).trim();
  const nome = testo(r.nome).trim();
  const id = testo(r.vino_id);
  const lwin7 = testo(r.lwin7);
  if (!id || !produttore || !nome || !LWIN7.test(lwin7)) return null;
  const livello = LIVELLI.find((l) => l === r.livello);
  const punteggio = typeof r.punteggio === "number" && Number.isFinite(r.punteggio) ? r.punteggio : null;
  const territorio = testoOnull(r.territorio);
  // La regione del wizard accetta solo un territorio di tipo regione: un paese o una denominazione
  // non sono una regione e non vengono spacciati per tale.
  const regione = r.territorio_tipo === "region" ? territorio : null;
  return {
    fonte: CODICE_FONTE_CANONICA,
    id,
    produttore,
    nome,
    annata: null,
    formato: null,
    regione,
    denominazione: testoOnull(r.denominazione),
    // Il colore LWIN è in inglese e non coincide con le cinque tipologie del wizard: non si traduce.
    tipo: null,
    ...(livello && punteggio !== null ? { corrispondenzaServer: { livello, punteggio } } : {}),
    annunci: 0,
    canonico: {
      lwin7,
      paese: testoOnull(r.paese),
      territorio,
      fonteNome: testoOnull(r.fonte_nome),
      licenza: testoOnull(r.fonte_licenza),
      attribuzione: testoOnull(r.attribuzione),
    },
  };
}

/** Candidati del catalogo canonico. Un errore resta un errore: la composizione decide come trattarlo. */
export function sorgenteCanonica(client: ClienteRpcCanonico | null): SorgenteCandidati {
  return {
    codice: CODICE_FONTE_CANONICA,
    async cerca(domanda: DomandaCandidati): Promise<Result<CandidatoVino[]>> {
      if (!client) return { ok: false, error: MESSAGGIO_RICERCA_NON_DISPONIBILE };
      if (livelliDiRicerca(domanda).length === 0) return { ok: true, data: [] };
      try {
        const { data, error } = await client.rpc(FUNZIONE_RICERCA_CANONICA, {
          p_produttore: domanda.produttore,
          p_nome: domanda.nome,
          p_limite: LIMITE_RISULTATI_CANONICI,
        });
        if (error || !Array.isArray(data)) return { ok: false, error: MESSAGGIO_RICERCA_NON_DISPONIBILE };
        const candidati: CandidatoVino[] = [];
        for (const riga of data) {
          const c = candidatoDaRigaCanonica(riga);
          if (c) candidati.push(c);
        }
        return { ok: true, data: candidati };
      } catch (errore) {
        console.error("[ricerca-vini] catalogo canonico non riuscito:", codiceErrore(errore));
        return { ok: false, error: MESSAGGIO_RICERCA_NON_DISPONIBILE };
      }
    },
  };
}

/**
 * La sorgente principale (motore WI-006B) più il catalogo canonico come aggiunta.
 * • Il risultato della principale decide l'esito: se fallisce, fallisce (ripiego e messaggio restano quelli di prima).
 * • Il canonico, se fallisce o è vuoto, non toglie nulla: i candidati della principale passano invariati.
 * • Le due ricerche partono insieme; i candidati canonici seguono quelli della principale e
 *   `valutaCandidati` ordina per somiglianza, deduplicando a parità di vino (vince la scheda canonica).
 */
export function sorgenteConCanonico(
  principale: SorgenteCandidati,
  canonica: SorgenteCandidati,
): SorgenteCandidati {
  return {
    codice: principale.codice,
    async cerca(domanda) {
      const [p, c] = await Promise.all([
        principale.cerca(domanda),
        canonica.cerca(domanda).catch((): Result<CandidatoVino[]> => ({ ok: true, data: [] })),
      ]);
      if (!p.ok) return p;
      return { ok: true, data: c.ok ? [...p.data, ...c.data] : p.data };
    },
  };
}
