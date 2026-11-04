import { randomBytes } from "node:crypto";
import { createServerClient } from "@supabase/ssr";
import type { Browser, BrowserContext, Page, TestInfo } from "@playwright/test";
import { passwordFixture } from "./support/api";
import { contestoAutenticato, opzioniDelProgetto } from "./support/browser";
import { ripristinaFixture } from "./support/db";
import { attendiCaricamento, problemiAccessibilita, senzaScorrimentoOrizzontale } from "./support/pagina";
import { risolviBersaglio } from "./support/stack";
import { expect, test } from "./support/test";
import { etichettaCorsa, preparaBottigliaInCantina } from "./support/vino";

/**
 * VPM-018-UX-FIX-03: difetti piccoli e indipendenti dell'audit UX, misurati nel browser
 * su Chromium desktop, Chromium 375 px e WebKit. La geometria è la prova: i contratti
 * sul testo dei sorgenti non dicono cosa sta sotto a cosa.
 */

const SEGNAPOSTO_ABBINAMENTO = "Cosa prepari? es. brasato, risotto";
const ID_INESISTENTE = "00000000-0000-4000-8000-000000000000";

/** Dopo la verifica della sessione: l'overlay dell'AgeGate coprirebbe ciò che si vuole vedere. */
const fotografa = async (page: Page, info: TestInfo, nome: string) => {
  await expect(page.getByRole("status").filter({ hasText: /^Verifica d/ })).toHaveCount(0);
  await page.screenshot({ path: info.outputPath(`${nome}.png`) });
};

/**
 * Un utente appena nato senza data di nascita: lo stato di chi entra per la prima volta
 * con Google. La password nasce qui, non tocca il browser; il dominio della fixture lo
 * affida alla pulizia di fine corsa. Sessione nei cookie, come `contestoAutenticato`.
 */
const contestoSenzaDataDiNascita = async (browser: Browser, info: TestInfo): Promise<BrowserContext> => {
  const { apiUrl, anonKey } = risolviBersaglio();
  const catturati: { name: string; value: string }[] = [];
  const client = createServerClient(apiUrl, anonKey, {
    cookies: {
      getAll: () => [],
      setAll: (cookies) => {
        for (const { name, value } of cookies) catturati.push({ name, value });
      },
    },
  });
  const email = `ux-${randomBytes(6).toString("hex")}@e2e-12zk.test`;
  const { error } = await client.auth.signUp({ email, password: `Vinea-${randomBytes(9).toString("hex")}Aa1!` });
  if (error || catturati.length === 0) throw new Error("Utente senza data di nascita non creato.");
  const contesto = await browser.newContext(opzioniDelProgetto(info));
  const host = new URL(info.project.use.baseURL ?? "http://127.0.0.1:3187").hostname;
  await contesto.addCookies(
    catturati.map(({ name, value }) => ({ name, value, domain: host, path: "/", httpOnly: false, secure: false })),
  );
  return contesto;
};

test.describe("UX-FIX-03 moduli di accesso @cross", () => {
  test("/completa-profilo: requisiti subito sotto la password, prima della conferma", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoSenzaDataDiNascita(browser, info);
    const page = await contesto.newPage();
    diagnostica.osserva(page, "senza data di nascita");
    await page.goto("/completa-profilo");
    await attendiCaricamento(page);

    const campo = page.getByTestId("password-vinea");
    const conferma = page.getByTestId("password-vinea-conferma");
    const requisiti = page.getByTestId("requisiti-password");
    await expect(requisiti).toBeVisible();
    await fotografa(page, info, "completa-profilo");

    const [c, r, f] = await Promise.all([campo.boundingBox(), requisiti.boundingBox(), conferma.boundingBox()]);
    if (!c || !r || !f) throw new Error("Geometria non disponibile.");
    expect(r.y).toBeGreaterThanOrEqual(c.y + c.height - 1);
    expect(r.y - (c.y + c.height)).toBeLessThan(24);
    expect(f.y).toBeGreaterThanOrEqual(r.y + r.height - 1);

    const descrizione = await campo.getAttribute("aria-describedby");
    expect(descrizione).toBe("requisiti-password-vinea");
    await expect(page.locator(`#${descrizione}`)).toHaveAttribute("data-testid", "requisiti-password");

    await campo.focus();
    await page.keyboard.press("Tab");
    await expect(conferma).toBeFocused();

    expect(await senzaScorrimentoOrizzontale(page)).toBe(true);
    expect(await problemiAccessibilita(page), "/completa-profilo").toEqual([]);
    await contesto.close();
  });

  test("/registrati: la data di nascita occupa la riga come la password", async ({ browser, diagnostica }, info) => {
    const contesto = await browser.newContext(opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "nuovo utente");
    await page.goto("/registrati");
    await attendiCaricamento(page);
    await fotografa(page, info, "registrati");

    const [password, dob] = await Promise.all([
      page.getByTestId("password-registrazione").boundingBox(),
      page.getByLabel("Data di nascita").boundingBox(),
    ]);
    if (!password || !dob) throw new Error("Geometria non disponibile.");
    expect(Math.abs(password.width - dob.width)).toBeLessThan(2);
    expect(Math.abs(password.x - dob.x)).toBeLessThan(2);
    expect(await senzaScorrimentoOrizzontale(page)).toBe(true);
    await contesto.close();
  });
});

test.describe("UX-FIX-03 wizard /vendi @cross", () => {
  const nome = `Barolo E2E-UX3 ${etichettaCorsa()}`;
  let bottigliaId = "";

  test.beforeAll(async () => {
    ripristinaFixture(passwordFixture());
    bottigliaId = (await preparaBottigliaInCantina("venditore", { nome })).bottleUnitIds[0];
  });

  test("la barra delle azioni resta ordinata e nessun pulsante va a capo", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    await page.goto(`/vendi?mode=sell&bottiglia=${bottigliaId}`);
    await attendiCaricamento(page);

    const continua = page.getByRole("button", { name: /Continua/ });
    await continua.click();
    await continua.scrollIntoViewIfNeeded();
    await fotografa(page, info, "vendi-barra");

    const indietro = page.getByRole("button", { name: "Indietro" });
    const bozza = page.getByRole("button", { name: "Salva bozza" });
    const [i, b, c] = await Promise.all([indietro.boundingBox(), bozza.boundingBox(), continua.boundingBox()]);
    if (!i || !b || !c) throw new Error("Geometria non disponibile.");

    // Le azioni secondarie stanno insieme: «Indietro» non resta da solo su una riga.
    expect(Math.abs(i.y - b.y)).toBeLessThan(2);
    // Un pulsante a una riga è alto come gli altri: il testo non è andato a capo.
    expect(Math.abs(i.height - b.height)).toBeLessThan(2);
    expect(Math.abs(c.height - b.height)).toBeLessThan(2);
    expect(c.height).toBeLessThan(48);

    const stretta = (page.viewportSize()?.width ?? 1280) < 640;
    if (stretta) {
      // A 375 px l'azione principale ha la riga tutta per sé, sotto le altre due.
      expect(c.y).toBeGreaterThanOrEqual(i.y + i.height - 1);
      expect(c.width).toBeGreaterThan(i.width + b.width);
    } else {
      expect(Math.abs(i.y - c.y)).toBeLessThan(2);
    }
    expect(await senzaScorrimentoOrizzontale(page)).toBe(true);
    await contesto.close();
  });

  test("l'ultimo passo senza vendita: l'etichetta lunga resta dentro il pulsante", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    await page.goto("/vendi");
    await attendiCaricamento(page);
    await page.getByRole("button", { name: /cantina pubblica/i }).first().click();

    const continua = page.getByRole("button", { name: /Continua/ });
    for (let passo = 0; passo < 8 && (await continua.count()) > 0; passo++) {
      if (await page.locator("#vendi-produttore").isVisible()) {
        await page.locator("#vendi-produttore").fill("Cantina di prova");
        await page.locator("#vendi-nome").fill("Vino di prova");
        await page.locator("#vendi-annata").fill("2016");
        await page.locator("#vendi-regione").click();
        await page.getByRole("option").first().click();
      }
      await continua.click();
    }
    const finale = page.getByRole("button", { name: "Aggiungi alla cantina pubblica" });
    await expect(finale).toBeVisible();
    await finale.scrollIntoViewIfNeeded();
    await fotografa(page, info, "vendi-ultimo-passo");

    const dentro = await finale.evaluate((b) => b.scrollWidth <= b.clientWidth + 1);
    expect(dentro, "il testo non esce dal pulsante").toBe(true);
    const [f, i] = await Promise.all([finale.boundingBox(), page.getByRole("button", { name: "Indietro" }).boundingBox()]);
    if (!f || !i) throw new Error("Geometria non disponibile.");
    expect(f.x + f.width).toBeLessThanOrEqual((page.viewportSize()?.width ?? 1280) + 1);
    if ((page.viewportSize()?.width ?? 1280) < 640) expect(f.y).toBeGreaterThanOrEqual(i.y + i.height - 1);
    expect(await senzaScorrimentoOrizzontale(page)).toBe(true);
    await contesto.close();
  });

  test("toccando l'etichetta si apre il selettore della regione (TEST-B3)", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    // Il selettore esiste solo per una bottiglia nuova: da Cantina il vino è già noto.
    await page.goto("/vendi");
    await attendiCaricamento(page);
    const identificazione = page.getByRole("heading", { name: "Identificazione", exact: true });
    for (let passo = 0; passo < 3 && !(await identificazione.isVisible()); passo++) {
      await page.getByRole("button", { name: /Continua/ }).click();
    }
    await expect(identificazione).toBeVisible();

    const selettore = page.locator("#vendi-regione");
    await expect(selettore).toBeEnabled();
    await expect(selettore).toHaveAttribute("aria-expanded", "false");
    await page.locator('label[for="vendi-regione"]').click();
    await expect(page.getByRole("listbox")).toBeVisible();
    await expect(selettore).toHaveAttribute("aria-expanded", "true");
    await page.keyboard.press("Escape");
    await expect(page.getByRole("listbox")).toHaveCount(0);
    await contesto.close();
  });
});

test.describe("UX-FIX-03 404 annidati @cross", () => {
  for (const { percorso, titolo, messaggio, nome } of [
    { percorso: `/annuncio/${ID_INESISTENTE}`, titolo: "Annuncio non trovato", messaggio: /venduto o rimosso/, nome: "404-annuncio" },
    { percorso: `/checkout/${ID_INESISTENTE}`, titolo: "Annuncio non trovato", messaggio: /venduto o rimosso/, nome: "404-checkout" },
    { percorso: `/profilo/${ID_INESISTENTE}`, titolo: "Profilo non disponibile", messaggio: /non è disponibile/, nome: "404-profilo" },
  ]) {
    test(`${percorso}: stessa struttura del 404 di root, con testo proprio`, async ({ browser, diagnostica }, info) => {
      const contesto = await browser.newContext(opzioniDelProgetto(info));
      const page = await contesto.newPage();
      diagnostica.osserva(page, "ospite");
      diagnostica.ammetti(percorso); // il documento risponde 404: è ciò che si prova
      const risposta = await page.goto(percorso);
      expect(risposta?.status()).toBe(404);
      await attendiCaricamento(page);
      await fotografa(page, info, nome);

      await expect(page.getByRole("heading", { level: 1, name: titolo })).toHaveCount(1);
      await expect(page.getByRole("main").getByText("404", { exact: true })).toBeVisible();
      await expect(page.getByRole("main").getByText(messaggio)).toBeVisible();
      await expect(page.getByRole("main").getByRole("link")).toHaveCount(2);
      expect(await senzaScorrimentoOrizzontale(page)).toBe(true);
      await contesto.close();
    });
  }
});

test.describe("UX-FIX-03 stati vuoti e ricerca @cross", () => {
  test("/messaggi vuoto: il titolo si vede, non è solo per gli screen reader", async ({ browser, diagnostica }, info) => {
    ripristinaFixture(passwordFixture());
    const contesto = await contestoAutenticato(browser, "segnalante", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "segnalante");
    await page.goto("/messaggi");
    await attendiCaricamento(page);
    await expect(page.getByText("Nessuna conversazione")).toBeVisible();
    await fotografa(page, info, "messaggi-vuoto");

    const titolo = page.getByRole("heading", { level: 1, name: "Messaggi" });
    await expect(titolo).toHaveCount(1);
    const box = await titolo.boundingBox();
    if (!box) throw new Error("Titolo senza geometria.");
    expect(box.height).toBeGreaterThan(20);
    expect(box.width).toBeGreaterThan(50);
    await contesto.close();
  });

  test("il segnaposto dell'abbinamento entra nel campo di ricerca (UX-B7)", async ({ browser, diagnostica }, info) => {
    const contesto = await browser.newContext(opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "ospite");
    await page.goto("/esplora");
    await attendiCaricamento(page);

    // La modalità abbinamento è dietro la flag IA, spenta nella prova: si misura la stringa
    // con il carattere e la larghezza reali del campo.
    const misura = (testo: string) =>
      page.getByTestId("esplora-search-input").locator("visible=true").evaluate((campo, t) => {
        const stile = getComputedStyle(campo);
        const contesto2d = document.createElement("canvas").getContext("2d");
        if (!contesto2d) throw new Error("Canvas non disponibile.");
        contesto2d.font = `${stile.fontStyle} ${stile.fontWeight} ${stile.fontSize} ${stile.fontFamily}`;
        const utile = campo.clientWidth - parseFloat(stile.paddingLeft) - parseFloat(stile.paddingRight);
        return { testo: Math.ceil(contesto2d.measureText(t).width), utile: Math.floor(utile) };
      }, testo);

    const nuovo = await misura(SEGNAPOSTO_ABBINAMENTO);
    const vecchio = await misura("Cosa stai preparando? es. brasato, ostriche, risotto…");
    info.annotations.push({
      type: "misura",
      description: `spazio ${nuovo.utile} px; nuovo ${nuovo.testo} px; precedente ${vecchio.testo} px`,
    });
    expect(nuovo.testo).toBeLessThanOrEqual(nuovo.utile);
    await contesto.close();
  });
});
