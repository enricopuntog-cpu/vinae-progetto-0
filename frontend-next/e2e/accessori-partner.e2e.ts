import { randomUUID } from "node:crypto";
import { accedi, accendiPubblicazione, caricaFoto, idCategoriaCalici, passwordFixture, rpc } from "./support/api";
import { contestoAutenticato, opzioniDelProgetto } from "./support/browser";
import { eseguiSql, ripristinaFixture } from "./support/db";
import { pagaConEventoFirmato } from "./support/pagamenti";
import { pngSintetico } from "./support/immagine";
import { attendiCaricamento, problemiAccessibilita, senzaScorrimentoOrizzontale } from "./support/pagina";
import {
  accendiCatalogo,
  accendiCheckout,
  attivaPartner,
  creaLogisticaDiProva,
  creaSchedaCatalogo,
  decidiPartner,
  impostaVenditaPartner,
  prenotaConLeStessePorte,
} from "./support/partner";
import { expect, test } from "./support/test";

/**
 * Percorso Vinea Partner dei nuovi Accessori su stack isolato (VPM-015QA-FINAL-B2-COMPLETION):
 * Partner attivo (venditore) crea una scorta commerciale da 10 pezzi con foto e scheda di catalogo, pubblica
 * un annuncio da 6, un secondo account prenota e (con il pagamento simulato dal solo database) compra 3.
 * Poi sospensione, revoca, accessi estranei e interruttore `vendita_partner` spento. Nessun Stripe.
 * Le verità economiche vengono dal database; la UI deve mostrarle, non ricalcolarle.
 */

const NOME = "Calice Partner E2E";
const SCHEDA = "Scheda Vinea E2E partner";
const PROVIDER = "e2e_b5a";
const euro = (cents: number): string =>
  new Intl.NumberFormat("it-IT", { style: "currency", currency: "EUR" }).format(cents / 100).replace(/\s/g, " ");

const riga = (sql: string): string => eseguiSql(sql);

/** "scorta/annuncio/disponibili" dal database. */
const inventario = (cantinaId: string, annuncioId: string): string =>
  riga(`select (select quantita from private.cantina_accessori where id = '${cantinaId}') || '/'
    || (select quantita from private.annunci_accessori where id = '${annuncioId}') || '/'
    || private.accessori_disponibili('${annuncioId}');`);

test.describe.serial("Partner Accessori: scorta commerciale, vetrina, vendita, sospensione e revoca @smoke @cross", () => {
  let partnerA = "";
  let partnerB = "";
  let cantinaId = "";
  let annuncioId = "";
  let annuncioUrl = "";
  let ordinePagato = "";
  let ordineAperto = "";

  test.beforeAll(async () => {
    ripristinaFixture(passwordFixture());
    await accendiPubblicazione();
    await accendiCatalogo();
    await creaSchedaCatalogo("scheda-e2e-partner", SCHEDA);
    creaLogisticaDiProva(PROVIDER);
    await accendiCheckout();
    partnerA = await attivaPartner("venditore", "1234567890");
    partnerB = await attivaPartner("segnalante", "2345678901");
    expect(riga("select vendita_partner::text from private.inventario_impostazioni;")).toBe("false");
  });

  test("1-2. il database riconosce il Partner attivo e la pagina Partner si apre; il privato vede solo la spiegazione", async ({
    browser,
    diagnostica,
  }, info) => {
    const stato = await rpc<{ partner_stato: string; scorte_abilitate: boolean; vendita_partner: boolean }>(
      "accessori_partner_stato",
      {},
      await accedi("venditore"),
    );
    expect(stato.body).toMatchObject({ partner_stato: "attivo", scorte_abilitate: true, vendita_partner: false });

    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "partner");
    await page.goto("/partner/accessori");
    await attendiCaricamento(page);
    await expect(page.getByRole("heading", { level: 1, name: "Accessori nuovi" })).toBeVisible();
    await expect(page.getByTestId("cantina-accessori")).toContainText("Accessori nuovi in vendita");
    await expect(page.getByRole("button", { name: "Aggiungi accessorio" })).toBeVisible();
    await contesto.close();

    const estraneo = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const p = await estraneo.newPage();
    diagnostica.osserva(p, "privato");
    await p.goto("/partner/accessori");
    await attendiCaricamento(p);
    await expect(p.getByText("disponibile ai Partner attivi")).toBeVisible(); // prima il positivo: la pagina è caricata
    await expect(p.getByTestId("cantina-accessori")).toHaveCount(0);
    await expect(p.getByRole("button", { name: "Aggiungi accessorio" })).toHaveCount(0);
    await estraneo.close();
  });

  test("3-5. scorta commerciale nuova da 10 pezzi, con foto e scheda di catalogo", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "partner");
    await page.goto("/partner/accessori");
    await attendiCaricamento(page);

    await page.getByRole("button", { name: "Aggiungi accessorio" }).click();
    const dialogo = page.getByRole("dialog", { name: "Nuovo accessorio" });
    const tipo = dialogo.getByLabel("Tipo di accessorio");
    await tipo.selectOption(await tipo.locator("option", { hasText: "Calici da rosso" }).first().getAttribute("value"));
    await dialogo.getByLabel("Nome", { exact: true }).fill(NOME);
    await dialogo.getByLabel("Quantità").fill("10");
    await dialogo.getByLabel("Scheda Vinea collegata (facoltativa)").selectOption({ label: SCHEDA });
    await dialogo.getByRole("button", { name: "Salva" }).click();
    await expect(page.getByText("Ora puoi aggiungere le foto.")).toBeVisible();
    await page.getByLabel("Aggiungi una foto").setInputFiles({ name: "calice.png", mimeType: "image/png", buffer: pngSintetico() });
    await expect(page.getByText("Foto aggiunta.").first()).toBeVisible();
    await page.getByRole("dialog").getByRole("button", { name: "Chiudi" }).first().click();

    const scheda = page.getByTestId("cantina-accessorio").filter({ hasText: NOME });
    await expect(scheda).toContainText("Scorta commerciale · nuovo");
    await expect(scheda).toContainText("10 pezzi");
    await info.attach("scorta-partner.png", { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });

    const r = riga(`select id || ' ' || inventario || ' ' || quantita || ' ' || (partner_id = '${partnerA}')::text
      || ' ' || (catalogo_id is not null)::text || ' ' || coalesce(array_length(immagini, 1), 0)
      from private.cantina_accessori where nome = '${NOME}';`).split(" ");
    cantinaId = r[0];
    expect(r.slice(1)).toEqual(["commerciale", "10", "true", "true", "1"]);
    await contesto.close();
  });

  test("12. distinzione dalla Cantina privata: la scorta commerciale non compare in /cantina né del Partner né di un privato", async ({
    browser,
    diagnostica,
  }, info) => {
    // Per un Partner la «Cantina» è il catalogo commerciale del vino: le scorte Accessori vivono solo in /partner/accessori.
    const partner = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const p = await partner.newPage();
    diagnostica.osserva(p, "partner");
    await p.goto("/cantina");
    await attendiCaricamento(p);
    await expect(p.getByRole("heading", { name: "Catalogo commerciale" })).toBeVisible();
    await expect(p.getByText(NOME)).toHaveCount(0);
    await partner.close();

    const privato = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const q = await privato.newPage();
    diagnostica.osserva(q, "privato");
    await q.goto("/cantina");
    await attendiCaricamento(q);
    await expect(q.getByTestId("cantina-accessori")).toBeVisible();
    await expect(q.getByTestId("cantina-accessori")).toContainText("Accessori");
    await q.waitForLoadState("networkidle");
    await expect(q.getByText(NOME)).toHaveCount(0);
    await expect(q.getByText("Scorta commerciale")).toHaveCount(0);
    await privato.close();
  });

  test("6. annuncio commerciale: 6 pezzi su 10 a 20,00 €, pubblicato con la UI", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "partner");
    await page.goto("/partner/accessori");
    await attendiCaricamento(page);

    await page.getByTestId("cantina-accessorio").filter({ hasText: NOME }).getByRole("button", { name: "Prepara annuncio" }).click();
    const dialogo = page.getByTestId("annuncio-accessorio-dialog");
    await dialogo.getByLabel("Pezzi in vendita").fill("6");
    await dialogo.getByLabel("Prezzo per pezzo che vuoi ricevere (€)").fill("20,00");
    await dialogo.getByLabel("Descrizione dell'offerta (facoltativa)").fill("Sei calici nuovi da rosso.");
    await dialogo.getByText("Dati del pacco (facoltativi)").click();
    await dialogo.getByLabel("Peso (g)").fill("400");
    await dialogo.getByLabel("Lungh. (mm)").fill("250");
    await dialogo.getByLabel("Largh. (mm)").fill("100");
    await dialogo.getByLabel("Alt. (mm)").fill("100");
    await dialogo.getByRole("checkbox", { name: /Dichiaro che l'articolo non è un prodotto alcolico/ }).check();

    // Il prezzo all'acquirente lo calcola il database: margine Partner 1500 bps -> 2375 per un pezzo; il totale
    // della UI per 6 pezzi è quello del database (costo di pagamento una sola volta per ordine), non un calcolo del browser.
    const venditore = await accedi("venditore");
    const uno = await rpc<{ preventivo: { totaleCents: number; margineObiettivoBps: number } }>(
      "annunci_accessori_preventivo",
      { p_prezzo_unitario_cents: 2000, p_quantita: 1, p_cantina_id: cantinaId },
      venditore,
    );
    expect(uno.body.preventivo.totaleCents).toBe(2375);
    expect(uno.body.preventivo.margineObiettivoBps).toBe(1500);
    const sei = await rpc<{ preventivo: { totaleCents: number; subtotaleCents: number } }>(
      "annunci_accessori_preventivo",
      { p_prezzo_unitario_cents: 2000, p_quantita: 6, p_cantina_id: cantinaId },
      venditore,
    );
    expect(sei.body.preventivo.subtotaleCents).toBe(12000);
    expect(sei.body.preventivo.totaleCents).toBeLessThan(6 * 2375);
    await expect(dialogo.getByTestId("riepilogo-totale")).toHaveText(euro(sei.body.preventivo.totaleCents));

    await dialogo.getByRole("button", { name: "Salva bozza" }).click();
    await dialogo.getByRole("button", { name: "Pubblica annuncio" }).click();
    await dialogo.getByRole("button", { name: "Chiudi" }).click();
    const scheda = page.getByTestId("cantina-accessorio").filter({ hasText: NOME });
    await expect(scheda.getByTestId("vendita-accessorio-stato")).toContainText("Pubblicato · 6 pezzi a 20,00 €");

    annuncioId = riga(`select id from private.annunci_accessori where cantina_accessorio_id = '${cantinaId}' and stato = 'pubblicato';`);
    expect(annuncioId).toMatch(/^[0-9a-f-]{36}$/);
    annuncioUrl = `/accessori/annunci/${annuncioId}`;
    expect(inventario(cantinaId, annuncioId)).toBe("10/6/6");
    await contesto.close();
  });

  test("17. con vendita_partner SPENTO l'annuncio non è in vetrina e non si può prenotare", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    await page.goto("/accessori/annunci");
    await attendiCaricamento(page);
    await page.waitForLoadState("networkidle");
    await expect(page.locator(`a[href="${annuncioUrl}"]`)).toHaveCount(0);
    // Aprendo direttamente il dettaglio: fail-closed, 404 (il browser lo registra in console, è l'esito atteso).
    diagnostica.ammetti(annuncioUrl);
    const diretto = await page.goto(annuncioUrl);
    expect(diretto?.status()).toBe(404);
    await expect(page.getByTestId("sezione-prenotazione")).toHaveCount(0);

    // La porta del database dice no, indipendentemente dalla UI.
    const esito = await rpc("accessori_logistica_preventivo_congela", { p_annuncio: annuncioId, p_quantita: 1 }, await accedi("altro"));
    expect(esito.ok).toBe(false);
    expect(riga(`select count(*) from private.accessori_ordini where annuncio_id = '${annuncioId}';`)).toBe("0");
    await contesto.close();
    impostaVenditaPartner(true);
  });

  test("7-8. vetrina con badge di venditore professionale e prezzo 23,75 € calcolato dal database", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    await page.goto("/accessori/annunci");
    await attendiCaricamento(page);
    const carta = page.locator(`a[href="${annuncioUrl}"]`);
    await expect(carta).toBeVisible();
    await expect(carta).toContainText(NOME);
    await expect(carta).toContainText("23,75 € a pezzo");

    await carta.click();
    await expect(page).toHaveURL(new RegExp(`${annuncioUrl}$`));
    const badge = page.getByTestId("venditore-partner");
    await expect(badge).toContainText("Venditore professionale Vinea Partner");
    await expect(page.getByTestId("venditore-privato")).toHaveCount(0);
    const corpo = await page.locator("body").innerText();
    // Il prezzo richiesto dal venditore non è pubblico (si normalizzano gli spazi: la UI usa uno spazio non separabile).
    expect(corpo.replace(/s/g, " ")).not.toContain("20,00 €");
    await info.attach("dettaglio-partner.png", { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });
    await contesto.close();
  });

  test("9-11. un secondo account prenota 3 pezzi; col pagamento simulato la vendita parziale lascia 7/3/3", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    await page.goto(annuncioUrl);
    const sezione = page.getByTestId("sezione-prenotazione");
    await expect(sezione.getByTestId("prenotazione-disponibili")).toContainText("6 pezzi disponibili");
    await sezione.getByTestId("prenotazione-quantita").fill("3");
    await sezione.getByTestId("prenotazione-prepara").click();
    await expect(sezione.getByTestId("prenotazione-riepilogo")).toBeVisible();
    expect(inventario(cantinaId, annuncioId)).toBe("10/6/6");
    await sezione.getByTestId("prenotazione-conferma").click();
    await expect(sezione.getByTestId("ordine-stato")).toHaveText("Prenotato, in attesa di pagamento");

    // Prenotazione: nessuna scorta scritta, tre pezzi impegnati.
    expect(inventario(cantinaId, annuncioId)).toBe("10/6/3");
    ordinePagato = riga(`select id from private.accessori_ordini where annuncio_id = '${annuncioId}' and stato = 'in_attesa_pagamento';`);
    const ordine = riga(`select venditore_classe::text || ' ' || margine_obiettivo_bps || ' ' || seller_id::text from private.accessori_ordini where id = '${ordinePagato}';`);
    expect(ordine).toBe(`partner 1500 ${(await accedi("venditore")).id}`);

    // Pagamento simulato dalla sola funzione privata (nessun Stripe): una sola sottrazione, tre pezzi.
    riga(`select private.accessori_ordine_segna_pagato('${ordinePagato}');`);
    expect(inventario(cantinaId, annuncioId)).toBe("7/3/3");
    expect(riga(`select stato from private.accessori_ordini where id = '${ordinePagato}';`)).toBe("pagato");
    await contesto.close();

    // Il Partner vede la scorta aggiornata (7 pezzi), e una sola riga di movimento di vendita.
    const venditore = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const pv = await venditore.newPage();
    diagnostica.osserva(pv, "partner");
    await pv.goto("/partner/accessori");
    await attendiCaricamento(pv);
    await expect(pv.getByTestId("cantina-accessorio").filter({ hasText: NOME })).toContainText("7 pezzi");
    await expect(pv.getByTestId("vendita-accessorio-stato")).toContainText("3 pezzi");
    await venditore.close();
  });

  test("13+15. Partner SOSPESO: scorte consultabili, modifica bloccata, nessuna nuova prenotazione; l'ordine già prenotato si completa", async ({
    browser,
    diagnostica,
  }, info) => {
    // Una seconda prenotazione aperta PRIMA della sospensione (1 pezzo).
    ordineAperto = await prenotaConLeStessePorte("altro", annuncioId, 1);
    expect(inventario(cantinaId, annuncioId)).toBe("7/3/2");
    expect(await decidiPartner(partnerA, "sospendi")).toBe("sospeso");

    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "partner sospeso");
    // Il rifiuto del database alla modifica è proprio ciò che il caso prova: 403 e relativo messaggio in console.
    diagnostica.ammetti("accessori_partner_scorta_salva");
    await page.goto("/partner/accessori");
    await attendiCaricamento(page);
    const scheda = page.getByTestId("cantina-accessorio").filter({ hasText: NOME });
    await expect(scheda).toBeVisible(); // consultazione consentita
    await scheda.getByRole("button", { name: "Modifica" }).click();
    const dialogo = page.getByRole("dialog");
    await dialogo.getByLabel("Quantità").fill("12");
    await dialogo.getByRole("button", { name: "Salva" }).click();
    await expect(page.getByText("solo con un Partner attivo").first()).toBeVisible();
    expect(riga(`select quantita from private.cantina_accessori where id = '${cantinaId}';`)).toBe("7");
    await contesto.close();

    // Nessuna nuova vendita: l'annuncio esce dalla vetrina e il database rifiuta il preventivo.
    const acquirente = await contestoAutenticato(browser, "adminSenzaRilascio", opzioniDelProgetto(info));
    const pa = await acquirente.newPage();
    diagnostica.osserva(pa, "acquirente 2");
    await pa.goto("/accessori/annunci");
    await attendiCaricamento(pa);
    await pa.waitForLoadState("networkidle");
    await expect(pa.locator(`a[href="${annuncioUrl}"]`)).toHaveCount(0);
    const rifiuto = await rpc("accessori_logistica_preventivo_congela", { p_annuncio: annuncioId, p_quantita: 1 }, await accedi("adminSenzaRilascio"));
    expect(rifiuto.ok).toBe(false);
    await acquirente.close();

    // Esito finanziario coerente: l'ordine già incassato resta pagato; la prenotazione aperta si completa e apre il post-vendita.
    expect(riga(`select stato from private.accessori_ordini where id = '${ordinePagato}';`)).toBe("pagato");
    // Incasso dal solo evento attendibile (la stessa porta del webhook firmato): il pagamento in ritardo non è bloccato.
    pagaConEventoFirmato(ordineAperto, (await accedi("altro")).id, "sospeso");
    expect(riga(`select stato from private.accessori_ordini where id = '${ordineAperto}';`)).toBe("pagato");
    expect(riga(`select count(*) from private.accessori_postvendita where ordine_id = '${ordineAperto}' and seller_id = (select titolare_id from private.partners where id = '${partnerA}');`)).toBe("1");
    expect(inventario(cantinaId, annuncioId)).toBe("6/2/2");
  });

  test("14. Partner REVOCATO: nessuna nuova vendita né scorta", async ({ browser, diagnostica }, info) => {
    expect(await decidiPartner(partnerA, "revoca")).toBe("revocato");
    const venditore = await accedi("venditore");
    const nuova = await rpc(
      "accessori_partner_scorta_salva",
      { p_id: randomUUID(), p_dati: { categoria_id: await idCategoriaCalici(), nome: "Nuova", quantita: 2 } },
      venditore,
    );
    expect(nuova.ok).toBe(false);
    const prenota = await rpc("accessori_logistica_preventivo_congela", { p_annuncio: annuncioId, p_quantita: 1 }, await accedi("altro"));
    expect(prenota.ok).toBe(false);

    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    await page.goto("/accessori/annunci");
    await attendiCaricamento(page);
    await page.waitForLoadState("networkidle");
    await expect(page.locator(`a[href="${annuncioUrl}"]`)).toHaveCount(0);
    await contesto.close();

    const pagina = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const p = await pagina.newPage();
    diagnostica.osserva(p, "partner revocato");
    await p.goto("/partner/accessori");
    await attendiCaricamento(p);
    await expect(p.getByRole("button", { name: "Aggiungi accessorio" })).toHaveCount(0);
    await pagina.close();
  });

  test("16. accessi non autorizzati: privato e altro Partner non leggono né modificano le scorte altrui", async () => {
    const privato = await accedi("altro");
    const altroPartner = await accedi("segnalante");
    const lista = await rpc<unknown[]>("accessori_partner_scorte_elenca", { p_archiviati: false }, privato);
    expect(lista.ok && lista.body).toEqual([]);
    const listaB = await rpc<unknown[]>("accessori_partner_scorte_elenca", { p_archiviati: false }, altroPartner);
    expect(listaB.ok && listaB.body).toEqual([]);
    const modificaPrivato = await rpc("accessori_partner_scorta_salva", { p_id: cantinaId, p_dati: { quantita: 99 } }, privato);
    const modificaB = await rpc("accessori_partner_scorta_salva", { p_id: cantinaId, p_dati: { quantita: 99 } }, altroPartner);
    const archiviaB = await rpc("accessori_partner_scorta_archivia", { p_id: cantinaId, p_archivia: true }, altroPartner);
    expect([modificaPrivato.ok, modificaB.ok, archiviaB.ok]).toEqual([false, false, false]);
    expect(riga(`select quantita || ' ' || (archiviato_at is null)::text from private.cantina_accessori where id = '${cantinaId}';`)).toBe("6 true");
    expect(partnerB).not.toBe(partnerA);
    // L'anonimo è respinto dal database (nessun privilegio sull'elenco).
    const anonimo = await rpc("accessori_partner_scorte_elenca", { p_archiviati: false });
    expect(anonimo.ok).toBe(false);
  });
});

test.describe.serial("Partner Accessori: responsive, accessibilità, cross-browser @smoke @cross", () => {
  let annuncioUrl = "";

  test.beforeAll(async () => {
    ripristinaFixture(passwordFixture());
    await accendiPubblicazione();
    creaLogisticaDiProva(PROVIDER);
    await accendiCheckout();
    await attivaPartner("venditore", "1234567890");
    impostaVenditaPartner(true);
    const venditore = await accedi("venditore");
    const cantinaId = randomUUID();
    const creato = await rpc(
      "accessori_partner_scorta_salva",
      { p_id: cantinaId, p_dati: { categoria_id: await idCategoriaCalici(), nome: "Calice Partner cross", quantita: 8 } },
      venditore,
    );
    if (!creato.ok) throw new Error(`Scorta non creata: HTTP ${creato.status}`);
    const foto = `${venditore.id}/${cantinaId}/${randomUUID()}.webp`;
    if ((await caricaFoto(venditore, foto)) >= 300) throw new Error("Foto non caricata.");
    await rpc("cantina_accessori_immagini_imposta", { p_id: cantinaId, p_percorsi: [foto] }, venditore);
    const id = randomUUID();
    const bozza = await rpc(
      "annunci_accessori_salva",
      {
        p_id: id,
        p_dati: {
          cantina_id: cantinaId, quantita: 5, prezzo_unitario_cents: 2000, condizione: "nuovo", descrizione: "Cinque calici.",
          conforme: true, peso_g: 400, lunghezza_mm: 250, larghezza_mm: 100, altezza_mm: 100, fragile: false,
        },
      },
      venditore,
    );
    if (!bozza.ok) throw new Error(`Bozza non creata: HTTP ${bozza.status}`);
    const pubblicato = await rpc("annunci_accessori_pubblica", { p_id: id }, venditore);
    if (!pubblicato.ok) throw new Error(`Annuncio non pubblicato: HTTP ${pubblicato.status}`);
    annuncioUrl = `/accessori/annunci/${id}`;
  });

  test("la pagina Partner con una scorta sta nel viewport e non ha problemi di accessibilità di base", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "partner");
    await page.goto("/partner/accessori");
    await attendiCaricamento(page);
    const scheda = page.getByTestId("cantina-accessorio").filter({ hasText: "Calice Partner cross" });
    await expect(scheda).toContainText("Scorta commerciale · nuovo");
    await expect(scheda).toContainText("8 pezzi");
    expect(await senzaScorrimentoOrizzontale(page), "scorrimento orizzontale").toBe(true);
    expect(await problemiAccessibilita(page)).toEqual([]);
    await info.attach(`partner-${info.project.name}.png`, { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });
    await contesto.close();
  });

  test("il dettaglio dell'annuncio mostra il badge professionale e la prenotazione, nel viewport", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    await page.goto(annuncioUrl);
    await attendiCaricamento(page);
    await expect(page.getByTestId("venditore-partner")).toContainText("Venditore professionale Vinea Partner");
    await expect(page.getByTestId("prenotazione-disponibili")).toContainText("5 pezzi disponibili");
    expect(await senzaScorrimentoOrizzontale(page), "scorrimento orizzontale").toBe(true);
    expect(await problemiAccessibilita(page)).toEqual([]);
    await info.attach(`dettaglio-partner-${info.project.name}.png`, { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });
    await contesto.close();
  });
});
