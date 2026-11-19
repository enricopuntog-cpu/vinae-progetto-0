// Server PostgreSQL FINTO con TLS, solo per i test (WI-001C-FIX-01). Gira come processo Node separato (il TLS lato server di Node
// non è affidabile se il test gira dentro Bun). Parla il minimo del protocollo: richiesta SSL, startup, query semplici.
//
// Uso:  node mock-pg-server.mjs '<json config>'
//   config = { cert, key, allowTls, responses: [{ match: 'sottostringa', columns: [[nome, oid]], values: [..] }] }
// Stampa su stdout: {"port":N} all'avvio, poi ogni 150 ms {"log":{...}} (connessioni, richieste SSL, startup, query, esiti TLS).
// Una query contenente `drop_connection` fa cadere il socket (simula una connessione interrotta).
import net from 'node:net';
import tls from 'node:tls';

const cfg = JSON.parse(process.argv[2]);
const i32 = (n) => { const b = Buffer.alloc(4); b.writeInt32BE(n); return b; };
const i16 = (n) => { const b = Buffer.alloc(2); b.writeInt16BE(n); return b; };
const msg = (t, body = Buffer.alloc(0)) => Buffer.concat([Buffer.from(t), i32(body.length + 4), body]);
const log = { connections: 0, sslRequests: 0, tlsOk: 0, tlsErr: [], plainStartup: 0, startup: [], queries: [] };

function rowResult(r) {
  if (!r || !r.columns) return Buffer.concat([msg('C', Buffer.from('SELECT 0\0')), msg('Z', Buffer.from('I'))]);
  const desc = Buffer.concat([i16(r.columns.length), ...r.columns.map(([name, oid]) => Buffer.concat([
    Buffer.from(`${name}\0`), i32(0), i16(0), i32(oid), i16(-1), i32(-1), i16(0)]))]);
  const data = Buffer.concat([i16(r.values.length), ...r.values.map((v) => {
    if (v === null) return i32(-1);
    const b = Buffer.from(String(v));
    return Buffer.concat([i32(b.length), b]);
  })]);
  return Buffer.concat([msg('T', desc), msg('D', data), msg('C', Buffer.from('SELECT 1\0')), msg('Z', Buffer.from('I'))]);
}
const respond = (q) => (cfg.responses ?? []).find((r) => q.includes(r.match));

const server = net.createServer((raw) => {
  log.connections += 1;
  let stage = 'init';
  let buf = Buffer.alloc(0);
  let sock = raw;
  const onData = (d) => {
    buf = Buffer.concat([buf, d]);
    for (;;) {
      if (stage === 'init' || stage === 'startup') {
        if (buf.length < 8) return;
        const len = buf.readInt32BE(0);
        if (buf.length < len) return;
        const code = buf.readInt32BE(4);
        const body = buf.subarray(8, len);
        buf = buf.subarray(len);
        if (code === 80877103) {
          log.sslRequests += 1;
          if (cfg.allowTls === false) { sock.write('N'); stage = 'startup'; continue; }
          sock.write('S');
          const t = new tls.TLSSocket(raw, { isServer: true, cert: cfg.cert, key: cfg.key });
          t.on('secure', () => { log.tlsOk += 1; });
          t.on('error', (e) => log.tlsErr.push(e.code || e.message));
          raw.removeListener('data', onData);
          sock = t;
          t.on('data', onData);
          stage = 'startup';
          buf = Buffer.alloc(0);
          return;
        }
        const params = body.toString('utf8').split('\0').filter(Boolean);
        log.startup.push(params);
        if (!(sock instanceof tls.TLSSocket)) log.plainStartup += 1;
        sock.write(Buffer.concat([msg('R', i32(0)), msg('S', Buffer.from('server_version\x0016.0\x00')),
          msg('K', Buffer.concat([i32(1234), i32(5678)])), msg('Z', Buffer.from('I'))]));
        stage = 'ready';
        continue;
      }
      if (buf.length < 5) return;
      const t = String.fromCharCode(buf[0]);
      const len = buf.readInt32BE(1);
      if (buf.length < 1 + len) return;
      const body = buf.subarray(5, 1 + len);
      buf = buf.subarray(1 + len);
      if (t === 'Q') {
        const q = body.toString('utf8').replace(/\0$/, '');
        log.queries.push(q);
        if (q.includes('drop_connection')) { raw.destroy(); return; }
        sock.write(rowResult(respond(q)));
      } else if (t === 'X') {
        sock.end();
        return;
      }
    }
  };
  raw.on('data', onData);
  raw.on('error', () => {});
});
server.listen(0, '127.0.0.1', () => {
  console.log(JSON.stringify({ port: server.address().port }));
  setInterval(() => console.log(JSON.stringify({ log })), 150).unref();
});
process.on('SIGTERM', () => process.exit(0));
