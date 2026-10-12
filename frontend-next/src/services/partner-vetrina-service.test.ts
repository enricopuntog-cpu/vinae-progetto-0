import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import type { SupabaseClient } from "@supabase/supabase-js";
import { BUCKET_PARTNER_VETRINE, MAX_DESCRIZIONE, MAX_FOTO_VETRINA, MAX_PRESENTAZIONE } from "@/lib/partner/vetrina";
import {
  creaVetrinaPartnerPubblicaService,
  creaVetrinaPartnerService,
} from "@/services/partner-vetrina-service";

type Risposta = { data: unknown; error: { code?: string; message?: string; hint?: string } | null };

const T = "11111111-1111-4111-8111-111111111111";
const P = "22222222-2222-4222-8222-222222222222";
const U = "55555555-5555-4555-8555-555555555555";

function client(risposte: Risposta[], storage?: { upload?: Risposta; remove?: Risposta }) {
  const chiamate: Array<{ tipo: string; args: unknown[] }> = [];
  const c = {
    rpc: (nome: string, args?: unknown) => {
      chiamate.push({ tipo: `rpc:${nome}`, args: [args] });
      const r = risposte.shift();
      if (!r) throw new Error("risposta fake mancante");
      return Promise.resolve(r);
    },
    from: (vista: string) => {
      const q = {
        select: (...a: unknown[]) => (chiamate.push({ tipo: `${vista}.select`, args: a }), q),
        eq: (...a: unknown[]) => (chiamate.push({ tipo: `${vista}.eq`, args: a }), q),
        order: (...a: unknown[]) => (chiamate.push({ tipo: `${vista}.order`, args: a }), q),
        limit: (...a: unknown[]) => {
          chiamate.push({ tipo: `${vista}.limit`, args: a });
          return Promise.resolve(risposte.shift());
        },
      };
      return q;
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

const mia = {
  partner_id: P,
  titolare_id: T,
  nome_commerciale: "Enoteca",
  stato: "attivo",
  modificabile: true,
  cartella: `${T}/${P}`,
  foto_paths: [],
};

describe("VetrinaPartnerService (titolare)", () => {
  it("mia: null senza Partner, nessun argomento passato", async () => {
    const { c, chiamate } = client([{ data: null, error: null }]);
    expect(await creaVetrinaPartnerService(c).mia()).toEqual({ ok: true, data: null });
    expect(chiamate).toEqual([{ tipo: "rpc:vetrina_partner_mia", args: [undefined] }]);
  });

  it("salva: testi ripuliti, percorsi così come sono, nessun proprietario", async () => {
    const { c, chiamate } = client([{ data: mia, error: null }]);
    const esito = await creaVetrinaPartnerService(c).salva({
      presentazione: "  Vini  ",
      descrizione: "   ",
      logoPath: null,
      copertinaPath: null,
      fotoPaths: ["a", "b", "c", "d", "e"],
    });
    expect(esito.ok).toBe(true);
    expect(chiamate[0]).toEqual({
      tipo: "rpc:vetrina_partner_salva",
      args: [
        {
          p_presentazione: "Vini",
          p_descrizione: null,
          p_logo: null,
          p_copertina: null,
          // Anche la quinta: il limite lo fa rispettare il server, a voce alta.
          p_foto: ["a", "b", "c", "d", "e"],
        },
      ],
    });
  });

  it("traduce gli hint del server in frasi, mai il testo di PostgreSQL", async () => {
    const { c } = client([
      { data: null, error: { code: "P0001", hint: "vetrina_non_modificabile", message: "relation private.x" } },
    ]);
    const esito = await creaVetrinaPartnerService(c).salva({
      presentazione: null, descrizione: null, logoPath: null, copertinaPath: null, fotoPaths: [],
    });
    expect(esito).toEqual({ ok: false, error: "La vetrina non è modificabile nello stato attuale del Partner." });
  });

  it("carica nella cartella del server, come file nuovo WebP senza sovrascrivere", async () => {
    const { c, chiamate } = client([]);
    const blob = new Blob(["x"], { type: "image/webp" });
    const esito = await creaVetrinaPartnerService(c, () => U.toUpperCase()).caricaMedia(`${T}/${P}`, blob);
    expect(esito).toEqual({ ok: true, data: `${T}/${P}/${U}.webp` });
    expect(chiamate[0]).toEqual({
      tipo: `storage:${BUCKET_PARTNER_VETRINE}.upload`,
      args: [`${T}/${P}/${U}.webp`, blob, { contentType: "image/webp", upsert: false }],
    });
  });

  it("non carica fuori da una cartella valida", async () => {
    const { c, chiamate } = client([]);
    const esito = await creaVetrinaPartnerService(c, () => U).caricaMedia(`${T}/../${P}`, new Blob());
    expect(esito.ok).toBe(false);
    expect(chiamate).toEqual([]);
  });

  it("la pulizia dei file è best effort e non chiama nulla se non c'è nulla", async () => {
    const { c, chiamate } = client([], { remove: { data: null, error: { message: "in uso" } } });
    await creaVetrinaPartnerService(c).cancellaMedia([]);
    expect(chiamate).toEqual([]);
    await creaVetrinaPartnerService(c).cancellaMedia(["x"]);
    expect(chiamate[0]?.tipo).toBe(`storage:${BUCKET_PARTNER_VETRINE}.remove`);
  });

  it("senza client: errore leggibile, nessuna eccezione", async () => {
    expect((await creaVetrinaPartnerService(null).mia()).ok).toBe(false);
  });
});

describe("VetrinaPartnerPubblicaService", () => {
  it("un id che non è un uuid non arriva al database", async () => {
    const { c, chiamate } = client([]);
    const s = creaVetrinaPartnerPubblicaService(c);
    expect(await s.perProfilo("pippo")).toEqual({ ok: true, data: null });
    expect(await s.acquistoDisponibile("demo-venditore")).toEqual({ ok: true, data: true });
    expect(await s.clubDelTitolare("pippo")).toEqual({ ok: true, data: [] });
    expect(chiamate).toEqual([]);
  });

  it("perProfilo: null è «non è una vetrina», una riga illeggibile è un guasto", async () => {
    const { c, chiamate } = client([
      { data: null, error: null },
      { data: { partner_id: P }, error: null },
    ]);
    const s = creaVetrinaPartnerPubblicaService(c);
    expect(await s.perProfilo(T)).toEqual({ ok: true, data: null });
    expect((await s.perProfilo(T)).ok).toBe(false);
    expect(chiamate[0]).toEqual({ tipo: "rpc:vetrina_partner_pubblica", args: [{ p_user_id: T }] });
  });

  it("acquistoDisponibile: solo un booleano vero è una risposta", async () => {
    const { c, chiamate } = client([
      { data: false, error: null },
      { data: "false", error: null },
    ]);
    const s = creaVetrinaPartnerPubblicaService(c);
    expect(await s.acquistoDisponibile(T)).toEqual({ ok: true, data: false });
    expect((await s.acquistoDisponibile(T)).ok).toBe(false);
    expect(chiamate[0]).toEqual({ tipo: "rpc:acquisto_da_venditore_disponibile", args: [{ p_seller_id: T }] });
  });

  it("i Club del titolare vengono dalla vista pubblica dei Club, filtrati per owner_id", async () => {
    const { c, chiamate } = client([
      { data: [{ slug: "langa", nome: "Langa", territorio: "" }, { slug: 3 }], error: null },
    ]);
    expect(await creaVetrinaPartnerPubblicaService(c).clubDelTitolare(T)).toEqual({
      ok: true,
      data: [{ slug: "langa", nome: "Langa", territorio: null }],
    });
    expect(chiamate.map((x) => x.tipo)).toEqual([
      "public_clubs.select",
      "public_clubs.eq",
      "public_clubs.order",
      "public_clubs.limit",
    ]);
    expect(chiamate[1]?.args).toEqual(["owner_id", T]);
  });
});

describe("contratto con la migrazione 20261011200000", () => {
  const radice = resolve(import.meta.dir, "../../..");
  const sql = readFileSync(
    resolve(radice, "supabase/migrations/20261011200000_partner_program_blocco_b_vetrina.sql"),
    "utf8",
  ).replace(/--.*$/gm, "");
  const servizio = readFileSync(resolve(import.meta.dir, "partner-vetrina-service.ts"), "utf8");

  it("ogni RPC del servizio esiste; solo la lettura pubblica e lo specchio sono ad anon", () => {
    const rpc = [...servizio.matchAll(/rpc\("([a-z_]+)"/g)].map((m) => m[1]);
    expect(new Set(rpc)).toEqual(
      new Set([
        "vetrina_partner_mia",
        "vetrina_partner_salva",
        "vetrina_partner_pubblica",
        "acquisto_da_venditore_disponibile",
        // VP-C: il catalogo commerciale vive nella migrazione delle quantità.
        "vetrina_partner_catalogo",
      ]),
    );
    const sqlVpC = readFileSync(
      resolve(import.meta.dir, "../../../supabase/migrations/20261012150000_vp_c_annunci_allocazioni_ordini.sql"),
      "utf8",
    );
    for (const nome of rpc) {
      expect(nome === "vetrina_partner_catalogo" ? sqlVpC : sql).toContain(`create function public.${nome}(`);
    }
    expect(sqlVpC).toMatch(
      /grant execute on function public\.vetrina_partner_catalogo\(uuid\) to anon, authenticated;/,
    );
    expect(sql).toMatch(/grant execute on function public\.vetrina_partner_mia\(\) to authenticated;/);
    expect(sql).toMatch(/grant execute on function public\.vetrina_partner_salva\([^)]*\) to authenticated;/);
    expect(sql).toMatch(/grant execute on function public\.vetrina_partner_pubblica\(uuid\) to anon, authenticated;/);
    expect(sql).toMatch(
      /grant execute on function public\.acquisto_da_venditore_disponibile\(uuid\) to anon, authenticated;/,
    );
  });

  it("bucket, limiti e chiavi della proiezione coincidono con il database", () => {
    expect(sql).toContain(`values ('${BUCKET_PARTNER_VETRINE}', '${BUCKET_PARTNER_VETRINE}', true, 2097152, array['image/webp'])`);
    expect(sql).toContain(`between 1 and ${MAX_PRESENTAZIONE}`);
    expect(sql).toContain(`between 1 and ${MAX_DESCRIZIONE}`);
    expect(sql).toContain(`cardinality(foto_paths) <= ${MAX_FOTO_VETRINA}`);
    const proiezione = sql.slice(
      sql.indexOf("create function private.partner_vetrina_json"),
      sql.indexOf("revoke execute on function private.partner_vetrina_json"),
    );
    const chiavi = [...proiezione.matchAll(/'([a-z_]+)', (?:[pv]\.|coalesce\(to_jsonb\(v\.)/g)]
      .map((m) => m[1])
      .sort();
    expect(chiavi).toEqual(
      [
        "aggiornata_at", "attivo_dal", "copertina_path", "descrizione", "foto_paths", "logo_path",
        "nome_commerciale", "paese", "partner_id", "presentazione", "sede_citta", "sede_provincia",
        "tipologia", "titolare_id",
      ].sort(),
    );
    expect(proiezione).not.toMatch(/partita_iva|ragione_sociale|sede_indirizzo|email|ultimo_motivo|stato/);
  });

  it("non tocca margine, ruoli, checkout né il gate del Blocco A", () => {
    expect(sql).not.toMatch(/marketplace_config|user_roles|order_checkout_reserve|vinea\.pq_review/);
    expect(sql).not.toMatch(/drop trigger|orders_partner_checkout_gate|create or replace function private\.partner_checkout_gate/);
    expect(sql).toContain("create trigger proposals_partner_gate");
  });
});
