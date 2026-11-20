import { describe, expect, it } from "bun:test";
import { estraiCampiDaTestoOcr, qualitaLettura } from "./estrazione";

describe("estraiCampiDaTestoOcr", () => {
  it("riconosce produttore, nome, annata, denominazione e formato", () => {
    const c = estraiCampiDaTestoOcr(
      "TENUTA BORGO ANTICO\n—— SIENA ——\nRosso di Prova\nChianti Classico DOCG\n2019\n750 ml - 13,5% vol\n",
    );
    expect(c.produttore).toBe("Tenuta Borgo Antico");
    expect(c.nome).toBe("Rosso di Prova");
    expect(c.annata).toBe(2019);
    expect(c.denominazione).toBe("Chianti Classico DOCG");
    expect(c.formato).toBe("0,75 L");
  });

  it("usa «imbottigliato da» per il produttore quando c'è", () => {
    const c = estraiCampiDaTestoOcr("Barolo\nProdotto e imbottigliato da Azienda Fittizia S.r.l.\n2016");
    expect(c.produttore).toBe("Azienda Fittizia");
    expect(c.annata).toBe(2016);
  });

  it("campi incompleti: ciò che non c'è resta null, mai inventato", () => {
    const c = estraiCampiDaTestoOcr("Qualcosa di Scritto\n");
    expect(c.annata).toBeNull();
    expect(c.denominazione).toBeNull();
    expect(c.formato).toBeNull();
    expect(c.produttore).toBeNull();
    expect(qualitaLettura(c, 80)).toBe("parziale");
  });

  it("annata assente → null; annate multiple → null con alternative", () => {
    expect(estraiCampiDaTestoOcr("Vino Rosso Fantasia").annata).toBeNull();
    const m = estraiCampiDaTestoOcr("Vino Fantasia\n2015 2019");
    expect(m.annata).toBeNull();
    expect(m.annateAlternative).toEqual([2015, 2019]);
  });

  it("annata implausibile (anno futuro, numeri lunghi) non è un'annata", () => {
    const futuro = String(new Date().getFullYear() + 5);
    expect(estraiCampiDaTestoOcr(`Vino\n${futuro}`).annata).toBeNull();
    expect(estraiCampiDaTestoOcr("Lotto 12019345").annata).toBeNull();
  });

  it("formati: 75 cl, 1,5 L, magnum; uno fuori elenco resta null", () => {
    expect(estraiCampiDaTestoOcr("Vino\n75 cl").formato).toBe("0,75 L");
    expect(estraiCampiDaTestoOcr("Vino\n1,5 L").formato).toBe("1,5 L");
    expect(estraiCampiDaTestoOcr("Vino Magnum").formato).toBe("1,5 L");
    expect(estraiCampiDaTestoOcr("Vino\n77 cl").formato).toBeNull();
  });

  it("qualità: rumore e testo vuoto → nessuna; testo senza campi → scarsa", () => {
    expect(qualitaLettura(estraiCampiDaTestoOcr(""), 90)).toBe("nessuna");
    expect(qualitaLettura(estraiCampiDaTestoOcr("|| ~ .. -- ##"), 10)).toBe("nessuna");
    expect(
      qualitaLettura(estraiCampiDaTestoOcr("contiene solfiti\nnon disperdere nell'ambiente"), 70),
    ).toBe("scarsa");
  });
});
