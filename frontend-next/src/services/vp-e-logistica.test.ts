/**
 * VP-E: logistica multi-bottiglia e multi-collo.
 *
 * Colli, imballaggio, trasporto e totale li decide il database. Questi test
 * fissano che il client li legga senza ricalcolarli, che una risposta
 * incoerente non diventi un importo, che il checkout non si confermi con la
 * spedizione non configurata, che gli ordini da una bottiglia restino come
 * prima e che nessun vettore compaia nel codice.
 */
import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  creaLogisticaService,
  leggiLogisticaOrdine,
  leggiOpzioneLogistica,
  leggiPreventivoLogistica,
} from "@/services/logistica-service";
import {
  elencoMancanze,
  etichettaImballaggio,
  etichettaMancanza,
  etichettaModalita,
  misureCm,
  opzioneConsigliata,
  pesoKg,
  riassuntoColli,
} from "@/lib/logistica/etichette";
import { logisticaAddebitata, riepilogoCheckout } from "@/lib/beta/checkout";
import { scomposizioneAddebito } from "@/lib/orders/seller-status";

const progetto = join(import.meta.dir, "../..");
const leggi = (p: string) => readFileSync(join(progetto, p), "utf8");

type Esito = { data: unknown; error: unknown };

function clientRpc(risposte: Record<string, Esito>) {
  const chiamate: Array<{ nome: string; parametri: unknown }> = [];
  const client = {
    rpc: (nome: string, parametri?: unknown) => {
      chiamate.push({ nome, parametri });
      return Promise.resolve(risposte[nome] ?? { data: null, error: { code: "PGRST202", message: "x" } });
    },
  } as unknown as SupabaseClient;
  return { client, chiamate };
}

const collo = (numero: number, packagingFormat: string, bottiglie: number, imballaggioCents: number) => ({
  numero,
  packagingFormat,
  bottiglie,
  pesoG: bottiglie === 6 ? 9500 : 3200,
  lunghezzaMm: bottiglie === 6 ? 394 : 310,
  larghezzaMm: bottiglie === 6 ? 310 : 150,
  altezzaMm: 375,
  volumeCm3: bottiglie === 6 ? 45803 : 17438,
  imballaggioCents,
});

const economico = {
  classe: "privato",
  configId: 5,
  quantita: 8,
  prezzoUnitarioCents: 4000,
  subtotaleCents: 32000,
  commissioneCents: 3324,
  totaleCents: 35324,
  margineObiettivoBps: 800,
  riferimentoPercentualeBps: 209,
  riferimentoFissoCents: 25,
};

type ColloGrezzo = ReturnType<typeof collo>;
type PudoGrezza = {
  destinazione: string;
  capability: string;
  disponibile: boolean;
  ordinabile: boolean;
  colli: ColloGrezzo[];
  imballaggioCents: number;
  trasportoCents: number;
  altriCostiCents: number;
  bufferCents: number;
  totaleCents: number;
};
type HomeGrezza = {
  destinazione: string;
  capability: string;
  disponibile: boolean;
  ordinabile: boolean;
  motivoNonOrdinabile: string;
  mancanti: Array<{ packagingFormat: string; capacita: number; motivi: string[] }>;
};
type RispostaGrezza = {
  listingId: string;
  quantita: number;
  formato: string;
  origine: string;
  addebitata: boolean;
  consigliata: string;
  opzioni: [PudoGrezza, HomeGrezza];
  modalita: Array<{ origine: string; destinazione: string; capability: string; disponibile: boolean }>;
  economico: typeof economico;
  totaleOrdineCents: number | null;
};

/** La risposta della porta per 8 bottiglie, come nella griglia 12zc. */
const risposta8 = (): RispostaGrezza => ({
  listingId: "l-1",
  quantita: 8,
  formato: "0,75 L",
  origine: "pudo",
  addebitata: true,
  consigliata: "pudo",
  opzioni: [
    {
      destinazione: "pudo",
      capability: "PUDO_TO_PUDO",
      disponibile: true,
      ordinabile: true,
      colli: [collo(1, "bottiglia_6", 6, 609), collo(2, "bottiglia_2", 2, 369)],
      imballaggioCents: 978,
      trasportoCents: 844,
      altriCostiCents: 0,
      bufferCents: 0,
      totaleCents: 1822,
    },
    {
      destinazione: "home",
      capability: "PUDO_TO_HOME",
      disponibile: false,
      ordinabile: false,
      motivoNonOrdinabile: "indirizzo_consegna_non_gestito",
      mancanti: [
        { packagingFormat: "bottiglia_6", capacita: 6, motivi: ["servizio_per_rotta", "tariffa_trasporto"] },
        { packagingFormat: "bottiglia_2", capacita: 2, motivi: ["servizio_per_rotta", "tariffa_trasporto"] },
      ],
    },
  ],
  modalita: [
    { origine: "pudo", destinazione: "pudo", capability: "PUDO_TO_PUDO", disponibile: true },
    { origine: "pudo", destinazione: "home", capability: "PUDO_TO_HOME", disponibile: false },
    { origine: "home", destinazione: "pudo", capability: "HOME_TO_PUDO", disponibile: true },
    { origine: "home", destinazione: "home", capability: "HOME_TO_HOME", disponibile: false },
  ],
  economico,
  totaleOrdineCents: 35324 + 1822,
});

describe("VP-E — lettura del preventivo logistico", () => {
  it("legge colli, importi e totale d'ordine senza ricalcolarli", () => {
    const p = leggiPreventivoLogistica(risposta8());
    expect(p).toBeDefined();
    const pudo = p?.opzioni.find((o) => o.destinazione === "pudo");
    expect(pudo?.colli.map((c) => `${c.packagingFormat}:${c.bottiglie}`)).toEqual([
      "bottiglia_6:6",
      "bottiglia_2:2",
    ]);
    expect(pudo?.totaleCents).toBe(1822);
    expect(pudo?.ordinabile).toBe(true);
    expect(p?.totaleOrdineCents).toBe(37146);
    expect(p?.addebitata).toBe(true);
    expect(p?.modalita).toHaveLength(4);
  });

  it("un'opzione non disponibile porta le sue mancanze e nessun importo", () => {
    const p = leggiPreventivoLogistica(risposta8());
    const home = p?.opzioni.find((o) => o.destinazione === "home");
    expect(home?.disponibile).toBe(false);
    expect(home?.totaleCents).toBeNull();
    expect(home?.colli).toEqual([]);
    expect(home?.motivoNonOrdinabile).toBe("indirizzo_consegna_non_gestito");
    expect(home?.mancanti[0].motivi).toContain("tariffa_trasporto");
  });

  it("rifiuta colli che non sommano la quantità", () => {
    const r = risposta8();
    r.opzioni[0].colli = [collo(1, "bottiglia_6", 6, 609), collo(2, "bottiglia_2", 2, 369), collo(3, "bottiglia_1", 1, 0)];
    expect(leggiPreventivoLogistica(r)).toBeUndefined();
  });

  it("rifiuta un totale che non è imballaggio + trasporto + altri costi + buffer", () => {
    const r = risposta8();
    r.opzioni[0].totaleCents = 1500;
    expect(leggiPreventivoLogistica(r)).toBeUndefined();
  });

  it("rifiuta un imballaggio che non è la somma dei colli", () => {
    const r = risposta8();
    r.opzioni[0].imballaggioCents = 900;
    r.opzioni[0].totaleCents = 900 + 844;
    expect(leggiPreventivoLogistica(r)).toBeUndefined();
  });

  it("rifiuta un totale d'ordine diverso da mercato + logistica", () => {
    const r = risposta8();
    r.totaleOrdineCents = 35324;
    expect(leggiPreventivoLogistica(r)).toBeUndefined();
  });

  it("rifiuta formati d'imballaggio sconosciuti, importi negativi e capability inventate", () => {
    const a = risposta8();
    a.opzioni[0].colli[0].packagingFormat = "scatola_misteriosa";
    expect(leggiPreventivoLogistica(a)).toBeUndefined();
    const b = risposta8();
    b.opzioni[0].trasportoCents = -1;
    expect(leggiPreventivoLogistica(b)).toBeUndefined();
    const c = risposta8();
    c.modalita[0].capability = "DRONE_TO_PUDO";
    expect(leggiPreventivoLogistica(c)).toBeUndefined();
  });

  it("una bottiglia: preventivo informativo, non addebitato, senza totale d'ordine", () => {
    const p = leggiPreventivoLogistica({
      ...risposta8(),
      quantita: 1,
      addebitata: false,
      opzioni: [
        {
          destinazione: "pudo",
          capability: "PUDO_TO_PUDO",
          disponibile: true,
          ordinabile: true,
          colli: [{ ...collo(1, "bottiglia_1", 1, 319), pesoG: 1700 }],
          imballaggioCents: 319,
          trasportoCents: 415,
          altriCostiCents: 0,
          bufferCents: 0,
          totaleCents: 734,
        },
      ],
      economico: { ...economico, quantita: 1, subtotaleCents: 4000, commissioneCents: 403, totaleCents: 4403 },
      totaleOrdineCents: null,
    });
    expect(p?.addebitata).toBe(false);
    expect(p?.totaleOrdineCents).toBeNull();
  });

  it("legge l'economia del venditore solo se presente e ben formata", () => {
    const base = risposta8().opzioni[0];
    const o = leggiOpzioneLogistica(
      {
        ...base,
        venditore: {
          trasportoEffettivoCents: 1454,
          deduzioneRitiroCents: 610,
          costoRealeCents: 2432,
          costoRealePerBottigliaCents: 304,
          obiettivoTransazioneCents: 1000,
          obiettivoPrezzoBottigliaMaxCents: 5000,
          obiettivoApplicabile: true,
          entroObiettivoTransazione: false,
          sogliaStoricaCents: 1500,
          entroSogliaStorica: false,
        },
      },
      8,
    );
    expect(o?.venditore?.deduzioneRitiroCents).toBe(610);
    expect(leggiOpzioneLogistica({ ...base, venditore: { costoRealeCents: "molto" } }, 8)).toBeUndefined();
    expect(leggiOpzioneLogistica(base, 8)?.venditore).toBeNull();
  });
});

describe("VP-E — servizio", () => {
  it("chiede il preventivo alla porta con quantità e prezzo della proposta", async () => {
    const { client, chiamate } = clientRpc({ listing_logistica_preventivo: { data: risposta8(), error: null } });
    const r = await creaLogisticaService(client).preventivo("l-1", 8, 3500);
    expect(r.ok).toBe(true);
    expect(chiamate[0]).toEqual({
      nome: "listing_logistica_preventivo",
      parametri: { p_listing_id: "l-1", p_quantita: 8, p_prezzo_unitario_cents: 3500 },
    });
  });

  it("un errore o una risposta incoerente non diventano un importo", async () => {
    const errore = clientRpc({ listing_logistica_preventivo: { data: null, error: { code: "P0001", message: "x" } } });
    expect((await creaLogisticaService(errore.client).preventivo("l-1", 2)).ok).toBe(false);
    const rotta = risposta8();
    rotta.opzioni[0].totaleCents = 1;
    const incoerente = clientRpc({ listing_logistica_preventivo: { data: rotta, error: null } });
    expect((await creaLogisticaService(incoerente.client).preventivo("l-1", 8)).ok).toBe(false);
    expect((await creaLogisticaService(null).preventivo("l-1", 8)).ok).toBe(false);
  });

  it("legge la logistica congelata di un ordine", async () => {
    const dati = {
      orderId: "o-1",
      quantita: 8,
      logisticaCents: 1822,
      destinazione: "pudo",
      imballaggioCents: 978,
      trasportoCents: 844,
      colli: [collo(1, "bottiglia_6", 6, 609), collo(2, "bottiglia_2", 2, 369)],
    };
    const { client, chiamate } = clientRpc({ ordine_logistica_leggi: { data: dati, error: null } });
    const r = await creaLogisticaService(client).ordine("o-1");
    expect(r.ok && r.data.colli.length).toBe(2);
    expect(chiamate[0].parametri).toEqual({ p_order_id: "o-1" });
    expect(leggiLogisticaOrdine({ orderId: "o-2", quantita: 1, logisticaCents: 0, colli: [] })?.colli).toEqual([]);
    expect(leggiLogisticaOrdine({ ...dati, colli: [{ numero: 1 }] })).toBeUndefined();
  });
});

describe("VP-E — parole della logistica", () => {
  it("nomina imballaggi, modalità e colli in italiano", () => {
    expect(etichettaImballaggio("bottiglia_6")).toBe("Cartone da 6 bottiglie");
    expect(etichettaImballaggio("magnum_1_5l")).toBe("Cartone Magnum");
    expect(etichettaModalita("HOME_TO_PUDO")).toBe("Ritiro dal venditore, consegna a punto di ritiro");
    expect(riassuntoColli([{ bottiglie: 6 }, { bottiglie: 2 }])).toBe("2 colli: 6 + 2 bottiglie");
    expect(riassuntoColli([{ bottiglie: 1 }])).toBe("1 collo da 1 bottiglia");
    expect(riassuntoColli([{ bottiglie: 3 }])).toBe("1 collo da 3 bottiglie");
    expect(pesoKg(9500)).toBe("9,5 kg");
    expect(misureCm({ lunghezzaMm: 394, larghezzaMm: 310, altezzaMm: 375 })).toBe("39,4 × 31 × 37,5 cm");
  });

  it("dice che cosa manca una volta sola, poi le mancanze proprie di un formato", () => {
    const righe = elencoMancanze([
      { packagingFormat: "bottiglia_6", motivi: ["imballaggio_operativo", "tariffa_trasporto_non_attiva"] },
      { packagingFormat: "bottiglia_2", motivi: ["imballaggio_operativo", "tariffa_trasporto_non_attiva"] },
      { packagingFormat: "bottiglia_12", motivi: ["contributo_imballaggio", "imballaggio_operativo", "tariffa_trasporto_non_attiva"] },
    ]);
    expect(righe).toEqual([
      "imballaggio operativo (misure e peso) non configurato",
      "tariffa di trasporto non ancora attiva",
      "Cartone da 12 bottiglie: contributo d'imballaggio non configurato",
    ]);
    expect(elencoMancanze([{ packagingFormat: null, motivi: ["formato_non_supportato"] }])).toEqual([
      "nessun imballaggio previsto per questo formato di bottiglia",
    ]);
    expect(etichettaMancanza("novita_futura")).toBe("configurazione mancante (novita_futura)");
  });

  it("propone il punto di ritiro come opzione consigliata", () => {
    const p = leggiPreventivoLogistica(risposta8());
    expect(opzioneConsigliata(p?.opzioni ?? [])?.destinazione).toBe("pudo");
  });
});

describe("VP-E — checkout e ordini", () => {
  const pudo = { ordinabile: true, totaleCents: 1822 };

  it("la logistica entra nel totale solo per più bottiglie spedite", () => {
    expect(logisticaAddebitata(1, "spedizione", pudo)).toBe(0);
    expect(logisticaAddebitata(8, "consegna_mano", pudo)).toBe(0);
    expect(logisticaAddebitata(8, "spedizione", pudo)).toBe(1822);
  });

  it("spedizione non configurata o non leggibile: nessun importo, checkout bloccato", () => {
    expect(logisticaAddebitata(8, "spedizione", null)).toBeNull();
    expect(logisticaAddebitata(8, "spedizione", { ordinabile: false, totaleCents: null })).toBeNull();
  });

  it("il riepilogo somma la logistica fuori dalla commissione", () => {
    const r = riepilogoCheckout(
      {
        classe: "privato",
        quantita: 8,
        prezzoUnitarioCents: 4000,
        subtotaleCents: 32000,
        commissioneCents: 3324,
        totaleCents: 35324,
        margineObiettivoBps: 800,
        riferimentoPercentualeBps: 209,
        riferimentoFissoCents: 25,
      },
      0,
      1822,
    );
    expect(r).toEqual({
      prezzoCents: 32000,
      commissioneCents: 3324,
      imballaggioCents: 0,
      logisticaCents: 1822,
      feePagamentoCents: 0,
      totaleCents: 37146,
    });
  });

  it("nello storico la logistica è la parte dell'addebito che non è mercato né imballaggio 7c", () => {
    const multi = scomposizioneAddebito({
      prezzo_cents: 32000,
      commissione_cents: 3324,
      totale_cents: 35324,
      imballaggio_cents: 0,
      addebito_totale_cents: 37146,
    });
    expect(multi.logisticaCents).toBe(1822);
    const singola = scomposizioneAddebito({
      prezzo_cents: 4000,
      commissione_cents: 403,
      totale_cents: 4403,
      imballaggio_cents: 450,
      addebito_totale_cents: 4853,
    });
    expect(singola.logisticaCents).toBe(0);
  });
});

describe("VP-E — guardrail sui sorgenti", () => {
  const file = [
    "src/services/logistica-service.ts",
    "src/lib/logistica/etichette.ts",
    "src/components/vinea/logistica/PreventivoLogistica.tsx",
    "src/app/checkout/[id]/checkout-summary.tsx",
    "src/app/checkout/[id]/page-client.tsx",
  ];

  it("nessun vettore per nome e nessuna tariffa nel codice del client", () => {
    for (const f of file) {
      const s = leggi(f).toLowerCase();
      for (const nome of ["inpost", "sda", "brt", "poste", "gls", "dhl", "ups"]) {
        expect(new RegExp(`\\b${nome}\\b`).test(s)).toBe(false);
      }
      // Nessun importo di listino scritto a mano (gli unici numeri ammessi sono
      // quelli che arrivano dal database).
      expect(/\b(415|422|319|369|379|609|509)\b/.test(s)).toBe(false);
    }
  });

  it("il checkout non conferma con la spedizione non configurata", () => {
    const s = leggi("src/app/checkout/[id]/page-client.tsx");
    expect(s).toContain("disabled={checkout.inCorso || blocco !== null}");
    expect(s).toContain("bloccoConsegna(bottiglie, checkout.dati, logistica)");
    expect(s).toContain("checkout-logistica-bloccata");
  });

  it("lo storico non seleziona colonne nuove: la logistica si ricava dai numeri congelati", () => {
    const s = leggi("src/services/phase7/order-service.ts");
    expect(s).not.toContain("logistica_cents");
  });
});
