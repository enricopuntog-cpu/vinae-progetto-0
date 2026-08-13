import { describe, expect, it } from "bun:test";
import {
  ETICHETTA_IA,
  NOMINA_IA,
  type SuperficieIA,
} from "@/lib/phase10/etichette-ia";

const SUPERFICI: SuperficieIA[] = ["sommelier", "catalogazione", "abbinamento"];

describe("etichette di trasparenza IA", () => {
  it("copre tutte e tre le superfici IA della Fase 10, e nessuna di più", () => {
    // Le tre superfici sono quelle chiuse dal checkpoint 10c: pannello
    // Sommelier nel Layout, pannello Assistente del passo Identificazione,
    // pannello di abbinamento in `/esplora`. Una quarta superficie IA — le
    // quattro della Fase 11 lo saranno — deve comparire qui e non altrove.
    expect(Object.keys(ETICHETTA_IA).sort()).toEqual([...SUPERFICI].sort());
  });

  it("ogni etichetta nomina l'IA", () => {
    // È l'unica cosa che l'etichetta deve fare. Una riformulazione che
    // togliesse la parola resterebbe leggibile e smetterebbe di dichiarare
    // niente, e nessun altro controllo se ne accorgerebbe.
    for (const superficie of SUPERFICI) {
      expect(ETICHETTA_IA[superficie]).toMatch(NOMINA_IA);
    }
  });

  it("ogni etichetta è una riga sola e resta breve", () => {
    // «Testo minimo»: una frase che entra accanto al titolo del pannello. Il
    // pannello Sommelier è largo 420px e ne ospita anche due bottoni.
    for (const superficie of SUPERFICI) {
      const testo = ETICHETTA_IA[superficie];
      expect(testo.trim()).toBe(testo);
      expect(testo).not.toInclude("\n");
      expect(testo.length).toBeLessThanOrEqual(60);
      expect(testo.length).toBeGreaterThan(0);
    }
  });

  it("nessuna etichetta promette un'azione automatica del modello", () => {
    // La catalogazione suggerisce e non compila: applicare il suggerimento ai
    // campi è un secondo gesto del venditore. Vale anche come promemoria per la
    // 7.3a, dove l'autofill avrà una sua etichetta e una sua conferma.
    expect(ETICHETTA_IA.catalogazione).toInclude("suggerire");
    expect(ETICHETTA_IA.catalogazione).not.toInclude("compila");
  });

  it("le tre etichette sono distinte", () => {
    expect(new Set(Object.values(ETICHETTA_IA)).size).toBe(SUPERFICI.length);
  });
});
