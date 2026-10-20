import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { creaAccessoriAdminService, creaAccessoriLetturaService } from "./accessori-service";

type Risposta = { data: unknown; error: { code?: string; message?: string; hint?: string } | null };

const ID = "11111111-1111-4111-8111-111111111111";
const IMG = "22222222-2222-4222-8222-222222222222";
const PERCORSO = `${ID}/${IMG}.webp`;

function client(risposte: Risposta[], storage?: { upload?: Risposta; remove?: Risposta }) {
  const chiamate: Array<{ tipo: string; args: unknown[] }> = [];
  const c = {
    rpc: (nome: string, args?: unknown) => {
      chiamate.push({ tipo: `rpc:${nome}`, args: [args] });
      const r = risposte.shift();
      if (!r) throw new Error("risposta fake mancante");
      return Promise.resolve(r);
    },
    from: (tabella: string) => {
      chiamate.push({ tipo: `from:${tabella}`, args: [] });
      throw new Error("il servizio Accessori non legge tabelle");
    },
    storage: {
      from: (bucket: string) => ({
        upload: (...a: unknown[]) => {
          chiamate.push({ tipo: `storage:${bucket}.upload`, args: a });
          return Promise.resolve(storage?.upload ?? { data: {}, error: null });
        },
        remove: (...a: unknown[]) => {
          chiamate.push({ tipo: `storage:${bucket}.remove`, args: a });
          return Promise.resolve(storage?.remove ?? { data: [], error: null });
        },
      }),
    },
  } as unknown as SupabaseClient;
  return { c, chiamate };
}

const schedaPubblica = {
  slug: "calice-di-prova",
  nome: "Calice di prova",
  descrizione: "Descrizione sintetica.",
  marchio: null,
  condizione: "nuovo",
  attributi: {},
  immagini: [PERCORSO],
  categoria: { slug: "calici", nome: "Calici", genitore_slug: null, genitore_nome: null },
};

const schedaAdmin = {
  ...schedaPubblica,
  id: ID,
  categoria_id: IMG,
  stato: "bozza",
  quantita: null,
  pubblicato_il: null,
  created_at: "2026-10-20T09:00:00Z",
  updated_at: "2026-10-20T09:00:00Z",
};

describe("lettura pubblica", () => {
  it("chiama le sole porte accessori_* con il flag di anteprima", async () => {
    const { c, chiamate } = client([
      { data: [{ slug: "calici", nome: "Calici", descrizione: "", genitore_slug: null, conteggio: 1 }], error: null },
      { data: [schedaPubblica], error: null },
      { data: schedaPubblica, error: null },
    ]);
    const s = creaAccessoriLetturaService(c);
    expect((await s.categorie(false)).ok).toBe(true);
    const elenco = await s.elenco("calici", true);
    expect(elenco.ok && elenco.data.length).toBe(1);
    const det = await s.dettaglio("calice-di-prova", false);
    expect(det.ok && det.data?.slug).toBe("calice-di-prova");
    expect(chiamate.map((x) => x.tipo)).toEqual([
      "rpc:accessori_categorie_elenca",
      "rpc:accessori_elenca",
      "rpc:accessori_dettaglio",
    ]);
    expect(chiamate[0].args[0]).toEqual({ p_anteprima: false });
    expect(chiamate[1].args[0]).toEqual({ p_categoria_slug: "calici", p_anteprima: true });
    expect(chiamate[2].args[0]).toEqual({ p_slug: "calice-di-prova", p_anteprima: false });
  });

  it("un dettaglio null e «non trovato», non un errore", async () => {
    const { c } = client([{ data: null, error: null }]);
    const r = await creaAccessoriLetturaService(c).dettaglio("assente", false);
    expect(r).toEqual({ ok: true, data: null });
  });

  it("una scheda illeggibile e un guasto, non un 404", async () => {
    const { c } = client([{ data: { rotta: true }, error: null }]);
    const r = await creaAccessoriLetturaService(c).dettaglio("x-x-x", false);
    expect(r.ok).toBe(false);
  });

  it("senza client risponde con un messaggio, senza lanciare", async () => {
    const r = await creaAccessoriLetturaService(null).elenco(null, false);
    expect(r.ok).toBe(false);
  });

  it("un errore del database non filtra il messaggio interno", async () => {
    const { c } = client([{ data: null, error: { code: "XX000", message: "relation private.accessori" } }]);
    const r = await creaAccessoriLetturaService(c).elenco(null, false);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error).not.toContain("private");
  });
});

describe("porte admin", () => {
  it("salva una scheda con i soli campi ammessi, senza stato ne immagini", async () => {
    const { c, chiamate } = client([{ data: schedaAdmin, error: null }]);
    const r = await creaAccessoriAdminService(c).salva(null, {
      categoriaId: IMG,
      slug: "calice-di-prova",
      nome: "Calice di prova",
      descrizione: "Descrizione sintetica.",
      marchio: null,
      condizione: "nuovo",
      quantita: 3,
      attributi: { materiale: "vetro" },
    });
    expect(r.ok && r.data.stato).toBe("bozza");
    const args = chiamate[0].args[0] as { p_id: unknown; p_dati: Record<string, unknown> };
    expect(args.p_id).toBeNull();
    expect(Object.keys(args.p_dati).sort()).toEqual([
      "attributi",
      "categoria_id",
      "condizione",
      "descrizione",
      "marchio",
      "nome",
      "quantita",
      "slug",
    ]);
  });

  it("un errore con hint diventa un messaggio comprensibile", async () => {
    const { c } = client([{ data: null, error: { code: "23505", hint: "slug_in_uso", message: "duplicate key" } }]);
    const r = await creaAccessoriAdminService(c).salva(null, {
      categoriaId: IMG, slug: "x-x-x", nome: "Nome", descrizione: "", marchio: null,
      condizione: "nuovo", quantita: null, attributi: {},
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error).toContain("già usato");
  });

  it("legge lo stato della visibilita pubblica, senza mai scriverlo", async () => {
    const { c, chiamate } = client([{ data: { visibilita_pubblica: false }, error: null }]);
    const r = await creaAccessoriAdminService(c).visibilitaPubblica();
    expect(r).toEqual({ ok: true, data: false });
    expect(chiamate.map((x) => x.tipo)).toEqual(["rpc:accessori_admin_stato"]);
  });

  it("carica l'immagine come WebP nella cartella della scheda, senza sovrascrivere", async () => {
    const { c, chiamate } = client([]);
    const r = await creaAccessoriAdminService(c, () => IMG).caricaImmagine(ID, new Blob(["x"]));
    expect(r).toEqual({ ok: true, data: PERCORSO });
    expect(chiamate[0].tipo).toBe("storage:accessori-media.upload");
    expect(chiamate[0].args[0]).toBe(PERCORSO);
    expect(chiamate[0].args[2]).toEqual({ contentType: "image/webp", upsert: false });
  });

  it("rifiuta di caricare in una cartella che non e una scheda", async () => {
    const { c, chiamate } = client([]);
    const r = await creaAccessoriAdminService(c, () => IMG).caricaImmagine("../x", new Blob(["x"]));
    expect(r.ok).toBe(false);
    expect(chiamate).toHaveLength(0);
  });

  it("collega le immagini con una porta dedicata", async () => {
    const { c, chiamate } = client([{ data: schedaAdmin, error: null }]);
    await creaAccessoriAdminService(c).impostaImmagini(ID, [PERCORSO]);
    expect(chiamate[0].tipo).toBe("rpc:accessori_admin_immagini_imposta");
    expect(chiamate[0].args[0]).toEqual({ p_id: ID, p_percorsi: [PERCORSO] });
  });

  it("la pulizia dei file non fa nulla senza percorsi", async () => {
    const { c, chiamate } = client([]);
    await creaAccessoriAdminService(c).cancellaImmagini([]);
    expect(chiamate).toHaveLength(0);
  });
});
