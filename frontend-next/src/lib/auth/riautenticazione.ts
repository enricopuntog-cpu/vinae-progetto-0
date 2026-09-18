import type { OAuthProvider } from "@/services/types";

/**
 * Step-up auth: il database rifiuta un prelievo nuovo se la sessione del token
 * non è nata negli ultimi 15 minuti (`private.autenticazione_recente_richiedi`).
 * Il rifiuto arriva da PostgREST come 403 con questo `code`, prodotto dallo
 * stesso meccanismo `raise sqlstate 'PGRST'` di `rate_limit_exceeded`.
 *
 * Il controllo vero sta nel database. Questo modulo decide soltanto COME
 * chiedere all'utente di rifare l'accesso; saltarlo non apre alcuna porta.
 */
export const CODICE_RIAUTENTICAZIONE = "reauth_required";

/** Dove rientra chi conferma con un provider OAuth: la pagina del saldo. */
export const PERCORSO_RITORNO_RIAUTENTICAZIONE = "/account";

/**
 * Quali prove può dare l'utente corrente. Non si indovina dal modo in cui è
 * entrato oggi: si legge dalle identità collegate all'account.
 *
 * - `password`: esiste un'identità `email`, quindi un accesso con password.
 * - `oauth`: i provider sociali collegati, nell'ordine in cui li mostriamo.
 *
 * Un account nato con Google non ha un'identità `email` e quindi non vede un
 * campo password: gli chiederemmo qualcosa che non ha mai avuto.
 */
export type MetodiRiautenticazione = {
  readonly email: string | null;
  readonly password: boolean;
  readonly oauth: readonly OAuthProvider[];
};

const ORDINE_OAUTH: readonly OAuthProvider[] = ["google", "facebook"];

export const metodiRiautenticazioneDa = (
  identita: ReadonlyArray<{ provider?: string | null }> | null | undefined,
  email: string | null | undefined,
): MetodiRiautenticazione => {
  const provider = new Set((identita ?? []).map((i) => i.provider ?? ""));
  const emailNota = typeof email === "string" && email.trim() !== "" ? email : null;
  return {
    email: emailNota,
    // Senza email non c'è nulla da passare a signInWithPassword.
    password: provider.has("email") && emailNota !== null,
    oauth: ORDINE_OAUTH.filter((p) => provider.has(p)),
  };
};

export const nessunMetodoRiautenticazione = (metodi: MetodiRiautenticazione): boolean =>
  !metodi.password && metodi.oauth.length === 0;

export const ETICHETTA_PROVIDER: Record<OAuthProvider, string> = {
  google: "Google",
  facebook: "Facebook",
};
