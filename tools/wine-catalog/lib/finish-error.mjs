// Classificazione CONSERVATIVA di un errore di `finish_import_run` (WI-001C-FIX-03 / R2). Funzioni pure, provabili senza rete.
//
// Il finish è UNA transazione di promozione. Un errore lato client NON prova che sia stata annullata: la connessione può cadere mentre
// il server conferma, il driver può non riuscire a decodificare una risposta di successo, una scadenza JavaScript non ferma la query.
// Si dichiara «fallito» (rollback noto) SOLO quando il server stesso ha risposto con un errore dotato di SQLSTATE affidabile, la
// sessione è ancora integra e la classe dell'errore non è tra quelle che coinvolgono la connessione o il server in sé.
// Ogni altro caso è «sconosciuto»: nessun `fail_import_run` (cancellerebbe finding e staging di un run forse già `succeeded`: la
// funzione della migration WI-001B cancella i finding a prescindere dallo stato terminale), nessun rollback dichiarato, nessuna ripetizione.
import { isConnectionLost } from './cloud-tls.mjs';

// SQLSTATE: 5 caratteri [0-9A-Z] con almeno una cifra (esclude codici di sistema come `EPIPE`, `ENOENT`).
const SQLSTATE_RE = /^(?!E)(?=.*\d)[0-9A-Z]{5}$/;
// Classi/codici che NON provano un rollback pur arrivando con uno SQLSTATE:
//  08xxx connessione; 57P01-05 arresto/crash/«non posso connettermi»/database eliminato/sessione inattiva (la sessione muore: il
//  backend può aver confermato prima di cadere); 58xxx errore di sistema (I/O); XXxxx errore interno.
//  40003 statement_completion_unknown (per definizione: esito non noto); 25P03 idle_in_transaction_session_timeout (FATAL).
const UNCERTAIN_SQLSTATE = [/^08/, /^57P0[1-5]$/, /^58/, /^XX/, /^40003$/, /^25P03$/];

/**
 * SQLSTATE dell'errore SOLO se proviene in modo affidabile dal server:
 *  - `sqlState`/`sqlstate` (driver in stile node-postgres);
 *  - Bun.SQL: `errno` quando `code === 'ERR_POSTGRES_SERVER_ERROR'` (errore di protocollo restituito dal server);
 *  - `code` già nella forma di uno SQLSTATE e senza `syscall` (gli errori di sistema Node hanno `syscall`).
 * Un errore senza SQLSTATE affidabile (rete, driver, decodifica, non PostgreSQL) restituisce null.
 */
export function extractSqlState(e) {
  if (!e || typeof e !== 'object') return null;
  if (e.syscall) return null;
  const candidates = [e.sqlState, e.sqlstate, e.code === 'ERR_POSTGRES_SERVER_ERROR' ? e.errno : null, e.code];
  for (const c of candidates) {
    if (typeof c === 'string' && SQLSTATE_RE.test(c)) return c;
  }
  return null;
}

/**
 * Esito della classificazione: `{ status: 'failed' | 'unknown', sqlstate, reason }`.
 *  cloud: la sessione è quella riservata cloud (`db.state` esiste). In locale (database di prova, nessun login dedicato) vale la regola
 *         storica: un errore del finish è «fallito».
 *  sessionBroken: la sessione è già marcata interrotta (connessione caduta o scadenza JavaScript).
 * `57014` (query_canceled) copre sia `statement_timeout` sia `pg_cancel_backend` di CHIUNQUE (monitor, amministratore, pooler): se è
 * un errore restituito dal server su una sessione integra, l'istruzione è stata interrotta e la transazione annullata; NON se ne deduce
 * chi l'abbia richiesta (lo decide `finalizeWal`: «annullato dal monitor» solo se il monitor ha una richiesta riuscita).
 */
export function classifyFinishError(e, { cloud = true, sessionBroken = false } = {}) {
  const sqlstate = extractSqlState(e);
  if (!cloud) return { status: 'failed', sqlstate, reason: 'local_session' };
  if (e && typeof e === 'object' && e.code === 'WI_DEADLINE') return { status: 'unknown', sqlstate: null, reason: 'deadline_expired' };
  if (sessionBroken) return { status: 'unknown', sqlstate, reason: 'session_broken' };
  if (!sqlstate) return { status: 'unknown', sqlstate: null, reason: isConnectionLost(e) ? 'connection_lost' : 'no_reliable_sqlstate' };
  // severità FATAL/PANIC: la sessione o il server sono terminati dall'errore, l'esito non si deduce dal solo SQLSTATE
  if (/^(FATAL|PANIC)$/i.test(String(e?.severity ?? e?.severityLocal ?? ''))) return { status: 'unknown', sqlstate, reason: 'fatal_severity' };
  if (UNCERTAIN_SQLSTATE.some((re) => re.test(sqlstate))) return { status: 'unknown', sqlstate, reason: 'sqlstate_connection_or_server_class' };
  return { status: 'failed', sqlstate, reason: sqlstate === '57014' ? 'query_canceled_server_reported' : 'server_error_reported' };
}
