import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

const progetto = join(import.meta.dir, "../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");
const esiste = (percorso: string) => existsSync(join(progetto, percorso));
const fileRicorsivi = (directory: string): string[] =>
  readdirSync(directory, { withFileTypes: true }).flatMap((voce) => {
    const percorso = join(directory, voce.name);
    return voce.isDirectory() ? fileRicorsivi(percorso) : [percorso];
  });

describe("superfici pubbliche della beta", () => {
  it("non dichiara evidenza IA sull'annuncio senza un dato canonico", () => {
    const dettaglio = leggi("src/app/annuncio/[id]/page-client.tsx");
    expect(dettaglio).not.toInclude('TrustBadge source="ia"');
    expect(dettaglio).toInclude('TrustBadge source="piattaforma"');
  });

  it("invia le proposte con il servizio Phase 7 e non con lo store locale", () => {
    const proposta = leggi("src/components/vinea/ProposalAction.tsx");
    expect(proposta).toInclude("createProposalService(client)");
    expect(proposta).toInclude("service.invia(listingId, cents)");
    expect(proposta).not.toMatch(/\bcreateProposal\(|pushNotifica|toast\.success/);
  });

  it("richiede altre foto soltanto con conversazione e messaggio Phase 8", () => {
    const contatti = leggi("src/components/vinea/ListingContactActions.tsx");
    expect(contatti).toInclude("openConversation({ listingId })");
    expect(contatti).toInclude("await sendMessage({");
    expect(contatti).not.toMatch(/richiediAltreFoto|pushNotifica|toast/);
  });

  it("non espone preferiti o follow locali sulle schede pubbliche", () => {
    const superfici = [
      leggi("src/components/vinea/WineCard.tsx"),
      leggi("src/app/annuncio/[id]/page-client.tsx"),
    ].join("\n");
    expect(superfici).not.toMatch(/toggleFavorite|toggleFollow|Aggiunto ai preferiti|Ora segui/);
  });

  it("inoltra la ricerca regionale dalla landing al catalogo", () => {
    const landing = leggi("src/app/page-client.tsx");
    const pagina = leggi("src/app/esplora/page.tsx");
    const catalogo = leggi("src/app/esplora/page-client.tsx");
    expect(landing).toInclude("/esplora?regione=");
    expect(pagina).toInclude('initialRegion={regione ?? "Tutte"}');
    expect(catalogo).toInclude("regioni.includes(initialRegion)");
  });

  it("rende irraggiungibile la community dimostrativa", () => {
    expect(leggi("src/app/community/page.tsx")).toInclude("notFound()");
    expect(leggi("src/app/community/[slug]/page.tsx")).toInclude("notFound()");
    expect(leggi("src/components/vinea/Layout.tsx")).not.toInclude('href: "/community"');
    expect(esiste("src/app/community/page-client.tsx")).toBeFalse();
  });

  it("usa il nome profilo autenticato senza identita personale hardcoded", () => {
    const home = leggi("src/app/home/page-client.tsx");
    expect(home).toInclude("authProfileName");
    expect(home).not.toMatch(/Elena Rossi|preferiti|seguiti|communityPosts/);
  });

  it("legge lo username dalla riga profiles canonica", () => {
    const auth = leggi("src/services/auth-service.ts");
    expect(auth).toInclude('.from("profiles")');
    expect(auth).toInclude('.select("username")');
    expect(auth).toInclude('.eq("id", userId)');
  });

  it("non mostra il promemoria non persistito", () => {
    const finestra = leggi("src/components/vinea/DrinkWindow.tsx");
    expect(finestra).not.toMatch(/Ricordamelo|Promemoria impostato|toast\.success/);
  });

  it("non monta i domini demo rimossi nel provider globale", () => {
    const store = leggi("src/lib/vinea-store.tsx");
    expect(store).not.toMatch(/use(Order|Clubs|Listings|Messaging|Moderation|Profile)Domain/);
    for (const file of [
      "clubs-domain.ts",
      "listings-domain.ts",
      "messaging-domain.ts",
      "moderation-domain.ts",
      "order-domain.ts",
      "profile-domain.ts",
    ]) {
      expect(esiste(`src/lib/store/${file}`)).toBeFalse();
    }
  });

  it("non usa servizi messaggi mock come fallback pubblico", () => {
    const controller = leggi("src/lib/phase8/use-phase8-controller.ts");
    expect(controller).toInclude('mode: client ? "supabase" : "unavailable"');
    expect(controller).not.toInclude("createMockPhase8Services");
    expect(leggi("src/components/vinea/messaging/MessagesPageClient.tsx")).not.toInclude(
      "MOCK_PHASE8_USER_ID",
    );
  });

  it("non usa dati moderazione mock come fallback pubblico", () => {
    const controller = leggi("src/lib/phase9/use-phase9-moderation.ts");
    expect(controller).toInclude('mode: "unavailable" as const');
    expect(controller).not.toMatch(/reportsMock|auditMock|mode: "mock"/);
  });

  it("rimuove personalizzazioni e storico inventato dalla cantina", () => {
    const cantina = leggi("src/app/cantina/page-client.tsx");
    expect(cantina).not.toMatch(/PreferenzeCantina|SfondoDialog|ANDAMENTO|ultimi 12 mesi/);
    expect(cantina).toInclude("Somma dei prezzi collegati");
  });

  it("blocca il punto logistico demo senza renderlo raggiungibile", () => {
    expect(esiste("src/components/vinea/orders/PackagingPointPicker.tsx")).toBeFalse();
    expect(leggi("src/components/vinea/orders/SellerPrepPanel.tsx")).toInclude(
      '<BetaActionNotice tipo="spedizione"',
    );
  });

  it("fallisce chiuso quando il servizio segnalazioni non e configurato", () => {
    const report = leggi("src/components/vinea/ReportDialog.tsx");
    const controllo = report.indexOf("if (!client)");
    const invio = report.indexOf("createSupabaseModerationService(client).segnala");
    expect(controllo).toBeGreaterThan(-1);
    expect(invio).toBeGreaterThan(controllo);
  });

  it("non lascia identita demo nel runtime delle route pubbliche", () => {
    const sorgenti = ["src/app", "src/components", "src/hooks", "src/lib/store"]
      .flatMap((directory) => fileRicorsivi(join(progetto, directory)))
      .filter((file) => /\.(ts|tsx)$/.test(file) && !file.endsWith(".test.ts"))
      .map((file) => readFileSync(file, "utf8"))
      .join("\n");
    expect(sorgenti).not.toMatch(/Elena Rossi|elena@demo\.it|i\.pravatar\.cc/);
  });
});
