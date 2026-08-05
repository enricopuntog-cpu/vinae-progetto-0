import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  ETICHETTE_STATO_COMPRATORE,
  ETICHETTE_STATO_VENDITORE,
  puoConfermare,
  puoContestare,
  puoPreparare,
  puoRecensire,
  puoSegnalareConsegna,
  puoSpedire,
  scomposizioneAddebito,
  sellerStatusDaOrdine,
  type IstantaneaVenditore,
} from "@/lib/orders/seller-status";
import type { OrderStatus, SellerOrderStatus } from "@/services/types";

const MIGRAZIONE_7C = readFileSync(
  join(
    import.meta.dir,
    "../../../../supabase/migrations/20260804160000_phase_7c_delivery_packaging.sql",
  ),
  "utf8",
);

/**
 * La migrazione senza i commenti di riga. La prosa dei commenti contiene gli
 * stessi identificatori che qui si cercano come struttura, e una regex che li
 * incontra passerebbe anche quando il codice vero è divergente.
 */
const SQL = MIGRAZIONE_7C.split("\n")
  .filter((riga) => !riga.trimStart().startsWith("--"))
  .join("\n");

const ordine = (patch: Partial<IstantaneaVenditore>): IstantaneaVenditore => ({
  stato: "pagato",
  preparazione_avviata_at: null,
  ...patch,
});

const TUTTI_GLI_STATI: OrderStatus[] = [
  "in_attesa_pagamento",
  "pagato",
  "in_preparazione",
  "spedito",
  "consegnato",
  "verifica",
  "completato",
  "contestato",
  "rimborsato",
  "annullato",
];

describe("sellerStatusDaOrdine", () => {
  it("distingue «nuovo» da «da_preparare» su preparazione_avviata_at", () => {
    expect(sellerStatusDaOrdine(ordine({ preparazione_avviata_at: null }))).toBe("nuovo");
    expect(
      sellerStatusDaOrdine(ordine({ preparazione_avviata_at: "2026-08-04T10:00:00Z" })),
    ).toBe("da_preparare");
  });

  it("mappa in_preparazione su da_spedire, come generaLabel in frontend/", () => {
    expect(sellerStatusDaOrdine(ordine({ stato: "in_preparazione" }))).toBe("da_spedire");
  });

  it("copre ogni stato dell'ordine senza restituire undefined", () => {
    for (const stato of TUTTI_GLI_STATI) {
      expect(sellerStatusDaOrdine(ordine({ stato }))).toBeDefined();
    }
  });

  it("porta `verifica` su consegnato, senza perderlo", () => {
    expect(sellerStatusDaOrdine(ordine({ stato: "verifica" }))).toBe("consegnato");
  });
});

describe("parità con frontend/src/data/orders.ts", () => {
  const ATTESI_VENDITORE: SellerOrderStatus[] = [
    "nuovo",
    "da_preparare",
    "da_spedire",
    "spedito",
    "consegnato",
    "completato",
    "contestato",
    "rimborsato",
    "annullato",
  ];

  it("le nove etichette venditore sono tutte e sole quelle di frontend/", () => {
    expect(Object.keys(ETICHETTE_STATO_VENDITORE).sort()).toEqual([...ATTESI_VENDITORE].sort());
  });

  it("le dieci etichette compratore sono tutte e sole quelle di frontend/", () => {
    expect(Object.keys(ETICHETTE_STATO_COMPRATORE).sort()).toEqual([...TUTTI_GLI_STATI].sort());
  });
});

describe("coerenza con la migrazione 7c", () => {
  it("public.order_seller_stato esiste e mappa gli stessi nove valori", () => {
    expect(SQL).toContain("create or replace function public.order_seller_stato");
    const corpo = SQL.slice(SQL.indexOf("public.order_seller_stato"));
    for (const valore of Object.keys(ETICHETTE_STATO_VENDITORE)) {
      expect(corpo).toContain(`'${valore}'`);
    }
  });

  it("la SQL distingue nuovo da da_preparare sulla stessa colonna che usa il TypeScript", () => {
    const corpo = SQL.slice(
      SQL.indexOf("public.order_seller_stato"),
      SQL.indexOf("public.order_seller_stato") + 900,
    );
    expect(corpo).toContain("preparazione_avviata_at is null");
  });

  it("totale_cents resta prezzo + commissione: l'imballaggio non entra nella base 7b", () => {
    expect(SQL).toContain(
      "generated always as (prezzo_cents + commissione_cents + imballaggio_cents) stored",
    );
    // La colonna della 7b non viene ridefinita da nessuna parte in questa
    // migrazione. Il confine di parola conta: `addebito_totale_cents` contiene
    // `totale_cents`, e una regex non ancorata prenderebbe la colonna nuova
    // scambiandola per la vecchia.
    expect(SQL).not.toContain("drop column totale_cents");
    expect(SQL).not.toMatch(/(?:^|[\s,(])totale_cents\s+integer\s+generated/);
    expect(SQL).not.toMatch(/add column totale_cents\b/);
  });

  it("payments.amount_cents nasce dall'addebito comprensivo di imballaggio", () => {
    expect(SQL).toContain("values (v_order.id, v_order.addebito_totale_cents, v_order.currency)");
  });

  it("la formula del rincaro della 7b non è ridefinita", () => {
    expect(SQL).not.toContain("function private.marketplace_totale_cents");
  });

  it("nessuna funzione di denaro della 7b è ridefinita e payouts non è scritta", () => {
    // `create or replace` è il prefisso che conta: nominare una funzione della
    // 7b è legittimo — `ordine_contestazione_apri` la chiama e un `revoke` la
    // cita — ridefinirla no.
    for (const funzione of [
      "payout_prepara",
      "payout_coda",
      "payout_registra_esito",
      "ordine_auto_rilascio_esegui",
      "ordine_contesta(",
      "conferma_ricezione",
      "ordine_segna_consegnato",
    ]) {
      expect(SQL).not.toContain(`create or replace function public.${funzione}`);
      expect(SQL).not.toContain(`create function public.${funzione}`);
    }
    expect(SQL).not.toMatch(/(insert|update|delete)[\s\S]{0,20}public\.payouts/);
  });

  it("ordine_contesta della 7b è composta, non sostituita, e chiusa al client", () => {
    expect(SQL).toContain("perform public.ordine_contesta(p_order_id, p_motivo)");
    expect(SQL).toContain(
      "revoke execute on function public.ordine_contesta(uuid, text) from authenticated",
    );
  });

  it("la risoluzione della contestazione non è concessa ad authenticated", () => {
    expect(SQL).toContain("ordine_contestazione_risolvi");
    const grants = SQL.split("\n").filter(
      (riga) => riga.includes("grant execute") || riga.includes("ordine_contestazione_risolvi"),
    );
    const concessa = grants.some(
      (riga, i) =>
        riga.includes("ordine_contestazione_risolvi") &&
        grants.slice(i, i + 3).some((r) => r.includes("to authenticated")),
    );
    expect(concessa).toBe(false);
    expect(SQL).toContain(
      "revoke execute on function public.ordine_contesta(uuid, text) from authenticated",
    );
  });
});

describe("precondizioni delle transizioni", () => {
  it("il venditore prepara solo da pagato o in_preparazione", () => {
    expect(TUTTI_GLI_STATI.filter(puoPreparare)).toEqual(["pagato", "in_preparazione"]);
    expect(TUTTI_GLI_STATI.filter(puoSpedire)).toEqual(["pagato", "in_preparazione"]);
  });

  it("la consegna si dichiara anche senza passare da in_preparazione", () => {
    expect(TUTTI_GLI_STATI.filter(puoSegnalareConsegna)).toEqual([
      "pagato",
      "in_preparazione",
      "spedito",
    ]);
  });

  it("un ordine contestato non è più confermabile né ri-contestabile", () => {
    const contestato = { stato: "consegnato" as OrderStatus, contestato_at: "2026-08-04T10:00:00Z" };
    expect(puoConfermare(contestato)).toBe(false);
    expect(puoContestare(contestato)).toBe(false);
  });

  it("il compratore conferma anche prima della consegna dichiarata", () => {
    expect(puoConfermare({ stato: "pagato", contestato_at: null })).toBe(true);
  });

  it("si recensisce solo un ordine completato", () => {
    expect(TUTTI_GLI_STATI.filter(puoRecensire)).toEqual(["completato"]);
  });
});

describe("scomposizioneAddebito", () => {
  it("tiene l'imballaggio fuori dal totale di mercato e dentro l'addebito", () => {
    const s = scomposizioneAddebito({
      prezzo_cents: 10000,
      commissione_cents: 686,
      totale_cents: 10686,
      imballaggio_cents: 450,
      addebito_totale_cents: 11136,
    });
    expect(s.totaleMercatoCents).toBe(s.prezzoCents + s.commissioneCents);
    expect(s.addebitoTotaleCents).toBe(s.totaleMercatoCents + s.imballaggioCents);
  });

  it("con imballaggio a zero i due totali coincidono, come per ogni ordine pre-7c", () => {
    const s = scomposizioneAddebito({
      prezzo_cents: 10000,
      commissione_cents: 686,
      totale_cents: 10686,
      imballaggio_cents: 0,
      addebito_totale_cents: 10686,
    });
    expect(s.addebitoTotaleCents).toBe(s.totaleMercatoCents);
  });
});
