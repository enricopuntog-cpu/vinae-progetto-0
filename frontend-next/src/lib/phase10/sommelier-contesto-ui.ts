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
  /** `vuota`: la pagina sa già che non c'è nulla da condividere. */
  | { tipo: "cantina"; vuota: boolean };

export type Consenso = { utenteId: string; sessionId: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ETICHETTA_MAX = 80;

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
  return consensoCantina && !contesto.vuota ? { tipo: "cantina", consenso: true } : undefined;
};

/** Pulsante «Chiedi al Sommelier» solo per annunci reali: un id dimostrativo non ha un vino da leggere. */
export const contestoVinoDaAnnuncio = (listingId: string | undefined, etichetta: string): ContestoUi | null => {
  if (!listingId || !UUID.test(listingId)) return null;
  const pulita = etichetta.replace(/\s+/g, " ").trim().slice(0, ETICHETTA_MAX).trimEnd();
  return { tipo: "vino", annuncioId: listingId.toLowerCase(), etichetta: pulita };
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
