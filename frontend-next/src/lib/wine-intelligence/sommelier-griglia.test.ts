import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * WI-004 — la griglia SQL `wi004_sommelier_cantina_lettura.sql` prova sul database reale che le
 * colonne dell'elenco chiuso esistono e sono leggibili da `service_role`. Le liste dentro la
 * griglia devono restare uguali alle costanti della Edge Function: se una cambia senza l'altra,
 * la griglia proverebbe colonne che la function non legge (o viceversa).
 */

const radice = join(import.meta.dir, "../../../..");
const leggi = (p: string) => readFileSync(join(radice, p), "utf8");

const costante = (sorgente: string, nome: string): string => {
  // Concatenazione di letterali (o template) fino al `;` della dichiarazione.
  const m = sorgente.match(new RegExp(`const ${nome} = ([\\s\\S]*?);\\n`));
  if (!m) throw new Error(`costante ${nome} non trovata`);
  return m[1];
};

const colonne = (espressione: string): string[] =>
  espressione
    .replace(/\\\n/g, "")
    .replace(/\$\{COLONNE_VINO\}/g, "")
    .replace(/wines!inner\(\)/g, "")
    .replace(/"\s*\+\s*`?/g, "")
    .replace(/[`"]/g, " ")
    .split(/[,\s]+/)
    .map((c) => c.trim())
    .filter((c) => c && !c.startsWith("//"));

const dallaGriglia = (griglia: string, tabella: string): string[] => {
  const blocco = griglia.split(`-- @colonne ${tabella}`)[1].split("array[")[1].split("]")[0];
  return [...blocco.matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
};

const index = leggi("supabase/functions/ai-sommelier/index.ts");
const griglia = leggi("supabase/tests/wi004_sommelier_cantina_lettura.sql");

describe("griglia wi004 allineata alla Edge Function", () => {
  it("le colonne di wines della griglia sono quelle di COLONNE_VINO, senza ripetizioni di troppo", () => {
    const funzione = colonne(costante(index, "COLONNE_VINO")).sort();
    const g = dallaGriglia(griglia, "wines").sort();
    expect(funzione.length).toBeGreaterThan(15);
    expect(g).toEqual(funzione);
  });

  it("le colonne di bottle_units della griglia includono tutte quelle di COLONNE_BOTTIGLIA", () => {
    const funzione = colonne(costante(index, "COLONNE_BOTTIGLIA")).filter((c) => !c.startsWith("wines!inner")).sort();
    const g = dallaGriglia(griglia, "bottle_units");
    // La function filtra anche su owner_id, inventario, deleted_at e wine_id: la griglia le verifica in più.
    for (const c of funzione) expect(g).toContain(c);
    for (const filtro of ["owner_id", "inventario", "deleted_at", "wine_id"]) expect(g).toContain(filtro);
  });

  it("la function filtra davvero su proprietario, inventario personale, non eliminate/cedute, chiuse o aperte", () => {
    for (const frammento of [
      '.eq("owner_id", userId)',
      '.eq("inventario", "personale")',
      '.is("deleted_at", null)',
      '.is("ceduta_at", null)',
      '.in("stato", ["chiusa", "aperta"])',
    ]) {
      expect(index).toContain(frammento);
    }
  });

  it("il runner CI esegue la griglia", () => {
    expect(leggi("supabase/tests/12g_ci_run.sh")).toContain("wi004_sommelier_cantina_lettura.sql");
  });
});
