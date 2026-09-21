import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "bun:test";

const root = resolve(import.meta.dir, "../../..");
const read = (path: string) => readFileSync(resolve(root, path), "utf8");

describe("fondamenta operative fail-closed", () => {
  it("non assegna automaticamente la capability di emergenza", () => {
    const sql = read("supabase/migrations/20260920230154_operational_continuity_disputes_clubs.sql");
    expect(sql).toInclude("public.has_role(v_uid, 'emergency_delegate')");
    expect(sql).not.toMatch(/insert\s+into\s+public\.user_roles/i);
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
