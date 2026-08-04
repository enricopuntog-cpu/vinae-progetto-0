// Orchestrazione del checkout: autenticazione, validazione del corpo,
// prenotazione atomica, apertura della sessione presso il fornitore,
// compensazione in caso di errore.
//
// Questo file non conosce nessun fornitore. Parla solo con `CheckoutProvider`
// (../_shared/payment-provider.ts). L'unico punto in cui compare un nome di
// fornitore è la riga di import dell'adapter, qui sotto, e la lettura del suo
// segreto: sostituirlo è cambiare quelle righe, non riscrivere il flusso.
//
// Dalla Fase 7b l'importo aperto presso il fornitore è il **totale** — prezzo
// del venditore più commissione — e non il prezzo del venditore. La
// scomposizione è già congelata sull'ordine dalla RPC di prenotazione: questa
// function la trasporta e non la ricalcola. L'incasso non porta istruzioni di
// trasferimento, quindi i fondi restano sul balance della piattaforma finché
// `payouts-release` non crea il Transfer.

import { createClient } from "@supabase/supabase-js";
import { corsHeadersFor } from "../_shared/cors.ts";
import type { CheckoutProvider } from "../_shared/payment-provider.ts";
import { creaStripeProvider } from "./providers/stripe.ts";

type CheckoutInput = {
  listingId?: string;
  proposalId?: string | null;
  deliveryMode?: "consegna_mano" | "spedizione";
};

type Reservation = {
  order_id: string;
  /** Quanto paga il compratore: prezzo del venditore più commissione. */
  amount_cents: number;
  prezzo_venditore_cents?: number;
  commissione_cents?: number;
  margine_obiettivo_bps?: number;
  riferimento_stripe_percentuale_bps?: number;
  riferimento_stripe_fisso_cents?: number;
  currency: string;
  wine_name?: string;
  checkout_url?: string | null;
  provider?: string | null;
  provider_session_id?: string | null;
  reservation_expires_at?: string | null;
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

/**
 * Gli URL di ritorno sono dominio Vinea, non del fornitore: l'origine e la sua
 * allowlist si risolvono qui, così l'adapter non ha modo di scegliere dove
 * rimandare l'utente.
 */
const risolviOrigineRitorno = (): string => {
  const origin = env("PAYMENT_REDIRECT_ORIGIN").replace(/\/$/, "");
  const allowed = new Set(
    env("PAYMENT_REDIRECT_ALLOWED_ORIGINS").split(",").map((value) => value.trim()),
  );
  if (!allowed.has(origin)) throw new Error("Origine di ritorno non consentita.");
  return origin;
};

// Unico punto di scelta del fornitore. L'adapter legge da sé le proprie
// credenziali: qui non compare nessun nome di variabile del fornitore.
const provider: CheckoutProvider = creaStripeProvider();

/**
 * La risposta al browser. `clientSecret` è ciò che monta il Payment Element;
 * `checkoutUrl` resta per un eventuale fornitore che offra solo una pagina
 * ospitata. La scomposizione dell'importo viaggia insieme perché il compratore
 * deve vedere quanto della cifra è commissione, e quella cifra è quella
 * congelata sull'ordine — non una ricalcolata dal browser.
 */
const rispostaCheckout = (
  reservation: Reservation,
  handle: { clientSecret: string | null; redirectUrl: string | null },
) => ({
  clientSecret: handle.clientSecret,
  checkoutUrl: handle.redirectUrl,
  orderId: reservation.order_id,
  amountCents: reservation.amount_cents,
  prezzoVenditoreCents: reservation.prezzo_venditore_cents ?? null,
  commissioneCents: reservation.commissione_cents ?? null,
  // I parametri congelati viaggiano con la risposta: il browser deve poter
  // spiegare il rincaro, non ricalcolarlo. La percentuale effettiva è un
  // rapporto fra due numeri che sono già qui.
  margineObiettivoBps: reservation.margine_obiettivo_bps ?? null,
  riferimentoStripePercentualeBps: reservation.riferimento_stripe_percentuale_bps ?? null,
  riferimentoStripeFissoCents: reservation.riferimento_stripe_fisso_cents ?? null,
  currency: reservation.currency,
});

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
  if (reservation.order_status === "annullato" || reservation.payment_status === "failed") {
    return json({ error: "Checkout precedente chiuso; usa una nuova chiave idempotenza." }, 409, corsHeaders);
  }

  // Ritentativo con la stessa chiave: l'incasso è già aperto presso il
  // fornitore. Il `client_secret` non è nel database — è un segreto, non un dato
  // di dominio — quindi si richiede quello esistente invece di aprirne un
  // secondo.
  if (reservation.provider_session_id) {
    const ripresa = await provider.riprendiCheckout({
      provider: reservation.provider ?? provider.id,
      sessionId: reservation.provider_session_id,
    });
    if (!ripresa.ok) {
      return json({ error: "Checkout temporaneamente non disponibile." }, 502, corsHeaders);
    }
    return json(rispostaCheckout(reservation, ripresa.data), 200, corsHeaders);
  }

  let redirectOrigin: string;
  try {
    redirectOrigin = risolviOrigineRitorno();
  } catch {
    await supabase.rpc("order_checkout_release", {
      p_order_id: reservation.order_id,
      p_buyer_id: authData.user.id,
    });
    return json({ error: "Checkout temporaneamente non disponibile." }, 502, corsHeaders);
  }

  const apertura = await provider.apriCheckout({
    orderId: reservation.order_id,
    buyerId: authData.user.id,
    listingId: input.listingId,
    descrizione: reservation.wine_name ?? "Ordine Vinea",
    amountCents: reservation.amount_cents,
    currency: reservation.currency,
    successUrl: `${redirectOrigin}/ordini/${reservation.order_id}?checkout=success`,
    cancelUrl: `${redirectOrigin}/annuncio/${input.listingId}?checkout=cancelled`,
    idempotencyKey,
    expiresAt: reservation.reservation_expires_at ?? null,
  });
  if (!apertura.ok) {
    await supabase.rpc("order_checkout_release", {
      p_order_id: reservation.order_id,
      p_buyer_id: authData.user.id,
    });
    return json({ error: "Checkout temporaneamente non disponibile." }, 502, corsHeaders);
  }

  const { error: attachError } = await supabase.rpc("payment_checkout_attach", {
    p_order_id: reservation.order_id,
    p_buyer_id: authData.user.id,
    p_provider: apertura.data.ref.provider,
    p_provider_session_id: apertura.data.ref.sessionId,
    p_checkout_url: apertura.data.redirectUrl,
  });
  if (attachError) {
    return json({ error: "Checkout creato ma non ancora collegato; riprova." }, 502, corsHeaders);
  }
  return json(rispostaCheckout(reservation, apertura.data), 201, corsHeaders);
});
