import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dir, "../../../../..");
const read = (path: string) => readFileSync(resolve(root, path), "utf8");
const route = read("frontend-next/src/app/admin/beta-validation/page.tsx");
const client = read(
  "frontend-next/src/components/vinea/market-validation/MarketValidationAdminClient.tsx",
);
const service = read("frontend-next/src/services/market-validation-admin-service.ts");
const analytics = read("frontend-next/src/lib/market-validation/admin-analytics.ts");
const adminPanel = read("frontend-next/src/components/vinea/moderation/ModerationPanelClient.tsx");
const publicLayout = read("frontend-next/src/components/vinea/Layout.tsx");
const docs = read("docs/market-validation/README.md");
const packageJson = read("frontend-next/package.json");
const qrGenerate = read("frontend-next/scripts/generate-market-validation-qr.mjs");
const qrVerify = read("frontend-next/scripts/verify-market-validation-qr.mjs");

const executable = (source: string) =>
  source
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");

describe("MV3 admin launch readiness", () => {
  it("protegge la route con sessione e ruolo admin reali", () => {
    expect(route).toInclude("await connection();");
    expect(route).toInclude("await client.auth.getUser()");
    expect(route).toInclude('.from("user_roles")');
    expect(route).toInclude('.select("role")');
    expect(route).toInclude("if (!client || !utente) redirect(PERCORSO_ACCESSO);");
    expect(route).toInclude("if (!eAdminReale(ruoli)) notFound();");
    expect(route).toInclude("%2Fadmin%2Fbeta-validation");
    expect(route).not.toMatch(/service_role|SERVICE_ROLE|SUPABASE_SERVICE/);
  });

  it("mantiene la route fuori dagli indici e fornisce il loading segment", () => {
    expect(route).toInclude("robots: { index: false, follow: false }");
    expect(
      read("frontend-next/src/app/admin/beta-validation/loading.tsx"),
    ).toInclude('LoadingBlock label="Caricamento analytics Market Validation"');
  });

  it("espone il link soltanto nell'area admin, mai nella navigazione pubblica", () => {
    expect(adminPanel).toInclude('href="/admin/beta-validation"');
    expect(adminPanel).toInclude("Market Validation");
    expect(publicLayout).not.toInclude("/admin/beta-validation");
  });

  it("rende loading, errore e vuoto con la copy richiesta", () => {
    expect(client).toInclude("<LoadingBlock");
    expect(client).toInclude("<ErrorState");
    expect(client).toInclude('title="Nessun test registrato."');
    expect(client).toInclude("onRetry={() => void load(activeFilter)}");
    expect(client).toInclude("loading && !loaded");
  });

  it("usa funnel step-to-step e tiene la foto fuori dal funnel Seller", () => {
    expect(client).toInclude("step-to-step");
    expect(client).toInclude("percentage(step.value, previous)");
    const sellerStart = client.indexOf("const sellerSteps");
    const sellerEnd = client.indexOf("return (", sellerStart);
    const sellerSteps = client.slice(sellerStart, sellerEnd);
    expect(sellerSteps).toInclude("sellStarted");
    expect(sellerSteps).toInclude("sellCompleted");
    expect(sellerSteps).not.toInclude("sellPhotoSelected");
    expect(client).toInclude("Ha provato ad aggiungere una foto");
  });

  it("dichiara il denominatore AI e la metrica Club sui tester avviati", () => {
    expect(client).toInclude("Interesse dichiarato dopo aver visto la preview");
    expect(client).toInclude("summary.ai.interestRate");
    expect(client).toInclude("summary.club.viewedRate");
    expect(client).toInclude("dei tester avviati");
  });

  it("filtra col parser canonico e mantiene richieste bounded", () => {
    expect(analytics).toInclude("parseMarketValidationParticipantCode(value)");
    expect(client).toInclude("Usa un codice da V001 a V999.");
    expect(service).toInclude("p_limit: options.limit");
    expect(service).toInclude("p_offset: options.offset");
    expect(service).toInclude("MARKET_VALIDATION_EXPORT_PAGE_SIZE");
    expect(service).toInclude("MARKET_VALIDATION_MAX_PARTICIPANTS");
    expect(service).toInclude("Math.min(MARKET_VALIDATION_EXPORT_PAGE_SIZE, remaining)");
  });

  it("non legge tabelle private e usa soltanto le due RPC MV3", () => {
    const code = executable(`${client}\n${service}`);
    expect(code).not.toMatch(/\.from\(|beta_validation_sessions|beta_validation_events/);
    expect(code).toInclude('rpc("beta_validation_admin_summary")');
    expect(code).toInclude('"beta_validation_admin_participants"');
    expect(code).not.toMatch(/capability_hash|session_id|raw_metadata|user_agent|ip_address/);
  });

  it("non introduce tracker esterni, provider AI o domini mutabili", () => {
    const code = executable(`${route}\n${client}\n${service}\n${analytics}`).toLowerCase();
    for (const forbidden of [
      "google analytics",
      "meta pixel",
      "hotjar",
      "mixpanel",
      "segment",
      "posthog",
      "fingerprint",
      "payment-service",
      "order-service",
      "listing-service",
      "club-service",
      "storage.from(",
      ".upload(",
    ]) {
      expect(code).not.toInclude(forbidden);
    }
  });

  it("documenta attivazione a due flag, kill switch e indipendenza", () => {
    expect(docs).toInclude("NEXT_PUBLIC_MARKET_VALIDATION_ENABLED=true");
    expect(docs).toInclude("MARKET_VALIDATION_ENABLED=true");
    expect(docs).toInclude("MARKET_VALIDATION_ENABLED=false");
    for (const independent of ["AI_ENABLED", "PAYMENTS_ENABLED", "shipping operativo", "scritture Club"] ) {
      expect(docs).toInclude(independent);
    }
    expect(docs).toInclude("scansione con smartphone");
  });

  it("versiona QR PNG e SVG deterministici con payload canonico", () => {
    expect(existsSync(resolve(root, "docs/market-validation/vinea-beta-test-qr.png"))).toBeTrue();
    expect(existsSync(resolve(root, "docs/market-validation/vinea-beta-test-qr.svg"))).toBeTrue();
    expect(qrGenerate).toInclude('"https://vineawineclub.com/beta-test"');
    expect(qrGenerate).toInclude("margin: 4");
    expect(qrGenerate).toInclude("width: 1200");
    expect(qrVerify).toInclude("storedPng.equals(expected.png)");
    expect(qrVerify).toInclude("storedSvg !== expected.svg");
    expect(qrVerify).toInclude('decodeQr(storedPng, "PNG")');
    expect(qrVerify).toInclude('decodeQr(svgRaster, "SVG")');
    expect(packageJson).toInclude('"qrcode": "1.5.4"');
    expect(packageJson).toInclude('"jsqr": "1.4.0"');
  });

  it("non aggiunge il QR encoder alle dipendenze runtime", () => {
    const parsed = JSON.parse(packageJson) as {
      dependencies: Record<string, string>;
      devDependencies: Record<string, string>;
    };
    expect(parsed.dependencies.qrcode).toBeUndefined();
    expect(parsed.dependencies.jsqr).toBeUndefined();
    expect(parsed.devDependencies.qrcode).toBe("1.5.4");
    expect(parsed.devDependencies.jsqr).toBe("1.4.0");
  });

  it("mantiene invariata la soglia CI della suite", () => {
    const ci = read(".github/workflows/ci.yml");
    expect(ci).toInclude('MIN_TESTS: "2271"');
  });

  it("versiona esattamente la coppia fondazione + analytics MV", () => {
    const migrations = join(root, "supabase/migrations");
    expect(existsSync(join(migrations, "20261003170000_market_validation_foundation.sql"))).toBeTrue();
    expect(existsSync(join(migrations, "20261006160000_market_validation_admin_analytics.sql"))).toBeTrue();
  });
});
