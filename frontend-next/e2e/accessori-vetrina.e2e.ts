import { accendiPubblicazione, passwordFixture, pubblicaAnnuncioPreparato } from "./support/api";
import { contestoAutenticato, opzioniDelProgetto } from "./support/browser";
import { ripristinaFixture } from "./support/db";
import { attendiCaricamento, problemiAccessibilita, senzaScorrimentoOrizzontale } from "./support/pagina";
import { expect, test } from "./support/test";

/**
 * Vetrina e dettaglio degli annunci Accessori nei tre profili (Chromium
 * desktop, Chromium 375 px, WebKit): layout senza scorrimento orizzontale,
 * accessibilità di base, sessione riconosciuta dal client in ogni motore.
 * Sola lettura sullo stesso stato preparato con le porte reali.
 */
test.describe("Vetrina Accessori: responsive, accessibilità, cross-browser @smoke @cross", () => {
  let annuncioId = "";

  test.beforeAll(async () => {
    ripristinaFixture(passwordFixture());
    await accendiPubblicazione();
    annuncioId = (await pubblicaAnnuncioPreparato("Calice E2E vetrina")).annuncioId;
  });

  test("la vetrina pubblica sta nel viewport e non ha problemi di accessibilità di base", async ({ page }, info) => {
    await page.goto("/accessori/annunci");
    await attendiCaricamento(page);
    const carta = page.locator(`a[href="/accessori/annunci/${annuncioId}"]`);
    await expect(carta).toBeVisible();
    await expect(carta).toContainText("Non ancora acquistabile");
    expect(await senzaScorrimentoOrizzontale(page), "scorrimento orizzontale").toBe(true);
    expect(await problemiAccessibilita(page)).toEqual([]);
    await info.attach(`vetrina-${info.project.name}.png`, { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });
  });

  test("il dettaglio pubblico mostra prezzo e avviso, e rinvia all'accesso per segnalare", async ({ page }, info) => {
    await page.goto(`/accessori/annunci/${annuncioId}`);
    await attendiCaricamento(page);
    await expect(page.getByRole("heading", { name: "Calice E2E vetrina" })).toBeVisible();
    await expect(page.getByText("22,73 €").first()).toBeVisible();
    await expect(page.getByText("Gli acquisti non sono ancora disponibili.").first()).toBeVisible();
    await expect(page.getByRole("link", { name: "Accedi per segnalare l'annuncio" })).toBeVisible();
    expect(await senzaScorrimentoOrizzontale(page), "scorrimento orizzontale").toBe(true);
    expect(await problemiAccessibilita(page)).toEqual([]);
    await info.attach(`dettaglio-${info.project.name}.png`, { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });
  });

  test("con una sessione il client la riconosce e offre la segnalazione", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "segnalante", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "segnalante");
    await page.goto(`/accessori/annunci/${annuncioId}`);
    await attendiCaricamento(page);
    await expect(page.getByRole("button", { name: "Segnala annuncio" })).toBeVisible();
    await expect(page.getByRole("link", { name: "Accedi per segnalare l'annuncio" })).toHaveCount(0);
    expect(await senzaScorrimentoOrizzontale(page), "scorrimento orizzontale").toBe(true);
    await contesto.close();
  });
});
