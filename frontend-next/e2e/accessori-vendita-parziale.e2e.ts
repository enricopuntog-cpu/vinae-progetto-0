import type { Page } from "@playwright/test";
import {
  accedi,
  accendiPubblicazione,
  accendiVisibilitaCantina,
  firmaFoto,
  passwordFixture,
  rpc,
} from "./support/api";
import { contestoAutenticato, opzioniDelProgetto } from "./support/browser";
import { eseguiSql, ripristinaFixture } from "./support/db";
import { pngSintetico } from "./support/immagine";
import { attendiCaricamento } from "./support/pagina";
import { expect, test } from "./support/test";

/**
 * Flusso completo Accessori su stack isolato, con utenti distinti:
 * venditore (Cantina, foto, esposizione, vendita parziale 2 pezzi su 6),
 * altro account (vetrina e dettaglio), segnalante, amministratore.
 * Un annuncio pubblicato è una vetrina: nessun acquisto, ordine o pagamento.
 */

const NOME = "Calice E2E vendita parziale";
const NOTA_PRIVATA = "NOTA-PRIVATA-E2E-UI";
const euro = (cents: number): string =>
  new Intl.NumberFormat("it-IT", { style: "currency", currency: "EUR" }).format(cents / 100).replace(/\s/g, " ");

const RICHIESTE_DI_ACQUISTO = /payments-checkout|stripe|\/checkout\/|\/ordine\//i;

/** Risposta del database (camelCase), ciò che la UI deve mostrare senza ricalcolare. */
interface Preventivo {
  preventivo: {
    quantita: number;
    prezzoUnitarioCents: number;
    subtotaleCents: number;
    commissioneCents: number;
    totaleCents: number;
    quotaVineaCents: number;
    costoPagamentoRiferimentoCents: number;
  };
}

test.describe.serial("Accessori: vendita parziale 2 su 6, moderazione e assenza di acquisti @smoke", () => {
  const richiesteAcquisto: string[] = [];
  let venditoreId = "";
  let annuncioUrl = "";
  let cantinaId = "";
  let percorsoFoto = "";

  const osservaAcquisti = (page: Page) =>
    page.on("request", (r) => {
      if (RICHIESTE_DI_ACQUISTO.test(r.url())) richiesteAcquisto.push(r.url());
    });

  test.beforeAll(async () => {
    ripristinaFixture(passwordFixture());
    await accendiPubblicazione();
    venditoreId = (await accedi("venditore")).id;
  });

  test("1. il venditore aggiunge 6 calici alla Cantina (privati) e carica la foto", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    osservaAcquisti(page);

    await page.goto("/cantina");
    await attendiCaricamento(page);
    await expect(page.getByTestId("cantina-accessori")).toBeVisible();

    await page.getByRole("button", { name: "Aggiungi accessorio" }).click();
    const dialogo = page.getByRole("dialog", { name: "Nuovo accessorio" });
    const tipo = dialogo.getByLabel("Tipo di accessorio");
    await tipo.selectOption(await tipo.locator("option", { hasText: "Calici da rosso" }).first().getAttribute("value"));
    await dialogo.getByLabel("Nome", { exact: true }).fill(NOME);
    const condizione = dialogo.getByLabel("Condizione");
    await condizione.selectOption(await condizione.locator("option", { hasText: "Usato" }).first().getAttribute("value"));
    await dialogo.getByLabel("Quantità").fill("6");
    await dialogo.getByLabel("Note private (visibili solo a te)").fill(NOTA_PRIVATA);
    await dialogo.getByRole("button", { name: "Salva" }).click();
    await expect(page.getByText("Accessorio salvato (privato). Ora puoi aggiungere le foto.")).toBeVisible();

    await page.getByLabel("Aggiungi una foto").setInputFiles({ name: "calice.png", mimeType: "image/png", buffer: pngSintetico() });
    await expect(page.getByText("Foto aggiunta.").first()).toBeVisible();
    await expect(page.getByAltText("Foto 1")).toBeVisible();
    await page.getByRole("dialog").getByRole("button", { name: "Chiudi" }).first().click();

    const scheda = page.getByTestId("cantina-accessorio").filter({ hasText: NOME });
    await expect(scheda).toContainText("Usato · 6 pezzi");
    await expect(scheda).toContainText("Privato");
    await info.attach("cantina-accessorio-privato.png", { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });

    // Verità dal database: una riga, 6 pezzi, nota privata presente solo per il proprietario.
    const cantina = await rpc<{ id: string; nome: string; quantita: number; immagini: string[] }[]>(
      "cantina_accessori_elenca",
      { p_archiviati: false },
      await accedi("venditore"),
    );
    const mio = cantina.body.find((a) => a.nome === NOME);
    expect(mio?.quantita).toBe(6);
    expect(mio?.immagini.length).toBe(1);
    cantinaId = mio?.id ?? "";
    percorsoFoto = mio?.immagini[0] ?? "";
    await contesto.close();
  });

  test("2. privato → esposto → visibile: l'altro account vede solo ciò che è pubblico, mai la nota", async ({ browser, diagnostica }, info) => {
    const vVenditore = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const pv = await vVenditore.newPage();
    diagnostica.osserva(pv, "venditore");
    await pv.goto("/cantina");
    await attendiCaricamento(pv);

    const vAltro = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const pa = await vAltro.newPage();
    diagnostica.osserva(pa, "altro");
    osservaAcquisti(pa);

    // Privato: nel profilo non compare nulla.
    await pa.goto(`/profilo/${venditoreId}`);
    await attendiCaricamento(pa);
    await expect(pa.getByText(NOME)).toHaveCount(0);

    // Esposto, ma l'interruttore pubblico del database è ancora spento: resta invisibile e il venditore lo sa.
    await pv.getByTestId("cantina-accessorio").filter({ hasText: NOME }).getByRole("button", { name: "Esponi" }).click();
    await pv.getByRole("button", { name: "Sì, esponi" }).click();
    await expect(pv.getByTestId("cantina-accessorio").filter({ hasText: NOME })).toContainText("non ancora visibile al pubblico");
    await pa.reload();
    await attendiCaricamento(pa);
    await expect(pa.getByText(NOME)).toHaveCount(0);

    // Acceso l'interruttore pubblico (porta del ruolo di rilascio): l'altro account lo vede, senza nota privata.
    await accendiVisibilitaCantina();
    await pa.reload();
    await attendiCaricamento(pa);
    const pubblico = pa.getByTestId("accessorio-cantina-pubblico").filter({ hasText: NOME });
    await expect(pubblico).toBeVisible();
    await expect(pubblico).toContainText("6 pezzi");
    expect(await pa.locator("body").innerText()).not.toContain(NOTA_PRIVATA);
    await info.attach("profilo-accessorio-esposto.png", { body: await pa.screenshot({ fullPage: true }), contentType: "image/png" });

    // Il venditore lo rende di nuovo privato: sparisce di nuovo per l'altro account.
    await pv.reload();
    await attendiCaricamento(pv);
    await pv.getByTestId("cantina-accessorio").filter({ hasText: NOME }).getByRole("button", { name: "Rendi privato" }).click();
    await expect(pv.getByTestId("cantina-accessorio").filter({ hasText: NOME })).toContainText("Privato");
    await pa.reload();
    await attendiCaricamento(pa);
    await expect(pa.getByText(NOME)).toHaveCount(0);

    await vVenditore.close();
    await vAltro.close();
  });

  test("3. vendita parziale: 2 pezzi su 6 a 20,00 €, preventivo mostrato = preventivo del database", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    osservaAcquisti(page);
    await page.goto("/cantina");
    await attendiCaricamento(page);

    await page.getByTestId("cantina-accessorio").filter({ hasText: NOME }).getByRole("button", { name: "Prepara annuncio" }).click();
    const dialogo = page.getByTestId("annuncio-accessorio-dialog");
    await expect(dialogo.getByTestId("avviso-acquisti-non-disponibili")).toBeVisible();
    await dialogo.getByLabel("Pezzi in vendita").fill("2");
    await dialogo.getByLabel("Prezzo per pezzo che vuoi ricevere (€)").fill("20,00");
    await dialogo.getByLabel("Descrizione dell'offerta (facoltativa)").fill("Due calici da rosso in ottimo stato.");
    await dialogo.getByRole("checkbox", { name: /Dichiaro che l'articolo non è un prodotto alcolico/ }).check();

    // Il database è l'autorità: stesso preventivo che la UI deve mostrare.
    const preventivoDb = await rpc<Preventivo>(
      "annunci_accessori_preventivo",
      { p_prezzo_unitario_cents: 2000, p_quantita: 2, p_cantina_id: cantinaId },
      await accedi("venditore"),
    );
    expect(preventivoDb.ok).toBe(true);
    const p = preventivoDb.body.preventivo;
    expect(p.quantita).toBe(2);
    expect(p.subtotaleCents).toBe(4000);
    // Identità garantite dal database: totale = subtotale + commissione; commissione = quota Vinea + costi di pagamento.
    expect(p.totaleCents).toBe(p.subtotaleCents + p.commissioneCents);
    expect(p.commissioneCents).toBe(p.quotaVineaCents + p.costoPagamentoRiferimentoCents);

    await expect(dialogo.getByTestId("riepilogo-ricevi")).toHaveText(euro(p.subtotaleCents));
    await expect(dialogo.getByTestId("riepilogo-totale")).toHaveText(euro(p.totaleCents));
    await expect(dialogo.getByTestId("riepilogo-commissione")).toHaveText(euro(p.quotaVineaCents));
    await expect(dialogo.getByTestId("riepilogo-pagamento")).toHaveText(euro(p.costoPagamentoRiferimentoCents));
    await expect(dialogo.getByTestId("riepilogo-spedizione")).toContainText("Preventivo non disponibile");
    await info.attach("annuncio-preventivo.png", { body: await page.screenshot(), contentType: "image/png" });

    await dialogo.getByRole("button", { name: "Salva bozza" }).click();
    await expect(dialogo.getByRole("button", { name: "Pubblica annuncio" })).toBeEnabled();
    await contesto.close();
  });

  test("4. la pubblicazione è automatica (ambiente di prova) e la Cantina resta a 6 pezzi", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    osservaAcquisti(page);
    await page.goto("/cantina");
    await attendiCaricamento(page);

    await page.getByTestId("cantina-accessorio").filter({ hasText: NOME }).getByRole("button", { name: "Gestisci annuncio" }).click();
    await page.getByTestId("annuncio-accessorio-dialog").getByRole("button", { name: "Pubblica annuncio" }).click();
    await page.getByTestId("annuncio-accessorio-dialog").getByRole("button", { name: "Chiudi" }).click();

    const scheda = page.getByTestId("cantina-accessorio").filter({ hasText: NOME });
    await expect(scheda.getByTestId("vendita-accessorio-stato")).toContainText("Pubblicato · 2 pezzi a 20,00 €");
    await expect(scheda.getByTestId("vendita-accessorio-stato")).toContainText("In vetrina, non acquistabile.");
    await expect(scheda).toContainText("Usato · 6 pezzi");

    const mie = await rpc<{ id: string; stato: string; pubblico: boolean; quantita: number }[]>(
      "annunci_accessori_elenca",
      { p_ritirati: false },
      await accedi("venditore"),
    );
    const annuncio = mie.body.find((a) => a.stato === "pubblicato");
    expect(annuncio?.pubblico).toBe(true);
    expect(annuncio?.quantita).toBe(2);
    annuncioUrl = `/accessori/annunci/${annuncio?.id}`;
    await contesto.close();
  });

  test("5. un altro account vede vetrina e dettaglio, senza alcun controllo di acquisto", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "altro");
    osservaAcquisti(page);

    await page.goto("/accessori/annunci");
    const carta = page.locator(`a[href="${annuncioUrl}"]`);
    await expect(carta).toBeVisible();
    await expect(carta).toContainText(NOME);
    await expect(carta).toContainText("2 pezzi");
    await expect(carta).toContainText("22,73 € a pezzo");
    await expect(carta).toContainText("Non ancora acquistabile");

    await carta.click();
    await expect(page).toHaveURL(new RegExp(`${annuncioUrl}$`));
    await expect(page.getByRole("heading", { name: NOME })).toBeVisible();
    await expect(page.getByText("2 pezzi offerti")).toBeVisible();
    await expect(page.getByText("Gli acquisti non sono ancora disponibili.").first()).toBeVisible();
    const corpo = await page.locator("body").innerText();
    expect(corpo).not.toContain(NOTA_PRIVATA);
    expect(corpo).not.toContain("20,00 €"); // il prezzo del venditore non è pubblico, solo quello per l'acquirente
    await expect(page.getByRole("button", { name: /acquista|compra|prenota|carrello|checkout|paga/i })).toHaveCount(0);
    await expect(page.getByRole("link", { name: /acquista|compra|prenota|carrello|checkout|paga/i })).toHaveCount(0);
    await info.attach("dettaglio-altro-account.png", { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });
    await contesto.close();
  });

  test("6. un altro utente segnala l'annuncio", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "segnalante", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "segnalante");
    await page.goto(annuncioUrl);
    await attendiCaricamento(page);

    await page.getByRole("button", { name: "Segnala annuncio" }).click();
    const dialogo = page.getByRole("dialog");
    await dialogo.getByRole("radio", { name: /alcolico o regolamentato/i }).click();
    await dialogo.getByRole("button", { name: "Continua" }).click();
    await dialogo.getByLabel("Descrizione facoltativa").fill("Segnalazione di prova E2E.");
    await dialogo.getByRole("button", { name: "Invia segnalazione" }).click();
    await expect(dialogo.getByText("La segnalazione è stata registrata.")).toBeVisible();

    const mie = await fetch(`${process.env.E2E_SUPABASE_URL}/rest/v1/my_reports?select=target_tipo,stato,priorita`, {
      headers: { apikey: process.env.E2E_ANON_KEY ?? "", Authorization: `Bearer ${(await accedi("segnalante")).token}` },
    });
    const righe = (await mie.json()) as { target_tipo: string; priorita: string }[];
    expect(righe).toHaveLength(1);
    expect(righe[0].target_tipo).toBe("annuncio_accessorio");
    await contesto.close();
  });

  test("7. l'amministratore oscura l'annuncio dalla pratica; il contenuto non è più raggiungibile", async ({ browser, diagnostica }, info) => {
    diagnostica.ammetti("status of 404"); // il dettaglio oscurato risponde 404: è l'esito atteso
    const admin = await contestoAutenticato(browser, "adminSenzaRilascio", opzioniDelProgetto(info));
    const pad = await admin.newPage();
    diagnostica.osserva(pad, "admin");
    await pad.goto("/admin/accessori");
    await attendiCaricamento(pad);

    const moderazione = pad.getByTestId("moderazione-annunci-accessori");
    await moderazione.getByRole("button", { name: "Con segnalazioni aperte" }).click();
    const riga = moderazione.locator("li").filter({ hasText: NOME });
    await expect(riga).toContainText("1 segnalazione aperta");
    await riga.getByRole("button", { name: "Apri" }).click();

    const dettaglio = pad.getByTestId("moderazione-dettaglio");
    await expect(dettaglio).toBeVisible();
    await dettaglio.getByRole("button", { name: "Oscura (sospendi)" }).click();
    await dettaglio.getByLabel("Motivazione (obbligatoria, visibile al venditore)").fill("Verifica E2E: sospetto articolo regolamentato.");
    await info.attach("moderazione-oscura.png", { body: await pad.screenshot(), contentType: "image/png" });
    await dettaglio.getByRole("button", { name: "Conferma: Oscura (sospendi)" }).click();
    await expect(pad.getByRole("status").filter({ hasText: /oscurato|sospes|provvedimento|registrat/i }).first()).toBeVisible();
    await admin.close();

    // Altro account e anonimo: fuori vetrina, dettaglio 404.
    const altro = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const pa = await altro.newPage();
    diagnostica.osserva(pa, "altro");
    osservaAcquisti(pa);
    await pa.goto("/accessori/annunci");
    await expect(pa.getByText("Nessun annuncio in vetrina")).toBeVisible();
    await expect(pa.locator(`a[href="${annuncioUrl}"]`)).toHaveCount(0);
    expect((await pa.goto(annuncioUrl))?.status()).toBe(404);
    await altro.close();

    const anonimo = await browser.newContext(opzioniDelProgetto(info));
    const pn = await anonimo.newPage();
    diagnostica.osserva(pn, "anonimo");
    expect((await pn.goto(annuncioUrl))?.status()).toBe(404);
    await anonimo.close();

    // La foto non si firma più per il pubblico; il database lo conferma.
    expect(await firmaFoto(percorsoFoto)).toBeGreaterThanOrEqual(400);
    const dettaglioPubblico = await rpc("annunci_accessori_pubblico_dettaglio", { p_id: annuncioUrl.split("/").pop() });
    expect(dettaglioPubblico.body).toBeNull();
  });

  test("8. il venditore vede che Vinea è intervenuta e non può riaprire l'annuncio", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    await page.goto("/cantina");
    await attendiCaricamento(page);
    const scheda = page.getByTestId("cantina-accessorio").filter({ hasText: NOME });
    await expect(scheda.getByTestId("vendita-accessorio-stato")).toContainText("Vinea è intervenuta");
    await scheda.getByRole("button", { name: "Gestisci annuncio" }).click();
    const dialogo = page.getByTestId("annuncio-accessorio-dialog");
    await expect(dialogo.getByTestId("annuncio-stato-messaggio")).toBeVisible();
    await expect(dialogo.getByRole("button", { name: "Pubblica annuncio" })).toHaveCount(0);
    await info.attach("venditore-annuncio-oscurato.png", { body: await page.screenshot(), contentType: "image/png" });
    await contesto.close();
  });

  test("9. nessun acquisto, ordine o pagamento in tutto il flusso", async () => {
    expect(richiesteAcquisto, `Richieste di acquisto inattese:\n${richiesteAcquisto.join("\n")}`).toEqual([]);
    expect(eseguiSql("select count(*) from public.orders;")).toBe("0");
  });
});
