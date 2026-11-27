import { passwordFixture } from "./support/api";
import { contestoAutenticato, opzioniDelProgetto } from "./support/browser";
import { CATALOGO_PULITO, rimuoviCanonico } from "./support/canonico";
import { eseguiSql, ripristinaFixture } from "./support/db";
import { attendiCaricamento } from "./support/pagina";
import { expect, test } from "./support/test";
import { PRODUTTORE_E2E, etichettaCorsa, leggiDalDatabase, preparaBottigliaInCantina, uuid, type BottigliaPreparata } from "./support/vino";
import { apriIdentificazione } from "./support/wizard-ricerca";

/**
 * WI-011/WI-012/WI-013 · ciclo di vita del catalogo nel browser, con Auth, PostgREST e database veri dello stack E2E
 * dedicato: proposta ESPLICITA dalla Cantina, revisione dal pannello, vino senza LWIN creato e pubblicato, scheda
 * consultabile per UUID senza alcun annuncio; pannello chiuso a chi non è admin; cruscotto onesto su Sentinel.
 *
 * Gli interruttori si accendono solo nello stack di prova e tornano spenti. La pulizia toglie ogni riga creata (anche
 * lo storico, con i trigger spenti): lo spec WI-007 pretende un catalogo vuoto.
 */

const BLOCCA_PROPOSTE = `create or replace function public.wi016_e2e_blocca() returns trigger language plpgsql as
  $$ begin raise exception 'guasto di prova' using errcode = 'P0001'; end $$;
  create or replace trigger wi016_e2e_blocca before insert on catalog.contributions
  for each row execute function public.wi016_e2e_blocca();`;
const SBLOCCA_PROPOSTE = `drop trigger if exists wi016_e2e_blocca on catalog.contributions;
  drop function if exists public.wi016_e2e_blocca();`;

const pulisci = (): string => {
  eseguiSql(SBLOCCA_PROPOSTE);
  eseguiSql(`begin;
  set local session_replication_role = replica;
  update catalog.intake_settings set user_proposals_enabled = false, listing_harvest_enabled = false, auto_close_known_enabled = false;
  update catalog.public_projection_settings set enabled = false;
  delete from public.wine_catalog_selections;
  delete from catalog.contribution_intents;
  delete from catalog.contribution_submissions;
  delete from brain.suspensions;
  delete from brain.market_reviews;
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

  test("WI-016: il consenso dato creando la bottiglia diventa una proposta visibile e ritirabile in Cantina", async ({ browser, diagnostica }, info) => {
    const nomeConsenso = `Consenso E2E ${corsa}`;
    await preparaBottigliaInCantina("venditore", { nome: nomeConsenso, consensoCatalogo: "manuale" });
    const stato = () =>
      leggiDalDatabase(
        `select concat_ws(' ', status, first_origin, submissions_count) from catalog.contributions where identity ->> 'nome' = '${nomeConsenso}';`,
      );
    expect(stato()).toBe("aperta manuale 1");

    const contesto = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const page = await contesto.newPage();
    diagnostica.osserva(page, "venditore");
    await page.goto("/cantina");
    await attendiCaricamento(page);
    const elenco = page.getByTestId("proposte-inviate");
    await elenco.locator("summary").click();
    const voce = elenco.locator("li").filter({ hasText: nomeConsenso });
    await expect(voce).toContainText("In revisione");
    await voce.getByRole("button", { name: "Ritira" }).click();
    await expect(page.getByTestId("proposte-inviate").locator("li").filter({ hasText: nomeConsenso })).toHaveCount(0);
    expect(stato()).toBe("ritirata manuale 0");
    await contesto.close();
  });

  test("WI-016: wizard reale — consenso, pagina chiusa prima della risposta, ritentativo dallo scheduler e revoca", async ({ browser, diagnostica }, info) => {
    const nomeWizard = `Wizard E2E ${corsa}`;
    const stato = () =>
      leggiDalDatabase(
        `select concat_ws(' ',
           (select count(*) from public.bottle_units b join public.wines w on w.id = b.wine_id where w.nome = '${nomeWizard}'),
           (select count(*) from catalog.contribution_intents where data ->> 'nome' = '${nomeWizard}'),
           (select coalesce(string_agg(status, ','), '-') from catalog.contributions where identity ->> 'nome' = '${nomeWizard}'));`,
      );
    // guasto del catalogo SOLO per questa prova: la registrazione diretta fallisce, la bottiglia no
    eseguiSql(BLOCCA_PROPOSTE);

    const { contesto, page } = await apriIdentificazione(browser, "venditore", info, diagnostica);
    await page.getByLabel("Produttore", { exact: true }).fill(PRODUTTORE_E2E);
    await page.getByLabel("Nome / Etichetta", { exact: true }).fill(nomeWizard);
    await page.getByLabel("Annata", { exact: true }).fill("2019");
    await page.getByLabel("Regione (obbligatoria)").click();
    await page.getByRole("option", { name: "Piemonte", exact: true }).click();
    const continua = page.getByRole("button", { name: /Continua/ });
    for (const titolo of ["Condizioni", "Provenienza e conservazione"]) {
      await continua.click();
      await expect(page.getByRole("heading", { name: titolo, exact: true })).toBeVisible();
    }
    await continua.click();
    const consenso = page.getByTestId("wizard-proposta-consenso");
    await expect(consenso).not.toBeChecked();
    await consenso.check();

    // la richiesta arriva DAVVERO al server; la risposta non raggiunge mai la pagina, che viene chiusa
    let consegnata: (corpo: string) => void = () => {};
    const arrivata = new Promise<string>((risolvi) => (consegnata = risolvi));
    // La richiesta resta SENZA risposta: la pagina viene chiusa mentre aspetta, e il client non esegue nulla dopo.
    await page.route("**/rest/v1/rpc/cellar_bottiglie_aggiungi", async (route) => {
      const risposta = await route.fetch();
      consegnata(await risposta.text());
    });
    await page.getByRole("button", { name: "Aggiungi alla cantina privata", exact: true }).click();
    expect(JSON.parse(await arrivata)).toMatchObject({ quantita: 1, catalogo: "in_sospeso" });
    await page.close();
    await contesto.close();
    expect(stato()).toBe("1 1 -");

    // il catalogo torna disponibile: registra il lavoro dello scheduler, senza alcun client aperto
    eseguiSql(SBLOCCA_PROPOSTE);
    eseguiSql("select brain.run_job('proposte_in_sospeso', 'e2e-scheduler');");
    expect(stato()).toBe("1 0 aperta");
    eseguiSql("select brain.run_job('proposte_in_sospeso', 'e2e-scheduler');");
    expect(stato()).toBe("1 0 aperta");

    const dopo = await contestoAutenticato(browser, "venditore", opzioniDelProgetto(info));
    const cantina = await dopo.newPage();
    diagnostica.osserva(cantina, "venditore");
    await cantina.goto("/cantina");
    await attendiCaricamento(cantina);
    const elenco = cantina.getByTestId("proposte-inviate");
    await elenco.locator("summary").click();
    const voce = elenco.locator("li").filter({ hasText: nomeWizard });
    await expect(voce).toContainText("In revisione");
    await voce.getByRole("button", { name: "Ritira" }).click();
    await expect(cantina.getByTestId("proposte-inviate").locator("li").filter({ hasText: nomeWizard })).toHaveCount(0);
    expect(stato()).toBe("1 0 ritirata");

    // revoca PRIMA del ritentativo: l'intenzione cade e lo scheduler non ha più nulla da registrare
    const nomeRevocato = `Revocato E2E ${corsa}`;
    eseguiSql(BLOCCA_PROPOSTE);
    await preparaBottigliaInCantina("venditore", { nome: nomeRevocato, consensoCatalogo: "manuale" });
    eseguiSql(SBLOCCA_PROPOSTE);
    await cantina.reload();
    await attendiCaricamento(cantina);
    await cantina.getByTestId("proposte-inviate").locator("summary").click();
    const inAttesa = cantina.getByTestId("proposte-inviate").locator("li").filter({ hasText: nomeRevocato });
    await expect(inAttesa).toContainText("in attesa di invio");
    await inAttesa.getByRole("button", { name: "Ritira" }).click();
    await expect(cantina.getByTestId("proposte-inviate").locator("li").filter({ hasText: nomeRevocato })).toHaveCount(0);
    eseguiSql("select brain.run_job('proposte_in_sospeso', 'e2e-scheduler');");
    expect(
      leggiDalDatabase(
        `select concat_ws(' ', (select count(*) from catalog.contribution_intents where data ->> 'nome' = '${nomeRevocato}'),
           (select count(*) from catalog.contributions where identity ->> 'nome' = '${nomeRevocato}'));`,
      ),
    ).toBe("0 0");
    await dopo.close();
  });

  test("WI-016: dal Control Center si ferma tutto e si ripristina; il mercato apre solo revisioni", async ({ browser, diagnostica }, info) => {
    const admin = await contestoAutenticato(browser, "adminSenzaRilascio", opzioniDelProgetto(info));
    const page = await admin.newPage();
    diagnostica.osserva(page, "adminSenzaRilascio");
    await page.goto("/admin/azienda");
    await attendiCaricamento(page);
    await page.getByRole("tab", { name: "Controllo" }).click();
    const centro = page.getByTestId("control-center");
    await expect(centro).toContainText("Nessuna sospensione attiva.");
    await expect(centro.getByTestId("protezioni")).toContainText("ricerca_vini: protetta");
    await expect(centro.getByTestId("protezioni")).toContainText("periodo non deciso");
    await expect(centro.getByTestId("ai-configurazione")).toContainText("riserva nessuna");
    await expect(page.getByTestId("kill-switch")).toBeDisabled();
    await centro.getByLabel("Motivo (obbligatorio per sospendere o ripristinare)").fill("Incidente simulato E2E");
    await page.getByTestId("kill-switch").click();
    await expect(page.getByTestId("sospensioni-attive")).toContainText("globale");
    expect(leggiDalDatabase("select brain.is_suspended('ai', 'ai:chat')::text;")).toBe("true");
    await page.getByTestId("control-center").getByLabel("Motivo (obbligatorio per sospendere o ripristinare)").fill("Fine prova E2E");
    await page.getByTestId("kill-switch").click();
    // sessione appena creata: la conferma recente dell'identità è soddisfatta
    await expect(page.getByTestId("control-center")).toContainText("Nessuna sospensione attiva.");
    expect(leggiDalDatabase("select brain.is_suspended('ai', 'ai:chat')::text;")).toBe("false");

    await page.getByRole("tab", { name: "Mercato" }).click();
    const mercato = page.getByTestId("mercato-monitor");
    await expect(mercato).toContainText("non è una classificazione fiscale");
    await mercato.getByRole("button", { name: "Esegui i controlli ora" }).click();
    await expect(mercato).toContainText("Controlli eseguiti");
    await admin.close();
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
    // WI-015: stati dichiarati dal database, mai presentati come operativi
    await expect(page.getByTestId("scheduler")).toContainText("Non pianificato (nessun giro automatico)");
    await expect(page.getByTestId("agenti")).toContainText("Nessun agente registrato.");
    await expect(page.getByTestId("fonti-monitor")).toContainText("Disattivata");
    await expect(page.getByTestId("spesa-ai")).toContainText("non fattura");
    await expect(page.getByTestId("rapporto")).toContainText("Nel periodo:");
    await page.goto("/admin/catalogo");
    await attendiCaricamento(page);
    await page.getByRole("tab", { name: "Fonti e import" }).click();
    await expect(page.getByTestId("aggiornamento-lwin")).toContainText("Conflitti con vini nativi");
    await admin.close();
  });
});
