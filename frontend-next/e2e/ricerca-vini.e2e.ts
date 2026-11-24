import { passwordFixture } from "./support/api";
import { ripristinaFixture } from "./support/db";
import { problemiAccessibilita, senzaScorrimentoOrizzontale } from "./support/pagina";
import { expect, test } from "./support/test";
import { apriIdentificazione, cerca } from "./support/wizard-ricerca";
import {
  PRODUTTORE_E2E,
  etichettaCorsa,
  leggiDalDatabase,
  preparaBottigliaInCantina,
  pubblicaAnnuncioVino,
} from "./support/vino";
import type { Page } from "@playwright/test";

/**
 * WI-006A · ricerca dei vini nel passo Identificazione di `/vendi`, su dati reali dello stack isolato.
 *
 * Tre vini sintetici: uno PRIVATO del venditore (scheda utente nella sua Cantina), uno del venditore con
 * un ANNUNCIO PUBBLICO attivo, uno PRIVATO dell'altro utente. Prova, dal browser e con token veri:
 * - il venditore ritrova i propri vini e non vede quello privato dell'altro;
 * - l'altro utente vede il vino pubblicato ma non il privato del venditore;
 * - la scelta è esplicita («Usa questo vino» riempie i campi, «Nessuno» non tocca nulla);
 * - la ricerca non scrive: nessuna richiesta di scrittura, nessun vino nuovo, nessuna Edge Function (AI).
 */

const EMAIL_ALTRO_RUOLO = "altro" as const;

test.describe.serial("Ricerca dei vini nel wizard: dati accessibili, scelta esplicita, nessuna scrittura @smoke @cross", () => {
  const corsa = etichettaCorsa();
  const nomePrivato = `Segreto ${corsa}`;
  const nomePubblico = `Vetrina ${corsa}`;
  const nomeAltro = `Cassetto ${corsa}`;

  test.beforeAll(async () => {
    ripristinaFixture(passwordFixture());
    await preparaBottigliaInCantina("venditore", { nome: nomePrivato, annata: 2016 });
    const pubblico = await preparaBottigliaInCantina("venditore", { nome: nomePubblico, annata: 2017 });
    await pubblicaAnnuncioVino("venditore", pubblico.bottleUnitIds[0], 4200);
    await preparaBottigliaInCantina(EMAIL_ALTRO_RUOLO, { nome: nomeAltro, annata: 2018 });
  });

  const contaVini = () => leggiDalDatabase(`select count(*) from public.wines where nome like '%${corsa}';`).trim();

  /**
   * La ricerca ha risposto (elenco o «nessun vino») senza errore e il vino cercato NON è tra i candidati.
   * Il token della corsa è condiviso dai vini sintetici, quindi un elenco di altri vini è legittimo.
   */
  async function esitoSenza(page: Page, nome: string) {
    await expect(page.getByTestId("ricerca-manuale-candidati").or(page.getByTestId("ricerca-manuale-nessuno-trovato"))).toBeVisible();
    await expect(page.getByTestId("ricerca-manuale-errore")).toHaveCount(0);
    await expect(page.getByTestId("ricerca-manuale-candidati")).not.toContainText(nome);
  }

  test("il venditore ritrova i propri vini, sceglie e conferma; l'altro privato non compare; nessuna scrittura", async ({ browser, diagnostica }, info) => {
    const viniPrima = contaVini();
    const { contesto, page, richieste } = await apriIdentificazione(browser, "venditore", info, diagnostica);
    const ricerca = page.getByTestId("ricerca-manuale");
    await expect(ricerca).toBeVisible();
    expect(await senzaScorrimentoOrizzontale(page), "scorrimento orizzontale").toBe(true);
    expect(await problemiAccessibilita(page)).toEqual([]);

    // Senza gesto non parte nessuna ricerca sui vini.
    expect(richieste.filter((r) => /\/rest\/v1\/wines|public_listings|rpc\/vini_cerca/.test(r.url))).toEqual([]);

    // Ricerca per nome parziale: il proprio vino privato c'è, quello dell'altro no.
    await cerca(page, PRODUTTORE_E2E, nomePrivato);
    const candidati = ricerca.getByTestId("ricerca-manuale-candidati");
    await expect(candidati).toBeVisible();
    await expect(candidati).toContainText(nomePrivato);
    await expect(candidati).not.toContainText(nomeAltro);
    await info.attach(`ricerca-risultati-${info.project.name}.png`, { body: await ricerca.screenshot(), contentType: "image/png" });

    // Finché l'utente non sceglie, «Usa questo vino» è spento e i campi restano come digitati.
    await expect(page.getByTestId("ricerca-manuale-usa-btn")).toBeDisabled();
    await expect(page.getByLabel("Nome / Etichetta", { exact: true })).toHaveValue(nomePrivato);

    // Refuso nel nome (OCR): il vino si ritrova comunque.
    await cerca(page, PRODUTTORE_E2E, nomePrivato.replace("Segreto", "Segrteo"));
    await expect(page.getByTestId("ricerca-manuale-candidati")).toContainText(nomePrivato);

    // Un altro vino privato (dell'altro utente) cercato per nome esatto: nessun risultato, non un errore.
    await cerca(page, PRODUTTORE_E2E, nomeAltro);
    await esitoSenza(page, nomeAltro);
    await expect(page.getByTestId("ricerca-manuale-errore")).toHaveCount(0);

    // Scelta esplicita: i campi si riempiono solo con «Usa questo vino».
    await cerca(page, PRODUTTORE_E2E, nomePrivato);
    await ricerca.getByTestId("ricerca-manuale-candidati").locator("label", { hasText: nomePrivato }).locator("input").check();
    await page.getByTestId("ricerca-manuale-usa-btn").click();
    await expect(page.getByTestId("ricerca-manuale-applicato")).toBeVisible();
    await expect(page.getByLabel("Annata", { exact: true })).toHaveValue("2016");
    await info.attach(`ricerca-confermata-${info.project.name}.png`, { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });

    // «Nessuno di questi» lascia i campi com'erano e permette di continuare a mano.
    await cerca(page, PRODUTTORE_E2E, nomePrivato);
    await ricerca.getByTestId("ricerca-manuale-candidati").locator("label", { hasText: nomePrivato }).locator("input").check();
    await page.getByTestId("ricerca-manuale-nessuno").click();
    await expect(page.getByTestId("ricerca-manuale-usa-btn")).toBeDisabled();
    await expect(page.getByLabel("Nome / Etichetta", { exact: true })).toHaveValue(nomePrivato);
    await page.getByLabel("Nome / Etichetta", { exact: true }).fill(`Nuovo ${corsa}`);
    await cerca(page, PRODUTTORE_E2E, `Nuovo ${corsa}`);
    await esitoSenza(page, `Nuovo ${corsa}`);
    await expect(page.getByLabel("Nome / Etichetta", { exact: true })).toHaveValue(`Nuovo ${corsa}`);

    // La ricerca passa dal motore sul server (RPC `vini_cerca`, WI-006B): ogni richiesta è un POST di sola
    // lettura, nessun ripiego sulle tabelle (il motore ha risposto), nessuna Edge Function (AI), nessun vino nuovo.
    const ricerche = richieste.filter((r) => /\/rest\/v1\/rpc\/vini_cerca/.test(r.url));
    expect(ricerche.length).toBeGreaterThan(0);
    expect(ricerche.every((r) => r.metodo === "POST")).toBe(true);
    expect(richieste.filter((r) => /\/rest\/v1\/(wines|public_listings)\?/.test(r.url))).toEqual([]);
    expect(richieste.filter((r) => /\/functions\/v1\//.test(r.url))).toEqual([]);
    // Nessuna scrittura su tabelle (le RPC della pagina sono POST di sola lettura, non la ricerca); il conteggio dei vini lo prova sotto.
    expect(richieste.filter((r) => /\/rest\/v1\//.test(r.url) && !/\/rest\/v1\/rpc\//.test(r.url) && r.metodo !== "GET")).toEqual([]);
    expect(contaVini()).toBe(viniPrima);
    await contesto.close();
  });

  test("l'altro utente vede il vino pubblicato ma non il privato del venditore; ritrova il proprio", async ({ browser, diagnostica }, info) => {
    const { contesto, page } = await apriIdentificazione(browser, "altro", info, diagnostica);

    await cerca(page, PRODUTTORE_E2E, nomePubblico);
    await expect(page.getByTestId("ricerca-manuale-candidati")).toContainText(nomePubblico);

    await cerca(page, PRODUTTORE_E2E, nomePrivato);
    await esitoSenza(page, nomePrivato);

    await cerca(page, PRODUTTORE_E2E, nomeAltro);
    await expect(page.getByTestId("ricerca-manuale-candidati")).toContainText(nomeAltro);
    await expect(page.getByTestId("ricerca-manuale-candidati")).not.toContainText(nomePrivato);
    await contesto.close();
  });
});
