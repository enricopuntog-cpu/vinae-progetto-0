import { describe, expect, it } from "bun:test";
import { cercaCorrispondenze } from "@/lib/vendi/foto-etichetta/pipeline";
import type { DomandaCandidati, SorgenteCandidati } from "@/lib/vendi/foto-etichetta/candidati";
import {
  type ClienteRicerca,
  creaSorgenteRicerca,
  sorgenteComposta,
  sorgenteDaAnnunciPubblici,
  sorgenteDaCatalogo,
} from "./sorgenti";

type Riga = Record<string, unknown>;

type Chiamata = {
  tabella: string;
  select: string;
  or: string[];
  order: string[];
  limit: number | null;
};

/**
 * Un PostgREST in miniatura: applica gli stessi `ilike` (senza piegare gli
 * accenti, come PostgreSQL), l'AND tra più `.or()`, l'ordine e il tetto. Le
 * righe che contiene sono quelle che RLS lascerebbe vedere all'utente: la
 * visibilità la decide il database, qui si prova solo ciò che il client chiede.
 */
function clienteFinto(
  tabelle: Record<string, Riga[]>,
  { errore = [] as string[], log = [] as Chiamata[] } = {},
): ClienteRicerca & { log: Chiamata[] } {
  const valuta = (riga: Riga, filtro: string) =>
    filtro.split(",").some((cond) => {
      const m = /^([a-z_]+)\.ilike\.\*(.+)\*$/.exec(cond);
      if (!m) throw new Error(`filtro non supportato: ${cond}`);
      return String(riga[m[1]] ?? "").toLowerCase().includes(m[2].toLowerCase());
    });
  return {
    log,
    from(tabella: string) {
      const c: Chiamata = { tabella, select: "", or: [], order: [], limit: null };
      const b = {
        select(colonne: string) {
          c.select = colonne;
          return b;
        },
        or(f: string) {
          c.or.push(f);
          return b;
        },
        order(col: string) {
          c.order.push(col);
          return b;
        },
        limit(n: number) {
          c.limit = n;
          return b;
        },
        then(ok: (v: unknown) => unknown, ko?: (e: unknown) => unknown) {
          log.push(c);
          if (errore.includes(tabella)) {
            return Promise.resolve({ data: null, error: { message: "boom" } }).then(ok, ko);
          }
          let righe = (tabelle[tabella] ?? []).filter((r) => c.or.every((f) => valuta(r, f)));
          righe = [...righe].sort((a, z) => {
            for (const col of c.order) {
              const x = a[col] as string | number;
              const y = z[col] as string | number;
              if (x < y) return -1;
              if (x > y) return 1;
            }
            return 0;
          });
          return Promise.resolve({ data: righe.slice(0, c.limit ?? 1000), error: null }).then(ok, ko);
        },
      };
      return b;
    },
  } as unknown as ClienteRicerca & { log: Chiamata[] };
}

const riga = (slug: string, produttore: string, nome: string, annata: number, extra: Riga = {}): Riga => ({
  id: `id-${slug}`,
  slug,
  wine_id: `id-${slug}`,
  wine_slug: slug,
  produttore,
  nome,
  annata,
  regione: "Toscana",
  denominazione: "",
  tipo: "Rosso",
  formato: "0,75 L",
  // `public_listings.ricerca`
  ricerca: `${produttore} ${nome}`,
  ...extra,
});

const dom = (produttore: string, nome: string, annata: number | null = null, formato: string | null = null): DomandaCandidati => ({
  produttore,
  nome,
  annata,
  formato,
});

const CATALOGO = [
  riga("tignanello-2019", "Marchesi Antinori", "Tignanello", 2019),
  riga("tignanello-2018", "Marchesi Antinori", "Tignanello", 2018),
  riga("solaia-2018", "Marchesi Antinori", "Solaia", 2018),
  riga("sassicaia-2018", "Tenuta San Guido", "Sassicaia", 2018),
  riga("tignanelli-2019", "Cantina Lontana", "Tignanello Riserva", 2019),
  riga("dom-perignon-2013", "Moët & Chandon", "Dom Pérignon", 2013, { tipo: "Bollicine" }),
  riga("magnum-tignanello-2019", "Marchesi Antinori", "Tignanello", 2019, { formato: "1,5 L" }),
];

const cerca = async (s: SorgenteCandidati, d: DomandaCandidati) => {
  const e = await cercaCorrispondenze(d, s);
  if (!e.ok) throw new Error(e.messaggio);
  return e;
};

describe("sorgenteDaCatalogo — ricerca lato database", () => {
  const sorgente = () => sorgenteDaCatalogo(clienteFinto({ wines: CATALOGO }));

  it("ricerca esatta: un solo candidato esatto", async () => {
    const e = await cerca(sorgente(), dom("Marchesi Antinori", "Solaia", 2018));
    expect(e.candidati[0].id).toBe("solaia-2018");
    expect(e.candidati[0].esito).toBe("esatta");
    expect(e.sintesi).toBe("unica");
  });

  it("produttore parziale", async () => {
    const e = await cerca(sorgente(), dom("Antinori", "Solaia", 2018));
    expect(e.candidati[0].id).toBe("solaia-2018");
  });

  it("refuso OCR nel nome: il livello tollerante lo recupera", async () => {
    const e = await cerca(sorgente(), dom("Antinori", "Tignaello", 2019));
    expect(e.candidati[0].nome).toBe("Tignanello");
    expect(e.candidati[0].annata).toBe(2019);
  });

  it("accento perso: Dom Perignon trova Dom Pérignon", async () => {
    const e = await cerca(sorgente(), dom("", "Dom Perignon", 2013));
    expect(e.candidati[0].id).toBe("dom-perignon-2013");
  });

  it("annata diversa: stesso vino, annata diversa, mai «esatta»", async () => {
    const e = await cerca(sorgente(), dom("Antinori", "Solaia", 2015));
    expect(e.candidati[0].id).toBe("solaia-2018");
    expect(e.candidati[0].esito).toBe("annata_diversa");
    expect(e.sintesi).toBe("ambigua");
  });

  it("formato diverso: il formato non è nel filtro, distingue ma non esclude", async () => {
    const e = await cerca(sorgente(), dom("Antinori", "Tignanello", 2019, "0,375 L"));
    const formati = e.candidati.map((c) => c.formato).sort();
    expect(formati).toContain("0,75 L");
    expect(formati).toContain("1,5 L");
    expect(e.candidati.every((c) => c.esito === "formato_diverso" || c.esito === "annata_diversa")).toBe(true);
  });

  it("vini con nome simile: restano candidati distinti e la scelta è dell’utente", async () => {
    const e = await cerca(sorgente(), dom("", "Tignanello", 2019));
    const ids = e.candidati.map((c) => c.id);
    expect(ids).toContain("tignanello-2019");
    expect(ids).toContain("tignanelli-2019");
    expect(e.sintesi).toBe("ambigua");
  });

  it("nessun risultato: elenco vuoto, non errore", async () => {
    const e = await cerca(sorgente(), dom("Zzzzzz", "Qqqqqqq"));
    expect(e.candidati).toEqual([]);
    expect(e.sintesi).toBe("nessuna");
  });

  it("domanda vuota o senza parole utili: nessuna richiesta al database", async () => {
    const client = clienteFinto({ wines: CATALOGO });
    const s = sorgenteDaCatalogo(client);
    expect(await s.cerca(dom("", ""))).toEqual({ ok: true, data: [] });
    expect(await s.cerca(dom("di", "il"))).toEqual({ ok: true, data: [] });
    expect(client.log).toHaveLength(0);
  });

  it("errore del database: errore con messaggio fisso, non «nessun risultato»", async () => {
    const s = sorgenteDaCatalogo(clienteFinto({ wines: CATALOGO }, { errore: ["wines"] }));
    const e = await s.cerca(dom("Antinori", "Solaia"));
    expect(e).toEqual({ ok: false, error: "Non è stato possibile consultare i vini già presenti su Vinea." });
    const p = await cercaCorrispondenze(dom("Antinori", "Solaia"), s);
    expect(p.ok).toBe(false);
  });

  it("senza client (Supabase assente): errore, non vuoto", async () => {
    const e = await sorgenteDaCatalogo(null).cerca(dom("Antinori", "Solaia"));
    expect(e.ok).toBe(false);
  });

  it("un'eccezione del trasporto diventa un errore senza dettagli", async () => {
    const client = {
      from() {
        throw new Error("rete giù: https://segreto");
      },
    } as unknown as ClienteRicerca;
    const e = await sorgenteDaCatalogo(client).cerca(dom("Antinori", "Solaia"));
    expect(e).toEqual({ ok: false, error: "Non è stato possibile consultare i vini già presenti su Vinea." });
  });

  it("chiede solo colonne pubbliche del GRANT, mai creato_da o provenienza", async () => {
    const client = clienteFinto({ wines: CATALOGO });
    await sorgenteDaCatalogo(client).cerca(dom("Antinori", "Solaia"));
    for (const c of client.log) {
      expect(c.select).not.toContain("creato_da");
      expect(c.select).not.toContain("provenienza");
      expect(c.select).not.toBe("*");
    }
  });
});

describe("limiti e costo", () => {
  it("ogni richiesta ha un filtro, un tetto e un ordine totale: mai l'intera tabella", async () => {
    const client = clienteFinto({ wines: CATALOGO, public_listings: CATALOGO });
    await creaSorgenteRicerca(client).cerca(dom("Antinori", "Tignaello", 2019));
    expect(client.log.length).toBeGreaterThan(0);
    for (const c of client.log) {
      expect(c.or.length).toBeGreaterThan(0);
      expect(c.limit).not.toBeNull();
      expect(c.limit as number).toBeLessThanOrEqual(60);
      expect(c.order.length).toBeGreaterThanOrEqual(4);
    }
  });

  it("un vino noto costa una sola richiesta per fonte", async () => {
    const client = clienteFinto({ wines: CATALOGO, public_listings: [] });
    await creaSorgenteRicerca(client).cerca(dom("Antinori", "Tignanello", 2019));
    expect(client.log.filter((c) => c.tabella === "wines")).toHaveLength(1);
  });

  it("anche nel caso peggiore al più tre richieste per fonte, non una per riga", async () => {
    const client = clienteFinto({ wines: CATALOGO, public_listings: CATALOGO });
    await creaSorgenteRicerca(client).cerca(dom("Xyzzyqwerty", "Qwertyzxcv"));
    expect(client.log.filter((c) => c.tabella === "wines").length).toBeLessThanOrEqual(3);
    expect(client.log.filter((c) => c.tabella === "public_listings").length).toBeLessThanOrEqual(3);
  });
});

describe("dataset grande (sintetico)", () => {
  const produttori = ["Castello", "Tenuta", "Podere", "Cantina", "Fattoria", "Villa", "Azienda", "Masseria"];
  const luoghi = ["Alba", "Bolgheri", "Chianti", "Etna", "Franciacorta", "Langa", "Montalcino", "Soave", "Taurasi", "Verona"];
  const nomi = ["Riserva", "Vigna", "Selezione", "Cru", "Superiore", "Rosso", "Bianco", "Brut"];
  const molti: Riga[] = [];
  for (let i = 0; i < 20_000; i++) {
    const p = `${produttori[i % 8]} ${luoghi[(i >> 3) % 10]} ${i}`;
    const n = `${nomi[(i >> 5) % 8]} ${luoghi[(i >> 7) % 10]} ${i}`;
    molti.push(riga(`sint-${i}`, p, n, 1990 + (i % 30)));
  }
  molti.push(riga("bersaglio-2016", "Poderi Zanzibar", "Obliquo Grande Cuvée", 2016));

  it("trova l'ago con 20.000 vini senza portare nel browser più del tetto", async () => {
    const client = clienteFinto({ wines: molti, public_listings: [] });
    const e = await cerca(creaSorgenteRicerca(client), dom("Poderi Zanzibar", "Obliquo Grande Cuvée", 2016));
    expect(e.candidati[0].id).toBe("bersaglio-2016");
    expect(e.candidati[0].esito).toBe("esatta");
  });

  it("una domanda generica non scarica il catalogo: tetto rispettato, risultati ≤ 5", async () => {
    const client = clienteFinto({ wines: molti, public_listings: [] });
    const t0 = performance.now();
    const e = await cerca(creaSorgenteRicerca(client), dom("Castello", "Riserva"));
    const durata = performance.now() - t0;
    expect(e.candidati.length).toBeLessThanOrEqual(5);
    for (const c of client.log) expect(c.limit as number).toBeLessThanOrEqual(60);
    // Il matching nel browser vede al più `somma dei tetti` righe, non 20.000.
    expect(durata).toBeLessThan(2000);
  });

  it("il refuso nel produttore con 20.000 righe resta limitato e ordinato in modo stabile", async () => {
    const client = clienteFinto({ wines: molti, public_listings: [] });
    const a = await cerca(creaSorgenteRicerca(client), dom("Zanzibarr", "Obliquo Grande", 2016));
    const b = await cerca(creaSorgenteRicerca(client), dom("Zanzibarr", "Obliquo Grande", 2016));
    expect(a.candidati.map((c) => c.id)).toEqual(b.candidati.map((c) => c.id));
    expect(a.candidati[0].id).toBe("bersaglio-2016");
  });
});

describe("sorgenteComposta", () => {
  const ok = (id: string): SorgenteCandidati => ({
    codice: id,
    cerca: async () => ({
      ok: true,
      data: [{ fonte: id, id, produttore: "A", nome: "B", annata: 2019, formato: "0,75 L", regione: null, denominazione: null, tipo: null }],
    }),
  });
  const vuota: SorgenteCandidati = { codice: "v", cerca: async () => ({ ok: true, data: [] }) };
  const rotta: SorgenteCandidati = { codice: "r", cerca: async () => ({ ok: false, error: "x" }) };
  const lancia: SorgenteCandidati = {
    codice: "l",
    cerca: async () => {
      throw new Error("dettagli interni");
    },
  };

  it("unisce i risultati di più fonti", async () => {
    const e = await sorgenteComposta([ok("a"), ok("b")]).cerca(dom("A", "B"));
    expect(e.ok && e.data.map((c) => c.id)).toEqual(["a", "b"]);
  });
  it("una fonte rotta non cancella i risultati dell'altra", async () => {
    const e = await sorgenteComposta([rotta, ok("b")]).cerca(dom("A", "B"));
    expect(e.ok && e.data).toHaveLength(1);
  });
  it("tutte vuote: nessun risultato", async () => {
    expect(await sorgenteComposta([vuota, vuota]).cerca(dom("A", "B"))).toEqual({ ok: true, data: [] });
  });
  it("una fonte rotta e l'altra vuota: errore, perché «non trovato» sarebbe falso", async () => {
    const e = await sorgenteComposta([rotta, vuota]).cerca(dom("A", "B"));
    expect(e.ok).toBe(false);
  });
  it("un'eccezione di una fonte è un errore pulito", async () => {
    const e = await sorgenteComposta([lancia]).cerca(dom("A", "B"));
    expect(e).toEqual({ ok: false, error: "Non è stato possibile consultare i vini già presenti su Vinea." });
  });
});

describe("nessuna fusione e nessun duplicato", () => {
  it("lo stesso vino da catalogo e da annunci è un solo candidato", async () => {
    const client = clienteFinto({
      wines: CATALOGO,
      public_listings: [CATALOGO[0], { ...CATALOGO[0], id: "altro-annuncio" }],
    });
    const e = await cerca(creaSorgenteRicerca(client), dom("Antinori", "Tignanello", 2019, "0,75 L"));
    const tignanello = e.candidati.filter((c) => c.id === "tignanello-2019");
    expect(tignanello).toHaveLength(1);
  });

  it("le sorgenti sono di sola lettura: l'unica chiamata del client è from(...).select", async () => {
    const usati: string[] = [];
    const client = {
      from() {
        const b: Record<string, unknown> = {};
        for (const m of ["select", "or", "order", "limit"]) {
          b[m] = () => {
            usati.push(m);
            return b;
          };
        }
        b.then = (ok: (v: unknown) => unknown) => Promise.resolve({ data: [], error: null }).then(ok);
        return b;
      },
    } as unknown as ClienteRicerca;
    await sorgenteDaAnnunciPubblici(client).cerca(dom("Antinori", "Solaia"));
    expect(new Set(usati)).toEqual(new Set(["select", "or", "order", "limit"]));
  });
});
