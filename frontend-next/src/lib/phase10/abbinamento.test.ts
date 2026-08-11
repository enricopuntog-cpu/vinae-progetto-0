import { describe, expect, it } from "bun:test";
import { risolviScelte } from "@/lib/phase10/abbinamento";
import type { Wine } from "@/data/wines";

const UUID_A = "10000000-0000-4000-8000-00000000000a";
const UUID_B = "10000000-0000-4000-8000-00000000000b";

const annuncio = (id: string, listingId?: string): Wine => ({
  id,
  listingId,
  detailHref: `/annuncio/${id}`,
  produttore: "Giacomo Conterno",
  nome: "Monfortino",
  annata: 2015,
  regione: "Piemonte",
  denominazione: "Barolo DOCG",
  tipo: "Rosso",
  formato: "0,75 L",
  prezzo: 1180,
  condizione: "Perfetto",
  conservazione: "Cantina a 14°C",
  venditore: {
    nome: "Marco B.",
    citta: "Alba (CN)",
    rating: 4.9,
    valutazioni: 127,
    verificato: true,
    avatar: "",
  },
  immagini: [],
  storia: "",
  degustazione: "",
  disponibili: 1,
  tag: [],
  createdAt: "2026-07-14",
});

describe("risoluzione degli abbinamenti proposti dall'AI", () => {
  it("risolve per UUID, che è ciò che la function propone dopo la 7.8", () => {
    // `public_listings.id` è la chiave primaria; nel frontend `Wine.id` è lo
    // slug e l'UUID sta in `listingId`. Cercare per `id` non troverebbe nulla.
    const annunci = [annuncio("monfortino-2015", UUID_A), annuncio("tignanello-2019", UUID_B)];
    const risolte = risolviScelte(
      [{ annuncioId: UUID_B, motivazione: "Regge il brasato." }],
      annunci,
    );

    expect(risolte).toHaveLength(1);
    expect(risolte[0].annuncio.id).toBe("tignanello-2019");
    expect(risolte[0].motivazione).toBe("Regge il brasato.");
  });

  it("risolve anche per slug, se un giorno la function proponesse quello", () => {
    const annunci = [annuncio("monfortino-2015", UUID_A)];
    const risolte = risolviScelte([{ annuncioId: "monfortino-2015", motivazione: "x" }], annunci);
    expect(risolte).toHaveLength(1);
  });

  it("lascia cadere un identificativo che non corrisponde a nessun annuncio", () => {
    // Fra la lettura del catalogo dentro la function e questa pagina passa il
    // tempo di una richiesta: un annuncio può essere stato ritirato nel mezzo,
    // e una scheda vuota sarebbe peggio di una scheda in meno.
    const risolte = risolviScelte(
      [
        { annuncioId: UUID_A, motivazione: "c'è" },
        { annuncioId: "10000000-0000-4000-8000-0000000000ff", motivazione: "non c'è" },
      ],
      [annuncio("monfortino-2015", UUID_A)],
    );
    expect(risolte).toHaveLength(1);
    expect(risolte[0].motivazione).toBe("c'è");
  });

  it("non mostra due volte lo stesso annuncio", () => {
    const annunci = [annuncio("monfortino-2015", UUID_A)];
    const risolte = risolviScelte(
      [
        { annuncioId: UUID_A, motivazione: "prima" },
        { annuncioId: "monfortino-2015", motivazione: "stesso annuncio per slug" },
      ],
      annunci,
    );
    expect(risolte).toHaveLength(1);
    expect(risolte[0].motivazione).toBe("prima");
  });

  it("conserva l'ordine proposto dal modello", () => {
    const annunci = [annuncio("primo", UUID_A), annuncio("secondo", UUID_B)];
    const risolte = risolviScelte(
      [
        { annuncioId: UUID_B, motivazione: "b" },
        { annuncioId: UUID_A, motivazione: "a" },
      ],
      annunci,
    );
    expect(risolte.map((s) => s.annuncio.id)).toEqual(["secondo", "primo"]);
  });

  it("un annuncio senza listingId (dati mock) resta risolvibile per id", () => {
    const risolte = risolviScelte(
      [{ annuncioId: "monfortino-2015", motivazione: "x" }],
      [annuncio("monfortino-2015")],
    );
    expect(risolte).toHaveLength(1);
  });

  it("nessuna scelta dà nessun risultato, senza sollevare", () => {
    expect(risolviScelte([], [annuncio("monfortino-2015", UUID_A)])).toEqual([]);
    expect(risolviScelte([{ annuncioId: UUID_A, motivazione: "x" }], [])).toEqual([]);
  });
});
