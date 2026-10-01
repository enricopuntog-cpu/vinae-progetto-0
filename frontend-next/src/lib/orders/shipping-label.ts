/**
 * La geometria dei due fogli di stampa, e nient'altro.
 *
 * Questo modulo **non genera etichette**: non disegna codici a barre, non
 * ricostruisce QR, non ricompone il layout del corriere. L'etichetta è un
 * documento del fornitore e si stampa così com'è. Qui si calcola solo quanto
 * grande può apparire su un foglio, perché è l'unico punto in cui una stampa
 * può rovinarla: ingrandita fino a uscire dal bordo, o adattata al foglio
 * deformandola, diventa un codice che il lettore della rete non legge.
 *
 * Perciò una sola regola, `contain`: il documento entra intero, conserva le
 * proporzioni, e lo spazio che avanza resta bianco. Mai `cover`, mai un
 * ritaglio.
 */

import type { ShipmentLabelFormat } from "@/services/types";

export type Foglio = { larghezzaMm: number; altezzaMm: number };

/** A4 e termica 100×150, in millimetri: le misure sono il contratto. */
export const FOGLI: Record<ShipmentLabelFormat, Foglio> = {
  a4: { larghezzaMm: 210, altezzaMm: 297 },
  thermal_100x150: { larghezzaMm: 100, altezzaMm: 150 },
};

export type Riquadro = {
  larghezzaMm: number;
  altezzaMm: number;
  /** Margine calcolato, non richiesto: è ciò che avanza attorno al documento. */
  offsetXMm: number;
  offsetYMm: number;
  /** Il fattore applicato al documento. Non supera mai 1: non si ingrandisce. */
  scala: number;
};

/**
 * Dove sta il documento dentro il foglio, a proporzioni intatte.
 *
 * Il fattore è il minore fra i due rapporti — è questo che rende la regola
 * `contain` e non `cover` — ed è tagliato a 1: un documento più piccolo del
 * foglio si stampa alla sua misura invece di essere gonfiato, perché
 * ingrandire un codice a barre stampato ne allarga anche le imprecisioni.
 *
 * Un documento di misura non positiva non ha una collocazione: torna `null`,
 * e chi stampa decide che farne, invece di ricevere un riquadro inventato.
 */
export function riquadroContenuto(
  documento: { larghezzaMm: number; altezzaMm: number },
  formato: ShipmentLabelFormat,
): Riquadro | null {
  if (
    !Number.isFinite(documento.larghezzaMm) ||
    !Number.isFinite(documento.altezzaMm) ||
    documento.larghezzaMm <= 0 ||
    documento.altezzaMm <= 0
  ) {
    return null;
  }

  const foglio = FOGLI[formato];
  const scala = Math.min(
    1,
    foglio.larghezzaMm / documento.larghezzaMm,
    foglio.altezzaMm / documento.altezzaMm,
  );

  const larghezzaMm = documento.larghezzaMm * scala;
  const altezzaMm = documento.altezzaMm * scala;

  return {
    larghezzaMm,
    altezzaMm,
    offsetXMm: (foglio.larghezzaMm - larghezzaMm) / 2,
    offsetYMm: (foglio.altezzaMm - altezzaMm) / 2,
    scala,
  };
}

/**
 * Le proporzioni sono conservate se il rapporto d'aspetto sopravvive alla
 * scalatura. La tolleranza assorbe il virgola mobile, non una deformazione:
 * un millesimo di differenza è aritmetica, un centesimo è un'etichetta storta.
 */
export function proporzioniConservate(
  documento: { larghezzaMm: number; altezzaMm: number },
  riquadro: Riquadro,
): boolean {
  const atteso = documento.larghezzaMm / documento.altezzaMm;
  const ottenuto = riquadro.larghezzaMm / riquadro.altezzaMm;
  return Math.abs(atteso - ottenuto) < 1e-9;
}

/** Vero quando il documento esce dal foglio: con `contain` non accade mai. */
export function eccedeIlFoglio(riquadro: Riquadro, formato: ShipmentLabelFormat): boolean {
  const foglio = FOGLI[formato];
  const tolleranza = 1e-9;
  return (
    riquadro.larghezzaMm > foglio.larghezzaMm + tolleranza ||
    riquadro.altezzaMm > foglio.altezzaMm + tolleranza ||
    riquadro.offsetXMm < -tolleranza ||
    riquadro.offsetYMm < -tolleranza
  );
}
