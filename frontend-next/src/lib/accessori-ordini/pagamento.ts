/**
 * Pagamento di una prenotazione Accessori nel browser — VPM-015B5D.
 *
 * Logica pura attorno al Payment Element. Il browser non decide nulla di
 * economico: apre il pagamento con il solo id dell'ordine (servizio B5B
 * `apriPagamentoAccessori`), conferma con Stripe.js e poi RILEGGE l'ordine.
 * Nessun esito di Stripe.js, nessun redirect e nessun `checkout=success` è una
 * prova di pagamento: l'ordine è `pagato` solo quando lo dice il database,
 * cioè dopo il webhook firmato.
 */

import type { OrdineAccessorio } from "@/lib/accessori-ordini/ordine";

export type MotivoNonPagabile =
  | "gate_spento"
  | "chiave_mancante"
  | "non_acquirente"
  | "non_in_attesa"
  | "prenotazione_scaduta";

export const MESSAGGI_NON_PAGABILE: Readonly<Record<MotivoNonPagabile, string>> = {
  gate_spento: "Il pagamento non è ancora attivo.",
  chiave_mancante: "Il pagamento non è disponibile in questo momento.",
  non_acquirente: "",
  non_in_attesa: "",
  prenotazione_scaduta: "La prenotazione è scaduta: i pezzi non sono più tenuti da parte.",
};

/** Una chiave publishable Stripe ha il prefisso `pk_`; una chiave segreta o vuota non è accettata. */
export const chiavePublishableValida = (k: string | null | undefined): k is string =>
  typeof k === "string" && /^pk_(test|live)_[A-Za-z0-9]{8,}$/.test(k);

/**
 * Il pulsante «Paga» compare solo se tutto concorda. È un filtro di interfaccia:
 * i gate autoritativi (`PAYMENTS_ENABLED`, `checkout_attivo`, proprietà
 * dell'ordine, riserva) restano nella Edge Function e nel database.
 */
export function valutaPagabilita(input: {
  ordine: OrdineAccessorio;
  azioniAbilitate: boolean;
  chiavePublishable: string | null | undefined;
  adesso: number;
}): { pagabile: true } | { pagabile: false; motivo: MotivoNonPagabile } {
  const { ordine } = input;
  if (ordine.ruolo !== "acquirente") return { pagabile: false, motivo: "non_acquirente" };
  if (ordine.stato !== "in_attesa_pagamento") return { pagabile: false, motivo: "non_in_attesa" };
  if (Date.parse(ordine.scadeAt) <= input.adesso) return { pagabile: false, motivo: "prenotazione_scaduta" };
  if (!input.azioniAbilitate) return { pagabile: false, motivo: "gate_spento" };
  if (!chiavePublishableValida(input.chiavePublishable)) return { pagabile: false, motivo: "chiave_mancante" };
  return { pagabile: true };
}

/** Stessa chiave per lo stesso ordine: doppio click, refresh e retry riusano l'intento già aperto. */
export const chiaveAperturaPagamento = (ordineId: string): string => `acc-pay-${ordineId}`;

/** Dove Stripe riporta l'utente dopo un'eventuale autenticazione: sempre l'ordine, mai un'origine del client arbitraria. */
export function indirizzoRitorno(origine: string, ordineId: string): string | null {
  let url: URL;
  try {
    url = new URL(origine);
  } catch {
    return null;
  }
  if (url.origin !== origine || (url.protocol !== "https:" && url.hostname !== "localhost")) return null;
  return `${url.origin}/ordini-accessori/${encodeURIComponent(ordineId)}?checkout=ritorno`;
}

export type EsitoConferma =
  | { tipo: "in_verifica" } // Stripe ha accettato o sta elaborando: la parola finale è del webhook
  | { tipo: "errore"; messaggio: string }
  | { tipo: "richiede_azione" };

const MESSAGGIO_GENERICO = "Il pagamento non è andato a buon fine. Riprova o usa un altro metodo.";

type RispostaStripe = {
  error?: { type?: string; message?: string } | undefined;
  paymentIntent?: { status?: string } | undefined;
};

/**
 * Traduce l'esito di `stripe.confirmPayment` in uno stato di interfaccia.
 * `succeeded` NON significa «pagato»: significa «in verifica» finché l'ordine
 * riletto non è `pagato`.
 */
export function esitoDaStripe(r: RispostaStripe): EsitoConferma {
  if (r.error) {
    const t = r.error.type;
    // I messaggi di carta e validazione sono scritti da Stripe per l'utente; gli altri sono generici.
    const messaggio =
      (t === "card_error" || t === "validation_error") && r.error.message ? r.error.message : MESSAGGIO_GENERICO;
    return { tipo: "errore", messaggio };
  }
  const s = r.paymentIntent?.status;
  if (s === "succeeded" || s === "processing") return { tipo: "in_verifica" };
  if (s === "requires_action") return { tipo: "richiede_azione" };
  return { tipo: "errore", messaggio: MESSAGGIO_GENERICO };
}

export type FaseRilettura = "pagato" | "in_attesa" | "chiuso";

/** Che cosa dice l'ordine riletto dal database. L'unica fonte della parola «pagato». */
export const faseDaOrdine = (o: Pick<OrdineAccessorio, "stato">): FaseRilettura =>
  o.stato === "pagato" ? "pagato" : o.stato === "in_attesa_pagamento" ? "in_attesa" : "chiuso";

export const RILETTURA_MS = 3000;
export const RILETTURA_TENTATIVI = 20; // ~60 secondi, poi stato esplicito «ancora in verifica»

export const TESTI_PAGAMENTO = {
  paga: "Paga",
  apertura: "Preparo il pagamento…",
  conferma: "Confermo…",
  confermaPagamento: "Conferma il pagamento",
  inElaborazione: "Pagamento in elaborazione. Non chiudere la pagina: aggiorniamo lo stato appena il pagamento è confermato.",
  inElaborazioneLunga:
    "Il pagamento è ancora in verifica. Puoi lasciare la pagina: lo stato dell'ordine si aggiorna appena Vinea riceve la conferma.",
  confermato: "Pagamento confermato.",
  nonRiuscito: "Pagamento non riuscito",
  aperturaFallita: "Non riesco ad aprire il pagamento. Riprova fra qualche istante.",
  nonSupportato: "Questo metodo di pagamento non è ancora supportato.",
  azioneRichiesta: "Completa l'autenticazione richiesta dalla tua banca per proseguire.",
  ricontrolla: "Ricontrolla lo stato",
  moduloNonCaricato: "Non riesco a caricare il modulo di pagamento. Riprova fra qualche istante.",
  chiusoDuranteVerifica:
    "La prenotazione si è chiusa prima della conferma del pagamento. Se hai pagato, l'importo ti viene rimborsato: lo stato si aggiorna in questa pagina.",
  riservaFino: "I pezzi sono tenuti da parte fino alle",
  sullaCopia:
    "La conferma del pagamento arriva da Vinea, non da questa pagina: finché non è registrata l'ordine resta in attesa.",
} as const;
