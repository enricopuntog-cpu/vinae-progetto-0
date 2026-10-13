/**
 * Pre-lancio: indirizzi strutturati e logistica pronta per API.
 *
 * Proprietario, Paese, costo, servizio e corriere li decide il database. Questi
 * test fissano che l'adattatore passi solo i dati dell'utente alle porte, che
 * una risposta incoerente non diventi un indirizzo o un importo, che la
 * riservatezza per parte arrivi intatta e che il preventivo conosca il ritiro
 * in sede e il domicilio addebitato.
 */
import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  creaIndirizziService,
  leggiIndirizziOrdine,
  leggiIndirizzo,
} from "@/services/indirizzi-service";
import { leggiPreventivoLogistica } from "@/services/logistica-service";
import { etichettaMancanza, etichettaModalita } from "@/lib/logistica/etichette";

const radice = join(import.meta.dir, "../../..");
const migrazione = readFileSync(
  join(radice, "supabase/migrations/20261013160000_logistica_indirizzi_api.sql"),
  "utf8",
).replace(/--.*$/gm, "");

type Esito = { data: unknown; error: { code?: string; message?: string; hint?: string } | null };

function clientRpc(risposte: Esito[]) {
  const chiamate: Array<{ nome: string; parametri: unknown }> = [];
  const client = {
    rpc: (nome: string, parametri?: unknown) => {
      chiamate.push({ nome, parametri });
      const r = risposte.shift();
      if (!r) throw new Error("risposta fake mancante");
      return Promise.resolve(r);
    },
    from: () => {
      throw new Error("il servizio indirizzi non legge tabelle");
    },
  } as unknown as SupabaseClient;
  return { client, chiamate };
}

const riga = {
  id: "i-1",
  etichetta: null,
  destinatario: "Bruno Rossi",
  via: "Via delle Vigne 3",
  cap: "12051",
  citta: "Alba",
  provincia: "CN",
  paese: "IT",
  telefono: "+39 333 1234567",
  note: null,
  predefinitoRitiro: false,
  predefinitoConsegna: true,
  updatedAt: "2026-10-13T10:00:00Z",
};

const input = {
  etichetta: "  ",
  destinatario: " Bruno Rossi ",
  via: "Via delle Vigne 3",
  cap: " 12051 ",
  citta: "Alba",
  provincia: "cn",
  telefono: "",
  note: "",
  predefinitoRitiro: false,
  predefinitoConsegna: true,
};

describe("IndirizziService", () => {
  it("salva passa solo i dati normalizzati: nessun proprietario, nessun Paese", async () => {
    const { client, chiamate } = clientRpc([{ data: riga, error: null }]);
    const esito = await creaIndirizziService(client).salva(null, input);
    expect(esito.ok && esito.data.provincia).toBe("CN");
    expect(chiamate[0]).toEqual({
      nome: "indirizzo_salva",
      parametri: {
        p_id: null,
        p_etichetta: null,
        p_destinatario: "Bruno Rossi",
        p_via: "Via delle Vigne 3",
        p_cap: "12051",
        p_citta: "Alba",
        p_provincia: "CN",
        p_telefono: null,
        p_note: null,
        p_predefinito_ritiro: false,
        p_predefinito_consegna: true,
      },
    });
    const parametri = chiamate[0].parametri as Record<string, unknown>;
    expect("p_paese" in parametri || "p_user_id" in parametri).toBe(false);
  });

  it("un elenco con una riga malformata è un errore, non un elenco parziale", async () => {
    const { client } = clientRpc([{ data: [riga, { ...riga, cap: "1205" }], error: null }]);
    const esito = await creaIndirizziService(client).miei();
    expect(esito.ok).toBe(false);
  });

  it("gli errori del database diventano frasi per chi legge", async () => {
    const { client } = clientRpc([
      { data: null, error: { code: "P0001", hint: "troppi_indirizzi", message: "x" } },
      { data: null, error: { code: "22023", message: "Il CAP deve avere 5 cifre." } },
      { data: null, error: { code: "XX000", message: "relation private.indirizzi" } },
    ]);
    const s = creaIndirizziService(client);
    expect(await s.salva(null, input)).toEqual({
      ok: false,
      error: "Hai raggiunto il numero massimo di indirizzi (20).",
    });
    expect(await s.salva(null, input)).toEqual({ ok: false, error: "Il CAP deve avere 5 cifre." });
    const r = await s.salva(null, input);
    expect(r.ok === false && r.error.includes("private")).toBe(false);
  });

  it("la consegna al punto non invia un indirizzo; il domicilio sì", async () => {
    const { client, chiamate } = clientRpc([
      { data: { listingId: "l-1", destinazione: "pudo", indirizzoId: null }, error: null },
      { data: { listingId: "l-1", destinazione: "home", indirizzoId: "i-1" }, error: null },
    ]);
    const s = creaIndirizziService(client);
    expect((await s.impostaConsegna("l-1", "pudo", "i-1")).ok).toBe(true);
    expect((await s.impostaConsegna("l-1", "home", "i-1")).ok).toBe(true);
    expect(chiamate.map((c) => c.parametri)).toEqual([
      { p_listing_id: "l-1", p_destinazione: "pudo", p_indirizzo_id: null },
      { p_listing_id: "l-1", p_destinazione: "home", p_indirizzo_id: "i-1" },
    ]);
  });

  it("indirizzi dell'ordine: il dettaglio c'è solo per la parte che legge; null se non congelati", async () => {
    const venditore = {
      origine: { tipo: "sede", citta: "Torino", provincia: "TO", destinatario: "Enoteca", via: "Corso 9", cap: "10121", paese: "IT", telefono: null },
      destinazione: { tipo: "domicilio", citta: "Alba", provincia: "CN" },
      congelatoAt: "2026-10-13T10:00:00Z",
    };
    const { client } = clientRpc([
      { data: venditore, error: null },
      { data: null, error: null },
      { data: { ...venditore, destinazione: { tipo: "sede", citta: "X", provincia: "XX" } }, error: null },
    ]);
    const s = creaIndirizziService(client);
    const a = await s.ordine("o-1");
    expect(a.ok && a.data?.origine.dettaglio?.via).toBe("Corso 9");
    expect(a.ok && a.data?.destinazione.dettaglio).toBeNull();
    expect(a.ok && a.data?.destinazione.citta).toBe("Alba");
    expect(await s.ordine("o-1")).toEqual({ ok: true, data: null });
    expect((await s.ordine("o-1")).ok).toBe(false);
  });

  it("parser: provincia e Paese a due lettere maiuscole, booleani veri", () => {
    expect(leggiIndirizzo(riga)?.id).toBe("i-1");
    expect(leggiIndirizzo({ ...riga, provincia: "cn" })).toBeNull();
    expect(leggiIndirizzo({ ...riga, predefinitoRitiro: "false" })).toBeNull();
    expect(leggiIndirizziOrdine(undefined)).toBeNull();
    expect(leggiIndirizziOrdine("x")).toBeUndefined();
  });
});

describe("contratto con la migrazione 20261013160000", () => {
  const servizio = readFileSync(join(import.meta.dir, "indirizzi-service.ts"), "utf8");

  it("ogni RPC del servizio esiste, solo ad authenticated", () => {
    const chiamate = [...new Set([...servizio.matchAll(/rpc\("([a-z_]+)"/g)].map((m) => m[1]))];
    expect(chiamate.sort()).toEqual([
      "checkout_consegna_imposta",
      "indirizzi_miei",
      "indirizzo_archivia",
      "indirizzo_salva",
      "ordine_indirizzi_leggi",
    ]);
    for (const nome of chiamate) {
      expect(migrazione).toContain(`create function public.${nome}(`);
      expect(migrazione).toMatch(new RegExp(`grant execute on function public\\.${nome}\\([^)]*\\) to authenticated;`));
      expect(migrazione).toMatch(
        new RegExp(`revoke execute on function public\\.${nome}\\([^)]*\\) from public, anon, service_role;`),
      );
    }
    expect(migrazione).not.toMatch(/to anon/);
  });

  it("nessun dato operativo inventato: nessun servizio, punto, tariffa o capacita inseriti", () => {
    for (const tabella of [
      "logistics_service_definitions",
      "logistics_service_capabilities",
      "logistics_commercial_rate_sources",
      "logistics_pickup_points",
      "logistics_provider_operazioni",
    ]) {
      // Istruzioni di primo livello: gli insert dentro le porte admin ricreate
      // sono configurazione futura, non dati seminati dalla migrazione.
      expect(migrazione).not.toMatch(new RegExp(`^insert into private\\.${tabella}`, "m"));
    }
    expect(migrazione).not.toMatch(/https?:\/\//);
  });
});

describe("preventivo: ritiro in sede e domicilio addebitato", () => {
  const economico = {
    classe: "partner",
    configId: 6,
    quantita: 1,
    prezzoUnitarioCents: 4500,
    subtotaleCents: 4500,
    commissioneCents: 811,
    totaleCents: 5311,
    margineObiettivoBps: 1500,
    riferimentoPercentualeBps: 209,
    riferimentoFissoCents: 25,
  };
  const disponibile = (destinazione: string, capability: string, totale: number, fee: number) => ({
    destinazione,
    capability,
    disponibile: true,
    ordinabile: true,
    colli: [
      {
        numero: 1,
        packagingFormat: "bottiglia_1",
        bottiglie: 1,
        pesoG: 1700,
        lunghezzaMm: 158,
        larghezzaMm: 150,
        altezzaMm: 375,
        volumeCm3: 8888,
        imballaggioCents: 170,
      },
    ],
    imballaggioCents: 170,
    trasportoCents: totale - 170,
    altriCostiCents: 0,
    bufferCents: 0,
    totaleCents: totale,
    feePagamentoCents: fee,
  });
  const risposta = (totaleDomicilio: number | null) => ({
    listingId: "l-1",
    quantita: 1,
    formato: "0,75 L",
    origine: "sede",
    addebitata: false,
    consigliata: "pudo",
    opzioni: [
      disponibile("pudo", "SEDE_TO_PUDO", 720, 18),
      { ...disponibile("home", "SEDE_TO_HOME", 960, 23), addebitata: true, richiedeIndirizzo: true },
    ],
    modalita: [
      { origine: "pudo", destinazione: "pudo", capability: "PUDO_TO_PUDO", disponibile: false },
      { origine: "sede", destinazione: "pudo", capability: "SEDE_TO_PUDO", disponibile: true },
      { origine: "sede", destinazione: "home", capability: "SEDE_TO_HOME", disponibile: true },
    ],
    economico,
    imballaggioAnnuncioCents: 0,
    feePagamentoCents: null,
    feePagamentoSenzaLogisticaCents: 0,
    totaleOrdineCents: null,
    totaleOrdineDomicilioCents: totaleDomicilio,
  });

  it("legge l'origine sede, le capability SEDE_* e il totale a domicilio coerente", () => {
    const p = leggiPreventivoLogistica(risposta(5311 + 960 + 23));
    expect(p?.origine).toBe("sede");
    expect(p?.modalita.map((m) => m.capability)).toContain("SEDE_TO_HOME");
    expect(p?.totaleOrdineDomicilioCents).toBe(6294);
    expect(p?.opzioni.find((o) => o.destinazione === "home")?.ordinabile).toBe(true);
  });

  it("un totale a domicilio che non torna non diventa un importo", () => {
    expect(leggiPreventivoLogistica(risposta(6000))).toBeUndefined();
  });

  it("etichette italiane per la sede e per l'indirizzo di ritiro mancante", () => {
    expect(etichettaModalita("SEDE_TO_PUDO")).toBe("Ritiro presso la sede del Partner, consegna a punto di ritiro");
    expect(etichettaMancanza("indirizzo_ritiro_mancante")).toBe("manca l'indirizzo di ritiro del venditore");
  });
});
