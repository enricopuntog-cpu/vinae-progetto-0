import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  CODICI_ERRORE_AUTH,
  MESSAGGI_ERRORE_AUTH,
  classificaErroreAuth,
  messaggioErroreAuth,
} from "@/lib/auth/errori-auth";
import { PERCORSO_REIMPOSTA_PASSWORD, urlRitornoAuth } from "@/lib/auth/ritorno-auth";

/**
 * Consenso alla registrazione con Google, recupero password e impostazione di
 * una password su un account nato social.
 *
 * Stessa forma delle prove di `flusso-ingresso.test.ts`, e per la stessa
 * ragione: quasi tutto ciò che va garantito qui è **un'assenza** — che il giro
 * dal provider non parta senza consenso, che nessuna pagina dica se un
 * indirizzo è registrato, che nessuna password venga scritta o registrata da
 * qualche parte. Un'assenza non si dimostra rendendo il caso a cui si è
 * pensato: si dimostra mostrando che il codice non ha il modo di produrla.
 */

const leggi = (percorso: string) => readFileSync(join(process.cwd(), percorso), "utf8");

/** I divieti si verificano sul codice vivo, non sui commenti che li spiegano. */
const senzaCommenti = (sorgente: string) =>
  sorgente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

const ACCEDI = leggi("src/app/accedi/page-client.tsx");
const REGISTRATI = leggi("src/app/registrati/page-client.tsx");
const SOCIAL = leggi("src/components/vinea/SocialAuthButtons.tsx");
const SERVIZIO = leggi("src/services/auth-service.ts");
const REIMPOSTA = leggi("src/app/reimposta-password/page-client.tsx");
const REIMPOSTA_PAGINA = leggi("src/app/reimposta-password/page.tsx");
const SICUREZZA = leggi("src/app/account/sicurezza-account.tsx");
const ACCOUNT = leggi("src/app/account/page-client.tsx");
const CALLBACK = leggi("src/app/auth/callback/route.ts");

describe("registrazione con Google: il consenso viene prima del provider", () => {
  it("il gesto social è bloccabile dalla superficie che lo ospita", () => {
    const codice = senzaCommenti(SOCIAL);
    expect(codice).toInclude("consensoMancante");
    expect(codice).toInclude("const bloccato = consensoMancante !== null");
  });

  it("senza consenso il servizio OAuth non viene mai chiamato", () => {
    const codice = senzaCommenti(SOCIAL);
    // La guardia sta *prima* della chiamata, non solo sul pulsante: `disabled`
    // è una proprietà del DOM, e ciò che non deve accadere è che il giro parta.
    // `lastIndexOf`: nel file c'è anche il `return (` dell'icona SVG, che sta
    // prima di `avvia` e produrrebbe una fetta vuota.
    const corpo = codice.slice(codice.indexOf("const avvia ="), codice.lastIndexOf("return ("));
    const guardia = corpo.indexOf("if (bloccato) return");
    const chiamata = corpo.indexOf("authAccediConOAuth(");
    expect(guardia).toBeGreaterThan(-1);
    expect(chiamata).toBeGreaterThan(guardia);
  });

  it("il pulsante è disabilitato e dice perché, in modo leggibile da uno screen reader", () => {
    expect(SOCIAL).toInclude("disabled={avvio !== null || bloccato}");
    expect(SOCIAL).toInclude('aria-describedby={bloccato ? "social-consenso-mancante" : undefined}');
    expect(SOCIAL).toInclude('id="social-consenso-mancante"');
  });

  it("con il consenso concesso parte una sola chiamata OAuth", () => {
    const codice = senzaCommenti(SOCIAL);
    // `lastIndexOf`: nel file c'è anche il `return (` dell'icona SVG, che sta
    // prima di `avvia` e produrrebbe una fetta vuota.
    const corpo = codice.slice(codice.indexOf("const avvia ="), codice.lastIndexOf("return ("));
    // Una sola chiamata nel corpo, e un `if (avvio) return` che impedisce al
    // secondo click di aggiungerne un'altra mentre la prima è in volo.
    expect((corpo.match(/authAccediConOAuth\(/g) ?? []).length).toBe(1);
    expect(corpo).toInclude("if (avvio) return");
  });

  it("/registrati passa la casella già esistente, senza aggiungerne una seconda", () => {
    expect(REGISTRATI).toInclude("consensoMancante={");
    expect(REGISTRATI).toInclude("terms\n                ? null");
    // Una sola ConsentCheckbox in pagina: il consenso riguarda la creazione
    // dell'account, non il metodo scelto per crearlo.
    expect((REGISTRATI.match(/<ConsentCheckbox/g) ?? []).length).toBe(1);
    // E la stessa casella continua a chiudere l'invio del form email.
    expect(senzaCommenti(REGISTRATI)).toMatch(/dobError === null &&\s*terms;/);
  });

  it("il testo del consenso dice che vale per entrambi i metodi", () => {
    expect(REGISTRATI).toInclude("qualsiasi metodo, email o");
  });

  it("/accedi non chiede di nuovo il consenso: rientrare non è creare", () => {
    const social = ACCEDI.slice(ACCEDI.indexOf("<SocialAuthButtons"));
    expect(social).not.toInclude("consensoMancante");
    expect(ACCEDI).not.toInclude("<ConsentCheckbox");
  });
});

describe("recupero password: contratto del servizio", () => {
  it("usa Supabase Auth e non una custodia propria della password", () => {
    const codice = senzaCommenti(SERVIZIO);
    expect(codice).toInclude("supabase.auth.resetPasswordForEmail(");
    expect(codice).toInclude("supabase.auth.updateUser({ password })");
    // Nessuna password verso una tabella di questo progetto, e nessun hash
    // calcolato qui: l'unico posto in cui la password esiste è Supabase Auth.
    expect(codice).not.toMatch(/from\("profiles"\)[\s\S]{0,200}password/);
    expect(codice).not.toMatch(/\.(insert|update|upsert)\([^)]*password/);
    // `token_hash` della verifica email è un'altra cosa: qui si cerca una
    // custodia propria della password, cioè un hash calcolato da noi.
    expect(codice).not.toMatch(/bcrypt|scrypt|argon|passwordHash|password_hash/i);
  });

  it("nessuna password viene registrata in un log", () => {
    for (const sorgente of [SERVIZIO, REIMPOSTA, SICUREZZA]) {
      const codice = senzaCommenti(sorgente);
      expect(codice).not.toMatch(/console\.(log|error|warn|info|debug)\([^)]*password/i);
    }
  });

  it("ogni ramo d'errore passa dal classificatore, mai il messaggio del provider", () => {
    const codice = senzaCommenti(SERVIZIO);
    const recupero = codice.slice(
      codice.indexOf("async inviaRecuperoPassword"),
      codice.indexOf("async accediConOAuth"),
    );
    expect(recupero).toInclude('classificaErroreAuth(error, "recupero-password")');
    expect(recupero).toInclude('classificaErroreAuth(error, "aggiornamento-password")');
    expect(recupero).not.toMatch(/error:\s*error\.message/);
  });

  it("i nuovi codici stanno nel vocabolario chiuso e hanno un testo italiano", () => {
    for (const codice of [
      "recupero-non-inviato",
      "sessione-recupero-assente",
      "password-non-aggiornata",
      "password-troppo-debole",
    ] as const) {
      expect(CODICI_ERRORE_AUTH as readonly string[]).toContain(codice);
      expect(MESSAGGI_ERRORE_AUTH[codice].length).toBeGreaterThan(10);
    }
  });

  it("un link scaduto diventa «richiedine uno nuovo», non «riprova»", () => {
    // Il testo di Supabase per una sessione assente/scaduta cade nella famiglia
    // che suggerisce l'unica azione utile.
    for (const messaggio of ["Auth session missing!", "JWT expired", "otp_expired"]) {
      expect(classificaErroreAuth({ message: messaggio }, "aggiornamento-password")).toBe(
        "sessione-recupero-assente",
      );
    }
  });

  it("una password rifiutata perché debole lo dice, invece di un generico riprova", () => {
    expect(
      classificaErroreAuth({ message: "Password should be at least 6 characters" }, "aggiornamento-password"),
    ).toBe("password-troppo-debole");
    expect(classificaErroreAuth({ message: "weak_password" }, "aggiornamento-password")).toBe(
      "password-troppo-debole",
    );
  });

  it("un errore non riconosciuto resta un messaggio nostro e non nomina Supabase", () => {
    for (const operazione of ["recupero-password", "aggiornamento-password"] as const) {
      const codice = classificaErroreAuth({ message: "boom internal x" }, operazione);
      const testo = messaggioErroreAuth(codice);
      expect(testo).not.toMatch(/supabase|postgres|pgrst|jwt|token|null/i);
      expect(testo).toMatch(/[a-z]/);
    }
  });
});

describe("ritorno del link di recupero: nessuna seconda porta", () => {
  it("il recupero rientra dalla callback esistente, come next", () => {
    const codice = senzaCommenti(SERVIZIO);
    expect(codice).toInclude("urlRitornoAuthDalBrowser({ next: PERCORSO_REIMPOSTA_PASSWORD })");
  });

  it("l'URL prodotto punta alla callback e porta la destinazione validata", () => {
    const url = urlRitornoAuth("https://vinea.example", { next: PERCORSO_REIMPOSTA_PASSWORD });
    expect(url).toBe("https://vinea.example/auth/callback?next=%2Freimposta-password");
  });

  it("una destinazione assoluta non sopravvive: niente open redirect", () => {
    for (const ostile of [
      "https://malizia.example/ruba",
      "//malizia.example",
      "http://localhost:3000/altro",
    ]) {
      const url = urlRitornoAuth("https://vinea.example", { next: ostile });
      expect(url).toBe("https://vinea.example/auth/callback");
      expect(url).not.toInclude("malizia.example");
    }
  });

  it("la callback non è stata riscritta per il recupero", () => {
    // L'unico ramo dedicato è il ritorno d'errore, che riporta il recupero
    // sulla propria superficie invece di abbandonarlo su /accedi (provato
    // eseguendo la route in `recupero-comportamento.test.ts`). Il percorso di
    // successo resta uno solo: nessun secondo punto di scambio del code.
    expect(CALLBACK).toInclude("exchangeCodeForSession(code)");
    expect(CALLBACK).not.toInclude("recovery");
    expect((CALLBACK.match(/exchangeCodeForSession/g) ?? []).length).toBe(1);
    // E l'origine resta decisa dal server, non dedotta dalla richiesta.
    expect(CALLBACK).toInclude("risolviOriginePubblica(");
  });
});

describe("/accedi: password dimenticata senza enumerazione degli account", () => {
  it("offre il gesto e lo distingue dagli altri due in corso", () => {
    expect(ACCEDI).toInclude('data-testid="password-dimenticata"');
    expect(ACCEDI).toInclude('"password" | "magic-link" | "recupero" | null');
  });

  it("la conferma è neutra e non esiste un ramo che riveli l'esistenza dell'email", () => {
    expect(ACCEDI).toInclude("Se esiste un account associato a questa email");
    const codice = senzaCommenti(ACCEDI);
    expect(codice).not.toMatch(/non\s+(esiste|registrat|trovat)/i);
    expect(codice).not.toMatch(/user_not_found|email.*non.*registrata/i);
    // Un solo esito mostrato: `recuperoRichiesto` è un booleano, non un
    // verdetto sull'indirizzo.
    expect(codice).toInclude("setRecuperoRichiesto(true)");
  });

  it("il provider risponde ok anche per un indirizzo sconosciuto: nessuna distinzione a valle", () => {
    const corpo = senzaCommenti(ACCEDI).slice(
      senzaCommenti(ACCEDI).indexOf("const recupera ="),
      senzaCommenti(ACCEDI).indexOf("if (authLoading)"),
    );
    expect((corpo.match(/authInviaRecuperoPassword\(/g) ?? []).length).toBe(1);
    expect(corpo).toInclude("if (inCorso) return");
  });

  it("l'errore mostrato è tradotto, mai il testo del provider", () => {
    expect(ACCEDI).toInclude("messaggioErroreAuth(erroreRecupero)");
    expect(ACCEDI).toInclude('data-testid="errore-recupero"');
    expect(ACCEDI).toInclude('role="alert"');
  });

  it("il magic link e l'accesso con password non sono cambiati", () => {
    expect(ACCEDI).toInclude("authInviaMagicLink(email.trim(), { superficie: \"accedi\", next })");
    expect(ACCEDI).toInclude("authLogin(email.trim(), password)");
  });
});

describe("/reimposta-password", () => {
  it("la route esiste e non è indicizzabile", () => {
    expect(REIMPOSTA_PAGINA).toInclude("robots: { index: false, follow: false }");
    expect(PERCORSO_REIMPOSTA_PASSWORD).toBe("/reimposta-password");
  });

  it("valida lunghezza e coincidenza prima di permettere il salvataggio", () => {
    const codice = senzaCommenti(REIMPOSTA);
    expect(codice).toInclude("const LUNGHEZZA_MINIMA_PASSWORD = 6");
    expect(codice).toInclude("password.length >= LUNGHEZZA_MINIMA_PASSWORD");
    expect(codice).toInclude("password === conferma");
    expect(codice).toInclude("const valido = abbastanzaLunga && combaciano");
    expect(codice).toInclude("disabled={!valido || inCorso}");
  });

  it("il mismatch è un errore annunciato, non un pulsante che tace", () => {
    expect(REIMPOSTA).toInclude('data-testid="errore-mismatch"');
    expect(REIMPOSTA).toInclude("Le due password non coincidono.");
    expect(REIMPOSTA).toInclude("aria-invalid={mostraMismatch}");
  });

  it("il doppio invio non produce due aggiornamenti", () => {
    const corpo = senzaCommenti(REIMPOSTA).slice(
      senzaCommenti(REIMPOSTA).indexOf("const salva ="),
      senzaCommenti(REIMPOSTA).indexOf("if (authLoading)"),
    );
    const guardia = corpo.indexOf("if (inCorso) return");
    const chiamata = corpo.indexOf("authAggiornaPasswordNuova(");
    expect(guardia).toBeGreaterThan(-1);
    expect(chiamata).toBeGreaterThan(guardia);
    expect((corpo.match(/authAggiornaPasswordNuova\(/g) ?? []).length).toBe(1);
    expect(REIMPOSTA).toInclude("aria-busy={inCorso}");
  });

  it("una sessione di recupero assente porta a chiedere un link nuovo", () => {
    expect(REIMPOSTA).toInclude("if (!authUser)");
    // Il motivo lo riporta la callback quando c'è: lo scambio fallito e il
    // link mai aperto sono lo stesso vicolo cieco ma non la stessa frase.
    // Senza motivo resta quella di prima, e la CTA è la stessa in entrambi.
    expect(REIMPOSTA).toInclude(
      'messaggioErroreAuth(erroreRientro ?? "sessione-recupero-assente")',
    );
    // Il codice che arriva dall'URL è validato dal server contro il
    // vocabolario chiuso prima di scendere qui: la pagina non rende mai una
    // stringa scelta da chi ha costruito l'indirizzo.
    expect(senzaCommenti(REIMPOSTA_PAGINA)).toInclude("eCodiceErroreAuth(errore) ? errore : null");
    expect(REIMPOSTA).toInclude('data-testid="richiedi-nuovo-link"');
    expect(REIMPOSTA).toInclude('href="/accedi"');
  });

  it("il successo dice cosa fare dopo e non lascia la password in memoria", () => {
    expect(REIMPOSTA).toInclude('data-testid="password-aggiornata"');
    expect(REIMPOSTA).toInclude('href="/account"');
    const codice = senzaCommenti(REIMPOSTA);
    expect(codice).toMatch(/setPassword\(""\);\s*setConferma\(""\);\s*setFatto\(true\)/);
  });

  it("nessun messaggio grezzo del provider raggiunge la pagina", () => {
    const codice = senzaCommenti(REIMPOSTA);
    expect(codice).toInclude("messaggioErroreAuth(errore)");
    expect(codice).not.toMatch(/\{\s*(esito\.)?error(\.message)?\s*\}/);
    expect(codice).not.toMatch(/error\.message/);
  });

  it("non chiede la password attuale: un account Google non ne ha una", () => {
    const codice = senzaCommenti(REIMPOSTA);
    expect(codice).not.toMatch(/password.?(attuale|corrente|vecchia|precedente)/i);
    expect(codice).not.toInclude('autoComplete="current-password"');
  });
});

describe("/account — Sicurezza", () => {
  it("la sezione è montata nella pagina account", () => {
    expect(ACCOUNT).toInclude("<SicurezzaAccount />");
    expect(ACCOUNT).toInclude('import SicurezzaAccount from "./sicurezza-account"');
  });

  it("la CTA manda un link alla propria email e vale anche per gli account Google", () => {
    expect(SICUREZZA).toInclude('data-testid="imposta-cambia-password"');
    expect(SICUREZZA).toInclude("Imposta o cambia password");
    expect(SICUREZZA).toInclude("Riceverai un link alla tua email");
    expect(SICUREZZA).toInclude("Funziona anche");
    expect(SICUREZZA).toInclude("authInviaRecuperoPassword(email)");
  });

  it("l'indirizzo è quello della sessione, non un campo compilabile", () => {
    const codice = senzaCommenti(SICUREZZA);
    expect(codice).toInclude("const email = authUser?.email ?? null");
    expect(codice).not.toInclude("<Input");
  });

  it("nessun privilegio elevato e nessun reset amministrativo", () => {
    const codice = senzaCommenti(SICUREZZA);
    expect(codice).not.toMatch(/service_?role|admin|SERVICE_ROLE/i);
    expect(codice).not.toMatch(/auth\.admin/);
  });

  it("non indovina se una password esista già", () => {
    const codice = senzaCommenti(SICUREZZA);
    // Nessuna euristica sul provider dell'identità: la CTA è la stessa per
    // tutti, ed è ciò che la rende corretta per un account nato con Google.
    expect(codice).not.toMatch(/app_metadata|identities|provider\s*===/);
  });

  it("un doppio click non manda due email", () => {
    const codice = senzaCommenti(SICUREZZA);
    const corpo = codice.slice(codice.indexOf("const richiedi ="), codice.indexOf("return ("));
    expect(corpo).toInclude("if (inCorso || !email) return");
    expect((corpo.match(/authInviaRecuperoPassword\(/g) ?? []).length).toBe(1);
    expect(codice).toInclude("disabled={inCorso}");
  });
});
