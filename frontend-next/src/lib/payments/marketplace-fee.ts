/**
 * Matematica del rincaro di piattaforma.
 *
 * Il rincaro non è una percentuale scelta: è una percentuale *risultante*. Il
 * parametro scelto è il margine netto che deve restare alla piattaforma DOPO la
 * fee del fornitore, e il totale è il numero che lo realizza:
 *
 *     totale = ceil( (prezzo * (10000 + margine) / 10000 + fisso)
 *                    / (1 - percentuale / 10000) )
 *
 * Due conseguenze che vale la pena aspettarsi prima di vederle nei numeri:
 *
 * - la percentuale effettiva è **alta sui prezzi bassi** — su 10 € la quota
 *   fissa da 0,25 € pesa quanto il 2,5% — e scende verso un asintoto sui prezzi
 *   alti. Non è un difetto del calcolo: è la quota fissa che si diluisce;
 * - l'arrotondamento è **sempre per eccesso**. Per difetto il margine
 *   scenderebbe sotto l'obiettivo di un centesimo, e sotto l'obiettivo è sotto
 *   l'obiettivo anche per un centesimo.
 *
 * Tre cose vanno tenute distinte, e questo modulo esiste per non farle
 * confondere:
 *
 * - **calcolare** un totale dai parametri correnti serve a *mostrare* un
 *   preventivo prima che l'ordine esista;
 * - **leggere** la scomposizione di un ordine già nato serve a mostrare quanto
 *   si sta pagando davvero, e quei numeri sono congelati sulla riga;
 * - **proiettare** il margine è una previsione costruita su una fee di
 *   riferimento, non una misura: la fee vera dipende dal metodo di pagamento e
 *   si riconcilia altrove.
 *
 * Ricalcolare il secondo caso a partire dalla configurazione corrente è il bug
 * che questo file rende difficile scrivere: `scomposizioneOrdine` non prende
 * nessun parametro di configurazione, perché non ne ha bisogno.
 *
 * L'autorità sul calcolo resta la RPC `order_checkout_reserve`, che chiama
 * `private.marketplace_totale_cents`. Questa è la copia che il browser usa per
 * il preventivo, e usa la stessa identità in aritmetica intera: numeratore e
 * denominatore moltiplicati per 10000, `ceil` applicato una volta sola.
 */

/** Massimi ammessi anche dai `check` di `marketplace_config`. */
export const MARGINE_OBIETTIVO_BPS_MASSIMO = 5000;
export const RIFERIMENTO_PERCENTUALE_BPS_MASSIMO = 5000;
export const RIFERIMENTO_FISSO_CENTS_MASSIMO = 10000;

/** I tre parametri versionati. Viaggiano insieme: nessuno ha senso da solo. */
export type ParametriCommissione = {
  /** Margine netto che deve restare DOPO la fee del fornitore. */
  margineObiettivoBps: number;
  /** Quota percentuale della fee di riferimento. */
  riferimentoStripePercentualeBps: number;
  /** Quota fissa della fee di riferimento, in centesimi. */
  riferimentoStripeFissoCents: number;
};

export type ScomposizionePrezzo = ParametriCommissione & {
  /** Quanto incassa il venditore. */
  prezzoVenditoreCents: number;
  commissioneCents: number;
  /** Quanto paga il compratore: la commissione sta sopra, non dentro. */
  totaleCents: number;
};

/** Ciò che serve leggere di un ordine per mostrarne la scomposizione. */
export type OrdineConCommissione = {
  prezzo_cents: number;
  commissione_cents: number;
  totale_cents: number;
  margine_obiettivo_bps: number;
  riferimento_stripe_percentuale_bps: number;
  riferimento_stripe_fisso_cents: number;
};

const interoNonNegativo = (valore: number): boolean =>
  Number.isInteger(valore) && valore >= 0;

const validaParametri = (parametri: ParametriCommissione): void => {
  const {
    margineObiettivoBps,
    riferimentoStripePercentualeBps,
    riferimentoStripeFissoCents,
  } = parametri;
  if (!interoNonNegativo(margineObiettivoBps) || margineObiettivoBps > MARGINE_OBIETTIVO_BPS_MASSIMO) {
    throw new RangeError(
      `Il margine obiettivo deve essere un intero fra 0 e ${MARGINE_OBIETTIVO_BPS_MASSIMO} punti base.`,
    );
  }
  if (
    !interoNonNegativo(riferimentoStripePercentualeBps) ||
    riferimentoStripePercentualeBps > RIFERIMENTO_PERCENTUALE_BPS_MASSIMO
  ) {
    throw new RangeError(
      `La percentuale di riferimento deve essere un intero fra 0 e ${RIFERIMENTO_PERCENTUALE_BPS_MASSIMO} punti base.`,
    );
  }
  if (
    !interoNonNegativo(riferimentoStripeFissoCents) ||
    riferimentoStripeFissoCents > RIFERIMENTO_FISSO_CENTS_MASSIMO
  ) {
    throw new RangeError(
      `La quota fissa di riferimento deve essere un intero fra 0 e ${RIFERIMENTO_FISSO_CENTS_MASSIMO} centesimi.`,
    );
  }
};

/**
 * Preventivo: quanto pagherebbe oggi un compratore per un dato prezzo di
 * vendita. Non è ciò che verrà addebitato se la configurazione cambia fra
 * questa schermata e la creazione dell'ordine — il numero vincolante nasce in
 * transazione lato server.
 *
 * Il denominatore non si annulla mai: `riferimentoStripePercentualeBps` è al
 * massimo 5000, quindi vale almeno 5000. È lo stesso `check` che sta sulla
 * tabella, ripetuto qui perché questa funzione non vede il database.
 */
export const calcolaCommissione = (
  prezzoVenditoreCents: number,
  parametri: ParametriCommissione,
): ScomposizionePrezzo => {
  if (!Number.isInteger(prezzoVenditoreCents) || prezzoVenditoreCents <= 0) {
    throw new RangeError("Il prezzo del venditore deve essere un intero positivo di centesimi.");
  }
  validaParametri(parametri);

  const numeratore =
    prezzoVenditoreCents * (10000 + parametri.margineObiettivoBps) +
    parametri.riferimentoStripeFissoCents * 10000;
  const denominatore = 10000 - parametri.riferimentoStripePercentualeBps;
  const totaleCents = Math.ceil(numeratore / denominatore);

  return {
    ...parametri,
    prezzoVenditoreCents,
    // Per sottrazione, non per moltiplicazione: è ciò che tiene
    // `totale = prezzo + commissione` vero per costruzione, come la colonna
    // generata in database pretende che sia.
    commissioneCents: totaleCents - prezzoVenditoreCents,
    totaleCents,
  };
};

/**
 * Scomposizione di un ordine esistente, letta e non ricalcolata.
 *
 * Se la riga fosse incoerente — commissione che non corrisponde ai parametri
 * congelati — questa funzione **non la corregge**: restituisce ciò che il
 * database ha scritto. Correggere qui significherebbe mostrare al compratore un
 * numero diverso da quello addebitato.
 */
export const scomposizioneOrdine = (ordine: OrdineConCommissione): ScomposizionePrezzo => ({
  prezzoVenditoreCents: ordine.prezzo_cents,
  commissioneCents: ordine.commissione_cents,
  totaleCents: ordine.totale_cents,
  margineObiettivoBps: ordine.margine_obiettivo_bps,
  riferimentoStripePercentualeBps: ordine.riferimento_stripe_percentuale_bps,
  riferimentoStripeFissoCents: ordine.riferimento_stripe_fisso_cents,
});

/**
 * Percentuale davvero addebitata, in punti base. È un rapporto derivato e non
 * una colonna: memorizzarla darebbe due sorgenti per lo stesso numero, e prima
 * o poi divergerebbero di un centesimo.
 */
export const commissioneEffettivaBps = (scomposizione: ScomposizionePrezzo): number =>
  (scomposizione.commissioneCents * 10000) / scomposizione.prezzoVenditoreCents;

/**
 * Margine netto proiettato, in centesimi, con la fee di riferimento NON
 * arrotondata. Può essere frazionario apposta: è il numero su cui vale
 * l'invariante del `ceil`, e arrotondarlo qui nasconderebbe proprio il
 * centesimo che l'arrotondamento per eccesso è lì a difendere.
 *
 * Entrambe le quantità si calcolano come **numeratore intero diviso 10000**, e
 * non sommando termini già divisi. Non è pedanteria: `a/10000 - b/10000` accumula
 * un errore di 1e-14 che rende `>=` un lancio di dadi proprio sui casi in cui
 * margine e obiettivo coincidono — che sono i casi interessanti. Con un solo
 * quoziente finale il confronto resta esatto, perché la divisione per una
 * costante positiva conserva l'ordine.
 *
 * Il margine reale — quello con la fee davvero trattenuta — non si calcola: si
 * misura, e vive in `order_margine_riconciliazione`.
 */
export const margineProiettatoCents = (scomposizione: ScomposizionePrezzo): number =>
  (scomposizione.totaleCents * 10000 -
    scomposizione.totaleCents * scomposizione.riferimentoStripePercentualeBps -
    scomposizione.riferimentoStripeFissoCents * 10000 -
    scomposizione.prezzoVenditoreCents * 10000) /
  10000;

/** L'obiettivo che il margine proiettato deve raggiungere o superare. */
export const margineObiettivoCents = (scomposizione: ScomposizionePrezzo): number =>
  (scomposizione.prezzoVenditoreCents * scomposizione.margineObiettivoBps) / 10000;

/** Percentuale leggibile, per le schermate: 500 punti base → "5%". */
export const percentualeLeggibile = (bps: number): string => {
  const percentuale = bps / 100;
  return `${Number.isInteger(percentuale) ? percentuale : percentuale.toFixed(2)}%`;
};
