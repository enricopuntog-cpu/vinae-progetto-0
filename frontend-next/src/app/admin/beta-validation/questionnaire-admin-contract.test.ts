import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { eAdminReale } from "@/lib/auth/role";

const root = resolve(import.meta.dir, "../../../../..");
const read = (path: string) => readFileSync(resolve(root, path), "utf8");

const route = read("frontend-next/src/app/admin/beta-validation/page.tsx");
const client = read("frontend-next/src/components/vinea/market-validation/MarketValidationAdminClient.tsx");
const panels = read("frontend-next/src/components/vinea/market-validation/Qv2AdminPanels.tsx");
const service = read("frontend-next/src/services/market-validation-questionnaire-admin-service.ts");
const domain = read("frontend-next/src/lib/market-validation/questionnaire-admin.ts");
const migration = read("supabase/migrations/20261008180000_market_validation_qv2_admin.sql");
const grid = read("supabase/tests/12u_market_validation_questionnaire_admin.sql");
const gate = read("supabase/tests/12g_ci_run.sh");
const scope = read(".github/scripts/supabase-db-gate-scope.sh");

const executableTs = (source: string) =>
  source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");
const executableSql = (source: string) => source.replace(/--.*$/gm, "");
const sql = executableSql(migration);

const PUBLIC_RPCS = [
  "beta_validation_qv2_admin_summary()",
  "beta_validation_qv2_admin_participants(text, text, integer, integer)",
  "beta_validation_qv2_admin_participant_detail(text)",
  "beta_validation_qv2_admin_distributions()",
] as const;

const count = (source: string, needle: string) => source.split(needle).length - 1;

describe("QV2 admin: accesso", () => {
  it("solo il ruolo admin reale apre la dashboard", () => {
    expect(eAdminReale(["admin"])).toBeTrue();
    expect(eAdminReale(["user", "admin"])).toBeTrue();
    for (const roles of [[], ["user"], ["moderator"], ["emergency_delegate"], ["Admin"], ["admin "]]) {
      expect(eAdminReale(roles)).toBeFalse();
    }
  });

  it("la route resta protetta da sessione, ruolo e notFound per i non-admin", () => {
    // Doppio controllo: pagina (qui) e database (12u). La route non viene
    // invocata con un mock.module di @/lib/supabase/server perché quel modulo è
    // già sostituito da altri file di test nello stesso processo.
    expect(route).toInclude("await connection();");
    expect(route).toInclude("if (!client || !utente) redirect(PERCORSO_ACCESSO);");
    expect(route).toInclude("if (!eAdminReale(ruoli)) notFound();");
    expect(route).toInclude("return <MarketValidationAdminClient />;");
    expect(route).not.toMatch(/service_role|SERVICE_ROLE|SUPABASE_SERVICE/);
  });
});

describe("QV2 admin: migration additiva e read-only", () => {
  it("crea quattro porte pubbliche e un solo helper privato", () => {
    expect(count(sql, "create function public.beta_validation_qv2_admin_")).toBe(4);
    expect(count(sql, "create function private.beta_validation_qv2_admin_rows()")).toBe(1);
    expect(count(sql, "create function")).toBe(5);
  });

  it("ogni porta ricontrolla auth.uid() e il ruolo admin in public.user_roles", () => {
    expect(count(sql, "auth.uid() is null or not exists")).toBe(4);
    expect(count(sql, "from public.user_roles ur")).toBe(4);
    expect(count(sql, "and ur.role = 'admin'")).toBe(4);
    expect(count(sql, "raise exception 'Operazione non autorizzata.' using errcode = '42501';")).toBe(4);
  });

  it("security definer, stable e search_path vuoto", () => {
    expect(count(sql, "security definer")).toBe(4);
    expect(count(sql, "set search_path = ''")).toBe(5);
    expect(count(sql, "\nstable\n")).toBe(5);
    expect(sql).not.toMatch(/\bvolatile\b/);
  });

  it("EXECUTE solo ad authenticated, mai anon o service_role", () => {
    for (const rpc of PUBLIC_RPCS) {
      expect(sql).toInclude(`revoke all on function public.${rpc} from public;`);
      expect(sql).toInclude(`revoke all on function public.${rpc} from anon;`);
      expect(sql).toInclude(`revoke all on function public.${rpc} from service_role;`);
      expect(sql).toInclude(`grant execute on function public.${rpc} to authenticated;`);
    }
    expect(sql).not.toMatch(/grant [^;]* to anon/);
    expect(sql).toInclude(
      "revoke all on function private.beta_validation_qv2_admin_rows() from public, anon, authenticated;",
    );
    expect(sql).not.toMatch(/grant [^;]*private\./);
  });

  it("non scrive, non crea tabelle e non tocca le migrazioni distribuite", () => {
    expect(sql).not.toMatch(/\b(insert into|update private|update public|delete from|create table|alter table|drop |truncate)\b/i);
    expect(sql).not.toMatch(/grant [^;]* on (table )?private\./);
  });

  it("non proietta capability, hash, UUID di sessione, IP o user-agent", () => {
    expect(sql).not.toInclude("capability_hash");
    expect(sql).not.toMatch(/user_agent|ip_address|fingerprint|email|metadata/);
    const participantsReturns = sql.slice(
      sql.indexOf("create function public.beta_validation_qv2_admin_participants("),
      sql.indexOf("language plpgsql", sql.indexOf("create function public.beta_validation_qv2_admin_participants(")),
    );
    expect(participantsReturns).not.toMatch(/session_id|capability/);
    const detail = sql.slice(sql.indexOf("create function public.beta_validation_qv2_admin_participant_detail("));
    const detailOutput = detail.slice(detail.indexOf("return jsonb_build_object("), detail.indexOf("end;\n$$;"));
    expect(detailOutput).not.toMatch(/'session_?id'|capability/i);
  });

  it("il dettaglio valida il participant_code lato server", () => {
    expect(sql).toInclude("v_code !~ '^V[0-9]{3}$' or v_code = 'V000'");
    expect(sql).toInclude("raise exception 'Codice partecipante non valido.' using errcode = '22023';");
    expect(sql).toInclude("if v_cohort is not null and v_cohort not in ('qv2', 'legacy') then");
    expect(sql).toInclude("if v_limit < 1 or v_limit > 200 then");
    expect(sql).toInclude("if v_offset < 0 or v_offset > 999 then");
  });

  it("una sola regola di aggregazione: QV2 dalla sola sessione del questionario, legacy come MV3", () => {
    expect(sql).toInclude("order by s.participant_code, s.started_at, s.id");
    expect(sql).toInclude("where p.session_id is null or p.session_id = s.id");
    expect(count(sql, "from private.beta_validation_qv2_admin_rows()")).toBe(4);
  });
});

describe("QV2 admin: griglia 12u nel gate DB", () => {
  it("è cablata nel gate 12g e negli scope", () => {
    expect(gate).toInclude(
      'run_grid "12u QV2 admin questionario" 12u_market_validation_questionnaire_admin.sql 3',
    );
    expect(scope).toInclude("supabase/tests/12u_*");
    expect(read(".github/scripts/supabase-db-gate.test.sh")).toInclude(
      "scope_for supabase/tests/12u_market_validation_questionnaire_admin.sql",
    );
  });

  it("gira in transazione chiusa da ROLLBACK con guard sugli utenti reali", () => {
    expect(grid.trimStart().split("\n").find((line) => line.trim() === "begin;")).toBeDefined();
    expect(grid.trimEnd().endsWith("rollback;")).toBeTrue();
    expect(grid).toInclude("email not like '%.test'");
    expect(grid).not.toMatch(/\bcommit;/);
  });

  it("copre dinieghi, KPI, incroci, legacy, distribuzioni, paginazione e assenza di scritture", () => {
    for (const covered of [
      "anon summary QV2 negato",
      "authenticated non-admin summary QV2 negato",
      "anon dettaglio negato",
      "authenticated non-admin distribuzioni negate",
      "tabella privata QV2 non leggibile dal client admin",
      "CORE (beta_completed) distinto da FULL (validation_completed)",
      "metriche legacy separate",
      "nessun incrocio tra sessione QV2 e sessione legacy",
      "legacy senza questionario",
      "multi-select",
      "paginazione stabile senza duplicati ne buchi",
      "participants senza capability, UUID o PII",
      "nessuna scrittura su sessioni, eventi e risposte",
      "dataset vuoto zero-safe",
    ]) {
      expect(grid).toInclude(covered);
    }
  });
});

describe("QV2 admin: client senza accesso diretto ai dati privati", () => {
  const code = executableTs(`${client}\n${panels}\n${service}\n${domain}`);

  it("usa soltanto le porte RPC, mai tabelle o storage", () => {
    expect(code).not.toMatch(/\.from\(|beta_validation_sessions|beta_validation_events|private\.|storage\./);
    for (const rpc of [
      "beta_validation_qv2_admin_summary",
      "beta_validation_qv2_admin_participants",
      "beta_validation_qv2_admin_participant_detail",
      "beta_validation_qv2_admin_distributions",
    ]) {
      expect(service).toInclude(`"${rpc}"`);
    }
  });

  it("non maneggia capability, hash o identificativi di sessione", () => {
    // La copy «Nessuna capability…» è ammessa; identificatori e campi no.
    expect(code).not.toMatch(
      /capability_hash|p_capability|\.capability\b|capability:|session_id|sessionId|user_agent|ip_address|fingerprint/,
    );
  });

  it("la dashboard è read-only: nessuna porta di scrittura QV2 o MV", () => {
    expect(code).not.toMatch(/beta_validation_qv2_(answer|start|finish_pre|finish_post|read)|beta_validation_event_record|beta_validation_session_start/);
  });

  it("espone KPI, funnel, distribuzioni, dettaglio e due export", () => {
    for (const piece of ["<Qv2KpiSection", "<Qv2FunnelCard", "<Qv2DistributionsSection", "<Qv2ParticipantDetailSheet", "<Qv2TesterTable"]) {
      expect(client).toInclude(piece);
    }
    expect(client).toInclude("buildQv2ParticipantsCsv(rows)");
    expect(client).toInclude("buildMarketValidationParticipantsCsv(rows)");
    expect(panels).toInclude("le percentuali possono superare complessivamente il 100%");
    expect(panels).toInclude("Dichiarato vs provato");
    expect(panels).toInclude("{QUESTIONNAIRE_UNAVAILABLE}");
  });
});
