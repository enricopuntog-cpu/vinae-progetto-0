// Guardie sui percorsi condivise dagli strumenti da riga di comando del catalogo:
// gli output (report, snapshot) non devono mai finire dentro il repository.
import { realpathSync, existsSync } from 'node:fs';
import { resolve, relative, isAbsolute, dirname, basename, join, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

export const REPO_ROOT = realpathSync(resolve(dirname(fileURLToPath(import.meta.url)), '..', '..', '..'));

/** Percorso canonico anche se il file non esiste: realpath del primo antenato esistente + resto. */
export function canonical(p) {
  let cur = resolve(p);
  const rest = [];
  while (!existsSync(cur)) {
    rest.unshift(basename(cur));
    const up = dirname(cur);
    if (up === cur) break;
    cur = up;
  }
  return join(realpathSync(cur), ...rest);
}

export function insideRepo(p) {
  const rel = relative(REPO_ROOT, canonical(p));
  if (rel === '') return true;
  const escapes = rel === '..' || rel.startsWith('..' + sep) || isAbsolute(rel);
  return !escapes;
}

// Allowlist restrittiva dei parametri di connessione ammessi nell'URL (tutto il resto è rifiutato: `host`, `hostaddr`,
// `service`, `options`, `port` ripetuti, socket, ecc. potrebbero reindirizzare la connessione altrove).
const ALLOWED_QUERY = new Set(['sslmode', 'application_name', 'connect_timeout']);
const LOOPBACK = new Set(['localhost', '127.0.0.1', '[::1]']);

/**
 * Solo database locali (loopback), senza override. Verifica la struttura dell'URL, non una sottostringa:
 *  - schema postgres:// o postgresql://;
 *  - UN solo host, esattamente localhost / 127.0.0.1 / [::1] (niente socket o host vuoto, niente elenchi «a,b»,
 *    niente varianti numeriche 127.1 / 2130706433, niente 127.0.0.1.evil.com, niente `@` ingannevoli);
 *  - nessun parametro di query diverso da sslmode / application_name / connect_timeout (quindi niente `host=`).
 */
export function assertLocalDatabaseUrl(url) {
  let u;
  try {
    u = new URL(url);
  } catch {
    throw new Error('URL del database non valido.');
  }
  if (!/^postgres(ql)?:$/.test(u.protocol)) throw new Error('L\x27URL del database deve usare lo schema postgres://.');
  if (!u.hostname) throw new Error('URL senza host: i socket e le connessioni implicite non sono ammessi.');
  if (!LOOPBACK.has(u.hostname)) {
    throw new Error(`Rifiuto di collegarmi a "${u.hostname}": WI-001B consente solo database locali (loopback: localhost, 127.0.0.1, [::1]).`);
  }
  // l'host è stato letto da WHATWG URL; si controlla anche la stringa grezza per elenchi di host (`a,b`) tra @ e / o :
  const authority = String(url).replace(/^[a-z]+:\/\//i, '').split(/[/?#]/)[0].split('@').pop();
  if (authority.includes(',')) throw new Error('URL con più host: non ammesso.');
  // anche l'host «grezzo» (senza porta) deve essere esattamente loopback: il risultato non dipende da come un altro parser normalizza l'URL
  const rawHost = authority.startsWith('[') ? authority.slice(0, authority.indexOf(']') + 1) : authority.split(':')[0];
  if (!LOOPBACK.has(rawHost.toLowerCase())) throw new Error(`Host "${rawHost}" non ammesso (solo localhost, 127.0.0.1, [::1] scritti esattamente così).`);
  for (const key of u.searchParams.keys()) {
    if (!ALLOWED_QUERY.has(key.toLowerCase())) throw new Error(`Parametro di connessione "${key}" non ammesso (allowlist: ${[...ALLOWED_QUERY].join(', ')}).`);
  }
  return u;
}
