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

/** Suffisso dei domini gestiti da Netlify. */
const SUFFISSO_NETLIFY = ".netlify.app";

/**
 * Il dominio immutabile di un singolo deploy: ventiquattro cifre esadecimali.
 * Non è mai un destinatario valido — è l'indirizzo di *quel* deploy, non del
 * sito, e mandarci un utente lo legherebbe a un deploy che sarà sostituito.
 */
const PREFISSO_DEPLOY_IMMUTABILE = /^[0-9a-f]{24}$/;

/**
 * Riconosce un alias Netlify **dello stesso sito**, cioè
 * `<qualcosa>--<nome-sito>.netlify.app`, dove `<nome-sito>` è ricavato dal
 * dominio fidato e mai dalla richiesta.
 *
 * Serve perché la misura sulla Deploy Preview della #45 dice che a runtime
 * esiste **soltanto** `URL`: `CONTEXT` e `DEPLOY_PRIME_URL` non ci sono, quindi
 * dalle sole variabili di Netlify una preview è indistinguibile dalla
 * produzione, e senza questa regola chi prova una preview verrebbe rimandato in
 * produzione a metà del login.
 *
 * Non è fiducia indiscriminata nell'`Host`: è un elenco chiuso **derivato da un
 * valore del server**. `evil.example`, `x--altro-sito.netlify.app` e
 * `timely-lokum.netlify.app.evil.example` non passano, e i sottodomini
 * `<qualcosa>--<sito>` sono riservati da Netlify ai deploy di quel sito, quindi
 * non sono rivendicabili da terzi.
 */
const eAliasDelloStessoSito = (richiesta: URL, canonico: string): boolean => {
  if (richiesta.protocol !== "https:") return false;

  const hostCanonico = new URL(canonico).hostname;
  if (!hostCanonico.endsWith(SUFFISSO_NETLIFY)) return false;

  const nomeSito = hostCanonico.slice(0, -SUFFISSO_NETLIFY.length);
  if (!nomeSito || nomeSito.includes(".")) return false;

  const coda = `--${nomeSito}${SUFFISSO_NETLIFY}`;
  if (!richiesta.hostname.endsWith(coda) || richiesta.hostname.length <= coda.length) return false;

  const prefisso = richiesta.hostname.slice(0, -coda.length);
  return !PREFISSO_DEPLOY_IMMUTABILE.test(prefisso);
};

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
  | "netlify-alias-sito"
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
  hostAnnunciato?: string | undefined,
): OriginePubblica => {
  const override = origineDa(ambiente.AUTH_REDIRECT_ORIGIN);
  if (override) return { origine: override, sorgente: "override-esplicito" };

  const contesto = ambiente.CONTEXT ?? "";
  const anteprima = origineDa(ambiente.DEPLOY_PRIME_URL);
  const produzione = origineDa(ambiente.URL);

  /**
   * `CONTEXT` da solo non basta, ed è una misura e non una precauzione: sulla
   * Deploy Preview della #45 la prima versione di questo modulo rispondeva
   * `netlify-produzione`, cioè mandava in produzione chi stava provando la
   * preview. Nella Next runtime di Netlify `URL` è leggibile a runtime e
   * `CONTEXT` no, quindi la regola che dipendeva da `CONTEXT` non scattava mai.
   *
   * Quando `CONTEXT` c'è comanda lui, anche per dire `production`. Quando manca,
   * la differenza fra `DEPLOY_PRIME_URL` e `URL` dice la stessa cosa: in
   * produzione Netlify le tiene uguali, su una preview o un branch deploy no.
   */
  const nonProduzione = contesto
    ? CONTESTI_NON_PRODUZIONE.has(contesto)
    : anteprima !== null && anteprima !== produzione;

  if (anteprima && nonProduzione) {
    return { origine: anteprima, sorgente: "netlify-non-produzione" };
  }

  if (produzione) {
    /**
     * Ultima difesa della preview quando `DEPLOY_PRIME_URL` non è leggibile.
     *
     * L'ordine dei due candidati non è indifferente, ed è una misura: sulla
     * Deploy Preview della #45 `request.nextUrl.origin` vale il **dominio
     * immutabile del deploy** (`6a81e37c…--timely-lokum-43a12e.netlify.app`),
     * mentre l'host annunciato dal bordo è quello giusto
     * (`deploy-preview-45--…`). È esattamente il difetto segnalato all'origine
     * di questa PR, riprodotto: il dominio buono sopravvive solo
     * nell'intestazione, e `nextUrl` porta quello sbagliato.
     *
     * Nessuno dei due viene creduto sulla parola: passano solo se sono alias di
     * *questo* sito, e il dominio immutabile è escluso per forma anche quando
     * lo è. Un host falsificato vale al massimo un altro deploy nostro, mai un
     * dominio di terzi — non è un redirect aperto.
     */
    for (const candidato of [hostAnnunciato && `https://${hostAnnunciato}`, richiesta.href]) {
      if (!candidato) continue;
      let url: URL;
      try {
        url = new URL(candidato);
      } catch {
        continue;
      }
      if (eAliasDelloStessoSito(url, produzione)) {
        return { origine: url.origin, sorgente: "netlify-alias-sito" };
      }
    }
    return { origine: produzione, sorgente: "netlify-produzione" };
  }

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
