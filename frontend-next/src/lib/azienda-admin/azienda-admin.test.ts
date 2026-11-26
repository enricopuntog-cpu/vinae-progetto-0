import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { SupabaseClient } from "@supabase/supabase-js";
import { etichettaAgente, etichettaFonte, etichettaScheduler, etichettaSentinel, serviziAziendaAdmin, type StatoSentinel } from "./azienda-admin";

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

  it("WI-015: l'«ignora» porta la durata scelta e l'esecuzione si conferma con una decisione distinta", async () => {
    const chiamate: [string, unknown][] = [];
    const client = { rpc: async (n: string, a: unknown) => (chiamate.push([n, a]), { data: "ok", error: null }) } as unknown as SupabaseClient;
    const s = serviziAziendaAdmin(client);
    await s.aggiornaAnomalia(1, "ignora", "rumore", 48);
    await s.aggiornaAnomalia(2, "risolvi", "fatto");
    await s.decidiTask("t", "conferma_eseguito", "eseguito dal pannello");
    expect(chiamate).toEqual([
      ["azienda_admin_anomalia_aggiorna", { p_id: 1, p_azione: "ignora", p_nota: "rumore", p_ore: 48 }],
      ["azienda_admin_anomalia_aggiorna", { p_id: 2, p_azione: "risolvi", p_nota: "fatto", p_ore: null }],
      ["azienda_admin_task_decidi", { p_id: "t", p_decisione: "conferma_eseguito", p_nota: "eseguito dal pannello" }],
    ]);
  });

  it("WI-015: ogni stato di fonte e di agente ha un'etichetta onesta; ciò che non si conosce è «non verificato»", () => {
    expect(
      ["disponibile", "degradata", "errore", "in_ritardo", "disattivata", "non_verificata", "mai-visto"].map(etichettaFonte),
    ).toEqual(["Disponibile", "Degradata", "Errore", "In ritardo", "Disattivata", "Non verificata", "Non verificata"]);
    expect(etichettaAgente("acceso_senza_attivita")).toBe("Acceso, nessuna attività nelle ultime 24 ore");
    expect(etichettaAgente("spento")).toBe("Spento");
    expect(etichettaScheduler({ stato: "recente", pg_cron_installato: false, job_cron_attivo: false })).toBe(
      "Non pianificato (nessun giro automatico)",
    );
    expect(etichettaScheduler({ stato: "in_ritardo", pg_cron_installato: true, job_cron_attivo: true })).toBe("Pianificato ma in ritardo");
    expect(etichettaScheduler({ stato: "recente", pg_cron_installato: true, job_cron_attivo: true })).toBe("Pianificato e recente");
  });

  it("WI-015: il rapporto periodico passa dalla porta admin", async () => {
    const chiamate: [string, unknown][] = [];
    const client = { rpc: async (n: string, a: unknown) => (chiamate.push([n, a]), { data: {}, error: null }) } as unknown as SupabaseClient;
    await serviziAziendaAdmin(client).rapporto(7);
    expect(chiamate).toEqual([["azienda_admin_rapporto", { p_giorni: 7 }]]);
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
