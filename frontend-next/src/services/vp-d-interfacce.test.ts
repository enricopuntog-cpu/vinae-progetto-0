/**
 * VP-D, parte 2: preventivi autorevoli e superfici.
 *
 * Il prezzo per l'acquirente lo decide il database (classe, riga di
 * configurazione, formula). Questi test fissano che il client lo legga senza
 * mai scegliere un'aliquota, che una risposta incoerente non diventi un prezzo,
 * e che le superfici non offrano azioni che il database rifiuterebbe.
 */
import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  creaPreventivoService,
  leggiPreventivoAnnuncio,
  leggiPreventivoEconomico,
} from "@/services/preventivo-service";
import { creaScortePartnerService } from "@/services/partner-scorte-service";
import {
  eProdottoCommerciale,
  euro,
  messaggioNonAcquistabile,
  spiegazionePrezzo,
  statoAcquistoDaPreventivo,
} from "@/lib/prezzi/classe";
import { centesimiDaEuro } from "@/components/vinea/partner/CreaProdottoPartner";

const progetto = join(import.meta.dir, "../..");
const leggi = (p: string) => readFileSync(join(progetto, p), "utf8");
const senzaCommenti = (s: string) =>
  s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1").replace(/\{\/\*[\s\S]*?\*\/\}/g, "");
const spazi = (s: string) => s.replace(/\s/g, " ");

type Esito = { data: unknown; error: unknown };

const economico = (classe: "privato" | "partner", prezzo: number, quantita: number, totale: number) => ({
  classe,
  configId: 4,
  quantita,
  prezzoUnitarioCents: prezzo,
  subtotaleCents: prezzo * quantita,
  commissioneCents: totale - prezzo * quantita,
  totaleCents: totale,
  margineObiettivoBps: classe === "partner" ? 1500 : 800,
  riferimentoPercentualeBps: 209,
  riferimentoFissoCents: 25,
});

function clientRpc(risposte: Record<string, Esito>) {
  const chiamate: Array<{ nome: string; parametri: unknown }> = [];
  const client = {
    rpc: (nome: string, parametri?: unknown) => {
      chiamate.push({ nome, parametri });
      return Promise.resolve(risposte[nome] ?? { data: null, error: { code: "PGRST202", message: "x" } });
    },
  } as unknown as SupabaseClient;
  return { client, chiamate };
}

describe("VP-D — preventivo dell'annuncio dal database", () => {
  it("chiede listing_preventivo senza alcuna classe e legge il preventivo Partner", async () => {
    const { client, chiamate } = clientRpc({
      listing_preventivo: {
        data: {
          listingId: "a1",
          classe: "partner",
          acquistabile: true,
          motivo: null,
          disponibili: 8,
          imballaggioCents: null,
          preventivo: economico("partner", 4500, 1, 5311),
        },
        error: null,
      },
    });
    const esito = await creaPreventivoService(client).annuncio("a1", { quantita: 1 });
    expect(esito.ok && esito.data.preventivo?.totaleCents).toBe(5311);
    expect(esito.ok && esito.data.acquistabile).toBe(true);
    expect(chiamate[0]).toEqual({
      nome: "listing_preventivo",
      parametri: { p_listing_id: "a1", p_quantita: 1, p_prezzo_unitario_cents: null },
    });
  });

  it("una risposta incoerente o un errore non diventano mai un prezzo", async () => {
    // Totale che non è subtotale + commissione, o classe sconosciuta: si scarta.
    expect(leggiPreventivoEconomico({ ...economico("partner", 4500, 1, 5311), commissioneCents: 1 })).toBeUndefined();
    expect(leggiPreventivoEconomico({ ...economico("partner", 4500, 1, 5311), classe: "professionale" })).toBeUndefined();
    const { client } = clientRpc({ listing_preventivo: { data: null, error: { code: "P0001", message: "x" } } });
    const esito = await creaPreventivoService(client).annuncio("a1");
    expect(esito.ok).toBe(false);
    expect(statoAcquistoDaPreventivo(esito)).toBe("non_verificato");
  });

  it("acquistabile solo con un preventivo in mano", () => {
    const r = leggiPreventivoAnnuncio({
      listingId: "a1",
      classe: "privato",
      acquistabile: true,
      motivo: null,
      disponibili: 1,
      imballaggioCents: null,
      preventivo: null,
    });
    expect(r?.acquistabile).toBe(false);
  });

  it("stato d'acquisto: disponibile, partner, non verificato", () => {
    const base = { listingId: "a", disponibili: 1, imballaggioCents: null, preventivo: null };
    expect(
      statoAcquistoDaPreventivo({
        ok: true,
        data: {
          ...base,
          classe: "privato",
          acquistabile: true,
          motivo: null,
          preventivo: economico("privato", 4500, 1, 4990),
        },
      }),
    ).toBe("disponibile");
    for (const motivo of ["partner_vendita_non_disponibile", "partner_annuncio_personale", "partner_sospeso"] as const) {
      expect(
        statoAcquistoDaPreventivo({ ok: true, data: { ...base, classe: "partner", acquistabile: false, motivo } }),
      ).toBe("partner");
    }
    expect(
      statoAcquistoDaPreventivo({
        ok: true,
        data: { ...base, classe: "partner", acquistabile: false, motivo: "configurazione_mancante" },
      }),
    ).toBe("non_verificato");
  });

  it("prodotto commerciale: classe Partner che non sia un annuncio personale", () => {
    expect(eProdottoCommerciale({ classe: "partner", motivo: "partner_vendita_non_disponibile" })).toBe(true);
    expect(eProdottoCommerciale({ classe: "partner", motivo: "annuncio_non_attivo" })).toBe(true);
    expect(eProdottoCommerciale({ classe: "partner", motivo: "partner_annuncio_personale" })).toBe(false);
    expect(eProdottoCommerciale({ classe: "privato", motivo: null })).toBe(false);
    expect(eProdottoCommerciale(null)).toBe(false);
  });
});

describe("VP-D — spiegazione del prezzo al Partner", () => {
  it("45 euro Partner: ricevi 45, servizio 8,11, l'acquirente paga 53,11; non «commissione 15%»", () => {
    const s = spiegazionePrezzo(economico("partner", 4500, 1, 5311));
    expect(spazi(s.ricevi)).toBe("45,00 €");
    expect(spazi(s.servizio)).toBe("8,11 €");
    expect(spazi(s.totale)).toBe("53,11 €");
    expect(s.composizione).toContain("Margine Vinea 15%");
    expect(s.composizione).toContain("2,09%");
    expect(s.composizione).not.toMatch(/commissione del 15/i);
  });

  it("più bottiglie: subtotale e prezzo unitario distinti", () => {
    const s = spiegazionePrezzo(economico("partner", 4500, 3, 15882));
    expect(spazi(s.ricevi)).toBe("135,00 € (3 × 45,00 €)");
    expect(spazi(s.totale)).toBe("158,82 €");
  });

  it("i motivi del database diventano frasi, mai un prezzo di ripiego", () => {
    expect(messaggioNonAcquistabile("configurazione_mancante")).toContain("non è determinabile");
    expect(messaggioNonAcquistabile("partner_sospeso")).toContain("sospeso");
    expect(messaggioNonAcquistabile(null)).toContain("non è disponibile");
  });

  it("il prezzo scritto in euro diventa centesimi solo se è un importo valido", () => {
    expect(centesimiDaEuro("45")).toBe(4500);
    expect(centesimiDaEuro("45,5")).toBe(4550);
    expect(centesimiDaEuro("45.05")).toBe(4505);
    for (const testo of ["", "0", "-3", "4,555", "abc", "1e3"]) {
      expect(centesimiDaEuro(testo)).toBeNull();
    }
  });
});

describe("VP-D — catalogo e scorte del Partner", () => {
  it("prodotti_partner_miei: legge i prodotti e rifiuta una forma diversa", async () => {
    const prodotto = {
      listingId: "l1",
      slug: "nebbiolo-2020",
      stato: "bozza",
      prezzoCents: 4500,
      produttore: "Cantina",
      nome: "Nebbiolo",
      annata: 2020,
      tipo: "Rosso",
      regione: "Piemonte",
      formato: "0,75 L",
      immagini: [],
      offerte: 8,
      disponibili: 8,
      riservate: 0,
      vendute: 0,
      vendibile: false,
      motivo: "partner_vendita_non_disponibile",
      preventivoUnitario: economico("partner", 4500, 1, 5311),
    };
    const ok = clientRpc({ prodotti_partner_miei: { data: [prodotto], error: null } });
    const esito = await creaPreventivoService(ok.client).prodottiPartner();
    expect(esito.ok && esito.data[0]?.preventivoUnitario?.totaleCents).toBe(5311);
    const ko = clientRpc({ prodotti_partner_miei: { data: [{ ...prodotto, offerte: "otto" }], error: null } });
    expect((await creaPreventivoService(ko.client).prodottiPartner()).ok).toBe(false);
  });

  it("unità occupate da cantina_unita_annunci; senza lettura nessuna unità proposta", async () => {
    const ok = clientRpc({
      cantina_unita_annunci: { data: [{ bottle_unit_id: "u1" }, { bottle_unit_id: "u2" }], error: null },
    });
    const esito = await creaScortePartnerService(ok.client).occupate();
    expect(esito.ok && [...esito.data]).toEqual(["u1", "u2"]);
    const ko = clientRpc({});
    expect((await creaScortePartnerService(ko.client).occupate()).ok).toBe(false);
  });

  it("interruttore vendita_partner letto dallo specchio, errore se illeggibile", async () => {
    const ok = clientRpc({ inventario_capacita: { data: { venditaPartner: false }, error: null } });
    expect(await creaPreventivoService(ok.client).venditaPartnerAperta()).toEqual({ ok: true, data: false });
    const ko = clientRpc({ inventario_capacita: { data: {}, error: null } });
    expect((await creaPreventivoService(ko.client).venditaPartnerAperta()).ok).toBe(false);
  });
});

describe("VP-D — superfici", () => {
  it("il checkout non calcola più con parametri fissi nel codice", () => {
    const riepilogo = senzaCommenti(leggi("src/lib/beta/checkout.ts"));
    expect(riepilogo).not.toMatch(/PARAMETRI_REPO|calcolaCommissione|margineObiettivoBps:\s*\d/);
    const summary = senzaCommenti(leggi("src/app/checkout/[id]/checkout-summary.tsx"));
    expect(summary).toInclude("riepilogoCheckout(economico, dati.imballaggioCodice, logisticaCents ?? 0)");
    expect(summary).toInclude('data-testid="checkout-totale-non-disponibile"');
  });

  it("nessuna superficie sceglie un'aliquota: niente 800, 1500 o calcolaCommissione", () => {
    for (const f of [
      "src/components/vinea/PrezzoPerAcquirente.tsx",
      "src/components/vinea/partner/CreaProdottoPartner.tsx",
      "src/components/vinea/partner/ProdottiPartner.tsx",
      "src/components/vinea/partner/PubblicazioneProdottoPartner.tsx",
      "src/components/vinea/ProposalAction.tsx",
      "src/app/annuncio/[id]/page.tsx",
      "src/app/checkout/[id]/page.tsx",
    ]) {
      expect(senzaCommenti(leggi(f))).not.toMatch(/calcolaCommissione|\b1500\b|\b800\b|marketplace_config/);
    }
  });

  it("il prodotto nasce in bozza dalle unità libere commerciali, con il preventivo del Partner", () => {
    const crea = senzaCommenti(leggi("src/components/vinea/partner/CreaProdottoPartner.tsx"));
    expect(crea).toInclude('preventivi.vendita(cents, q, "commerciale")');
    expect(crea).toInclude("bottleUnitIds: libere.slice(0, q)");
    expect(crea).toInclude('data-testid="crea-prodotto-non-verificato"');
  });

  it("pubblicazione chiusa senza un pulsante che il database rifiuterebbe", () => {
    const pub = senzaCommenti(leggi("src/components/vinea/partner/PubblicazioneProdottoPartner.tsx"));
    const guardia = pub.indexOf("if (!PUBBLICABILE.has(motivo)) {");
    expect(pub).toInclude('data-testid="pubblicazione-prodotto-chiusa"');
    expect(guardia).toBeGreaterThan(-1);
    expect(guardia).toBeLessThan(pub.indexOf("pubblicaConLogistica({"));
  });

  it("la scheda mostra il prezzo per l'acquirente solo dove si può acquistare o al venditore", () => {
    const scheda = senzaCommenti(leggi("src/app/annuncio/[id]/page-client.tsx"));
    expect(scheda).toInclude('{sonoIlVenditore || statoAcquisto === "disponibile" ? (');
    expect(scheda).toInclude('vista={sonoIlVenditore ? "venditore" : "acquirente"}');
  });

  it("checkout e riepilogo ordine mostrano gli importi al centesimo, mai arrotondati all'euro", () => {
    expect(euro(4959).replace(/\s/g, " ")).toBe("49,59 €");
    expect(euro(759).replace(/\s/g, " ")).toBe("7,59 €");
    for (const f of ["src/app/checkout/[id]/checkout-summary.tsx", "src/components/vinea/orders/OrderSummary.tsx"]) {
      const sorgente = senzaCommenti(leggi(f));
      expect(sorgente).not.toInclude("formatEUR");
      expect(sorgente).toMatch(/import \{[^}]*\beuro\b[^}]*\} from "@\/lib\/prezzi\/classe"/);
    }
  });
});
