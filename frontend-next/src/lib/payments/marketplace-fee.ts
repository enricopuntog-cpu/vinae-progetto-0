/**
 * Matematica della commissione di piattaforma.
 *
 * Due cose vanno tenute distinte, e questo modulo esiste per non farle
 * confondere:
 *
 * - **calcolare** una commissione da una percentuale serve a *mostrare* un
 *   preventivo prima che l'ordine esista;
 * - **leggere** la commissione di un ordine già nato serve a mostrare quanto si
 *   sta pagando davvero, e quel numero è congelato sulla riga.
 *
 * Ricalcolare il secondo caso a partire dalla configurazione corrente è il bug
 * che questo file rende difficile scrivere: `scomposizioneOrdine` non prende
 * nessuna percentuale come parametro, perché non ne ha bisogno.
 *
 * L'autorità sul calcolo resta la RPC `order_checkout_reserve` — questa è la
 * copia che il browser usa per il preventivo. Le due arrotondano allo stesso
 * modo: `round(prezzo * bps / 10000)` in Postgres su `numeric`,
 * `Math.round(prezzo * bps / 10000)` qui. Entrambi gli operandi sono positivi,
 * quindi "metà per eccesso" e "metà lontano da zero" coincidono.
 */

/** Massimo ammesso anche dal `check` di `marketplace_config.commissione_bps`. */
export const COMMISSIONE_BPS_MASSIMA = 5000;

export type ScomposizionePrezzo = {
  /** Quanto incassa il venditore. */
  prezzoVenditoreCents: number;
  commissioneCents: number;
  /** Quanto paga il compratore: la commissione sta sopra, non dentro. */
  totaleCents: number;
  commissioneBps: number;
};

/** Ciò che serve leggere di un ordine per mostrarne la scomposizione. */
export type OrdineConCommissione = {
  prezzo_cents: number;
  commissione_bps: number;
  commissione_cents: number;
  totale_cents: number;
};

const interoNonNegativo = (valore: number): boolean =>
  Number.isInteger(valore) && valore >= 0;

/**
 * Preventivo: quanto pagherebbe oggi un compratore per un prezzo di vendita.
 * Non è ciò che verrà addebitato se la configurazione cambia fra questa schermata
 * e la creazione dell'ordine — il numero vincolante nasce in transazione lato
 * server.
 */
export const calcolaCommissione = (
  prezzoVenditoreCents: number,
  commissioneBps: number,
): ScomposizionePrezzo => {
  if (!Number.isInteger(prezzoVenditoreCents) || prezzoVenditoreCents <= 0) {
    throw new RangeError("Il prezzo del venditore deve essere un intero positivo di centesimi.");
  }
  if (!interoNonNegativo(commissioneBps) || commissioneBps > COMMISSIONE_BPS_MASSIMA) {
    throw new RangeError(
      `La percentuale deve essere un intero fra 0 e ${COMMISSIONE_BPS_MASSIMA} punti base.`,
    );
  }

  const commissioneCents = Math.round((prezzoVenditoreCents * commissioneBps) / 10000);
  return {
    prezzoVenditoreCents,
    commissioneCents,
    totaleCents: prezzoVenditoreCents + commissioneCents,
    commissioneBps,
  };
};

/**
 * Scomposizione di un ordine esistente, letta e non ricalcolata.
 *
 * Se la riga fosse incoerente — commissione che non corrisponde alla percentuale
 * congelata — questa funzione **non la corregge**: restituisce ciò che il
 * database ha scritto. Correggere qui significherebbe mostrare al compratore un
 * numero diverso da quello addebitato.
 */
export const scomposizioneOrdine = (ordine: OrdineConCommissione): ScomposizionePrezzo => ({
  prezzoVenditoreCents: ordine.prezzo_cents,
  commissioneCents: ordine.commissione_cents,
  totaleCents: ordine.totale_cents,
  commissioneBps: ordine.commissione_bps,
});

/** Percentuale leggibile, per le schermate: 500 punti base → "5%". */
export const percentualeLeggibile = (commissioneBps: number): string => {
  const percentuale = commissioneBps / 100;
  return `${Number.isInteger(percentuale) ? percentuale : percentuale.toFixed(2)}%`;
};
