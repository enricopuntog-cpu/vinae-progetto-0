// WI-006B — sorgente di candidati sulla RPC `public.vini_cerca`.
//
// Il database trova e ordina per pertinenza (identificativo → esatto → prefisso/testo →
// simile) e restituisce al massimo 20 righe; qui si valida la risposta e la si porta nel
// contratto `CandidatoVino`. Il matching finale (`valutaCandidati`), la conferma
// dell'utente e il fallback manuale restano quelli di WI-002 e WI-006A.
//
// Visibilità: la RPC è SECURITY DEFINER e applica a mano la stessa visibilità delle policy di `wines`
// (equivalenza provata dalla griglia wi006b: se una policy cambia, quella griglia diventa rossa); le righe sono quelle che RLS e GRANT già
// concedono al chiamante. Il client non riceve né invia mai la chiave service_role.
// `catalog.*` non è raggiungibile: quando esisterà una proiezione pubblica approvata, il
// punto di estensione è la RPC (nuova migration), non questo file.

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Result } from "@/services/types";
import type {
  CandidatoVino,
  SorgenteCandidati,
} from "@/lib/vendi/foto-etichetta/candidati";
import { codiceErrore } from "@/lib/errore-per-log";
import { livelliDiRicerca } from "./filtri";
import { MESSAGGIO_RICERCA_NON_DISPONIBILE } from "./sorgenti";
import { sorgenteCanonica, sorgenteConCanonico } from "./canonico";

export const FUNZIONE_RICERCA_VINI = "vini_cerca";
export const CODICE_FONTE_MOTORE = "motore_vinea";
/** Righe chieste al server: il tetto del server è 20, il wizard ne mostra poche. */
export const LIMITE_RISULTATI_SERVER = 15;

export type ClienteRpc = Pick<SupabaseClient, "rpc">;

/** WI-016: il server rifiuta per protezione (raffica, concorrenza, saturazione). Non è un guasto. */
export const MESSAGGIO_TROPPE_RICERCHE = "Troppe ricerche in poco tempo. Attendi qualche secondo e riprova.";
const CODICI_PROTEZIONE: ReadonlySet<string> = new Set([
  "rate_limit_exceeded",
  "troppe_ricerche_in_corso",
  "ricerca_satura",
]);

const LIVELLI = ["identificativo", "esatto", "prefisso", "testo", "simile"] as const;
type Livello = (typeof LIVELLI)[number];

const testo = (v: unknown): string => (typeof v === "string" ? v : "");
const interoPositivo = (v: unknown): number | null =>
  typeof v === "number" && Number.isInteger(v) && v > 0 ? v : null;

/** Una riga della RPC → candidato; `null` se non ha identità sufficiente (riga scartata). */
export function candidatoDaRigaRpc(riga: unknown): CandidatoVino | null {
  if (typeof riga !== "object" || riga === null) return null;
  const r = riga as Record<string, unknown>;
  const produttore = testo(r.produttore).trim();
  const nome = testo(r.nome).trim();
  const id = testo(r.slug) || testo(r.vino_id);
  if (!id || !produttore || !nome) return null;
  const livello = LIVELLI.find((l) => l === r.livello);
  const punteggio = typeof r.punteggio === "number" && Number.isFinite(r.punteggio) ? r.punteggio : null;
  return {
    fonte: testo(r.fonte) || CODICE_FONTE_MOTORE,
    id,
    produttore,
    nome,
    annata: interoPositivo(r.annata),
    formato: testo(r.formato) || null,
    regione: testo(r.regione) || null,
    denominazione: testo(r.denominazione) || null,
    tipo: testo(r.tipo) || null,
    ...(livello && punteggio !== null
      ? { corrispondenzaServer: { livello: livello as Livello, punteggio } }
      : {}),
    annunci: interoPositivo(r.annunci) ?? 0,
  };
}

/** Candidati ordinati dal database. Un errore resta un errore: «non so» non è «non trovato». */
export function sorgenteDaRpc(client: ClienteRpc | null): SorgenteCandidati {
  return {
    codice: CODICE_FONTE_MOTORE,
    async cerca(domanda, opzioni): Promise<Result<CandidatoVino[]>> {
      if (!client || opzioni?.segnale?.aborted) return { ok: false, error: MESSAGGIO_RICERCA_NON_DISPONIBILE };
      // Domanda senza parole utilizzabili: nessuna richiesta (come in WI-006A).
      if (livelliDiRicerca(domanda).length === 0) return { ok: true, data: [] };
      try {
        const richiesta = client.rpc(FUNZIONE_RICERCA_VINI, {
          p_produttore: domanda.produttore,
          p_nome: domanda.nome,
          p_annata: domanda.annata,
          p_formato: domanda.formato,
          p_limite: LIMITE_RISULTATI_SERVER,
        });
        const segnale = opzioni?.segnale;
        const { data, error, status } = await (segnale && typeof richiesta.abortSignal === "function"
          ? richiesta.abortSignal(segnale)
          : richiesta);
        if (status === 429 || (error?.code && CODICI_PROTEZIONE.has(error.code))) {
          return { ok: false, error: MESSAGGIO_TROPPE_RICERCHE };
        }
        if (error || !Array.isArray(data)) return { ok: false, error: MESSAGGIO_RICERCA_NON_DISPONIBILE };
        const candidati: CandidatoVino[] = [];
        for (const riga of data) {
          const c = candidatoDaRigaRpc(riga);
          if (c) candidati.push(c);
        }
        return { ok: true, data: candidati };
      } catch (errore) {
        if (!opzioni?.segnale?.aborted) console.error("[ricerca-vini] rpc non riuscita:", codiceErrore(errore));
        return { ok: false, error: MESSAGGIO_RICERCA_NON_DISPONIBILE };
      }
    },
  };
}

/** Entrambe le sorgenti di prodotto passano dalle RPC protette. */
export function creaMotoreRicerca(client: ClienteRpc | null): SorgenteCandidati {
  return sorgenteConCanonico(sorgenteDaRpc(client), sorgenteCanonica(client));
}
