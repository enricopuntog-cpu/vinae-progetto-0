/**
 * Destinazione di rientro che si chiede a Supabase Auth per i flussi che
 * tornano nell'app con un `code` da scambiare: conferma della registrazione,
 * magic link e OAuth.
 *
 * PERCHÉ UN MODULO E NON TRE STRINGHE. Il valore va scritto **identico** nei
 * tre punti che lo inviano (`registra`, `inviaMagicLink`, `accediConOAuth`),
 * perché Supabase non lo accetta per somiglianza: lo confronta con l'elenco
 * "Redirect URLs" del progetto e, se non trova corrispondenza, **non rifiuta
 * la richiesta** — ricade in silenzio sul Site URL. Un solo punto che lo
 * costruisce è ciò che impedisce a uno dei tre di divergere senza che nessun
 * errore lo segnali.
 *
 * PERCHÉ `/auth/callback` E NON L'ORIGINE NUDA. Il client browser è creato con
 * `createBrowserClient` di @supabase/ssr (vedi lib/supabase/client.ts), che usa
 * il flusso PKCE: il link di conferma non riporta una sessione già fatta, ma un
 * `?code=` che qualcuno deve scambiare con `exchangeCodeForSession`. L'unico
 * punto dell'app che lo fa è la route `/auth/callback`, il cui compito è
 * dichiarato nel suo stesso commento — «punto di ritorno per i flussi che
 * rimandano all'app con un code da scambiare per una sessione». Mandare la
 * conferma sull'origine nuda la fa atterrare su una pagina che quel code non
 * lo scambia.
 *
 * NESSUNA QUERY STRING, E NON È UNA PREFERENZA DI STILE. Misurato sul progetto
 * reale il 17 agosto 2026 interrogando `/auth/v1/verify` con un token non
 * valido — una GET che non crea utenti e non invia email:
 *
 *   https://timely-lokum-43a12e.netlify.app/auth/callback
 *     -> risolto in sé stesso                                    (ammesso)
 *   https://timely-lokum-43a12e.netlify.app/auth/callback?next=%2Fhome
 *     -> risolto in http://localhost:3000                    (NON ammesso)
 *   https://timely-lokum-43a12e.netlify.app/auth/callback/
 *     -> risolto in http://localhost:3000                    (NON ammesso)
 *
 * La voce in elenco per il dominio beta è **esatta e senza wildcard**, quindi
 * qualunque cosa si aggiunga in coda — un `?next=`, perfino una barra finale —
 * fa ricadere l'utente sul Site URL, che è `http://localhost:3000`. Finché
 * quella voce resta esatta, questo modulo non deve produrre né query né barra
 * finale: la destinazione dopo lo scambio la decide `/auth/callback` da sé,
 * che senza `next` manda a `/home`.
 */

/** Unico punto dell'app che scambia un `code` per una sessione. */
export const PERCORSO_RITORNO_AUTH = "/auth/callback";

/**
 * Compone la destinazione di rientro a partire da un'origine.
 *
 * Normalizza le barre finali dell'origine per non produrre mai `//auth/callback`,
 * che sarebbe una stringa diversa da quella in elenco e ricadrebbe sul Site URL
 * esattamente come gli altri scarti misurati sopra.
 */
export function urlRitornoAuth(origine: string): string {
  return `${origine.replace(/\/+$/, "")}${PERCORSO_RITORNO_AUTH}`;
}

/**
 * La stessa destinazione, ricavata dall'origine da cui l'utente sta davvero
 * navigando. Torna `undefined` fuori dal browser invece di indovinare
 * un'origine: durante il render server non esiste un'origine dell'utente, e
 * inventarne una manderebbe la conferma su un dominio che non è il suo.
 */
export function urlRitornoAuthDalBrowser(): string | undefined {
  if (typeof window === "undefined") return undefined;
  return urlRitornoAuth(window.location.origin);
}
