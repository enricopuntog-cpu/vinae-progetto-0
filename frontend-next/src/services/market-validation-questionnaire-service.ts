import type { SupabaseClient } from "@supabase/supabase-js";
import type { QuestionnaireAnswer } from "@/lib/market-validation/questionnaire";
import type {
  MarketValidationQuestionnaireService,
  MarketValidationQuestionnaireState,
  MarketValidationSession,
} from "@/services/types";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CODE = /^V(00[1-9]|0[1-9][0-9]|[1-9][0-9]{2})$/;
const ERROR = "Non siamo riusciti a salvare il questionario. Riprova.";

function object(value: unknown): Record<string, unknown> | null {
  if (Array.isArray(value)) value = value[0];
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown> : null;
}

function timestamp(value: unknown): value is string | null {
  return value === null || (typeof value === "string" && !Number.isNaN(Date.parse(value)));
}

function stateFrom(value: unknown): MarketValidationQuestionnaireState | null {
  const data = object(value);
  const rawAnswers = object(data?.answers);
  if (!data || !rawAnswers || typeof data.session_id !== "string" || !UUID.test(data.session_id) ||
      typeof data.participant_code !== "string" || !CODE.test(data.participant_code) ||
      !timestamp(data.pre_finished_at) || !timestamp(data.post_finished_at)) return null;
  const answers: Record<string, QuestionnaireAnswer | null> = {};
  for (let index = 1; index <= 20; index++) {
    const key = `q${String(index).padStart(2, "0")}`;
    const value = rawAnswers[key];
    if (value != null && typeof value !== "string" && !Array.isArray(value) && !object(value)) return null;
    answers[key] = value == null ? null : value as QuestionnaireAnswer;
  }
  // SQL keeps typed columns separate; expose the conditional questions as the
  // same closed objects the form submits, without leaking internal column names.
  for (const [key, fields] of Object.entries({
    q02: ["other"], q05: ["other"], q06: ["where", "why"], q07: ["other"],
    q10: ["actions", "other"], q11: ["where", "main_difficulty"], q15: ["why_not"], q19: ["other"],
  })) {
    const base = answers[key];
    if (base === null) continue;
    if (base && typeof base === "object" && !Array.isArray(base)) continue;
    const extras: Record<string, string | string[]> = {};
    for (const field of fields) {
      const extra = rawAnswers[`${key}_${field}`];
      if (typeof extra === "string" || (field === "actions" && Array.isArray(extra)))
        extras[field] = extra as string | string[];
    }
    if (key === "q05" || key === "q07" || key === "q19") answers[key] = { choices: base as string[], ...extras };
    else answers[key] = { choice: base as string, ...extras };
  }
  if (typeof rawAnswers.final_feedback === "string") answers.final_feedback = rawAnswers.final_feedback;
  return {
    session_id: data.session_id,
    participant_code: data.participant_code,
    pre_finished_at: data.pre_finished_at,
    post_finished_at: data.post_finished_at,
    validation_completed_at: timestamp(data.validation_completed_at) ? data.validation_completed_at : null,
    buyer_completed: data.buyer_completed === true,
    seller_completed: data.seller_completed === true,
    ai_viewed: data.ai_viewed === true,
    club_viewed: data.club_viewed === true,
    cellar_viewed: data.cellar_viewed === true,
    experience_completed: data.experience_completed === true,
    core_completed: data.core_completed === true,
    answers,
  };
}

export function createMarketValidationQuestionnaireService(client: SupabaseClient | null): MarketValidationQuestionnaireService {
  const read = async (sessionId: string, capability: string) => {
    if (!client || !UUID.test(sessionId) || !UUID.test(capability)) return { ok: false as const, error: ERROR };
    const { data, error } = await client.rpc("beta_validation_qv2_read", {
      p_session_id: sessionId, p_capability: capability,
    });
    const state = error ? null : stateFrom(data);
    if (!state || state.session_id !== sessionId) return { ok: false as const, error: ERROR };
    return { ok: true as const, data: { state } };
  };
  return {
    async startOrResume(capability) {
      if (!client || !UUID.test(capability)) return { ok: false, error: ERROR };
      const { data, error } = await client.rpc("beta_validation_qv2_start", { p_capability: capability });
      const start = error ? null : object(data);
      if (!start || typeof start.session_id !== "string" || !UUID.test(start.session_id) ||
          typeof start.participant_code !== "string" || !CODE.test(start.participant_code) ||
          typeof start.started_at !== "string" || Number.isNaN(Date.parse(start.started_at)) ||
          typeof start.resumed !== "boolean") return { ok: false, error: ERROR };
      const session: MarketValidationSession = {
        sessionId: start.session_id,
        participantCode: start.participant_code as MarketValidationSession["participantCode"],
        capability, startedAt: start.started_at, resumed: start.resumed,
      };
      const result = await read(session.sessionId, capability);
      return result.ok ? { ok: true, data: { session, state: result.data.state } } : result;
    },
    read,
    async answer(sessionId, capability, question, answer) {
      if (!client || !UUID.test(sessionId) || !UUID.test(capability) ||
          !/^(q(0[1-9]|1[0-9]|20)|final_feedback)$/.test(question)) return { ok: false, error: ERROR };
      const { error } = await client.rpc("beta_validation_qv2_answer", {
        p_session_id: sessionId, p_capability: capability, p_question: question, p_answer: answer,
      });
      return error ? { ok: false, error: ERROR } : { ok: true, data: { answer_key: question } };
    },
    async finishPre(sessionId, capability) {
      if (!client || !UUID.test(sessionId) || !UUID.test(capability)) return { ok: false, error: ERROR };
      const { data, error } = await client.rpc("beta_validation_qv2_finish_pre", {
        p_session_id: sessionId, p_capability: capability,
      });
      return error || data !== true ? { ok: false, error: ERROR } : { ok: true, data: true };
    },
    async finishPost(sessionId, capability) {
      if (!client || !UUID.test(sessionId) || !UUID.test(capability)) return { ok: false, error: ERROR };
      const { data, error } = await client.rpc("beta_validation_qv2_finish_post", {
        p_session_id: sessionId, p_capability: capability,
      });
      return error || data !== true ? { ok: false, error: ERROR } : { ok: true, data: true };
    },
  };
}
