import type { PreventivoEconomico } from "@/services/preventivo-service";
import type { OpzioneLogistica } from "@/services/logistica-service";
import type { OrderDeliveryMode, PackagingOption } from "@/services/types";

/**
 * Destinazione di una spedizione: punto di ritiro (predefinito, PUDO-first) o
 * un indirizzo della rubrica dell'acquirente. La legge il checkout del
 * database da `checkout_consegna_imposta`; qui è solo la scelta della pagina.
 */
export type DestinazioneCheckout = "pudo" | "home";

export type CheckoutPasso = "contatti" | "consegna" | "imballaggio" | "pagamento";
export type MetodoPagamentoBeta = "carta" | "wallet";

export type DatiCheckoutBeta = {
  email: string;
  telefono: string;
  deliveryMode: OrderDeliveryMode;
  destinazione: DestinazioneCheckout;
  /** Indirizzo della rubrica per la consegna a domicilio (solo l'id). */
  indirizzoId: string | null;
  imballaggioCodice: string;
  metodoPagamento: MetodoPagamentoBeta;
};

export type ErroriCheckout = Partial<Record<keyof DatiCheckoutBeta, string>>;

export const creaDatiCheckout = (email = ""): DatiCheckoutBeta => ({
  email,
  telefono: "",
  deliveryMode: "spedizione",
  destinazione: "pudo",
  indirizzoId: null,
  imballaggioCodice: "nessuno",
  metodoPagamento: "carta",
});

export const passiCheckout = (imballaggioVisibile: boolean): CheckoutPasso[] =>
  imballaggioVisibile
    ? ["contatti", "consegna", "imballaggio", "pagamento"]
    : ["contatti", "consegna", "pagamento"];

/**
 * Dove atterra chi ha pagato interamente con il saldo Vinea.
 *
 * Non c'è nessuna pagina del fornitore da mostrare, quindi la conferma è tutta
 * nostra: si atterra su `/acquisti`, la lista degli ordini dell'acquirente, con
 * l'ordine appena creato indicato dai due parametri. Nessuna rotta nuova.
 *
 * L'identificativo viene codificato: finisce in una query string, e un valore
 * inatteso non deve poter aggiungere parametri che nessuno ha scritto.
 */
export const destinazioneSaldoOnly = (orderId: string): string =>
  `/acquisti?checkout=saldo&orderId=${encodeURIComponent(orderId)}`;

export const validaPassoCheckout = (
  passo: CheckoutPasso,
  dati: DatiCheckoutBeta,
): ErroriCheckout => {
  if (passo === "contatti") {
    return {
      ...(!/^\S+@\S+\.\S+$/.test(dati.email) ? { email: "Inserisci un indirizzo email valido." } : {}),
      ...(!/^\+?[0-9][0-9\s-]{5,}$/.test(dati.telefono)
        ? { telefono: "Inserisci un numero di telefono valido." }
        : {}),
    };
  }

  // L'indirizzo non si scrive più qui: si sceglie dalla rubrica, che il
  // database valida (`indirizzo_salva`) e congela sull'ordine. Il punto di
  // ritiro non chiede indirizzi all'acquirente.
  if (
    passo === "consegna" &&
    dati.deliveryMode === "spedizione" &&
    dati.destinazione === "home" &&
    !dati.indirizzoId
  ) {
    return { indirizzoId: "Scegli o aggiungi l'indirizzo di consegna." };
  }

  return {};
};

/** Listino locale uguale al seed 7c: prezzi zero per decisione esplicita. */
export const OPZIONI_IMBALLAGGIO_BETA: ReadonlyArray<PackagingOption> = Object.freeze([
  {
    codice: "kit_domicilio",
    provider: "fake",
    modalita: "kit_a_domicilio",
    etichetta: "Kit a domicilio",
    descrizione: "Materiale consegnato a casa; nessuna prenotazione viene creata nella beta.",
    prezzoCents: 0,
    richiedePunto: false,
  },
  {
    codice: "centro_partner",
    provider: "fake",
    modalita: "centro_partner",
    etichetta: "Centro attrezzato",
    descrizione: "Preferenza beta per un futuro punto di imballaggio.",
    prezzoCents: 0,
    richiedePunto: true,
  },
  {
    codice: "punto_quartiere",
    provider: "fake",
    modalita: "punto_quartiere",
    etichetta: "Punto di quartiere",
    descrizione: "Preferenza beta per una futura consegna di prossimità.",
    prezzoCents: 0,
    richiedePunto: true,
  },
]);

/**
 * Riepilogo del checkout sopra il preventivo autorevole del database (VP-D):
 * prezzo, servizio Vinea e totale vengono dalla stessa classe, riga e formula
 * che il checkout userà; qui si aggiungono gli accessori, fuori dalla
 * commissione, letti dal preventivo logistico del database
 * (`accessoriCheckout`). Senza preventivo non c'è riepilogo: nessun numero
 * ricavato da parametri fissi nel codice (prima di VP-D qui stavano i 500/150
 * bps della configurazione iniziale, superati dal 15 settembre 2026).
 */
export const riepilogoCheckout = (
  preventivo: PreventivoEconomico | null,
  imballaggioCents = 0,
  logisticaCents = 0,
  feePagamentoCents = 0,
) => {
  if (!preventivo) return null;

  return {
    prezzoCents: preventivo.subtotaleCents,
    commissioneCents: preventivo.commissioneCents,
    // Imballaggio 7c dichiarato sull'annuncio, come lo addebita il checkout
    // (non la preferenza beta scelta nel passo "imballaggio").
    imballaggioCents,
    // VP-E: la logistica di più bottiglie spedite (colli, imballaggio,
    // trasporto) è una riga a sé, fuori dalla commissione, dal preventivo
    // logistico del database.
    logisticaCents,
    // Copertura della fee di pagamento generata dagli accessori: calcolata dal
    // database con la formula unica, separata dal servizio Vinea.
    feePagamentoCents,
    totaleCents: preventivo.totaleCents + imballaggioCents + logisticaCents + feePagamentoCents,
  };
};

/** Vero se la logistica entra nell'addebito per questa scelta. */
export const logisticaInTotale = (
  quantita: number,
  deliveryMode: OrderDeliveryMode,
  destinazione: DestinazioneCheckout = "pudo",
): boolean => deliveryMode === "spedizione" && (destinazione === "home" || quantita > 1);

/**
 * VP-E: quanto della logistica entra nel totale. Al punto di ritiro solo per
 * più bottiglie spedite; a domicilio sempre, anche per una bottiglia (il
 * domicilio ha sempre un costo logistico, come nel checkout del database).
 * Zero senza logistica addebitata (una bottiglia al punto di ritiro, consegna
 * a mano); `null` se l'opzione della destinazione scelta non è ordinabile: il
 * checkout non si conferma e nessun prezzo viene inventato.
 */
export const logisticaAddebitata = (
  quantita: number,
  deliveryMode: OrderDeliveryMode,
  opzione: { ordinabile: boolean; totaleCents: number | null } | null,
  destinazione: DestinazioneCheckout = "pudo",
): number | null => {
  if (!logisticaInTotale(quantita, deliveryMode, destinazione)) return 0;
  if (!opzione || !opzione.ordinabile || opzione.totaleCents === null) return null;
  return opzione.totaleCents;
};

/** L'opzione del preventivo per la destinazione scelta, se il database la dà. */
export const opzioneDestinazione = <O extends { destinazione: DestinazioneCheckout }>(
  logistica: { opzioni: ReadonlyArray<O> } | null,
  destinazione: DestinazioneCheckout,
): O | null => logistica?.opzioni.find((o) => o.destinazione === destinazione) ?? null;

/**
 * Vero se il venditore consegna con ritiro (domicilio o sede) e l'indirizzo di
 * ritiro manca: il checkout del database fallirebbe con
 * `indirizzo_ritiro_mancante` anche per una bottiglia al punto di ritiro.
 */
export const ritiroVenditoreMancante = (
  opzione: { mancanti: ReadonlyArray<{ motivi: ReadonlyArray<string> }> } | null,
): boolean =>
  opzione?.mancanti.some((m) => m.motivi.includes("indirizzo_ritiro_mancante")) ?? false;

export type BloccoConsegna =
  /** Il venditore ritira a domicilio o in sede e il suo indirizzo manca. */
  | { motivo: "ritiro_venditore" }
  /** Domicilio scelto senza un indirizzo della rubrica. */
  | { motivo: "indirizzo_consegna" }
  /** L'opzione della destinazione scelta non è ordinabile (o il preventivo non si legge). */
  | { motivo: "logistica"; mancanti: OpzioneLogistica["mancanti"] };

/**
 * Perché la conferma non può partire con la consegna scelta, o `null`. Le
 * stesse condizioni che il checkout del database verifica (origine,
 * destinazione, logistica addebitata), dette prima del clic: mai un prezzo
 * inventato, mai una prenotazione che il database rifiuterebbe.
 */
export const bloccoConsegna = (
  quantita: number,
  dati: Pick<DatiCheckoutBeta, "deliveryMode" | "destinazione" | "indirizzoId">,
  logistica: { opzioni: ReadonlyArray<Pick<OpzioneLogistica, "destinazione" | "ordinabile" | "totaleCents" | "mancanti">> } | null,
): BloccoConsegna | null => {
  if (dati.deliveryMode !== "spedizione") return null;
  const opzione = opzioneDestinazione(logistica, dati.destinazione);
  if (ritiroVenditoreMancante(opzione)) return { motivo: "ritiro_venditore" };
  if (dati.destinazione === "home" && !dati.indirizzoId) return { motivo: "indirizzo_consegna" };
  if (logisticaAddebitata(quantita, dati.deliveryMode, opzione, dati.destinazione) === null) {
    return { motivo: "logistica", mancanti: opzione?.mancanti ?? [] };
  }
  return null;
};

/**
 * Accessori che entrano nel totale, tutti dal preventivo logistico del
 * database (nessuna formula nel client): imballaggio 7c dell'annuncio,
 * logistica addebitata e la copertura della fee di pagamento che generano,
 * la stessa che `order_checkout_reserve` congela sull'ordine. Con la
 * logistica addebitata (più bottiglie al punto di ritiro, o il domicilio)
 * vale la copertura dell'opzione della destinazione scelta; altrimenti (una
 * bottiglia al punto di ritiro, consegna a mano) quella senza logistica. `null` quando un importo
 * non è determinabile: preventivo non letto, spedizione non configurata o
 * copertura assente con accessori a pagamento.
 */
export const accessoriCheckout = (
  quantita: number,
  deliveryMode: OrderDeliveryMode,
  logistica: {
    opzioni: ReadonlyArray<
      Pick<OpzioneLogistica, "destinazione" | "ordinabile" | "totaleCents" | "feePagamentoCents">
    >;
    imballaggioAnnuncioCents: number;
    feePagamentoSenzaLogisticaCents: number | null;
  } | null,
  destinazione: DestinazioneCheckout = "pudo",
): { imballaggioCents: number; logisticaCents: number; feePagamentoCents: number } | null => {
  if (!logistica) return null;
  const opzione = opzioneDestinazione(logistica, destinazione);
  const logisticaCents = logisticaAddebitata(quantita, deliveryMode, opzione, destinazione);
  if (logisticaCents === null) return null;
  const imballaggioCents = logistica.imballaggioAnnuncioCents;
  const conLogistica = logisticaInTotale(quantita, deliveryMode, destinazione);
  const fee = conLogistica ? opzione?.feePagamentoCents : logistica.feePagamentoSenzaLogisticaCents;
  const feePagamentoCents = fee ?? (imballaggioCents + logisticaCents === 0 ? 0 : null);
  if (feePagamentoCents === null) return null;
  return { imballaggioCents, logisticaCents, feePagamentoCents };
};
