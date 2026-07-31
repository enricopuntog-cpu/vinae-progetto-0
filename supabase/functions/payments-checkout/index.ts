import { createClient } from "@supabase/supabase-js";
import { corsHeadersFor } from "../_shared/cors.ts";

type CheckoutInput = {
  listingId?: string;
  proposalId?: string | null;
  deliveryMode?: "consegna_mano" | "spedizione";
};

type Reservation = {
  order_id: string;
  amount_cents: number;
  currency: string;
  wine_name?: string;
  checkout_url?: string | null;
  stripe_session_id?: string | null;
  order_status?: string;
  payment_status?: string;
};

const json = (body: unknown, status: number, headers: HeadersInit = {}): Response =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...headers },
  });

const env = (name: string): string => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Configurazione server mancante: ${name}`);
  return value;
};

const createStripeSession = async ({
  reservation,
  buyerId,
  listingId,
  idempotencyKey,
}: {
  reservation: Reservation;
  buyerId: string;
  listingId: string;
  idempotencyKey: string;
}): Promise<{ id: string; url: string }> => {
  const redirectOrigin = env("PAYMENT_REDIRECT_ORIGIN").replace(/\/$/, "");
  const allowed = new Set(
    env("PAYMENT_REDIRECT_ALLOWED_ORIGINS").split(",").map((origin) => origin.trim()),
  );
  if (!allowed.has(redirectOrigin)) throw new Error("Origine di ritorno non consentita.");

  const form = new URLSearchParams({
    mode: "payment",
    client_reference_id: reservation.order_id,
    "line_items[0][quantity]": "1",
    "line_items[0][price_data][currency]": reservation.currency,
    "line_items[0][price_data][unit_amount]": String(reservation.amount_cents),
    "line_items[0][price_data][product_data][name]": reservation.wine_name ?? "Ordine Vinea",
    "metadata[order_id]": reservation.order_id,
    "metadata[buyer_id]": buyerId,
    "metadata[listing_id]": listingId,
    success_url: `${redirectOrigin}/ordini/${reservation.order_id}?checkout=success`,
    cancel_url: `${redirectOrigin}/annuncio/${listingId}?checkout=cancelled`,
  });
  const response = await fetch("https://api.stripe.com/v1/checkout/sessions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env("STRIPE_SECRET_KEY")}`,
      "Content-Type": "application/x-www-form-urlencoded",
      "Idempotency-Key": idempotencyKey,
    },
    body: form,
  });
  const result = (await response.json()) as { id?: string; url?: string; error?: { type?: string } };
  if (!response.ok || !result.id || !result.url) {
    throw new Error(`Creazione sessione Stripe fallita (${result.error?.type ?? response.status}).`);
  }
  return { id: result.id, url: result.url };
};

Deno.serve(async (request) => {
  const corsHeaders = corsHeadersFor(request);
  if (!corsHeaders) return json({ error: "Origine non consentita." }, 403);
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Metodo non consentito." }, 405, corsHeaders);
  if (Deno.env.get("PAYMENTS_ENABLED") !== "true") {
    return json({ error: "Pagamenti non attivi." }, 503, corsHeaders);
  }

  const authorization = request.headers.get("authorization") ?? "";
  const accessToken = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  const idempotencyKey = request.headers.get("x-idempotency-key") ?? "";
  if (!accessToken || !/^[A-Za-z0-9._:-]{8,128}$/.test(idempotencyKey)) {
    return json({ error: "Autenticazione o chiave idempotenza non valida." }, 401, corsHeaders);
  }

  const supabase = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await supabase.auth.getUser(accessToken);
  if (authError || !authData.user) return json({ error: "Sessione non valida." }, 401, corsHeaders);

  let input: CheckoutInput;
  try {
    input = (await request.json()) as CheckoutInput;
  } catch {
    return json({ error: "Corpo richiesta non valido." }, 400, corsHeaders);
  }
  if (!input.listingId || !["consegna_mano", "spedizione"].includes(input.deliveryMode ?? "")) {
    return json({ error: "Dati checkout non validi." }, 400, corsHeaders);
  }

  const { data, error } = await supabase.rpc("order_checkout_reserve", {
    p_buyer_id: authData.user.id,
    p_listing_id: input.listingId,
    p_proposal_id: input.proposalId ?? null,
    p_delivery_mode: input.deliveryMode,
    p_idempotency_key: idempotencyKey,
  });
  if (error) {
    const readable = new Set(["P0001", "42501", "23505", "22023", "PGRST"]);
    return json(
      { error: readable.has(error.code ?? "") ? error.message : "Checkout non disponibile." },
      error.code === "PGRST" ? 429 : 409,
      corsHeaders,
    );
  }
  const reservation = data as Reservation;
  if (reservation.checkout_url) return json({ checkoutUrl: reservation.checkout_url }, 200, corsHeaders);
  if (reservation.order_status === "annullato" || reservation.payment_status === "failed") {
    return json({ error: "Checkout precedente chiuso; usa una nuova chiave idempotenza." }, 409, corsHeaders);
  }

  let session: { id: string; url: string };
  try {
    session = await createStripeSession({
      reservation,
      buyerId: authData.user.id,
      listingId: input.listingId,
      idempotencyKey,
    });
  } catch {
    await supabase.rpc("order_checkout_release", {
      p_order_id: reservation.order_id,
      p_buyer_id: authData.user.id,
    });
    return json({ error: "Checkout temporaneamente non disponibile." }, 502, corsHeaders);
  }

  const { error: attachError } = await supabase.rpc("payment_checkout_attach", {
    p_order_id: reservation.order_id,
    p_buyer_id: authData.user.id,
    p_stripe_session_id: session.id,
    p_checkout_url: session.url,
  });
  if (attachError) {
    return json({ error: "Checkout creato ma non ancora collegato; riprova." }, 502, corsHeaders);
  }
  return json({ checkoutUrl: session.url }, 201, corsHeaders);
});
