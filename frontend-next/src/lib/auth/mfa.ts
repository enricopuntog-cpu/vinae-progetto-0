/**
 * Verifica in due passaggi (TOTP di Supabase Auth) per la capability di
 * continuità.
 *
 * IL CONFINE È NEL DATABASE. `public.incident_notice_set` rifiuta un
 * `emergency_delegate` la cui sessione non ha `aal = aal2` nel JWT, anche se
 * chiama la RPC direttamente (migrazione 20260923200000, griglia 12h e prova
 * REST 12h MFA). Questo modulo decide soltanto che cosa il browser mostra:
 * mandare il delegato a configurare o confermare il secondo fattore prima di
 * presentargli un modulo che il server rifiuterebbe.
 *
 * L'admin conserva il comportamento precedente (aal1 ammesso): la regola nasce
 * per l'identità di emergenza, non cambia l'accesso ordinario del titolare.
 * Per gli utenti normali la MFA non è né chiesta né offerta.
 */

export const PERCORSO_SICUREZZA = "/account/sicurezza";
export const PERCORSO_CONTINUITA = "/continuita";

/** Hint che la porta del banner allega al rifiuto per sessione aal1. */
export const HINT_AAL2_RICHIESTO = "aal2_required";

export const RUOLI_CONTINUITA = ["admin", "emergency_delegate"] as const;

export const haRuoloContinuita = (ruoli: readonly string[]): boolean =>
  ruoli.some((ruolo) => (RUOLI_CONTINUITA as readonly string[]).includes(ruolo));

export type AccessoContinuita = "negato" | "ammesso" | "configura-mfa" | "verifica-mfa";

type FattoreMinimo = { readonly factor_type?: string; readonly status?: string };

export const haTotpVerificato = (fattori: readonly FattoreMinimo[] | null | undefined): boolean =>
  (fattori ?? []).some((f) => f.factor_type === "totp" && f.status === "verified");

/**
 * Chi può aprire /continuita, e con quale sessione.
 *
 * - senza ruolo di continuità: negato (404, come prima);
 * - admin: ammesso a qualunque livello;
 * - emergency_delegate senza fattore TOTP verificato: deve configurarlo;
 * - emergency_delegate con fattore ma sessione non aal2: deve confermarlo;
 * - emergency_delegate in aal2: ammesso.
 *
 * `aal` assente o sconosciuto vale aal1: fail-closed come il database.
 */
export function accessoContinuita(input: {
  readonly ruoli: readonly string[];
  readonly aal: string | null | undefined;
  readonly fattori: readonly FattoreMinimo[] | null | undefined;
}): AccessoContinuita {
  if (input.ruoli.includes("admin")) return "ammesso";
  if (!input.ruoli.includes("emergency_delegate")) return "negato";
  if (input.aal === "aal2") return "ammesso";
  return haTotpVerificato(input.fattori) ? "verifica-mfa" : "configura-mfa";
}

/** Il rifiuto della RPC dipende dalla sessione aal1, non dal ruolo. */
export const erroreRichiedeMfa = (
  errore: { readonly hint?: string | null } | null | undefined,
): boolean => errore?.hint === HINT_AAL2_RICHIESTO;

/** Codice di un'app authenticator: sei cifre, spazi ammessi durante la digitazione. */
export const normalizzaCodiceTotp = (valore: string): string => valore.replace(/\s+/g, "");
export const codiceTotpValido = (valore: string): boolean =>
  /^\d{6}$/.test(normalizzaCodiceTotp(valore));

/**
 * Messaggi per i codici d'errore di Supabase Auth MFA. Nessun dettaglio
 * interno: solo che cosa l'utente può fare.
 */
export function messaggioErroreMfa(codice: string | null | undefined): string {
  switch (codice) {
    case "mfa_verification_failed":
    case "mfa_challenge_expired":
      return "Codice non valido o scaduto. Usa il codice attuale dell'app e riprova.";
    case "mfa_totp_enroll_not_enabled":
    case "mfa_totp_verify_not_enabled":
      return "La verifica in due passaggi non è attiva sul servizio. Avvisa il titolare di Vinea.";
    case "too_many_enrolled_mfa_factors":
      return "Hai troppi fattori registrati. Avvisa il titolare di Vinea.";
    case "over_request_rate_limit":
      return "Troppi tentativi ravvicinati. Attendi qualche minuto e riprova.";
    default:
      return "Operazione non riuscita. Riprova tra poco.";
  }
}
