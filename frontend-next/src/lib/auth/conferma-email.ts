/**
 * Conferma dell'email di registrazione con `token_hash`, verificata dal server.
 *
 * PERCHÉ NON BASTAVA `/auth/callback`. Il client browser usa il flusso PKCE
 * (`createBrowserClient`, vedi lib/supabase/client.ts): `signUp` lascia nei
 * cookie del browser che registra un `code_verifier`, e il link standard della
 * mail (`{{ .ConfirmationURL }}`) passa da `/auth/v1/verify` e torna su
 * `/auth/callback?code=…`, dove lo scambio richiede **quello stesso verifier**.
 * Il 9 ottobre 2026 una registrazione fatta da Chrome su iPhone è stata
 * confermata aprendo la mail in Safari: `/verify` è riuscito ed
 * `email_confirmed_at` è stato scritto, ma nei log Auth non compare alcuna
 * `POST /token?grant_type=pkce` — Safari non aveva il verifier, auth-js ha
 * lanciato `AuthPKCECodeVerifierMissingError` prima di chiamare il server e la
 * callback ha mostrato «Non è stato possibile completare l'accesso», con
 * l'account in realtà già confermato.
 *
 * Con il template «Confirm signup» che punta a `/auth/confirm?token_hash=…`, la
 * route chiama `verifyOtp` dal server: la prova di possesso è il `token_hash`
 * arrivato nella casella dell'utente, non un segreto rimasto in un altro
 * browser. La sessione viene scritta nei cookie del browser che apre il link,
 * qualunque esso sia. È il flusso documentato da Supabase per Auth SSR.
 *
 * Questo modulo non tocca Supabase: legge la richiesta e classifica l'esito, e
 * la route (`app/auth/confirm/route.ts`) esegue la verifica. Così ogni ramo si
 * prova senza rete e senza sostituire moduli.
 */

import type { EmailOtpType } from "@supabase/supabase-js";
import { percorsoRelativoSicuro } from "@/lib/auth/origine-redirect";
import { classificaErroreAuth, type CodiceErroreAuth, type ErroreGrezzo } from "@/lib/auth/errori-auth";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";

/** Percorso pubblico della route; il template email deve citarlo identico. */
export const PERCORSO_CONFERMA_EMAIL = "/auth/confirm";

/** Destinazione dopo una conferma riuscita, se il link non ne porta una. */
export const DESTINAZIONE_PREDEFINITA_CONFERMA = "/home";

/** Dove porta un link di conferma che non si completa: l'account esiste già. */
export const SUPERFICIE_ERRORE_CONFERMA = "/accedi";

/**
 * Tipi OTP ammessi su questa route. `email` è quello del template documentato
 * da Supabase per «Confirm signup»; `signup` è il nome storico dello stesso
 * evento. Recupero password, magic link, invito e cambio email restano fuori:
 * hanno i loro flussi, e questa route non deve aprire una sessione di recupero
 * o confermare un cambio d'indirizzo per conto loro.
 */
export const TIPI_OTP_CONFERMA = ["email", "signup"] as const satisfies readonly EmailOtpType[];
export type TipoOtpConferma = (typeof TIPI_OTP_CONFERMA)[number];

const eTipoConferma = (valore: string | null): valore is TipoOtpConferma =>
  valore !== null && (TIPI_OTP_CONFERMA as readonly string[]).includes(valore);

/**
 * Forma minima di un `token_hash` di GoTrue: esadecimale, eventualmente con il
 * prefisso `pkce_` delle registrazioni avviate in PKCE. Il controllo non è una
 * difesa crittografica — la decide il server Auth — ma evita di mandargli
 * stringhe arbitrarie e di confondere un link troncato con un link scaduto.
 */
const FORMA_TOKEN_HASH = /^(pkce_)?[0-9a-f]{20,128}$/i;

/**
 * Destinazione richiesta dal link, sempre relativa. Viene letta da `next` e, in
 * mancanza, dal `next` dentro `redirect_to` (il `{{ .RedirectTo }}` del
 * template, cioè l'`emailRedirectTo` chiesto da `signUp`, oggi
 * `<origine>/auth/callback?superficie=…&next=…`). Dell'URL di `redirect_to`
 * non si usa **nient'altro**: né l'origine né il percorso, perché l'origine dei
 * redirect la decide il server (`risolviOriginePubblica`) e un link costruito a
 * mano non deve poterla scegliere.
 */
export const destinazioneDaLink = (parametri: URLSearchParams): string => {
  const diretta = percorsoRelativoSicuro(parametri.get(PARAMETRO_NEXT));
  if (diretta) return diretta;

  const redirectTo = parametri.get("redirect_to");
  if (redirectTo) {
    try {
      const annidata = percorsoRelativoSicuro(new URL(redirectTo).searchParams.get(PARAMETRO_NEXT));
      if (annidata) return annidata;
    } catch {
      // `redirect_to` non è un URL assoluto: si ignora, non è un errore utente.
    }
  }
  return DESTINAZIONE_PREDEFINITA_CONFERMA;
};

export type LetturaConferma =
  | { readonly ok: true; readonly tokenHash: string; readonly tipo: TipoOtpConferma; readonly destinazione: string }
  | { readonly ok: false; readonly codice: CodiceErroreAuth; readonly destinazione: string };

/**
 * Valida la richiesta prima di qualunque chiamata al provider. Un tipo diverso
 * da quelli ammessi o un token mancante/malformato non arrivano a `verifyOtp`.
 */
export const leggiRichiestaConferma = (parametri: URLSearchParams): LetturaConferma => {
  const destinazione = destinazioneDaLink(parametri);
  const tokenHash = parametri.get("token_hash");
  const tipo = parametri.get("type");

  if (!tokenHash || !FORMA_TOKEN_HASH.test(tokenHash) || !eTipoConferma(tipo)) {
    return { ok: false, codice: "conferma-link-non-valido", destinazione };
  }
  return { ok: true, tokenHash, tipo, destinazione };
};

/**
 * Classifica l'errore di `verifyOtp`. GoTrue risponde allo stesso modo — 403
 * `otp_expired`, «Email link is invalid or has expired» — a un link scaduto e
 * a uno già usato, quindi per l'utente sono un caso solo, e il più delle volte
 * l'indirizzo risulta già confermato: l'azione utile è accedere.
 */
export const classificaErroreConferma = (errore: ErroreGrezzo): CodiceErroreAuth => {
  const testo = `${errore?.code ?? ""} ${errore?.message ?? ""}`.toLowerCase();
  if (/otp_expired|invalid or has expired|token not found|otp_disabled|flow_state/.test(testo)) {
    return "conferma-link-non-valido";
  }
  const famiglia = classificaErroreAuth(errore, "conferma-email");
  return famiglia === "troppi-tentativi" ? famiglia : "conferma-non-riuscita";
};

/**
 * Percorso di ritorno quando la conferma non si completa: sempre `/accedi`, con
 * un codice del vocabolario e, se c'era, la destinazione già validata. Nessun
 * valore ricevuto entra nell'URL, tanto meno il `token_hash`.
 */
export const percorsoErroreConferma = (codice: CodiceErroreAuth, destinazione: string): string => {
  const parametri = new URLSearchParams({ errore: codice });
  if (destinazione !== DESTINAZIONE_PREDEFINITA_CONFERMA) parametri.set(PARAMETRO_NEXT, destinazione);
  return `${SUPERFICIE_ERRORE_CONFERMA}?${parametri.toString()}`;
};
