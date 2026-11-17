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

/** Solo database locali: loopback. Nessun override. */
export function assertLocalDatabaseUrl(url) {
  let u;
  try {
    u = new URL(url);
  } catch {
    throw new Error('URL del database non valido.');
  }
  if (!/^postgres(ql)?:$/.test(u.protocol)) throw new Error('L\'URL del database deve usare lo schema postgres://.');
  const host = u.hostname.replace(/^\[|\]$/g, '');
  if (!['localhost', '127.0.0.1', '::1'].includes(host)) {
    throw new Error(`Rifiuto di collegarmi a "${host}": WI-001B consente solo database locali (loopback).`);
  }
  return u;
}
