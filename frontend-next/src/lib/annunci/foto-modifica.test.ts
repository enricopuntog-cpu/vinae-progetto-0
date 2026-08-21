import { describe, expect, it } from "bun:test";
import {
  MAX_FOTO,
  aggiungiFoto,
  creaBozzaFoto,
  percorsiFoto,
  percorsiSessioneNonUsati,
  revocaAnteprimeBlob,
  rimuoviFoto,
  sostituisciFoto,
  spostaFoto,
  type FotoModifica,
} from "@/lib/annunci/foto-modifica";

const persistita = (percorso: string): FotoModifica => ({
  chiave: `persistita:${percorso}`,
  percorso,
  anteprima: `/pubblico/${percorso}`,
  origine: "persistita",
});

const sessione = (percorso: string): FotoModifica => ({
  chiave: `sessione:${percorso}`,
  percorso,
  anteprima: `blob:${percorso}`,
  origine: "sessione",
});

describe("bozza fotografica di un annuncio", () => {
  it("inizializza tutte le foto persistite mantenendo ordine e percorsi grezzi", () => {
    const foto = creaBozzaFoto(["uid/a.jpg", "uid/b.webp"], (p) => `/pubblico/${p}`);

    expect(foto.map((elemento) => elemento.origine)).toEqual(["persistita", "persistita"]);
    expect(percorsiFoto(foto)).toEqual(["uid/a.jpg", "uid/b.webp"]);
    expect(foto.map((elemento) => elemento.anteprima)).toEqual([
      "/pubblico/uid/a.jpg",
      "/pubblico/uid/b.webp",
    ]);
  });

  it("aggiunge fino a sei fotografie senza superare il limite", () => {
    let foto = [persistita("uid/a.jpg")];
    for (let i = 1; i < MAX_FOTO; i += 1) foto = aggiungiFoto(foto, sessione(`uid/${i}.jpg`));

    expect(foto).toHaveLength(MAX_FOTO);
    expect(aggiungiFoto(foto, sessione("uid/eccesso.jpg"))).toEqual(foto);
  });

  it("rimuove e sostituisce senza alterare le altre posizioni", () => {
    const originali = [persistita("uid/a.jpg"), persistita("uid/b.jpg"), persistita("uid/c.jpg")];
    const sostituita = sostituisciFoto(originali, 1, sessione("uid/nuova.jpg"));

    expect(percorsiFoto(sostituita)).toEqual(["uid/a.jpg", "uid/nuova.jpg", "uid/c.jpg"]);
    expect(percorsiFoto(rimuoviFoto(sostituita, 0))).toEqual(["uid/nuova.jpg", "uid/c.jpg"]);
  });

  it("riordina e rende principale la fotografia spostata in posizione zero", () => {
    const originali = [persistita("uid/a.jpg"), persistita("uid/b.jpg"), persistita("uid/c.jpg")];
    const aSinistra = spostaFoto(originali, 1, -1);

    expect(percorsiFoto(aSinistra)).toEqual(["uid/b.jpg", "uid/a.jpg", "uid/c.jpg"]);
    expect(spostaFoto(aSinistra, 0, -1)).toBe(aSinistra);
    expect(spostaFoto(aSinistra, 2, 1)).toBe(aSinistra);
  });

  it("seleziona per il cleanup soltanto upload della sessione non più usati", () => {
    const foto = [persistita("uid/vecchia.jpg"), sessione("uid/tenuta.jpg")];

    expect(
      percorsiSessioneNonUsati(
        ["uid/tenuta.jpg", "uid/rimossa.jpg", "uid/rimossa.jpg"],
        foto,
      ),
    ).toEqual(["uid/rimossa.jpg"]);
  });

  it("revoca soltanto le anteprime blob create dal browser", () => {
    const revocati: string[] = [];
    const originale = URL.revokeObjectURL;
    URL.revokeObjectURL = (url) => revocati.push(url);

    try {
      revocaAnteprimeBlob([
        persistita("uid/persistita.jpg"),
        sessione("uid/locale.jpg"),
      ]);
    } finally {
      URL.revokeObjectURL = originale;
    }

    expect(revocati).toEqual(["blob:uid/locale.jpg"]);
  });
});
