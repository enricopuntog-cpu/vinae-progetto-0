import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  ADMIN_LOOKUP_LIMIT,
  ADMIN_LOOKUP_MIN_LENGTH,
  adminOperationsDetail,
  adminOperationsLookup,
  adminOperationsOverview,
} from "@/services/phase9/admin-operations-service";

const root = join(import.meta.dir, "../../../..");
const read = (path: string) => readFileSync(join(root, path), "utf8");
const panel = read("src/components/vinea/moderation/ModerationPanelClient.tsx");
const search = read("src/components/vinea/moderation/AdminOperationsSearch.tsx");
const page = read("src/app/admin/page.tsx");
const service = read("src/services/phase9/admin-operations-service.ts");
const migration = read(
  "../supabase/migrations/20260830192000_admin_operations_readonly_completion.sql",
);

const fakeClient = (result: unknown) => {
  const calls: Array<{ name: string; args: Record<string, unknown> | undefined }> = [];
  return {
    client: {
      rpc: async (name: string, args?: Record<string, unknown>) => {
        calls.push({ name, args });
        return { data: result, error: null };
      },
    },
    calls,
    getCall: () => calls.at(-1) ?? null,
  };
};

describe("Admin Operations — gate e superficie", () => {
  it("mantiene entrambi i gate sul ruolo reale", () => {
    expect(page).toContain("eAdminReale(ruoli)");
    expect(panel).toContain("const { authRuolo } = useVinea();");
    expect(panel).toContain('const moderatore = authRuolo === "admin";');
    expect(panel).not.toContain('ruolo === "admin"');
  });

  it("chiude Operazioni Admin a chi non e admin, prima di renderizzarle", () => {
    expect(page).toContain("if (!eAdminReale(ruoli)) notFound();");
    const gate = panel.indexOf("if (!moderatore) {");
    expect(gate).toBeGreaterThan(-1);
    expect(panel).toContain("<PermissionDeniedState");
    for (const superficie of ["admin-overview-title", "kpi-open-reports", "<AdminOperationsSearch"]) {
      expect(panel.indexOf(superficie)).toBeGreaterThan(gate);
    }
  });

  it("non chiede i KPI quando chi guarda non e admin", () => {
    // L'effetto esce prima della chiamata: un non-admin non deve nemmeno
    // bussare alla porta per sentirsi rispondere 42501.
    expect(panel).toContain("if (!moderatore) return;");
    expect(panel).toContain("adminOperationsOverview(getSupabaseClient())");
  });

  it("presenta le otto sezioni finali e non lascia una tab Ricerca generica", () => {
    const sezioni = ["overview", "coda", "controversie", "utenti", "annunci", "ordini", "club", "audit"];
    for (const sezione of sezioni) {
      expect(panel).toContain(`<TabsTrigger value="${sezione}">`);
    }
    expect(panel).toContain("<TabsTrigger value=\"utenti\">Utenti</TabsTrigger>");
    expect(panel).toContain("<TabsTrigger value=\"club\">Club</TabsTrigger>");
    expect(panel).not.toContain('<TabsTrigger value="ricerca">');
    expect(panel.match(/<TabsTrigger value=/g)?.length).toBe(sezioni.length);
  });
});

describe("Admin Operations — difetti corretti", () => {
  it("indirizza il profilo pubblico per UUID e non per username", () => {
    expect(search).toContain("href={`/profilo/${encodeURIComponent(entity.id)}`}");
    expect(search).not.toContain("/profilo/${encodeURIComponent(result.username)}");
    expect(search).not.toContain("/profilo/${result.username}");
  });

  it("non promette piu un codice ordine ricercabile", () => {
    expect(search.toLowerCase()).not.toContain("codice ordine");
    expect(search).toContain("UUID ordine (identificativo esatto)");
    expect(search).toContain("Solo UUID esatto: gli ordini non hanno un codice ricercabile.");
  });

  it("prende gli annunci in revisione da listings e non dalle segnalazioni", () => {
    expect(panel).toContain("overview.listingsInReview");
    expect(panel).toContain("kpi-review-listings");
    // Il KPI vecchio deduceva lo stato dell'annuncio dallo stato della pratica.
    expect(panel).not.toContain('report.targetType === "annuncio" && report.stato === "in_revisione"');
    expect(migration).toContain("l.stato = 'in_revisione'::public.listing_stato");
  });

  it("espone anche gli annunci realmente sospesi", () => {
    expect(panel).toContain("overview.listingsSuspended");
    expect(panel).toContain("kpi-suspended-listings");
    expect(migration).toContain("l.stato = 'sospeso'::public.listing_stato");
  });

  it("porta ogni KPI a una destinazione coerente", () => {
    for (const id of [
      "kpi-open-reports",
      "kpi-open-disputes",
      "kpi-high-priority",
      "kpi-info-requested",
      "kpi-review-listings",
      "kpi-suspended-listings",
    ]) {
      expect(panel).toContain(id);
    }
    expect(panel).toContain('focalizzaCoda({ kind: "priorita-alta"');
    expect(panel).toContain('focalizzaCoda({ kind: "info-richieste"');
    expect(panel).toContain('onClick: () => vaiA("annunci")');
  });
});

describe("Admin Operations — servizio", () => {
  it("rifiuta query corte prima della RPC", async () => {
    expect(ADMIN_LOOKUP_MIN_LENGTH).toBe(2);
    const fake = fakeClient({ users: [], listings: [], orders: [], clubs: [] });
    await expect(adminOperationsLookup(fake.client as never, "a")).rejects.toThrow("almeno 2");
    expect(fake.getCall()).toBeNull();
  });

  it("usa una sola RPC limitata e restituisce anche i club", async () => {
    expect(ADMIN_LOOKUP_LIMIT).toBe(10);
    const fake = fakeClient({
      users: [],
      listings: [],
      orders: [],
      clubs: [{ slug: "barolo-club", nome: "Barolo Club", ownerId: null, ownerUsername: null, createdAt: null, postingMode: "OPEN", openReportCount: 0 }],
    });
    const risultati = await adminOperationsLookup(fake.client as never, "barolo");
    expect(fake.getCall()).toEqual({
      name: "admin_operations_lookup",
      args: { p_query: "barolo", p_limit: 10 },
    });
    expect(risultati.clubs).toHaveLength(1);
    expect(risultati.clubs[0]?.slug).toBe("barolo-club");
  });

  it("legge i KPI da una porta dedicata, senza argomenti", async () => {
    const fake = fakeClient({
      openReports: 4,
      highPriorityReports: 1,
      infoRequestedReports: 2,
      openDisputes: 3,
      listingsInReview: 7,
      listingsSuspended: 5,
    });
    const overview = await adminOperationsOverview(fake.client as never);
    expect(fake.getCall()?.name).toBe("admin_operations_overview");
    expect(overview.listingsInReview).toBe(7);
    expect(overview.listingsSuspended).toBe(5);
  });

  it("apre il dettaglio su identificatore esatto e per ambito", async () => {
    const fake = fakeClient({ tipo: "utente", entity: { id: "u1" }, reports: [] });
    await adminOperationsDetail(fake.client as never, "utente", "  enrico  ");
    expect(fake.getCall()).toEqual({
      name: "admin_operations_detail",
      args: { p_tipo: "utente", p_identificatore: "enrico" },
    });
    await expect(adminOperationsDetail(fake.client as never, "club", "a")).rejects.toThrow(
      "Identificatore non valido.",
    );
  });
});

describe("Admin Operations — le quattro sezioni", () => {
  it("condivide una sola ricerca configurata per ambito", () => {
    for (const scope of ["utente", "annuncio", "ordine", "club"]) {
      expect(panel).toContain(`scope="${scope}"`);
    }
    expect(panel.match(/<AdminOperationsSearch/g)?.length).toBe(4);
    expect(search).toContain("const SCOPE_UX: Record<AdminScope");
  });

  it("copre ricerca, caricamento, vuoto, errore, risultati e dettaglio", () => {
    expect(search).toContain('role="search"');
    expect(search).toContain("Ricerca in corso…");
    expect(search).toContain("Apertura dettaglio…");
    expect(search).toContain("Nessun risultato.");
    expect(search).toContain("La ricerca non e disponibile. Riprova.");
    expect(search).toContain("Il dettaglio non e disponibile. Riprova.");
    expect(search).toContain('data-testid="admin-detail-back"');
    expect(search).toContain("← Torna ai risultati");
  });

  it("mostra utenti in ricerca e in dettaglio", () => {
    expect(search).toContain('data-testid="admin-user-result"');
    expect(search).toContain('data-testid="admin-user-detail"');
    expect(search).toContain("Username oppure UUID utente");
    expect(search).toContain("orderCountAsBuyer");
    expect(search).toContain("recentListings");
  });

  it("mostra annunci in ricerca e in dettaglio", () => {
    expect(search).toContain('data-testid="admin-listing-result"');
    expect(search).toContain('data-testid="admin-listing-detail"');
    expect(search).toContain("UUID annuncio, slug, vino o produttore");
    expect(search).toContain("href={`/annuncio/${encodeURIComponent(entity.slug)}`}");
  });

  it("mostra ordini in ricerca e in dettaglio", () => {
    expect(search).toContain('data-testid="admin-order-result"');
    expect(search).toContain('data-testid="admin-order-detail"');
    expect(search).toContain("Stato payout");
    expect(search).toContain("ID contestazione");
  });

  it("mostra club in ricerca e in dettaglio", () => {
    expect(search).toContain('data-testid="admin-club-result"');
    expect(search).toContain('data-testid="admin-club-detail"');
    expect(search).toContain("Nome oppure slug del club");
    expect(search).toContain("href={`/community/${encodeURIComponent(entity.slug)}`}");
  });
});

describe("Admin Operations — focus correlato", () => {
  it("focalizza le segnalazioni di un utente sul suo id", () => {
    expect(search).toContain('data-testid="admin-focus-user-reports"');
    expect(search).toContain('onFocusReports({ kind: "profilo", id: entity.id');
    expect(panel).toContain('return report.targetType === "profilo" && report.targetId === focus.id;');
  });

  it("focalizza le segnalazioni di un annuncio sul suo id", () => {
    expect(search).toContain('data-testid="admin-focus-listing-reports"');
    expect(search).toContain('onFocusReports({ kind: "annuncio", id: entity.id');
    expect(panel).toContain('return report.targetType === "annuncio" && report.targetId === focus.id;');
  });

  it("focalizza le segnalazioni di un club sullo slug e non sul targetId", () => {
    // Una segnalazione diretta su un Club puo avere targetId vuoto.
    expect(search).toContain('data-testid="admin-focus-club-reports"');
    expect(search).toContain('onFocusReports({ kind: "club", slug: entity.slug');
    expect(panel).toContain('return report.targetType === "club" && report.clubSlug === focus.slug;');
  });

  it("focalizza la contestazione sull'ordine esatto", () => {
    expect(search).toContain('data-testid="admin-focus-order-dispute"');
    expect(search).toContain("onFocusDispute({ orderId: entity.id");
    expect(panel).toContain("riga.orderId === focusContestazione.orderId");
  });

  it("non si limita a cambiare scheda e offre sempre la via d'uscita", () => {
    expect(panel).toContain("setFocusCoda(focus);");
    expect(panel).toContain('setTab("coda");');
    expect(panel).toContain("setFocusContestazione(focus);");
    expect(panel).toContain('setTab("controversie");');
    expect(panel).toContain("Rimuovi filtro");
    expect(panel).toContain('testId="admin-coda-filtro"');
    expect(panel).toContain('testId="admin-controversie-filtro"');
    expect(panel).toContain("data-testid={testId}");
    expect(panel).toContain("setFocusCoda(null)");
    expect(panel).toContain("setFocusContestazione(null)");
  });
});

describe("Admin Operations — confini della BUILD read-only", () => {
  it("non introduce gestione ruoli o azioni sull'account", () => {
    const eseguibile = `${search}\n${service}`.toLowerCase();
    for (const vietato of [
      "assign admin",
      "delete account",
      "grant role",
      "approve qualification",
      "suspend user",
      "sospendi account",
    ]) {
      expect(eseguibile).not.toContain(vietato);
    }
    expect(migration).not.toContain("insert into");
    expect(migration).not.toContain("update public.");
    expect(migration).not.toContain("delete from");
  });

  it("non introduce azioni finanziarie o sul provider", () => {
    const eseguibile = `${search}\n${service}`.toLowerCase();
    for (const vietato of ["refund", "capture", "payout release", "release payout", "transfer_data", "on_behalf_of", "stripe", "service_role"]) {
      expect(eseguibile).not.toContain(vietato);
    }
    // La scheda Ordini rimanda alla contestazione e non nega gli effetti del
    // workflow D10: dichiara soltanto l'assenza di leve manuali di pagamento.
    expect(search).toContain(
      "La decisione chiude la contestazione secondo il workflow esistente",
    );
    expect(search).toContain("Il rimborso e le operazioni");
  });

  it("tiene fuori i dati privati dalla superficie Admin", () => {
    for (const vietato of ["email", "password", "qualification", "document", "metadata", "storage", "data_di_nascita", "date_of_birth"]) {
      expect(search.toLowerCase()).not.toContain(vietato);
      expect(migration.toLowerCase()).not.toContain(vietato);
    }
  });
});

describe("Admin Operations — la nuova migrazione", () => {
  it("protegge ogni porta con il ruolo reale e un search_path vuoto", () => {
    expect(migration.match(/security definer/g)?.length).toBe(3);
    expect(migration.match(/set search_path = ''/g)?.length).toBe(3);
    expect(migration.match(/stable/g)?.length).toBe(3);
    expect(migration.match(/auth\.uid\(\) is null/g)?.length).toBe(3);
    expect(migration.match(/ur\.role = 'admin'/g)?.length).toBe(3);
  });

  it("nega anon e service_role e concede solo authenticated", () => {
    for (const fn of [
      "public.admin_operations_lookup(text, integer)",
      "public.admin_operations_overview()",
      "public.admin_operations_detail(text, text)",
    ]) {
      for (const ruolo of ["public", "anon", "authenticated", "service_role"]) {
        expect(migration).toContain(`revoke all on function ${fn} from ${ruolo};`);
      }
      expect(migration).toContain(`grant execute on function ${fn} to authenticated;`);
    }
  });

  it("mantiene il tetto sui risultati e il minimo sulla query", () => {
    expect(migration).toContain("least(greatest(coalesce(p_limit, 10), 1), 20)");
    expect(migration).toContain("Inserisci almeno 2 caratteri.");
    expect(migration.match(/limit v_limit/g)?.length).toBe(4);
    expect(migration.match(/limit 10/g)?.length).toBe(2);
  });

  it("aggiunge i club e cerca gli ordini solo per UUID esatto", () => {
    expect(migration).toContain("'clubs', v_clubs");
    expect(migration).toContain("from public.clubs c");
    expect(migration).toContain("rep.club_slug = c.slug");
    expect(migration).toContain("where o.id = v_exact_uuid");
  });

  it("non tocca la migrazione gia congelata e non apre una porta _v2", () => {
    const congelata = read("../supabase/migrations/20260830191000_admin_operations_lookup.sql");
    expect(congelata).toContain("'orders', v_orders\n  );");
    expect(congelata).not.toContain("v_clubs");
    expect(migration).not.toContain("_v2");
    expect(migration).not.toContain("admin_v2");
  });
});
