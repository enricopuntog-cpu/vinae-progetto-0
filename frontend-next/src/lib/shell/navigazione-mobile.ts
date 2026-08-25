/**
 * Modello della shell mobile: barra inferiore e azioni dell'header.
 *
 * Sta fuori da `Layout.tsx` perché è l'unica parte della shell che si può
 * verificare senza montare React, ed è anche quella che sbaglia in modo
 * silenzioso: una rotta che non esiste, una voce che resta accesa sulla pagina
 * sbagliata, la lente che ricompare dove non deve. Il componente continua a
 * decidere l'aspetto; qui c'è soltanto che cosa mostrare e quando è attivo.
 *
 * Le due liste sono separate e non una filtrata dall'altra: da autenticati la
 * quinta voce è Cantina e Account sparisce dalla barra, perché l'avatar
 * dell'header ci porta già. Da ospiti la barra resta quella che era.
 */

export type IconaNavMobile = "home" | "ricerca" | "vendi" | "club" | "cantina" | "account";

export type VoceNavMobile = {
  readonly to: string;
  readonly label: string;
  readonly icona: IconaNavMobile;
  /** Home è l'unica voce che non deve accendersi sulle rotte discendenti. */
  readonly exact: boolean;
};

export const NAV_MOBILE_OSPITE: readonly VoceNavMobile[] = [
  { to: "/", label: "Home", icona: "home", exact: true },
  { to: "/esplora", label: "Ricerca", icona: "ricerca", exact: false },
  { to: "/vendi", label: "Vendi", icona: "vendi", exact: false },
  { to: "/community", label: "Club", icona: "club", exact: false },
  { to: "/account", label: "Account", icona: "account", exact: false },
] as const;

export const NAV_MOBILE_AUTENTICATA: readonly VoceNavMobile[] = [
  { to: "/home", label: "Home", icona: "home", exact: true },
  { to: "/esplora", label: "Ricerca", icona: "ricerca", exact: false },
  { to: "/vendi", label: "Vendi", icona: "vendi", exact: false },
  { to: "/community", label: "Club", icona: "club", exact: false },
  { to: "/cantina", label: "Cantina", icona: "cantina", exact: false },
] as const;

export const navMobile = (autenticato: boolean): readonly VoceNavMobile[] =>
  autenticato ? NAV_MOBILE_AUTENTICATA : NAV_MOBILE_OSPITE;

/**
 * `/` e `/home` sono la stessa casella della barra: la landing pubblica e la
 * home privata non stanno mai entrambe nella stessa lista, quindi accendere la
 * voce Home su tutte e due non può accendere due voci insieme.
 */
const PERCORSI_HOME = new Set(["/", "/home"]);

/**
 * Una rotta e le sue discendenti, con il separatore esplicito e non
 * `startsWith` nudo: `/vendite` è una rotta reale e con il prefisso nudo
 * accendeva `Vendi`. La navigazione desktop faceva già il confronto giusto;
 * questo lo rende l'unica forma disponibile, così che non torni al prefisso
 * nudo il prossimo link che deve dirsi attivo.
 */
export const percorsoAttivo = (to: string, pathname: string): boolean =>
  pathname === to || pathname.startsWith(`${to}/`);

export const voceNavAttiva = (voce: VoceNavMobile, pathname: string): boolean => {
  if (voce.exact) {
    return PERCORSI_HOME.has(voce.to) ? PERCORSI_HOME.has(pathname) : pathname === voce.to;
  }
  return percorsoAttivo(voce.to, pathname);
};

/**
 * La lente esce dall'header mobile autenticato.
 *
 * Le azioni dell'header autenticato sono tre — Messaggi, Notifiche, avatar — e
 * la Ricerca ha già la sua voce nella barra inferiore: la lente sarebbe la
 * stessa destinazione due volte, e ruberebbe il posto all'avatar. Su desktop la
 * barra inferiore non esiste, quindi lì la lente resta dov'era.
 *
 * Da ospiti la stringa è vuota di proposito: la lente ospite deve restare
 * esattamente il link di prima, senza nemmeno una classe di display in più.
 * `md:inline-flex` compare solo dove serve a riaccendere ciò che `hidden` ha
 * spento.
 */
export const classiRicercaHeader = (autenticato: boolean): string =>
  autenticato ? "hidden md:inline-flex" : "";
