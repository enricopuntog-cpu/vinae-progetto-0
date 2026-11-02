import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  contestazioneComeFascicolo,
  parseElencoPostVenditaAdmin,
  parsePostvendita,
} from "@/lib/accessori-postvendita/postvendita";
import { creaAccessoriPostvenditaService } from "./accessori-postvendita-service";

const ORDINE = "11111111-1111-4111-8111-111111111111";

const base = {
  ordineId: ORDINE,
  incassato: true,
  consegna: { registrataAt: "2026-11-02T10:00:00Z", fonte: "manuale_admin", provaVettore: false },
  finestraContestazioneScadeAt: "2026-11-04T10:00:00Z",
  puoContestare: true,
  contestazione: null,
  rimborso: { rimborsatoCents: 0, inCorsoCents: 0 },
  ricavo: null,
};

const storageFinto = (opzioni: { uploadFallisce?: number; rpcFallisce?: boolean; firmaFallisce?: boolean } = {}) => {
  const caricati: string[] = [];
  const rimossi: string[] = [];
  const chiamate: Chiamata[] = [];
  const firme: Array<{ bucket: string; paths: string[]; durata: number }> = [];
  const client = {
    auth: { getUser: async () => ({ data: { user: { id: "utente-test" } } }) },
    rpc: async (nome: string, args: Record<string, unknown>) => {
      chiamate.push({ nome, args });
      return { error: opzioni.rpcFallisce ? { code: "XX000" } : null };
    },
    storage: { from: (bucket: string) => ({
      upload: async (path: string) => {
        caricati.push(path);
        return { error: caricati.length === opzioni.uploadFallisce ? { code: "XX000" } : null };
      },
      remove: async (paths: string[]) => { rimossi.push(...paths); return { error: null }; },
      createSignedUrls: async (paths: string[], durata: number) => {
        firme.push({ bucket, paths, durata });
        return { error: opzioni.firmaFallisce ? { code: "XX000" } : null,
          data: [{ signedUrl: "https://prove.test/1" }, { signedUrl: "" }, { signedUrl: null }] };
      },
    }) },
  } as unknown as SupabaseClient;
  return { client, caricati, rimossi, chiamate, firme };
};
const foto = () => new File(["webp"], "prova.webp", { type: "image/webp" });

type Chiamata = { nome: string; args?: Record<string, unknown> };
const finto = (risposte: Record<string, { data?: unknown; error?: { code?: string; hint?: string } | null }>) => {
  const chiamate: Chiamata[] = [];
  const client = {
    rpc: async (nome: string, args?: Record<string, unknown>) => {
      chiamate.push({ nome, args });
      return { data: risposte[nome]?.data ?? null, error: risposte[nome]?.error ?? null };
    },
    storage: { from: () => ({ createSignedUrls: async () => ({ data: [], error: null }) }) },
  } as unknown as SupabaseClient;
  return { client, chiamate };
};

describe("parsePostvendita (B5C)", () => {
  it("accetta la forma del database e distingue la prova del vettore dalla registrazione manuale", () => {
    const p = parsePostvendita(base);
    expect(p?.consegna).toEqual({ registrataAt: "2026-11-02T10:00:00Z", fonte: "manuale_admin", provaVettore: false });
    expect(parsePostvendita({ ...base, consegna: { ...base.consegna, fonte: "vettore", provaVettore: true } })?.consegna?.provaVettore).toBe(true);
  });

  it("rifiuta forme fuori contratto invece di inventare valori", () => {
    expect(parsePostvendita(null)).toBeNull();
    expect(parsePostvendita({ ...base, incassato: "si" })).toBeNull();
    expect(parsePostvendita({ ...base, consegna: { registrataAt: "x", fonte: "altro", provaVettore: true } })).toBeNull();
    expect(parsePostvendita({ ...base, rimborso: { rimborsatoCents: -1, inCorsoCents: 0 } })).toBeNull();
    expect(parsePostvendita({ ...base, ricavo: { stato: "pagato", importoCents: 1, stornatoCents: 0, rilasciatoAt: null } })).toBeNull();
  });

  it("adatta la contestazione al fascicolo del vino con il ciclo di vita corretto", () => {
    const aperta = parsePostvendita({
      ...base,
      contestazione: {
        stato: "aperta", motivo: "Articolo rotto", descrizione: "Scheggiato.", foto: ["a/b/c.webp"],
        apertaAt: "2026-11-02T11:00:00Z", venditoreScadenzaAt: "2026-11-04T11:00:00Z", puoRispondere: true,
        risposta: null, esitoNota: null, importoRimborsoCents: null, chiusaAt: null,
      },
    });
    expect(aperta).not.toBeNull();
    const fascicolo = contestazioneComeFascicolo(aperta!, { acquirente: ["https://u/1"], venditore: [] });
    expect(fascicolo?.lifecycle_status).toBe("attesa_venditore");
    expect(fascicolo?.foto).toEqual(["https://u/1"]);
    expect(contestazioneComeFascicolo(parsePostvendita(base)!, { acquirente: [], venditore: [] })).toBeNull();
  });
});

describe("parseElencoPostVenditaAdmin (B5C)", () => {
  it("legge contestazioni e rimborsi; rifiuta un'origine ignota", () => {
    const r = {
      rimborsoId: "r1", ordineId: ORDINE, origine: "dovuto_automatico", stato: "richiesto", importoCents: 1000,
      tentativi: 0, richiestoAt: "2026-11-02T10:00:00Z", aggiornatoAt: "2026-11-02T10:00:00Z", ultimoErrore: null,
    };
    expect(parseElencoPostVenditaAdmin({ contestazioni: [], rimborsi: [r] })?.rimborsi).toHaveLength(1);
    expect(parseElencoPostVenditaAdmin({ contestazioni: [], rimborsi: [{ ...r, origine: "altro" }] })).toBeNull();
    expect(parseElencoPostVenditaAdmin({ contestazioni: [] })).toBeNull();
  });
});

describe("creaAccessoriPostvenditaService (B5C)", () => {
  it("senza client: errore chiaro, nessuna chiamata", async () => {
    const s = creaAccessoriPostvenditaService(null);
    expect((await s.leggi(ORDINE)).ok).toBe(false);
    expect((await s.adminElenco()).ok).toBe(false);
  });

  it("identificativo non valido: rifiutato prima della rete", async () => {
    const { client, chiamate } = finto({});
    const s = creaAccessoriPostvenditaService(client);
    expect((await s.leggi("non-un-uuid")).ok).toBe(false);
    expect((await s.adminDecidi({ ordineId: "x", esito: "respinta", importoCents: null, nota: "" })).ok).toBe(false);
    expect(chiamate).toHaveLength(0);
  });

  it("la decisione porta l'importo solo per «rimborsata»; la risposta del database è tradotta, mai il testo interno", async () => {
    const { client, chiamate } = finto({ accessori_contestazione_admin_decidi: { error: { code: "22023", hint: "importo_non_valido" } } });
    const s = creaAccessoriPostvenditaService(client);
    const r = await s.adminDecidi({ ordineId: ORDINE, esito: "rimborsata", importoCents: 1500, nota: "x" });
    expect(r).toEqual({ ok: false, error: "Importo del rimborso non valido." });
    await s.adminDecidi({ ordineId: ORDINE, esito: "respinta", importoCents: 1500, nota: "x" });
    expect(chiamate[0]?.args).toMatchObject({ p_esito: "rimborsata", p_importo_cents: 1500 });
    expect(chiamate[1]?.args).toMatchObject({ p_esito: "respinta", p_importo_cents: null });
  });

  it("leggi valida la risposta con il parser rigido", async () => {
    const buona = creaAccessoriPostvenditaService(finto({ accessori_postvendita_leggi: { data: base } }).client);
    expect((await buona.leggi(ORDINE)).ok).toBe(true);
    const cattiva = creaAccessoriPostvenditaService(finto({ accessori_postvendita_leggi: { data: { ordineId: ORDINE } } }).client);
    expect((await cattiva.leggi(ORDINE)).ok).toBe(false);
  });

  for (const operazione of ["apri", "rispondi"] as const) {
    const invia = (s: ReturnType<typeof creaAccessoriPostvenditaService>, files: File[]) => operazione === "apri"
      ? s.apriContestazione({ ordineId: ORDINE, motivo: "Articolo rotto", descrizione: "Rotto.", foto: files })
      : s.rispondi({ ordineId: ORDINE, tipo: "contesta", risposta: "Integro.", foto: files });
    it(`${operazione}: carica le prove, invia solo percorsi e non cancella sul successo`, async () => {
      const f = storageFinto();
      expect((await invia(creaAccessoriPostvenditaService(f.client), [foto(), foto()])).ok).toBe(true);
      expect(f.caricati).toHaveLength(2);
      expect(f.chiamate[0]?.nome).toBe(operazione === "apri" ? "accessori_contestazione_apri" : "accessori_contestazione_venditore_rispondi");
      expect(f.chiamate[0]?.args?.p_foto).toEqual(f.caricati);
      expect(f.rimossi).toHaveLength(0);
    });
    it(`${operazione}: upload parziale fallito ripulisce solo le prove già caricate e non chiama RPC`, async () => {
      const f = storageFinto({ uploadFallisce: 2 });
      expect((await invia(creaAccessoriPostvenditaService(f.client), [foto(), foto()])).ok).toBe(false);
      expect(f.rimossi).toEqual([f.caricati[0]!]);
      expect(f.chiamate).toHaveLength(0);
    });
    it(`${operazione}: RPC rifiutata ripulisce tutte le nuove prove`, async () => {
      const f = storageFinto({ rpcFallisce: true });
      expect((await invia(creaAccessoriPostvenditaService(f.client), [foto(), foto()])).ok).toBe(false);
      expect(f.rimossi).toEqual(f.caricati);
    });
  }

  it("firmaProve usa bucket privato e TTL 900, filtra URL vuoti e gestisce gli errori", async () => {
    const f = storageFinto();
    const s = creaAccessoriPostvenditaService(f.client);
    expect(await s.firmaProve([])).toEqual([]);
    expect(f.firme).toHaveLength(0);
    expect(await s.firmaProve(["a.webp"])).toEqual(["https://prove.test/1"]);
    expect(f.firme).toEqual([{ bucket: "dispute-evidence", paths: ["a.webp"], durata: 900 }]);
    expect(await creaAccessoriPostvenditaService(storageFinto({ firmaFallisce: true }).client).firmaProve(["a"])).toEqual([]);
    expect(await creaAccessoriPostvenditaService(null).firmaProve(["a"])).toEqual([]);
  });

  it("adminConsegna e adminReso usano solo le porte di dominio, con errori sicuri", async () => {
    const f = finto({ accessori_reso_rientro_admin_registra: { error: { hint: "quantita_non_valida" } } });
    const s = creaAccessoriPostvenditaService(f.client);
    expect((await s.adminConsegna({ ordineId: ORDINE, riferimento: "Prova manuale" })).ok).toBe(true);
    expect(await s.adminReso({ ordineId: ORDINE, quantita: 2, nota: "Rientrati" })).toEqual({ ok: false, error: "Quantità non valida." });
    expect(f.chiamate).toEqual([
      { nome: "accessori_consegna_admin_registra", args: { p_ordine: ORDINE, p_riferimento: "Prova manuale" } },
      { nome: "accessori_reso_rientro_admin_registra", args: { p_ordine: ORDINE, p_quantita: 2, p_nota: "Rientrati" } },
    ]);
    await s.adminConsegna({ ordineId: "x", riferimento: "x" });
    await s.adminReso({ ordineId: "x", quantita: 2, nota: "x" });
    expect(f.chiamate).toHaveLength(2);
  });

  it("nessun metodo raggiunge Stripe, un rimborso o un rilascio", () => {
    const s = creaAccessoriPostvenditaService(null) as unknown as Record<string, unknown>;
    expect(Object.keys(s).sort()).toEqual([
      "adminConsegna", "adminDecidi", "adminElenco", "adminReso", "apriContestazione", "firmaProve", "leggi", "rispondi",
    ]);
  });
});
