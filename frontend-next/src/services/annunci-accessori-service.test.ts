import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  creaAnnunciAccessoriAdminService,
  creaAnnunciAccessoriService,
} from "./annunci-accessori-service";

const U1 = "11111111-1111-4111-8111-111111111111";
const U2 = "22222222-2222-4222-8222-222222222222";

type Chiamata = { nome: string; args: Record<string, unknown> };

function finto(rpc?: (nome: string, args: Record<string, unknown>) => { data?: unknown; error?: unknown }) {
  const chiamate: Chiamata[] = [];
  const client = {
    rpc: async (nome: string, args: Record<string, unknown> = {}) => {
      chiamate.push({ nome, args });
      const r = rpc?.(nome, args) ?? { data: null };
      return { data: r.data ?? null, error: r.error ?? null };
    },
    from: () => {
      throw new Error("le tabelle non si leggono dal browser");
    },
  } as unknown as SupabaseClient;
  return { client, chiamate };
}

const annuncio = {
  id: U1, cantina_id: U2, stato: "bozza", quantita: 2, prezzo_unitario_cents: 1200,
  condizione: "usato", descrizione: "", conforme: true,
  spedizione: { peso_g: null, lunghezza_mm: null, larghezza_mm: null, altezza_mm: null, fragile: false },
  posseduti: 6, impegnati: 2, disponibili: 4, foto: 0, inviato_at: null, ritirato_at: null,
  created_at: "2026-10-21T10:00:00Z", updated_at: "2026-10-21T10:00:00Z",
};

const dati = {
  cantinaId: U2, quantita: 2, prezzoUnitarioCents: 1200, condizione: "usato" as const,
  descrizione: "", conforme: true,
  spedizione: { pesoG: 420, lunghezzaMm: 90, larghezzaMm: 90, altezzaMm: 230, fragile: true },
};

describe("servizio degli annunci Accessori", () => {
  it("senza client risponde con un errore leggibile, mai con un'eccezione", async () => {
    const s = creaAnnunciAccessoriService(null);
    expect((await s.stato()).ok).toBe(false);
    expect((await s.elenco(false)).ok).toBe(false);
    expect((await s.preventivo(1000, 1)).ok).toBe(false);
    expect((await s.salva(U1, dati)).ok).toBe(false);
    expect((await s.transizione(U1, "ritirato")).ok).toBe(false);
  });

  it("salva passa solo i campi dell'offerta: nessuna classe, margine, commissione, totale, stato o venditore", async () => {
    const { client, chiamate } = finto(() => ({ data: annuncio }));
    const r = await creaAnnunciAccessoriService(client).salva(U1, dati);
    expect(r.ok).toBe(true);
    expect(chiamate).toHaveLength(1);
    expect(chiamate[0].nome).toBe("annunci_accessori_salva");
    const p = chiamate[0].args.p_dati as Record<string, unknown>;
    expect(Object.keys(p).sort()).toEqual([
      "altezza_mm", "cantina_id", "condizione", "conforme", "descrizione", "fragile", "larghezza_mm",
      "lunghezza_mm", "peso_g", "prezzo_unitario_cents", "quantita",
    ]);
    expect(Object.keys(chiamate[0].args).sort()).toEqual(["p_dati", "p_id"]);
    expect(p.prezzo_unitario_cents).toBe(1200);
  });

  it("il preventivo manda solo prezzo, quantità e accessorio; un id non valido non parte", async () => {
    const { client, chiamate } = finto(() => ({
      data: {
        dominio: "accessori_enologici", classe: "privato", venditore_ammesso: true, motivo: null,
        vendite_attive: false, disponibili: 4, preventivo: null,
        spedizione: { disponibile: false, motivi: ["tariffa_accessori_non_configurata"] },
      },
    }));
    const s = creaAnnunciAccessoriService(client);
    const ok = await s.preventivo(1200, 2, U2);
    expect(ok.ok).toBe(true);
    expect(chiamate[0].args).toEqual({ p_prezzo_unitario_cents: 1200, p_quantita: 2, p_cantina_id: U2 });
    const no = await s.preventivo(1200, 2, "x");
    expect(no.ok).toBe(false);
    expect(chiamate).toHaveLength(1);
  });

  it("una risposta incoerente del preventivo diventa «non disponibile», non un importo", async () => {
    const { client } = finto(() => ({ data: { classe: "privato", venditore_ammesso: true } }));
    const r = await creaAnnunciAccessoriService(client).preventivo(1200, 2);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error).toContain("non è disponibile");
  });

  it("la transizione chiede solo bozza, in_revisione o ritirato per un id, mai uno stato acquistabile", async () => {
    const { client, chiamate } = finto(() => ({ data: { ...annuncio, stato: "in_revisione", inviato_at: "2026-10-21T10:05:00Z" } }));
    const r = await creaAnnunciAccessoriService(client).transizione(U1, "in_revisione");
    expect(r.ok).toBe(true);
    expect(chiamate[0]).toEqual({ nome: "annunci_accessori_transizione", args: { p_id: U1, p_a: "in_revisione" } });
  });

  it("gli errori del database diventano frasi, senza esporre interni", async () => {
    const { client } = finto(() => ({ error: { code: "22023", hint: "quantita_non_disponibile", message: "dettaglio interno" } }));
    const r = await creaAnnunciAccessoriService(client).salva(U1, dati);
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.error).toContain("pezzi disponibili");
      expect(r.error).not.toContain("interno");
    }
    const { client: c2 } = finto(() => ({ error: { code: "42501", hint: "partner_percorso_non_consentito" } }));
    const p = await creaAnnunciAccessoriService(c2).salva(U1, dati);
    expect(p.ok).toBe(false);
    if (!p.ok) expect(p.error).toContain("Partner");
  });

  it("elenco: scarta le voci malformate e passa il filtro dei ritirati", async () => {
    const { client, chiamate } = finto(() => ({ data: [annuncio, { stato: "attivo" }, null] }));
    const r = await creaAnnunciAccessoriService(client).elenco(true);
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.data).toHaveLength(1);
    expect(chiamate[0]).toEqual({ nome: "annunci_accessori_elenca", args: { p_ritirati: true } });
  });

  it("lo stato con vendite dichiarate attive chiude la sezione", async () => {
    const { client } = finto(() => ({
      data: { abilitata: true, vendite_attive: true, classe: "privato", venditore_ammesso: true, motivo: null },
    }));
    expect((await creaAnnunciAccessoriService(client).stato()).ok).toBe(false);
  });
});

describe("servizio admin", () => {
  it("passa solo l'interruttore e il motivo; il permesso lo decide il database", async () => {
    const { client, chiamate } = finto();
    const r = await creaAnnunciAccessoriAdminService(client).imposta(true, "collaudo");
    expect(r.ok).toBe(true);
    expect(chiamate[0]).toEqual({ nome: "annunci_accessori_admin_imposta", args: { p_attiva: true, p_motivo: "collaudo" } });
  });

  it("un rifiuto per mancanza di rilascio è un messaggio, non un'eccezione", async () => {
    const { client } = finto(() => ({ error: { code: "42501", hint: "rilascio_non_autorizzato" } }));
    const r = await creaAnnunciAccessoriAdminService(client).imposta(true, "x");
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error).toContain("approvazione esplicita del titolare");
  });

  it("legge lo stato e rifiuta una pubblicazione dichiarata attiva", async () => {
    const buono = { preparazione_attiva: false, pubblicazione_attiva: false, cantina_funzione_attiva: true, puo_rilasciare: true };
    expect((await creaAnnunciAccessoriAdminService(finto(() => ({ data: buono })).client).stato()).ok).toBe(true);
    const guasto = { ...buono, pubblicazione_attiva: true };
    expect((await creaAnnunciAccessoriAdminService(finto(() => ({ data: guasto })).client).stato()).ok).toBe(false);
  });
});
