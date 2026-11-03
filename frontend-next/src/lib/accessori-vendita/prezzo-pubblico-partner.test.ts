import { describe, expect, it } from "bun:test";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

/**
 * VPM-015QA-FINAL-B2-COMPLETION — il prezzo pubblico di un annuncio Partner è quello del checkout.
 * Contratto di sorgente della migrazione correttiva; il comportamento lo prova la griglia 12zr (caso 24) su
 * PostgreSQL e lo spec browser dei Partner. Il B3 distribuito non si modifica.
 */

const radice = join(import.meta.dir, "../../../..");
const cartella = join(radice, "supabase/migrations");
const leggi = (nome: string) => readFileSync(join(cartella, nome), "utf8");
const migrazioni = readdirSync(cartella).sort();
const CORRETTIVA = migrazioni.find((n) => n.includes("vpm_015qa_final_b2_prezzo_pubblico_partner")) ?? "";
const B3 = migrazioni.find((n) => n.includes("vpm_015b3_pubblicazione_accessori")) ?? "";
const PARTNER = migrazioni.find((n) => n.includes("vpm_015c_accessori_partner")) ?? "";
const senzaCommenti = (s: string) => s.replace(/--.*$/gm, "");

describe("migrazione correttiva del prezzo pubblico dei Partner", () => {
  it("esiste, è successiva alla 015C e non ricrea tabelle, policy o privilegi", () => {
    expect(CORRETTIVA).not.toBe("");
    expect(CORRETTIVA > PARTNER).toBe(true);
    const sql = senzaCommenti(leggi(CORRETTIVA));
    expect(sql).not.toMatch(/create\s+table|create\s+policy|alter\s+table|\bgrant\b|disable\s+row\s+level/i);
    // Un solo revoke ammesso: riaffermare la chiusura della funzione corretta.
    const revoke = sql.match(/\brevoke\b[^;]*;/gi) ?? [];
    expect(revoke).toHaveLength(1);
    expect(revoke[0]).toMatch(/annuncio_accessorio_pubblico_json\(uuid\)\s+from public, anon, authenticated/i);
  });

  it("sostituisce la classe scritta nel sorgente con quella del venditore PER ARTICOLO, con asserzione di una sola occorrenza", () => {
    const sql = leggi(CORRETTIVA);
    expect(sql).toContain("pg_get_functiondef");
    expect(sql).toContain("v_n <> 1");
    expect(sql).toContain("private.annuncio_accessorio_pubblico_json(uuid)");
    expect(sql).toContain("private.annuncio_accessorio_venditore(a.seller_id, a.cantina_accessorio_id)");
    // Fallback fail-safe sulla classe privata (mai null verso preventivo_dominio).
    expect(sql).toContain("coalesce(");
  });

  it("il B3 distribuito resta intatto (la correzione è una migrazione nuova, non una modifica)", () => {
    const b3 = leggi(B3);
    expect(b3).toContain("'privato'::public.classe_venditore,\n                                  a.prezzo_unitario_cents, 1, null)");
  });
});
