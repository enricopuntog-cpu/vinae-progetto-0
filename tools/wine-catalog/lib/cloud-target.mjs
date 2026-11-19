// Destinazione cloud del caricatore (WI-001C). DISABILITATA di default.
//
// Questo modulo NON apre connessioni: valida soltanto l'identità della destinazione e le autorizzazioni, prima
// che qualunque connessione venga tentata. Le protezioni loopback di WI-001B (`paths.mjs`) restano intatte e sono
// l'unico percorso usato senza `--cloud`.
//
// Un'importazione cloud richiede TUTTE queste condizioni insieme:
//   1. `--cloud` sulla riga di comando;
//   2. variabile d'ambiente CATALOG_CLOUD_IMPORT=enabled (interruttore esplicito, mai impostato da default);
//   3. `--target-ref <ref>` uguale al ref di progetto contenuto nell'host della URL (identificazione della destinazione);
//   4. host ammesso: SOLO `db.<ref>.supabase.co` (connessione diretta) o `aws-<n>-<regione>.pooler.supabase.com`
//      con utente `<ruolo>.<ref>` (pooler in modalità sessione, porta 5432). Nessun altro host cloud;
//   5. TLS verificato: `sslmode=verify-full` (la CA si passa con --ca-file);
//   6. la URL arriva da CATALOG_DATABASE_URL (mai da riga di comando: resterebbe nella cronologia e nell'elenco dei processi);
//   7. il ref di Production è rifiutato salvo approvazione esplicita:
//      `--allow-production` + CATALOG_PRODUCTION_APPROVAL=approved:<ref>:<riferimento-approvazione>.
//      Oggi NESSUNA approvazione esiste: non impostarla senza una decisione scritta del founder.
//
// La pooler in modalità transazione (porta 6543) è rifiutata: lo stato di sessione (ruolo, timeout) e gli advisory
// lock del protocollo di import non sono garantiti.

export const PRODUCTION_REF = 'pijnmcllmfgjmgsvtcej';
export const CLOUD_ENABLE_ENV = 'CATALOG_CLOUD_IMPORT';
export const CLOUD_ENABLE_VALUE = 'enabled';
export const PRODUCTION_APPROVAL_ENV = 'CATALOG_PRODUCTION_APPROVAL';

const REF_RE = /^[a-z0-9]{20}$/;
const DIRECT_HOST_RE = /^db\.([a-z0-9]{20})\.supabase\.co$/;
const POOLER_HOST_RE = /^aws-[0-9]{1,2}-[a-z0-9-]{3,30}\.pooler\.supabase\.com$/;
const ALLOWED_QUERY = new Set(['sslmode', 'application_name', 'connect_timeout']);

/**
 * Analizza la URL e ne ricava l'identità della destinazione. Lancia se la URL non è una destinazione Supabase
 * ammessa. Non restituisce mai la password.
 */
export function parseCloudUrl(url) {
  let u;
  try {
    u = new URL(url);
  } catch {
    throw new Error('URL del database non valida.');
  }
  if (!/^postgres(ql)?:$/.test(u.protocol)) throw new Error('L\x27URL del database deve usare lo schema postgres://.');
  const authority = String(url).replace(/^[a-z]+:\/\//i, '').split(/[/?#]/)[0].split('@').pop();
  if (authority.includes(',')) throw new Error('URL con più host: non ammesso.');
  const host = u.hostname.toLowerCase();
  const port = u.port ? Number(u.port) : 5432;
  if (port === 6543) throw new Error('Porta 6543 (pooler in modalità transazione) non ammessa: serve una sessione dedicata (5432).');
  if (port !== 5432) throw new Error(`Porta ${port} non ammessa (solo 5432).`);
  const seenKeys = new Set();
  for (const key of u.searchParams.keys()) {
    const k = key.toLowerCase();
    if (!ALLOWED_QUERY.has(k)) throw new Error(`Parametro di connessione "${key}" non ammesso (allowlist: ${[...ALLOWED_QUERY].join(', ')}).`);
    // un parametro ripetito (es. sslmode=verify-full&sslmode=disable) potrebbe essere letto diversamente dal client
    if (seenKeys.has(k)) throw new Error(`Parametro di connessione "${key}" ripetuto: non ammesso.`);
    seenKeys.add(k);
  }
  const sslmode = (u.searchParams.get('sslmode') ?? '').toLowerCase();
  if (sslmode !== 'verify-full') throw new Error('TLS verificato obbligatorio: la URL deve avere sslmode=verify-full.');

  let kind;
  let ref;
  const direct = DIRECT_HOST_RE.exec(host);
  if (direct) {
    kind = 'direct';
    ref = direct[1];
  } else if (POOLER_HOST_RE.test(host)) {
    kind = 'pooler';
    const user = decodeURIComponent(u.username);
    const m = /^[a-z_][a-z0-9_]*\.([a-z0-9]{20})$/.exec(user);
    if (!m) throw new Error('Pooler: l\x27utente deve avere la forma <ruolo>.<ref-progetto>.');
    ref = m[1];
  } else {
    throw new Error(`Host "${host}" non ammesso: solo db.<ref>.supabase.co o un pooler Supabase in modalità sessione.`);
  }
  if (!REF_RE.test(ref)) throw new Error('Ref di progetto non valido.');
  const database = u.pathname.replace(/^\//, '') || 'postgres';
  if (!/^[A-Za-z0-9_]{1,63}$/.test(database)) throw new Error('Nome del database non valido.');
  return { kind, host, port, ref, database, user: decodeURIComponent(u.username), production: ref === PRODUCTION_REF };
}

/** URL con la password mascherata, adatta ai log e ai report. */
export function redactUrl(url) {
  try {
    const u = new URL(url);
    if (u.password) u.password = '***';
    return u.toString();
  } catch {
    return '[url non valida]';
  }
}

/**
 * Tutte le condizioni di autorizzazione all'import cloud. `env` e `flags` sono passati esplicitamente
 * (testabili senza toccare process.env). Restituisce la destinazione identificata; lancia al primo requisito mancante.
 */
export function assertCloudAuthorized({ url, env = {}, flags = {} }) {
  if (!flags.cloud) throw new Error('Importazione cloud non richiesta: manca --cloud.');
  if (env[CLOUD_ENABLE_ENV] !== CLOUD_ENABLE_VALUE) {
    throw new Error(`Importazione cloud DISABILITATA: serve ${CLOUD_ENABLE_ENV}=${CLOUD_ENABLE_VALUE} nell'ambiente del processo.`);
  }
  if (flags.databaseUrlOnCommandLine) {
    throw new Error('In modalità cloud la URL del database non si passa con --database-url: usare CATALOG_DATABASE_URL.');
  }
  if (!url) throw new Error('Manca CATALOG_DATABASE_URL.');
  if (!flags.targetRef) throw new Error('Manca --target-ref <ref>: la destinazione va identificata esplicitamente.');
  if (!REF_RE.test(flags.targetRef)) throw new Error('--target-ref non è un ref di progetto Supabase valido (20 caratteri [a-z0-9]).');
  const target = parseCloudUrl(url);
  if (target.ref !== flags.targetRef) {
    throw new Error('Il ref dell\x27URL non coincide con --target-ref: destinazione non confermata.');
  }
  if (target.production) {
    const approval = env[PRODUCTION_APPROVAL_ENV] ?? '';
    const ok = new RegExp(`^approved:${target.ref}:[A-Za-z0-9._-]{4,64}$`).test(approval);
    if (!flags.allowProduction || !ok) {
      throw new Error('Destinazione Production rifiutata: serve --allow-production e CATALOG_PRODUCTION_APPROVAL=approved:<ref>:<riferimento> (nessuna approvazione esiste oggi).');
    }
  } else if (flags.allowProduction) {
    throw new Error('--allow-production con una destinazione che non è Production: richiesta incoerente.');
  }
  return target;
}

export const CLOUD_DEFAULTS = Object.freeze({
  batchSize: 1000,
  maxBatchSize: 5000,
  maxWalMb: 3000,
  batchTimeoutSec: 120,
  finishTimeoutMin: 30,
  lockTimeoutSec: 30,
  idleTxTimeoutSec: 60,
});

/** Limiti di risorse della sessione cloud, validati (interi positivi entro intervalli sensati). */
export function resolveCloudLimits(raw = {}) {
  const num = (name, v, def, min, max) => {
    if (v === undefined || v === null || v === '') return def;
    const n = Number(v);
    if (!Number.isInteger(n) || n < min || n > max) throw new Error(`${name} deve essere un intero tra ${min} e ${max}.`);
    return n;
  };
  return {
    batchSize: num('--batch-size', raw.batchSize, CLOUD_DEFAULTS.batchSize, 1, CLOUD_DEFAULTS.maxBatchSize),
    maxWalMb: num('--max-wal-mb', raw.maxWalMb, CLOUD_DEFAULTS.maxWalMb, 50, 50000),
    batchTimeoutSec: num('--batch-timeout-sec', raw.batchTimeoutSec, CLOUD_DEFAULTS.batchTimeoutSec, 5, 900),
    finishTimeoutMin: num('--finish-timeout-min', raw.finishTimeoutMin, CLOUD_DEFAULTS.finishTimeoutMin, 1, 120),
    lockTimeoutSec: CLOUD_DEFAULTS.lockTimeoutSec,
    idleTxTimeoutSec: CLOUD_DEFAULTS.idleTxTimeoutSec,
  };
}
