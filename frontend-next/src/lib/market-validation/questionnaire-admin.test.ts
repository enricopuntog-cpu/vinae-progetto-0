import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { QUESTIONS, Q10_ACTIONS } from "@/lib/market-validation/questionnaire";
import {
  EMPTY_QV2_ADMIN_SUMMARY,
  NOT_ANSWERED,
  QV2_CSV_HEADERS,
  QV2_DETAIL_EVENTS,
  QV2_DISTRIBUTION_QUESTIONS,
  UNKNOWN_VALUE,
  buildQuestionDistribution,
  buildQv2Funnel,
  buildQv2ParticipantsCsv,
  decodeAnswer,
  decodeQuestionnaire,
  parseQv2AdminParticipant,
  parseQv2AdminParticipantsPage,
  parseQv2AdminSummary,
  parseQv2Answers,
  parseQv2CohortFilter,
  parseQv2Distributions,
  parseQv2ParticipantDetail,
  qv2CsvExportScope,
  qv2TesterStatus,
  type Qv2AdminParticipant,
} from "@/lib/market-validation/questionnaire-admin";

const AT = "2026-10-05T09:10:00+00:00";

const qv2Row = (overrides: Record<string, unknown> = {}) => ({
  participant_code: "V001",
  cohort: "qv2",
  sessions_count: 1,
  started_at: "2026-10-05T09:00:00+00:00",
  last_activity_at: "2026-10-05T09:50:00+00:00",
  pre_completed_at: AT,
  core_completed_at: "2026-10-05T09:40:00+00:00",
  post_completed_at: "2026-10-05T09:50:00+00:00",
  validation_completed_at: "2026-10-05T09:50:00+00:00",
  marketplace_viewed: 2,
  demo_listing_viewed: 1,
  favorite_added: 1,
  checkout_started: 1,
  shipping_cost_viewed: 1,
  checkout_beta_completed: 1,
  sell_started: 1,
  sell_photo_selected: 0,
  sell_completed: 1,
  ai_preview_viewed: 1,
  ai_interest_clicked: 0,
  club_viewed: 1,
  beta_completed: 1,
  q01: "25_34",
  q02: "other",
  q02_other: "Sommelier amatoriale",
  q03: "one_two_month",
  q04: "20_40",
  q05: ["wine_shop", "producer", "other"],
  q05_other: "=Mercatini",
  q06: "yes",
  q06_where: "Mercatino",
  q06_why: "Prezzo; migliore",
  q07: ["authenticity", "shipping"],
  q08: "Garanzia di \"autenticità\"",
  q09: "one_five",
  q10: "yes",
  q10_actions: ["gifted", "other"],
  q10_other: "Asta di beneficenza",
  q11: "once",
  q11_where: "Forum",
  q11_main_difficulty: "Fiducia",
  q12: "six_nine",
  q13: "ten_twelve",
  q14: "buy",
  q15: "no",
  q15_why_not: "Prezzi alti",
  q16: "maybe",
  q17: "Spedizione\nlenta",
  q18: "+Più foto",
  q19: ["protected_payment", "authenticity_guarantee"],
  q20: "both",
  final_feedback: "@ottimo",
  total_count: 3,
  ...overrides,
});

const legacyRow = (overrides: Record<string, unknown> = {}) => ({
  ...Object.fromEntries(Object.entries(qv2Row()).map(([key, value]) => [key, /^q\d|final/.test(key) ? null : value])),
  participant_code: "V017",
  cohort: "legacy",
  sessions_count: 2,
  pre_completed_at: null,
  post_completed_at: null,
  validation_completed_at: null,
  ...overrides,
});

const parsed = (row: Record<string, unknown>): Qv2AdminParticipant => {
  const participant = parseQv2AdminParticipant(row);
  if (!participant) throw new Error("riga non valida");
  return participant;
};

// Parser CSV minimale (RFC 4180 con «;») per verificare celle e escaping.
const parseCsv = (text: string): string[][] => {
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = "";
  let quoted = false;
  for (let index = 0; index < text.length; index++) {
    const char = text[index];
    if (quoted) {
      if (char === '"' && text[index + 1] === '"') { cell += '"'; index++; }
      else if (char === '"') quoted = false;
      else cell += char;
    } else if (char === '"') quoted = true;
    else if (char === ";") { row.push(cell); cell = ""; }
    else if (char === "\r" && text[index + 1] === "\n") { row.push(cell); rows.push(row); row = []; cell = ""; index++; }
    else cell += char;
  }
  return rows;
};

describe("QV2 admin: summary e funnel", () => {
  it("normalizza KPI QV2 e legacy separati", () => {
    const summary = parseQv2AdminSummary({
      qv2: { started: 4, preCompleted: 3, buyCompleted: 2, sellCompleted: 2, coreCompleted: 1, postCompleted: 1, validationCompleted: 1, completionRate: 25, favoriteAdded: 1 },
      legacy: { codes: 2, coreCompleted: 1, coreCompletionRate: 50 },
      allCodes: 6,
    });
    expect(summary.qv2.started).toBe(4);
    expect(summary.qv2.completionRate).toBe(25);
    expect(summary.legacy).toEqual({ codes: 2, coreCompleted: 1, favoriteAdded: 0, coreCompletionRate: 50 });
    expect(summary.allCodes).toBe(6);
  });

  it("rende zero ciò che è assente, negativo o fuori scala", () => {
    expect(parseQv2AdminSummary(null)).toEqual(EMPTY_QV2_ADMIN_SUMMARY);
    const summary = parseQv2AdminSummary({ qv2: { started: -3, completionRate: 140 }, legacy: { coreCompletionRate: "50" } });
    expect(summary.qv2.started).toBe(0);
    expect(summary.qv2.completionRate).toBe(100);
    expect(summary.legacy.coreCompletionRate).toBe(0);
  });

  it("funnel con base fissa sui test iniziati e CORE distinto da FULL", () => {
    const steps = buildQv2Funnel(parseQv2AdminSummary({
      qv2: { started: 4, preCompleted: 3, buyCompleted: 2, sellCompleted: 1, coreCompleted: 1, postCompleted: 1, validationCompleted: 0 },
    }));
    expect(steps.map((step) => step.key)).toEqual(["started", "pre", "buy", "sell", "core", "post", "full"]);
    expect(steps.every((step) => step.denominator === 4)).toBeTrue();
    expect(steps.map((step) => step.value)).toEqual([4, 3, 2, 1, 1, 1, 0]);
    expect(steps.map((step) => step.rate)).toEqual([100, 75, 50, 25, 25, 25, 0]);
    expect(steps.find((step) => step.key === "core")?.label).toBe("Core Beta completata");
    expect(steps.find((step) => step.key === "full")?.label).toBe("Market Validation completa");
  });

  it("acquisto e vendita sono passi paralleli, non ordinati", () => {
    const steps = buildQv2Funnel(parseQv2AdminSummary({ qv2: { started: 2, buyCompleted: 0, sellCompleted: 2 } }));
    expect(steps.filter((step) => step.parallel).map((step) => step.key)).toEqual(["buy", "sell"]);
    // La vendita può superare l'acquisto: nessun vincolo di ordine o di monotonia.
    expect(steps.find((step) => step.key === "sell")?.rate).toBe(100);
  });

  it("non divide per zero senza dati QV2", () => {
    const steps = buildQv2Funnel(EMPTY_QV2_ADMIN_SUMMARY);
    expect(steps.every((step) => step.rate === 0 && step.value === 0 && step.denominator === 0)).toBeTrue();
  });
});

describe("QV2 admin: elenco tester", () => {
  it("collega risposte e conteggi di una riga QV2", () => {
    const participant = parsed(qv2Row());
    expect(participant.cohort).toBe("qv2");
    expect(participant.answers?.q05).toEqual(["wine_shop", "producer", "other"]);
    expect(participant.answers?.q02_other).toBe("Sommelier amatoriale");
    expect(participant.events.marketplaceViewed).toBe(2);
  });

  it("non inventa risposte per i legacy anche se arrivano colonne", () => {
    const participant = parsed(legacyRow({ q01: "25_34" }));
    expect(participant.cohort).toBe("legacy");
    expect(participant.answers).toBeNull();
    expect(participant.sessionsCount).toBe(2);
  });

  it("scarta codici o coorti malformati e non conserva identificativi di sessione", () => {
    expect(parseQv2AdminParticipant(qv2Row({ participant_code: "V000" }))).toBeNull();
    expect(parseQv2AdminParticipant(qv2Row({ cohort: "mv3" }))).toBeNull();
    const participant = parsed(qv2Row({ session_id: "12bc0000-0000-4000-8000-000000000101", capability_hash: "a".repeat(64) }));
    expect(JSON.stringify(participant)).not.toMatch(/session_id|capability|12bc0000/);
  });

  it("legge il totale della paginazione e scarta righe invalide", () => {
    const page = parseQv2AdminParticipantsPage([qv2Row(), qv2Row({ participant_code: "V000" }), legacyRow()]);
    expect(page.participants.map((participant) => participant.participantCode)).toEqual(["V001", "V017"]);
    expect(page.total).toBe(3);
    expect(parseQv2AdminParticipantsPage([])).toEqual({ participants: [], total: 0 });
    expect(parseQv2AdminParticipantsPage({ not: "array" })).toEqual({ participants: [], total: 0 });
  });

  it("distingue CORE (beta_completed) da COMPLETE (validation_completed)", () => {
    const coreOnly = qv2TesterStatus(parsed(qv2Row({ post_completed_at: null, validation_completed_at: null })));
    expect(coreOnly.core).toBeTrue();
    expect(coreOnly.post).toBeFalse();
    expect(coreOnly.complete).toBeFalse();
    const full = qv2TesterStatus(parsed(qv2Row()));
    expect(full).toEqual({ pre: true, buy: true, sell: true, core: true, ai: true, club: true, post: true, complete: true });
    const fresh = qv2TesterStatus(parsed(qv2Row({
      pre_completed_at: null, post_completed_at: null, validation_completed_at: null,
      checkout_beta_completed: 0, sell_completed: 0, beta_completed: 0, ai_preview_viewed: 0, club_viewed: 0,
    })));
    expect(Object.values(fresh).every((value) => value === false)).toBeTrue();
  });

  it("accetta soltanto le coorti chiuse come filtro", () => {
    expect(parseQv2CohortFilter("qv2")).toBe("qv2");
    expect(parseQv2CohortFilter("legacy")).toBe("legacy");
    expect(parseQv2CohortFilter("tutti")).toBeNull();
  });
});

describe("QV2 admin: decodifica Q1–Q20", () => {
  const answers = parsed(qv2Row()).answers!;

  it("decodifica ogni codice chiuso con le label approvate", () => {
    for (const question of QUESTIONS.filter((item) => item.kind !== "text")) {
      for (const [code, label] of question.options ?? []) {
        const key = `q${String(question.number).padStart(2, "0")}`;
        const decoded = decodeAnswer(question.number, parseQv2Answers({ [key]: question.kind === "multi" ? [code] : code }));
        expect(decoded.values).toEqual([label]);
      }
    }
    expect(decodeAnswer(2, parseQv2Answers({ q02: "enthusiast" })).values).toEqual(["Appassionato"]);
  });

  it("copre Q1–Q13 nel PRE e Q14–Q20 nel POST", () => {
    expect(decodeQuestionnaire(answers, 1, 13).map((item) => item.number)).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]);
    expect(decodeQuestionnaire(answers, 14, 20).map((item) => item.number)).toEqual([14, 15, 16, 17, 18, 19, 20]);
    expect(decodeQuestionnaire(answers, 1, 20).every((item) => item.answered)).toBeTrue();
  });

  it("mantiene l'ordine registrato delle scelte multiple", () => {
    expect(decodeAnswer(5, answers).values).toEqual(["Enoteca", "Produttore", "Altro"]);
    expect(decodeAnswer(19, answers).values).toEqual(["Pagamento protetto", "Garanzia autenticità"]);
    const reversed = parseQv2Answers({ q07: ["shipping", "authenticity"] });
    expect(decodeAnswer(7, reversed).values).toEqual(["Spedizione", "Autenticità"]);
  });

  it("mostra i campi condizionali con le label della UI pubblica", () => {
    const label = (number: number, field: "condition" | "secondCondition") =>
      QUESTIONS[number - 1][field]?.label;
    expect(decodeAnswer(2, answers).extras).toEqual([{ label: label(2, "condition")!, value: "Sommelier amatoriale" }]);
    expect(decodeAnswer(5, answers).extras).toEqual([{ label: label(5, "condition")!, value: "=Mercatini" }]);
    expect(decodeAnswer(6, answers).extras).toEqual([
      { label: label(6, "condition")!, value: "Mercatino" },
      { label: label(6, "secondCondition")!, value: "Prezzo; migliore" },
    ]);
    expect(decodeAnswer(10, answers).extras).toEqual([
      { label: label(10, "condition")!, value: "Regalate, Altro" },
      { label: Q10_ACTIONS.find(([code]) => code === "other")![1], value: "Asta di beneficenza" },
    ]);
    expect(decodeAnswer(11, answers).extras.map((extra) => extra.value)).toEqual(["Forum", "Fiducia"]);
    expect(decodeAnswer(15, answers).extras).toEqual([{ label: label(15, "condition")!, value: "Prezzi alti" }]);
  });

  it("non mostra condizionali assenti e segnala le domande senza risposta", () => {
    const partial = parseQv2Answers({ q01: "45_54", q06: "no", q11: "never" });
    expect(decodeAnswer(6, partial).extras).toEqual([]);
    expect(decodeAnswer(11, partial).extras).toEqual([]);
    const missing = decodeAnswer(2, partial);
    expect(missing.answered).toBeFalse();
    expect(missing.values).toEqual([]);
    expect(decodeAnswer(8, partial).answered).toBeFalse();
    expect(NOT_ANSWERED).toBe("Non risposto");
  });

  it("restituisce i testi aperti senza alterarli", () => {
    expect(decodeAnswer(8, answers).values).toEqual(['Garanzia di "autenticità"']);
    expect(decodeAnswer(17, answers).values).toEqual(["Spedizione\nlenta"]);
  });

  it("non espone codici tecnici: un valore ignoto diventa non riconosciuto", () => {
    expect(decodeAnswer(1, parseQv2Answers({ q01: "99_100" })).values).toEqual([UNKNOWN_VALUE]);
  });

  it("riusa il dizionario di questionnaire.ts senza duplicare le label", () => {
    const source = readFileSync(resolve(import.meta.dir, "questionnaire-admin.ts"), "utf8");
    expect(source).toInclude('from "@/lib/market-validation/questionnaire"');
    for (const duplicated of ["Appassionato", "Consumatore occasionale", "Enoteca", "Pagamento protetto", "Cercare una bottiglia"]) {
      expect(source).not.toInclude(duplicated);
    }
  });
});

describe("QV2 admin: dettaglio tester", () => {
  it("ordina gli eventi della guida e riempie i mancanti a zero", () => {
    const detail = parseQv2ParticipantDetail({
      participantCode: "V001",
      cohort: "qv2",
      sessionsCount: 1,
      startedAt: "2026-10-05T09:00:00+00:00",
      events: [
        { event: "club_viewed", count: 1, firstAt: AT, lastAt: AT },
        { event: "marketplace_viewed", count: 2, firstAt: AT, lastAt: AT },
        { event: "beta_started", count: 1 },
        { event: "invented_event", count: 5 },
      ],
      completion: { preCompletedAt: AT, coreCompletedAt: null },
      questionnaire: { q01: "25_34" },
    });
    expect(detail?.events.map((event) => event.event)).toEqual(QV2_DETAIL_EVENTS.map(([event]) => event));
    expect(detail?.events.find((event) => event.event === "marketplace_viewed")?.count).toBe(2);
    expect(detail?.events.find((event) => event.event === "sell_completed")?.count).toBe(0);
    expect(detail?.questionnaire?.q01).toBe("25_34");
    expect(detail?.completion.preCompletedAt).toBe(AT);
    expect(detail?.completion.coreCompletedAt).toBeNull();
  });

  it("legacy e codice inesistente non hanno questionario", () => {
    const legacy = parseQv2ParticipantDetail({ participantCode: "V017", cohort: "legacy", questionnaire: { q01: "25_34" }, events: [] });
    expect(legacy?.questionnaire).toBeNull();
    expect(parseQv2ParticipantDetail(null)).toBeNull();
    expect(parseQv2ParticipantDetail({ participantCode: "V000", cohort: "qv2" })).toBeNull();
  });
});

describe("QV2 admin: distribuzioni", () => {
  const distributions = parseQv2Distributions({
    respondents: 4,
    preCompleted: 3,
    postCompleted: 1,
    questions: {
      q01: { base: 4, counts: { "25_34": 2, "45_54": 1, "65_plus": 1 } },
      q05: { base: 3, counts: { wine_shop: 2, producer: 2, other: 1, auction: 1 } },
      q19: { base: 1, counts: { protected_payment: 1, authenticity_guarantee: 1 } },
      "drop table": { base: 9, counts: {} },
    },
  });

  it("scarta chiavi non previste", () => {
    expect(Object.keys(distributions.questions).sort()).toEqual(["q01", "q05", "q19"]);
  });

  it("usa l'ordine approvato delle opzioni, zeri compresi, e la base dei rispondenti", () => {
    const q01 = buildQuestionDistribution(distributions, 1);
    expect(q01.rows.map((row) => row.code)).toEqual(QUESTIONS[0].options!.map(([code]) => code));
    expect(q01.rows.find((row) => row.code === "25_34")).toEqual({ code: "25_34", label: "25-34", count: 2, percentage: 50 });
    expect(q01.rows.find((row) => row.code === "18_24")?.count).toBe(0);
    expect(q01.multi).toBeFalse();
  });

  it("multi-select: una persona contribuisce a più opzioni e il totale supera il 100%", () => {
    const q05 = buildQuestionDistribution(distributions, 5);
    expect(q05.multi).toBeTrue();
    expect(q05.base).toBe(3);
    const totalPercentage = q05.rows.reduce((sum, row) => sum + row.percentage, 0);
    expect(totalPercentage).toBeGreaterThan(100);
    expect(q05.rows.find((row) => row.code === "wine_shop")?.percentage).toBeCloseTo(66.67, 1);
  });

  it("senza dati QV2 non inventa valori", () => {
    const empty = buildQuestionDistribution(parseQv2Distributions(null), 14);
    expect(empty.base).toBe(0);
    expect(empty.rows.every((row) => row.count === 0 && row.percentage === 0)).toBeTrue();
  });

  it("copre le domande richieste PRE e POST", () => {
    expect([...QV2_DISTRIBUTION_QUESTIONS.pre]).toEqual([1, 2, 3, 4, 5, 6, 7, 9, 11, 12, 13]);
    expect([...QV2_DISTRIBUTION_QUESTIONS.post]).toEqual([14, 15, 16, 19, 20]);
  });
});

describe("QV2 admin: CSV completo", () => {
  const participants = [parsed(qv2Row()), parsed(legacyRow())];
  const csv = buildQv2ParticipantsCsv(participants);
  const rows = parseCsv(csv.slice(1));

  it("usa BOM UTF-8, separatore ; e CRLF", () => {
    expect(csv.charCodeAt(0)).toBe(0xfeff);
    expect(csv.endsWith("\r\n")).toBeTrue();
    expect(csv.split("\r\n")[0].replace("﻿", "")).toBe(QV2_CSV_HEADERS.join(";"));
  });

  it("ha intestazioni stabili nell'ordine logico richiesto", () => {
    const required = [
      "participant_code", "started_at",
      "q01_age_range", "q02_wine_relationship", "q02_other", "q03_purchase_frequency", "q04_average_bottle_spend",
      "q05_purchase_channels", "q05_other", "q06_bought_private", "q06_where", "q06_why",
      "q07_private_purchase_concerns", "q08_trust_requirements", "q09_sellable_bottles",
      "q10_had_unwanted_bottles", "q10_actions", "q10_other", "q11_sold_wine_frequency", "q11_where",
      "q11_main_difficulty", "q12_shipping_max_50", "q13_shipping_max_150", "pre_completed_at",
      "listings_viewed_count", "favorites_count", "checkout_started", "shipping_cost_viewed", "checkout_completed",
      "sell_started", "sell_completed", "ai_preview_viewed", "ai_interest_clicked", "club_viewed", "core_beta_completed",
      "q14_first_action", "q15_would_consider_buying", "q15_why_not", "q16_would_sell_now", "q17_main_barrier",
      "q18_missing_improvement", "q19_important_services", "q20_first_use", "final_feedback",
      "post_completed_at", "validation_completed_at",
    ];
    const positions = required.map((header) => QV2_CSV_HEADERS.indexOf(header));
    expect(positions.every((position) => position >= 0)).toBeTrue();
    expect([...positions].sort((a, b) => a - b)).toEqual(positions);
    expect(new Set(QV2_CSV_HEADERS).size).toBe(QV2_CSV_HEADERS.length);
  });

  it("una riga per participant_code con tutte le celle allineate", () => {
    expect(rows).toHaveLength(3);
    expect(rows.every((row) => row.length === QV2_CSV_HEADERS.length)).toBeTrue();
    expect(rows.slice(1).map((row) => row[0])).toEqual(["V001", "V017"]);
  });

  it("serializza le multi-select in modo deterministico nell'ordine registrato", () => {
    const cell = (row: string[], header: string) => row[QV2_CSV_HEADERS.indexOf(header)];
    expect(cell(rows[1], "q05_purchase_channels")).toBe("wine_shop | producer | other");
    expect(cell(rows[1], "q19_important_services")).toBe("protected_payment | authenticity_guarantee");
    expect(cell(rows[1], "q06_why")).toBe("Prezzo; migliore");
    expect(cell(rows[1], "q08_trust_requirements")).toBe('Garanzia di "autenticità"');
    expect(cell(rows[1], "q17_main_barrier")).toBe("Spedizione\nlenta");
    expect(cell(rows[1], "listings_viewed_count")).toBe("1");
  });

  it("neutralizza la CSV formula injection", () => {
    const cell = (header: string) => rows[1][QV2_CSV_HEADERS.indexOf(header)];
    expect(cell("q05_other")).toBe("'=Mercatini");
    expect(cell("q18_missing_improvement")).toBe("'+Più foto");
    expect(cell("final_feedback")).toBe("'@ottimo");
    const tricky = buildQv2ParticipantsCsv([parsed(qv2Row({ q08: "-1+1", q17: "\tcmd" }))]);
    const trickyRow = parseCsv(tricky.slice(1))[1];
    expect(trickyRow[QV2_CSV_HEADERS.indexOf("q08_trust_requirements")]).toBe("'-1+1");
    expect(trickyRow[QV2_CSV_HEADERS.indexOf("q17_main_barrier")]).toBe("'\tcmd");
  });

  it("lascia vuote le risposte legacy mancanti", () => {
    const legacy = rows[2];
    for (const header of QV2_CSV_HEADERS.filter((item) => /^q\d|final_feedback|pre_completed_at|post_completed_at|validation_completed_at/.test(item))) {
      expect(legacy[QV2_CSV_HEADERS.indexOf(header)]).toBe("");
    }
    expect(legacy[QV2_CSV_HEADERS.indexOf("cohort")]).toBe("legacy");
  });

  it("non contiene capability, hash, token, UUID di sessione o PII", () => {
    const withSecrets = buildQv2ParticipantsCsv([
      parsed(qv2Row({ session_id: "12bc0000-0000-4000-8000-000000000101", capability_hash: "f".repeat(64), email: "x@y.it" })),
    ]);
    expect(withSecrets).not.toMatch(/12bc0000|f{64}|x@y\.it/);
    expect(QV2_CSV_HEADERS.join(";")).not.toMatch(
      /capability|hash|secret|token|session_id|(^|[;_])ip([;_]|$)|user_agent|email/,
    );
  });

  it("senza tester produce soltanto le intestazioni", () => {
    expect(buildQv2ParticipantsCsv([])).toBe(`﻿${QV2_CSV_HEADERS.join(";")}\r\n`);
  });
});

describe("QV2 admin: perimetro dell'export", () => {
  it("senza filtri è completo, con codice o coorte è dichiarato filtrato", () => {
    expect(qv2CsvExportScope(null, null)).toEqual({
      label: "Esporta CSV completo",
      filename: "market-validation-qv2-completo.csv",
    });
    expect(qv2CsvExportScope("V001", "qv2")).toEqual({
      label: "Esporta CSV filtrato",
      filename: "market-validation-qv2-V001.csv",
    });
    expect(qv2CsvExportScope(null, "legacy")).toEqual({
      label: "Esporta CSV filtrato",
      filename: "market-validation-qv2-legacy.csv",
    });
  });
});
