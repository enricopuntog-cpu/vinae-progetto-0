import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { analizzaEvidenze, SEGNALI_AUTENTICITA } from "./analisi";

const base = {
  dichiarato: { produttore: "Cantina Aurelia", annata: 2015 },
  etichetta: { produttore: "", annata: null },
  documentoAcquisto: null,
  fotoNitida: null,
  condizioniDubbie: false,
};

describe("WI-016 — Authenticity Assistant: segnali, mai un verdetto", () => {
  it("senza evidenze nulla è verificato e l'autenticità non è determinabile", () => {
    const r = analizzaEvidenze(base);
    expect(r.identificazione.esito).toBe("non_verificata");
    expect(r.qualitaFoto.esito).toBe("non_valutata");
    expect(r.provenienza.esito).toBe("non_verificata");
    expect(r.segnali).toEqual([]);
    expect(r.autenticita).toEqual({ esito: "non_determinabile", motivo: expect.any(String) });
  });

  it("tutto coerente e documentato: l'autenticità resta comunque non determinabile", () => {
    const r = analizzaEvidenze({ ...base, etichetta: { produttore: "CANTINA  AURÉLIA", annata: 2015 }, documentoAcquisto: true, fotoNitida: true });
    expect(r.identificazione.esito).toBe("coerente");
    expect(r.provenienza.esito).toBe("documentata");
    expect(r.segnali).toEqual([]);
    expect(r.autenticita.esito).toBe("non_determinabile");
  });

  it("incoerenze, foto scadente, mancanza di documenti e condizioni dubbie diventano segnali distinti", () => {
    const r = analizzaEvidenze({
      dichiarato: base.dichiarato,
      etichetta: { produttore: "Tenuta Diversa", annata: 2016 },
      documentoAcquisto: false,
      fotoNitida: false,
      condizioniDubbie: true,
    });
    expect(r.identificazione.esito).toBe("non_coerente");
    expect(r.segnali).toEqual([
      "produttore_non_coerente",
      "annata_non_coerente",
      "qualita_foto_insufficiente",
      "provenienza_non_documentata",
      "condizioni_da_verificare",
    ]);
  });

  it("un nome contenuto nell'altro non è un'incoerenza", () => {
    expect(analizzaEvidenze({ ...base, etichetta: { produttore: "Aurelia", annata: null } }).segnali).toEqual([]);
  });

  it("l'elenco dei segnali coincide con quello chiuso del database", () => {
    const sql = readFileSync(join(import.meta.dir, "../../../../supabase/migrations/20261130120000_wi_016c_orchestrazione_ricerca_agenti.sql"), "utf8");
    for (const s of SEGNALI_AUTENTICITA) expect(sql).toContain(`'${s}'`);
    const dichiarati = sql.match(/anomalie <@ array\[([\s\S]*?)\]::text\[\]/)![1].match(/'([a-z_]+)'/g)!.map((x) => x.slice(1, -1));
    expect([...dichiarati].sort()).toEqual([...SEGNALI_AUTENTICITA].sort());
  });
});
