import { afterAll, afterEach, describe, expect, it } from "bun:test";
import type { CandidatoValutato } from "@/lib/vendi/foto-etichetta/candidati";
import { apriDom, chiudiDom } from "@/test/dom";

/** WI-007 — l'elenco mostra LWIN e l'attribuzione della fonte solo per i vini canonici. */
apriDom();
const { cleanup, render, screen } = await import("@testing-library/react");
const { ElencoCandidati } = await import("./elenco-candidati");

afterEach(cleanup);
afterAll(chiudiDom);

const BASE: CandidatoValutato = {
  fonte: "catalogo_vinea",
  id: "a",
  produttore: "Gaja",
  nome: "Sorì Tildìn",
  annata: null,
  formato: null,
  regione: null,
  denominazione: null,
  tipo: null,
  punteggio: 1,
  esito: "probabile",
  occorrenze: 1,
};

const monta = (candidati: CandidatoValutato[]) =>
  render(
    <ElencoCandidati
      candidati={candidati}
      sintesi="unica"
      selezionato={null}
      onSeleziona={() => undefined}
      nomeGruppo="g"
      prefissoTest="t"
    />,
  );

describe("ElencoCandidati — catalogo canonico", () => {
  it("senza vini canonici: nessun LWIN e nessuna attribuzione", () => {
    monta([BASE]);
    expect(screen.queryByTestId("t-attribuzione")).toBeNull();
    expect(screen.queryByText(/LWIN/)).toBeNull();
  });

  it("con un vino canonico: LWIN e attribuzione (una sola volta anche con più vini)", () => {
    const canonico = (id: string, lwin7: string): CandidatoValutato => ({
      ...BASE,
      id,
      fonte: "catalogo_canonico",
      canonico: { lwin7, paese: null, territorio: null, fonteNome: "Liv-ex LWIN", licenza: "CC BY 4.0", attribuzione: "Dati LWIN, CC BY 4.0" },
    });
    monta([canonico("b", "1010003"), canonico("c", "1010004")]);
    expect(screen.getByText(/LWIN 1010003/)).toBeTruthy();
    expect(screen.getByTestId("t-attribuzione").textContent).toBe("Dati LWIN, CC BY 4.0");
  });

  it("attribuzione assente nella fonte: ripiego su nome e licenza, mai vuota", () => {
    monta([{ ...BASE, canonico: { lwin7: "1010003", paese: null, territorio: null, fonteNome: "Liv-ex LWIN", licenza: "CC BY 4.0", attribuzione: null } }]);
    expect(screen.getByTestId("t-attribuzione").textContent).toBe("Liv-ex LWIN — CC BY 4.0");
  });
});
