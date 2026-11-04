import type { Page } from "@playwright/test";
import { passwordFixture } from "./support/api";
import { contestoAutenticato, opzioniDelProgetto } from "./support/browser";
import { ripristinaFixture } from "./support/db";
import { attendiCaricamento, senzaScorrimentoOrizzontale } from "./support/pagina";
import { expect, test } from "./support/test";
import { etichettaCorsa, preparaBottigliaInCantina } from "./support/vino";

/**
 * VPM-018-PERF-01, misura di LABORATORIO usata come guardia di regressione: sulla build di
 * produzione `/cantina` e il wizard non devono spostare la pagina al caricamento. Non sono Core
 * Web Vitals reali. Solo Chromium: WebKit non espone `layout-shift`.
 */
const osservaSpostamenti = () => {
  const stato = { cls: 0 };
  (window as unknown as { __cls: typeof stato }).__cls = stato;
  new PerformanceObserver((lista) => {
    for (const voce of lista.getEntries() as (PerformanceEntry & { hadRecentInput: boolean; value: number })[]) {
      if (!voce.hadRecentInput) stato.cls += voce.value;
    }
  }).observe({ type: "layout-shift", buffered: true });
};

const clsDopoIlCaricamento = async (page: Page): Promise<number> => {
  await attendiCaricamento(page);
  await page.waitForLoadState("networkidle", { timeout: 30_000 }).catch(() => undefined);
  await page.waitForTimeout(800);
  return page.evaluate(() => (window as unknown as { __cls: { cls: number } }).__cls.cls);
};

test.describe("Stabilità del layout al caricamento @smoke @cross", () => {
  const nome = `Barolo E2E-PERF ${etichettaCorsa()}`;
  let bottigliaId = "";

  test.beforeAll(async () => {
    ripristinaFixture(passwordFixture());
    bottigliaId = (await preparaBottigliaInCantina("venditore", { nome, costoAcquistoCents: 3700 })).bottleUnitIds[0];
  });

  test("/cantina con sessione: spostamenti ≤ 0,1 e hero già nel primo HTML", async ({ browser, browserName, diagnostica }, info) => {
    test.skip(browserName !== "chromium", "WebKit non espone layout-shift");
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    await page.addInitScript(osservaSpostamenti);
    const risposta = await page.goto("/cantina");
    const html = (await risposta?.text()) ?? "";
    expect(html).toMatch(/<img[^>]*vinea-cellar/);
    // Il guscio arriva già coperto dall'AgeGate, con i pulsanti esclusi dalla tastiera, e la
    // risposta non è riutilizzabile: l'HTML cambia in base al cookie di sessione.
    expect(html).toContain("Verifica dell");
    expect(html).toMatch(/<div[^>]*\binert\b[^>]*>(?:(?!<\/section>)[\s\S])*\/vendi\?mode=catalog/);
    expect(risposta?.headers()["cache-control"]).toBe("private, no-store");
    expect(await clsDopoIlCaricamento(page)).toBeLessThanOrEqual(0.1);

    // Finita l'attesa i pulsanti tornano utilizzabili. `attendiCaricamento` non riconosce
    // «Verifica del profilo…», e questo controllo non ritenta: si aspetta qui.
    await expect(page.getByText("Verifica del profilo")).toHaveCount(0);
    const aggiungi = page.getByRole("link", { name: "Aggiungi bottiglia" });
    await expect(aggiungi).toBeVisible();
    expect(await aggiungi.evaluate((el) => el.closest("[inert]") === null)).toBe(true);

    await expect(page.getByRole("heading", { name: /mia cantina/ })).toBeVisible();
    await page.screenshot({ path: info.outputPath("cantina-hero.png") });
    // Un solo hero: niente doppioni fra il guscio di caricamento e la pagina.
    await expect(page.getByRole("heading", { name: /mia cantina/ })).toHaveCount(1);
    expect(await senzaScorrimentoOrizzontale(page)).toBe(true);
    await contesto.close();
  });

  test("se il grafico non arriva, la Cantina resta in piedi", async ({ browser, browserName }, info) => {
    test.skip(browserName !== "chromium", "un solo motore basta: il confine non dipende dal browser");
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    // Si fa fallire solo il pezzo di JavaScript che contiene recharts, riconosciuto dal contenuto
    // perché il nome del file cambia a ogni build. Niente `diagnostica`: l'errore è voluto.
    let bloccati = 0;
    await page.route("**/_next/static/chunks/*.js", async (route) => {
      const risposta = await route.fetch();
      if ((await risposta.text()).includes("recharts-")) {
        bloccati += 1;
        await route.abort();
      } else {
        await route.fulfill({ response: risposta });
      }
    });
    await page.goto("/cantina");
    await attendiCaricamento(page);
    await expect(page.getByText("Grafico non disponibile")).toBeVisible();
    await expect(page.getByRole("heading", { name: /mia cantina/ })).toBeVisible();
    expect(bloccati).toBeGreaterThan(0);
    await page.unrouteAll({ behavior: "ignoreErrors" });
    await contesto.close();
  });

  test("i pulsanti dell'hero seguono l'overlay dell'AgeGate, non il caricamento della Cantina", async ({ browser, browserName }, info) => {
    test.skip(browserName !== "chromium", "un solo motore basta: è una condizione dello stato");
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    // La lettura del profilo dell'AgeGate, l'unica che chiede `dob`, resta in sospeso: la Cantina
    // arriva prima e l'overlay rimane. Anche la Cantina legge `profiles`, ma altre colonne.
    let rilascia = () => {};
    const profiloLibero = new Promise<void>((risolvi) => {
      rilascia = risolvi;
    });
    await page.route("**/rest/v1/profiles*", async (route) => {
      if (route.request().url().includes("dob")) await profiloLibero;
      await route.fallback();
    });
    await page.goto("/cantina");
    const overlay = page.getByText("Verifica del profilo");
    await expect(overlay).toBeVisible();
    await expect(page.getByText("Bottiglie", { exact: true }).first()).toBeAttached();
    const aggiungi = page.locator('a[href="/vendi?mode=catalog"]').first();
    expect(await aggiungi.evaluate((el) => el.closest("[inert]") !== null)).toBe(true);

    rilascia();
    await expect(overlay).toHaveCount(0);
    expect(await aggiungi.evaluate((el) => el.closest("[inert]") === null)).toBe(true);
    await page.unrouteAll({ behavior: "ignoreErrors" });

    // Il caso opposto: overlay finito e Cantina ancora in lettura, i pulsanti visibili rispondono.
    const pagina2 = await contesto.newPage();
    let rilascia2 = () => {};
    const cantinaLibera = new Promise<void>((risolvi) => {
      rilascia2 = risolvi;
    });
    await pagina2.route("**/rest/v1/bottle_units*", async (route) => {
      await cantinaLibera;
      await route.fallback();
    });
    await pagina2.goto("/cantina");
    await expect(pagina2.getByText("Carico la tua cantina")).toBeVisible();
    await expect(pagina2.getByText(/^Verifica d/)).toHaveCount(0);
    const aggiungi2 = pagina2.locator('a[href="/vendi?mode=catalog"]').first();
    expect(await aggiungi2.evaluate((el) => el.closest("[inert]") === null)).toBe(true);
    rilascia2();
    await pagina2.unrouteAll({ behavior: "ignoreErrors" });
    await contesto.close();
  });

  test("wizard con sessione: spostamenti ≤ 0,1 e nessun fondale scaricato", async ({ browser, browserName, diagnostica }, info) => {
    test.skip(browserName !== "chromium", "WebKit non espone layout-shift");
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    const immagini: string[] = [];
    page.on("request", (r) => {
      if (r.resourceType() === "image") immagini.push(r.url());
    });
    await page.addInitScript(osservaSpostamenti);
    await page.goto(`/vendi?mode=sell&bottiglia=${bottigliaId}`);
    expect(await clsDopoIlCaricamento(page)).toBeLessThanOrEqual(0.1);
    expect(immagini.filter((u) => u.includes("vinea-crate"))).toEqual([]);
    await expect(page.getByRole("heading", { name: "Vendi la tua bottiglia" })).toBeVisible();
    await contesto.close();
  });

  test("un ospite non riceve né scarica l'immagine della pagina privata", async ({ browser, diagnostica }, info) => {
    const contesto = await browser.newContext(opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "ospite");
    const immagini: string[] = [];
    page.on("request", (r) => {
      if (r.resourceType() === "image") immagini.push(r.url());
    });
    const risposta = await page.goto("/cantina");
    expect((await risposta?.text()) ?? "").not.toContain("vinea-cellar");
    await attendiCaricamento(page);
    await expect(page.getByRole("heading", { name: "Accedi per vedere la tua cantina" })).toBeVisible();
    expect(immagini.filter((u) => u.includes("vinea-cellar"))).toEqual([]);
    await contesto.close();
  });
});
