import { describe, expect, it } from "bun:test";
import {
  QUESTIONS,
  answerValid,
  questionKey,
  questionnaireStage,
  type QuestionnaireState,
} from "./questionnaire";

const state = (overrides: Partial<QuestionnaireState> = {}): QuestionnaireState => ({
  session_id: "10000000-0000-4000-8000-000000000001",
  participant_code: "V001",
  pre_finished_at: null,
  post_finished_at: null,
  validation_completed_at: null,
  buyer_completed: false,
  seller_completed: false,
  core_completed: false,
  answers: {},
  ...overrides,
});
const question = (number: number) => QUESTIONS[number - 1];
const AT = "2026-10-08T10:00:00.000Z";

describe("Questionario QV2: lifecycle", () => {
  it("segue LANDING → PRE → CORE → POST → GRAZIE dallo stato server", () => {
    expect(questionnaireStage(state())).toBe("pre-questionnaire");
    // Anche con eventi core già registrati, il PRE aperto ha la precedenza.
    expect(questionnaireStage(state({ core_completed: true }))).toBe("pre-questionnaire");
    expect(questionnaireStage(state({ pre_finished_at: AT }))).toBe("hub");
    expect(questionnaireStage(state({ pre_finished_at: AT, buyer_completed: true, seller_completed: true }))).toBe("hub");
    expect(questionnaireStage(state({ pre_finished_at: AT, core_completed: true }))).toBe("post-questionnaire");
    expect(questionnaireStage(state({ pre_finished_at: AT, core_completed: true, post_finished_at: AT }))).toBe("complete");
  });

  it("numera Q1-Q20 con le chiavi SQL q01-q20, senza final_feedback", () => {
    expect(QUESTIONS.map((item) => item.number)).toEqual(Array.from({ length: 20 }, (_, index) => index + 1));
    expect(questionKey(1)).toBe("q01");
    expect(questionKey(13)).toBe("q13");
    expect(questionKey(20)).toBe("q20");
  });
});

describe("Questionario QV2: validazione client", () => {
  it("accetta solo codici chiusi per le scelte singole", () => {
    expect(answerValid(question(1), "25_34")).toBeTrue();
    expect(answerValid(question(1), "99_100")).toBeFalse();
    expect(answerValid(question(20), "both")).toBeTrue();
    expect(answerValid(question(20), null)).toBeFalse();
  });

  it("rispetta massimo e duplicati delle scelte multiple", () => {
    expect(answerValid(question(7), ["authenticity", "storage", "price"])).toBeTrue();
    expect(answerValid(question(7), ["authenticity", "storage", "price", "payment"])).toBeFalse();
    expect(answerValid(question(19), ["reviews", "reviews"])).toBeFalse();
    expect(answerValid(question(19), [])).toBeFalse();
  });

  it("richiede il testo condizionale solo quando la scelta lo prevede", () => {
    expect(answerValid(question(5), { choices: ["supermarket"] })).toBeTrue();
    expect(answerValid(question(5), { choices: ["other"] })).toBeFalse();
    expect(answerValid(question(5), { choices: ["other"], other: "Mercatini" })).toBeTrue();
    expect(answerValid(question(10), { choice: "no" })).toBeTrue();
    expect(answerValid(question(10), { choice: "yes" })).toBeFalse();
    expect(answerValid(question(10), { choice: "yes", actions: ["sold"] })).toBeTrue();
    expect(answerValid(question(10), { choice: "yes", actions: ["other"] })).toBeFalse();
  });

  it("accetta testo libero non vuoto entro il limite", () => {
    expect(answerValid(question(8), "Pagamento protetto")).toBeTrue();
    expect(answerValid(question(8), "   ")).toBeFalse();
    expect(answerValid(question(17), "x".repeat(1001))).toBeFalse();
  });
});
