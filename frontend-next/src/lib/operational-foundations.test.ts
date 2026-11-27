import { readdirSync, readFileSync } from "node:fs";
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

  it("ogni workflow con secret li prende da un environment ristretto a main", () => {
    const dir = resolve(root, ".github/workflows");
    const workflow = readdirSync(dir).filter((f) => f.endsWith(".yml"));
    expect(workflow.length).toBeGreaterThan(0);
    const conSecret = workflow.filter((f) => /\$\{\{\s*secrets\./.test(read(`.github/workflows/${f}`)));
    expect(conSecret.sort()).toEqual([
      "company-brain-worker.yml",
      "offsite-backup-freshness.yml",
      "offsite-backup.yml",
      "payouts-auto-release.yml",
      "technical-heartbeat.yml",
      "wine-catalog-cloud-import.yml",
    ]);
    for (const f of conSecret) {
      expect(read(`.github/workflows/${f}`)).toMatch(
        /\n {4}environment: (production-(backup|payouts)|catalog-cloud-import|company-brain-ingest|company-brain-\$\{\{ inputs\.agente \}\})\r?\n/,
      );
    }
    // WI-016: ogni step che consegna un segnale o legge il brain passa la CA del progetto: fuori da loopback i
    // processi la pretendono, quindi senza di essa l'invio acceso sarebbe sempre rifiutato.
    for (const f of workflow) {
      const testo = read(`.github/workflows/${f}`);
      const conCredenziale = testo.match(/VINEA_(INGEST|OBSERVER|AGENT)_DATABASE_URL: \$\{\{ secrets\./g) ?? [];
      const passi = testo.split(/\r?\n {6}- name: /).filter((p) => /_DATABASE_URL: \$\{\{ secrets\./.test(p));
      if (conCredenziale.length) {
        for (const passo of passi) expect(passo).toInclude("VINEA_DB_CA_PEM: ${{ secrets.VINEA_DB_CA_PEM }}");
      }
    }
    // WI-016: l'invio dei segnali è un job a parte, spento, con environment proprio e permessi di sola lettura; il job
    // che sorveglia il sito e i payout resta senza environment e senza secret.
    const battito = read(".github/workflows/technical-heartbeat.yml").replace(/\r\n/g, "\n");
    const [sorveglianza, segnali] = battito.split("\n  brain-signals:\n");
    expect(sorveglianza).not.toMatch(/secrets\.|environment:/);
    expect(segnali).toInclude("needs: heartbeat");
    expect(segnali).toInclude("vars.VINEA_INGEST_ENABLED == 'true'");
    expect(segnali).toInclude("github.ref == 'refs/heads/main'");
    expect(segnali).toMatch(/permissions:\n {6}contents: read\n {6}actions: read\n(?! {6}\w)/);
    expect(segnali).not.toMatch(/: write|service_role|SERVICE_ROLE|SUPABASE_DB_URL|B2_/);
    // WI-016: il worker del Company Brain resta inerte allo stesso modo, senza pianificazione e senza chiavi
    // amministrative: GitHub non è lo scheduler.
    const worker = read(".github/workflows/company-brain-worker.yml");
    expect(worker).toInclude("workflow_dispatch:");
    expect(worker).not.toMatch(/\n {2}(push|pull_request|schedule|workflow_run):/);
    expect(worker).toInclude("if: github.ref == 'refs/heads/main' && vars.VINEA_WORKER_ENABLED == 'true'");
    expect(worker).not.toMatch(/service_role|SERVICE_ROLE|SUPABASE_DB_URL/);
    // Il workflow del catalogo resta inerte: solo dispatch manuale, solo da main, solo con la variabile esatta.
    const catalogo = read(".github/workflows/wine-catalog-cloud-import.yml");
    expect(catalogo).toInclude("workflow_dispatch:");
    expect(catalogo).not.toMatch(/\n {2}(push|pull_request|schedule):/);
    expect(catalogo).toInclude("github.ref == 'refs/heads/main'");
    expect(catalogo).toInclude("vars.CATALOG_CLOUD_IMPORT_ENABLED == 'true'");
    // Nessun trigger che esegua codice di una PR nel contesto di main.
    for (const f of workflow) expect(read(`.github/workflows/${f}`)).not.toInclude("pull_request_target");
  });

  it("CODEOWNERS copre tutto, .github e se stesso; solo la status page resta senza owner", () => {
    const righe = read(".github/CODEOWNERS")
      .split("\n")
      .map((r) => r.trim())
      .filter((r) => r && !r.startsWith("#"));
    expect(righe).toEqual([
      "*                       @enricopuntog-cpu",
      "/status-page/site/",
      "/.github/               @enricopuntog-cpu",
      "/.github/CODEOWNERS     @enricopuntog-cpu",
    ]);
  });

  it("non esegue il backup offsite senza il gate esatto", () => {
    const script = read(".github/scripts/offsite-backup.sh");
    const workflow = read(".github/workflows/offsite-backup.yml");
    expect(script).toInclude('if [[ "${BACKUP_OFFSITE_ENABLED:-}" != "true" ]]');
    expect(workflow).toInclude("vars.BACKUP_OFFSITE_ENABLED == 'true'");
  });
});
