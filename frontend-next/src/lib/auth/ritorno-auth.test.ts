import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  PARAMETRO_NEXT,
  PARAMETRO_SUPERFICIE,
  PERCORSO_RITORNO_AUTH,
  PERCORSO_SUPERFICIE_AUTH,
  superficieAuthDa,
  urlRitornoAuth,
} from "@/lib/auth/ritorno-auth";

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
   * Senza contesto la forma resta quella di prima, byte per byte. Il vincolo
   * originale era misurato sul progetto reale: finché la voce in elenco per il
   * dominio beta era esatta, una query string faceva ricadere l'utente sul
   * Site URL senza nessun errore. La voce è poi diventata `/**`, ma questo caso
   * resta a fissare che aggiungere parametri non è mai il comportamento
   * predefinito: li produce solo chi li chiede.
   */
  it("non produce query string né barra finale quando nessuno chiede nulla", () => {
    for (const origine of [PRODUZIONE, "http://localhost:3000"]) {
      for (const url of [urlRitornoAuth(origine), urlRitornoAuth(origine, {})]) {
        expect(url).not.toInclude("?");
        expect(url).not.toInclude("#");
        expect(url.endsWith("/")).toBe(false);
      }
    }
    expect(PERCORSO_RITORNO_AUTH).toBe("/auth/callback");
  });
});

describe("contesto di ritorno: superficie e destinazione", () => {
  it("porta la superficie di partenza, così l'errore torna dove è cominciato", () => {
    expect(urlRitornoAuth(PRODUZIONE, { superficie: "registrati" })).toBe(
      `${PRODUZIONE}/auth/callback?${PARAMETRO_SUPERFICIE}=registrati`,
    );
    expect(urlRitornoAuth(PRODUZIONE, { superficie: "accedi" })).toBe(
      `${PRODUZIONE}/auth/callback?${PARAMETRO_SUPERFICIE}=accedi`,
    );
  });

  it("porta la destinazione richiesta, se è un percorso relativo", () => {
    expect(urlRitornoAuth(PRODUZIONE, { next: "/vendite" })).toBe(
      `${PRODUZIONE}/auth/callback?${PARAMETRO_NEXT}=%2Fvendite`,
    );
    expect(urlRitornoAuth(PRODUZIONE, { superficie: "accedi", next: "/vendite" })).toBe(
      `${PRODUZIONE}/auth/callback?${PARAMETRO_SUPERFICIE}=accedi&${PARAMETRO_NEXT}=%2Fvendite`,
    );
  });

  /**
   * Un `next` che non è un percorso relativo non viene rifiutato con un errore:
   * viene semplicemente omesso, e la callback ricade su /home. È lo stesso
   * `percorsoRelativoSicuro` che difende /auth/callback — la difesa è una sola,
   * applicata due volte, non due difese che devono restare d'accordo.
   */
  it("lascia cadere qualunque destinazione non relativa", () => {
    for (const ostile of [
      "https://evil.example/phishing",
      "//evil.example",
      "http://evil.example",
      "/\\evil.example",
      "evil.example",
      "",
      null,
    ]) {
      expect(urlRitornoAuth(PRODUZIONE, { next: ostile })).toBe(`${PRODUZIONE}/auth/callback`);
    }
  });

  it("riconosce solo le due superfici esistenti, e in dubbio sceglie /accedi", () => {
    expect(superficieAuthDa("registrati")).toBe("registrati");
    expect(superficieAuthDa("accedi")).toBe("accedi");
    for (const ignoto of [null, undefined, "", "home", "REGISTRATI", "/registrati"]) {
      expect(superficieAuthDa(ignoto)).toBe("accedi");
    }
  });

  it("mappa ogni superficie su un percorso nostro, mai su un URL", () => {
    expect(PERCORSO_SUPERFICIE_AUTH.accedi).toBe("/accedi");
    expect(PERCORSO_SUPERFICIE_AUTH.registrati).toBe("/registrati");
    for (const percorso of Object.values(PERCORSO_SUPERFICIE_AUTH)) {
      expect(percorso.startsWith("/")).toBe(true);
      expect(percorso.startsWith("//")).toBe(false);
    }
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
    // Tre invocazioni del modulo: registrazione, magic link, OAuth. Da D5
    // passano tutte il contesto ricevuto dalla pagina, quindi la firma non è
    // più a zero argomenti.
    const usi = codice.match(/urlRitornoAuthDalBrowser\(contesto\)/g) ?? [];
    expect(usi.length).toBeGreaterThanOrEqual(3);
  });
});
