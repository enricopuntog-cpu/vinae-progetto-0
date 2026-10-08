import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { extname, join, relative, resolve } from "node:path";
import { MARKET_VALIDATION_CLUB_DEMOS } from "@/lib/market-validation/club-demo";
import {
  MARKET_VALIDATION_SELL_DEMO_BOTTLES,
  MARKET_VALIDATION_SELL_DEMO_DESTINATIONS,
} from "@/lib/market-validation/sell-demo";

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
    resolve(root, "frontend-next/src/services/market-validation-questionnaire-service.ts"),
  ].filter((file) => !file.endsWith(".test.ts"));

const betaSource = () =>
  sourceFiles(betaRoot)
    .filter((file) => !file.endsWith(".test.ts"))
    .map((file) => readFileSync(file, "utf8"))
    .join("\n");

// Con MARKET_VALIDATION_QUESTIONNAIRE_V2_ENABLED spento /beta-test serve la guida
// approvata in page-client-legacy.tsx; acceso, il client QV2 la incorpora tra PRE e
// POST. Le regole della guida valgono quindi per entrambi i client.
const LEGACY_CLIENT = "frontend-next/src/app/beta-test/page-client-legacy.tsx";
const QV2_CLIENT = "frontend-next/src/app/beta-test/page-client.tsx";
const GUIDE_CLIENTS = [LEGACY_CLIENT, QV2_CLIENT];

const component = (name: string) => read(`frontend-next/src/app/beta-test/_components/${name}.tsx`);

// Le schermate interne che hanno un ritorno: tutte con lo stesso «← Indietro».
const SCREENS_WITH_BACK = [
  "DemoMarketplace",
  "DemoListingDetail",
  "DemoCheckout",
  "SellDemo",
  "StaticAiPreview",
  "ClubDemo",
  "CellarPreview",
];

describe("Market Validation MV2 UI contract", () => {
  it.each(GUIDE_CLIENTS)("resta single-route con Vendi e Club come schermate interne della guida (%s)", (clientPath) => {
    const client = read(clientPath);
    const hub = component("ValidationHub");
    expect(client).toInclude("MarketValidationScreen");
    expect(client).toInclude(
      clientPath === LEGACY_CLIENT
        ? 'useState<MarketValidationScreen>("hub")'
        : "useState<MarketValidationScreen>(() => questionnaireStage(questionnaire))",
    );
    expect(client).not.toInclude("useRouter");
    expect(client).not.toInclude("router.push");
    expect(client).not.toInclude("<Link");
    expect(client).toInclude('if (screen === "seller")');
    expect(client).toInclude('if (screen === "club")');
    expect(client).toInclude("<SellDemo");
    expect(client).toInclude("<ClubDemo");
    const unionStart = hub.indexOf("export type MarketValidationScreen");
    const screenUnion = hub.slice(unionStart, hub.indexOf(";", unionStart));
    for (const screen of ["hub", "marketplace", "detail", "checkout", "seller", "ai", "club", "cellar", "complete"]) {
      expect(screenUnion).toInclude(`"${screen}"`);
    }

    const routes = sourceFiles(resolve(root, "frontend-next/src/app/beta-test"))
      .filter((file) => /[\\/]page\.tsx$/.test(file));
    expect(routes.map((file) => relative(betaRoot, file))).toEqual(["page.tsx"]);
  });

  it("risolve lo shipping sul server e completa solo dopo gli eventi hard-gated", () => {
    const page = read("frontend-next/src/app/beta-test/page.tsx");
    const legacy = read(LEGACY_CLIENT);
    const qv2 = read(QV2_CLIENT);
    const checkout = component("DemoCheckout");
    expect(page).toInclude("marketValidationShippingFeeCents()");
    expect(page).toInclude("shippingFeeCents=");
    expect(legacy.indexOf('track("beta_completed"')).toBeGreaterThan(0);
    expect(legacy.indexOf('track("beta_completed"')).toBeLessThan(legacy.indexOf('setScreen("complete")'));
    // QV2: beta_completed registrato apre il POST; GRAZIE solo dopo finish_post.
    expect(qv2.indexOf('track("beta_completed"')).toBeGreaterThan(0);
    expect(qv2.indexOf('track("beta_completed"')).toBeLessThan(qv2.indexOf('setScreen("post-questionnaire")'));
    expect(qv2.indexOf("finishQuestionnairePost(session.sessionId")).toBeLessThan(qv2.indexOf('setScreen("complete")'));
    expect(checkout.indexOf('track(\n      "checkout_beta_completed"')).toBeLessThan(checkout.indexOf("onCompleted();"));
    expect(checkout).toInclude("Non è stato creato alcun ordine, pagamento");
  });

  it.each(GUIDE_CLIENTS)("mantiene il percorso Acquista demo: marketplace, dettaglio, preferiti e checkout (%s)", (clientPath) => {
    const client = read(clientPath);
    for (const name of ["DemoMarketplace", "DemoListingDetail", "DemoCheckout", "ValidationComplete"]) {
      expect(existsSync(resolve(betaRoot, `_components/${name}.tsx`))).toBeTrue();
      expect(client).toInclude(`<${name}`);
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

  it("conserva struttura e ordine delle 4 card, presentate come step e approfondimenti", () => {
    const hub = component("ValidationHub");
    for (const fixed of [
      "Hub tester",
      "Prova Vinea",
      "Test {participantCode}",
      "Step del test",
      "{stepsDone} di 2 completati",
      "Completa i due step, Acquista e Vendi, per raggiungere il traguardo.",
      "AI, Club e Cantina sono approfondimenti da scoprire quando vuoi.",
      "Completato",
      "marketValidationCanComplete(progress)",
      "disabled={!completed || completing}",
      "Raggiungi il traguardo",
      "Prossimo passo: ",
      "min-h-12",
      "sm:grid-cols-2",
    ]) {
      expect(hub).toInclude(fixed);
    }
    // Nessuna parola di obbligo nell'hub.
    for (const removed of ["Obbligatorio", "obbligatori", "Facoltativo", "facoltativi", "Percorsi obbligatori"]) {
      expect(hub).not.toInclude(removed);
    }
    const titles = ['title: "Acquista"', 'title: "Vendi"', 'title: "Anteprima AI"', 'title: "Club"'];
    const positions = titles.map((title) => hub.indexOf(title));
    expect(positions.every((position) => position > 0)).toBeTrue();
    expect([...positions].sort((a, b) => a - b)).toEqual(positions);
    const areasStart = hub.indexOf("const areas");
    const cards = hub.slice(areasStart, hub.indexOf("return (", areasStart));
    expect(cards.match(/badge: "Step 1"/g)).toHaveLength(1);
    expect(cards.match(/badge: "Step 2"/g)).toHaveLength(1);
    expect(cards.match(/badge: "Approfondimento"/g)).toHaveLength(2);
    expect(cards.indexOf('badge: "Step 1"')).toBeGreaterThan(cards.indexOf('title: "Acquista"'));
    expect(cards.indexOf('badge: "Step 2"')).toBeGreaterThan(cards.indexOf('title: "Vendi"'));
    expect(cards.indexOf('badge: "Step 2"')).toBeLessThan(cards.indexOf('title: "Anteprima AI"'));
    // Ogni card apre una schermata interna: nessun link, nessuna nuova scheda.
    expect(hub).not.toInclude("next/link");
    expect(hub).not.toInclude("href");
    expect(hub).not.toInclude("target=");
    expect(hub).not.toInclude("ExternalLink");
  });

  it.each(GUIDE_CLIENTS)("aumenta la leggibilità mobile dell'hub senza testi sotto il corpo base (%s)", (clientPath) => {
    const hub = component("ValidationHub");
    const body = hub.slice(hub.indexOf("function CardBody"));
    expect(body).toInclude('className="mt-1 text-base leading-6 text-muted-foreground">{area.text}</p>');
    expect(body).not.toInclude("text-xs");
    expect(hub).toInclude("text-base leading-7 text-muted-foreground");
    const client = read(clientPath);
    expect(client).toInclude("text-base leading-7 text-muted-foreground md:text-lg");
  });

  it("usa un unico «← Indietro» a sinistra in tutte le schermate della guida", () => {
    const back = component("DemoBackButton");
    expect(back).toInclude("<ArrowLeft");
    expect(back).toInclude("Indietro");
    expect(back).toInclude("self-start");
    for (const name of SCREENS_WITH_BACK) {
      const source = component(name);
      expect(source).toInclude('import { DemoBackButton } from "./DemoBackButton";');
      expect(source).toInclude("<DemoBackButton onBack=");
      expect(source).not.toMatch(/>\s*Hub\s*</);
    }
    expect(betaSource()).not.toInclude("← Torna");
  });

  it.each(GUIDE_CLIENTS)("Vendi è una demo interna che si completa solo sulla conferma finale (%s)", (clientPath) => {
    const hub = component("ValidationHub");
    const client = read(clientPath);
    const sell = component("SellDemo");
    const seller = hub.slice(hub.indexOf('key: "seller"'), hub.indexOf('key: "ai"'));
    expect(seller).toInclude('screen: "seller"');
    expect(seller).toInclude('title: "Vendi"');
    expect(seller).toInclude("Aggiungi una bottiglia con l'aiuto dell'AI e scegli se tenerla in Cantina o metterla in vendita.");

    // Apertura: solo `sell_started`, mai il completamento.
    const start = sell.slice(sell.indexOf("useEffect(() => {"), sell.indexOf("}, [track]);"));
    expect(start).toInclude('track("sell_started", {}, "sell_started")');
    expect(start).not.toInclude("sell_completed");
    expect(start).not.toInclude("onCompleted");

    // Completamento: solo dopo la conferma esplicita e l'evento registrato.
    const confirm = sell.slice(sell.indexOf("const confirm = async"), sell.indexOf("if (showSuccess)"));
    expect(confirm).toInclude("if (pending || !bottle || !aiFilled || !destination) return;");
    expect(confirm.indexOf('track("sell_completed", {}, "sell_completed")')).toBeGreaterThan(0);
    expect(confirm.indexOf('track("sell_completed", {}, "sell_completed")')).toBeLessThan(confirm.indexOf("if (!result.ok)"));
    expect(confirm.indexOf("if (!result.ok)")).toBeLessThan(confirm.indexOf("onCompleted();"));
    expect(sell.match(/onCompleted\(\)/g)).toHaveLength(1);
    expect(sell).toInclude("onClick={confirm}");
    expect(sell).toInclude("Conferma la simulazione");
    expect(client.match(/sellerCompleted: true/g)).toHaveLength(1);
    expect(client).toInclude("onCompleted={markSellerCompleted}");

    // Nessuna conferma «l'ho provato» né apertura del vero /vendi.
    for (const removed of ["Sì, l'ho provato", "Hai provato il percorso di vendita?", "sellerOpened", "onSellerConfirm", "Prova la vendita"]) {
      expect(betaSource()).not.toInclude(removed);
    }
  });

  it("la demo Vendi ricalca /vendi: foto, assistente AI, destinazione e riepilogo, senza upload", () => {
    const sell = component("SellDemo");
    const data = read("frontend-next/src/lib/market-validation/sell-demo.ts");
    for (const step of ["Scegli la foto della bottiglia", "L'assistente AI compila per te", "Come vuoi usare questa bottiglia?", "Riepilogo"]) {
      expect(sell).toInclude(step);
    }
    expect(data).toInclude('"Foto",\n  "Assistente AI",\n  "Destinazione",\n  "Riepilogo",');
    expect(sell).toInclude("non pubblica nulla da solo");
    expect(sell).toInclude("in questa demo nessuna AI analizza la foto");
    // Le tre destinazioni hanno le stesse parole delle opzioni di /vendi.
    const vendi = read("frontend-next/src/app/vendi/page-client.tsx");
    expect(MARKET_VALIDATION_SELL_DEMO_DESTINATIONS.map((option) => option.status)).toEqual([
      "privata",
      "cantina_pubblica",
      "in_vendita",
    ]);
    for (const option of MARKET_VALIDATION_SELL_DEMO_DESTINATIONS) {
      expect(vendi).toInclude(option.title);
      expect(vendi).toInclude(option.text);
    }
    for (const bottle of MARKET_VALIDATION_SELL_DEMO_BOTTLES) {
      expect(bottle.id.startsWith("mv_sell_")).toBeTrue();
      expect(bottle.example).toBeTrue();
      expect(existsSync(resolve(root, "frontend-next/public", `.${bottle.image}`))).toBeTrue();
    }
    for (const forbidden of ['type="file"', "URL.createObjectURL", "<form", "<Input", "<Textarea", '"sell_photo_selected"', "FileReader"]) {
      expect(sell).not.toInclude(forbidden);
    }
  });

  it.each(GUIDE_CLIENTS)("Club è una demo interna con club_viewed e soltanto funzioni reali dei Club (%s)", (clientPath) => {
    const hub = component("ValidationHub");
    const client = read(clientPath);
    const club = component("ClubDemo");
    const data = read("frontend-next/src/lib/market-validation/club-demo.ts");
    const card = hub.slice(hub.indexOf('key: "club"'), hub.indexOf("];", hub.indexOf('key: "club"')));
    expect(card).toInclude('screen: "club"');
    expect(card).toInclude("Scopri le community di Vinea dedicate a territori, denominazioni, produttori e passioni.");

    expect(club.indexOf('track("club_viewed", {}, "club_viewed")')).toBeGreaterThan(0);
    const viewed = club.slice(club.indexOf('track("club_viewed"'), club.indexOf("onViewed();"));
    expect(viewed).toInclude("if (active && result.ok)");
    expect(client).toInclude("onViewed={markClubViewed}");
    expect(client.match(/clubViewed: true/g)).toHaveLength(1);

    for (const fact of [
      "un territorio, a una denominazione, a un produttore o a una passione",
      "Aperti o su approvazione",
      "Nei Club aperti entri subito",
      "invii una richiesta che i gestori del Club valutano",
      "Discussioni verticali",
      "Proponi un Club con nome, descrizione, regole e copertina: diventa pubblico dopo la revisione di Vinea.",
      "non ti iscrivi, non pubblichi e non segui nessun Club",
    ]) {
      expect(club).toInclude(fact);
    }
    // Accesso e tipi di post sono quelli dei Club reali.
    const types = read("frontend-next/src/services/types.ts");
    expect(types).toInclude('export type ClubAccessType = "aperto" | "chiuso";');
    for (const kind of ["discussione", "domanda", "degustazione", "consiglio"]) {
      expect(types.slice(types.indexOf("export type ClubPostTipo"))).toInclude(`| "${kind}"`);
    }
    expect(types).toInclude("il Club diventa pubblico soltanto dopo la");
    expect(new Set(MARKET_VALIDATION_CLUB_DEMOS.map((demo) => demo.access))).toEqual(new Set(["aperto", "chiuso"]));
    expect(new Set(MARKET_VALIDATION_CLUB_DEMOS.map((demo) => demo.axis))).toEqual(
      new Set(["Territorio", "Denominazione", "Produttore", "Passione"]),
    );
    for (const demo of MARKET_VALIDATION_CLUB_DEMOS) {
      expect(existsSync(resolve(root, "frontend-next/public", `.${demo.cover}`))).toBeTrue();
      expect(demo.example).toBeTrue();
    }
    // Ogni Club, in elenco e nel dettaglio, porta il segno «Esempio»: non sono
    // community reali dichiarate.
    expect(club.match(/<ExampleBadge \/>/g)).toHaveLength(2);
    expect(club).toInclude('data-testid="club-demo-example"');
    for (const source of [club, data, card]) {
      for (const notYet of ["premium", "a pagamento", "abbonament", "professionist"]) {
        expect(source.toLocaleLowerCase("it-IT")).not.toInclude(notYet);
      }
    }
    // Nessun bottone che finga un'iscrizione, un follow o un post.
    for (const fakeAction of ["Unisciti", "Iscriviti", "Segui il Club", "Pubblica", "Richiedi l'ingresso"]) {
      expect(club).not.toInclude(`>${fakeAction}`);
    }
  });

  it("non riusa i nomi della vecchia preview Club né form o foto locali", () => {
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

  it("durante il test non porta mai al sito reale: l'unico link è dopo il traguardo", () => {
    const source = betaSource();
    const links = source.match(/<Link\b[^>]*>/g) ?? [];
    expect(links).toHaveLength(1);
    expect(links[0]).toInclude('href="/"');
    expect(links[0]).toInclude('target="_blank"');
    expect(links[0]).toInclude('rel="noopener noreferrer"');
    const destinations = [...source.matchAll(/href(?:=|: )"([^"]+)"/g)].map((match) => match[1]);
    expect([...new Set(destinations)]).toEqual(["/"]);
    for (const name of ["ValidationHub", ...SCREENS_WITH_BACK]) {
      const screen = component(name);
      expect(screen).not.toInclude("next/link");
      expect(screen).not.toInclude("href");
    }
    for (const navigation of ["useRouter", "router.push", "window.open", "window.location", "<a "]) {
      expect(source).not.toInclude(navigation);
    }
  });

  it("offre «Continua a esplorare Vinea» solo dopo beta_completed, senza condizionarlo", () => {
    const complete = component("ValidationComplete");
    const legacy = read(LEGACY_CLIENT);
    const qv2 = read(QV2_CLIENT);
    const link = complete.match(/<Link\b[^>]*>/g) ?? [];
    expect(link).toHaveLength(1);
    expect(link[0]).toInclude('href="/"');
    expect(link[0]).toInclude('target="_blank"');
    expect(complete).toInclude("Continua a esplorare Vinea");
    expect(complete).not.toInclude("track(");
    expect(complete).not.toInclude("MarketValidationTrack");
    expect(complete).not.toInclude("onClick");
    // La schermata finale si monta solo dopo l'evento registrato.
    expect(legacy.indexOf('track("beta_completed"')).toBeLessThan(legacy.indexOf('setScreen("complete")'));
    expect(legacy).toInclude('if (screen === "complete") return <ValidationComplete />;');
    // QV2: GRAZIE con il codice concluso e il solo comando esplicito
    // «Fai provare Vinea a un'altra persona», fornito dal client.
    expect(qv2).toMatch(/<ValidationComplete\s+qv2\s+participantCode=\{session\.participantCode\}\s+action=\{/);
    expect(qv2).toInclude("<Button onClick={onNewTester}");
    expect(qv2).toInclude("{NEW_TESTER_LABEL}");
  });

  it.each(GUIDE_CLIENTS)("dichiara che tutto il test si svolge nella guida ed è simulato (%s)", (clientPath) => {
    const hub = component("ValidationHub");
    const client = read(clientPath);
    expect(hub).toInclude("Tutto il test si svolge qui ed è una simulazione: non crea ordini,");
    expect(hub).toInclude("pagamenti, annunci o spedizioni reali.");
    expect(hub).not.toInclude("aprono le vere funzioni di Vinea");
    // La landing QV2 dichiara la Beta di ricerca con la copy approvata.
    expect(client).toInclude(clientPath === QV2_CLIENT
      ? "Questa è una Beta di ricerca. Nessun pagamento, vendita o spedizione reale verrà effettuato."
      : "Tutto si svolge qui ed è una simulazione: nessun pagamento,");
    expect(client).not.toInclude("il vero percorso per mettere in vendita");
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
    const ai = component("StaticAiPreview");
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

  it("spiega le quattro aree AI e a cosa servono, senza link al sito", () => {
    const ai = component("StaticAiPreview");
    // Le costanti precedono il JSX: l'ordine visivo si verifica dentro il render.
    const render = ai.slice(ai.indexOf("return (\n    <section"));
    const renderOrder = [
      "<DemoBackButton onBack={onBack} />",
      ">Vinea AI<",
      "L&apos;intelligenza artificiale in Vinea supporta diverse parti dell&apos;esperienza.",
      "Come Vinea usa l&apos;AI",
      "AI_SURFACES.map",
      "A cosa serve.",
      "Foto e presentazione",
      "Anteprima foto AI",
      "Anteprima di una funzione in sviluppo",
      "adattando lo sfondo al tipo di scatto",
      "grid gap-5 rounded-3xl",
    ].map((text) => render.indexOf(text));
    expect(renderOrder.every((position) => position >= 0)).toBeTrue();
    expect([...renderOrder].sort((a, b) => a - b)).toEqual(renderOrder);

    const surfaces = [
      'title: "Sommelier AI"',
      "title: \"Assistente AI per l'annuncio\"",
      'title: "Foto e sfondo AI"',
      'title: "Abbinamenti AI"',
    ].map((title) => ai.indexOf(title));
    expect(surfaces.every((position) => position > 0)).toBeTrue();
    expect([...surfaces].sort((a, b) => a - b)).toEqual(surfaces);
    expect(ai.match(/purpose: "Serve /g)).toHaveLength(4);
    expect(ai).toInclude("puoi fare domande, approfondire bottiglie e orientarti tra vini, caratteristiche e abbinamenti");
    expect(ai).toInclude("suggerendo le informazioni da inserire");
    expect(ai).toInclude("non pubblica nulla da solo e ogni campo resta sotto il tuo controllo");
    expect(ai).toInclude("possibili abbinamenti tra vino e cibo");
    // Lo stato delle tre superfici reali segue le flag che le montano;
    // la foto è dichiarata in sviluppo.
    expect(ai).toInclude('if (surface === "foto") return "Funzione in sviluppo";');
    expect(ai).toInclude('return AI_UI[surface] ? null : "Non ancora attiva in questa versione di Vinea";');
    expect(ai).toInclude('import type { SuperficieIA } from "@/lib/phase10/etichette-ia";');
    // Nessun link alle pagine reali e nessun rimando al launcher, assente nella guida.
    for (const removed of ["next/link", "<Link", "href", "ExternalLink", "Provalo in Vendi", "Scopri gli abbinamenti", "in basso a destra"]) {
      expect(ai).not.toInclude(removed);
    }
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
      /^@\/services\/market-validation-questionnaire-service$/,
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
    for (const destination of ["/checkout", "/annuncio", "/ordine", "/cantina", "/vendi", "/community", "/esplora"]) {
      expect(source).not.toInclude(`href="${destination}`);
      expect(source).not.toInclude(`href: "${destination}`);
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
      "20261008120000_market_validation_questionnaire_qv2.sql",
      "20261008180000_market_validation_qv2_admin.sql",
      "20261008220000_market_validation_qv2_other_options.sql",
    ]);
  });
});
