import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createBalanceService } from "@/services/phase7/balance-service";

// ---------------------------------------------------------------------------
// Doppio del client: registra ogni RPC con i suoi argomenti, così un test può
// provare che cosa esattamente attraversa il confine verso il database — e,
// altrettanto importante, che non lo attraversi due volte in modo diverso.
// ---------------------------------------------------------------------------

type Risposta = { data?: unknown; error?: { message?: string } | null };

const fakeClient = (risposta: Risposta = { data: null }) => {
  const chiamate: { nome: string; args: Record<string, unknown> }[] = [];
  const client = {
    rpc: (nome: string, args: Record<string, unknown>) => {
      chiamate.push({ nome, args });
      return Promise.resolve(risposta);
    },
  } as unknown as SupabaseClient;
  return { client, chiamate };
};

const PRELIEVO = {
  id: "w-1",
  stato: "richiesto",
  amount_cents: 2500,
  currency: "eur",
  created_at: "2026-08-27T10:00:00Z",
};

describe("richiediPrelievo", () => {
  it("manda al database l'importo e la chiave di idempotenza del chiamante", async () => {
    const { client, chiamate } = fakeClient({ data: PRELIEVO });
    const esito = await createBalanceService(client).richiediPrelievo(2500, "chiave-abcdefgh");

    expect(chiamate).toEqual([
      {
        nome: "balance_prelievo_richiedi",
        args: { p_amount_cents: 2500, p_idempotency_key: "chiave-abcdefgh" },
      },
    ]);
    expect(esito).toEqual({
      ok: true,
      data: { id: "w-1", stato: "richiesto", amountCents: 2500, createdAt: "2026-08-27T10:00:00Z" },
    });
  });

  it("non inventa una chiave propria: due chiamate con la stessa chiave la ripetono identica", async () => {
    const { client, chiamate } = fakeClient({ data: PRELIEVO });
    const servizio = createBalanceService(client);
    await servizio.richiediPrelievo(2500, "chiave-abcdefgh");
    await servizio.richiediPrelievo(2500, "chiave-abcdefgh");

    expect(chiamate).toHaveLength(2);
    expect(chiamate[0]!.args).toEqual(chiamate[1]!.args);
  });

  it("senza client non tocca nulla e non finge un prelievo", async () => {
    const esito = await createBalanceService(null).richiediPrelievo(2500, "chiave-abcdefgh");
    expect(esito.ok).toBe(false);
  });

  it("una risposta senza identificativo non diventa un prelievo riuscito", async () => {
    const { client } = fakeClient({ data: null });
    const esito = await createBalanceService(client).richiediPrelievo(2500, "chiave-abcdefgh");
    expect(esito.ok).toBe(false);
  });

  it("l'errore del database non passa per un successo", async () => {
    const { client } = fakeClient({ data: null, error: { message: "Saldo Vinea insufficiente." } });
    const esito = await createBalanceService(client).richiediPrelievo(9_999_900, "chiave-abcdefgh");
    expect(esito.ok).toBe(false);
  });
});

describe("annullaPrelievo", () => {
  it("passa il solo identificativo: lo stato lo decide il database", async () => {
    const { client, chiamate } = fakeClient({ data: { id: "w-1", stato: "annullato" } });
    const esito = await createBalanceService(client).annullaPrelievo("w-1");

    expect(chiamate).toEqual([
      { nome: "balance_prelievo_annulla", args: { p_withdrawal_id: "w-1" } },
    ]);
    expect(esito.ok).toBe(true);
  });

  it("il rifiuto di annullare un prelievo in trasferimento resta un errore", async () => {
    const { client } = fakeClient({
      data: null,
      error: { message: "Questo prelievo è già in trasferimento e non può essere annullato." },
    });
    const esito = await createBalanceService(client).annullaPrelievo("w-1");
    expect(esito.ok).toBe(false);
  });
});
