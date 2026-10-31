import { randomUUID } from "node:crypto";
import { passwordFixture } from "./support/api";
import { contestoAutenticato, opzioniDelProgetto } from "./support/browser";
import { ripristinaFixture } from "./support/db";
import { attendiCaricamento } from "./support/pagina";
import { expect, test } from "./support/test";

/**
 * Accessori con gli interruttori del database spenti (stato di consegna).
 * Le flag d'ambiente sono accese nel solo processo di prova, quindi le route
 * rispondono: ciò che deve restare nascosto lo nasconde il database.
 */
test.describe("Accessori con interruttori spenti @smoke @cross", () => {
  test.beforeAll(() => {
    ripristinaFixture(passwordFixture());
  });

  test("la vetrina e il catalogo pubblici sono vuoti, senza annunci né link a dettagli", async ({ page }) => {
    await page.goto("/accessori/annunci");
    await expect(page.getByRole("heading", { name: "Annunci della community" })).toBeVisible();
    await expect(page.getByText("Nessun annuncio in vetrina")).toBeVisible();
    await expect(page.locator('a[href^="/accessori/annunci/"]')).toHaveCount(0);

    await page.goto("/accessori");
    await expect(page.getByText("Il catalogo si sta preparando")).toBeVisible();
    await expect(page.getByText("non è possibile acquistarli o riservarli")).toBeVisible();
  });

  test("un annuncio inesistente risponde 404, non una pagina vuota", async ({ page, diagnostica }) => {
    diagnostica.ammetti("status of 404"); // il 404 è l'esito atteso, il browser lo registra in console
    const risposta = await page.goto(`/accessori/annunci/${randomUUID()}`);
    expect(risposta?.status()).toBe(404);
  });

  test("la Cantina di un utente non mostra la sezione Accessori", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "utente");
    await page.goto("/cantina");
    await attendiCaricamento(page);
    // Prova che la Cantina è davvero caricata, poi l'assenza della sezione.
    await expect(page.getByText("Il tuo patrimonio in bottiglia")).toBeVisible();
    await expect(page.getByTestId("cantina-accessori")).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Aggiungi accessorio" })).toHaveCount(0);
    await contesto.close();
  });

  test("un admin senza ruolo di rilascio vede tutto spento e non può accendere nulla", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "adminSenzaRilascio", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "utente");
    await page.goto("/admin/accessori");
    await attendiCaricamento(page);
    await expect(page.getByText("Visibilità pubblica (database): SPENTA")).toBeVisible();
    await expect(page.getByText("Funzione Cantina Accessori: SPENTA")).toBeVisible();
    await expect(page.getByText("Il tuo account non ha il permesso di rilascio").first()).toBeVisible();
    await expect(page.getByRole("button", { name: "Rendi pubblico il catalogo" })).toHaveCount(0);
    await contesto.close();
  });

  test("un utente ordinario non entra nell'area admin Accessori", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "utente");
    diagnostica.ammetti("status of 404");
    const risposta = await page.goto("/admin/accessori");
    expect(risposta?.status()).toBe(404);
    await attendiCaricamento(page);
    await expect(page.getByText("Visibilità pubblica (database)")).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Rendi pubblico il catalogo" })).toHaveCount(0);
    await contesto.close();
  });
});
