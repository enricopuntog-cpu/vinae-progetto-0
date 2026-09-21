import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const root = join(import.meta.dir, "../../../../..");
const migration = readFileSync(
  join(root, "supabase/migrations/20260921170806_complete_club_dispute_lifecycles.sql"),
  "utf8",
).toLowerCase();
const clubFoundation = readFileSync(
  join(root, "supabase/migrations/20260920230225_club_governance_foundations.sql"),
  "utf8",
).toLowerCase();
const panel = readFileSync(join(import.meta.dir, "ClubGovernancePanels.tsx"), "utf8");
const moderation = readFileSync(
  join(root, "frontend-next/src/components/vinea/moderation/ModerationPanelClient.tsx"),
  "utf8",
);

const body = (name: string, next: string) => {
  const start = migration.indexOf(`create or replace function public.${name}`);
  const end = migration.indexOf(next, start);
  expect(start).toBeGreaterThan(-1);
  expect(end).toBeGreaterThan(start);
  return migration.slice(start, end);
};

describe("completamento governance Club", () => {
  it("confina la nomina dei moderatori al proprietario dello stesso Club", () => {
    const sql = body("club_moderatore_imposta", "create or replace function public.club_link_proponi");
    expect(sql).toContain("role = 'proprietario'");
    expect(sql).toContain("club_slug = p_club_slug");
    expect(sql).toContain("solo il proprietario");
    expect(sql).toContain("c.approval_status = 'approvato'");
  });

  it("impedisce di nominare moderatore un non membro", () => {
    const sql = body("club_moderatore_imposta", "create or replace function public.club_link_proponi");
    expect(sql).toContain("from public.club_memberships");
    expect(sql).toContain("solo un membro del club");
  });

  it("protegge il proprietario da rimozione ed escalation del proprio ruolo", () => {
    const sql = body("club_moderatore_imposta", "create or replace function public.club_link_proponi");
    expect(sql).toContain("p_user_id = v_uid or v_target_role = 'proprietario'");
  });

  it("rende atomica la numerazione dei regolamenti", () => {
    const sql = body("club_regolamento_proponi", "revoke all on function private.append_only_guard");
    expect(sql).toContain("from public.clubs where slug = p_club_slug for update");
    expect(clubFoundation).toContain("club_rule_versions_one_pending_idx");
  });

  it("non abilita gestione o regolamenti su un Club ancora non approvato", () => {
    expect(migration.match(/c\.approval_status = 'approvato'/g)?.length).toBeGreaterThanOrEqual(4);
  });

  it("rende gestibile il Club storico solo quando il suo unico owner e deterministico", () => {
    expect(migration).toContain("having count(*) = 1");
    expect(migration).toContain("where c.slug = single_member.club_slug and c.owner_id is null");
  });

  it("accetta soltanto link HTTPS e piattaforme dichiarate", () => {
    const sql = body("club_link_proponi", "create or replace function public.club_link_revisiona");
    expect(sql).toContain("facebook','instagram','x','telegram','discord','sito','altro");
    expect(sql).toContain("^https://");
  });

  it("rende append-only il nuovo audit Club", () => {
    expect(migration).toContain("club_management_events_no_update");
    expect(migration).toContain("club_management_events_no_delete");
    expect(migration).toContain("club_management_events_no_truncate");
  });

  it("espone una UI mobile per tutte le aree di gestione richieste", () => {
    for (const label of ["Informazioni", "Membri", "Richieste", "Moderatori", "Regolamento", "Link"]) {
      expect(panel).toContain(label);
    }
    expect(panel).toContain('className="h-auto flex-wrap justify-start"');
  });

  it("mantiene separate revisione admin e gestione del singolo Club", () => {
    expect(panel).toContain("export function AdminClubGovernance");
    expect(panel).toContain("export function ClubManagementPanel");
  });
});

describe("completamento contestazioni", () => {
  it("richiede un admin reale per presa in carico, revisione, note e decisione", () => {
    for (const fn of [
      "moderazione_contestazione_prendi_in_carico",
      "moderazione_contestazione_inizia_revisione",
      "moderazione_contestazione_nota_privata",
      "moderazione_contestazione_decidi",
    ]) {
      const start = migration.indexOf(`create or replace function public.${fn}`);
      expect(migration.slice(start, start + 850)).toContain("public.has_role(v_uid, 'admin')");
    }
  });

  it("serializza due admin sulla stessa pratica", () => {
    const sql = body("moderazione_contestazione_decidi", "create or replace function public.contestazione_venditore_rispondi");
    expect(sql).toContain("where order_id = p_order_id for update");
    expect(migration).toContain("la contestazione e gia presa in carico");
  });

  it("impedisce la decisione prima della revisione", () => {
    const sql = body("moderazione_contestazione_decidi", "create or replace function public.contestazione_venditore_rispondi");
    expect(sql).toContain("v_d.lifecycle_status <> 'in_revisione'");
    expect(sql).toContain("v_d.assigned_to is distinct from v_uid");
  });

  it("obbliga a motivare ogni correzione successiva", () => {
    const sql = body("moderazione_contestazione_decidi", "create or replace function public.contestazione_venditore_rispondi");
    expect(sql).toContain("per correggere una decisione serve un motivo");
    expect(sql).toContain("decisione_corretta");
  });

  it("registra decisioni e note in tabelle append-only", () => {
    for (const trigger of [
      "dispute_admin_notes_no_update", "dispute_admin_notes_no_delete",
      "dispute_decisions_no_update", "dispute_decisions_no_delete",
      "dispute_case_events_no_update", "dispute_case_events_no_delete",
    ]) expect(migration).toContain(trigger);
  });

  it("non espone le note private alle parti", () => {
    const viewStart = migration.indexOf("create or replace view public.moderation_dispute_admin_notes");
    const viewEnd = migration.indexOf("create or replace view public.dispute_case_timeline", viewStart);
    expect(migration.slice(viewStart, viewEnd)).toContain("public.has_role((select auth.uid()), 'admin')");
    expect(migration.slice(viewStart, viewEnd)).not.toContain("buyer_id");
  });

  it("separa la decisione da ordini, payout, pagamenti e provider", () => {
    const sql = body("moderazione_contestazione_decidi", "create or replace function public.contestazione_venditore_rispondi");
    expect(sql).not.toMatch(/update public\.(orders|payouts|payments)/);
    expect(sql).not.toContain("ordine_contestazione_risolvi");
    expect(sql).not.toContain("stripe");
  });

  it("mostra le cinque decisioni senza offrire operazioni economiche", () => {
    for (const outcome of ["favore_acquirente", "favore_venditore", "accordo", "respinta", "cancellata"]) {
      expect(moderation).toContain(`value="${outcome}"`);
    }
    expect(moderation).toContain("La decisione non esegue rimborsi, payout o altre movimentazioni economiche");
  });

  it("mostra all'admin la timeline completa e tiene le note private separate", () => {
    expect(moderation).toContain("Timeline completa");
    expect(moderation).toContain("Note amministrative private");
  });
});
