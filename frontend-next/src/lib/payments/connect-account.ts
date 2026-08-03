/**
 * Stato dell'account di incasso del venditore, e chiusura del debito
 * `seller_enabled` lasciato aperto dalla Fase 6a.
 *
 * Il ruolo venditore non è più un flag che qualcuno assegna: è una conseguenza
 * di ciò che il fornitore dichiara. Diventa vero quando l'account ha insieme
 * `charges_enabled` e `payouts_enabled`, e torna falso appena una delle due
 * decade — sempre attraverso un evento firmato, mai da una risposta a una
 * richiesta del venditore.
 *
 * L'autorità è il trigger `private.seller_enabled_sync`, che vincola anche
 * `service_role`. Questo modulo è la copia leggibile che serve alle schermate e
 * al Route Handler; i test rileggono la migrazione per accorgersi se le due
 * divergono.
 */

export type StatoAccountVenditore = {
  chargesEnabled: boolean;
  payoutsEnabled: boolean;
  detailsSubmitted: boolean;
  requisitiPendenti: string[];
  disabledReason: string | null;
};

export type FaseOnboarding =
  | "assente"
  | "da_completare"
  | "in_verifica"
  | "parziale"
  | "abilitato";

/** Il ruolo `seller_enabled` vale esattamente questa congiunzione, nient'altro. */
export const derivaSellerEnabled = (stato: StatoAccountVenditore | null): boolean =>
  stato !== null && stato.chargesEnabled && stato.payoutsEnabled;

/**
 * Fase leggibile per l'interfaccia. `parziale` esiste perché è uno stato reale e
 * frequente: il fornitore abilita gli incassi prima dei versamenti, e in quella
 * finestra il venditore può vendere ma non essere pagato. Chiamarla "abilitato"
 * sarebbe una bugia utile a nessuno.
 */
export const faseOnboarding = (stato: StatoAccountVenditore | null): FaseOnboarding => {
  if (stato === null) return "assente";
  if (stato.chargesEnabled && stato.payoutsEnabled) return "abilitato";
  if (!stato.detailsSubmitted) return "da_completare";
  if (stato.chargesEnabled || stato.payoutsEnabled) return "parziale";
  return stato.requisitiPendenti.length > 0 ? "da_completare" : "in_verifica";
};

/**
 * Gli eventi del fornitore non arrivano in ordine. Un `account.updated` più
 * vecchio dell'ultimo applicato non deve riaprire un account chiuso né chiudere
 * un account riaperto.
 *
 * Il confronto è `>=` e non `>`: due eventi con lo stesso istante sono
 * indistinguibili per ordine, e la deduplicazione su `(provider, event_id)` ha
 * già escluso che siano lo stesso evento. Rifiutare il secondo perderebbe un
 * aggiornamento vero.
 */
export const eventoApplicabile = (
  ultimoApplicatoISO: string | null,
  eventoISO: string,
): boolean => {
  const evento = new Date(eventoISO).getTime();
  if (Number.isNaN(evento)) return false;
  if (ultimoApplicatoISO === null) return true;
  const ultimo = new Date(ultimoApplicatoISO).getTime();
  return Number.isNaN(ultimo) ? true : evento >= ultimo;
};
