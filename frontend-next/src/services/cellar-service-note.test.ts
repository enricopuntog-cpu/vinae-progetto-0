import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createCellarService } from "@/services/cellar-service";
import { notaVuota, type NotaPersonaleVino } from "@/lib/cantina/note-personali";

type Chiamata = { tipo: "rpc" | "from"; nome: string; parametri?: Record<string, unknown> };

/**
 * Client finto: `from(tabella)` restituisce una catena che si risolve nelle righe date; `rpc`
 * registra la chiamata. Nessuna rete e nessun database.
 */
function fakeClient(opzioni: {
  righe?: Record<string, unknown[]>;
  rpc?: (nome: string) => { data?: unknown; error?: { code?: string; message?: string } | null };
}) {
  const chiamate: Chiamata[] = [];
  const catena = (tabella: string): unknown => {
    const esito = Promise.resolve({ data: opzioni.righe?.[tabella] ?? [], error: null });
    const proxy: unknown = new Proxy(() => undefined, {
      get(_t, prop) {
        if (prop === "then") return esito.then.bind(esito);
        return () => proxy;
      },
    });
    return proxy;
  };
  const client = {
    from: (tabella: string) => {
      chiamate.push({ tipo: "from", nome: tabella });
      return catena(tabella);
    },
    rpc: (nome: string, parametri?: Record<string, unknown>) => {
      chiamate.push({ tipo: "rpc", nome, parametri });
      const r = opzioni.rpc?.(nome) ?? { data: null, error: null };
      return Promise.resolve({ data: r.data ?? null, error: r.error ?? null });
    },
    auth: { getUser: () => Promise.resolve({ data: { user: null } }) },
    storage: { from: () => ({ createSignedUrls: () => Promise.resolve({ data: [], error: null }) }) },
  } as unknown as SupabaseClient;
  return { client, chiamate };
}

const nota = (extra: Partial<NotaPersonaleVino> = {}): NotaPersonaleVino => ({ ...notaVuota(), ...extra });

describe("CellarService — note personali sul vino", () => {
  it("carica: legge la tabella delle note e le indicizza per slug del vino", async () => {
    const { client, chiamate } = fakeClient({
      righe: {
        wine_personal_notes: [
          {
            abbinamenti: ["Brasato"],
            temperatura_servizio_c: 16,
            decantazione_minuti: 30,
            calice: "Ballon",
            annata_dichiarata: 2016,
            non_millesimato: false,
            denominazione_dichiarata: "Barolo",
            regione_dichiarata: "Piemonte",
            osservazioni: "Mia nota",
            updated_at: "2026-11-20T10:00:00Z",
            wines: { slug: "barolo-2015" },
          },
          {
            abbinamenti: [],
            temperatura_servizio_c: null,
            decantazione_minuti: null,
            calice: "",
            annata_dichiarata: null,
            non_millesimato: true,
            denominazione_dichiarata: "",
            regione_dichiarata: "",
            osservazioni: "",
            updated_at: "2026-11-20T11:00:00Z",
            wines: [{ slug: "spumante-nv" }],
          },
        ],
      },
    });
    const dati = await createCellarService(client).carica();
    expect(chiamate.some((c) => c.tipo === "from" && c.nome === "wine_personal_notes")).toBe(true);
    expect(dati.notePerVino["barolo-2015"]).toEqual({
      abbinamenti: ["Brasato"],
      temperaturaC: 16,
      decantazioneMinuti: 30,
      calice: "Ballon",
      annataDichiarata: 2016,
      nonMillesimato: false,
      denominazione: "Barolo",
      regione: "Piemonte",
      osservazioni: "Mia nota",
      aggiornataAt: "2026-11-20T10:00:00Z",
    });
    expect(dati.notePerVino["spumante-nv"].nonMillesimato).toBe(true);
    expect(Object.keys(dati.notePerVino).sort()).toEqual(["barolo-2015", "spumante-nv"]);
  });

  it("carica: senza note l'oggetto è vuoto e non rompe la Cantina", async () => {
    const dati = await createCellarService(fakeClient({}).client).carica();
    expect(dati.notePerVino).toEqual({});
  });

  it("carica: senza client la Cantina è vuota e senza note", async () => {
    expect((await createCellarService(null).carica()).notePerVino).toEqual({});
  });

  it("salvaNotaVino: una sola chiamata alla funzione controllata, con i parametri tipizzati", async () => {
    const { client, chiamate } = fakeClient({});
    const esito = await createCellarService(client).salvaNotaVino(
      "barolo-2015",
      nota({ abbinamenti: ["Brasato"], temperaturaC: 16, decantazioneMinuti: 45, calice: "Ballon", osservazioni: "x" }),
    );
    expect(esito).toEqual({ ok: true, data: undefined });
    expect(chiamate).toEqual([
      {
        tipo: "rpc",
        nome: "cellar_nota_vino_salva",
        parametri: {
          p_wine_slug: "barolo-2015",
          p_abbinamenti: ["Brasato"],
          p_temperatura: 16,
          p_decantazione: 45,
          p_calice: "Ballon",
          p_annata: null,
          p_non_millesimato: false,
          p_denominazione: "",
          p_regione: "",
          p_osservazioni: "x",
        },
      },
    ]);
  });

  it("salvaNotaVino non scrive mai direttamente nelle tabelle", async () => {
    const { client, chiamate } = fakeClient({});
    await createCellarService(client).salvaNotaVino("v", nota({ osservazioni: "x" }));
    await createCellarService(client).eliminaNotaVino("v");
    expect(chiamate.filter((c) => c.tipo === "from")).toEqual([]);
  });

  it("salvaNotaVino rifiuta lato client una nota non valida, senza chiamare il database", async () => {
    const { client, chiamate } = fakeClient({});
    const esito = await createCellarService(client).salvaNotaVino("v", nota({ temperaturaC: 99 }));
    expect(esito.ok).toBe(false);
    expect(chiamate).toEqual([]);
  });

  it("eliminaNotaVino chiama la funzione di cancellazione sul solo vino indicato", async () => {
    const { client, chiamate } = fakeClient({});
    expect(await createCellarService(client).eliminaNotaVino("barolo-2015")).toEqual({ ok: true, data: undefined });
    expect(chiamate).toEqual([{ tipo: "rpc", nome: "cellar_nota_vino_elimina", parametri: { p_wine_slug: "barolo-2015" } }]);
  });

  it("un errore del database non espone messaggi interni; un messaggio applicativo P0001 sì", async () => {
    const interno = fakeClient({ rpc: () => ({ error: { code: "42501", message: "permission denied for table x" } }) });
    const r1 = await createCellarService(interno.client).salvaNotaVino("v", nota({ osservazioni: "x" }));
    expect(r1.ok).toBe(false);
    if (!r1.ok) expect(r1.error).not.toContain("permission");

    const applicativo = fakeClient({ rpc: () => ({ error: { code: "P0001", message: "Puoi annotare solo i vini presenti nella tua Cantina." } }) });
    const r2 = await createCellarService(applicativo.client).salvaNotaVino("v", nota({ osservazioni: "x" }));
    expect(r2).toEqual({ ok: false, error: "Puoi annotare solo i vini presenti nella tua Cantina." });
  });

  it("senza client: errore di connessione, nessuna eccezione", async () => {
    const svc = createCellarService(null);
    expect((await svc.salvaNotaVino("v", nota({ osservazioni: "x" }))).ok).toBe(false);
    expect((await svc.eliminaNotaVino("v")).ok).toBe(false);
  });
});
