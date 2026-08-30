import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * L'ordine delle sezioni nella scheda annuncio.
 *
 * Chi apre la scheda sta guardando una bottiglia: quando aprirla e con che cosa
 * berla vengono prima del contesto di prezzo. Price Intelligence resta lo stesso
 * pannello di prima — stessa vista, stessi dati D3 — e quello che è cambiato è
 * soltanto dove sta nella pagina. Questa prova fissa la posizione, così un
 * riordino successivo non la riporta in cima senza che nessuno se ne accorga.
 */
const progetto = join(import.meta.dir, "../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");
const senzaCommenti = (sorgente: string) =>
  sorgente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

const PAGINA = senzaCommenti(leggi("src/app/annuncio/[id]/page-client.tsx"));

describe("ordine delle sezioni della scheda annuncio", () => {
  it("mette «quando berlo» e gli abbinamenti prima di Price Intelligence", () => {
    const quandoBerlo = PAGINA.indexOf("<DrinkWindowSection");
    const abbinamenti = PAGINA.indexOf("<FoodPairingSection");
    const prezzi = PAGINA.indexOf("<PriceIntelligencePanel");

    expect(quandoBerlo).toBeGreaterThan(-1);
    expect(abbinamenti).toBeGreaterThan(quandoBerlo);
    expect(prezzi).toBeGreaterThan(abbinamenti);
  });

  it("il pannello prezzi è uno solo: è stato spostato, non copiato", () => {
    expect(PAGINA.split("<PriceIntelligencePanel").length - 1).toBe(1);
    expect(PAGINA.split("<DrinkWindowSection").length - 1).toBe(1);
    expect(PAGINA.split("<FoodPairingSection").length - 1).toBe(1);
  });

  it("lo spostamento non tocca la vista che il pannello riceve", () => {
    // Stessa prop, stessa sorgente: il riordino è di layout e nient'altro.
    expect(PAGINA).toInclude("<PriceIntelligencePanel vista={vistaPrezzi} />");
  });

  it("le due sezioni restano indicizzate per vino e non per annuncio", () => {
    // Su dati reali `id` è lo slug dell'annuncio: cercare per quello non
    // troverebbe nulla. Il riordino non doveva cambiare la chiave, e non l'ha
    // cambiata.
    expect(PAGINA).toInclude("<DrinkWindowSection wineId={wine.wineSlug ?? wine.id} />");
    expect(PAGINA).toInclude("<FoodPairingSection wineId={wine.wineSlug ?? wine.id} />");
  });
});
