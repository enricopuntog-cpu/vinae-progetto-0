import { describe, expect, it } from "bun:test";
import {
  messaggioErroreAccessori,
  nuovoPercorsoImmagine,
  parseCategoria,
  parseCategoriaAdmin,
  parseElenco,
  parseScheda,
  parseSchedaAdmin,
  slugDaNome,
  slugValido,
  urlImmagineAccessorio,
} from "./accessori";

const ID = "11111111-1111-4111-8111-111111111111";
const IMG = "22222222-2222-4222-8222-222222222222";
const PERCORSO = `${ID}/${IMG}.webp`;

const schedaGrezza = (extra: Record<string, unknown> = {}) => ({
  slug: "calice-di-prova",
  nome: "Calice di prova",
  descrizione: "Una descrizione sintetica.",
  marchio: null,
  condizione: "nuovo",
  attributi: { materiale: "cristallo" },
  immagini: [PERCORSO],
  categoria: { slug: "calici", nome: "Calici", genitore_slug: null, genitore_nome: null },
  ...extra,
});

describe("parseScheda", () => {
  it("legge una scheda pubblica ben formata, senza stato", () => {
    const s = parseScheda(schedaGrezza());
    expect(s?.slug).toBe("calice-di-prova");
    expect(s?.stato).toBeNull();
    expect(s?.categoria.genitoreSlug).toBeNull();
  });

  it("legge lo stato solo se presente, e lo rifiuta se inventato", () => {
    expect(parseScheda(schedaGrezza({ stato: "bozza" }))?.stato).toBe("bozza");
    expect(parseScheda(schedaGrezza({ stato: "venduto" }))).toBeNull();
  });

  it("scarta forme non valide invece di indovinarle", () => {
    expect(parseScheda(null)).toBeNull();
    expect(parseScheda([])).toBeNull();
    expect(parseScheda(schedaGrezza({ condizione: "rotto" }))).toBeNull();
    expect(parseScheda(schedaGrezza({ slug: "Maiuscolo" }))).toBeNull();
    expect(parseScheda(schedaGrezza({ attributi: { a: 3 } }))).toBeNull();
    expect(parseScheda(schedaGrezza({ immagini: ["http://evil/x.webp"] }))).toBeNull();
    expect(parseScheda(schedaGrezza({ immagini: Array(7).fill(PERCORSO) }))).toBeNull();
    expect(parseScheda(schedaGrezza({ categoria: { slug: "x" } }))).toBeNull();
  });

  it("non lascia passare campi economici: ignora tutto cio che non conosce", () => {
    const s = parseScheda(schedaGrezza({ prezzo_cents: 1000, valuta: "EUR" })) as Record<string, unknown>;
    expect(s).not.toBeNull();
    expect("prezzo_cents" in s).toBe(false);
    expect("valuta" in s).toBe(false);
  });
});

describe("parseSchedaAdmin", () => {
  const admin = (extra: Record<string, unknown> = {}) =>
    schedaGrezza({
      id: ID,
      categoria_id: IMG,
      stato: "pubblicato",
      quantita: 5,
      pubblicato_il: "2026-10-20T10:00:00Z",
      created_at: "2026-10-20T09:00:00Z",
      updated_at: "2026-10-20T10:00:00Z",
      ...extra,
    });

  it("legge i campi interni", () => {
    const s = parseSchedaAdmin(admin());
    expect(s?.stato).toBe("pubblicato");
    expect(s?.quantita).toBe(5);
  });

  it("accetta quantita e data nulle, rifiuta quantita non intera", () => {
    expect(parseSchedaAdmin(admin({ quantita: null, pubblicato_il: null }))?.quantita).toBeNull();
    expect(parseSchedaAdmin(admin({ quantita: 1.5 }))).toBeNull();
    expect(parseSchedaAdmin(admin({ quantita: "5" }))).toBeNull();
  });

  it("richiede lo stato: una scheda admin senza stato e illeggibile", () => {
    const senza: Record<string, unknown> = admin();
    delete senza.stato;
    expect(parseSchedaAdmin(senza)).toBeNull();
  });
});

describe("categorie", () => {
  it("legge la categoria pubblica con il conteggio", () => {
    expect(
      parseCategoria({ slug: "calici", nome: "Calici", descrizione: "", genitore_slug: null, conteggio: 3 }),
    ).toEqual({ slug: "calici", nome: "Calici", descrizione: "", genitoreSlug: null, conteggio: 3 });
    expect(parseCategoria({ slug: "x", nome: "X" })).toBeNull();
  });

  it("legge la categoria admin", () => {
    const c = parseCategoriaAdmin({
      id: ID,
      genitore_id: null,
      slug: "apertura",
      nome: "Apertura",
      descrizione: "",
      ordine: 10,
      attiva: true,
      accessori: 0,
    });
    expect(c?.attiva).toBe(true);
    expect(parseCategoriaAdmin({ id: ID, slug: "x" })).toBeNull();
  });

  it("parseElenco scarta le voci illeggibili e rifiuta cio che non e un array", () => {
    expect(parseElenco([schedaGrezza(), { rotta: true }], parseScheda)?.length).toBe(1);
    expect(parseElenco({}, parseScheda)).toBeNull();
    expect(parseElenco(null, parseScheda)).toBeNull();
  });
});

describe("immagini e indirizzi", () => {
  it("costruisce l'URL pubblico solo per percorsi della forma attesa", () => {
    expect(urlImmagineAccessorio(PERCORSO, "https://abc.supabase.co")).toBe(
      `https://abc.supabase.co/storage/v1/object/public/accessori-media/${PERCORSO}`,
    );
    expect(urlImmagineAccessorio("../x.webp", "https://abc.supabase.co")).toBeNull();
    expect(urlImmagineAccessorio(`${ID}/foto.webp`, "https://abc.supabase.co")).toBeNull();
    expect(urlImmagineAccessorio(PERCORSO, "javascript:alert(1)")).toBeNull();
    expect(urlImmagineAccessorio(null, "https://abc.supabase.co")).toBeNull();
    expect(urlImmagineAccessorio(PERCORSO, "")).toBeNull();
  });

  it("il nome di un file nuovo sta nella cartella della scheda", () => {
    expect(nuovoPercorsoImmagine(ID, IMG)).toBe(PERCORSO);
    expect(nuovoPercorsoImmagine("non-un-uuid", IMG)).toBeNull();
    expect(nuovoPercorsoImmagine(ID, "../../x")).toBeNull();
  });

  it("slugDaNome toglie accenti e punteggiatura", () => {
    expect(slugDaNome("Calice «Crû» da Rosso!")).toBe("calice-cru-da-rosso");
    expect(slugDaNome("  --  ")).toBe("");
    expect(slugDaNome("a".repeat(120)).length).toBeLessThanOrEqual(80);
  });

  it("slugValido rispetta forma e lunghezza", () => {
    expect(slugValido("calice-rosso")).toBe(true);
    expect(slugValido("ab")).toBe(false);
    expect(slugValido("Calice")).toBe(false);
    expect(slugValido("a--b")).toBe(false);
    expect(slugValido("x".repeat(61), 60)).toBe(false);
  });
});

describe("messaggioErroreAccessori", () => {
  it("traduce gli hint noti", () => {
    expect(messaggioErroreAccessori({ hint: "slug_in_uso" }, "r")).toContain("già usato");
    expect(messaggioErroreAccessori({ hint: "pubblicazione_incompleta" }, "r")).toContain("immagine");
  });

  it("non lascia filtrare messaggi interni", () => {
    expect(
      messaggioErroreAccessori({ code: "XX000", message: "relation private.accessori does not exist" }, "Riprova."),
    ).toBe("Riprova.");
    expect(messaggioErroreAccessori({ code: "42501" }, "r")).toBe("Operazione non consentita.");
  });
});
