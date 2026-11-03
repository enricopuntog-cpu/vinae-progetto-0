import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import path from "node:path";
import {
  CONTAINER_DB_E2E,
  IsolamentoNonProvato,
  PORTE_E2E,
  PRODUCTION_REF,
  PROJECT_ID_E2E,
  SQL_MARCATORE,
  ambienteStackE2E,
  componiBersaglio,
  confrontaLedger,
  corsaPerSql,
  decidiDown,
  decidiUp,
  garantisciDockerLocale,
  garantisciBersaglioIsolato,
  leggiIdentitaStack,
  payloadJwt,
  projectIdDaConfig,
  sqlProtetto,
  versioniMigrazioni,
  èLoopback,
  type BersaglioE2E,
  type IdentitaStack,
} from "./target";
import { risolviBersaglio } from "./stack";

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

const RADICE = path.resolve(__dirname, "..", "..", "..");
const PROJECT_ID_SVILUPPO = projectIdDaConfig(readFileSync(path.join(RADICE, "supabase", "config.toml"), "utf8"));
const NONCE = "0123456789abcdef0123456789abcdef";
const identita: IdentitaStack = { projectId: PROJECT_ID_E2E, nonce: NONCE };
const fontiValide = {
  identita,
  apiUrl: `http://127.0.0.1:${PORTE_E2E.api}`,
  anonKey: "chiave-locale-di-prova",
  appUrl: "http://127.0.0.1:3100",
  dbContainerRichiesto: undefined,
  projectIdSviluppo: PROJECT_ID_SVILUPPO,
};

describe("stack E2E dedicato (VPM-018-FIX-E2E-01)", () => {
  test("il progetto riservato non è quello di sviluppo e la CLI lo riceve con porte proprie", () => {
    expect(PROJECT_ID_E2E).not.toBe(PROJECT_ID_SVILUPPO);
    expect(CONTAINER_DB_E2E).toBe(`supabase_db_${PROJECT_ID_E2E}`);
    expect(ambienteStackE2E()).toEqual({
      SUPABASE_PROJECT_ID: PROJECT_ID_E2E,
      SUPABASE_API_PORT: "55321",
      SUPABASE_DB_PORT: "55322",
      SUPABASE_DB_SHADOW_PORT: "55320",
    });
  });

  test("stack effimero identificato: bersaglio consentito sul container riservato", () => {
    expect(componiBersaglio(fontiValide)).toEqual({
      apiUrl: fontiValide.apiUrl,
      anonKey: fontiValide.anonKey,
      appUrl: fontiValide.appUrl,
      dbContainer: CONTAINER_DB_E2E,
    });
    expect(componiBersaglio({ ...fontiValide, dbContainerRichiesto: CONTAINER_DB_E2E }).dbContainer).toBe(CONTAINER_DB_E2E);
  });

  test("target implicito condiviso: l'API dello stack di sviluppo è rifiutata", () => {
    for (const apiUrl of ["http://127.0.0.1:54321", "http://localhost:56321", "http://127.0.0.1"]) {
      expect(() => componiBersaglio({ ...fontiValide, apiUrl })).toThrow(IsolamentoNonProvato);
    }
  });

  test("container diverso da quello autorizzato: rifiutato", () => {
    for (const dbContainerRichiesto of [`supabase_db_${PROJECT_ID_SVILUPPO}`, "supabase_db_vpm018_audit", "supabase_db_vinea_e2e2"]) {
      expect(() => componiBersaglio({ ...fontiValide, dbContainerRichiesto })).toThrow(IsolamentoNonProvato);
    }
  });

  test("progetto E2E uguale a quello di sviluppo: rifiutato", () => {
    expect(() => componiBersaglio({ ...fontiValide, projectIdSviluppo: PROJECT_ID_E2E })).toThrow(IsolamentoNonProvato);
  });

  test("identità non provata: file assente, illeggibile, altro progetto o nonce non valido", () => {
    const casi: (string | null)[] = [
      null,
      "non json",
      JSON.stringify({ projectId: PROJECT_ID_SVILUPPO, nonce: NONCE }),
      JSON.stringify({ projectId: PROJECT_ID_E2E }),
      JSON.stringify({ projectId: PROJECT_ID_E2E, nonce: "corto" }),
      JSON.stringify({ projectId: PROJECT_ID_E2E, nonce: `${NONCE}'; drop schema public; --` }),
      "null",
    ];
    for (const testo of casi) expect(() => leggiIdentitaStack(testo)).toThrow(IsolamentoNonProvato);
    // Senza file il motivo deve indicare come creare lo stack dedicato, non un generico errore di formato.
    expect(() => leggiIdentitaStack(null)).toThrow("bun run e2e:stack up");
    expect(leggiIdentitaStack(JSON.stringify({ projectId: PROJECT_ID_E2E, nonce: NONCE, creatoIl: "x" }))).toEqual(identita);
  });

  test("risolviBersaglio rifiuta lo stack di sviluppo senza eseguire nulla e senza toccare l'ambiente", () => {
    const prima = { url: process.env.E2E_SUPABASE_URL, chiave: process.env.E2E_ANON_KEY, db: process.env.E2E_DB_CONTAINER };
    try {
      process.env.E2E_SUPABASE_URL = "http://127.0.0.1:54321";
      process.env.E2E_ANON_KEY = "chiave-locale-di-prova";
      delete process.env.E2E_DB_CONTAINER;
      // Con o senza file di identità in questa copia di lavoro, lo stack di sviluppo non passa.
      expect(() => risolviBersaglio()).toThrow(IsolamentoNonProvato);
      expect(process.env.E2E_DB_CONTAINER).toBeUndefined();
    } finally {
      for (const [chiave, valore] of [
        ["E2E_SUPABASE_URL", prima.url],
        ["E2E_ANON_KEY", prima.chiave],
        ["E2E_DB_CONTAINER", prima.db],
      ] as const) {
        if (valore === undefined) delete process.env[chiave];
        else process.env[chiave] = valore;
      }
    }
  });

  test("ogni SQL parte dopo la verifica del marcatore, nella stessa sessione", () => {
    const sql = sqlProtetto("delete from x;", { e2e_password: "abc" }, { nonce: NONCE, corsa: "" });
    const guardia = sql.indexOf("do $guardia$");
    expect(guardia).toBeGreaterThan(0);
    expect(sql.indexOf("delete from x;")).toBeGreaterThan(sql.indexOf("$guardia$;", guardia + 1));
    expect(sql).toContain(`\\set e2e_nonce '${NONCE}'`);
    expect(sql).toContain("\\set e2e_corsa ''");
    expect(sql).toContain("\\set e2e_password 'abc'");
    expect(sql).toContain("to_regclass('vinea_e2e.identita') is null");
    expect(sql).toContain("nonce = current_setting('vinea_e2e.nonce')");
    expect(sql).toContain("corsa = current_setting('vinea_e2e.corsa')");
  });

  test("senza prova di possesso valida il SQL non viene nemmeno composto", () => {
    expect(() => sqlProtetto("select 1;", {}, { nonce: "", corsa: "" })).toThrow(IsolamentoNonProvato);
    expect(() => sqlProtetto("select 1;", {}, { nonce: NONCE, corsa: "x'; --" })).toThrow(IsolamentoNonProvato);
    expect(() => sqlProtetto("select 1;", { "a;b": "1" }, { nonce: NONCE, corsa: "" })).toThrow("Variabile psql non ammessa.");
    expect(() => sqlProtetto("select 1;", { e2e_password: "x'y" }, { nonce: NONCE, corsa: "" })).toThrow("Variabile psql non ammessa.");
  });

  test("senza token di corsa solo le chiamate del setup prima del possesso possono eseguire SQL", () => {
    expect(() => corsaPerSql(undefined, false)).toThrow(IsolamentoNonProvato);
    expect(() => corsaPerSql("", false)).toThrow(IsolamentoNonProvato);
    expect(corsaPerSql(NONCE, false)).toBe(NONCE);
    expect(corsaPerSql(undefined, true)).toBe("");
    expect(corsaPerSql(NONCE, true)).toBe("");
  });

  test("il marcatore si scrive solo su uno stack nuovo e non è esposto", () => {
    expect(SQL_MARCATORE).toContain("create schema vinea_e2e;");
    expect(SQL_MARCATORE).not.toContain("if not exists");
    expect(SQL_MARCATORE).toContain("revoke all on schema vinea_e2e from public;");
    expect(SQL_MARCATORE).not.toMatch(/grant/i);
  });

  test("up rifiuta risorse già esistenti del progetto riservato", () => {
    expect(() => decidiUp([])).not.toThrow();
    expect(() => decidiUp([CONTAINER_DB_E2E])).toThrow(IsolamentoNonProvato);
    expect(() => decidiUp([`supabase_storage_${PROJECT_ID_E2E}`])).toThrow(IsolamentoNonProvato);
  });

  test("down su stack non autorizzato: rifiutato", () => {
    const valido = { conferma: true, identita, etichettaContainer: PROJECT_ID_E2E, nonceNelDatabase: NONCE };
    const rifiutati = [
      { ...valido, conferma: false },
      { ...valido, identita: null },
      { ...valido, etichettaContainer: null },
      { ...valido, etichettaContainer: PROJECT_ID_SVILUPPO },
      { ...valido, nonceNelDatabase: null },
      { ...valido, nonceNelDatabase: "fedcba9876543210fedcba9876543210" },
    ];
    for (const stato of rifiutati) expect(() => decidiDown(stato)).toThrow(IsolamentoNonProvato);
  });

  test("down su stack dedicato verificato: solo il progetto riservato, mai quello di sviluppo", () => {
    const argomenti = decidiDown({ conferma: true, identita, etichettaContainer: PROJECT_ID_E2E, nonceNelDatabase: NONCE });
    expect(argomenti).toEqual(["stop", "--no-backup", "--project-id", PROJECT_ID_E2E]);
    expect(argomenti).not.toContain(PROJECT_ID_SVILUPPO);
  });
});

describe("runner senza percorsi distruttivi impliciti (VPM-018-FIX-E2E-01)", () => {
  const leggi = (relativo: string): string => readFileSync(path.join(RADICE, relativo), "utf8");

  test("nessun globalTeardown e nessun server riusato", () => {
    const configurazione = leggi("frontend-next/playwright.config.ts");
    expect(configurazione).not.toMatch(/globalTeardown\s*:/);
    expect(configurazione).toContain("reuseExistingServer: false");
    expect(configurazione).not.toContain("E2E_REUSE_SERVER");
    expect(() => leggi("frontend-next/e2e/global-teardown.ts")).toThrow();
  });

  test("il workflow non avvia né distrugge stack senza il progetto riservato", () => {
    const workflow = leggi(".github/workflows/e2e-browser.yml");
    expect(workflow).not.toMatch(/^\s*supabase (start|stop|status)/m);
    for (const riga of workflow.split("\n").filter((r) => /supabase@[\d.]+ stop/.test(r))) {
      expect(riga).toContain(`--project-id ${PROJECT_ID_E2E}`);
    }
    expect(workflow).toContain("bun run e2e:stack up");
    expect(workflow).toContain("bun run e2e:stack down --conferma");
    expect(workflow).toContain("pulizia completata");
    expect(workflow).not.toContain("E2E_EPHEMERAL");
  });
});
