import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "bun:test";
import { eAdminReale, ruoloDaSessione } from "@/lib/auth/role";

const root = resolve(import.meta.dir, "../../..");
const read = (path: string) => readFileSync(resolve(root, path), "utf8");

describe("fondamenta operative fail-closed", () => {
  it("non assegna automaticamente la capability di emergenza", () => {
    const sql = read("supabase/migrations/20260920230154_operational_continuity_disputes_clubs.sql");
    expect(sql).toInclude("public.has_role(v_uid, 'emergency_delegate')");
    expect(sql).not.toMatch(/insert\s+into\s+public\.user_roles/i);
  });

  it("il delegato di emergenza non e admin per la shell ne per l'Area Admin", () => {
    const utente = { userId: "00000000-0000-4000-8000-000000000002" };
    expect(ruoloDaSessione(utente, ["emergency_delegate"])).toBe("user");
    expect(eAdminReale(["emergency_delegate"])).toBe(false);
    expect(ruoloDaSessione(utente, ["admin"])).toBe("admin");
    expect(read("frontend-next/src/app/admin/page.tsx")).toInclude("if (!eAdminReale(ruoli)) notFound();");
  });

  it("/continuita si apre soltanto ad admin ed emergency_delegate e usa solo la porta del banner", () => {
    const pagina = read("frontend-next/src/app/continuita/page.tsx");
    expect(pagina).toInclude("const accesso = accessoContinuita({");
    expect(pagina).toInclude('if (accesso === "negato") notFound();');
    expect(pagina).toInclude('if (accesso !== "ammesso") redirect(PERCORSO_SICUREZZA);');
    // aal dal JWT verificato, non dal cookie decodificato.
    expect(pagina).toInclude("client.auth.getClaims()");
    const pannello = read("frontend-next/src/components/vinea/moderation/IncidentNoticeAdmin.tsx");
    expect(pannello.match(/client\.rpc\(/g)?.length).toBe(1);
    expect(pannello).toInclude('client.rpc("incident_notice_set"');
    expect(pannello).not.toMatch(/\.from\(/);
  });

  it("mantiene private le prove delle contestazioni", () => {
    const sql = read("supabase/migrations/20260920230218_dispute_evidence_and_seller_response.sql");
    expect(sql).toInclude("'dispute-evidence', 'dispute-evidence', false");
    expect(sql).toInclude("dispute_evidence_participants_select");
    expect(sql).not.toMatch(/grant\s+select\s+on\s+storage\.objects/i);
  });

  it("distribuisce i Club chiusi finche il lancio non e deliberato", () => {
    const sql = read("supabase/migrations/20260920230225_club_governance_foundations.sql");
    expect(sql).toMatch(/revoke all on public\.public_clubs,[\s\S]*from public, anon, authenticated;/);
    expect(read("frontend-next/src/config/features.ts")).toMatch(
      /valoreFlagEsattamenteTrue\(\s*process\.env\.NEXT_PUBLIC_CLUBS_ENABLED,?\s*\)/,
    );
    expect(read("frontend-next/src/lib/clubs/gate.ts")).toMatch(
      /process\.env\.CLUBS_ENABLED[\s\S]*process\.env\.NEXT_PUBLIC_CLUBS_ENABLED/,
    );
    expect(read("frontend-next/src/proxy.ts")).toMatch(
      /percorsoClub && !clubAbilitatiServer\(\)[\s\S]*status: 404/,
    );
  });

  it("il lancio espone soltanto Club approvati e mantiene le scritture nelle RPC", () => {
    const sql = read("supabase/migrations/20260921111621_launch_clubs.sql");
    expect(sql).toMatch(/c\.approval_status = 'approvato'/);
    expect(sql).toMatch(/grant select on public\.public_clubs,[\s\S]*to anon, authenticated/);
    expect(sql).not.toMatch(/grant\s+(insert|update|delete)/i);
    const servizio = read("frontend-next/src/services/phase12/supabase-club-service.ts");
    expect(servizio).toInclude('client.rpc("club_ingresso_richiedi"');
    expect(servizio).toInclude('client.rpc("club_abbandona"');
    expect(servizio).toInclude('client.rpc("club_proposta_crea"');
  });

  it("non esegue il backup offsite senza il gate esatto", () => {
    const script = read(".github/scripts/offsite-backup.sh");
    const workflow = read(".github/workflows/offsite-backup.yml");
    expect(script).toInclude('if [[ "${BACKUP_OFFSITE_ENABLED:-}" != "true" ]]');
    expect(workflow).toInclude("vars.BACKUP_OFFSITE_ENABLED == 'true'");
  });
});
