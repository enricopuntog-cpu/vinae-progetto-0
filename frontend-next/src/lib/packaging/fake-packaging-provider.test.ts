import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  __puntiFintiPerTest,
  createFakePackagingProvider,
} from "@/lib/packaging/fake-packaging-provider";
import type { PackagingOption } from "@/services/types";

const MIGRAZIONE_7C = readFileSync(
  join(
    import.meta.dir,
    "../../../../supabase/migrations/20260804160000_phase_7c_delivery_packaging.sql",
  ),
  "utf8",
);

/**
 * Il sorgente del fake **senza commenti**. La distinzione conta: il commento in
 * testa al file dice «non nomina GEL Proximity, MBE, Nakpack», e una scansione
 * del testo grezzo leggerebbe quella frase come una violazione. Ciò che deve
 * essere pulito è il codice, non la prosa che spiega perché lo è.
 */
const SORGENTE_FAKE = readFileSync(join(import.meta.dir, "fake-packaging-provider.ts"), "utf8")
  .replace(/\/\*[\s\S]*?\*\//g, "")
  .split("\n")
  .filter((riga) => !riga.trimStart().startsWith("//"))
  .join("\n");

const CATALOGO: PackagingOption[] = [
  {
    codice: "kit_domicilio",
    provider: "fake",
    modalita: "kit_a_domicilio",
    etichetta: "Kit a domicilio",
    descrizione: null,
    prezzoCents: 0,
    richiedePunto: false,
  },
  {
    codice: "centro_partner",
    provider: "fake",
    modalita: "centro_partner",
    etichetta: "Centro partner più vicino",
    descrizione: null,
    prezzoCents: 0,
    richiedePunto: true,
  },
  {
    codice: "punto_quartiere",
    provider: "fake",
    modalita: "punto_quartiere",
    etichetta: "Punto di consegna in quartiere",
    descrizione: null,
    prezzoCents: 0,
    richiedePunto: true,
  },
];

const provider = createFakePackagingProvider({ catalogo: CATALOGO });

describe("determinismo", () => {
  it("lo stesso CAP produce sempre la stessa lista di punti", () => {
    expect(__puntiFintiPerTest("20121")).toEqual(__puntiFintiPerTest("20121"));
  });

  it("CAP diversi producono liste diverse", () => {
    const a = __puntiFintiPerTest("20121");
    const b = __puntiFintiPerTest("50122");
    expect(a.map((p) => p.id)).not.toEqual(b.map((p) => p.id));
  });

  it("restituisce fra 4 e 6 punti", () => {
    for (const cap of ["20121", "50122", "10121", "00184", "80133", "37121"]) {
      const punti = __puntiFintiPerTest(cap);
      expect(punti.length).toBeGreaterThanOrEqual(4);
      expect(punti.length).toBeLessThanOrEqual(6);
    }
  });

  it("un CAP malformato ricade sul predefinito invece di rompersi", () => {
    expect(__puntiFintiPerTest("non-un-cap")).toEqual(__puntiFintiPerTest("20121"));
    expect(__puntiFintiPerTest(null)).toEqual(__puntiFintiPerTest("20121"));
  });

  it("gli id sono unici dentro una stessa lista", () => {
    const ids = __puntiFintiPerTest("20121").map((p) => p.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it("non inventa città e provincia, che da un CAP non sono derivabili", () => {
    for (const punto of __puntiFintiPerTest("20121")) {
      expect(punto.citta).toBe("");
      expect(punto.provincia).toBe("");
    }
  });
});

describe("opzioni e punti", () => {
  it("offre solo ciò che il catalogo contiene: non inventa opzioni", async () => {
    const esito = await provider.opzioniDisponibili({ near: null, formato: null, quantita: 1 });
    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data.map((o) => o.codice).sort()).toEqual(
      CATALOGO.map((o) => o.codice).sort(),
    );
  });

  it("con catalogo vuoto non offre nulla", async () => {
    const vuoto = createFakePackagingProvider({ catalogo: [] });
    const esito = await vuoto.opzioniDisponibili({ near: null, formato: null, quantita: 1 });
    expect(esito.ok && esito.data).toEqual([]);
  });

  it("un'opzione che non richiede punto non ne restituisce", async () => {
    const esito = await provider.puntiVicini({ codice: "kit_domicilio", cap: "20121" });
    expect(esito.ok && esito.data).toEqual([]);
  });

  it("un'opzione che richiede punto ne restituisce", async () => {
    const esito = await provider.puntiVicini({ codice: "centro_partner", cap: "20121" });
    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data.length).toBeGreaterThan(0);
  });

  it("un codice sconosciuto è un errore, non una lista vuota", async () => {
    const esito = await provider.puntiVicini({ codice: "non_esiste", cap: "20121" });
    expect(esito.ok).toBe(false);
  });
});

describe("prenota", () => {
  it("restituisce un riferimento riconoscibile come finto", async () => {
    const esito = await provider.prenota({
      codice: "kit_domicilio",
      puntoId: null,
      riferimentoOrdine: "ord-1",
    });
    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data.provider).toBe("fake");
    expect(esito.data.prenotazioneId).toContain("FAKE-");
  });

  it("rifiuta una modalità con punto obbligatorio senza punto", async () => {
    const esito = await provider.prenota({
      codice: "centro_partner",
      puntoId: null,
      riferimentoOrdine: "ord-1",
    });
    expect(esito.ok).toBe(false);
  });
});

describe("il fake resta finto", () => {
  it("non contiene alcuna chiamata di rete", () => {
    expect(SORGENTE_FAKE).not.toMatch(/\bfetch\s*\(/);
    expect(SORGENTE_FAKE).not.toMatch(/XMLHttpRequest|WebSocket|axios/);
    expect(SORGENTE_FAKE).not.toMatch(/https?:\/\//);
  });

  it("non nomina alcun fornitore reale", () => {
    // Confini di parola, non sottostringhe: «mbe» sta dentro `number` e «gel»
    // starebbe dentro mille parole italiane. Un test che fallisce su `number`
    // non sta proteggendo l'invariante, sta solo rumoreggiando.
    for (const nome of ["gel", "proximity", "mbe", "nakpack", "bartolini", "poste", "dhl"]) {
      expect(SORGENTE_FAKE).not.toMatch(new RegExp(`\\b${nome}\\b`, "i"));
    }
  });

  it("non contiene prezzi: il listino è dato autoritativo del server", () => {
    // Nessuna cifra seguita da `Cents` o assegnata a un campo di prezzo.
    expect(SORGENTE_FAKE).not.toMatch(/prezzoCents\s*[:=]\s*\d/);
    expect(SORGENTE_FAKE).not.toMatch(/prezzo_cents/);
  });
});

describe("coerenza con la migrazione 7c", () => {
  it("i tre codici del seed sono quelli che il catalogo di prova usa", () => {
    for (const opzione of CATALOGO) {
      expect(MIGRAZIONE_7C).toContain(`'${opzione.codice}'`);
    }
  });

  it("il seed della migrazione semina prezzi a zero, come deciso", () => {
    const seed = MIGRAZIONE_7C.slice(
      MIGRAZIONE_7C.indexOf("insert into public.packaging_options"),
      MIGRAZIONE_7C.indexOf("comment on table public.packaging_options"),
    );
    // Tre righe di seed, ognuna con il prezzo a 0 prima dei due flag finali.
    expect(seed.match(/\n\s+0, (?:false|true), \d+\)/g)?.length).toBe(3);
  });

  it("le tre modalità del TypeScript sono quelle ammesse dal CHECK in SQL", () => {
    expect(MIGRAZIONE_7C).toContain(
      "check (modalita in ('kit_a_domicilio', 'centro_partner', 'punto_quartiere'))",
    );
  });
});
