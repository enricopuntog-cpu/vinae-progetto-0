import { randomBytes } from "node:crypto";
import type { BrowserContext, Page } from "@playwright/test";
import { EMAIL, passwordFixture } from "./support/api";
import { opzioniDelProgetto } from "./support/browser";
import { ripristinaFixture } from "./support/db";
import { attendiCaricamento } from "./support/pagina";
import { risolviBersaglio } from "./support/stack";
import { expect, test } from "./support/test";
import { scriviSegreto } from "./support/segreti";
import { etichettaCorsa, leggiDalDatabase } from "./support/vino";

/**
 * Autenticazione e sessioni (VPM-018-E2E-CRIT-01), dal BROWSER: registrazione
 * dal modulo `/registrati`, accesso dal modulo `/accedi`, credenziali errate,
 * sessione riconosciuta sulle pagine private, uscita e perdita di accesso,
 * sessione assente, revocata o manomessa, azioni che richiedono l'accesso.
 *
 * Qui le password si scrivono nei moduli del browser, sempre con
 * `scriviSegreto` e mai con `fill`: il titolo del passo (`Fill "…"`) porterebbe
 * il valore nel report HTML (R-PASS-01; `support/segreti.test.ts` lo vieta).
 * Per l'intero file trace, screenshot e video sono spenti (`test.use`) e ogni
 * caso lo verifica dalle opzioni effettive prima di partire; le password
 * nascono a runtime, vivono in memoria e un controllo finale prova che non
 * compaiono nella diagnostica allegata.
 *
 * Limiti dichiarati (stack dedicato senza Mailpit, `enable_confirmations=false`
 * come la configurazione locale): la conferma email e il link di recupero
 * password NON sono esercitati; si prova che la richiesta di recupero dal
 * browser dà lo stesso testo neutro a un iscritto con invio fallito e a un
 * indirizzo sconosciuto (R-AUTH-01: mitigazione dell'interfaccia; GoTrue resta
 * un oracolo, annotato). OAuth e MFA non sono chiamati (nessun provider esterno).
 */
test.use({ trace: "off", screenshot: "off", video: "off" });

const nomeCookieSessione = /^sb-.+-auth-token/;

/** Una password conforme alla policy (minuscola, maiuscola, cifra, simbolo), nuova per ogni corsa. */
const passwordNuova = (): string => `Vinea-${randomBytes(9).toString("hex")}Aa1!`;

const modoDi = (opzione: unknown): string =>
  typeof opzione === "string" ? opzione : String((opzione as { mode?: string } | undefined)?.mode ?? "?");

test.beforeEach(({ trace, screenshot, video }) => {
  // Le password digitate non devono finire in trace, screenshot o video: se un giorno
  // qualcuno riaccende questi artefatti per il file, i casi si fermano qui.
  expect([modoDi(trace), modoDi(screenshot), modoDi(video)]).toEqual(["off", "off", "off"]);
});

const contestoNuovo = async (browser: import("@playwright/test").Browser, info: import("@playwright/test").TestInfo) =>
  browser.newContext(opzioniDelProgetto(info));

const cookieDiSessione = async (contesto: BrowserContext) =>
  (await contesto.cookies()).filter((c) => nomeCookieSessione.test(c.name));

const accediDalModulo = async (page: Page, email: string, password: string, next = "/account") => {
  await page.goto(`/accedi?next=${encodeURIComponent(next)}`);
  await attendiCaricamento(page);
  await page.getByLabel("Email", { exact: true }).fill(email);
  await scriviSegreto(page.getByLabel("Password", { exact: true }), password);
  await page.getByTestId("accedi-password").click();
};

const nessunaPasswordNellaDiagnostica = (eventi: unknown, ...password: string[]) => {
  const testo = JSON.stringify(eventi);
  for (const p of password) expect(testo.includes(p), "una password è finita nella diagnostica").toBe(false);
};

test.describe.serial("Autenticazione dal browser: registrazione, accesso, uscita e sessioni @smoke", () => {
  const tag = etichettaCorsa();
  const email = `crit-${tag}@e2e-12zk.test`;
  const username = `e2ecrit_${tag}`;
  const password = passwordNuova();
  let cookieRevocati: Awaited<ReturnType<typeof cookieDiSessione>> = [];

  test.beforeAll(() => {
    ripristinaFixture(passwordFixture());
  });

  test("senza sessione le pagine private chiedono l'accesso e i comandi riservati non ci sono", async ({ page }) => {
    await page.goto("/account");
    await attendiCaricamento(page);
    await expect(page.getByRole("heading", { name: "Serve prima l'accesso" })).toBeVisible();
    await page.goto("/vendi");
    await attendiCaricamento(page);
    await expect(page.getByRole("heading", { name: "Accedi per catalogare o vendere" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Pubblica annuncio" })).toHaveCount(0);
  });

  test("registrazione dal modulo /registrati: l'account nasce e la sessione è attiva", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoNuovo(browser, info);
    const page = await contesto.newPage();
    diagnostica.osserva(page, "nuovo utente");
    await page.goto("/registrati?next=%2Faccount");
    await attendiCaricamento(page);
    await page.getByLabel("Nome utente").fill(username);
    await page.getByLabel("Email", { exact: true }).fill(email);
    await scriviSegreto(page.getByLabel("Password", { exact: true }), password);
    await page.getByLabel("Data di nascita").fill("1990-05-05");
    await page.getByTestId("consenso-termini").click();
    await page.getByTestId("crea-account").click();

    await expect(page).toHaveURL(/\/account/);
    await attendiCaricamento(page);
    await expect(page.getByRole("heading", { name: "Il tuo profilo" })).toBeVisible();
    await expect(page.getByText(email)).toBeVisible();
    expect((await cookieDiSessione(contesto)).length).toBeGreaterThan(0);
    // Il profilo nasce dal trigger del database, con il nome scelto e la data dichiarata.
    expect(
      leggiDalDatabase(`select p.username || ' ' || p.dob from public.profiles p join auth.users u on u.id = p.id where u.email = '${email}';`),
    ).toBe(`${username} 1990-05-05`);
    nessunaPasswordNellaDiagnostica(diagnostica.eventi, password);
    await contesto.close();
  });

  test("accesso dal modulo /accedi con credenziali valide: la sessione apre le pagine private", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoNuovo(browser, info);
    const page = await contesto.newPage();
    diagnostica.osserva(page, "utente");
    await accediDalModulo(page, email, password);
    await expect(page).toHaveURL(/\/account/);
    await attendiCaricamento(page);
    await expect(page.getByRole("heading", { name: "Il tuo profilo" })).toBeVisible();
    await page.goto("/vendi");
    await attendiCaricamento(page);
    await expect(page.getByRole("heading", { name: "Accedi per catalogare o vendere" })).toHaveCount(0);
    await expect(page.getByRole("heading", { name: "Aggiungi una bottiglia" })).toBeVisible();

    // Uscita dall'interfaccia: la sessione sparisce e le pagine private tornano a chiedere l'accesso.
    cookieRevocati = await cookieDiSessione(contesto);
    expect(cookieRevocati.length).toBeGreaterThan(0);
    await page.goto("/account");
    await attendiCaricamento(page);
    await page.getByTestId("logout").click();
    await expect(page.getByRole("heading", { name: "Serve prima l'accesso" })).toBeVisible();
    expect(await cookieDiSessione(contesto)).toEqual([]);
    await page.reload();
    await attendiCaricamento(page);
    await expect(page.getByRole("heading", { name: "Serve prima l'accesso" })).toBeVisible();
    nessunaPasswordNellaDiagnostica(diagnostica.eventi, password);
    await contesto.close();
  });

  test("i cookie di una sessione chiusa con «Esci» non riaprono l'account", async ({ browser, diagnostica }, info) => {
    expect(cookieRevocati.length).toBeGreaterThan(0);
    const contesto = await contestoNuovo(browser, info);
    await contesto.addCookies(cookieRevocati);
    const page = await contesto.newPage();
    diagnostica.osserva(page, "sessione revocata");
    // GoTrue rifiuta la sessione chiusa (403 su /auth/v1/user): è il rifiuto che il caso vuole vedere.
    diagnostica.ammetti("/auth/v1/user");
    await page.goto("/account");
    await attendiCaricamento(page);
    await expect(page.getByRole("heading", { name: "Serve prima l'accesso" })).toBeVisible();
    await expect(page.getByText(email)).toHaveCount(0);
    await contesto.close();
  });

  test("un cookie di sessione manomesso vale come nessuna sessione, senza errori del server", async ({ browser, diagnostica }, info) => {
    expect(cookieRevocati.length).toBeGreaterThan(0);
    const contesto = await contestoNuovo(browser, info);
    await contesto.addCookies([{ ...cookieRevocati[0], value: `base64-${Buffer.from('{"access_token":"manomesso"}').toString("base64")}` }]);
    const page = await contesto.newPage();
    diagnostica.osserva(page, "sessione manomessa");
    diagnostica.ammetti("/auth/v1/user");
    const risposta = await page.goto("/account");
    expect(risposta?.status()).toBeLessThan(500);
    await attendiCaricamento(page);
    await expect(page.getByRole("heading", { name: "Serve prima l'accesso" })).toBeVisible();
    await contesto.close();
  });

  test("credenziali errate: rifiuto visibile, nessuna sessione, si resta su /accedi", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoNuovo(browser, info);
    const page = await contesto.newPage();
    diagnostica.osserva(page, "credenziali errate");
    // GoTrue risponde 400 alle credenziali sbagliate: è l'esito atteso.
    diagnostica.ammetti("/auth/v1/token", "status of 400");
    const sbagliata = passwordNuova();
    await accediDalModulo(page, email, sbagliata);
    await expect(page.getByTestId("errore-password")).toBeVisible();
    await expect(page).toHaveURL(/\/accedi/);
    expect(await cookieDiSessione(contesto)).toEqual([]);
    await page.goto("/account");
    await attendiCaricamento(page);
    await expect(page.getByRole("heading", { name: "Serve prima l'accesso" })).toBeVisible();
    nessunaPasswordNellaDiagnostica(diagnostica.eventi, password, sbagliata);
    await contesto.close();
  });

  test("recupero password: la pagina risponde allo stesso modo a un iscritto con invio fallito e a un indirizzo sconosciuto (R-AUTH-01)", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoNuovo(browser, info);
    const page = await contesto.newPage();
    diagnostica.osserva(page, "recupero");
    // Lo stack dedicato non avvia Mailpit: per un iscritto GoTrue fallisce l'invio (500, oppure 429 se il
    // budget `email_sent` è esaurito). È il guasto che il caso vuole: non lo si simula, lo si osserva.
    diagnostica.ammetti("/auth/v1/recover");
    const esiti: string[] = [];
    const statiProvider: number[] = [];
    for (const indirizzo of [email, `assente-${tag}@e2e-12zk.test`]) {
      await page.goto("/accedi");
      await attendiCaricamento(page);
      await page.getByLabel("Email", { exact: true }).fill(indirizzo);
      const risposta = page.waitForResponse((r) => r.url().includes("/auth/v1/recover") && r.request().method() === "POST");
      await page.getByTestId("password-dimenticata").click();
      statiProvider.push((await risposta).status());
      const esito = page.getByTestId("recupero-inviato").or(page.getByTestId("errore-recupero"));
      await expect(esito).toBeVisible();
      esiti.push(`${await esito.getAttribute("data-testid")}: ${await esito.innerText()}`);
    }
    await info.attach("esiti-recupero.json", { body: JSON.stringify({ esiti, statiProvider }, null, 2), contentType: "application/json" });
    // Un indirizzo sconosciuto: GoTrue risponde 200 senza cercare oltre, la pagina dà la conferma neutra.
    expect(statiProvider[1]).toBe(200);
    expect(esiti[1]).toMatch(/^recupero-inviato: Se esiste un account associato a questa email/);
    // Un iscritto: GoTrue ha davvero fallito l'invio (senza questo il caso proverebbe solo il successo)...
    expect(statiProvider[0], "senza Mailpit l'invio a un iscritto deve fallire: il caso esercita il guasto").not.toBe(200);
    // ...e la pagina mostra lo STESSO testo dell'indirizzo sconosciuto.
    expect(esiti[0]).toBe(esiti[1]);

    // Il provider resta un oracolo per chi chiama `/auth/v1/recover` direttamente con la chiave anon
    // (mitigazione PARZIALE): lo si misura dal protocollo e lo si annota, senza farne un verde.
    const { apiUrl, anonKey } = risolviBersaglio();
    const sonda = async (indirizzo: string) => {
      const r = await fetch(`${apiUrl}/auth/v1/recover`, {
        method: "POST",
        headers: { apikey: anonKey, "Content-Type": "application/json" },
        body: JSON.stringify({ email: indirizzo }),
        signal: AbortSignal.timeout(10_000),
      });
      const corpo = (await r.json().catch(() => ({}))) as { error_code?: string };
      return `${r.status} ${corpo.error_code ?? ""}`.trim();
    };
    info.annotations.push({
      type: "R-AUTH-01 residuo del provider",
      description: `pagina: identica | GoTrue dal browser: registrato ${statiProvider[0]}, non registrato ${statiProvider[1]} | GoTrue diretto: registrato ${await sonda(email)}, non registrato ${await sonda(`assente2-${tag}@e2e-12zk.test`)}`,
    });
    await contesto.close();
  });
});

/**
 * Modulo di accesso nei tre profili (Chromium desktop, Chromium 375 px, WebKit).
 * L'utente nasce per ogni progetto dalla porta reale di GoTrue (`/auth/v1/signup`),
 * con una password nuova digitata solo nel modulo.
 */
test.describe("Autenticazione dal browser: modulo di accesso cross-browser @cross", () => {
  const tag = etichettaCorsa();
  const email = `crit-x-${tag}@e2e-12zk.test`;
  const password = passwordNuova();

  test.beforeAll(async () => {
    ripristinaFixture(passwordFixture());
    const { apiUrl, anonKey } = risolviBersaglio();
    const res = await fetch(`${apiUrl}/auth/v1/signup`, {
      method: "POST",
      headers: { apikey: anonKey, "Content-Type": "application/json" },
      body: JSON.stringify({ email, password, data: { username: `e2ecritx_${tag}`, dob: "1988-03-03" } }),
    });
    if (!res.ok) throw new Error(`Utente di prova non creato: HTTP ${res.status}`);
  });

  test("accesso valido e uscita in ogni motore, con rifiuto delle credenziali di un altro utente", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoNuovo(browser, info);
    const page = await contesto.newPage();
    diagnostica.osserva(page, "utente");
    diagnostica.ammetti("/auth/v1/token", "status of 400");
    const sbagliata = passwordNuova();

    // Email reale della fixture, password inventata: rifiutata.
    await accediDalModulo(page, EMAIL.altro, sbagliata);
    await expect(page.getByTestId("errore-password")).toBeVisible();
    expect(await cookieDiSessione(contesto)).toEqual([]);

    await accediDalModulo(page, email, password);
    await expect(page).toHaveURL(/\/account/);
    await attendiCaricamento(page);
    await expect(page.getByText(email)).toBeVisible();
    await page.getByTestId("logout").click();
    await expect(page.getByRole("heading", { name: "Serve prima l'accesso" })).toBeVisible();
    expect(await cookieDiSessione(contesto)).toEqual([]);
    nessunaPasswordNellaDiagnostica(diagnostica.eventi, password, sbagliata);
    await contesto.close();
  });
});
