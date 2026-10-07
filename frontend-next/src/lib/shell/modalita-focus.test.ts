import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { PERCORSI_FOCUS, modalitaFocus } from "@/lib/shell/modalita-focus";
import {
  NAV_MOBILE_AUTENTICATA,
  NAV_MOBILE_OSPITE,
  navMobile,
} from "@/lib/shell/navigazione-mobile";

const progetto = join(import.meta.dir, "../../..");
const layout = readFileSync(join(progetto, "src/components/vinea/Layout.tsx"), "utf8");
const navigazione = readFileSync(join(progetto, "src/lib/shell/navigazione-mobile.ts"), "utf8");

describe("modalità focus della guida Market Validation", () => {
  it("vale su /beta-test e sulle sue sottorotte", () => {
    expect(PERCORSI_FOCUS).toEqual(["/beta-test"]);
    expect(modalitaFocus("/beta-test")).toBe(true);
    expect(modalitaFocus("/beta-test/qualcosa")).toBe(true);
  });

  it("non vale sulle normali pagine di Vinea né su rotte che somigliano soltanto", () => {
    for (const pathname of [
      "/",
      "/home",
      "/esplora",
      "/vendi",
      "/community",
      "/cantina",
      "/account",
      "/admin/beta-validation",
      "/beta-testing",
      "/beta",
    ]) {
      expect(modalitaFocus(pathname)).toBe(false);
    }
    expect(modalitaFocus(null)).toBe(false);
    expect(modalitaFocus(undefined)).toBe(false);
  });

  it("navMobile() resta quella di prima: la guida non è un filtro delle voci", () => {
    expect(navMobile(true)).toBe(NAV_MOBILE_AUTENTICATA);
    expect(navMobile(false)).toBe(NAV_MOBILE_OSPITE);
    expect(navigazione).not.toInclude("beta-test");
    expect(navigazione).not.toInclude("modalitaFocus");
  });
});

describe("la shell applica la modalità focus", () => {
  it("ricava il focus dal pathname con una sola chiamata", () => {
    expect(layout).toInclude('import { modalitaFocus } from "@/lib/shell/modalita-focus";');
    expect(layout).toInclude("const focus = modalitaFocus(pathname);");
    expect(layout.match(/modalitaFocus\(/g)).toHaveLength(1);
  });

  it("non disegna la barra mobile in focus e la lascia identica altrove", () => {
    const guardia = layout.indexOf("{!focus && (", layout.indexOf("</footer>"));
    const barra = layout.indexOf('data-testid="mobile-nav"');
    expect(guardia).toBeGreaterThan(-1);
    expect(barra).toBeGreaterThan(guardia);
    // Dentro la guardia la barra è quella di sempre.
    const blocco = layout.slice(guardia, layout.indexOf("</nav>", barra));
    expect(blocco).toInclude("{vociMobile.map((n) => {");
    expect(blocco).toInclude("grid-cols-5");
    expect(blocco).toInclude("pb-safe");
  });

  it("non disegna la navigazione desktop in focus e lascia l'header", () => {
    const guardia = layout.indexOf("{!focus && (");
    const desktop = layout.indexOf('data-testid="desktop-nav"');
    expect(guardia).toBeGreaterThan(layout.indexOf('data-testid="brand-logo-link"'));
    expect(desktop).toBeGreaterThan(guardia);
    expect(layout.slice(guardia, desktop)).not.toInclude("</nav>");
    expect(layout.indexOf('data-testid="app-header"')).toBeLessThan(guardia);
    // Navigazione desktop, azioni dell'header e barra mobile.
    expect(layout.match(/\{!focus && \(/g)).toHaveLength(3);
  });

  it("in focus il marchio resta visibile ma non è un link", () => {
    const ramo = layout.slice(layout.indexOf("{focus ? ("), layout.indexOf(") : (", layout.indexOf("{focus ? (")));
    expect(ramo).toInclude('data-testid="brand-logo-static"');
    expect(ramo).toInclude("<Marchio />");
    expect(ramo).not.toInclude("<Link");
    expect(ramo).not.toInclude("href");
    // Fuori dalla guida il marchio porta alla home come prima.
    const link = layout.slice(layout.indexOf(") : (", layout.indexOf("{focus ? (")));
    expect(link.slice(0, link.indexOf("</Link>"))).toInclude(
      '<Link href="/" className="flex items-center gap-2.5" data-testid="brand-logo-link">',
    );
    expect(layout.match(/data-testid="beta-badge"/g)).toHaveLength(1);
  });

  it("in focus non disegna nessuna azione dell'header", () => {
    const azioni = layout.indexOf('className="ml-auto flex items-center gap-2"');
    const guardia = layout.lastIndexOf("{!focus && (", azioni);
    expect(guardia).toBeGreaterThan(layout.indexOf("</nav>", layout.indexOf('data-testid="desktop-nav"')));
    // Tra la guardia e il contenitore delle azioni c'è solo il contenitore.
    expect(layout.slice(guardia + "{!focus && (".length, azioni).trim()).toBe("<div");
    const fine = layout.indexOf("</header>");
    const blocco = layout.slice(azioni, fine);
    for (const azione of ["cta-register", "header-search-link", "<HeaderInboxActions />", "header-avatar-link", "<DemoSwitch"]) {
      expect(blocco).toInclude(azione);
    }
  });

  it("in focus non monta il Sommelier, che non fa parte della guida", () => {
    expect(layout).toInclude("{!focus && AI_UI.sommelier && <SommelierChat />}");
    expect(layout.match(/<SommelierChat \/>/g)).toHaveLength(1);
  });

  it("in focus apre i rimandi legali del footer in una nuova scheda, altrove come prima", () => {
    expect(layout).toInclude(
      'const legaleInFocus = focus\n    ? ({ target: "_blank", rel: "noopener noreferrer" } as const)\n    : {};',
    );
    const footer = layout.slice(layout.indexOf("<footer"), layout.indexOf("</footer>"));
    const link = footer.match(/<Link [^>]*>/g) ?? [];
    expect(link.map((tag) => tag.match(/href="([^"]+)"/)?.[1])).toEqual([
      "/legale",
      "/legale#privacy",
      "/legale#termini",
      "/legale#cookie",
    ]);
    for (const tag of link) expect(tag).toInclude("{...legaleInFocus}");
    // Nessun altro target nel footer: fuori dalla guida lo spread è vuoto.
    expect(footer).not.toInclude("target=");
  });

  it("toglie lo spazio della barra inferiore solo in focus", () => {
    expect(layout).toInclude(
      '${focus ? "" : "pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-0"}',
    );
    expect(layout).toInclude('data-focus-mode={focus ? "true" : undefined}');
  });
});
