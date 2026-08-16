import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  percorsoRelativoSicuro,
  risolviOriginePubblica,
  type AmbienteOrigine,
} from "@/lib/auth/origine-redirect";

const PRODUZIONE = "https://timely-lokum-43a12e.netlify.app";
const ANTEPRIMA = "https://deploy-preview-45--timely-lokum-43a12e.netlify.app";
/** Dominio immutabile del singolo deploy: mai un destinatario valido. */
const IMMUTABILE = "https://6a81cfdc84aaf4000821392f--timely-lokum-43a12e.netlify.app";

const ambienteProduzione: AmbienteOrigine = { CONTEXT: "production", URL: PRODUZIONE };
const ambienteAnteprima: AmbienteOrigine = {
  CONTEXT: "deploy-preview",
  DEPLOY_PRIME_URL: ANTEPRIMA,
  URL: PRODUZIONE,
};

const richiesta = (href: string) => new URL(href);

describe("origine pubblica dei redirect Auth", () => {
  it("in produzione ignora il dominio immutabile del deploy e resta sul dominio pubblico", () => {
    const risolta = risolviOriginePubblica(
      richiesta(`${IMMUTABILE}/auth/callback?code=abc`),
      ambienteProduzione,
    );

    expect(risolta.origine).toBe(PRODUZIONE);
    expect(risolta.sorgente).toBe("netlify-produzione");
  });

  it("su una Deploy Preview resta sul proprio DEPLOY_PRIME_URL e non scivola in produzione", () => {
    const risolta = risolviOriginePubblica(
      richiesta(`${ANTEPRIMA}/auth/callback?code=abc`),
      ambienteAnteprima,
    );

    expect(risolta.origine).toBe(ANTEPRIMA);
    expect(risolta.sorgente).toBe("netlify-non-produzione");
  });

  it("tratta allo stesso modo un branch deploy", () => {
    const branch = "https://main--timely-lokum-43a12e.netlify.app";
    const risolta = risolviOriginePubblica(richiesta(`${branch}/auth/callback`), {
      CONTEXT: "branch-deploy",
      DEPLOY_PRIME_URL: branch,
      URL: PRODUZIONE,
    });

    expect(risolta.origine).toBe(branch);
  });

  it("in locale resta su localhost, con la porta di sviluppo", () => {
    for (const locale of ["http://localhost:3000", "http://127.0.0.1:3000"]) {
      const risolta = risolviOriginePubblica(richiesta(`${locale}/auth/callback`), {});

      expect(risolta.origine).toBe(locale);
      expect(risolta.sorgente).toBe("richiesta-locale");
    }
  });

  it("non accetta un hostname arbitrario inoltrato con la richiesta", () => {
    for (const inoltrato of [
      "https://evil.example.com/auth/callback?code=abc",
      "https://timely-lokum-43a12e.netlify.app.evil.example/auth/callback",
      "https://localhost.evil.example/auth/callback",
      `${IMMUTABILE}/auth/callback`,
    ]) {
      const risolta = risolviOriginePubblica(richiesta(inoltrato), ambienteProduzione);

      expect(risolta.origine).toBe(PRODUZIONE);
      expect(risolta.sorgente).toBe("netlify-produzione");
    }
  });

  it("non lascia che un hostname che finisce per localhost passi per locale", () => {
    const risolta = risolviOriginePubblica(
      richiesta("https://evil-localhost/auth/callback"),
      {},
    );

    expect(risolta.sorgente).toBe("richiesta-non-attendibile");
  });

  it("l'override esplicito vince su Netlify, per gli ambienti che Netlify non sono", () => {
    const risolta = risolviOriginePubblica(richiesta(`${IMMUTABILE}/auth/callback`), {
      ...ambienteAnteprima,
      AUTH_REDIRECT_ORIGIN: "https://app.vinea.test",
    });

    expect(risolta.origine).toBe("https://app.vinea.test");
    expect(risolta.sorgente).toBe("override-esplicito");
  });

  it("scarta un valore di ambiente inutilizzabile invece di trasformarlo in Location", () => {
    for (const invalido of ["", "   ", "non-un-url", "/accedi", "javascript:alert(1)"]) {
      const risolta = risolviOriginePubblica(richiesta(`${IMMUTABILE}/auth/callback`), {
        AUTH_REDIRECT_ORIGIN: invalido,
        ...ambienteProduzione,
      });

      expect(risolta.origine).toBe(PRODUZIONE);
    }
  });

  it("tiene la sola origine e scarta percorso e query della variabile", () => {
    const risolta = risolviOriginePubblica(richiesta(`${IMMUTABILE}/auth/callback`), {
      URL: `${PRODUZIONE}/una/sottocartella?x=1`,
    });

    expect(risolta.origine).toBe(PRODUZIONE);
  });

  it("senza DEPLOY_PRIME_URL una preview ricade sul dominio di produzione, non sulla richiesta", () => {
    const risolta = risolviOriginePubblica(richiesta(`${ANTEPRIMA}/auth/callback`), {
      CONTEXT: "deploy-preview",
      URL: PRODUZIONE,
    });

    expect(risolta.origine).toBe(PRODUZIONE);
    expect(risolta.sorgente).toBe("netlify-produzione");
  });
});

describe("percorso di ritorno `next`", () => {
  it("accetta i percorsi relativi", () => {
    for (const percorso of ["/home", "/cantina", "/annuncio/abc?x=1", "/accedi#sezione"]) {
      expect(percorsoRelativoSicuro(percorso)).toBe(percorso);
    }
  });

  it("rifiuta le forme che sembrano relative e portano su un altro host", () => {
    for (const percorso of [
      "//evil.example.com",
      "//evil.example.com/home",
      "/\\evil.example.com",
      "https://evil.example.com",
      "http://evil.example.com",
      "home",
      "",
    ]) {
      expect(percorsoRelativoSicuro(percorso)).toBeNull();
    }

    expect(percorsoRelativoSicuro(null)).toBeNull();
  });

  it("un percorso ammesso non può cambiare host una volta unito all'origine", () => {
    for (const percorso of ["/home", "/annuncio/abc?x=1"]) {
      const ammesso = percorsoRelativoSicuro(percorso);
      expect(new URL(`${PRODUZIONE}${ammesso}`).origin).toBe(PRODUZIONE);
    }
  });
});

describe("la route di callback usa l'origine risolta e mai quella della richiesta", () => {
  const sorgenteRoute = readFileSync(
    join(import.meta.dir, "../../app/auth/callback/route.ts"),
    "utf8",
  );

  it("non estrae più `origin` da nextUrl", () => {
    expect(sorgenteRoute).not.toInclude("origin } = request.nextUrl");
    expect(sorgenteRoute).not.toInclude("nextUrl.origin");
  });

  it("costruisce ogni redirect dall'origine risolta", () => {
    expect(sorgenteRoute).toInclude("risolviOriginePubblica");
    expect(sorgenteRoute).toInclude("percorsoRelativoSicuro");

    const redirect = [...sorgenteRoute.matchAll(/NextResponse\.redirect\(\s*`([^`]*)`/g)].map(
      ([, modello]) => modello,
    );
    expect(redirect.length).toBeGreaterThan(0);
    for (const modello of redirect) {
      expect(modello.startsWith("${origine}")).toBeTrue();
    }
  });

  it("copre tutti e cinque i rientri della route, non il solo successo", () => {
    for (const ramo of [
      "errore=${encodeURIComponent(errorDescription)}",
      "Callback senza codice di autorizzazione.",
      "Supabase non configurato su questo ambiente.",
      "errore=${encodeURIComponent(error.message)}",
      "return vaiA(destinazione);",
    ]) {
      expect(sorgenteRoute).toInclude(ramo);
    }
  });
});
