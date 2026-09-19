// Run only against the disposable restore project. No production credentials.
// Config path: VINEA_DRILL_CONFIG; { url, key, password, conversationId }.
import { readFileSync } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';

const cfg = JSON.parse(readFileSync(process.env.VINEA_DRILL_CONFIG, 'utf8'));
const projectRef = new URL(cfg.url).hostname.split('.')[0];
if (!cfg.expectedProjectId || cfg.expectedProjectId !== projectRef || projectRef === 'pijnmcllmfgjmgsvtcej') {
  throw new Error('Disposable project guard');
}
const outcomes = [];
const sockets = [];
function check(name, ok, detail) {
  outcomes.push({ name, pass: !!ok, detail });
  if (!ok) throw new Error(name);
}
async function request(path, token, method = 'GET', body, contentType = 'application/json') {
  const response = await fetch(cfg.url + path, {
    method, headers: { apikey: cfg.key, Authorization: `Bearer ${token || cfg.key}`, 'Content-Type': contentType },
    body: body === undefined ? undefined : contentType === 'application/json' ? JSON.stringify(body) : body,
  });
  const bytes = new Uint8Array(await response.arrayBuffer());
  let data; try { data = JSON.parse(new TextDecoder().decode(bytes)); } catch { data = null; }
  return { status: response.status, data, bytes };
}
function join(token, topic) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(cfg.url.replace('https:', 'wss:') + `/realtime/v1/websocket?apikey=${encodeURIComponent(cfg.key)}&vsn=1.0.0`);
    sockets.push(ws);
    const events = [];
    const system = [];
    const timer = setTimeout(() => reject(new Error('Realtime join timeout')), 15000);
    ws.onopen = () => ws.send(JSON.stringify({ topic: `realtime:${topic}`, event: 'phx_join', ref: '1', payload: { config: { private: true, broadcast: { ack: false, self: false, replication_ready: true }, presence: { enabled: false }, postgres_changes: [] }, access_token: token } }));
    ws.onmessage = event => {
      const msg = JSON.parse(event.data);
      if (msg.event === 'phx_reply' && msg.ref === '1') { clearTimeout(timer); resolve({ status: msg.payload.status, events, system }); }
      if (msg.event === 'system') system.push(msg.payload);
      if (msg.event === 'broadcast') events.push(msg.payload);
    };
    ws.onerror = () => { clearTimeout(timer); reject(new Error('Realtime connection error')); };
  });
}
try {
  const tokens = [];
  for (let n = 1; n <= 3; n++) {
    const r = await request('/auth/v1/token?grant_type=password', null, 'POST', { email: `restore-drill-${n}@example.invalid`, password: cfg.password });
    check(`real Auth session ${n}`, r.status === 200 && !!r.data?.access_token, r.status);
    tokens.push(r.data.access_token);
  }
  const [seller, buyer, outsider] = tokens;
  const topic = `conversation:${cfg.conversationId}`;
  const memberChannel = await join(seller, topic);
  check('private Realtime participant allowed', memberChannel.status === 'ok', memberChannel.status);
  const otherChannel = await join(outsider, topic);
  check('private Realtime outsider denied', otherChannel.status === 'error', otherChannel.status);
  const anonChannel = await join(cfg.key, topic);
  check('private Realtime anonymous denied', anonChannel.status === 'error', anonChannel.status);
  const readyDeadline = Date.now() + 20000;
  while (!memberChannel.system.some(x => x.status === 'ok') && Date.now() < readyDeadline) await new Promise(r => setTimeout(r, 100));
  check('Realtime replication ready', memberChannel.system.some(x => x.status === 'ok'), memberChannel.system.map(x => ({status:x.status, extension:x.extension})));
  const idempotency = randomUUID();
  const payload = { p_conversation_id: cfg.conversationId, p_text: 'Disposable restore security test', p_idempotency_key: idempotency };
  const sent = await request('/rest/v1/rpc/message_send', buyer, 'POST', payload);
  check('message participant RPC', sent.status === 200 && !!sent.data?.[0]?.id, sent.status);
  const retry = await request('/rest/v1/rpc/message_send', buyer, 'POST', payload);
  check('message retry idempotent', retry.data?.[0]?.id === sent.data[0].id, retry.status);
  const denied = await request('/rest/v1/rpc/message_send', outsider, 'POST', { ...payload, p_idempotency_key: randomUUID() });
  check('message outsider RPC denied', denied.status === 403, denied.status);
  const participantRead = await request(`/rest/v1/messages?conversation_id=eq.${cfg.conversationId}&select=id`, seller);
  const outsiderRead = await request(`/rest/v1/messages?conversation_id=eq.${cfg.conversationId}&select=id`, outsider);
  check('message RLS participant reads', participantRead.status === 200 && participantRead.data.some(x => x.id === sent.data[0].id), participantRead.status);
  check('message RLS outsider sees zero', outsiderRead.status === 200 && outsiderRead.data.length === 0, outsiderRead.status);
  const deadline = Date.now() + 10000;
  while (!memberChannel.events.length && Date.now() < deadline) await new Promise(r => setTimeout(r, 100));
  check('private Realtime delivers database broadcast', memberChannel.events.some(x => x.event === 'message.changed' && x.payload?.id === sent.data[0].id), memberChannel.events.length);
  check('outsider receives no broadcast', otherChannel.events.length === 0, otherChannel.events.length);

  const name = `e9190000-0000-4000-8000-000000000001/security-drill-${randomUUID()}.png`;
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jVAAAAABJRU5ErkJggg==', 'base64');
  const upload = await request(`/storage/v1/object/cantina/${name}`, seller, 'POST', png, 'image/png');
  check('private Storage owner upload', upload.status === 200, upload.status);
  const own = await request(`/storage/v1/object/authenticated/cantina/${name}`, seller);
  check('private Storage owner download byte match', own.status === 200 && Buffer.from(own.bytes).equals(png), own.status);
  const other = await request(`/storage/v1/object/authenticated/cantina/${name}`, outsider);
  check('private Storage outsider download denied', other.status >= 400, other.status);
  const anonymous = await request(`/storage/v1/object/public/cantina/${name}`, null);
  check('private Storage public URL denied', anonymous.status >= 400, anonymous.status);
  const otherUpload = await request(`/storage/v1/object/cantina/${name}-other.png`, outsider, 'POST', png, 'image/png');
  check('private Storage cross-user upload denied', otherUpload.status >= 400, otherUpload.status);
  const signed = await request(`/storage/v1/object/sign/cantina/${name}`, seller, 'POST', { expiresIn: 60 });
  check('private Storage owner signed URL', signed.status === 200 && !!signed.data?.signedURL, signed.status);
  const restored = await fetch(cfg.url + '/storage/v1' + signed.data.signedURL);
  const restoredBytes = Buffer.from(await restored.arrayBuffer());
  check('signed URL bytes SHA256 match', restored.status === 200 && createHash('sha256').update(restoredBytes).digest('hex') === createHash('sha256').update(png).digest('hex'), restored.status);
  const otherSign = await request(`/storage/v1/object/sign/cantina/${name}`, outsider, 'POST', { expiresIn: 60 });
  check('private Storage outsider signing denied', otherSign.status >= 400, otherSign.status);
  const removed = await request('/storage/v1/object/cantina', seller, 'DELETE', { prefixes: [name] });
  check('private Storage fixture removed', removed.status === 200 && removed.data?.length === 1, removed.status);
} catch (error) {
  console.error('Smoke stopped:', error.message);
  process.exitCode = 1;
} finally {
  for (const socket of sockets) socket.close();
  console.log(JSON.stringify({ project: projectRef, outcomes }, null, 2));
}
