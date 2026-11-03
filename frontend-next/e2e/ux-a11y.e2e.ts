import { passwordFixture } from "./support/api";
import { contestoAutenticato, opzioniDelProgetto } from "./support/browser";
import { ripristinaFixture } from "./support/db";
import { attendiCaricamento, problemiAccessibilita, senzaScorrimentoOrizzontale } from "./support/pagina";
import { expect, test } from "./support/test";
import { etichettaCorsa, preparaBottigliaInCantina } from "./support/vino";

/**
 * Accessibilità del wizard `/vendi` e delle pagine ritoccate (VPM-018-UX-A11Y-01,
 * R-A11Y-01). Ogni campo è trovato per etichetta (non per segnaposto), nessun
 * campo o pulsante resta senza nome accessibile nei passi del wizard, `/messaggi`
 * senza conversazioni ha il suo titolo e il campo di ricerca di `/esplora` ha un
 * nome. Nessuna scrittura dal browser: la bottiglia si prepara con la porta reale
 * della Cantina e la pulizia dei domini critici la rimuove.
 */

test.describe("Accessibilità del wizard /vendi e delle pagine ritoccate @cross", () => {
  const nome = `Barolo E2E-A11Y ${etichettaCorsa()}`;
  let bottigliaId = "";

  test.beforeAll(async () => {
    ripristinaFixture(passwordFixture());
    bottigliaId = (await preparaBottigliaInCantina("venditore", { nome })).bottleUnitIds[0];
  });

  test("i campi del wizard si trovano per etichetta e nessun passo ha controlli senza nome", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");

    await page.goto(`/vendi?mode=sell&bottiglia=${bottigliaId}`);
    await attendiCaricamento(page);
    const continua = page.getByRole("button", { name: /Continua/ });

    // Fotografie: sei slot vuoti, ognuno con un nome (prima: pulsanti con la sola icona).
    // «Aggiungi la fotografia 1» … «… 6»: nome numerato (il nome di ruolo corrisponde per sottostringa).
    await expect(page.getByRole("button", { name: "Aggiungi la fotografia" })).toHaveCount(6);
    await expect(page.getByRole("button", { name: "Aggiungi la fotografia 1", exact: true })).toHaveCount(1);
    expect(await problemiAccessibilita(page), "passo Fotografie").toEqual([]);
    await continua.click();
    await expect(page.getByRole("heading", { name: "Identificazione", exact: true })).toBeVisible();
    expect(await problemiAccessibilita(page), "passo Identificazione").toEqual([]);
    await continua.click();
    // Condizioni: pulsanti con stato, il selezionato lo dichiara.
    const ottimo = page.getByRole("button", { name: "Ottimo" });
    await expect(ottimo).toHaveAttribute("aria-pressed", "false");
    await ottimo.click();
    await expect(ottimo).toHaveAttribute("aria-pressed", "true");
    await expect(page.getByRole("button", { name: "Buono" })).toHaveAttribute("aria-pressed", "false");
    await continua.click();

    // Provenienza e conservazione: le due etichette del componente Field.
    await expect(page.getByRole("heading", { name: "Provenienza e conservazione" })).toBeVisible();
    const conservazione = page.getByLabel("Come è stata conservata", { exact: true });
    const storia = page.getByLabel("Racconta la sua storia (opzionale)", { exact: true });
    await expect(conservazione).toBeVisible();
    await expect(storia).toBeVisible();
    // Toccare l'etichetta porta il fuoco sul campo: è la prova dell'associazione, non solo del nome.
    await page.locator('label[for="vendi-conservazione"]').click();
    await expect(conservazione).toBeFocused();
    await conservazione.fill("Cantina interrata, 14 gradi.");
    expect(await problemiAccessibilita(page), "passo Provenienza").toEqual([]);
    await continua.click();

    // Prezzo e bottiglie in vendita.
    await expect(page.getByRole("heading", { name: "Prezzo", exact: true })).toBeVisible();
    const prezzo = page.getByLabel("Prezzo per bottiglia (€)", { exact: true });
    await page.locator('label[for="vendi-prezzo"]').click();
    await expect(prezzo).toBeFocused();
    await prezzo.fill("42");
    await expect(prezzo).toHaveValue("42");
    await expect(page.getByLabel("Bottiglie in vendita", { exact: true })).toBeVisible();
    expect(await problemiAccessibilita(page), "passo Prezzo").toEqual([]);
    expect(await senzaScorrimentoOrizzontale(page), "scorrimento orizzontale nel wizard").toBe(true);
    await contesto.close();
  });

  test("/messaggi senza conversazioni ha un titolo e /esplora un campo di ricerca con nome", async ({ browser, page, diagnostica }, info) => {
    await page.goto("/esplora");
    await attendiCaricamento(page);
    await expect(page.getByRole("textbox", { name: /Cerca vino, produttore, annata/ })).toBeVisible();
    expect(await problemiAccessibilita(page), "/esplora").toEqual([]);

    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const pagina = await contesto.newPage();
    diagnostica.osserva(pagina, "venditore");
    await pagina.goto("/messaggi");
    await attendiCaricamento(pagina);
    await expect(pagina.getByText("Nessuna conversazione")).toBeVisible();
    await expect(pagina.getByRole("heading", { level: 1, name: "Messaggi" })).toHaveCount(1);
    expect(await problemiAccessibilita(pagina), "/messaggi").toEqual([]);
    await contesto.close();
  });
});
