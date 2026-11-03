import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * VPM-015QA-FINAL-B2-COMPLETION — le date del pannello contestazioni usano un fuso esplicito.
 * Il server gira in UTC e il browser in Europe/Rome: senza fuso l'HTML del server e quello del client
 * differiscono (React #418, trovato dal collaudo browser in CI su un ordine Partner con contestazione).
 */
describe("DisputePanel: date deterministiche fra server e browser", () => {
  it("ogni toLocale*String ha timeZone Europe/Rome", () => {
    const sorgente = readFileSync(join(import.meta.dir, "DisputePanel.tsx"), "utf8");
    const chiamate = sorgente.match(/toLocale(Date)?String\([^)]*\)/g) ?? [];
    expect(chiamate.length).toBeGreaterThanOrEqual(3);
    for (const c of chiamate) expect(c).toContain('timeZone: "Europe/Rome"');
  });
});
