import { describe, expect, test } from "bun:test";
import type { CandidatoVino, SorgenteCandidati } from "@/lib/vendi/foto-etichetta/candidati";
import { valutaCandidati } from "@/lib/vendi/foto-etichetta/candidati";
import { aRisultatoRicerca } from "./contratto";
import {
  type ClienteRpcCanonico,
  FUNZIONE_RICERCA_CANONICA,
  candidatoDaRigaCanonica,
  sorgenteCanonica,
  sorgenteConCanonico,
} from "./canonico";

const RIGA = {
  fonte: "catalogo_canonico",
  vino_id: "7b0f6f6e-0000-4000-8000-000000000001",
  lwin7: "1010001",
  produttore: "Giacomo Conterno",
  nome: "Barolo Monfortino",
  paese: "Italia",
  territorio: "Piemonte",
  territorio_tipo: "region",
  denominazione: "Barolo DOCG",
  tipo: "Still",
  colore: "Red",
  punteggio: 100,
  livello: "esatto",
  fonte_nome: "Liv-ex LWIN",
  fonte_licenza: "CC BY 4.0",
  attribuzione: "Dati LWIN, Liv-ex, CC BY 4.0",
};

const DOMANDA = { produttore: "Giacomo Conterno", nome: "Barolo Monfortino", annata: null, formato: null };

const clienteCon = (risposta: { data: unknown; error: unknown }, chiamate: unknown[] = []) =>
  ({
    rpc: async (nome: string, args: unknown) => {
      chiamate.push([nome, args]);
      return risposta;
    },
  }) as never as ClienteRpcCanonico;

describe("candidatoDaRigaCanonica", () => {
  test("riga completa → candidato con LWIN, provenienza e nessun dato inventato", () => {
    const c = candidatoDaRigaCanonica(RIGA);
    expect(c).not.toBeNull();
    expect(c?.annata).toBeNull();
    expect(c?.formato).toBeNull();
    expect(c?.tipo).toBeNull();
    expect(c?.regione).toBe("Piemonte");
    expect(c?.canonico?.lwin7).toBe("1010001");
    expect(c?.canonico?.attribuzione).toBe("Dati LWIN, Liv-ex, CC BY 4.0");
    expect(c?.corrispondenzaServer).toEqual({ livello: "esatto", punteggio: 100 });
  });

  test("un territorio che non è una regione non diventa la regione", () => {
    const c = candidatoDaRigaCanonica({ ...RIGA, territorio: "Italia", territorio_tipo: "country" });
    expect(c?.regione).toBeNull();
    expect(c?.canonico?.territorio).toBe("Italia");
  });

  test.each([
    ["senza produttore", { ...RIGA, produttore: " " }],
    ["senza nome", { ...RIGA, nome: "" }],
    ["senza id", { ...RIGA, vino_id: undefined }],
    ["LWIN non di 7 cifre", { ...RIGA, lwin7: "12345" }],
    ["non un oggetto", "x"],
    ["null", null],
  ])("scartata: %s", (_t, riga) => {
    expect(candidatoDaRigaCanonica(riga)).toBeNull();
  });

  test("livello sconosciuto: nessuna corrispondenza server inventata", () => {
    const c = candidatoDaRigaCanonica({ ...RIGA, livello: "boh" });
    expect(c?.corrispondenzaServer).toBeUndefined();
  });
});

describe("sorgenteCanonica", () => {
  test("chiama solo la RPC canonica con i parametri della domanda, mai catalog.*", async () => {
    const chiamate: unknown[] = [];
    const esito = await sorgenteCanonica(clienteCon({ data: [RIGA], error: null }, chiamate)).cerca(DOMANDA);
    expect(esito.ok && esito.data).toHaveLength(1);
    expect(chiamate).toEqual([
      [FUNZIONE_RICERCA_CANONICA, { p_produttore: "Giacomo Conterno", p_nome: "Barolo Monfortino", p_limite: 10 }],
    ]);
  });

  test("domanda senza parole utili: nessuna richiesta", async () => {
    const chiamate: unknown[] = [];
    const esito = await sorgenteCanonica(clienteCon({ data: [], error: null }, chiamate)).cerca({
      produttore: "il",
      nome: "di",
      annata: null,
      formato: null,
    });
    expect(esito).toEqual({ ok: true, data: [] });
    expect(chiamate).toHaveLength(0);
  });

  test("errore, risposta non valida, eccezione e client assente restano errori", async () => {
    for (const client of [
      clienteCon({ data: null, error: { message: "x" } }),
      clienteCon({ data: { a: 1 }, error: null }),
      { rpc: async () => { throw new Error("rete"); } },
      null,
    ]) {
      const esito = await sorgenteCanonica(client as never).cerca(DOMANDA);
      expect(esito.ok).toBe(false);
    }
  });

  test("righe non valide scartate, le valide passano", async () => {
    const esito = await sorgenteCanonica(clienteCon({ data: [RIGA, { ...RIGA, lwin7: "x" }], error: null })).cerca(DOMANDA);
    expect(esito.ok && esito.data.length).toBe(1);
  });
});

const principaleCon = (data: CandidatoVino[] | "errore"): SorgenteCandidati => ({
  codice: "motore_vinea",
  cerca: async () => (data === "errore" ? { ok: false, error: "ko" } : { ok: true, data }),
});

const DAL_CATALOGO: CandidatoVino = {
  fonte: "catalogo_vinea",
  id: "monfortino-slug",
  produttore: "Giacomo Conterno",
  nome: "Barolo Monfortino",
  annata: null,
  formato: null,
  regione: "Piemonte",
  denominazione: null,
  tipo: null,
};

describe("sorgenteConCanonico", () => {
  test("canonico spento (zero righe): i candidati della principale passano invariati", async () => {
    const s = sorgenteConCanonico(principaleCon([DAL_CATALOGO]), sorgenteCanonica(clienteCon({ data: [], error: null })));
    expect(await s.cerca(DOMANDA)).toEqual({ ok: true, data: [DAL_CATALOGO] });
  });

  test("un errore del canonico non fa fallire né svuota la ricerca", async () => {
    const s = sorgenteConCanonico(
      principaleCon([DAL_CATALOGO]),
      sorgenteCanonica(clienteCon({ data: null, error: { message: "x" } })),
    );
    expect(await s.cerca(DOMANDA)).toEqual({ ok: true, data: [DAL_CATALOGO] });
  });

  test("un'eccezione del canonico è assorbita", async () => {
    const s = sorgenteConCanonico(principaleCon([DAL_CATALOGO]), {
      codice: "x",
      cerca: async () => {
        throw new Error("boom");
      },
    });
    expect(await s.cerca(DOMANDA)).toEqual({ ok: true, data: [DAL_CATALOGO] });
  });

  test("l'errore della principale resta un errore anche se il canonico risponde", async () => {
    const s = sorgenteConCanonico(principaleCon("errore"), sorgenteCanonica(clienteCon({ data: [RIGA], error: null })));
    expect((await s.cerca(DOMANDA)).ok).toBe(false);
  });

  test("stesso vino in catalogo e canonico: una riga sola, vince la scheda canonica con il LWIN", async () => {
    const s = sorgenteConCanonico(principaleCon([DAL_CATALOGO]), sorgenteCanonica(clienteCon({ data: [RIGA], error: null })));
    const esito = await s.cerca(DOMANDA);
    if (!esito.ok) throw new Error("atteso ok");
    const valutati = valutaCandidati(DOMANDA, esito.data);
    expect(valutati).toHaveLength(1);
    expect(valutati[0]?.canonico?.lwin7).toBe("1010001");
    const r = aRisultatoRicerca(valutati[0]!);
    expect(r.identita.codiceLwin).toBe("1010001");
    expect(r.nonDisponibile).toEqual(["alias"]);
    expect(r.attribuzione?.licenza).toBe("CC BY 4.0");
  });

  test("solo canonico: il LWIN arriva al contratto; senza canonico resta non disponibile", async () => {
    const solo = valutaCandidati(DOMANDA, [candidatoDaRigaCanonica(RIGA)!]);
    expect(aRisultatoRicerca(solo[0]!).identita.codiceLwin).toBe("1010001");
    const senza = valutaCandidati(DOMANDA, [DAL_CATALOGO]);
    const r = aRisultatoRicerca(senza[0]!);
    expect(r.identita.codiceLwin).toBeNull();
    expect(r.nonDisponibile).toEqual(["codice_lwin", "alias", "territorio_canonico"]);
    expect(r.attribuzione).toBeUndefined();
  });
});
