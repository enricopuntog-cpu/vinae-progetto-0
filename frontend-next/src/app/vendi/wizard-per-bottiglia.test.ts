/**
 * Un wizard per bottiglia (VPM-018-E2E-CRIT-01, D-VENDI-01), misurato sulla
 * sorgente come gli altri contratti di `/vendi` (`logistica-consegna.test.ts`).
 *
 * Dal selettore della Cantina (`/vendi?mode=sell` → `&bottiglia=…`) la rotta è
 * la stessa: senza `key` il wizard non si rimonta e passo, dati, foto, bozza e
 * riuso restano quelli di prima («Passo 0 di 7»). Il percorso nel browser è in
 * `e2e/marketplace-vino.e2e.ts`.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const pagina = readFileSync(join(import.meta.dir, "page-client.tsx"), "utf8");

describe("wizard /vendi rimontato per bottiglia", () => {
  it("l'export della pagina rende il wizard con la bottiglia dell'URL come chiave", () => {
    const esportato = pagina.slice(pagina.indexOf("export default function VendiPageClient"));
    const corpo = esportato.slice(0, esportato.indexOf("\n}\n"));
    expect(corpo).toMatch(/useSearchParams\(\)\.get\("bottiglia"\)/);
    expect(corpo).toMatch(/<WizardVendi key=\{bottiglia \?\? "nuova"\} \/>/);
  });

  it("lo stato del wizard vive solo nel componente con la chiave", () => {
    const esportato = pagina.slice(pagina.indexOf("export default function VendiPageClient"));
    const corpo = esportato.slice(0, esportato.indexOf("\n}\n"));
    expect(corpo).not.toMatch(/useSellWizard|useState/);
    expect(pagina).toMatch(/function WizardVendi\(\)[\s\S]*useSellWizard\(/);
  });
});
