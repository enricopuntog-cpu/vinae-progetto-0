import { problemiAccessibilita, senzaScorrimentoOrizzontale } from "./support/pagina";
import { expect, test } from "./support/test";
import { UUID_INESISTENTE } from "./support/vino";

/**
 * Pagine di «non trovato» (VPM-018-UX-A11Y-01, GAP-005). Sola lettura, nessun
 * account: un URL senza pagina, un annuncio inesistente e una route spenta dalla
 * sua flag (`/beta-test`, spenta nello stack di prova) rispondono ancora 404, ora
 * con la pagina di marca in italiano al posto di quella predefinita di Next.
 * L'errore applicativo forzato (`error.tsx`, `global-error.tsx`) non si può
 * provocare dal browser senza una route di prova: è coperto da
 * `src/app/pagine-di-errore.test.tsx` e dalla verifica manuale del rapporto.
 */

test.describe("Pagine non trovate: marchio, italiano, nessun dettaglio @smoke @cross", () => {
  test("un URL senza pagina risponde 404 con la pagina di marca e una via d'uscita da tastiera", async ({ page, diagnostica }, info) => {
    diagnostica.ammetti("/pagina-che-non-esiste");
    const risposta = await page.goto("/pagina-che-non-esiste");
    expect(risposta?.status()).toBe(404);

    await expect(page.getByRole("heading", { level: 1, name: "Pagina non trovata" })).toBeVisible();
    await expect(page.getByText("La pagina che cercavi non esiste o è stata spostata.")).toBeVisible();
    await expect(page.getByText(/could not be found/i)).toHaveCount(0);
    await expect(page.getByRole("main").getByRole("link", { name: /Esplora la ricerca/ })).toHaveAttribute("href", "/esplora");
    expect(await problemiAccessibilita(page), "accessibilità di base").toEqual([]);
    expect(await senzaScorrimentoOrizzontale(page), "scorrimento orizzontale").toBe(true);

    // Tastiera: il link «Torna alla home» si raggiunge con Tab e si attiva con Invio.
    // Safari/WebKit non include i link nell'ordine di Tab senza l'opzione di sistema: lì si porta il fuoco a mano.
    const home = page.getByRole("main").getByRole("link", { name: "Torna alla home" });
    if (info.project.name === "webkit-desktop") {
      await home.focus();
    } else {
      for (let i = 0; i < 40; i++) {
        await page.keyboard.press("Tab");
        if (await home.evaluate((e) => e === document.activeElement)) break;
      }
    }
    await expect(home).toBeFocused();
    await page.keyboard.press("Enter");
    await expect(page).toHaveURL((url) => url.pathname === "/");
  });

  test("un annuncio inesistente resta 404 e ha un titolo di primo livello", async ({ page, diagnostica }) => {
    diagnostica.ammetti(`/annuncio/${UUID_INESISTENTE}`);
    const risposta = await page.goto(`/annuncio/${UUID_INESISTENTE}`);
    expect(risposta?.status()).toBe(404);
    await expect(page.getByRole("heading", { level: 1, name: "Annuncio non trovato" })).toBeVisible();
    await expect(page.getByRole("link", { name: "Torna alla ricerca" })).toHaveAttribute("href", "/esplora");
  });

  test("una route spenta dalla sua flag resta 404 con la stessa pagina di qualunque URL sconosciuto", async ({ page, diagnostica }) => {
    diagnostica.ammetti("/beta-test");
    const risposta = await page.goto("/beta-test");
    expect(risposta?.status()).toBe(404);
    await expect(page.getByRole("heading", { level: 1, name: "Pagina non trovata" })).toBeVisible();
  });
});
