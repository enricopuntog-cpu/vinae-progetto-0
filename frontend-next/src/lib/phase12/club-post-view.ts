// Fase 12b - derivazioni pure delle discussioni di un club.
//
// Stanno qui e non dentro la pagina per gli stessi due motivi di club-view.ts:
// sono provabili senza montare React, ed e cosi che filtri e ordinamenti
// restano derivazioni. La lezione di 10c e che ripulire o ricalcolare un
// risultato derivato appartiene a una derivazione e mai a un effetto, perche la
// regola `set-state-in-effect` di Next 16 rifiuta un setState sincrono dentro
// un effetto - e ha ragione.
//
// Qui c'e in piu la validazione della composizione. I limiti replicano i CHECK
// della migrazione, e la replica e voluta: il vincolo autoritativo resta quello
// del database - e resta l'unico che conta per un chiamante che non sia questa
// UI - ma un messaggio in italiano prima del giro di rete e meglio di un 23514
// dopo che l'utente ha scritto ottomila caratteri.
//
// Nessun "use client" e nessun import di React: questo file e condiviso fra il
// componente server che legge le discussioni e quello client che le compone.

import type { ClubPost, ClubPostTipo, NuovoClubPost } from "@/services/types";

// I sette valori del CHECK a database, nello stesso ordine di PostTipo
// (frontend/src/data/communities.ts:134-135).
export const TIPI_POST: readonly ClubPostTipo[] = [
  "discussione",
  "domanda",
  "degustazione",
  "confronto",
  "consiglio",
  "sondaggio",
  "annuncio",
] as const;

export const ETICHETTE_TIPO_POST: Record<ClubPostTipo, string> = {
  discussione: "Discussione",
  domanda: "Domanda",
  degustazione: "Degustazione",
  confronto: "Confronto",
  consiglio: "Consiglio",
  sondaggio: "Sondaggio",
  annuncio: "Annuncio",
};

// Gli stessi numeri dei CHECK in 20260817120000_phase_12b_club_content.sql.
// Se divergono, quello che vince e il database: qui si perde solo il messaggio
// gentile.
export const LIMITI_POST = {
  titoloMin: 3,
  titoloMax: 160,
  corpoMin: 1,
  corpoMax: 8000,
  rispostaMax: 4000,
} as const;

// `null` quando va bene: la forma piu corta per "nessun errore", e quella che
// rende `if (errore)` l'unico ramo da scrivere nel componente.
export const validaNuovoPost = (input: NuovoClubPost): string | null => {
  const titolo = input.titolo.trim();
  const corpo = input.corpo.trim();

  if (titolo.length < LIMITI_POST.titoloMin) {
    return `Il titolo deve avere almeno ${LIMITI_POST.titoloMin} caratteri.`;
  }
  if (titolo.length > LIMITI_POST.titoloMax) {
    return `Il titolo non puo superare ${LIMITI_POST.titoloMax} caratteri.`;
  }
  if (corpo.length < LIMITI_POST.corpoMin) return "Scrivi il testo della discussione.";
  if (corpo.length > LIMITI_POST.corpoMax) {
    return `Il testo non puo superare ${LIMITI_POST.corpoMax} caratteri.`;
  }
  // Il vincolo che l'annuncio sia pubblico e, per questo tipo, dell'autore lo
  // verifica un trigger: il client non ha modo di saperlo e non deve fingere di
  // saperlo. Quello che puo dire e che il campo manca del tutto, che a database
  // e club_posts_annuncio_ha_listing.
  if (input.tipo === "annuncio" && !input.listingId) {
    return "Un post di tipo annuncio deve collegare un tuo annuncio pubblicato.";
  }
  return null;
};

export const validaRisposta = (corpo: string): string | null => {
  const testo = corpo.trim();
  if (testo.length === 0) return "Scrivi la tua risposta.";
  if (testo.length > LIMITI_POST.rispostaMax) {
    return `La risposta non puo superare ${LIMITI_POST.rispostaMax} caratteri.`;
  }
  return null;
};

export const filtraPostPerTipo = (
  post: ClubPost[],
  tipo: ClubPostTipo | "",
): ClubPost[] => (tipo ? post.filter((p) => p.tipo === tipo) : post);

// "Popolare" e definito qui e in un posto solo: piu mi piace, a parita piu
// risposte, a parita ancora il piu recente. Deliberatamente NON una formula con
// pesi - `miPiace * 2 + risposte` direbbe che due risposte valgono un like, che
// e un'affermazione sul prodotto che nessuna sessione ha fatto. Tre criteri in
// cascata si spiegano a chi guarda l'elenco; un punteggio no.
//
// Ordina una copia: `sort` muta l'array, e mutare la prop che il componente
// server ha consegnato farebbe divergere l'ordine dell'altro tab.
export const ordinaPerPopolarita = (post: ClubPost[]): ClubPost[] =>
  [...post].sort(
    (a, b) =>
      b.miPiace - a.miPiace ||
      b.risposte - a.risposte ||
      b.createdAt.localeCompare(a.createdAt),
  );

// I tipi che compaiono davvero fra le discussioni lette, nell'ordine canonico
// dei sette. Come `opzioniFiltro` per i club: un elenco scritto a mano si
// scollerebbe dal contenuto e offrirebbe un filtro che non seleziona nulla.
export const tipiPresenti = (post: ClubPost[]): ClubPostTipo[] => {
  const presenti = new Set(post.map((p) => p.tipo));
  return TIPI_POST.filter((t) => presenti.has(t));
};
