/**
 * Vinea Partner — Blocco B: le superfici in cui un Partner cambia
 * l'interfaccia, verificate leggendo i file (stessa forma dei test delle
 * pagine profilo) e, per la classe e lo stato d'acquisto, eseguendo la logica
 * con un client finto. Ciò che si prova qui è la relazione fra pagine e porte:
 * chi decide la classe, che cosa succede quando la lettura fallisce, dove
 * l'acquisto sparisce, che cosa non cambia per i privati. I gate veri sono nel
 * database e li prova la griglia 12y.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { AuthRetryableFetchError, AuthSessionMissingError, type SupabaseClient } from "@supabase/supabase-js";
import { classeDelChiamante } from "@/lib/partner/classe-server";
import { statoAcquistoDa } from "@/lib/partner/vetrina";

const progetto = join(import.meta.dir, "../../..");
const leggi = (p: string) => readFileSync(join(progetto, p), "utf8");
const senzaCommenti = (s: string) =>
  s
    .replace(/\{\s*\/\*(?:(?!\*\/)[\s\S])*\*\/\s*\}/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");

const UTENTE = "11111111-1111-4111-8111-111111111111";
const rigaPartner = (stato: string) => ({
  id: "22222222-2222-4222-8222-222222222222",
  stato,
  nome_commerciale: "Enoteca",
  created_at: "2026-10-01T00:00:00Z",
  updated_at: "2026-10-01T00:00:00Z",
});

function clientFinto(
  utente: { user: { id: string } | null; error: Error | null },
  partnerMe?: { data: unknown; error: { code?: string; message?: string } | null },
) {
  const chiamate: string[] = [];
  const c = {
    auth: { getUser: async () => ({ data: { user: utente.user }, error: utente.error }) },
    rpc: async (nome: string) => {
      chiamate.push(nome);
      if (!partnerMe) throw new Error("rpc inattesa");
      return partnerMe;
    },
  } as unknown as SupabaseClient;
  return { c, chiamate };
}

describe("classeDelChiamante: privato, commerciale o errore — mai confusi", () => {
  it("senza Supabase configurato è la modalità dimostrativa: privato", async () => {
    expect(await classeDelChiamante(null)).toEqual({ tipo: "privato" });
  });

  it("un anonimo è privato e non interroga partner_me", async () => {
    const { c, chiamate } = clientFinto({ user: null, error: new AuthSessionMissingError() });
    expect(await classeDelChiamante(c)).toEqual({ tipo: "privato" });
    expect(chiamate).toEqual([]);
  });

  it("un guasto di rete verso Auth è un errore, non un anonimo", async () => {
    const { c } = clientFinto({ user: null, error: new AuthRetryableFetchError("rete", 0) });
    expect(await classeDelChiamante(c)).toEqual({ tipo: "errore" });
  });

  it("un utente senza Partner è privato", async () => {
    const { c, chiamate } = clientFinto({ user: { id: UTENTE }, error: null }, { data: null, error: null });
    expect(await classeDelChiamante(c)).toEqual({ tipo: "privato" });
    expect(chiamate).toEqual(["partner_me"]);
  });

  it("invitato, in verifica e revocato restano all'interfaccia di oggi", async () => {
    for (const stato of ["invitato", "in_verifica", "revocato"]) {
      const { c } = clientFinto({ user: { id: UTENTE }, error: null }, { data: rigaPartner(stato), error: null });
      expect(await classeDelChiamante(c)).toEqual({ tipo: "privato" });
    }
  });

  it("attivo e sospeso sono la classe commerciale, con il titolare dalla sessione", async () => {
    for (const stato of ["attivo", "sospeso"] as const) {
      const { c } = clientFinto({ user: { id: UTENTE }, error: null }, { data: rigaPartner(stato), error: null });
      const classe = await classeDelChiamante(c);
      expect(classe.tipo).toBe("commerciale");
      if (classe.tipo === "commerciale") {
        expect(classe.titolareId).toBe(UTENTE);
        expect(classe.partner.stato).toBe(stato);
      }
    }
  });

  it("una lettura di partner_me fallita o illeggibile è un errore, non un privato", async () => {
    const rotto = clientFinto({ user: { id: UTENTE }, error: null }, { data: null, error: { code: "PGRST000" } });
    expect(await classeDelChiamante(rotto.c)).toEqual({ tipo: "errore" });
    const illeggibile = clientFinto({ user: { id: UTENTE }, error: null }, { data: { stato: "attivo" }, error: null });
    expect(await classeDelChiamante(illeggibile.c)).toEqual({ tipo: "errore" });
  });
});

describe("statoAcquistoDa: un errore non è una disponibilità confermata", () => {
  it("traduce l'esito della porta in tre stati", () => {
    expect(statoAcquistoDa(null)).toBe("disponibile");
    expect(statoAcquistoDa({ ok: true, data: true })).toBe("disponibile");
    expect(statoAcquistoDa({ ok: true, data: false })).toBe("partner");
    expect(statoAcquistoDa({ ok: false, error: "x" })).toBe("non_verificato");
  });
});

describe("acquisti da Partner non raggiungibili dall'interfaccia", () => {
  const paginaAnnuncio = leggi("src/app/annuncio/[id]/page.tsx");
  const clientAnnuncio = leggi("src/app/annuncio/[id]/page-client.tsx");
  const checkout = leggi("src/app/checkout/[id]/page.tsx");

  it("la scheda annuncio chiede al server se l'acquisto è disponibile, e l'errore resta errore", () => {
    // VP-D: la disponibilità non è più lo specchio per venditore ma il
    // preventivo autorevole dell'annuncio (classe, vendibilità, prezzo).
    expect(paginaAnnuncio).toInclude("creaPreventivoService(client).annuncio(daMostrare.listingId ?? daMostrare.id)");
    expect(paginaAnnuncio).toInclude("const statoAcquisto = statoAcquistoDaPreventivo(preventivo);");
    expect(paginaAnnuncio).toInclude("statoAcquisto={statoAcquisto}");
    expect(senzaCommenti(paginaAnnuncio)).not.toMatch(/esitoAcquisto\?\.ok \? esitoAcquisto\.data : true/);
  });

  it("senza acquisto confermato: né «Compra ora» né proposta; il contatto resta", () => {
    const ramo = clientAnnuncio.slice(
      clientAnnuncio.indexOf('{statoAcquisto === "disponibile" ? ('),
      clientAnnuncio.indexOf("<ListingContactActions"),
    );
    expect(ramo).toInclude("Compra ora");
    expect(ramo).toInclude("<ProposalAction");
    const altrimenti = ramo.indexOf(') : statoAcquisto === "partner" ? (');
    expect(altrimenti).toBeGreaterThan(ramo.indexOf("<ProposalAction"));
    expect(ramo.indexOf("<AcquistiPartnerNonDisponibili")).toBeGreaterThan(altrimenti);
    expect(ramo.indexOf("<AcquistoNonVerificato")).toBeGreaterThan(ramo.indexOf("<AcquistiPartnerNonDisponibili"));
    // Il default resta «acquistabile»: i privati non cambiano.
    expect(clientAnnuncio).toInclude('statoAcquisto = "disponibile",');
  });

  it("il checkout si apre solo con disponibilità confermata", () => {
    const controllo = checkout.indexOf("creaPreventivoService(client).annuncio(");
    expect(controllo).toBeGreaterThan(-1);
    expect(checkout).toInclude('if (statoAcquisto !== "disponibile") {');
    expect(checkout).toInclude("<AcquistiPartnerNonDisponibili />");
    expect(checkout).toInclude("<AcquistoNonVerificato />");
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
  const paginaAnnuncio = leggi("src/app/annuncio/[id]/page.tsx");
  const clientAnnuncio = leggi("src/app/annuncio/[id]/page-client.tsx");

  it("la classe la decide il server da partner_me, mai il client o le qualifiche", () => {
    expect(classe).toInclude("creaPartnerService(client).mio()");
    expect(classe).toInclude("classeCommerciale(esito.data.stato)");
    expect(senzaCommenti(classe)).not.toMatch(/professionista|qualific|localStorage|searchParams/);
    expect(cantina).not.toInclude('"use client"');
  });

  it("per i privati la Cantina resta quella di sempre; un errore non la apre", () => {
    expect(cantina).toInclude('if (classe.tipo === "privato") return <CantinaPageClient />;');
    expect(cantina).toInclude('if (classe.tipo === "errore") return <ClasseNonVerificata');
  });

  it("la vista commerciale non ha strumenti da collezionista né quantità inventate", () => {
    expect(commerciale).not.toMatch(
      /AperturaBottiglia|bottiglia_apri|degustazion|Cellar3D|patrimon|valore|portfolio|quantit[àa]\s*:|\bdisponibili\b/i,
    );
    expect(commerciale).toInclude("<AcquistiPartnerNonDisponibili />");
    // VP-D: il catalogo dei prodotti vive in un componente proprio.
    expect(commerciale).toInclude("<ProdottiPartner prodotti={prodotti}");
    expect(senzaCommenti(leggi("src/components/vinea/partner/ProdottiPartner.tsx"))).toInclude(
      'data-testid="catalogo-commerciale-vuoto"',
    );
  });

  it("annunci e bottiglie personali non diventano catalogo: nessuna lettura, nessuna scrittura", () => {
    for (const s of [senzaCommenti(cantina), commerciale]) {
      expect(s).not.toMatch(/mieiAnnunci|annunci=|AnnuncioProprietario|WineCard|WineThumbnail|bottle_units/);
      expect(s).not.toMatch(/crea\(|aggiorna\(|insert|update/);
    }
    expect(commerciale).toInclude('data-testid="beni-personali-intatti"');
  });

  it("degustazione e wizard privato non sono strade del Partner, né di chi non si classifica", () => {
    expect(degustazione).toInclude('if (classe.tipo === "commerciale") redirect("/cantina");');
    expect(degustazione).toInclude('if (classe.tipo === "errore") {');
    expect(vendi).toInclude("classeDelChiamante(await getSupabaseServerClient())");
    expect(vendi).toInclude('if (classe.tipo === "errore") {');
    expect(vendi).toInclude('data-testid="vendi-partner-non-disponibile"');
    expect(vendi.indexOf('classe.tipo === "errore"')).toBeLessThan(vendi.indexOf("<VendiPageClient"));
    expect(paginaAnnuncio).toInclude('const visitatoreCommerciale = classeVisitatore.tipo !== "privato";');
    expect(clientAnnuncio).toInclude("{visitatoreCommerciale ? null : (");
  });

  it("nessuna superficie usa più il vecchio predicato a due esiti", () => {
    for (const p of [cantina, degustazione, vendi, paginaAnnuncio, classe]) {
      expect(p).not.toInclude("partnerCommercialeDelChiamante");
    }
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

  it("catalogo: solo prodotti commerciali, mai gli annunci personali del titolare (VP-C)", () => {
    // Vuoto finché la vendita Partner non apre la pubblicazione (VP-D): lo
    // stato vuoto resta.
    expect(vetrina).toInclude('data-testid="vetrina-catalogo-vuoto"');
    // Il catalogo arriva solo dalla porta commerciale, come `ProdottoVetrina`:
    // niente annunci personali, niente schede vino del marketplace.
    expect(vetrina).toInclude("catalogo?: ProdottoVetrina[]");
    expect(vetrina).not.toMatch(/prodotti=|WineCard|annunciAttivi|annunci=|\bWine\b/);
    const pagina = senzaCommenti(leggi("src/app/profilo/[id]/page.tsx"));
    expect(pagina).toInclude("vetrina ? servizioVetrina.catalogo(vetrina.partnerId) : NESSUNA_LETTURA");
    expect(pagina).toInclude("vetrina ? NESSUNA_LETTURA : service.annunciAttivi(id)");
    expect(leggi("src/services/partner-vetrina-service.ts")).toInclude('rpc("vetrina_partner_catalogo"');
  });

  it("il contatto diretto è dichiarato differito, senza un pulsante finto", () => {
    expect(vetrina).toInclude('data-testid="vetrina-contatto"');
    expect(vetrina).toInclude("arriverà insieme al");
    expect(vetrina).not.toMatch(/conversation_open|message_send|Contatta l|<Button|href=\{?["'`]\/messaggi/);
  });
});
