// Adapter Stripe per gli account di incasso. Unico file dell'onboarding
// autorizzato a nominare Stripe: se `api.stripe.com` o `STRIPE_` compaiono
// altrove nella function, il confine si è riaperto.
//
// Il tipo di account è **Express**: onboarding ospitato da Stripe, adatto a
// venditori privati. Non Standard (che darebbe al venditore una dashboard
// completa e un rapporto diretto con Stripe) e non Custom (che scaricherebbe su
// Vinea l'intera raccolta KYC).

import type {
  ConnectAccountRef,
  ConnectAccountState,
  ConnectOnboardingLink,
  ConnectProvider,
  Result,
} from "../../_shared/payment-provider.ts";

const STRIPE_ACCOUNTS = "https://api.stripe.com/v1/accounts";
const STRIPE_ACCOUNT_LINKS = "https://api.stripe.com/v1/account_links";

type StripeAccountResponse = {
  id?: string;
  charges_enabled?: boolean;
  payouts_enabled?: boolean;
  details_submitted?: boolean;
  requirements?: { currently_due?: string[]; disabled_reason?: string | null };
  error?: { type?: string; message?: string };
};

type StripeAccountLinkResponse = {
  url?: string;
  expires_at?: number;
  error?: { type?: string };
};

const chiamaStripe = async (
  url: string,
  secretKey: string,
  form: URLSearchParams,
  idempotencyKey?: string,
): Promise<Result<Record<string, unknown>>> => {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${secretKey}`,
    "Content-Type": "application/x-www-form-urlencoded",
  };
  if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey;

  let response: Response;
  try {
    response = await fetch(url, { method: "POST", headers, body: form });
  } catch {
    return { ok: false, error: "stripe_unreachable" };
  }
  let result: Record<string, unknown>;
  try {
    result = (await response.json()) as Record<string, unknown>;
  } catch {
    return { ok: false, error: `stripe_bad_response_${response.status}` };
  }
  if (!response.ok) {
    const error = result.error as { type?: string } | undefined;
    return { ok: false, error: `stripe_failed_${error?.type ?? response.status}` };
  }
  return { ok: true, data: result };
};

const leggiStato = (account: StripeAccountResponse): ConnectAccountState => ({
  chargesEnabled: account.charges_enabled === true,
  payoutsEnabled: account.payouts_enabled === true,
  detailsSubmitted: account.details_submitted === true,
  requisitiPendenti: account.requirements?.currently_due ?? [],
  disabledReason: account.requirements?.disabled_reason ?? null,
});

export const creaStripeConnectProvider = (): ConnectProvider => ({
  id: "stripe",

  async creaAccount(input): Promise<Result<ConnectAccountRef>> {
    // Il segreto si legge per chiamata, non all'avvio del modulo: se manca, la
    // richiesta fallisce invece di far cadere la function al boot.
    const secretKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!secretKey) return { ok: false, error: "stripe_secret_missing" };

    const form = new URLSearchParams({
      type: "express",
      country: input.paese,
      "business_type": "individual",
      "capabilities[transfers][requested]": "true",
      // La piattaforma incassa per conto proprio e trasferisce dopo, quindi le
      // capability di incasso restano sulla piattaforma: all'account del
      // venditore serve poter *ricevere*.
      "metadata[seller_id]": input.sellerId,
      "settings[payouts][schedule][interval]": "manual",
    });
    if (input.email) form.set("email", input.email);

    // Idempotente sul venditore: un doppio clic non apre due account.
    const esito = await chiamaStripe(
      STRIPE_ACCOUNTS,
      secretKey,
      form,
      `vinea-connect-account-${input.sellerId}`,
    );
    if (!esito.ok) return esito;
    const account = esito.data as StripeAccountResponse;
    if (!account.id) return { ok: false, error: "stripe_account_senza_id" };
    return { ok: true, data: { provider: "stripe", accountId: account.id } };
  },

  async creaLinkOnboarding(input): Promise<Result<ConnectOnboardingLink>> {
    const secretKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!secretKey) return { ok: false, error: "stripe_secret_missing" };

    // Nessuna chiave di idempotenza: un Account Link scade in pochi minuti e
    // riusarne uno vecchio manderebbe il venditore su una pagina morta.
    const esito = await chiamaStripe(
      STRIPE_ACCOUNT_LINKS,
      secretKey,
      new URLSearchParams({
        account: input.accountId,
        refresh_url: input.refreshUrl,
        return_url: input.returnUrl,
        type: "account_onboarding",
        "collection_options[fields]": "currently_due",
      }),
    );
    if (!esito.ok) return esito;
    const link = esito.data as StripeAccountLinkResponse;
    if (!link.url) return { ok: false, error: "stripe_link_senza_url" };
    return {
      ok: true,
      data: {
        url: link.url,
        expiresAt: link.expires_at ? new Date(link.expires_at * 1000).toISOString() : null,
      },
    };
  },

  async statoAccount(accountId: string): Promise<Result<ConnectAccountState>> {
    const secretKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!secretKey) return { ok: false, error: "stripe_secret_missing" };

    let response: Response;
    try {
      response = await fetch(`${STRIPE_ACCOUNTS}/${encodeURIComponent(accountId)}`, {
        headers: { Authorization: `Bearer ${secretKey}` },
      });
    } catch {
      return { ok: false, error: "stripe_unreachable" };
    }
    let account: StripeAccountResponse;
    try {
      account = (await response.json()) as StripeAccountResponse;
    } catch {
      return { ok: false, error: `stripe_bad_response_${response.status}` };
    }
    if (!response.ok || !account.id) {
      return { ok: false, error: `stripe_account_failed_${account.error?.type ?? response.status}` };
    }
    return { ok: true, data: leggiStato(account) };
  },
});
