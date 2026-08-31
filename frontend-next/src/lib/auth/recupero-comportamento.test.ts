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
let erroreProvider: { message?: string; status?: number } | null = null;

/** `null` riproduce il progetto senza configurazione. */
let clientBrowserAttivo = true;

const registra = (nome: string, ...argomenti: readonly unknown[]) => {
  chiamate.push({ nome, argomenti });
  return Promise.resolve({ data: { url: null }, error: erroreProvider });
};

const clientBrowser = {
  auth: {
    resetPasswordForEmail: (email: string, opzioni?: unknown) =>
      registra("resetPasswordForEmail", email, opzioni),
    updateUser: (attributi: unknown) => registra("updateUser", attributi),
    signInWithOAuth: (parametri: unknown) => registra("signInWithOAuth", parametri),
  },
};

mock.module("@/lib/supabase/client", () => ({
  getSupabaseClient: () => (clientBrowserAttivo ? clientBrowser : null),
}));

/** Esito dello scambio del code, deciso dal singolo caso. */
let scambioFallisce: { message: string } | null = null;
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
          },
        }
      : null,
}));

const { supabaseAuthService } = await import("@/services/auth-service");
const { GET } = await import("@/app/auth/callback/route");

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
  clientBrowserAttivo = true;
  clientServerAttivo = true;
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
    // Il provider risponde ok in entrambi i casi, ed è l'unica cosa che il
    // servizio riferisce: non c'è alcun ramo che possa dire «non esiste».
    const noto = await supabaseAuthService.inviaRecuperoPassword("noto@esempio.it");
    const ignoto = await supabaseAuthService.inviaRecuperoPassword("mai-visto@esempio.it");
    expect(ignoto).toEqual(noto);
    expect(soloNome("resetPasswordForEmail").length).toBe(2);
  });

  it("il testo del provider non esce dal servizio", async () => {
    erroreProvider = { message: "User with this email address not found in project" };
    const esito = await supabaseAuthService.inviaRecuperoPassword("chi@esempio.it");

    expect(esito.ok).toBe(false);
    if (esito.ok) return;
    expect(eCodiceDelVocabolario(esito.error)).toBe(true);
    expect(esito.error).toBe("recupero-non-inviato");
    expect(String(esito.error)).not.toInclude("not found");
  });

  it("un limite di frequenza resta riconoscibile, perché l'azione utile è diversa", async () => {
    erroreProvider = { status: 429, message: "email rate limit exceeded" };
    const esito = await supabaseAuthService.inviaRecuperoPassword("chi@esempio.it");
    expect(esito).toEqual({ ok: false, error: "troppi-tentativi" });
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

  it("una password rifiutata perché debole lo dice", async () => {
    erroreProvider = { message: "Password should be at least 6 characters" };
    const esito = await supabaseAuthService.aggiornaPasswordNuova("corta");
    expect(esito).toEqual({ ok: false, error: "password-troppo-debole" });
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
