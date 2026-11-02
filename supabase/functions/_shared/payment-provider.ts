// Contratto agnostico verso il fornitore di incasso, per il runtime Deno delle
// Edge Function. Rispecchia `PaymentProvider` in
// frontend-next/src/services/types.ts: i due file vivono in progetti e runtime
// diversi e non possono importarsi a vicenda, quindi vanno cambiati insieme.
//
// Nessun modulo, tipo o stringa di un fornitore specifico entra in questo file.
// L'unico posto in cui il nome di un fornitore può comparire è un adapter sotto
// `<function>/providers/`.

export type Result<T, E = string> = { ok: true; data: T } | { ok: false; error: E };

/** Riferimento opaco a una transazione presso il fornitore. */
export type ProviderPaymentRef = {
  provider: string;
  sessionId: string;
  intentId?: string | null;
};

/**
 * Tutto risolto server-side: nessun campo arriva dal client.
 * Gli identificativi sono di dominio Vinea, non del fornitore: sta all'adapter
 * decidere come trasportarli nel proprio formato.
 */
export type CheckoutRequest = {
  orderId: string;
  buyerId: string;
  listingId: string;
  descrizione: string;
  amountCents: number;
  currency: string;
  successUrl: string;
  cancelUrl: string;
  idempotencyKey: string;
  expiresAt: string | null;
  /**
   * Dominio Vinea che possiede l'incasso. Assente = vino (comportamento
   * storico). Viaggia presso il fornitore come marcatore, cosi il webhook firmato
   * instrada l'evento al dominio giusto; la decisione resta del database.
   */
  dominio?: "accessori";
};

/**
 * Ciò che serve al browser per montare un unico componente di pagamento.
 *
 * `clientSecret` non è un URL di redirect: dalla Fase 7b l'incasso avviene in
 * pagina con un Payment Element, e i metodi disponibili (carta, wallet, PayPal,
 * Satispay) sono una configurazione dell'account presso il fornitore, non
 * flussi separati da costruire qui.
 *
 * `redirectUrl` resta perché un fornitore può non avere un componente in pagina
 * e offrire solo una pagina ospitata: chi lo implementa valorizza quello e
 * lascia `clientSecret` nullo.
 */
export type CheckoutHandle = {
  ref: ProviderPaymentRef;
  clientSecret: string | null;
  redirectUrl: string | null;
};

/** Tassonomia interna degli esiti: rispecchia l'enum `public.payment_outcome`. */
export type PaymentOutcomeKind =
  | "pending"
  | "authorized"
  | "settled"
  | "failed"
  | "expired"
  | "refunded";

export type PaymentOutcome =
  | { kind: "pending" }
  | { kind: "authorized" }
  | { kind: "settled"; amountCents: number; currency: string; settledAt: string }
  | { kind: "failed"; reason: string }
  | { kind: "expired" }
  | { kind: "refunded"; refundedCents: number; fully: boolean };

export type ProviderEvent = {
  id: string;
  occurredAt: string;
  ref: ProviderPaymentRef;
  outcome: PaymentOutcome;
  declaredAmountCents: number;
  declaredCurrency: string;
  orderRef: string | null;
};

export interface PaymentProvider {
  readonly id: string;
  apriCheckout(input: CheckoutRequest): Promise<Result<CheckoutHandle>>;
  /**
   * Riottiene un incasso già aperto. Serve al ritentativo idempotente: la
   * prenotazione conserva l'identificativo della transazione ma non può
   * conservare `clientSecret`, che è un segreto e non un dato di dominio.
   */
  riprendiCheckout(ref: ProviderPaymentRef): Promise<Result<CheckoutHandle>>;
  statoPagamento(ref: ProviderPaymentRef): Promise<Result<PaymentOutcome>>;
  interpretaEvento(input: {
    rawBody: string;
    headers: Headers;
    secret: string;
  }): Promise<Result<ProviderEvent>>;
}

/**
 * Esito dell'annullo di un incasso aperto ma mai collegato a un ordine pagabile
 * (VPM-015QA-FINAL-B1). Sei esiti distinti, perché solo i primi due provano che
 * l'incasso non è più possibile:
 *
 *  - `annullato`: il fornitore ha confermato la cancellazione;
 *  - `gia_annullato`: era già cancellato (idempotente, verificato rileggendolo);
 *  - `incassato`: l'incasso era già riuscito, NON è una cancellazione: importo,
 *    valuta e ordine dichiarati dal fornitore servono al database per riverificare;
 *  - `in_elaborazione`: il fornitore non lo cancella (metodo asincrono in corso);
 *  - `sconosciuto`: rete, timeout, risposta ambigua. Non prova nulla: va riconciliato.
 */
export type AnnulloEsito =
  | { kind: "annullato" }
  | { kind: "gia_annullato" }
  | { kind: "incassato"; amountCents: number; currency: string; orderRef: string | null }
  | { kind: "in_elaborazione" }
  | { kind: "sconosciuto"; error: string };

export interface CancelProvider {
  readonly id: string;
  /** Il riferimento viene sempre dalla risposta del fornitore alla creazione, mai dal browser. */
  annullaCheckout(ref: ProviderPaymentRef): Promise<AnnulloEsito>;
}

/**
 * La fetta che serve all'apertura del checkout. La Edge Function `payments-checkout`
 * dipende da questa e non dall'interfaccia intera: gli altri metodi vivono nel
 * runtime del webhook, che è un processo diverso. Restringere qui evita di
 * pretendere da un adapter di checkout codice che non gli compete.
 */
export type CheckoutProvider = Pick<PaymentProvider, "id" | "apriCheckout" | "riprendiCheckout"> &
  Pick<CancelProvider, "annullaCheckout">;

// ---- Account di incasso del venditore --------------------------------------
//
// Nella trattenuta fondi il venditore non è più solo il proprietario di una
// riga: è un destinatario di denaro presso il fornitore, con un'identità
// verificata da quello e non da noi. Questo blocco è il contratto di quella
// identità, e come tutto il resto del file non nomina nessun fornitore.

/** Riferimento opaco all'account del venditore presso il fornitore. */
export type ConnectAccountRef = {
  provider: string;
  accountId: string;
};

/**
 * Stato dichiarato dal fornitore. Sono affermazioni sue, non nostre: entrano
 * nel database solo attraverso un evento firmato, mai da una risposta a una
 * richiesta del venditore.
 */
export type ConnectAccountState = {
  chargesEnabled: boolean;
  payoutsEnabled: boolean;
  detailsSubmitted: boolean;
  requisitiPendenti: string[];
  disabledReason: string | null;
};

/** Link di onboarding ospitato dal fornitore. Ha una scadenza breve. */
export type ConnectOnboardingLink = {
  url: string;
  expiresAt: string | null;
};

export interface ConnectProvider {
  readonly id: string;
  /** Apre l'account del venditore. Gli URL di ritorno sono dominio Vinea. */
  creaAccount(input: {
    sellerId: string;
    email: string | null;
    paese: string;
  }): Promise<Result<ConnectAccountRef>>;
  creaLinkOnboarding(input: {
    accountId: string;
    refreshUrl: string;
    returnUrl: string;
  }): Promise<Result<ConnectOnboardingLink>>;
  statoAccount(accountId: string): Promise<Result<ConnectAccountState>>;
}

/**
 * Creazione del trasferimento verso il venditore, separata dall'incasso.
 *
 * È l'altra metà di "separate charges and transfers": l'addebito non porta
 * alcuna istruzione di trasferimento, quindi i fondi restano sul balance della
 * piattaforma, e questo metodo è l'unico che li muove. L'importo è il prezzo del
 * venditore — la commissione resta alla piattaforma per il fatto stesso di non
 * comparire qui.
 */
export type TransferRequest = {
  orderId: string;
  destinationAccountId: string;
  amountCents: number;
  currency: string;
  idempotencyKey: string;
};

export interface TransferProvider {
  readonly id: string;
  creaTransfer(input: TransferRequest): Promise<Result<{ transferId: string }>>;
}

/**
 * Rimborso di un incasso (VPM-015B5C). Un rimborso è un'uscita di denaro dalla
 * piattaforma verso l'acquirente: l'importo e la chiave di idempotenza arrivano
 * dal database (mai dal browser), la chiave è stabile per richiesta, e la
 * risposta "accettato" NON è un rimborso eseguito: l'esecuzione la conferma
 * soltanto l'evento firmato `charge.refunded`.
 */
export type RefundRequest = {
  paymentIntentId: string;
  amountCents: number;
  currency: string;
  idempotencyKey: string;
  refundRef: string;
};

export interface RefundProvider {
  readonly id: string;
  creaRimborso(input: RefundRequest): Promise<Result<{ refundId: string }>>;
}
