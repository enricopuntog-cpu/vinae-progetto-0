/**
 * Vinea Partner — Blocco B: le superfici in cui un Partner cambia
 * l'interfaccia, verificate leggendo i file (stessa forma dei test delle
 * pagine profilo). Ciò che si prova qui è la relazione fra pagine e porte:
 * chi decide la classe, dove l'acquisto sparisce, che cosa non cambia per i
 * privati. I gate veri sono nel database e li prova la griglia 12y.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { AnnuncioProprietario, ListingStato } from "@/services/listing-service";
import { ETICHETTA_STATO_PRODOTTO, catalogoCommerciale, presentabile } from "@/lib/partner/catalogo";

const progetto = join(import.meta.dir, "../../..");
const leggi = (p: string) => readFileSync(join(progetto, p), "utf8");
const senzaCommenti = (s: string) =>
  s
    .replace(/\{\s*\/\*(?:(?!\*\/)[\s\S])*\*\/\s*\}/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");

describe("acquisti da Partner non raggiungibili dall'interfaccia", () => {
  const paginaAnnuncio = leggi("src/app/annuncio/[id]/page.tsx");
  const clientAnnuncio = leggi("src/app/annuncio/[id]/page-client.tsx");
  const checkout = leggi("src/app/checkout/[id]/page.tsx");

  it("la scheda annuncio chiede al server se l'acquisto è disponibile", () => {
    expect(paginaAnnuncio).toInclude("acquistoDisponibile(venditoreId)");
    expect(paginaAnnuncio).toInclude("const acquistoDisponibile = esitoAcquisto?.ok ? esitoAcquisto.data : true;");
    expect(paginaAnnuncio).toInclude("acquistoDisponibile={acquistoDisponibile}");
  });

  it("senza acquisto: né «Compra ora» né proposta, ma lo stato spiegato; il contatto resta", () => {
    const ramo = clientAnnuncio.slice(
      clientAnnuncio.indexOf("{acquistoDisponibile ? ("),
      clientAnnuncio.indexOf("<ListingContactActions"),
    );
    expect(ramo).toInclude("Compra ora");
    expect(ramo).toInclude("<ProposalAction");
    expect(ramo).toInclude("<AcquistiPartnerNonDisponibili");
    expect(ramo.indexOf("<ProposalAction")).toBeLessThan(ramo.indexOf(") : ("));
    expect(ramo.indexOf("<AcquistiPartnerNonDisponibili")).toBeGreaterThan(ramo.indexOf(") : ("));
    // Il default resta «acquistabile»: i privati non cambiano.
    expect(clientAnnuncio).toInclude("acquistoDisponibile = true,");
  });

  it("il checkout diretto non si apre verso un Partner", () => {
    const controllo = checkout.indexOf("acquistoDisponibile(wine.venditore.userId)");
    expect(controllo).toBeGreaterThan(-1);
    expect(checkout).toInclude("if (esito.ok && !esito.data) {");
    expect(checkout).toInclude("<AcquistiPartnerNonDisponibili />");
    expect(controllo).toBeLessThan(checkout.indexOf("<CheckoutPageClient"));
  });

  it("nessuna di queste pagine tocca flag di pagamento o calcola commissioni", () => {
    for (const s of [paginaAnnuncio, checkout].map(senzaCommenti)) {
      expect(s).not.toMatch(/PAYMENTS_ENABLED|calcolaCommissione|marketplace_config|1500|bps/);
    }
  });
});

describe("Cantina del Partner = catalogo commerciale", () => {
  const cantina = leggi("src/app/cantina/page.tsx");
  const classe = leggi("src/lib/partner/classe-server.ts");
  const commerciale = senzaCommenti(leggi("src/components/vinea/partner/CantinaCommerciale.tsx"));
  const degustazione = leggi("src/app/cantina/[bottleId]/degustazione/page.tsx");
  const vendi = leggi("src/app/vendi/page.tsx");
  const clientAnnuncio = leggi("src/app/annuncio/[id]/page-client.tsx");

  it("la classe la decide il server da partner_me, mai il client o le qualifiche", () => {
    expect(classe).toInclude("creaPartnerService(client).mio()");
    expect(classe).toInclude("classeCommerciale(esito.data.stato)");
    expect(senzaCommenti(classe)).not.toMatch(/professionista|qualific|localStorage|searchParams/);
    expect(cantina).not.toInclude('"use client"');
  });

  it("per i privati la Cantina resta quella di sempre", () => {
    expect(cantina).toInclude("if (!commerciale) return <CantinaPageClient />;");
  });

  it("la vista commerciale non ha strumenti da collezionista né quantità inventate", () => {
    expect(commerciale).not.toMatch(
      /AperturaBottiglia|bottiglia_apri|degustazion|Cellar3D|patrimon|valore|portfolio|quantit[àa]\s*:|\bdisponibili\b/i,
    );
    expect(commerciale).toInclude("<AcquistiPartnerNonDisponibili />");
    expect(commerciale).toInclude('data-testid="catalogo-commerciale-vuoto"');
  });

  it("nessuna conversione: la vista legge gli annunci, non scrive bottiglie", () => {
    expect(cantina).toInclude("mieiAnnunciConEsito()");
    expect(senzaCommenti(cantina)).not.toMatch(/crea\(|aggiorna\(|bottle_units|insert|update/);
  });

  it("degustazione e wizard privato non sono strade del Partner", () => {
    expect(degustazione).toInclude('redirect("/cantina")');
    expect(vendi).toInclude("partnerCommercialeDelChiamante(await getSupabaseServerClient())");
    expect(vendi).toInclude('data-testid="vendi-partner-non-disponibile"');
    expect(clientAnnuncio).toInclude("{visitatoreCommerciale ? null : (");
  });
});

describe("catalogo commerciale", () => {
  const annuncio = (stato: ListingStato, id: string) =>
    ({ stato, wine: { id } }) as unknown as AnnuncioProprietario;

  it("ogni stato dell'annuncio ha un'etichetta", () => {
    const stati: ListingStato[] = [
      "bozza", "in_revisione", "modifiche_richieste", "attivo", "riservato",
      "sospeso", "scaduto", "venduto", "rifiutato",
    ];
    for (const s of stati) expect(ETICHETTA_STATO_PRODOTTO[s]).toBeTruthy();
  });

  it("in vetrina solo ciò che la vetrina pubblica mostra (annunci attivi)", () => {
    expect(presentabile("attivo")).toBe(true);
    expect(presentabile("riservato")).toBe(false);
    const { inVetrina, altri } = catalogoCommerciale([
      annuncio("attivo", "a"),
      annuncio("bozza", "b"),
      annuncio("venduto", "c"),
    ]);
    expect(inVetrina.map((a) => a.wine.id)).toEqual(["a"]);
    expect(altri.map((a) => a.wine.id)).toEqual(["b", "c"]);
  });

  it("catalogo vuoto: due elenchi vuoti, nessun errore", () => {
    expect(catalogoCommerciale([])).toEqual({ inVetrina: [], altri: [] });
  });
});

describe("vetrina pubblica", () => {
  const vetrina = senzaCommenti(leggi("src/components/vinea/partner/VetrinaPartner.tsx"));

  it("badge della classe commerciale distinto dalla qualifica personale", () => {
    expect(vetrina).toInclude("Partner Vinea · Venditore professionale");
    expect(vetrina).toInclude("Qualifica professionale verificata del titolare");
  });

  it("nessun dato amministrativo e nessun dato inventato", () => {
    expect(vetrina).not.toMatch(/partitaIva|ragioneSociale|sedeIndirizzo|emailCommerciale|ultimoMotivo/);
    expect(vetrina).not.toMatch(/Math\.random|lorem|demo|mock/i);
  });

  it("le recensioni sono dichiarate del titolare, non dell'attività", () => {
    expect(vetrina).toInclude('data-testid="nota-recensioni-titolare"');
    expect(vetrina).toInclude("non sono recensioni di acquisti dall&apos;attività");
  });

  it("immagini solo da percorsi validati e con testo alternativo", () => {
    expect(vetrina).toInclude("urlMediaVetrina(p, vetrina.titolareId, vetrina.partnerId)");
    for (const alt of ["Copertina di", "Logo di", "Fotografia ${i + 1} di ${foto.length}"]) {
      expect(vetrina).toInclude(alt);
    }
  });

  it("catalogo vuoto e contatto tramite la messaggistica esistente", () => {
    expect(vetrina).toInclude('data-testid="vetrina-catalogo-vuoto"');
    expect(vetrina).toInclude("Contatta il venditore");
    expect(vetrina).not.toMatch(/conversation_open|message_send/);
  });
});
