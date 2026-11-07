import { randomUUID } from "node:crypto";
import type { BrowserContext } from "@playwright/test";
import { accedi, accendiPubblicazione, caricaFoto, idCategoriaCalici, passwordFixture, rpc } from "./support/api";
import { contestoAutenticato, opzioniDelProgetto } from "./support/browser";
import { eseguiSql, ripristinaFixture } from "./support/db";
import { senzaScorrimentoOrizzontale } from "./support/pagina";
import { expect, test } from "./support/test";

/**
 * Payment Element degli Accessori (VPM-015B5D) su stack isolato, con Stripe.js
 * e la Edge Function dei pagamenti SOSTITUITI da mock deterministici nel solo
 * browser: nessuna richiesta raggiunge Stripe, nessun pagamento reale.
 *
 * Cosa si prova: il pulsante «Paga» compare solo a gate accesi; il doppio click
 * apre un solo pagamento con il solo id dell'ordine; errore e riprova; lo stato
 * «in elaborazione»; il ritorno da Stripe senza webhook NON è un pagamento; solo
 * l'evento attendibile (qui l'applicazione della vendita lato database, la stessa
 * funzione del webhook firmato) porta l'ordine a «Pagamento confermato».
 * NON si prova Stripe reale: il vero Stripe.js e il vero PaymentIntent in test
 * mode restano da provare con una chiave `pk_test_` autorizzata.
 */

const PROVIDER = "e2e_b5d";
const NOME = "Calice E2E pagamento";

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
  values ('${PROVIDER}', 'e2e_b5d_rete', 'Rete di prova E2E B5D', true, v_t) returning id into v_rete;
  insert into private.logistics_service_pudo_networks (service_definition_id, network_id, endpoint_role)
  values (v_srv, v_rete, 'both');
  insert into private.accessori_logistica_tariffe (
    provider_code, service_code, capability, classe_codice, peso_max_g, lunghezza_max_mm,
    larghezza_max_mm, altezza_max_mm, fragile_ammesso, prezzo_cents, fonte, stato, effective_from)
  values ('${PROVIDER}', 'standard', 'PUDO_TO_PUDO', 'm', 8000, 450, 300, 300, true, 790,
          'Prova E2E B5D (non una tariffa)', 'active', v_t);
end
$f$;`);
};

/** Stripe.js finto: stessa superficie che usa il Payment Element, esito scelto dal test. */
const STRIPE_FINTO = `
(function () {
  window.__stripeEsito = window.__stripeEsito || "succeeded";
  window.__confermeStripe = 0;
  function elemento() {
    var h = {};
    return {
      mount: function (n) {
        var i = document.createElement("input");
        i.setAttribute("data-testid", "stripe-finto-campo");
        i.setAttribute("aria-label", "Carta (campo finto di prova)");
        n.appendChild(i);
        setTimeout(function () { if (h.ready) h.ready({ elementType: "payment" }); }, 0);
      },
      on: function (e, f) { h[e] = f; },
      off: function () {}, once: function (e, f) { h[e] = f; },
      update: function () {}, unmount: function () {}, destroy: function () {},
      focus: function () {}, blur: function () {}, clear: function () {}, collapse: function () {}
    };
  }
  function Stripe() {
    var els = null;
    var elements = {
      create: function () { els = elemento(); return els; },
      getElement: function () { return els; },
      update: function () {},
      fetchUpdates: function () { return Promise.resolve({}); },
      submit: function () { return Promise.resolve({}); }
    };
    return {
      elements: function () { return elements; },
      confirmPayment: function () {
        window.__confermeStripe += 1;
        var e = window.__stripeEsito;
        if (e === "errore") return Promise.resolve({ error: { type: "card_error", message: "Carta rifiutata (prova)." } });
        return Promise.resolve({ paymentIntent: { status: e } });
      },
      createToken: function () { return Promise.resolve({}); },
      createPaymentMethod: function () { return Promise.resolve({}); },
      confirmCardPayment: function () { return Promise.resolve({}); },
      retrievePaymentIntent: function () { return Promise.resolve({}); },
      _registerWrapper: function () {}, registerAppInfo: function () {}
    };
  }
  Stripe.version = 3;
  window.Stripe = Stripe;
})();`;

interface Mock {
  aperture: { corpo: unknown; chiave: string | undefined }[];
  richiesteStripeReali: string[];
}

/** Sostituisce Stripe.js e la Edge Function: nessuna richiesta esce dallo stack di prova. */
const installaMock = async (contesto: BrowserContext): Promise<Mock> => {
  const mock: Mock = { aperture: [], richiesteStripeReali: [] };
  // Un solo gestore per tutti gli host Stripe: Stripe.js è il mock, ogni altra richiesta sarebbe reale e si blocca.
  await contesto.route(/^https:\/\/([^/]*\.)?stripe\.(com|network)\//, (r) => {
    const url = r.request().url();
    if (/^https:\/\/js\.stripe\.com\//.test(url)) {
      return r.fulfill({ status: 200, contentType: "application/javascript", body: STRIPE_FINTO });
    }
    mock.richiesteStripeReali.push(url);
    return r.abort();
  });
  await contesto.route(/\/functions\/v1\/payments-checkout/, async (r) => {
    if (r.request().method() === "OPTIONS") {
      return r.fulfill({
        status: 204,
        headers: {
          "access-control-allow-origin": "*",
          "access-control-allow-headers": "authorization, apikey, x-client-info, content-type, x-idempotency-key",
          "access-control-allow-methods": "POST, OPTIONS",
        },
      });
    }
    mock.aperture.push({
      corpo: r.request().postDataJSON(),
      chiave: r.request().headers()["x-idempotency-key"],
    });
    // Piccola attesa: rende osservabile il doppio click.
    await new Promise((ok) => setTimeout(ok, 400));
    return r.fulfill({
      status: 200,
      contentType: "application/json",
      headers: { "access-control-allow-origin": "*" },
      body: JSON.stringify({ clientSecret: "pi_finto_secret_finto", checkoutUrl: null }),
    });
  });
  return mock;
};

const statoDb = (id: string): string =>
  eseguiSql(`select stato || ' ' || coalesce(pagamento_modo, '-') from private.accessori_ordini where id = '${id}';`);


/** 6 calici in Cantina, 4 in annuncio a 20,00 € con peso e misure del collo (senza, l'annuncio non è ordinabile). */
const pubblicaAnnuncioOrdinabile = async (): Promise<string> => {
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
  const id = randomUUID();
  const bozza = await rpc(
    "annunci_accessori_salva",
    {
      p_id: id,
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
  const pubblicato = await rpc("annunci_accessori_pubblica", { p_id: id }, venditore);
  if (!pubblicato.ok) throw new Error(`Annuncio non pubblicato: HTTP ${pubblicato.status}`);
  return id;
};
let annuncioId = "";
let ordineId = "";

const creaOrdine = async (): Promise<string> => {
  const sessione = await accedi("altro");
  const congelato = await rpc<{ preventivoId: string }>(
    "accessori_logistica_preventivo_congela",
    { p_annuncio: annuncioId, p_quantita: 1, p_destinazione: "punto_ritiro", p_assicurazione: false },
    sessione,
  );
  if (!congelato.ok) throw new Error(`Preventivo non congelato: HTTP ${congelato.status} ${JSON.stringify(congelato.body).slice(0, 200)}`);
  const ordine = await rpc<{ id: string }>(
    "accessori_checkout_crea",
    { p_preventivo_id: congelato.body.preventivoId, p_chiave: `e2e-b5d-${randomUUID()}` },
    sessione,
  );
  if (!ordine.ok) throw new Error(`Ordine non creato: HTTP ${ordine.status} ${JSON.stringify(ordine.body).slice(0, 200)}`);
  return ordine.body.id;
};

test.describe.serial("Accessori: Payment Element con provider simulato @smoke @cross", () => {
  test.beforeAll(async () => {
    ripristinaFixture(passwordFixture());
    await accendiPubblicazione();
    creaLogisticaDiProva();
    const rilascio = await accedi("rilascio");
    const motivo = "prova browser E2E B5D";
    const logistica = await rpc("accessori_logistica_admin_imposta", { p_attiva: true, p_motivo: motivo }, rilascio);
    const checkout = await rpc("accessori_checkout_admin_imposta", { p_attivo: true, p_motivo: motivo }, rilascio);
    if (!logistica.ok || !checkout.ok) throw new Error("Interruttori di prova non accesi.");
    annuncioId = await pubblicaAnnuncioOrdinabile();
    ordineId = await creaOrdine();
  });

  test("1. «Paga» compare all'acquirente; doppio click: un solo pagamento, con il solo id dell'ordine", async ({
    browser,
    diagnostica,
  }, info) => {
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const mock = await installaMock(contesto);
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    await page.goto(`/ordini-accessori/${ordineId}`);
    await expect(page.getByTestId("ordine-stato")).toHaveText("Prenotato, in attesa di pagamento");
    await expect(page.getByTestId("ordine-scadenza")).toContainText("non addebita denaro");
    const paga = page.getByTestId("pagamento-paga");
    await expect(paga).toBeVisible();
    // Stripe.js non si carica alla sola vista dell'ordine.
    expect(mock.aperture).toHaveLength(0);

    await paga.dblclick();
    await expect(page.getByTestId("stripe-finto-campo")).toBeVisible();
    expect(mock.aperture).toHaveLength(1);
    expect(mock.aperture[0].corpo).toEqual({ accessoriOrdineId: ordineId });
    expect(mock.aperture[0].chiave).toBe(`acc-pay-${ordineId}`);
    expect(await senzaScorrimentoOrizzontale(page)).toBe(true);
    await info.attach("payment-element.png", { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });
    expect(statoDb(ordineId)).toBe("in_attesa_pagamento -");
    expect(mock.richiesteStripeReali).toEqual([]);
    await contesto.close();
  });

  test("2. errore e riprova; poi «in elaborazione»: il browser da solo non conferma nulla", async ({
    browser,
    diagnostica,
  }, info) => {
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const mock = await installaMock(contesto);
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    await page.addInitScript(() => {
      (window as unknown as { __stripeEsito: string }).__stripeEsito = "errore";
    });
    await page.goto(`/ordini-accessori/${ordineId}`);
    await page.getByTestId("pagamento-paga").click();
    await page.getByTestId("pagamento-conferma").click();
    await expect(page.getByTestId("pagamento-errore")).toContainText("Carta rifiutata (prova).");
    expect(statoDb(ordineId)).toBe("in_attesa_pagamento -");

    // Riprova: Stripe accetta; la pagina dice «in elaborazione», NON «confermato».
    await page.evaluate(() => {
      (window as unknown as { __stripeEsito: string }).__stripeEsito = "processing";
    });
    await page.getByTestId("pagamento-conferma").click();
    await expect(page.getByTestId("pagamento-stato")).toContainText("Pagamento in elaborazione");
    await expect(page.getByTestId("ordine-stato")).toHaveText("Prenotato, in attesa di pagamento");
    expect(await page.evaluate(() => (window as unknown as { __confermeStripe: number }).__confermeStripe)).toBe(2);
    expect(statoDb(ordineId)).toBe("in_attesa_pagamento -");
    await info.attach("in-elaborazione.png", { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });

    // Refresh: la sessione di pagamento si riprende con la stessa chiave.
    await page.reload();
    await page.getByTestId("pagamento-paga").click();
    await expect(page.getByTestId("stripe-finto-campo")).toBeVisible();
    expect(mock.aperture.map((a) => a.chiave)).toEqual([`acc-pay-${ordineId}`, `acc-pay-${ordineId}`]);
    await contesto.close();
  });

  test("3. ritorno da Stripe senza webhook: non è un pagamento; l'evento attendibile lo conferma", async ({
    browser,
    diagnostica,
  }, info) => {
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    await installaMock(contesto);
    // Le due visite rappresentano ingressi indipendenti. Su WebKit una seconda
    // navigazione nella stessa scheda annulla le letture avviate dalla prima.
    const paginaEsitoInventato = await contesto.newPage();
    diagnostica.osserva(paginaEsitoInventato, "esito inventato");
    await paginaEsitoInventato.goto(`/ordini-accessori/${ordineId}?checkout=success`);
    await expect(paginaEsitoInventato.getByTestId("ordine-stato")).toHaveText("Prenotato, in attesa di pagamento");
    await expect(paginaEsitoInventato.getByTestId("pagamento-paga")).toBeVisible();

    const page = await contesto.newPage();
    diagnostica.osserva(page, "ritorno");
    await page.goto(`/ordini-accessori/${ordineId}?checkout=ritorno`);
    await expect(page.getByTestId("pagamento-stato")).toContainText("Pagamento in elaborazione");
    await expect(page.getByTestId("ordine-stato")).toHaveText("Prenotato, in attesa di pagamento");
    expect(statoDb(ordineId)).toBe("in_attesa_pagamento -");

    // Evento attendibile: la stessa funzione che applica il webhook firmato (modo provider).
    eseguiSql(`select private.accessori_ordine_vendita_applica('${ordineId}', 'provider');`);
    await expect(page.getByTestId("ordine-stato")).toHaveText("Pagamento confermato", { timeout: 15_000 });
    await expect(page.getByTestId("pagamento-paga")).toHaveCount(0);
    await expect(page.getByTestId("pagamento-stato")).toHaveCount(0);
    expect(statoDb(ordineId)).toBe("pagato provider");
    await info.attach("pagamento-confermato.png", { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });
    await contesto.close();
  });

  test("4. venditore e account estraneo: nessun pagamento; gate spento: ordine pagato ancora consultabile", async ({
    browser,
    diagnostica,
  }, info) => {
    const nuovo = await creaOrdine();

    const venditore = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const mockV = await installaMock(venditore);
    const pv = await venditore.newPage();
    diagnostica.osserva(pv, "venditore");
    await pv.goto(`/ordini-accessori/${nuovo}`);
    await expect(pv.getByTestId("ordine-ricevi")).toBeVisible();
    await expect(pv.getByTestId("pagamento-paga")).toHaveCount(0);
    await expect(pv.getByTestId("pagamento-accessorio")).toHaveCount(0);
    expect(mockV.aperture).toHaveLength(0);
    await venditore.close();

    const estraneo = await contestoAutenticato(browser, "segnalante", opzioniDelProgetto(info));
    const pe = await estraneo.newPage();
    diagnostica.osserva(pe, "estraneo");
    diagnostica.ammetti("status of 404");
    const risposta = await pe.goto(`/ordini-accessori/${nuovo}`);
    expect(risposta?.status()).toBe(404);
    await expect(pe.getByTestId("pagamento-paga")).toHaveCount(0);
    await estraneo.close();

    // Spegnimento commerciale: la prenotazione non pagata sparisce, quella incassata resta leggibile.
    const admin = await accedi("adminSenzaRilascio");
    const spento = await rpc("accessori_checkout_admin_imposta", { p_attivo: false, p_motivo: "prova browser E2E B5D" }, admin);
    expect(spento.ok).toBe(true);
    const acquirente = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const mockA = await installaMock(acquirente);
    const pa = await acquirente.newPage();
    diagnostica.osserva(pa, "acquirente");
    // Il database ha chiuso il checkout: la prenotazione resta leggibile ma senza alcun pulsante di pagamento.
    await pa.goto(`/ordini-accessori/${nuovo}`);
    await expect(pa.getByTestId("ordine-stato")).toHaveText("Prenotato, in attesa di pagamento");
    await expect(pa.getByTestId("pagamento-non-disponibile")).toContainText("non è ancora attivo");
    await expect(pa.getByTestId("pagamento-paga")).toHaveCount(0);
    await pa.goto(`/ordini-accessori/${ordineId}`);
    await expect(pa.getByTestId("ordine-stato")).toHaveText("Pagamento confermato");
    expect(mockA.aperture).toHaveLength(0);
    expect(mockA.richiesteStripeReali).toEqual([]);
    expect(eseguiSql("select (select count(*) from public.orders) || '/' || (select count(*) from public.payments);")).toBe("0/0");
    await acquirente.close();
  });
});

