// Adattatore verso PostgreSQL con il client integrato di Bun (nessuna dipendenza da installare).
// Una sola connessione. Il ruolo `catalog_loader` NON si imposta con un `set role` dopo la connessione (andrebbe perso se
// il client si ricollega): lo si passa come parametro di AVVIO della sessione, quindi vale per ogni connessione che il
// client apre. In più `assertRole()` verifica il ruolo effettivo prima di ogni operazione privilegiata.
import { assertLocalDatabaseUrl } from './paths.mjs';
import { assertEffectiveRole } from './role-check.mjs';
import { assertVerifiedTlsUrl, tlsOptions, describeConnectError, isConnectionLost } from './cloud-tls.mjs';
import { MONITOR_SQL_ALLOWED, SESSION_LIMITS_SQL } from './cloud-guards.mjs';
import { sanitizeSqlForFilter } from './sql-scan.mjs';

export async function connectLocal(url, { role = 'catalog_loader' } = {}) {
  assertLocalDatabaseUrl(url);
  if (typeof Bun === 'undefined' || typeof Bun.SQL !== 'function') {
    throw new Error('Il caricatore usa il client PostgreSQL integrato di Bun: eseguire con `bun tools/wine-catalog/lwin-load.mjs`.');
  }
  if (!role || !/^[a-z_][a-z0-9_]*$/.test(role)) throw new Error('Ruolo mancante o non valido: il caricatore non opera mai con il ruolo di connessione.');
  const sql = new Bun.SQL({ url, max: 1, connection: { role } });
  const db = {
    async query(text, params = []) {
      const rows = await sql.unsafe(text, params);
      return { rows: Array.from(rows) };
    },
    async close() {
      await sql.close();
    },
    /** Verifica il ruolo EFFETTIVO della sessione corrente (da chiamare prima di ogni operazione privilegiata). */
    async assertRole() {
      await assertEffectiveRole((t, p) => db.query(t, p), role);
    },
  };
  await db.assertRole();
  return db;
}

// ---------------------------------------------------------------------------------------------------------------------
// Connessione CLOUD (WI-001C / FIX-01). Usare SOLO dopo `assertCloudAuthorized` (cloud-target.mjs): la funzione non ripete la
// validazione dell'identità della destinazione, ma impone TLS verificato (CA obbligatoria, hostname verificato) e una sessione
// che NON si riapre da sola.
//
// Verificato su Bun 1.3.14 (test/tls-bun.test.mjs, server TLS isolato):
//  - `Bun.SQL` si ricollega IN SILENZIO se il socket cade: la nuova sessione ha perso ruolo, timeout e ogni stato → qui si usa una
//    connessione RISERVATA (`reserve()`), che dopo una caduta fallisce invece di ricollegarsi; in più ogni errore di connessione
//    marca la sessione come interrotta e le richieste successive sono rifiutate;
//  - il ruolo `catalog_loader` si imposta con `SET ROLE` esplicito sulla connessione riservata (non come parametro di avvio: il
//    pooler Supavisor non garantisce di inoltrarlo) e si riverifica con `assertRole()`; il login è verificato da
//    `assertCloudSession`: dal login è raggiungibile SOLO catalog_loader, quindi `RESET ROLE` non porta a privilegi maggiori.
// ---------------------------------------------------------------------------------------------------------------------
// CONFINE DI FIDUCIA (WI-001C-FIX-02). Tre livelli, nessuno basato SOLO su espressioni regolari:
//  1. `raw()` = SQL interno fidato (SET ROLE, impostazioni iniziali, `setLimits`): testi costanti scritti in questo file o in
//     cloud-guards.mjs, mai costruiti con input esterno; non è raggiungibile dall'API `query()`.
//  2. monitor: ELENCO CHIUSO di testi esatti (MONITOR_SQL_ALLOWED): qualunque altro testo è rifiutato, senza interpretazione.
//  3. sessione del caricatore: il chiamante può inviare solo SELECT/WITH/VALUES in un solo statement, senza DML diretto e senza
//     `set_config` (i timeout si impostano solo con `setLimits`). Questi filtri sono DIFESA IN PROFONDITÀ: la barriera vera è il database
//     (login senza privilegi propri, ruolo `catalog_loader` con soli privilegi di import, audit transitivo in assertCloudSession).
// I filtri lavorano sul testo SENZA commenti (un commento vale come spazio: PostgreSQL accetta \`SET/**/ROLE\`).
const stripComments = (t) => String(t).replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/--[^\n]*(?:\n|$)/g, ' ');
const READ_ONLY_START = /^\s*(?:select|show|values|with)\b/i;
const DML_ANYWHERE = /\b(?:insert\b|update\b[^;]*\bset\b|delete\b|truncate\b|merge\b|into\b|copy\b|call\b|do\b)/i;
// Cambi di ruolo e controllo di transazione NON ammessi al chiamante: ovunque nel testo e con un solo statement (un \`;\` interno
// permetterebbe di accodare un RESET ROLE). \`set_config\` non è ammesso al chiamante (si usa \`setLimits\`). I nostri testi SQL non contengono mai \`;\`.
const ROLE_SWITCH = new RegExp([
  '\\breset\\s+(?:role|session\\s+authorization|all)\\b',
  '\\bset\\s+(?:local\\s+|session\\s+)?(?:role|session\\s+authorization)\\b',
  '\\bsession_authorization\\b',
  '\\b(?:default_)?transaction_read_only\\b',
  '\\bset_config\\b',
  '^\\s*(?:begin|start\\s+transaction|commit|rollback|end|abort|savepoint|release)\\b',
].join('|'), 'i');
const WRITE_START = /^\s*(?:select|with|values)\b/i;
const normalizeSql = (t) => String(t).trim().replace(/\s+/g, ' ');
const multiStatement = (text) => /;\s*\S/.test(String(text).replace(/'(?:[^']|'')*'/g, "''"));

/**
 * Filtro del testo SQL del CHIAMANTE sulla sessione cloud (livello 3 sopra). Lancia se il testo non è ammesso. Difesa in profondità: non è un
 * parser SQL e non sostituisce i privilegi del database. Esportata per le prove di regressione del filtro (nessuna connessione richiesta).
 */
export function assertCallerSql(text, { readOnly = false } = {}) {
  const clean = sanitizeSqlForFilter(text);
  if (ROLE_SWITCH.test(clean) || multiStatement(clean)) throw new Error('Cambio di ruolo, controllo di transazione o più istruzioni: non ammesso al chiamante.');
  if (readOnly && (!READ_ONLY_START.test(clean) || DML_ANYWHERE.test(clean))) throw new Error('Sessione di sola lettura: ammesse solo SELECT/SHOW/WITH.');
  // il chiamante legge e invoca le funzioni catalog.*; nessuna scrittura diretta (le scritture stanno nelle funzioni del database)
  if (!WRITE_START.test(clean) || DML_ANYWHERE.test(clean)) throw new Error('Istruzione non ammessa al chiamante: solo SELECT/WITH/VALUES senza scritture dirette.');
}

async function closeQuietly(fn, ms = 3000) {
  try {
    await Promise.race([Promise.resolve().then(fn), new Promise((r) => setTimeout(r, ms))]);
  } catch {
    // la connessione potrebbe essere già chiusa
  }
}

function wrapReserved({ sql, conn, redact, readOnly, allow = null }) {
  const state = { broken: false, why: null };
  const guard = () => {
    if (state.broken) throw new Error('Sessione cloud interrotta: la connessione è caduta e non viene riaperta (fail-closed).');
  };
  const db = {
    state,
    async query(text, params = []) {
      guard();
      if (allow) {
        // monitor: solo i testi esatti dell'elenco chiuso
        if (!allow.has(normalizeSql(text))) throw new Error('Istruzione non ammessa sulla connessione di monitoraggio.');
        return db.raw(text, params);
      }
      assertCallerSql(text, { readOnly });
      return db.raw(text, params);
    },
    /** Timeout di sessione: SQL interno fidato e costante (passato da cloud-guards), valori solo come parametri. */
    async setLimits(text, params) {
      if (normalizeSql(text) !== normalizeSql(SESSION_LIMITS_SQL)) throw new Error('setLimits accetta solo il testo costante dei timeout di sessione.');
      return db.raw(text, params);
    },
    async raw(text, params = []) {
      // uso interno (SET ROLE e impostazioni iniziali): salta i filtri del chiamante
      guard();
      try {
        const rows = await conn.unsafe(text, params);
        return { rows: Array.from(rows) };
      } catch (e) {
        if (isConnectionLost(e)) {
          state.broken = true;
          state.why = redact(String(e?.code ?? e?.message ?? 'connessione caduta'));
        }
        throw e;
      }
    },
    async close() {
      state.broken = true;
      await closeQuietly(() => conn.release());
      await closeQuietly(() => sql.close());
    },
  };
  // il monitor espone SOLO query/close/state: niente `raw` né `setLimits` (SQL arbitrario) a chi tiene l'oggetto
  if (allow) return { state, query: db.query, close: db.close };
  return db;
}

async function openReserved(url, { caPem, connectTimeoutSec, applicationName }) {
  assertVerifiedTlsUrl(url);
  const tls = tlsOptions(caPem);
  const redact = (s) => String(s).split(String(url)).join('[url]');
  const sql = new Bun.SQL({
    url, max: 1, tls, connectionTimeout: connectTimeoutSec, idleTimeout: 0, maxLifetime: 0,
    connection: { application_name: applicationName },
  });
  try {
    const conn = await sql.reserve();
    await conn.unsafe('select 1');
    return { sql, conn, redact };
  } catch (e) {
    await closeQuietly(() => sql.close());
    throw new Error(describeConnectError(e, redact));
  }
}

export async function connectCloud(url, { role = 'catalog_loader', caPem = null, connectTimeoutSec = 20, readOnly = false } = {}) {
  if (typeof Bun === 'undefined' || typeof Bun.SQL !== 'function') {
    throw new Error('Il caricatore usa il client PostgreSQL integrato di Bun: eseguire con `bun tools/wine-catalog/lwin-load.mjs`.');
  }
  if (!role || !/^[a-z_][a-z0-9_]*$/.test(role)) throw new Error('Ruolo mancante o non valido.');
  const { sql, conn, redact } = await openReserved(url, { caPem, connectTimeoutSec, applicationName: 'vinea-wi-catalog-import' });
  const db = wrapReserved({ sql, conn, redact, readOnly });
  try {
    await db.raw(`set role "${role}"`);
    if (readOnly) {
      // sola lettura per DEFAULT di sessione (ogni transazione implicita) + filtro SELECT-only lato client; il DB rifiuta le scritture (25006)
      await db.raw(`select set_config('default_transaction_read_only', 'on', false)`);
      const ro = (await db.raw(`select current_setting('transaction_read_only') as ro`)).rows[0];
      if (ro?.ro !== 'on') throw new Error('Sessione di sola lettura non attivata: importazione rifiutata.');
    }
    db.backendPid = Number((await db.raw('select pg_backend_pid() as pid')).rows[0].pid);
    db.readOnly = readOnly;
    db.assertRole = async () => { await assertEffectiveRole((t, p) => db.raw(t, p), role); };
    /** La sessione è ancora quella verificata: stesso backend, stesso ruolo, sola lettura se richiesta. Lancia altrimenti. */
    db.assertIntact = async () => {
      const r = (await db.raw(
        `select pg_backend_pid() as pid, current_user::text as cu, current_setting('transaction_read_only') as ro`,
      )).rows[0];
      if (Number(r.pid) !== db.backendPid) throw new Error('Sessione cloud cambiata (backend diverso): importazione interrotta.');
      if (r.cu !== role) throw new Error(`Ruolo di sessione cambiato (${r.cu}): importazione interrotta.`);
      if (readOnly && r.ro !== 'on') throw new Error('La sessione non è più di sola lettura: importazione interrotta.');
    };
    await db.assertRole();
  } catch (e) {
    await db.close();
    throw e;
  }
  return db;
}

/**
 * Connessione di MONITORAGGIO (stesso login, nessun SET ROLE): serve solo a leggere la posizione WAL e a chiamare
 * `pg_cancel_backend` sul backend dell'import. Resta il login (non `catalog_loader`) perché pg_cancel_backend è consentito a chi
 * ha i privilegi del ruolo di sessione del backend bersaglio, cioè il login. Non scrive nulla.
 */
export async function connectCloudMonitor(url, { caPem = null, connectTimeoutSec = 20 } = {}) {
  if (typeof Bun === 'undefined' || typeof Bun.SQL !== 'function') throw new Error('Serve Bun.');
  const { sql, conn, redact } = await openReserved(url, { caPem, connectTimeoutSec, applicationName: 'vinea-wi-catalog-monitor' });
  return wrapReserved({ sql, conn, redact, readOnly: false, allow: MONITOR_SQL_ALLOWED });
}
