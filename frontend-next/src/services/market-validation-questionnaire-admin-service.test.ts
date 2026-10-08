import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { MarketValidationAdminError } from "@/services/market-validation-admin-service";
import {
  loadAllQv2AdminParticipants,
  loadQv2AdminDistributions,
  loadQv2AdminParticipants,
  loadQv2AdminSummary,
  loadQv2ParticipantDetail,
} from "@/services/market-validation-questionnaire-admin-service";

type RpcResponse = { data: unknown; error: { code?: string; message?: string } | null };

const fakeClient = (responses: RpcResponse[]) => {
  const calls: Array<{ name: string; args: unknown }> = [];
  const client = {
    rpc: (name: string, args?: unknown) => {
      calls.push({ name, args });
      const response = responses.shift();
      if (!response) throw new Error("risposta fake mancante");
      return Promise.resolve(response);
    },
    from: () => {
      throw new Error("le tabelle non si leggono dal client admin");
    },
  } as unknown as SupabaseClient;
  return { client, calls };
};

const code = (index: number) => `V${String(index).padStart(3, "0")}`;
const rows = (from: number, count: number, total: number) =>
  Array.from({ length: count }, (_, index) => ({
    participant_code: code(from + index),
    cohort: "legacy",
    sessions_count: 1,
    total_count: total,
  }));

describe("QV2 admin Supabase adapter", () => {
  it("chiama la RPC summary QV2 senza argomenti", async () => {
    const { client, calls } = fakeClient([{ data: { qv2: { started: 2 } }, error: null }]);
    expect((await loadQv2AdminSummary(client)).qv2.started).toBe(2);
    expect(calls).toEqual([{ name: "beta_validation_qv2_admin_summary", args: undefined }]);
  });

  it("chiama la RPC distribuzioni e normalizza", async () => {
    const { client, calls } = fakeClient([{ data: { respondents: 1, questions: { q01: { base: 1, counts: { "25_34": 1 } } } }, error: null }]);
    const distributions = await loadQv2AdminDistributions(client);
    expect(distributions.questions.q01.counts["25_34"]).toBe(1);
    expect(calls[0].name).toBe("beta_validation_qv2_admin_distributions");
  });

  it("manda filtro codice, coorte, limite e offset alla porta bounded", async () => {
    const { client, calls } = fakeClient([{ data: rows(17, 1, 1), error: null }]);
    const page = await loadQv2AdminParticipants(client, { participantCode: "V017", cohort: "legacy", limit: 50, offset: 0 });
    expect(page.total).toBe(1);
    expect(calls).toEqual([
      {
        name: "beta_validation_qv2_admin_participants",
        args: { p_participant_code: "V017", p_cohort: "legacy", p_limit: 50, p_offset: 0 },
      },
    ]);
  });

  it("l'export pagina fino al totale dichiarato", async () => {
    const { client, calls } = fakeClient([
      { data: rows(1, 200, 250), error: null },
      { data: rows(201, 50, 250), error: null },
    ]);
    const participants = await loadAllQv2AdminParticipants(client, { participantCode: null, cohort: null });
    expect(participants).toHaveLength(250);
    expect(new Set(participants.map((participant) => participant.participantCode)).size).toBe(250);
    expect(calls.map((call) => (call.args as { p_offset: number; p_limit: number }))).toEqual([
      expect.objectContaining({ p_offset: 0, p_limit: 200 }),
      expect.objectContaining({ p_offset: 200, p_limit: 200 }),
    ]);
  });

  it("l'export fallisce invece di troncare in silenzio", async () => {
    const { client } = fakeClient([
      { data: rows(1, 200, 450), error: null },
      { data: rows(201, 100, 450), error: null },
    ]);
    await expect(loadAllQv2AdminParticipants(client, { participantCode: null, cohort: null })).rejects.toThrow(
      "Esportazione incompleta: 300 righe su 450",
    );
  });

  it("l'export rifiuta codici duplicati", async () => {
    const { client } = fakeClient([{ data: [...rows(1, 2, 3), ...rows(1, 1, 3)], error: null }]);
    await expect(loadAllQv2AdminParticipants(client, { participantCode: null, cohort: null })).rejects.toBeInstanceOf(
      MarketValidationAdminError,
    );
  });

  it("export vuoto senza errori", async () => {
    const { client } = fakeClient([{ data: [], error: null }]);
    expect(await loadAllQv2AdminParticipants(client, { participantCode: null, cohort: "qv2" })).toEqual([]);
  });

  it("chiede il dettaglio per participant_code e accetta null", async () => {
    const { client, calls } = fakeClient([
      { data: { participantCode: "V001", cohort: "qv2", events: [], questionnaire: {} }, error: null },
      { data: null, error: null },
    ]);
    expect((await loadQv2ParticipantDetail(client, "V001"))?.participantCode).toBe("V001");
    expect(await loadQv2ParticipantDetail(client, "V999")).toBeNull();
    expect(calls.map((call) => call.args)).toEqual([{ p_participant_code: "V001" }, { p_participant_code: "V999" }]);
  });

  it("propaga il diniego del database con messaggio leggibile", async () => {
    const { client } = fakeClient([{ data: null, error: { code: "42501", message: "Operazione non autorizzata." } }]);
    await expect(loadQv2AdminSummary(client)).rejects.toThrow("Operazione non autorizzata.");
  });

  it("non espone dettagli interni per errori generici", async () => {
    const { client } = fakeClient([{ data: null, error: { code: "XX000", message: "relation private.x leaked" } }]);
    await expect(loadQv2AdminDistributions(client)).rejects.toThrow("Non è stato possibile caricare le analytics. Riprova.");
  });

  it("senza client configurato fallisce in modo esplicito", async () => {
    await expect(loadQv2AdminSummary(null)).rejects.toThrow("Connessione a Supabase non configurata.");
  });
});
