// WI-002 — ricerca e valutazione dei vini candidati.
//
// Tre cose separate, perché il catalogo crescerà e le prime due devono poter
// cambiare senza toccare la terza:
//
//   1. `SorgenteCandidati` — da dove arrivano i candidati. Oggi sono il
//      catalogo e gli annunci pubblici, con ricerca limitata lato database
//      (`@/lib/vendi/ricerca-vini`); domani può essere il catalogo canonico
//      LWIN o un'altra fonte, dietro la stessa interfaccia e
//      con la ricerca lato server. Una fonte restituisce già un sottoinsieme.
//   2. `valutaCandidati` — normalizzazione, punteggio, ordinamento. Funzione
//      pura e deterministica: stesso input, stesso ordine, sempre.
//   3. La conferma dell'utente — fuori da qui (`pipeline.ts`/interfaccia).
//
// Nessuna fusione automatica di vini e nessuna creazione di dati di catalogo:
// questo modulo legge e ordina, mai scrive.

import type { Result } from "@/services/types";

export type CandidatoVino = {
  /** Codice della fonte che l'ha prodotto (es. `annunci_vinea`). */
  fonte: string;
  id: string;
  produttore: string;
  nome: string;
  annata: number | null;
  formato: string | null;
  regione: string | null;
  denominazione: string | null;
  tipo: string | null;
  /**
   * WI-006B — solo se la fonte ordina per pertinenza sul server (`vini_cerca`).
   * Le sorgenti senza ranking lasciano il campo assente; `valutaCandidati`
   * non lo usa per il punteggio (resta deterministico su produttore e nome).
   */
  corrispondenzaServer?: {
    livello: "identificativo" | "esatto" | "prefisso" | "testo" | "simile";
    punteggio: number;
  };
  /** Annunci pubblici attivi che descrivono questo vino (0 = solo catalogo). */
  annunci?: number;
  /**
   * WI-007 — solo per i vini del catalogo canonico (proiezione pubblica approvata):
   * identificativo LWIN-7 e provenienza con l'attribuzione richiesta dalla licenza
   * della fonte. Assente per ogni altra sorgente.
   * WI-011 — `codice` è il LWIN-7 quando esiste, altrimenti l'UUID del vino
   * canonico (identità nativa Vinea): `lwin7` resta `null`, mai inventato.
   */
  canonico?: {
    lwin7: string | null;
    codice: string;
    paese: string | null;
    territorio: string | null;
    fonteNome: string | null;
    licenza: string | null;
    attribuzione: string | null;
  };
};

export type DomandaCandidati = {
  produttore: string;
  nome: string;
  annata: number | null;
  formato: string | null;
};

/** WI-009 — la fonte facoltativa del catalogo non ha risposto in tempo oppure non ha risposto affatto. */
export type CatalogoIncompleto = "lento" | "non_disponibile";

export type OpzioniRicerca = {
  /** FIX-03B — facoltativo: chi lo supporta annulla la richiesta in corso quando il segnale scatta (tetto di attesa). */
  segnale?: AbortSignal;
  /** WI-009 — avvisa che i risultati sono completi solo per la fonte principale: chi chiama lo dichiara all utente. */
  onCatalogoIncompleto?: (motivo: CatalogoIncompleto) => void;
  /** WI-009 — tetto di attesa del catalogo per QUESTA ricerca (secondo tentativo chiesto dall utente). */
  attesaCatalogoMs?: number;
};

export interface SorgenteCandidati {
  readonly codice: string;
  cerca(domanda: DomandaCandidati, opzioni?: OpzioniRicerca): Promise<Result<CandidatoVino[]>>;
}

// -- Normalizzazione ---------------------------------------------------------

const PAROLE_VUOTE = new Set([
  "il", "lo", "la", "i", "gli", "le", "un", "una", "di", "del", "dello", "della", "dei",
  "degli", "delle", "de", "da", "the", "of", "et", "e", "and", "en", "des", "du", "d", "l",
]);

/** Parole che qualificano il produttore senza identificarlo. */
const FILLER_PRODUTTORE = new Set([
  "azienda", "agricola", "az", "agr", "societa", "soc", "cantina", "cantine", "tenuta",
  "tenute", "fattoria", "casa", "vinicola", "cascina", "cooperativa", "srl", "spa", "ss",
  "domaine", "chateau", "bodega", "weingut", "vigneti", "vignaioli",
]);

const SIGLE_DENOMINAZIONE = new Set(["docg", "doc", "igt", "igp", "dop", "aoc", "aop"]);

export function normalizzaTesto(testo: string): string {
  return testo
    .normalize("NFD")
    .replace(/\p{M}+/gu, "")
    // Sigle puntate («S.r.l.», «S.p.A.») diventano una parola sola.
    .replace(/\b(\p{L})\.(?=\p{L}\b)/gu, "$1")
    .toLocaleLowerCase("it-IT")
    .replace(/['’`]/g, " ")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();
}

export function tokenNormalizzati(testo: string, comeProduttore = false): string[] {
  return normalizzaTesto(testo)
    .split(" ")
    .filter(Boolean)
    .filter((t) => !PAROLE_VUOTE.has(t))
    .filter((t) => !SIGLE_DENOMINAZIONE.has(t))
    .filter((t) => !/^(?:19|20)\d{2}$/.test(t))
    .filter((t) => !(comeProduttore && FILLER_PRODUTTORE.has(t)));
}

// -- Similarità --------------------------------------------------------------

function distanzaEntro(a: string, b: string, limite: number): boolean {
  if (Math.abs(a.length - b.length) > limite) return false;
  const righe: number[][] = Array.from({ length: a.length + 1 }, (_, i) => [i]);
  for (let j = 1; j <= b.length; j++) righe[0][j] = j;
  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      righe[i][j] = Math.min(
        righe[i - 1][j] + 1,
        righe[i][j - 1] + 1,
        righe[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1),
      );
    }
  }
  return righe[a.length][b.length] <= limite;
}

/** 1 se uguali, 0,85 se differiscono per un refuso da OCR, altrimenti 0. */
function similitudineToken(a: string, b: string): number {
  if (a === b) return 1;
  const limite = Math.min(a.length, b.length) >= 9 ? 2 : Math.min(a.length, b.length) >= 5 ? 1 : 0;
  return limite > 0 && distanzaEntro(a, b, limite) ? 0.85 : 0;
}

/**
 * Similarità tra due insiemi di parole, in [0,1]. Dice sui token, più un
 * riconoscimento dell'inclusione («Antinori» in «Marchesi Antinori»), che però
 * non arriva mai a 1: un nome contenuto in un altro non è lo stesso nome.
 */
export function similitudine(a: string[], b: string[]): number {
  if (a.length === 0 || b.length === 0) return 0;
  const usati = new Set<number>();
  let somma = 0;
  let abbinati = 0;
  for (const ta of a) {
    let migliore = 0;
    let indice = -1;
    b.forEach((tb, i) => {
      if (usati.has(i)) return;
      const s = similitudineToken(ta, tb);
      if (s > migliore) {
        migliore = s;
        indice = i;
      }
    });
    if (indice >= 0) {
      usati.add(indice);
      somma += migliore;
      abbinati++;
    }
  }
  const dice = (2 * somma) / (a.length + b.length);
  const minore = Math.min(a.length, b.length);
  const inclusione = abbinati === minore ? 0.85 * (somma / minore) : 0;
  return Math.max(dice, inclusione);
}

// -- Valutazione -------------------------------------------------------------

export type EsitoCorrispondenza =
  | "esatta"
  | "probabile"
  | "annata_diversa"
  | "formato_diverso"
  | "possibile";

export type CandidatoValutato = CandidatoVino & {
  /** In [0,1]; confronta solo produttore e nome. */
  punteggio: number;
  esito: EsitoCorrispondenza;
  /** Quanti annunci/righe della fonte descrivono questo stesso vino. */
  occorrenze: number;
  /**
   * FIX-03A — quante ALTRE schede hanno lo stesso produttore e nome (almeno una canonica) senza che l'identità sia
   * provata. Assente se zero. L'interfaccia lo dichiara; la scelta resta all'utente.
   */
  omonimi?: number;
};

export type SintesiRicerca = "nessuna" | "unica" | "ambigua";

export const MAX_CANDIDATI = 5;
export const SOGLIA_MINIMA = 0.55;
const SOGLIA_ESATTA = 0.9;

const ORDINE_ESITO: Record<EsitoCorrispondenza, number> = {
  esatta: 0,
  probabile: 1,
  annata_diversa: 2,
  formato_diverso: 3,
  possibile: 4,
};

const confronta = (a: string, b: string) => a.localeCompare(b, "it", { sensitivity: "base" });

function chiaveVino(c: CandidatoVino): string {
  return [
    tokenNormalizzati(c.produttore, true).join(" "),
    tokenNormalizzati(c.nome).join(" "),
    c.annata ?? "",
    c.formato ?? "",
  ].join("|");
}

export function valutaCandidati(
  domanda: DomandaCandidati,
  candidati: readonly CandidatoVino[],
  opzioni: { max?: number; sogliaMinima?: number } = {},
): CandidatoValutato[] {
  const max = opzioni.max ?? MAX_CANDIDATI;
  const soglia = opzioni.sogliaMinima ?? SOGLIA_MINIMA;
  const tProd = tokenNormalizzati(domanda.produttore, true);
  const tNome = tokenNormalizzati(domanda.nome);
  if (tProd.length === 0 && tNome.length === 0) return [];

  // Uno stesso vino può comparire in più righe (più annunci): si conta, non si moltiplica.
  // FIX-03A — la chiave descrittiva (produttore + nome + annata + formato) identifica le righe Vinea della STESSA
  // fonte, non prova che una scheda canonica sia lo stesso vino. Quindi: una scheda canonica si raggruppa solo con
  // un'altra scheda canonica dello stesso LWIN-7 (identità autorevole) e NON si fonde mai con un vino Vinea; due LWIN
  // diversi con la stessa chiave restano due candidati; il vino Vinea conserva tutti i suoi campi e non riceve alcun
  // LWIN. Dentro un gruppo vince l'id più piccolo solo fra righe equivalenti, quindi l'esito non dipende dall'ordine
  // di arrivo. Se più schede hanno lo stesso nome, `omonimi` lo dichiara e sceglie l'utente.
  const unici = new Map<string, { scelto: CandidatoVino; occorrenze: number }>();
  for (const c of candidati) {
    const k = c.canonico ? `scheda|${c.canonico.codice}` : chiaveVino(c);
    const presente = unici.get(k);
    if (!presente) unici.set(k, { scelto: c, occorrenze: 1 });
    else {
      presente.occorrenze++;
      if (confronta(c.id, presente.scelto.id) < 0) presente.scelto = c;
    }
  }

  const valutati: CandidatoValutato[] = [];
  for (const { scelto: c, occorrenze } of unici.values()) {
    const sProd = similitudine(tProd, tokenNormalizzati(c.produttore, true));
    const sNome = similitudine(tNome, tokenNormalizzati(c.nome));
    const entrambi = tProd.length > 0 && tNome.length > 0;
    // Con un solo dei due campi letti il punteggio non può superare 0,8: il
    // vino non è identificato, solo compatibile.
    const punteggio = entrambi
      ? 0.45 * sProd + 0.55 * sNome
      : Math.min(0.8, tProd.length > 0 ? sProd : sNome);
    if (punteggio < soglia) continue;

    let esito: EsitoCorrispondenza;
    const annataNota = domanda.annata !== null && c.annata !== null;
    const formatoNoto = domanda.formato !== null && c.formato !== null;
    if (annataNota && domanda.annata !== c.annata) esito = "annata_diversa";
    else if (formatoNoto && domanda.formato !== c.formato) esito = "formato_diverso";
    else if (
      entrambi && sProd >= SOGLIA_ESATTA && sNome >= SOGLIA_ESATTA && annataNota
    ) esito = "esatta";
    else if (entrambi && punteggio >= 0.8) esito = "probabile";
    else esito = "possibile";

    valutati.push({ ...c, punteggio: Math.round(punteggio * 1e6) / 1e6, esito, occorrenze });
  }

  // Omonimia dichiarata: stesso produttore e nome di un'altra scheda, con almeno una canonica e annata/formato non
  // contraddittori (la scheda canonica li ha `null`). Due vini Vinea di annate diverse non sono omonimi.
  const chiaveNome = (c: CandidatoVino) =>
    `${tokenNormalizzati(c.produttore, true).join(" ")}|${tokenNormalizzati(c.nome).join(" ")}`;
  const compatibili = (a: CandidatoVino, b: CandidatoVino) =>
    !(a.annata !== null && b.annata !== null && a.annata !== b.annata) &&
    !(a.formato !== null && b.formato !== null && a.formato !== b.formato);
  const chiaviNome = new Map(valutati.map((v) => [v, chiaveNome(v)]));
  for (const v of valutati) {
    const omonimi = valutati.filter(
      (w) => w !== v && (v.canonico || w.canonico) && chiaviNome.get(w) === chiaviNome.get(v) && compatibili(v, w),
    ).length;
    if (omonimi > 0) v.omonimi = omonimi;
  }

  valutati.sort(
    (a, b) =>
      b.punteggio - a.punteggio ||
      ORDINE_ESITO[a.esito] - ORDINE_ESITO[b.esito] ||
      confronta(a.produttore, b.produttore) ||
      confronta(a.nome, b.nome) ||
      (a.annata ?? 0) - (b.annata ?? 0) ||
      confronta(a.formato ?? "", b.formato ?? "") ||
      confronta(a.id, b.id),
  );
  return valutati.slice(0, max);
}

/**
 * `unica` solo se un candidato è esatto e nessun altro è alla pari: in tutti gli
 * altri casi l'utente deve scegliere, e può sempre rifiutarli tutti.
 */
export function sintesiRicerca(valutati: readonly CandidatoValutato[]): SintesiRicerca {
  if (valutati.length === 0) return "nessuna";
  const [primo, secondo] = valutati;
  if (valutati.length === 1 && primo.esito === "esatta") return "unica";
  if (primo.esito === "esatta" && secondo && secondo.punteggio < primo.punteggio - 0.1 && secondo.esito !== "esatta") {
    return "unica";
  }
  return "ambigua";
}
