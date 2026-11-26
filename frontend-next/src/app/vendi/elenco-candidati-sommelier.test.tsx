import { afterAll, afterEach, describe, expect, it } from "bun:test";
import type { CandidatoValutato } from "@/lib/vendi/foto-etichetta/candidati";
import { apriDom, chiudiDom } from "@/test/dom";

/** WI-008 — «Chiedi al Sommelier» sui soli candidati canonici: scelta esplicita per codice, senza toccare la selezione. */
process.env.NEXT_PUBLIC_AI_UI_ENABLED = "true";
apriDom();
const { cleanup, fireEvent, render, screen } = await import("@testing-library/react");
const { ElencoCandidati } = await import("./elenco-candidati");
const { ascoltaRichiesteSommelier } = await import("@/lib/phase10/sommelier-contesto-ui");

afterEach(cleanup);
afterAll(chiudiDom);

const BASE: CandidatoValutato = {
  fonte: "catalogo_vinea",
  id: "a",
  produttore: "Gaja",
  nome: "Sorì Tildìn",
  annata: 2016,
  formato: "0,75 L",
  regione: null,
  denominazione: null,
  tipo: null,
  punteggio: 1,
  esito: "probabile",
  occorrenze: 1,
};

const canonico = (id: string, lwin7: string): CandidatoValutato => ({
  ...BASE,
  id,
  annata: null,
  formato: null,
  fonte: "catalogo_canonico",
  canonico: { lwin7, paese: "Italy", territorio: null, fonteNome: "Liv-ex LWIN", licenza: "CC BY 4.0", attribuzione: "Dati LWIN, CC BY 4.0" },
});

const monta = (candidati: CandidatoValutato[], scelte: (string | null)[] = []) =>
  render(
    <ElencoCandidati
      candidati={candidati}
      sintesi="ambigua"
      selezionato={null}
      onSeleziona={(id) => scelte.push(id)}
      nomeGruppo="g"
      prefissoTest="t"
    />,
  );

describe("ElencoCandidati — Chiedi al Sommelier", () => {
  it("un vino non canonico non ha il pulsante: senza codice autorevole non c'è un'identità da chiedere", () => {
    monta([BASE]);
    expect(screen.queryByTestId("t-sommelier-a")).toBeNull();
  });

  it("due omonimi hanno ciascuno il proprio pulsante, con il proprio codice LWIN", () => {
    const richieste: unknown[] = [];
    const smetti = ascoltaRichiesteSommelier((c) => richieste.push(c));
    monta([canonico("b", "1010003"), canonico("c", "1010004")]);
    fireEvent.click(screen.getByTestId("t-sommelier-c"));
    smetti();
    expect(richieste).toEqual([
      { tipo: "ricerca", produttore: "Gaja", nome: "Sorì Tildìn", codice: "1010004", etichetta: "Gaja Sorì Tildìn" },
    ]);
  });

  it("chiedere al Sommelier non sceglie il vino e non applica nulla al wizard", () => {
    const scelte: (string | null)[] = [];
    monta([canonico("b", "1010003")], scelte);
    fireEvent.click(screen.getByTestId("t-sommelier-b"));
    expect(scelte).toEqual([]);
    expect(screen.getByTestId("t-sommelier-b").closest("label")).toBeNull();
  });
});
