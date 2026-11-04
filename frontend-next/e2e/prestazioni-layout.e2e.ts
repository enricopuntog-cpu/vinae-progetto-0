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

test.describe("Stabilità del layout al caricamento @cross", () => {
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
    expect(await clsDopoIlCaricamento(page)).toBeLessThanOrEqual(0.1);

    await expect(page.getByRole("heading", { name: /mia cantina/ })).toBeVisible();
    await page.screenshot({ path: info.outputPath("cantina-hero.png") });
    // Un solo hero: niente doppioni fra il guscio di caricamento e la pagina.
    await expect(page.getByRole("heading", { name: /mia cantina/ })).toHaveCount(1);
    expect(await senzaScorrimentoOrizzontale(page)).toBe(true);
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
