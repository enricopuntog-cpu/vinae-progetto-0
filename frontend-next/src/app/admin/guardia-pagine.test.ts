import { describe, expect, it } from "bun:test";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

/**
 * Ogni pagina di `/admin` ripete la propria guardia, perché il `proxy` non protegge `/admin` e un
 * `layout.tsx` non si riesegue alla navigazione lato client: non sostituirebbe il controllo per pagina.
 * Questo test impedisce a una pagina nuova di dimenticarlo (GAP-022).
 */
const pagine = (cartella: string): string[] =>
  readdirSync(cartella).flatMap((voce) => {
    const percorso = join(cartella, voce);
    if (statSync(percorso).isDirectory()) return pagine(percorso);
    return voce === "page.tsx" ? [percorso] : [];
  });

describe("guardia delle pagine admin", () => {
  const elenco = pagine(import.meta.dir);

  it("vede tutte le pagine note", () => {
    expect(elenco.length).toBeGreaterThanOrEqual(5);
  });

  it.each(elenco)("%s: sessione lato server e ruolo reale, altrimenti accesso o 404", (percorso) => {
    const testo = readFileSync(percorso, "utf8");
    expect(testo).toContain("auth.getUser()");
    expect(testo).toContain("redirect(PERCORSO_ACCESSO)");
    expect(testo).toMatch(/eAdminReale\(/);
    expect(testo).toContain("notFound()");
  });
});
