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

describe("Market Validation MV2 UI contract", () => {
  it("resta single-route e usa soltanto navigazione interna locale", () => {
    const client = read("frontend-next/src/app/beta-test/page-client.tsx");
    expect(client).toInclude("MarketValidationScreen");
    expect(client).toInclude('useState<MarketValidationScreen>("hub")');
    expect(client).not.toInclude("useRouter");
    expect(client).not.toInclude("router.push");
    expect(client).not.toInclude("<Link");

    const routes = sourceFiles(resolve(root, "frontend-next/src/app/beta-test"))
      .filter((file) => /[\\/]page\.tsx$/.test(file));
    expect(routes.map((file) => relative(betaRoot, file))).toEqual(["page.tsx"]);
  });

  it("risolve lo shipping sul server e completa solo dopo gli eventi hard-gated", () => {
    const page = read("frontend-next/src/app/beta-test/page.tsx");
    const client = read("frontend-next/src/app/beta-test/page-client.tsx");
    const checkout = read("frontend-next/src/app/beta-test/_components/DemoCheckout.tsx");
    const seller = read("frontend-next/src/app/beta-test/_components/DemoSellerFlow.tsx");
    expect(page).toInclude("marketValidationShippingFeeCents()");
    expect(page).toInclude("shippingFeeCents=");
    expect(client.indexOf('track("beta_completed"')).toBeLessThan(client.indexOf('setScreen("complete")'));
    expect(checkout.indexOf('track(\n      "checkout_beta_completed"')).toBeLessThan(checkout.indexOf("onCompleted();"));
    expect(seller.indexOf('track("sell_completed"')).toBeLessThan(seller.indexOf("onCompleted();"));
    expect(checkout).toInclude("Non è stato creato alcun ordine, pagamento");
    expect(seller).toInclude("Nessun annuncio è stato pubblicato");
  });

  it("espone hub, stati, touch target e progressione obbligatoria accessibile", () => {
    const hub = read("frontend-next/src/app/beta-test/_components/ValidationHub.tsx");
    expect(hub).toInclude("Acquisto e vendita sono obbligatori. AI e Club sono facoltativi.");
    expect(hub).toInclude("marketValidationCanComplete(progress)");
    expect(hub).toInclude("disabled={!completed || completing}");
    expect(hub).toInclude("Completa il test");
    expect(hub).toInclude("min-h-12");
    expect(hub).toInclude("sm:grid-cols-2");
    expect(hub).toInclude("Completato");
  });

  it("mantiene preferiti e foto locali e non persiste il form venditore", () => {
    const client = read("frontend-next/src/app/beta-test/page-client.tsx");
    const seller = read("frontend-next/src/app/beta-test/_components/DemoSellerFlow.tsx");
    const progress = read("frontend-next/src/lib/market-validation/progress.ts");
    expect(client).toInclude("favoriteDemoIds");
    expect(seller).toInclude("URL.createObjectURL(file)");
    expect(seller).toInclude("revokeMarketValidationPhotoUrl");
    expect(seller).toInclude("Zero upload");
    expect(progress).not.toInclude("sellerDraft");
    expect(progress).not.toInclude("photoUrl");
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
    expect(ai).toInclude("non chiama provider AI");
    expect(ai.indexOf('track("ai_interest_clicked"')).toBeLessThan(ai.indexOf("onInterest();"));
  });

  it("collega tutti gli eventi MV2 alla porta server MV1 esistente", () => {
    const source = sourceFiles(betaRoot).map((file) => readFileSync(file, "utf8")).join("\n");
    for (const eventName of [
      "marketplace_viewed",
      "demo_listing_viewed",
      "favorite_added",
      "checkout_started",
      "shipping_cost_viewed",
      "checkout_beta_completed",
      "sell_started",
      "sell_photo_selected",
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

  it("non importa o invoca domini con side effect fuori da MV", () => {
    const files = [
      ...sourceFiles(betaRoot),
      ...sourceFiles(marketValidationRoot),
      resolve(root, "frontend-next/src/services/market-validation-service.ts"),
    ].filter((file) => !file.endsWith(".test.ts"));
    const source = files.map((file) => readFileSync(file, "utf8")).join("\n");
    for (const forbidden of [
      "payment-service",
      "order-service",
      "listing-service",
      "logistics-service",
      "club-service",
      "AiService",
      "PhotoRoom",
      "storage.from(",
      ".upload(",
      "payments-checkout",
      "balance_prelievo",
      "payout",
      "stripe",
    ]) {
      expect(source.toLocaleLowerCase("en-US")).not.toInclude(forbidden.toLocaleLowerCase("en-US"));
    }
    for (const destination of ["/checkout/", "/vendi", "/annuncio/", "/esplora", "/community"]) {
      expect(source).not.toInclude(`href="${destination}`);
      expect(source).not.toInclude(`push("${destination}`);
    }
  });

  it("lascia immutata la migrazione MV1 e non crea migrazioni MV2", () => {
    const migration = read("supabase/migrations/20261003170000_market_validation_foundation.sql");
    expect(migration).toInclude("create function public.beta_validation_event_record(");
    expect(migration).not.toInclude("mv2");
    expect(readdirSync(resolve(root, "supabase/migrations")).filter((name) => name.includes("market_validation"))).toEqual([
      "20261003170000_market_validation_foundation.sql",
      "20261006160000_market_validation_admin_analytics.sql",
    ]);
  });
});
