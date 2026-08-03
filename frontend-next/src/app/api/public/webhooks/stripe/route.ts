import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { traduciEventoStripe } from "@/lib/payments/payment-state";
import {
  isStripeAccountEvent,
  isSupportedStripeEvent,
  normalizeStripeAccount,
  normalizeStripeObject,
  type StripeAccountEventEnvelope,
  type StripeEventEnvelope,
} from "@/lib/payments/stripe-event";
import { verifyStripeSignature } from "@/lib/payments/stripe-signature";

/** Identificativo del fornitore per la chiave di deduplicazione (provider, event_id). */
const PROVIDER = "stripe";

export const runtime = "nodejs";

const requiredEnv = (name: string): string | null => process.env[name] ?? null;

const hashSubject = async (value: string): Promise<string> => {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
};

export const POST = async (request: Request): Promise<NextResponse> => {
  if (process.env.PAYMENTS_ENABLED !== "true") {
    return NextResponse.json({ error: "Pagamenti non attivi." }, { status: 503 });
  }
  const secret = requiredEnv("STRIPE_WEBHOOK_SECRET");
  const url = requiredEnv("NEXT_PUBLIC_SUPABASE_URL");
  const serviceKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
  const signature = request.headers.get("stripe-signature");
  if (!secret || !url || !serviceKey) {
    return NextResponse.json({ error: "Configurazione server incompleta." }, { status: 503 });
  }

  const payload = await request.text();
  if (!signature || !(await verifyStripeSignature({ payload, header: signature, secret }))) {
    return NextResponse.json({ error: "Firma non valida." }, { status: 400 });
  }

  let event: StripeEventEnvelope;
  try {
    event = JSON.parse(payload) as StripeEventEnvelope;
  } catch {
    return NextResponse.json({ error: "Payload non valido." }, { status: 400 });
  }
  if (!event.id || !event.created || !event.data?.object) {
    return NextResponse.json({ error: "Evento incompleto." }, { status: 400 });
  }
  if (!isSupportedStripeEvent(event.type) && !isStripeAccountEvent(event.type)) {
    return NextResponse.json({ received: true });
  }

  const supabase = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const forwardedFor = request.headers.get("x-forwarded-for")?.split(",", 1)[0]?.trim() ?? "unknown";
  const subject = await hashSubject(forwardedFor);
  const { error: limitError } = await supabase.rpc("rate_limit_consume", {
    p_scope: "stripe-webhook",
    p_subject: `ip-sha256:${subject}`,
    p_limit: Number(process.env.PAYMENTS_WEBHOOK_RATE_LIMIT ?? "600"),
    p_window_seconds: Number(process.env.PAYMENTS_WEBHOOK_RATE_WINDOW_SECONDS ?? "60"),
  });
  if (limitError) return NextResponse.json({ error: "Troppe richieste." }, { status: 429 });

  // Gli eventi di account viaggiano su un'altra RPC e su un'altra tabella di
  // deduplicazione: non hanno un esito di incasso, e farne passare uno per
  // `payment_apply_provider_event` significherebbe inventarne uno.
  //
  // È l'unico punto in cui `charges_enabled` e `payouts_enabled` entrano nel
  // sistema, e da qui — attraverso un trigger — decidono il ruolo
  // `seller_enabled`. Un venditore non se lo può assegnare: deve passare da un
  // evento firmato dal fornitore.
  if (isStripeAccountEvent(event.type)) {
    const account = normalizeStripeAccount(
      event.data.object as StripeAccountEventEnvelope["data"]["object"],
    );
    if (!account.provider_account_id) {
      return NextResponse.json({ error: "Evento account incompleto." }, { status: 400 });
    }
    const { error: accountError } = await supabase.rpc("seller_payout_account_apply_event", {
      p_provider: PROVIDER,
      p_event_id: event.id,
      p_provider_event_type: event.type,
      p_provider_account_id: account.provider_account_id,
      p_charges_enabled: account.charges_enabled,
      p_payouts_enabled: account.payouts_enabled,
      p_details_submitted: account.details_submitted,
      p_requisiti: account.requisiti_pendenti,
      p_disabled_reason: account.disabled_reason,
      p_occurred_at: event.created,
    });
    if (accountError) {
      console.error("[Stripe webhook] applicazione evento account fallita", {
        eventId: event.id,
        eventType: event.type,
        code: accountError.code,
      });
      return NextResponse.json({ error: "Evento non applicato." }, { status: 500 });
    }
    return NextResponse.json({ received: true });
  }

  // Ridondante rispetto al filtro sopra, ma è ciò che restringe `event.type` a
  // `StripeEventType`: senza, il traduttore non sarebbe totale sulla whitelist e
  // aggiungere un evento senza tradurlo compilerebbe.
  if (!isSupportedStripeEvent(event.type)) return NextResponse.json({ received: true });

  // La traduzione dal vocabolario Stripe alla tassonomia interna avviene qui,
  // prima del confine: la RPC riceve un esito e non un nome evento.
  const { error } = await supabase.rpc("payment_apply_provider_event", {
    p_provider: PROVIDER,
    p_event_id: event.id,
    p_outcome: traduciEventoStripe(event.type, event.data.object),
    p_occurred_at: event.created,
    p_object: normalizeStripeObject(event.data.object, event.type),
  });
  if (error) {
    console.error("[Stripe webhook] applicazione evento fallita", {
      eventId: event.id,
      eventType: event.type,
      code: error.code,
    });
    return NextResponse.json({ error: "Evento non applicato." }, { status: 500 });
  }
  return NextResponse.json({ received: true });
};
