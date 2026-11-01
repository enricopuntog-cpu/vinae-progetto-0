/**
 * Guardia di isolamento della suite browser.
 *
 * Fail-closed e senza rete: la suite crea utenti, accende interruttori e scrive
 * su Storage, quindi parte solo se API, app e database sono provabilmente uno
 * stack Supabase locale effimero. Niente qui conosce segreti: i valori arrivano
 * dal chiamante e non vengono mai stampati per intero.
 *
 * Modulo puro (nessun import di Playwright) perché lo eseguono anche i test di
 * `bun test`.
 */

/** Riferimento del progetto Supabase di produzione: rifiutato ovunque compaia. */
export const PRODUCTION_REF = "pijnmcllmfgjmgsvtcej";

/** Versione della CLI Supabase fissata, la stessa di `supabase-db-regression.yml`. */
export const SUPABASE_CLI_VERSION = "2.117.0";

const LOOPBACK_HOSTS: ReadonlySet<string> = new Set(["127.0.0.1", "localhost", "[::1]"]);

export class IsolamentoNonProvato extends Error {
  constructor(motivo: string) {
    super(`ISOLAMENTO NON PROVATO: ${motivo}`);
    this.name = "IsolamentoNonProvato";
  }
}

export interface BersaglioE2E {
  /** URL dell'API Supabase locale (gateway). */
  apiUrl: string;
  /** URL dell'applicazione sotto prova. */
  appUrl: string;
  /** Chiave anonima dello stack locale (pubblica per costruzione). */
  anonKey: string;
  /** Nome del container Docker del database locale. */
  dbContainer: string;
}

const nomeHost = (valore: string, etichetta: string): string => {
  let url: URL;
  try {
    url = new URL(valore);
  } catch {
    throw new IsolamentoNonProvato(`${etichetta} non è un URL valido`);
  }
  return url.hostname.toLowerCase();
};

export const èLoopback = (valore: string): boolean => {
  try {
    return LOOPBACK_HOSTS.has(new URL(valore).hostname.toLowerCase());
  } catch {
    return false;
  }
};

/** Legge il payload di un JWT senza verificarlo; `null` se non è un JWT. */
export const payloadJwt = (token: string): Record<string, unknown> | null => {
  const parti = token.split(".");
  if (parti.length !== 3) return null;
  try {
    const json = Buffer.from(parti[1].replace(/-/g, "+").replace(/_/g, "/"), "base64").toString("utf8");
    const valore: unknown = JSON.parse(json);
    return valore && typeof valore === "object" ? (valore as Record<string, unknown>) : null;
  } catch {
    return null;
  }
};

/**
 * Lancia `IsolamentoNonProvato` se anche una sola condizione non è dimostrata.
 * Non ha un percorso "forza": un caso che non si può isolare resta NON VERIFICATO.
 */
export const garantisciBersaglioIsolato = (bersaglio: BersaglioE2E): void => {
  const { apiUrl, appUrl, anonKey, dbContainer } = bersaglio;

  if (!apiUrl) throw new IsolamentoNonProvato("URL API mancante");
  if (!appUrl) throw new IsolamentoNonProvato("URL applicazione mancante");
  if (!anonKey) throw new IsolamentoNonProvato("chiave anonima mancante");

  for (const [etichetta, valore] of [
    ["API", apiUrl],
    ["applicazione", appUrl],
  ] as const) {
    const host = nomeHost(valore, etichetta);
    if (!LOOPBACK_HOSTS.has(host)) {
      throw new IsolamentoNonProvato(`${etichetta} non è su loopback (${host})`);
    }
    if (valore.includes(PRODUCTION_REF) || host.endsWith(".supabase.co")) {
      throw new IsolamentoNonProvato(`${etichetta} indica un progetto Supabase ospitato`);
    }
  }

  if (anonKey.includes(PRODUCTION_REF)) {
    throw new IsolamentoNonProvato("la chiave anonima nomina il progetto di produzione");
  }
  const claims = payloadJwt(anonKey);
  if (claims && ("ref" in claims || String(claims.iss ?? "").includes(PRODUCTION_REF))) {
    throw new IsolamentoNonProvato("la chiave anonima appartiene a un progetto ospitato");
  }

  if (!/^supabase_db_[A-Za-z0-9_.-]+$/.test(dbContainer)) {
    throw new IsolamentoNonProvato("il database non è il container locale `supabase_db_*`");
  }
};

/**
 * `docker exec` agisce sul daemon indicato da `DOCKER_HOST`: se puntasse a un
 * host remoto (tcp, ssh, tls) il database "locale" potrebbe non esserlo. Ammessi
 * solo daemon locali: variabile assente, socket unix, named pipe, o tcp su loopback.
 */
export const garantisciDockerLocale = (dockerHost: string | undefined): void => {
  const valore = (dockerHost ?? "").trim();
  if (valore === "" || /^(unix|npipe):/i.test(valore)) return;
  if (/^(tcp|http|https):\/\//i.test(valore) && èLoopback(valore.replace(/^tcp:/i, "http:"))) return;
  throw new IsolamentoNonProvato("DOCKER_HOST non indica un daemon locale");
};

/** Estrae `project_id` dal testo di `supabase/config.toml`. */
export const projectIdDaConfig = (testoToml: string): string => {
  const trovato = /^\s*project_id\s*=\s*"([^"]+)"/m.exec(testoToml);
  if (!trovato) throw new IsolamentoNonProvato("project_id assente in supabase/config.toml");
  return trovato[1];
};

/** Versioni del ledger confrontabili con i prefissi dei file di migrazione. */
export const versioniMigrazioni = (nomiFile: readonly string[]): string[] =>
  nomiFile
    .filter((n) => n.endsWith(".sql"))
    .map((n) => n.split("_")[0])
    .sort();

/** Differenze fra ledger e file: entrambe vuote = stack costruito da questo commit. */
export const confrontaLedger = (
  ledger: readonly string[],
  file: readonly string[],
): { mancanti: string[]; inPiu: string[] } => {
  const inLedger = new Set(ledger);
  const suDisco = new Set(file);
  return {
    mancanti: file.filter((v) => !inLedger.has(v)),
    inPiu: ledger.filter((v) => !suDisco.has(v)),
  };
};
