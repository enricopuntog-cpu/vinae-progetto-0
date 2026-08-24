/**
 * Le due decisioni sul prezzo del wizard /vendi che non sono interfaccia.
 *
 * Stanno qui e non dentro `useSellWizard` perché sono l'unica parte di quel
 * passo che si può sbagliare in silenzio: un campo compilato male si vede, una
 * conferma chiesta a sproposito no — si vede solo come attrito, e l'attrito si
 * attribuisce all'utente.
 */

/**
 * Da centesimi interi al valore del campo prezzo, che è in euro.
 *
 * `String(cents / 100)` e non una formattazione: quel valore torna indietro
 * come `Math.round(Number(prezzo) * 100)` quando si pubblica, e qualsiasi
 * separatore di migliaia o simbolo di valuta lo farebbe diventare `NaN`. La
 * divisione è esatta per costruzione — i centesimi sono interi, quindi il
 * risultato ha al massimo due decimali e `String` ne dà la scrittura più corta
 * che li rappresenta tutti.
 */
export const euroDaCents = (cents: number): string => String(cents / 100);

/**
 * Se il prezzo ereditato dall'annuncio precedente vada ancora confermato.
 *
 * La regola vecchia era «c'è un prezzo precedente, quindi chiedi conferma», e
 * chiedeva conferma anche a chi il prezzo lo aveva appena cambiato. Quella
 * domanda ha una risposta sola possibile e nessun contenuto: l'utente ha già
 * scelto, e la casella gli chiede di confermare un numero che non è più nel
 * campo.
 *
 * Il punto è che «prezzo precompilato» e «prezzo scelto» sono due cose diverse:
 *
 *   * precompilato e mai toccato — nessuno l'ha deciso, e fra i due annunci può
 *     essere passato molto tempo. La conferma serve, ed è l'unico caso;
 *   * modificato a mano — è già una scelta, fatta digitando;
 *   * applicato con «Usa questo prezzo» — è già una scelta, fatta con un clic
 *     esplicito su un numero che l'utente ha visto.
 *
 * Nessun prezzo precedente significa nessuna eredità da confermare.
 */
export const richiedeConfermaPrezzoPrecedente = (stato: {
  prezzoPrecedenteCents: number | null;
  /** L'utente ha digitato un prezzo o applicato il suggerimento. */
  sceltaEsplicita: boolean;
  /** L'utente ha spuntato la casella di conferma. */
  confermato: boolean;
}): boolean =>
  stato.prezzoPrecedenteCents !== null && !stato.sceltaEsplicita && !stato.confermato;
