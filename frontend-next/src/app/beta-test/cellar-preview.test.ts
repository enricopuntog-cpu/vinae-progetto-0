import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { phaseLabel, THEME_LABELS } from "@/data/cellar";
import {
  MARKET_VALIDATION_CELLAR_BOTTLES,
  MARKET_VALIDATION_CELLAR_REFERENCE_YEAR,
  MARKET_VALIDATION_CELLAR_STATUS_LABEL,
  MARKET_VALIDATION_CELLAR_THEMES,
  MARKET_VALIDATION_CELLAR_VALUE_SERIES,
  marketValidationCellarDrinkWindow,
  marketValidationCellarKpis,
  marketValidationCellarMaturityPercent,
  marketValidationCellarStatusCounts,
  marketValidationCellarThemeLabel,
} from "@/lib/market-validation/cellar-preview";
import {
  marketValidationCanComplete,
  marketValidationProgressPercent,
} from "@/lib/market-validation/mv2-flow";
import { INITIAL_MARKET_VALIDATION_PROGRESS } from "@/lib/market-validation/progress";

const root = resolve(import.meta.dir, "../../../..");
const read = (path: string) => readFileSync(resolve(root, path), "utf8");
const preview = () => read("frontend-next/src/app/beta-test/_components/CellarPreview.tsx");
const hub = () => read("frontend-next/src/app/beta-test/_components/ValidationHub.tsx");
const client = () => read("frontend-next/src/app/beta-test/page-client.tsx");
const data = () => read("frontend-next/src/lib/market-validation/cellar-preview.ts");

describe("card Cantina nell'hub", () => {
  it("sta dopo le quattro card e prima del banner, fuori dai percorsi del test", () => {
    const source = hub();
    const areasStart = source.indexOf("const areas");
    const areas = source.slice(areasStart, source.indexOf("return (", areasStart));
    // «Cantina» compare nella copy di Vendi: qui conta che la card non sia uno step.
    expect(areas).not.toInclude("La tua Cantina");
    expect(areas).not.toInclude("\"cellar\"");

    const grid = source.indexOf("{areas.map((area) => (");
    const card = source.indexOf('onClick={() => onOpen("cellar")}');
    const banner = source.indexOf("Tutto il test si svolge qui");
    expect(grid).toBeGreaterThan(0);
    expect(card).toBeGreaterThan(grid);
    expect(banner).toBeGreaterThan(card);
  });

  it("ha titolo, copy, badge «Scopri» e CTA interna, mai «Obbligatorio»", () => {
    const source = hub();
    const card = source.slice(
      source.indexOf('onClick={() => onOpen("cellar")}'),
      source.indexOf("Tutto il test si svolge qui"),
    );
    expect(card).toInclude("La tua Cantina");
    expect(card).toInclude(">Scopri<");
    expect(card).toInclude(
      "Organizza la tua collezione, decidi quali bottiglie mostrare o vendere e segui nel tempo il valore della Cantina.",
    );
    expect(card).toInclude("Scopri la Cantina");
    expect(card).not.toInclude("Obbligatorio");
    expect(card).not.toInclude("Facoltativo");
    expect(card).not.toInclude("href");
    expect(card).not.toInclude("/cantina");
  });

  it("non tocca il conteggio «0 di 2» né la completion", () => {
    const source = hub();
    expect(source).toInclude("const stepsDone = percent / 50;");
    expect(source).toInclude("{stepsDone} di 2 completati");
    expect(source).toInclude("const completed = marketValidationCanComplete(progress);");
    // La completion dipende solo da acquisto e vendita, qualunque altra cosa sia vista.
    expect(marketValidationCanComplete(INITIAL_MARKET_VALIDATION_PROGRESS)).toBeFalse();
    expect(marketValidationProgressPercent(INITIAL_MARKET_VALIDATION_PROGRESS)).toBe(0);
    expect(read("frontend-next/src/lib/market-validation/progress.ts")).not.toMatch(/cellar|cantina/i);
    expect(read("frontend-next/src/lib/market-validation/mv2-flow.ts")).not.toMatch(/cellar|cantina/i);
  });

  it("apre una schermata interna senza eventi né progressi", () => {
    const source = client();
    const branch = source.slice(
      source.indexOf('if (screen === "cellar")'),
      source.indexOf('if (screen === "ai")'),
    );
    expect(branch).toInclude('<CellarPreview onBack={() => open("hub")} />');
    expect(branch).not.toInclude("track(");
    expect(branch).not.toInclude("updateProgress");
    expect(preview()).not.toInclude("track(");
    expect(preview()).not.toInclude("MarketValidationTrack");
    expect(preview()).not.toInclude("onProgress");
  });
});

describe("anteprima Cantina", () => {
  it("dichiara che i dati sono di esempio e che nulla viene aggiunto", () => {
    const source = preview();
    expect(source).toInclude("Dati di esempio.");
    expect(source).toInclude("Nessuna bottiglia reale viene aggiunta");
    expect(source).toInclude("Dati di esempio, non dati di mercato.");
  });

  it("mostra fra quattro e otto bottiglie d'esempio con gli stati della Cantina reale", () => {
    expect(MARKET_VALIDATION_CELLAR_BOTTLES.length).toBeGreaterThanOrEqual(4);
    expect(MARKET_VALIDATION_CELLAR_BOTTLES.length).toBeLessThanOrEqual(8);
    const statuses = new Set(MARKET_VALIDATION_CELLAR_BOTTLES.map((bottle) => bottle.status));
    expect([...statuses].sort()).toEqual(["cantina_pubblica", "in_vendita", "privata"]);
    expect(MARKET_VALIDATION_CELLAR_STATUS_LABEL).toEqual({
      in_vendita: "In vendita",
      privata: "Solo in Cantina",
      cantina_pubblica: "Visibile nel profilo",
    });
    // Le stesse parole dei badge di /cantina.
    const cantina = read("frontend-next/src/app/cantina/page-client.tsx");
    expect(cantina).toInclude('"Visibile nel profilo"');
    expect(cantina).toInclude(">In vendita<");

    const phases = new Set(MARKET_VALIDATION_CELLAR_BOTTLES.map((bottle) => bottle.phase));
    expect(phases.has("attesa")).toBeTrue();
    expect(phases.has("pronto") || phases.has("ideale")).toBeTrue();
    for (const bottle of MARKET_VALIDATION_CELLAR_BOTTLES) {
      expect(bottle.id.startsWith("mv_cellar_")).toBeTrue();
      expect(bottle.example).toBeTrue();
      expect(Number.isSafeInteger(bottle.referenceValueCents)).toBeTrue();
      expect(bottle.quantity).toBeGreaterThan(0);
    }
    expect(phaseLabel.attesa).toBe("Da attendere");
    expect(phaseLabel.pronto).toBe("Pronto da bere");
  });

  it("deriva i KPI d'esempio dalle bottiglie d'esempio e li etichetta come esempio", () => {
    expect(marketValidationCellarKpis()).toEqual({
      bottles: 10,
      referenceValueCents: 58950,
      forSale: 3,
      readyToDrink: 4,
    });
    const source = preview();
    for (const label of ["Bottiglie", "Valore di riferimento", "In vendita", "Pronte da bere"]) {
      expect(source).toInclude(`label="${label}"`);
    }
    const kpi = source.slice(source.indexOf("function ExampleKpi"));
    expect(kpi.slice(0, kpi.indexOf("\n}\n"))).toInclude(">Esempio<");
  });

  it("chiama la serie «Valore della Cantina nel tempo» e non andamento prezzo", () => {
    const source = preview();
    expect(source).toInclude("Valore della Cantina nel tempo");
    expect(source).not.toMatch(/andamento (del )?prezzo/i);
    expect(source).toInclude("nulla viene ricostruito all&apos;indietro");
    expect(source).toInclude("Esempio: valore della Cantina da");
    const last = MARKET_VALIDATION_CELLAR_VALUE_SERIES.at(-1)!;
    expect(last.valueCents).toBe(marketValidationCellarKpis().referenceValueCents);
    expect(data()).toInclude("non il prezzo di una singola bottiglia né un dato di");
  });

  it("spiega la contabilità con le voci reali, senza inventare fonti", () => {
    const source = preview();
    for (const voce of [
      "valore di riferimento Vinea",
      "capitale noto",
      "incassi trasferiti",
      "la performance",
    ]) {
      expect(source).toInclude(voce);
    }
    // Il dominio chiama la voce «Performance», senza «netta».
    expect(source).not.toMatch(/performance netta/i);
    const dominio = read("frontend-next/src/lib/cantina/presentazione.ts");
    expect(dominio).toInclude(" * Performance: valore corrente più incassi meno capitale noto.");
    expect(dominio).not.toMatch(/performance netta/i);
    const cantina = read("frontend-next/src/app/cantina/page-client.tsx");
    for (const voce of ["Valore di riferimento Vinea", "Capitale noto", "Incassi trasferiti"]) {
      expect(cantina).toInclude(voce);
    }
    expect(source).not.toMatch(/Wine-Searcher|Liv-ex|\baste?\b|quotazion/i);
  });

  it("mostra la finestra di bevuta con i quattro riquadri della Cantina reale", () => {
    expect(marketValidationCellarDrinkWindow()).toEqual({
      drinkNow: 3,
      drinkSoon: 1,
      wait: 2,
      plannedOpenings: 1,
    });
    const source = preview();
    const cantina = read("frontend-next/src/app/cantina/page-client.tsx");
    for (const title of ["Cosa bere adesso", "Da bere presto", "Da attendere", "Aperture programmate"]) {
      expect(source).toInclude(`title="${title}"`);
      expect(cantina).toInclude(`title="${title}"`);
    }
    expect(source).toInclude("La Cantina non è solo un valore");
  });

  it("racconta il 3D con un'immagine d'esempio, senza una finta esperienza 3D", () => {
    expect([...MARKET_VALIDATION_CELLAR_THEMES]).toEqual(["moderna", "classica", "rustica"]);
    expect(MARKET_VALIDATION_CELLAR_THEMES.map(marketValidationCellarThemeLabel)).toEqual([
      THEME_LABELS.moderna,
      THEME_LABELS.classica,
      THEME_LABELS.rustica,
    ]);
    const source = preview();
    expect(source).toInclude("La Cantina può essere organizzata e personalizzata in base al tuo spazio");
    expect(source).toInclude("li arredi e li guardi anche in 3D");
    expect(source).toInclude('src="/images/vinea-cellar.jpg"');
    expect(source).toInclude("Immagine d&apos;esempio");
    expect(source).toInclude("In questa anteprima la vista 3D non è disponibile.");
    // Niente rack interattivo, preset selezionabili o motore 3D.
    for (const removed of [
      "useState<MarketValidationCellarTheme>",
      "aria-pressed={theme === option}",
      "mv-cellar-rack",
      "Cellar3D",
      "three",
      "@react-three",
      "<canvas",
    ]) {
      expect(source).not.toInclude(removed);
    }
    expect(source).not.toMatch(/localStorage|sessionStorage|creaAmbiente|useEnvironmentConfigurator/);
  });

  it("presenta le bottiglie come schede visive consultabili, con filtri e dettaglio", () => {
    const source = preview();
    expect(source).toInclude("<WineThumbnail src={bottle.image}");
    expect(source).toInclude('const [filter, setFilter] = useState<Filter>("tutte")');
    expect(source).toInclude("aria-pressed={filter === option}");
    expect(source).toInclude("onClick={() => setSelected(bottle)}");
    expect(source).toInclude("<CellarBottleDetail bottle={selected} onBack={() => setSelected(null)} />");
    expect(source).toInclude("Tre modi di tenere una bottiglia");
    expect(source).toInclude("Finestra di bevuta");
    expect(marketValidationCellarStatusCounts()).toEqual({ in_vendita: 2, privata: 2, cantina_pubblica: 2 });
    for (const bottle of MARKET_VALIDATION_CELLAR_BOTTLES) {
      expect(existsSync(resolve(root, "frontend-next/public", `.${bottle.image}`))).toBeTrue();
      expect(bottle.drinkTo).toBeGreaterThan(bottle.drinkFrom);
    }
    for (const image of ["vinea-crate.jpg", "vinea-cellar.jpg"]) {
      expect(existsSync(resolve(root, "frontend-next/public/images", image))).toBeTrue();
    }
  });

  it("colloca l'anno di riferimento fisso dentro la finestra di bevuta", () => {
    expect(MARKET_VALIDATION_CELLAR_REFERENCE_YEAR).toBe(2026);
    expect(marketValidationCellarMaturityPercent({ drinkFrom: 2027, drinkTo: 2040 })).toBe(0);
    expect(marketValidationCellarMaturityPercent({ drinkFrom: 2022, drinkTo: 2026 })).toBe(100);
    expect(marketValidationCellarMaturityPercent({ drinkFrom: 2024, drinkTo: 2028 })).toBe(50);
    expect(marketValidationCellarMaturityPercent({ drinkFrom: 2030, drinkTo: 2030 })).toBe(0);
    // La fase dichiarata è coerente con la posizione nella finestra.
    for (const bottle of MARKET_VALIDATION_CELLAR_BOTTLES) {
      const percent = marketValidationCellarMaturityPercent(bottle);
      if (bottle.phase === "attesa") expect(percent).toBe(0);
      if (bottle.phase === "presto") expect(percent).toBe(100);
      if (bottle.phase === "pronto" || bottle.phase === "ideale") {
        expect(percent).toBeGreaterThan(0);
        expect(percent).toBeLessThan(100);
      }
    }
    // L'anteprima non legge l'orologio.
    expect(preview()).not.toMatch(/new Date|Date\.now/);
    expect(data()).not.toMatch(/new Date|Date\.now/);
  });

  it("resta dentro la guida: nessun link alla vera Cantina o al sito", () => {
    const source = preview();
    expect(source).not.toMatch(/<Link\b/);
    expect(source).not.toInclude("next/link");
    expect(source).not.toInclude("href");
    expect(source).not.toInclude("Apri la vera Cantina");
    expect(source).not.toMatch(/registrati|\/accedi/i);
    expect(source).toInclude("<DemoBackButton onBack={onBack} />");
    expect(source).toInclude("Torna al test");
  });

  it("è una preview UI: nessun servizio, store, rete o scrittura", () => {
    for (const source of [preview(), data()]) {
      for (const forbidden of [
        "@/services",
        "@/lib/supabase",
        "useVinea",
        "vinea-store",
        "fetch(",
        "track(",
        "recordEvent",
        "functions.invoke",
        ".insert(",
        ".update(",
        ".upsert(",
        ".rpc(",
        "cellar_preview_viewed",
      ]) {
        expect(source).not.toInclude(forbidden);
      }
    }
    // Dal dominio Cantina arrivano solo etichette e tipi: nessuna funzione o mock.
    const imports = [...data().matchAll(/import \{([^}]+)\} from "@\/data\/cellar"/g)];
    expect(imports).toHaveLength(1);
    const names = imports[0]![1]!.split(",").map((name) => name.trim()).filter(Boolean).sort();
    expect(names).toEqual([
      "THEME_LABELS",
      "phaseLabel",
      "type DrinkPhase",
      "type EnvTheme",
      "type SaleStatus",
    ]);
  });

  it("non aggiunge eventi alla tassonomia", () => {
    const contract = read("frontend-next/src/lib/market-validation/contract.ts");
    expect(contract).not.toInclude("cellar");
    expect(contract).not.toInclude("cantina");
  });
});
