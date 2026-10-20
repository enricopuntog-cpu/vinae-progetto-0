import { describe, expect, it } from "bun:test";
import {
  chiaveAttributo,
  moduloCategoriaVuoto,
  moduloDaScheda,
  moduloSchedaVuoto,
  validaModuloCategoria,
  validaModuloScheda,
  TRANSIZIONI_STATO,
  type ModuloScheda,
} from "./modulo";

const buono = (extra: Partial<ModuloScheda> = {}): ModuloScheda => ({
  ...moduloSchedaVuoto("cat-1"),
  nome: "Calice di prova",
  slug: "calice-di-prova",
  descrizione: "Descrizione sintetica.",
  ...extra,
});

describe("validaModuloScheda", () => {
  it("compone i dati da inviare, senza alcun campo economico", () => {
    const r = validaModuloScheda(
      buono({
        marchio: " Marchio Prova ",
        quantita: "5",
        attributi: [{ chiave: "Materiale", valore: " cristallo " }],
      }),
    );
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.dati.marchio).toBe("Marchio Prova");
    expect(r.dati.quantita).toBe(5);
    expect(r.dati.attributi).toEqual({ materiale: "cristallo" });
    expect(Object.keys(r.dati).sort()).toEqual([
      "attributi",
      "categoriaId",
      "condizione",
      "descrizione",
      "marchio",
      "nome",
      "quantita",
      "slug",
    ]);
  });

  it("marchio e quantita vuoti diventano null", () => {
    const r = validaModuloScheda(buono());
    expect(r.ok && r.dati.marchio === null && r.dati.quantita === null).toBe(true);
  });

  it("rifiuta categoria assente, nome corto, indirizzo riservato o malformato", () => {
    expect(validaModuloScheda(buono({ categoriaId: "" })).ok).toBe(false);
    expect(validaModuloScheda(buono({ nome: "a" })).ok).toBe(false);
    expect(validaModuloScheda(buono({ slug: "categoria" })).ok).toBe(false);
    expect(validaModuloScheda(buono({ slug: "Calice Rosso" })).ok).toBe(false);
  });

  it("rifiuta quantita negative, decimali, testuali o enormi", () => {
    for (const q of ["-1", "1.5", "abc", "100001", "1e3"]) {
      expect(validaModuloScheda(buono({ quantita: q })).ok).toBe(false);
    }
    expect(validaModuloScheda(buono({ quantita: "0" })).ok).toBe(true);
  });

  it("valida gli attributi: righe vuote ignorate, ripetizioni e oltre 12 rifiutate", () => {
    expect(validaModuloScheda(buono({ attributi: [{ chiave: "", valore: "" }] })).ok).toBe(true);
    expect(validaModuloScheda(buono({ attributi: [{ chiave: "Colore", valore: "" }] })).ok).toBe(false);
    expect(
      validaModuloScheda(
        buono({
          attributi: [
            { chiave: "Colore", valore: "a" },
            { chiave: "colore", valore: "b" },
          ],
        }),
      ).ok,
    ).toBe(false);
    const tredici = Array.from({ length: 13 }, (_, i) => ({
      chiave: `Attributo ${String.fromCharCode(97 + i)}`,
      valore: "v",
    }));
    expect(validaModuloScheda(buono({ attributi: tredici })).ok).toBe(false);
  });

  it("il modulo di una scheda esistente riparte dai suoi valori", () => {
    const m = moduloDaScheda({
      id: "i",
      categoriaId: "c",
      slug: "s-s",
      nome: "N",
      descrizione: "",
      marchio: null,
      condizione: "usato",
      attributi: { materiale: "vetro" },
      immagini: [],
      categoria: { slug: "x", nome: "X", genitoreSlug: null, genitoreNome: null },
      stato: "bozza",
      quantita: null,
      pubblicatoIl: null,
      createdAt: "",
      updatedAt: "",
    });
    expect(m.slugManuale).toBe(true);
    expect(m.attributi).toEqual([{ chiave: "materiale", valore: "vetro" }]);
    expect(m.quantita).toBe("");
  });
});

describe("chiaveAttributo", () => {
  it("normalizza le etichette in chiavi minuscole", () => {
    expect(chiaveAttributo("Capacità (ml)")).toBe("capacita_ml");
    expect(chiaveAttributo("123")).toBe("");
  });
});

describe("validaModuloCategoria", () => {
  it("accetta una categoria ben formata e converte il genitore vuoto in null", () => {
    const r = validaModuloCategoria({ ...moduloCategoriaVuoto(), nome: "Prova", slug: "prova-cat" });
    expect(r.ok && r.dati.genitoreId === null && r.dati.ordine === 100).toBe(true);
  });

  it("rifiuta indirizzo e ordine non validi", () => {
    expect(validaModuloCategoria({ ...moduloCategoriaVuoto(), nome: "Prova", slug: "x" }).ok).toBe(false);
    expect(
      validaModuloCategoria({ ...moduloCategoriaVuoto(), nome: "Prova", slug: "prova-cat", ordine: "-3" }).ok,
    ).toBe(false);
  });
});

describe("TRANSIZIONI_STATO", () => {
  it("rispecchia la macchina a stati del database", () => {
    expect(TRANSIZIONI_STATO.bozza.map((t) => t.verso)).toEqual(["pubblicato"]);
    expect(TRANSIZIONI_STATO.pubblicato.map((t) => t.verso)).toEqual(["bozza", "archiviato"]);
    expect(TRANSIZIONI_STATO.archiviato.map((t) => t.verso)).toEqual(["bozza"]);
  });
});
