import { describe, expect, test } from "bun:test";
import { preparaCorsa, type DipendenzeSetup } from "./global-setup";
import { IsolamentoNonProvato, NOME_VARIABILE_CORSA, PORTE_E2E } from "./support/target";

/**
 * VPM-018-FIX-E2E-01: setup e pulizia con dipendenze finte che registrano ogni
 * chiamata. Nessun Docker, nessun database: si osserva solo CHI verrebbe
 * chiamato. Le scritture SQL sono `rivendicaStack`, `puliziaFixture` e
 * `verificaResidui`; le letture sono ledger, utenti estranei e fixture.
 */
const CORSA = "abcdefabcdefabcdefabcdefabcdefab";

const finte = (sovrascritture: Partial<DipendenzeSetup> = {}) => {
  const chiamate: string[] = [];
  const traccia =
    <T,>(nome: string, valore: T) =>
    (): T => {
      chiamate.push(nome);
      return valore;
    };
  const env: Record<string, string | undefined> = {};
  const dipendenze: DipendenzeSetup = {
    risolviBersaglio: traccia("risolviBersaglio", {
      apiUrl: `http://127.0.0.1:${PORTE_E2E.api}`,
      appUrl: "http://127.0.0.1:3100",
      anonKey: "chiave",
      dbContainer: "supabase_db_vinea_e2e",
    }),
    garantisciGateway: traccia("garantisciGateway", undefined),
    verificaLedger: traccia("verificaLedger", 108),
    utentiEstranei: traccia("utentiEstranei", 0),
    rivendicaStack: (corsa) => {
      chiamate.push(`rivendicaStack:${corsa}`);
    },
    utentiFixturePresenti: traccia("utentiFixturePresenti", 0),
    puliziaFixture: traccia("puliziaFixture", ""),
    verificaResidui: () => {
      chiamate.push(`verificaResidui:${env[NOME_VARIABILE_CORSA] ?? "-"}`);
      return "0 0 0 0 0 0 0 0 0 false false false false";
    },
    generaCorsa: () => CORSA,
    generaPassword: () => "password-di-prova",
    env,
    ...sovrascritture,
  };
  return { chiamate, env, dipendenze };
};

const SCRITTURE = /^(rivendicaStack|puliziaFixture|verificaResidui)/;
const fallisce = (motivo: string) => () => {
  throw new IsolamentoNonProvato(motivo);
};

describe("setup e pulizia della suite browser (VPM-018-FIX-E2E-01)", () => {
  test("stack identificato: possesso, pulizia finale con la stessa corsa", async () => {
    const { chiamate, env, dipendenze } = finte();
    const pulizia = preparaCorsa(dipendenze);
    expect(env[NOME_VARIABILE_CORSA]).toBe(CORSA);
    expect(env.E2E_PASSWORD).toBe("password-di-prova");
    expect(chiamate).toEqual([
      "risolviBersaglio",
      "garantisciGateway",
      "verificaLedger",
      "utentiEstranei",
      `rivendicaStack:${CORSA}`,
      "utentiFixturePresenti",
    ]);
    env[NOME_VARIABILE_CORSA] = "manomessa";
    await pulizia();
    expect(chiamate.at(-1)).toBe(`verificaResidui:${CORSA}`);
  });

  test("residui di una corsa interrotta sullo stesso stack: puliti DOPO la presa di possesso", () => {
    const { chiamate, dipendenze } = finte({ utentiFixturePresenti: () => 5 });
    preparaCorsa(dipendenze);
    expect(chiamate.indexOf("puliziaFixture")).toBeGreaterThan(chiamate.indexOf(`rivendicaStack:${CORSA}`));
  });

  const fallimenti: [string, Partial<DipendenzeSetup>][] = [
    ["identità dello stack non provata", { risolviBersaglio: fallisce("nessuno stack E2E dedicato") }],
    ["gateway di un altro progetto", { garantisciGateway: fallisce("porta del gateway") }],
    ["ledger errato o marcatore di un'altra copia di lavoro", { verificaLedger: fallisce("il ledger non coincide") }],
    ["utenti estranei (stack di sviluppo)", { utentiEstranei: () => 3 }],
  ];

  for (const [caso, sovrascritture] of fallimenti) {
    test(`setup fallito (${caso}): zero scritture, nessuna pulizia restituita, nessun token`, () => {
      const { chiamate, env, dipendenze } = finte(sovrascritture);
      env[NOME_VARIABILE_CORSA] = "ereditato-dalla-shell";
      let pulizia: unknown;
      expect(() => {
        pulizia = preparaCorsa(dipendenze);
      }).toThrow(IsolamentoNonProvato);
      expect(pulizia).toBeUndefined();
      expect(chiamate.filter((c) => SCRITTURE.test(c))).toEqual([]);
      expect(env[NOME_VARIABILE_CORSA]).toBeUndefined();
      expect(env.E2E_PASSWORD).toBeUndefined();
    });
  }

  test("setup fallito DOPO la presa di possesso: nessuna pulizia restituita, nessuna verifica dei residui", () => {
    const { chiamate, env, dipendenze } = finte({
      utentiFixturePresenti: () => 5,
      puliziaFixture: fallisce("possesso perso durante la pulizia del residuo"),
    });
    let pulizia: unknown;
    expect(() => {
      pulizia = preparaCorsa(dipendenze);
    }).toThrow(IsolamentoNonProvato);
    expect(pulizia).toBeUndefined();
    expect(chiamate).toContain(`rivendicaStack:${CORSA}`);
    expect(chiamate.some((c) => c.startsWith("verificaResidui"))).toBe(false);
    expect(env.E2E_PASSWORD).toBeUndefined();
  });

  test("un token di corsa dalla shell non concede il possesso", () => {
    const { chiamate, env, dipendenze } = finte();
    env[NOME_VARIABILE_CORSA] = "ereditato-dalla-shell";
    let tokenAlRisolvere: string | undefined = "non letto";
    dipendenze.risolviBersaglio = () => {
      tokenAlRisolvere = env[NOME_VARIABILE_CORSA];
      chiamate.push("risolviBersaglio");
      return finte().dipendenze.risolviBersaglio();
    };
    preparaCorsa(dipendenze);
    expect(tokenAlRisolvere).toBeUndefined();
    expect(env[NOME_VARIABILE_CORSA]).toBe(CORSA);
  });
});
