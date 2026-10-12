/**
 * VP-C: quantità multiple nei servizi e nelle superfici.
 *
 * Ogni quantità che l'interfaccia mostra è un conteggio di righe fatto dal
 * database; questi test fissano che il client legga le porte giuste, non
 * inventi numeri, tenga separati patrimonio personale e scorte commerciali e
 * non apra percorsi che il database tiene chiusi.
 */
import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createCellarService } from "@/services/cellar-service";
import { createListingService } from "@/services/listing-service";
import { createPaymentService } from "@/services/phase7/payment-service";
import { creaScortePartnerService, raggruppaScorte } from "@/services/partner-scorte-service";
import { chiaveGruppo } from "@/lib/cantina/gruppo";

const radice = join(import.meta.dir, "../../..");
const progetto = join(import.meta.dir, "../..");
const leggi = (p: string) => readFileSync(join(progetto, p), "utf8");
const leggiRepo = (p: string) => readFileSync(join(radice, p), "utf8");
const senzaCommenti = (s: string) =>
  s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1").replace(/\{\/\*[\s\S]*?\*\/\}/g, "");

type Esito = { data: unknown; error: unknown };

/**
 * Client finto: ogni `from(tabella)` restituisce una catena che registra i
 * filtri e si risolve con la risposta di quella tabella; `rpc` con quella della
 * funzione.
 */
function clientFinto(tabelle: Record<string, Esito>, rpc: Record<string, Esito>) {
  const filtri: Array<{ tabella: string; metodo: string; argomenti: unknown[] }> = [];
  const chiamateRpc: Array<{ nome: string; parametri: unknown }> = [];
  const catena = (tabella: string) => {
    const risposta = tabelle[tabella] ?? { data: [], error: null };
    const builder: Record<string, unknown> = {};
    for (const metodo of ["select", "eq", "is", "in", "order", "range", "limit"]) {
      builder[metodo] = (...argomenti: unknown[]) => {
        filtri.push({ tabella, metodo, argomenti });
        return builder;
      };
    }
    builder.maybeSingle = () => Promise.resolve(risposta);
    builder.then = (ok: (v: Esito) => unknown, ko?: (e: unknown) => unknown) =>
      Promise.resolve(risposta).then(ok, ko);
    return builder;
  };
  const client = {
    from: (tabella: string) => catena(tabella),
    rpc: (nome: string, parametri?: unknown) => {
      chiamateRpc.push({ nome, parametri });
      return Promise.resolve(rpc[nome] ?? { data: null, error: { code: "PGRST202", message: "x" } });
    },
    auth: { getUser: () => Promise.resolve({ data: { user: { id: "venditore" } } }) },
    storage: { from: () => ({ createSignedUrls: () => Promise.resolve({ data: [], error: null }) }) },
    functions: {
      invoke: (nome: string, opzioni: { body: unknown }) => {
        chiamateRpc.push({ nome, parametri: opzioni.body });
        return Promise.resolve({ data: { checkoutUrl: "https://esempio.test" }, error: null });
      },
    },
  } as unknown as SupabaseClient;
  return { client, filtri, chiamateRpc };
}

const vino = (slug: string, annata = 2019) => ({
  slug,
  produttore: "Cantina Za",
  nome: "Barolo",
  annata,
  regione: "Piemonte",
  denominazione: "",
  tipo: "Rosso",
  formato: "0,75 L",
  provenienza: "utente",
  finestra_inizio: null,
  finestra_fine: null,
  apice_inizio: null,
  apice_fine: null,
  finestra_fonte: "unavailable",
  finestra_affidabilita: null,
  finestra_aggiornata_at: null,
  temperatura_servizio: "",
  decantazione_minuti: null,
  calice: "",
  occasione: "",
  abbinamenti: [],
});

const unita = (id: string, slug: string, formato: string, extra: Record<string, unknown> = {}) => ({
  id,
  stato: "chiusa",
  visibilita: "privata",
  apertura_pianificata: null,
  note_personali: "",
  degustazione_nota: "",
  degustazione_at: null,
  prezzo_visibilita: "visibile",
  override_finestra_inizio: null,
  override_finestra_fine: null,
  override_apice_inizio: null,
  override_apice_fine: null,
  override_preferenza: null,
  override_nota: "",
  ceduta_at: null,
  immagini: [],
  created_at: `2026-10-12T0${id.length % 9}:00:00Z`,
  formato,
  lotto_id: "lotto-1",
  acquisition_cost_cents: 5200,
  wines: vino(slug),
  cellar_slots: null,
  listings: [],
  ...extra,
});

describe("Cantina: gruppi per vino e formato, bottiglie per riga", () => {
  const righe = [
    unita("u1", "barolo-2019", "0,75 L"),
    unita("u2", "barolo-2019", "0,75 L"),
    unita("u3", "barolo-2019", "0,75 L", { stato: "aperta" }),
    unita("m1", "barolo-2019", "1,5 L"),
  ];

  it("una scheda per gruppo, la Magnum separata; ogni bottiglia resta una riga", async () => {
    const { client, filtri } = clientFinto(
      { bottle_units: { data: righe, error: null }, cellar_environments: { data: [], error: null } },
      { cantina_unita_annunci: { data: [], error: null } },
    );
    const dati = await createCellarService(client).carica();
    expect(dati.bottiglie).toHaveLength(4);
    expect(dati.vini.map((v) => v.gruppoCantina).sort()).toEqual(
      [chiaveGruppo("barolo-2019", "0,75 L"), chiaveGruppo("barolo-2019", "1,5 L")].sort(),
    );
    const standard = dati.vini.find((v) => v.gruppoCantina === "barolo-2019");
    // Due chiuse su tre: l'aperta resta una riga ma non si conta fra le disponibili.
    expect(standard?.disponibili).toBe(2);
    expect(standard?.formato).toBe("0,75 L");
    expect(dati.vini.find((v) => v.formato === "1,5 L")?.disponibili).toBe(1);
    expect(dati.bottiglie.find((b) => b.bottleId === "m1")?.wineVintageId).toBe("barolo-2019@1-5-l");
    expect(dati.bottiglie.find((b) => b.bottleId === "u1")?.wineSlug).toBe("barolo-2019");
    expect(dati.metaPerVino["barolo-2019@1-5-l"]).toBeDefined();
    // Solo il patrimonio personale entra nella Cantina.
    expect(filtri).toContainEqual({ tabella: "bottle_units", metodo: "eq", argomenti: ["inventario", "personale"] });
  });

  it("una bottiglia in un annuncio di più bottiglie è in vendita e non si apre, anche se non è la rappresentativa", async () => {
    const { client } = clientFinto(
      { bottle_units: { data: righe, error: null }, cellar_environments: { data: [], error: null } },
      {
        cantina_unita_annunci: {
          data: [
            { bottle_unit_id: "u2", listing_id: "l1", listing_slug: "barolo", listing_stato: "attivo", stato: "in_vendita" },
            { bottle_unit_id: "u1", listing_id: "l1", listing_slug: "barolo", listing_stato: "attivo", stato: "venduta" },
          ],
          error: null,
        },
      },
    );
    const dati = await createCellarService(client).carica();
    const u2 = dati.bottiglie.find((b) => b.bottleId === "u2");
    expect(u2?.saleStatus).toBe("in_vendita");
    expect(u2?.statoAnnuncio).toBe("in_vendita");
    expect(u2?.annuncioBloccante).toEqual({ id: "l1", stato: "attivo" });
    expect(dati.bottiglie.find((b) => b.bottleId === "u1")?.saleStatus).toBe("venduta");
    expect(dati.bottiglie.find((b) => b.bottleId === "m1")?.saleStatus).toBe("privata");
  });

  it("se la lettura degli annunci per bottiglia fallisce la Cantina si mostra lo stesso", async () => {
    const { client } = clientFinto(
      { bottle_units: { data: righe, error: null }, cellar_environments: { data: [], error: null } },
      { cantina_unita_annunci: { data: null, error: { code: "42501" } } },
    );
    const dati = await createCellarService(client).carica();
    expect(dati.bottiglie).toHaveLength(4);
    expect(dati.bottiglie.every((b) => b.saleStatus === "privata")).toBe(true);
  });
});

describe("Aggiunta multipla in Cantina", () => {
  const dati = {
    produttore: "Cantina Za",
    nome: "Barolo",
    annata: 2019,
    regione: "Piemonte",
    tipo: "Rosso" as const,
    visibilita: "privata" as const,
    immagini: [],
    formato: "0,75 L",
    quantita: 12,
    idempotencyKey: "cantina:chiave-di-prova",
    acquisitionCostCents: 5200,
  };

  it("una sola chiamata con quantità, formato, chiave e costo per bottiglia", async () => {
    const ids = Array.from({ length: 12 }, (_, i) => `b${i}`);
    const { client, chiamateRpc } = clientFinto({}, {
      cellar_bottiglie_aggiungi: {
        data: { lottoId: "l", wineId: "w", formato: "0,75 L", quantita: 12, bottleUnitIds: ids, replay: false },
        error: null,
      },
    });
    const esito = await createCellarService(client).aggiungiBottiglie(dati);
    expect(esito).toEqual({
      ok: true,
      data: { lottoId: "l", wineId: "w", formato: "0,75 L", quantita: 12, bottleUnitIds: ids, replay: false },
    });
    expect(chiamateRpc).toHaveLength(1);
    expect(chiamateRpc[0]).toMatchObject({
      nome: "cellar_bottiglie_aggiungi",
      parametri: {
        p_quantita: 12,
        p_formato: "0,75 L",
        p_idempotency_key: "cantina:chiave-di-prova",
        p_acquisition_cost_cents: 5200,
        p_acquired_at: null,
      },
    });
  });

  it("una risposta con meno bottiglie di quelle dichiarate è un guasto, non un successo", async () => {
    const { client } = clientFinto({}, {
      cellar_bottiglie_aggiungi: {
        data: { lottoId: "l", wineId: "w", quantita: 12, bottleUnitIds: ["solo-una"] },
        error: null,
      },
    });
    const esito = await createCellarService(client).aggiungiBottiglie(dati);
    expect(esito.ok).toBe(false);
  });

  it("il messaggio applicativo della porta arriva all'utente, gli altri no", async () => {
    const { client } = clientFinto({}, {
      cellar_bottiglie_aggiungi: {
        data: null,
        error: { code: "P0001", message: "Puoi aggiungere da 1 a 120 bottiglie per volta." },
      },
    });
    expect(await createCellarService(client).aggiungiBottiglie(dati)).toEqual({
      ok: false,
      error: "Puoi aggiungere da 1 a 120 bottiglie per volta.",
    });
    const { client: rotto } = clientFinto({}, {
      cellar_bottiglie_aggiungi: { data: null, error: { code: "42501", message: "permission denied for table x" } },
    });
    const esito = await createCellarService(rotto).aggiungiBottiglie(dati);
    expect(esito.ok).toBe(false);
    expect(esito.ok ? "" : esito.error).not.toContain("permission");
  });
});

describe("Annunci di più bottiglie e quantità in vendita", () => {
  it("creaLotto passa le bottiglie scelte e il prezzo per bottiglia", async () => {
    const { client, chiamateRpc } = clientFinto({}, {
      listing_crea_lotto: { data: [{ annuncio_id: "a1", annuncio_slug: "barolo-2019" }], error: null },
    });
    const esito = await createListingService(client).creaLotto({
      bottleUnitIds: ["b1", "b2", "b3"],
      prezzoCents: 5000,
      condizione: "Ottimo",
      conservazione: "",
      storia: "",
      immagini: [],
    });
    expect(esito).toEqual({ ok: true, data: { id: "a1", slug: "barolo-2019" } });
    expect(chiamateRpc[0]).toMatchObject({
      nome: "listing_crea_lotto",
      parametri: { p_bottle_unit_ids: ["b1", "b2", "b3"], p_prezzo_cents: 5000 },
    });
  });

  it("impostaQuantita restituisce i conteggi del database e rifiuta una risposta incompleta", async () => {
    const conteggi = { listingId: "a1", offerte: 4, disponibili: 1, riservate: 3, vendute: 2, ritirate: 2 };
    const { client } = clientFinto({}, { listing_quantita_imposta: { data: conteggi, error: null } });
    expect(await createListingService(client).impostaQuantita("a1", 4)).toEqual({
      ok: true,
      data: { offerte: 4, disponibili: 1, riservate: 3, vendute: 2, ritirate: 2 },
    });
    const { client: monco } = clientFinto({}, { listing_quantita_imposta: { data: { offerte: 4 }, error: null } });
    expect((await createListingService(monco).impostaQuantita("a1", 4)).ok).toBe(false);
  });

  it("quantitaMie indicizza i conteggi per annuncio", async () => {
    const { client } = clientFinto({}, {
      listing_quantita_mie: {
        data: [{ listing_id: "a1", offerte: 5, disponibili: 3, riservate: 2, vendute: 0, ritirate: 0 }],
        error: null,
      },
    });
    expect(await createListingService(client).quantitaMie()).toEqual({
      ok: true,
      data: { a1: { offerte: 5, disponibili: 3, riservate: 2, vendute: 0, ritirate: 0 } },
    });
  });
});

describe("Checkout: una quantità, mai un importo", () => {
  it("il servizio pagamenti inoltra la quantità (o null) alla Edge Function", async () => {
    const { client, chiamateRpc } = clientFinto({}, {});
    await createPaymentService(client).creaCheckout({
      listingId: "a1",
      deliveryMode: "spedizione",
      idempotencyKey: "chiave-12345678",
      quantita: 2,
    });
    await createPaymentService(client).creaCheckout({
      listingId: "a1",
      deliveryMode: "spedizione",
      idempotencyKey: "chiave-87654321",
    });
    expect(chiamateRpc[0]).toMatchObject({ nome: "payments-checkout", parametri: { quantita: 2 } });
    expect(chiamateRpc[1]).toMatchObject({ nome: "payments-checkout", parametri: { quantita: null } });
  });

  it("la Edge Function valida la quantità e la passa alla porta; l'importo resta del database", () => {
    const edge = leggiRepo("supabase/functions/payments-checkout/index.ts");
    expect(edge).toInclude("quantita < 1 || quantita > 24");
    expect(edge).toInclude("p_quantita: quantita,");
    expect(edge).toInclude('Deno.env.get("PAYMENTS_ENABLED") !== "true"');
  });

  it("la pagina di checkout accetta dall'indirizzo solo un intero fra 1 e le disponibili", () => {
    const pagina = leggi("src/app/checkout/[id]/page.tsx");
    expect(pagina).toInclude("quantitaDaTesto(");
    expect(pagina).toInclude("Math.min(wine.disponibili, MAX_BOTTIGLIE_PER_ORDINE)");
  });
});

describe("Scorte commerciali del Partner", () => {
  it("si raggruppano per vino e formato contando righe", () => {
    const vinoScorte = { slug: "barolo-2019", produttore: "Za", nome: "Barolo", annata: 2019, regione: "Piemonte", tipo: "Rosso" };
    const gruppi = raggruppaScorte([
      { id: "1", formato: "0,75 L", wines: vinoScorte },
      { id: "2", formato: "0,75 L", wines: [vinoScorte] },
      { id: "3", formato: "1,5 L", wines: vinoScorte },
      { id: "4", formato: null, wines: vinoScorte },
    ]);
    expect(gruppi.map((g) => [g.formato, g.quantita])).toEqual([
      ["0,75 L", 3],
      ["1,5 L", 1],
    ]);
  });

  it("si leggono solo le righe commerciali, mai il patrimonio personale", async () => {
    const { client, filtri } = clientFinto({ bottle_units: { data: [], error: null } }, {});
    expect(await creaScortePartnerService(client).elenco()).toEqual({ ok: true, data: [] });
    expect(filtri).toContainEqual({ tabella: "bottle_units", metodo: "eq", argomenti: ["inventario", "commerciale"] });
  });

  it("l'aggiunta passa dalla porta del Partner con chiave d'idempotenza", async () => {
    const { client, chiamateRpc } = clientFinto({}, {
      scorte_partner_aggiungi: {
        data: { lottoId: "l", wineId: "w", formato: "0,75 L", quantita: 6, bottleUnitIds: ["a", "b", "c", "d", "e", "f"] },
        error: null,
      },
    });
    const esito = await creaScortePartnerService(client).aggiungi({
      produttore: "Za",
      nome: "Barolo",
      annata: 2019,
      regione: "Piemonte",
      tipo: "Rosso",
      formato: "0,75 L",
      quantita: 6,
      idempotencyKey: "scorte:chiave-1",
    });
    expect(esito.ok).toBe(true);
    expect(chiamateRpc[0]).toMatchObject({
      nome: "scorte_partner_aggiungi",
      parametri: { p_quantita: 6, p_idempotency_key: "scorte:chiave-1" },
    });
  });
});

describe("Superfici", () => {
  it("il wizard aggiunge N bottiglie in un gesto e vende più bottiglie dello stesso gruppo", () => {
    const wizard = senzaCommenti(leggi("src/hooks/useSellWizard.ts"));
    expect(wizard).toInclude("cellarService.aggiungiBottiglie(");
    expect(wizard).toInclude("idempotencyKey: chiaveAggiunta.current");
    expect(wizard).toInclude("listingService.creaLotto(");
    expect(wizard).toInclude("vendibili.slice(0, quante)");
    const pagina = senzaCommenti(leggi("src/app/vendi/page-client.tsx"));
    expect(pagina).toInclude('Field label="Formato"');
    expect(pagina).toInclude('Field label="Quante bottiglie"');
    expect(pagina).toInclude('Field label="Bottiglie in vendita"');
    expect(pagina).toInclude("unitaVendibiliDelGruppo(");
  });

  it("la Cantina lega schede e bottiglie per gruppo e mostra il dettaglio di ogni bottiglia", () => {
    const cantina = senzaCommenti(leggi("src/app/cantina/page-client.tsx"));
    expect(cantina).toInclude("<DettaglioGruppo");
    expect(cantina).toInclude("<RiepilogoGruppoCantina");
    expect(cantina).not.toInclude("w.wineSlug ?? w.id");
    const dettaglio = senzaCommenti(leggi("src/components/vinea/GruppoCantina.tsx"));
    // Le azioni restano per bottiglia: l'apertura riceve la singola unità.
    expect(dettaglio).toInclude("<AperturaBottiglia bottiglia={b}");
  });

  it("la Cantina commerciale legge solo le scorte e non ha strumenti da collezionista", () => {
    const commerciale = senzaCommenti(leggi("src/components/vinea/partner/CantinaCommerciale.tsx"));
    expect(commerciale).toInclude("scorte: Result<GruppoScorte[]>");
    expect(commerciale).not.toMatch(/AperturaBottiglia|degustazion|Cellar3D|portfolio|WineCard|mieiAnnunci/i);
    const pagina = senzaCommenti(leggi("src/app/cantina/page.tsx"));
    expect(pagina).toInclude("creaScortePartnerService(client)");
    expect(pagina).toInclude("servizioScorte.elenco()");
  });

  it("l'acquirente non vede un selettore che il database rifiuterebbe", () => {
    const quantita = senzaCommenti(leggi("src/components/vinea/QuantitaAnnuncio.tsx"));
    expect(quantita).toInclude('rpc("inventario_capacita")');
    expect(quantita).toInclude("if (!ordiniMultiUnita || massimo <= 1)");
  });
});
