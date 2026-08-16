/**
 * Origine pubblica attendibile per i redirect della route di callback Auth.
 *
 * La route costruiva ogni `Location` da `request.nextUrl.origin`, cioè da un
 * dato che arriva **con la richiesta**. Su Netlify oggi il risultato è giusto,
 * ma lo è per come la piattaforma normalizza l'`Host` a monte, non perché il
 * codice lo imponga: nessuna riga dice quale sia il dominio buono. Un dominio
 * personalizzato, un alias nuovo o un cambio di comportamento del bordo
 * sposterebbero il `Location` senza che niente fallisca, e i cookie di sessione
 * scritti da `exchangeCodeForSession` sono legati all'hostname — quindi la
 * sessione si perderebbe in silenzio subito dopo essere stata creata.
 *
 * Qui l'origine viene **decisa dal server** e la richiesta non la sceglie mai,
 * salvo in sviluppo locale. È la stessa forma già usata dai pagamenti, dove
 * `PAYMENT_REDIRECT_ORIGIN` è scelta dal server e deve appartenere a
 * `PAYMENT_REDIRECT_ALLOWED_ORIGINS` (`supabase/functions/payments-checkout/index.ts:65-67`).
 *
 * Nessuna di queste variabili è `NEXT_PUBLIC_*`: il dato serve solo al server e
 * metterlo nel bundle del browser lo renderebbe pubblico senza alcun guadagno.
 */

/** Contesti Netlify in cui il dominio corretto **non** è quello di produzione. */
const CONTESTI_NON_PRODUZIONE: ReadonlySet<string> = new Set(["deploy-preview", "branch-deploy"]);

/**
 * Gli unici hostname per cui ci si fida della richiesta.
 *
 * Elenco chiuso e confronto sull'hostname intero, mai per sottostringa o
 * suffisso: `localhost.evil.example` non è localhost, e un confronto per
 * suffisso lo accetterebbe.
 */
const HOSTNAME_LOCALI: ReadonlySet<string> = new Set(["localhost", "127.0.0.1", "::1", "[::1]"]);

/**
 * Quale regola ha prodotto l'origine. Serve a rendere la verifica **misurabile**
 * invece che dedotta: sul redirect giusto da solo non si distingue il caso in
 * cui ha deciso il server da quello in cui ha deciso la richiesta, perché su
 * Netlify i due valori coincidono. Viaggia in un header di risposta e nomina la
 * regola, mai un valore di ambiente.
 */
export type SorgenteOrigine =
  | "override-esplicito"
  | "netlify-non-produzione"
  | "netlify-produzione"
  | "richiesta-locale"
  | "richiesta-non-attendibile";

export type OriginePubblica = {
  readonly origine: string;
  readonly sorgente: SorgenteOrigine;
};

/**
 * Le sole variabili lette. `CONTEXT`, `DEPLOY_PRIME_URL` e `URL` sono riservate
 * di Netlify e le popola la piattaforma; `AUTH_REDIRECT_ORIGIN` è l'override
 * esplicito per gli ambienti che non sono Netlify.
 */
export type AmbienteOrigine = {
  readonly AUTH_REDIRECT_ORIGIN?: string | undefined;
  readonly CONTEXT?: string | undefined;
  readonly DEPLOY_PRIME_URL?: string | undefined;
  readonly URL?: string | undefined;
};

/**
 * Le quattro letture, scritte una per una invece di passare l'intero
 * `process.env`: `process.env.NOME` è la forma che Next riconosce e sostituisce,
 * e l'elenco esplicito rende visibile in un punto solo che cosa questa route
 * legge dall'ambiente.
 */
export const ambienteCorrente = (): AmbienteOrigine => ({
  AUTH_REDIRECT_ORIGIN: process.env.AUTH_REDIRECT_ORIGIN,
  CONTEXT: process.env.CONTEXT,
  DEPLOY_PRIME_URL: process.env.DEPLOY_PRIME_URL,
  URL: process.env.URL,
});

/**
 * Estrae l'origine da un valore di ambiente, scartando tutto ciò che non è un
 * URL assoluto `http`/`https`. Scartare invece di accettare significa che una
 * variabile vuota, mal scritta o `javascript:` fa scendere alla regola
 * successiva anziché diventare un `Location`.
 */
const origineDa = (valore: string | undefined): string | null => {
  if (!valore) return null;
  try {
    const url = new URL(valore.trim());
    return url.protocol === "http:" || url.protocol === "https:" ? url.origin : null;
  } catch {
    return null;
  }
};

/**
 * Risolve l'origine su cui rimandare l'utente, in ordine di fiducia decrescente.
 *
 * L'ultimo caso ricade sull'origine della richiesta: è esattamente il
 * comportamento precedente a questa correzione, quindi non introduce una
 * regressione, e su Netlify non è raggiungibile perché `URL` esiste sempre.
 * È marcato `richiesta-non-attendibile` proprio perché si veda quando accade.
 */
export const risolviOriginePubblica = (
  richiesta: URL,
  ambiente: AmbienteOrigine,
): OriginePubblica => {
  const override = origineDa(ambiente.AUTH_REDIRECT_ORIGIN);
  if (override) return { origine: override, sorgente: "override-esplicito" };

  if (CONTESTI_NON_PRODUZIONE.has(ambiente.CONTEXT ?? "")) {
    const anteprima = origineDa(ambiente.DEPLOY_PRIME_URL);
    if (anteprima) return { origine: anteprima, sorgente: "netlify-non-produzione" };
  }

  const produzione = origineDa(ambiente.URL);
  if (produzione) return { origine: produzione, sorgente: "netlify-produzione" };

  if (HOSTNAME_LOCALI.has(richiesta.hostname)) {
    return { origine: richiesta.origin, sorgente: "richiesta-locale" };
  }

  return { origine: richiesta.origin, sorgente: "richiesta-non-attendibile" };
};

/**
 * Ammette per `next` soltanto un percorso relativo alla nostra stessa origine.
 *
 * `/home` va bene; `https://evil.example` no, e nemmeno `//evil.example` o
 * `/\evil.example`, che **sembrano** relativi e non lo sono: il parser URL dei
 * browser li legge come assoluti verso un altro host — il secondo perché negli
 * schemi speciali la barra rovesciata viene normalizzata in barra. Sono le due
 * forme con cui un controllo scritto come il solo `startsWith("/")` diventa un
 * redirect aperto.
 */
export const percorsoRelativoSicuro = (valore: string | null): string | null => {
  if (!valore || !valore.startsWith("/")) return null;
  const secondoCarattere = valore.charAt(1);
  if (secondoCarattere === "/" || secondoCarattere === "\\") return null;
  return valore;
};
