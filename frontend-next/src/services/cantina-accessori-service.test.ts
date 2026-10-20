import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { leggiAccessoriPubblici } from "@/lib/cantina-accessori/pubblici-server";
import {
  creaCantinaAccessoriAdminService,
  creaCantinaAccessoriPubblicaService,
  creaCantinaAccessoriService,
} from "./cantina-accessori-service";

const U1 = "11111111-1111-4111-8111-111111111111";
const U2 = "22222222-2222-4222-8222-222222222222";
const U3 = "33333333-3333-4333-8333-333333333333";
const FOTO = `${U1}/${U2}/${U3}.webp`;

type Chiamata = { nome: string; args: unknown };

function finto(opzioni: {
  rpc?: (nome: string, args: unknown) => { data?: unknown; error?: unknown };
  firme?: { path: string; signedUrl: string; error: null }[] | null;
}) {
  const chiamate: Chiamata[] = [];
  const rimossi: string[][] = [];
  const caricati: { percorso: string; opzioni: unknown }[] = [];
  const client = {
    rpc: async (nome: string, args: unknown) => {
      chiamate.push({ nome, args });
      const r = opzioni.rpc?.(nome, args) ?? { data: null };
      return { data: r.data ?? null, error: r.error ?? null };
    },
    storage: {
      from: () => ({
        createSignedUrls: async () =>
          opzioni.firme === null
            ? { data: null, error: { message: "no" } }
            : { data: opzioni.firme ?? [], error: null },
        remove: async (percorsi: string[]) => {
          rimossi.push(percorsi);
          return { error: null };
        },
        upload: async (percorso: string, _file: unknown, opz: unknown) => {
          caricati.push({ percorso, opzioni: opz });
          return { error: null };
        },
      }),
    },
  } as unknown as SupabaseClient;
  return { client, chiamate, rimossi, caricati };
}

const personaleJson = {
  id: U2, nome: "Calice", descrizione: "", marchio: null, condizione: "nuovo", quantita: 1,
  note: "", immagini: [], visibilita: "privata", archiviato: false, catalogo_slug: null,
  categoria: { id: U3, slug: "pulizia", nome: "Pulizia", genitore_id: null, genitore_slug: null, genitore_nome: null },
  created_at: "2026-10-21T10:00:00Z", updated_at: "2026-10-21T10:00:00Z",
};

describe("servizio del proprietario", () => {
  it("senza client risponde con un errore leggibile, mai con un'eccezione", async () => {
    const s = creaCantinaAccessoriService(null);
    expect((await s.stato()).ok).toBe(false);
    expect((await s.elenco(false)).ok).toBe(false);
  });

  it("salva non invia mai un proprietario: solo id e dati dell'accessorio", async () => {
    const f = finto({ rpc: () => ({ data: personaleJson }) });
    const s = creaCantinaAccessoriService(f.client);
    const r = await s.salva(U2, {
      categoriaId: U3, nome: "Calice", descrizione: "", marchio: null, condizione: "nuovo",
      quantita: 1, note: "",
    });
    expect(r.ok).toBe(true);
    const chiamata = f.chiamate.find((c) => c.nome === "cantina_accessori_salva");
    expect(Object.keys(chiamata?.args as object).sort()).toEqual(["p_dati", "p_id"]);
    const dati = (chiamata?.args as { p_dati: Record<string, unknown> }).p_dati;
    expect(Object.keys(dati)).not.toContain("owner_id");
    expect(Object.keys(dati)).not.toContain("visibilita");
  });

  it("una risposta illeggibile è un guasto, non un successo a metà", async () => {
    const f = finto({ rpc: () => ({ data: { id: "x" } }) });
    const r = await creaCantinaAccessoriService(f.client).archivia(U2, true);
    expect(r.ok).toBe(false);
  });

  it("traduce l'errore del database in un messaggio e non lo propaga grezzo", async () => {
    const f = finto({ rpc: () => ({ error: { code: "22023", hint: "limite_raggiunto", message: "dettaglio interno" } }) });
    const r = await creaCantinaAccessoriService(f.client).impostaVisibilita(U2, "cantina_pubblica");
    expect(r).toEqual({ ok: false, error: "Hai raggiunto il numero massimo di accessori." });
  });

  it("rimuovi cancella dal bucket le foto restituite dal database", async () => {
    const f = finto({ rpc: () => ({ data: { rimosso: true, percorsi: [FOTO] } }) });
    const r = await creaCantinaAccessoriService(f.client).rimuovi(U2);
    expect(r.ok).toBe(true);
    expect(f.rimossi).toEqual([[FOTO]]);
  });

  it("carica le foto come WebP, senza sovrascrivere, nella cartella proprietario/accessorio", async () => {
    const f = finto({});
    const s = creaCantinaAccessoriService(f.client, () => U3);
    const r = await s.caricaFoto(U1, U2, new Blob(["x"]));
    expect(r).toEqual({ ok: true, data: FOTO });
    expect(f.caricati[0].opzioni).toEqual({ contentType: "image/webp", upsert: false });
    expect((await s.caricaFoto("no", U2, new Blob(["x"]))).ok).toBe(false);
  });

  it("firma solo percorsi validi e senza duplicati; un percorso non firmabile manca dal risultato", async () => {
    const f = finto({ firme: [{ path: FOTO, signedUrl: "https://firma", error: null }] });
    const r = await creaCantinaAccessoriService(f.client).urlFoto([FOTO, FOTO, "../x", "x/y.webp"]);
    expect(r).toEqual({ ok: true, data: { [FOTO]: "https://firma" } });
    const vuoto = await creaCantinaAccessoriService(f.client).urlFoto(["../x"]);
    expect(vuoto).toEqual({ ok: true, data: {} });
  });
});

describe("servizio pubblico e lettura per le pagine", () => {
  const pubblicoJson = {
    id: U2, nome: "Cavatappi", descrizione: "", marchio: null, condizione: "nuovo", quantita: 2,
    immagini: [FOTO], categoria_slug: "cavatappi", categoria_nome: "Cavatappi", genitore_nome: "Apertura",
  };

  it("chiama la porta con il profilo, il limite e l'anteprima spenta di default", async () => {
    const f = finto({ rpc: () => ({ data: [pubblicoJson] }) });
    const r = await creaCantinaAccessoriPubblicaService(f.client).perProfilo(U1, { limite: 7 });
    expect(r.ok && r.data.length).toBe(1);
    expect(f.chiamate[0]).toEqual({
      nome: "cantina_accessori_pubblica_profilo",
      args: { p_user_id: U1, p_limit: 7, p_offset: 0, p_anteprima: false },
    });
  });

  it("la lettura per le pagine firma le prime foto", async () => {
    const f = finto({
      rpc: () => ({ data: [pubblicoJson] }),
      firme: [{ path: FOTO, signedUrl: "https://firma", error: null }],
    });
    const r = await leggiAccessoriPubblici(f.client, U1, { limite: 6 });
    expect(r.accessori).toHaveLength(1);
    expect(r.url[FOTO]).toBe("https://firma");
  });

  it("fail closed: client assente, errore del database, forma illeggibile, firma fallita", async () => {
    expect(await leggiAccessoriPubblici(null, U1, { limite: 6 })).toEqual({ accessori: [], url: {} });
    const errore = finto({ rpc: () => ({ error: { code: "42883" } }) });
    expect((await leggiAccessoriPubblici(errore.client, U1, { limite: 6 })).accessori).toEqual([]);
    const brutto = finto({ rpc: () => ({ data: "no" }) });
    expect((await leggiAccessoriPubblici(brutto.client, U1, { limite: 6 })).accessori).toEqual([]);
    const senzaFirma = finto({ rpc: () => ({ data: [pubblicoJson] }), firme: null });
    const r = await leggiAccessoriPubblici(senzaFirma.client, U1, { limite: 6 });
    expect(r.accessori).toHaveLength(1);
    expect(r.url).toEqual({});
  });

  it("l'admin accende con motivo e riceve l'errore del database se manca il rilascio", async () => {
    const f = finto({ rpc: () => ({ error: { code: "42501", hint: "rilascio_non_autorizzato" } }) });
    const r = await creaCantinaAccessoriAdminService(f.client).imposta("funzione", true, "ok");
    expect(r.ok).toBe(false);
    expect(f.chiamate[0]).toEqual({
      nome: "cantina_accessori_admin_imposta",
      args: { p_interruttore: "funzione", p_attiva: true, p_motivo: "ok" },
    });
  });
});
