/**
 * Ciò che WP6B tiene **separato**, misurato sulla sorgente.
 *
 * Il file della migrazione promette, nella sua intestazione, che i nomi
 * commerciali vivono in un solo blocco delimitato e che «un test di guardia
 * verifica che non compaiano altrove». Questo è quel test: senza di esso la
 * promessa sarebbe una frase in un commento.
 *
 * Qui si misurano tre separazioni che nessun test di comportamento vede,
 * perché il codice funzionerebbe comunque:
 *
 *   - il NOME del fornitore è un dato, non un ramo del programma;
 *   - i metadati d'acquisto (pallet, scorta pianificata, riordino, MOQ) non
 *     entrano in nessuna funzione che decide una rotta o la producibilità di
 *     un'etichetta;
 *   - il costo che paghiamo al fornitore non è il contributo di imballaggio
 *     che l'acquirente versa in una transazione.
 *
 * La griglia 12p prova le stesse separazioni a runtime, ma gira solo nel gate
 * con un database effimero. Queste righe girano nel job `frontend-next` a ogni
 * commit, ed è la ragione per cui la duplicazione è voluta.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync, readdirSync } from "node:fs";
import { join, relative } from "node:path";

const repository = join(import.meta.dir, "../../../..");
const progetto = join(import.meta.dir, "../../..");
const leggi = (percorso: string) => readFileSync(join(repository, percorso), "utf8");

const MIGRAZIONE = "supabase/migrations/20260930170000_logistics_beta_routing.sql";
const migrazione = leggi(MIGRAZIONE);

// Un divieto si cerca nel codice, non nella prosa che lo spiega: l'intestazione
// della migrazione *nomina* pallet e scorta pianificata proprio per dire che
// non entrano nelle decisioni di rotta.
const senzaCommentiSql = (sorgente: string) => sorgente.replace(/^\s*--.*$/gm, "");
const senzaCommentiTs = (sorgente: string) =>
  sorgente.replace(/\/\*(?:(?!\*\/)[\s\S])*\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

// I marcatori si ancorano alla riga intera: l'intestazione del file li *cita*
// per spiegare la regola, e cercarli con un `indexOf` nudo ritaglierebbe la
// prosa dell'intestazione invece del blocco in fondo.
const posizione = (marcatore: RegExp) => migrazione.search(marcatore);
const inizioSeed = posizione(/^-- >>> SEED COMMERCIALE BETA$/m);
const fineSeed = posizione(/^-- <<< SEED COMMERCIALE BETA$/m);
const seed = migrazione.slice(inizioSeed, fineSeed);
// Tutto il file tranne il blocco del seme: il taglio tiene dentro
// l'intestazione, che i marcatori li cita.
const fuoriDalSeed = migrazione.slice(0, inizioSeed) + migrazione.slice(fineSeed);

const NOME_FORNITORE = /\bvigoroso\b/i;
const SKU_FORNITORE = /\b(?:OMNIS\d|TRIPLEX\d)/;
const VOCABOLARIO_ACQUISTO = /pallet|\bmoq\b|conai|reorder|planned|supplier/i;

/**
 * Corpo di una funzione SQL: dalla firma alla chiusura del suo `$$`.
 *
 * Fermarsi alla `create` successiva sarebbe sbagliato per l'ultima funzione
 * del file, che si porterebbe dentro i `grant` e l'intero seme commerciale:
 * la guardia leggerebbe il seme come se fosse codice di quella funzione.
 */
const corpoFunzione = (sorgente: string, firma: string): string => {
  const inizio = sorgente.indexOf(firma);
  if (inizio === -1) {
    throw new Error(`Firma assente nella migrazione: ${firma}`);
  }
  const fine = sorgente.indexOf("\n$$;", inizio + firma.length);
  if (fine === -1) {
    throw new Error(`Corpo non terminato per: ${firma}`);
  }
  return sorgente.slice(inizio, fine);
};

/** Ogni funzione di dominio della migrazione, con la sua firma e il suo corpo. */
const funzioniDiDominio = (): { firma: string; corpo: string }[] => {
  const pulita = senzaCommentiSql(migrazione);
  const firme =
    pulita.match(/create\s+or\s+replace\s+function\s+(?:private|public)\.[\w]+/gi) ?? [];
  return [...new Set(firme)].map((firma) => ({ firma, corpo: corpoFunzione(pulita, firma) }));
};

const fileRicorsivi = (directory: string): string[] =>
  readdirSync(directory, { withFileTypes: true }).flatMap((voce) => {
    const percorso = join(directory, voce.name);
    return voce.isDirectory() ? fileRicorsivi(percorso) : [percorso];
  });

const sorgentiFrontend = fileRicorsivi(join(progetto, "src"))
  .filter((file) => /\.tsx?$/.test(file) && !/\.test\.tsx?$/.test(file))
  .map((file) => ({
    nome: relative(progetto, file).replaceAll("\\", "/"),
    sorgente: readFileSync(file, "utf8"),
  }));

describe("WP6B — il fornitore è un dato, non un ramo del programma", () => {
  it("nomina il fornitore e i suoi SKU soltanto dentro il blocco del seme", () => {
    expect(inizioSeed).toBeGreaterThan(-1);
    expect(fineSeed).toBeGreaterThan(inizioSeed);
    expect(NOME_FORNITORE.test(seed)).toBe(true);
    expect(SKU_FORNITORE.test(seed)).toBe(true);
    expect(NOME_FORNITORE.test(fuoriDalSeed)).toBe(false);
    expect(SKU_FORNITORE.test(fuoriDalSeed)).toBe(false);
  });

  it("non confronta mai un codice fornitore o uno SKU con una costante fuori dal seme", () => {
    const pulita = senzaCommentiSql(fuoriDalSeed);
    // `where supplier_code = p_supplier_code` è il contrario di un ramo: legge
    // un parametro. Il difetto da impedire è il confronto con un LETTERALE.
    const confronti = [
      ...pulita.matchAll(/supplier_(?:code|sku)\s*(=|<>|!=|~\*?|in)\s*\(?\s*'([^']*)'/gi),
    ];
    // `check (supplier_code ~ '^[a-z0-9_]{2,40}$')` non è un ramo su un valore:
    // è il vincolo di FORMA della colonna, e deve restare lecito. Tutto il
    // resto — a partire da un `=` su un nome commerciale — non lo è.
    const rami = confronti.filter(
      ([, operatore, letterale]) => !(operatore?.startsWith("~") && letterale?.startsWith("^[")),
    );
    expect(rami.map((m) => m[0])).toEqual([]);
    // E la guardia deve aver guardato: i vincoli di forma esistono.
    expect(confronti.length).toBeGreaterThanOrEqual(3);
  });

  it("risolve lo scaglione senza nominare nessun fornitore", () => {
    const risolutore = corpoFunzione(
      migrazione,
      "create or replace function private.logistics_supplier_tier_risolvi",
    );
    expect(NOME_FORNITORE.test(risolutore)).toBe(false);
    expect(SKU_FORNITORE.test(risolutore)).toBe(false);
    // La quantità minima ordinabile si legge dal profilo: un `50` cablato qui
    // sarebbe una condizione commerciale scritta nel motore.
    expect(risolutore).toContain("v_profilo.moq_units");
    expect(/p_quantity\s*<\s*\d/.test(risolutore)).toBe(false);
  });

  it("non lascia il nome del fornitore né i suoi SKU in nessun sorgente del frontend", () => {
    for (const { nome, sorgente } of sorgentiFrontend) {
      expect(NOME_FORNITORE.test(sorgente), `Nome fornitore in ${nome}`).toBe(false);
      expect(SKU_FORNITORE.test(sorgente), `SKU fornitore in ${nome}`).toBe(false);
    }
  });

  it("non lascia nessun prezzo d'acquisto nel frontend", () => {
    // I cinque primi scaglioni del listino, cercati come sequenza completa:
    // `170` da solo è un numero qualunque, i cinque insieme sono un listino.
    const listino = [170, 199, 206, 369, 300];
    for (const { nome, sorgente } of sorgentiFrontend) {
      const pulito = senzaCommentiTs(sorgente);
      const presenti = listino.filter((prezzo) =>
        new RegExp(`\\b${prezzo}\\b`).test(pulito),
      ).length;
      expect(presenti, `Listino d'acquisto in ${nome}`).toBeLessThan(listino.length);
    }
  });
});

describe("WP6B — i metadati d'acquisto non entrano nella rotta", () => {
  it("tiene il vocabolario d'acquisto fuori da ogni funzione che non sia del fornitore", () => {
    const funzioni = funzioniDiDominio();
    // Una guardia che non guarda niente passerebbe sempre: i conteggi sono
    // esatti perché una migrazione distribuita non cambia più, e se crollassero
    // sarebbe la regex delle firme a essersi rotta, non il codice a essere
    // diventato pulito.
    expect(funzioni.length).toBe(51);
    const diRotta = funzioni.filter(({ firma }) => !/supplier/i.test(firma));
    expect(diRotta).toHaveLength(43);
    for (const { firma, corpo } of diRotta) {
      expect(VOCABOLARIO_ACQUISTO.test(corpo), `Vocabolario d'acquisto in ${firma}`).toBe(false);
    }
  });

  it("non lascia il vocabolario d'acquisto nel contratto corriere né nell'orchestratore", () => {
    for (const percorso of [
      "frontend-next/src/services/logistics/shipment-orchestrator.ts",
      "frontend-next/src/services/logistics/fake-shipment-provider.ts",
      "frontend-next/src/lib/orders/shipping-label.ts",
    ]) {
      const sorgente = senzaCommentiTs(leggi(percorso));
      expect(VOCABOLARIO_ACQUISTO.test(sorgente), `Vocabolario d'acquisto in ${percorso}`).toBe(
        false,
      );
    }
  });

  it("non espone nessuna porta pubblica che legga pallet o scorta pianificata senza essere admin", () => {
    const pulita = senzaCommentiSql(migrazione);
    const porteFornitore =
      pulita.match(/create\s+or\s+replace\s+function\s+public\.\w*supplier\w*/gi) ?? [];
    expect(porteFornitore).toHaveLength(7);
    for (const porta of porteFornitore) {
      const corpo = corpoFunzione(pulita, porta);
      expect(corpo, porta).toContain("private.logistics_admin_richiedi()");
      expect(corpo, porta).toContain("set search_path = ''");
      expect(corpo, porta).toContain("security definer");
    }
    // Nessuna vista espone il dominio d'acquisto: le viste `public_*` sono la
    // superficie anonima del marketplace, e un listino d'acquisto lì sarebbe
    // il costo di fornitura pubblicato.
    expect(/create\s+(or\s+replace\s+)?view\s+public\.\w*supplier/i.test(pulita)).toBe(false);
  });
});

describe("WP6B — il costo d'acquisto non è il contributo di imballaggio", () => {
  it("non scrive nessun contributo di imballaggio nel seme d'acquisto", () => {
    expect(/insert\s+into\s+private\.logistics_packaging_contributions/i.test(seed)).toBe(false);
    // 369 centesimi è insieme il primo scaglione del cartone da sei e un
    // contributo possibile della Beta: proprio perché coincidono, devono
    // restare in due tabelle diverse.
    expect(seed).toContain("logistics_packaging_supplier_price_tiers");
    expect(seed).toContain("369");
  });

  it("non fa dipendere nessun contributo di imballaggio da uno scaglione d'acquisto", () => {
    const pulita = senzaCommentiSql(migrazione);
    const contributo =
      pulita.match(/create\s+or\s+replace\s+function\s+\w+\.\w*packaging_contribution\w*/gi) ?? [];
    expect(contributo).toHaveLength(1);
    for (const firma of contributo) {
      expect(VOCABOLARIO_ACQUISTO.test(corpoFunzione(pulita, firma)), firma).toBe(false);
    }
    // E il contrario: le porte del fornitore non scrivono nel dominio della
    // transazione.
    const pulitaFornitore = (pulita.match(
      /create\s+or\s+replace\s+function\s+public\.\w*supplier\w*/gi,
    ) ?? []).map((firma) => corpoFunzione(pulita, firma));
    for (const corpo of pulitaFornitore) {
      expect(/logistics_packaging_contributions|logistics_unit_economics/i.test(corpo)).toBe(false);
    }
  });

  it("non crea nessuna colonna che possa ospitare un peso del collo pieno non misurato", () => {
    const sezione = senzaCommentiSql(migrazione).match(
      /create\s+table\s+private\.logistics_packaging_supplier_items[\s\S]*?\n\);/i,
    );
    expect(sezione).not.toBeNull();
    const tabella = sezione?.[0] ?? "";
    expect(tabella).toContain("empty_weight_g");
    for (const vietata of [/prudenzial/i, /full_weight/i, /gross_weight/i, /peso_pieno/i]) {
      expect(vietata.test(tabella)).toBe(false);
    }
    // Soglia e quantità di riordino esistono come colonne ma non hanno un
    // `default`: la decisione non è stata presa, e un default la inventerebbe.
    expect(/reorder_threshold\s+integer(?![^,]*default)/i.test(tabella)).toBe(true);
    expect(/reorder_quantity\s+integer(?![^,]*default)/i.test(tabella)).toBe(true);
  });
});
