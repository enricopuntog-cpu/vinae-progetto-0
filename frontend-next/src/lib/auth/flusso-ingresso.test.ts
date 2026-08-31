import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { CODICI_ERRORE_AUTH } from "@/lib/auth/errori-auth";

/**
 * Il flusso di ingresso — /accedi, /registrati, i pulsanti social e la callback
 * — è fatto di pezzi che devono restare d'accordo fra loro. Sono prove di
 * contratto sulla sorgente e non prove di comportamento perché ciò che
 * garantiscono è **un'assenza**: che nessun testo di terzi arrivi in pagina,
 * che nessun errore finisca accanto al pulsante sbagliato, che nessuna
 * operazione parta due volte. Un'assenza non si osserva rendendo il componente
 * con l'unico caso a cui si è pensato; si osserva guardando che il codice non
 * abbia il modo di produrla.
 */

const leggi = (percorso: string) => readFileSync(join(process.cwd(), percorso), "utf8");

/**
 * I divieti vanno verificati sul codice vivo: spiegare in un commento perché
 * `error.message` non deve comparire non deve far fallire la verifica che
 * `error.message` non compare.
 */
const senzaCommenti = (sorgente: string) =>
  sorgente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

const CALLBACK = leggi("src/app/auth/callback/route.ts");
const ACCEDI = leggi("src/app/accedi/page-client.tsx");
const REGISTRATI = leggi("src/app/registrati/page-client.tsx");
const SOCIAL = leggi("src/components/vinea/SocialAuthButtons.tsx");
const SERVIZIO = leggi("src/services/auth-service.ts");

describe("errori sicuri: niente testo di terzi arriva all'utente", () => {
  it("il servizio non restituisce mai il messaggio di Supabase", () => {
    const codice = senzaCommenti(SERVIZIO);
    // Ogni ramo d'errore passa dal classificatore. `error.message` può ancora
    // essere letto per un log, ma non può essere il valore restituito.
    expect(codice).not.toMatch(/error:\s*error\.message/);
    expect(codice).not.toMatch(/error:\s*"[^"]*NEXT_PUBLIC/);
    const classificazioni = codice.match(/classificaErroreAuth\(/g) ?? [];
    expect(classificazioni.length).toBeGreaterThanOrEqual(5);
  });

  it("la callback mette nel redirect un codice, non un motivo", () => {
    const codice = senzaCommenti(CALLBACK);
    expect(codice).toInclude("new URLSearchParams({ errore: codice })");
    // Nessun ramo costruisce più il parametro a mano dal testo ricevuto.
    expect(codice).not.toInclude("encodeURIComponent(errorDescription)");
    expect(codice).not.toInclude("encodeURIComponent(error.message)");
    // E nessun modello di stringa della route trasporta un dettaglio tecnico.
    for (const modello of [...codice.matchAll(/`([^`]*)`/g)].map(([, m]) => m)) {
      expect(modello).not.toInclude("message");
      expect(modello).not.toInclude("descrizione");
      expect(modello).not.toInclude("erroreProvider");
    }
  });

  it("il dettaglio tecnico resta in un log del server", () => {
    const codice = senzaCommenti(CALLBACK);
    expect(codice).toInclude('console.error("[auth/callback]"');
    // Il dettaglio entra solo nel log: la funzione che costruisce il redirect
    // lo riceve come secondo argomento e non lo serializza.
    const corpo = codice.slice(codice.indexOf("const vaiAErrore"), codice.indexOf("const erroreProvider"));
    expect(corpo).toInclude("dettaglio");
    expect(corpo).not.toMatch(/parametri\.set\([^)]*dettaglio/);
  });

  it("ogni ramo della callback nomina un codice del vocabolario", () => {
    const citati = [...CALLBACK.matchAll(/vaiAErrore\(\s*"([^"]+)"/g)].map(([, c]) => c);
    expect(citati.length).toBeGreaterThanOrEqual(3);
    for (const codice of citati) {
      expect(CODICI_ERRORE_AUTH as readonly string[]).toContain(codice);
    }
  });

  it("le pagine mostrano messaggi tradotti, mai il valore ricevuto", () => {
    for (const pagina of [ACCEDI, REGISTRATI, SOCIAL]) {
      expect(pagina).toInclude("messaggioErroreAuth(");
      // Il difetto precedente, letteralmente: `{authError}` e `{erroreCallback}`
      // renderizzati come testo.
      expect(pagina).not.toMatch(/\{\s*authError\s*\}/);
      expect(pagina).not.toMatch(/\{\s*erroreCallback\s*\}/);
    }
  });

  it("le pagine validano il codice che arriva dall'URL", () => {
    for (const pagina of [ACCEDI, REGISTRATI]) {
      expect(pagina).toInclude("codiceErroreAuth(");
    }
  });
});

describe("superficie di partenza: l'errore torna dove è cominciato", () => {
  it("la callback ricorda da quale pagina si era partiti", () => {
    const codice = senzaCommenti(CALLBACK);
    expect(codice).toInclude("superficieAuthDa(searchParams.get(PARAMETRO_SUPERFICIE))");
    expect(codice).toInclude("PERCORSO_SUPERFICIE_AUTH[superficie]");
    // Il ritorno non è più una scelta fissa.
    expect(codice).not.toMatch(/vaiA\(\s*`\/accedi/);
  });

  it("ogni superficie dichiara la propria, e la manda al provider", () => {
    expect(ACCEDI).toInclude('superficie="accedi"');
    expect(ACCEDI).toInclude('{ superficie: "accedi", next }');
    expect(REGISTRATI).toInclude('superficie="registrati"');
    expect(REGISTRATI).toInclude('{ superficie: "registrati", next }');
  });
});

describe("destinazione: un solo contratto, relativo e validato", () => {
  it("chi legge un `next` lo fa passare dalla stessa funzione", () => {
    for (const sorgente of [CALLBACK, ACCEDI, REGISTRATI]) {
      expect(sorgente).toInclude("percorsoRelativoSicuro(");
      expect(sorgente).toInclude("PARAMETRO_NEXT");
    }
    // Nessuno costruisce un secondo nome per la stessa cosa.
    for (const sorgente of [senzaCommenti(ACCEDI), senzaCommenti(REGISTRATI)]) {
      expect(sorgente).not.toInclude('get("redirect")');
      expect(sorgente).not.toInclude('get("returnTo")');
    }
  });

  it("in mancanza di destinazione si torna a /home, non altrove", () => {
    for (const sorgente of [CALLBACK, ACCEDI, REGISTRATI]) {
      expect(sorgente).toInclude('?? "/home"');
    }
  });

  it("il login riuscito segue la destinazione invece di forzare /home", () => {
    expect(senzaCommenti(ACCEDI)).toInclude("router.push(destinazione)");
    expect(senzaCommenti(ACCEDI)).not.toInclude('router.push("/home")');
    expect(senzaCommenti(REGISTRATI)).not.toInclude('router.push("/home")');
  });

  it("nessuna superficie si fida di un URL assoluto ricevuto dal browser", () => {
    for (const sorgente of [senzaCommenti(ACCEDI), senzaCommenti(REGISTRATI), senzaCommenti(SOCIAL)]) {
      expect(sorgente).not.toInclude("window.location.origin");
      expect(sorgente).not.toInclude("document.referrer");
    }
  });

  it("il contesto viaggia in query, senza cookie né storage", () => {
    for (const sorgente of [senzaCommenti(ACCEDI), senzaCommenti(REGISTRATI), senzaCommenti(SOCIAL), senzaCommenti(SERVIZIO)]) {
      expect(sorgente).not.toInclude("localStorage");
      expect(sorgente).not.toInclude("sessionStorage");
      expect(sorgente).not.toInclude("document.cookie");
    }
  });
});

describe("entry point privati: chi ferma l'utente dice anche dove riportarlo", () => {
  /**
   * Un cancello che manda a `/accedi` nudo fa entrare l'utente e poi lo lascia
   * sulla Home, cioè non dove stava andando. Finché `/accedi` non leggeva
   * `next` quel parametro sarebbe stato una promessa non mantenuta; ora la
   * legge, e ometterlo è la promessa mancata.
   */
  const CANCELLI = [
    ["src/app/vendite/page.tsx", "/accedi", "%2Fvendite"],
    ["src/app/account/page-client.tsx", "/accedi", "%2Faccount"],
    ["src/app/cantina/page-client.tsx", "/registrati", "%2Fcantina"],
    ["src/app/completa-profilo/page-client.tsx", "/accedi", "%2Fcompleta-profilo"],
    ["src/app/vendi/page-client.tsx", "/registrati", "%2Fvendi"],
  ] as const;

  for (const [percorso, superficie, destinazione] of CANCELLI) {
    it(`${percorso} riporta a ${decodeURIComponent(destinazione)}`, () => {
      const codice = senzaCommenti(leggi(percorso));
      expect(codice).toInclude(`${superficie}?\${PARAMETRO_NEXT}=${destinazione}`);
      expect(codice).toInclude('PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth"');
      // Il difetto che questa prova impedisce di reintrodurre: il link nudo.
      expect(codice).not.toInclude(`href="${superficie}"`);
    });
  }

  it("la destinazione è scritta, non dedotta da un dato in arrivo", () => {
    // Ogni cancello conosce staticamente la propria pagina. Ricavarla
    // dall'URL della richiesta aprirebbe una porta che qui non serve.
    for (const [percorso] of CANCELLI) {
      const codice = senzaCommenti(leggi(percorso));
      expect(codice).not.toMatch(/PARAMETRO_NEXT\}=\$\{/);
    }
  });
});

describe("Google: la superficie decide il testo, e l'errore resta suo", () => {
  const codice = senzaCommenti(SOCIAL);

  it("dice cosa sta per succedere, non quale marchio si apre", () => {
    expect(codice).toInclude('accedi: "Continua con Google"');
    expect(codice).toInclude('registrati: "Registrati con Google"');
    expect(codice).toInclude("ETICHETTA_GOOGLE[superficie]");
  });

  it("durante l'apertura il pulsante è chiuso e lo dichiara", () => {
    // `|| bloccato`: la stessa proprietà porta ora anche il consenso mancante
    // su /registrati. Il gesto in volo resta la prima delle due ragioni per
    // cui il pulsante è spento — vedi `recupero-password.test.ts`.
    expect(codice).toInclude("disabled={avvio !== null || bloccato}");
    expect(codice).toInclude('aria-busy={avvio === "google"}');
    expect(codice).toInclude("if (avvio) return;");
  });

  it("dopo un fallimento si può riprovare subito", () => {
    // Il riavvio è possibile solo se lo stato di avvio viene rilasciato: senza,
    // un errore lascerebbe il pulsante spento per sempre.
    const fallimento = codice.slice(codice.indexOf("if (!esito.ok)"));
    expect(fallimento).toInclude("setErrore(esito.error)");
    expect(fallimento).toInclude("setAvvio(null)");
  });

  it("l'errore social vive accanto ai pulsanti social", () => {
    expect(codice).toInclude('data-testid="errore-oauth"');
    // E le pagine gli passano solo i codici della sua famiglia.
    for (const pagina of [ACCEDI, REGISTRATI]) {
      expect(pagina).toInclude('erroreRitorno.startsWith("oauth-")');
      expect(pagina).toInclude("erroreIniziale={erroreSocialIniziale}");
    }
  });

  it("un errore superato non riappare perché il parametro è ancora nell'URL", () => {
    expect(codice).toInclude("scartato");
    expect(codice).toInclude("setScartato(true)");
    for (const pagina of [senzaCommenti(ACCEDI), senzaCommenti(REGISTRATI)]) {
      expect(pagina).toInclude("ritornoScartato");
      expect(pagina).toInclude("setRitornoScartato(true)");
    }
  });
});

describe("coordinamento: si sa quale operazione è in corso", () => {
  const codice = senzaCommenti(ACCEDI);

  it("/accedi distingue password e magic link invece di un booleano solo", () => {
    // Il terzo membro è il recupero password, aggiunto dopo: il punto della
    // prova non è quanti gesti ci sono, ma che ognuno sappia di essere suo.
    expect(codice).toInclude('useState<"password" | "magic-link" | "recupero" | null>');
    expect(codice).toInclude('inCorso === "password"');
    expect(codice).toInclude('inCorso === "magic-link"');
    expect(codice).toInclude('inCorso === "recupero"');
    // Il difetto precedente: un `inCorso` booleano condiviso dai due gesti, che
    // spegneva anche il pulsante dell'altro.
    expect(codice).not.toInclude("setInCorso(true)");
    expect(codice).not.toInclude("setInCorso(false)");
  });

  it("nessuna operazione può partire due volte", () => {
    const guardie = codice.match(/if \(inCorso\) return;/g) ?? [];
    expect(guardie.length).toBeGreaterThanOrEqual(2);
    expect(senzaCommenti(REGISTRATI)).toInclude("if (inCorso) return;");
  });

  it("ogni errore ha il proprio riquadro, accanto al proprio pulsante", () => {
    for (const testId of ["errore-password", "errore-magic-link", "errore-ritorno"]) {
      expect(codice).toInclude(`data-testid="${testId}"`);
    }
    expect(senzaCommenti(REGISTRATI)).toInclude('data-testid="errore-registrazione"');
    // Il riquadro social è nel componente social, non qui.
    expect(codice).not.toInclude('data-testid="errore-oauth"');
  });

  it("un nuovo tentativo pulisce solo il proprio errore", () => {
    const accedi = codice.slice(codice.indexOf("const accedi ="), codice.indexOf("const magicLink ="));
    expect(accedi).toInclude("setErrorePassword(null)");
    expect(accedi).not.toInclude("setErroreMagicLink(null)");
    const magic = codice.slice(codice.indexOf("const magicLink ="));
    expect(magic.slice(0, magic.indexOf("if (authLoading)"))).toInclude("setErroreMagicLink(null)");
  });

  it("cambiare le credenziali scarta l'errore che le descriveva", () => {
    expect(codice).toInclude("const aggiornaEmail");
    expect(codice).toInclude("const aggiornaPassword");
  });
});

describe("magic link: stesso flusso, non una pipeline parallela", () => {
  const codice = senzaCommenti(ACCEDI);

  it("rientra dalla callback esistente", () => {
    // Nessuna seconda route di ritorno: il contesto va al servizio, che
    // costruisce la destinazione con il modulo condiviso.
    expect(codice).toInclude("authInviaMagicLink(email.trim(), { superficie");
    expect(senzaCommenti(SERVIZIO)).toInclude("urlRitornoAuthDalBrowser(contesto)");
    expect(codice).not.toInclude("/auth/magic");
  });

  it("la schermata di conferma resta dopo l'invio riuscito", () => {
    expect(codice).toInclude("setMagicLinkInviato(true)");
    expect(codice).toInclude("Link inviato");
  });

  it("tornare indietro dalla conferma non lascia un errore vecchio", () => {
    expect(codice).toInclude("setMagicLinkInviato(false)");
    expect(codice).toInclude("setErroreMagicLink(null)");
  });
});

describe("sessione già attiva", () => {
  it("nessun form e nessun riavvio automatico del giro social", () => {
    for (const pagina of [ACCEDI, REGISTRATI]) {
      const codice = senzaCommenti(pagina);
      const inizio = codice.indexOf("if (authUser)");
      expect(inizio).toBeGreaterThan(-1);
      // Il ramo finisce dove comincia la guardia successiva, in cima al corpo
      // del componente.
      const successiva = codice.indexOf("\n  if (", inizio + 1);
      const ramo = codice.slice(inizio, successiva > -1 ? successiva : undefined);
      expect(ramo).not.toInclude("SocialAuthButtons");
      expect(ramo).not.toInclude("<Input");
      // Nessun redirect imposto: chi arriva qui con una sessione spesso ci
      // arriva per uscirne o per cambiare account.
      expect(ramo).not.toInclude("router.replace");
      expect(ramo).not.toInclude("router.push");
    }
  });

  it("la destinazione richiesta resta la meta proposta, e l'uscita resta possibile", () => {
    for (const pagina of [ACCEDI, REGISTRATI]) {
      expect(pagina).toInclude("<Link href={destinazione}>");
      expect(pagina).toInclude('data-testid="logout"');
      expect(pagina).toInclude("authLogout()");
    }
  });
});

describe("confini: D5 non tocca ciò che non è suo", () => {
  it("non duplica AgeGate né la verifica dei 18 anni nel giro social", () => {
    const codice = senzaCommenti(SOCIAL);
    expect(codice).not.toInclude("isMaggiorenne");
    expect(codice).not.toInclude("AgeGate");
    expect(codice).not.toInclude("dob");
    // E la callback non trasforma un profilo senza data di nascita in un
    // errore di autenticazione.
    expect(senzaCommenti(CALLBACK)).not.toInclude("dob");
  });

  it("non riaccende Facebook", () => {
    const codice = senzaCommenti(SOCIAL);
    expect(codice.toLowerCase()).not.toInclude("facebook");
    expect(codice).not.toInclude("FacebookIcon");
  });

  it("resta provider-agnostico dove lo era già", () => {
    // Il pulsante nomina Google; il gesto no. È ciò che rende riaccendibile un
    // secondo provider senza riscrivere il servizio.
    expect(senzaCommenti(SOCIAL)).toInclude("authAccediConOAuth(provider,");
    expect(senzaCommenti(SERVIZIO)).toInclude("accediConOAuth(provider");
  });

  it("non aggiunge password né account linking al giro Google", () => {
    // Il recupero password è arrivato dopo, e vive nel servizio accanto — non
    // dentro il gesto Google. Ciò che resta vietato ovunque è il collegamento
    // automatico di identità: unire due account è una decisione di chi li
    // possiede, non un effetto collaterale di un login.
    for (const sorgente of [SOCIAL, ACCEDI, REGISTRATI, SERVIZIO]) {
      expect(senzaCommenti(sorgente)).not.toInclude("linkIdentity");
    }
    // E la superficie social non tocca password in nessuna forma.
    for (const proibito of ["resetPasswordForEmail", "updateUser", "password"]) {
      expect(senzaCommenti(SOCIAL)).not.toInclude(proibito);
    }
    // Nel servizio, le due operazioni sulla password stanno fuori dal ramo
    // OAuth: quello apre il provider e finisce lì.
    const codice = senzaCommenti(SERVIZIO);
    const oauth = codice.slice(
      codice.indexOf("async accediConOAuth"),
      codice.indexOf("async signInWithGoogle"),
    );
    expect(oauth).not.toInclude("resetPasswordForEmail");
    expect(oauth).not.toInclude("updateUser");
  });

  it("il consenso legale non nasce dal click su Google: la superficie lo riceve", () => {
    const codice = senzaCommenti(SOCIAL);
    // Nessuna casella qui dentro e nessuno stato di consenso proprio: il
    // componente sa solo se è bloccato, e chi lo ospita sa perché.
    expect(codice).not.toInclude("ConsentCheckbox");
    expect(codice).not.toInclude("setConsenso");
    expect(codice).not.toInclude("terms");
    expect(codice).toInclude("consensoMancante = null,");
    expect(codice).toInclude("const bloccato = consensoMancante !== null");
  });
});
