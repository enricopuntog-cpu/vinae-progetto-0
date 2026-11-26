import { passwordFixture } from "./support/api";
import { contestoAutenticato, opzioniDelProgetto } from "./support/browser";
import { CATALOGO_PULITO, rimuoviCanonico } from "./support/canonico";
import { eseguiSql, ripristinaFixture } from "./support/db";
import { attendiCaricamento } from "./support/pagina";
import { expect, test } from "./support/test";
import { PRODUTTORE_E2E, etichettaCorsa, leggiDalDatabase, preparaBottigliaInCantina, uuid, type BottigliaPreparata } from "./support/vino";

/**
 * WI-011/WI-012/WI-013 · ciclo di vita del catalogo nel browser, con Auth, PostgREST e database veri dello stack E2E
 * dedicato: proposta ESPLICITA dalla Cantina, revisione dal pannello, vino senza LWIN creato e pubblicato, scheda
 * consultabile per UUID senza alcun annuncio; pannello chiuso a chi non è admin; cruscotto onesto su Sentinel.
 *
 * Gli interruttori si accendono solo nello stack di prova e tornano spenti. La pulizia toglie ogni riga creata (anche
 * lo storico, con i trigger spenti): lo spec WI-007 pretende un catalogo vuoto.
 */

const pulisci = (): string => {
  eseguiSql(`begin;
  set local session_replication_role = replica;
  update catalog.intake_settings set user_proposals_enabled = false, listing_harvest_enabled = false, auto_close_known_enabled = false;
  update catalog.public_projection_settings set enabled = false;
  delete from public.wine_catalog_selections;
  delete from catalog.contribution_submissions;
  delete from catalog.contributions;
  delete from catalog.wine_links;
  delete from catalog.wine_formats;
  delete from catalog.wine_vintages;
  delete from catalog.wines where origin = 'manual';
  delete from catalog.producers where origin = 'manual';
  delete from catalog.canonical_events;
  delete from brain.task_evidence;
  delete from brain.tasks;
  delete from brain.anomalies;
  delete from brain.sentinel_runs;
  delete from brain.events;
  commit;`);
  return leggiDalDatabase(
    `select concat_ws(' ', (select count(*) from catalog.contributions), (select count(*) from brain.anomalies),
       (select user_proposals_enabled::text from catalog.intake_settings));`,
  );
};

test.describe.serial("Catalogo vivo: dalla Cantina alla scheda senza LWIN, con revisione umana @smoke", () => {
  const corsa = etichettaCorsa();
  const nomeVino = `Nativo E2E ${corsa}`;
  let vino: BottigliaPreparata;
  let vinoCanonico = "";

  test.beforeAll(async () => {
    ripristinaFixture(passwordFixture());
    expect(rimuoviCanonico()).toBe(CATALOGO_PULITO);
    expect(pulisci()).toBe("0 0 false");
    vino = await preparaBottigliaInCantina("venditore", { nome: nomeVino });
    eseguiSql("update catalog.intake_settings set user_proposals_enabled = true;");
  });

  test.afterAll(() => {
    expect(pulisci()).toBe("0 0 false");
    expect(rimuoviCanonico()).toBe(CATALOGO_PULITO);
  });

  test("il proprietario propone il vino con consenso esplicito", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    await page.goto("/cantina");
    await attendiCaricamento(page);
    const scheda = page.locator('[id^="gruppo-"]').filter({ hasText: nomeVino }).first();
    const slug = leggiDalDatabase(`select slug from public.wines where id = '${uuid(vino.wineId)}';`);
    await scheda.getByTestId(`proposta-${slug}-apri`).click();
    await expect(scheda.getByTestId(`proposta-${slug}-invia`)).toBeDisabled();
    await scheda.getByTestId(`proposta-${slug}-consenso`).check();
    await scheda.getByTestId(`proposta-${slug}-invia`).click();
    await expect(scheda.getByTestId(`proposta-${slug}-inviata`)).toContainText("curatore");
    expect(
      leggiDalDatabase(
        `select concat_ws(' ', count(*), min(status), min(first_origin), (select count(*) from catalog.wines)) from catalog.contributions;`,
      ),
    ).toBe("1 aperta cantina 0");
    await contesto.close();
  });

  test("l'admin rivede la proposta, crea il vino senza LWIN e lo pubblica", async ({ browser, diagnostica }, info) => {
    const contesto = await contestoAutenticato(browser, "adminSenzaRilascio", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "adminSenzaRilascio");
    await page.goto("/admin/catalogo");
    await attendiCaricamento(page);
    await page.getByRole("tab", { name: "Proposte" }).click();
    const proposta = page.locator('[data-testid^="proposta-admin-"]').filter({ hasText: nomeVino });
    await expect(proposta).toContainText("non verificato");
    await proposta.getByLabel("Motivo o nota di provenienza").fill("Verificato in prova E2E");
    await proposta.getByRole("button", { name: "Crea nuovo vino" }).click();
    await expect(proposta).toHaveCount(0);
    vinoCanonico = uuid(
      leggiDalDatabase(`select id from catalog.wines where origin = 'manual' and lwin7 is null and name = '${nomeVino}';`),
    );

    await page.getByRole("tab", { name: "Catalogo" }).click();
    await page.getByLabel("Produttore, nome o LWIN-7").fill(nomeVino);
    await page.getByRole("button", { name: "Cerca", exact: true }).click();
    await expect(page.getByText("nativa, non pubblicata")).toBeVisible();
    await page.getByRole("button", { name: "Apri" }).click();
    const scheda = page.getByTestId("catalogo-admin-scheda");
    await scheda.getByLabel("Nota di provenienza o motivo (obbligatoria)").fill("Pubblicazione in prova E2E");
    await scheda.getByRole("button", { name: "Pubblica la scheda" }).click();
    await expect(scheda.getByRole("button", { name: "Ritira la pubblicazione" })).toBeVisible();
    await contesto.close();
  });

  test("a proiezione accesa la scheda senza LWIN è consultabile per UUID, senza alcun annuncio", async ({ browser, diagnostica }, info) => {
    eseguiSql("update catalog.public_projection_settings set enabled = true;");
    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    await page.goto(`/vino-catalogo/${vinoCanonico}`);
    const scheda = page.getByTestId("scheda-catalogo");
    await expect(scheda).toContainText(nomeVino);
    await expect(scheda).toContainText(PRODUTTORE_E2E);
    await expect(scheda).toContainText("senza codice LWIN");
    await expect(scheda).toContainText("verificata da un curatore");
    eseguiSql("update catalog.public_projection_settings set enabled = false;");
    await contesto.close();
  });

  test("chi non è admin non vede il pannello; il cruscotto dichiara che Sentinel non è pianificato", async ({ browser, diagnostica }, info) => {
    const utente = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const paginaUtente = await utente.newPage();
    for (const percorso of ["/admin/catalogo", "/admin/azienda"]) {
      const risposta = await paginaUtente.goto(percorso);
      expect(risposta?.status()).toBe(404);
    }
    await utente.close();

    const admin = await contestoAutenticato(browser, "adminSenzaRilascio", opzioniDelProgetto(info));
    const page = await admin.newPage();
    diagnostica.osserva(page, "adminSenzaRilascio");
    await page.goto("/admin/azienda");
    await attendiCaricamento(page);
    await expect(page.getByTestId("sentinel-stato")).toContainText("Non pianificato");
    await expect(page.getByTestId("sentinel-stato")).toContainText("mai eseguito");
    await page.getByRole("button", { name: "Esegui i controlli ora" }).click();
    await expect(page.getByTestId("sentinel-stato")).toContainText("eseguito di recente");
    await expect(page.getByTestId("sorgenti-non-collegate")).toContainText("backup");
    await admin.close();
  });
});
