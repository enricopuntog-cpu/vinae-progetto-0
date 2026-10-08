import { describe, expect, it } from "bun:test";
import { renderToStaticMarkup } from "react-dom/server";
import {
  Qv2DistributionsSection,
  Qv2FunnelCard,
  Qv2KpiSection,
  Qv2ParticipantDetailView,
  Qv2TesterTable,
} from "@/components/vinea/market-validation/Qv2AdminPanels";
import {
  EMPTY_QV2_DISTRIBUTIONS,
  parseQv2AdminParticipantsPage,
  parseQv2AdminSummary,
  parseQv2Distributions,
  parseQv2ParticipantDetail,
  type Qv2ParticipantDetail,
} from "@/lib/market-validation/questionnaire-admin";

// Render server-side reale dei pannelli: ciò che l'admin legge, non il sorgente.
const html = (node: React.ReactNode) => renderToStaticMarkup(<>{node}</>);
const text = (markup: string) => markup.replace(/<[^>]+>/g, " ").replace(/&#x27;/g, "'").replace(/&quot;/g, '"').replace(/\s+/g, " ");

const summary = parseQv2AdminSummary({
  qv2: {
    started: 4, preCompleted: 3, buyCompleted: 2, sellCompleted: 2, aiViewed: 2, clubViewed: 2, cellarViewed: 1,
    experienceCompleted: 1, coreCompleted: 1, postCompleted: 1, validationCompleted: 1, completionRate: 25,
  },
  legacy: { codes: 2, coreCompleted: 1, coreCompletionRate: 50 },
  allCodes: 6,
});

const detail = (overrides: Record<string, unknown> = {}): Qv2ParticipantDetail => {
  const parsed = parseQv2ParticipantDetail({
    participantCode: "V001",
    cohort: "qv2",
    sessionsCount: 1,
    startedAt: "2026-10-05T09:00:00+00:00",
    lastActivityAt: "2026-10-05T09:50:00+00:00",
    events: [
      { event: "checkout_beta_completed", count: 1, firstAt: "2026-10-05T09:17:00+00:00", lastAt: "2026-10-05T09:17:00+00:00" },
      { event: "marketplace_viewed", count: 2, firstAt: "2026-10-05T09:11:00+00:00", lastAt: "2026-10-05T09:12:00+00:00" },
    ],
    completion: { preCompletedAt: "2026-10-05T09:10:00+00:00", coreCompletedAt: null, postCompletedAt: null, validationCompletedAt: null },
    questionnaire: {
      q01: "25_34",
      q02: "enthusiast",
      q05: ["wine_shop", "other"],
      q05_other: "Fiere",
      q15: "no",
      q15_why_not: "Prezzi alti",
      final_feedback: null,
    },
    ...overrides,
  });
  if (!parsed) throw new Error("dettaglio non valido");
  return parsed;
};

describe("Pannelli admin QV2 renderizzati", () => {
  it("KPI con etichette comprensibili, cinque aree e 5/5 distinto da FULL", () => {
    const output = text(html(<Qv2KpiSection summary={summary} />));
    for (const label of [
      "Test iniziati", "PRE completati", "Acquisto completato", "Vendita completata", "Vinea AI visitata",
      "Club visitato", "Cantina visitata", "Prova Vinea 5/5", "POST completati", "Market Validation completate",
      "Completion rate",
    ]) {
      expect(output).toInclude(label);
    }
    expect(output).toInclude("1 complete su 4 test iniziati");
    expect(output).toInclude("25%");
  });

  it("funnel con numeri, base e percentuali", () => {
    const output = text(html(<Qv2FunnelCard summary={summary} />));
    expect(output).toInclude("PRE completato");
    expect(output).toInclude("3 su 4 · 75%");
    expect(output).toInclude("Market Validation completa");
    expect(output).toInclude("1 su 4 · 25%");
    expect(output).toInclude("Prova Vinea 5/5");
    expect(output.match(/percorso indipendente/g)).toHaveLength(5);
  });

  it("tabella compatta con ✓/— e legacy senza stati PRE/POST", () => {
    const page = parseQv2AdminParticipantsPage([
      { participant_code: "V001", cohort: "qv2", pre_completed_at: "2026-10-05T09:10:00+00:00", checkout_beta_completed: 1, beta_completed: 1, total_count: 2 },
      { participant_code: "V017", cohort: "legacy", beta_completed: 1, total_count: 2 },
    ]);
    const markup = html(<Qv2TesterTable participants={page.participants} onOpen={() => undefined} />);
    const output = text(markup);
    expect(output).toInclude("V001");
    expect(output).toInclude("V017");
    expect(output).toInclude("QV2");
    expect(output).toInclude("Legacy");
    expect(markup).toInclude('aria-label="Questionario PRE completato: sì"');
    expect(markup).toInclude('aria-label="Vendita completata (sell_completed): no"');
    expect(markup).toInclude('aria-label="Cantina visualizzata (cellar_viewed): no"');
    for (const label of ["BUY", "SELL", "AI", "CLUB", "CELLAR", "5/5", "FULL"]) expect(output).toInclude(label);
    expect(markup).toInclude('title="Non previsto nel percorso legacy"');
    expect(markup.match(/<tr/g)).toHaveLength(3);
  });

  it("dettaglio: risposte decodificate, condizionali, eventi e Non risposto", () => {
    const output = text(html(<Qv2ParticipantDetailView detail={detail()} />));
    expect(output).toInclude("A · Questionario PRE");
    expect(output).toInclude("B · Comportamento reale");
    expect(output).toInclude("C · Questionario POST");
    expect(output).toInclude("D · Completamento");
    expect(output).toInclude("Dichiarato vs provato");
    expect(output).toInclude("Appassionato");
    expect(output).not.toInclude("enthusiast");
    expect(output).toInclude("Enoteca");
    expect(output).toInclude("Dove altro?: Fiere");
    expect(output).toInclude("Perché?: Prezzi alti");
    expect(output).toInclude("Non risposto");
    expect(output).toInclude("Marketplace visualizzato");
    expect(output).toInclude("2×");
    expect(output).toInclude("non registrato");
  });

  it("dettaglio: stato PRE, cinque aree, EXPERIENCE 5/5, POST e COMPLETE", () => {
    const fullMarkup = html(<Qv2ParticipantDetailView detail={detail({
      events: ["checkout_beta_completed", "sell_completed", "ai_preview_viewed", "club_viewed", "cellar_viewed", "beta_completed"]
        .map((event) => ({ event, count: 1, firstAt: "2026-10-05T09:20:00+00:00", lastAt: "2026-10-05T09:20:00+00:00" })),
      completion: {
        preCompletedAt: "2026-10-05T09:10:00+00:00", experienceCompleted: true, coreCompletedAt: "2026-10-05T09:30:00+00:00",
        postCompletedAt: "2026-10-05T09:50:00+00:00", validationCompletedAt: "2026-10-05T09:50:00+00:00",
      },
    })} />);
    const full = text(fullMarkup);
    for (const label of ["PRE: sì", "ACQUISTO: sì", "VENDITA: sì", "AI: sì", "CLUB: sì", "CANTINA: sì", "EXPERIENCE 5/5: sì", "POST: sì", "COMPLETE: sì"]) {
      expect(fullMarkup).toInclude(`aria-label="${label}"`);
    }
    expect(full).toInclude("Cantina visualizzata");
    expect(full).not.toInclude("regola precedente");

    const previous = html(<Qv2ParticipantDetailView detail={detail({
      events: ["checkout_beta_completed", "sell_completed", "ai_preview_viewed", "beta_completed"]
        .map((event) => ({ event, count: 1, firstAt: "2026-10-05T09:20:00+00:00", lastAt: "2026-10-05T09:20:00+00:00" })),
      completion: {
        preCompletedAt: "2026-10-05T09:10:00+00:00", experienceCompleted: false, coreCompletedAt: "2026-10-05T09:30:00+00:00",
        postCompletedAt: null, validationCompletedAt: null,
      },
    })} />);
    expect(previous).toInclude('aria-label="EXPERIENCE 3/5: no"');
    expect(previous).toInclude('aria-label="CANTINA: no"');
    expect(text(previous)).toInclude("regola precedente (Acquisto + Vendita)");
  });

  it("dettaglio legacy: questionario non disponibile, senza risposte inventate", () => {
    const output = text(html(<Qv2ParticipantDetailView detail={detail({ cohort: "legacy", sessionsCount: 2 })} />));
    expect(output).toInclude("Questionario non disponibile");
    expect(output).toInclude("2 sessioni aggregate");
    expect(output).not.toInclude("Appassionato");
    expect(output).not.toInclude("Feedback finale");
  });

  it("distribuzioni con base, conteggi, percentuali e nota multi-select", () => {
    const output = text(html(
      <Qv2DistributionsSection
        distributions={parseQv2Distributions({
          respondents: 3,
          preCompleted: 3,
          postCompleted: 0,
          questions: {
            q01: { base: 3, counts: { "25_34": 2, "45_54": 1 } },
            q05: { base: 3, counts: { wine_shop: 2, producer: 2 } },
          },
        })}
      />,
    ));
    expect(output).toInclude("Base: 3 rispondenti");
    expect(output).toInclude("2 · 66,7%");
    expect(output).toInclude("le percentuali possono superare complessivamente il 100%");
    expect(output).toInclude("Nessuna risposta registrata.");
  });

  it("zero-data state: nessuna distribuzione inventata", () => {
    const output = text(html(<Qv2DistributionsSection distributions={EMPTY_QV2_DISTRIBUTIONS} />));
    expect(output).toInclude("Nessuna risposta QV2 registrata.");
    expect(output).not.toInclude("Base:");
  });
});
