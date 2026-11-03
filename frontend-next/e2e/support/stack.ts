import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import {
  CONTAINER_API_E2E,
  IsolamentoNonProvato,
  PORTE_E2E,
  SUPABASE_CLI_VERSION,
  ambienteStackE2E,
  componiBersaglio,
  garantisciDockerLocale,
  leggiIdentitaStack,
  projectIdDaConfig,
  type BersaglioE2E,
  type IdentitaStack,
} from "./target";

export const RADICE_REPO = path.resolve(__dirname, "..", "..", "..");
export const CARTELLA_TEST_SQL = path.join(RADICE_REPO, "supabase", "tests");
export const CARTELLA_MIGRAZIONI = path.join(RADICE_REPO, "supabase", "migrations");
/** Scritto da `e2e:stack up`, ignorato da Git: identità dello stack dedicato di questa copia di lavoro. */
export const FILE_IDENTITA = path.join(RADICE_REPO, "frontend-next", "e2e", ".stack-e2e.json");

export const PORTA_APP = Number(process.env.E2E_APP_PORT ?? "3100");
export const URL_APP = `http://127.0.0.1:${PORTA_APP}`;

const leggiValoreEnv = (testo: string, chiave: string): string => {
  const riga = testo.split(/\r?\n/).find((r) => r.startsWith(`${chiave}=`));
  return riga ? riga.slice(chiave.length + 1).replace(/^"|"$/g, "") : "";
};

/** Identità dello stack dedicato; rilegge il file a ogni chiamata (nessuna cache). */
export const leggiIdentita = (): IdentitaStack =>
  leggiIdentitaStack(existsSync(FILE_IDENTITA) ? readFileSync(FILE_IDENTITA, "utf8") : null);

export const projectIdSviluppo = (): string =>
  projectIdDaConfig(readFileSync(path.join(RADICE_REPO, "supabase", "config.toml"), "utf8"));

/**
 * Risolve il bersaglio: SOLO lo stack dedicato creato da `e2e:stack up` in
 * questa copia di lavoro (file di identità), mai lo stack di sviluppo. URL e
 * chiave vengono da `supabase status` del progetto riservato, oppure
 * dall'ambiente (memorizzati qui alla prima risoluzione, così configurazione,
 * worker e server li ereditano), e in entrambi i casi devono stare sulla porta
 * riservata. Il possesso del database si prova poi a ogni SQL (`sqlProtetto`).
 */
export const risolviBersaglio = (): BersaglioE2E => {
  const identita = leggiIdentita();
  let apiUrl = process.env.E2E_SUPABASE_URL ?? "";
  let anonKey = process.env.E2E_ANON_KEY ?? "";

  if (!apiUrl || !anonKey) {
    let uscita: string;
    try {
      uscita = execFileSync("npx", ["--yes", `supabase@${SUPABASE_CLI_VERSION}`, "status", "-o", "env"], {
        cwd: RADICE_REPO,
        encoding: "utf8",
        env: { ...process.env, ...ambienteStackE2E() },
        shell: process.platform === "win32",
        stdio: ["ignore", "pipe", "ignore"],
        timeout: 120_000,
      });
    } catch {
      throw new Error(
        "Stack E2E dedicato non raggiungibile: avviarlo con `bun run e2e:stack up` (richiede Docker).",
      );
    }
    apiUrl = leggiValoreEnv(uscita, "API_URL");
    anonKey = leggiValoreEnv(uscita, "ANON_KEY");
  }

  const bersaglio = componiBersaglio({
    identita,
    apiUrl,
    anonKey,
    appUrl: URL_APP,
    dbContainerRichiesto: process.env.E2E_DB_CONTAINER,
    projectIdSviluppo: projectIdSviluppo(),
  });
  garantisciDockerLocale(process.env.DOCKER_HOST);

  process.env.E2E_SUPABASE_URL = apiUrl;
  process.env.E2E_ANON_KEY = anonKey;
  process.env.E2E_DB_CONTAINER = bersaglio.dbContainer;
  return bersaglio;
};

/**
 * Lega l'URL dell'API al progetto: la porta riservata deve essere pubblicata
 * proprio dal gateway `supabase_kong_<progetto E2E>`, non da un altro stack.
 */
export const garantisciGatewayDelProgetto = (): void => {
  let pubblicate: string;
  try {
    pubblicate = execFileSync("docker", ["port", CONTAINER_API_E2E, "8000/tcp"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
      timeout: 30_000,
    });
  } catch {
    throw new IsolamentoNonProvato(`il gateway \`${CONTAINER_API_E2E}\` non è in esecuzione`);
  }
  if (!pubblicate.split(/\r?\n/).some((riga) => riga.trim().endsWith(`:${PORTE_E2E.api}`))) {
    throw new IsolamentoNonProvato(`il gateway del progetto E2E non pubblica la porta ${PORTE_E2E.api}`);
  }
};

export const fileMigrazioni = (): string[] => readdirSync(CARTELLA_MIGRAZIONI);
