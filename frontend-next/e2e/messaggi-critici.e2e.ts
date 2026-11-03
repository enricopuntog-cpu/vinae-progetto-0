import type { Page } from "@playwright/test";
import { accedi, passwordFixture, rpc } from "./support/api";
import { contestoAutenticato, opzioniDelProgetto } from "./support/browser";
import { ripristinaFixture } from "./support/db";
import { attendiCaricamento } from "./support/pagina";
import { risolviBersaglio } from "./support/stack";
import { expect, test } from "./support/test";
import { etichettaCorsa, leggiDalDatabase, preparaBottigliaInCantina, pubblicaAnnuncioVino, type AnnuncioVino } from "./support/vino";

/**
 * Messaggistica fra utenti distinti (VPM-018-E2E-CRIT-01): acquirente,
 * venditore e un terzo utente. Conversazione aperta dall'annuncio, invio,
 * lettura dal destinatario, persistenza e ordine dopo il ricaricamento,
 * isolamento del terzo utente, rifiuto senza sessione, errore d'invio con nuovo
 * tentativo senza duplicati.
 *
 * Lo stack dedicato NON avvia Realtime: la consegna in tempo reale non è
 * collaudata qui. Il destinatario vede i messaggi dopo una navigazione o un
 * ricaricamento, che è ciò che questi casi provano.
 */

const SCRIVI = /Scrivi un messaggio/;

/** Il pannello della conversazione aperta (non la lista, che ripete l'ultimo messaggio come anteprima). */
const pannello = (page: Page) =>
  page.locator("section").filter({ has: page.getByRole("button", { name: "Invia messaggio" }) });

const invia = async (page: Page, testo: string) => {
  await page.getByPlaceholder(SCRIVI).fill(testo);
  await page.getByRole("button", { name: "Invia messaggio" }).click();
  await expect(pannello(page).getByText(testo)).toBeVisible();
};

/** I testi compaiono nel pannello in quest'ordine (dall'alto al basso). */
const attendiOrdine = async (page: Page, testi: string[]) => {
  for (const t of testi) await expect(pannello(page).getByText(t)).toBeVisible();
  const contenuto = await pannello(page).innerText();
  const posizioni = testi.map((t) => contenuto.indexOf(t));
  expect(posizioni.every((p) => p >= 0), "messaggi presenti").toBe(true);
  expect([...posizioni].sort((a, b) => a - b), "ordine dei messaggi").toEqual(posizioni);
};

test.describe.serial("Messaggi fra utenti distinti: conversazione, persistenza, ordine e isolamento @smoke @cross", () => {
  const tag = etichettaCorsa();
  const nomeVino = `Brunello E2E-CRIT ${tag}`;
  const primo = `Buongiorno, la bottiglia è ancora disponibile? ${tag}-1`;
  const secondo = `Posso passare a ritirarla di persona? ${tag}-2`;
  const risposta = `Sì, è disponibile e può ritirarla. ${tag}-3`;
  const dopoErrore = `Messaggio inviato al secondo tentativo ${tag}-4`;
  let annuncio: AnnuncioVino;
  let conversazioneId = "";

  test.beforeAll(async () => {
    ripristinaFixture(passwordFixture());
    const bottiglia = await preparaBottigliaInCantina("venditore", { nome: nomeVino });
    annuncio = await pubblicaAnnuncioVino("venditore", bottiglia.bottleUnitIds[0], 6500);
  });

  test("l'acquirente apre la conversazione dall'annuncio e la trova vuota", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    await page.goto(`/annuncio/${annuncio.slug}`);
    await attendiCaricamento(page);
    await page.getByRole("button", { name: "Messaggio" }).click();
    await expect(page).toHaveURL(/\/messaggi\?conversation=[0-9a-f-]{36}$/);
    conversazioneId = new URL(page.url()).searchParams.get("conversation") ?? "";
    // Finisce nelle letture di controllo: solo un UUID.
    expect(conversazioneId).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
    await attendiCaricamento(page);
    await expect(page.getByText("Nessun messaggio. Inizia la conversazione.")).toBeVisible();
    // Una conversazione legata all'annuncio, con i due soli partecipanti.
    expect(
      leggiDalDatabase(`select c.listing_id || ' ' || (select count(*) from public.conversation_participants p where p.conversation_id = c.id)
        || ' ' || (select count(*) from public.messages m where m.conversation_id = c.id) from public.conversations c where c.id = '${conversazioneId}';`),
    ).toBe(`${annuncio.listingId} 2 0`);
    await contesto.close();
  });

  test("l'acquirente invia due messaggi: dopo il ricaricamento restano, nell'ordine di invio", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    await page.goto(`/messaggi?conversation=${conversazioneId}`);
    await attendiCaricamento(page);
    await invia(page, primo);
    await invia(page, secondo);
    await page.reload();
    await attendiCaricamento(page);
    await attendiOrdine(page, [primo, secondo]);
    expect(leggiDalDatabase(`select count(*) from public.messages where conversation_id = '${conversazioneId}';`)).toBe("2");
    await contesto.close();
  });

  test("il venditore li trova in /messaggi, li legge in ordine e risponde", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    await page.goto("/messaggi");
    await attendiCaricamento(page);
    const voce = page.getByRole("button", { name: /e2e12zk_u03/ });
    await expect(voce).toBeVisible();
    await expect(voce).toContainText(secondo);
    await voce.click();
    await attendiOrdine(page, [primo, secondo]);
    await invia(page, risposta);
    await attendiOrdine(page, [primo, secondo, risposta]);
    await info.attach("messaggi-venditore.png", { body: await page.screenshot({ fullPage: true }), contentType: "image/png" });
    await contesto.close();
  });

  test("l'acquirente vede la risposta dopo la navigazione, in coda alla cronologia", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    await page.goto(`/messaggi?conversation=${conversazioneId}`);
    await attendiCaricamento(page);
    await attendiOrdine(page, [primo, secondo, risposta]);
    await contesto.close();
  });

  test("un terzo utente non vede la conversazione, non la legge e non ci scrive", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "segnalante", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "terzo");
    await page.goto(`/messaggi?conversation=${conversazioneId}`);
    await attendiCaricamento(page);
    await expect(page.getByText("Nessuna conversazione")).toBeVisible();
    for (const t of [primo, secondo, risposta]) await expect(page.getByText(t)).toHaveCount(0);
    await contesto.close();

    // Le porte rifiutano il terzo anche chiamate direttamente.
    const terzo = await accedi("segnalante");
    const lettura = await rpc<unknown[]>("messages_page", { p_conversation_id: conversazioneId, p_before_created_at: null, p_before_id: null, p_limit: 50 }, terzo);
    // La porta risponde (niente 404 di firma): rifiuto o pagina vuota, mai i messaggi altrui.
    expect(lettura.status).not.toBe(404);
    if (lettura.ok) expect(lettura.body).toEqual([]);
    const scrittura = await rpc("message_send", { p_conversation_id: conversazioneId, p_text: "intruso", p_idempotency_key: crypto.randomUUID() }, terzo);
    expect(scrittura.ok).toBe(false);
    expect(scrittura.status).not.toBe(404);
    const apertura = await rpc("conversation_open", { p_listing_id: annuncio.listingId, p_order_id: null }, terzo);
    // Il terzo può aprire SOLO una propria conversazione col venditore, mai entrare in quella esistente:
    // la porta risponde (ok o rifiuto), ma in nessun caso con l'id della conversazione altrui.
    expect([200, 400, 401, 403, 404]).toContain(apertura.status);
    expect(JSON.stringify(apertura.body ?? null)).not.toContain(conversazioneId);
    expect(leggiDalDatabase(`select count(*) from public.messages where conversation_id = '${conversazioneId}';`)).toBe("3");
  });

  test("senza sessione: nessun comando di contatto e nessun invio accettato", async ({ page }) => {
    await page.goto(`/annuncio/${annuncio.slug}`);
    await attendiCaricamento(page);
    await expect(page.getByRole("link", { name: "Accedi per contattare il venditore" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Messaggio" })).toHaveCount(0);

    const { apiUrl, anonKey } = risolviBersaglio();
    const res = await fetch(`${apiUrl}/rest/v1/rpc/message_send`, {
      method: "POST",
      headers: { apikey: anonKey, Authorization: `Bearer ${anonKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ p_conversation_id: conversazioneId, p_text: "anonimo", p_idempotency_key: crypto.randomUUID() }),
    });
    // 401 (anonimo senza permesso), non 404: un 404 di PostgREST vorrebbe dire firma non trovata.
    expect(res.ok).toBe(false);
    expect(res.status).toBe(401);
    expect(leggiDalDatabase(`select count(*) from public.messages where conversation_id = '${conversazioneId}';`)).toBe("3");
  });

  test("un invio fallito mostra l'errore e il nuovo tentativo non duplica il messaggio", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "acquirente");
    // Guasto simulato una sola volta e nel caso peggiore: la richiesta RAGGIUNGE il database (il messaggio è
    // scritto) ma la risposta si perde. Il nuovo tentativo deve riusare la chiave d'idempotenza, non duplicare.
    diagnostica.ammetti("/rest/v1/rpc/message_send", "message_send");
    let guasti = 0;
    await page.route("**/rest/v1/rpc/message_send", async (route) => {
      if (guasti === 0) {
        guasti += 1;
        await route.fetch();
        await route.fulfill({ status: 503, contentType: "application/json", body: JSON.stringify({ message: "servizio non disponibile" }) });
        return;
      }
      await route.continue();
    });

    await page.goto(`/messaggi?conversation=${conversazioneId}`);
    await attendiCaricamento(page);
    await attendiOrdine(page, [primo, secondo, risposta]);
    await page.getByPlaceholder(SCRIVI).fill(dopoErrore);
    await page.getByRole("button", { name: "Invia messaggio" }).click();
    await expect(pannello(page).getByRole("alert")).toContainText("Il nuovo tentativo");
    // Il testo resta nel campo: il nuovo tentativo è un clic.
    await expect(page.getByPlaceholder(SCRIVI)).toHaveValue(dopoErrore);
    await page.getByRole("button", { name: "Invia messaggio" }).click();
    await expect(pannello(page).getByRole("alert")).toHaveCount(0);
    await attendiOrdine(page, [primo, secondo, risposta, dopoErrore]);
    expect(guasti).toBe(1);
    expect(
      leggiDalDatabase(`select count(*) from public.messages where conversation_id = '${conversazioneId}' and body = '${dopoErrore}';`),
    ).toBe("1");
    await contesto.close();
  });
});
