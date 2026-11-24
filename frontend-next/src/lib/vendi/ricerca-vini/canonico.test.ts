import { describe, expect, test } from "bun:test";
import type { CandidatoVino, SorgenteCandidati } from "@/lib/vendi/foto-etichetta/candidati";
import { sintesiRicerca, valutaCandidati } from "@/lib/vendi/foto-etichetta/candidati";
import { campiWizardDaConferma } from "@/lib/vendi/foto-etichetta/applica";
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

  // FIX-03A — una chiave descrittiva coincidente NON è una prova di identità: la scheda canonica non si attribuisce
  // al vino Vinea e fra più schede canoniche non si sceglie con l'ordine degli id. Decide l'utente, dall'elenco.
  const vineaConAnnunci: CandidatoVino = { ...DAL_CATALOGO, tipo: "Rosso", annunci: 3 };
  const canonico = (extra: Record<string, unknown> = {}) => candidatoDaRigaCanonica({ ...RIGA, ...extra })!;
  const ordini = <T,>(v: T[]): T[][] =>
    v.length <= 1 ? [v] : v.flatMap((x, i) => ordini([...v.slice(0, i), ...v.slice(i + 1)]).map((r) => [x, ...r]));

  test("FIX-03A: Vinea e canonico con la stessa chiave restano DUE candidati, in ogni ordine, ciascuno intatto", async () => {
    const s = sorgenteConCanonico(principaleCon([vineaConAnnunci]), sorgenteCanonica(clienteCon({ data: [RIGA], error: null })));
    const esito = await s.cerca(DOMANDA);
    if (!esito.ok) throw new Error("atteso ok");
    expect(esito.data).toHaveLength(2);
    for (const ordine of ordini(esito.data)) {
      const valutati = valutaCandidati(DOMANDA, ordine);
      expect(valutati).toHaveLength(2);
      const vinea = valutati.find((c) => c.canonico === undefined)!;
      const canon = valutati.find((c) => c.canonico !== undefined)!;
      // Il vino Vinea non riceve alcun LWIN e conserva tipologia, regione e annunci.
      expect(vinea.id).toBe("monfortino-slug");
      expect(vinea.tipo).toBe("Rosso");
      expect(vinea.regione).toBe("Piemonte");
      expect(vinea.annunci).toBe(3);
      expect(aRisultatoRicerca(vinea).identita.codiceLwin).toBeNull();
      // La scheda canonica conserva LWIN, provenienza e attribuzione, e nessun dato Vinea.
      expect(canon.id).toBe(RIGA.vino_id);
      expect(canon.canonico?.lwin7).toBe("1010001");
      expect(canon.tipo).toBeNull();
      expect(canon.annunci).toBe(0);
      const r = aRisultatoRicerca(canon);
      expect(r.identita.codiceLwin).toBe("1010001");
      expect(r.attribuzione?.licenza).toBe("CC BY 4.0");
      // L'ambiguità è dichiarata, non risolta.
      expect(vinea.omonimi).toBe(1);
      expect(canon.omonimi).toBe(1);
    }
  });

  test("FIX-03A: due LWIN diversi con la stessa chiave descrittiva restano distinti, senza scelta per id", () => {
    const a = canonico({ vino_id: "a-id", lwin7: "1010002" });
    const b = canonico({ vino_id: "z-id", lwin7: "1010003" });
    for (const ordine of ordini([a, b])) {
      const valutati = valutaCandidati(DOMANDA, ordine);
      expect(valutati.map((c) => c.canonico?.lwin7).sort()).toEqual(["1010002", "1010003"]);
      expect(valutati.every((c) => c.omonimi === 1)).toBe(true);
    }
    // Stessa risposta con gli id invertiti: l'id non decide nulla.
    const aInv = canonico({ vino_id: "z-id", lwin7: "1010002" });
    const bInv = canonico({ vino_id: "a-id", lwin7: "1010003" });
    expect(valutaCandidati(DOMANDA, [aInv, bInv]).map((c) => c.canonico?.lwin7).sort()).toEqual(["1010002", "1010003"]);
  });

  test("FIX-03A: produttori omonimi di territori diversi restano distinti e riconoscibili dal territorio", () => {
    const piemonte = canonico({ vino_id: "p-id", lwin7: "1010004", territorio: "Piemonte" });
    const toscana = canonico({ vino_id: "t-id", lwin7: "1010005", territorio: "Toscana" });
    const valutati = valutaCandidati(DOMANDA, [toscana, piemonte]);
    expect(valutati).toHaveLength(2);
    expect(valutati.map((c) => c.regione).sort()).toEqual(["Piemonte", "Toscana"]);
  });

  test("FIX-03A: annata o formato diversi non fondono nulla e la scheda canonica non riceve annata né formato", () => {
    const v2015: CandidatoVino = { ...DAL_CATALOGO, id: "v-2015", annata: 2015 };
    const v2016: CandidatoVino = { ...DAL_CATALOGO, id: "v-2016", annata: 2016 };
    const magnum: CandidatoVino = { ...DAL_CATALOGO, id: "v-mag", annata: 2015, formato: "1.5 L" };
    const canon = canonico();
    const valutati = valutaCandidati({ ...DOMANDA, annata: 2015 }, [v2016, canon, magnum, v2015]);
    expect(valutati).toHaveLength(4);
    expect(valutati.find((c) => c.canonico)?.annata).toBeNull();
    // Le quattro schede sono quelle in ingresso, nessuna fusa: tre Vinea intatte (senza LWIN) e una canonica.
    expect(valutati.filter((c) => !c.canonico).map((c) => c.id).sort()).toEqual(["v-2015", "v-2016", "v-mag"]);
    expect(valutati.filter((c) => c.canonico)).toHaveLength(1);
  });

  test("FIX-03A: duplicati realmente equivalenti (stesso LWIN, o stessa scheda ripetuta) collassano in uno", () => {
    const x = canonico({ vino_id: "k-id", lwin7: "1010006" });
    const y = canonico({ vino_id: "b-id", lwin7: "1010006" });
    const z = canonico({ vino_id: "k-id", lwin7: "1010006" });
    for (const ordine of ordini([x, y, z])) {
      const valutati = valutaCandidati(DOMANDA, ordine);
      expect(valutati).toHaveLength(1);
      expect(valutati[0]?.id).toBe("b-id");
      expect(valutati[0]?.occorrenze).toBe(3);
      expect(valutati[0]?.omonimi).toBeUndefined();
    }
    // Più annunci dello stesso vino Vinea: come prima, una riga sola.
    const due = valutaCandidati(DOMANDA, [DAL_CATALOGO, { ...DAL_CATALOGO, id: "monfortino-slug-2" }]);
    expect(due).toHaveLength(1);
    expect(due[0]?.occorrenze).toBe(2);
    expect(due[0]?.canonico).toBeUndefined();
  });

  test("FIX-03A: l'elenco non dipende dall'ordine di arrivo", () => {
    const tutti = [
      { ...DAL_CATALOGO, id: "v1", annata: 2015 },
      { ...DAL_CATALOGO, id: "v2" },
      canonico({ vino_id: "c1", lwin7: "1010007" }),
      canonico({ vino_id: "c2", lwin7: "1010008" }),
    ];
    const atteso = JSON.stringify(valutaCandidati(DOMANDA, tutti));
    for (const ordine of ordini(tutti)) expect(JSON.stringify(valutaCandidati(DOMANDA, ordine))).toBe(atteso);
  });

  test("FIX-03A: con più schede omonime la sintesi è «ambigua», mai «unica»", () => {
    const esatta: CandidatoVino = { ...DAL_CATALOGO, annata: 2015 };
    const valutati = valutaCandidati({ ...DOMANDA, annata: 2015 }, [esatta, canonico()]);
    expect(valutati).toHaveLength(2);
    expect(sintesiRicerca(valutati)).toBe("ambigua");
    // Senza omonimi (canonico spento) il caso esatto resta «unica»: nessuna regressione.
    expect(sintesiRicerca(valutaCandidati({ ...DOMANDA, annata: 2015 }, [esatta]))).toBe("unica");
  });

  test("FIX-03A: scegliere una scheda copia solo campi di visualizzazione; il LWIN non entra nei campi del wizard", () => {
    const conferma = { produttore: "x", nome: "y", annata: "2015", denominazione: "", formato: "" };
    const correnti = { produttore: "", nome: "", annata: "", denominazione: "", regione: "", tipo: "", formato: "" };
    const daCanonico = campiWizardDaConferma(conferma, canonico(), correnti as never, ["Piemonte"]);
    const daVinea = campiWizardDaConferma(conferma, vineaConAnnunci, correnti as never, ["Piemonte"]);
    expect(JSON.stringify(daCanonico)).not.toContain("1010001");
    expect(JSON.stringify(daCanonico)).not.toContain(RIGA.vino_id);
    expect(daCanonico.produttore).toBe("Giacomo Conterno");
    // Le due scelte non si contaminano: la tipologia Vinea arriva solo scegliendo la scheda Vinea.
    expect(daVinea.tipo).toBe("Rosso");
    expect(daCanonico.tipo).toBe("");
  });

  test("tetto di attesa: un canonico lento non trattiene la ricerca principale", async () => {
    const lento: SorgenteCandidati = { codice: "lento", cerca: () => new Promise(() => {}) };
    const s = sorgenteConCanonico(principaleCon([DAL_CATALOGO]), lento, { tettoMs: 20 });
    const inizio = Date.now();
    expect(await s.cerca(DOMANDA)).toEqual({ ok: true, data: [DAL_CATALOGO] });
    expect(Date.now() - inizio).toBeLessThan(1000);
  });

  test("FIX-03B: oltre il tetto la richiesta canonica viene ANNULLATA (AbortSignal), in tempo no", async () => {
    let segnale: AbortSignal | undefined;
    const lento: SorgenteCandidati = {
      codice: "lento",
      cerca: (_d, opzioni) => {
        segnale = opzioni?.segnale;
        return new Promise(() => {});
      },
    };
    await sorgenteConCanonico(principaleCon([DAL_CATALOGO]), lento, { tettoMs: 20 }).cerca(DOMANDA);
    expect(segnale).toBeDefined();
    expect(segnale?.aborted).toBe(true);

    let segnaleVeloce: AbortSignal | undefined;
    const veloce: SorgenteCandidati = {
      codice: "veloce",
      cerca: async (_d, opzioni) => {
        segnaleVeloce = opzioni?.segnale;
        return { ok: true, data: [] };
      },
    };
    await sorgenteConCanonico(principaleCon([DAL_CATALOGO]), veloce, { tettoMs: 1000 }).cerca(DOMANDA);
    expect(segnaleVeloce?.aborted).toBe(false);
  });

  test("FIX-03B: la sorgente canonica passa il segnale alla richiesta RPC (strumento esistente di supabase-js)", async () => {
    const ricevuti: unknown[] = [];
    const client = {
      rpc: () => {
        const richiesta = Promise.resolve({ data: [RIGA], error: null }) as Promise<unknown> & {
          abortSignal: (s: AbortSignal) => unknown;
        };
        richiesta.abortSignal = (s: AbortSignal) => {
          ricevuti.push(s);
          return richiesta;
        };
        return richiesta;
      },
    } as never as ClienteRpcCanonico;
    const controllo = new AbortController();
    const esito = await sorgenteCanonica(client).cerca(DOMANDA, { segnale: controllo.signal });
    expect(esito.ok && esito.data.length).toBe(1);
    expect(ricevuti).toEqual([controllo.signal]);
    // Un client senza `abortSignal` (fake semplici) continua a funzionare.
    const semplice = await sorgenteCanonica(clienteCon({ data: [RIGA], error: null })).cerca(DOMANDA, {
      segnale: controllo.signal,
    });
    expect(semplice.ok && semplice.data.length).toBe(1);
  });

  test("FIX-03B: una richiesta annullata dal tetto non è un errore per l'utente", async () => {
    const annullabile: SorgenteCandidati = {
      codice: "annullabile",
      cerca: (_d, opzioni) =>
        new Promise((_ok, ko) => opzioni?.segnale?.addEventListener("abort", () => ko(new Error("abort")))),
    };
    const esito = await sorgenteConCanonico(principaleCon([DAL_CATALOGO]), annullabile, { tettoMs: 20 }).cerca(DOMANDA);
    expect(esito).toEqual({ ok: true, data: [DAL_CATALOGO] });
  });

  test("tetto di attesa: un canonico che risponde in tempo viene usato", async () => {
    const s = sorgenteConCanonico(
      principaleCon([DAL_CATALOGO]),
      sorgenteCanonica(clienteCon({ data: [RIGA], error: null })),
      { tettoMs: 1000 },
    );
    const esito = await s.cerca(DOMANDA);
    expect(esito.ok && esito.data.length).toBe(2);
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
