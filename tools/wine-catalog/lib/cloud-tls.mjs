// TLS della connessione cloud (WI-001C-FIX-01 / I-1). Funzioni pure, indipendenti da Bun: provabili senza rete.
//
// Comportamento VERIFICATO su Bun 1.3.14 contro un server TLS isolato (test/tls-bun.test.mjs):
//  - `tls: { ca, rejectUnauthorized: true }` con `sslmode=verify-full` nell'URL: CA e hostname sono verificati;
//    CA errata → UNABLE_TO_VERIFY_LEAF_SIGNATURE; hostname errato → rifiuto (con messaggio vuoto: lo normalizziamo qui);
//    server che risponde «N» alla richiesta SSL → nessuna connessione (scade il timeout);
//  - `sslmode=require` nell'URL ABBASSA la verifica (accetta un hostname errato) e `sslmode=disable` apre una sessione in chiaro:
//    per questo l'URL deve contenere ESATTAMENTE un `sslmode=verify-full` e il chiamante non può scegliere altro.

const PEM_CERT = /-----BEGIN CERTIFICATE-----[A-Za-z0-9+/=\s]+-----END CERTIFICATE-----/g;
const MAX_PEM_BYTES = 64 * 1024;

/**
 * Valida la catena CA (PEM) con cui verificare il server. Una o più firme certificato, nessuna chiave privata, dimensione limitata.
 * Restituisce il PEM normalizzato (solo i blocchi CERTIFICATE).
 */
export function normalizeCaPem(pem) {
  const text = String(pem ?? '');
  if (text.length === 0) throw new Error('CA mancante: la verifica TLS richiede la CA del progetto (CATALOG_DB_CA_PEM o --ca-file).');
  if (text.length > MAX_PEM_BYTES) throw new Error('CA troppo grande (massimo 64 KB): file non valido.');
  if (/PRIVATE KEY/.test(text)) throw new Error('Il file della CA contiene una chiave privata: rifiutato (serve solo il certificato pubblico).');
  const blocks = text.match(PEM_CERT);
  if (!blocks || blocks.length === 0) throw new Error('CA non valida: nessun blocco CERTIFICATE in formato PEM.');
  if (blocks.length > 10) throw new Error('CA non valida: troppi certificati (massimo 10).');
  return `${blocks.map((b) => b.trim()).join('\n')}\n`;
}

/**
 * Sorgente della CA: variabile d'ambiente (preferita: nessun file su disco) oppure file. Entrambe → rifiuto (ambiguità).
 * `readFile` è iniettato (test senza file system).
 */
export function loadCaPem({ caFile = null, envPem = null, readFile }) {
  if (caFile && envPem) throw new Error('CA indicata sia con --ca-file sia con CATALOG_DB_CA_PEM: usarne una sola.');
  if (!caFile && !envPem) throw new Error('CA mancante: impostare CATALOG_DB_CA_PEM (preferito) oppure --ca-file <ca.pem>. Il TLS non verificato è rifiutato.');
  return normalizeCaPem(caFile ? readFile(caFile) : envPem);
}

/**
 * L'URL deve avere un solo `sslmode` e deve essere `verify-full`. Qualunque altro valore (disable, allow, prefer, require, verify-ca)
 * o parametro ripetuto è rifiutato PRIMA di aprire un socket.
 */
export function assertVerifiedTlsUrl(url) {
  let parsed;
  try {
    parsed = new URL(String(url));
  } catch {
    throw new Error('URL del database non valida.');
  }
  if (parsed.hash) throw new Error('URL con frammento (#) non ammessa.');
  const keys = [...parsed.searchParams.keys()].map((k) => k.toLowerCase());
  const sslKeys = keys.filter((k) => k === 'sslmode');
  if (sslKeys.length !== 1 || String([...parsed.searchParams].find(([k]) => k.toLowerCase() === 'sslmode')?.[1] ?? '').toLowerCase() !== 'verify-full') {
    throw new Error('TLS verificato obbligatorio: un solo sslmode, e deve essere verify-full (disable/allow/prefer/require/verify-ca sono rifiutati).');
  }
  const allowed = new Set(['sslmode', 'application_name', 'connect_timeout']);
  const stray = keys.filter((k) => !allowed.has(k));
  if (stray.length > 0) {
    throw new Error(`Parametri di connessione nell'URL non ammessi (${stray.slice(0, 3).join(', ')}): la CA si passa solo con CATALOG_DB_CA_PEM o --ca-file.`);
  }
  const modes = [...String(url).matchAll(/[?&]sslmode=([^&#]*)/gi)].map((m) => m[1].toLowerCase());
  if (modes.length !== 1 || modes[0] !== 'verify-full') {
    throw new Error('TLS verificato obbligatorio: un solo sslmode, e deve essere verify-full (disable/allow/prefer/require/verify-ca sono rifiutati).');
  }
  if (/[?&](ssl|sslrootcert|sslcert|sslkey|tls)=/i.test(String(url))) {
    throw new Error('Parametri TLS nell\x27URL non ammessi: la CA si passa solo con CATALOG_DB_CA_PEM o --ca-file.');
  }
}

/** Opzioni TLS per Bun.SQL: sempre verifica della catena e dell'hostname, mai `rejectUnauthorized: false`. */
export function tlsOptions(caPem) {
  return { ca: normalizeCaPem(caPem), rejectUnauthorized: true };
}

const TLS_CODES = new Set([
  'UNABLE_TO_VERIFY_LEAF_SIGNATURE', 'SELF_SIGNED_CERT_IN_CHAIN', 'DEPTH_ZERO_SELF_SIGNED_CERT', 'CERT_HAS_EXPIRED',
  'ERR_TLS_CERT_ALTNAME_INVALID', 'UNABLE_TO_GET_ISSUER_CERT_LOCALLY', 'CERT_NOT_YET_VALID', 'HOSTNAME_MISMATCH',
]);

/** Messaggio d'errore di connessione leggibile e senza segreti (Bun restituisce a volte un messaggio vuoto per l'hostname errato). */
export function describeConnectError(err, redactor = (s) => s) {
  const code = String(err?.code ?? '');
  const msg = redactor(String(err?.message ?? '').trim());
  if (TLS_CODES.has(code) || (!msg && !code)) {
    return `Connessione cloud rifiutata: verifica TLS fallita (CA, certificato o hostname non accettati)${code ? ` [${code}]` : ''}.`;
  }
  if (code === 'ERR_POSTGRES_CONNECTION_TIMEOUT') {
    return 'Connessione cloud rifiutata: timeout (il server non accetta TLS, non risponde o non è raggiungibile).';
  }
  return `Connessione cloud rifiutata${code ? ` [${code}]` : ''}: ${msg || 'errore sconosciuto'}`.slice(0, 300);
}

/** Vero se l'errore indica che la connessione è caduta (la sessione non è più quella verificata). */
export function isConnectionLost(err) {
  const code = String(err?.code ?? '');
  return code === 'ERR_POSTGRES_CONNECTION_CLOSED' || code === 'ERR_POSTGRES_CONNECTION_TIMEOUT'
    || code === 'ERR_POSTGRES_IDLE_TIMEOUT' || code === 'ERR_POSTGRES_LIFETIME_TIMEOUT' || /^57P0[123]$/.test(code)
    || /connection (closed|terminated)|socket|ECONNRESET|EPIPE/i.test(String(err?.message ?? ''));
}
