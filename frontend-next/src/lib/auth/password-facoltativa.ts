/**
 * Password Vinea facoltativa al primo accesso.
 *
 * Chi arriva da Google ha un account senza password. In /completa-profilo può
 * dargliene una nello stesso passaggio in cui sceglie nome utente e data di
 * nascita — oppure no, e continuare ad accedere con Google. Da qui nascono tre
 * casi e non due, ed è il terzo quello che va detto ad alta voce: un solo campo
 * compilato non è «niente password» e non è «questa password», è una frase a
 * metà, e indovinare quale metà valesse non è compito di nessuno.
 *
 * La decisione sta qui, fuori dal componente, perché è la parte che decide se
 * l'account viene toccato: si prova eseguendola, non leggendo il JSX che la
 * chiama.
 *
 * La soglia è la stessa di /registrati e /reimposta-password. Tre soglie
 * diverse per la stessa password vorrebbero dire che due delle tre pagine
 * mentono.
 */

/** Stessa soglia del form di registrazione. Vedi /registrati. */
export const LUNGHEZZA_MINIMA_PASSWORD = 6;

/**
 * La password è in gioco solo se l'utente ha scritto in almeno uno dei due
 * campi. Entrambi vuoti significa «continuo con Google»: nessuna chiamata ad
 * Auth deve partire.
 *
 * Nessun `trim`: gli spazi dentro una password sono caratteri come gli altri e
 * toglierli qui vorrebbe dire salvare una password diversa da quella digitata.
 */
export const richiedePasswordVinea = (password: string, conferma: string): boolean =>
  password.length > 0 || conferma.length > 0;

/**
 * Il motivo per cui la password facoltativa non è utilizzabile, oppure `null`
 * se non c'è nulla da obiettare — compreso il caso in cui non è stata chiesta.
 *
 * `null` NON significa «c'è una password da scrivere»: per quello serve anche
 * `richiedePasswordVinea`.
 */
export const problemaPasswordVinea = (password: string, conferma: string): string | null => {
  if (!richiedePasswordVinea(password, conferma)) return null;
  if (password.length === 0) return "Scrivi la password Vinea, oppure svuota il campo di conferma.";
  if (password.length < LUNGHEZZA_MINIMA_PASSWORD)
    return `La password deve avere almeno ${LUNGHEZZA_MINIMA_PASSWORD} caratteri.`;
  if (conferma.length === 0) return "Ripeti la password per confermarla.";
  if (password !== conferma) return "Le due password non coincidono.";
  return null;
};

type EsitoOperazione<E> = { ok: true } | { ok: false; error: E };

type EsitoCompletamento<ErrorePassword> =
  | { tipo: "errore-validazione"; messaggio: string; passwordImpostata: false }
  | { tipo: "errore-password"; errore: ErrorePassword; passwordImpostata: false }
  | { tipo: "errore-profilo"; passwordImpostata: boolean }
  | { tipo: "completato"; passwordImpostata: boolean };

/**
 * Esegue le due scritture nell'ordine che impedisce a un errore password di
 * lasciare il profilo completato. Le dipendenze sono funzioni, non client:
 * questa regola non deve conoscere Supabase né duplicare il servizio Auth.
 *
 * `passwordGiaImpostata` è la memoria del tentativo precedente nella stessa
 * pagina. Se il profilo fallisce dopo una password riuscita, il retry salta la
 * prima funzione e riprova soltanto la seconda. Nessun retry automatico:
 * quando l'esito della scrittura password è incerto, il chiamante mostra
 * l'errore e lascia decidere all'utente se riprovare.
 */
export const completaProfiloConPasswordFacoltativa = async <ErrorePassword>({
  password,
  conferma,
  passwordGiaImpostata,
  aggiornaPassword,
  completaProfilo,
}: {
  password: string;
  conferma: string;
  passwordGiaImpostata: boolean;
  aggiornaPassword: (password: string) => Promise<EsitoOperazione<ErrorePassword>>;
  completaProfilo: () => Promise<EsitoOperazione<unknown>>;
}): Promise<EsitoCompletamento<ErrorePassword>> => {
  const problema = problemaPasswordVinea(password, conferma);
  if (problema)
    return { tipo: "errore-validazione", messaggio: problema, passwordImpostata: false };

  const passwordRichiesta = richiedePasswordVinea(password, conferma);
  let passwordImpostata = passwordGiaImpostata;
  if (passwordRichiesta && !passwordImpostata) {
    const esitoPassword = await aggiornaPassword(password);
    if (!esitoPassword.ok)
      return { tipo: "errore-password", errore: esitoPassword.error, passwordImpostata: false };
    passwordImpostata = true;
  }

  const esitoProfilo = await completaProfilo();
  if (!esitoProfilo.ok) return { tipo: "errore-profilo", passwordImpostata };
  return { tipo: "completato", passwordImpostata };
};
