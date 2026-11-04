import { passwordFixture } from "./support/api";
import { contestoAutenticato, opzioniDelProgetto } from "./support/browser";
import { ripristinaFixture } from "./support/db";
import { attendiCaricamento, senzaScorrimentoOrizzontale } from "./support/pagina";
import { scriviSegreto } from "./support/segreti";
import { expect, test } from "./support/test";
import { etichettaCorsa, preparaBottigliaInCantina } from "./support/vino";

/**
 * VPM-018-UX-FIX-02. UX-B1: i requisiti della password stanno subito sotto il
 * campo e sono collegati con `aria-describedby`. UX-B2: la Cantina senza alcun
 * riferimento di valore non mostra una variazione (−€ / −100%) costruita su un
 * valore che non esiste. Nessuna scrittura dal browser: la bottiglia si prepara
 * con la porta reale della Cantina e la pulizia dei domini critici la rimuove.
 */

test.describe("Requisiti password adiacenti al campo in /registrati @cross", () => {
  test("i requisiti seguono il campo password, prima della data di nascita, e lo descrivono", async ({ browser, diagnostica }, info) => {
    const contesto = await browser.newContext(opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "nuovo utente");
    await page.goto("/registrati");
    await attendiCaricamento(page);

    const campo = page.getByLabel("Password", { exact: true });
    const requisiti = page.getByTestId("requisiti-password");
    const dob = page.getByLabel("Data di nascita");
    await expect(requisiti).toBeVisible();

    const [c, r, d] = await Promise.all([campo.boundingBox(), requisiti.boundingBox(), dob.boundingBox()]);
    if (!c || !r || !d) throw new Error("Geometria non disponibile.");
    // Subito sotto il campo (pochi pixel di respiro), mai dopo la data di nascita.
    expect(r.y).toBeGreaterThanOrEqual(c.y + c.height - 1);
    expect(r.y - (c.y + c.height)).toBeLessThan(24);
    expect(d.y).toBeGreaterThanOrEqual(r.y + r.height - 1);

    // Nome accessibile: `aria-describedby` risolve proprio nel blocco dei requisiti.
    const idDescrizione = await campo.getAttribute("aria-describedby");
    expect(idDescrizione).toBe("requisiti-password-registrazione");
    await expect(page.locator(`#${idDescrizione}`)).toHaveAttribute("data-testid", "requisiti-password");

    // Il riscontro dinamico resta vivo: nessun requisito soddisfatto, poi tutti.
    await expect(page.locator('[data-testid^="requisito-"][data-soddisfatto="true"]')).toHaveCount(0);
    await scriviSegreto(campo, `Ab1!${etichettaCorsa()}Zz9?`);
    await expect(page.getByTestId("requisiti-riepilogo")).toHaveText(/5 di 5\./);
    await expect(page.locator('[data-testid^="requisito-"][data-soddisfatto="true"]').first()).toBeVisible();

    // Tastiera: dal campo password un Tab porta alla data di nascita (i requisiti non sono controlli).
    await campo.focus();
    await page.keyboard.press("Tab");
    await expect(dob).toBeFocused();

    expect(await senzaScorrimentoOrizzontale(page)).toBe(true);
    await contesto.close();
  });
});

test.describe("Valore di Cantina senza riferimento non mostra variazioni @cross", () => {
  const nome = `Barolo E2E-VAL ${etichettaCorsa()}`;

  test.beforeAll(async () => {
    ripristinaFixture(passwordFixture());
    // Costo noto (37 €), nessun riferimento di valore: il caso di `venditore-cantina`.
    await preparaBottigliaInCantina("venditore", { nome, costoAcquistoCents: 3700 });
  });

  test("«Non disponibile» non convive con importo e percentuale di variazione", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    await page.goto("/cantina");
    await attendiCaricamento(page);

    const blocco = page.locator('section[aria-labelledby="contabilita-cantina"]');
    await expect(blocco).toBeVisible();
    await expect(blocco.getByText("Non disponibile").first()).toBeVisible();
    // Nessuna pillola di tendenza, nessuna percentuale nel riquadro del valore.
    await expect(page.getByTestId("cantina-tendenza")).toHaveCount(0);
    await expect(blocco).not.toContainText(/[-−+]\s?\d+[.,]\d%/);
    await expect(blocco).not.toContainText("−37");
    await expect(blocco).not.toContainText("-37");
    await expect(blocco).toContainText("Serve almeno un riferimento di valore");

    expect(await senzaScorrimentoOrizzontale(page)).toBe(true);
    await contesto.close();
  });
});
