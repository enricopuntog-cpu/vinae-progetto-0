import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
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

/**
 * L'interruttore «Mostra nel mio profilo».
 *
 * Il permesso di scrivere `bottle_units.visibilita` esisteva già prima della
 * Cantina pubblica: un GRANT di colonna `UPDATE (visibilita)` più la policy
 * `bottle_units_update_own`. Quello che non esisteva era un posto da cui usarlo.
 * Questi test fissano la forma della scrittura — quale tabella, quale colonna,
 * quali righe — perché è quella forma, e non una RPC nuova, a essere la scelta.
 */
describe("CellarService — visibilità nella Cantina pubblica", () => {
  const fakeAggiornamento = (errore: { code?: string; message?: string } | null = null) => {
    const scritture: Array<{
      tabella: string;
      valori: Record<string, unknown>;
      colonnaFiltro: string;
      idFiltro: unknown;
    }> = [];
    const client = {
      from: (tabella: string) => ({
        update: (valori: Record<string, unknown>) => ({
          in: (colonnaFiltro: string, idFiltro: unknown) => {
            scritture.push({ tabella, valori, colonnaFiltro, idFiltro });
            return Promise.resolve({ error: errore });
          },
        }),
      }),
    } as unknown as SupabaseClient;

    return { client, scritture };
  };

  it("espone le unità scrivendo la sola colonna `visibilita`", async () => {
    const { client, scritture } = fakeAggiornamento();

    const esito = await createCellarService(client).impostaVisibilitaCantina(
      ["unita-1", "unita-2"],
      "cantina_pubblica",
    );

    expect(esito).toEqual({ ok: true, data: undefined });
    expect(scritture).toEqual([
      {
        tabella: "bottle_units",
        valori: { visibilita: "cantina_pubblica" },
        colonnaFiltro: "id",
        idFiltro: ["unita-1", "unita-2"],
      },
    ]);
  });

  it("richiude le stesse unità: l'interruttore va in tutte e due le direzioni", async () => {
    const { client, scritture } = fakeAggiornamento();

    await createCellarService(client).impostaVisibilitaCantina(["unita-1"], "privata");

    expect(scritture[0]?.valori).toEqual({ visibilita: "privata" });
  });

  it("non tocca nessun'altra colonna, e nessun'altra tabella", async () => {
    const { client, scritture } = fakeAggiornamento();

    await createCellarService(client).impostaVisibilitaCantina(["unita-1"], "cantina_pubblica");

    // `stato` e `deleted_at` sono stati revocati dalla 20260729230000: scriverli
    // qui fallirebbe in produzione e basterebbe un `update` un po' largo per
    // provarci. La scrittura resta di una chiave sola.
    expect(Object.keys(scritture[0]?.valori ?? {})).toEqual(["visibilita"]);
    expect(scritture.map((s) => s.tabella)).toEqual(["bottle_units"]);
  });

  it("un elenco vuoto non diventa un `update` senza filtro", async () => {
    const { client, scritture } = fakeAggiornamento();

    // Senza questa uscita anticipata, `.in("id", [])` partirebbe comunque: oggi
    // PostgREST non aggiornerebbe nulla, ma una scrittura che parte con un
    // filtro vuoto è una riga di codice che chiede solo di essere sbagliata.
    expect(await createCellarService(client).impostaVisibilitaCantina([], "privata")).toEqual({
      ok: true,
      data: undefined,
    });
    expect(scritture).toEqual([]);
  });

  it("un rifiuto del database non svela il database", async () => {
    const { client } = fakeAggiornamento({ code: "42501", message: 'permission denied for table "bottle_units"' });

    const esito = await createCellarService(client).impostaVisibilitaCantina(
      ["unita-di-un-altro"],
      "cantina_pubblica",
    );

    expect(esito.ok).toBe(false);
    expect(esito.ok === false && esito.error).toBe(
      "Non è stato possibile completare l'operazione. Riprova.",
    );
  });

  it("senza client configurato non finge di aver scritto", async () => {
    const esito = await createCellarService(null).impostaVisibilitaCantina(["u-1"], "privata");
    expect(esito.ok).toBe(false);
  });
});

// ===========================================================================
// La preferenza del proprietario sul valore nella Cantina pubblica
//
// Due porte owner-only e nient'altro: `private.cellar_public_settings` non ha
// policy e non ha grant, quindi il client non può leggerla né scriverla nemmeno
// sbagliando. Queste prove difendono la parte che *potrebbe* sbagliare: passare
// un identificativo che la porta non accetta, o fidarsi di una risposta che non
// è un booleano.
// ===========================================================================

describe("CellarService — valore nella Cantina pubblica", () => {
  const fakeRpcPreferenza = (risposta: { data: unknown; error: unknown }) => {
    const chiamateRpc: { nome: string; parametri: unknown }[] = [];
    const relazioni: string[] = [];
    const client = {
      from: (relazione: string) => {
        relazioni.push(relazione);
        throw new Error("la preferenza non legge tabelle: passa da due sole RPC");
      },
      rpc: (nome: string, parametri?: unknown) => {
        chiamateRpc.push({ nome, parametri });
        return Promise.resolve(risposta);
      },
    } as unknown as SupabaseClient;
    return { client, chiamateRpc, relazioni };
  };

  it("la lettura chiama solo la porta di lettura, senza parametri e senza ownerId", async () => {
    const { client, chiamateRpc, relazioni } = fakeRpcPreferenza({ data: true, error: null });

    const esito = await createCellarService(client).leggiVisibilitaValorePubblico();

    expect(esito).toEqual({ ok: true, data: true });
    expect(chiamateRpc).toHaveLength(1);
    expect(chiamateRpc[0]!.nome).toBe("cantina_pubblica_valore_impostazione");
    // Nessun identificativo in firma: la riga è quella di `auth.uid()`, e un
    // parametro qui sarebbe un invito a leggere la preferenza di un altro.
    expect(chiamateRpc[0]!.parametri).toBeUndefined();
    expect(relazioni).toEqual([]);
  });

  it("la lettura riporta `false` quando il database dice false, non un default nostro", async () => {
    const { client } = fakeRpcPreferenza({ data: false, error: null });
    expect(await createCellarService(client).leggiVisibilitaValorePubblico()).toEqual({
      ok: true,
      data: false,
    });
  });

  it("la scrittura accende passando `p_visibile: true` alla sola porta di scrittura", async () => {
    const { client, chiamateRpc, relazioni } = fakeRpcPreferenza({ data: true, error: null });

    const esito = await createCellarService(client).impostaVisibilitaValorePubblico(true);

    expect(esito).toEqual({ ok: true, data: true });
    expect(chiamateRpc).toEqual([
      { nome: "cantina_pubblica_valore_imposta", parametri: { p_visibile: true } },
    ]);
    expect(relazioni).toEqual([]);
  });

  it("la scrittura spegne passando `p_visibile: false`", async () => {
    const { client, chiamateRpc } = fakeRpcPreferenza({ data: false, error: null });

    const esito = await createCellarService(client).impostaVisibilitaValorePubblico(false);

    expect(esito).toEqual({ ok: true, data: false });
    expect(chiamateRpc[0]!.parametri).toEqual({ p_visibile: false });
  });

  it("l'esito arriva dal database, non dall'argomento che abbiamo mandato", async () => {
    // Se la porta rispondesse diversamente da quanto chiesto, la verità è la
    // sua: lo stato dell'interruttore non va dedotto dal gesto dell'utente.
    const { client } = fakeRpcPreferenza({ data: false, error: null });
    const esito = await createCellarService(client).impostaVisibilitaValorePubblico(true);
    expect(esito).toEqual({ ok: true, data: false });
  });

  it("una risposta che non è booleana è un errore mediato, non un `true` per distrazione", async () => {
    for (const data of [null, undefined, "true", 1, {}]) {
      const lettura = fakeRpcPreferenza({ data, error: null });
      const esitoLettura =
        await createCellarService(lettura.client).leggiVisibilitaValorePubblico();
      expect(esitoLettura.ok).toBe(false);

      const scrittura = fakeRpcPreferenza({ data, error: null });
      const esitoScrittura =
        await createCellarService(scrittura.client).impostaVisibilitaValorePubblico(true);
      expect(esitoScrittura.ok).toBe(false);
    }
  });

  it("un rifiuto del database diventa un messaggio nostro, mai quello di PostgreSQL", async () => {
    const errore = { code: "42501", message: "permission denied for schema private" };

    const lettura = fakeRpcPreferenza({ data: null, error: errore });
    const esitoLettura = await createCellarService(lettura.client).leggiVisibilitaValorePubblico();
    expect(esitoLettura.ok).toBe(false);
    const messaggioLettura = esitoLettura.ok ? "" : esitoLettura.error;
    expect(messaggioLettura).toBe("Non è stato possibile leggere questa preferenza.");
    expect(messaggioLettura).not.toContain("permission denied");
    expect(messaggioLettura).not.toContain("private");

    const scrittura = fakeRpcPreferenza({ data: null, error: errore });
    const esitoScrittura = await createCellarService(
      scrittura.client,
    ).impostaVisibilitaValorePubblico(true);
    expect(esitoScrittura.ok).toBe(false);
    const messaggioScrittura = esitoScrittura.ok ? "" : esitoScrittura.error;
    expect(messaggioScrittura).toBe("Non è stato possibile salvare questa preferenza. Riprova.");
    expect(messaggioScrittura).not.toContain("42501");
  });

  it("senza client configurato nessuna delle due finge un esito", async () => {
    expect((await createCellarService(null).leggiVisibilitaValorePubblico()).ok).toBe(false);
    expect((await createCellarService(null).impostaVisibilitaValorePubblico(true)).ok).toBe(false);
  });

  it("la tabella privata non è nominata dal codice: esistono solo le due porte", () => {
    const codice = readFileSync(
      join(import.meta.dir, "../../src/services/cellar-service.ts"),
      "utf8",
    )
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/\/\/.*$/gm, "");

    expect(codice).not.toContain("cellar_public_settings");
    expect(codice).not.toContain('from("cellar_public_settings")');
    expect(codice).toContain("cantina_pubblica_valore_impostazione");
    expect(codice).toContain("cantina_pubblica_valore_imposta");
  });
});
