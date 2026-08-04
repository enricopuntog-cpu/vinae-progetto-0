import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { traduciEventoStripe } from "@/lib/payments/payment-state";
import { STRIPE_EVENT_TYPES } from "@/lib/payments/stripe-event";
import type { PaymentOutcomeKind } from "@/services/types";

// La tassonomia interna, riscritta a mano qui apposta: un tipo TypeScript non
// esiste a runtime, quindi l'elenco duplicato è il prezzo per poterlo
// confrontare con l'enum SQL. Se qualcuno cambia PaymentOutcomeKind senza
// toccare la migrazione, il confronto più sotto fallisce.
const TASSONOMIA: readonly PaymentOutcomeKind[] = [
  "pending",
  "authorized",
  "settled",
  "failed",
  "expired",
  "refunded",
];

const MIGRAZIONE = readFileSync(
  join(
    import.meta.dir,
    "../../../../supabase/migrations/20260731135455_phase_7_order_payment_service.sql",
  ),
  "utf8",
);

describe("traduzione degli eventi Stripe", () => {
  it("traduce ogni evento della whitelist", () => {
    expect(traduciEventoStripe("checkout.session.completed", { payment_status: "paid" })).toBe(
      "settled",
    );
    expect(traduciEventoStripe("checkout.session.async_payment_succeeded", {})).toBe("settled");
    expect(traduciEventoStripe("checkout.session.async_payment_failed", {})).toBe("failed");
    expect(traduciEventoStripe("checkout.session.expired", {})).toBe("expired");
    expect(traduciEventoStripe("charge.refunded", {})).toBe("refunded");
  });

  it("traduce gli esiti del Payment Element", () => {
    // Un PaymentIntent `succeeded` non si biforca: è già un incasso avvenuto.
    // `processing` invece è il caso dei metodi che rimandano l'incasso —
    // PayPal, Satispay, addebiti bancari — e non vale come pagato.
    expect(traduciEventoStripe("payment_intent.succeeded", {})).toBe("settled");
    expect(traduciEventoStripe("payment_intent.succeeded", { payment_status: "unpaid" })).toBe(
      "settled",
    );
    expect(traduciEventoStripe("payment_intent.processing", {})).toBe("authorized");
    expect(traduciEventoStripe("payment_intent.payment_failed", {})).toBe("failed");
    expect(traduciEventoStripe("payment_intent.canceled", {})).toBe("expired");
  });

  it("non tratta come incassata una sessione conclusa ma non pagata", () => {
    // È il caso su cui la vecchia copia TypeScript divergeva dalla RPC.
    for (const stato of ["unpaid", "no_payment_required", undefined]) {
      expect(traduciEventoStripe("checkout.session.completed", { payment_status: stato })).toBe(
        "authorized",
      );
    }
  });

  it("copre la whitelist per intero, senza esiti fuori tassonomia", () => {
    const prodotti = STRIPE_EVENT_TYPES.map((tipo) =>
      traduciEventoStripe(tipo, { payment_status: "paid" }),
    );
    expect(prodotti).toHaveLength(STRIPE_EVENT_TYPES.length);
    for (const esito of prodotti) expect(TASSONOMIA).toContain(esito);
  });
});

// Questi casi non eseguono il SQL — nessun Postgres è disponibile in postazione
// — ma leggono il file di migrazione vero. Falliscono se le due implementazioni
// tornano a divergere, che è il modo in cui il bug precedente era passato
// inosservato.
describe("accordo fra tassonomia TypeScript e schema SQL", () => {
  it("l'enum public.payment_outcome elenca esattamente la tassonomia", () => {
    const blocco = MIGRAZIONE.match(/create type public\.payment_outcome as enum \(([^)]*)\)/);
    expect(blocco).not.toBeNull();
    const valoriSql = [...blocco![1].matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
    expect(valoriSql.sort()).toEqual([...TASSONOMIA].sort());
  });

  it("ogni esito prodotto dal traduttore ha un ramo nella RPC", () => {
    const prodotti = new Set(
      STRIPE_EVENT_TYPES.flatMap((tipo) => [
        traduciEventoStripe(tipo, { payment_status: "paid" }),
        traduciEventoStripe(tipo, {}),
      ]),
    );
    for (const esito of prodotti) {
      expect(MIGRAZIONE).toContain(`p_outcome = '${esito}'`);
    }
  });

  it("il ramo 'authorized' non tocca un pagamento già chiuso", () => {
    // La guardia SQL è ciò che rende inoffensivo un `completed` non pagato che
    // arrivi su un pagamento `expired`: fuori da questi due stati non cambia
    // nulla. È l'altra metà del bug trovato.
    const ramo = MIGRAZIONE.match(
      /elsif p_outcome = 'authorized'\s*\n\s*and v_payment\.stato in \(([^)]*)\)/,
    );
    expect(ramo).not.toBeNull();
    const statiAmmessi = [...ramo![1].matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
    expect(statiAmmessi).toEqual(["checkout_pending", "processing"]);
    expect(statiAmmessi).not.toContain("expired");
  });

  it("la RPC non ramifica più su nomi evento del fornitore", () => {
    const corpo = MIGRAZIONE.slice(
      MIGRAZIONE.indexOf("function public.payment_apply_provider_event"),
    );
    expect(corpo.length).toBeGreaterThan(0);
    for (const tipo of STRIPE_EVENT_TYPES) {
      expect(corpo).not.toContain(`'${tipo}'`);
    }
    expect(corpo.toLowerCase()).not.toContain("stripe");
  });
});
