// WI-006A — dalla domanda di ricerca ai filtri da mandare al database.
//
// Funzioni pure. Il database non fa il matching (quello resta `valutaCandidati`,
// deterministico, WI-002): restringe soltanto l'insieme di righe che vale la
// pena portare nel browser. Una ricerca è una sequenza di LIVELLI, dal più
// preciso al più tollerante; ogni livello è un AND di gruppi e ogni gruppo un
// OR di frammenti di testo. Si passa al livello successivo solo se i risultati
// raccolti sono ancora pochi, così il caso comune costa una sola richiesta e il
// caso peggiore ne costa tre, mai una per riga.
//
//   1. «preciso»        ogni parola significativa compare, per intero
//   2. «per lato»       produttore e nome tollerano un refuso o un accento,
//                       ma devono comunque tornare entrambi
//   3. «ampio»          basta un frammento qualsiasi (l'altro lato può essere
//                       stato letto male del tutto)
//
// La tolleranza ai refusi non usa l'operatore di similarità di pg_trgm (non è
// raggiungibile da PostgREST senza una funzione SQL nuova): ogni parola lunga
// è divisa in due metà, e un singolo errore (OCR, accento perso, lettera
// doppia) lascia comunque intatta una delle due. Due errori in metà diverse
// possono sfuggire: è un limite dichiarato, il modulo WI-006B lo supera.

import type { DomandaCandidati } from "@/lib/vendi/foto-etichetta/candidati";
import { tokenNormalizzati } from "@/lib/vendi/foto-etichetta/candidati";

/** Una parola più corta di così non seleziona nulla: troppe righe, nessun segnale. */
export const LUNGHEZZA_MINIMA_PAROLA = 3;
/** Massimo di parole significative usate: una domanda lunga non allunga la query. */
export const MAX_PAROLE = 6;
/** Sotto questa soglia di risultati distinti si passa al livello più tollerante. */
export const RISULTATI_SUFFICIENTI = 3;

/** Un OR di frammenti: la riga passa se contiene almeno uno di questi testi. */
export type GruppoFrammenti = readonly string[];

export type LivelloRicerca = {
  nome: "preciso" | "per_lato" | "ampio";
  /** AND dei gruppi. Mai vuoto. */
  gruppi: readonly GruppoFrammenti[];
  /** Tetto di righe richieste al database per questo livello. */
  limite: number;
};

export const LIMITE_PRECISO = 40;
export const LIMITE_TOLLERANTE = 60;

const unici = <T>(valori: readonly T[]): T[] => [...new Set(valori)];

function paroleSignificative(testo: string, comeProduttore: boolean): string[] {
  return unici(
    tokenNormalizzati(testo, comeProduttore).filter((t) => t.length >= LUNGHEZZA_MINIMA_PAROLA),
  );
}

/**
 * Frammenti di una parola che sopravvivono a un singolo errore. Una parola di
 * 3-5 lettere non si può dividere senza perdere il segnale: resta intera (e il
 * refuso su parole così corte lo recupera solo il livello ampio sul resto).
 */
export function frammentiTolleranti(parola: string): string[] {
  if (parola.length < 6) return [parola];
  const meta = Math.floor(parola.length / 2);
  return unici([parola.slice(0, meta), parola.slice(parola.length - meta)]);
}

const chiave = (gruppi: readonly GruppoFrammenti[]) =>
  gruppi.map((g) => [...g].sort().join("|")).sort().join("&");

/**
 * I livelli di ricerca per una domanda. Vuoto se la domanda non ha nessuna
 * parola utilizzabile: in quel caso non si interroga il database.
 */
export function livelliDiRicerca(domanda: DomandaCandidati): LivelloRicerca[] {
  const prod = paroleSignificative(domanda.produttore, true).slice(0, MAX_PAROLE);
  const nome = paroleSignificative(domanda.nome, false)
    .filter((p) => !prod.includes(p))
    .slice(0, MAX_PAROLE);
  const tutte = unici([...prod, ...nome]).slice(0, MAX_PAROLE);
  if (tutte.length === 0) return [];

  const preciso: GruppoFrammenti[] = tutte.map((p) => [p]);

  const frammentiLato = (parole: readonly string[]) =>
    unici(parole.flatMap(frammentiTolleranti));
  const perLato: GruppoFrammenti[] = [];
  if (prod.length > 0) perLato.push(frammentiLato(prod));
  if (nome.length > 0) perLato.push(frammentiLato(nome));

  const ampio: GruppoFrammenti[] = [frammentiLato(tutte)];

  const candidati: LivelloRicerca[] = [
    { nome: "preciso", gruppi: preciso, limite: LIMITE_PRECISO },
    { nome: "per_lato", gruppi: perLato, limite: LIMITE_TOLLERANTE },
    { nome: "ampio", gruppi: ampio, limite: LIMITE_TOLLERANTE },
  ];
  // Un livello che produce lo stesso filtro del precedente non aggiunge nulla.
  const visti = new Set<string>();
  return candidati.filter((l) => {
    const k = chiave(l.gruppi);
    if (visti.has(k)) return false;
    visti.add(k);
    return true;
  });
}

// -- Rendering per PostgREST -------------------------------------------------

/** Solo lettere e cifre: nessun carattere speciale di PostgREST o di LIKE. */
const FRAMMENTO_SICURO = /^[\p{L}\p{N}]+$/u;

/**
 * Un gruppo come stringa di `.or()` di PostgREST, su uno o più campi:
 * `produttore.ilike.*sas*,nome.ilike.*sas*`. I frammenti arrivano da
 * `tokenNormalizzati` (solo lettere e cifre), ma si ricontrolla qui: un valore
 * con virgole, parentesi o `%` non deve mai entrare in un filtro.
 */
export function gruppoComeOr(gruppo: GruppoFrammenti, campi: readonly string[]): string {
  const parti: string[] = [];
  for (const frammento of gruppo) {
    if (!FRAMMENTO_SICURO.test(frammento)) {
      throw new Error("Frammento di ricerca non valido.");
    }
    for (const campo of campi) parti.push(`${campo}.ilike.*${frammento}*`);
  }
  return parti.join(",");
}

// -- Valutazione locale (solo per i test e per la fonte simulata) ------------

/**
 * Cosa farebbe `ilike '%frammento%'` sul campo: stessa semantica del database,
 * quindi SENZA piegare gli accenti. Serve a dimostrare nei test che un livello
 * trova (o non trova) una riga, non a sostituire il database.
 */
export function righeCheSoddisfano(
  livello: LivelloRicerca,
  campi: readonly string[],
  riga: Readonly<Record<string, string>>,
): boolean {
  return livello.gruppi.every((gruppo) =>
    gruppo.some((frammento) =>
      campi.some((c) => (riga[c] ?? "").toLocaleLowerCase("en-US").includes(frammento)),
    ),
  );
}
