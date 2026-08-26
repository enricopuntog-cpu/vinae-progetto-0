import { describe, expect, it } from "bun:test";
import {
  CODICI_ERRORE_AUTH,
  MESSAGGI_ERRORE_AUTH,
  classificaErroreAuth,
  classificaErroreProvider,
  codiceErroreAuth,
  eCodiceErroreAuth,
  messaggioErroreAuth,
  type CodiceErroreAuth,
} from "@/lib/auth/errori-auth";

/**
 * Il punto di questi casi non è che la classificazione sia esaustiva — non lo
 * è per scelta — ma che **nessun testo di terzi** riesca ad attraversare il
 * modulo. Un errore sconosciuto deve diventare un messaggio nostro, non il suo
 * stesso testo con una cornice intorno.
 */

// Testi reali restituiti da Supabase Auth e dai provider OAuth, tenuti qui
// perché ognuno è il caso che l'utente incontra davvero.
const TESTI_SUPABASE = {
  credenziali: "Invalid login credentials",
  emailNonValida: "Unable to validate email address: invalid format",
  rateLimit: "For security purposes, you can only request this after 51 seconds.",
  ignoto: "Database error saving new user (constraint profiles_username_key)",
} as const;

describe("vocabolario chiuso degli errori di autenticazione", () => {
  it("dà un messaggio a ogni codice, e nessun messaggio vuoto", () => {
    for (const codice of CODICI_ERRORE_AUTH) {
      const messaggio = MESSAGGI_ERRORE_AUTH[codice];
      expect(typeof messaggio).toBe("string");
      expect(messaggio.trim().length).toBeGreaterThan(0);
    }
    expect(Object.keys(MESSAGGI_ERRORE_AUTH).sort()).toEqual([...CODICI_ERRORE_AUTH].sort());
  });

  it("non nomina un provider: il codice non sa quale pulsante lo ha prodotto", () => {
    for (const messaggio of Object.values(MESSAGGI_ERRORE_AUTH)) {
      expect(messaggio.toLowerCase()).not.toInclude("google");
      expect(messaggio.toLowerCase()).not.toInclude("facebook");
      expect(messaggio.toLowerCase()).not.toInclude("supabase");
    }
  });

  it("non espone dettagli di configurazione a chi non può farci nulla", () => {
    // Il testo precedente per "non configurato" nominava le due variabili
    // d'ambiente e il percorso del file in cui metterle. Era scritto per chi
    // sviluppa e finiva davanti a chi usa il sito.
    for (const messaggio of Object.values(MESSAGGI_ERRORE_AUTH)) {
      expect(messaggio).not.toInclude("NEXT_PUBLIC_");
      expect(messaggio).not.toInclude(".env");
      expect(messaggio).not.toInclude("http");
    }
  });

  it("riconosce solo i codici del vocabolario", () => {
    for (const codice of CODICI_ERRORE_AUTH) expect(eCodiceErroreAuth(codice)).toBe(true);
    for (const estraneo of [null, undefined, 42, {}, "", "boom", "GENERICO", "oauth-"]) {
      expect(eCodiceErroreAuth(estraneo)).toBe(false);
    }
  });

  it("normalizza qualunque valore ricevuto da un URL in un codice nostro", () => {
    expect(codiceErroreAuth("oauth-annullato")).toBe("oauth-annullato");
    // Il caso che conta: un `?errore=` costruito a mano non diventa testo in
    // pagina, diventa il messaggio generico.
    for (const ostile of [
      "<script>alert(1)</script>",
      "Invalid login credentials",
      "https://evil.example",
      null,
      undefined,
    ]) {
      expect(codiceErroreAuth(ostile)).toBe("generico");
      expect(messaggioErroreAuth(ostile)).toBe(MESSAGGI_ERRORE_AUTH.generico);
    }
  });
});

describe("classificazione degli errori Supabase", () => {
  const casi: ReadonlyArray<
    readonly [string, Parameters<typeof classificaErroreAuth>[0], "login" | "magic-link", CodiceErroreAuth]
  > = [
    ["credenziali sbagliate", { message: TESTI_SUPABASE.credenziali }, "login", "credenziali-non-valide"],
    ["codice stabile equivalente", { code: "invalid_credentials" }, "login", "credenziali-non-valide"],
    ["email malformata", { message: TESTI_SUPABASE.emailNonValida }, "login", "email-non-valida"],
    ["rate limit testuale", { message: TESTI_SUPABASE.rateLimit }, "magic-link", "troppi-tentativi"],
    ["rate limit per status", { status: 429, message: "boom" }, "login", "troppi-tentativi"],
  ];

  for (const [nome, errore, operazione, atteso] of casi) {
    it(`riconosce: ${nome}`, () => {
      expect(classificaErroreAuth(errore, operazione)).toBe(atteso);
    });
  }

  it("un errore ignoto ricade sull'operazione, mai sul suo stesso testo", () => {
    const ignoto = { message: TESTI_SUPABASE.ignoto };
    expect(classificaErroreAuth(ignoto, "login")).toBe("generico");
    expect(classificaErroreAuth(ignoto, "registrazione")).toBe("generico");
    expect(classificaErroreAuth(ignoto, "magic-link")).toBe("magic-link-non-inviato");
    expect(classificaErroreAuth(ignoto, "oauth-avvio")).toBe("oauth-avvio-non-riuscito");
    expect(classificaErroreAuth(ignoto, "scambio-codice")).toBe("scambio-non-riuscito");
  });

  it("nessun frammento del testo Supabase sopravvive nel messaggio mostrato", () => {
    for (const testo of Object.values(TESTI_SUPABASE)) {
      const messaggio = messaggioErroreAuth(classificaErroreAuth({ message: testo }, "login"));
      expect(messaggio).not.toInclude("constraint");
      expect(messaggio).not.toInclude("profiles_");
      // Nessuna parola del testo originale, non solo nessuna copia integrale.
      for (const parola of testo.split(/\W+/).filter((p) => p.length > 6)) {
        expect(messaggio.toLowerCase()).not.toInclude(parola.toLowerCase());
      }
    }
  });

  it("sopravvive a un errore assente senza inventare una famiglia", () => {
    expect(classificaErroreAuth(null, "login")).toBe("generico");
    expect(classificaErroreAuth({}, "scambio-codice")).toBe("scambio-non-riuscito");
  });
});

describe("classificazione del rientro d'errore del provider OAuth", () => {
  it("separa l'annullamento dell'utente dal rifiuto", () => {
    // Annullare non è un guasto: dire "non è andata a buon fine" a chi ha
    // premuto Annulla lo manda a cercare un problema che non esiste.
    expect(classificaErroreProvider("access_denied", "The user denied the request")).toBe(
      "oauth-annullato",
    );
    expect(classificaErroreProvider(null, "User cancelled the sign-in flow")).toBe(
      "oauth-annullato",
    );
    expect(classificaErroreProvider("server_error", "Unexpected failure")).toBe("oauth-rifiutato");
    expect(classificaErroreProvider(null, null)).toBe("oauth-rifiutato");
  });

  it("non lascia passare la descrizione del provider dentro il messaggio", () => {
    const descrizione = "Error getting user profile from external provider: 502 Bad Gateway";
    const messaggio = messaggioErroreAuth(classificaErroreProvider("server_error", descrizione));
    expect(messaggio).not.toInclude("502");
    expect(messaggio).not.toInclude("Gateway");
    expect(messaggio).not.toInclude("provider:");
  });

  it("resta in famiglia oauth, così la pagina sa accanto a quale pulsante metterlo", () => {
    for (const [error, descrizione] of [
      ["access_denied", "denied"],
      ["server_error", "boom"],
      [null, null],
    ] as const) {
      expect(classificaErroreProvider(error, descrizione).startsWith("oauth-")).toBe(true);
    }
  });
});
