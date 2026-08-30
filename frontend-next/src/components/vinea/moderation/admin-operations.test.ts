import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  ADMIN_LOOKUP_LIMIT,
  ADMIN_LOOKUP_MIN_LENGTH,
  adminOperationsLookup,
} from "@/services/phase9/admin-operations-service";

const root = join(import.meta.dir, "../../../..");
const read = (path: string) => readFileSync(join(root, path), "utf8");
const panel = read("src/components/vinea/moderation/ModerationPanelClient.tsx");
const search = read("src/components/vinea/moderation/AdminOperationsSearch.tsx");
const page = read("src/app/admin/page.tsx");
const service = read("src/services/phase9/admin-operations-service.ts");
const migration = read("../supabase/migrations/20260830191000_admin_operations_lookup.sql");

const fakeClient = (result: unknown) => {
  let call: { name: string; args: Record<string, unknown> } | null = null;
  return {
    client: {
      rpc: async (name: string, args: Record<string, unknown>) => {
        call = { name, args };
        return { data: result, error: null };
      },
    },
    getCall: () => call,
  };
};

describe("Admin Operations", () => {
  it("mantiene entrambi i gate sul ruolo reale", () => {
    expect(page).toContain("eAdminReale(ruoli)");
    expect(panel).toContain('const { authRuolo } = useVinea();');
    expect(panel).toContain('const moderatore = authRuolo === "admin";');
    expect(panel).not.toContain('ruolo === "admin"');
  });

  it("deriva KPI operativi dalle code reali", () => {
    expect(panel).toContain("const segnalazioniAperte = coda.filter");
    expect(panel).toContain("const controversieAperte = contestazioni.filter");
    expect(panel).toContain('report.priorita === "alta"');
    expect(panel).toContain('report.targetType === "annuncio" && report.stato === "in_revisione"');
    for (const id of ["kpi-open-reports", "kpi-open-disputes", "kpi-high-priority", "kpi-review-listings"]) {
      expect(panel).toContain(id);
    }
  });

  it("raggruppa la ricerca e copre loading, vuoto ed errore", () => {
    expect(search).toContain('title="Utenti"');
    expect(search).toContain('title="Annunci"');
    expect(search).toContain('title="Ordini"');
    expect(search).toContain("Ricerca in corso…");
    expect(search).toContain("Nessun risultato.");
    expect(search).toContain("La ricerca non e disponibile. Riprova.");
  });

  it("rifiuta query corte prima della RPC", async () => {
    expect(ADMIN_LOOKUP_MIN_LENGTH).toBe(2);
    const fake = fakeClient({ users: [], listings: [], orders: [] });
    await expect(adminOperationsLookup(fake.client as never, "a")).rejects.toThrow("almeno 2");
    expect(fake.getCall()).toBeNull();
  });

  it("usa una sola RPC limitata", async () => {
    expect(ADMIN_LOOKUP_LIMIT).toBe(10);
    const fake = fakeClient({ users: [], listings: [], orders: [] });
    await adminOperationsLookup(fake.client as never, "barolo");
    expect(fake.getCall()).toEqual({
      name: "admin_operations_lookup",
      args: { p_query: "barolo", p_limit: 10 },
    });
  });

  it("mantiene i risultati utente minimali e senza dati privati", () => {
    expect(search).toContain('data-testid="admin-user-result"');
    expect(search).toContain("listingCount");
    expect(search).toContain("openReportCount");
    for (const forbidden of ["email", "password", "qualification", "document", "metadata", "storage"]) {
      expect(search.toLowerCase()).not.toContain(forbidden);
    }
  });

  it("mostra annunci e ordini in sola lettura con link alle code", () => {
    expect(search).toContain('data-testid="admin-listing-result"');
    expect(search).toContain('data-testid="admin-order-result"');
    expect(search).toContain("Vai alle segnalazioni");
    expect(search).toContain("Apri contestazione");
    expect(search).toContain("onReports");
    expect(search).toContain("onDisputes");
  });

  it("non introduce azioni finanziarie o gestione ruoli", () => {
    const executable = `${search}\n${service}`.toLowerCase();
    for (const forbidden of ["refund", "capture", "release payout", "assign admin", "delete account", "approve qualification", "service_role"]) {
      expect(executable).not.toContain(forbidden);
    }
  });

  it("chiude Operazioni Admin a chi non e admin, prima di renderizzarle", () => {
    // Il gate del client non basta da solo, ma deve comunque precedere la
    // superficie: se il ritorno per non-admin venisse dopo Overview/Ricerca,
    // un utente normale vedrebbe quali comandi esistono.
    expect(page).toContain("if (!eAdminReale(ruoli)) notFound();");
    const gate = panel.indexOf("if (!moderatore) {");
    expect(gate).toBeGreaterThan(-1);
    expect(panel).toContain("<PermissionDeniedState");
    for (const superficie of ["admin-overview-title", "kpi-open-reports", "<AdminOperationsSearch"]) {
      expect(panel.indexOf(superficie)).toBeGreaterThan(gate);
    }
  });

  it("protegge la RPC nel database e limita ogni gruppo", () => {
    expect(migration).toContain("security definer");
    expect(migration).toContain("set search_path = ''");
    expect(migration).toContain("auth.uid() is null");
    expect(migration).toContain("ur.role = 'admin'");
    expect(migration).toContain("least(greatest(coalesce(p_limit, 10), 1), 20)");
    expect(migration.match(/limit v_limit/g)?.length).toBe(3);
    expect(migration).toContain("revoke all on function public.admin_operations_lookup(text, integer) from anon");
    expect(migration).toContain("grant execute on function public.admin_operations_lookup(text, integer) to authenticated");
  });
});
