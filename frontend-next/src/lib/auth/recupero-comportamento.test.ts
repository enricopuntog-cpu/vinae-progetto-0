import { afterAll, beforeEach, describe, expect, it, mock } from "bun:test";
import { NextRequest } from "next/server";
import { CODICI_ERRORE_AUTH } from "@/lib/auth/errori-auth";
import { PERCORSO_REIMPOSTA_PASSWORD } from "@/lib/auth/ritorno-auth";

/**
 * Recupero password e consenso social, provati **eseguendo** il codice.
 *
 * `recupero-password.test.ts` accanto a questo file dimostra delle assenze
 * leggendo il sorgente, ed è la forma giusta per quelle: che una password non
 * venga mai scritta in un log non si prova chiamando una funzione una volta.
 * Ma tre fatti di questo work package sono **comportamenti**, non forme, e
 * leggerli nel testo del file non li dimostra:
 *
 * 1. quante volte parte una chiamata al provider (una, non due, non zero);
 * 2. che cosa esce da `/auth/callback` quando lo scambio del code fallisce;
 * 3. che l'errore mostrato sia sempre un codice del vocabolario e mai il testo
 *    che il provider ha restituito.
 *
 * Perciò qui il servizio viene costruito davvero, con un client falso al posto
 * di Supabase, e la route handler viene invocata con una richiesta vera.
 *
 * PERCHÉ `mock.module` E NON UN CLIENT INIETTATO. `AuthService` prende il suo
 * client da `getSupabaseClient()` e la callback dal suo omologo server: sono
 * moduli, non parametri, ed è una scelta deliberata — la sessione vive nei
 * cookie e un secondo modo di procurarsi il client sarebbe un secondo posto in
 * cui sbagliare quale sessione si sta leggendo. Il doppio si mette quindi al
 * livello del modulo. Nessun altro file di test importa questi due moduli, e
 * questo è ciò che rende l'operazione contenuta.
 */

// ---------------------------------------------------------------------------
// Doppi
// ---------------------------------------------------------------------------

type Chiamata = { nome: string; argomenti: readonly unknown[] };

/** Ogni chiamata al finto Supabase, in ordine: il conteggio è una prova. */
const chiamate: Chiamata[] = [];

/** Errore che il finto provider restituirà alla prossima chiamata. */
let erroreProvider: {
  message?: string;
  status?: number;
  code?: string;
  reasons?: string[];
} | null = null;

/** `null` riproduce il progetto senza configurazione. */
let clientBrowserAttivo = true;

const registra = (nome: string, ...argomenti: readonly unknown[]) => {
  chiamate.push({ nome, argomenti });
  return Promise.resolve({ data: { url: null }, error: erroreProvider });
};

/**
 * Stato del finto Auth per la conferma d'identità prima di un prelievo
 * (step-up auth). Vive qui perché questo è l'unico file che sostituisce
 * `@/lib/supabase/client`: un secondo `mock.module` dello stesso modulo in un
 * altro file si contenderebbe il registro dei moduli nello stesso processo.
 */
type UtenteFinto = { id: string; email: string | null; identities: { provider: string }[] };
let utenteSessione: UtenteFinto | null = null;
let utenteServer: UtenteFinto | null = null;
let idDopoLogin: string | null = null;
let registrazione: {
  user: { id: string; email_confirmed_at: string | null } | null;
  session: object | null;
} = { user: null, session: null };
let ruoliFinti: { data: { role: unknown }[] | null; error: { message: string } | null } = { data: [], error: null };

const clientBrowser = {
  auth: {
    getSession: async () => ({
      data: { session: utenteSessione ? { user: utenteSessione } : null },
      error: null,
    }),
    getUser: async () => {
      chiamate.push({ nome: "getUser", argomenti: [] });
      return utenteServer
        ? { data: { user: utenteServer }, error: null }
        : { data: { user: null }, error: { message: "Auth session missing!" } };
    },
    signInWithPassword: async (credenziali: { email: string; password: string }) => {
      chiamate.push({ nome: "signInWithPassword", argomenti: [credenziali] });
      if (erroreProvider) return { data: { user: null, session: null }, error: erroreProvider };
      return { data: { user: { id: idDopoLogin ?? utenteSessione?.id } }, error: null };
    },
    resetPasswordForEmail: (email: string, opzioni?: unknown) =>
      registra("resetPasswordForEmail", email, opzioni),
    updateUser: (attributi: unknown) => registra("updateUser", attributi),
    signInWithOAuth: (parametri: unknown) => registra("signInWithOAuth", parametri),
    signUp: async (parametri: unknown) => {
      chiamate.push({ nome: "signUp", argomenti: [parametri] });
      if (erroreProvider) return { data: { user: null, session: null }, error: erroreProvider };
      return { data: registrazione, error: null };
    },
    verifyOtp: (parametri: unknown) => registra("verifyOtp", parametri),
    signInWithOtp: (parametri: unknown) => registra("signInWithOtp", parametri),
    signOut: () => registra("signOut"),
  },
  from: (tabella: string) => ({
    select: (colonne: string) => ({
      eq: async (colonna: string, valore: string) => {
        chiamate.push({ nome: "from", argomenti: [tabella, colonne, colonna, valore] });
        return ruoliFinti;
      },
    }),
  }),
};

mock.module("@/lib/supabase/client", () => ({
  getSupabaseClient: () => (clientBrowserAttivo ? clientBrowser : null),
}));

/** Esito dello scambio del code, deciso dal singolo caso. */
let scambioFallisce: { message: string } | null = null;
/** Esito di verifyOtp per /auth/confirm, deciso dal singolo caso. */
let verificaFallisce: { message: string; code?: string; status?: number } | null = null;
let clientServerAttivo = true;

mock.module("@/lib/supabase/server", () => ({
  getSupabaseServerClient: async () =>
    clientServerAttivo
      ? {
          auth: {
            exchangeCodeForSession: async (code: string) => {
              chiamate.push({ nome: "exchangeCodeForSession", argomenti: [code] });
              return { error: scambioFallisce };
            },
            verifyOtp: async (parametri: { token_hash: string; type: string }) => {
              chiamate.push({ nome: "verifyOtp", argomenti: [parametri] });
              return { data: {}, error: verificaFallisce };
            },
          },
        }
      : null,
}));

const { supabaseAuthService } = await import("@/services/auth-service");
const { GET } = await import("@/app/auth/callback/route");
const conferma = await import("@/app/auth/confirm/route");
const recupero = await import("@/app/auth/recupero/route");
const accesso = await import("@/app/auth/accesso/route");

/**
 * Il servizio è un modulo client e compone la destinazione di rientro
 * dall'origine da cui l'utente sta navigando. Fuori dal browser quell'origine
 * non esiste, e il codice lo sa: senza un `window` si limiterebbe a non
 * mandare alcun `redirectTo`, e il caso interessante — quale destinazione
 * chiede — non verrebbe mai esercitato.
 */
const windowOriginale = (globalThis as { window?: unknown }).window;
const navigazioni: string[] = [];
(globalThis as { window?: unknown }).window = {
  location: {
    origin: "https://vinea.test",
    href: "https://vinea.test/accedi",
    assign: (url: string) => navigazioni.push(url),
  },
};

afterAll(() => {
  if (windowOriginale === undefined) {
    delete (globalThis as { window?: unknown }).window;
  } else {
    (globalThis as { window?: unknown }).window = windowOriginale;
  }
});

beforeEach(() => {
  chiamate.length = 0;
  navigazioni.length = 0;
  erroreProvider = null;
  scambioFallisce = null;
  verificaFallisce = null;
  clientBrowserAttivo = true;
  clientServerAttivo = true;
  utenteSessione = null;
  utenteServer = null;
  idDopoLogin = null;
  registrazione = { user: null, session: null };
  ruoliFinti = { data: [], error: null };
});

const soloNome = (nome: string) => chiamate.filter((c) => c.nome === nome);

/** Nessun testo mostrato all'utente è mai qualcosa di diverso da un codice. */
const eCodiceDelVocabolario = (valore: unknown) =>
  (CODICI_ERRORE_AUTH as readonly string[]).includes(String(valore));

// ---------------------------------------------------------------------------
// Servizio
// ---------------------------------------------------------------------------

describe("inviaRecuperoPassword — eseguito", () => {
  it("chiama il provider una volta sola e chiede il rientro dalla callback esistente", async () => {
    const esito = await supabaseAuthService.inviaRecuperoPassword("chi@esempio.it");

    expect(esito).toEqual({ ok: true, data: undefined });
    const invii = soloNome("resetPasswordForEmail");
    expect(invii.length).toBe(1);
    expect(invii[0]?.argomenti[0]).toBe("chi@esempio.it");

    const { redirectTo } = invii[0]?.argomenti[1] as { redirectTo: string };
    const url = new URL(redirectTo);
    expect(url.origin).toBe("https://vinea.test");
    expect(url.pathname).toBe("/auth/callback");
    expect(url.searchParams.get("next")).toBe(PERCORSO_REIMPOSTA_PASSWORD);
  });

  it("un indirizzo sconosciuto è indistinguibile da uno noto", async () => {
    // Nel ramo di successo il servizio risponde identico; gli errori che il
    // provider dà solo agli iscritti sono provati sotto (R-AUTH-01).
    const noto = await supabaseAuthService.inviaRecuperoPassword("noto@esempio.it");
    const ignoto = await supabaseAuthService.inviaRecuperoPassword("mai-visto@esempio.it");
    expect(ignoto).toEqual(noto);
    expect(soloNome("resetPasswordForEmail").length).toBe(2);
  });

  it("il testo del provider non esce dal servizio", async () => {
    // Sul ramo che mostra l'errore: senza sessione questo errore è già neutro.
    erroreProvider = { message: "User with this email address not found in project" };
    const esito = await supabaseAuthService.inviaRecuperoPassword("chi@esempio.it", { indirizzoDellaSessione: true });

    expect(esito.ok).toBe(false);
    if (esito.ok) return;
    expect(eCodiceDelVocabolario(esito.error)).toBe(true);
    expect(esito.error).toBe("recupero-non-inviato");
    expect(String(esito.error)).not.toInclude("not found");
  });

  /**
   * R-AUTH-01. Le risposte di GoTrue v2.196.0 `POST /recover` misurate nel
   * laboratorio isolato (docs/VPM_018_R_AUTH_01.md § 3), nella forma che
   * supabase-js ne dà: qui quelle che esistono SOLO per un indirizzo registrato
   * (un 5xx arriva come `AuthRetryableFetchError` con lo stato e senza codice),
   * più la risposta non JSON (`AuthUnknownError`, senza stato) che un proxy
   * potrebbe dare solo agli iscritti; sotto quelle decise prima della ricerca.
   */
  const SOLO_PER_ISCRITTI = [
    { status: 429, code: "over_email_send_rate_limit", message: "For security purposes, you can only request this after 59 seconds." },
    { status: 429, code: "over_email_send_rate_limit", message: "email rate limit exceeded" },
    { status: 500, message: "Error sending recovery email" },
    { status: 400, code: "email_address_invalid", message: "Email address \"x@y.test\" is invalid" },
    { status: 504, message: "upstream request timeout" },
    { message: "Unexpected token '<', \"<html>\" is not valid JSON" },
  ];

  it("senza sessione: un errore che esiste solo per un iscritto risponde come il successo", async () => {
    const neutro = await supabaseAuthService.inviaRecuperoPassword("mai-visto@esempio.it");
    for (const errore of SOLO_PER_ISCRITTI) {
      erroreProvider = errore;
      expect(await supabaseAuthService.inviaRecuperoPassword("iscritto@esempio.it")).toEqual(neutro);
    }
    expect(neutro).toEqual({ ok: true, data: undefined });
    // La chiamata al provider parte comunque, una per richiesta: nulla è simulato.
    expect(soloNome("resetPasswordForEmail").length).toBe(SOLO_PER_ISCRITTI.length + 1);
  });

  it("senza sessione: i rifiuti decisi prima della ricerca dell'account restano visibili", async () => {
    const casi = [
      [{ status: 429, code: "over_request_rate_limit", message: "Request rate limit reached" }, "troppi-tentativi"],
      [{ status: 400, code: "validation_failed", message: "Unable to validate email address: invalid format" }, "email-non-valida"],
      [{ status: 400, code: "captcha_failed", message: "captcha protection: request disallowed" }, "recupero-non-inviato"],
      [{ status: 400, code: "email_provider_disabled", message: "Email logins are disabled" }, "recupero-non-inviato"],
      [{ status: 0, message: "Failed to fetch" }, "recupero-non-inviato"],
      [{ status: 0, message: "Load failed" }, "recupero-non-inviato"],
    ] as const;
    for (const [errore, atteso] of casi) {
      erroreProvider = { ...errore };
      expect(await supabaseAuthService.inviaRecuperoPassword("chiunque@esempio.it")).toEqual({ ok: false, error: atteso });
    }
  });

  it("con l'indirizzo della sessione l'errore vero resta riconoscibile, perché l'azione utile è diversa", async () => {
    erroreProvider = { status: 429, code: "over_email_send_rate_limit", message: "email rate limit exceeded" };
    expect(
      await supabaseAuthService.inviaRecuperoPassword("mio@esempio.it", { indirizzoDellaSessione: true }),
    ).toEqual({ ok: false, error: "troppi-tentativi" });
    erroreProvider = { status: 500, message: "Error sending recovery email" };
    expect(
      await supabaseAuthService.inviaRecuperoPassword("mio@esempio.it", { indirizzoDellaSessione: true }),
    ).toEqual({ ok: false, error: "recupero-non-inviato" });
  });

  it("senza configurazione non parte alcuna chiamata", async () => {
    clientBrowserAttivo = false;
    const esito = await supabaseAuthService.inviaRecuperoPassword("chi@esempio.it");
    expect(esito).toEqual({ ok: false, error: "configurazione-assente" });
    expect(chiamate).toEqual([]);
  });
});

describe("aggiornaPasswordNuova — eseguito", () => {
  it("aggiorna una volta sola, e la password va solo a Supabase Auth", async () => {
    const esito = await supabaseAuthService.aggiornaPasswordNuova("nuova-password-lunga");

    expect(esito).toEqual({ ok: true, data: undefined });
    const aggiornamenti = soloNome("updateUser");
    expect(aggiornamenti.length).toBe(1);
    // L'unico attributo inviato è la password: nessun ruolo, nessun metadato,
    // nessuna scrittura di comodo che passi da qui.
    expect(aggiornamenti[0]?.argomenti[0]).toEqual({ password: "nuova-password-lunga" });
    // E nessuna tabella di questo progetto è stata toccata.
    expect(chiamate.map((c) => c.nome)).toEqual(["updateUser"]);
  });

  it("una sessione di recupero scaduta chiede un link nuovo, non «riprova»", async () => {
    erroreProvider = { message: "Auth session missing!" };
    const esito = await supabaseAuthService.aggiornaPasswordNuova("nuova-password-lunga");
    expect(esito).toEqual({ ok: false, error: "sessione-recupero-assente" });
  });

  it("una password rifiutata per i requisiti lo dice", async () => {
    erroreProvider = { message: "Password should be at least 6 characters" };
    const esito = await supabaseAuthService.aggiornaPasswordNuova("corta");
    expect(esito).toEqual({ ok: false, error: "password-requisiti-mancanti" });
  });

  it("una password compromessa arriva dal server con il suo motivo, distinto dai requisiti", async () => {
    // Forma di `AuthWeakPasswordError` di supabase-js per un 422 `weak_password`
    // con la protezione HIBP attiva in produzione.
    erroreProvider = {
      code: "weak_password",
      status: 422,
      message: "Password is known to be weak and easy to guess, please choose a different one.",
      reasons: ["pwned"],
    };
    const esito = await supabaseAuthService.aggiornaPasswordNuova("Password1!");
    expect(esito).toEqual({ ok: false, error: "password-compromessa" });
  });

  it("un guasto non riconosciuto resta un codice nostro", async () => {
    erroreProvider = { message: 'relation "auth.users" does not exist' };
    const esito = await supabaseAuthService.aggiornaPasswordNuova("nuova-password-lunga");
    expect(esito.ok).toBe(false);
    if (esito.ok) return;
    expect(esito.error).toBe("password-non-aggiornata");
    expect(String(esito.error)).not.toInclude("auth.users");
  });
});

describe("accediConOAuth — eseguito", () => {
  it("una richiesta di accesso social produce una sola chiamata al provider", async () => {
    const esito = await supabaseAuthService.accediConOAuth("google", {
      superficie: "registrati",
    });

    expect(esito).toEqual({ ok: true, data: undefined });
    const avvii = soloNome("signInWithOAuth");
    expect(avvii.length).toBe(1);
    const { provider, options } = avvii[0]?.argomenti[0] as {
      provider: string;
      options: { redirectTo: string };
    };
    expect(provider).toBe("google");
    const url = new URL(options.redirectTo);
    expect(url.pathname).toBe("/auth/callback");
    expect(url.searchParams.get("superficie")).toBe("registrati");
  });

  it("una destinazione assoluta non sopravvive al giro", async () => {
    await supabaseAuthService.accediConOAuth("google", {
      superficie: "accedi",
      next: "https://evil.example/rubata",
    });
    const { options } = soloNome("signInWithOAuth")[0]?.argomenti[0] as {
      options: { redirectTo: string };
    };
    expect(new URL(options.redirectTo).searchParams.get("next")).toBeNull();
    expect(options.redirectTo).not.toInclude("evil.example");
  });

  it("un avvio fallito è un codice, non il testo del provider", async () => {
    erroreProvider = { message: "provider is not enabled" };
    const esito = await supabaseAuthService.accediConOAuth("google");
    expect(esito.ok).toBe(false);
    if (esito.ok) return;
    expect(esito.error).toBe("oauth-avvio-non-riuscito");
    expect(String(esito.error)).not.toInclude("provider is not enabled");
  });
});

// ---------------------------------------------------------------------------
// Callback
// ---------------------------------------------------------------------------

/** Solo percorso e query: l'origine la decide il server ed è provata altrove. */
const destinazioneDi = (risposta: Response) => {
  const posizione = risposta.headers.get("location");
  expect(posizione).not.toBeNull();
  const url = new URL(String(posizione));
  return { percorso: url.pathname, parametri: url.searchParams, href: String(posizione) };
};

const chiama = (query: string) =>
  GET(new NextRequest(`https://vinea.test/auth/callback${query}`));

describe("/auth/callback — recupero password, eseguito", () => {
  it("A. il link valido apre la sessione e porta alla pagina di reimpostazione", async () => {
    const risposta = await chiama("?code=valido&next=%2Freimposta-password");

    expect(soloNome("exchangeCodeForSession").length).toBe(1);
    expect(soloNome("exchangeCodeForSession")[0]?.argomenti[0]).toBe("valido");
    const { percorso, parametri } = destinazioneDi(risposta);
    expect(percorso).toBe(PERCORSO_REIMPOSTA_PASSWORD);
    expect(parametri.get("errore")).toBeNull();
  });

  it("B. il link scaduto resta dentro il recupero, e non finisce su /accedi", async () => {
    // È il caso normale, non il caso raro: questi link valgono una volta sola.
    // Mandare qui l'utente su /accedi significava rispondere «non è stato
    // possibile completare l'accesso» a chi la password non ce l'ha — ed è il
    // motivo per cui aveva chiesto il link.
    scambioFallisce = { message: "invalid flow state, no valid flow state found" };
    const risposta = await chiama("?code=scaduto&next=%2Freimposta-password");

    const { percorso, parametri, href } = destinazioneDi(risposta);
    expect(percorso).toBe(PERCORSO_REIMPOSTA_PASSWORD);
    expect(percorso).not.toBe("/accedi");
    expect(eCodiceDelVocabolario(parametri.get("errore"))).toBe(true);
    expect(parametri.get("errore")).toBe("scambio-non-riuscito");
    // Il testo del provider non viaggia nell'URL: né nella barra degli
    // indirizzi, né nella cronologia, né nei log del bordo.
    expect(href).not.toInclude("flow state");
  });

  it("B bis. anche un link senza code torna nel recupero con un motivo mediato", async () => {
    const risposta = await chiama("?next=%2Freimposta-password");
    const { percorso, parametri } = destinazioneDi(risposta);
    expect(percorso).toBe(PERCORSO_REIMPOSTA_PASSWORD);
    expect(parametri.get("errore")).toBe("callback-senza-codice");
    expect(soloNome("exchangeCodeForSession")).toEqual([]);
  });

  it("B ter. senza configurazione il recupero dice che non è disponibile, non dove guardare", async () => {
    clientServerAttivo = false;
    const risposta = await chiama("?code=valido&next=%2Freimposta-password");
    const { percorso, parametri, href } = destinazioneDi(risposta);
    expect(percorso).toBe(PERCORSO_REIMPOSTA_PASSWORD);
    expect(parametri.get("errore")).toBe("configurazione-assente");
    expect(href).not.toInclude("SUPABASE");
  });

  it("il ritorno del recupero non è mai un URL esterno, nemmeno se `next` lo chiede", async () => {
    scambioFallisce = { message: "expired" };
    const risposta = await chiama("?code=x&next=https%3A%2F%2Fevil.example%2Frubata");
    const { percorso, href } = destinazioneDi(risposta);
    // `next` assoluto viene scartato: la destinazione ricade su /home, quindi
    // questo non è nemmeno un rientro di recupero, e l'errore torna sulla
    // superficie di ingresso. In nessuno dei due casi si esce dal sito.
    expect(href.startsWith("https://vinea.test/")).toBe(true);
    expect(href).not.toInclude("evil.example");
    expect(percorso).toBe("/accedi");
  });
});

describe("/auth/callback — gli altri flussi non sono cambiati", () => {
  it("un errore del provider torna sulla superficie che aveva avviato il gesto", async () => {
    const risposta = await chiama("?error=access_denied&superficie=registrati");
    const { percorso, parametri, href } = destinazioneDi(risposta);
    expect(percorso).toBe("/registrati");
    expect(parametri.get("errore")).toBe("oauth-annullato");
    expect(href).not.toInclude("access_denied");
  });

  it("uno scambio riuscito senza `next` porta a /home", async () => {
    const risposta = await chiama("?code=valido");
    expect(destinazioneDi(risposta).percorso).toBe("/home");
  });

  it("uno scambio fallito fuori dal recupero conserva la destinazione richiesta", async () => {
    scambioFallisce = { message: "invalid request" };
    const risposta = await chiama("?code=x&next=%2Fcantina&superficie=accedi");
    const { percorso, parametri } = destinazioneDi(risposta);
    expect(percorso).toBe("/accedi");
    expect(parametri.get("next")).toBe("/cantina");
  });
});

// ---------------------------------------------------------------------------
// /auth/confirm: conferma della registrazione con token_hash
// ---------------------------------------------------------------------------

/** Forma di un token_hash GoTrue, non un token reale. */
const HASH = "c".repeat(56);

const confermaCon = (query: string) =>
  conferma.GET(new NextRequest(`https://vinea.test/auth/confirm${query}`));

describe("/auth/confirm — eseguito", () => {
  it("un link valido verifica dal server e apre la sessione senza code_verifier", async () => {
    const risposta = await confermaCon(`?token_hash=${HASH}&type=email`);

    // La prova di possesso è il token_hash: nessuno scambio PKCE, quindi nessun
    // bisogno del browser in cui è avvenuta la registrazione.
    expect(soloNome("verifyOtp")).toEqual([
      { nome: "verifyOtp", argomenti: [{ token_hash: HASH, type: "email" }] },
    ]);
    expect(soloNome("exchangeCodeForSession")).toEqual([]);
    expect(risposta.status).toBe(303);
    const { percorso, href } = destinazioneDi(risposta);
    expect(percorso).toBe("/home");
    // Il token non sopravvive nell'URL finale.
    expect(href).not.toInclude(HASH);
    expect(href).not.toInclude("token_hash");
    expect(risposta.headers.get("cache-control")).toInclude("no-store");
  });

  it("la destinazione arriva da redirect_to del template, l'origine no", async () => {
    const redirectTo = encodeURIComponent(
      "https://evil.example/auth/callback?superficie=registrati&next=%2Faccount",
    );
    const risposta = await confermaCon(`?token_hash=${HASH}&type=email&redirect_to=${redirectTo}`);
    const { percorso, href } = destinazioneDi(risposta);
    expect(percorso).toBe("/account");
    expect(href.startsWith("https://vinea.test/")).toBe(true);
    expect(href).not.toInclude("evil.example");
  });

  it("un redirect non attendibile ricade su /home", async () => {
    const risposta = await confermaCon(
      `?token_hash=${HASH}&type=email&next=%2F%2Fevil.example`,
    );
    const { percorso, href } = destinazioneDi(risposta);
    expect(percorso).toBe("/home");
    expect(href).not.toInclude("evil.example");
  });

  it("link scaduto o già usato: /accedi con un messaggio mediato", async () => {
    verificaFallisce = {
      code: "otp_expired",
      status: 403,
      message: "Email link is invalid or has expired",
    };
    const risposta = await confermaCon(`?token_hash=${HASH}&type=email&next=%2Faccount`);
    const { percorso, parametri, href } = destinazioneDi(risposta);
    expect(percorso).toBe("/accedi");
    expect(parametri.get("errore")).toBe("conferma-link-non-valido");
    expect(parametri.get("next")).toBe("/account");
    expect(href).not.toInclude("expired");
    expect(href).not.toInclude(HASH);
  });

  it("riaprire lo stesso link non apre una seconda sessione", async () => {
    await confermaCon(`?token_hash=${HASH}&type=email`);
    verificaFallisce = { code: "otp_expired", status: 403, message: "One-time token not found" };
    const seconda = await confermaCon(`?token_hash=${HASH}&type=email`);
    expect(soloNome("verifyOtp").length).toBe(2);
    expect(destinazioneDi(seconda).parametri.get("errore")).toBe("conferma-link-non-valido");
  });

  it("un tipo OTP diverso dalla conferma non raggiunge il provider", async () => {
    for (const tipo of ["recovery", "magiclink", "invite", "email_change"]) {
      const risposta = await confermaCon(`?token_hash=${HASH}&type=${tipo}`);
      expect(destinazioneDi(risposta).parametri.get("errore")).toBe("conferma-link-non-valido");
    }
    expect(soloNome("verifyOtp")).toEqual([]);
  });

  it("un errore sconosciuto del provider non arriva all'utente", async () => {
    verificaFallisce = { status: 500, message: "Database error finding user: dettaglio interno" };
    const risposta = await confermaCon(`?token_hash=${HASH}&type=email`);
    const { parametri, href } = destinazioneDi(risposta);
    expect(eCodiceDelVocabolario(parametri.get("errore"))).toBe(true);
    expect(parametri.get("errore")).toBe("conferma-non-riuscita");
    expect(href).not.toInclude("Database");
  });

  it("senza configurazione Supabase non verifica e lo dice senza dettagli", async () => {
    clientServerAttivo = false;
    const risposta = await confermaCon(`?token_hash=${HASH}&type=email`);
    expect(destinazioneDi(risposta).parametri.get("errore")).toBe("configurazione-assente");
  });
});

// ---------------------------------------------------------------------------
// /auth/recupero e /auth/accesso: recupero password e magic link con token_hash
// ---------------------------------------------------------------------------

const recuperoCon = (query: string) =>
  recupero.GET(new NextRequest(`https://vinea.test/auth/recupero${query}`));
const accessoCon = (query: string) =>
  accesso.GET(new NextRequest(`https://vinea.test/auth/accesso${query}`));

describe("/auth/recupero — eseguito", () => {
  it("un link valido apre la sessione di recupero dal server, senza code_verifier", async () => {
    const risposta = await recuperoCon(`?token_hash=pkce_${HASH}&type=recovery`);
    expect(soloNome("verifyOtp")).toEqual([
      { nome: "verifyOtp", argomenti: [{ token_hash: `pkce_${HASH}`, type: "recovery" }] },
    ]);
    expect(soloNome("exchangeCodeForSession")).toEqual([]);
    expect(risposta.status).toBe(303);
    const { percorso, href } = destinazioneDi(risposta);
    expect(percorso).toBe("/reimposta-password");
    expect(href).not.toInclude("token_hash");
    expect(href).not.toInclude(HASH);
    expect(risposta.headers.get("cache-control")).toInclude("no-store");
  });

  it("la destinazione è una costante: né next né redirect_to la cambiano", async () => {
    const redirectTo = encodeURIComponent("https://evil.example/auth/callback?next=%2Fvendite");
    const risposta = await recuperoCon(
      `?token_hash=${HASH}&type=recovery&next=%2Fadmin&redirect_to=${redirectTo}`,
    );
    const { percorso, href } = destinazioneDi(risposta);
    expect(percorso).toBe("/reimposta-password");
    expect(href.startsWith("https://vinea.test/")).toBe(true);
    expect(href).not.toInclude("evil.example");
  });

  it("link scaduto o già usato: la pagina di recupero con il motivo, mai /accedi", async () => {
    verificaFallisce = { code: "otp_expired", status: 403, message: "Email link is invalid or has expired" };
    const risposta = await recuperoCon(`?token_hash=${HASH}&type=recovery`);
    const { percorso, parametri, href } = destinazioneDi(risposta);
    expect(percorso).toBe("/reimposta-password");
    expect(parametri.get("errore")).toBe("recupero-link-non-valido");
    expect(href).not.toInclude("expired");
    expect(href).not.toInclude(HASH);
  });

  it("un link malformato o di un altro tipo non raggiunge il provider", async () => {
    for (const query of [
      "",
      "?type=recovery",
      `?token_hash=${HASH}`,
      "?token_hash=non-esadecimale&type=recovery",
      `?token_hash=${HASH.slice(0, 10)}&type=recovery`,
      `?token_hash=${HASH}&type=email`,
      `?token_hash=${HASH}&type=signup`,
      `?token_hash=${HASH}&type=magiclink`,
    ]) {
      const risposta = await recuperoCon(query);
      expect(destinazioneDi(risposta).parametri.get("errore")).toBe("recupero-link-non-valido");
    }
    expect(soloNome("verifyOtp")).toEqual([]);
  });

  it("un errore sconosciuto del provider resta un codice nostro", async () => {
    verificaFallisce = { status: 500, message: "Database error: dettaglio interno" };
    const risposta = await recuperoCon(`?token_hash=${HASH}&type=recovery`);
    const { parametri, href } = destinazioneDi(risposta);
    expect(parametri.get("errore")).toBe("sessione-recupero-assente");
    expect(href).not.toInclude("Database");
  });
});

describe("/auth/accesso — eseguito", () => {
  it("un magic link valido apre la sessione dal server e segue il next del template", async () => {
    const redirectTo = encodeURIComponent(
      "https://evil.example/auth/callback?superficie=accedi&next=%2Fcantina",
    );
    const risposta = await accessoCon(`?token_hash=${HASH}&type=magiclink&redirect_to=${redirectTo}`);
    expect(soloNome("verifyOtp")).toEqual([
      { nome: "verifyOtp", argomenti: [{ token_hash: HASH, type: "magiclink" }] },
    ]);
    expect(soloNome("exchangeCodeForSession")).toEqual([]);
    const { percorso, href } = destinazioneDi(risposta);
    expect(percorso).toBe("/cantina");
    expect(href.startsWith("https://vinea.test/")).toBe(true);
    expect(href).not.toInclude("evil.example");
    expect(href).not.toInclude("token_hash");
  });

  it("senza destinazione valida porta a /home", async () => {
    const risposta = await accessoCon(`?token_hash=${HASH}&type=magiclink&next=%2F%2Fevil.example`);
    expect(destinazioneDi(risposta).percorso).toBe("/home");
  });

  it("link scaduto o già usato: /accedi con il motivo e la destinazione", async () => {
    verificaFallisce = { code: "otp_expired", status: 403, message: "Email link is invalid or has expired" };
    const risposta = await accessoCon(`?token_hash=${HASH}&type=magiclink&next=%2Fcantina`);
    const { percorso, parametri } = destinazioneDi(risposta);
    expect(percorso).toBe("/accedi");
    expect(parametri.get("errore")).toBe("accesso-link-non-valido");
    expect(parametri.get("next")).toBe("/cantina");
  });

  it("un tipo diverso dal magic link non raggiunge il provider", async () => {
    for (const tipo of ["recovery", "email", "signup", "invite", "email_change"]) {
      const risposta = await accessoCon(`?token_hash=${HASH}&type=${tipo}`);
      expect(destinazioneDi(risposta).parametri.get("errore")).toBe("accesso-link-non-valido");
    }
    expect(soloNome("verifyOtp")).toEqual([]);
  });

  it("senza configurazione Supabase non verifica e lo dice senza dettagli", async () => {
    clientServerAttivo = false;
    const risposta = await accessoCon(`?token_hash=${HASH}&type=magiclink`);
    expect(destinazioneDi(risposta).parametri.get("errore")).toBe("configurazione-assente");
  });
});

// ---------------------------------------------------------------------------
// Step-up auth: conferma d'identità prima di un prelievo
// ---------------------------------------------------------------------------

const EMAIL_UTENTE = { id: "u-1", email: "a@vinea.test", identities: [{ provider: "email" }] };
const GOOGLE_UTENTE = { id: "u-2", email: "g@vinea.test", identities: [{ provider: "google" }] };

describe("riautenticaConPassword — eseguito", () => {
  it("usa l'email della sessione e apre una sessione nuova con una sola chiamata", async () => {
    utenteSessione = EMAIL_UTENTE;
    const esito = await supabaseAuthService.riautenticaConPassword("giusta-123");
    expect(esito).toEqual({ ok: true, data: undefined });
    const accessi = soloNome("signInWithPassword");
    expect(accessi.length).toBe(1);
    expect(accessi[0]?.argomenti[0]).toEqual({ email: "a@vinea.test", password: "giusta-123" });
  });

  it("password sbagliata: un codice del vocabolario, mai il testo del provider", async () => {
    utenteSessione = EMAIL_UTENTE;
    erroreProvider = { message: "Invalid login credentials", status: 400 };
    const esito = await supabaseAuthService.riautenticaConPassword("sbagliata");
    expect(esito).toEqual({ ok: false, error: "credenziali-non-valide" });
  });

  it("senza sessione non tenta un accesso: non c'è un'identità da confermare", async () => {
    const esito = await supabaseAuthService.riautenticaConPassword("qualunque");
    expect(esito.ok).toBe(false);
    if (!esito.ok) expect(eCodiceDelVocabolario(esito.error)).toBe(true);
    expect(soloNome("signInWithPassword").length).toBe(0);
  });

  it("un accesso che restituisce un altro utente non vale come conferma", async () => {
    utenteSessione = EMAIL_UTENTE;
    idDopoLogin = "u-altro";
    const esito = await supabaseAuthService.riautenticaConPassword("giusta-123");
    expect(esito.ok).toBe(false);
  });
});

describe("metodiRiautenticazione — eseguito", () => {
  it("chiede le identità al server e per un account Google non offre la password", async () => {
    utenteServer = GOOGLE_UTENTE;
    const metodi = await supabaseAuthService.metodiRiautenticazione();
    expect(soloNome("getUser").length).toBe(1);
    expect(metodi).toEqual({ email: "g@vinea.test", password: false, oauth: ["google"] });
  });

  it("account email/password: solo la password", async () => {
    utenteServer = EMAIL_UTENTE;
    expect(await supabaseAuthService.metodiRiautenticazione()).toEqual({
      email: "a@vinea.test",
      password: true,
      oauth: [],
    });
  });

  it("senza utente lato server: nessun metodo, non un'ipotesi", async () => {
    expect(await supabaseAuthService.metodiRiautenticazione()).toBeNull();
  });
});

describe("conferma con provider — rientro sul saldo", () => {
  it("il giro OAuth chiede di rientrare su /account passando dalla callback", async () => {
    await supabaseAuthService.accediConOAuth("google", { next: "/account" });
    const { options } = soloNome("signInWithOAuth")[0]?.argomenti[0] as {
      options: { redirectTo: string };
    };
    const url = new URL(options.redirectTo);
    expect(url.pathname).toBe("/auth/callback");
    expect(url.searchParams.get("next")).toBe("/account");
  });

  it("la callback, scambiato il code, riporta l'utente sulla pagina del saldo", async () => {
    const risposta = await chiama("?code=valido&next=%2Faccount");
    expect(destinazioneDi(risposta).percorso).toBe("/account");
  });
});

// ---------------------------------------------------------------------------
// Il resto del servizio (VPM-018-UI-TEST-01). Qui e non in un file a parte: questo è
// l'unico file che sostituisce `@/lib/supabase/client` per il servizio di autenticazione.
// ---------------------------------------------------------------------------

const ERRORE_INTERNO = { message: 'relation "auth.users" violates something at host db.interno', status: 500 };
const nonEspone = (esito: unknown) => expect(JSON.stringify(esito)).not.toContain("db.interno");

describe("registra — eseguito", () => {
  const dati = { email: "n@vinea.test", password: "Segreta1!", dataNascita: "1990-01-02", username: "nuovo" };

  it("una sola chiamata, con età e nome nei metadati e il rientro dalla callback", async () => {
    registrazione = { user: { id: "u-1", email_confirmed_at: null }, session: null };
    const esito = await supabaseAuthService.registra(dati);

    const inviti = soloNome("signUp");
    expect(inviti.length).toBe(1);
    const { options, email, password } = inviti[0]?.argomenti[0] as {
      email: string;
      password: string;
      options: { data: unknown; emailRedirectTo: string };
    };
    expect({ email, password }).toEqual({ email: dati.email, password: dati.password });
    expect(options.data).toEqual({ username: "nuovo", dob: "1990-01-02" });
    expect(new URL(options.emailRedirectTo).pathname).toBe("/auth/callback");
    expect(esito).toEqual({
      ok: true,
      data: { userId: "u-1", sessioneAttiva: false, confermaEmailRichiesta: true },
    });
  });

  it("con l'auto-conferma non chiede di aspettare un'email che non arriverà", async () => {
    registrazione = { user: { id: "u-2", email_confirmed_at: "2026-11-04T00:00:00Z" }, session: null };
    const esito = await supabaseAuthService.registra(dati);
    expect(esito).toEqual({
      ok: true,
      data: { userId: "u-2", sessioneAttiva: false, confermaEmailRichiesta: false },
    });
  });

  it("con una sessione già aperta l'utente è dentro e non deve confermare", async () => {
    registrazione = { user: { id: "u-3", email_confirmed_at: null }, session: {} };
    const esito = await supabaseAuthService.registra(dati);
    expect(esito).toEqual({
      ok: true,
      data: { userId: "u-3", sessioneAttiva: true, confermaEmailRichiesta: false },
    });
  });

  it("un rifiuto del provider è un codice, mai il suo testo", async () => {
    erroreProvider = ERRORE_INTERNO;
    const esito = await supabaseAuthService.registra(dati);
    expect(esito.ok).toBe(false);
    if (!esito.ok) expect(eCodiceDelVocabolario(esito.error)).toBe(true);
    nonEspone(esito);
  });

  it("una risposta senza utente non è un successo", async () => {
    expect(await supabaseAuthService.registra(dati)).toEqual({ ok: false, error: "generico" });
  });

  it("senza configurazione non parte alcuna chiamata", async () => {
    clientBrowserAttivo = false;
    expect(await supabaseAuthService.registra(dati)).toEqual({ ok: false, error: "configurazione-assente" });
    expect(chiamate).toEqual([]);
  });
});

describe("verificaEmail — eseguito", () => {
  it("verifica il token come conferma di registrazione, e nient'altro", async () => {
    expect(await supabaseAuthService.verificaEmail("hash-1")).toEqual({ ok: true, data: undefined });
    expect(soloNome("verifyOtp")[0]?.argomenti[0]).toEqual({ token_hash: "hash-1", type: "signup" });
  });

  it("un link rifiutato è un codice, mai il testo del provider", async () => {
    erroreProvider = ERRORE_INTERNO;
    const esito = await supabaseAuthService.verificaEmail("hash-1");
    expect(esito.ok).toBe(false);
    if (!esito.ok) expect(eCodiceDelVocabolario(esito.error)).toBe(true);
    nonEspone(esito);
  });
});

describe("login — eseguito", () => {
  it("restituisce l'identità della sessione e una chiamata sola", async () => {
    idDopoLogin = "u-9";
    expect(await supabaseAuthService.login("a@vinea.test", "Segreta1!")).toEqual({ ok: true, data: { userId: "u-9" } });
    expect(soloNome("signInWithPassword").length).toBe(1);
  });

  it("credenziali errate producono il codice dedicato", async () => {
    erroreProvider = { message: "Invalid login credentials", status: 400, code: "invalid_credentials" };
    expect(await supabaseAuthService.login("a@vinea.test", "x")).toEqual({
      ok: false,
      error: "credenziali-non-valide",
    });
  });

  it("un guasto interno non arriva all'utente", async () => {
    erroreProvider = ERRORE_INTERNO;
    const esito = await supabaseAuthService.login("a@vinea.test", "x");
    expect(esito.ok).toBe(false);
    if (!esito.ok) expect(eCodiceDelVocabolario(esito.error)).toBe(true);
    nonEspone(esito);
  });

  it("senza configurazione non parte alcuna chiamata", async () => {
    clientBrowserAttivo = false;
    expect(await supabaseAuthService.login("a@vinea.test", "x")).toEqual({
      ok: false,
      error: "configurazione-assente",
    });
    expect(chiamate).toEqual([]);
  });
});

describe("inviaMagicLink — eseguito", () => {
  it("invia una sola richiesta con il rientro dalla callback", async () => {
    expect(await supabaseAuthService.inviaMagicLink("a@vinea.test")).toEqual({ ok: true, data: undefined });
    const invio = soloNome("signInWithOtp");
    expect(invio.length).toBe(1);
    const { email, options } = invio[0]?.argomenti[0] as { email: string; options: { emailRedirectTo: string } };
    expect(email).toBe("a@vinea.test");
    expect(new URL(options.emailRedirectTo).pathname).toBe("/auth/callback");
  });

  it("un rifiuto è un codice, mai il testo del provider", async () => {
    erroreProvider = ERRORE_INTERNO;
    const esito = await supabaseAuthService.inviaMagicLink("a@vinea.test");
    expect(esito).toEqual({ ok: false, error: "magic-link-non-inviato" });
    nonEspone(esito);
  });
});

describe("logout e utenteCorrente — eseguiti", () => {
  it("logout chiude la sessione una volta sola", async () => {
    await supabaseAuthService.logout();
    expect(soloNome("signOut").length).toBe(1);
  });

  it("logout senza configurazione non lancia e non chiama nulla", async () => {
    clientBrowserAttivo = false;
    await supabaseAuthService.logout();
    expect(chiamate).toEqual([]);
  });

  it("senza sessione non c'è un utente corrente", async () => {
    expect(await supabaseAuthService.utenteCorrente()).toBeNull();
  });

  it("con una sessione restituisce solo identificativo ed email", async () => {
    utenteSessione = { id: "u-5", email: "c@vinea.test", identities: [] };
    expect(await supabaseAuthService.utenteCorrente()).toEqual({ userId: "u-5", email: "c@vinea.test" });
  });

  it("un'email assente resta null, non una stringa inventata", async () => {
    utenteSessione = { id: "u-6", email: null, identities: [] };
    expect(await supabaseAuthService.utenteCorrente()).toEqual({ userId: "u-6", email: null });
  });
});

describe("ruoliProfilo — eseguito", () => {
  it("legge la sola colonna del ruolo, sulla riga dell'utente richiesto", async () => {
    ruoliFinti = { data: [{ role: "admin" }, { role: "venditore" }], error: null };
    expect(await supabaseAuthService.ruoliProfilo("u-7")).toEqual({ ok: true, data: ["admin", "venditore"] });
    expect(soloNome("from")[0]?.argomenti).toEqual(["user_roles", "role", "user_id", "u-7"]);
  });

  it("un valore non testuale non diventa mai un ruolo", async () => {
    ruoliFinti = { data: [{ role: null }, { role: 7 }, { role: "user" }], error: null };
    expect(await supabaseAuthService.ruoliProfilo("u-7")).toEqual({ ok: true, data: ["user"] });
  });

  it("una lettura fallita è un codice fisso, senza il testo del database", async () => {
    ruoliFinti = { data: null, error: { message: "permission denied at db.interno" } };
    const esito = await supabaseAuthService.ruoliProfilo("u-7");
    expect(esito).toEqual({ ok: false, error: "ruoli-non-letti" });
    nonEspone(esito);
  });

  it("senza configurazione non legge nulla", async () => {
    clientBrowserAttivo = false;
    expect(await supabaseAuthService.ruoliProfilo("u-7")).toEqual({ ok: false, error: "configurazione-assente" });
    expect(chiamate).toEqual([]);
  });
});
