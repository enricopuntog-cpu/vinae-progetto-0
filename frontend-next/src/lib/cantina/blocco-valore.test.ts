import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * Il blocco valore della Cantina: dove sta nella pagina e come è fatto.
 *
 * Il lavoro è collocazione e gerarchia, non nuova analitica: le stesse quattro
 * voci e la stessa serie di D3-B, lette dagli stessi helper. Queste prove
 * fissano l'ordine delle sezioni e il fatto che nessun numero nasca qui.
 */
const progetto = join(import.meta.dir, "../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");
const senzaCommenti = (sorgente: string) =>
  sorgente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

const PAGINA = leggi("src/app/cantina/page-client.tsx");
const GRAFICO = leggi("src/components/vinea/ValoreNelTempo.tsx");

describe("ordine delle sezioni di Cantina", () => {
  const codice = senzaCommenti(PAGINA);

  it("mette il valore dopo l'elenco bottiglie e prima di «Cosa bere adesso»", () => {
    const elenco = codice.indexOf('<Tabs defaultValue="tutte">');
    const valore = codice.indexOf("<ContabilitaCantina");
    const cosaBere = codice.indexOf("Cosa bere adesso");
    expect(elenco).toBeGreaterThan(-1);
    expect(valore).toBeGreaterThan(elenco);
    expect(cosaBere).toBeGreaterThan(valore);
  });

  it("il blocco resta uno solo: non è stato copiato, è stato spostato", () => {
    expect(codice.split("<ContabilitaCantina").length - 1).toBe(1);
  });
});

describe("gerarchia del blocco valore", () => {
  const blocco = senzaCommenti(PAGINA).slice(
    senzaCommenti(PAGINA).indexOf("function ContabilitaCantina"),
  );

  it("dà un solo numero principale, e gli altri tre restano di supporto", () => {
    // Il totale è l'unico in font grande; le tre voci di dettaglio stanno in
    // una `<dl>` sotto, non in quattro caselle tutte uguali.
    expect(blocco).toInclude('id="contabilita-cantina"');
    expect(blocco).toMatch(/font-serif text-4xl[^"]*"[\s\S]{0,60}\{valore\.valore\}/);
    expect(blocco).toInclude("<dl");
    expect(blocco).toInclude("<dt");
    expect(blocco).toInclude("<dd");
  });

  it("conserva le quattro voci di D3-B con le stesse etichette", () => {
    for (const etichetta of [
      "Valore di riferimento Vinea",
      "Capitale noto",
      "Incassi trasferiti",
      "Performance netta",
    ]) {
      expect(blocco).toInclude(etichetta);
    }
    for (const voce of [
      "voceValoreRiferimento(analitica)",
      "voceCapitaleNoto(analitica)",
      "voceIncassiTrasferiti(analitica)",
      "vocePerformance(analitica)",
    ]) {
      expect(blocco).toInclude(voce);
    }
  });

  it("mostra la tendenza solo dove esiste un segno, mai un pareggio inventato", () => {
    expect(blocco).toInclude("analitica.performanceCents === null");
    expect(blocco).toInclude("analitica.performanceCents >= 0");
    expect(blocco).toInclude("{segno && (");
    expect(blocco).toInclude("<TrendingUp");
    expect(blocco).toInclude("<TrendingDown");
  });

  it("non introduce numeri, serie o fornitori che il dato non ha", () => {
    expect(blocco).not.toMatch(
      /\+\d+(?:[.,]\d+)?%|ultimi 12 mesi|ANDAMENTO|Math\.(random|pow)|new Date\(\)|fetch\(|\.from\(/,
    );
    // Nessun calcolo nuovo: il blocco legge l'analitica, non la rifà.
    expect(blocco).not.toMatch(/Cents \* |Cents \/ |reduce\(/);
  });

  it("lo stato mancante resta un blocco che parla, non uno zero", () => {
    expect(blocco).toInclude("Contabilità non disponibile");
    expect(blocco).toInclude("restano tutte qui sotto.");
  });
});

describe("grafico dentro la cornice della contabilità", () => {
  it("perde il bordo proprio senza perdere sezione, titolo e tabella", () => {
    expect(senzaCommenti(PAGINA)).toInclude("incorniciato={false}");
    expect(GRAFICO).toInclude("incorniciato = true");
    expect(GRAFICO).toInclude(
      'incorniciato ? "rounded-2xl border border-border bg-card p-4 md:p-6" : undefined',
    );
    expect(GRAFICO).toInclude('aria-labelledby="valore-nel-tempo"');
    expect(GRAFICO).toInclude("<table");
  });

  it("mantiene i tre stati della serie, compreso il punto singolo", () => {
    expect(GRAFICO).toInclude('stato === "vuota"');
    expect(GRAFICO).toInclude('stato === "osservazione_unica"');
    expect(GRAFICO).toInclude("puntiGrafico(serie)");
  });
});
