import type { PreventivoEconomico } from "@/services/preventivo-service";
import type { OpzioneLogistica } from "@/services/logistica-service";
import type { OrderDeliveryMode, PackagingOption } from "@/services/types";

export type CheckoutPasso = "contatti" | "consegna" | "imballaggio" | "pagamento";
export type MetodoPagamentoBeta = "carta" | "wallet";

export type DatiCheckoutBeta = {
  email: string;
  telefono: string;
  destinatario: string;
  via: string;
  cap: string;
  citta: string;
  provincia: string;
  deliveryMode: OrderDeliveryMode;
  imballaggioCodice: string;
  metodoPagamento: MetodoPagamentoBeta;
};

export type ErroriCheckout = Partial<Record<keyof DatiCheckoutBeta, string>>;

export const creaDatiCheckout = (email = ""): DatiCheckoutBeta => ({
  email,
  telefono: "",
  destinatario: "",
  via: "",
  cap: "",
  citta: "",
  provincia: "",
  deliveryMode: "spedizione",
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

const obbligatorio = (valore: string): boolean => valore.trim().length > 0;

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

  if (passo === "consegna" && dati.deliveryMode === "spedizione") {
    return {
      ...(!obbligatorio(dati.destinatario) ? { destinatario: "Campo obbligatorio." } : {}),
      ...(!obbligatorio(dati.via) ? { via: "Campo obbligatorio." } : {}),
      ...(!/^\d{5}$/.test(dati.cap) ? { cap: "Il CAP deve avere 5 cifre." } : {}),
      ...(!obbligatorio(dati.citta) ? { citta: "Campo obbligatorio." } : {}),
      ...(!/^[A-Za-z]{2}$/.test(dati.provincia)
        ? { provincia: "Usa la sigla di 2 lettere." }
        : {}),
    };
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

/**
 * VP-E: quanto della logistica entra nel totale. Solo per più bottiglie
 * spedite e solo se il punto di ritiro è ordinabile; altrimenti zero (una
 * bottiglia, consegna a mano) o `null` (spedizione non configurata: il
 * checkout non si conferma).
 */
export const logisticaAddebitata = (
  quantita: number,
  deliveryMode: OrderDeliveryMode,
  opzionePudo: { ordinabile: boolean; totaleCents: number | null } | null,
): number | null => {
  if (quantita <= 1 || deliveryMode !== "spedizione") return 0;
  if (!opzionePudo || !opzionePudo.ordinabile || opzionePudo.totaleCents === null) return null;
  return opzionePudo.totaleCents;
};

/**
 * Accessori che entrano nel totale, tutti dal preventivo logistico del
 * database (nessuna formula nel client): imballaggio 7c dell'annuncio,
 * logistica addebitata e la copertura della fee di pagamento che generano,
 * la stessa che `order_checkout_reserve` congela sull'ordine. Con più
 * bottiglie spedite vale la copertura del punto di ritiro; altrimenti (una
 * bottiglia, consegna a mano) quella senza logistica. `null` quando un importo
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
): { imballaggioCents: number; logisticaCents: number; feePagamentoCents: number } | null => {
  if (!logistica) return null;
  const pudo = logistica.opzioni.find((o) => o.destinazione === "pudo") ?? null;
  const logisticaCents = logisticaAddebitata(quantita, deliveryMode, pudo);
  if (logisticaCents === null) return null;
  const imballaggioCents = logistica.imballaggioAnnuncioCents;
  const conLogistica = quantita > 1 && deliveryMode === "spedizione";
  const fee = conLogistica ? pudo?.feePagamentoCents : logistica.feePagamentoSenzaLogisticaCents;
  const feePagamentoCents = fee ?? (imballaggioCents + logisticaCents === 0 ? 0 : null);
  if (feePagamentoCents === null) return null;
  return { imballaggioCents, logisticaCents, feePagamentoCents };
};
