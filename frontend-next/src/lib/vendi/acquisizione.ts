/**
 * La conversione dei due fatti di acquisizione che /vendi raccoglie.
 *
 * Sta fuori dal wizard per la stessa ragione di `prezzo.ts`: l'errore qui non
 * è visibile. Un campo vuoto convertito con `Number("")` diventa zero e «non lo
 * so» diventerebbe «pagata 0 €», un dato che il database poi considera reale.
 *
 * Le tre regole contabili sono quindi tenute insieme:
 *
 * - **campo vuoto = sconosciuto.** Resta `null` e non si trasforma in zero;
 * - **zero esplicito = noto.** Il database registra che il costo è noto;
 * - **data = data.** Il `<input type="date">` produce una data di calendario,
 *   non un istante. Il timestamp inviato è la mezzanotte locale di quel giorno:
 *   una data come `2024-02-03` rimane il tre febbraio per chi l'ha scelta, in
 *   ogni fuso orario.
 */

/**
 * Da euro digitati a centesimi interi, con lo stesso `Math.round` del prezzo
 * dell'annuncio: evita che `24.99 * 100` diventi `2498.9999999999995` e poi
 * `2498` per troncamento. Stringa vuota o spazi significano «non lo so».
 */
export const prezzoAcquistoCents = (valore: string): number | null => {
  const teso = valore.trim();
  if (teso === "") return null;
  return Math.round(Number(teso) * 100);
};

/**
 * Da `aaaa-mm-gg` del campo data al timestamp per la RPC, o `null` se il campo
 * è vuoto. Il `new Date(a, m, g)` locale è voluto: non sposta il giorno nel
 * giorno precedente quando il browser è avanti rispetto a UTC.
 */
export const dataAcquistoPerRpc = (valore: string): string | null => {
  const corrispondenza = /^(\d{4})-(\d{2})-(\d{2})$/.exec(valore);
  if (!corrispondenza) return null;

  const anno = Number(corrispondenza[1]);
  const mese = Number(corrispondenza[2]);
  const giorno = Number(corrispondenza[3]);
  const data = new Date(anno, mese - 1, giorno);
  if (Number.isNaN(data.getTime())) return null;

  return data.toISOString();
};

/** I due fatti come vanno sul contratto: assenza e zero restano distinti. */
export const acquisizioneDaCampi = (campi: {
  prezzoEuro: string;
  data: string;
}): { acquisitionCostCents: number | null; acquiredAt: string | null } => ({
  acquisitionCostCents: prezzoAcquistoCents(campi.prezzoEuro),
  acquiredAt: dataAcquistoPerRpc(campi.data),
});
