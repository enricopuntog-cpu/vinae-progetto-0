import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { parseIntentiOrfaniAdmin, parseRimborsiDovutiAdmin } from "@/lib/accessori-postvendita/postvendita";
import { creaAccessoriPostvenditaService } from "./accessori-postvendita-service";

/**
 * VPM-015QA-FINAL-B2-COMPLETION — letture admin di sola lettura su intenti orfani e rimborsi dovuti.
 * Il confine di sicurezza resta nel database (`accessori_admin_richiesto`): qui si prova il contratto
 * del browser — risposta fuori forma = errore, mai un falso elenco vuoto — e che nessuna porta scriva.
 */

const ORDINE = "11111111-1111-4111-8111-111111111111";
const orfano = {
  ordine_id: ORDINE, provider: "stripe", intento: "pi_test_1", importo_cents: 1250, valuta: "eur",
  stato_pagamento: "intento_creato", stato_intento: "incerto", motivo: "timeout", aggiornato_at: "2026-11-03T10:00:00Z",
};
const dovuto = {
  ordine_id: ORDINE, importo_cents: 1250, valuta: "eur", rimborsato_cents: 0, motivo: "ordine_non_applicabile",
  aggiornato_at: "2026-11-03T10:00:00Z",
};

const finto = (risposte: Record<string, { data?: unknown; error?: { code?: string; hint?: string } | null }>) => {
  const chiamate: string[] = [];
  const client = {
    rpc: async (nome: string) => {
      chiamate.push(nome);
      return { data: risposte[nome]?.data ?? null, error: risposte[nome]?.error ?? null };
    },
  } as unknown as SupabaseClient;
  return { client, chiamate };
};

describe("parser admin intenti orfani e rimborsi dovuti", () => {
  it("accetta una riga valida e trasforma i nomi del database", () => {
    expect(parseIntentiOrfaniAdmin([orfano])).toEqual([
      {
        ordineId: ORDINE, provider: "stripe", intento: "pi_test_1", importoCents: 1250, valuta: "eur",
        statoPagamento: "intento_creato", statoIntento: "incerto", motivo: "timeout", aggiornatoAt: "2026-11-03T10:00:00Z",
      },
    ]);
    expect(parseRimborsiDovutiAdmin([dovuto])?.[0]).toMatchObject({ ordineId: ORDINE, importoCents: 1250, rimborsatoCents: 0 });
  });

  it("l'elenco vuoto è valido, una forma sbagliata è null (non un elenco vuoto)", () => {
    expect(parseIntentiOrfaniAdmin([])).toEqual([]);
    expect(parseRimborsiDovutiAdmin([])).toEqual([]);
    for (const v of [null, undefined, {}, "x", 3]) {
      expect(parseIntentiOrfaniAdmin(v)).toBeNull();
      expect(parseRimborsiDovutiAdmin(v)).toBeNull();
    }
  });

  it("rifiuta stato dell'intento sconosciuto, importo non intero o campi mancanti", () => {
    expect(parseIntentiOrfaniAdmin([{ ...orfano, stato_intento: "annullato" }])).toBeNull();
    expect(parseIntentiOrfaniAdmin([{ ...orfano, importo_cents: 12.5 }])).toBeNull();
    expect(parseIntentiOrfaniAdmin([{ ...orfano, intento: undefined }])).toBeNull();
    expect(parseRimborsiDovutiAdmin([{ ...dovuto, rimborsato_cents: "0" }])).toBeNull();
    expect(parseRimborsiDovutiAdmin([{ ...dovuto, ordine_id: "" }])).toBeNull();
  });
});

describe("servizio admin: letture di sola lettura", () => {
  it("chiama solo le due RPC di elenco e restituisce i dati tipizzati", async () => {
    const { client, chiamate } = finto({
      accessori_pagamenti_intenti_orfani: { data: [orfano] },
      accessori_pagamenti_rimborso_dovuto: { data: [dovuto] },
    });
    const s = creaAccessoriPostvenditaService(client);
    const o = await s.adminIntentiOrfani();
    const d = await s.adminRimborsiDovuti();
    expect(o.ok && o.data[0].statoIntento).toBe("incerto");
    expect(d.ok && d.data[0].ordineId).toBe(ORDINE);
    expect(chiamate).toEqual(["accessori_pagamenti_intenti_orfani", "accessori_pagamenti_rimborso_dovuto"]);
  });

  it("un errore del database (non admin, rete) è un errore, non un elenco vuoto", async () => {
    const { client } = finto({
      accessori_pagamenti_intenti_orfani: { error: { code: "42501" } },
      accessori_pagamenti_rimborso_dovuto: { error: { code: "XX000" } },
    });
    const s = creaAccessoriPostvenditaService(client);
    const o = await s.adminIntentiOrfani();
    const d = await s.adminRimborsiDovuti();
    expect(o.ok).toBe(false);
    expect(d.ok).toBe(false);
    expect(JSON.stringify([o, d])).not.toContain("XX000");
  });

  it("una risposta illeggibile è un errore; senza client nessuna chiamata", async () => {
    const { client } = finto({ accessori_pagamenti_intenti_orfani: { data: { x: 1 } } });
    expect((await creaAccessoriPostvenditaService(client).adminIntentiOrfani()).ok).toBe(false);
    expect((await creaAccessoriPostvenditaService(null).adminRimborsiDovuti()).ok).toBe(false);
  });
});
