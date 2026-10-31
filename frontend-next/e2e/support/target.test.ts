import { describe, expect, test } from "bun:test";
import {
  IsolamentoNonProvato,
  PRODUCTION_REF,
  confrontaLedger,
  garantisciDockerLocale,
  garantisciBersaglioIsolato,
  payloadJwt,
  projectIdDaConfig,
  versioniMigrazioni,
  èLoopback,
  type BersaglioE2E,
} from "./target";

const base: BersaglioE2E = {
  apiUrl: "http://127.0.0.1:54321",
  appUrl: "http://127.0.0.1:3100",
  anonKey: "chiave-locale-di-prova",
  dbContainer: "supabase_db_p_rogettto_vinae",
};

const jwt = (payload: Record<string, unknown>): string =>
  ["e30", Buffer.from(JSON.stringify(payload)).toString("base64url"), "firma"].join(".");

describe("guardia di isolamento E2E", () => {
  test("accetta lo stack locale", () => {
    expect(() => garantisciBersaglioIsolato(base)).not.toThrow();
    expect(() => garantisciBersaglioIsolato({ ...base, apiUrl: "http://localhost:54321" })).not.toThrow();
    expect(() => garantisciBersaglioIsolato({ ...base, apiUrl: "http://[::1]:54321" })).not.toThrow();
  });

  test("rifiuta host non loopback e il progetto di produzione", () => {
    const rifiutati: Partial<BersaglioE2E>[] = [
      { apiUrl: `https://${PRODUCTION_REF}.supabase.co` },
      { apiUrl: "https://altro.supabase.co" },
      { apiUrl: "http://192.168.1.120:54321" },
      { apiUrl: "http://127.0.0.1.evil.example:54321" },
      { appUrl: "https://vineawineclub.com" },
      { appUrl: "http://localhost.evil.example" },
      { apiUrl: `http://127.0.0.1:54321/${PRODUCTION_REF}` },
    ];
    for (const sostituzione of rifiutati) {
      expect(() => garantisciBersaglioIsolato({ ...base, ...sostituzione })).toThrow(IsolamentoNonProvato);
    }
  });

  test("rifiuta valori mancanti o non URL, senza fallback", () => {
    expect(() => garantisciBersaglioIsolato({ ...base, apiUrl: "" })).toThrow(IsolamentoNonProvato);
    expect(() => garantisciBersaglioIsolato({ ...base, appUrl: "" })).toThrow(IsolamentoNonProvato);
    expect(() => garantisciBersaglioIsolato({ ...base, anonKey: "" })).toThrow(IsolamentoNonProvato);
    expect(() => garantisciBersaglioIsolato({ ...base, apiUrl: "non-un-url" })).toThrow(IsolamentoNonProvato);
  });

  test("rifiuta chiavi di un progetto ospitato", () => {
    expect(() => garantisciBersaglioIsolato({ ...base, anonKey: jwt({ ref: "abcd", role: "anon" }) })).toThrow(
      IsolamentoNonProvato,
    );
    expect(() =>
      garantisciBersaglioIsolato({ ...base, anonKey: jwt({ iss: `https://${PRODUCTION_REF}.supabase.co/auth/v1` }) }),
    ).toThrow(IsolamentoNonProvato);
    expect(() => garantisciBersaglioIsolato({ ...base, anonKey: `x-${PRODUCTION_REF}` })).toThrow(IsolamentoNonProvato);
    expect(() =>
      garantisciBersaglioIsolato({ ...base, anonKey: jwt({ iss: "supabase-demo", role: "anon" }) }),
    ).not.toThrow();
  });

  test("il database deve essere un container locale supabase_db_*", () => {
    expect(() => garantisciBersaglioIsolato({ ...base, dbContainer: "postgres" })).toThrow(IsolamentoNonProvato);
    expect(() => garantisciBersaglioIsolato({ ...base, dbContainer: "supabase_db_x; rm -rf /" })).toThrow(
      IsolamentoNonProvato,
    );
    expect(() => garantisciBersaglioIsolato({ ...base, dbContainer: "" })).toThrow(IsolamentoNonProvato);
  });

  test("DOCKER_HOST deve indicare un daemon locale", () => {
    for (const ok of [undefined, "", "unix:///var/run/docker.sock", "npipe:////./pipe/docker_engine", "tcp://127.0.0.1:2375", "tcp://localhost:2375"]) {
      expect(() => garantisciDockerLocale(ok)).not.toThrow();
    }
    for (const no of ["tcp://10.0.0.5:2375", "ssh://utente@server", "tcp://docker.example.com:2376", "https://remoto.example"]) {
      expect(() => garantisciDockerLocale(no)).toThrow(IsolamentoNonProvato);
    }
  });

  test("èLoopback non cade su input non validi", () => {
    expect(èLoopback("http://127.0.0.1:3000")).toBe(true);
    expect(èLoopback("https://vineawineclub.com")).toBe(false);
    expect(èLoopback("")).toBe(false);
  });

  test("payloadJwt legge solo JWT ben formati", () => {
    expect(payloadJwt(jwt({ role: "anon" }))).toEqual({ role: "anon" });
    expect(payloadJwt("non.un.jwt!")).toBeNull();
    expect(payloadJwt("sb_publishable_abc")).toBeNull();
  });

  test("projectIdDaConfig legge il project_id e fallisce se manca", () => {
    expect(projectIdDaConfig('# nota\nproject_id = "p_rogettto_vinae"\n[api]\n')).toBe("p_rogettto_vinae");
    expect(() => projectIdDaConfig("[api]\nport = 54321\n")).toThrow(IsolamentoNonProvato);
  });

  test("il ledger deve coincidere con i file di migrazione", () => {
    const file = versioniMigrazioni(["20261021090000_a.sql", "20261020120000_b.sql", "README.md"]);
    expect(file).toEqual(["20261020120000", "20261021090000"]);
    expect(confrontaLedger(file, file)).toEqual({ mancanti: [], inPiu: [] });
    expect(confrontaLedger(["20261020120000"], file)).toEqual({ mancanti: ["20261021090000"], inPiu: [] });
    expect(confrontaLedger([...file, "20990101000000"], file)).toEqual({ mancanti: [], inPiu: ["20990101000000"] });
  });
});
