import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  loadAllMarketValidationAdminParticipants,
  loadMarketValidationAdminParticipants,
  loadMarketValidationAdminSummary,
  MarketValidationAdminError,
} from "@/services/market-validation-admin-service";

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
  } as unknown as SupabaseClient;
  return { client, calls };
};

const row = (participantCode: string) => ({
  participant_code: participantCode,
  sessions_count: 1,
  completed: false,
});

describe("MV3 admin Supabase adapter", () => {
  it("chiama soltanto la RPC summary e normalizza il risultato", async () => {
    const { client, calls } = fakeClient([{ data: { testersStarted: 3 }, error: null }]);
    expect((await loadMarketValidationAdminSummary(client)).testersStarted).toBe(3);
    expect(calls).toEqual([{ name: "beta_validation_admin_summary", args: undefined }]);
  });

  it("manda filtro, limite e offset alla porta bounded", async () => {
    const { client, calls } = fakeClient([{ data: [row("V017")], error: null }]);
    const result = await loadMarketValidationAdminParticipants(client, {
      participantCode: "V017",
      limit: 100,
      offset: 0,
    });
    expect(result.map((participant) => participant.participantCode)).toEqual(["V017"]);
    expect(calls).toEqual([
      {
        name: "beta_validation_admin_participants",
        args: { p_participant_code: "V017", p_limit: 100, p_offset: 0 },
      },
    ]);
  });

  it("scarta righe malformate invece di esportare identificativi inattesi", async () => {
    const { client } = fakeClient([{ data: [row("V017"), row("V000"), { session_id: "secret" }], error: null }]);
    expect(await loadMarketValidationAdminParticipants(client, {
      participantCode: null,
      limit: 100,
      offset: 0,
    })).toHaveLength(1);
  });

  it("pagina l'export in blocchi controllati e si ferma sull'ultima pagina", async () => {
    const first = Array.from({ length: 200 }, (_, index) => row(`V${String(index + 1).padStart(3, "0")}`));
    const { client, calls } = fakeClient([
      { data: first, error: null },
      { data: [row("V201")], error: null },
    ]);
    const result = await loadAllMarketValidationAdminParticipants(client, null);
    expect(result).toHaveLength(201);
    expect(calls.map((call) => call.args)).toEqual([
      { p_participant_code: null, p_limit: 200, p_offset: 0 },
      { p_participant_code: null, p_limit: 200, p_offset: 200 },
    ]);
  });

  it("non supera V999 neppure quando ogni pagina è piena", async () => {
    const page = (offset: number, count: number) =>
      Array.from({ length: count }, (_, index) => row(`V${String(offset + index + 1).padStart(3, "0")}`));
    const { client, calls } = fakeClient([
      { data: page(0, 200), error: null },
      { data: page(200, 200), error: null },
      { data: page(400, 200), error: null },
      { data: page(600, 200), error: null },
      { data: page(800, 199), error: null },
    ]);
    expect(await loadAllMarketValidationAdminParticipants(client, null)).toHaveLength(999);
    expect(calls.at(-1)?.args).toEqual({
      p_participant_code: null,
      p_limit: 199,
      p_offset: 800,
    });
  });

  it("un filtro esegue una sola pagina anche quando torna una riga", async () => {
    const { client, calls } = fakeClient([{ data: [row("V017")], error: null }]);
    await loadAllMarketValidationAdminParticipants(client, "V017");
    expect(calls).toHaveLength(1);
  });

  it("non rivela dettagli database inattesi e preserva gli errori intenzionali", async () => {
    const denied = fakeClient([{ data: null, error: { code: "42501", message: "Operazione non autorizzata." } }]);
    await expect(loadMarketValidationAdminSummary(denied.client)).rejects.toThrow("Operazione non autorizzata.");

    const internal = fakeClient([{ data: null, error: { code: "XX000", message: "private.secret_column" } }]);
    await expect(loadMarketValidationAdminSummary(internal.client)).rejects.toThrow(
      "Non è stato possibile caricare le analytics. Riprova.",
    );
    expect(() => loadMarketValidationAdminSummary(null)).toThrow(MarketValidationAdminError);
  });
});
