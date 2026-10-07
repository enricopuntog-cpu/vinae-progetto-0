import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { extname, join, relative, resolve } from "node:path";

const root = resolve(import.meta.dir, "../../../..");
const read = (path: string) => readFileSync(resolve(root, path), "utf8");
const betaRoot = resolve(root, "frontend-next/src/app/beta-test");
const marketValidationRoot = resolve(root, "frontend-next/src/lib/market-validation");

function sourceFiles(directory: string): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory()
      ? sourceFiles(path)
      : [".ts", ".tsx"].includes(extname(entry.name))
        ? [path]
        : [];
  });
}

const productionSources = () =>
  [
    ...sourceFiles(betaRoot),
    ...sourceFiles(marketValidationRoot),
    resolve(root, "frontend-next/src/services/market-validation-service.ts"),
  ].filter((file) => !file.endsWith(".test.ts"));

const betaSource = () =>
  sourceFiles(betaRoot)
    .filter((file) => !file.endsWith(".test.ts"))
    .map((file) => readFileSync(file, "utf8"))
    .join("\n");

// Le sole superfici reali verso cui la guida può navigare: semplici link,
// mai una copia della funzione dentro il test. `/cantina` parte solo
// dall'anteprima Cantina e `/` solo dalla schermata finale.
const REAL_DESTINATIONS = ["/", "/cantina", "/community", "/esplora", "/vendi"];

describe("Market Validation MV2 UI contract", () => {
  it("resta single-route: Vendi e Club non sono più schermate interne", () => {
    const client = read("frontend-next/src/app/beta-test/page-client.tsx");
    const hub = read("frontend-next/src/app/beta-test/_components/ValidationHub.tsx");
    expect(client).toInclude("MarketValidationScreen");
    expect(client).toInclude('useState<MarketValidationScreen>("hub")');
    expect(client).not.toInclude("useRouter");
    expect(client).not.toInclude("router.push");
    expect(client).not.toInclude("<Link");
    expect(client).not.toInclude('screen === "seller"');
    expect(client).not.toInclude('screen === "club"');
    const unionStart = hub.indexOf("export type MarketValidationScreen");
    const screenUnion = hub.slice(unionStart, hub.indexOf(";", unionStart));
    for (const screen of ["hub", "marketplace", "detail", "checkout", "ai", "cellar", "complete"]) {
      expect(screenUnion).toInclude(`"${screen}"`);
    }
    expect(screenUnion).not.toInclude('"seller"');
    expect(screenUnion).not.toInclude('"club"');

    const routes = sourceFiles(resolve(root, "frontend-next/src/app/beta-test"))
      .filter((file) => /[\\/]page\.tsx$/.test(file));
    expect(routes.map((file) => relative(betaRoot, file))).toEqual(["page.tsx"]);
  });

  it("risolve lo shipping sul server e completa solo dopo gli eventi hard-gated", () => {
    const page = read("frontend-next/src/app/beta-test/page.tsx");
    const client = read("frontend-next/src/app/beta-test/page-client.tsx");
    const checkout = read("frontend-next/src/app/beta-test/_components/DemoCheckout.tsx");
    expect(page).toInclude("marketValidationShippingFeeCents()");
    expect(page).toInclude("shippingFeeCents=");
    expect(client.indexOf('track("beta_completed"')).toBeLessThan(client.indexOf('setScreen("complete")'));
    expect(checkout.indexOf('track(\n      "checkout_beta_completed"')).toBeLessThan(checkout.indexOf("onCompleted();"));
    expect(checkout).toInclude("Non è stato creato alcun ordine, pagamento");
  });

  it("mantiene il percorso Acquista demo: marketplace, dettaglio, preferiti e checkout", () => {
    const client = read("frontend-next/src/app/beta-test/page-client.tsx");
    for (const component of ["DemoMarketplace", "DemoListingDetail", "DemoCheckout", "ValidationComplete"]) {
      expect(existsSync(resolve(betaRoot, `_components/${component}.tsx`))).toBeTrue();
      expect(client).toInclude(`<${component}`);
    }
    expect(client).toInclude("favoriteDemoIds");
    expect(client).toInclude("buyerCompleted: true");
    const source = betaSource();
    for (const eventName of [
      "marketplace_viewed",
      "demo_listing_viewed",
      "favorite_added",
      "checkout_started",
      "shipping_cost_viewed",
      "checkout_beta_completed",
    ]) {
      expect(source).toInclude(`"${eventName}"`);
    }
  });

  it("conserva struttura, ordine delle 4 card e obbligatorietà dell'hub approvato", () => {
    const hub = read("frontend-next/src/app/beta-test/_components/ValidationHub.tsx");
    for (const fixed of [
      "Hub tester",
      "Prova Vinea",
      "Test {participantCode}",
      "Percorsi obbligatori",
      "di 2 completati",
      "Acquisto e vendita sono obbligatori. AI e Club sono facoltativi.",
      "Obbligatorio",
      "Facoltativo",
      "Completato",
      "marketValidationCanComplete(progress)",
      "disabled={!completed || completing}",
      "Completa il test",
      "min-h-12",
      "sm:grid-cols-2",
    ]) {
      expect(hub).toInclude(fixed);
    }
    const titles = ['title: "Acquista"', 'title: "Vendi"', 'title: "Anteprima AI"', 'title: "Club"'];
    const positions = titles.map((title) => hub.indexOf(title));
    expect(positions.every((position) => position > 0)).toBeTrue();
    expect([...positions].sort((a, b) => a - b)).toEqual(positions);
    const areasStart = hub.indexOf("const areas");
    const cards = hub.slice(areasStart, hub.indexOf("return (", areasStart));
    expect(cards.match(/required: true/g)).toHaveLength(2);
    expect(cards.match(/required: false/g)).toHaveLength(2);
    expect(cards.indexOf("required: true")).toBeGreaterThan(cards.indexOf('title: "Acquista"'));
    expect(cards.lastIndexOf("required: true")).toBeLessThan(cards.indexOf('title: "Anteprima AI"'));
  });

  it("apre il vero /vendi e chiude il percorso solo sulla conferma al ritorno", () => {
    const hub = read("frontend-next/src/app/beta-test/_components/ValidationHub.tsx");
    const client = read("frontend-next/src/app/beta-test/page-client.tsx");
    expect(hub).toInclude("Prova il vero percorso di Vinea per aggiungere una bottiglia alla cantina o metterla in vendita.");
    expect(hub).toInclude('cta: "Prova la vendita"');
    expect(hub).toInclude('href: "/vendi"');
    expect(hub).toInclude("Apre la vera funzione di Vinea in una nuova scheda: per alcune azioni può servirti un account.");
    expect(hub).toInclude("onOpen: onSellerOpen");
    expect(hub).toInclude("Hai provato il percorso di vendita?");
    expect(hub).toInclude("Sì, l'ho provato");
    expect(hub).toInclude("sellerOpened && !progress.sellerCompleted");
    expect(hub).not.toInclude("Simula la pubblicazione locale");

    const openSeller = client.slice(client.indexOf("const openSeller"), client.indexOf("const confirmSeller"));
    expect(openSeller).toInclude('track("sell_started", {}, "sell_started")');
    expect(openSeller).not.toInclude("sellerCompleted");
    expect(openSeller).not.toInclude("sell_completed");

    const confirmSeller = client.slice(client.indexOf("const confirmSeller"), client.indexOf("const openClub"));
    expect(confirmSeller.indexOf('track("sell_completed", {}, "sell_completed")'))
      .toBeLessThan(confirmSeller.indexOf("if (!result.ok)"));
    expect(confirmSeller.indexOf("if (!result.ok)"))
      .toBeLessThan(confirmSeller.indexOf("sellerCompleted: true"));
    expect(client.match(/sellerCompleted: true/g)).toHaveLength(1);
  });

  it("rimuove il seller demo, la preview Club finta e ogni form o foto locale", () => {
    expect(existsSync(resolve(betaRoot, "_components/DemoSellerFlow.tsx"))).toBeFalse();
    expect(existsSync(resolve(betaRoot, "_components/ClubPreview.tsx"))).toBeFalse();
    const source = betaSource();
    for (const removed of [
      "DemoSellerFlow",
      "ClubPreview",
      'type="file"',
      "URL.createObjectURL",
      "Circolo dei Nebbioli",
      "Bolle d'Italia",
      "Collezionisti in cantina",
      "Vigne vulcaniche",
      "Bordeaux Lovers",
      "Champagne Club",
    ]) {
      expect(source).not.toInclude(removed);
    }
    // Lo storico resta interpretabile ma il nuovo percorso non lo emette più.
    expect(source).not.toInclude('"sell_photo_selected"');
    expect(read("frontend-next/src/lib/market-validation/contract.ts")).toInclude('"sell_photo_selected"');
    expect(read("frontend-next/src/lib/market-validation/admin-analytics.ts")).toInclude('"sell_photo_selected"');
    const progress = read("frontend-next/src/lib/market-validation/progress.ts");
    expect(progress).not.toInclude("sellerDraft");
    expect(progress).not.toInclude("photoUrl");
  });

  it("apre il vero /community con club_viewed e spiega solo funzioni reali dei Club", () => {
    const hub = read("frontend-next/src/app/beta-test/_components/ValidationHub.tsx");
    const client = read("frontend-next/src/app/beta-test/page-client.tsx");
    expect(hub).toInclude('title: "Club"');
    expect(hub).toInclude("Scopri le community di Vinea: trova Club dedicati a territori, denominazioni, produttori e passioni.");
    expect(hub).toInclude('cta: "Esplora i Club"');
    expect(hub).toInclude('href: "/community"');
    expect(hub).toInclude("onOpen: onClubOpen");
    expect(hub).toInclude("seguire i Club e crearne di nuovi");
    expect(hub).toInclude("quelli chiusi su approvazione");
    expect(hub).not.toInclude("Anteprima Club");
    for (const notYet of ["premium", "a pagamento", "professionist"]) {
      expect(hub.toLocaleLowerCase("it-IT")).not.toInclude(notYet);
    }
    const openClub = client.slice(client.indexOf("const openClub"));
    expect(openClub.indexOf('track("club_viewed", {}, "club_viewed")'))
      .toBeLessThan(openClub.indexOf("clubViewed: true"));
    expect(openClub.slice(0, openClub.indexOf("clubViewed: true"))).toInclude("if (result.ok)");
  });

  it("apre le superfici reali in una nuova scheda lasciando aperta la guida", () => {
    const source = betaSource();
    const links = source.match(/<Link\b[^>]*>/g) ?? [];
    // Hub (Vendi/Club), Anteprima AI, Anteprima Cantina, schermata finale.
    expect(links).toHaveLength(4);
    for (const link of links) {
      expect(link).toInclude('target="_blank"');
      expect(link).toInclude('rel="noopener noreferrer"');
    }
    const destinations = [...source.matchAll(/href(?:=|: )"([^"]+)"/g)].map((match) => match[1]);
    expect([...new Set(destinations)].sort()).toEqual(REAL_DESTINATIONS);
    for (const navigation of ["useRouter", "router.push", "window.open", "window.location", "<a "]) {
      expect(source).not.toInclude(navigation);
    }
  });

  it("offre «Continua a esplorare Vinea» solo dopo beta_completed, senza condizionarlo", () => {
    const complete = read("frontend-next/src/app/beta-test/_components/ValidationComplete.tsx");
    const client = read("frontend-next/src/app/beta-test/page-client.tsx");
    const link = complete.match(/<Link\b[^>]*>/g) ?? [];
    expect(link).toHaveLength(1);
    expect(link[0]).toInclude('href="/"');
    expect(link[0]).toInclude('target="_blank"');
    expect(complete).toInclude("Continua a esplorare Vinea");
    expect(complete).not.toInclude("track(");
    expect(complete).not.toInclude("MarketValidationTrack");
    expect(complete).not.toInclude("onClick");
    // La schermata finale si monta solo dopo l'evento registrato.
    expect(client.indexOf('track("beta_completed"')).toBeLessThan(client.indexOf('setScreen("complete")'));
    expect(client).toInclude('if (screen === "complete") return <ValidationComplete />;');
  });

  it("dice che solo l'acquisto è simulato e non promette più che tutto lo sia", () => {
    const hub = read("frontend-next/src/app/beta-test/_components/ValidationHub.tsx");
    const client = read("frontend-next/src/app/beta-test/page-client.tsx");
    expect(hub).not.toInclude("È tutto simulato");
    expect(hub).not.toInclude("Le foto scelte restano nel browser");
    expect(hub).toInclude("Il percorso di acquisto è simulato e non crea ordini o pagamenti.");
    expect(hub).toInclude("aprono le vere funzioni di Vinea");
    expect(hub).toInclude("pubblicare un annuncio reale per completare il test.");
    expect(client).not.toInclude("Nessuna operazione comporterà");
  });

  it("usa i tre asset AI statici e la mappatura source full/detail", () => {
    for (const asset of [
      "frontend-next/public/images/market-validation/ai/mv-ai-background-source.jpg",
      "frontend-next/public/images/market-validation/ai/mv-ai-result-full.png",
      "frontend-next/public/images/market-validation/ai/mv-ai-result-detail.png",
    ]) {
      expect(existsSync(resolve(root, asset))).toBeTrue();
    }
    const ai = read("frontend-next/src/app/beta-test/_components/StaticAiPreview.tsx");
    expect(ai).toInclude('sourcePosition: "left center"');
    expect(ai).toInclude('src: "/images/market-validation/ai/mv-ai-result-full.png"');
    expect(ai).toInclude('sourcePosition: "right center"');
    expect(ai).toInclude('src: "/images/market-validation/ai/mv-ai-result-detail.png"');
    expect(ai).toInclude("Bottiglia intera");
    expect(ai).toInclude("Primo piano / dettaglio");
    expect(ai).toInclude("Mi interessa questa funzione");
    expect(ai).toInclude("non chiama provider AI");
    expect(ai.indexOf('track("ai_preview_viewed"')).toBeGreaterThan(0);
    expect(ai.indexOf('track("ai_interest_clicked"')).toBeLessThan(ai.indexOf("onInterest();"));
  });

  it("spiega Sommelier, catalogazione, abbinamenti e foto come funzione in sviluppo", () => {
    const ai = read("frontend-next/src/app/beta-test/_components/StaticAiPreview.tsx");
    // Le costanti precedono il JSX: l'ordine visivo si verifica dentro il render.
    const render = ai.slice(ai.indexOf("return (\n    <section"));
    const renderOrder = [
      ">Vinea AI<",
      "L&apos;intelligenza artificiale in Vinea supporta diverse parti dell&apos;esperienza.",
      "Come Vinea usa l&apos;AI",
      "AI_SURFACES.map",
      "Foto e presentazione",
      "Anteprima foto AI",
      "Anteprima di una funzione in sviluppo",
      "adattando lo sfondo al tipo di scatto",
      "grid gap-5 rounded-3xl",
    ].map((text) => render.indexOf(text));
    expect(renderOrder.every((position) => position >= 0)).toBeTrue();
    expect([...renderOrder].sort((a, b) => a - b)).toEqual(renderOrder);

    const surfaces = ['title: "Sommelier AI"', 'title: "Assistente AI per la bottiglia"', 'title: "Abbinamenti AI"']
      .map((title) => ai.indexOf(title));
    expect(surfaces.every((position) => position > 0)).toBeTrue();
    expect([...surfaces].sort((a, b) => a - b)).toEqual(surfaces);
    expect(ai).toInclude("puoi fare domande, approfondire bottiglie e orientarti tra vini, caratteristiche e abbinamenti");
    expect(ai).toInclude("pulsante Sommelier in basso a destra");
    expect(ai).toInclude("suggerendo le informazioni da inserire");
    expect(ai).toInclude("non pubblica nulla da solo e ogni campo resta sotto il tuo controllo");
    expect(ai).toInclude("possibili abbinamenti tra vino e cibo");
    expect(ai).toInclude("«Per abbinamento cibo»");
    expect(read("frontend-next/src/app/esplora/page-client.tsx")).toInclude(">Per abbinamento cibo<");
    expect(ai).toInclude('{ href: "/vendi", label: "Provalo in Vendi" }');
    expect(ai).toInclude('{ href: "/esplora", label: "Scopri gli abbinamenti" }');
    // Il Sommelier è globale nel Layout: nessuna rotta inventata per lui.
    const sommelier = ai.slice(ai.indexOf('surface: "sommelier"'), ai.indexOf('surface: "catalogazione"'));
    expect(sommelier).not.toInclude("link:");
    expect(read("frontend-next/src/components/vinea/Layout.tsx")).toInclude("AI_UI.sommelier && <SommelierChat />");
    // Le CTA seguono le stesse flag che montano la superficie reale.
    expect(ai).toInclude("link && AI_UI[surface]");
    expect(ai).toInclude('import type { SuperficieIA } from "@/lib/phase10/etichette-ia";');
  });

  it("collega tutti gli eventi della nuova UX alla porta server MV1 esistente", () => {
    const source = betaSource();
    for (const eventName of [
      "marketplace_viewed",
      "demo_listing_viewed",
      "favorite_added",
      "checkout_started",
      "shipping_cost_viewed",
      "checkout_beta_completed",
      "sell_started",
      "sell_completed",
      "ai_preview_viewed",
      "ai_interest_clicked",
      "club_viewed",
      "beta_completed",
    ]) {
      expect(source).toInclude(`"${eventName}"`);
    }
    const actions = read("frontend-next/src/app/beta-test/actions.ts");
    expect(actions).toInclude("marketValidationAbilitataServer()");
    expect(actions).toInclude("createMarketValidationService(client).recordEvent(");
    expect(actions).toInclude("parseMarketValidationEventMetadata(");
    expect(actions).not.toInclude("beta_validation_event_record");
  });

  it("importa soltanto moduli MV, UI e tipi: nessun dominio con side effect", () => {
    const allowed = [
      /^\.{1,2}\//,
      /^@\/components\/ui\//,
      /^@\/components\/vinea\/WineThumbnail$/,
      /^@\/config\/features$/,
      // Solo etichette e tipi della Cantina per l'anteprima statica.
      /^@\/data\/cellar$/,
      /^@\/lib\/market-validation\//,
      /^@\/lib\/phase10\/etichette-ia$/,
      /^@\/lib\/supabase\/server$/,
      /^@\/services\/market-validation-service$/,
      /^@\/services\/types$/,
      /^@supabase\/supabase-js$/,
      /^lucide-react$/,
      /^next(\/(image|link|navigation|server))?$/,
      /^react$/,
    ];
    for (const file of productionSources()) {
      const source = readFileSync(file, "utf8");
      expect(source).not.toMatch(/\bimport\s*\(/);
      expect(source).not.toMatch(/\brequire\s*\(/);
      for (const [, specifier] of source.matchAll(/from "([^"]+)"/g)) {
        if (!allowed.some((pattern) => pattern.test(specifier))) {
          throw new Error(`${relative(root, file)} importa ${specifier}`);
        }
      }
    }
  });

  it("non invoca servizi di pagamento, ordini, annunci, Club, AI, storage o logistica", () => {
    const source = productionSources()
      .map((file) => readFileSync(file, "utf8"))
      .join("\n")
      .toLocaleLowerCase("en-US");
    for (const forbidden of [
      "payment-service",
      "paymentservice",
      "order-service",
      "orderservice",
      "listing-service",
      "listingservice",
      "logistics",
      "shipmentprovider",
      "club-service",
      "clubservice",
      "ai-service",
      "aiservice",
      "functions.invoke",
      "photoroom",
      "storage.from(",
      ".upload(",
      "payments-checkout",
      "balance_prelievo",
      "payout",
      "stripe",
      "bottle_unit",
      "inventory",
    ]) {
      expect(source).not.toInclude(forbidden);
    }
    for (const destination of ["/checkout/", "/annuncio/", "/ordine/", "/cantina/"]) {
      expect(source).not.toInclude(`href="${destination}`);
      expect(source).not.toInclude(`href: "${destination}`);
    }
    // La vera Cantina è un semplice link, e soltanto dall'anteprima Cantina.
    for (const file of productionSources()) {
      const text = readFileSync(file, "utf8");
      if (text.includes('href="/cantina"') || text.includes('href: "/cantina"')) {
        expect(relative(betaRoot, file)).toBe(join("_components", "CellarPreview.tsx"));
      }
    }
  });

  it("lascia immutata la migrazione MV1 e non crea migrazioni MV2", () => {
    const migration = read("supabase/migrations/20261003170000_market_validation_foundation.sql");
    expect(migration).toInclude("create function public.beta_validation_event_record(");
    expect(migration).not.toInclude("mv2");
    // `readdirSync` segue l'ordine della directory, che su ext4 in CI non è
    // quello alfabetico di NTFS: l'inventario va ordinato prima di confrontarlo.
    const inventario = readdirSync(resolve(root, "supabase/migrations"))
      .filter((name) => name.includes("market_validation"))
      .sort();
    expect(inventario).toEqual([
      "20261003170000_market_validation_foundation.sql",
      "20261006160000_market_validation_admin_analytics.sql",
    ]);
  });
});
