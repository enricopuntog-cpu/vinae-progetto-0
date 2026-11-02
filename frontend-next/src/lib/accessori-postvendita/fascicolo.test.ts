import { describe, expect, it } from "bun:test";
import { caricaFascicolo, creaCaricatoreFascicolo, dettaglioAccessorioDisponibile, type FascicoloAccessorio } from "./fascicolo";
import type { PostVenditaAccessorio } from "./postvendita";
import type { Result } from "@/services/types";

const postvendita: PostVenditaAccessorio = {
  ordineId: "ordine-a", incassato: true, consegna: null, finestraContestazioneScadeAt: null,
  puoContestare: false, contestazione: null, rimborso: null, ricavo: null,
};
const buono: Result<FascicoloAccessorio> = { ok: true, data: { postvendita, foto: { acquirente: [], venditore: [] } } };
const errore: Result<FascicoloAccessorio> = { ok: false, error: "Riprova." };
const servizio = (p = postvendita) => ({ leggi: async () => ({ ok: true as const, data: p }), firmaProve: async (paths: string[]) => paths.map(p => `https://prove.test/${p}`) });

describe("fascicolo Accessori: caricamento e gate", () => {
  it("carica entrambe le raccolte di prove e conserva risposta e importi del DB", async () => {
    const p: PostVenditaAccessorio = { ...postvendita, rimborso: { rimborsatoCents: 1200, inCorsoCents: 200 }, contestazione: {
      stato: "aperta", motivo: "Articolo rotto", descrizione: "Rotto.", foto: ["buyer.webp"], apertaAt: "2026-11-01T10:00:00Z",
      venditoreScadenzaAt: "2026-11-03T10:00:00Z", puoRispondere: false,
      risposta: { tipo: "contesta", testo: "Era integro.", foto: ["seller.webp"], at: "2026-11-02T10:00:00Z" },
      esitoNota: null, importoRimborsoCents: null, chiusaAt: null,
    } };
    const r = await caricaFascicolo(servizio(p), "ordine-a");
    expect(r).toEqual({ ok: true, data: { postvendita: p, foto: { acquirente: ["https://prove.test/buyer.webp"], venditore: ["https://prove.test/seller.webp"] } } });
  });
  it("non accetta il fascicolo di un altro ordine", async () => {
    expect((await caricaFascicolo(servizio(), "ordine-b")).ok).toBe(false);
  });
  it("firma incompleta: errore esplicito, nessun fascicolo decidibile", async () => {
    const p = { ...postvendita, contestazione: { foto: ["a"] } } as PostVenditaAccessorio;
    expect((await caricaFascicolo({ ...servizio(p), firmaProve: async () => [] }, "ordine-a")).ok).toBe(false);
  });
  it("errori di lettura e rigetti diventano risultati sicuri", async () => {
    expect(await caricaFascicolo({ ...servizio(), leggi: async () => errore }, "ordine-a")).toEqual(errore);
    const r = await caricaFascicolo({ ...servizio(), leggi: async () => { throw new Error("SQL segreto"); } }, "ordine-a");
    expect(r.ok).toBe(false);
    expect(JSON.stringify(r)).not.toContain("SQL segreto");
  });
  it("una selezione lenta non sovrascrive quella successiva", async () => {
    let completa!: (v: Result<PostVenditaAccessorio>) => void;
    const lento = { ...servizio(), leggi: () => new Promise<Result<PostVenditaAccessorio>>(r => { completa = r; }) };
    const caricatore = creaCaricatoreFascicolo();
    const applicati: unknown[] = [];
    const prima = caricatore.carica(lento, "ordine-a", r => applicati.push(r));
    await caricatore.carica(servizio({ ...postvendita, ordineId: "ordine-b" }), "ordine-b", r => applicati.push(r));
    completa({ ok: true, data: postvendita });
    await prima;
    expect(applicati).toHaveLength(1);
    expect(applicati[0]).toMatchObject({ data: { postvendita: { ordineId: "ordine-b" } } });
  });
  it("l'input manuale invalida anche una firma ancora in volo", async () => {
    let completa!: (v: string[]) => void;
    const caricatore = creaCaricatoreFascicolo();
    let applicato = false;
    const firma = new Promise<string[]>(r => { completa = r; });
    const pending = caricatore.carica({ ...servizio(), firmaProve: () => firma }, "ordine-a", () => { applicato = true; });
    caricatore.invalida();
    completa([]);
    await pending;
    expect(applicato).toBe(false);
  });
  it("flag spente: incassato disponibile, non incassato e simulato chiusi", () => {
    expect(dettaglioAccessorioDisponibile(false, buono, { stato: "pagato", pagamentoSimulato: false })).toBe(true);
    const nonIncassato = { ok: true as const, data: { ...buono.data, postvendita: { ...postvendita, incassato: false } } };
    expect(dettaglioAccessorioDisponibile(false, nonIncassato, { stato: "in_attesa_pagamento", pagamentoSimulato: false })).toBe(false);
    expect(dettaglioAccessorioDisponibile(false, nonIncassato, { stato: "pagato", pagamentoSimulato: true })).toBe(false);
    expect(dettaglioAccessorioDisponibile(true, nonIncassato, { stato: "in_attesa_pagamento", pagamentoSimulato: false })).toBe(true);
  });
  it("errore di lettura: solo pagato reale conserva il percorso di riprova a flag spente", () => {
    expect(dettaglioAccessorioDisponibile(false, errore, { stato: "pagato", pagamentoSimulato: false })).toBe(true);
    expect(dettaglioAccessorioDisponibile(false, errore, { stato: "pagato", pagamentoSimulato: true })).toBe(false);
    expect(dettaglioAccessorioDisponibile(false, errore, { stato: "in_attesa_pagamento", pagamentoSimulato: false })).toBe(false);
  });
});
