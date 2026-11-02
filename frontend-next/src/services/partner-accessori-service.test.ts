import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseMovimentoScorta,
  parseStatoPartnerAccessori,
  parseVenditoreAnnuncio,
} from "@/lib/partner-accessori/partner-accessori";
import { creaPartnerAccessoriService, leggiVenditoreAnnuncio } from "./partner-accessori-service";

const U1 = "11111111-1111-4111-8111-111111111111";
const U2 = "22222222-2222-4222-8222-222222222222";

type Chiamata = { nome: string; args: unknown };

function finto(rpc: (nome: string, args: unknown) => { data?: unknown; error?: unknown }) {
  const chiamate: Chiamata[] = [];
  const client = {
    rpc: async (nome: string, args: unknown) => {
      chiamate.push({ nome, args });
      const r = rpc(nome, args);
      return { data: r.data ?? null, error: r.error ?? null };
    },
    storage: { from: () => ({}) },
  } as unknown as SupabaseClient;
  return { client, chiamate };
}

const scorta = {
  id: U1,
  nome: "Calice",
  descrizione: "",
  marchio: null,
  condizione: "nuovo",
  quantita: 6,
  note: "",
  immagini: [],
  visibilita: "privata",
  archiviato: false,
  catalogo_slug: null,
  categoria: { id: U2, slug: "calici", nome: "Calici", genitore_id: null, genitore_slug: null, genitore_nome: null },
  created_at: "2026-11-02T10:00:00Z",
  updated_at: "2026-11-02T10:00:00Z",
};

const stato = {
  partner_stato: "attivo",
  scorte_abilitate: true,
  preparazione_annunci: true,
  pubblicazione_aperta: false,
  vendita_partner: false,
  checkout_attivo: false,
};

describe("servizio Accessori Partner (VPM-015C)", () => {
  it("salva passa dalla porta Partner e non invia Partner, classe, condizione, margine né prezzo", async () => {
    const { client, chiamate } = finto(() => ({ data: scorta }));
    const r = await creaPartnerAccessoriService(client).salva(U1, {
      categoriaId: U2,
      nome: "Calice",
      descrizione: "",
      marchio: "",
      condizione: "usato",
      quantita: 6,
      note: "",
      catalogoSlug: undefined,
    } as never);
    expect(r.ok).toBe(true);
    expect(chiamate).toHaveLength(1);
    expect(chiamate[0].nome).toBe("accessori_partner_scorta_salva");
    const args = chiamate[0].args as { p_id: string; p_dati: Record<string, unknown> };
    expect(args.p_id).toBe(U1);
    for (const vietata of ["condizione", "partner_id", "inventario", "classe", "margine", "prezzo", "owner_id"]) {
      expect(vietata in args.p_dati).toBe(false);
    }
  });

  it("elenco e archivia usano le porte Partner; foto e categorie restano quelle della Cantina", async () => {
    const { client, chiamate } = finto((nome) =>
      nome === "accessori_partner_scorte_elenca" ? { data: [scorta, { rotto: true }] } : { data: scorta },
    );
    const s = creaPartnerAccessoriService(client);
    const e = await s.elenco(false);
    expect(e.ok && e.data.length).toBe(1);
    expect((await s.archivia(U1, true)).ok).toBe(true);
    await s.categorie();
    await s.impostaFoto(U1, []);
    expect(chiamate.map((c) => c.nome)).toEqual([
      "accessori_partner_scorte_elenca",
      "accessori_partner_scorta_archivia",
      "cantina_accessori_categorie_elenca",
      "cantina_accessori_immagini_imposta",
    ]);
  });

  it("la sezione è abilitata solo per un Partner attivo o sospeso con la funzione accesa", async () => {
    const con = (partner: string | null, abilitata: boolean) =>
      finto((nome) =>
        nome === "accessori_partner_stato"
          ? { data: { ...stato, partner_stato: partner } }
          : { data: { abilitata, esposti_visibili: false } },
      );
    const chiedi = async (partner: string | null, abilitata: boolean) => {
      const r = await creaPartnerAccessoriService(con(partner, abilitata).client).stato();
      return r.ok && r.data.abilitata;
    };
    expect(await chiedi("attivo", true)).toBe(true);
    expect(await chiedi("sospeso", true)).toBe(true);
    expect(await chiedi("in_verifica", true)).toBe(false);
    expect(await chiedi("revocato", true)).toBe(false);
    expect(await chiedi(null, true)).toBe(false);
    expect(await chiedi("attivo", false)).toBe(false);
  });

  it("senza client o con errore del database risponde con un messaggio, mai con un dato", async () => {
    const senza = creaPartnerAccessoriService(null);
    expect((await senza.elenco(false)).ok).toBe(false);
    expect((await senza.movimenti(U1)).ok).toBe(false);
    const { client } = finto(() => ({ error: { code: "42501", hint: "partner_non_attivo" } }));
    const r = await creaPartnerAccessoriService(client).salva(U1, {} as never);
    expect(r).toEqual({ ok: false, error: "Le scorte commerciali si gestiscono solo con un Partner attivo." });
  });

  it("il venditore pubblico distingue Partner e privato e rifiuta risposte incoerenti", async () => {
    expect(parseVenditoreAnnuncio({ classe: "partner", nuovo: true, titolare_id: U1 })).toEqual({
      classe: "partner",
      titolareId: U1,
    });
    expect(parseVenditoreAnnuncio({ classe: "privato", nuovo: false })).toEqual({ classe: "privato" });
    expect(parseVenditoreAnnuncio({ classe: "privato", nuovo: true })).toBeNull();
    expect(parseVenditoreAnnuncio({ classe: "partner", nuovo: false, titolare_id: U1 })).toBeNull();
    expect(parseVenditoreAnnuncio({ classe: "partner", nuovo: true, titolare_id: "x" })).toBeNull();
    expect(parseVenditoreAnnuncio({ classe: "altro" })).toBeNull();

    const nullo = finto(() => ({ data: null }));
    expect(await leggiVenditoreAnnuncio(nullo.client, U1)).toEqual({ ok: true, data: null });
    expect(nullo.chiamate[0]).toEqual({ nome: "accessori_venditore_pubblico", args: { p_annuncio: U1 } });
    const rotto = finto(() => ({ data: { classe: "boh" } }));
    expect((await leggiVenditoreAnnuncio(rotto.client, U1)).ok).toBe(false);
  });

  it("parser di stato e movimenti rigidi", () => {
    expect(parseStatoPartnerAccessori(stato)?.partnerStato).toBe("attivo");
    expect(parseStatoPartnerAccessori({ ...stato, partner_stato: null })?.partnerStato).toBeNull();
    expect(parseStatoPartnerAccessori({ ...stato, partner_stato: "boh" })).toBeNull();
    expect(parseStatoPartnerAccessori({ ...stato, checkout_attivo: "no" })).toBeNull();
    const m = { causale: "vendita", delta: -2, quantita_dopo: 4, created_at: "2026-11-02T10:00:00Z" };
    expect(parseMovimentoScorta(m)).toEqual({
      causale: "vendita",
      delta: -2,
      quantitaDopo: 4,
      createdAt: "2026-11-02T10:00:00Z",
    });
    expect(parseMovimentoScorta({ ...m, delta: 0 })).toBeNull();
    expect(parseMovimentoScorta({ ...m, causale: "regalo" })).toBeNull();
    expect(parseMovimentoScorta({ ...m, quantita_dopo: -1 })).toBeNull();
  });
});
