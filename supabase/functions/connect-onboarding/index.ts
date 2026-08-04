// Onboarding dell'account di incasso del venditore.
//
// Ordine delle operazioni, e il motivo per cui è quello:
//
//   1. si legge se un account esiste già (`seller_payout_account_get`);
//   2. solo se non esiste se ne apre uno presso il fornitore;
//   3. lo si registra (`seller_payout_account_upsert`);
//   4. si genera il link ospitato e lo si restituisce.
//
// Aprire prima e controllare dopo lascerebbe un account orfano a ogni
// ritentativo: il fornitore l'avrebbe creato, il database no. Il passo 1 non è
// una ottimizzazione, è ciò che rende la funzione ripetibile.
//
// Questo file non conosce nessun fornitore: parla solo con `ConnectProvider`.
// L'unico punto in cui un nome compare è la riga di import dell'adapter.

import { createClient } from "@supabase/supabase-js";
import { corsHeadersFor } from "../_shared/cors.ts";
import type { ConnectProvider } from "../_shared/payment-provider.ts";
import { creaStripeConnectProvider } from "./providers/stripe.ts";

type AccountRow = {
  provider_account_id: string;
  charges_enabled: boolean;
  payouts_enabled: boolean;
  details_submitted: boolean;
  requisiti_pendenti?: string[];
  disabled_reason?: string | null;
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
 * rimandare l'utente. Stessa regola di `payments-checkout`.
 */
const risolviOrigineRitorno = (): string => {
  const origin = env("PAYMENT_REDIRECT_ORIGIN").replace(/\/$/, "");
  const allowed = new Set(
    env("PAYMENT_REDIRECT_ALLOWED_ORIGINS").split(",").map((value) => value.trim()),
  );
  if (!allowed.has(origin)) throw new Error("Origine di ritorno non consentita.");
  return origin;
};

const provider: ConnectProvider = creaStripeConnectProvider();

Deno.serve(async (request) => {
  const corsHeaders = corsHeadersFor(request);
  if (!corsHeaders) return json({ error: "Origine non consentita." }, 403);
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Metodo non consentito." }, 405, corsHeaders);
  // Stesso kill switch del checkout: l'onboarding apre account veri presso il
  // fornitore, quindi appartiene alla stessa verticale e allo stesso gate.
  if (Deno.env.get("PAYMENTS_ENABLED") !== "true") {
    return json({ error: "Pagamenti non attivi." }, 503, corsHeaders);
  }

  const authorization = request.headers.get("authorization") ?? "";
  const accessToken = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  if (!accessToken) return json({ error: "Autenticazione richiesta." }, 401, corsHeaders);

  const supabase = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await supabase.auth.getUser(accessToken);
  if (authError || !authData.user) return json({ error: "Sessione non valida." }, 401, corsHeaders);
  const sellerId = authData.user.id;

  let redirectOrigin: string;
  try {
    redirectOrigin = risolviOrigineRitorno();
  } catch {
    return json({ error: "Onboarding temporaneamente non disponibile." }, 502, corsHeaders);
  }

  const { data: esistente, error: letturaError } = await supabase.rpc(
    "seller_payout_account_get",
    { p_seller_id: sellerId, p_provider: provider.id },
  );
  if (letturaError) return json({ error: "Onboarding non disponibile." }, 502, corsHeaders);

  let accountId = (esistente as AccountRow | null)?.provider_account_id ?? null;

  if (!accountId) {
    const creazione = await provider.creaAccount({
      sellerId,
      email: authData.user.email ?? null,
      paese: Deno.env.get("CONNECT_ACCOUNT_COUNTRY") ?? "IT",
    });
    if (!creazione.ok) {
      return json({ error: "Onboarding temporaneamente non disponibile." }, 502, corsHeaders);
    }

    const { data: registrato, error: upsertError } = await supabase.rpc(
      "seller_payout_account_upsert",
      {
        p_seller_id: sellerId,
        p_provider: creazione.data.provider,
        p_provider_account_id: creazione.data.accountId,
      },
    );
    if (upsertError) return json({ error: "Onboarding non disponibile." }, 502, corsHeaders);
    // Una corsa fra due richieste dello stesso venditore finisce qui: la RPC
    // restituisce l'account già registrato e quello appena aperto viene
    // abbandonato. Un account Express senza onboarding non incassa nulla.
    accountId = (registrato as { provider_account_id: string }).provider_account_id;
  }

  const link = await provider.creaLinkOnboarding({
    accountId,
    refreshUrl: `${redirectOrigin}/venditore/incassi?onboarding=riprendi`,
    returnUrl: `${redirectOrigin}/venditore/incassi?onboarding=completato`,
  });
  if (!link.ok) {
    return json({ error: "Onboarding temporaneamente non disponibile." }, 502, corsHeaders);
  }

  // `charges_enabled` e `payouts_enabled` non si leggono da qui: arrivano solo
  // dall'evento firmato `account.updated`. Ciò che si restituisce è lo stato già
  // registrato, che può essere più vecchio del vero ma non è mai inventato.
  const stato = esistente as AccountRow | null;
  return json(
    {
      onboardingUrl: link.data.url,
      expiresAt: link.data.expiresAt,
      chargesEnabled: stato?.charges_enabled ?? false,
      payoutsEnabled: stato?.payouts_enabled ?? false,
      detailsSubmitted: stato?.details_submitted ?? false,
      requisitiPendenti: stato?.requisiti_pendenti ?? [],
    },
    201,
    corsHeaders,
  );
});
