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
  CatalogoIncompleto,
  DomandaCandidati,
  OpzioniRicerca,
  SorgenteCandidati,
} from "@/lib/vendi/foto-etichetta/candidati";
import { codiceErrore } from "@/lib/errore-per-log";
import { LWIN7, UUID_SCHEDA } from "@/lib/wine-intelligence/codice-scheda";
import { livelliDiRicerca } from "./filtri";
import { MESSAGGIO_RICERCA_NON_DISPONIBILE } from "./sorgenti";

export const FUNZIONE_RICERCA_CANONICA = "vini_canonici_cerca";
export const CODICE_FONTE_CANONICA = "catalogo_canonico";
export const LIMITE_RISULTATI_CANONICI = 10;

export type ClienteRpcCanonico = Pick<SupabaseClient, "rpc">;

const LIVELLI = ["identificativo", "esatto", "prefisso", "testo", "simile"] as const;

const testo = (v: unknown): string => (typeof v === "string" ? v : "");
const testoOnull = (v: unknown): string | null => testo(v).trim() || null;

/** Una riga della RPC → candidato; `null` se manca l'identità (riga scartata, mai completata a caso). */
export function candidatoDaRigaCanonica(riga: unknown): CandidatoVino | null {
  if (typeof riga !== "object" || riga === null) return null;
  const r = riga as Record<string, unknown>;
  const produttore = testo(r.produttore).trim();
  const nome = testo(r.nome).trim();
  const id = testo(r.vino_id);
  // WI-011: senza LWIN la scheda è identificata dall'UUID; un codice presente ma malformato resta una riga da scartare.
  const lwin7 = r.lwin7 === null ? null : testo(r.lwin7);
  if (!id || !produttore || !nome) return null;
  if (lwin7 === null ? !UUID_SCHEDA.test(id) : !LWIN7.test(lwin7)) return null;
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
      codice: lwin7 ?? id,
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
    async cerca(domanda: DomandaCandidati, opzioni?: OpzioniRicerca): Promise<Result<CandidatoVino[]>> {
      if (!client) return { ok: false, error: MESSAGGIO_RICERCA_NON_DISPONIBILE };
      if (livelliDiRicerca(domanda).length === 0) return { ok: true, data: [] };
      try {
        const richiesta = client.rpc(FUNZIONE_RICERCA_CANONICA, {
          p_produttore: domanda.produttore,
          p_nome: domanda.nome,
          p_limite: LIMITE_RISULTATI_CANONICI,
        });
        // Annullamento con lo strumento di supabase-js (`abortSignal`); un client senza il metodo (fake) prosegue come prima.
        const segnale = opzioni?.segnale;
        const annullabile = richiesta as unknown as { abortSignal?: (s: AbortSignal) => typeof richiesta };
        const { data, error } = await (segnale && typeof annullabile.abortSignal === "function"
          ? annullabile.abortSignal(segnale)
          : richiesta);
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
 * Tetto di attesa della sorgente facoltativa: oltre questo tempo il canonico conta come «vuoto» e la ricerca
 * principale (già pronta) non aspetta il livello «simile» lento della RPC (fino a 8 s di `statement_timeout`).
 */
export const TETTO_CANONICO_MS = 1500;

/** WI-009 — tetto del secondo tentativo, chiesto esplicitamente dall utente: sotto lo `statement_timeout` di 8 s. */
export const ATTESA_CATALOGO_RIPROVA_MS = 6000;

type EsitoFacoltativo = { candidati: CandidatoVino[]; incompleto: CatalogoIncompleto | null };

/**
 * Esito della sorgente entro il tetto; scadenza, errore o eccezione = nessun candidato (mai un errore), con il motivo.
 * Alla scadenza la richiesta in corso viene ANNULLATA (FIX-03B): il client non la aspetta più e, per i client che
 * propagano la chiusura, il server può smettere di lavorare. Resta un'ottimizzazione: la protezione del database
 * è il `statement_timeout` di piattaforma, non questo annullamento.
 */
function entroTetto(
  avvia: (segnale: AbortSignal) => Promise<Result<CandidatoVino[]>>,
  ms: number,
  segnaleEsterno: AbortSignal,
): Promise<EsitoFacoltativo> {
  const senza = (incompleto: CatalogoIncompleto): EsitoFacoltativo => ({ candidati: [], incompleto });
  const controllo = new AbortController();
  return new Promise((risolvi) => {
    const termina = (esito: EsitoFacoltativo) => {
      clearTimeout(timer);
      segnaleEsterno.removeEventListener("abort", annulla);
      risolvi(esito);
    };
    const annulla = () => {
      controllo.abort();
      termina(senza("non_disponibile"));
    };
    const timer = setTimeout(() => {
      controllo.abort();
      termina(senza("lento"));
    }, ms);
    segnaleEsterno.addEventListener("abort", annulla, { once: true });
    const attesa = Promise.resolve().then(() => {
      controllo.signal.throwIfAborted();
      return avvia(controllo.signal);
    });
    attesa.then(
      (esito) => termina(esito.ok ? { candidati: esito.data, incompleto: null } : senza("non_disponibile")),
      () => termina(senza("non_disponibile")),
    );
  });
}

/**
 * La sorgente principale (motore WI-006B) più il catalogo canonico come aggiunta.
 * • Il risultato della principale decide l'esito: se fallisce, fallisce.
 * • Il canonico, se fallisce o è vuoto, non toglie nulla: i candidati della principale passano invariati. Quando
 *   scade o fallisce (non quando è vuoto) lo segnala con `onCatalogoIncompleto` (WI-009): mai un silenzio.
 * • Le due ricerche partono insieme; i candidati canonici seguono quelli della principale e
 *   `valutaCandidati` ordina per somiglianza e, a parità di vino, UNISCE: restano i campi Vinea e si aggiunge la scheda
 *   canonica (LWIN, provenienza, attribuzione).
 * • Il canonico ha un tetto di attesa (`TETTO_CANONICO_MS`): se non risponde in tempo, la principale passa invariata.
 */
export function sorgenteConCanonico(
  principale: SorgenteCandidati,
  canonica: SorgenteCandidati,
  opzioni: { tettoMs?: number } = {},
): SorgenteCandidati {
  const tetto = opzioni.tettoMs ?? TETTO_CANONICO_MS;
  return {
    codice: principale.codice,
    async cerca(domanda, richiesta) {
      const controllo = new AbortController();
      const segnale = richiesta?.segnale
        ? AbortSignal.any([richiesta.segnale, controllo.signal])
        : controllo.signal;
      const indisponibile = { ok: false as const, error: MESSAGGIO_RICERCA_NON_DISPONIBILE };
      if (segnale.aborted) return indisponibile;

      try {
        const primaria = principale.cerca(domanda, { ...richiesta, segnale });
        const canonico = entroTetto(
          (segnale) => canonica.cerca(domanda, { segnale }),
          richiesta?.attesaCatalogoMs ?? tetto,
          segnale,
        );
        const p = await primaria;
        if (!p.ok) {
          controllo.abort();
          return p;
        }
        const c = await canonico;
        if (segnale.aborted) return indisponibile;
        if (c.incompleto) richiesta?.onCatalogoIncompleto?.(c.incompleto);
        return { ok: true, data: [...p.data, ...c.candidati] };
      } catch {
        controllo.abort();
        return indisponibile;
      }
    },
  };
}
