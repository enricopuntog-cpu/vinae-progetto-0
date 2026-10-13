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

  it("riabilita le vendite con id e motivo; accetta solo un esito senza blocco", async () => {
    const { client, calls } = fakeClient([
      { data: { partnerId: "p1", venditeBloccate: false, giaRiabilitato: false }, error: null },
      { data: { partnerId: "p1", venditeBloccate: true }, error: null },
      { data: null, error: { code: "42501", hint: "" } },
    ]);
    const servizio = creaPartnerAdminService(client);
    expect(await servizio.riabilitaVendite("p1", "verifiche completate")).toEqual({ ok: true, data: undefined });
    expect(calls[0]).toEqual({
      name: "partner_admin_vendite_riabilita",
      args: { p_partner_id: "p1", p_motivo: "verifiche completate" },
    });
    expect((await servizio.riabilitaVendite("p1", "x")).ok).toBe(false);
    expect(await servizio.riabilitaVendite("p1", "x")).toEqual({ ok: false, error: "Operazione non consentita." });
  });

  it("sospende gli annunci e restituisce il conteggio; rifiuta risposte non numeriche", async () => {
    const { client, calls } = fakeClient([
      { data: 3, error: null },
      { data: "3", error: null },
      { data: -1, error: null },
    ]);
    const servizio = creaPartnerAdminService(client);
    expect(await servizio.sospendiAnnunci("p1", "verifica")).toEqual({ ok: true, data: 3 });
    expect(calls[0]).toEqual({
      name: "partner_admin_annunci_sospendi",
      args: { p_partner_id: "p1", p_motivo: "verifica" },
    });
    expect((await servizio.sospendiAnnunci("p1", "verifica")).ok).toBe(false);
    expect((await servizio.sospendiAnnunci("p1", "verifica")).ok).toBe(false);
  });

  it("lo spegnimento di emergenza passa solo il motivo e accetta solo «spento»", async () => {
    const { client, calls } = fakeClient([
      { data: false, error: null },
      { data: true, error: null },
      { data: null, error: { code: "22023", message: "Lo spegnimento richiede un motivo." } },
    ]);
    const servizio = creaPartnerAdminService(client);
    expect(await servizio.spegniVenditaPartner("incidente")).toEqual({ ok: true, data: undefined });
    expect(calls[0]).toEqual({ name: "partner_admin_vendita_partner_spegni", args: { p_motivo: "incidente" } });
    expect((await servizio.spegniVenditaPartner("incidente")).ok).toBe(false);
    expect(await servizio.spegniVenditaPartner(" ")).toEqual({
      ok: false,
      error: "Lo spegnimento richiede un motivo.",
    });
  });

  it("vendite_bloccate arriva al Partner solo se è esattamente true", async () => {
    const { client } = fakeClient([
      { data: { ...riga, stato: "revocato", vendite_bloccate: true }, error: null },
      { data: { ...riga, stato: "revocato", vendite_bloccate: "true" }, error: null },
    ]);
    const servizio = creaPartnerService(client);
    const a = await servizio.mio();
    const b = await servizio.mio();
    expect(a.ok && a.data?.venditeBloccate).toBe(true);
    expect(b.ok && b.data?.venditeBloccate).toBe(false);
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
    const sicurezza = readFileSync(
      resolve(root, "supabase/migrations/20261013120000_partner_sicurezza_revoca.sql"),
      "utf8",
    ).replace(/--.*$/gm, "");
    const chiamate = [...servizio.matchAll(/rpc\("([a-z_]+)"/g)].map((m) => m[1]);
    expect(new Set(chiamate).size).toBe(12);
    for (const nome of chiamate) {
      if (sql.includes(`create function public.${nome}(`)) {
        expect(sql).toMatch(new RegExp(`'public\\.${nome}\\(`));
      } else {
        expect(sicurezza).toContain(`create function public.${nome}(`);
        expect(sicurezza).toMatch(new RegExp(`grant execute on function public\\.${nome}\\([^)]*\\) to authenticated;`));
        expect(sicurezza).toMatch(new RegExp(`revoke execute on function public\\.${nome}\\([^)]*\\) from public, anon, service_role;`));
      }
    }
    expect(sql).toContain("grant execute on function %s to authenticated");
    expect(sql).not.toMatch(/grant [^;]*to anon[^;]*function/);
    expect(sicurezza).not.toMatch(/to anon/);
  });

  it("non scrive ruoli, configurazione economica o il marcatore delle qualifiche", () => {
    expect(sql).not.toMatch(/insert into public\.user_roles|update public\.user_roles|delete from public\.user_roles/);
    expect(sql).not.toMatch(/marketplace_config/);
    expect(sql).not.toMatch(/vinea\.pq_review/);
  });
});
