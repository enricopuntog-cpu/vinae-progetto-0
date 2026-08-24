import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  createSupabasePriceIntelligenceService,
  mapObservation,
  noPriceIntelligenceClient,
} from "@/services/price-intelligence/supabase-price-intelligence-service";

// ---------------------------------------------------------------------------
// Doppio del client, sulla forma di quello della Fase 12: registra le
// relazioni toccate, i filtri e l'ordinamento, cosi un test puo provare che
// l'adapter non nomina MAI la tabella base e non chiede MAI una colonna che la
// vista non espone.
// ---------------------------------------------------------------------------

type Risposta = { data?: unknown; error?: { code?: string; message?: string } | null };

const fakeClient = (risposta: Risposta) => {
  const relazioni: string[] = [];
  const colonne: string[] = [];
  const filtri: Record<string, unknown> = {};
  const ordini: { colonna: string; ascending?: boolean }[] = [];
  const tetti: number[] = [];
  const scritture: string[] = [];

  const chain: Record<string, unknown> = {};
  chain.select = (c: string) => {
    colonne.push(c);
    return chain;
  };
  chain.eq = (colonna: string, valore: unknown) => {
    filtri[colonna] = valore;
    return chain;
  };
  chain.order = (colonna: string, opzioni?: { ascending?: boolean }) => {
    ordini.push({ colonna, ascending: opzioni?.ascending });
    return chain;
  };
  chain.limit = (n: number) => {
    tetti.push(n);
    return Promise.resolve(risposta);
  };
  // Se un giorno qualcuno aggiungesse una scrittura, questi la fanno emergere
  // come chiamata registrata invece che come errore silenzioso.
  chain.insert = () => {
    scritture.push("insert");
    return chain;
  };
  chain.update = () => {
    scritture.push("update");
    return chain;
  };
  chain.delete = () => {
    scritture.push("delete");
    return chain;
  };

  const client = {
    from: (relazione: string) => {
      relazioni.push(relazione);
      return chain;
    },
  } as unknown as SupabaseClient;

  return { client, relazioni, colonne, filtri, ordini, tetti, scritture };
};

const riga = (over: Record<string, unknown> = {}) => ({
  wine_id: "8b1d1a5e-0000-4000-8000-000000000001",
  wine_slug: "azienda-pi1a-rosso-2019",
  produttore: "Azienda PI1A",
  nome: "Rosso",
  annata: 2019,
  formato: "0,75 L",
  tipo: "richiesta",
  fonte: "vinea_interno",
  prezzo_cents: 12_000,
  valuta: "eur",
  observed_at: "2026-08-24T10:00:00.000Z",
  ...over,
});

describe("PriceIntelligenceService — lettura", () => {
  it("legge la vista pubblica e non la tabella base", async () => {
    // La ragione non e stilistica: `wine_price_observations` non ha alcun
    // grant per i ruoli client, quindi nominarla darebbe 42501 in produzione e
    // niente in un test con un doppio. Questo test e la rete che manca al
    // doppio.
    const { client, relazioni } = fakeClient({ data: [riga()] });
    await createSupabasePriceIntelligenceService(client).storico({
      wineId: "8b1d1a5e-0000-4000-8000-000000000001",
    });

    expect(relazioni).toEqual(["wine_price_history"]);
    expect(relazioni).not.toContain("wine_price_observations");
  });

  it("chiede un elenco chiuso di colonne, tutte esposte dalla vista", async () => {
    const { client, colonne } = fakeClient({ data: [] });
    await createSupabasePriceIntelligenceService(client).storico({ wineId: "w" });

    const chieste = colonne[0]!.split(",").map((c) => c.trim()).sort();
    expect(chieste).toEqual([
      "annata",
      "fonte",
      "formato",
      "nome",
      "observed_at",
      "prezzo_cents",
      "produttore",
      "tipo",
      "valuta",
      "wine_id",
      "wine_slug",
    ]);
    // Le colonne che porterebbero a una persona o a una transazione non
    // compaiono, e non basta ometterle: la vista non le ha proprio.
    //
    // Il confronto e sull'elenco gia scomposto e non sulla stringa: `id` e
    // sottostringa di `wine_id`, e una `not.toContain` sul testo grezzo
    // fallirebbe su una colonna del tutto legittima.
    for (const vietata of ["origine_ref", "seller_id", "buyer_id", "order_id", "id"]) {
      expect(chieste).not.toContain(vietata);
    }
  });

  it("non contiene alcun identificativo personale nel risultato", () => {
    const mappata = mapObservation(riga() as never);
    expect(Object.keys(mappata).sort()).toEqual([
      "annata",
      "fonte",
      "formato",
      "nome",
      "observedAt",
      "prezzoCents",
      "produttore",
      "tipo",
      "valuta",
      "wineId",
      "wineSlug",
    ]);
  });

  it("ordina dalla piu recente: e una storia, non un totale", async () => {
    const { client, ordini } = fakeClient({ data: [] });
    await createSupabasePriceIntelligenceService(client).storico({ wineId: "w" });

    expect(ordini).toEqual([{ colonna: "observed_at", ascending: false }]);
  });

  it("filtra sul formato quando lo riceve: una magnum non e una 0,75 L", async () => {
    const { client, filtri } = fakeClient({ data: [] });
    await createSupabasePriceIntelligenceService(client).storico({
      wineId: "w",
      formato: "  Magnum 1,5 L  ",
    });

    expect(filtri).toEqual({ wine_id: "w", formato: "Magnum 1,5 L" });
  });

  it("cerca per wine_slug quando riceve lo slug invece dell'UUID (1B)", async () => {
    // La via che usa /annuncio/[id]: il modello `Wine` porta lo slug del vino,
    // non il suo UUID, e allargarlo per una lettura sola sarebbe un costo
    // pagato da ogni consumatore di `Wine`. La colonna e esposta dalla stessa
    // vista, quindi il ramo nuovo non tocca la tabella base.
    const { client, relazioni, filtri } = fakeClient({ data: [] });
    await createSupabasePriceIntelligenceService(client).storico({
      wineSlug: "  conterno-monfortino-2015  ",
      formato: "0,75 L",
    });

    expect(relazioni).toEqual(["wine_price_history"]);
    expect(filtri).toEqual({ wine_slug: "conterno-monfortino-2015", formato: "0,75 L" });
    // Un solo criterio sul vino: mai i due insieme.
    expect(filtri).not.toHaveProperty("wine_id");
  });

  it("senza un vino identificabile non interroga nulla", async () => {
    // Il tipo dell'input lo vieta, quindi qui si prova cosa succede quando il
    // divieto viene aggirato: NON deve finire in `wine_slug = ''`, che
    // tornerebbe zero righe e farebbe sembrare vuota la storia di un vino che
    // non e stato nemmeno nominato.
    const { client, relazioni } = fakeClient({ data: [] });
    const esito = await createSupabasePriceIntelligenceService(client).storico({
      wineId: "   ",
    } as never);

    expect(relazioni).toEqual([]);
    expect(esito.ok).toBe(false);
    if (esito.ok) return;
    expect(esito.error).toBe("Storico prezzi non disponibile. Riprova.");
  });

  it("una stringa vuota non e un formato: non filtra invece di svuotare", async () => {
    // «Non lo so» non e «il formato senza nome». Filtrare su '' darebbe zero
    // righe, e una storia piena sembrerebbe vuota.
    const { client, filtri } = fakeClient({ data: [] });
    await createSupabasePriceIntelligenceService(client).storico({
      wineId: "w",
      formato: "   ",
    });

    expect(filtri).toEqual({ wine_id: "w" });
  });

  it("applica un tetto predefinito e non si fa superare quello massimo", async () => {
    const a = fakeClient({ data: [] });
    await createSupabasePriceIntelligenceService(a.client).storico({ wineId: "w" });
    expect(a.tetti).toEqual([500]);

    const b = fakeClient({ data: [] });
    await createSupabasePriceIntelligenceService(b.client).storico({
      wineId: "w",
      limite: 99_999,
    });
    expect(b.tetti).toEqual([1000]);

    const c = fakeClient({ data: [] });
    await createSupabasePriceIntelligenceService(c.client).storico({
      wineId: "w",
      limite: 0,
    });
    expect(c.tetti).toEqual([1]);
  });

  it("non scrive: nessun percorso dell'adapter chiama insert, update o delete", async () => {
    const { client, scritture } = fakeClient({ data: [riga()] });
    await createSupabasePriceIntelligenceService(client).storico({ wineId: "w" });

    expect(scritture).toEqual([]);
  });

  it("distingue richiesta e vendita invece di fonderle", async () => {
    // La 1A conserva i due tipi separati. Se li mediasse qui, la 1B non
    // potrebbe piu decidere: troverebbe la decisione gia presa.
    const { client } = fakeClient({
      data: [riga({ tipo: "vendita", prezzo_cents: 9_000 }), riga()],
    });
    const esito = await createSupabasePriceIntelligenceService(client).storico({
      wineId: "w",
    });

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data.map((o) => o.tipo)).toEqual(["vendita", "richiesta"]);
    expect(esito.data.map((o) => o.prezzoCents)).toEqual([9_000, 12_000]);
  });

  it("la fonte resta quella interna: nessun fornitore esterno e acceso", async () => {
    const { client } = fakeClient({ data: [riga()] });
    const esito = await createSupabasePriceIntelligenceService(client).storico({
      wineId: "w",
    });

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data.every((o) => o.fonte === "vinea_interno")).toBe(true);
  });

  it("un errore del database non esce dal servizio", async () => {
    const { client } = fakeClient({
      error: { code: "42501", message: "permission denied for table wine_price_observations" },
    });
    const esito = await createSupabasePriceIntelligenceService(client).storico({
      wineId: "w",
    });

    expect(esito.ok).toBe(false);
    if (esito.ok) return;
    expect(esito.error).toBe("Storico prezzi non disponibile. Riprova.");
    expect(esito.error).not.toContain("wine_price_observations");
    expect(esito.error).not.toContain("42501");
  });

  it("senza client configurato risponde senza tentare la rete", async () => {
    const esito = await createSupabasePriceIntelligenceService(null).storico({
      wineId: "w",
    });

    expect(esito).toEqual(noPriceIntelligenceClient());
  });
});
