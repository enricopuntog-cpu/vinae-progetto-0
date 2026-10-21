import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  creaAnnunciAccessoriAdminService,
  creaAnnunciAccessoriPubbliciService,
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
  posseduti: 6, impegnati: 2, disponibili: 4, foto: 0, ritirato_at: null,
  created_at: "2026-10-21T10:00:00Z", updated_at: "2026-10-21T10:00:00Z",
  pubblicato_at: null, versione: 0, pubblico: false, moderazione: null,
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
    expect((await s.pubblica(U1)).ok).toBe(false);
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

  it("la transizione chiede uno stato per un id e nient'altro; il ritiro è sempre una transizione", async () => {
    const { client, chiamate } = finto(() => ({ data: { ...annuncio, stato: "ritirato", ritirato_at: "2026-10-21T10:05:00Z" } }));
    const r = await creaAnnunciAccessoriService(client).transizione(U1, "ritirato");
    expect(r.ok).toBe(true);
    expect(chiamate[0]).toEqual({ nome: "annunci_accessori_transizione", args: { p_id: U1, p_a: "ritirato" } });
  });

  it("pubblica manda solo l'id: nessun consenso, categoria, stato o interruttore dal browser", async () => {
    const pubblicato = { ...annuncio, stato: "pubblicato", pubblicato_at: "2026-10-22T08:00:00Z", pubblico: true };
    const { client, chiamate } = finto(() => ({ data: pubblicato }));
    const r = await creaAnnunciAccessoriService(client).pubblica(U1);
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.data.stato).toBe("pubblicato");
      expect(r.data.pubblico).toBe(true);
    }
    expect(chiamate).toEqual([{ nome: "annunci_accessori_pubblica", args: { p_id: U1 } }]);
  });

  it("i rifiuti della pubblicazione diventano frasi: interruttore spento, categoria non approvata, articolo rimosso", async () => {
    for (const [hint, attesa] of [
      ["pubblicazione_chiusa", "non è ancora aperta"],
      ["categoria_non_pubblicabile", "non è ancora ammessa alla pubblicazione"],
      ["ripubblicazione_bloccata", "rimosso da Vinea"],
      ["contenuto_non_ammesso", "non si può pubblicare"],
      ["modifiche_non_effettuate", "Modifica l'annuncio"],
    ] as const) {
      const { client } = finto(() => ({ error: { code: "42501", hint, message: "interno" } }));
      const r = await creaAnnunciAccessoriService(client).pubblica(U1);
      expect(r.ok).toBe(false);
      if (!r.ok) {
        expect(r.error).toContain(attesa);
        expect(r.error).not.toContain("interno");
      }
    }
  });

  it("una pubblicazione che il database dice riuscita ma illeggibile è un guasto, non un successo", async () => {
    const { client } = finto(() => ({ data: { ...annuncio, stato: "pubblicato", pubblico: true, pubblicato_at: null, stato_x: 1, versione: "0" } }));
    expect((await creaAnnunciAccessoriService(client).pubblica(U1)).ok).toBe(false);
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
      data: {
        abilitata: true, pubblicazione_aperta: true, vendite_attive: true, classe: "privato",
        venditore_ammesso: true, motivo: null,
      },
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

  it("legge lo stato con i due interruttori e rifiuta una risposta senza il conteggio delle categorie", async () => {
    const buono = {
      preparazione_attiva: false, pubblicazione_attiva: false, cantina_funzione_attiva: true,
      puo_rilasciare: true, categorie_pubblicabili: 0,
    };
    const letto = await creaAnnunciAccessoriAdminService(finto(() => ({ data: buono })).client).stato();
    expect(letto.ok).toBe(true);
    if (letto.ok) expect(letto.data.pubblicazioneAttiva).toBe(false);
    const { categorie_pubblicabili: _, ...guasto } = buono;
    void _;
    expect((await creaAnnunciAccessoriAdminService(finto(() => ({ data: guasto })).client).stato()).ok).toBe(false);
  });

  it("l'interruttore di pubblicazione manda solo valore e motivo; il rilascio lo decide il database", async () => {
    const { client, chiamate } = finto();
    const r = await creaAnnunciAccessoriAdminService(client).impostaPubblicazione(true, "approvazione del titolare");
    expect(r.ok).toBe(true);
    expect(chiamate[0]).toEqual({
      nome: "annunci_accessori_admin_pubblicazione_imposta",
      args: { p_attiva: true, p_motivo: "approvazione del titolare" },
    });
    const { client: negato } = finto(() => ({ error: { code: "42501", hint: "rilascio_non_autorizzato" } }));
    const rifiuto = await creaAnnunciAccessoriAdminService(negato).impostaPubblicazione(true, "x");
    expect(rifiuto.ok).toBe(false);
    if (!rifiuto.ok) expect(rifiuto.error).toContain("approvazione esplicita del titolare");
  });

  it("approvare una categoria manda solo categoria, valore e motivo; un id non valido non parte", async () => {
    const { client, chiamate } = finto();
    const s = creaAnnunciAccessoriAdminService(client);
    expect((await s.impostaCategoriaPubblicabile(U1, true, "approvata dal titolare")).ok).toBe(true);
    expect(chiamate[0]).toEqual({
      nome: "annunci_accessori_admin_categoria_pubblicabile_imposta",
      args: { p_categoria: U1, p_pubblicabile: true, p_motivo: "approvata dal titolare" },
    });
    expect((await s.impostaCategoriaPubblicabile("x", true, "m")).ok).toBe(false);
    expect(chiamate).toHaveLength(1);
  });

  it("la moderazione manda azione e motivazione per un id; mai uno stato o un attore", async () => {
    const { client, chiamate } = finto();
    const s = creaAnnunciAccessoriAdminService(client);
    expect((await s.modera(U1, "oscura", "Foto da verificare")).ok).toBe(true);
    expect(chiamate[0]).toEqual({
      nome: "annunci_accessori_admin_modera",
      args: { p_id: U1, p_azione: "oscura", p_motivazione: "Foto da verificare" },
    });
    expect((await s.modera("x", "oscura", "m")).ok).toBe(false);
    const { client: negato } = finto(() => ({ error: { code: "42501", message: "Azione riservata alla moderazione." } }));
    const r = await creaAnnunciAccessoriAdminService(negato).modera(U1, "oscura", "m");
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error).toBe("Operazione non consentita.");
  });

  it("l'elenco di moderazione manda solo il filtro e scarta le voci malformate", async () => {
    const riga = {
      id: U1, stato: "pubblicato", provvedimento: null, nome: "Calice", venditore: "ua", quantita: 2,
      prezzo_unitario_cents: 1200, versione: 0, pubblicato_at: "2026-10-22T08:00:00Z",
      segnalazioni_aperte: 1, segnalazioni_totali: 2,
    };
    const { client, chiamate } = finto(() => ({ data: [riga, { id: "x" }] }));
    const s = creaAnnunciAccessoriAdminService(client);
    // una voce malformata rende illeggibile l'intero elenco: non si mostra un elenco mutilato
    expect((await s.elencoModerazione("segnalati")).ok).toBe(false);
    expect(chiamate[0]).toEqual({ nome: "annunci_accessori_admin_elenca", args: { p_filtro: "segnalati", p_limite: 100 } });
    const { client: buono } = finto(() => ({ data: [riga] }));
    const r = await creaAnnunciAccessoriAdminService(buono).elencoModerazione("tutti");
    expect(r.ok && r.data[0].segnalazioniAperte).toBe(1);
    // @ts-expect-error filtro inesistente
    expect((await s.elencoModerazione("inventato")).ok).toBe(false);
  });

  it("senza client ogni porta admin risponde con un errore leggibile", async () => {
    const s = creaAnnunciAccessoriAdminService(null);
    expect((await s.stato()).ok).toBe(false);
    expect((await s.impostaPubblicazione(false, "x")).ok).toBe(false);
    expect((await s.categoriePubblicazione()).ok).toBe(false);
    expect((await s.elencoModerazione("tutti")).ok).toBe(false);
    expect((await s.dettaglioModerazione(U1)).ok).toBe(false);
    expect((await s.urlFoto(["a"])).ok).toBe(false);
  });
});

describe("servizio della vetrina pubblica", () => {
  const FOTO = `${U1}/${U2}/33333333-3333-4333-8333-333333333333.webp`;
  const pubblico = {
    id: U1, nome: "Calice", marchio: null,
    categoria: { slug: "calici-da-rosso", nome: "Calici da rosso", genitore: "Calici" },
    condizione: "usato", quantita: 2, descrizione: "", foto: [FOTO],
    prezzo_acquirente_cents: 2273, pubblicato_at: "2026-10-22T08:00:00Z", aggiornato_at: "2026-10-22T08:00:00Z",
    venditore: { username: "ua", avatar_url: null }, acquistabile: false,
  };

  it("l'elenco manda solo categoria, limite e offset; nessun id di utente", async () => {
    const { client, chiamate } = finto(() => ({ data: [pubblico] }));
    const r = await creaAnnunciAccessoriPubbliciService(client).elenco({ categoriaSlug: "calici", limite: 10, offset: 20 });
    expect(r.ok).toBe(true);
    expect(chiamate[0]).toEqual({
      nome: "annunci_accessori_pubblici_elenca",
      args: { p_categoria: "calici", p_limite: 10, p_offset: 20 },
    });
  });

  it("una risposta che dichiara l'annuncio acquistabile non è quella promessa: scartata dall'elenco, guasto nel dettaglio", async () => {
    const { client } = finto(() => ({ data: [{ ...pubblico, acquistabile: true }, pubblico] }));
    const elenco = await creaAnnunciAccessoriPubbliciService(client).elenco();
    expect(elenco.ok).toBe(true);
    // l'annuncio che si dichiara acquistabile non entra in vetrina; l'altro sì
    if (elenco.ok) expect(elenco.data.map((a) => a.id)).toEqual([U1]);
    const { client: c2 } = finto(() => ({ data: { ...pubblico, acquistabile: true } }));
    expect((await creaAnnunciAccessoriPubbliciService(c2).dettaglio(U1)).ok).toBe(false);
  });

  it("il dettaglio nullo (non esiste o non è visibile) è un esito, non un errore; un id malformato non parte", async () => {
    const { client, chiamate } = finto(() => ({ data: null }));
    const s = creaAnnunciAccessoriPubbliciService(client);
    const r = await s.dettaglio(U1);
    expect(r.ok && r.data).toBeNull();
    expect(chiamate).toEqual([{ nome: "annunci_accessori_pubblico_dettaglio", args: { p_id: U1 } }]);
    const malformato = await s.dettaglio("../x");
    expect(malformato.ok && malformato.data).toBeNull();
    expect(chiamate).toHaveLength(1);
  });

  it("senza client risponde con un errore leggibile", async () => {
    const s = creaAnnunciAccessoriPubbliciService(null);
    expect((await s.elenco()).ok).toBe(false);
    expect((await s.dettaglio(U1)).ok).toBe(false);
    expect((await s.urlFoto([FOTO])).ok).toBe(false);
  });
});
