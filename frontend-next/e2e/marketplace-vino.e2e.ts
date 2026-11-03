import type { Page } from "@playwright/test";
import { EMAIL, accedi, passwordFixture, rpc } from "./support/api";
import { contestoAutenticato, opzioniDelProgetto } from "./support/browser";
import { ripristinaFixture } from "./support/db";
import { attendiCaricamento, problemiAccessibilita, senzaScorrimentoOrizzontale } from "./support/pagina";
import { risolviBersaglio } from "./support/stack";
import { expect, test } from "./support/test";
import {
  PRODUTTORE_E2E,
  UUID_INESISTENTE,
  etichettaCorsa,
  leggiDalDatabase,
  preparaBottigliaInCantina,
  pubblicaAnnuncioVino,
  type BottigliaPreparata,
  uuid,
} from "./support/vino";

/**
 * Marketplace vino (VPM-018-E2E-CRIT-01). Due account distinti: il venditore
 * ha una bottiglia in Cantina (preparata con la porta reale della Cantina) e la
 * pubblica dal wizard `/vendi` nel browser; un altro utente la cerca in
 * `/esplora`, apre la scheda e ne legge prezzo, titolo e disponibilità. La
 * scheda non espone dati privati del venditore (email, costo d'acquisto,
 * consegna scelta), un estraneo non la gestisce e non la modifica, e un annuncio
 * rimosso dalla vendita o inesistente non è più raggiungibile.
 */

const PREZZO_EURO = "42";
// `formatEUR` omette i decimali nulli: «42 €».
const PREZZO_MOSTRATO = /^42(,00)?\s€$/;
// Costo d'acquisto privato della bottiglia (37,21 €): non deve comparire in nessuna pagina pubblica.
const COSTO_PRIVATO_CENTS = 3721;

// `/esplora` ha anche lo scheletro di caricamento con lo stesso campo: si usa quello visibile.
const campoRicerca = (page: Page) => page.getByTestId("esplora-search-input").filter({ visible: true });

const attendiSchedaVino = async (page: Page, titolo: string) => {
  await attendiCaricamento(page);
  await expect(page.getByRole("heading", { level: 1, name: new RegExp(titolo) })).toBeVisible();
};

test.describe.serial("Marketplace vino: pubblicazione dal wizard, ricerca, scheda e isolamento @smoke", () => {
  const nomeVino = `Barolo E2E-CRIT ${etichettaCorsa()}`;
  let bottiglia: BottigliaPreparata;
  let listingId = "";
  let slug = "";

  test.beforeAll(async () => {
    ripristinaFixture(passwordFixture());
    bottiglia = await preparaBottigliaInCantina("venditore", { nome: nomeVino, costoAcquistoCents: COSTO_PRIVATO_CENTS });
  });

  test("il venditore pubblica la bottiglia della Cantina dal wizard e il database la conferma attiva", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");

    await page.goto("/vendi?mode=sell");
    await attendiCaricamento(page);
    await expect(page.getByRole("heading", { name: "Scegli dalla tua Cantina" })).toBeVisible();
    await page.getByRole("link", { name: new RegExp(nomeVino) }).click();
    await expect(page).toHaveURL(new RegExp(`bottiglia=${bottiglia.bottleUnitIds[0]}`));
    await expect(page.getByRole("heading", { name: "Vendi la tua bottiglia" })).toBeVisible();

    const continua = page.getByRole("button", { name: /Continua/ });
    // Con la bottiglia già scelta il wizard parte dalle Fotografie (il passo «Modalità» non ha nulla da chiedere).
    await expect(page.getByText("Passo 1 di 7")).toBeVisible();
    await expect(page.getByRole("heading", { name: "Fotografie", exact: true })).toBeVisible();
    await continua.click();
    await expect(page.getByRole("heading", { name: "Identificazione", exact: true })).toBeVisible();
    await expect(page.getByText(PRODUTTORE_E2E)).toBeVisible();
    await continua.click();
    await expect(page.getByRole("heading", { name: "Condizioni", exact: true })).toBeVisible();
    await page.getByRole("button", { name: "Ottimo" }).click();
    await continua.click();
    await expect(page.getByRole("heading", { name: "Provenienza e conservazione" })).toBeVisible();
    // Il componente `Field` del wizard non associa la Label al campo (nessun `htmlFor`): si usa il segnaposto.
    await page.getByPlaceholder(/Cantina climatizzata/).fill("Cantina interrata, 14 gradi, bottiglia coricata.");
    await continua.click();
    await expect(page.getByRole("heading", { name: "Prezzo", exact: true })).toBeVisible();
    await page.getByPlaceholder("Inserisci il prezzo").fill(PREZZO_EURO);
    await continua.click();
    await expect(page.getByRole("heading", { name: "Consegna", exact: true })).toBeVisible();
    // Senza le due dichiarazioni il passo non si supera (il database rifiuterebbe la pubblicazione).
    await continua.click();
    await expect(page.getByRole("heading", { name: "Consegna", exact: true })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Anteprima", exact: true })).toHaveCount(0);
    await page.getByRole("button", { name: /Nessuna confezione originale/ }).click();
    await page.getByRole("button", { name: /Drop-off presso punto di consegna/ }).click();
    await continua.click();
    await expect(page.getByRole("heading", { name: "Anteprima", exact: true })).toBeVisible();
    await expect(page.getByText(PREZZO_MOSTRATO).first()).toBeVisible();

    await page.getByRole("button", { name: "Pubblica annuncio" }).click();
    await expect(page.getByText("Annuncio pubblicato")).toBeVisible();
    await expect(page).toHaveURL(/\/cantina/);

    // Il database è l'autorità: un solo annuncio attivo del venditore, al prezzo digitato, su quella bottiglia.
    const riga = leggiDalDatabase(
      `select l.id || ' ' || coalesce(l.slug, '') || ' ' || l.stato || ' ' || l.prezzo_cents
         from public.listings l join private.listing_unita u on u.listing_id = l.id
        where u.bottle_unit_id = '${bottiglia.bottleUnitIds[0]}' and l.seller_id = '12ab2000-0000-4000-8000-000000000002';`,
    );
    const [id, slugLetto, stato, prezzo] = riga.split(" ");
    expect(stato).toBe("attivo");
    expect(prezzo).toBe("4200");
    listingId = uuid(id);
    slug = slugLetto || id;
    await info.attach("cantina-dopo-pubblicazione.png", { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });
    await contesto.close();
  });

  test("un altro utente la trova cercando in /esplora e la scheda mostra titolo, prezzo e disponibilità", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");

    await page.goto("/esplora");
    await attendiCaricamento(page);
    await campoRicerca(page).fill(nomeVino);
    const carta = page.getByRole("link", { name: new RegExp(nomeVino) }).first();
    await expect(carta).toBeVisible();
    await carta.click();
    await expect(page).toHaveURL(new RegExp(`/annuncio/(${slug}|${listingId})`));

    await attendiSchedaVino(page, nomeVino);
    await expect(page.getByText(PRODUTTORE_E2E).first()).toBeVisible();
    await expect(page.getByText(PREZZO_MOSTRATO).first()).toBeVisible();
    await expect(page.getByText("1 bottiglia disponibile")).toBeVisible();
    await expect(page.getByRole("link", { name: "e2e12zk_u02", exact: true })).toBeVisible();
    await expect(page.getByText("Venditore privato")).toBeVisible();
    await expect(page.getByText(/Totale stimato/)).toBeVisible();
    // Comandi del proprietario assenti per chi non lo è.
    await expect(page.getByRole("button", { name: /Rimuovi dalla vendita/ })).toHaveCount(0);
    await expect(page.getByRole("button", { name: /^Modifica$/ })).toHaveCount(0);
    expect(await senzaScorrimentoOrizzontale(page), "scorrimento orizzontale").toBe(true);
    await info.attach("scheda-acquirente.png", { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });
    await contesto.close();
  });

  test("la scheda e la ricerca non espongono dati privati del venditore", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    const risposte: Promise<string>[] = [];
    page.on("response", (r) => {
      if (r.url().includes("/rest/v1/") && r.request().method() === "GET") risposte.push(r.text().catch(() => ""));
    });

    await page.goto(`/annuncio/${slug}`);
    await attendiSchedaVino(page, nomeVino);
    const html = await page.content();
    const visibile = await page.locator("body").innerText();
    for (const privato of [EMAIL.venditore, "37,21", "Drop-off presso punto di consegna", "dropoff_pudo"]) {
      expect(visibile, `testo privato visibile: ${privato}`).not.toContain(privato);
      expect(html, `testo privato nell'HTML: ${privato}`).not.toContain(privato);
    }
    // La scheda è resa dal server: il browser può non leggere REST. Si aggiunge quindi la lettura
    // pubblica dell'annuncio fatta dall'acquirente, che deve trovarlo (controllo positivo) senza dati privati.
    const { apiUrl, anonKey } = risolviBersaglio();
    const altro = await accedi("altro");
    const pubblica = await fetch(`${apiUrl}/rest/v1/public_listings?id=eq.${listingId}&select=*`, {
      headers: { apikey: anonKey, Authorization: `Bearer ${altro.token}` },
    });
    expect(pubblica.ok).toBe(true);
    const corpoPubblico = await pubblica.text();
    expect(corpoPubblico, "annuncio nella lettura pubblica").toContain(listingId);
    const corpi = [corpoPubblico, ...(await Promise.all(risposte))];
    await info.attach("letture-rest.json", { body: JSON.stringify({ letture: corpi.length }), contentType: "application/json" });
    for (const corpo of corpi) {
      expect(corpo).not.toContain(EMAIL.venditore);
      expect(corpo).not.toContain(String(COSTO_PRIVATO_CENTS));
      expect(corpo).not.toContain("dropoff_pudo");
    }
    await contesto.close();
  });

  test("un utente diverso non può modificare né ritirare l'annuncio, nemmeno chiamando le porte", async ({ browser, diagnostica }, info) => {
    const altro = await accedi("altro");
    // Le porte del venditore rifiutano un estraneo: nessuna riga cambia.
    const sospendi = await rpc("listing_sospendi", { p_listing_id: listingId, p_motivo: "tentativo estraneo" }, altro);
    expect(sospendi.ok).toBe(false);
    const { apiUrl, anonKey } = risolviBersaglio();
    const patch = await fetch(`${apiUrl}/rest/v1/listings?id=eq.${listingId}`, {
      method: "PATCH",
      headers: { apikey: anonKey, Authorization: `Bearer ${altro.token}`, "Content-Type": "application/json", Prefer: "return=representation" },
      body: JSON.stringify({ prezzo_cents: 100 }),
    });
    const righe = patch.ok ? ((await patch.json()) as unknown[]) : [];
    expect(righe).toEqual([]);
    expect(leggiDalDatabase(`select stato || ' ' || prezzo_cents from public.listings where id = '${listingId}';`)).toBe("attivo 4200");

    // Nel browser: il wizard non apre la bottiglia di un altro.
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "estraneo");
    await page.goto(`/vendi?mode=sell&bottiglia=${bottiglia.bottleUnitIds[0]}`);
    await attendiCaricamento(page);
    await expect(page.getByRole("heading", { name: "Bottiglia non trovata" })).toBeVisible();
    await contesto.close();
  });

  test("il venditore la rimuove dalla vendita: per gli altri scheda 404 e fuori dalla ricerca", async ({ browser, diagnostica }, info) => {
    const venditore = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const pagina = await venditore.newPage();
    diagnostica.osserva(pagina, "venditore");
    await pagina.goto(`/annuncio/${slug}`);
    await attendiSchedaVino(pagina, nomeVino);
    await pagina.getByRole("button", { name: /Rimuovi dalla vendita/ }).click();
    await pagina.getByRole("dialog").getByRole("button", { name: "Rimuovi dalla vendita" }).click();
    await expect(pagina.getByText("Questo annuncio non è più visibile a chi compra.", { exact: false })).toBeVisible();
    expect(leggiDalDatabase(`select stato from public.listings where id = '${listingId}';`)).toBe("sospeso");
    await venditore.close();

    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    diagnostica.ammetti(`/annuncio/${slug}`); // il 404 è l'esito atteso, il browser lo registra in console
    const risposta = await page.goto(`/annuncio/${slug}`);
    expect(risposta?.status()).toBe(404);
    await page.goto("/esplora");
    await attendiCaricamento(page);
    await campoRicerca(page).fill(nomeVino);
    // Controllo positivo prima dell'assenza: la ricerca ha girato e non ha trovato nulla.
    // (lo stato vuoto cambia testo se non resta alcun annuncio: si legge il contatore).
    await expect(campoRicerca(page)).toHaveValue(nomeVino);
    await expect(page.getByText(/^0 risultati$/)).toBeVisible();
    await expect(page.getByRole("link", { name: new RegExp(nomeVino) })).toHaveCount(0);
    await contesto.close();
  });

  test("un annuncio inesistente risponde 404 senza errori dell'app", async ({ page, diagnostica }) => {
    diagnostica.ammetti(`/annuncio/${UUID_INESISTENTE}`);
    const risposta = await page.goto(`/annuncio/${UUID_INESISTENTE}`);
    expect(risposta?.status()).toBe(404);
    await expect(page.getByText(nomeVino)).toHaveCount(0);
  });
});

/**
 * Scheda di un annuncio vino nei tre profili (Chromium desktop, Chromium 375 px,
 * WebKit): stato preparato con le porte reali del venditore, sola lettura.
 */
test.describe("Marketplace vino: scheda pubblica responsive e cross-browser @cross", () => {
  const nomeVino = `Nebbiolo E2E-CRIT ${etichettaCorsa()}`;
  let slug = "";

  test.beforeAll(async () => {
    ripristinaFixture(passwordFixture());
    const bottiglia = await preparaBottigliaInCantina("venditore", { nome: nomeVino });
    slug = (await pubblicaAnnuncioVino("venditore", bottiglia.bottleUnitIds[0], 2500)).slug;
  });

  test("ricerca e scheda in ogni motore: titolo, prezzo, nessuno scorrimento orizzontale", async ({ page }, info) => {
    await page.goto("/esplora");
    await attendiCaricamento(page);
    await campoRicerca(page).fill(nomeVino);
    await expect(page.getByRole("link", { name: new RegExp(nomeVino) }).first()).toBeVisible();
    expect(await senzaScorrimentoOrizzontale(page), "scorrimento orizzontale in /esplora").toBe(true);

    await page.goto(`/annuncio/${slug}`);
    await attendiSchedaVino(page, nomeVino);
    await expect(page.getByText("25,00 €").first()).toBeVisible();
    await expect(page.getByRole("link", { name: "Accedi per contattare il venditore" })).toBeVisible();
    expect(await senzaScorrimentoOrizzontale(page), "scorrimento orizzontale nella scheda").toBe(true);
    expect(await problemiAccessibilita(page)).toEqual([]);
    await info.attach(`scheda-vino-${info.project.name}.png`, { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });
  });
});
