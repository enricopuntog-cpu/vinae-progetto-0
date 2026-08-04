import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  isStripeAccountEvent,
  isSupportedStripeEvent,
  normalizeStripeAccount,
  normalizeStripeObject,
  STRIPE_ACCOUNT_EVENT_TYPES,
  STRIPE_EVENT_TYPES,
} from "@/lib/payments/stripe-event";

const MIGRAZIONE = readFileSync(
  join(
    import.meta.dir,
    "../../../../supabase/migrations/20260803150000_phase_7b_stripe_connect_marketplace.sql",
  ),
  "utf8",
);

describe("eventi Stripe", () => {
  it("accetta soltanto gli eventi gestiti", () => {
    expect(isSupportedStripeEvent("checkout.session.completed")).toBeTrue();
    expect(isSupportedStripeEvent("customer.created")).toBeFalse();
  });

  it("tiene gli eventi di account fuori da quelli di incasso", () => {
    // Un `account.updated` non ha un esito di incasso: se finisse nella stessa
    // whitelist, la traduzione dovrebbe inventarne uno.
    for (const tipo of STRIPE_ACCOUNT_EVENT_TYPES) {
      expect(isStripeAccountEvent(tipo)).toBeTrue();
      expect(isSupportedStripeEvent(tipo)).toBeFalse();
    }
    expect(isStripeAccountEvent("checkout.session.completed")).toBeFalse();
  });

  it("riduce una sessione ai soli campi necessari, con nomi non di Stripe", () => {
    expect(
      normalizeStripeObject(
        {
          id: "cs_test_1",
          payment_intent: "pi_test_1",
          payment_status: "paid",
          amount_total: 4200,
          currency: "eur",
          metadata: { order_id: "11111111-1111-4111-8111-111111111111" },
          ignored: "not-persisted",
        },
        "checkout.session.completed",
      ),
    ).toEqual({
      session_id: "cs_test_1",
      intent_id: "pi_test_1",
      provider_event_type: "checkout.session.completed",
      amount_cents: 4200,
      amount_refunded: 0,
      refunded: false,
      currency: "eur",
      // Una sessione ospitata non porta la transazione di saldo: nulla, non zero.
      fee_reale_cents: null,
      fee_transazione_id: null,
      order_id: "11111111-1111-4111-8111-111111111111",
    });
  });

  it("non fa passare payment_status oltre il confine", () => {
    // La decisione che quel campo guidava vive ora in traduciEventoStripe.
    const normalizzato = normalizeStripeObject(
      { id: "cs_test_2", payment_status: "unpaid" },
      "checkout.session.completed",
    );
    expect(normalizzato).not.toHaveProperty("payment_status");
  });

  it("su un PaymentIntent prende l'identificativo da id per entrambe le colonne", () => {
    // Il PaymentIntent non ha un campo che punti a sé stesso: senza questo,
    // `provider_intent_id` resterebbe nullo e il rimborso — che si aggancia
    // proprio a quella colonna — non troverebbe la riga.
    const normalizzato = normalizeStripeObject(
      { id: "pi_test_3", amount: 10500, currency: "eur", metadata: { order_id: "ord-1" } },
      "payment_intent.succeeded",
    );
    expect(normalizzato.session_id).toBe("pi_test_3");
    expect(normalizzato.intent_id).toBe("pi_test_3");
    expect(normalizzato.amount_cents).toBe(10500);
  });

  it("su un rimborso continua a prendere l'incasso da payment_intent", () => {
    const daOggetto = normalizeStripeObject(
      { id: "ch_test_1", payment_intent: { id: "pi_test_4" }, amount: 10500, amount_refunded: 500 },
      "charge.refunded",
    );
    expect(daOggetto.intent_id).toBe("pi_test_4");
    expect(daOggetto.amount_refunded).toBe(500);
    expect(daOggetto.refunded).toBeFalse();
  });

  it("porta sempre il tipo evento, che la RPC conserva a fini forensi", () => {
    for (const tipo of STRIPE_EVENT_TYPES) {
      expect(normalizeStripeObject({ id: "x_1" }, tipo).provider_event_type).toBe(tipo);
    }
  });
});

describe("normalizzazione dell'oggetto account", () => {
  it("legge lo stato dichiarato e i requisiti pendenti", () => {
    expect(
      normalizeStripeAccount({
        id: "acct_test_1",
        charges_enabled: true,
        payouts_enabled: true,
        details_submitted: true,
        requirements: { currently_due: [], disabled_reason: null },
      }),
    ).toEqual({
      provider_account_id: "acct_test_1",
      charges_enabled: true,
      payouts_enabled: true,
      details_submitted: true,
      requisiti_pendenti: [],
      disabled_reason: null,
    });
  });

  it("tratta un campo assente come non abilitato", () => {
    // Prudenza asimmetrica: se il payload è incompleto, l'errore da evitare è
    // abilitare un venditore che il fornitore non ha abilitato.
    const normalizzato = normalizeStripeAccount({ id: "acct_test_2" });
    expect(normalizzato.charges_enabled).toBeFalse();
    expect(normalizzato.payouts_enabled).toBeFalse();
    expect(normalizzato.details_submitted).toBeFalse();
    expect(normalizzato.requisiti_pendenti).toEqual([]);
    expect(normalizzato.disabled_reason).toBeNull();
  });

  it("non si lascia abilitare da un valore vero ma non booleano", () => {
    const normalizzato = normalizeStripeAccount({
      id: "acct_test_3",
      charges_enabled: "true" as unknown as boolean,
    });
    expect(normalizzato.charges_enabled).toBeFalse();
  });
});

// La fee reale è l'unico numero del sistema che non possiamo calcolare: la
// decide il fornitore in base al metodo che ha usato il compratore. Questi casi
// riguardano solo il *leggerla*, mai il deciderci qualcosa sopra.
describe("fee reale letta dall'evento", () => {
  it("legge la fee quando la transazione di saldo è espansa sulla carica", () => {
    // Fixture di una carica riuscita a 106,86 € pagata con carta SEE: la fee
    // trattenuta è 1,85 €. È il caso in cui il payload basta a sé stesso.
    const normalizzato = normalizeStripeObject(
      {
        id: "ch_test_1",
        payment_intent: "pi_test_1",
        amount: 10686,
        currency: "eur",
        balance_transaction: { id: "txn_test_1", fee: 185 },
        metadata: { order_id: "11111111-1111-4111-8111-111111111111" },
      },
      "charge.refunded",
    );
    expect(normalizzato.fee_reale_cents).toBe(185);
    expect(normalizzato.fee_transazione_id).toBe("txn_test_1");
    // E non ha disturbato nulla di ciò che la RPC riverificava già prima.
    expect(normalizzato.intent_id).toBe("pi_test_1");
    expect(normalizzato.amount_cents).toBe(10686);
  });

  it("scende sulla carica collegata quando l'oggetto è un PaymentIntent", () => {
    // Su `payment_intent.*` la fee sta un livello sotto: l'intento non ce l'ha.
    const normalizzato = normalizeStripeObject(
      {
        id: "pi_test_2",
        amount: 5356,
        currency: "eur",
        latest_charge: {
          id: "ch_test_2",
          balance_transaction: { id: "txn_test_2", fee: 305 },
        },
      },
      "payment_intent.succeeded",
    );
    expect(normalizzato.fee_reale_cents).toBe(305);
    expect(normalizzato.fee_transazione_id).toBe("txn_test_2");
    expect(normalizzato.session_id).toBe("pi_test_2");
    expect(normalizzato.intent_id).toBe("pi_test_2");
  });

  it("conserva l'identificativo quando la transazione non è espansa", () => {
    // Il caso normale di un webhook: arriva la stringa e basta. La fee resta
    // nulla — "non misurata" — e l'identificativo è l'appiglio per recuperarla.
    const normalizzato = normalizeStripeObject(
      { id: "ch_test_3", amount: 1092, currency: "eur", balance_transaction: "txn_test_3" },
      "charge.refunded",
    );
    expect(normalizzato.fee_reale_cents).toBeNull();
    expect(normalizzato.fee_transazione_id).toBe("txn_test_3");
  });

  it("non inventa uno zero quando la transazione manca del tutto", () => {
    const normalizzato = normalizeStripeObject(
      { id: "cs_test_4", amount_total: 10686, currency: "eur" },
      "checkout.session.completed",
    );
    expect(normalizzato.fee_reale_cents).toBeNull();
    expect(normalizzato.fee_transazione_id).toBeNull();
  });

  it("respinge una fee negativa o frazionaria senza perdere l'identificativo", () => {
    // Una fee così non è un costo: è un payload da non credere. Ma la
    // transazione resta nota, quindi il valore giusto si può ancora recuperare.
    for (const fee of [-1, 12.5, Number.NaN]) {
      const normalizzato = normalizeStripeObject(
        { id: "ch_test_5", balance_transaction: { id: "txn_test_5", fee } },
        "charge.refunded",
      );
      expect(normalizzato.fee_reale_cents).toBeNull();
      expect(normalizzato.fee_transazione_id).toBe("txn_test_5");
    }
  });

  it("la RPC scrive la fee e nessun ramo la legge", () => {
    const struttura = MIGRAZIONE.replace(/--[^\n]*/g, "");
    // Il campo attraversa il confine con il nome che gli dà il normalizzatore.
    expect(struttura).toContain("nullif(p_object ->> 'fee_reale_cents', '')::integer");
    expect(struttura).toContain("fee_stripe_reale_cents = v_fee_reale");
    // La colonna esiste, è nullable e ammette solo valori non negativi.
    expect(struttura).toContain(
      "check (fee_stripe_reale_cents is null or fee_stripe_reale_cents >= 0)",
    );
    // E il rilascio fondi non la nomina: se comparisse in payout_prepara,
    // una misura sarebbe diventata una decisione.
    const prepara = struttura.slice(struttura.indexOf("function public.payout_prepara"));
    expect(prepara).not.toContain("fee_stripe_reale_cents");
  });
});
