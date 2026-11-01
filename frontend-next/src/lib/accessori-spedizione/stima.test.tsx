import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { renderToStaticMarkup } from "react-dom/server";
import { RiepilogoStimaLogistica } from "@/components/vinea/accessori-spedizione/StimaSpedizioneAccessorio";
import { creaAccessoriLogisticaService } from "@/services/accessori-spedizione-service";
import { messaggioMotivoLogistica, parseStimaLogistica } from "./stima";

const ID = "12f20000-0000-4000-8000-0000000000a1";

const valida = (extra: Record<string, unknown> = {}) => ({
  ok: true,
  destinazione: "punto_ritiro",
  ordinabile: true,
  motivoNonOrdinabile: null,
  prezzo: { unitarioCents: 2000, quantita: 2, subtotaleCents: 4000 },
  commissione: { cents: 480, margineBps: 1000 },
  pagamento: { coperturaSuLogisticaCents: 25 },
  logistica: {
    trasportoCents: 1180,
    assicurazioneCents: 0,
    assicurazioneRichiesta: false,
    totaleCents: 1180,
    colli: 2,
    pezziPerCollo: 1,
  },
  requisiti: { fragile: false, imballaggioProtettivoRichiesto: false, imballaggioACuraDel: "venditore" },
  totaleAcquirenteCents: 4000 + 480 + 1180 + 25,
  mancanti: [],
  ...extra,
});

const testo = (m: string) => m.replace(/<[^>]+>/g, " ").replace(/&#x27;/g, "'").replace(/\s+/g, " ");

describe("parseStimaLogistica", () => {
  it("legge una stima coerente, con le voci separate", () => {
    const s = parseStimaLogistica(valida());
    expect(s?.ok).toBe(true);
    if (s?.ok) {
      expect(s.commissioneCents).toBe(480);
      expect(s.coperturaPagamentoCents).toBe(25);
      expect(s.logistica.totaleCents).toBe(1180);
      expect(s.totaleAcquirenteCents).toBe(5685);
      expect(s.congelato).toBe(false);
    }
  });

  it("rifiuta somme che non tornano al centesimo", () => {
    expect(parseStimaLogistica(valida({ totaleAcquirenteCents: 5000 }))).toBeNull();
    expect(parseStimaLogistica(valida({ prezzo: { unitarioCents: 2000, quantita: 2, subtotaleCents: 3999 } }))).toBeNull();
    expect(
      parseStimaLogistica(
        valida({ logistica: { ...valida().logistica, totaleCents: 1000 } }),
      ),
    ).toBeNull();
  });

  it("rifiuta un domicilio dichiarato ordinabile, o un non ordinabile senza motivo", () => {
    expect(parseStimaLogistica(valida({ destinazione: "domicilio", ordinabile: true }))).toBeNull();
    expect(parseStimaLogistica(valida({ destinazione: "domicilio", ordinabile: false }))).toBeNull();
    const ok = parseStimaLogistica(
      valida({ destinazione: "domicilio", ordinabile: false, motivoNonOrdinabile: "domicilio_non_ordinabile" }),
    );
    expect(ok?.ok && ok.ordinabile).toBe(false);
  });

  it("l'assicurazione compare solo se richiesta e un preventivo congelato esige id e scadenza", () => {
    expect(
      parseStimaLogistica(
        valida({
          logistica: { ...valida().logistica, assicurazioneCents: 100, totaleCents: 1280 },
          totaleAcquirenteCents: 5785,
        }),
      ),
    ).toBeNull();
    expect(parseStimaLogistica(valida({ congelato: true }))).toBeNull();
    expect(parseStimaLogistica(valida({ preventivoId: ID }))).toBeNull();
    const c = parseStimaLogistica(valida({ congelato: true, preventivoId: ID, scadeAt: "2026-11-01T15:43:03+00:00" }));
    expect(c?.ok && c.congelato && c.preventivoId).toBe(ID);
  });

  it("legge il rifiuto fail-closed con i motivi e nessun prezzo", () => {
    const n = parseStimaLogistica({ ok: false, mancanti: ["peso_mancante", "misure_mancanti"], ordinabile: false });
    expect(n).toEqual({ ok: false, destinazione: null, ordinabile: false, motivi: ["peso_mancante", "misure_mancanti"] });
    expect(parseStimaLogistica({ ok: false, mancanti: [], ordinabile: false })).toBeNull();
    expect(parseStimaLogistica({ ok: false, mancanti: ["x"], ordinabile: true })).toBeNull();
    expect(parseStimaLogistica({ ok: false, mancanti: ["Peso Mancante!"], ordinabile: false })).toBeNull();
  });

  it("rifiuta forme sbagliate", () => {
    for (const v of [null, 3, "x", [], {}, { ok: "si" }, valida({ prezzo: null }), valida({ requisiti: {} })]) {
      expect(parseStimaLogistica(v)).toBeNull();
    }
  });
});

describe("messaggi e vista", () => {
  it("ogni motivo noto ha una frase italiana; uno ignoto non rivela dettagli tecnici", () => {
    expect(messaggioMotivoLogistica("tariffa_accessori_non_configurata")).toContain("non è ancora disponibile");
    expect(messaggioMotivoLogistica("qualcosa_di_nuovo")).toBe("La spedizione non è disponibile in questo momento.");
  });

  it("non disponibile: nessun importo, solo il perché", () => {
    const stima = parseStimaLogistica({ ok: false, mancanti: ["servizio_per_rotta"], ordinabile: false });
    if (!stima) throw new Error("stima");
    const t = testo(renderToStaticMarkup(<RiepilogoStimaLogistica stato={{ tipo: "pronto", stima }} />));
    expect(t).toContain("non c'è ancora un servizio");
    expect(t).not.toMatch(/€|Totale/);
  });

  it("disponibile: prezzo, commissione, spedizione, pagamento e totale in voci distinte", () => {
    const stima = parseStimaLogistica(valida());
    if (!stima) throw new Error("stima");
    const t = testo(renderToStaticMarkup(<RiepilogoStimaLogistica stato={{ tipo: "pronto", stima }} />));
    expect(t).toContain("2 pezzi × 20,00");
    expect(t).toContain("Commissione Vinea");
    expect(t).toContain("Spedizione (2 colli)");
    expect(t).toContain("Costo di pagamento sulla spedizione");
    expect(t).toContain("56,85");
  });
});

describe("creaAccessoriLogisticaService", () => {
  const finto = (risposta: { data: unknown; error: unknown }) => {
    const chiamate: Array<{ fn: string; args: Record<string, unknown> }> = [];
    const client = {
      rpc: async (fn: string, args: Record<string, unknown>) => {
        chiamate.push({ fn, args });
        return risposta;
      },
    } as unknown as SupabaseClient;
    return { client, chiamate };
  };

  it("invia solo annuncio, quantità, modalità e assicurazione: mai un importo", async () => {
    const { client, chiamate } = finto({ data: valida(), error: null });
    const r = await creaAccessoriLogisticaService(client).stima({ annuncioId: ID, quantita: 2 });
    expect(r.ok).toBe(true);
    expect(chiamate).toEqual([
      {
        fn: "annuncio_accessorio_logistica_preventivo",
        args: { p_annuncio: ID, p_quantita: 2, p_destinazione: "punto_ritiro", p_assicurazione: false },
      },
    ]);
  });

  it("richieste non valide non raggiungono il database", async () => {
    const { client, chiamate } = finto({ data: valida(), error: null });
    const s = creaAccessoriLogisticaService(client);
    for (const r of [
      { annuncioId: "x", quantita: 1 },
      { annuncioId: ID, quantita: 0 },
      { annuncioId: ID, quantita: 121 },
      { annuncioId: ID, quantita: 1.5 },
      { annuncioId: ID, quantita: 1, destinazione: "corriere" as never },
    ]) {
      expect((await s.stima(r)).ok).toBe(false);
      expect((await s.congela(r)).ok).toBe(false);
    }
    expect((await s.leggi("x")).ok).toBe(false);
    expect(chiamate).toHaveLength(0);
  });

  it("senza client, con errore del database o con risposta incoerente: non disponibile, senza dettagli", async () => {
    expect((await creaAccessoriLogisticaService(null).stima({ annuncioId: ID, quantita: 1 })).ok).toBe(false);
    const errore = finto({ data: null, error: { code: "42501", hint: "funzione_non_attiva", message: "segreto interno" } });
    const e = await creaAccessoriLogisticaService(errore.client).congela({ annuncioId: ID, quantita: 1 });
    expect(e).toEqual({ ok: false, error: "La spedizione degli Accessori non è ancora disponibile." });
    const rotta = finto({ data: valida({ totaleAcquirenteCents: 1 }), error: null });
    expect((await creaAccessoriLogisticaService(rotta.client).stima({ annuncioId: ID, quantita: 2 })).ok).toBe(false);
  });

  it("usa le sole porte di logistica", async () => {
    const { client, chiamate } = finto({ data: valida({ congelato: true, preventivoId: ID, scadeAt: "2026-11-01T15:43:03+00:00" }), error: null });
    const s = creaAccessoriLogisticaService(client);
    await s.congela({ annuncioId: ID, quantita: 2, assicurazione: false });
    await s.leggi(ID);
    expect(chiamate.map((c) => c.fn)).toEqual([
      "accessori_logistica_preventivo_congela",
      "accessori_logistica_preventivo_leggi",
    ]);
  });
});
