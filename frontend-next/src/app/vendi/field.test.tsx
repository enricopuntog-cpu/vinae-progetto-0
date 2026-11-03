/**
 * R-A11Y-01 (VPM-018-UX-A11Y-01): ogni campo del wizard `/vendi` ha un'etichetta
 * associata al controllo. Prima `Field` mostrava la `Label` senza `htmlFor` e
 * conservazione, storia e prezzo non avevano nome accessibile (restava il segnaposto).
 * Il percorso nel browser è in `e2e/marketplace-vino.e2e.ts` (`getByLabel`).
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { renderToStaticMarkup } from "react-dom/server";
import { Input } from "@/components/ui/input";
import { CAMPO_ID, Field } from "./field";

const pagina = readFileSync(join(import.meta.dir, "page-client.tsx"), "utf8");

describe("Field del wizard /vendi", () => {
  it("la Label punta al controllo con un for uguale al suo id", () => {
    const html = renderToStaticMarkup(
      <Field label="Prezzo per bottiglia (€)" htmlFor={CAMPO_ID.prezzo}>
        <Input id={CAMPO_ID.prezzo} type="number" />
      </Field>,
    );
    expect(html).toContain(`<label`);
    expect(html).toContain(`for="${CAMPO_ID.prezzo}"`);
    expect(html).toContain(`id="${CAMPO_ID.prezzo}"`);
    expect(html).toContain("Prezzo per bottiglia (€)");
  });

  it("gli id sono unici e stabili (nessun id generato a ogni rendering)", () => {
    const valori = Object.values(CAMPO_ID);
    expect(new Set(valori).size).toBe(valori.length);
    for (const v of valori) expect(v).toMatch(/^vendi-[a-z-]+$/);
  });
});

describe("page-client del wizard: ogni Field ha il suo controllo", () => {
  const aperture = [...pagina.matchAll(/<Field\b[^>]*>/g)].map((m) => m[0]);

  it("nessun Field senza htmlFor tratto da CAMPO_ID", () => {
    expect(aperture.length).toBeGreaterThanOrEqual(13);
    for (const a of aperture) expect(a).toMatch(/htmlFor=\{CAMPO_ID\.[a-zA-Z]+\}/);
  });

  it("per ogni chiave usata da un Field esiste esattamente un controllo con lo stesso id", () => {
    const usate = aperture.map((a) => a.match(/CAMPO_ID\.([a-zA-Z]+)/)![1]);
    expect(new Set(usate).size).toBe(usate.length);
    for (const chiave of usate) {
      const controlli = pagina.match(new RegExp(`\\bid=\\{CAMPO_ID\\.${chiave}\\}`, "g")) ?? [];
      expect(controlli.length, `controllo con id CAMPO_ID.${chiave}`).toBe(1);
    }
  });

  it("ogni chiave di CAMPO_ID è usata (nessun id orfano)", () => {
    for (const chiave of Object.keys(CAMPO_ID)) {
      expect(pagina, chiave).toContain(`htmlFor={CAMPO_ID.${chiave}}`);
    }
  });

  it("i selettori con etichetta visibile non la sostituiscono con un aria-label diverso", () => {
    // Un aria-label prevale sull'etichetta e non la contiene: «Regione» ≠ «Regione (obbligatoria)».
    expect(pagina).not.toMatch(/<SelectTrigger[^>]*aria-label=/);
  });

  it("il wizard non definisce più un Field locale senza associazione", () => {
    expect(pagina).not.toMatch(/function Field\(/);
    expect(pagina).toContain(`import { CAMPO_ID, Field } from "@/app/vendi/field"`);
  });
});
