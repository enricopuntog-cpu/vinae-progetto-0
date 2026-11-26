import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { SupabaseClient } from "@supabase/supabase-js";
import { etichettaSentinel, serviziAziendaAdmin, type StatoSentinel } from "./azienda-admin";

const stato = (o: Partial<StatoSentinel>): StatoSentinel => ({
  pianificato: false,
  intervallo_atteso_minuti: 60,
  stato: "recente",
  ultima_esecuzione: null,
  ...o,
});

describe("WI-013 — cruscotto del founder", () => {
  it("senza scheduler Sentinel non è mai presentato come pianificato, anche dopo un'esecuzione recente", () => {
    expect(etichettaSentinel(stato({}))).toBe("Non pianificato (solo esecuzione manuale) · eseguito di recente");
    expect(etichettaSentinel(stato({ stato: "mai_eseguito" }))).toContain("mai eseguito");
    expect(etichettaSentinel(stato({ pianificato: true, stato: "in_ritardo" }))).toBe("Pianificato · in ritardo sull'intervallo atteso");
  });

  it("usa solo le porte azienda_admin_*, senza letture dirette", async () => {
    const chiamate: string[] = [];
    const client = { rpc: async (n: string) => (chiamate.push(n), { data: [], error: null }) } as unknown as SupabaseClient;
    const s = serviziAziendaAdmin(client);
    await Promise.all([s.riepilogo(), s.anomalie(true, 1), s.eseguiSentinel(), s.task(1), s.decidiTask("x", "approva", "n"), s.aggiornaAnomalia(1, "ignora", "n")]);
    expect(chiamate.every((n) => n.startsWith("azienda_admin_"))).toBe(true);
    expect(readFileSync(join(import.meta.dir, "azienda-admin.ts"), "utf8")).not.toMatch(/\.from\(|\.schema\(/);
  });
});
