import { randomUUID } from "node:crypto";
import type { Page } from "@playwright/test";
import { accedi, accendiPubblicazione, caricaFoto, idCategoriaCalici, passwordFixture, rpc } from "./support/api";
import { contestoAutenticato, opzioniDelProgetto } from "./support/browser";
import { eseguiSql, ripristinaFixture } from "./support/db";
import { attendiCaricamento, problemiAccessibilita, senzaScorrimentoOrizzontale } from "./support/pagina";
import { expect, test } from "./support/test";

/**
 * Checkout Accessori (VPM-015B5A) su stack isolato, con utenti distinti:
 * 6 calici in Cantina, 4 in annuncio, 2 prenotati e poi "pagati" con la sola
 * funzione privata simulata (nessun pagamento reale, nessun Stripe).
 * Verifica la UI contro il database: inventario, importi congelati, retry,
 * doppio click, annullamento, scadenza, accessi e fail-closed.
 */

const NOME = "Calice E2E prenotazione";
const PROVIDER = "e2e_b5a";
const RICHIESTE_DI_PAGAMENTO = /payments-checkout|stripe|checkout\.stripe/i;

const euro = (cents: number): string =>
  new Intl.NumberFormat("it-IT", { style: "currency", currency: "EUR" }).format(cents / 100).replace(/\s/g, " ");

/** Servizio e tariffa di PROVA (valori inventati, non tariffe) per il solo stack isolato. */
const creaLogisticaDiProva = (): void => {
  eseguiSql(`
do $f$
declare
  v_t timestamptz := now() - interval '1 hour';
  v_srv uuid;
  v_rete uuid;
begin
  insert into private.logistics_service_definitions (
    provider_code, service_code, service_level, max_weight_g, max_length_mm, max_width_mm,
    max_height_mm, max_volume_cm3, eligible_packaging_formats, operational_eligibility, active, effective_from
  ) values ('${PROVIDER}', 'standard', 'standard', 20000, 600, 400, 400, 90000, '{}', true, true, v_t)
  returning id into v_srv;
  insert into private.logistics_service_capabilities (service_definition_id, capability) values (v_srv, 'PUDO_TO_PUDO');
  insert into private.logistics_pudo_networks (provider_code, network_code, label, active, effective_from)
  values ('${PROVIDER}', 'e2e_b5a_rete', 'Rete di prova E2E B5A', true, v_t) returning id into v_rete;
  insert into private.logistics_service_pudo_networks (service_definition_id, network_id, endpoint_role)
  values (v_srv, v_rete, 'both');
  insert into private.accessori_logistica_tariffe (
    provider_code, service_code, capability, classe_codice, peso_max_g, lunghezza_max_mm,
    larghezza_max_mm, altezza_max_mm, fragile_ammesso, prezzo_cents, fonte, stato, effective_from)
  values ('${PROVIDER}', 'standard', 'PUDO_TO_PUDO', 'm', 8000, 450, 300, 300, true, 790,
          'Prova E2E B5A (non una tariffa)', 'active', v_t);
end
$f$;`);
};

interface Scenario {
  annuncioId: string;
  cantinaId: string;
  url: string;
}

/** 6 calici in Cantina, 4 in annuncio a 20,00 €, logistica di prova e checkout accesi. */
const preparaScenario = async (): Promise<Scenario> => {
  ripristinaFixture(passwordFixture());
  await accendiPubblicazione();
  creaLogisticaDiProva();

  const rilascio = await accedi("rilascio");
  const motivo = "prova browser E2E";
  const logistica = await rpc("accessori_logistica_admin_imposta", { p_attiva: true, p_motivo: motivo }, rilascio);
  const checkout = await rpc("accessori_checkout_admin_imposta", { p_attivo: true, p_motivo: motivo }, rilascio);
  if (!logistica.ok || !checkout.ok) throw new Error(`Interruttori non accesi: ${logistica.status}/${checkout.status}`);

  const venditore = await accedi("venditore");
  const categoriaId = await idCategoriaCalici();
  const cantinaId = randomUUID();
  const creato = await rpc(
    "cantina_accessori_salva",
    { p_id: cantinaId, p_dati: { categoria_id: categoriaId, nome: NOME, quantita: 6, note: "NOTA-PRIVATA-E2E", condizione: "usato" } },
    venditore,
  );
  if (!creato.ok) throw new Error(`Accessorio non creato: HTTP ${creato.status}`);
  const percorsoFoto = `${venditore.id}/${cantinaId}/${randomUUID()}.webp`;
  if ((await caricaFoto(venditore, percorsoFoto)) >= 300) throw new Error("Foto non caricata.");
  const foto = await rpc("cantina_accessori_immagini_imposta", { p_id: cantinaId, p_percorsi: [percorsoFoto] }, venditore);
  if (!foto.ok) throw new Error(`Foto non collegata: HTTP ${foto.status}`);

  const annuncioId = randomUUID();
  const bozza = await rpc(
    "annunci_accessori_salva",
    {
      p_id: annuncioId,
      p_dati: {
        cantina_id: cantinaId,
        quantita: 4,
        prezzo_unitario_cents: 2000,
        condizione: "come_nuovo",
        descrizione: "Quattro calici da rosso.",
        conforme: true,
        peso_g: 400,
        lunghezza_mm: 250,
        larghezza_mm: 100,
        altezza_mm: 100,
        fragile: false,
      },
    },
    venditore,
  );
  if (!bozza.ok) throw new Error(`Bozza non creata: HTTP ${bozza.status}`);
  const pubblicato = await rpc("annunci_accessori_pubblica", { p_id: annuncioId }, venditore);
  if (!pubblicato.ok) throw new Error(`Annuncio non pubblicato: HTTP ${pubblicato.status}`);
  return { annuncioId, cantinaId, url: `/accessori/annunci/${annuncioId}` };
};

/** "cantina/annuncio/disponibili" dal database, la verità contro cui si confronta la UI. */
const inventario = (s: Scenario): string =>
  eseguiSql(`select (select quantita from private.cantina_accessori where id = '${s.cantinaId}') || '/'
    || (select quantita from private.annunci_accessori where id = '${s.annuncioId}') || '/'
    || private.accessori_disponibili('${s.annuncioId}');`);

const ordiniDi = (email: string, annuncioId: string): string[] =>
  eseguiSql(`select o.id || ' ' || o.stato || ' ' || o.quantita || ' ' || o.totale_acquirente_cents
    from private.accessori_ordini o join auth.users u on u.id = o.buyer_id
    where u.email = '${email}' and o.annuncio_id = '${annuncioId}' order by o.creato_at;`)
    .split(/\r?\n/)
    .filter(Boolean);

const totaleUltimoPreventivo = (email: string, annuncioId: string): number =>
  Number(
    eseguiSql(`select q.addebito_totale_cents from private.accessori_logistica_preventivi q
      join auth.users u on u.id = q.buyer_id where u.email = '${email}' and q.annuncio_id = '${annuncioId}'
      order by q.creato_at desc limit 1;`),
  );

const EMAIL_ALTRO = "u03@e2e-12zk.test";
const EMAIL_SEGNALANTE = "u04@e2e-12zk.test";

test.describe.serial("Accessori: prenotazione 2 su 6, retry, doppio click, scadenza e fail-closed @smoke", () => {
  const richiestePagamento: string[] = [];
  let s: Scenario;
  let ordineAltro = "";

  const osserva = (page: Page) =>
    page.on("request", (r) => {
      if (RICHIESTE_DI_PAGAMENTO.test(r.url())) richiestePagamento.push(r.url());
    });

  test.beforeAll(async () => {
    s = await preparaScenario();
  });

  test("1. esempio obbligatorio: 6 in Cantina, 4 in annuncio, 2 prenotati -> 6/4/2, nessuna sottrazione anticipata", async ({
    browser,
    diagnostica,
  }, info) => {
    expect(inventario(s)).toBe("6/4/4");
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    osserva(page);

    await page.goto(s.url);
    const sezione = page.getByTestId("sezione-prenotazione");
    await expect(sezione).toBeVisible();
    await expect(sezione.getByTestId("prenotazione-disponibili")).toContainText("4 pezzi disponibili");
    await sezione.getByTestId("prenotazione-quantita").fill("2");
    await sezione.getByTestId("prenotazione-prepara").click();

    const riepilogo = sezione.getByTestId("prenotazione-riepilogo");
    await expect(riepilogo).toBeVisible();
    // Il totale mostrato è quello CONGELATO dal database, non un calcolo del browser.
    const totaleDb = totaleUltimoPreventivo(EMAIL_ALTRO, s.annuncioId);
    expect(totaleDb).toBeGreaterThan(4000);
    await expect(riepilogo.getByTestId("stima-logistica-totale")).toHaveText(euro(totaleDb));
    await expect(riepilogo).toContainText("2 pezzi × 20,00 €");
    await expect(riepilogo).toContainText("Spedizione (2 colli)");
    // Il riepilogo non prenota: l'inventario è ancora intatto.
    expect(inventario(s)).toBe("6/4/4");
    expect(ordiniDi(EMAIL_ALTRO, s.annuncioId)).toHaveLength(0);
    await info.attach("riepilogo-prenotazione.png", { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });

    await sezione.getByTestId("prenotazione-conferma").click();
    const ordine = sezione.getByTestId("ordine-accessorio");
    await expect(ordine).toBeVisible();
    await expect(ordine.getByTestId("ordine-stato")).toHaveText("Prenotato, in attesa di pagamento");
    await expect(ordine.getByTestId("ordine-totale")).toHaveText(euro(totaleDb));
    await expect(ordine.getByTestId("ordine-scadenza")).toContainText("Nessun addebito");

    // Prenotazione: nessuna quantità scritta, disponibili 2. Un solo ordine, nessun ordine del vino.
    expect(inventario(s)).toBe("6/4/2");
    const righe = ordiniDi(EMAIL_ALTRO, s.annuncioId);
    expect(righe).toHaveLength(1);
    ordineAltro = righe[0].split(" ")[0];
    expect(righe[0]).toContain(`in_attesa_pagamento 2 ${totaleDb}`);
    expect(eseguiSql("select (select count(*) from public.orders) || '/' || (select count(*) from public.payments);")).toBe("0/0");
    await info.attach("prenotazione-confermata.png", { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });
    await contesto.close();
  });

  test("2. pagamento SIMULATO: 6/4/2 -> 4/2/2, una sola sottrazione; il venditore vede la vendita", async ({
    browser,
    diagnostica,
  }, info) => {
    eseguiSql(`select private.accessori_ordine_segna_pagato('${ordineAltro}');`);
    // Ripetere il pagamento non sottrae due volte.
    eseguiSql(`select private.accessori_ordine_segna_pagato('${ordineAltro}');`);
    expect(inventario(s)).toBe("4/2/2");

    const acquirente = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const pa = await acquirente.newPage();
    diagnostica.osserva(pa, "acquirente");
    await pa.goto(`/ordini-accessori/${ordineAltro}`);
    await expect(pa.getByTestId("ordine-stato")).toHaveText("Pagato (simulato)");
    await expect(pa.getByTestId("prenotazione-annulla")).toHaveCount(0);
    await acquirente.close();

    const venditore = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const pv = await venditore.newPage();
    diagnostica.osserva(pv, "venditore");
    await pv.goto("/ordini-accessori");
    const vendite = pv.getByRole("region", { name: "Le tue vendite" });
    await expect(vendite.getByTestId("ordine-riga")).toHaveCount(1);
    await expect(vendite).toContainText("Pagato (simulato)");
    await expect(vendite).toContainText("incassi 40,00");
    await pv.getByRole("link", { name: /Calice E2E prenotazione/ }).click();
    await expect(pv.getByTestId("ordine-ricevi")).toHaveText(euro(4000));
    await expect(pv.getByTestId("ordine-totale")).toHaveCount(0);
    await info.attach("vendita-del-venditore.png", { body: await pv.screenshot({ fullPage: true }), contentType: "image/png" });
    await venditore.close();
  });

  test("3. doppio click sulla conferma: un solo ordine, inventario 4/2/1", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "segnalante", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente 2");
    osserva(page);
    await page.goto(s.url);
    const sezione = page.getByTestId("sezione-prenotazione");
    await expect(sezione.getByTestId("prenotazione-disponibili")).toContainText("2 pezzi disponibili");
    await sezione.getByTestId("prenotazione-prepara").click();
    await expect(sezione.getByTestId("prenotazione-riepilogo")).toBeVisible();
    await sezione.getByTestId("prenotazione-conferma").dblclick();
    await expect(sezione.getByTestId("ordine-stato")).toHaveText("Prenotato, in attesa di pagamento");

    expect(ordiniDi(EMAIL_SEGNALANTE, s.annuncioId)).toHaveLength(1);
    expect(inventario(s)).toBe("4/2/1");
    await contesto.close();
  });

  test("4. annullamento: i pezzi tornano disponibili senza scrivere quantità (4/2/2); retry idempotente", async ({
    browser,
    diagnostica,
  }, info) => {
    const contesto = await contestoAutenticato(browser, "segnalante", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente 2");
    await page.goto("/ordini-accessori");
    const acquisti = page.getByRole("region", { name: "I tuoi acquisti" });
    await expect(acquisti.getByTestId("ordine-riga")).toHaveCount(1);
    await acquisti.getByTestId("ordine-riga").getByRole("link").click();
    await page.getByTestId("prenotazione-annulla").click();
    await expect(page.getByTestId("ordine-stato")).toHaveText("Annullato");
    await expect(page.getByTestId("ordine-chiusura")).toContainText("Hai annullato la prenotazione");
    expect(inventario(s)).toBe("4/2/2");
    expect(ordiniDi(EMAIL_SEGNALANTE, s.annuncioId)[0]).toContain("annullato");

    // Retry della stessa richiesta dal database: stessa chiave e stesso preventivo -> stesso ordine.
    const sessione = await accedi("segnalante");
    const congelato = await rpc<{ preventivoId: string }>(
      "accessori_logistica_preventivo_congela",
      { p_annuncio: s.annuncioId, p_quantita: 1 },
      sessione,
    );
    const chiave = `e2e-retry-${randomUUID()}`;
    const primo = await rpc<{ id: string }>("accessori_checkout_crea", { p_preventivo_id: congelato.body.preventivoId, p_chiave: chiave }, sessione);
    const secondo = await rpc<{ id: string }>("accessori_checkout_crea", { p_preventivo_id: congelato.body.preventivoId, p_chiave: chiave }, sessione);
    const terzo = await rpc<{ id: string }>(
      "accessori_checkout_crea",
      { p_preventivo_id: congelato.body.preventivoId, p_chiave: `e2e-altra-${randomUUID()}` },
      sessione,
    );
    expect(primo.ok && secondo.ok && terzo.ok).toBe(true);
    expect(secondo.body.id).toBe(primo.body.id);
    expect(terzo.body.id).toBe(primo.body.id);
    expect(ordiniDi(EMAIL_SEGNALANTE, s.annuncioId).filter((r) => r.includes("in_attesa_pagamento"))).toHaveLength(1);
    expect(inventario(s)).toBe("4/2/1");
    await contesto.close();
  });

  test("5. prenotazione scaduta: i pezzi tornano disponibili (4/2/2) e la UI la mostra scaduta", async ({ browser, diagnostica }, info) => {
    eseguiSql(`
      alter table private.accessori_ordini disable trigger accessori_ordini_guard;
      update private.accessori_ordini set creato_at = now() - interval '30 minutes', scade_at = now() - interval '15 minutes'
       where stato = 'in_attesa_pagamento';
      alter table private.accessori_ordini enable trigger accessori_ordini_guard;`);
    expect(inventario(s)).toBe("4/2/2");

    const contesto = await contestoAutenticato(browser, "segnalante", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente 2");
    await page.goto("/ordini-accessori");
    const acquisti = page.getByRole("region", { name: "I tuoi acquisti" });
    await expect(acquisti).toContainText("Scaduto");
    await acquisti.getByTestId("ordine-riga").filter({ hasText: "Scaduto" }).getByRole("link").click();
    await expect(page.getByTestId("ordine-stato")).toHaveText("Scaduto");
    await expect(page.getByTestId("ordine-chiusura")).toContainText("tornati disponibili");
    await expect(page.getByTestId("prenotazione-annulla")).toHaveCount(0);

    // Una prenotazione scaduta non blocca chi la possedeva: può riprenotare.
    await page.goto(s.url);
    const sezione = page.getByTestId("sezione-prenotazione");
    await expect(sezione.getByTestId("prenotazione-disponibili")).toContainText("2 pezzi disponibili");
    await sezione.getByTestId("prenotazione-prepara").click();
    await sezione.getByTestId("prenotazione-conferma").click();
    await expect(sezione.getByTestId("ordine-stato")).toHaveText("Prenotato, in attesa di pagamento");
    await sezione.getByTestId("prenotazione-annulla").click();
    await expect(sezione.getByTestId("ordine-stato")).toHaveText("Annullato");
    expect(inventario(s)).toBe("4/2/2");
    await contesto.close();
  });

  test("6. il proprio annuncio non si prenota; un estraneo non vede l'ordine (404); l'anonimo è invitato ad accedere", async ({
    browser,
    diagnostica,
  }, info) => {
    diagnostica.ammetti("status of 404");
    // Il preventivo per il proprio annuncio è rifiutato (403) e il servizio lo registra: esito atteso.
    diagnostica.ammetti("status of 403");
    diagnostica.ammetti("hint: proprio_annuncio");
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    await page.goto(s.url);
    const sezione = page.getByTestId("sezione-prenotazione");
    await sezione.getByTestId("prenotazione-prepara").click();
    await expect(sezione.getByTestId("prenotazione-errore")).toContainText("Non puoi chiedere un preventivo per il tuo annuncio");
    await contesto.close();

    const estraneo = await contestoAutenticato(browser, "adminSenzaRilascio", opzioniDelProgetto(info));
    const pe = await estraneo.newPage();
    diagnostica.osserva(pe, "estraneo");
    const risposta = await pe.goto(`/ordini-accessori/${ordineAltro}`);
    expect(risposta?.status()).toBe(404);
    await estraneo.close();

    const anonimo = await browser.newContext(opzioniDelProgetto(info));
    const pn = await anonimo.newPage();
    diagnostica.osserva(pn, "anonimo");
    await pn.goto(s.url);
    await expect(pn.getByRole("link", { name: "Accedi per prenotare" })).toBeVisible();
    await expect(pn.getByTestId("prenotazione-prepara")).toHaveCount(0);
    const dalLogin = await pn.goto("/ordini-accessori");
    expect(dalLogin?.url()).toContain("/accedi");
    await anonimo.close();
  });

  test("7. checkout spento: nessun comando di prenotazione e il database rifiuta (fail-closed); nessun pagamento reale", async ({
    browser,
    diagnostica,
  }, info) => {
    const admin = await accedi("adminSenzaRilascio");
    const spento = await rpc("accessori_checkout_admin_imposta", { p_attivo: false, p_motivo: "prova browser E2E" }, admin);
    expect(spento.ok).toBe(true);

    // Un preventivo valido congelato prima non basta a creare un ordine.
    const sessione = await accedi("altro");
    const congelato = await rpc<{ preventivoId: string }>(
      "accessori_logistica_preventivo_congela",
      { p_annuncio: s.annuncioId, p_quantita: 1 },
      sessione,
    );
    expect(congelato.ok && Boolean(congelato.body.preventivoId)).toBe(true);
    const ordini = await rpc(
      "accessori_checkout_crea",
      { p_preventivo_id: congelato.body.preventivoId, p_chiave: `e2e-spento-${randomUUID()}` },
      sessione,
    );
    expect(ordini.ok).toBe(false);
    expect(JSON.stringify(ordini.body)).toContain("checkout_non_attivo");
    expect(ordiniDi(EMAIL_ALTRO, s.annuncioId)).toHaveLength(1);

    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    osserva(page);
    await page.goto(s.url);
    await expect(page.getByTestId("prenotazione-chiusa")).toContainText("Gli acquisti non sono ancora disponibili.");
    await expect(page.getByTestId("prenotazione-prepara")).toHaveCount(0);
    await expect(page.getByTestId("prenotazione-conferma")).toHaveCount(0);
    await contesto.close();

    // Nessuna chiamata a Stripe o alla funzione dei pagamenti in tutta la prova.
    expect(richiestePagamento).toEqual([]);
    expect(eseguiSql("select (select count(*) from public.orders) || '/' || (select count(*) from public.payments);")).toBe("0/0");
    expect(inventario(s)).toBe("4/2/2");
  });
});

test.describe.serial("Prenotazione Accessori: responsive, accessibilità, cross-browser @smoke @cross", () => {
  let s: Scenario;
  let ordine = "";

  test.beforeAll(async () => {
    s = await preparaScenario();
    const sessione = await accedi("altro");
    const congelato = await rpc<{ preventivoId: string }>(
      "accessori_logistica_preventivo_congela",
      { p_annuncio: s.annuncioId, p_quantita: 2 },
      sessione,
    );
    const creato = await rpc<{ id: string }>(
      "accessori_checkout_crea",
      { p_preventivo_id: congelato.body.preventivoId, p_chiave: `e2e-cross-${randomUUID()}` },
      sessione,
    );
    if (!creato.ok) throw new Error(`Ordine di scenario non creato: HTTP ${creato.status}`);
    ordine = creato.body.id;
  });

  test("la scheda con prenotazione sta nel viewport e non ha problemi di accessibilità di base", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "segnalante", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente 2");
    await page.goto(s.url);
    await attendiCaricamento(page);
    const sezione = page.getByTestId("sezione-prenotazione");
    await expect(sezione.getByTestId("prenotazione-disponibili")).toContainText("2 pezzi disponibili");
    await sezione.getByTestId("prenotazione-prepara").click();
    await expect(sezione.getByTestId("prenotazione-riepilogo")).toBeVisible();
    await expect(sezione.getByTestId("prenotazione-conferma")).toBeVisible();
    expect(await senzaScorrimentoOrizzontale(page), "scorrimento orizzontale").toBe(true);
    expect(await problemiAccessibilita(page)).toEqual([]);
    await info.attach(`prenotazione-${info.project.name}.png`, { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });
    await contesto.close();
  });

  test("la pagina dell'ordine mostra tutte le voci e l'annullamento, nel viewport", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    await page.goto(`/ordini-accessori/${ordine}`);
    await attendiCaricamento(page);
    await expect(page.getByTestId("ordine-stato")).toHaveText("Prenotato, in attesa di pagamento");
    await expect(page.getByTestId("ordine-accessorio")).toContainText("Commissione Vinea");
    await expect(page.getByTestId("ordine-accessorio")).toContainText("Costo di pagamento sulla spedizione");
    await expect(page.getByTestId("prenotazione-annulla")).toBeVisible();
    expect(await senzaScorrimentoOrizzontale(page), "scorrimento orizzontale").toBe(true);
    expect(await problemiAccessibilita(page)).toEqual([]);
    await info.attach(`ordine-${info.project.name}.png`, { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });
    await contesto.close();
  });
});
