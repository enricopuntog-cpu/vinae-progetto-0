/**
 * VP-D: classi economiche nei servizi.
 *
 * L'aliquota è decisa dal database: questi test fissano che il client chieda
 * la configurazione di una classe esplicita (mai «la» configurazione), che una
 * classe senza riga non ricada su un'altra, e che la migrazione VP-D tenga la
 * forma promessa al frontend.
 */
import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createMarketplaceConfigService } from "@/services/phase7/marketplace-config-service";

const radice = join(import.meta.dir, "../../..");
const leggiRepo = (p: string) => readFileSync(join(radice, p), "utf8");

type Esito = { data: unknown; error: unknown };

function clientConfig(righe: Array<Record<string, unknown>>) {
  const filtri: Array<{ metodo: string; argomenti: unknown[] }> = [];
  const client = {
    from: (tabella: string) => {
      let classe: unknown;
      const builder: Record<string, unknown> = {
        select: (...argomenti: unknown[]) => {
          filtri.push({ metodo: `select:${tabella}`, argomenti });
          return builder;
        },
        eq: (colonna: string, valore: unknown) => {
          filtri.push({ metodo: "eq", argomenti: [colonna, valore] });
          if (colonna === "classe_venditore") classe = valore;
          return builder;
        },
        maybeSingle: (): Promise<Esito> => {
          const trovate = righe.filter((r) => r.classe_venditore === classe);
          return Promise.resolve(
            trovate.length > 1
              ? { data: null, error: { code: "PGRST116", message: "più righe" } }
              : { data: trovate[0] ?? null, error: null },
          );
        },
      };
      return builder;
    },
  } as unknown as SupabaseClient;
  return { client, filtri };
}

const riga = (classe: string, margine: number) => ({
  margine_obiettivo_bps: margine,
  riferimento_stripe_percentuale_bps: 209,
  riferimento_stripe_fisso_cents: 25,
  auto_rilascio_giorni: 2,
  classe_venditore: classe,
});

describe("VP-D — configurazione di mercato per classe", () => {
  it("chiede la riga della classe indicata e la restituisce", async () => {
    const { client, filtri } = clientConfig([riga("privato", 800), riga("partner", 1500)]);
    const servizio = createMarketplaceConfigService(client);

    const privato = await servizio.corrente("privato");
    const partner = await servizio.corrente("partner");

    expect(privato.ok && privato.data?.margine_obiettivo_bps).toBe(800);
    expect(partner.ok && partner.data?.margine_obiettivo_bps).toBe(1500);
    expect(filtri.filter((f) => f.metodo === "eq")).toEqual([
      { metodo: "eq", argomenti: ["classe_venditore", "privato"] },
      { metodo: "eq", argomenti: ["classe_venditore", "partner"] },
    ]);
  });

  it("una classe senza riga corrente risponde null, senza ripiegare sull'altra", async () => {
    const { client } = clientConfig([riga("privato", 800)]);
    const esito = await createMarketplaceConfigService(client).corrente("partner");
    expect(esito).toEqual({ ok: true, data: null });
  });

  it("senza client non inventa una configurazione", async () => {
    const esito = await createMarketplaceConfigService(null).corrente("privato");
    expect(esito.ok).toBe(false);
  });
});

describe("VP-D — forma della migrazione promessa al frontend", () => {
  const migrazione = leggiRepo("supabase/migrations/20261012200000_vp_d_classi_economiche.sql");

  it("1500 bps per i Partner, mai 1600, con fee copiate dalla riga privata", () => {
    expect(migrazione).toContain("'partner', 1500,");
    expect(migrazione).not.toMatch(/'partner',\s*1600/);
    expect(migrazione).toContain("v_privata.riferimento_stripe_percentuale_bps");
  });

  it("una riga corrente per classe e nessun lettore a zero argomenti", () => {
    expect(migrazione).toContain("drop index public.marketplace_config_una_corrente;");
    expect(migrazione).toContain("on public.marketplace_config (classe_venditore)");
    expect(migrazione).toContain("drop function private.marketplace_config_corrente();");
  });

  it("le porte di preventivo non accettano una classe dal client", () => {
    const firma = migrazione.match(/create function public\.listing_preventivo\(([^)]*)\)/);
    expect(firma?.[1]).not.toContain("classe_venditore");
    const vendita = migrazione.match(/create function public\.preventivo_vendita\(([^)]*)\)/);
    expect(vendita?.[1]).not.toContain("classe_venditore");
  });

  it("non accende vendita_partner né ordini_multi_unita", () => {
    expect(migrazione).not.toMatch(/set\s+vendita_partner\s*=\s*true/i);
    expect(migrazione).not.toMatch(/set\s+ordini_multi_unita\s*=\s*true/i);
  });
});
