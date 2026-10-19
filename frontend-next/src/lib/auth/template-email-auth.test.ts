import { describe, expect, it } from "bun:test";
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * Template email di Supabase Auth versionati in `supabase/templates/`.
 *
 * Il modello è `confirm-signup.html` (PR #202/#203, approvato e attivo in
 * produzione): gli altri ne riprendono lo scheletro e cambiano solo testi e
 * link. Le regole sui link sono quelle di docs/EMAIL_AUTH_TEMPLATES.md:
 * `/auth/confirm` accetta solo `email`/`signup`; recupero password e magic link
 * hanno route `token_hash` proprie (`/auth/recupero`, `/auth/accesso`, VPM-001);
 * invito e cambio email restano sul link standard `{{ .ConfirmationURL }}` e
 * Reauthentication mostra solo `{{ .Token }}`. Le variabili ammesse per ciascun template sono le chiavi
 * delle mappe che GoTrue passa a `html/template`
 * (supabase/auth, internal/mailer/templatemailer/templatemailer.go).
 */

const RADICE = join(process.cwd(), "..", "supabase");
const leggi = (file: string) =>
  readFileSync(join(RADICE, "templates", file), "utf8").replace(/\r\n/g, "\n");

/** Impronta del template approvato sul `main` del 13 ottobre 2026. */
const IMPRONTA_CONFIRM_SIGNUP = "4779a6bd577701bdbd7874c62bfa4685c9ad0669c01e4d8ded7ebeec6a7a6b10";

const SITO = "https://vineawineclub.com";
const LOGO = "https://vineawineclub.com/brand/vinea-email-logo-240-v1.png";
const BASE = ["SiteURL", "Email", "Data"];
const LINK = [...BASE, "ConfirmationURL", "Token", "TokenHash", "RedirectTo"];

type Template = {
  file: string;
  sezione: string;
  oggetto: string;
  titolo: string;
  /** Variabili che GoTrue fornisce a questo template. */
  variabili: readonly string[];
  tipo: "link" | "codice" | "notifica";
  cta?: string;
};

const AUTENTICAZIONE: readonly Template[] = [
  {
    file: "invite.html",
    sezione: "template.invite",
    oggetto: "Il tuo invito a Vinea Wine Club",
    titolo: "Sei invitato in Vinea Wine Club",
    variabili: LINK,
    tipo: "link",
    cta: "Accetta l&rsquo;invito",
  },
  {
    file: "magic-link.html",
    sezione: "template.magic_link",
    oggetto: "Accedi a Vinea Wine Club",
    titolo: "Il tuo accesso a Vinea",
    variabili: LINK,
    tipo: "link",
    cta: "Accedi a Vinea",
  },
  {
    file: "email-change.html",
    sezione: "template.email_change",
    oggetto: "Conferma il tuo nuovo indirizzo email | Vinea",
    titolo: "Conferma il nuovo indirizzo email",
    variabili: [...LINK, "NewEmail", "SendingTo"],
    tipo: "link",
    cta: "Conferma la nuova email",
  },
  {
    file: "reset-password.html",
    sezione: "template.recovery",
    oggetto: "Reimposta la password | Vinea Wine Club",
    titolo: "Reimposta la tua password",
    variabili: LINK,
    tipo: "link",
    cta: "Reimposta la password",
  },
  {
    file: "reauthentication.html",
    sezione: "template.reauthentication",
    oggetto: "Verifica di sicurezza | Vinea Wine Club",
    titolo: "Conferma la tua identit&agrave;",
    variabili: [...BASE, "Token"],
    tipo: "codice",
  },
];

const NOTIFICHE: readonly Template[] = [
  ["password-changed-notification.html", "password_changed", "La tua password è stata modificata | Vinea Wine Club", "Password modificata", []],
  ["email-changed-notification.html", "email_changed", "Il tuo indirizzo email è stato modificato | Vinea Wine Club", "Indirizzo email modificato", ["OldEmail"]],
  ["phone-changed-notification.html", "phone_changed", "Il tuo numero di telefono è stato modificato | Vinea Wine Club", "Numero di telefono modificato", ["Phone", "OldPhone"]],
  ["identity-linked-notification.html", "identity_linked", "Nuovo metodo di accesso collegato | Vinea Wine Club", "Nuovo metodo di accesso collegato", ["Provider"]],
  ["identity-unlinked-notification.html", "identity_unlinked", "Metodo di accesso rimosso | Vinea Wine Club", "Metodo di accesso rimosso", ["Provider"]],
  ["mfa-factor-enrolled-notification.html", "mfa_factor_enrolled", "Nuovo metodo di verifica aggiunto | Vinea Wine Club", "Nuovo metodo di verifica aggiunto", ["FactorType"]],
  ["mfa-factor-unenrolled-notification.html", "mfa_factor_unenrolled", "Metodo di verifica rimosso | Vinea Wine Club", "Metodo di verifica rimosso", ["FactorType"]],
].map(([file, chiave, oggetto, titolo, extra]) => ({
  file: file as string,
  sezione: `notification.${chiave as string}`,
  oggetto: oggetto as string,
  titolo: titolo as string,
  variabili: [...BASE, ...(extra as string[])],
  tipo: "notifica" as const,
}));

const TUTTI = [...AUTENTICAZIONE, ...NOTIFICHE];

/**
 * Template il cui link punta a una route `token_hash` dedicata invece che a
 * `{{ .ConfirmationURL }}` (VPM-001): il link PKCE standard richiedeva il
 * browser della richiesta. Le route sono `app/auth/recupero` e
 * `app/auth/accesso`; `/auth/confirm` resta della sola registrazione.
 */
const LINK_TOKEN_HASH: Record<string, { href: string; testo: string; cta: string }> = {
  "reset-password.html": {
    href: "{{ .SiteURL }}/auth/recupero?token_hash={{ .TokenHash }}&type=recovery",
    testo: "{{ .SiteURL }}/auth/recupero?token_hash={{ .TokenHash }}&amp;type=recovery",
    cta: "Reimposta la password",
  },
  "magic-link.html": {
    href: "{{ .SiteURL }}/auth/accesso?token_hash={{ .TokenHash }}&type=magiclink&redirect_to={{ .RedirectTo }}",
    testo: "{{ .SiteURL }}/auth/accesso?token_hash={{ .TokenHash }}&amp;type=magiclink",
    cta: "Accedi a Vinea",
  },
};

const hrefs = (html: string) => [...html.matchAll(/href="([^"]*)"/g)].map((m) => m[1]);
const variabiliUsate = (html: string) =>
  new Set([...html.matchAll(/\{\{-?\s*(?:if\s+|else\s*|end\s*)?\.?([A-Za-z]*)/g)].map((m) => m[1]).filter(Boolean));

/** Blocco del config.toml che inizia con l'intestazione data. */
const sezioneConfig = (config: string, intestazione: string) => {
  const inizio = config.indexOf(`[${intestazione}]`);
  if (inizio < 0) return null;
  const resto = config.slice(inizio + intestazione.length + 2);
  const fine = resto.search(/^\[/m);
  return fine < 0 ? resto : resto.slice(0, fine);
};

describe("template approvato Confirm signup", () => {
  it("resta byte per byte quello approvato", () => {
    const impronta = createHash("sha256").update(leggi("confirm-signup.html")).digest("hex");
    expect(impronta).toBe(IMPRONTA_CONFIRM_SIGNUP);
  });
});

describe("identità grafica condivisa", () => {
  const approvato = leggi("confirm-signup.html");
  const testa = approvato.slice(0, approvato.indexOf("<title>"));
  const logo = approvato.slice(approvato.indexOf("<img "), approvato.indexOf("</p>", approvato.indexOf("<img ")) + 4);
  const riquadro = /<td class="riquadro"[^>]*>/.exec(approvato)![0];
  const marchio = approvato.slice(approvato.lastIndexOf("Vinea Wine Club &middot;"), approvato.indexOf("</body>"));

  for (const t of TUTTI) {
    it(`${t.file}: stesso scheletro del template approvato`, () => {
      const html = leggi(t.file);
      expect(html.startsWith(testa)).toBe(true);
      expect(html).toInclude(logo);
      expect(html).toInclude(LOGO);
      expect(html).toInclude(riquadro);
      expect(html).toInclude("border-top:4px solid #6b2138");
      expect(html).toInclude('width="560"');
      expect(html).toInclude("background-color:#f4eee2");
      expect(html.endsWith(marchio + "</body>\n</html>\n")).toBe(true);
      expect(html).toInclude(`<h1 class="titolo"`);
      expect(html).toMatch(new RegExp(`<h1 [^>]*>\\s*${t.titolo.replace(/[|]/g, "\\|")}\\s*</h1>`));
    });

    it(`${t.file}: nessuno script, font esterno o immagine incorporata`, () => {
      const html = leggi(t.file);
      expect(html).not.toMatch(/<script|<link |@import|@font-face|src="(data|cid):/i);
      expect([...html.matchAll(/<img /g)]).toHaveLength(1);
    });

    it(`${t.file}: usa solo variabili che GoTrue fornisce a questo template`, () => {
      for (const v of variabiliUsate(leggi(t.file))) expect(t.variabili).toContain(v);
    });

    it(`${t.file}: non passa mai da /auth/confirm`, () => {
      expect(leggi(t.file)).not.toInclude("/auth/confirm");
    });

    if (!LINK_TOKEN_HASH[t.file]) {
      it(`${t.file}: non costruisce link con token_hash`, () => {
        const html = leggi(t.file);
        expect(html).not.toInclude("TokenHash");
        expect(html).not.toInclude("token_hash");
      });
    }
  }
});

describe("recupero password e magic link: token_hash su route dedicate (VPM-001)", () => {
  for (const [file, { href, testo, cta }] of Object.entries(LINK_TOKEN_HASH)) {
    it(`${file}: pulsante VML, pulsante e link alternativo verificati dal server`, () => {
      const html = leggi(file);
      const azioni = hrefs(html).filter((h) => h !== SITO);
      expect(azioni).toEqual([href, href, href]);
      expect(html).toInclude(`>${testo}</a>`);
      expect(html).toInclude(`>${cta}</a>`);
      expect(html).not.toInclude("ConfirmationURL");
      expect(html).not.toInclude(".Token }}");
    });

    it(`${file}: non chiede più di usare lo stesso browser`, () => {
      const html = leggi(file);
      expect(html).not.toInclude("stesso browser");
      expect(html).toInclude("Puoi aprire il link anche da un altro dispositivo o browser.");
    });
  }

  it("il recupero non porta redirect_to: la destinazione è una costante della route", () => {
    expect(leggi("reset-password.html")).not.toInclude("RedirectTo");
  });
});

describe("link e codici", () => {
  for (const t of AUTENTICAZIONE.filter((x) => x.tipo === "link" && !LINK_TOKEN_HASH[x.file])) {
    it(`${t.file}: pulsante e link alternativo puntano allo stesso {{ .ConfirmationURL }}`, () => {
      const html = leggi(t.file);
      const azioni = hrefs(html).filter((h) => h !== SITO);
      // VML per Outlook, pulsante, link alternativo: sempre la stessa destinazione.
      expect(azioni).toEqual(["{{ .ConfirmationURL }}", "{{ .ConfirmationURL }}", "{{ .ConfirmationURL }}"]);
      expect(html).toInclude(">{{ .ConfirmationURL }}</a>");
      expect(html).toInclude(`>${t.cta}</a>`);
      expect(html).not.toInclude(".Token }}");
    });
  }

  it("reauthentication.html: mostra il codice OTP e nessun link d'azione", () => {
    const html = leggi("reauthentication.html");
    expect(hrefs(html)).toEqual([SITO]);
    expect([...html.matchAll(/\{\{ \.Token \}\}/g)]).toHaveLength(1);
    expect(html).toMatch(/<span class="codice-cifre"[^>]*>\{\{ \.Token \}\}<\/span>/);
    expect(html).not.toInclude("ConfirmationURL");
  });

  it("email-change.html: mostra indirizzo attuale e nuovo come testo", () => {
    const html = leggi("email-change.html");
    expect(html).toInclude("{{ .Email }}");
    expect(html).toInclude("{{ .NewEmail }}");
    expect(html).toInclude("solo se l&rsquo;hai richiesta tu");
  });

  for (const t of NOTIFICHE) {
    it(`${t.file}: nessun token, solo link fissi del sito`, () => {
      const html = leggi(t.file);
      expect(html).not.toMatch(/ConfirmationURL|\.Token\b|RedirectTo/);
      for (const h of hrefs(html)) expect([SITO, `${SITO}/accedi`]).toContain(h);
    });
  }
});

describe("supabase/config.toml", () => {
  const config = readFileSync(join(RADICE, "config.toml"), "utf8");

  for (const t of TUTTI) {
    it(`[auth.email.${t.sezione}] punta al file e all'oggetto italiano`, () => {
      const blocco = sezioneConfig(config, `auth.email.${t.sezione}`);
      expect(blocco).not.toBeNull();
      expect(blocco).toInclude(`subject = "${t.oggetto}"`);
      expect(blocco).toInclude(`content_path = "./supabase/templates/${t.file}"`);
      expect(existsSync(join(RADICE, "templates", t.file))).toBe(true);
      expect(leggi(t.file)).toInclude(`<title>${t.oggetto.replace("è", "&egrave;")}</title>`);
    });
  }

  it("le notifiche di sicurezza restano spente", () => {
    for (const t of NOTIFICHE) {
      expect(sezioneConfig(config, `auth.email.${t.sezione}`)).toMatch(/^enabled = false$/m);
    }
  });
});
