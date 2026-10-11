import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import type { SupabaseClient } from "@supabase/supabase-js";
import { PARTNER_STATI, PARTNER_TIPOLOGIE } from "@/lib/partner/partner";
import { creaPartnerAdminService, creaPartnerService } from "@/services/partner-service";

type RpcResponse = { data: unknown; error: { code?: string; message?: string; hint?: string } | null };

const fakeClient = (responses: RpcResponse[]) => {
  const calls: Array<{ name: string; args: unknown }> = [];
  const client = {
    rpc: (name: string, args?: unknown) => {
      calls.push({ name, args });
      const response = responses.shift();
      if (!response) throw new Error("risposta fake mancante");
      return Promise.resolve(response);
    },
    from: () => {
      throw new Error("il servizio Partner non legge tabelle");
    },
  } as unknown as SupabaseClient;
  return { client, calls };
};

const riga = {
  id: "p1",
  stato: "invitato",
  paese: "IT",
  created_at: "2026-10-11T09:00:00Z",
  updated_at: "2026-10-11T09:00:00Z",
};

describe("PartnerService (titolare)", () => {
  it("partner_me null diventa un risultato vuoto, non un errore", async () => {
    const { client, calls } = fakeClient([{ data: null, error: null }]);
    expect(await creaPartnerService(client).mio()).toEqual({ ok: true, data: null });
    expect(calls).toEqual([{ name: "partner_me", args: undefined }]);
  });

  it("accetta l'invito passando solo il token: nessun proprietario, nessun ruolo", async () => {
    const { client, calls } = fakeClient([{ data: "p1", error: null }]);
    expect(await creaPartnerService(client).accettaInvito("t".repeat(64))).toEqual({ ok: true, data: "p1" });
    expect(calls).toEqual([{ name: "partner_invito_accetta", args: { p_token: "t".repeat(64) } }]);
  });

  it("normalizza i dati prima della porta e non invia campi d'identità", async () => {
    const { client, calls } = fakeClient([{ data: riga, error: null }]);
    await creaPartnerService(client).aggiornaDati({
      ragioneSociale: "  Enoteca Srl ",
      nomeCommerciale: "",
      partitaIva: "IT 12345678903",
      emailCommerciale: " info@enoteca.it ",
      tipologia: "enoteca",
      sedeIndirizzo: "Via Roma 1",
      sedeCap: "12051",
      sedeCitta: "Alba",
      sedeProvincia: "cn",
    });
    expect(calls[0]).toEqual({
      name: "partner_dati_aggiorna",
      args: {
        p_ragione_sociale: "Enoteca Srl",
        p_nome_commerciale: null,
        p_partita_iva: "12345678903",
        p_email_commerciale: "info@enoteca.it",
        p_tipologia: "enoteca",
        p_sede_indirizzo: "Via Roma 1",
        p_sede_cap: "12051",
        p_sede_citta: "Alba",
        p_sede_provincia: "CN",
      },
    });
    const chiavi = Object.keys(calls[0].args as object).join(",");
    expect(chiavi).not.toMatch(/stato|titolare|user|role|margine/);
  });

  it("mappa l'hint del server in un messaggio leggibile", async () => {
    const { client } = fakeClient([
      { data: null, error: { code: "42501", message: "...", hint: "invito_email_diversa" } },
    ]);
    const esito = await creaPartnerService(client).accettaInvito("t".repeat(64));
    expect(esito.ok).toBe(false);
    if (!esito.ok) expect(esito.error).toContain("altro indirizzo email");
  });

  it("senza client risponde con un errore neutro", async () => {
    const esito = await creaPartnerService(null).mio();
    expect(esito.ok).toBe(false);
  });
});

describe("PartnerAdminService", () => {
  it("crea l'invito e restituisce il token una volta", async () => {
    const { client, calls } = fakeClient([
      {
        data: { invito_id: "i1", token: "f".repeat(64), scade_at: "2026-10-25T00:00:00Z", email: "a@b.it" },
        error: null,
      },
    ]);
    const esito = await creaPartnerAdminService(client).creaInvito({ email: "a@b.it", validitaGiorni: 14, nota: null });
    expect(esito).toEqual({
      ok: true,
      data: { invitoId: "i1", token: "f".repeat(64), scadeAt: "2026-10-25T00:00:00Z", email: "a@b.it" },
    });
    expect(calls[0]).toEqual({
      name: "partner_admin_invito_crea",
      args: { p_email: "a@b.it", p_validita_giorni: 14, p_nota: null },
    });
  });

  it("decide con azione e motivo e rifiuta risposte fuori dal dominio", async () => {
    const { client, calls } = fakeClient([
      { data: "attivo", error: null },
      { data: "approvata", error: null },
    ]);
    const servizio = creaPartnerAdminService(client);
    expect(await servizio.decidi("p1", "approva", null)).toEqual({ ok: true, data: "attivo" });
    expect(calls[0]).toEqual({
      name: "partner_admin_decidi",
      args: { p_partner_id: "p1", p_azione: "approva", p_motivo: null },
    });
    expect((await servizio.decidi("p1", "approva", null)).ok).toBe(false);
  });

  it("scarta righe malformate negli elenchi", async () => {
    const { client } = fakeClient([
      { data: [{ id: "i1", email: "a@b.it", stato: "valido", scade_at: "x", created_at: "y" }, { id: 3 }], error: null },
    ]);
    const esito = await creaPartnerAdminService(client).inviti();
    expect(esito.ok && esito.data.length).toBe(1);
  });
});

describe("contratto con la migrazione 20261011150000", () => {
  const root = resolve(import.meta.dir, "../../..");
  const sql = readFileSync(
    resolve(root, "supabase/migrations/20261011150000_partner_program_blocco_a_fondazione.sql"),
    "utf8",
  ).replace(/--.*$/gm, "");
  const servizio = readFileSync(resolve(import.meta.dir, "partner-service.ts"), "utf8");

  const etichetteEnum = (tipo: string) => {
    const corpo = sql.match(new RegExp(`create type public\\.${tipo} as enum \\(([^)]*)\\)`))?.[1] ?? "";
    return [...corpo.matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
  };

  it("stati e tipologie coincidono con gli enum SQL", () => {
    expect(etichetteEnum("partner_stato")).toEqual([...PARTNER_STATI]);
    expect(etichetteEnum("partner_tipologia")).toEqual(PARTNER_TIPOLOGIE.map((t) => t.value));
  });

  it("ogni RPC chiamata dal servizio esiste ed è concessa ad authenticated", () => {
    const chiamate = [...servizio.matchAll(/rpc\("([a-z_]+)"/g)].map((m) => m[1]);
    expect(new Set(chiamate).size).toBe(9);
    for (const nome of chiamate) {
      expect(sql).toContain(`create function public.${nome}(`);
      expect(sql).toMatch(new RegExp(`'public\\.${nome}\\(`));
    }
    expect(sql).toContain("grant execute on function %s to authenticated");
    expect(sql).not.toMatch(/grant [^;]*to anon[^;]*function/);
  });

  it("non scrive ruoli, configurazione economica o il marcatore delle qualifiche", () => {
    expect(sql).not.toMatch(/insert into public\.user_roles|update public\.user_roles|delete from public\.user_roles/);
    expect(sql).not.toMatch(/marketplace_config/);
    expect(sql).not.toMatch(/vinea\.pq_review/);
  });
});
