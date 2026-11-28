import { describe, expect, it } from "bun:test";
import { cercaCorrispondenze } from "@/lib/vendi/foto-etichetta/pipeline";
import type {
  DomandaCandidati,
} from "@/lib/vendi/foto-etichetta/candidati";
import { valutaCandidati } from "@/lib/vendi/foto-etichetta/candidati";
import { aRisultatoRicerca } from "./contratto";
import {
  LIMITE_RISULTATI_SERVER,
  MESSAGGIO_TROPPE_RICERCHE,
  type ClienteRpc,
  candidatoDaRigaRpc,
  creaMotoreRicerca,
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

});

describe("WI-017 — il motore usa solo le RPC protette", () => {
  it.each([
    [429, "", MESSAGGIO_TROPPE_RICERCHE],
    [503, "lettura_non_disponibile", MESSAGGIO_RICERCA_NON_DISPONIBILE],
    [504, "57014", MESSAGGIO_RICERCA_NON_DISPONIBILE],
    [403, "42501", MESSAGGIO_RICERCA_NON_DISPONIBILE],
    [404, "PGRST202", MESSAGGIO_RICERCA_NON_DISPONIBILE],
    [503, "ricerca_satura", MESSAGGIO_TROPPE_RICERCHE],
  ])("HTTP %i, codice %s: zero letture dirette", async (status, code, messaggio) => {
    let lettureDirette = 0;
    const client = {
      from: () => { lettureDirette++; throw new Error("Lettura diretta inattesa"); },
      rpc: async () => ({ status, data: null, error: { code, message: "x" } }),
    };
    const esito = await creaMotoreRicerca(client as never).cerca(dom("Antinori", "Tignanello"));
    expect(lettureDirette).toBe(0);
    expect(esito).toEqual({ ok: false, error: messaggio });
  });

  it("uno zero di entrambe le RPC è un risultato valido", async () => {
    const client = clienteRpc(async () => ({ data: [], error: null }));
    expect(await creaMotoreRicerca(client).cerca(dom("Antinori", "Tignanello")))
      .toEqual({ ok: true, data: [] });
    expect(client!.chiamate.map(({ nome }) => nome)).toEqual(["vini_cerca", "vini_canonici_cerca"]);
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
