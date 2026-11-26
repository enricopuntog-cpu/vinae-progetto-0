import { accedi, passwordFixture, rpc } from "./support/api";
import {
  CATALOGO_PULITO,
  LWIN_GEMELLO_A,
  LWIN_GEMELLO_B,
  LWIN_SINGOLO,
  PRODUTTORE_CANONICO,
  creaCanonico,
  impostaFonte,
  impostaProiezione,
  rimuoviCanonico,
} from "./support/canonico";
import { ripristinaFixture } from "./support/db";
import { expect, test } from "./support/test";
import { PRODUTTORE_E2E, etichettaCorsa, leggiDalDatabase, preparaBottigliaInCantina } from "./support/vino";
import { apriIdentificazione, cerca } from "./support/wizard-ricerca";
import { opzioniDelProgetto } from "./support/browser";
import type { Page } from "@playwright/test";

/**
 * WI-007 / FIX-03C · ricerca canonica nel passo Identificazione di `/vendi`, con Auth, PostgREST, database e browser
 * veri dello stack E2E dedicato. Prova che NON basta il precedente E2E generico: qui il catalogo canonico è ACCESO
 * (solo nello stack di prova) e si guarda che cosa vede l'utente.
 *
 * - interruttore SPENTO: nessuna scheda canonica (RPC diretta e wizard); anonimo rifiutato in ogni caso;
 * - ACCESO: due LWIN con lo stesso nome restano due schede, dichiarate omonime, senza attribuzione arbitraria; il vino
 *   Vinea con lo stesso nome non riceve alcun LWIN e conserva annata e dati; la scelta è esplicita e non scrive;
 * - fonte revocata: nessuna scheda; ripristinata: tornano (il caso è sensibile);
 * - errore o lentezza della RPC canonica: la ricerca principale risponde comunque, senza errori per l'utente;
 * - nessuna scrittura: conteggi di vini, bottiglie, annunci e catalogo invariati; nessuna richiesta di scrittura su tabelle.
 *
 * Il percorso OCR usa la stessa sorgente (`creaMotoreRicerca` → `cercaCorrispondenze`) ed è provato dai test unitari.
 * Fixture e interruttori tornano ai valori di partenza (verificato in `afterAll`).
 */

/** Codice LWIN mostrato su una scheda canonica («LWIN 9100001»); il testo di omonimia nomina «LWIN» ma non un codice. */
const CON_LWIN = /LWIN \d{7}/;

test.describe.serial("Ricerca canonica nel wizard: catalogo acceso solo in prova, identità non attribuite, nessuna scrittura @smoke", () => {
  const corsa = etichettaCorsa();
  const nomeGemello = `Gemello ${corsa}`;
  const nomeSingolo = `Singolo ${corsa}`;
  const argomenti = (nome: string) => ({ p_produttore: PRODUTTORE_CANONICO, p_nome: nome });
  let vinoVineaId = "";

  const scritture = () =>
    leggiDalDatabase(
      `select concat_ws(' ', (select count(*) from public.wines), (select count(*) from public.bottle_units),
         (select count(*) from public.listings), (select count(*) from catalog.wines), (select count(*) from catalog.producers),
         (select count(*) from catalog.source_records), (select count(*) from catalog.canonical_events));`,
    );

  test.beforeAll(async () => {
    ripristinaFixture(passwordFixture());
    // Residuo di una corsa interrotta: lo stato di partenza deve essere pulito prima di creare nulla.
    expect(rimuoviCanonico()).toBe(CATALOGO_PULITO);
    creaCanonico(corsa);
    // Il vino Vinea con lo STESSO produttore e nome di una scheda canonica: non deve ricevere il suo LWIN.
    vinoVineaId = (await preparaBottigliaInCantina("venditore", { nome: nomeSingolo, annata: 2016 })).wineId;
  });

  test.afterAll(() => {
    expect(rimuoviCanonico(), "catalogo, interruttore e fonte devono tornare ai valori di partenza").toBe(CATALOGO_PULITO);
  });

  /** Etichette (schede) dell'elenco che contengono il testo, con o senza il codice LWIN. */
  const schede = (page: Page, testo: string) =>
    page.getByTestId("ricerca-manuale-candidati").locator("label", { hasText: testo });

  test("interruttore SPENTO: nessuna scheda canonica; l'anonimo è rifiutato; il vino Vinea si trova come prima", async ({ browser, diagnostica }, info) => {
    impostaProiezione(false);
    const venditore = await accedi("venditore");
    const sessione = await rpc<unknown[]>("vini_canonici_cerca", argomenti(nomeGemello), venditore);
    expect(sessione.ok, `RPC come utente identificato: HTTP ${sessione.status}`).toBe(true);
    expect(sessione.body).toEqual([]);
    const anonimo = await rpc("vini_canonici_cerca", argomenti(nomeGemello));
    expect(anonimo.ok).toBe(false);
    expect([401, 403]).toContain(anonimo.status);

    const prima = scritture();
    const { contesto, page } = await apriIdentificazione(browser, "venditore", info, diagnostica);
    await cerca(page, PRODUTTORE_E2E, nomeSingolo);
    await expect(page.getByTestId("ricerca-manuale-candidati")).toContainText(nomeSingolo);
    await expect(page.getByTestId("ricerca-manuale-candidati")).not.toContainText(CON_LWIN);
    await expect(page.getByTestId("ricerca-manuale-errore")).toHaveCount(0);
    expect(scritture()).toBe(prima);
    await contesto.close();
  });

  test("ACCESO: due LWIN con lo stesso nome restano due schede omonime, nessuna attribuzione arbitraria; scelta esplicita senza scritture", async ({ browser, diagnostica }, info) => {
    impostaProiezione(true);
    // RPC diretta: l'utente identificato vede le due schede; l'anonimo resta rifiutato anche con l'interruttore acceso.
    const venditore = await accedi("venditore");
    const diretta = await rpc<Array<{ lwin7: string; fonte_licenza: string; attribuzione: string }>>(
      "vini_canonici_cerca",
      argomenti(nomeGemello),
      venditore,
    );
    expect(diretta.ok).toBe(true);
    expect(diretta.body.map((r) => r.lwin7).sort()).toEqual([LWIN_GEMELLO_A, LWIN_GEMELLO_B]);
    expect(diretta.body.every((r) => Boolean(r.attribuzione) || Boolean(r.fonte_licenza))).toBe(true);
    expect((await rpc("vini_canonici_cerca", argomenti(nomeGemello))).ok).toBe(false);

    const prima = scritture();
    const { contesto, page, richieste } = await apriIdentificazione(browser, "venditore", info, diagnostica);
    await cerca(page, PRODUTTORE_E2E, nomeGemello);
    const candidati = page.getByTestId("ricerca-manuale-candidati");
    await expect(candidati).toBeVisible();
    await expect(schede(page, nomeGemello)).toHaveCount(2);
    await expect(schede(page, LWIN_GEMELLO_A)).toHaveCount(1);
    await expect(schede(page, LWIN_GEMELLO_B)).toHaveCount(1);
    // L'ambiguità è dichiarata e fra le due non si sceglie da soli: nessuna è preselezionata.
    await expect(candidati.getByText(/Altre schede hanno lo stesso nome/)).toHaveCount(2);
    await expect(page.getByTestId("ricerca-manuale-usa-btn")).toBeDisabled();
    await expect(candidati.locator("input[type=radio]:checked")).toHaveCount(1); // solo «Nessuno di questi»

    // Scelta esplicita della seconda scheda (Toscana; la prima è Piemonte): produttore e nome sono uguali nelle due schede
    // e `cerca` li ha già scritti, quindi a discriminare è la REGIONE, che arriva solo con «Usa questo vino».
    const regione = page.getByRole("combobox", { name: /Regione/ });
    await expect(regione).not.toContainText("Toscana");
    await schede(page, LWIN_GEMELLO_B).locator("input").check();
    await expect(regione).not.toContainText("Toscana"); // scegliere non applica: serve il gesto esplicito
    await page.getByTestId("ricerca-manuale-usa-btn").click();
    await expect(page.getByTestId("ricerca-manuale-applicato")).toBeVisible();
    await expect(regione).toContainText("Toscana");
    await expect(regione).not.toContainText("Piemonte");
    await expect(page.getByLabel("Nome / Etichetta", { exact: true })).toHaveValue(nomeGemello);
    await expect(page.getByLabel("Produttore", { exact: true })).toHaveValue(PRODUTTORE_CANONICO);

    // Il LWIN non entra nei campi del wizard (nessun campo lo persiste) e la scelta non ha scritto nulla.
    for (const campo of await page.locator("input, textarea").all()) {
      expect(await campo.inputValue().catch(() => "")).not.toContain(LWIN_GEMELLO_B);
    }
    const canoniche = richieste.filter((r) => /\/rest\/v1\/rpc\/vini_canonici_cerca/.test(r.url));
    expect(canoniche.length).toBeGreaterThan(0);
    expect(canoniche.every((r) => r.metodo === "POST")).toBe(true);
    expect(richieste.filter((r) => /\/rest\/v1\//.test(r.url) && !/\/rest\/v1\/rpc\//.test(r.url) && r.metodo !== "GET")).toEqual([]);
    expect(richieste.filter((r) => /\/functions\/v1\//.test(r.url))).toEqual([]);
    expect(scritture()).toBe(prima);
    await contesto.close();
  });

  test("ACCESO: il vino Vinea con lo stesso nome NON riceve il LWIN e conserva i suoi dati; chi non ha il vino Vinea vede la sola scheda canonica", async ({ browser, diagnostica }, info) => {
    impostaProiezione(true);
    const prima = scritture();
    const { contesto, page } = await apriIdentificazione(browser, "venditore", info, diagnostica);
    await cerca(page, PRODUTTORE_E2E, nomeSingolo);
    await expect(schede(page, nomeSingolo)).toHaveCount(2);
    // Una scheda con il LWIN (canonica) e una senza (Vinea): mai fuse in una sola.
    await expect(schede(page, nomeSingolo).filter({ hasText: LWIN_SINGOLO })).toHaveCount(1);
    const vinea = schede(page, nomeSingolo).filter({ hasNotText: CON_LWIN });
    await expect(vinea).toHaveCount(1);
    await expect(vinea).toContainText("2016");
    // Scegliendo la scheda Vinea si ottiene l'annata Vinea e nessun LWIN.
    await vinea.locator("input").check();
    await page.getByTestId("ricerca-manuale-usa-btn").click();
    await expect(page.getByLabel("Annata", { exact: true })).toHaveValue("2016");
    await expect(page.getByLabel("Nome / Etichetta", { exact: true })).toHaveValue(nomeSingolo);
    for (const campo of await page.locator("input, textarea").all()) {
      expect(await campo.inputValue().catch(() => "")).not.toContain(LWIN_SINGOLO);
    }
    expect(scritture()).toBe(prima);
    await contesto.close();

    // L'altro utente non vede il vino privato Vinea: trova la sola scheda canonica, con LWIN e attribuzione.
    const altro = await apriIdentificazione(browser, "altro", info, diagnostica);
    await cerca(altro.page, PRODUTTORE_E2E, nomeSingolo);
    await expect(schede(altro.page, nomeSingolo)).toHaveCount(1);
    await expect(schede(altro.page, nomeSingolo)).toContainText(`LWIN ${LWIN_SINGOLO}`);
    await expect(altro.page.getByTestId("ricerca-manuale-attribuzione")).toBeVisible();
    await expect(altro.page.getByText(/Altre schede hanno lo stesso nome/)).toHaveCount(0);
    await altro.contesto.close();
  });

  test("fonte revocata: nessuna scheda canonica; ripristinata, tornano", async ({ browser, diagnostica }, info) => {
    impostaProiezione(true);
    impostaFonte("restricted");
    const venditore = await accedi("venditore");
    const chiusa = await rpc<unknown[]>("vini_canonici_cerca", argomenti(nomeGemello), venditore);
    expect(chiusa.ok).toBe(true);
    expect(chiusa.body).toEqual([]);
    const { contesto, page } = await apriIdentificazione(browser, "altro", info, diagnostica);
    await cerca(page, PRODUTTORE_E2E, nomeSingolo);
    await expect(page.getByTestId("ricerca-manuale-nessuno-trovato").or(page.getByTestId("ricerca-manuale-candidati"))).toBeVisible();
    await expect(page.getByTestId("ricerca-manuale-candidati").getByText(CON_LWIN)).toHaveCount(0);
    await expect(page.getByTestId("ricerca-manuale-errore")).toHaveCount(0);

    impostaFonte("authorized");
    await cerca(page, PRODUTTORE_E2E, nomeSingolo);
    await expect(schede(page, nomeSingolo)).toContainText(`LWIN ${LWIN_SINGOLO}`);
    await contesto.close();
  });

  test("errore o lentezza della RPC canonica: la ricerca principale risponde comunque, senza errori per l'utente", async ({ browser, diagnostica }, info) => {
    impostaProiezione(true);
    diagnostica.ammetti("vini_canonici_cerca");
    const { contesto, page } = await apriIdentificazione(browser, "venditore", info, diagnostica);

    // Rete caduta solo per la RPC canonica.
    await page.route("**/rest/v1/rpc/vini_canonici_cerca", (route) => route.abort("failed"));
    await cerca(page, PRODUTTORE_E2E, nomeSingolo);
    await expect(schede(page, nomeSingolo)).toHaveCount(1);
    await expect(schede(page, nomeSingolo)).toContainText("2016");
    await expect(page.getByTestId("ricerca-manuale-errore")).toHaveCount(0);
    await page.unroute("**/rest/v1/rpc/vini_canonici_cerca");

    // Errore HTTP 500 vero (non un errore di rete) solo per la RPC canonica: l'app è su un'altra origine dell'API, quindi il
    // preflight CORS passa al server reale e solo la POST riceve la risposta finta con gli header CORS.
    const stati: number[] = [];
    page.on("response", (r) => {
      if (/vini_canonici_cerca/.test(r.url()) && r.request().method() === "POST") stati.push(r.status());
    });
    await page.route("**/rest/v1/rpc/vini_canonici_cerca", (route) => {
      if (route.request().method() !== "POST") return route.continue();
      return route.fulfill({
        status: 500,
        contentType: "application/json",
        headers: { "access-control-allow-origin": "*" },
        body: JSON.stringify({ message: "boom" }),
      });
    });
    await cerca(page, PRODUTTORE_E2E, nomeSingolo);
    await expect(schede(page, nomeSingolo)).toHaveCount(1);
    await expect(page.getByTestId("ricerca-manuale-errore")).toHaveCount(0);
    expect(stati, "la RPC canonica deve aver risposto davvero 500").toContain(500);
    await page.unroute("**/rest/v1/rpc/vini_canonici_cerca");

    // Lentezza: oltre il tetto del client (1,5 s) la principale non aspetta; la scheda tardiva non arriva.
    await page.route("**/rest/v1/rpc/vini_canonici_cerca", async (route) => {
      await new Promise((r) => setTimeout(r, 5000));
      await route.continue().catch(() => undefined);
    });
    const annullate: string[] = [];
    page.on("requestfailed", (r) => {
      if (/vini_canonici_cerca/.test(r.url())) annullate.push(r.failure()?.errorText ?? "");
    });
    const inizio = Date.now();
    await cerca(page, PRODUTTORE_E2E, nomeSingolo);
    await expect(schede(page, nomeSingolo)).toHaveCount(1, { timeout: 4000 });
    expect(Date.now() - inizio, "la ricerca ha aspettato il canonico lento").toBeLessThan(4500);
    await expect(page.getByTestId("ricerca-manuale-errore")).toHaveCount(0);
    await expect(page.getByTestId("ricerca-manuale-candidati").getByText(CON_LWIN)).toHaveCount(0);
    // FIX-03B: scaduto il tetto, il client annulla la richiesta canonica invece di lasciarla pendente.
    await expect.poll(() => annullate.length, { timeout: 3000 }).toBeGreaterThan(0);
    await page.unroute("**/rest/v1/rpc/vini_canonici_cerca").catch(() => undefined);
    await contesto.close();
  });

  test("WI-008: scheda autonoma solo per utenti identificati; in Cantina la scelta è personale, esplicita e reversibile", async ({ browser, diagnostica }, info) => {
    impostaProiezione(true);
    diagnostica.ammetti("/vino-catalogo/");
    const slug = leggiDalDatabase(`select slug from public.wines where id = '${vinoVineaId}';`);
    const collegamenti = () => leggiDalDatabase("select count(*) from catalog.wine_links;");
    const scelte = () =>
      leggiDalDatabase(`select coalesce(string_agg(lwin7, ','), '') from public.wine_catalog_selections where wine_id = '${vinoVineaId}';`);
    const collegamentiPrima = collegamenti();
    const prima = scritture();

    const anonimo = await browser.newContext(opzioniDelProgetto(info));
    const pagina = await anonimo.newPage();
    await pagina.goto(`/vino-catalogo/${LWIN_SINGOLO}`);
    await expect(pagina.getByTestId("scheda-catalogo-accesso")).toBeVisible();
    await expect(pagina.getByText(nomeSingolo)).toHaveCount(0);
    await anonimo.close();

    const { contesto, page } = await apriIdentificazione(browser, "venditore", info, diagnostica);
    await page.goto(`/vino-catalogo/${LWIN_SINGOLO}`);
    const scheda = page.getByTestId("scheda-catalogo");
    await expect(scheda).toContainText(`LWIN ${LWIN_SINGOLO}`);
    await expect(scheda).toContainText(nomeSingolo);
    await expect(page.getByTestId("scheda-catalogo-mancanti")).toContainText("Prezzo");
    await expect(scheda.locator("img")).toHaveCount(0);
    await expect(page.locator('meta[name="robots"]').first()).toHaveAttribute("content", /noindex/);

    await page.goto("/cantina");
    await page.getByTestId(`catalogo-${slug}-cerca`).click();
    const candidati = page.getByTestId(`catalogo-${slug}-candidati`);
    await expect(candidati).toContainText(`LWIN ${LWIN_SINGOLO}`);
    expect(scelte()).toBe("");
    await expect(page.getByTestId(`catalogo-${slug}-conferma`)).toBeDisabled();
    await candidati.locator("label", { hasText: LWIN_SINGOLO }).locator("input").check();
    await page.getByTestId(`catalogo-${slug}-conferma`).click();
    await expect(page.getByTestId(`catalogo-${slug}`)).toContainText(`scelta da te: LWIN ${LWIN_SINGOLO}`);
    expect(scelte()).toBe(LWIN_SINGOLO);
    await page.reload();
    await expect(page.getByTestId(`catalogo-${slug}`)).toContainText(`LWIN ${LWIN_SINGOLO}`);
    await page.getByTestId(`catalogo-${slug}-rimuovi`).click();
    await expect(page.getByTestId(`catalogo-${slug}-cerca`)).toBeVisible();
    expect(scelte()).toBe("");
    expect(collegamenti()).toBe(collegamentiPrima);
    expect(scritture()).toBe(prima);

    // Catalogo spento: la scheda non esiste più e in Cantina non compare alcun comando.
    impostaProiezione(false);
    await page.goto(`/vino-catalogo/${LWIN_SINGOLO}`);
    await expect(page.getByTestId("scheda-catalogo")).toHaveCount(0);
    await page.goto("/cantina");
    await expect(page.getByText(nomeSingolo).first()).toBeVisible();
    await expect(page.getByTestId(`catalogo-${slug}-cerca`)).toHaveCount(0);
    await contesto.close();
  });
});
