import { mkdirSync } from "node:fs";
import path from "node:path";
import { passwordFixture } from "./support/api";
import { contestoAutenticato, opzioniDelProgetto } from "./support/browser";
import { ripristinaFixture } from "./support/db";
import { attendiCaricamento, problemiAccessibilita, senzaScorrimentoOrizzontale } from "./support/pagina";
import { expect, test } from "./support/test";
import { preparaBottigliaInCantina, pubblicaAnnuncioVino } from "./support/vino";

// Acquisizione ripetibile sulla build di produzione. La baseline usa lo stesso caso
// senza asserire il contrasto corretto; i controlli geometrici restano attivi.
test.describe("Design vite @smoke @cross", () => {
  test.beforeAll(async () => {
    ripristinaFixture(passwordFixture());
    const vino = await preparaBottigliaInCantina("venditore", { nome: "Barolo Riserva Design", costoAcquistoCents: 3700 });
    await pubblicaAnnuncioVino("venditore", vino.bottleUnitIds[0], 4200);
  });

  for (const [nome, url] of [["home", "/"], ["esplora", "/esplora?regione=Piemonte"], ["cantina", "/cantina"]]) {
    test(`${nome}: palette, leggibilità e layout`, async ({ browser, diagnostica }, info) => {
      const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
      const page = await contesto.newPage();
      diagnostica.osserva(page, "venditore");
      await page.goto(url);
      await attendiCaricamento(page);
      await expect(page.getByText("Verifica del profilo")).toHaveCount(0);
      await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
      await page.evaluate(() => document.fonts.ready);
      expect(await senzaScorrimentoOrizzontale(page)).toBe(true);
      expect(await problemiAccessibilita(page)).toEqual([]);
      const fase = process.env.VITE_BASELINE === "1" ? "prima" : "dopo";
      const cartella = path.resolve("e2e/artifacts/design-vite", fase, info.project.name);
      mkdirSync(cartella, { recursive: true });
      await page.screenshot({ path: path.join(cartella, `${nome}.png`), fullPage: true });
      if (fase === "dopo") {
        // Colore realmente applicato ai produttori, su card bianche e fondo crema.
        const produttore = page.getByText("Cantina E2E-CRIT", { exact: true }).first();
        await expect(produttore).toBeVisible();
        const colore = await produttore.evaluate((el) => getComputedStyle(el).color);
        expect(colore).toBe("rgb(74, 83, 68)");
      }
      if (nome === "cantina" && fase === "dopo") {
        const titolo = page.getByText("Da attendere", { exact: true }).first();
        const suggerimento = page.getByText("Ancora in evoluzione", { exact: true });
        await expect(titolo).toBeVisible();
        for (const testo of [titolo, suggerimento]) {
          expect(await testo.evaluate((el) => getComputedStyle(el).opacity)).toBe("1");
          expect(await testo.evaluate((el) => getComputedStyle(el).color)).toBe("rgb(74, 83, 68)");
        }
      }
      if (nome === "home") {
        const regione = page.getByRole("link", { name: "Piemonte", exact: true });
        await regione.hover();
        await regione.focus();
        await expect(regione).toBeFocused();
        expect(await regione.evaluate((el) => getComputedStyle(el).outlineStyle)).not.toBe("none");
        await regione.screenshot({ path: path.join(cartella, "regione-hover-focus.png") });
      }
      if (nome === "esplora") {
        const ricerca = page.getByRole("textbox", { name: "Cerca vino, produttore, annata" });
        await ricerca.focus();
        await expect(ricerca).toBeFocused();
        await page.screenshot({ path: path.join(cartella, "esplora-focus.png") });
        await ricerca.fill("nessun-vino-corrispondente-design");
        await expect(page.getByText(/Nessun risultato|Nessuna bottiglia trovata/).first()).toBeVisible();
        expect(await senzaScorrimentoOrizzontale(page)).toBe(true);
        await page.screenshot({ path: path.join(cartella, "esplora-vuoto.png"), fullPage: true });
      }
      await contesto.close();
    });
  }
});
