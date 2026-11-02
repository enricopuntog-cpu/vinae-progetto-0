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

  it("nessun metodo raggiunge Stripe, un rimborso o un rilascio", () => {
    const s = creaAccessoriPostvenditaService(null) as unknown as Record<string, unknown>;
    expect(Object.keys(s).sort()).toEqual([
      "adminConsegna", "adminDecidi", "adminElenco", "adminReso", "apriContestazione", "firmaProve", "leggi", "rispondi",
    ]);
  });
});
