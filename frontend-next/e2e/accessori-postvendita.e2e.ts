import { accedi, rpc } from "./support/api";
import { contestoAutenticato, opzioniDelProgetto } from "./support/browser";
import { eseguiSql } from "./support/db";
import { pngSintetico } from "./support/immagine";
import { attendiCaricamento, problemiAccessibilita, senzaScorrimentoOrizzontale } from "./support/pagina";
import {
  apriPagamento,
  applicaEvento,
  eventoRimborso,
  invecchiaPrenotazione,
  pagaConEventoFirmato,
  simulaInvioRimborso,
  statoOrdine,
  statoPagamento,
  totaleOrdine,
} from "./support/pagamenti";
import { impostaVenditaPartner, prenotaConLeStessePorte, preparaScenarioPartner, spegniCheckout, type ScenarioPartner } from "./support/partner";

import { expect, test } from "./support/test";

/**
 * Post-vendita Accessori su un ordine PARTNER e pannello admin (VPM-015QA-FINAL-B2-COMPLETION).
 * Utenti distinti: acquirente (`altro`), Partner venditore, admin (`adminSenzaRilascio`), un estraneo.
 * Gli eventi del fornitore sono SIMULATI con la porta del webhook firmato (nessun Stripe): si prova il
 * database e l'interazione utente/amministratore nel browser, non il comportamento di Stripe.
 */

const PROVIDER = "e2e_b5a";
const euro = (cents: number): string =>
  new Intl.NumberFormat("it-IT", { style: "currency", currency: "EUR" }).format(cents / 100).replace(/\s/g, " ");
const riga = (sql: string): string => eseguiSql(sql);
const azzeraLimiti = (): void => void eseguiSql("delete from private.rate_limit_buckets;");
const PAGINA_ADMIN = "/admin/accessori-postvendita";

test.describe.serial("Post-vendita Accessori (ordine Partner) e pannello admin @smoke @cross", () => {
  let s: ScenarioPartner;
  let buyerId = "";
  let venditoreId = "";
  // Ordini dei casi
  let oPagato = "";
  let intentoPagato = "";
  let oOrfanoAnnullare = "";
  let oOrfanoIncerto = "";
  let oTardivo = "";
  let oInCorso = "";
  let oScaduto = "";

  test.beforeAll(async () => {
    s = await preparaScenarioPartner(PROVIDER, 12, 10);
    buyerId = (await accedi("altro")).id;
    venditoreId = (await accedi("venditore")).id;
  });

  test("0. preparazione dei casi: ordine pagato, intenti orfani, incasso tardivo, pagamento in corso, sessione scaduta", async () => {
    azzeraLimiti();
    oPagato = await prenotaConLeStessePorte("altro", s.annuncioId, 2);
    intentoPagato = pagaConEventoFirmato(oPagato, buyerId, "pagato");
    expect(statoOrdine(oPagato)).toBe("pagato");
    expect(statoPagamento(oPagato)).toBe("paid");

    // Orfano «da annullare»: prenotazione annullata dall'acquirente con un pagamento aperto, intento rimasto presso il fornitore.
    azzeraLimiti();
    oOrfanoAnnullare = await prenotaConLeStessePorte("altro", s.annuncioId, 1);
    riga(`select public.accessori_pagamento_apri('${oOrfanoAnnullare}', '${buyerId}');`);
    expect((await rpc("accessori_ordine_annulla", { p_id: oOrfanoAnnullare }, await accedi("altro"))).ok).toBe(true);
    riga(`select public.accessori_pagamento_orfano_gestisci('${oOrfanoAnnullare}', '${buyerId}', 'stripe', 'pi_e2e_orfano_a');`);

    // Orfano «incerto»: stesso caso, ma lo stato presso il fornitore è sconosciuto.
    azzeraLimiti();
    oOrfanoIncerto = await prenotaConLeStessePorte("altro", s.annuncioId, 1);
    riga(`select public.accessori_pagamento_apri('${oOrfanoIncerto}', '${buyerId}');`);
    expect((await rpc("accessori_ordine_annulla", { p_id: oOrfanoIncerto }, await accedi("altro"))).ok).toBe(true);
    riga(`select public.accessori_pagamento_orfano_gestisci('${oOrfanoIncerto}', '${buyerId}', 'stripe', 'pi_e2e_orfano_i');`);
    riga(`select public.accessori_pagamento_orfano_esito('${oOrfanoIncerto}', 'stripe', 'pi_e2e_orfano_i', 'sconosciuto');`);

    // Incasso tardivo: la prenotazione è scaduta e il fornitore incassa lo stesso -> rimborso dovuto.
    azzeraLimiti();
    oTardivo = await prenotaConLeStessePorte("altro", s.annuncioId, 1);
    riga(`select public.accessori_pagamento_apri('${oTardivo}', '${buyerId}');`);
    invecchiaPrenotazione(oTardivo);
    const tardivo = applicaEvento("evt_e2e_tardivo", "settled", {
      session_id: "pi_e2e_tardivo", intent_id: "pi_e2e_tardivo", provider_event_type: "payment_intent.succeeded",
      amount_cents: totaleOrdine(oTardivo), currency: "eur", order_id: oTardivo, dominio: "accessori",
    });
    expect(tardivo).toMatch(/late|processed|refund/i);
    expect(statoPagamento(oTardivo)).toBe("refund_due");

    // Pagamento in corso (autorizzato dal fornitore, non ancora incassato).
    azzeraLimiti();
    oInCorso = await prenotaConLeStessePorte("altro", s.annuncioId, 1);
    apriPagamento(oInCorso, buyerId, "pi_e2e_incorso");
    applicaEvento("evt_e2e_incorso", "authorized", {
      session_id: "pi_e2e_incorso", intent_id: "pi_e2e_incorso", provider_event_type: "payment_intent.processing",
      amount_cents: totaleOrdine(oInCorso), currency: "eur", order_id: oInCorso, dominio: "accessori",
    });
    expect(statoPagamento(oInCorso)).toBe("processing");

    // Sessione scaduta: pagamento aperto, prenotazione oltre i 15 minuti.
    azzeraLimiti();
    // Un acquirente ha una sola prenotazione aperta per annuncio: la sessione scaduta è di un secondo account.
    oScaduto = await prenotaConLeStessePorte("segnalante", s.annuncioId, 1);
    apriPagamento(oScaduto, (await accedi("segnalante")).id, "pi_e2e_scaduto");
    invecchiaPrenotazione(oScaduto);
  });

  test("1. pannello admin: anonimo, privato e Partner non lo aprono; le RPC rifiutano; l'admin reale lo vede", async ({
    browser,
    diagnostica,
  }, info) => {
    const anonimo = await browser.newContext(opzioniDelProgetto(info));
    const pa = await anonimo.newPage();
    diagnostica.osserva(pa, "anonimo");
    await pa.goto(PAGINA_ADMIN);
    await expect(pa).toHaveURL(/\/accedi/);
    await anonimo.close();

    for (const ruolo of ["altro", "venditore"] as const) {
      const contesto = await contestoAutenticato(browser, ruolo, opzioniDelProgetto(info));
      const page = await contesto.newPage();
      diagnostica.osserva(page, ruolo);
      diagnostica.ammetti("/admin/accessori-postvendita");
      const risposta = await page.goto(PAGINA_ADMIN);
      expect(risposta?.status(), `${ruolo}: stato HTTP`).toBe(404);
      await expect(page.getByRole("heading", { name: "Post-vendita Accessori" })).toHaveCount(0);
      const corpo = await page.locator("body").innerText();
      expect(corpo).not.toContain("pi_e2e_orfano");
      await contesto.close();
    }

    // Il confine è il database: nessuna delle due letture risponde a chi non è admin.
    for (const nome of ["accessori_pagamenti_intenti_orfani", "accessori_pagamenti_rimborso_dovuto"]) {
      const risposte = [
        await rpc(nome, {}),
        await rpc(nome, {}, await accedi("altro")),
        await rpc(nome, {}, await accedi("venditore")),
        await rpc(nome, {}, await accedi("segnalante")),
      ];
      expect(risposte.map((r) => r.ok), nome).toEqual([false, false, false, false]);
      const admin = await rpc<unknown[]>(nome, {}, await accedi("adminSenzaRilascio"));
      expect(admin.ok && Array.isArray(admin.body)).toBe(true);
    }

    const admin = await contestoAutenticato(browser, "adminSenzaRilascio", opzioniDelProgetto(info));
    const p = await admin.newPage();
    diagnostica.osserva(p, "admin");
    await p.goto(PAGINA_ADMIN);
    await expect(p.getByRole("heading", { level: 1, name: "Post-vendita Accessori" })).toBeVisible();
    await admin.close();
  });

  test("2. con checkout e vendita_partner SPENTI l'admin vede intenti orfani e rimborsi dovuti, e li apre nel fascicolo", async ({
    browser,
    diagnostica,
  }, info) => {
    await spegniCheckout();
    impostaVenditaPartner(false);

    const contesto = await contestoAutenticato(browser, "adminSenzaRilascio", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "admin");
    await page.goto(PAGINA_ADMIN);
    await expect(page.getByRole("heading", { level: 1, name: "Post-vendita Accessori" })).toBeVisible();

    const orfani = page.getByTestId("intenti-orfani-admin");
    await expect(orfani.getByRole("listitem")).toHaveCount(2);
    const daAnnullare = orfani.getByRole("listitem").filter({ hasText: "pi_e2e_orfano_a" });
    const incerto = orfani.getByRole("listitem").filter({ hasText: "pi_e2e_orfano_i" });
    await expect(daAnnullare).toContainText("Da annullare");
    await expect(incerto).toContainText("Incerto");
    await expect(daAnnullare).toContainText(`Ordine ${oOrfanoAnnullare}`);
    await expect(daAnnullare).toContainText(euro(totaleOrdine(oOrfanoAnnullare)));
    await expect(daAnnullare).toContainText("stripe");
    await expect(orfani).toContainText("non annulla né rimborsa");
    await expect(orfani.getByRole("button", { name: /annulla|rimborsa|riconcilia/i })).toHaveCount(0);

    const dovuti = page.getByTestId("rimborsi-dovuti-admin");
    await expect(dovuti.getByRole("listitem")).toHaveCount(1);
    await expect(dovuti).toContainText(`Ordine ${oTardivo}`);
    await expect(dovuti).toContainText(euro(totaleOrdine(oTardivo)));
    await expect(dovuti.getByRole("button", { name: /rimborsa ora|annulla|riconcilia/i })).toHaveCount(0);
    await expect(page.getByTestId("postvendita-admin")).not.toContainText("service_role");
    await expect(page.getByTestId("postvendita-admin")).not.toContainText("sk_");

    // Presa in carico: «Apri nel fascicolo» carica l'ordine nelle operazioni.
    await incerto.getByRole("button", { name: "Apri nel fascicolo" }).click();
    await expect(page.getByTestId("fascicolo-accessorio-admin")).toContainText(`Ordine ${oOrfanoIncerto}`);
    await info.attach("admin-orfani-e-dovuti.png", { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });
    await contesto.close();
  });

  test("3. pagamento in corso: l'annullo è rifiutato con un messaggio chiaro e l'ordine resta prenotato", async ({
    browser,
    diagnostica,
  }, info) => {
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    diagnostica.ammetti("accessori_ordine_annulla");
    await page.goto(`/ordini-accessori/${oInCorso}`);
    await attendiCaricamento(page);
    await page.getByTestId("prenotazione-annulla").click();
    await expect(page.getByText("Il pagamento è in corso: attendi l'esito prima di annullare.")).toBeVisible();
    expect(statoOrdine(oInCorso)).toBe("in_attesa_pagamento");
    expect(statoPagamento(oInCorso)).toBe("processing");
    await contesto.close();
  });

  test("4. sessione scaduta: l'ordine risulta scaduto, non si può pagare né annullare, e i pezzi sono tornati disponibili", async ({
    browser,
    diagnostica,
  }, info) => {
    const contesto = await contestoAutenticato(browser, "segnalante", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente 2");
    await page.goto(`/ordini-accessori/${oScaduto}`);
    await attendiCaricamento(page);
    await expect(page.getByTestId("ordine-stato")).toHaveText("Scaduto");
    await expect(page.getByTestId("ordine-chiusura")).toContainText("tornati disponibili");
    await expect(page.getByTestId("pagamento-paga")).toHaveCount(0);
    await expect(page.getByTestId("prenotazione-annulla")).toHaveCount(0);
    expect(statoOrdine(oScaduto)).toBe("scaduto");
    await contesto.close();
  });

  test("5. l'admin registra la consegna a mano; l'acquirente vede la consegna e può contestare entro 48 ore", async ({
    browser,
    diagnostica,
  }, info) => {
    const admin = await contestoAutenticato(browser, "adminSenzaRilascio", opzioniDelProgetto(info));
    const pa = await admin.newPage();
    diagnostica.osserva(pa, "admin");
    await pa.goto(PAGINA_ADMIN);
    await pa.getByLabel("Identificativo dell'ordine").fill(oPagato);
    await pa.getByRole("button", { name: "Carica / riprova fascicolo" }).click();
    await expect(pa.getByTestId("fascicolo-accessorio-admin")).toContainText(`Ordine ${oPagato}`);
    await pa.getByLabel("Nota o riferimento").fill("Consegna verificata dal supporto (prova E2E)");
    await pa.getByRole("button", { name: "Registra consegna (manuale)" }).click();
    await expect(pa.getByText("Operazione registrata.")).toBeVisible();
    await admin.close();
    expect(riga(`select consegna_fonte from private.accessori_postvendita where ordine_id = '${oPagato}';`)).toMatch(/manuale/);

    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    await page.goto(`/ordini-accessori/${oPagato}`);
    await attendiCaricamento(page);
    await expect(page.getByTestId("postvendita-consegna")).toContainText("registrata dal supporto Vinea, senza conferma del vettore");
    await expect(page.getByTestId("postvendita-apri")).toBeVisible();
    await contesto.close();
  });

  test("6. l'acquirente apre la contestazione con una fotografia privata", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    await page.goto(`/ordini-accessori/${oPagato}`);
    await attendiCaricamento(page);
    const modulo = page.getByTestId("postvendita-apri");
    await modulo.getByLabel("Descrivi il problema").fill("Un calice è arrivato rotto (prova E2E).");
    await modulo.getByLabel("Fotografie (fino a 8)").setInputFiles({ name: "rotto.png", mimeType: "image/png", buffer: pngSintetico() });
    await modulo.getByRole("button", { name: "Apri la contestazione" }).click();
    await expect(page.getByText("Contestazione · attesa venditore")).toBeVisible();

    const r = riga(`select stato || ' ' || coalesce(array_length(foto, 1), 0) from private.accessori_contestazioni where ordine_id = '${oPagato}';`);
    expect(r).toMatch(/^(aperta|in_valutazione) 1$/);
    const percorso = riga(`select foto[1] from private.accessori_contestazioni where ordine_id = '${oPagato}';`);
    // Prova privata: percorso `<ordine>/<utente>/<file>` nel bucket privato; un estraneo non legge il fascicolo (la RPC lo rifiuta).
    expect(percorso.startsWith(`${oPagato}/${buyerId}/`)).toBe(true);
    const firmaEstraneo = await rpc("accessori_postvendita_leggi", { p_ordine: oPagato }, await accedi("segnalante"));
    expect(firmaEstraneo.ok).toBe(false);
    await contesto.close();
  });

  test("7. il Partner risponde alla contestazione dal browser", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "partner");
    await page.goto(`/ordini-accessori/${oPagato}`);
    await attendiCaricamento(page);
    await expect(page.getByText("Un calice è arrivato rotto (prova E2E).")).toBeVisible();
    await expect(page.getByTestId("postvendita-apri")).toHaveCount(0); // il venditore non apre contestazioni
    await page.getByLabel("Posizione").selectOption({ label: "Propongo una soluzione" });
    await page.getByLabel("Spiegazione o soluzione proposta").fill("Rimborso parziale concordato (prova E2E).");
    await page.getByRole("button", { name: "Invia risposta" }).click();
    await expect(page.getByText("Risposta del venditore")).toBeVisible();
    await expect(page.getByTestId("postvendita-ricavo")).toContainText("Trattenuto da Vinea");
    await contesto.close();
    expect(riga(`select (venditore_risposta_at is not null)::text from private.accessori_contestazioni where ordine_id = '${oPagato}';`)).toBe("true");
  });

  test("8. l'admin decide un rimborso parziale: richiesto, non ancora eseguito, nessun accredito al venditore", async ({
    browser,
    diagnostica,
  }, info) => {
    const admin = await contestoAutenticato(browser, "adminSenzaRilascio", opzioniDelProgetto(info));
    const page = await admin.newPage();
    diagnostica.osserva(page, "admin");
    await page.goto(PAGINA_ADMIN);
    const contestazione = page.getByRole("listitem").filter({ hasText: `ordine ${oPagato}` });
    await expect(contestazione).toContainText("pronta per la decisione");
    await contestazione.getByRole("button", { name: "Seleziona" }).click();
    const fascicolo = page.getByTestId("fascicolo-accessorio-admin");
    await expect(fascicolo).toContainText(`Ordine ${oPagato}`);
    await expect(fascicolo).toContainText("Un calice è arrivato rotto (prova E2E).");
    // La prova privata dell'acquirente si vede davvero (URL firmato e temporaneo, non un'immagine rotta).
    const prova = fascicolo.getByAltText("Prove dell'acquirente 1");
    await expect(prova).toBeVisible();
    await expect.poll(() => prova.evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth > 0)).toBe(true);
    await page.getByLabel("Importo da rimborsare (euro, solo per «rimborsata»)").fill("20,00");
    await page.getByLabel("Nota o riferimento").fill("Rimborso di un calice (prova E2E).");
    await page.getByRole("button", { name: "Decidi: rimborsata" }).click();
    await expect(page.getByText("Operazione registrata.")).toBeVisible();
    await info.attach("admin-decisione.png", { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });
    await admin.close();

    // Rimborso richiesto, non eseguito: pagamento ancora «paid», una sola richiesta, importo deciso dal database.
    const rimborsi = riga(`select count(*) || ' ' || sum(importo_cents) || ' ' || min(stato) || ' ' || min(origine)
      from private.accessori_rimborsi where ordine_id = '${oPagato}';`);
    expect(rimborsi).toMatch(/^1 2000 (richiesto|in_invio) contestazione$/);
    expect(statoPagamento(oPagato)).toBe("paid");

    // Il ricavo del venditore NON è rilasciato né accreditato.
    const leggi = await rpc<{ ricavo: { stato: string } | null }>("accessori_postvendita_leggi", { p_ordine: oPagato }, await accedi("venditore"));
    expect(leggi.ok).toBe(true);
    expect(leggi.ok && leggi.body.ricavo?.stato).toMatch(/^(trattenuto|stornato)$/); // mai «rilasciato»
  });

  test("9. stato finale solo dall'evento firmato: parziale, duplicato e ritentativo non raddoppiano il rimborso", async ({
    browser,
    diagnostica,
  }, info) => {
    const rimborsoId = riga(`select id from private.accessori_rimborsi where ordine_id = '${oPagato}';`);
    const rimborso = { id: "re_e2e_1", rimborsoId, cents: 2000 };
    // Provider finto: la richiesta è accettata dal fornitore, ma NON ancora eseguita (serve l'evento firmato).
    simulaInvioRimborso(rimborsoId, "re_e2e_1");
    expect(statoPagamento(oPagato)).toBe("paid");

    // Prima dell'evento il browser non mostra «rimborsato».
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    await page.goto(`/ordini-accessori/${oPagato}`);
    await attendiCaricamento(page);
    await expect(page.getByTestId("postvendita-rimborso")).not.toContainText("Rimborsato: 20,00");

    expect(eventoRimborso(oPagato, intentoPagato, "evt_e2e_r1", 2000, false, rimborso)).toBe("processed");
    expect(statoPagamento(oPagato)).toBe("partially_refunded");
    // Stesso evento riconsegnato dal fornitore, e un ritentativo con un altro id ma lo stesso cumulato.
    expect(eventoRimborso(oPagato, intentoPagato, "evt_e2e_r1", 2000, false, rimborso)).toBe("duplicate");
    eventoRimborso(oPagato, intentoPagato, "evt_e2e_r1b", 2000, false, rimborso);
    expect(statoPagamento(oPagato)).toBe("partially_refunded");
    expect(riga(`select count(*) || ' ' || sum(importo_cents) from private.accessori_rimborsi where ordine_id = '${oPagato}';`)).toBe("1 2000");
    expect(riga(`select amount_refunded_cents from private.accessori_pagamenti where ordine_id = '${oPagato}';`)).toBe("2000");

    await page.reload();
    await attendiCaricamento(page);
    await expect(page.getByTestId("postvendita-rimborso")).toContainText("Rimborsato: 20,00");
    await contesto.close();

    // Dal lato del venditore: ancora nessun rilascio del ricavo, e lo stornato è quello dell'evento.
    const v = await rpc<{ ricavo: { stato: string; stornatoCents: number } | null }>("accessori_postvendita_leggi", { p_ordine: oPagato }, await accedi("venditore"));
    expect(v.ok).toBe(true);
    expect(v.ok && v.body.ricavo?.stato).toMatch(/^(trattenuto|stornato)$/); // mai «rilasciato»
    expect(riga(`select seller_id::text from private.accessori_ordini where id = '${oPagato}';`)).toBe(venditoreId);
  });

  test("10. rimborso dovuto (incasso tardivo): resta in coda finché non arriva charge.refunded firmato; poi esce dal pannello", async ({
    browser,
    diagnostica,
  }, info) => {
    const totale = totaleOrdine(oTardivo);
    const automatico = riga(`select count(*) || ' ' || sum(importo_cents) || ' ' || min(origine) from private.accessori_rimborsi where ordine_id = '${oTardivo}';`);
    expect(automatico).toBe(`1 ${totale} dovuto_automatico`);

    const admin = await contestoAutenticato(browser, "adminSenzaRilascio", opzioniDelProgetto(info));
    const page = await admin.newPage();
    diagnostica.osserva(page, "admin");
    await page.goto(PAGINA_ADMIN);
    await expect(page.getByTestId("rimborsi-dovuti-admin")).toContainText(`Ordine ${oTardivo}`);
    await expect(page.getByRole("listitem").filter({ hasText: `Ordine ${oTardivo}` }).first()).toBeVisible();

    const rimborsoId = riga(`select id from private.accessori_rimborsi where ordine_id = '${oTardivo}';`);
    simulaInvioRimborso(rimborsoId, "re_e2e_t");
    expect(statoPagamento(oTardivo)).toBe("refund_due"); // accettato dal fornitore, non ancora eseguito
    expect(eventoRimborso(oTardivo, "pi_e2e_tardivo", "evt_e2e_rt", totale, true, { id: "re_e2e_t", rimborsoId, cents: totale })).toBe("processed");
    expect(statoPagamento(oTardivo)).toBe("refunded");
    // Doppio evento: nessun secondo rimborso.
    expect(eventoRimborso(oTardivo, "pi_e2e_tardivo", "evt_e2e_rt", totale, true, { id: "re_e2e_t", rimborsoId, cents: totale })).toBe("duplicate");
    expect(riga(`select count(*) from private.accessori_rimborsi where ordine_id = '${oTardivo}';`)).toBe("1");

    await page.reload();
    await expect(page.getByTestId("rimborsi-dovuti-admin")).toContainText("Nessuno."); // sezione caricata e vuota
    await expect(page.getByTestId("rimborsi-dovuti-admin")).not.toContainText(`Ordine ${oTardivo}`);
    await admin.close();
    expect(statoOrdine(oTardivo)).not.toBe("pagato"); // nessuna vendita applicata dall'incasso tardivo
  });
});

test.describe.serial("Pannello admin Accessori: responsive e accessibilità @smoke @cross", () => {
  let oOrfano = "";

  test.beforeAll(async () => {
    const s = await preparaScenarioPartner(PROVIDER, 6, 4);
    const buyerId = (await accedi("altro")).id;
    oOrfano = await prenotaConLeStessePorte("altro", s.annuncioId, 1);
    riga(`select public.accessori_pagamento_apri('${oOrfano}', '${buyerId}');`);
    expect((await rpc("accessori_ordine_annulla", { p_id: oOrfano }, await accedi("altro"))).ok).toBe(true);
    riga(`select public.accessori_pagamento_orfano_gestisci('${oOrfano}', '${buyerId}', 'stripe', 'pi_e2e_cross_orfano');`);
  });

  test("la sezione degli intenti orfani sta nel viewport e non ha problemi di accessibilità di base", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "adminSenzaRilascio", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "admin");
    await page.goto(PAGINA_ADMIN);
    await expect(page.getByTestId("intenti-orfani-admin")).toContainText("pi_e2e_cross_orfano");
    expect(await senzaScorrimentoOrizzontale(page), "scorrimento orizzontale").toBe(true);
    expect(await problemiAccessibilita(page)).toEqual([]);
    await info.attach(`admin-${info.project.name}.png`, { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });
    await contesto.close();
  });
});
