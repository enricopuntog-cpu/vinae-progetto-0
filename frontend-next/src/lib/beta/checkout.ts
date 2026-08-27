import { calcolaCommissione } from "@/lib/payments/marketplace-fee";
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

const PARAMETRI_REPO = {
  margineObiettivoBps: 500,
  riferimentoStripePercentualeBps: 150,
  riferimentoStripeFissoCents: 25,
} as const;

export const stimaCheckout = (prezzoEuro: number, imballaggioCodice: string) => {
  const mercato = calcolaCommissione(Math.round(prezzoEuro * 100), PARAMETRI_REPO);
  const imballaggioCents =
    OPZIONI_IMBALLAGGIO_BETA.find((opzione) => opzione.codice === imballaggioCodice)
      ?.prezzoCents ?? 0;

  return {
    prezzoCents: mercato.prezzoVenditoreCents,
    commissioneCents: mercato.commissioneCents,
    imballaggioCents,
    totaleCents: mercato.totaleCents + imballaggioCents,
  };
};
