// WI-004 — stato lato client del contesto del Sommelier.
//
// Qui non c'è nessuna autorità: il browser dice COSA l'utente vuole condividere
// (un annuncio, la propria Cantina) e il server decide e legge. Il modulo è puro
// e senza DOM, così le regole sul consenso si provano senza montare niente.
//
// Regole sul consenso alla Cantina, tutte imposte da qui e dal componente:
// - nasce spento e vive SOLO in memoria (mai in `localStorage`): una scheda
//   nuova, un ricaricamento o un logout lo azzerano;
// - è legato alla coppia (utente, sessione di conversazione): se cambia l'una o
//   l'altra non vale più;
// - aprire il Sommelier dalla Cantina NON lo concede: serve un gesto esplicito;
// - il server lo ripretende a ogni richiesta (`consenso: true` esatto).

import type { RichiestaContestoSommelier } from "@/services/types";

export type ContestoUi =
  | { tipo: "vino"; annuncioId: string; etichetta: string }
  /** WI-008: un vino del catalogo canonico, scelto con il suo codice LWIN-7. */
  | { tipo: "ricerca"; produttore: string; nome: string; codice: string; etichetta: string }
  /** `vuota`: la pagina sa già che non c'è nulla da condividere. */
  | { tipo: "cantina"; vuota: boolean };

export type Consenso = { utenteId: string; sessionId: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ETICHETTA_MAX = 80;
/** Limite del server per produttore e nome del contesto di ricerca. */
const CAMPO_RICERCA_MAX = 120;
const LWIN7 = /^[0-9]{7}$/;

const compatta = (testo: string, max: number): string => testo.replace(/\s+/g, " ").trim().slice(0, max).trimEnd();

/** Concede il consenso: possibile solo con un utente autenticato e una sessione di chat. */
export const concediConsenso = (utenteId: string | null, sessionId: string | null): Consenso | null =>
  utenteId && sessionId ? { utenteId, sessionId } : null;

/** Vale solo per esattamente quell'utente e quella sessione. */
export const consensoAttivo = (
  consenso: Consenso | null,
  utenteId: string | null,
  sessionId: string | null,
): boolean =>
  consenso !== null && utenteId !== null && sessionId !== null &&
  consenso.utenteId === utenteId && consenso.sessionId === sessionId;

/**
 * Il contesto da mandare al server, o `undefined` per il Sommelier generale.
 * - vino: solo l'identificativo dell'annuncio (dato pubblico);
 * - Cantina: solo con consenso attivo e Cantina non vuota, e mai altro che il consenso.
 */
export const richiestaContestoServer = (
  contesto: ContestoUi | null,
  consensoCantina: boolean,
): RichiestaContestoSommelier | undefined => {
  if (!contesto) return undefined;
  if (contesto.tipo === "vino") return { tipo: "vino", annuncioId: contesto.annuncioId };
  if (contesto.tipo === "ricerca") {
    return { tipo: "ricerca", produttore: contesto.produttore, nome: contesto.nome, codice: contesto.codice };
  }
  return consensoCantina && !contesto.vuota ? { tipo: "cantina", consenso: true } : undefined;
};

/** Pulsante «Chiedi al Sommelier» solo per annunci reali: un id dimostrativo non ha un vino da leggere. */
export const contestoVinoDaAnnuncio = (listingId: string | undefined, etichetta: string): ContestoUi | null => {
  if (!listingId || !UUID.test(listingId)) return null;
  return { tipo: "vino", annuncioId: listingId.toLowerCase(), etichetta: compatta(etichetta, ETICHETTA_MAX) };
};

/**
 * WI-008: solo un candidato con codice LWIN-7 del catalogo canonico può essere «questo vino»: nome e produttore da soli
 * non identificano (omonimi). Il codice è la scelta esplicita dell'utente; il server lo risolve e rilegge i dati.
 */
export const contestoRicercaDaCandidato = (candidato: {
  produttore: string;
  nome: string;
  canonico?: { lwin7: string };
}): ContestoUi | null => {
  const codice = candidato.canonico?.lwin7;
  if (!codice || !LWIN7.test(codice)) return null;
  return {
    tipo: "ricerca",
    produttore: compatta(candidato.produttore, CAMPO_RICERCA_MAX),
    nome: compatta(candidato.nome, CAMPO_RICERCA_MAX),
    codice,
    etichetta: compatta(`${candidato.produttore} ${candidato.nome}`, ETICHETTA_MAX),
  };
};

// ---------------------------------------------------------------------------
// Apertura da una pagina
// ---------------------------------------------------------------------------

type Ascoltatore = (contesto: ContestoUi) => void;
const ascoltatori = new Set<Ascoltatore>();

/** Chi mostra il Sommelier (il launcher e il pannello) si registra qui. */
export const ascoltaRichiesteSommelier = (ascoltatore: Ascoltatore): (() => void) => {
  ascoltatori.add(ascoltatore);
  return () => {
    ascoltatori.delete(ascoltatore);
  };
};

/**
 * Una pagina chiede di aprire il Sommelier su un contesto. L'evento descrive il
 * contesto e basta: non porta, e non può portare, alcun consenso.
 */
export const richiediSommelier = (contesto: ContestoUi): void => {
  for (const a of [...ascoltatori]) a(contesto);
};
