/**
 * Pagine di errore e di pagina non trovata (VPM-018-UX-A11Y-01, GAP-005).
 * Il percorso nel browser (URL inesistente, errore forzato) è in
 * `e2e/pagine-di-errore.e2e.ts`.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { renderToStaticMarkup } from "react-dom/server";
import { ErroreDiPagina, impronta } from "@/components/vinea/ErroreDiPagina";
import ErroreApplicazione from "./error";
import NonTrovato from "./not-found";
import ErroreGlobale from "./global-error";

const testo = (html: string) => html.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
const sorgente = (p: string) => readFileSync(join(import.meta.dir, p), "utf8");

class ErroreConDettagli extends Error {
  digest = "abc123";
  constructor() {
    super("password=segreto host=db.interno.vinea SELECT * FROM private.ordini");
    this.stack = "Error: boom\n    at /srv/app/server/chiave-privata.ts:12:3";
  }
}

describe("error.tsx", () => {
  const html = renderToStaticMarkup(<ErroreApplicazione error={new ErroreConDettagli()} retry={() => {}} />);

  it("mostra un solo h1 in italiano, un avviso e le due vie d'uscita", () => {
    expect(html.match(/<h1\b/g)).toHaveLength(1);
    expect(testo(html)).toContain("Qualcosa non ha funzionato");
    // Un solo annuncio: il fuoco sul titolo, non anche role="alert".
    expect(html).not.toContain('role="alert"');
    expect(html).toContain('tabindex="-1"');
    expect(html).toMatch(/<button[^>]*>[^]*Riprova/);
    expect(html).toMatch(/<a [^>]*href="\/"[^>]*>Torna alla home<\/a>/);
  });

  it("non espone messaggio, traccia, host o impronta", () => {
    const t = testo(html);
    for (const vietato of ["segreto", "db.interno", "SELECT", "chiave-privata", "abc123", "boom", "digest"]) {
      expect(html).not.toContain(vietato);
      expect(t).not.toContain(vietato);
    }
  });

  it("usa retry (non reset) e non ricarica da sé: nessun ciclo", () => {
    const src = sorgente("error.tsx");
    expect(src).toContain("onRetry={retry ?? reset}");
    expect(src).not.toMatch(/useEffect|setTimeout|router\.refresh/);
  });

  it("senza onRetry non mostra un pulsante che non fa nulla", () => {
    const h = renderToStaticMarkup(<ErroreDiPagina errore={new Error("x")} />);
    expect(h).not.toContain("<button");
    expect(h).toContain("Torna alla home");
  });
});

describe("impronta", () => {
  it("restituisce solo un digest ben formato, mai il messaggio", () => {
    expect(impronta(new ErroreConDettagli())).toBe("abc123");
    expect(impronta(new Error("password=segreto"))).toBe("n/d");
    expect(impronta("stringa")).toBe("n/d");
    expect(impronta(null)).toBe("n/d");
    expect(impronta({ digest: "x y; DROP" })).toBe("n/d");
    expect(impronta({ digest: 42 })).toBe("n/d");
  });
});

describe("not-found.tsx di root", () => {
  const html = renderToStaticMarkup(<NonTrovato />);

  it("è in italiano, con un h1 e il cammino verso home e ricerca", () => {
    expect(html.match(/<h1\b/g)).toHaveLength(1);
    expect(testo(html)).toContain("Pagina non trovata");
    expect(html).toMatch(/href="\/"/);
    expect(html).toMatch(/href="\/esplora"/);
    expect(html).not.toContain("could not be found");
  });

  it("non cambia le guardie: è una pagina senza logica di autorizzazione", () => {
    const src = sorgente("not-found.tsx");
    expect(src).not.toMatch(/supabase|redirect|cookies|headers|notFound\(/);
  });
});

describe("global-error.tsx", () => {
  const html = renderToStaticMarkup(<ErroreGlobale error={new ErroreConDettagli()} retry={() => {}} />);

  it("porta html, lingua, titolo, noindex e il marchio da brand", () => {
    expect(html).toMatch(/<html[^>]*lang="it"/);
    expect(html).toContain("<body");
    expect(html).toContain("<title>Qualcosa non ha funzionato — Vinea</title>");
    expect(html).toContain('content="noindex, nofollow"');
    expect(testo(html)).toContain("Vinea Wine Club");
  });

  it("è la stessa pagina senza dettagli, con un solo h1", () => {
    expect(html.match(/<h1\b/g)).toHaveLength(1);
    expect(html).toContain("Riprova");
    for (const vietato of ["segreto", "db.interno", "SELECT", "chiave-privata", "abc123"]) {
      expect(html).not.toContain(vietato);
    }
  });

  it("non dipende da provider, sessione o Supabase (il layout è quello che è fallito)", () => {
    const src = sorgente("global-error.tsx");
    expect(src).not.toMatch(/supabase|Providers|VineaProvider|useVinea|next\/link/);
  });
});

describe("not-found annidati: un titolo di pagina vero", () => {
  for (const p of [
    "annuncio/[id]/not-found.tsx",
    "checkout/[id]/not-found.tsx",
    "community/[slug]/not-found.tsx",
    "profilo/[id]/not-found.tsx",
  ]) {
    it(p, () => {
      expect(sorgente(p).match(/<h1\b/g)).toHaveLength(1);
    });
  }
});
