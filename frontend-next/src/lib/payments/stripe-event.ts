export const STRIPE_EVENT_TYPES = [
  // Sessione ospitata — resta supportata: un fornitore non smette di emettere
  // eventi per gli incassi già aperti solo perché noi abbiamo cambiato modo di
  // aprirli.
  "checkout.session.completed",
  "checkout.session.async_payment_succeeded",
  "checkout.session.async_payment_failed",
  "checkout.session.expired",
  // Payment Element (Fase 7b): l'incasso è un PaymentIntent e questi sono i
  // suoi esiti.
  "payment_intent.succeeded",
  "payment_intent.processing",
  "payment_intent.payment_failed",
  "payment_intent.canceled",
  "charge.refunded",
] as const;

export type StripeEventType = (typeof STRIPE_EVENT_TYPES)[number];

/**
 * Eventi di account, tenuti in un elenco separato perché non sono esiti di
 * incasso: non hanno un `PaymentOutcomeKind` e non passano dalla RPC dei
 * pagamenti. Fonderli in un elenco solo costringerebbe a inventare un esito di
 * incasso che nessuno ha dichiarato.
 */
export const STRIPE_ACCOUNT_EVENT_TYPES = ["account.updated"] as const;

export type StripeAccountEventType = (typeof STRIPE_ACCOUNT_EVENT_TYPES)[number];

/**
 * La transazione di saldo: è lì che vive la fee davvero trattenuta. Nel payload
 * di un webhook arriva quasi sempre come **identificativo**, non espansa — e in
 * quel caso la fee non è nel messaggio e va recuperata dopo. Il tipo ammette
 * entrambe le forme apposta: quella espansa quando c'è, l'identificativo come
 * appiglio quando non c'è.
 */
type StripeBalanceTransaction = { id?: string; fee?: number };

type StripeObject = Record<string, unknown> & {
  id?: string;
  payment_intent?: string | { id?: string };
  payment_status?: string;
  amount_total?: number;
  amount?: number;
  amount_received?: number;
  amount_refunded?: number;
  refunded?: boolean;
  currency?: string;
  balance_transaction?: string | StripeBalanceTransaction;
  latest_charge?: string | { id?: string; balance_transaction?: string | StripeBalanceTransaction };
  metadata?: { order_id?: string };
};

type StripeAccountObject = Record<string, unknown> & {
  id?: string;
  charges_enabled?: boolean;
  payouts_enabled?: boolean;
  details_submitted?: boolean;
  requirements?: { currently_due?: string[]; disabled_reason?: string | null };
};

export type StripeEventEnvelope = {
  id: string;
  type: string;
  created: number;
  data: { object: StripeObject };
};

export type StripeAccountEventEnvelope = {
  id: string;
  type: string;
  created: number;
  data: { object: StripeAccountObject };
};

export const isSupportedStripeEvent = (type: string): type is StripeEventType =>
  (STRIPE_EVENT_TYPES as readonly string[]).includes(type);

export const isStripeAccountEvent = (type: string): type is StripeAccountEventType =>
  (STRIPE_ACCOUNT_EVENT_TYPES as readonly string[]).includes(type);

const isPaymentIntentEvent = (type: StripeEventType): boolean =>
  type.startsWith("payment_intent.");

/** Ciò che si riesce a sapere della fee da un payload, che può essere poco. */
export type RiferimentoSaldo = {
  /** Nulla quando il payload non porta la transazione espansa: non è zero. */
  feeCents: number | null;
  /** L'appiglio per recuperare la fee più tardi. */
  transazioneId: string | null;
};

const leggiTransazione = (
  valore: string | StripeBalanceTransaction | undefined,
): RiferimentoSaldo => {
  if (typeof valore === "string") return { feeCents: null, transazioneId: valore };
  if (!valore || typeof valore !== "object") return { feeCents: null, transazioneId: null };
  // Una fee frazionaria o negativa non è un costo: è un payload da non credere.
  const fee = valore.fee;
  return {
    feeCents: typeof fee === "number" && Number.isInteger(fee) && fee >= 0 ? fee : null,
    transazioneId: typeof valore.id === "string" ? valore.id : null,
  };
};

/**
 * Dove cercare la transazione di saldo, in ordine: sull'oggetto stesso (eventi
 * `charge.*`), poi sulla carica collegata (eventi `payment_intent.*`, dove
 * l'oggetto è l'intento e la fee sta un livello sotto).
 *
 * Se nessuna delle due è espansa si esce con l'identificativo e `feeCents`
 * nullo, che è la verità: la fee non era nel messaggio.
 */
export const riferimentoSaldoDa = (object: StripeObject): RiferimentoSaldo => {
  const diretta = leggiTransazione(object.balance_transaction);
  if (diretta.feeCents !== null) return diretta;
  const carica = object.latest_charge;
  if (carica && typeof carica === "object") {
    const indiretta = leggiTransazione(carica.balance_transaction);
    if (indiretta.feeCents !== null || indiretta.transazioneId !== null) return indiretta;
  }
  return diretta;
};

/**
 * Riduce l'oggetto Stripe ai soli campi che la RPC riverifica, con nomi che non
 * sono di Stripe: è il payload che attraversa il confine verso il database.
 *
 * `payment_status` non passa: era il campo su cui la RPC decideva se l'incasso
 * fosse avvenuto, e quella decisione ora è tradotta in un `PaymentOutcomeKind`
 * da `traduciEventoStripe`. Il database non legge vocabolario Stripe.
 *
 * Sui `payment_intent.*` sessione e incasso sono **lo stesso oggetto**: il
 * PaymentIntent non ha un campo `payment_intent` che punti a sé stesso, quindi
 * l'identificativo va preso da `id` per entrambe le colonne. Senza questo, il
 * rimborso — che si aggancia per `provider_intent_id` — non troverebbe la riga.
 */
export const normalizeStripeObject = (
  object: StripeObject,
  eventType: StripeEventType,
): Record<string, unknown> => {
  const saldo = riferimentoSaldoDa(object);
  return {
    session_id: object.id,
    intent_id: isPaymentIntentEvent(eventType)
      ? object.id
      : typeof object.payment_intent === "string"
        ? object.payment_intent
        : object.payment_intent?.id,
    provider_event_type: eventType,
    amount_cents: object.amount_total ?? object.amount ?? 0,
    amount_refunded: object.amount_refunded ?? 0,
    refunded: object.refunded ?? false,
    currency: object.currency,
    // La fee non decide nulla: attraversa il confine come misura, e la RPC la
    // scrive senza che alcun ramo la legga. Nulla resta nulla.
    fee_reale_cents: saldo.feeCents,
    fee_transazione_id: saldo.transazioneId,
    order_id: object.metadata?.order_id,
  };
};

/** Ciò che la RPC di Connect riverifica. Nessun campo con nome di Stripe. */
export type AccountEventNormalizzato = {
  provider_account_id: string | undefined;
  charges_enabled: boolean;
  payouts_enabled: boolean;
  details_submitted: boolean;
  requisiti_pendenti: string[];
  disabled_reason: string | null;
};

export const normalizeStripeAccount = (
  object: StripeAccountObject,
): AccountEventNormalizzato => ({
  provider_account_id: object.id,
  // I booleani non arrivano mai indefiniti dal confine: un campo assente vale
  // "non abilitato", che è l'assunzione prudente quando si parla di denaro.
  charges_enabled: object.charges_enabled === true,
  payouts_enabled: object.payouts_enabled === true,
  details_submitted: object.details_submitted === true,
  requisiti_pendenti: object.requirements?.currently_due ?? [],
  disabled_reason: object.requirements?.disabled_reason ?? null,
});
