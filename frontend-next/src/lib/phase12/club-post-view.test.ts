import { describe, expect, it } from "bun:test";
import {
  ETICHETTE_TIPO_POST,
  LIMITI_POST,
  TIPI_POST,
  filtraPostPerTipo,
  ordinaPerPopolarita,
  tipiPresenti,
  validaNuovoPost,
  validaRisposta,
} from "@/lib/phase12/club-post-view";
import type { ClubPost, ClubPostTipo, NuovoClubPost } from "@/services/types";

const post = (parziale: Partial<ClubPost> & { id: string }): ClubPost => ({
  clubSlug: "barolo",
  tipo: "discussione",
  titolo: "Titolo",
  corpo: "Corpo",
  autoreId: "u1",
  autoreUsername: "autore",
  autoreAvatarUrl: null,
  vino: null,
  annuncio: null,
  risposte: 0,
  miPiace: 0,
  piaciuto: false,
  mio: false,
  createdAt: "2026-08-17T10:00:00.000Z",
  ...parziale,
});

const nuovo = (parziale: Partial<NuovoClubPost> = {}): NuovoClubPost => ({
  clubSlug: "barolo",
  tipo: "discussione",
  titolo: "Un titolo valido",
  corpo: "Un corpo valido.",
  ...parziale,
});

describe("i sette tipi", () => {
  it("sono quelli del mock, e ognuno ha un'etichetta", () => {
    expect(TIPI_POST).toEqual([
      "discussione",
      "domanda",
      "degustazione",
      "confronto",
      "consiglio",
      "sondaggio",
      "annuncio",
    ]);
    for (const tipo of TIPI_POST) {
      expect(ETICHETTE_TIPO_POST[tipo]).toBeTruthy();
    }
  });

  it("non ne ha altri: l'etichettario e esattamente l'elenco", () => {
    expect(Object.keys(ETICHETTE_TIPO_POST).sort()).toEqual([...TIPI_POST].sort());
  });
});

describe("validaNuovoPost", () => {
  it("accetta un post normale", () => {
    expect(validaNuovoPost(nuovo())).toBeNull();
  });

  it("rifiuta un titolo troppo corto o troppo lungo, come il CHECK", () => {
    expect(validaNuovoPost(nuovo({ titolo: "ab" }))).toContain("almeno");
    expect(
      validaNuovoPost(nuovo({ titolo: "x".repeat(LIMITI_POST.titoloMax + 1) })),
    ).toContain("non puo superare");
  });

  it("conta il titolo dopo il trim, come `titolo = btrim(titolo)` a database", () => {
    expect(validaNuovoPost(nuovo({ titolo: "   ab   " }))).toContain("almeno");
  });

  it("rifiuta un corpo vuoto o di soli spazi", () => {
    expect(validaNuovoPost(nuovo({ corpo: "" }))).toBe("Scrivi il testo della discussione.");
    expect(validaNuovoPost(nuovo({ corpo: "    " }))).toBe(
      "Scrivi il testo della discussione.",
    );
  });

  it("rifiuta un post `annuncio` senza annuncio collegato", () => {
    // A database e club_posts_annuncio_ha_listing. Qui si guadagna il
    // messaggio in italiano prima del giro di rete.
    expect(validaNuovoPost(nuovo({ tipo: "annuncio" }))).toContain("annuncio pubblicato");
    expect(validaNuovoPost(nuovo({ tipo: "annuncio", listingId: "l1" }))).toBeNull();
  });

  it("non pretende un annuncio dagli altri sei tipi", () => {
    for (const tipo of TIPI_POST.filter((t) => t !== "annuncio")) {
      expect(validaNuovoPost(nuovo({ tipo }))).toBeNull();
    }
  });
});

describe("validaRisposta", () => {
  it("rifiuta il vuoto e accetta il testo", () => {
    expect(validaRisposta("   ")).toBe("Scrivi la tua risposta.");
    expect(validaRisposta("Sono d'accordo.")).toBeNull();
  });

  it("rifiuta oltre il tetto del CHECK", () => {
    expect(validaRisposta("x".repeat(LIMITI_POST.rispostaMax + 1))).toContain(
      "non puo superare",
    );
  });
});

describe("ordinaPerPopolarita", () => {
  const a = post({ id: "a", miPiace: 5, risposte: 1, createdAt: "2026-08-01T00:00:00.000Z" });
  const b = post({ id: "b", miPiace: 9, risposte: 0, createdAt: "2026-08-02T00:00:00.000Z" });
  const c = post({ id: "c", miPiace: 5, risposte: 7, createdAt: "2026-08-03T00:00:00.000Z" });
  const d = post({ id: "d", miPiace: 5, risposte: 7, createdAt: "2026-08-09T00:00:00.000Z" });

  it("ordina per like, poi risposte, poi il piu recente", () => {
    expect(ordinaPerPopolarita([a, b, c, d]).map((p) => p.id)).toEqual([
      "b",
      "d",
      "c",
      "a",
    ]);
  });

  it("non muta l'array ricevuto", () => {
    // La prop arriva dal componente server ed e condivisa fra i due tab:
    // `sort` in place farebbe cambiare l'ordine anche all'altro.
    const originale = [a, b, c];
    ordinaPerPopolarita(originale);
    expect(originale.map((p) => p.id)).toEqual(["a", "b", "c"]);
  });
});

describe("filtri", () => {
  const righe = [
    post({ id: "1", tipo: "domanda" }),
    post({ id: "2", tipo: "degustazione" }),
    post({ id: "3", tipo: "domanda" }),
  ];

  it("il filtro spento e l'assenza di un valore, non un valore che vale tutto", () => {
    expect(filtraPostPerTipo(righe, "")).toHaveLength(3);
    expect(filtraPostPerTipo(righe, "domanda").map((p) => p.id)).toEqual(["1", "3"]);
  });

  it("i tipi presenti si ricavano dai post veri, nell'ordine canonico", () => {
    expect(tipiPresenti(righe)).toEqual(["domanda", "degustazione"] as ClubPostTipo[]);
    expect(tipiPresenti([])).toEqual([]);
  });
});
