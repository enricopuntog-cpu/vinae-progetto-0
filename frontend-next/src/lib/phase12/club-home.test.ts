import { describe, expect, it } from "bun:test";
import {
  clubDaScoprire,
  clubSeguiti,
  LIMITE_CLUB_HOME,
} from "@/lib/phase12/club-home";
import type { Club } from "@/services/types";

const club = (patch: Partial<Club> & { slug: string }): Club => ({
  nome: patch.slug,
  territorio: null,
  denominazione: null,
  produttore: null,
  tipologia: null,
  descrizione: "Descrizione del club, abbastanza lunga.",
  regole: [],
  membri: 0,
  seguito: false,
  ownerId: null,
  ownerUsername: null,
  postingMode: "OPEN",
  coverImage: null,
  mio: false,
  createdAt: "2026-08-24T09:00:00.000Z",
  ...patch,
});

const catalogo: Club[] = [
  club({ slug: "barolo", nome: "Barolo", membri: 120, seguito: true }),
  club({ slug: "champagne", nome: "Champagne", membri: 80 }),
  club({ slug: "etna", nome: "Etna", membri: 200 }),
  club({ slug: "franciacorta", nome: "Franciacorta", membri: 80, seguito: true }),
  club({ slug: "grandi-formati", nome: "Grandi formati", membri: 10 }),
];

describe("clubSeguiti", () => {
  it("tiene soltanto i club con seguito true", () => {
    expect(clubSeguiti(catalogo).map((c) => c.slug)).toEqual(["barolo", "franciacorta"]);
  });

  it("per un anonimo - nessun seguito - restituisce la lista vuota", () => {
    const anonimo = catalogo.map((c) => ({ ...c, seguito: false }));
    expect(clubSeguiti(anonimo)).toEqual([]);
  });

  it("non supera il limite della Home", () => {
    const molti = Array.from({ length: 9 }, (_, i) =>
      club({ slug: `club-${i}`, nome: `Club ${i}`, membri: i, seguito: true }),
    );
    expect(clubSeguiti(molti)).toHaveLength(LIMITE_CLUB_HOME);
  });
});

describe("clubDaScoprire", () => {
  it("esclude i club gia seguiti", () => {
    const slugs = clubDaScoprire(catalogo).map((c) => c.slug);
    expect(slugs).not.toContain("barolo");
    expect(slugs).not.toContain("franciacorta");
  });

  it("ordina per membri decrescenti e taglia al limite", () => {
    expect(clubDaScoprire(catalogo).map((c) => c.slug)).toEqual([
      "etna",
      "champagne",
      "grandi-formati",
    ]);
  });

  it("a parita di membri ordina per nome, cosi due letture danno lo stesso ordine", () => {
    const pari = [
      club({ slug: "zibibbo", nome: "Zibibbo", membri: 50 }),
      club({ slug: "amarone", nome: "Amarone", membri: 50 }),
    ];
    expect(clubDaScoprire(pari).map((c) => c.slug)).toEqual(["amarone", "zibibbo"]);
    expect(clubDaScoprire([...pari].reverse()).map((c) => c.slug)).toEqual([
      "amarone",
      "zibibbo",
    ]);
  });

  it("con tutti i club gia seguiti non resta niente da scoprire", () => {
    const tutti = catalogo.map((c) => ({ ...c, seguito: true }));
    expect(clubDaScoprire(tutti)).toEqual([]);
  });

  it("senza club pubblicati restituisce la lista vuota", () => {
    expect(clubDaScoprire([])).toEqual([]);
    expect(clubSeguiti([])).toEqual([]);
  });

  it("non mutila ne riordina l'elenco ricevuto", () => {
    const originale = [...catalogo];
    clubDaScoprire(catalogo);
    clubSeguiti(catalogo);
    expect(catalogo).toEqual(originale);
  });
});
