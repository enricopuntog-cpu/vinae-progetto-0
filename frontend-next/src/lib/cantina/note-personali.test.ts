import { describe, expect, it } from "bun:test";
import {
  confrontaConCatalogo,
  eNotaVuota,
  notaVuota,
  righeAbbinamenti,
  validaNotaPersonale,
  type NotaPersonaleVino,
} from "@/lib/cantina/note-personali";

describe("righeAbbinamenti", () => {
  it("separa per riga e per punto e virgola, senza virgole: un piatto può contenerle", () => {
    expect(righeAbbinamenti("Pasta, funghi\nBrasato; Parmigiano")).toEqual([
      "Pasta, funghi",
      "Brasato",
      "Parmigiano",
    ]);
  });
  it("ignora le righe vuote", () => {
    expect(righeAbbinamenti("\n  \nRisotto\n")).toEqual(["Risotto"]);
  });
});

describe("validaNotaPersonale", () => {
  it("accetta una nota completa e normalizza spazi e duplicati senza distinguere le maiuscole", () => {
    const esito = validaNotaPersonale({
      abbinamenti: ["  Brasato   al Barolo ", "brasato al barolo", "Tagliatelle al ragù"],
      temperaturaC: "16",
      decantazioneMinuti: 45,
      calice: " Ballon ",
      annataDichiarata: "2015",
      denominazione: " Barolo DOCG ",
      regione: "Piemonte",
      osservazioni: "Regalo di Marco.\nProvato a Natale.",
    });
    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.nota).toMatchObject({
      abbinamenti: ["Brasato al Barolo", "Tagliatelle al ragù"],
      temperaturaC: 16,
      decantazioneMinuti: 45,
      calice: "Ballon",
      annataDichiarata: 2015,
      nonMillesimato: false,
      denominazione: "Barolo DOCG",
      regione: "Piemonte",
    });
    expect(esito.nota.osservazioni).toBe("Regalo di Marco.\nProvato a Natale.");
  });

  it("accetta una nota vuota: significa nessuna annotazione", () => {
    const esito = validaNotaPersonale({});
    expect(esito.ok).toBe(true);
    if (esito.ok) expect(eNotaVuota(esito.nota)).toBe(true);
  });

  it("rifiuta più di 8 abbinamenti, voci troppo corte o troppo lunghe", () => {
    const molti = validaNotaPersonale({ abbinamenti: Array.from({ length: 9 }, (_, i) => `Piatto ${i + 1}`) });
    expect(molti.ok).toBe(false);
    if (!molti.ok) expect(molti.errori.abbinamenti).toMatch(/al massimo 8/);
    const corto = validaNotaPersonale({ abbinamenti: ["a"] });
    expect(corto.ok).toBe(false);
    const lungo = validaNotaPersonale({ abbinamenti: ["x".repeat(61)] });
    expect(lungo.ok).toBe(false);
  });

  it("rifiuta temperatura, decantazione e annata fuori scala o non intere", () => {
    for (const input of [
      { temperaturaC: 30 },
      { temperaturaC: -1 },
      { temperaturaC: "16.5" },
      { decantazioneMinuti: 601 },
      { decantazioneMinuti: "abc" },
      { annataDichiarata: 1799 },
      { annataDichiarata: 2101 },
      { annataDichiarata: "20x5" },
    ]) {
      const esito = validaNotaPersonale(input);
      expect(esito.ok).toBe(false);
    }
  });

  it("non ammette annata dichiarata e non millesimato insieme", () => {
    const esito = validaNotaPersonale({ annataDichiarata: 2015, nonMillesimato: true });
    expect(esito.ok).toBe(false);
    if (!esito.ok) expect(esito.errori.annataDichiarata).toMatch(/non millesimato/i);
  });

  it("rifiuta caratteri di controllo e testi oltre i limiti", () => {
    expect(validaNotaPersonale({ calice: "Bal\u0000lon" }).ok).toBe(false);
    expect(validaNotaPersonale({ osservazioni: "x".repeat(1001) }).ok).toBe(false);
    expect(validaNotaPersonale({ regione: "x".repeat(81) }).ok).toBe(false);
    expect(validaNotaPersonale({ denominazione: "x".repeat(121) }).ok).toBe(false);
    expect(validaNotaPersonale({ calice: "x".repeat(41) }).ok).toBe(false);
  });

  it("non esegue né interpreta il markup: lo conserva come testo", () => {
    const esito = validaNotaPersonale({ osservazioni: "<script>alert(1)</script>" });
    expect(esito.ok).toBe(true);
    if (esito.ok) expect(esito.nota.osservazioni).toBe("<script>alert(1)</script>");
  });
});

describe("confrontaConCatalogo", () => {
  const nota = (extra: Partial<NotaPersonaleVino>): NotaPersonaleVino => ({ ...notaVuota(), ...extra });
  const catalogo = { annata: 2015, regione: "Piemonte", denominazione: "Barolo DOCG" };

  it("nessun conflitto se la dichiarazione coincide, a meno di maiuscole e spazi", () => {
    expect(
      confrontaConCatalogo(nota({ annataDichiarata: 2015, regione: " piemonte ", denominazione: "barolo docg" }), catalogo),
    ).toEqual([]);
  });

  it("segnala la divergenza senza dire quale delle due sia giusta", () => {
    const c = confrontaConCatalogo(nota({ annataDichiarata: 2016, regione: "Toscana" }), catalogo);
    expect(c.map((x) => x.campo).sort()).toEqual(["annata", "regione"]);
    expect(c.find((x) => x.campo === "annata")).toMatchObject({ personale: "2016", catalogo: "2015" });
  });

  it("non millesimato dichiarato su un vino che il catalogo data è un conflitto", () => {
    const c = confrontaConCatalogo(nota({ nonMillesimato: true }), catalogo);
    expect(c).toEqual([expect.objectContaining({ campo: "annata", personale: "non millesimato", catalogo: "2015" })]);
  });

  it("annata assente nel catalogo non è un errore e non produce conflitti", () => {
    expect(confrontaConCatalogo(nota({ nonMillesimato: true }), { ...catalogo, annata: 0 })).toEqual([]);
  });

  it("campi non dichiarati non confliggono", () => {
    expect(confrontaConCatalogo(nota({}), catalogo)).toEqual([]);
  });
});
