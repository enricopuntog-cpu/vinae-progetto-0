import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { PERCORSO_RITORNO_AUTH, urlRitornoAuth } from "@/lib/auth/ritorno-auth";

const PRODUZIONE = "https://timely-lokum-43a12e.netlify.app";

describe("destinazione di rientro chiesta a Supabase Auth", () => {
  it("manda al percorso che scambia il code, non all'origine nuda", () => {
    expect(urlRitornoAuth(PRODUZIONE)).toBe(`${PRODUZIONE}/auth/callback`);
    expect(urlRitornoAuth(PRODUZIONE)).not.toBe(PRODUZIONE);
  });

  it("normalizza le barre finali invece di produrre //auth/callback", () => {
    expect(urlRitornoAuth(`${PRODUZIONE}/`)).toBe(`${PRODUZIONE}/auth/callback`);
    expect(urlRitornoAuth(`${PRODUZIONE}///`)).toBe(`${PRODUZIONE}/auth/callback`);
  });

  it("funziona su localhost e sulle anteprime senza casi speciali", () => {
    expect(urlRitornoAuth("http://localhost:3000")).toBe("http://localhost:3000/auth/callback");
    expect(urlRitornoAuth("https://deploy-preview-50--timely-lokum-43a12e.netlify.app")).toBe(
      "https://deploy-preview-50--timely-lokum-43a12e.netlify.app/auth/callback",
    );
  });

  /**
   * Il vincolo misurato sul progetto reale: la voce in elenco per il dominio
   * beta è esatta, quindi una query string o una barra finale fanno ricadere
   * l'utente sul Site URL (http://localhost:3000) senza nessun errore. Questo
   * caso esiste perché aggiungere un `?next=` è la modifica più naturale del
   * mondo e romperebbe la produzione in silenzio.
   */
  it("non produce query string né barra finale", () => {
    for (const origine of [PRODUZIONE, "http://localhost:3000"]) {
      const url = urlRitornoAuth(origine);
      expect(url).not.toInclude("?");
      expect(url).not.toInclude("#");
      expect(url.endsWith("/")).toBe(false);
    }
    expect(PERCORSO_RITORNO_AUTH).toBe("/auth/callback");
  });
});

/**
 * Prova di contratto sulla sorgente: i tre flussi che rientrano nell'app devono
 * passare tutti da questo modulo. Senza, uno dei tre può tornare a mandare
 * `window.location.origin` nudo — che è esattamente il difetto corretto qui — e
 * nessun test di comportamento se ne accorgerebbe, perché il fallimento non è
 * un errore ma un redirect silenzioso verso il Site URL.
 */
describe("contratto: auth-service non costruisce destinazioni per conto suo", () => {
  const sorgente = readFileSync(
    join(process.cwd(), "src/services/auth-service.ts"),
    "utf8",
  );
  const righeVive = sorgente
    .split("\n")
    .filter((riga) => !riga.trimStart().startsWith("//") && !riga.trimStart().startsWith("*"));
  const codice = righeVive.join("\n");

  it("importa il modulo condiviso", () => {
    expect(codice).toInclude("urlRitornoAuthDalBrowser");
  });

  it("non passa mai window.location.origin nudo a Supabase", () => {
    // Ogni uso di window.location.origin deve essere mediato dal modulo: la
    // ricerca è sulle sole righe vive, così spiegare il divieto in un commento
    // non fa fallire la verifica del divieto.
    expect(codice).not.toInclude("window.location.origin");
  });

  it("copre tutti e tre i flussi che rientrano con un code", () => {
    for (const metodo of ["signUp", "signInWithOtp", "signInWithOAuth"]) {
      expect(codice).toInclude(metodo);
    }
    // Tre invocazioni del modulo: registrazione, magic link, OAuth.
    const usi = codice.match(/urlRitornoAuthDalBrowser\(\)/g) ?? [];
    expect(usi.length).toBeGreaterThanOrEqual(3);
  });
});
