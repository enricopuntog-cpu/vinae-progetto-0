import { passwordFixture } from "./support/api";
import { contestoAutenticato, opzioniDelProgetto } from "./support/browser";
import { eseguiSql, ripristinaFixture } from "./support/db";
import { attendiCaricamento, problemiAccessibilita, senzaScorrimentoOrizzontale } from "./support/pagina";
import { expect, test } from "./support/test";
import { etichettaCorsa, leggiDalDatabase, preparaBottigliaInCantina, uuid, type BottigliaPreparata } from "./support/vino";

/**
 * WI-005B · «Completa le informazioni» in `/cantina`, su dati reali dello stack isolato.
 *
 * Percorso: Cantina → Completa i dati → Modifica → Conferma → Salvataggio → Scheda aggiornata.
 * Il vino è CONDIVISO da due utenti (stesso `wine_id`): le annotazioni sono private, restano dopo
 * un nuovo accesso, non compaiono all'altro utente e non toccano la riga di `public.wines`.
 * Nessuna chiamata a Edge Function (nessuna AI).
 */

const EMAIL_ALTRO = "u03@e2e-12zk.test";

const sqlVino = (wineId: string): string =>
  leggiDalDatabase(
    `select annata || '|' || regione || '|' || denominazione || '|' || updated_at::text from public.wines where id = '${uuid(wineId)}';`,
  );

test.describe.serial("Note personali sul vino: salvate, private e senza toccare il catalogo @smoke @cross", () => {
  const corsa = etichettaCorsa();
  const nomeVino = `Condiviso E2E ${corsa}`;
  let vino: BottigliaPreparata;
  let catalogoPrima = "";

  test.beforeAll(async () => {
    ripristinaFixture(passwordFixture());
    // Il venditore possiede il vino tramite la porta reale; l'altro utente lo possiede con una
    // propria bottiglia (fixture tecnica, rimossa con l'utente).
    vino = await preparaBottigliaInCantina("venditore", { nome: nomeVino });
    eseguiSql(
      `insert into public.bottle_units (owner_id, wine_id, stato, visibilita)
       select u.id, '${uuid(vino.wineId)}', 'chiusa', 'privata' from auth.users u where u.email = '${EMAIL_ALTRO}';`,
    );
    catalogoPrima = sqlVino(vino.wineId);
  });

  const schedaDelVino = (page: import("@playwright/test").Page) =>
    page.locator('[id^="gruppo-"]').filter({ hasText: nomeVino }).first();

  test("Completa i dati → modifica → conferma → salva: la scheda mostra le dichiarazioni come tue e private", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    const chiamateFunzioni: string[] = [];
    page.on("request", (r) => {
      if (/\/functions\/v1\//.test(r.url())) chiamateFunzioni.push(r.url());
    });
    await page.goto("/cantina");
    await attendiCaricamento(page);

    // 1. «Completa i dati» elenca il vino con i campi che mancano (denominazione, abbinamenti).
    const sezione = page.getByTestId("consigli-cantina");
    await sezione.getByTestId("consigli-tab-dati").click();
    const carta = sezione.getByTestId("dati-mancanti-vino").filter({ hasText: nomeVino });
    await expect(carta).toContainText("Denominazione");
    await expect(carta).toContainText("Abbinamenti");

    // 2. Il comando reale apre l'editor di QUEL vino.
    await carta.getByTestId("dati-completa-info").click();
    const dialogo = page.getByRole("dialog", { name: "Completa le informazioni" });
    await expect(dialogo).toBeVisible();
    await expect(dialogo.getByTestId("nota-privacy")).toContainText("private");
    await expect(dialogo.getByTestId("nota-catalogo")).toContainText("Piemonte");
    expect(await senzaScorrimentoOrizzontale(page), "scorrimento orizzontale con l'editor aperto").toBe(true);
    expect(await problemiAccessibilita(page)).toEqual([]);
    await info.attach(`nota-modifica-${info.project.name}.png`, { body: await dialogo.screenshot(), contentType: "image/png" });

    // 3. Modifica: una dichiarazione che contraddice il catalogo, abbinamenti e osservazioni.
    await dialogo.getByTestId("nota-abbinamenti").fill("Tagliatelle ai funghi porcini\nBrasato al Barolo");
    await dialogo.getByTestId("nota-denominazione").fill("Barolo DOCG");
    await dialogo.getByTestId("nota-regione").fill("Toscana");
    await dialogo.getByTestId("nota-osservazioni").fill("Regalo di Marco, provato a Natale.");
    await dialogo.getByTestId("nota-temperatura").fill("99");
    await dialogo.getByTestId("nota-rivedi").click();
    await expect(dialogo.getByTestId("nota-errore-temperaturaC")).toBeVisible();
    await dialogo.getByTestId("nota-temperatura").fill("17");

    // 4. Conferma: il riepilogo dice che sono dichiarazioni tue e mostra il conflitto col catalogo.
    await dialogo.getByTestId("nota-rivedi").click();
    const riepilogo = dialogo.getByTestId("nota-conferma");
    await expect(riepilogo).toContainText("Dichiarato da te");
    await expect(dialogo.getByTestId("nota-conflitti")).toContainText("Il database non cambia");
    await info.attach(`nota-conferma-${info.project.name}.png`, { body: await dialogo.screenshot(), contentType: "image/png" });
    // Finché non si conferma, nulla è stato scritto.
    expect(leggiDalDatabase("select count(*) from public.wine_personal_notes;").trim()).toBe("0");

    // 5. Salvataggio.
    await dialogo.getByTestId("nota-salva").click();
    await expect(dialogo).toBeHidden();
    await expect(page.getByText("Informazioni salvate").first()).toBeVisible();
    expect(leggiDalDatabase("select count(*) from public.wine_personal_notes;").trim()).toBe("1");

    // 6. Scheda aggiornata: «Completa i dati» non elenca più i campi completati.
    await sezione.getByTestId("consigli-tab-dati").click();
    const ancoraCarta = sezione.getByTestId("dati-mancanti-vino").filter({ hasText: nomeVino });
    await expect(ancoraCarta).not.toContainText("Denominazione");
    await expect(ancoraCarta).not.toContainText("Abbinamenti");

    // 7. La scheda intelligente distingue dati condivisi e dichiarazioni personali.
    const scheda = schedaDelVino(page);
    await scheda.getByTestId("wine-intelligence").locator("summary").click();
    const personale = scheda.getByTestId("wi-personale");
    await expect(personale).toContainText("Le tue dichiarazioni");
    await expect(personale).toContainText("Barolo DOCG");
    await expect(personale).toContainText("Tagliatelle ai funghi porcini");
    await expect(personale).toContainText("Regalo di Marco");
    await expect(scheda.getByTestId("wi-segnalazioni")).toContainText("Toscana");
    await expect(scheda.getByTestId("wine-intelligence")).toContainText("completat");
    await info.attach(`nota-scheda-${info.project.name}.png`, { body: await scheda.screenshot(), contentType: "image/png" });

    // 8. «Cosa abbino a cena» usa l'abbinamento dichiarato e lo dice.
    await sezione.getByTestId("consigli-tab-cena").click();
    await sezione.getByTestId("consigli-piatto").fill("funghi");
    const consiglio = sezione.getByTestId("consiglio-cantina").filter({ hasText: nomeVino });
    await expect(consiglio).toHaveCount(1);
    await expect(consiglio).toContainText("Abbinamento dichiarato da te");
    await expect(consiglio).not.toContainText("Abbinamento registrato");

    // 9. Il catalogo pubblico non è cambiato e nessuna Edge Function è stata chiamata.
    expect(sqlVino(vino.wineId)).toBe(catalogoPrima);
    expect(chiamateFunzioni, "nessuna chiamata a Edge Function (AI)").toEqual([]);
    await contesto.close();
  });

  test("«Vai alla bottiglia» raggiunge la scheda anche con un filtro diverso attivo", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    await page.goto("/cantina");
    await attendiCaricamento(page);
    await page.getByRole("tab", { name: "In vendita" }).click();
    await expect(page.getByRole("tab", { name: "In vendita" })).toHaveAttribute("data-state", "active");
    await expect(schedaDelVino(page)).toHaveCount(0);

    const sezione = page.getByTestId("consigli-cantina");
    await sezione.getByTestId("consigli-tab-dati").click();
    await sezione.getByTestId("dati-mancanti-vino").filter({ hasText: nomeVino }).getByRole("link", { name: "Vai alla bottiglia" }).click();
    await expect(page.getByRole("tab", { name: "Tutte" })).toHaveAttribute("data-state", "active");
    await expect(schedaDelVino(page)).toBeVisible();
    await expect(sezione.getByTestId("consigli-avviso")).toHaveCount(0);
    await contesto.close();
  });

  test("le annotazioni restano dopo un nuovo accesso e si possono modificare e cancellare", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    await page.goto("/cantina");
    await attendiCaricamento(page);

    await schedaDelVino(page).getByTestId("cantina-completa-info").click();
    const dialogo = page.getByRole("dialog", { name: "Completa le informazioni" });
    // Persistenza: i campi arrivano dal database, non da memoria del browser.
    await expect(dialogo.getByTestId("nota-denominazione")).toHaveValue("Barolo DOCG");
    await expect(dialogo.getByTestId("nota-abbinamenti")).toHaveValue(/Tagliatelle ai funghi porcini/);

    // Modifica: un abbinamento in meno.
    await dialogo.getByTestId("nota-abbinamenti").fill("Risotto ai funghi");
    await dialogo.getByTestId("nota-rivedi").click();
    await dialogo.getByTestId("nota-salva").click();
    await expect(dialogo).toBeHidden();
    expect(leggiDalDatabase("select abbinamenti::text from public.wine_personal_notes;").trim()).toBe("{\"Risotto ai funghi\"}");

    // Cancellazione, con seconda conferma.
    await schedaDelVino(page).getByTestId("cantina-completa-info").click();
    await dialogo.getByTestId("nota-elimina").click();
    await dialogo.getByTestId("nota-elimina-conferma").click();
    await expect(dialogo).toBeHidden();
    expect(leggiDalDatabase("select count(*) from public.wine_personal_notes;").trim()).toBe("0");
    await expect(schedaDelVino(page).getByTestId("wi-personale")).toHaveCount(0);
    expect(sqlVino(vino.wineId)).toBe(catalogoPrima);
    await contesto.close();
  });

  test("un altro proprietario dello stesso vino non vede le annotazioni e può averne di proprie", async ({ browser, diagnostica }, info) => {
    // Il venditore annota di nuovo.
    const proprietario = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const pagina = await proprietario.newPage();
    diagnostica.osserva(pagina, "venditore");
    await pagina.goto("/cantina");
    await attendiCaricamento(pagina);
    await schedaDelVino(pagina).getByTestId("cantina-completa-info").click();
    const d1 = pagina.getByRole("dialog", { name: "Completa le informazioni" });
    await d1.getByTestId("nota-osservazioni").fill("RISERVATA-DEL-VENDITORE");
    await d1.getByTestId("nota-rivedi").click();
    await d1.getByTestId("nota-salva").click();
    await expect(d1).toBeHidden();
    await proprietario.close();

    // L'altro possiede lo stesso vino: non vede nulla di privato dell'altro.
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "altro");
    await page.goto("/cantina");
    await attendiCaricamento(page);
    await expect(schedaDelVino(page)).toBeVisible();
    await expect(page.locator("body")).not.toContainText("RISERVATA-DEL-VENDITORE");
    await expect(schedaDelVino(page).getByTestId("wi-personale")).toHaveCount(0);
    await expect(schedaDelVino(page).getByTestId("cantina-completa-info")).toContainText("Completa le informazioni");

    // Annota in proprio: separato da quello del venditore.
    await schedaDelVino(page).getByTestId("cantina-completa-info").click();
    const d2 = page.getByRole("dialog", { name: "Completa le informazioni" });
    await d2.getByTestId("nota-osservazioni").fill("Nota dell'altro");
    await d2.getByTestId("nota-rivedi").click();
    await d2.getByTestId("nota-salva").click();
    await expect(d2).toBeHidden();
    expect(leggiDalDatabase("select count(*) from public.wine_personal_notes;").trim()).toBe("2");
    expect(sqlVino(vino.wineId)).toBe(catalogoPrima);
    await contesto.close();

    // Cambio account: il venditore, rientrando, trova solo la propria.
    const rientro = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const p3 = await rientro.newPage();
    diagnostica.osserva(p3, "venditore");
    await p3.goto("/cantina");
    await attendiCaricamento(p3);
    await schedaDelVino(p3).getByTestId("wine-intelligence").locator("summary").click();
    await expect(schedaDelVino(p3).getByTestId("wi-personale")).toContainText("RISERVATA-DEL-VENDITORE");
    await expect(p3.locator("body")).not.toContainText("Nota dell'altro");
    await rientro.close();
  });
});
