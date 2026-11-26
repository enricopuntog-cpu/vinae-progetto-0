// WI-015 — regole dei worker, senza database e senza rete (node --test).
import test from "node:test";
import assert from "node:assert/strict";
import { analizzaProposta, analizzaQualita, analizzaTecnico, classificaSegnali } from "../lib/analisi.mjs";
import { controllaConnessione } from "../lib/connessione.mjs";
import { eseguiLotto, eseguiUnGiro } from "../lib/worker.mjs";

const proposta = (o) => ({ tipo: "catalogo.proposta", stato: "aperta", contributo_id: 7, corrispondenza: "sconosciuto", candidati: [], mancanti: [], ...o });
const VINO = "11111111-1111-4111-8111-111111111111";

test("proposta gia decisa: nessuna evidenza, solo la chiusura che il server deve confermare", () => {
  assert.deepEqual(analizzaProposta(proposta({ stato: "gia_decisa" })), { evidenze: [], chiusura: true });
});

test("collega solo un'identita unica; il collegamento gia approvato e distinto dal probabile", () => {
  const autorevole = analizzaProposta(proposta({ corrispondenza: "autorevole", candidati: [{ wine_id: VINO, motivo: "collegamento_approvato" }] }));
  assert.equal(autorevole.proposta.azione, "collega");
  assert.equal(autorevole.proposta.certezza, "collegamento_gia_approvato");
  const probabile = analizzaProposta(proposta({ corrispondenza: "probabile", candidati: [{ wine_id: VINO, motivo: "nome_identico" }] }));
  assert.equal(probabile.proposta.certezza, "probabile_da_verificare");
});

test("ambiguita, fonte non promossa e sola somiglianza non diventano mai collegamento o creazione", () => {
  const due = [{ wine_id: VINO, motivo: "nome_identico" }, { wine_id: "22222222-2222-4222-8222-222222222222", motivo: "nome_identico" }];
  assert.equal(analizzaProposta(proposta({ corrispondenza: "ambiguo", candidati: due })).proposta.azione, "conflitto");
  assert.equal(analizzaProposta(proposta({ corrispondenza: "probabile", candidati: due })).proposta.azione, "conflitto");
  const fonte = [{ wine_id: VINO, motivo: "nome_identico" }, { source_record_id: 5, lwin7: "1234567", motivo: "fonte_lwin_non_promossa" }];
  assert.equal(analizzaProposta(proposta({ corrispondenza: "probabile", candidati: fonte })).proposta.azione, "verifica_fonte");
  assert.equal(analizzaProposta(proposta({ candidati: [{ wine_id: VINO, motivo: "simile" }] })).proposta.azione, "verifica_duplicato");
  assert.equal(analizzaProposta(proposta({})).proposta.azione, "crea");
});

test("l'evidenza porta soli riferimenti, mai i testi dei candidati, e resta sotto i 4 KB", () => {
  const molti = Array.from({ length: 40 }, (_, i) => ({ wine_id: VINO, motivo: "simile", produttore: "Nome lungo ".repeat(10), nome: `Vino ${i}` }));
  const r = analizzaProposta(proposta({ candidati: molti, mancanti: ["annata"], proposte_stesso_nome: 2 }));
  assert.equal(r.evidenze[0].dettaglio.candidati.length, 10);
  assert.ok(!JSON.stringify(r.evidenze).includes("Nome lungo"));
  assert.ok(Buffer.byteLength(JSON.stringify(r.evidenze[0].dettaglio)) < 4096);
  assert.ok(r.proposta.avvisi.some((a) => a.includes("annata")));
  assert.ok(r.proposta.avvisi.some((a) => a.includes("stesso nome")));
});

test("qualita: senza rilievi chiede la chiusura; altrimenti ordina per gravita e propone, non esegue", () => {
  assert.deepEqual(analizzaQualita({ rilievi: [] }), { evidenze: [], chiusura: true });
  const r = analizzaQualita({ rilievi: [
    { codice: "omonimi_attivi", severita: "P3", conteggio: 4, esempi: [VINO] },
    { codice: "conflitti_nativi", severita: "P2", conteggio: 1, esempi: [VINO] },
  ] });
  assert.equal(r.proposta.priorita, "P2");
  assert.deepEqual(r.proposta.rilievi.map((x) => x.codice), ["conflitti_nativi", "omonimi_attivi"]);
  assert.equal(r.proposta.azione, "rivedi_qualita");
});

const s = (stato, minutiFa, riferimento) => ({ stato, osservato: new Date(Date.UTC(2026, 10, 26, 20) - minutiFa * 60000).toISOString(), riferimento });

test("tecnico: distingue stato attuale e storia; il verde dopo un guasto va verificato, non chiuso", () => {
  assert.equal(classificaSegnali({ segnali: [] }).classe, "non_verificato");
  assert.equal(classificaSegnali({ segnali: [s("guasto", 0), s("guasto", 30)] }).classe, "guasto_persistente");
  assert.equal(classificaSegnali({ segnali: [s("guasto", 0), s("ok", 30)] }).classe, "guasto_isolato");
  assert.equal(classificaSegnali({ segnali: [s("ok", 0), s("guasto", 30)] }).classe, "ripristino_da_verificare");
  assert.equal(classificaSegnali({ segnali: [s("ok", 0), s("ok", 30)] }).classe, "regolare");
});

test("tecnico: un buco oltre la cadenza attesa e dichiarato (caso del heartbeat in ritardo); mai deploy o rollback", () => {
  const r = analizzaTecnico({ fonte: "technical_heartbeat", intervallo_atteso_minuti: 30, segnali: [s("guasto", 0), s("ok", 600)] });
  assert.match(r.proposta.nota_freschezza, /cadenza/);
  assert.doesNotMatch(JSON.stringify(r.proposta), /deploy|rollback|riavvi/i);
});

function dbFinto(presa, { contesto, erroreContesto } = {}) {
  const chiamate = [];
  const coda = [...(Array.isArray(presa) ? presa : [presa])];
  return {
    chiamate,
    claim: async () => coda.shift() ?? null,
    context: async () => {
      if (erroreContesto) throw Object.assign(new Error("x"), { errno: "42501" });
      return contesto;
    },
    evidence: async (...a) => chiamate.push(["evidence", a[2]]),
    finish: async (_t, _l, ok, p) => (chiamate.push(["finish", ok, p?.azione ?? null]), ok ? "in_approvazione" : "in_attesa"),
    closeIfAllowed: async () => chiamate.push(["close"]),
  };
}
const PRESA = { task_id: "t", lease_token: "l", task_type: "catalogo.proposta" };

test("ciclo: evidenza prima della consegna, e la consegna va in approvazione", async () => {
  const db = dbFinto(PRESA, { contesto: proposta({}) });
  assert.equal((await eseguiUnGiro(db)).esito, "in_approvazione");
  assert.deepEqual(db.chiamate, [["evidence", "corrispondenza"], ["finish", true, "crea"]]);
});

test("ciclo: un errore restituisce il task come guasto con il solo codice e ferma il lotto", async () => {
  const db = dbFinto([PRESA, PRESA], { erroreContesto: true });
  const giri = await eseguiLotto(db, 10);
  assert.deepEqual(giri.map((g) => [g.esito, g.codice]), [["errore", "42501"]]);
  assert.deepEqual(db.chiamate, [["finish", false, null]]);
});

test("ciclo: chiusura consentita solo tramite la porta del server; coda vuota = niente da fare", async () => {
  const db = dbFinto(PRESA, { contesto: proposta({ stato: "gia_decisa" }) });
  assert.equal((await eseguiUnGiro(db)).esito, "chiuso_per_regola");
  assert.deepEqual(db.chiamate, [["close"]]);
  assert.equal((await eseguiUnGiro(db)).esito, "niente_da_fare");
});

test("connessione: rifiutati proprietario, chiavi amministrative e TLS non verificato fuori da loopback", () => {
  for (const url of [
    "postgresql://postgres:x@127.0.0.1:54322/postgres",
    "postgresql://postgres.abcdef:x@aws-0.pooler.supabase.com:5432/postgres?sslmode=verify-full",
    "postgresql://service_role:x@127.0.0.1/postgres",
    "postgresql://catalog_import_login:x@127.0.0.1/postgres",
    "postgresql://vinea_agent_x:x@db.example.com/postgres?sslmode=require",
    "http://vinea_agent_x@127.0.0.1",
    "non-un-url",
  ]) {
    assert.equal(controllaConnessione(url).ok, false, url);
  }
  assert.equal(controllaConnessione("postgresql://vinea_agent_x:y@127.0.0.1:54322/postgres").ok, true);
  assert.equal(controllaConnessione("postgresql://vinea_agent_x.ref:y@aws-0.pooler.supabase.com:5432/postgres?sslmode=verify-full").ok, true);
});
