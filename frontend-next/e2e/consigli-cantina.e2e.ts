import { accedi, passwordFixture, rpc } from "./support/api";
import { contestoAutenticato, opzioniDelProgetto } from "./support/browser";
import { eseguiSql, ripristinaFixture } from "./support/db";
import { attendiCaricamento, problemiAccessibilita, senzaScorrimentoOrizzontale } from "./support/pagina";
import { expect, test } from "./support/test";
import { etichettaCorsa, preparaBottigliaInCantina, uuid, type BottigliaPreparata } from "./support/vino";

/**
 * WI-005 · «Consigli dalla tua Cantina» in `/cantina`, su dati reali dello stack
 * isolato: le bottiglie nascono dalla porta reale `cellar_bottiglie_aggiungi`,
 * l'apertura da `bottiglia_apri`. Il consiglio deve riflettere SOLO le unità
 * apribili, cambiare dopo l'apertura, non mostrare la Cantina di altri utenti
 * e dichiarare i dati mancanti senza inventarli.
 */

const ANNO = new Date().getFullYear();

const impostaMetadati = (wineId: string): void => {
  const abbinamenti = JSON.stringify([
    {
      categoria: "Brasati e stufati",
      piatto: "Brasato al Barolo",
      livello: "ideale",
      note: "Struttura e tannino sostengono il piatto.",
      emoji: "🍖",
      keywords: ["brasato", "stufato"],
    },
  ]).replace(/'/g, "''");
  eseguiSql(
    `update public.wines set finestra_inizio = ${ANNO - 3}, finestra_fine = ${ANNO + 12}, apice_inizio = ${ANNO - 1}, apice_fine = ${ANNO + 4}, finestra_fonte = 'editorial', finestra_affidabilita = 'media', abbinamenti = '${abbinamenti}'::jsonb where id = '${uuid(wineId)}';`,
  );
};

test.describe.serial("Consigli dalla tua Cantina: bottiglie reali, stato aggiornato e isolamento @smoke @cross", () => {
  const corsa = etichettaCorsa();
  const conFinestra = `Consigliato E2E ${corsa}`;
  const senzaFinestra = `Ignoto E2E ${corsa}`;
  const aperto = `Gia aperto E2E ${corsa}`;
  let a: BottigliaPreparata;
  let b: BottigliaPreparata;
  let c: BottigliaPreparata;

  test.beforeAll(async () => {
    ripristinaFixture(passwordFixture());
    a = await preparaBottigliaInCantina("venditore", { nome: conFinestra, quantita: 2 });
    b = await preparaBottigliaInCantina("venditore", { nome: senzaFinestra });
    c = await preparaBottigliaInCantina("venditore", { nome: aperto });
    impostaMetadati(a.wineId);
    impostaMetadati(c.wineId);
    // C: l'unica bottiglia viene aperta con la porta reale, quindi non è più apribile.
    const sessione = await accedi("venditore");
    const esito = await rpc("bottiglia_apri", { p_bottle_unit_id: c.bottleUnitIds[0], p_nota: null }, sessione);
    expect(esito.ok).toBe(true);
  });

  test("il proprietario vede solo bottiglie apribili, motivate e senza dati inventati", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    await page.goto("/cantina");
    await attendiCaricamento(page);

    const sezione = page.getByTestId("consigli-cantina");
    await expect(sezione.getByRole("heading", { name: "Consigli dalla tua Cantina" })).toBeVisible();

    // A: nel momento ideale, con due bottiglie disponibili contate una volta.
    const consigli = sezione.getByTestId("consiglio-cantina");
    await expect(consigli).toHaveCount(1);
    await expect(consigli.first()).toContainText(conFinestra);
    await expect(consigli.first().getByTestId("consiglio-disponibili")).toContainText("2 bottiglie");
    await expect(consigli.first()).toContainText("momento ideale");
    await expect(sezione).not.toContainText(aperto);
    // B senza finestra: non è «pronta» per stasera, lo si dichiara.
    await expect(sezione).not.toContainText(senzaFinestra);
    await expect(sezione.getByTestId("consigli-note-stasera")).toContainText("non hanno");

    // Collegamento alla scheda della bottiglia in pagina.
    const href = await consigli.first().getByRole("link", { name: "Vai alla bottiglia" }).getAttribute("href");
    expect(href).toMatch(/^#gruppo-/);
    await expect(page.locator(href!)).toHaveCount(1);

    expect(await senzaScorrimentoOrizzontale(page), "scorrimento orizzontale in /cantina").toBe(true);
    expect(await problemiAccessibilita(page)).toEqual([]);
    await info.attach(`consigli-stasera-${info.project.name}.png`, { body: await sezione.screenshot(), contentType: "image/png" });

    // Cena: categoria documentata → A; piatto sconosciuto → nessun abbinamento inventato.
    await sezione.getByTestId("consigli-tab-cena").click();
    await sezione.getByTestId("consigli-categoria").first().click();
    await expect(sezione.getByTestId("consiglio-cantina")).toHaveCount(1);
    await expect(sezione.getByTestId("consiglio-cantina").first()).toContainText("Abbinamento registrato");
    await sezione.getByTestId("consigli-piatto").fill("gelato al pistacchio");
    await expect(sezione.getByTestId("consiglio-cantina")).toHaveCount(0);
    await expect(sezione.getByTestId("consigli-cena-nessuno")).toBeVisible();
    await info.attach(`consigli-cena-${info.project.name}.png`, { body: await sezione.screenshot(), contentType: "image/png" });

    // Dati: B manca di finestra; c'è un comando reale solo se esiste un annuncio collegato.
    await sezione.getByTestId("consigli-tab-dati").click();
    await expect(sezione.getByTestId("dati-mancanti-vino").filter({ hasText: senzaFinestra })).toContainText("Finestra di bevuta");
    await info.attach(`consigli-dati-${info.project.name}.png`, { body: await sezione.screenshot(), contentType: "image/png" });
    await contesto.close();
  });

  test("dopo l'apertura di una bottiglia il consiglio si aggiorna; poi la bottiglia non è più proposta", async ({ browser, diagnostica }, info) => {
    const sessione = await accedi("venditore");
    const apri = await rpc("bottiglia_apri", { p_bottle_unit_id: a.bottleUnitIds[0], p_nota: null }, sessione);
    expect(apri.ok).toBe(true);

    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    await page.goto("/cantina");
    await attendiCaricamento(page);
    const consiglio = page.getByTestId("consigli-cantina").getByTestId("consiglio-cantina");
    await expect(consiglio).toHaveCount(1);
    await expect(consiglio.first().getByTestId("consiglio-disponibili")).toContainText("1 bottiglia");

    const apri2 = await rpc("bottiglia_apri", { p_bottle_unit_id: a.bottleUnitIds[1], p_nota: null }, sessione);
    expect(apri2.ok).toBe(true);
    await page.reload();
    await attendiCaricamento(page);
    await expect(page.getByTestId("consigli-cantina").getByTestId("consiglio-cantina")).toHaveCount(0);
    await expect(page.getByTestId("consigli-nessuna-apribile")).toBeVisible();
    await contesto.close();
  });

  test("un altro utente non vede le bottiglie del proprietario né i suoi consigli", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "altro", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "altro");
    await page.goto("/cantina");
    await attendiCaricamento(page);
    const sezione = page.getByTestId("consigli-cantina");
    await expect(sezione).not.toContainText(corsa);
    await expect(page.locator("body")).not.toContainText(b.wineId);
    await expect(sezione.getByTestId("consigli-vuota")).toBeVisible();
    await contesto.close();
  });
});
