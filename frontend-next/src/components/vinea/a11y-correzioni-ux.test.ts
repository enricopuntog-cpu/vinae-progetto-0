/**
 * Correzioni di accessibilità e testo di VPM-018-UX-A11Y-01, misurate sulla
 * sorgente come gli altri contratti delle pagine client. Il comportamento nel
 * browser è in `e2e/ux-a11y.e2e.ts`.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const src = (p: string) => readFileSync(join(import.meta.dir, "..", "..", p), "utf8");

describe("slot foto vuoti", () => {
  it("hanno sempre un nome accessibile, anche fuori dall'editor (wizard /vendi)", () => {
    const f = src("components/vinea/FotoGriglia.tsx");
    const slot = f.slice(f.indexOf("`vuota-${i}`"), f.indexOf("<Camera"));
    expect(slot).toContain("aria-label={`Aggiungi la fotografia ${foto.length + i + 1}`}");
    expect(slot).not.toMatch(/aria-label=\{editor/);
  });
});

describe("Condizioni del wizard /vendi", () => {
  it("sono pulsanti con stato (aria-pressed) e senza paragrafi dentro il pulsante", () => {
    const f = src("app/vendi/page-client.tsx");
    const blocco = f.slice(f.indexOf('["Perfetto", "Ottimo", "Buono"]'), f.indexOf('<span className="block font-serif text-base">{c}</span>'));
    expect(blocco).toContain('type="button"');
    expect(blocco).toContain("aria-pressed={d.condizione === c}");
    expect(f).not.toContain('<p className="font-serif text-base">{c}</p>');
  });
});

describe("card dell'annuncio", () => {
  it("il pin della località compare solo se la città c'è", () => {
    const f = src("components/vinea/WineCard.tsx");
    // Nessun pin seguito direttamente dalla città: sempre dentro una condizione sulla città.
    expect(f).not.toContain("<MapPin className=\"h-3 w-3\" /> {wine.venditore.citta}");
    expect(f.split("wine.venditore.citta ? (").length - 1).toBeGreaterThanOrEqual(2);
  });
});

describe("foto del wizard", () => {
  it("ogni rimozione dice quale fotografia toglie", () => {
    const f = src("components/vinea/FotoGriglia.tsx");
    expect(f).toContain("aria-label={`Rimuovi la fotografia ${i + 1}`}");
    expect(f).not.toContain('"Rimuovi fotografia"');
  });
});

describe("/messaggi", () => {
  it("ogni stato senza elenco ha il titolo h1 «Messaggi»", () => {
    const f = src("components/vinea/messaging/MessagesPageClient.tsx");
    // Visibile dal UX-B6: la prova di ciò che si vede è in `e2e/ux-fix-03.e2e.ts`.
    expect(f.match(/<h1\b[^>]*>Messaggi<\/h1>/g)).toHaveLength(1);
    expect(f).not.toContain("sr-only");
    for (const stato of ["OfflineState", "LoadingBlock", "ErrorState", "EmptyState"]) {
      const i = f.indexOf(`<${stato}`);
      expect(f.slice(Math.max(0, i - 80), i), stato).toContain("{intestazione}");
    }
  });
});

describe("/completa-profilo", () => {
  it("il campo descrive i requisiti solo quando ci sono: nessun riferimento a vuoto", () => {
    const f = src("app/completa-profilo/page-client.tsx");
    expect(f).toContain('aria-describedby={passwordGiaImpostata ? undefined : "requisiti-password-vinea"}');
    // Dopo lo spread di attributiPasswordNuova, che imposterebbe il riferimento comunque.
    expect(f.indexOf("aria-describedby={passwordGiaImpostata")).toBeGreaterThan(
      f.indexOf('{...attributiPasswordNuova("requisiti-password-vinea")}'),
    );
  });
});

describe("/esplora", () => {
  const f = src("app/esplora/page-client.tsx");
  it("il campo di ricerca ha un nome accessibile oltre al segnaposto", () => {
    const campo = f.slice(f.indexOf('data-testid="esplora-search-input"'), f.indexOf('className="pl-10 h-11'));
    expect(campo).toContain("aria-label=");
    // Etichetta nel nome (WCAG 2.5.3): il nome contiene il testo del segnaposto (senza i puntini).
    expect(campo).toContain('"Cerca vino, produttore, annata"');
    expect(campo).toContain('"Cerca vino, produttore, annata…"');
  });
  it("il conteggio usa il singolare per un risultato", () => {
    expect(f).toContain('filtered.length === 1 ? "1 risultato"');
    // Il vecchio JSX era `<Badge …>{filtered.length} risultati</Badge>`: non deve tornare.
    expect(f).not.toContain(">{filtered.length} risultati");
  });
});
