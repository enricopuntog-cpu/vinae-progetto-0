import { execFileSync } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import {
  SUPABASE_CLI_VERSION,
  garantisciBersaglioIsolato,
  garantisciDockerLocale,
  projectIdDaConfig,
  type BersaglioE2E,
} from "./target";

export const RADICE_REPO = path.resolve(__dirname, "..", "..", "..");
export const CARTELLA_TEST_SQL = path.join(RADICE_REPO, "supabase", "tests");
export const CARTELLA_MIGRAZIONI = path.join(RADICE_REPO, "supabase", "migrations");

export const PORTA_APP = Number(process.env.E2E_APP_PORT ?? "3100");
export const URL_APP = `http://127.0.0.1:${PORTA_APP}`;

const leggiValoreEnv = (testo: string, chiave: string): string => {
  const riga = testo.split(/\r?\n/).find((r) => r.startsWith(`${chiave}=`));
  return riga ? riga.slice(chiave.length + 1).replace(/^"|"$/g, "") : "";
};

/**
 * Risolve il bersaglio. Ordine: variabili `E2E_SUPABASE_URL` / `E2E_ANON_KEY`
 * (come la CI), altrimenti `supabase status` dello stack locale. Il risultato
 * viene memorizzato nell'ambiente del processo, così la configurazione, i
 * worker e il server lo ereditano senza ripetere la chiamata e senza file.
 */
export const risolviBersaglio = (): BersaglioE2E => {
  let apiUrl = process.env.E2E_SUPABASE_URL ?? "";
  let anonKey = process.env.E2E_ANON_KEY ?? "";

  if (!apiUrl || !anonKey) {
    let uscita: string;
    try {
      uscita = execFileSync("npx", ["--yes", `supabase@${SUPABASE_CLI_VERSION}`, "status", "-o", "env"], {
        cwd: RADICE_REPO,
        encoding: "utf8",
        shell: process.platform === "win32",
        stdio: ["ignore", "pipe", "ignore"],
        timeout: 120_000,
      });
    } catch {
      throw new Error(
        "Stack Supabase locale non raggiungibile: avviarlo con `bun run e2e:stack up` (richiede Docker).",
      );
    }
    apiUrl = leggiValoreEnv(uscita, "API_URL");
    anonKey = leggiValoreEnv(uscita, "ANON_KEY");
  }

  const projectId = projectIdDaConfig(readFileSync(path.join(RADICE_REPO, "supabase", "config.toml"), "utf8"));
  const bersaglio: BersaglioE2E = {
    apiUrl,
    anonKey,
    appUrl: URL_APP,
    dbContainer: process.env.E2E_DB_CONTAINER ?? `supabase_db_${projectId}`,
  };
  garantisciBersaglioIsolato(bersaglio);
  garantisciDockerLocale(process.env.DOCKER_HOST);

  process.env.E2E_SUPABASE_URL = apiUrl;
  process.env.E2E_ANON_KEY = anonKey;
  process.env.E2E_DB_CONTAINER = bersaglio.dbContainer;
  return bersaglio;
};

export const fileMigrazioni = (): string[] => readdirSync(CARTELLA_MIGRAZIONI);
