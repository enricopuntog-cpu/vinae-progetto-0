import { describe, expect, it } from "bun:test";
import {
  etichettaCategoria,
  messaggioErroreCantinaAccessori,
  moduloCantinaVuoto,
  moduloDaAccessorio,
  nuovoPercorsoFoto,
  parseAccessorioPersonale,
  parseAccessorioPubblico,
  parseCategoriaTassonomia,
  parseRimozione,
  parseStatoCantinaAccessori,
  parseStatoInterruttori,
  percorsoFotoValido,
  sceltePerCategoria,
  validaModuloCantina,
} from "./cantina-accessori";

const U1 = "11111111-1111-4111-8111-111111111111";
const U2 = "22222222-2222-4222-8222-222222222222";
const U3 = "33333333-3333-4333-8333-333333333333";
const U4 = "44444444-4444-4444-8444-444444444444";
const FOTO = `${U1}/${U2}/${U3}.webp`;

const personale = (extra: Record<string, unknown> = {}) => ({
  id: U2,
  nome: "Calice di prova",
  descrizione: "Descrizione",
  marchio: null,
  condizione: "usato",
  quantita: 3,
  note: "nota privata",
  immagini: [FOTO],
  visibilita: "privata",
  archiviato: false,
  catalogo_slug: null,
  categoria: {
    id: U4,
    slug: "calici-da-rosso",
    nome: "Calici da rosso",
    genitore_id: U3,
    genitore_slug: "calici",
    genitore_nome: "Calici",
  },
  created_at: "2026-10-21T10:00:00Z",
  updated_at: "2026-10-21T10:00:00Z",
  ...extra,
});

describe("parseAccessorioPersonale", () => {
  it("legge un accessorio del proprietario, con note e visibilità", () => {
    const a = parseAccessorioPersonale(personale());
    expect(a?.nome).toBe("Calice di prova");
    expect(a?.note).toBe("nota privata");
    expect(a?.visibilita).toBe("privata");
    expect(a?.categoria.genitoreNome).toBe("Calici");
  });

  it.each([
    ["quantità zero", { quantita: 0 }],
    ["quantità oltre il tetto", { quantita: 1000 }],
    ["quantità non intera", { quantita: 1.5 }],
    ["condizione ignota", { condizione: "rotto" }],
    ["visibilità ignota", { visibilita: "pubblica" }],
    ["foto con forma errata", { immagini: ["x/y.webp"] }],
    ["più di quattro foto", { immagini: [FOTO, FOTO, FOTO, FOTO, FOTO] }],
    ["archiviato non booleano", { archiviato: "no" }],
    ["id non uuid", { id: "abc" }],
  ])("scarta: %s", (_etichetta, extra) => {
    expect(parseAccessorioPersonale(personale(extra))).toBeNull();
  });

  it("scarta un valore che non è un oggetto", () => {
    expect(parseAccessorioPersonale(null)).toBeNull();
    expect(parseAccessorioPersonale([])).toBeNull();
    expect(parseAccessorioPersonale("x")).toBeNull();
  });
});

describe("parseAccessorioPubblico", () => {
  const pubblico = (extra: Record<string, unknown> = {}) => ({
    id: U2,
    nome: "Cavatappi",
    descrizione: "",
    marchio: "Marca",
    condizione: "come_nuovo",
    quantita: 1,
    immagini: [],
    categoria_slug: "cavatappi",
    categoria_nome: "Cavatappi",
    genitore_nome: "Apertura",
    ...extra,
  });

  it("legge la forma chiusa e NON riporta mai note, proprietario o legami anche se arrivassero", () => {
    const a = parseAccessorioPubblico(
      pubblico({ note: "segreto", owner_id: U1, catalogo_slug: "x", visibilita: "privata" }),
    );
    expect(a).not.toBeNull();
    expect(Object.keys(a ?? {}).sort()).toEqual([
      "categoriaNome", "categoriaSlug", "condizione", "descrizione", "genitoreNome", "id",
      "immagini", "marchio", "nome", "quantita",
    ]);
    expect(JSON.stringify(a)).not.toContain("segreto");
  });

  it("scarta le forme non valide", () => {
    expect(parseAccessorioPubblico(pubblico({ quantita: "3" }))).toBeNull();
    expect(parseAccessorioPubblico(pubblico({ condizione: "x" }))).toBeNull();
    expect(parseAccessorioPubblico(pubblico({ categoria_slug: null }))).toBeNull();
  });
});

describe("tassonomia e scelte", () => {
  const tassonomia = [
    parseCategoriaTassonomia({
      id: U1, slug: "calici", nome: "Calici",
      sottocategorie: [{ id: U2, slug: "calici-da-rosso", nome: "Calici da rosso" }],
    }),
    parseCategoriaTassonomia({ id: U3, slug: "pulizia", nome: "Pulizia", sottocategorie: [] }),
  ].flatMap((c) => (c ? [c] : []));

  it("offre la sottocategoria dove esiste e la categoria dove è foglia, mai una categoria con figli", () => {
    const scelte = sceltePerCategoria(tassonomia);
    expect(scelte.map((s) => s.id)).toEqual([U2, U3]);
    expect(scelte[0].gruppo).toBe("Calici");
    expect(scelte[1].gruppo).toBeNull();
  });

  it("scarta una tassonomia malformata", () => {
    expect(parseCategoriaTassonomia({ id: U1, slug: "x", nome: "X", sottocategorie: [{ id: "no" }] })).toBeNull();
    expect(parseCategoriaTassonomia({ id: U1, slug: "x", nome: "X" })).toBeNull();
  });

  it("compone l'etichetta della categoria", () => {
    const a = parseAccessorioPersonale(personale());
    expect(a && etichettaCategoria(a.categoria)).toBe("Calici · Calici da rosso");
  });
});

describe("foto", () => {
  it("accetta solo <proprietario>/<accessorio>/<foto>.webp", () => {
    expect(percorsoFotoValido(FOTO)).toBe(true);
    expect(percorsoFotoValido(`${U2}/${U3}.webp`)).toBe(false);
    expect(percorsoFotoValido(`${FOTO}.png`)).toBe(false);
    expect(percorsoFotoValido(`../${FOTO}`)).toBe(false);
    expect(percorsoFotoValido(null)).toBe(false);
  });

  it("compone un percorso nuovo solo con tre uuid validi", () => {
    expect(nuovoPercorsoFoto(U1, U2, U3)).toBe(FOTO);
    expect(nuovoPercorsoFoto(U1, "x", U3)).toBeNull();
    expect(nuovoPercorsoFoto("../", U2, U3)).toBeNull();
  });
});

describe("stati e rimozione", () => {
  it("legge lo stato per l'utente e quello degli interruttori", () => {
    expect(parseStatoCantinaAccessori({ abilitata: true, esposti_visibili: false })).toEqual({
      abilitata: true, espostiVisibili: false,
    });
    expect(parseStatoCantinaAccessori({ abilitata: "true" })).toBeNull();
    expect(
      parseStatoInterruttori({
        funzione_attiva: true, visibilita_pubblica: false, catalogo_visibile: false, puo_rilasciare: true,
      }),
    ).toEqual({ funzioneAttiva: true, visibilitaPubblica: false, catalogoVisibile: false, puoRilasciare: true });
    expect(parseStatoInterruttori({ funzione_attiva: true })).toBeNull();
  });

  it("legge i percorsi restituiti dalla rimozione, solo se rimosso", () => {
    expect(parseRimozione({ rimosso: true, percorsi: [FOTO] })).toEqual([FOTO]);
    expect(parseRimozione({ rimosso: false, percorsi: [] })).toBeNull();
    expect(parseRimozione({ rimosso: true, percorsi: ["x"] })).toBeNull();
  });
});

describe("modulo", () => {
  const valide = new Set([U4]);

  it("un modulo vuoto non passa e segnala tipo e nome", () => {
    const r = validaModuloCantina(moduloCantinaVuoto(), valide);
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(Object.keys(r.errori).sort()).toEqual(["categoriaId", "nome"]);
    }
  });

  it("produce i dati per la porta, ripuliti e senza proprietario", () => {
    const r = validaModuloCantina(
      { ...moduloCantinaVuoto(), categoriaId: U4, nome: "  Calice  ", quantita: "4", marchio: " ", note: " n " },
      valide,
    );
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.dati).toEqual({
        categoriaId: U4, nome: "Calice", descrizione: "", marchio: null, condizione: "usato",
        quantita: 4, note: "n", catalogoSlug: null,
      });
      expect(Object.keys(r.dati)).not.toContain("ownerId");
    }
  });

  it.each(["0", "1000", "1.5", "", "abc", "-2"])("rifiuta la quantità %p", (q) => {
    const r = validaModuloCantina({ ...moduloCantinaVuoto(), categoriaId: U4, nome: "Prova", quantita: q }, valide);
    expect(r.ok).toBe(false);
  });

  it("rifiuta una categoria fuori dalla tassonomia", () => {
    const r = validaModuloCantina({ ...moduloCantinaVuoto(), categoriaId: U1, nome: "Prova" }, valide);
    expect(r.ok).toBe(false);
  });

  it("riporta un accessorio nel modulo", () => {
    const a = parseAccessorioPersonale(personale({ marchio: "M" }));
    expect(a && moduloDaAccessorio(a)).toMatchObject({ categoriaId: U4, quantita: "3", marchio: "M" });
  });
});

describe("messaggi di errore", () => {
  it("traduce gli hint noti e non rivela dettagli interni", () => {
    expect(messaggioErroreCantinaAccessori({ hint: "sottocategoria_obbligatoria" }, "x")).toContain("sottocategoria");
    expect(messaggioErroreCantinaAccessori({ hint: "funzione_non_attiva" }, "x")).toContain("non è ancora attiva");
    expect(messaggioErroreCantinaAccessori({ code: "42501" }, "x")).toBe("Operazione non consentita.");
    expect(messaggioErroreCantinaAccessori({ code: "XX000", message: "relation private.x" }, "ricaduta")).toBe("ricaduta");
    expect(messaggioErroreCantinaAccessori(null, "ricaduta")).toBe("ricaduta");
  });
});
