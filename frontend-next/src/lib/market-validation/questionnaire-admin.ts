import {
  escapeMarketValidationCsvCell,
  percentage,
} from "@/lib/market-validation/admin-analytics";
import { parseMarketValidationParticipantCode } from "@/lib/market-validation/contract";
import { QUESTIONS, Q10_ACTIONS, questionKey, type Question } from "@/lib/market-validation/questionnaire";
import type { MarketValidationParticipantCode } from "@/services/types";

// Dashboard admin QV2: parsing delle quattro porte read-only, decodifica delle
// risposte con le label approvate di questionnaire.ts (unico dizionario),
// funnel, distribuzioni ed export CSV. Nessun identificativo di sessione entra
// in questi tipi.

export const QV2_ADMIN_PAGE_SIZE = 50;
export const QV2_EXPORT_PAGE_SIZE = 200;
export const QV2_MAX_PARTICIPANTS = 999;

export const NOT_ANSWERED = "Non risposto";
export const QUESTIONNAIRE_UNAVAILABLE = "Questionario non disponibile";
export const UNKNOWN_VALUE = "Valore non riconosciuto";

export type Qv2Cohort = "qv2" | "legacy";
export type Qv2CohortFilter = Qv2Cohort | null;

const STRING_FIELDS = [
  "q01", "q02", "q02_other", "q03", "q04", "q05_other", "q06", "q06_where", "q06_why",
  "q07_other", "q08", "q09", "q10", "q10_other", "q11", "q11_where", "q11_main_difficulty", "q12", "q13",
  "q14", "q15", "q15_why_not", "q16", "q17", "q18", "q19_other", "q20", "final_feedback",
] as const;
const ARRAY_FIELDS = ["q05", "q07", "q10_actions", "q19"] as const;

type StringField = (typeof STRING_FIELDS)[number];
type ArrayField = (typeof ARRAY_FIELDS)[number];
export type Qv2Answers = { [K in StringField]: string | null } & { [K in ArrayField]: string[] | null };

export type Qv2EventCounts = {
  marketplaceViewed: number;
  demoListingViewed: number;
  favoriteAdded: number;
  checkoutStarted: number;
  shippingCostViewed: number;
  checkoutBetaCompleted: number;
  sellStarted: number;
  sellPhotoSelected: number;
  sellCompleted: number;
  aiPreviewViewed: number;
  aiInterestClicked: number;
  clubViewed: number;
  cellarViewed: number;
  betaCompleted: number;
};

export type Qv2AdminParticipant = {
  participantCode: MarketValidationParticipantCode;
  cohort: Qv2Cohort;
  sessionsCount: number;
  startedAt: string | null;
  lastActivityAt: string | null;
  preCompletedAt: string | null;
  coreCompletedAt: string | null;
  postCompletedAt: string | null;
  validationCompletedAt: string | null;
  // Cinque aree della Prova Vinea registrate, derivato dal database.
  experienceCompleted: boolean;
  events: Qv2EventCounts;
  answers: Qv2Answers | null;
};

export type Qv2AdminParticipantsPage = {
  participants: Qv2AdminParticipant[];
  total: number;
};

export type Qv2AdminSummary = {
  qv2: {
    started: number;
    preCompleted: number;
    buyCompleted: number;
    sellCompleted: number;
    experienceCompleted: number;
    coreCompleted: number;
    postCompleted: number;
    validationCompleted: number;
    aiViewed: number;
    clubViewed: number;
    cellarViewed: number;
    favoriteAdded: number;
    completionRate: number;
  };
  legacy: {
    codes: number;
    coreCompleted: number;
    favoriteAdded: number;
    coreCompletionRate: number;
  };
  allCodes: number;
};

export const EMPTY_QV2_ADMIN_SUMMARY: Qv2AdminSummary = {
  qv2: {
    started: 0,
    preCompleted: 0,
    buyCompleted: 0,
    sellCompleted: 0,
    experienceCompleted: 0,
    coreCompleted: 0,
    postCompleted: 0,
    validationCompleted: 0,
    aiViewed: 0,
    clubViewed: 0,
    cellarViewed: 0,
    favoriteAdded: 0,
    completionRate: 0,
  },
  legacy: { codes: 0, coreCompleted: 0, favoriteAdded: 0, coreCompletionRate: 0 },
  allCodes: 0,
};

export type Qv2Distributions = {
  respondents: number;
  preCompleted: number;
  postCompleted: number;
  questions: Record<string, { base: number; counts: Record<string, number> }>;
};

export const EMPTY_QV2_DISTRIBUTIONS: Qv2Distributions = {
  respondents: 0,
  preCompleted: 0,
  postCompleted: 0,
  questions: {},
};

// Eventi mostrati nel dettaglio, nell'ordine della guida Prova Vinea. Le
// label descrivono solo ciò che l'evento registra, senza dedurre altre azioni.
export const QV2_DETAIL_EVENTS = [
  ["marketplace_viewed", "Marketplace visualizzato"],
  ["demo_listing_viewed", "Annuncio demo aperto"],
  ["favorite_added", "Preferito aggiunto"],
  ["checkout_started", "Checkout avviato"],
  ["shipping_cost_viewed", "Costo di spedizione visualizzato"],
  ["checkout_beta_completed", "Acquisto beta completato"],
  ["sell_started", "Vendita avviata"],
  ["sell_photo_selected", "Foto selezionata"],
  ["sell_completed", "Vendita completata"],
  ["ai_preview_viewed", "Anteprima AI visualizzata"],
  ["ai_interest_clicked", "Interesse AI dichiarato"],
  ["club_viewed", "Club visualizzati"],
  ["cellar_viewed", "Cantina visualizzata"],
  ["beta_completed", "Prova Vinea conclusa (beta_completed)"],
] as const;

export type Qv2DetailEventName = (typeof QV2_DETAIL_EVENTS)[number][0];

export type Qv2EventDetail = {
  event: Qv2DetailEventName;
  label: string;
  count: number;
  firstAt: string | null;
  lastAt: string | null;
};

export type Qv2ParticipantDetail = {
  participantCode: MarketValidationParticipantCode;
  cohort: Qv2Cohort;
  sessionsCount: number;
  startedAt: string | null;
  lastActivityAt: string | null;
  events: Qv2EventDetail[];
  completion: {
    preCompletedAt: string | null;
    experienceCompleted: boolean;
    coreCompletedAt: string | null;
    postCompletedAt: string | null;
    validationCompletedAt: string | null;
  };
  questionnaire: Qv2Answers | null;
};

const asObject = (value: unknown): Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};

const asNumber = (value: unknown): number =>
  typeof value === "number" && Number.isFinite(value) ? value : 0;

const asCount = (value: unknown): number => Math.max(0, Math.trunc(asNumber(value)));

const asRate = (value: unknown): number => Math.min(100, Math.max(0, asNumber(value)));

const asNullableIso = (value: unknown): string | null =>
  typeof value === "string" && !Number.isNaN(Date.parse(value)) ? value : null;

const asNullableString = (value: unknown): string | null =>
  typeof value === "string" && value.length > 0 ? value : null;

const asNullableStringArray = (value: unknown): string[] | null =>
  Array.isArray(value) && value.length > 0 && value.every((item) => typeof item === "string")
    ? [...(value as string[])]
    : null;

const asCohort = (value: unknown): Qv2Cohort | null =>
  value === "qv2" || value === "legacy" ? value : null;

export function parseQv2Answers(value: unknown): Qv2Answers {
  const source = asObject(value);
  const answers = {} as Qv2Answers;
  for (const field of STRING_FIELDS) answers[field] = asNullableString(source[field]);
  for (const field of ARRAY_FIELDS) answers[field] = asNullableStringArray(source[field]);
  return answers;
}

export function parseQv2AdminSummary(value: unknown): Qv2AdminSummary {
  const source = asObject(value);
  const qv2 = asObject(source.qv2);
  const legacy = asObject(source.legacy);
  return {
    qv2: {
      started: asCount(qv2.started),
      preCompleted: asCount(qv2.preCompleted),
      buyCompleted: asCount(qv2.buyCompleted),
      sellCompleted: asCount(qv2.sellCompleted),
      experienceCompleted: asCount(qv2.experienceCompleted),
      coreCompleted: asCount(qv2.coreCompleted),
      postCompleted: asCount(qv2.postCompleted),
      validationCompleted: asCount(qv2.validationCompleted),
      aiViewed: asCount(qv2.aiViewed),
      clubViewed: asCount(qv2.clubViewed),
      cellarViewed: asCount(qv2.cellarViewed),
      favoriteAdded: asCount(qv2.favoriteAdded),
      completionRate: asRate(qv2.completionRate),
    },
    legacy: {
      codes: asCount(legacy.codes),
      coreCompleted: asCount(legacy.coreCompleted),
      favoriteAdded: asCount(legacy.favoriteAdded),
      coreCompletionRate: asRate(legacy.coreCompletionRate),
    },
    allCodes: asCount(source.allCodes),
  };
}

export function parseQv2AdminParticipant(value: unknown): Qv2AdminParticipant | null {
  const source = asObject(value);
  const participantCode =
    typeof source.participant_code === "string"
      ? parseMarketValidationParticipantCode(source.participant_code)
      : null;
  const cohort = asCohort(source.cohort);
  if (!participantCode || !cohort) return null;
  return {
    participantCode,
    cohort,
    sessionsCount: asCount(source.sessions_count),
    startedAt: asNullableIso(source.started_at),
    lastActivityAt: asNullableIso(source.last_activity_at),
    preCompletedAt: asNullableIso(source.pre_completed_at),
    coreCompletedAt: asNullableIso(source.core_completed_at),
    postCompletedAt: asNullableIso(source.post_completed_at),
    validationCompletedAt: asNullableIso(source.validation_completed_at),
    experienceCompleted: source.experience_completed === true,
    events: {
      marketplaceViewed: asCount(source.marketplace_viewed),
      demoListingViewed: asCount(source.demo_listing_viewed),
      favoriteAdded: asCount(source.favorite_added),
      checkoutStarted: asCount(source.checkout_started),
      shippingCostViewed: asCount(source.shipping_cost_viewed),
      checkoutBetaCompleted: asCount(source.checkout_beta_completed),
      sellStarted: asCount(source.sell_started),
      sellPhotoSelected: asCount(source.sell_photo_selected),
      sellCompleted: asCount(source.sell_completed),
      aiPreviewViewed: asCount(source.ai_preview_viewed),
      aiInterestClicked: asCount(source.ai_interest_clicked),
      clubViewed: asCount(source.club_viewed),
      cellarViewed: asCount(source.cellar_viewed),
      betaCompleted: asCount(source.beta_completed),
    },
    // Un legacy non ha questionario: nessuna risposta viene inventata.
    answers: cohort === "qv2" ? parseQv2Answers(source) : null,
  };
}

export function parseQv2AdminParticipantsPage(value: unknown): Qv2AdminParticipantsPage {
  if (!Array.isArray(value)) return { participants: [], total: 0 };
  const participants = value.flatMap((row) => {
    const participant = parseQv2AdminParticipant(row);
    return participant ? [participant] : [];
  });
  const total = value.length > 0 ? asCount(asObject(value[0]).total_count) : 0;
  return { participants, total: Math.max(total, participants.length) };
}

export function parseQv2ParticipantDetail(value: unknown): Qv2ParticipantDetail | null {
  if (value === null || value === undefined) return null;
  const source = asObject(value);
  const participantCode =
    typeof source.participantCode === "string"
      ? parseMarketValidationParticipantCode(source.participantCode)
      : null;
  const cohort = asCohort(source.cohort);
  if (!participantCode || !cohort) return null;
  const rawEvents = Array.isArray(source.events) ? source.events.map(asObject) : [];
  const completion = asObject(source.completion);
  return {
    participantCode,
    cohort,
    sessionsCount: asCount(source.sessionsCount),
    startedAt: asNullableIso(source.startedAt),
    lastActivityAt: asNullableIso(source.lastActivityAt),
    events: QV2_DETAIL_EVENTS.map(([event, label]) => {
      const raw = rawEvents.find((item) => item.event === event) ?? {};
      return {
        event,
        label,
        count: asCount(raw.count),
        firstAt: asNullableIso(raw.firstAt),
        lastAt: asNullableIso(raw.lastAt),
      };
    }),
    completion: {
      preCompletedAt: asNullableIso(completion.preCompletedAt),
      experienceCompleted: completion.experienceCompleted === true,
      coreCompletedAt: asNullableIso(completion.coreCompletedAt),
      postCompletedAt: asNullableIso(completion.postCompletedAt),
      validationCompletedAt: asNullableIso(completion.validationCompletedAt),
    },
    questionnaire:
      cohort === "qv2" && source.questionnaire !== null && typeof source.questionnaire === "object"
        ? parseQv2Answers(source.questionnaire)
        : null,
  };
}

export function parseQv2Distributions(value: unknown): Qv2Distributions {
  const source = asObject(value);
  const questions: Qv2Distributions["questions"] = {};
  for (const [key, raw] of Object.entries(asObject(source.questions))) {
    if (!/^q[0-9]{2}(_actions)?$/.test(key)) continue;
    const entry = asObject(raw);
    const counts: Record<string, number> = {};
    for (const [code, count] of Object.entries(asObject(entry.counts))) counts[code] = asCount(count);
    questions[key] = { base: asCount(entry.base), counts };
  }
  return {
    respondents: asCount(source.respondents),
    preCompleted: asCount(source.preCompleted),
    postCompleted: asCount(source.postCompleted),
    questions,
  };
}

export function parseQv2CohortFilter(value: string): Qv2CohortFilter {
  return value === "qv2" || value === "legacy" ? value : null;
}

/* ---------------------------------------------------------------- */
/*  Stato del tester e funnel                                        */
/* ---------------------------------------------------------------- */

export type Qv2TesterStatus = {
  pre: boolean;
  buy: boolean;
  sell: boolean;
  ai: boolean;
  club: boolean;
  cellar: boolean;
  experience: boolean;
  post: boolean;
  complete: boolean;
};

// Le cinque aree obbligatorie della Prova Vinea, nell'ordine dell'hub tester.
export const QV2_EXPERIENCE_AREAS = ["buy", "sell", "ai", "club", "cellar"] as const;

export const QV2_STATUS_COLUMNS: ReadonlyArray<{ key: keyof Qv2TesterStatus; label: string; title: string }> = [
  { key: "pre", label: "PRE", title: "Questionario PRE completato" },
  { key: "buy", label: "BUY", title: "Acquisto beta completato (checkout_beta_completed)" },
  { key: "sell", label: "SELL", title: "Vendita completata (sell_completed)" },
  { key: "ai", label: "AI", title: "Anteprima AI visualizzata (ai_preview_viewed)" },
  { key: "club", label: "CLUB", title: "Club visualizzati (club_viewed)" },
  { key: "cellar", label: "CELLAR", title: "Cantina visualizzata (cellar_viewed)" },
  { key: "experience", label: "5/5", title: "Prova Vinea completa: tutte e cinque le aree" },
  { key: "post", label: "POST", title: "Questionario POST completato" },
  { key: "complete", label: "FULL", title: "Market Validation completa (validation_completed)" },
];

export function qv2TesterStatus(participant: Qv2AdminParticipant): Qv2TesterStatus {
  return {
    pre: participant.preCompletedAt !== null,
    buy: participant.events.checkoutBetaCompleted > 0,
    sell: participant.events.sellCompleted > 0,
    ai: participant.events.aiPreviewViewed > 0,
    club: participant.events.clubViewed > 0,
    cellar: participant.events.cellarViewed > 0,
    experience: participant.experienceCompleted,
    post: participant.postCompletedAt !== null,
    complete: participant.validationCompletedAt !== null,
  };
}

export function qv2ExperienceAreasDone(status: Pick<Qv2TesterStatus, (typeof QV2_EXPERIENCE_AREAS)[number]>): number {
  return QV2_EXPERIENCE_AREAS.filter((area) => status[area]).length;
}

// Test chiuso con la regola precedente (Acquisto + Vendita): la Prova Vinea
// risulta conclusa ma le cinque aree non sono tutte registrate. Lo stato resta
// quello storico, senza attribuire visite mai avvenute.
export function qv2ClosedWithPreviousRule(participant: Qv2AdminParticipant): boolean {
  return participant.cohort === "qv2" && participant.events.betaCompleted > 0 && !participant.experienceCompleted;
}

export type Qv2FunnelStep = {
  key: string;
  label: string;
  value: number;
  denominator: number;
  rate: number;
  parallel?: boolean;
};

// Ogni passaggio conta i codici QV2 che hanno raggiunto quel traguardo, con
// base fissa sui test iniziati della coorte QV2. Le cinque aree sono percorsi
// indipendenti, senza un ordine fra loro; il POST richiede tutte e cinque.
export function buildQv2Funnel(summary: Qv2AdminSummary): Qv2FunnelStep[] {
  const base = summary.qv2.started;
  const step = (key: string, label: string, value: number, parallel = false): Qv2FunnelStep => ({
    key,
    label,
    value,
    denominator: base,
    rate: key === "started" ? (base > 0 ? 100 : 0) : percentage(value, base),
    ...(parallel ? { parallel } : {}),
  });
  return [
    step("started", "Test iniziato", base),
    step("pre", "PRE completato", summary.qv2.preCompleted),
    step("buy", "Acquisto completato", summary.qv2.buyCompleted, true),
    step("sell", "Vendita completata", summary.qv2.sellCompleted, true),
    step("ai", "Vinea AI visitata", summary.qv2.aiViewed, true),
    step("club", "Club visitato", summary.qv2.clubViewed, true),
    step("cellar", "Cantina visitata", summary.qv2.cellarViewed, true),
    step("experience", "Prova Vinea 5/5", summary.qv2.experienceCompleted),
    step("post", "POST completato", summary.qv2.postCompleted),
    step("full", "Market Validation completa", summary.qv2.validationCompleted),
  ];
}

/* ---------------------------------------------------------------- */
/*  Decodifica delle risposte                                        */
/* ---------------------------------------------------------------- */

const questionByNumber = (number: number): Question => {
  const question = QUESTIONS.find((item) => item.number === number);
  if (!question) throw new Error(`Domanda ${number} inesistente.`);
  return question;
};

export function optionLabel(
  options: readonly (readonly [string, string])[] | undefined,
  code: string,
): string {
  return options?.find(([value]) => value === code)?.[1] ?? UNKNOWN_VALUE;
}

export type DecodedExtra = { label: string; value: string };
export type DecodedAnswer = {
  number: number;
  key: string;
  title: string;
  kind: Question["kind"];
  answered: boolean;
  values: string[];
  extras: DecodedExtra[];
};

const q10OtherLabel = optionLabel(Q10_ACTIONS, "other");

// Campi condizionali con le label della UI pubblica. Compaiono solo quando la
// risposta li contiene: un campo non applicabile non diventa «Non risposto».
function extrasFor(number: number, answers: Qv2Answers): DecodedExtra[] {
  const question = questionByNumber(number);
  const first = question.condition?.label ?? "";
  const second = question.secondCondition?.label ?? "";
  const extras: Array<[string, string | null]> = (() => {
    switch (number) {
      case 2: return [[first, answers.q02_other]];
      case 5: return [[first, answers.q05_other]];
      case 6: return [[first, answers.q06_where], [second, answers.q06_why]];
      case 7: return [[first, answers.q07_other]];
      case 10: return [
        [first, answers.q10_actions?.map((code) => optionLabel(Q10_ACTIONS, code)).join(", ") ?? null],
        [q10OtherLabel, answers.q10_other],
      ];
      case 11: return [[first, answers.q11_where], [second, answers.q11_main_difficulty]];
      case 15: return [[first, answers.q15_why_not]];
      case 19: return [[first, answers.q19_other]];
      default: return [];
    }
  })();
  return extras.flatMap(([label, value]) => (value ? [{ label, value }] : []));
}

export function decodeAnswer(number: number, answers: Qv2Answers): DecodedAnswer {
  const question = questionByNumber(number);
  const key = questionKey(number) as StringField | ArrayField;
  const raw = (answers as Record<string, string | string[] | null>)[key];
  let values: string[] = [];
  if (question.kind === "text") {
    values = typeof raw === "string" ? [raw] : [];
  } else if (Array.isArray(raw)) {
    // Ordine di scelta del tester, senza riordinare né filtrare.
    values = raw.map((code) => optionLabel(question.options, code));
  } else if (typeof raw === "string") {
    values = [optionLabel(question.options, raw)];
  }
  return {
    number,
    key,
    title: question.title,
    kind: question.kind,
    answered: values.length > 0,
    values,
    extras: values.length > 0 ? extrasFor(number, answers) : [],
  };
}

export function decodeQuestionnaire(answers: Qv2Answers, from: number, to: number): DecodedAnswer[] {
  const decoded: DecodedAnswer[] = [];
  for (let number = from; number <= to; number++) decoded.push(decodeAnswer(number, answers));
  return decoded;
}

export const PRE_RANGE = [1, 13] as const;
export const POST_RANGE = [14, 20] as const;

/* ---------------------------------------------------------------- */
/*  Distribuzioni                                                    */
/* ---------------------------------------------------------------- */

export const QV2_DISTRIBUTION_QUESTIONS = {
  pre: [1, 2, 3, 4, 5, 6, 7, 9, 11, 12, 13],
  post: [14, 15, 16, 19, 20],
} as const;

export type DistributionRow = { code: string; label: string; count: number; percentage: number };
export type QuestionDistribution = {
  number: number;
  key: string;
  title: string;
  multi: boolean;
  base: number;
  rows: DistributionRow[];
};

// Opzioni nell'ordine approvato del questionario, comprese quelle a zero;
// percentuali sulla base dei rispondenti della domanda. Per le multi-select la
// somma può superare il 100%.
export function buildQuestionDistribution(
  distributions: Qv2Distributions,
  number: number,
): QuestionDistribution {
  const question = questionByNumber(number);
  const key = questionKey(number);
  const entry = distributions.questions[key] ?? { base: 0, counts: {} };
  return {
    number,
    key,
    title: question.title,
    multi: question.kind === "multi",
    base: entry.base,
    rows: (question.options ?? []).map(([code, label]) => {
      const count = entry.counts[code] ?? 0;
      return { code, label, count, percentage: percentage(count, entry.base) };
    }),
  };
}

/* ---------------------------------------------------------------- */
/*  CSV                                                              */
/* ---------------------------------------------------------------- */

type CsvCell = string | number | boolean | null;

// Le scelte multiple restano codici stabili nell'ordine registrato, separati
// da " | ": deterministico e leggibile in Excel senza rompere la colonna.
const csvList = (values: string[] | null): string | null => (values ? values.join(" | ") : null);
const answer = (participant: Qv2AdminParticipant, field: StringField): CsvCell =>
  participant.answers?.[field] ?? null;
const list = (participant: Qv2AdminParticipant, field: ArrayField): CsvCell =>
  csvList(participant.answers?.[field] ?? null);

const QV2_CSV_COLUMNS: ReadonlyArray<readonly [string, (participant: Qv2AdminParticipant) => CsvCell]> = [
  ["participant_code", (p) => p.participantCode],
  ["started_at", (p) => p.startedAt],
  ["cohort", (p) => p.cohort],
  ["sessions_count", (p) => p.sessionsCount],
  ["last_activity_at", (p) => p.lastActivityAt],
  ["q01_age_range", (p) => answer(p, "q01")],
  ["q02_wine_relationship", (p) => answer(p, "q02")],
  ["q02_other", (p) => answer(p, "q02_other")],
  ["q03_purchase_frequency", (p) => answer(p, "q03")],
  ["q04_average_bottle_spend", (p) => answer(p, "q04")],
  ["q05_purchase_channels", (p) => list(p, "q05")],
  ["q05_other", (p) => answer(p, "q05_other")],
  ["q06_bought_private", (p) => answer(p, "q06")],
  ["q06_where", (p) => answer(p, "q06_where")],
  ["q06_why", (p) => answer(p, "q06_why")],
  ["q07_private_purchase_concerns", (p) => list(p, "q07")],
  ["q07_other", (p) => answer(p, "q07_other")],
  ["q08_trust_requirements", (p) => answer(p, "q08")],
  ["q09_sellable_bottles", (p) => answer(p, "q09")],
  ["q10_had_unwanted_bottles", (p) => answer(p, "q10")],
  ["q10_actions", (p) => list(p, "q10_actions")],
  ["q10_other", (p) => answer(p, "q10_other")],
  ["q11_sold_wine_frequency", (p) => answer(p, "q11")],
  ["q11_where", (p) => answer(p, "q11_where")],
  ["q11_main_difficulty", (p) => answer(p, "q11_main_difficulty")],
  ["q12_shipping_max_50", (p) => answer(p, "q12")],
  ["q13_shipping_max_150", (p) => answer(p, "q13")],
  ["pre_completed_at", (p) => p.preCompletedAt],
  ["listings_viewed_count", (p) => p.events.demoListingViewed],
  ["favorites_count", (p) => p.events.favoriteAdded],
  ["checkout_started", (p) => p.events.checkoutStarted],
  ["shipping_cost_viewed", (p) => p.events.shippingCostViewed],
  ["checkout_completed", (p) => p.events.checkoutBetaCompleted],
  ["sell_started", (p) => p.events.sellStarted],
  ["sell_completed", (p) => p.events.sellCompleted],
  ["ai_preview_viewed", (p) => p.events.aiPreviewViewed],
  ["ai_interest_clicked", (p) => p.events.aiInterestClicked],
  ["club_viewed", (p) => p.events.clubViewed],
  ["cellar_viewed", (p) => p.events.cellarViewed],
  ["experience_completed", (p) => p.experienceCompleted],
  ["core_beta_completed", (p) => p.events.betaCompleted],
  ["marketplace_viewed", (p) => p.events.marketplaceViewed],
  ["sell_photo_selected", (p) => p.events.sellPhotoSelected],
  ["core_completed_at", (p) => p.coreCompletedAt],
  ["q14_first_action", (p) => answer(p, "q14")],
  ["q15_would_consider_buying", (p) => answer(p, "q15")],
  ["q15_why_not", (p) => answer(p, "q15_why_not")],
  ["q16_would_sell_now", (p) => answer(p, "q16")],
  ["q17_main_barrier", (p) => answer(p, "q17")],
  ["q18_missing_improvement", (p) => answer(p, "q18")],
  ["q19_important_services", (p) => list(p, "q19")],
  ["q19_other", (p) => answer(p, "q19_other")],
  ["q20_first_use", (p) => answer(p, "q20")],
  ["final_feedback", (p) => answer(p, "final_feedback")],
  ["post_completed_at", (p) => p.postCompletedAt],
  ["validation_completed_at", (p) => p.validationCompletedAt],
];

export const QV2_CSV_HEADERS: readonly string[] = QV2_CSV_COLUMNS.map(([header]) => header);

export function buildQv2ParticipantsCsv(participants: readonly Qv2AdminParticipant[]): string {
  const rows = [
    QV2_CSV_HEADERS.join(";"),
    ...participants.map((participant) =>
      QV2_CSV_COLUMNS.map(([, value]) => escapeMarketValidationCsvCell(value(participant))).join(";"),
    ),
  ];
  return `﻿${rows.join("\r\n")}\r\n`;
}

// L'export segue i filtri attivi (come il CSV MV3): l'etichetta e il nome file
// dichiarano il perimetro, così un export filtrato non passa per completo.
export function qv2CsvExportScope(
  participantCode: string | null,
  cohort: Qv2CohortFilter,
): { label: string; filename: string } {
  const filtered = participantCode !== null || cohort !== null;
  return {
    label: filtered ? "Esporta CSV filtrato" : "Esporta CSV completo",
    filename: `market-validation-qv2-${participantCode ?? cohort ?? "completo"}.csv`,
  };
}
