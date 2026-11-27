import { describe, expect, it } from "bun:test";
import {
  ACQUISIZIONE_IMMAGINI_REALI,
  analizzaImmaginiDiProva,
  coerenzaEtichetta,
  ispezionaImmagine,
  misuraQualita,
} from "./immagini";

// Fixture SINTETICHE costruite in memoria: nessuna fotografia reale entra in questo banco.
const be32 = (n: number) => [(n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255];
const be16 = (n: number) => [(n >>> 8) & 255, n & 255];
const le24 = (n: number) => [n & 255, (n >>> 8) & 255, (n >>> 16) & 255];
const le32 = (n: number) => [...le24(n), (n >>> 24) & 255];
const ascii = (s: string) => [...s].map((c) => c.charCodeAt(0));

const png = (w: number, h: number) =>
  new Uint8Array([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
    ...be32(13), ...ascii("IHDR"), ...be32(w), ...be32(h), 8, 2, 0, 0, 0, ...be32(0),
    ...be32(0), ...ascii("IEND"), 0xae, 0x42, 0x60, 0x82,
  ]);
const jpeg = (w: number, h: number) =>
  new Uint8Array([
    0xff, 0xd8, 0xff, 0xe0, ...be16(4), 0, 0,
    0xff, 0xc0, ...be16(11), 8, ...be16(h), ...be16(w), 1, 1, 0x11, 0,
    0xff, 0xda, ...be16(2), 0x12, 0x34, 0xff, 0xd9,
  ]);
const webp = (w: number, h: number) => {
  const dati = [...ascii("VP8X"), ...le32(10), 0, 0, 0, 0, ...le24(w - 1), ...le24(h - 1)];
  return new Uint8Array([...ascii("RIFF"), ...le32(dati.length + 4), ...ascii("WEBP"), ...dati]);
};

describe("WI-016 — contenuto reale, formato e dimensioni (solo fixture)", () => {
  it.each([
    ["image/png", png(1200, 1600), "png"],
    ["image/jpeg", jpeg(1200, 1600), "jpeg"],
    ["image/webp", webp(1200, 1600), "webp"],
  ])("%s valida: formato e dimensioni letti dal contenuto", (mime, byte, formato) => {
    expect(ispezionaImmagine(byte, mime)).toEqual({ ok: true, formato: formato as never, larghezza: 1200, altezza: 1600 });
  });

  it("il tipo dichiarato non basta: contenuto diverso, eseguibile o testo rinominato sono rifiutati", () => {
    expect(ispezionaImmagine(png(1200, 1600), "image/jpeg")).toEqual({ ok: false, motivo: "contenuto_non_corrisponde" });
    for (const byte of [new Uint8Array(ascii("<svg onload=alert(1)></svg>")), new Uint8Array([0x4d, 0x5a, 0x90, 0])]) {
      expect(ispezionaImmagine(byte, "image/png")).toEqual({ ok: false, motivo: "contenuto_non_corrisponde" });
    }
    expect(ispezionaImmagine(png(1200, 1600), "image/svg+xml")).toEqual({ ok: false, motivo: "formato_non_ammesso" });
  });

  it("vuota, oltre il tetto in byte, troncata o con dimensioni fuori misura", () => {
    expect(ispezionaImmagine(new Uint8Array(0), "image/png")).toEqual({ ok: false, motivo: "vuoto" });
    expect(ispezionaImmagine(new Uint8Array(5 * 1024 * 1024 + 1), "image/png")).toEqual({ ok: false, motivo: "troppo_grande" });
    for (const [byte, mime] of [[png(1200, 1600), "image/png"], [jpeg(1200, 1600), "image/jpeg"], [webp(1200, 1600), "image/webp"]] as const) {
      expect(ispezionaImmagine(byte.slice(0, byte.length - 3), mime)).toEqual({ ok: false, motivo: "troncata" });
    }
    for (const [w, h] of [[200, 1600], [1200, 200], [13000, 1600], [12000, 12000]]) {
      expect(ispezionaImmagine(png(w, h), "image/png")).toEqual({ ok: false, motivo: "dimensioni_non_ammesse" });
    }
  });

  it("coda aggiunta dopo la fine dell'immagine (file poliglotta): rifiutata", () => {
    const conCoda = new Uint8Array([...png(1200, 1600), ...ascii("<?php echo 1; ?>")]);
    expect(ispezionaImmagine(conCoda, "image/png")).toEqual({ ok: false, motivo: "troncata" });
  });
});

const griglia = (lato: number, f: (x: number, y: number) => number) => ({
  larghezza: lato,
  altezza: lato,
  grigi: Uint8Array.from({ length: lato * lato }, (_, i) => f(i % lato, Math.floor(i / lato))),
});

describe("WI-016 — qualità della fotografia", () => {
  it("un motivo nitido e ben esposto è sufficiente; sfocato, buio o bruciato no", () => {
    expect(misuraQualita(griglia(64, (x, y) => ((x >> 1) + (y >> 1)) % 2 === 0 ? 60 : 190)).sufficiente).toBe(true);
    expect(misuraQualita(griglia(64, (x) => 100 + (x >> 4))).motivi).toContain("sfocata");
    expect(misuraQualita(griglia(64, (x, y) => ((x >> 1) + (y >> 1)) % 2 === 0 ? 0 : 20)).motivi).toContain("troppo_scura");
    expect(misuraQualita(griglia(64, (x, y) => ((x >> 1) + (y >> 1)) % 2 === 0 ? 255 : 254)).motivi).toContain("troppo_chiara");
  });

  it("matrice incoerente: non valutabile come sufficiente", () => {
    expect(misuraQualita({ larghezza: 10, altezza: 10, grigi: new Uint8Array(5) })).toEqual({ sufficiente: false, motivi: ["non_misurabile"] });
  });
});

describe("WI-016 — coerenza con il testo letto dall'etichetta", () => {
  const dichiarato = { produttore: "Cantina Aurelia", annata: 2019 };

  it("annata diversa e produttore diverso diventano segnali, mai un verdetto", () => {
    const r = coerenzaEtichetta("Tenuta Ostile\nRosso del Faro\n2015", dichiarato);
    expect(r.segnali).toEqual(["produttore_non_coerente", "annata_non_coerente"]);
    expect(r.autenticita.esito).toBe("non_determinabile");
  });

  it("testo illeggibile: nessuna incoerenza inventata", () => {
    const r = coerenzaEtichetta("~~ || ..", dichiarato);
    expect(r.segnali).toEqual([]);
    expect(r.identificazione.esito).toBe("non_verificata");
  });
});

describe("WI-016 — analisi completa: l'acquisizione di immagini reali è spenta", () => {
  const prova = {
    byte: png(1200, 1600),
    mime: "image/png",
    pixel: griglia(64, (x) => 100 + (x >> 4)),
    testoOcr: "Cantina Aurelia\nRosso del Faro\n2019",
    dichiarato: { produttore: "Cantina Aurelia", annata: 2019 },
  };

  it("una fotografia dell'utente non viene analizzata", () => {
    expect(ACQUISIZIONE_IMMAGINI_REALI).toBe(false);
    expect(analizzaImmaginiDiProva({ ...prova, origine: "utente" })).toEqual({ stato: "acquisizione_disattivata" });
  });

  it("con una fixture: segnali dell'elenco chiuso e autenticità non determinabile", () => {
    const r = analizzaImmaginiDiProva({ ...prova, origine: "fixture" });
    expect(r).toMatchObject({ stato: "analizzata", segnali: ["qualita_foto_insufficiente"], autenticita: "non_determinabile" });
    expect(JSON.stringify(r)).not.toMatch(/\b(autentica|falsa|certificat[ao])\b/i);
  });

  it("file non valido: nessuna analisi del contenuto", () => {
    expect(analizzaImmaginiDiProva({ ...prova, origine: "fixture", mime: "image/jpeg" }))
      .toEqual({ stato: "file_rifiutato", motivo: "contenuto_non_corrisponde" });
  });
});
