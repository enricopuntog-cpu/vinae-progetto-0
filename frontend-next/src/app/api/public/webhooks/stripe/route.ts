import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { traduciEventoStripe } from "@/lib/payments/payment-state";
import {
  isSupportedStripeEvent,
  normalizeStripeObject,
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
  if (!isSupportedStripeEvent(event.type)) return NextResponse.json({ received: true });

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
