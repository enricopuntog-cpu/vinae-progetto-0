import type { PrelievoSaldoStato } from "@/services/types";

/**
 * Le due decisioni che il pannello del prelievo deve prendere prima di parlare
 * con il database (D1).
 *
 * Stanno qui e non nel componente perché sono le uniche parti in cui un errore
 * si trasforma in denaro: un importo letto male diventa una richiesta di
 * prelievo sbagliata, e un bottone «Annulla» offerto sullo stato sbagliato
 * diventa una promessa che il server dovrà rompere.
 *
 * Nessuna delle due è autorevole. Il server rivalida l'importo contro lo
 * spendibile e rifiuta comunque l'annullamento di un bonifico partito: queste
 * funzioni servono a non far arrivare fin lì una richiesta già sbagliata.
 */

/** Sotto questa soglia un bonifico costa più di quanto trasferisce. */
export const PRELIEVO_MINIMO_CENTS = 1000;

export type ImportoPrelievo =
  | { ok: true; cents: number }
  | { ok: false; errore: string };

/**
 * Da quello che una persona digita ai centesimi interi.
 *
 * La virgola italiana e il punto valgono lo stesso; più di due decimali sono un
 * rifiuto e non un arrotondamento, perché arrotondare in silenzio significa
 * prelevare una cifra diversa da quella scritta.
 */
export const importoPrelievoInCentesimi = (
  testo: string,
  spendibileCents: number,
): ImportoPrelievo => {
  const pulito = testo.trim().replace(",", ".");
  if (pulito.length === 0) return { ok: false, errore: "Indica l'importo da prelevare." };
  if (!/^\d+(\.\d{1,2})?$/.test(pulito)) {
    return { ok: false, errore: "Scrivi l'importo in euro, con al massimo due decimali." };
  }

  const cents = Math.round(Number(pulito) * 100);
  if (!Number.isSafeInteger(cents) || cents <= 0) {
    return { ok: false, errore: "Indica un importo maggiore di zero." };
  }
  if (cents < PRELIEVO_MINIMO_CENTS) {
    return { ok: false, errore: "L'importo minimo di un prelievo è 10 €." };
  }
  if (cents > spendibileCents) {
    return { ok: false, errore: "L'importo supera il saldo spendibile." };
  }
  return { ok: true, cents };
};

/**
 * Un prelievo si annulla finché il denaro è soltanto impegnato.
 *
 * `in_corso` è fuori di proposito: il bonifico può essere già in volo, e
 * sciogliere lì la prenotazione aprirebbe la finestra in cui lo stesso importo
 * esce due volte. `fallito` invece rientra, perché è la via d'uscita di un
 * trasferimento che non riesce e continuerebbe altrimenti a tenere impegnati
 * centesimi che nessuno riuscirà a spostare.
 */
export const prelievoAnnullabile = (stato: PrelievoSaldoStato | string): boolean =>
  stato === "richiesto" || stato === "fallito";
