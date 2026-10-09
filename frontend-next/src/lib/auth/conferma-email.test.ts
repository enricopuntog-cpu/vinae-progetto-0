import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  DESTINAZIONE_PREDEFINITA_CONFERMA,
  PERCORSO_CONFERMA_EMAIL,
  TIPI_OTP_CONFERMA,
  classificaErroreConferma,
  destinazioneDaLink,
  leggiRichiestaConferma,
  percorsoErroreConferma,
} from "@/lib/auth/conferma-email";
import { CODICI_ERRORE_AUTH, MESSAGGI_ERRORE_AUTH } from "@/lib/auth/errori-auth";

/** Forma di un token_hash GoTrue (sha224 esadecimale), non un token reale. */
const HASH = "a".repeat(56);
const HASH_PKCE = `pkce_${"b".repeat(56)}`;

const parametri = (query: string) => new URLSearchParams(query);

describe("leggiRichiestaConferma", () => {
  it("accetta il link del template documentato (type=email)", () => {
    const lettura = leggiRichiestaConferma(parametri(`token_hash=${HASH}&type=email`));
    expect(lettura).toEqual({
      ok: true,
      tokenHash: HASH,
      tipo: "email",
      destinazione: DESTINAZIONE_PREDEFINITA_CONFERMA,
    });
  });

  it("accetta il nome storico signup e l'hash con prefisso pkce_", () => {
    const lettura = leggiRichiestaConferma(parametri(`token_hash=${HASH_PKCE}&type=signup`));
    expect(lettura.ok).toBe(true);
    if (lettura.ok) expect(lettura.tipo).toBe("signup");
  });

  it.each(["recovery", "magiclink", "invite", "email_change", "SIGNUP", ""])(
    "rifiuta il tipo OTP %p senza chiamare il provider",
    (tipo) => {
      const lettura = leggiRichiestaConferma(parametri(`token_hash=${HASH}&type=${tipo}`));
      expect(lettura).toEqual({
        ok: false,
        codice: "conferma-link-non-valido",
        destinazione: DESTINAZIONE_PREDEFINITA_CONFERMA,
      });
    },
  );

  it.each([
    ["senza token", "type=email"],
    ["token troncato", "token_hash=abc&type=email"],
    ["token con caratteri estranei", `token_hash=${HASH}%3Cscript%3E&type=email`],
    ["senza tipo", `token_hash=${HASH}`],
  ])("rifiuta un link %s", (_caso, query) => {
    const lettura = leggiRichiestaConferma(parametri(query));
    expect(lettura.ok).toBe(false);
    if (!lettura.ok) expect(lettura.codice).toBe("conferma-link-non-valido");
  });

  it("i tipi ammessi sono solo quelli della conferma di registrazione", () => {
    expect([...TIPI_OTP_CONFERMA].sort()).toEqual(["email", "signup"]);
  });
});

describe("destinazioneDaLink — nessun redirect aperto", () => {
  it("usa next se è un percorso relativo", () => {
    expect(destinazioneDaLink(parametri("next=%2Faccount"))).toBe("/account");
  });

  it("ricava next da redirect_to, ignorandone origine e percorso", () => {
    const redirectTo = encodeURIComponent(
      "https://vineawineclub.com/auth/callback?superficie=registrati&next=%2Faccount",
    );
    expect(destinazioneDaLink(parametri(`redirect_to=${redirectTo}`))).toBe("/account");
  });

  it.each([
    ["next assoluto", "next=https%3A%2F%2Fevil.example"],
    ["next protocol-relative", "next=%2F%2Fevil.example"],
    ["next con barra rovesciata", "next=%2F%5Cevil.example"],
    ["redirect_to ostile senza next", `redirect_to=${encodeURIComponent("https://evil.example/x")}`],
    [
      "redirect_to con next ostile",
      `redirect_to=${encodeURIComponent("https://evil.example/?next=//evil.example")}`,
    ],
    ["redirect_to non URL", "redirect_to=%2F%2F%2F"],
  ])("%s ricade sulla destinazione predefinita", (_caso, query) => {
    expect(destinazioneDaLink(parametri(query))).toBe(DESTINAZIONE_PREDEFINITA_CONFERMA);
  });

  it("next diretto vince su redirect_to", () => {
    const redirectTo = encodeURIComponent("https://vineawineclub.com/auth/callback?next=%2Fvendi");
    expect(destinazioneDaLink(parametri(`next=%2Fcantina&redirect_to=${redirectTo}`))).toBe("/cantina");
  });
});

describe("classificaErroreConferma", () => {
  it("link scaduto e link già usato sono lo stesso caso per l'utente", () => {
    const scaduto = classificaErroreConferma({
      code: "otp_expired",
      status: 403,
      message: "Email link is invalid or has expired",
    });
    const giaUsato = classificaErroreConferma({ message: "One-time token not found", status: 403 });
    expect(scaduto).toBe("conferma-link-non-valido");
    expect(giaUsato).toBe("conferma-link-non-valido");
  });

  it("un limite di frequenza resta riconoscibile", () => {
    expect(classificaErroreConferma({ status: 429, message: "rate limit" })).toBe("troppi-tentativi");
  });

  it("ogni altro errore diventa un codice neutro del vocabolario", () => {
    const codice = classificaErroreConferma({ status: 500, message: "Database error: secret detail" });
    expect(codice).toBe("conferma-non-riuscita");
    expect(MESSAGGI_ERRORE_AUTH[codice]).not.toInclude("secret");
  });
});

describe("percorsoErroreConferma", () => {
  it("porta su /accedi con il solo codice", () => {
    expect(percorsoErroreConferma("conferma-link-non-valido", DESTINAZIONE_PREDEFINITA_CONFERMA)).toBe(
      "/accedi?errore=conferma-link-non-valido",
    );
  });

  it("conserva una destinazione già validata", () => {
    const url = new URL(`https://x.test${percorsoErroreConferma("conferma-non-riuscita", "/account")}`);
    expect(url.pathname).toBe("/accedi");
    expect(url.searchParams.get("errore")).toBe("conferma-non-riuscita");
    expect(url.searchParams.get("next")).toBe("/account");
  });
});

describe("vocabolario e template", () => {
  it("i due codici nuovi hanno un messaggio italiano con l'azione successiva", () => {
    for (const codice of ["conferma-link-non-valido", "conferma-non-riuscita"] as const) {
      expect(CODICI_ERRORE_AUTH).toContain(codice);
      expect(MESSAGGI_ERRORE_AUTH[codice]).toInclude("accedi");
    }
  });

  it("il template versionato punta a questa route con token_hash e type=email", () => {
    const template = readFileSync(
      join(process.cwd(), "..", "supabase", "templates", "confirm-signup.html"),
      "utf8",
    );
    expect(template).toInclude(
      `{{ .SiteURL }}${PERCORSO_CONFERMA_EMAIL}?token_hash={{ .TokenHash }}&type=email`,
    );
    // Il vecchio link PKCE non deve sopravvivere nel template nuovo.
    expect(template).not.toInclude("ConfirmationURL");
    // Il logo è un URL HTTPS assoluto sul dominio di produzione.
    expect(template).toMatch(/src="https:\/\/vineawineclub\.com\/brand\/vinea-email-logo-[^"]+"/);
    expect(template).toInclude('lang="it"');
    expect(template).toInclude("Conferma la mia email");
  });

  it("il nome del club resta testo HTML anche se il client blocca il logo", () => {
    const template = readFileSync(
      join(process.cwd(), "..", "supabase", "templates", "confirm-signup.html"),
      "utf8",
    );
    const logo = /<img [^>]*vinea-email-logo-[^>]*>/.exec(template)![0];
    // Un logo bloccato lascia un riquadro piccolo, non il nome del club.
    expect(logo).toInclude('width="80"');
    expect(logo).toInclude('height="80"');
    // Il nome segue il logo come testo, fuori da ogni immagine.
    expect(template.slice(template.indexOf(logo) + logo.length)).toMatch(/^\s*<p [^>]*>\s*VINEA WINE CLUB\s*<\/p>/);
    // Nessuna immagine incorporata: Supabase Auth non gestisce allegati o CID.
    expect(template).not.toMatch(/src="(data|cid):/);
  });
});
