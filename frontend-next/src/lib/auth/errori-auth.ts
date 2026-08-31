/**
 * Errori di autenticazione: un vocabolario chiuso dell'applicazione, e un solo
 * punto in cui quel vocabolario diventa testo per l'utente.
 *
 * PERCHÉ UN CODICE E NON UNA STRINGA. Prima di questo modulo il canale d'errore
 * dei flussi di ingresso portava direttamente `error.message` di Supabase e
 * `error_description` del provider OAuth: due testi scritti da terzi, in
 * inglese, che arrivavano in pagina così com'erano e — nel caso della callback —
 * viaggiavano anche dentro la query string del redirect. Un codice fa tre cose
 * che una stringa non può fare:
 *
 * 1. attraversa un redirect senza portare con sé alcun dettaglio tecnico;
 * 2. si valida (`eCodiceErroreAuth`), quindi un `?errore=` inventato da chi
 *    costruisce l'URL non diventa testo arbitrario mostrato dentro la nostra
 *    pagina;
 * 3. lascia la scelta delle parole all'applicazione, in un punto solo.
 *
 * NON SI ENUMERANO TUTTI GLI ERRORI SUPABASE. Le famiglie riconosciute sono
 * quelle su cui l'utente può fare qualcosa di diverso; tutto il resto ricade sul
 * fallback dell'operazione, che è sempre un messaggio sicuro. Riconoscere di
 * meno significa un messaggio più vago, mai un dettaglio in più esposto.
 */

/** Vocabolario chiuso. L'ordine non conta; l'appartenenza sì. */
export const CODICI_ERRORE_AUTH = [
  "credenziali-non-valide",
  "email-non-valida",
  "troppi-tentativi",
  "magic-link-non-inviato",
  "oauth-annullato",
  "oauth-rifiutato",
  "oauth-avvio-non-riuscito",
  "callback-senza-codice",
  "scambio-non-riuscito",
  "configurazione-assente",
  "recupero-non-inviato",
  "sessione-recupero-assente",
  "password-non-aggiornata",
  "password-troppo-debole",
  "generico",
] as const;

export type CodiceErroreAuth = (typeof CODICI_ERRORE_AUTH)[number];

/**
 * Quale gesto stava compiendo l'utente. Serve a scegliere il fallback: un
 * errore non riconosciuto durante l'invio di un magic link non è lo stesso
 * evento di un errore non riconosciuto durante lo scambio del code, e dirlo
 * all'utente non costa alcun dettaglio tecnico.
 */
export type OperazioneAuth =
  | "login"
  | "registrazione"
  | "magic-link"
  | "oauth-avvio"
  | "scambio-codice"
  | "recupero-password"
  | "aggiornamento-password";

const FALLBACK_OPERAZIONE: Record<OperazioneAuth, CodiceErroreAuth> = {
  login: "generico",
  registrazione: "generico",
  "magic-link": "magic-link-non-inviato",
  "oauth-avvio": "oauth-avvio-non-riuscito",
  "scambio-codice": "scambio-non-riuscito",
  "recupero-password": "recupero-non-inviato",
  "aggiornamento-password": "password-non-aggiornata",
};

/**
 * Testi mostrati all'utente. Italiani, brevi, e con l'azione successiva dentro
 * la frase: un errore che non dice cosa fare dopo lascia l'utente fermo esatta-
 * mente come un errore incomprensibile.
 *
 * Volutamente senza il nome di un provider: il codice `oauth-*` non sa quale
 * provider lo ha prodotto, e la superficie che mostra il messaggio è già accanto
 * al pulsante che lo ha avviato. Aggiungere "Google" qui vorrebbe dire riscrivere
 * questo modulo il giorno in cui il secondo provider viene riacceso.
 */
export const MESSAGGI_ERRORE_AUTH: Record<CodiceErroreAuth, string> = {
  "credenziali-non-valide": "Email o password non corrette. Controlla i dati e riprova.",
  "email-non-valida": "L'indirizzo email non sembra valido. Correggilo e riprova.",
  "troppi-tentativi": "Troppi tentativi ravvicinati. Attendi qualche minuto e riprova.",
  "magic-link-non-inviato":
    "Non è stato possibile inviare il link di accesso. Riprova fra qualche istante.",
  "oauth-annullato": "Accesso annullato prima di completarlo. Puoi riprovare quando vuoi.",
  "oauth-rifiutato":
    "L'accesso social non è andato a buon fine. Riprova, oppure usa email e password.",
  "oauth-avvio-non-riuscito":
    "Non è stato possibile avviare l'accesso social. Riprova fra qualche istante.",
  "callback-senza-codice": "Il link di accesso non è più valido. Richiedine uno nuovo.",
  "scambio-non-riuscito": "Non è stato possibile completare l'accesso. Riprova dall'inizio.",
  "configurazione-assente": "L'accesso non è disponibile in questo momento. Riprova più tardi.",
  // Il messaggio del recupero non nomina mai l'esito lato provider: chi lo
  // legge non deve poter dedurre se quell'indirizzo esiste. La superficie
  // mostra comunque la stessa conferma neutra in caso di successo.
  "recupero-non-inviato":
    "Non è stato possibile inviare il link per reimpostare la password. Riprova fra qualche istante.",
  "sessione-recupero-assente":
    "Il link per reimpostare la password non è più valido. Richiedine uno nuovo.",
  "password-non-aggiornata":
    "Non è stato possibile aggiornare la password. Riprova fra qualche istante.",
  "password-troppo-debole": "La password è troppo debole. Scegline una più lunga e meno comune.",
  generico: "Non è stato possibile completare l'operazione. Riprova.",
};

export const eCodiceErroreAuth = (valore: unknown): valore is CodiceErroreAuth =>
  typeof valore === "string" && (CODICI_ERRORE_AUTH as readonly string[]).includes(valore);

/**
 * Normalizza qualunque cosa arrivi da un URL in un codice del vocabolario.
 * Un valore assente, sconosciuto o costruito a mano diventa `generico`: la
 * pagina mostra un messaggio nostro e mai il valore ricevuto.
 */
export const codiceErroreAuth = (valore: unknown): CodiceErroreAuth =>
  eCodiceErroreAuth(valore) ? valore : "generico";

/** L'unico punto in cui un codice diventa testo. */
export const messaggioErroreAuth = (valore: unknown): string =>
  MESSAGGI_ERRORE_AUTH[codiceErroreAuth(valore)];

/** La forma minima di un errore Supabase, senza dipendere dal loro tipo. */
export type ErroreGrezzo = {
  readonly message?: string | undefined;
  readonly code?: string | undefined;
  readonly status?: number | undefined;
} | null;

const testoGrezzo = (errore: ErroreGrezzo): string =>
  `${errore?.code ?? ""} ${errore?.message ?? ""}`.toLowerCase();

/**
 * Classifica un errore restituito da Supabase Auth.
 *
 * Il confronto è sul testo perché supabase-js non espone un codice stabile per
 * tutte le famiglie che ci interessano; dove il codice c'è viene comunque
 * incluso nella stringa cercata, così una futura stabilizzazione lato loro
 * continua a cadere nella stessa famiglia senza modifiche qui.
 */
export const classificaErroreAuth = (
  errore: ErroreGrezzo,
  operazione: OperazioneAuth,
): CodiceErroreAuth => {
  const testo = testoGrezzo(errore);

  if (errore?.status === 429 || /rate limit|too many|over_.*_rate|for security purposes/.test(testo)) {
    return "troppi-tentativi";
  }
  if (/invalid login credentials|invalid_credentials|invalid grant|bad_credentials/.test(testo)) {
    return "credenziali-non-valide";
  }
  if (/invalid email|email_address_invalid|unable to validate email/.test(testo)) {
    return "email-non-valida";
  }
  // Famiglie del solo percorso password: una password rifiutata perché debole
  // è l'unico caso in cui l'utente può fare qualcosa di diverso dal riprovare.
  if (/weak_password|password.*(too short|at least|weak)|short_password/.test(testo)) {
    return "password-troppo-debole";
  }
  // La sessione di recupero non esiste o è scaduta: chiedere di nuovo il link
  // è l'azione utile, e riprovare a salvare non lo è.
  if (
    /auth session missing|session_not_found|session missing|jwt expired|token has expired|otp_expired/.test(
      testo,
    )
  ) {
    return operazione === "aggiornamento-password" ? "sessione-recupero-assente" : "generico";
  }
  return FALLBACK_OPERAZIONE[operazione];
};

/**
 * Classifica il rientro di errore di un provider OAuth, cioè il caso in cui la
 * callback riceve `?error=` invece di `?code=`.
 *
 * L'annullamento dell'utente è separato dal rifiuto perché non è un guasto:
 * dire "non è andata a buon fine" a chi ha premuto Annulla lo manda a cercare
 * un problema che non esiste.
 */
export const classificaErroreProvider = (
  error: string | null,
  errorDescription: string | null,
): CodiceErroreAuth => {
  const testo = `${error ?? ""} ${errorDescription ?? ""}`.toLowerCase();
  if (/access_denied|user_cancelled|user_denied|cancell|annull|denied/.test(testo)) {
    return "oauth-annullato";
  }
  return "oauth-rifiutato";
};
