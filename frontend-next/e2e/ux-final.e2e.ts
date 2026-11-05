import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import type { Locator, Page, TestInfo } from "@playwright/test";
import { passwordFixture } from "./support/api";
import { contestoAutenticato, opzioniDelProgetto } from "./support/browser";
import { ripristinaFixture } from "./support/db";
import { attendiCaricamento, senzaScorrimentoOrizzontale } from "./support/pagina";
import { expect, test } from "./support/test";
import { preparaBottigliaInCantina, pubblicaAnnuncioVino } from "./support/vino";

const prima = process.env.VITE_BASELINE === "1";
const cartella = (info: TestInfo) => {
  const dir = path.resolve("e2e/artifacts/ux-final", prima ? "prima" : "dopo", info.project.name);
  mkdirSync(dir, { recursive: true });
  return dir;
};

// Il canvas risolve anche color(srgb ...) e oklab restituiti da Tailwind 4.
// Componiamo separatamente pixel del testo e dello sfondo, poi l'opacità di
// ogni gruppo antenato: non basta leggere il solo token del testo.
async function contrasto(elemento: Locator) {
  return elemento.evaluate((el) => {
    const ctx = document.createElement("canvas").getContext("2d", { willReadFrequently: true })!;
    const colore = (css: string): number[] => {
      ctx.clearRect(0, 0, 1, 1);
      ctx.fillStyle = css;
      ctx.fillRect(0, 0, 1, 1);
      const p = [...ctx.getImageData(0, 0, 1, 1).data];
      return [p[0], p[1], p[2], p[3] / 255];
    };
    const sopra = (a: number[], b: number[]) => {
      const alpha = a[3] + b[3] * (1 - a[3]);
      return [...[0, 1, 2].map((i) => alpha ? (a[i] * a[3] + b[i] * b[3] * (1 - a[3])) / alpha : 0), alpha];
    };
    const stile = getComputedStyle(el);
    let testo = colore(stile.color);
    let fondo = [0, 0, 0, 0];
    const strati: { background: string; opacity: string }[] = [];
    for (let nodo: Element | null = el; nodo; nodo = nodo.parentElement) {
      const s = getComputedStyle(nodo);
      if (s.backgroundImage !== "none") throw new Error("Sfondo immagine: contrasto non certificabile con questa misura.");
      strati.push({ background: s.backgroundColor, opacity: s.opacity });
      const bg = colore(s.backgroundColor);
      testo = sopra(testo, bg);
      fondo = sopra(fondo, bg);
      testo[3] *= Number(s.opacity);
      fondo[3] *= Number(s.opacity);
    }
    testo = sopra(testo, [255, 255, 255, 1]);
    fondo = sopra(fondo, [255, 255, 255, 1]);
    const luminanza = (c: number[]) => c.slice(0, 3).map((n) => n / 255)
      .map((n) => n <= 0.04045 ? n / 12.92 : ((n + 0.055) / 1.055) ** 2.4)
      .reduce((sum, n, i) => sum + n * [0.2126, 0.7152, 0.0722][i], 0);
    const a = luminanza(testo), b = luminanza(fondo);
    return { color: stile.color, fontSize: stile.fontSize, testo, fondo, strati, rapporto: (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05) };
  });
}

async function pronto(page: Page) {
  await attendiCaricamento(page);
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  await expect(page.getByText("Verifica del profilo")).toHaveCount(0);
  await page.evaluate(() => document.fonts.ready);
}

test.describe("UX final @cross", () => {
  let slug = "";
  test.beforeAll(async () => {
    ripristinaFixture(passwordFixture());
    const vino = await preparaBottigliaInCantina("venditore", { nome: "Barolo UX Final", quantita: 2 });
    slug = (await pubblicaAnnuncioVino("venditore", vino.bottleUnitIds[0], 4200)).slug;
  });

  test("salvia: contrasto composto di FoodPairing e bottle-selector", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    const misure: Record<string, Awaited<ReturnType<typeof contrasto>>> = {};
    await page.goto(`/annuncio/${slug}`);
    await pronto(page);
    const badge = page.getByText("ottimo", { exact: true }).first();
    await expect(badge).toBeVisible();
    misure.ottimo = await contrasto(badge);
    await badge.locator("../../..").screenshot({ path: path.join(cartella(info), "food-pairing.png") });
    await page.getByRole("button", { name: "Cosa stai preparando?" }).click();
    await page.getByPlaceholder("es. brasato, ostriche, ragù…").fill("pecorino");
    const esito = page.getByText("Questo vino è adatto (ottimo).");
    await expect(esito).toBeVisible();
    misure.abbinamento = await contrasto(esito);
    await page.getByRole("dialog").screenshot({ path: path.join(cartella(info), "abbinamento.png") });
    await page.getByRole("button", { name: "Chiudi", exact: true }).click();
    await page.goto("/vendi?mode=sell");
    await pronto(page);
    const produttore = page.getByText("Cantina E2E-CRIT", { exact: true }).first();
    await expect(produttore).toBeVisible();
    misure.bottleSelector = await contrasto(produttore);
    writeFileSync(path.join(cartella(info), "contrasti.json"), JSON.stringify(misure, null, 2));
    if (!prima) for (const [nome, misura] of Object.entries(misure)) expect(misura.rapporto, nome).toBeGreaterThanOrEqual(4.5);
    await contesto.close();
  });

  test("Cantina: tutte le tab leggibili e azionabili a 375 e 320 px", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    await page.goto("/cantina");
    await pronto(page);
    const misure = [];
    for (const width of [375, 320]) {
      await page.setViewportSize({ width, height: 812 });
      const primaTab = page.getByRole("tab", { name: "Tutte", exact: true });
      const ultima = page.getByRole("tab", { name: "Da attendere", exact: true });
      const lista = primaTab.locator("..");
      await primaTab.scrollIntoViewIfNeeded();
      const geometria = await lista.evaluate((el) => ({ client: el.clientWidth, scroll: el.scrollWidth, viewport: innerWidth, rect: el.getBoundingClientRect().toJSON(), tabs: [...el.children].map((t) => ({ testo: t.textContent, rect: t.getBoundingClientRect().toJSON(), client: t.clientWidth, scroll: t.scrollWidth })) }));
      misure.push({ width, ...geometria });
      await page.screenshot({ path: path.join(cartella(info), `cantina-${width}.png`) });
      if (!prima) {
        expect(await senzaScorrimentoOrizzontale(page)).toBe(true);
        for (const tab of geometria.tabs) {
          expect(tab.rect.x).toBeGreaterThanOrEqual(0);
          expect(tab.rect.right).toBeLessThanOrEqual(width);
          expect(tab.scroll).toBeLessThanOrEqual(tab.client + 1);
        }
        await primaTab.focus();
        await page.keyboard.press("End");
        await expect(ultima).toBeFocused();
        await expect(ultima).toHaveAttribute("aria-selected", "true");
        await expect(page.getByRole("tabpanel")).toBeVisible();
        await page.keyboard.press("Home");
        await expect(primaTab).toBeFocused();
        if (info.project.use.hasTouch) await ultima.tap();
        else await ultima.click();
        await expect(ultima).toHaveAttribute("aria-selected", "true");
        await primaTab.click();
      }
    }
    writeFileSync(path.join(cartella(info), "cantina-geometria.json"), JSON.stringify(misure, null, 2));
    await contesto.close();
  });

  test("Home: card fuori viewport, full-page e viewport dopo scroll", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    await page.goto("/");
    await pronto(page);
    const card = page.getByTestId(/^wine-card-/).first();
    await expect(card).toHaveCount(1);
    await page.screenshot({ path: path.join(cartella(info), "home-full-iniziale.png"), fullPage: true });
    await card.scrollIntoViewIfNeeded();
    const produttore = card.getByText("Cantina E2E-CRIT", { exact: true });
    await expect(produttore).toBeVisible();
    await expect(card.getByText(/Barolo UX Final/)).toBeVisible();
    await page.evaluate(async () => {
      await document.fonts.ready;
      await Promise.all([...document.querySelectorAll("img")].map((i) => i.decode().catch(() => {})));
      await new Promise<void>((r) => requestAnimationFrame(() => requestAnimationFrame(() => r())));
    });
    await page.screenshot({ path: path.join(cartella(info), "home-viewport-scroll.png") });
    await card.screenshot({ path: path.join(cartella(info), "home-card.png") });
    await page.screenshot({ path: path.join(cartella(info), "home-full-dopo-scroll.png"), fullPage: true });
    writeFileSync(path.join(cartella(info), "home-rendering.json"), JSON.stringify(await card.evaluate((el) => ({ contentVisibility: getComputedStyle(el).contentVisibility, contain: getComputedStyle(el).contain, fonts: document.fonts.status, rect: el.getBoundingClientRect().toJSON(), images: [...el.querySelectorAll("img")].map((i) => ({ complete: i.complete, width: i.naturalWidth })) })), null, 2));
    await contesto.close();
  });
});
