// Certificati di PROVA generati al volo con `openssl` (nessun certificato né chiave committati). Validi 2 giorni, solo per i test TLS.
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export function opensslAvailable() {
  const r = spawnSync('openssl', ['version'], { encoding: 'utf8' });
  return r.status === 0;
}

function run(args, cwd) {
  const r = spawnSync('openssl', args, { cwd, encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`openssl ${args[0]} fallito: ${r.stderr}`);
}

/**
 * Crea due CA (`ca`, `otherCa`) e due certificati server firmati da `ca`:
 *  - `good`: SAN = localhost e 127.0.0.1
 *  - `wrongName`: SAN = altro.example.com (hostname errato per localhost)
 */
export function makeTlsFixtures() {
  const dir = mkdtempSync(join(tmpdir(), 'wi001c-tls-'));
  const mkCa = (name) => run(['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', `${name}.key`, '-out', `${name}.pem`,
    '-days', '2', '-subj', `/CN=${name}`, '-addext', 'basicConstraints=critical,CA:TRUE'], dir);
  mkCa('ca');
  mkCa('otherca');
  const mkServer = (name, san) => {
    run(['req', '-newkey', 'rsa:2048', '-nodes', '-keyout', `${name}.key`, '-out', `${name}.csr`, '-subj', `/CN=${name}`], dir);
    writeFileSync(join(dir, `${name}.ext`), `subjectAltName=${san}\n`);
    run(['x509', '-req', '-in', `${name}.csr`, '-CA', 'ca.pem', '-CAkey', 'ca.key', '-CAcreateserial', '-out', `${name}.pem`, '-days', '2', '-extfile', `${name}.ext`], dir);
  };
  mkServer('good', 'DNS:localhost,IP:127.0.0.1');
  mkServer('wrongname', 'DNS:altro.example.com');
  const rd = (f) => readFileSync(join(dir, f), 'utf8');
  return {
    ca: rd('ca.pem'), otherCa: rd('otherca.pem'),
    good: { cert: rd('good.pem'), key: rd('good.key') },
    wrongName: { cert: rd('wrongname.pem'), key: rd('wrongname.key') },
    dispose: () => rmSync(dir, { recursive: true, force: true }),
  };
}
