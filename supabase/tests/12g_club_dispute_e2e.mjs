// Driver E2E 12g: Club con moderatore distinto e contestazione completa.
//
// Attraversa GoTrue, PostgREST, RLS, RPC e Storage con JWT reali degli utenti
// creati da 12g_club_dispute_e2e_fixtures.sql su un branch Supabase
// temporaneo. Non contatta provider di pagamento e non usa service_role.
// In CI lo esegue 12g_ci_run.sh su uno stack locale effimero.
//
//   E2E_SUPABASE_URL=https://<branch>.supabase.co \
//   E2E_ANON_KEY=<chiave publishable del branch> \
//   E2E_PASSWORD=<password temporanea della fixture> \
//   E2E_PHASE=club|dispute-open|dispute-decide \
//   bun supabase/tests/12g_club_dispute_e2e.mjs
//
// Ogni controllo dichiara il comportamento corretto; l'uscita e non zero se
// almeno un controllo fallisce. Nessun token o password viene stampato.

const URL_BASE = process.env.E2E_SUPABASE_URL ?? "";
const ANON = process.env.E2E_ANON_KEY ?? "";
const PASSWORD = process.env.E2E_PASSWORD ?? "";
const PHASE = process.env.E2E_PHASE ?? "";
const PRODUCTION_REF = "pijnmcllmfgjmgsvtcej";

if (!URL_BASE || !ANON || !PASSWORD || !PHASE) {
  console.error("Servono E2E_SUPABASE_URL, E2E_ANON_KEY, E2E_PASSWORD, E2E_PHASE.");
  process.exit(2);
}
// Target accettati: loopback (stack locale, l'unico ammesso in CI con
// E2E_REQUIRE_LOOPBACK=true) oppure un branch Preview `<ref>.supabase.co`
// diverso dalla produzione. Qualunque altro host e rifiutato: niente fallback.
let target;
try {
  target = new URL(URL_BASE);
} catch {
  console.error("Rifiutato: E2E_SUPABASE_URL non e un URL valido.");
  process.exit(2);
}
const isLoopback = ["127.0.0.1", "localhost", "[::1]"].includes(target.hostname);
const branchRef = /^([a-z0-9]{20})\.supabase\.co$/.exec(target.hostname)?.[1];
if (URL_BASE.includes(PRODUCTION_REF) || (!isLoopback && (!branchRef || branchRef === PRODUCTION_REF))) {
  console.error("Rifiutato: il target non e uno stack locale ne un branch Preview identificabile.");
  process.exit(2);
}
if (process.env.E2E_REQUIRE_LOOPBACK === "true" && !isLoopback) {
  console.error("Rifiutato: E2E_REQUIRE_LOOPBACK impone uno stack locale.");
  process.exit(2);
}

const uid = (n) => `12ee0000-0000-4000-8000-0000000000${String(n).padStart(2, "0")}`;
const order = (n) => `12ee4000-0000-4000-8000-00000000000${n}`;
const WEBP = Uint8Array.from(
  atob("UklGRiQAAABXRUJQVlA4IBgAAAAwAQCdASoBAAEAAwA0JaQAA3AA/vuUAAA="),
  (c) => c.charCodeAt(0),
);

const results = [];
const record = (id, ok, detail) => {
  results.push({ id, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"} ${id}${detail ? ` — ${detail}` : ""}`);
};

const tokens = new Map();
const login = async (n) => {
  if (tokens.has(n)) return tokens.get(n);
  const res = await fetch(`${URL_BASE}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: ANON, "Content-Type": "application/json" },
    body: JSON.stringify({ email: `u${String(n).padStart(2, "0")}@e2e-12g.test`, password: PASSWORD }),
  });
  const body = await res.json();
  if (!res.ok || !body.access_token) throw new Error(`login u${n} fallito: HTTP ${res.status}`);
  tokens.set(n, body.access_token);
  return body.access_token;
};

const headers = (n, extra = {}) => ({
  apikey: ANON,
  Authorization: `Bearer ${n === null ? ANON : tokens.get(n)}`,
  ...extra,
});

const parse = async (res) => {
  const text = await res.text();
  try { return text ? JSON.parse(text) : null; } catch { return text; }
};

const rpc = async (n, fn, args) => {
  const res = await fetch(`${URL_BASE}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: headers(n, { "Content-Type": "application/json" }),
    body: JSON.stringify(args),
  });
  return { status: res.status, body: await parse(res) };
};
const get = async (n, path) => {
  const res = await fetch(`${URL_BASE}/rest/v1/${path}`, { headers: headers(n) });
  return { status: res.status, body: await parse(res) };
};
const insert = async (n, table, row) => {
  const res = await fetch(`${URL_BASE}/rest/v1/${table}`, {
    method: "POST",
    headers: headers(n, { "Content-Type": "application/json", Prefer: "return=minimal" }),
    body: JSON.stringify(row),
  });
  return { status: res.status, body: await parse(res) };
};
const remove = async (n, path) => {
  const res = await fetch(`${URL_BASE}/rest/v1/${path}`, {
    method: "DELETE",
    headers: headers(n, { Prefer: "return=representation" }),
  });
  return { status: res.status, body: await parse(res) };
};
const upload = async (n, path) => {
  const res = await fetch(`${URL_BASE}/storage/v1/object/dispute-evidence/${path}`, {
    method: "POST",
    headers: headers(n, { "Content-Type": "image/webp", "x-upsert": "false" }),
    body: WEBP,
  });
  return { status: res.status, body: await parse(res) };
};
const sign = async (n, path) => {
  const res = await fetch(`${URL_BASE}/storage/v1/object/sign/dispute-evidence/${path}`, {
    method: "POST",
    headers: headers(n, { "Content-Type": "application/json" }),
    body: JSON.stringify({ expiresIn: 60 }),
  });
  const body = await parse(res);
  return { status: res.status, ok: res.ok && Boolean(body?.signedURL ?? body?.signedUrl) };
};
const deleteObjects = async (n, paths) => {
  const res = await fetch(`${URL_BASE}/storage/v1/object/dispute-evidence`, {
    method: "DELETE",
    headers: headers(n, { "Content-Type": "application/json" }),
    body: JSON.stringify({ prefixes: paths }),
  });
  const body = await parse(res);
  return { status: res.status, deleted: Array.isArray(body) ? body.length : 0 };
};

const isOk = (r) => r.status >= 200 && r.status < 300;
const code = (r) => (r.body && typeof r.body === "object" ? r.body.code : undefined);
const expectOk = (id, r, detail) =>
  record(id, isOk(r), isOk(r) ? detail : `HTTP ${r.status} ${code(r) ?? ""} ${r.body?.message ?? ""}`);
const expectCode = (id, r, expected) =>
  record(id, !isOk(r) && code(r) === expected, `atteso ${expected}, ottenuto HTTP ${r.status} ${code(r) ?? ""}`);
const expectDenied = (id, r) =>
  record(id, !isOk(r) && (r.status === 401 || r.status === 403 || code(r) === "42501"),
    `ottenuto HTTP ${r.status} ${code(r) ?? ""}`);
const expectEmpty = (id, r) =>
  record(id, isOk(r) && Array.isArray(r.body) && r.body.length === 0,
    `HTTP ${r.status}, righe ${Array.isArray(r.body) ? r.body.length : "n/d"}`);
const rows = (r) => (Array.isArray(r.body) ? r.body : []);
const newPath = (orderN, userN) => `${order(orderN)}/${uid(userN)}/${crypto.randomUUID()}.webp`;

// ---------------------------------------------------------------------------
// Club
// ---------------------------------------------------------------------------
const clubPhase = async () => {
  for (const n of [1, 2, 3, 4, 5, 6, 10]) await login(n);

  const proposta = (nome, links) => ({
    p_nome: nome,
    p_descrizione: "Club temporaneo per la verifica E2E 12g.",
    p_categoria: "Degustazione",
    p_territorio: "Toscana",
    p_access_type: "chiuso",
    p_requirements: "Solo per la verifica E2E",
    p_regole: ["Rispetta gli altri membri"],
    p_posting_mode: "OPEN",
    p_cover_image: null,
    p_external_links: links,
  });

  const creaA = await rpc(2, "club_proposta_crea", proposta("E2E 12g Club A",
    [{ platform: "sito", url: "https://example.org/e2e-12g-a", label: "Sito A" }]));
  expectOk("C01 owner propone Club A chiuso", creaA);
  const slugA = creaA.body?.slug;
  expectEmpty("C02 Club in attesa non pubblico", await get(null, `public_clubs?slug=eq.${slugA}&select=slug`));
  expectDenied("C03 moderatore futuro non approva proposte", await rpc(3, "club_proposta_revisiona",
    { p_club_slug: slugA, p_approva: true, p_nota: "tentativo" }));
  expectOk("C04 admin approva Club A", await rpc(1, "club_proposta_revisiona",
    { p_club_slug: slugA, p_approva: true, p_nota: "Approvato per E2E" }));
  const pubA = await get(null, `public_clubs?slug=eq.${slugA}&select=slug,access_type,regole`);
  record("C05 Club A pubblico e chiuso", rows(pubA).length === 1 && rows(pubA)[0].access_type === "chiuso");
  record("C06 link approvato con la proposta visibile",
    rows(await get(null, `public_club_external_links?club_slug=eq.${slugA}&select=url`)).length === 1);

  const creaB = await rpc(10, "club_proposta_crea", proposta("E2E 12g Club B", []));
  const slugB = creaB.body?.slug;
  expectOk("C07 admin approva Club B", await rpc(1, "club_proposta_revisiona",
    { p_club_slug: slugB, p_approva: true, p_nota: "Approvato per E2E" }));

  for (const n of [3, 4, 5, 6]) {
    const r = await rpc(n, "club_ingresso_richiedi", { p_club_slug: slugA, p_messaggio: "Vorrei entrare" });
    record(`C08 richiesta ingresso u${n} in attesa`, isOk(r) && r.body?.status === "in_attesa");
  }
  const reqB = await rpc(5, "club_ingresso_richiedi", { p_club_slug: slugB, p_messaggio: "Vorrei entrare" });
  record("C09 richiesta u05 nel Club B in attesa", isOk(reqB) && reqB.body?.status === "in_attesa");

  const codaOwner = rows(await get(2, `club_membership_request_queue?club_slug=eq.${slugA}&select=id,user_id`));
  record("C10 owner vede 4 richieste del proprio Club", codaOwner.length === 4);
  const reqId = (n) => codaOwner.find((r) => r.user_id === uid(n))?.id;
  const codaB = rows(await get(10, `club_membership_request_queue?club_slug=eq.${slugB}&select=id,user_id`));
  const reqIdB = codaB.find((r) => r.user_id === uid(5))?.id;

  expectOk("C11 owner approva u03", await rpc(2, "club_ingresso_revisiona",
    { p_request_id: reqId(3), p_approva: true, p_nota: null }));
  expectOk("C12 owner nomina u03 moderatore", await rpc(2, "club_moderatore_imposta",
    { p_club_slug: slugA, p_user_id: uid(3), p_moderatore: true }));
  expectCode("C13 non membro non diventa moderatore", await rpc(2, "club_moderatore_imposta",
    { p_club_slug: slugA, p_user_id: uid(6), p_moderatore: true }), "22023");

  const modView = rows(await get(3, `club_management_moderators?club_slug=eq.${slugA}&select=user_id,role`));
  record("C14 moderatore vede owner e se stesso con ruoli distinti",
    modView.some((r) => r.user_id === uid(2) && r.role === "proprietario")
      && modView.some((r) => r.user_id === uid(3) && r.role === "moderatore"));
  record("C15 moderatore vede il pannello del Club A",
    rows(await get(3, `club_management_clubs?slug=eq.${slugA}&select=slug`)).length === 1);

  expectOk("C16 moderatore approva u04", await rpc(3, "club_ingresso_revisiona",
    { p_request_id: reqId(4), p_approva: true, p_nota: "Benvenuto" }));
  expectOk("C17 moderatore rifiuta u05 con nota", await rpc(3, "club_ingresso_revisiona",
    { p_request_id: reqId(5), p_approva: false, p_nota: "Requisiti non soddisfatti" }));
  const mieReq = rows(await get(5, `my_club_membership_requests?club_slug=eq.${slugA}&select=status,review_note`));
  record("C18 richiedente vede rifiuto e nota", mieReq[0]?.status === "rifiutata" && mieReq[0]?.review_note === "Requisiti non soddisfatti");
  const pub5 = rows(await get(5, `public_clubs?slug=eq.${slugA}&select=seguito,membership_request_status`));
  record("C19 richiedente rifiutato non e membro", pub5[0]?.seguito === false && pub5[0]?.membership_request_status === "rifiutata");

  const codaMod = rows(await get(3, "club_membership_request_queue?select=id,club_slug,user_id"));
  record("C20 coda moderatore limitata al proprio Club",
    codaMod.length === 1 && codaMod[0].club_slug === slugA && codaMod[0].user_id === uid(6));
  expectDenied("C21 moderatore A non revisiona richieste del Club B", await rpc(3, "club_ingresso_revisiona",
    { p_request_id: reqIdB, p_approva: true, p_nota: null }));
  expectDenied("C22 membro normale non revisiona richieste", await rpc(4, "club_ingresso_revisiona",
    { p_request_id: reqId(6), p_approva: true, p_nota: null }));
  expectDenied("C23 outsider non approva la propria richiesta", await rpc(6, "club_ingresso_revisiona",
    { p_request_id: reqId(6), p_approva: true, p_nota: null }));

  for (const view of ["club_management_clubs", "club_management_members", "club_management_moderators",
    "club_membership_request_queue", "club_rule_versions_visible", "club_external_links_visible",
    "club_management_events_visible"]) {
    expectEmpty(`C24 membro normale non vede ${view}`, await get(4, `${view}?select=club_slug`.replace(
      "club_management_clubs?select=club_slug", "club_management_clubs?select=slug")));
    expectEmpty(`C25 outsider non vede ${view}`, await get(6, `${view}?select=club_slug`.replace(
      "club_management_clubs?select=club_slug", "club_management_clubs?select=slug")));
  }

  expectDenied("C26 moderatore non nomina moderatori", await rpc(3, "club_moderatore_imposta",
    { p_club_slug: slugA, p_user_id: uid(4), p_moderatore: true }));
  expectDenied("C27 membro normale non nomina moderatori", await rpc(4, "club_moderatore_imposta",
    { p_club_slug: slugA, p_user_id: uid(4), p_moderatore: true }));

  expectDenied("C28 moderatore senza privilegi admin: proposta Club", await rpc(3, "club_proposta_revisiona",
    { p_club_slug: slugB, p_approva: false, p_nota: "tentativo" }));
  expectEmpty("C29 moderatore senza privilegi admin: coda contestazioni", await get(3, "moderation_dispute_queue?select=id"));
  expectEmpty("C30 moderatore senza privilegi admin: proposte Club", await get(3, "moderation_club_proposals?select=slug"));
  expectEmpty("C31 moderatore senza ruoli globali", await get(3, `user_roles?user_id=eq.${uid(3)}&select=role`));
  expectEmpty("C32 moderatore A non vede la gestione del Club B", await get(3, `club_management_clubs?slug=eq.${slugB}&select=slug`));
  expectDenied("C33 moderatore A non modifica il regolamento del Club B", await rpc(3, "club_regolamento_proponi",
    { p_club_slug: slugB, p_regole: ["Regola non autorizzata"] }));
  expectDenied("C34 moderatore A non propone link nel Club B", await rpc(3, "club_link_proponi",
    { p_club_slug: slugB, p_platform: "sito", p_url: "https://example.org/x", p_label: null }));

  expectOk("C35 membro pubblica nel Club A", await insert(4, "club_posts",
    { club_slug: slugA, tipo: "discussione", titolo: "Prima discussione E2E", corpo: "Contenuto di prova" }));
  expectDenied("C36 outsider non pubblica nel Club A", await insert(6, "club_posts",
    { club_slug: slugA, tipo: "discussione", titolo: "Intrusione E2E", corpo: "Non dovrebbe entrare" }));
  expectDenied("C37 richiedente rifiutato non pubblica", await insert(5, "club_posts",
    { club_slug: slugA, tipo: "discussione", titolo: "Intrusione E2E", corpo: "Non dovrebbe entrare" }));
  record("C38 discussione del membro pubblica",
    rows(await get(null, `public_club_posts?club_slug=eq.${slugA}&select=id`)).length === 1);

  const regole = await rpc(3, "club_regolamento_proponi",
    { p_club_slug: slugA, p_regole: ["Rispetta gli altri membri", "Niente vendite fuori piattaforma"] });
  record("C39 moderatore propone regolamento v2", isOk(regole) && regole.body?.version === 2 && regole.body?.status === "in_attesa");
  expectCode("C40 una sola modifica in attesa", await rpc(3, "club_regolamento_proponi",
    { p_club_slug: slugA, p_regole: ["Altra modifica"] }), "P0001");
  expectDenied("C41 membro normale non propone regolamento", await rpc(4, "club_regolamento_proponi",
    { p_club_slug: slugA, p_regole: ["Regola del membro"] }));
  record("C42 regolamento pubblico resta v1 finche non approvato",
    rows(await get(null, `public_clubs?slug=eq.${slugA}&select=regole`))[0]?.regole?.length === 1);
  expectDenied("C43 moderatore non approva il proprio regolamento", await rpc(3, "club_regolamento_revisiona",
    { p_version_id: regole.body?.id, p_approva: true, p_nota: null }));
  expectOk("C44 admin approva regolamento v2", await rpc(1, "club_regolamento_revisiona",
    { p_version_id: regole.body?.id, p_approva: true, p_nota: "Approvato" }));
  const versioni = rows(await get(2, `club_rule_versions_visible?club_slug=eq.${slugA}&select=version,status&order=version`));
  record("C45 v1 superata, v2 corrente",
    versioni.length === 2 && versioni[0].status === "superata" && versioni[1].status === "approvata");
  record("C46 regolamento pubblico aggiornato a v2",
    rows(await get(null, `public_clubs?slug=eq.${slugA}&select=regole`))[0]?.regole?.length === 2);

  const link = await rpc(3, "club_link_proponi",
    { p_club_slug: slugA, p_platform: "instagram", p_url: "https://instagram.com/e2e12g", p_label: "Instagram" });
  record("C47 moderatore propone link in attesa", isOk(link) && link.body?.status === "in_attesa");
  record("C48 link in attesa non pubblico",
    rows(await get(null, `public_club_external_links?club_slug=eq.${slugA}&select=url`)).length === 1);
  expectDenied("C49 moderatore non approva link", await rpc(3, "club_link_revisiona", { p_link_id: link.body?.id, p_approva: true }));
  expectOk("C50 admin approva link", await rpc(1, "club_link_revisiona", { p_link_id: link.body?.id, p_approva: true }));
  record("C51 link approvato pubblico",
    rows(await get(null, `public_club_external_links?club_slug=eq.${slugA}&select=url`)).length === 2);

  const rilabel = await rpc(3, "club_link_proponi",
    { p_club_slug: slugA, p_platform: "instagram", p_url: "https://instagram.com/e2e12g", p_label: "Offerte riservate: scrivici" });
  const pubLinks = rows(await get(null, `public_club_external_links?club_slug=eq.${slugA}&select=label`));
  record("C52 nuova etichetta di un link approvato torna in revisione",
    isOk(rilabel) && rilabel.body?.status === "in_attesa"
      && !pubLinks.some((l) => l.label === "Offerte riservate: scrivici"),
    `stato ${rilabel.body?.status}, etichette pubbliche ${JSON.stringify(pubLinks.map((l) => l.label))}`);

  expectDenied("C53 membro normale non propone link", await rpc(4, "club_link_proponi",
    { p_club_slug: slugA, p_platform: "sito", p_url: "https://example.org/membro", p_label: null }));
  expectDenied("C54 membro normale non rimuove link", await rpc(4, "club_link_rimuovi", { p_link_id: link.body?.id }));
  expectOk("C55 moderatore rimuove link", await rpc(3, "club_link_rimuovi", { p_link_id: link.body?.id }));

  const eventi = rows(await get(2, `club_management_events_visible?club_slug=eq.${slugA}&select=event_kind`)).map((e) => e.event_kind);
  record("C56 audit di gestione completo",
    ["moderatore_aggiunto", "link_proposto", "link_approvato", "link_rimosso"].every((k) => eventi.includes(k)),
    JSON.stringify(eventi));
  expectDenied("C57 audit non cancellabile dal client", await remove(2, `club_management_events?club_slug=eq.${slugA}`));
  const gov = rows(await get(3, `visible_club_governance_events?club_slug=eq.${slugA}&select=event_kind`)).map((e) => e.event_kind);
  record("C58 registro governance visibile al moderatore",
    ["ingresso_approvato", "ingresso_rifiutato", "regolamento_proposto", "regolamento_approvato"].every((k) => gov.includes(k)));
  expectEmpty("C59 registro governance del Club A invisibile all'outsider",
    await get(6, `visible_club_governance_events?club_slug=eq.${slugA}&event_kind=neq.ingresso_richiesto&select=event_kind`));

  expectDenied("C60 owner non cambia il proprio ruolo", await rpc(2, "club_moderatore_imposta",
    { p_club_slug: slugA, p_user_id: uid(2), p_moderatore: false }));
  expectCode("C61 owner non abbandona il Club", await rpc(2, "club_abbandona", { p_club_slug: slugA }), "P0001");
  expectOk("C62 owner rimuove il moderatore", await rpc(2, "club_moderatore_imposta",
    { p_club_slug: slugA, p_user_id: uid(3), p_moderatore: false }));
  expectDenied("C63 ex moderatore non revisiona piu", await rpc(3, "club_ingresso_revisiona",
    { p_request_id: reqId(6), p_approva: true, p_nota: null }));
  expectEmpty("C64 ex moderatore perde il pannello", await get(3, `club_management_clubs?slug=eq.${slugA}&select=slug`));
  record("C65 ex moderatore resta membro",
    rows(await get(3, `public_clubs?slug=eq.${slugA}&select=seguito`))[0]?.seguito === true);
  expectDenied("C66 anon non richiede ingresso", await rpc(null, "club_ingresso_richiedi",
    { p_club_slug: slugA, p_messaggio: null }));
};

// ---------------------------------------------------------------------------
// Contestazioni: apertura, risposta, revisione, note private
// ---------------------------------------------------------------------------
const disputeId = async (n, orderN) =>
  rows(await get(n, `disputes?order_id=eq.${order(orderN)}&select=id`))[0]?.id;

const disputeOpenPhase = async () => {
  for (const n of [1, 3, 6, 7, 8, 9]) await login(n);

  const scarto = newPath(1, 7);
  expectOk("D01 compratore carica una prova", await upload(7, scarto));
  const pulizia = await deleteObjects(7, [scarto]);
  record("D02 compratore rimuove un caricamento non inviato", pulizia.deleted === 1, `rimossi ${pulizia.deleted}`);

  const p7 = newPath(1, 7);
  expectOk("D03 compratore carica la prova da allegare", await upload(7, p7));
  record("D04 outsider non carica prove sull'ordine altrui", !isOk(await upload(6, newPath(1, 6))));
  record("D05 venditore non carica prove prima della contestazione", !isOk(await upload(8, newPath(1, 8))));
  expectDenied("D06 venditore non apre contestazioni", await rpc(8, "ordine_contestazione_apri",
    { p_order_id: order(1), p_motivo: "Bottiglia rotta", p_descrizione: "Tentativo del venditore", p_foto: [] }));

  const apertura = await rpc(7, "ordine_contestazione_apri", {
    p_order_id: order(1), p_motivo: "Bottiglia rotta",
    p_descrizione: "La bottiglia e arrivata con il collo rotto.", p_foto: [p7],
  });
  record("D07 compratore apre la contestazione entro 48 ore", isOk(apertura) && apertura.body?.stato === "contestato");
  expectCode("D08 seconda apertura rifiutata", await rpc(7, "ordine_contestazione_apri", {
    p_order_id: order(1), p_motivo: "Bottiglia rotta", p_descrizione: "Duplicato", p_foto: [],
  }), "P0001");
  expectCode("D09 apertura oltre 48 ore rifiutata", await rpc(9, "ordine_contestazione_apri", {
    p_order_id: order(3), p_motivo: "Bottiglia rotta", p_descrizione: "Troppo tardi", p_foto: [],
  }), "P0001");
  expectCode("D10 risposta venditore oltre 48 ore rifiutata", await rpc(8, "contestazione_venditore_rispondi", {
    p_order_id: order(4), p_tipo: "contesta", p_risposta: "Troppo tardi", p_foto: [],
  }), "P0001");

  const idA = await disputeId(7, 1);
  record("D11 compratore vede la propria pratica", Boolean(idA));
  for (const n of [6, 9, 3]) {
    expectEmpty(`D12 u${n} non vede la pratica A`, await get(n, `disputes?order_id=eq.${order(1)}&select=id`));
    expectEmpty(`D13 u${n} non vede gli eventi A`, await get(n, `dispute_events?dispute_id=eq.${idA}&select=id`));
    expectEmpty(`D14 u${n} non vede la timeline A`, await get(n, `dispute_case_timeline?dispute_id=eq.${idA}&select=id`));
    expectEmpty(`D15 u${n} non vede l'ordine A`, await get(n, `orders?id=eq.${order(1)}&select=id`));
    record(`D16 u${n} non firma la prova A`, !(await sign(n, p7)).ok);
    expectEmpty(`D17 u${n} non vede la coda amministrativa`, await get(n, "moderation_dispute_queue?select=id"));
  }

  const vistaVenditore = rows(await get(8,
    `disputes?order_id=eq.${order(1)}&select=lifecycle_status,foto,venditore_scadenza_at`))[0];
  record("D18 venditore vede la pratica in attesa", vistaVenditore?.lifecycle_status === "attesa_venditore");
  record("D19 venditore firma la prova del compratore", (await sign(8, p7)).ok);
  const p8 = newPath(1, 8);
  expectOk("D20 venditore carica la propria prova", await upload(8, p8));
  expectDenied("D21 compratore non risponde al posto del venditore", await rpc(7, "contestazione_venditore_rispondi",
    { p_order_id: order(1), p_tipo: "accetta", p_risposta: "Tentativo", p_foto: [] }));
  const risposta = await rpc(8, "contestazione_venditore_rispondi", {
    p_order_id: order(1), p_tipo: "contesta",
    p_risposta: "La bottiglia era integra alla spedizione.", p_foto: [p8],
  });
  record("D22 venditore risponde", isOk(risposta) && risposta.body?.lifecycle_status === "risposta_venditore");
  expectCode("D23 seconda risposta rifiutata", await rpc(8, "contestazione_venditore_rispondi",
    { p_order_id: order(1), p_tipo: "accetta", p_risposta: "Ripensamento", p_foto: [] }), "P0001");
  record("D24 compratore firma la prova del venditore", (await sign(7, p8)).ok);

  for (const n of [8, 3]) {
    for (const fn of ["moderazione_contestazione_prendi_in_carico", "moderazione_contestazione_documentazione_completa",
      "moderazione_contestazione_inizia_revisione"]) {
      expectDenied(`D25 u${n} non esegue ${fn}`, await rpc(n, fn, { p_order_id: order(1) }));
    }
    expectDenied(`D26 u${n} non scrive note private`, await rpc(n, "moderazione_contestazione_nota_privata",
      { p_order_id: order(1), p_nota: "Tentativo" }));
    expectDenied(`D27 u${n} non decide`, await rpc(n, "moderazione_contestazione_decidi",
      { p_order_id: order(1), p_esito: "favore_venditore", p_motivazione: "Tentativo", p_motivo_correzione: null }));
  }

  const coda = rows(await get(1, "moderation_dispute_queue?select=order_id,lifecycle_status"));
  record("D28 admin vede le pratiche in coda", coda.some((r) => r.order_id === order(1)));
  record("D29 admin firma la prova del compratore", (await sign(1, p7)).ok);
  record("D30 admin firma la prova del venditore", (await sign(1, p8)).ok);
  record("D31 admin legge gli eventi di base",
    rows(await get(1, `dispute_events?dispute_id=eq.${idA}&select=event_kind`)).length >= 2);

  expectOk("D32 admin prende in carico", await rpc(1, "moderazione_contestazione_prendi_in_carico", { p_order_id: order(1) }));
  expectCode("D33 decisione prima della revisione rifiutata", await rpc(1, "moderazione_contestazione_decidi",
    { p_order_id: order(1), p_esito: "favore_acquirente", p_motivazione: "Troppo presto", p_motivo_correzione: null }), "P0001");
  expectOk("D34 admin segna documentazione completa", await rpc(1, "moderazione_contestazione_documentazione_completa", { p_order_id: order(1) }));
  expectOk("D35 admin avvia la revisione", await rpc(1, "moderazione_contestazione_inizia_revisione", { p_order_id: order(1) }));
  const nota = await rpc(1, "moderazione_contestazione_nota_privata",
    { p_order_id: order(1), p_nota: "Nota interna E2E: foto coerenti con il danno." });
  expectOk("D36 admin registra una nota privata", nota);

  for (const n of [7, 8]) {
    expectEmpty(`D37 u${n} non legge note private dalla vista`, await get(n, "moderation_dispute_admin_notes?select=id"));
    expectDenied(`D38 u${n} non legge la tabella note`, await get(n, "dispute_admin_notes?select=id"));
    expectDenied(`D39 u${n} non legge l'assegnatario`, await get(n, `disputes?order_id=eq.${order(1)}&select=assigned_to`));
    const tl = rows(await get(n, `dispute_case_timeline?dispute_id=eq.${idA}&select=event_kind,detail`));
    record(`D40 u${n} vede solo eventi pubblici della revisione`,
      tl.length === 1 && tl[0].event_kind === "revisione_iniziata", JSON.stringify(tl.map((e) => e.event_kind)));
  }
  const tlAdmin = rows(await get(1, `dispute_case_timeline?dispute_id=eq.${idA}&select=event_kind`)).map((e) => e.event_kind);
  record("D41 admin vede la timeline completa",
    ["presa_in_carico", "revisione_iniziata", "nota_privata_aggiunta"].every((k) => tlAdmin.includes(k)));
  record("D42 admin legge la nota privata",
    rows(await get(1, `moderation_dispute_admin_notes?dispute_id=eq.${idA}&select=note`)).length === 1);

  // Ordine B: la revisione parte prima che il venditore usi le sue 48 ore.
  expectOk("D43 compratore B apre senza foto", await rpc(9, "ordine_contestazione_apri", {
    p_order_id: order(2), p_motivo: "Annata differente", p_descrizione: "Annata diversa dall'annuncio.", p_foto: [],
  }));
  expectOk("D44 admin prende in carico B", await rpc(1, "moderazione_contestazione_prendi_in_carico", { p_order_id: order(2) }));
  expectOk("D45 admin chiude la documentazione B", await rpc(1, "moderazione_contestazione_documentazione_completa", { p_order_id: order(2) }));
  expectOk("D46 admin avvia la revisione B", await rpc(1, "moderazione_contestazione_inizia_revisione", { p_order_id: order(2) }));
  expectOk("D47 venditore risponde su B entro 48 ore", await rpc(8, "contestazione_venditore_rispondi", {
    p_order_id: order(2), p_tipo: "propone_soluzione", p_risposta: "Propongo un reso concordato.", p_foto: [],
  }));
  const statoB = rows(await get(9, `disputes?order_id=eq.${order(2)}&select=lifecycle_status`))[0]?.lifecycle_status;
  record("D48 la risposta tardiva non riporta indietro la revisione B", statoB === "in_revisione", `stato ${statoB}`);
};

// ---------------------------------------------------------------------------
// Contestazioni: decisione, correzione, integrita delle prove
// ---------------------------------------------------------------------------
const disputeDecidePhase = async () => {
  for (const n of [1, 6, 7, 8, 9]) await login(n);
  const idA = await disputeId(7, 1);

  expectDenied("E01 venditore non decide", await rpc(8, "moderazione_contestazione_decidi",
    { p_order_id: order(1), p_esito: "favore_venditore", p_motivazione: "Tentativo", p_motivo_correzione: null }));
  expectDenied("E02 anon non decide", await rpc(null, "moderazione_contestazione_decidi",
    { p_order_id: order(1), p_esito: "favore_venditore", p_motivazione: "Tentativo", p_motivo_correzione: null }));
  expectCode("E03 decisione senza motivazione rifiutata", await rpc(1, "moderazione_contestazione_decidi",
    { p_order_id: order(1), p_esito: "favore_acquirente", p_motivazione: " ", p_motivo_correzione: null }), "22023");
  const decisione = await rpc(1, "moderazione_contestazione_decidi", {
    p_order_id: order(1), p_esito: "favore_acquirente",
    p_motivazione: "Le foto mostrano il collo della bottiglia rotto all'arrivo.", p_motivo_correzione: null,
  });
  record("E04 admin decide con motivazione", isOk(decisione) && decisione.body?.version === 1 && decisione.body?.corrected === false);
  expectCode("E05 doppio invio senza motivo di correzione rifiutato", await rpc(1, "moderazione_contestazione_decidi", {
    p_order_id: order(1), p_esito: "favore_acquirente", p_motivazione: "Doppio clic", p_motivo_correzione: null,
  }), "22023");

  for (const n of [7, 8]) {
    const vista = rows(await get(n, `disputes?order_id=eq.${order(1)}&select=lifecycle_status,resolution_kind,resolution_note,resolution_version`))[0];
    record(`E06 u${n} vede l'esito motivato v1`,
      vista?.lifecycle_status === "risolta_acquirente" && vista?.resolution_kind === "favore_acquirente"
        && vista?.resolution_version === 1 && typeof vista?.resolution_note === "string");
  }

  const correzione = await rpc(1, "moderazione_contestazione_decidi", {
    p_order_id: order(1), p_esito: "accordo",
    p_motivazione: "Le parti hanno comunicato un accordo dopo la decisione.",
    p_motivo_correzione: "Accordo comunicato dalle parti dopo la prima decisione.",
  });
  record("E07 admin corregge con motivo", isOk(correzione) && correzione.body?.version === 2 && correzione.body?.corrected === true);

  for (const n of [7, 8]) {
    const vista = rows(await get(n, `disputes?order_id=eq.${order(1)}&select=lifecycle_status,resolution_kind,resolution_version`))[0];
    record(`E08 u${n} vede la correzione v2`,
      vista?.lifecycle_status === "accordo" && vista?.resolution_kind === "accordo" && vista?.resolution_version === 2);
    const tl = rows(await get(n, `dispute_case_timeline?dispute_id=eq.${idA}&select=event_kind,detail,created_at&order=created_at,id`));
    const kinds = tl.map((e) => e.event_kind);
    const ordinata = tl.every((e, i) => i === 0 || tl[i - 1].created_at <= e.created_at);
    record(`E09 u${n} timeline finale ordinata e senza note`,
      ordinata && JSON.stringify(kinds) === JSON.stringify(["revisione_iniziata", "decisione_registrata", "decisione_corretta"])
        && tl.every((e) => !("note" in (e.detail ?? {})) && !("note_id" in (e.detail ?? {}))),
      JSON.stringify(kinds));
    const base = rows(await get(n, `dispute_events?dispute_id=eq.${idA}&select=event_kind&order=created_at,id`)).map((e) => e.event_kind);
    record(`E10 u${n} vede gli eventi di base`, base[0] === "aperta" && base.includes("risposta_venditore"), JSON.stringify(base));
    expectEmpty(`E11 u${n} non vede note dopo la decisione`, await get(n, "moderation_dispute_admin_notes?select=id"));
    expectDenied(`E12 u${n} non legge lo storico interno delle decisioni`, await get(n, "dispute_decisions?select=id"));
  }
  for (const n of [6, 9]) {
    expectEmpty(`E13 u${n} non vede la pratica decisa A`, await get(n, `disputes?order_id=eq.${order(1)}&select=id`));
    expectEmpty(`E14 u${n} non vede la timeline decisa A`, await get(n, `dispute_case_timeline?dispute_id=eq.${idA}&select=id`));
  }

  const decisioneB = await rpc(1, "moderazione_contestazione_decidi", {
    p_order_id: order(2), p_esito: "favore_venditore",
    p_motivazione: "Il venditore ha proposto una soluzione adeguata.", p_motivo_correzione: null,
  });
  record("E15 pratica B decidibile dopo la risposta tardiva", isOk(decisioneB),
    isOk(decisioneB) ? "" : `HTTP ${decisioneB.status} ${code(decisioneB) ?? ""} ${decisioneB.body?.message ?? ""}`);

  const provaCompratore = rows(await get(7, `disputes?order_id=eq.${order(1)}&select=foto`))[0]?.foto?.[0];
  const tentativo = await deleteObjects(7, [provaCompratore]);
  record("E16 prova depositata non cancellabile dal compratore",
    tentativo.deleted === 0 && (await sign(1, provaCompratore)).ok, `rimossi ${tentativo.deleted}`);
  const provaVenditore = rows(await get(8, `disputes?order_id=eq.${order(1)}&select=venditore_foto`))[0]?.venditore_foto?.[0];
  const tentativoV = await deleteObjects(8, [provaVenditore]);
  record("E17 prova depositata non cancellabile dal venditore",
    tentativoV.deleted === 0 && (await sign(1, provaVenditore)).ok, `rimossi ${tentativoV.deleted}`);
};

const phases = { club: clubPhase, "dispute-open": disputeOpenPhase, "dispute-decide": disputeDecidePhase };
if (!phases[PHASE]) {
  console.error(`Fase sconosciuta: ${PHASE}`);
  process.exit(2);
}
await phases[PHASE]();
const failed = results.filter((r) => !r.ok);
console.log(JSON.stringify({ phase: PHASE, total: results.length, passed: results.length - failed.length,
  failed: failed.map((f) => f.id) }));
process.exit(failed.length === 0 ? 0 : 1);
