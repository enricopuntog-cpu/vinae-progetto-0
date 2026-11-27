import { describe, expect, it } from "bun:test";
import { cercaCorrispondenze } from "@/lib/vendi/foto-etichetta/pipeline";
import type {
  CandidatoVino,
  DomandaCandidati,
  SorgenteCandidati,
} from "@/lib/vendi/foto-etichetta/candidati";
import { valutaCandidati } from "@/lib/vendi/foto-etichetta/candidati";
import { aRisultatoRicerca } from "./contratto";
import {
  LIMITE_RISULTATI_SERVER,
  MESSAGGIO_TROPPE_RICERCHE,
  type ClienteRpc,
  candidatoDaRigaRpc,
  creaMotoreRicerca,
  sorgenteConRipiego,
  sorgenteDaRpc,
} from "./rpc";
import { MESSAGGIO_RICERCA_NON_DISPONIBILE } from "./sorgenti";

const dom = (produttore: string, nome: string, annata: number | null = null, formato: string | null = null): DomandaCandidati => ({
  produttore, nome, annata, formato,
});

const riga = (extra: Record<string, unknown> = {}) => ({
  fonte: "catalogo_vinea",
  vino_id: "11111111-1111-4111-8111-111111111111",
  slug: "tignanello-2019",
  produttore: "Antinori",
  nome: "Tignanello",
  annata: 2019,
  formato: "0,75 L",
  regione: "Toscana",
  denominazione: "IGT",
  tipo: "Rosso",
  annunci: 0,
  punteggio: 100,
  livello: "esatto",
  ...extra,
});

type Chiamata = { nome: string; argomenti: Record<string, unknown> };
function clienteRpc(risposta: () => Promise<{ data: unknown; error: unknown }>) {
  const chiamate: Chiamata[] = [];
  return {
    chiamate,
    rpc: (nome: string, argomenti: Record<string, unknown>) => {
      chiamate.push({ nome, argomenti });
      return risposta();
    },
  } as never as Parameters<typeof sorgenteDaRpc>[0] & { chiamate: Chiamata[] };
}

describe("candidatoDaRigaRpc", () => {
  it("porta la riga nel contratto, con livello e punteggio del server", () => {
    const c = candidatoDaRigaRpc(riga());
    expect(c).toEqual({
      fonte: "catalogo_vinea",
      id: "tignanello-2019",
      produttore: "Antinori",
      nome: "Tignanello",
      annata: 2019,
      formato: "0,75 L",
      regione: "Toscana",
      denominazione: "IGT",
      tipo: "Rosso",
      corrispondenzaServer: { livello: "esatto", punteggio: 100 },
      annunci: 0,
    });
  });

  it("scarta le righe senza identità e tollera campi mancanti o di tipo sbagliato", () => {
    expect(candidatoDaRigaRpc(null)).toBeNull();
    expect(candidatoDaRigaRpc("x")).toBeNull();
    expect(candidatoDaRigaRpc(riga({ produttore: "  " }))).toBeNull();
    expect(candidatoDaRigaRpc(riga({ nome: 5 }))).toBeNull();
    expect(candidatoDaRigaRpc(riga({ slug: null, vino_id: null }))).toBeNull();
    const c = candidatoDaRigaRpc(riga({ annata: "2019", formato: null, regione: null, livello: "boh", punteggio: "x", annunci: -3 }));
    expect(c?.annata).toBeNull();
    expect(c?.formato).toBeNull();
    expect(c?.corrispondenzaServer).toBeUndefined();
    expect(c?.annunci).toBe(0);
  });

  it("senza slug usa l'uuid del vino come identificativo", () => {
    expect(candidatoDaRigaRpc(riga({ slug: null }))?.id).toBe("11111111-1111-4111-8111-111111111111");
  });
});

describe("sorgenteDaRpc", () => {
  it("chiama vini_cerca con la domanda e il tetto, e restituisce i candidati nell'ordine del server", async () => {
    const client = clienteRpc(async () => ({
      data: [riga(), riga({ slug: "tignanello-2016", annata: 2016, punteggio: 90, livello: "prefisso" })],
      error: null,
    }));
    const e = await sorgenteDaRpc(client).cerca(dom("Antinori", "Tignanello", 2019, "0,75 L"));
    expect(e.ok && e.data.map((c) => c.id)).toEqual(["tignanello-2019", "tignanello-2016"]);
    expect(client!.chiamate).toHaveLength(1);
    expect(client!.chiamate[0]).toEqual({
      nome: "vini_cerca",
      argomenti: { p_produttore: "Antinori", p_nome: "Tignanello", p_annata: 2019, p_formato: "0,75 L", p_limite: LIMITE_RISULTATI_SERVER },
    });
  });

  it("senza parole utili non fa nessuna richiesta", async () => {
    const client = clienteRpc(async () => ({ data: [riga()], error: null }));
    const e = await sorgenteDaRpc(client).cerca(dom("di", "il"));
    expect(e).toEqual({ ok: true, data: [] });
    expect(client!.chiamate).toHaveLength(0);
  });

  it("errore del server, risposta non valida, eccezione e client assente sono errori, non «nessun risultato»", async () => {
    for (const risposta of [
      async () => ({ data: null, error: { message: "boom" } }),
      async () => ({ data: { non: "un array" }, error: null }),
      async () => {
        throw new Error("rete");
      },
    ]) {
      const e = await sorgenteDaRpc(clienteRpc(risposta)).cerca(dom("Antinori", "Tignanello"));
      expect(e).toEqual({ ok: false, error: MESSAGGIO_RICERCA_NON_DISPONIBILE });
    }
    expect(await sorgenteDaRpc(null).cerca(dom("Antinori", "Tignanello"))).toEqual({
      ok: false,
      error: MESSAGGIO_RICERCA_NON_DISPONIBILE,
    });
  });

  it("zero risultati è una risposta valida", async () => {
    const e = await sorgenteDaRpc(clienteRpc(async () => ({ data: [], error: null }))).cerca(dom("Zzqxj", "Qwzxcv"));
    expect(e).toEqual({ ok: true, data: [] });
  });
});

describe("WI-016 — il rifiuto per protezione non diventa altro carico", () => {
  const clienteCheRifiuta = (code: string): ClienteRpc =>
    ({ rpc: async () => ({ data: null, error: { code, message: "x" } }) }) as unknown as ClienteRpc;

  it.each(["rate_limit_exceeded", "troppe_ricerche_in_corso", "ricerca_satura"])(
    "%s: messaggio di attesa, distinto dal guasto",
    async (code) => {
      const e = await sorgenteDaRpc(clienteCheRifiuta(code)).cerca(dom("Produttore", "Barolo"));
      expect(e).toEqual({ ok: false, error: MESSAGGIO_TROPPE_RICERCHE });
    },
  );

  it("dopo un limite NON parte il ripiego (che leggerebbe le tabelle più volte)", async () => {
    let ripieghi = 0;
    const ripiego = {
      codice: "r",
      cerca: async () => {
        ripieghi++;
        return { ok: true as const, data: [] };
      },
    };
    const e = await sorgenteConRipiego(sorgenteDaRpc(clienteCheRifiuta("rate_limit_exceeded")), ripiego).cerca(
      dom("Produttore", "Barolo"),
    );
    expect(e).toEqual({ ok: false, error: MESSAGGIO_TROPPE_RICERCHE });
    expect(ripieghi).toBe(0);
  });

  it("un guasto vero continua a usare il ripiego", async () => {
    let ripieghi = 0;
    const ripiego = {
      codice: "r",
      cerca: async () => {
        ripieghi++;
        return { ok: true as const, data: [] };
      },
    };
    await sorgenteConRipiego(sorgenteDaRpc(clienteCheRifiuta("PGRST202")), ripiego).cerca(dom("Produttore", "Barolo"));
    expect(ripieghi).toBe(1);
  });
});

describe("sorgenteConRipiego", () => {
  const fissa = (codice: string, esito: Awaited<ReturnType<SorgenteCandidati["cerca"]>>): SorgenteCandidati & { n: number } => {
    const s = { codice, n: 0, cerca: async () => { s.n++; return esito; } };
    return s;
  };
  const uno: CandidatoVino = {
    fonte: "x", id: "a", produttore: "A", nome: "B", annata: null, formato: null, regione: null, denominazione: null, tipo: null,
  };

  it("usa il ripiego solo se la primaria fallisce", async () => {
    const primaria = fissa("p", { ok: false, error: "no" });
    const ripiego = fissa("r", { ok: true, data: [uno] });
    const e = await sorgenteConRipiego(primaria, ripiego).cerca(dom("A", "B"));
    expect(e).toEqual({ ok: true, data: [uno] });
    expect(ripiego.n).toBe(1);
  });

  it("un elenco vuoto dalla primaria NON attiva il ripiego", async () => {
    const primaria = fissa("p", { ok: true, data: [] });
    const ripiego = fissa("r", { ok: true, data: [uno] });
    const e = await sorgenteConRipiego(primaria, ripiego).cerca(dom("A", "B"));
    expect(e).toEqual({ ok: true, data: [] });
    expect(ripiego.n).toBe(0);
  });

  it("se falliscono entrambe l'errore resta un errore", async () => {
    const e = await sorgenteConRipiego(fissa("p", { ok: false, error: "1" }), fissa("r", { ok: false, error: "2" })).cerca(dom("A", "B"));
    expect(e.ok).toBe(false);
  });

  it("creaMotoreRicerca: con la RPC non migrata ripiega sulle tabelle senza rompere la ricerca", async () => {
    const tabelle = {
      from: () => {
        const q: Record<string, unknown> = {};
        for (const m of ["select", "or", "order"]) q[m] = () => q;
        q.limit = async () => ({
          data: [{ id: "i", slug: "tignanello-2019", produttore: "Antinori", nome: "Tignanello", annata: 2019, regione: "Toscana", denominazione: "IGT", tipo: "Rosso", formato: "0,75 L" }],
          error: null,
        });
        return q;
      },
      rpc: async () => ({ data: null, error: { message: "function does not exist" } }),
    };
    const e = await creaMotoreRicerca(tabelle as never).cerca(dom("Antinori", "Tignanello", 2019));
    expect(e.ok && e.data.length).toBeGreaterThan(0);
  });
});

describe("integrazione con la valutazione e il contratto", () => {
  it("l'ordine del server arriva fino al wizard: esatta davanti, annata diversa dopo", async () => {
    const client = clienteRpc(async () => ({
      data: [
        riga(),
        riga({ slug: "tignanello-2016", annata: 2016, livello: "esatto", punteggio: 100 }),
      ],
      error: null,
    }));
    const esito = await cercaCorrispondenze(dom("Antinori", "Tignanello", 2019, "0,75 L"), sorgenteDaRpc(client));
    expect(esito.ok).toBe(true);
    if (esito.ok) {
      expect(esito.candidati.map((c) => [c.id, c.esito])).toEqual([
        ["tignanello-2019", "esatta"],
        ["tignanello-2016", "annata_diversa"],
      ]);
      expect(esito.candidati[0].corrispondenzaServer?.livello).toBe("esatto");
    }
  });

  it("aRisultatoRicerca: identità, annata, formato, provenienza e qualità distinte; nessun prezzo; LWIN non disponibile", () => {
    const [v] = valutaCandidati(dom("Antinori", "Tignanello", 2019), [candidatoDaRigaRpc(riga({ annunci: 3 }))!]);
    const r = aRisultatoRicerca(v);
    expect(r.identita).toEqual({
      id: "tignanello-2019", produttore: "Antinori", nome: "Tignanello", regione: "Toscana",
      denominazione: "IGT", tipo: "Rosso", codiceLwin: null,
    });
    expect(r.annata).toBe(2019);
    expect(r.formato).toBe("0,75 L");
    expect(r.provenienza).toEqual({ fonte: "catalogo_vinea", annunciAttivi: 3 });
    expect(r.corrispondenza).toMatchObject({ esito: "esatta", livelloServer: "esatto" });
    expect(r.nonDisponibile).toContain("codice_lwin");
    expect(JSON.stringify(r)).not.toMatch(/prezz|price|cents/i);
  });
});
