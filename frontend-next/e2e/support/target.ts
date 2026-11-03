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

/**
 * Stack E2E DEDICATO (VPM-018-FIX-E2E-01). Lo stack di sviluppo usa il
 * `project_id` di `supabase/config.toml`, condiviso da ogni worktree: la suite
 * non lo seleziona mai. `e2e:stack up` avvia un progetto con questo nome
 * riservato e porte proprie, e scrive nel suo database un marcatore con un
 * nonce casuale che solo questa copia di lavoro conosce (file di identità).
 * Ogni SQL della suite verifica il marcatore nella stessa sessione psql in cui
 * scrive; `down` distrugge solo il progetto riservato e solo se il marcatore
 * coincide. Nessuna variabile di consenso: l'identità si dimostra, non si dichiara.
 */
export const PROJECT_ID_E2E = "vinea_e2e";
export const CONTAINER_DB_E2E = `supabase_db_${PROJECT_ID_E2E}`;
export const CONTAINER_API_E2E = `supabase_kong_${PROJECT_ID_E2E}`;
/** Porte dell'host dello stack dedicato: diverse da quelle di sviluppo (5432x). */
export const PORTE_E2E = { api: 55321, db: 55322, shadow: 55320 } as const;
/** Etichetta che la CLI Supabase mette su container e volumi di un progetto. */
export const ETICHETTA_PROGETTO = "com.supabase.cli.project";

/** Override della CLI (viper, prefisso `SUPABASE_`): progetto e porte dello stack dedicato. */
export const ambienteStackE2E = (): Record<string, string> => ({
  SUPABASE_PROJECT_ID: PROJECT_ID_E2E,
  SUPABASE_API_PORT: String(PORTE_E2E.api),
  SUPABASE_DB_PORT: String(PORTE_E2E.db),
  SUPABASE_DB_SHADOW_PORT: String(PORTE_E2E.shadow),
});

export interface IdentitaStack {
  projectId: string;
  /** Segreto di possesso dello stack, scritto da `e2e:stack up` nel suo database. */
  nonce: string;
}

const NONCE = /^[0-9a-f]{32}$/;

/** Legge il file di identità scritto da `e2e:stack up`; `null` = file assente. */
export const leggiIdentitaStack = (testo: string | null): IdentitaStack => {
  if (testo === null) {
    throw new IsolamentoNonProvato(
      "nessuno stack E2E dedicato creato da questa copia di lavoro: avviarlo con `bun run e2e:stack up`",
    );
  }
  let valore: unknown;
  try {
    valore = JSON.parse(testo);
  } catch {
    throw new IsolamentoNonProvato("file di identità dello stack E2E illeggibile");
  }
  const { projectId, nonce } = (valore ?? {}) as Partial<IdentitaStack>;
  if (projectId !== PROJECT_ID_E2E) {
    throw new IsolamentoNonProvato(`il file di identità non nomina il progetto E2E riservato \`${PROJECT_ID_E2E}\``);
  }
  if (typeof nonce !== "string" || !NONCE.test(nonce)) {
    throw new IsolamentoNonProvato("il file di identità non contiene un nonce valido");
  }
  return { projectId, nonce };
};

/**
 * Compone e valida il bersaglio dello stack dedicato. Il container non si
 * sceglie: è quello del progetto riservato. L'API deve stare sulla porta
 * riservata, quindi un URL o una chiave dello stack di sviluppo non passano.
 */
export const componiBersaglio = (fonti: {
  identita: IdentitaStack;
  apiUrl: string;
  anonKey: string;
  appUrl: string;
  /** `E2E_DB_CONTAINER`, ammesso solo se uguale al container riservato. */
  dbContainerRichiesto: string | undefined;
  /** `project_id` di `supabase/config.toml`, cioè lo stack di sviluppo condiviso. */
  projectIdSviluppo: string;
}): BersaglioE2E => {
  const { identita, apiUrl, anonKey, appUrl, dbContainerRichiesto, projectIdSviluppo } = fonti;
  if (identita.projectId !== PROJECT_ID_E2E) {
    throw new IsolamentoNonProvato(`l'identità non nomina il progetto E2E riservato \`${PROJECT_ID_E2E}\``);
  }
  if (projectIdSviluppo === PROJECT_ID_E2E) {
    throw new IsolamentoNonProvato("il progetto E2E coincide con quello di sviluppo");
  }
  if (dbContainerRichiesto && dbContainerRichiesto !== CONTAINER_DB_E2E) {
    throw new IsolamentoNonProvato(`E2E_DB_CONTAINER deve essere \`${CONTAINER_DB_E2E}\` (stack dedicato)`);
  }
  const bersaglio: BersaglioE2E = { apiUrl, anonKey, appUrl, dbContainer: CONTAINER_DB_E2E };
  garantisciBersaglioIsolato(bersaglio);
  if (new URL(apiUrl).port !== String(PORTE_E2E.api)) {
    throw new IsolamentoNonProvato(`l'API non è sulla porta dello stack dedicato (${PORTE_E2E.api})`);
  }
  return bersaglio;
};

/** Token di corsa: lo scrive il setup nel marcatore, così una corsa più nuova toglie il possesso alla vecchia. */
export const NOME_VARIABILE_CORSA = "E2E_CORSA";

/**
 * Token da verificare in un SQL. Senza corsa sono ammesse solo le chiamate del
 * setup che precedono la presa di possesso (ledger, utenti estranei, rivendica):
 * un caso lanciato senza setup (UI mode, processo senza ambiente) non scrive.
 */
export const corsaPerSql = (corsa: string | undefined, primaDelPossesso: boolean): string => {
  if (primaDelPossesso) return "";
  if (!corsa) throw new IsolamentoNonProvato("nessuna corsa possiede lo stack: SQL fuori dal setup rifiutato");
  return corsa;
};

/**
 * Antepone a ogni SQL della suite la verifica del marcatore, nella stessa
 * sessione psql (ON_ERROR_STOP): se il database non è lo stack dedicato di
 * questa copia di lavoro, o la corsa non lo possiede più, nessuna istruzione
 * successiva parte. Le variabili psql non si espandono dentro `$$`, quindi i
 * valori passano per due impostazioni di sessione.
 */
export const sqlProtetto = (
  sql: string,
  variabili: Record<string, string>,
  possesso: { nonce: string; corsa: string },
): string => {
  if (!NONCE.test(possesso.nonce)) throw new IsolamentoNonProvato("nonce dello stack non valido");
  if (possesso.corsa !== "" && !NONCE.test(possesso.corsa)) throw new IsolamentoNonProvato("token di corsa non valido");
  const tutte = { ...variabili, e2e_nonce: possesso.nonce, e2e_corsa: possesso.corsa };
  const intestazione = Object.entries(tutte)
    .map(([nome, valore]) => {
      if (!/^[A-Za-z0-9_]+$/.test(nome) || !/^[A-Za-z0-9_.-]*$/.test(valore)) {
        throw new Error("Variabile psql non ammessa.");
      }
      return `\\set ${nome} '${valore}'`;
    })
    .join("\n");
  return `${intestazione}
set vinea_e2e.nonce = :'e2e_nonce';
set vinea_e2e.corsa = :'e2e_corsa';
do $guardia$
begin
  if to_regclass('vinea_e2e.identita') is null then
    raise exception 'ISOLAMENTO NON PROVATO: il database non porta il marcatore dello stack E2E dedicato';
  end if;
  if not exists (select 1 from vinea_e2e.identita where nonce = current_setting('vinea_e2e.nonce')) then
    raise exception 'ISOLAMENTO NON PROVATO: il marcatore dello stack non appartiene a questa copia di lavoro';
  end if;
  if current_setting('vinea_e2e.corsa') <> ''
     and not exists (select 1 from vinea_e2e.identita where corsa = current_setting('vinea_e2e.corsa')) then
    raise exception 'ISOLAMENTO NON PROVATO: questa corsa non possiede più lo stack';
  end if;
end
$guardia$;
${sql}`;
};

/** Marcatore scritto da `e2e:stack up` su uno stack appena creato (`create schema` senza `if not exists`). */
export const SQL_MARCATORE = `create schema vinea_e2e;
revoke all on schema vinea_e2e from public;
create table vinea_e2e.identita (
  unico boolean primary key default true check (unico),
  nonce text not null,
  corsa text,
  creato_il timestamptz not null default now()
);
revoke all on vinea_e2e.identita from public;
insert into vinea_e2e.identita (nonce) values (:'e2e_nonce');`;

/** `up` parte solo se non esiste alcuna risorsa Docker del progetto riservato (I10). */
export const decidiUp = (risorseEsistenti: readonly string[]): void => {
  if (risorseEsistenti.length > 0) {
    throw new IsolamentoNonProvato(
      `esistono già risorse Docker del progetto \`${PROJECT_ID_E2E}\` (${risorseEsistenti.join(", ")}): ` +
        "appartengono a un'altra sessione o a uno stack non chiuso; non vengono toccate",
    );
  }
};

/**
 * `down` distrugge (`stop --no-backup`) solo il progetto riservato, e solo se il
 * container porta l'etichetta del progetto e il marcatore nel database è quello
 * del file di identità di questa copia di lavoro. Ritorna gli argomenti della CLI.
 */
export const decidiDown = (stato: {
  conferma: boolean;
  identita: IdentitaStack | null;
  etichettaContainer: string | null;
  nonceNelDatabase: string | null;
}): string[] => {
  if (!stato.conferma) {
    throw new IsolamentoNonProvato("`down` distrugge lo stack E2E dedicato: rilanciare con --conferma");
  }
  if (!stato.identita) {
    throw new IsolamentoNonProvato("nessuno stack E2E creato da questa copia di lavoro: niente da distruggere");
  }
  if (stato.etichettaContainer !== PROJECT_ID_E2E) {
    throw new IsolamentoNonProvato(`il container \`${CONTAINER_DB_E2E}\` non è in esecuzione o non è del progetto E2E`);
  }
  if (stato.nonceNelDatabase !== stato.identita.nonce) {
    throw new IsolamentoNonProvato("il marcatore nel database non è quello di questa copia di lavoro");
  }
  return ["stop", "--no-backup", "--project-id", PROJECT_ID_E2E];
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
