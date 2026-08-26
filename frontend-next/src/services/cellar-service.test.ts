import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createCellarService } from "@/services/cellar-service";
import type { DatiNuovaBottiglia } from "@/services/types";

const bottiglia: DatiNuovaBottiglia = {
  produttore: "Produttore",
  nome: "Etichetta",
  annata: 2020,
  regione: "Toscana",
  tipo: "Rosso",
  visibilita: "privata",
  immagini: ["utente/bottiglia.webp"],
};

const fakeClient = () => {
  const chiamate: Array<{ nome: string; parametri: Record<string, unknown> }> = [];
  const client = {
    rpc: (nome: string, parametri: Record<string, unknown>) => {
      chiamate.push({ nome, parametri });
      return Promise.resolve({
        data: [{ bottle_unit_id: "bottle-1", wine_id: "wine-1" }],
        error: null,
      });
    },
  } as unknown as SupabaseClient;

  return { client, chiamate };
};
describe("CellarService — acquisizione", () => {
  it("mantiene compatibili i chiamanti esistenti e invia fatti assenti come null", async () => {
    const { client, chiamate } = fakeClient();

    expect(await createCellarService(client).aggiungiBottiglia(bottiglia)).toEqual({
      ok: true,
      data: { bottleUnitId: "bottle-1", wineId: "wine-1" },
    });
    expect(chiamate).toEqual([
      {
        nome: "cellar_bottiglia_aggiungi",
        parametri: {
          p_produttore: "Produttore",
          p_nome: "Etichetta",
          p_annata: 2020,
          p_regione: "Toscana",
          p_tipo: "Rosso",
          p_visibilita: "privata",
          p_immagini: ["utente/bottiglia.webp"],
          p_acquisition_cost_cents: null,
          p_acquired_at: null,
        },
      },
    ]);
  });

  it("inoltra costo zero e data senza confonderli con fatti sconosciuti", async () => {
    const { client, chiamate } = fakeClient();

    await createCellarService(client).aggiungiBottiglia({
      ...bottiglia,
      acquisitionCostCents: 0,
      acquiredAt: "2024-02-02T23:00:00.000Z",
    });

    expect(chiamate[0]?.parametri).toMatchObject({
      p_acquisition_cost_cents: 0,
      p_acquired_at: "2024-02-02T23:00:00.000Z",
    });
  });
});

describe("CellarService — analitica del portafoglio", () => {
  const posizionePiena = {
    bottleUnitId: "b-1",
    wineId: "w-1",
    wineSlug: "vino-uno",
    produttore: "Produttore",
    nome: "Etichetta",
    annata: 2020,
    tipo: "Rosso",
    formato: "0,75 L",
    stato: "in_cantina",
    acquiredAt: "2024-01-10T00:00:00.000Z",
    acquisizioneFonte: "manuale",
    costoManualeCents: 4000,
    ordineAcquistoId: null,
    acquistoPrezzoVenditoreCents: null,
    acquistoLordoCents: null,
    acquistoRimborsoCents: null,
    acquistoNettoCents: null,
    ordineVenditaId: null,
    venditaStato: null,
    venditaPayoutStato: null,
    venditaIncassoCents: null,
    venditaIncassoAt: null,
    cedutaAt: null,
    deletedAt: null,
    consumedAt: null,
    riferimentoCents: 5000,
    riferimentoComparabili: 3,
    riferimentoAt: "2026-01-01T00:00:00.000Z",
  };

  const fakeRpcAnalitica = (risposta: { data: unknown; error: unknown }) => {
    const chiamateRpc: string[] = [];
    const relazioni: string[] = [];
    const client = {
      from: (relazione: string) => {
        relazioni.push(relazione);
        throw new Error("l'analitica non legge tabelle: passa da una sola RPC");
      },
      rpc: (nome: string) => {
        chiamateRpc.push(nome);
        return Promise.resolve(risposta);
      },
    } as unknown as SupabaseClient;
    return { client, chiamateRpc, relazioni };
  };

  it("usa la sola RPC owner-only e calcola il risultato dal suo payload", async () => {
    const { client, chiamateRpc, relazioni } = fakeRpcAnalitica({
      data: {
        generatoAt: "2026-08-26T10:00:00.000Z",
        posizioni: [posizionePiena],
        storico: [
          {
            wineId: "w-1",
            formato: "0,75 L",
            medianaCents: 5000,
            comparabili: 3,
            observedAt: "2026-01-01T00:00:00.000Z",
          },
        ],
      },
      error: null,
    });

    const esito = await createCellarService(client).analitica();
    expect(chiamateRpc).toEqual(["cellar_portfolio_analitica"]);
    expect(relazioni).toEqual([]);
    expect(esito.ok).toBe(true);
    if (esito.ok) {
      expect(esito.data.valoreRiferimentoCents).toBe(5000);
      expect(esito.data.capitaleNotoCents).toBe(4000);
      expect(esito.data.performanceCents).toBe(1000);
      expect(esito.data.coperturaValore).toBe("completa");
      expect(esito.data.serieValore).toHaveLength(1);
    }
  });

  it("un payload malformato è un errore mediato, non un'eccezione né un dato falso", async () => {
    const { client } = fakeRpcAnalitica({ data: { posizioni: "non-un-array" }, error: null });
    const esito = await createCellarService(client).analitica();
    expect(esito.ok).toBe(false);
    if (!esito.ok) expect(esito.error).not.toContain("non-un-array");
  });

  it("l'errore di permesso è mediato e non espone il messaggio del database", async () => {
    const { client } = fakeRpcAnalitica({
      data: null,
      error: { code: "42501", message: "permission denied for function" },
    });
    const esito = await createCellarService(client).analitica();
    expect(esito.ok).toBe(false);
    if (!esito.ok) {
      expect(esito.error).not.toContain("permission denied for function");
      expect(esito.error).not.toContain("42501");
    }
  });

  it("un errore del database che non abbiamo scritto noi resta generico", async () => {
    const { client } = fakeRpcAnalitica({
      data: null,
      error: { code: "57014", message: "canceling statement due to statement timeout" },
    });
    const esito = await createCellarService(client).analitica();
    expect(esito.ok).toBe(false);
    if (!esito.ok) {
      expect(esito.error).not.toContain("statement timeout");
      expect(esito.error).not.toContain("57014");
    }
  });

  it("un P0001 arbitrario non diventa testo applicativo dell'analitica", async () => {
    const { client } = fakeRpcAnalitica({
      data: null,
      error: { code: "P0001", message: "Sessione non valida." },
    });
    const esito = await createCellarService(client).analitica();
    expect(esito.ok).toBe(false);
    if (!esito.ok) {
      expect(esito.error).toBe("Analitica non disponibile al momento.");
      expect(esito.error).not.toContain("Sessione non valida.");
      expect(esito.error).not.toContain("P0001");
    }
  });

  it("un payload senza le chiavi promesse non viene nemmeno calcolato", async () => {
    const { client } = fakeRpcAnalitica({ data: { posizioni: [], storico: [] }, error: null });
    const esito = await createCellarService(client).analitica();
    expect(esito.ok).toBe(false);
  });

  it("senza client configurato fallisce in modo esplicito", async () => {
    const esito = await createCellarService(null).analitica();
    expect(esito.ok).toBe(false);
  });
});
