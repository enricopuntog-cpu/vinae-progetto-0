// WI-016 — connessione dei processi del Company Brain con TLS verificato contro la CA del progetto, e osservatore
// indipendente dell'heartbeat (node --test, senza rete e senza database).
import test from "node:test";
import assert from "node:assert/strict";
import { opzioniConnessione } from "../lib/connessione.mjs";
import { valutaHeartbeat } from "../lib/osservatore.mjs";

const CERT = "-----BEGIN CERTIFICATE-----\nMIIBszCCAVmgAwIBAgIUQ2Fw\n-----END CERTIFICATE-----\n";
const OSPITATO = "postgresql://vinea_agent_x.ref:y@aws-0-eu.pooler.supabase.com:5432/postgres?sslmode=verify-full";

test("fuori da loopback serve la CA: senza non si connette, mai TLS non verificato", () => {
  const senza = opzioniConnessione(OSPITATO, {});
  assert.equal(senza.ok, false);
  assert.match(senza.motivo, /VINEA_DB_CA_PEM/);
});

test("con la CA: verifica di catena e nome obbligatoria", () => {
  const r = opzioniConnessione(OSPITATO, { VINEA_DB_CA_PEM: CERT });
  assert.equal(r.ok, true);
  assert.equal(r.opzioni.tls.rejectUnauthorized, true);
  assert.match(r.opzioni.tls.ca, /BEGIN CERTIFICATE/);
  assert.equal(r.opzioni.url, OSPITATO);
});

test("CA non valida, chiave privata, parametri TLS aggiunti o modalita piu deboli: rifiutati", () => {
  assert.equal(opzioniConnessione(OSPITATO, { VINEA_DB_CA_PEM: "ciao" }).ok, false);
  assert.equal(opzioniConnessione(OSPITATO, { VINEA_DB_CA_PEM: `${CERT}-----BEGIN PRIVATE KEY-----\nx\n-----END PRIVATE KEY-----` }).ok, false);
  assert.equal(opzioniConnessione(`${OSPITATO}&sslrootcert=x`, { VINEA_DB_CA_PEM: CERT }).ok, false);
  assert.equal(opzioniConnessione(OSPITATO.replace("verify-full", "require"), { VINEA_DB_CA_PEM: CERT }).ok, false);
});

test("loopback di sviluppo senza TLS; un ruolo amministrativo resta rifiutato anche con la CA", () => {
  const locale = opzioniConnessione("postgresql://vinea_agent_x:y@127.0.0.1:54322/postgres", {});
  assert.equal(locale.ok, true);
  assert.equal(locale.opzioni.tls, undefined);
  assert.equal(opzioniConnessione("postgresql://postgres.ref:y@aws-0.pooler.supabase.com:5432/postgres?sslmode=verify-full", { VINEA_DB_CA_PEM: CERT }).ok, false);
});

const soglie = { giroMinuti: 30, sentinelMinuti: 120 };

test("osservatore: verde solo con entrambi i numeri recenti; assenza, ritardo o forma inattesa sono rossi", () => {
  assert.deepEqual(valutaHeartbeat({ minuti_dall_ultimo_giro_pianificato: 3, minuti_dall_ultima_sentinel: 40, sentinel_non_eseguiti: 0 }, soglie), { verde: true, motivi: [] });
  assert.deepEqual(valutaHeartbeat({ minuti_dall_ultimo_giro_pianificato: 31, minuti_dall_ultima_sentinel: 40, sentinel_non_eseguiti: 0 }, soglie).motivi, ["scheduler_in_ritardo"]);
  assert.deepEqual(valutaHeartbeat({ minuti_dall_ultimo_giro_pianificato: null, minuti_dall_ultima_sentinel: null }, soglie).motivi,
    ["scheduler_mai_eseguito", "sentinel_mai_eseguita"]);
  assert.equal(valutaHeartbeat({}, soglie).verde, false);
  assert.equal(valutaHeartbeat(null, soglie).verde, false);
  assert.equal(valutaHeartbeat({ minuti_dall_ultimo_giro_pianificato: "0", minuti_dall_ultima_sentinel: 0 }, soglie).verde, false);
});

test("osservatore: un giro manuale recente e un ultimo Sentinel parziale non danno verde", () => {
  const parziale = {
    minuti_dall_ultimo_giro: 0, minuti_dall_ultimo_giro_pianificato: null,
    minuti_dall_ultima_sentinel: 0, sentinel_non_eseguiti: 1,
  };
  assert.deepEqual(valutaHeartbeat(parziale).motivi, ["scheduler_mai_eseguito", "sentinel_parziale"]);
});
