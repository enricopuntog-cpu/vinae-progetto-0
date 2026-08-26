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
 * NESSUNA QUERY STRING: OGGI UNA SCELTA, IERI UNA NECESSITÀ. Il 17 agosto 2026,
 * misurando sul progetto reale con `/auth/v1/verify` e un token non valido — una
 * GET che non crea utenti e non invia email — la voce in elenco per il dominio
 * beta era **esatta e senza wildcard**, e qualunque cosa si aggiungesse in coda
 * faceva ricadere l'utente sul Site URL, che allora era `http://localhost:3000`:
 *
 *   https://timely-lokum-43a12e.netlify.app/auth/callback
 *     -> risolto in sé stesso                                    (ammesso)
 *   https://timely-lokum-43a12e.netlify.app/auth/callback?next=%2Fhome
 *     -> risolto in http://localhost:3000                    (NON ammesso)
 *   https://timely-lokum-43a12e.netlify.app/auth/callback/
 *     -> risolto in http://localhost:3000                    (NON ammesso)
 *
 * Il **18 agosto 2026** la configurazione è cambiata, su autorizzazione
 * esplicita: `https://timely-lokum-43a12e.netlify.app/**` è stato aggiunto in
 * elenco e il Site URL non è più localhost. Rimisurato con la stessa sonda, un
 * `?next=` e una barra finale ora sarebbero **ammessi**, quindi quel vincolo è
 * decaduto. Fino a D5 questo modulo non produceva comunque query **per scelta**:
 * la destinazione dopo lo scambio la decideva `/auth/callback` da sé, e un
 * secondo posto in cui deciderla sarebbe stato un secondo posto in cui
 * sbagliarla.
 *
 * D5 rovescia quella premessa, non la ignora: la destinazione ora la conosce
 * **solo** la superficie di partenza — quale pagina ha avviato il gesto, e dove
 * l'utente voleva andare prima di essere mandato ad autenticarsi. Nessuno di
 * questi due dati sopravvive al giro dal provider se non viaggia nell'URL,
 * quindi i parametri esistono; ma li produce **solo chi li passa**, e restano
 * costruiti qui e in nessun altro punto. La barra finale continua a non
 * comparire mai.
 *
 * Quanto sopra descrive uno stato del progetto remoto, non una legge di natura:
 * la tabella completa, prima e dopo, sta in docs/ENVIRONMENT.md, ed è lì che va
 * riletta se la configurazione cambia ancora.
 */

import { percorsoRelativoSicuro } from "@/lib/auth/origine-redirect";

/** Unico punto dell'app che scambia un `code` per una sessione. */
export const PERCORSO_RITORNO_AUTH = "/auth/callback";

/**
 * Da quale delle due superfici di ingresso è partito il flusso.
 *
 * Serve alla callback per riportare un errore dove l'utente lo stava
 * aspettando: un tentativo Google iniziato da /registrati che finisce su
 * /accedi non è un errore mostrato male, è l'utente spedito su una pagina che
 * non stava usando.
 */
export type SuperficieAuth = "accedi" | "registrati";

export const PERCORSO_SUPERFICIE_AUTH: Record<SuperficieAuth, string> = {
  accedi: "/accedi",
  registrati: "/registrati",
};

/**
 * Elenco chiuso: qualunque altro valore — assente, inventato o costruito a mano
 * nell'URL — vale `accedi`. Il parametro sceglie fra due pagine nostre, quindi
 * non è mai un redirect aperto nemmeno quando è falsificato.
 */
export const superficieAuthDa = (valore: string | null | undefined): SuperficieAuth =>
  valore === "registrati" ? "registrati" : "accedi";

/** Nomi dei due parametri trasportati dal giro di andata e ritorno. */
export const PARAMETRO_SUPERFICIE = "superficie";
export const PARAMETRO_NEXT = "next";

export type ContestoRitornoAuth = {
  /** Superficie da cui è partito il gesto. */
  readonly superficie?: SuperficieAuth | undefined;
  /** Destinazione richiesta dall'utente, già relativa; validata di nuovo qui. */
  readonly next?: string | null | undefined;
};

/**
 * Compone la destinazione di rientro a partire da un'origine.
 *
 * Normalizza le barre finali dell'origine per non produrre mai `//auth/callback`,
 * che sarebbe una stringa diversa da quella in elenco e ricadrebbe sul Site URL
 * esattamente come gli altri scarti misurati sopra.
 *
 * Senza contesto il risultato è **identico** a prima, carattere per carattere:
 * chi non ha nulla da trasportare non guadagna una query string. I parametri
 * sono un'aggiunta esplicita, e dipendono dalla voce con wildcard in elenco su
 * Supabase — quella misurata il 18 agosto 2026 e descritta sopra. È l'unico
 * punto dell'app che costruisce quella query, così se l'elenco cambia c'è un
 * solo file da rileggere.
 *
 * `next` ripassa da `percorsoRelativoSicuro` anche se chi chiama lo ha già
 * validato: questo modulo scrive un URL che parte dal browser e torna dal
 * provider, e un secondo controllo qui costa una riga.
 */
export function urlRitornoAuth(origine: string, contesto?: ContestoRitornoAuth): string {
  const base = `${origine.replace(/\/+$/, "")}${PERCORSO_RITORNO_AUTH}`;
  const parametri = new URLSearchParams();

  if (contesto?.superficie) parametri.set(PARAMETRO_SUPERFICIE, contesto.superficie);

  const destinazione = percorsoRelativoSicuro(contesto?.next ?? null);
  if (destinazione) parametri.set(PARAMETRO_NEXT, destinazione);

  const query = parametri.toString();
  return query ? `${base}?${query}` : base;
}

/**
 * La stessa destinazione, ricavata dall'origine da cui l'utente sta davvero
 * navigando. Torna `undefined` fuori dal browser invece di indovinare
 * un'origine: durante il render server non esiste un'origine dell'utente, e
 * inventarne una manderebbe la conferma su un dominio che non è il suo.
 */
export function urlRitornoAuthDalBrowser(contesto?: ContestoRitornoAuth): string | undefined {
  if (typeof window === "undefined") return undefined;
  return urlRitornoAuth(window.location.origin, contesto);
}
