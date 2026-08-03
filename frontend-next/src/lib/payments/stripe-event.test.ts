import { describe, expect, it } from "bun:test";
import {
  isStripeAccountEvent,
  isSupportedStripeEvent,
  normalizeStripeAccount,
  normalizeStripeObject,
  STRIPE_ACCOUNT_EVENT_TYPES,
  STRIPE_EVENT_TYPES,
} from "@/lib/payments/stripe-event";

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
