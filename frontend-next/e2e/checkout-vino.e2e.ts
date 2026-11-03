import { accedi, passwordFixture, rpc } from "./support/api";
import { contestoAutenticato, opzioniDelProgetto } from "./support/browser";
import { ripristinaFixture } from "./support/db";
import { attendiCaricamento } from "./support/pagina";
import { risolviBersaglio } from "./support/stack";
import { expect, test } from "./support/test";
import {
  UUID_INESISTENTE,
  etichettaCorsa,
  leggiDalDatabase,
  prenotaOrdineComeServer,
  preparaBottigliaInCantina,
  pubblicaAnnuncioVino,
  type AnnuncioVino,
} from "./support/vino";

/**
 * Checkout vino (VPM-018-E2E-CRIT-01). Il checkout reale è commercialmente
 * spento: qui si prova che è FAIL-CLOSED, non che funziona.
 *
 * Gate della build di prova (come in produzione per la Beta):
 * `NEXT_PUBLIC_PHASE_7_PAYMENTS_ENABLED=false` → nessun «Compra ora» sulla
 * scheda; `PAYMENTS_ENABLED=false` lato server. La build E2E accende invece
 * `NEXT_PUBLIC_PAYMENT_ACTIONS_ENABLED` (serve al mock Accessori B5D), quindi la
 * conferma del checkout vino PARTE davvero verso `payments-checkout`, che sullo
 * stack dedicato non è servita (edge-runtime escluso): il caso prova che nessun
 * ordine, pagamento o prenotazione nasce e che l'errore è visibile. La risposta
 * della Edge Function con `PAYMENTS_ENABLED` spento NON è esercitata nel browser
 * (coperta dai test Bun della funzione): GATE VERIFICATO, CHECKOUT E2E NON VERIFICATO.
 *
 * Isolamento dei dati d'ordine: un ordine IN ATTESA DI PAGAMENTO nasce dalla
 * porta autorevole `order_checkout_reserve` con il ruolo del server, come la
 * farebbe nascere la Edge Function; mai pagato, nessun provider.
 */

const PREZZO_CENTS = 3000;

test.describe.serial("Checkout vino: gate fail-closed, nessun pagamento, ordine non leggibile da estranei @smoke @cross", () => {
  const nomeVino = `Barbaresco E2E-CRIT ${etichettaCorsa()}`;
  let annuncio: AnnuncioVino;
  let ordineId = "";

  test.beforeAll(async () => {
    ripristinaFixture(passwordFixture());
    const bottiglia = await preparaBottigliaInCantina("venditore", { nome: nomeVino });
    annuncio = await pubblicaAnnuncioVino("venditore", bottiglia.bottleUnitIds[0], PREZZO_CENTS);
  });

  test("la scheda non offre «Compra ora» con i pagamenti spenti", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    await page.goto(`/annuncio/${annuncio.slug}`);
    await attendiCaricamento(page);
    await expect(page.getByRole("heading", { level: 1, name: new RegExp(nomeVino) })).toBeVisible();
    // La scheda è caricata (c'è il contatto): l'assenza dell'acquisto non è un «non ancora arrivato».
    await expect(page.getByRole("button", { name: "Messaggio" })).toBeVisible();
    await expect(page.getByRole("button", { name: /Compra ora/ })).toHaveCount(0);
    await contesto.close();
  });

  test("il checkout aperto per indirizzo non crea ordini, pagamenti né prenotazioni e mostra l'errore", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    // La Edge Function dei pagamenti non è servita dallo stack dedicato: la richiesta fallisce, ed è l'esito atteso.
    diagnostica.ammetti("/functions/v1/payments-checkout", "[Phase7] payments-checkout fallita");
    const richieste: string[] = [];
    const statiFunzione: number[] = [];
    page.on("request", (r) => richieste.push(r.url()));
    page.on("response", (r) => {
      if (r.url().includes("/functions/v1/payments-checkout") && r.request().method() === "POST") statiFunzione.push(r.status());
    });

    await page.goto(`/checkout/${annuncio.slug}`);
    await attendiCaricamento(page);
    await expect(page.getByText("Beta · nessun addebito reale")).toBeVisible();
    await expect(page.getByRole("heading", { level: 1, name: "Checkout" })).toBeVisible();
    // Il riepilogo mostra il totale del preventivo del database, non un numero ricalcolato dal browser.
    const preventivo = await rpc<{ preventivo?: { totaleCents?: number } } | null>(
      "listing_preventivo",
      { p_listing_id: annuncio.listingId, p_quantita: 1, p_prezzo_unitario_cents: null },
      await accedi("altro"),
    );
    const totaleCents = preventivo.body?.preventivo?.totaleCents;
    expect(typeof totaleCents, "preventivo del database").toBe("number");
    const totale = ((totaleCents ?? 0) / 100).toFixed(2).replace(".", ",");
    await expect(page.getByText(new RegExp(`${totale}\\s€`)).first()).toBeVisible();

    await page.getByLabel("Telefono").fill("3331234567");
    const conferma = page.getByTestId("checkout-confirm");
    const avanti = page.getByTestId("checkout-next");
    for (let passo = 0; passo < 4; passo += 1) {
      // Si attende che il passo sia reso (avanti o conferma) prima di decidere: niente clic su un passo in transizione.
      await expect(avanti.or(conferma)).toBeVisible();
      if (await conferma.isVisible()) break;
      await avanti.click();
    }
    await expect(conferma).toBeVisible();
    await expect(conferma).toBeEnabled();
    // La pagina può già mostrare avvisi (es. logistica): l'errore della conferma è un avviso IN PIÙ.
    const avvisiPrima = await page.getByRole("alert").filter({ hasText: /./ }).count();
    await conferma.click();

    await expect(page.getByRole("alert").filter({ hasText: /./ })).toHaveCount(avvisiPrima + 1);
    await expect(page).toHaveURL(new RegExp(`/checkout/${annuncio.slug}`));
    expect(richieste.filter((u) => /stripe\.com|stripe\.network/.test(u)), "richieste verso Stripe").toEqual([]);
    expect(richieste.some((u) => u.includes("/functions/v1/payments-checkout")), "la conferma non è partita").toBe(true);
    // Nessuna risposta di successo dalla funzione dei pagamenti (sullo stack dedicato non è servita).
    expect(statiFunzione.filter((s) => s < 400), "risposte 2xx/3xx da payments-checkout").toEqual([]);
    await info.attach("stati-payments-checkout.json", { body: JSON.stringify(statiFunzione), contentType: "application/json" });

    // Il database è l'autorità: nessun ordine, pagamento, allocazione; annuncio ancora attivo e libero.
    expect(
      leggiDalDatabase(`select (select count(*) from public.orders) || ' ' || (select count(*) from public.payments)
        || ' ' || (select count(*) from private.listing_allocazioni) || ' ' || (select stato from public.listings where id = '${annuncio.listingId}')
        || ' ' || coalesce((select reserved_by::text from public.listings where id = '${annuncio.listingId}'), 'libero');`),
    ).toBe("0 0 0 attivo libero");
    await info.attach("checkout-gate.png", { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });
    await contesto.close();
  });

  test("un utente autenticato non può prenotare chiamando la porta del server", async () => {
    const altro = await accedi("altro");
    const esito = await rpc(
      "order_checkout_reserve",
      {
        p_buyer_id: altro.id,
        p_listing_id: annuncio.listingId,
        p_proposal_id: null,
        p_delivery_mode: "consegna_mano",
        p_idempotency_key: `e2e-crit-${etichettaCorsa()}`,
        p_quantita: null,
      },
      altro,
    );
    // 403 (permesso negato), non 404: un 404 di PostgREST vorrebbe dire firma non trovata, non porta chiusa.
    expect(esito.ok).toBe(false);
    expect(esito.status).toBe(403);
    expect(leggiDalDatabase("select count(*) from public.orders;")).toBe("0");
  });

  test("senza sessione il checkout chiede l'accesso e non offre la conferma", async ({ page }) => {
    await page.goto(`/checkout/${annuncio.slug}`);
    await attendiCaricamento(page);
    await expect(page.getByRole("heading", { name: "Accedi per continuare" })).toBeVisible();
    await expect(page.getByTestId("checkout-confirm")).toHaveCount(0);
    await expect(page.getByTestId("checkout-next")).toHaveCount(0);
  });

  test("un checkout di un annuncio inesistente risponde 404", async ({ page, diagnostica }) => {
    diagnostica.ammetti(`/checkout/${UUID_INESISTENTE}`);
    const risposta = await page.goto(`/checkout/${UUID_INESISTENTE}`);
    expect(risposta?.status()).toBe(404);
  });

  test("un ordine in attesa di pagamento è visibile all'acquirente e non a un estraneo", async ({ browser, diagnostica }, info) => {
    const acquirente = await accedi("altro");
    ordineId = prenotaOrdineComeServer(acquirente.id, annuncio.listingId);
    expect(leggiDalDatabase(`select stato from public.orders where id = '${ordineId}';`)).toBe("in_attesa_pagamento");

    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    await page.goto(`/ordine/${ordineId}`);
    await attendiCaricamento(page);
    await expect(page.getByRole("heading", { level: 1, name: ordineId.slice(0, 8) })).toBeVisible();
    await expect(page.getByText("Ordine · Acquisto")).toBeVisible();
    await contesto.close();

    const estraneo = await contestoAutenticato(browser, "segnalante", opzioniDelProgetto(info));
    const pagina = await estraneo.newPage();
    diagnostica.osserva(pagina, "estraneo");
    await pagina.goto(`/ordine/${ordineId}`);
    await attendiCaricamento(pagina);
    await expect(pagina.getByText("Ordine non disponibile")).toBeVisible();
    await expect(pagina.getByRole("heading", { level: 1, name: ordineId.slice(0, 8) })).toHaveCount(0);
    await estraneo.close();

    // Anche la lettura diretta della tabella: l'acquirente vede la sua riga (controllo positivo), l'estraneo nessuna.
    const { apiUrl, anonKey } = risolviBersaglio();
    const righeOrdine = async (ruolo: "altro" | "segnalante") => {
      const sessione = await accedi(ruolo);
      const res = await fetch(`${apiUrl}/rest/v1/orders?id=eq.${ordineId}&select=id`, {
        headers: { apikey: anonKey, Authorization: `Bearer ${sessione.token}` },
      });
      return res.ok ? ((await res.json()) as unknown[]).length : -res.status;
    };
    expect(await righeOrdine("altro")).toBe(1);
    expect(await righeOrdine("segnalante")).toBe(0);
    // L'ordine non è mai diventato pagato.
    expect(leggiDalDatabase(`select stato from public.orders where id = '${ordineId}';`)).toBe("in_attesa_pagamento");
  });
});
