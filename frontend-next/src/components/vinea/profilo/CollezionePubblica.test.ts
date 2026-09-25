import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";

const sorgente = readFileSync(new URL("./CollezionePubblica.tsx", import.meta.url), "utf8");
const codice = sorgente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

describe("CollezionePubblica", () => {
  it("disegna davvero entrambe le viste con la stessa proiezione pubblica", () => {
    expect(codice).toInclude('vista === "griglia"');
    expect(codice).toInclude('variante={vista}');
    expect(codice).toInclude('data-testid={`cantina-pubblica-vista-${vista}`}');
    expect(codice).toInclude("grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3");
    expect(codice).toInclude("grid grid-cols-1 gap-3");
  });

  it("usa collegamenti accessibili per cambiare vista senza stato client", () => {
    expect(sorgente).not.toInclude('"use client"');
    expect(codice).not.toMatch(/useState|useEffect|onClick/);
    expect(codice).toInclude('role="group"');
    expect(codice).toInclude('aria-label="Vista della collezione"');
    expect(codice).toInclude('aria-label="Mostra come griglia"');
    expect(codice).toInclude('aria-label="Mostra come elenco"');
    expect(codice).toInclude('aria-current={vista === "griglia" ? "page" : undefined}');
  });

  it("naviga fra pagine conservando la vista scelta", () => {
    expect(codice).toInclude('aria-label="Pagine della collezione"');
    expect(codice).toInclude("pagina: pagina - 1");
    expect(codice).toInclude("pagina: pagina + 1");
    expect(codice).toInclude('rel="prev"');
    expect(codice).toInclude('rel="next"');
    expect(codice).toInclude("{pagina > 1 ? (");
    expect(codice).toInclude("{altraPagina && (");
  });

  it("non confonde una pagina oltre la fine con una Cantina riservata", () => {
    expect(codice).toInclude("pagina === 1 ? (");
    expect(codice).toInclude("<CantinaVuota />");
    expect(codice).toInclude("Nessuna bottiglia in questa pagina");
    expect(codice).toInclude("Torna alla pagina precedente");
  });

  it("espone il flusso normale solo quando i pagamenti sono abilitati e non è il proprietario", () => {
    expect(codice).toInclude("PAGAMENTI_UI_ABILITATI && !profiloProprio");
    expect(codice).toInclude("compraOra={mostraCompraOra}");
    expect(codice).not.toMatch(/PaymentService|OrderService|prenot|riserv|carrell/i);
  });

  it("non apre il dominio privato né introduce una terza vista", () => {
    expect(codice).not.toMatch(
      /CellarService|createCellarService|useCellar|bottle_units|cellar_environments|cellar_modules|cellar_slots|Cellar3D/,
    );
    expect(codice).not.toMatch(/note_personali|apertura_pianificata|degustazione|acquisition|prezzo_visibilita/);
    expect(codice).not.toMatch(/vista[^\n]*3d|follow|notific|valore/i);
  });

  it("non costruisce controlli interattivi annidati", () => {
    expect(codice).not.toMatch(/<Link[^>]*>[\s\S]*?<button/i);
    expect(codice).not.toMatch(/<button[^>]*>[\s\S]*?<Link/i);
    expect(codice).not.toMatch(/min-w-\[|w-\[\d|overflow-x/);
  });
});
