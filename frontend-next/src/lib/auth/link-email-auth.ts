/**
 * Recupero password e magic link con `token_hash`, verificati dal server.
 *
 * STESSO DIFETTO DELLA CONFERMA DI REGISTRAZIONE (PR #202). Il client browser
 * usa PKCE: `resetPasswordForEmail` e `signInWithOtp` lasciano un
 * `code_verifier` nei cookie del browser che fa la richiesta, e il link
 * standard (`{{ .ConfirmationURL }}`) torna su `/auth/callback?code=…`, dove lo
 * scambio richiede proprio quel verifier. Chi chiede il link da Chrome e lo
 * apre dall'app Mail, cioè in Safari, arriva senza verifier: auth-js lancia
 * `AuthPKCECodeVerifierMissingError` prima di chiamare il server e il link,
 * benché valido, finisce in «Link non più valido».
 *
 * Il rimedio è quello già in produzione per la registrazione: il template
 * punta a una route che chiama `verifyOtp({ token_hash, type })` dal server.
 * La prova di possesso è il `token_hash` arrivato nella casella dell'utente, e
 * la sessione viene scritta nei cookie del browser che apre il link.
 *
 * UNA ROUTE PER FLUSSO, NON `/auth/confirm` PER TUTTI. `/auth/confirm` accetta
 * solo `email`/`signup` e deve restare così: con `type=email` GoTrue verifica
 * anche il token di recupero, e una conferma di registrazione che apre di
 * nascosto una sessione di recupero sarebbe una porta che nessuno ha chiesto.
 * Qui ogni flusso ha il proprio tipo ammesso, la propria destinazione e la
 * propria superficie d'errore:
 *
 * - `/auth/recupero`: solo `recovery`, sempre verso `/reimposta-password`
 *   (nessun `next` dal link: la destinazione è una costante), errore sulla
 *   stessa pagina che offre di chiedere un link nuovo;
 * - `/auth/accesso`: solo `magiclink`, verso il `next` validato del link
 *   (come `/auth/confirm`), errore su `/accedi`.
 *
 * Le regole condivise vengono da `conferma-email.ts`, non sono ricopiate: forma
 * del `token_hash`, lettura di `next` anche da `redirect_to`, classificazione
 * dell'esito. Questo modulo non tocca Supabase; la route esegue la verifica.
 */

import type { EmailOtpType } from "@supabase/supabase-js";
import { FORMA_TOKEN_HASH, classificaErroreConferma, destinazioneDaLink } from "@/lib/auth/conferma-email";
import type { CodiceErroreAuth, ErroreGrezzo } from "@/lib/auth/errori-auth";
import { PARAMETRO_NEXT, PERCORSO_REIMPOSTA_PASSWORD } from "@/lib/auth/ritorno-auth";

export const PERCORSO_LINK_RECUPERO = "/auth/recupero";
export const PERCORSO_LINK_ACCESSO = "/auth/accesso";

export type FlussoLinkEmail = {
  /** Percorso pubblico della route, identico a quello del template. */
  readonly percorso: string;
  /** Unico tipo OTP che la route passa a `verifyOtp`. */
  readonly tipo: Extract<EmailOtpType, "recovery" | "magiclink">;
  /** Etichetta dei log del server. */
  readonly etichettaLog: string;
  /** Destinazione dopo una verifica riuscita. */
  readonly destinazione: (parametri: URLSearchParams) => string;
  /** Codice per un link scaduto, già usato, troncato o di un altro tipo. */
  readonly codiceLinkNonValido: CodiceErroreAuth;
  /** Codice per ogni altro fallimento non riconosciuto. */
  readonly codiceNonRiuscito: CodiceErroreAuth;
  /** Pagina su cui tornare quando la verifica non si completa. */
  readonly percorsoErrore: (codice: CodiceErroreAuth, destinazione: string) => string;
};

export const FLUSSO_RECUPERO: FlussoLinkEmail = {
  percorso: PERCORSO_LINK_RECUPERO,
  tipo: "recovery",
  etichettaLog: "[auth/recupero]",
  destinazione: () => PERCORSO_REIMPOSTA_PASSWORD,
  codiceLinkNonValido: "recupero-link-non-valido",
  codiceNonRiuscito: "sessione-recupero-assente",
  percorsoErrore: (codice) =>
    `${PERCORSO_REIMPOSTA_PASSWORD}?${new URLSearchParams({ errore: codice }).toString()}`,
};

export const FLUSSO_ACCESSO: FlussoLinkEmail = {
  percorso: PERCORSO_LINK_ACCESSO,
  tipo: "magiclink",
  etichettaLog: "[auth/accesso]",
  destinazione: destinazioneDaLink,
  codiceLinkNonValido: "accesso-link-non-valido",
  codiceNonRiuscito: "scambio-non-riuscito",
  percorsoErrore: (codice, destinazione) => {
    const parametri = new URLSearchParams({ errore: codice });
    if (destinazione !== "/home") parametri.set(PARAMETRO_NEXT, destinazione);
    return `/accedi?${parametri.toString()}`;
  },
};

export type LetturaLinkEmail =
  | { readonly ok: true; readonly tokenHash: string; readonly destinazione: string }
  | { readonly ok: false; readonly codice: CodiceErroreAuth; readonly destinazione: string };

/**
 * Valida la richiesta prima di qualunque chiamata al provider: un tipo diverso
 * da quello del flusso o un token mancante o malformato non arrivano mai a
 * `verifyOtp`.
 */
export const leggiLinkEmail = (flusso: FlussoLinkEmail, parametri: URLSearchParams): LetturaLinkEmail => {
  const destinazione = flusso.destinazione(parametri);
  const tokenHash = parametri.get("token_hash");
  if (!tokenHash || !FORMA_TOKEN_HASH.test(tokenHash) || parametri.get("type") !== flusso.tipo) {
    return { ok: false, codice: flusso.codiceLinkNonValido, destinazione };
  }
  return { ok: true, tokenHash, destinazione };
};

/**
 * Esito di `verifyOtp` tradotto nel vocabolario del flusso. GoTrue risponde
 * 403 `otp_expired` sia a un link scaduto sia a uno già usato: per l'utente è
 * un caso solo, e l'azione è chiederne uno nuovo.
 */
export const classificaErroreLinkEmail = (flusso: FlussoLinkEmail, errore: ErroreGrezzo): CodiceErroreAuth => {
  const famiglia = classificaErroreConferma(errore);
  if (famiglia === "conferma-link-non-valido") return flusso.codiceLinkNonValido;
  if (famiglia === "troppi-tentativi") return famiglia;
  return flusso.codiceNonRiuscito;
};
