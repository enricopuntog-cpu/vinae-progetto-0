// WI-016 — acquisizione di ricerca, segnali ed esecuzione periodica: regole pure, senza database e senza rete.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { acquisisci, leggiElementi, percorsoAmmesso } from "../lib/acquisizione.mjs";
import { cicloPeriodico, intervalloMs } from "../lib/ciclo.mjs";
import { raccogliSegnali, segnaleCi, segnaleSalute } from "../lib/segnali.mjs";

const elemento = (o = {}) => ({
  soggetto: "wine", soggetto_id: "11111111-1111-4111-8111-111111111111", attributo: "grapes", valore: ["Nebbiolo"],
  riferimento: "https://consorzio.test/scheda/1", acquisita: "2026-11-26T10:00:00Z", attendibilita: 4, ...o,
});
const righe = (...v) => v.map((x) => (typeof x === "string" ? x : JSON.stringify(x))).join("\n");

test("acquisizione: una riga per elemento, campi esattamente chiusi; la riga errata si scarta con il solo numero", () => {
  const { fonte: _fonte, ...senzaFonte } = { fonte: "x", ...elemento() };
  const letto = leggiElementi(righe(senzaFonte, "", "non json", elemento({ fonte: "SCELTA-DAL-FILE" }), { soggetto: "wine" }, "[1]"));
  assert.equal(letto.elementi.length, 1);
  assert.deepEqual(letto.scartati, [
    { riga: 3, motivo: "json_non_valido" },
    { riga: 4, motivo: "campi_non_ammessi" },
    { riga: 5, motivo: "campi_mancanti" },
    { riga: 6, motivo: "non_un_oggetto" },
  ]);
  assert.ok(!JSON.stringify(letto.scartati).includes("SCELTA"));
});

test("acquisizione: tetti sul file e sulla riga; nessun indirizzo di rete come sorgente", () => {
  assert.throws(() => leggiElementi(righe(...Array.from({ length: 1001 }, () => elemento()))), /troppe_righe/);
  assert.equal(leggiElementi(righe(elemento({ valore: ["x".repeat(9000)] }))).scartati[0].motivo, "riga_troppo_lunga");
  assert.equal(percorsoAmmesso("esportazione.jsonl"), true);
  for (const p of ["https://sito.test/dati.jsonl", "HTTP://x", "ftp://x/y.jsonl", "file:///etc/passwd", "//server/condivisione.jsonl", "dati.csv", ""]) {
    assert.equal(percorsoAmmesso(p), false, p);
  }
});

test("acquisizione: lotti di 20, somme degli esiti, indici riportati al file; al primo errore si ferma", async () => {
  const lotti = [];
  const ok = await acquisisci(async (lotto) => {
    lotti.push(lotto.length);
    return { nuovi: lotto.length - 1, gia_visti: 1, rifiutati: lotti.length === 2 ? [{ indice: 0, codice: "P0001" }] : [] };
  }, Array.from({ length: 45 }, () => elemento()));
  assert.deepEqual(lotti, [20, 20, 5]);
  assert.deepEqual(ok, { esito: "completato", inviati: 45, nuovi: 42, gia_visti: 3, rifiutati: [{ elemento: 20, codice: "P0001" }] });
  let n = 0;
  const ko = await acquisisci(async () => {
    if (++n === 2) throw Object.assign(new Error("sospesa"), { errno: "42501" });
    return { nuovi: 20, gia_visti: 0, rifiutati: [] };
  }, Array.from({ length: 60 }, () => elemento()));
  assert.deepEqual(ko, { esito: "interrotto", codice: "42501", inviati: 20, nuovi: 20, gia_visti: 0, rifiutati: [] });
});

test("il file di esempio rispetta il contratto", () => {
  const letto = leggiElementi(readFileSync(new URL("../fixtures/ricerca-esempio.jsonl", import.meta.url), "utf8"));
  assert.equal(letto.scartati.length, 0);
  assert.ok(letto.elementi.length >= 2);
});

const QUANDO = new Date("2026-11-27T12:00:00Z");

test("segnali: la salute dell'applicazione distingue risposta errata da irraggiungibile", () => {
  assert.equal(segnaleSalute([], QUANDO).stato, "ok");
  assert.equal(segnaleSalute(["next_invalid_health"], QUANDO).stato, "degradato");
  assert.equal(segnaleSalute(["next_unreachable"], QUANDO).stato, "guasto");
  assert.equal(segnaleSalute(["next_unavailable"], QUANDO).stato, "guasto");
});

test("segnali CI: conta l'ultima corsa CONCLUSA su main; senza corse non c'e un verde", () => {
  const corsa = (o) => ({ id: 1, run_attempt: 1, head_branch: "main", status: "completed", conclusion: "success",
    updated_at: "2026-11-27T10:00:00Z", html_url: "https://github.com/o/r/actions/runs/1", ...o });
  assert.equal(segnaleCi([corsa({})]).stato, "ok");
  assert.equal(segnaleCi([corsa({ id: 2, status: "in_progress", conclusion: null }), corsa({ conclusion: "failure" })]).stato, "guasto");
  assert.equal(segnaleCi([corsa({ conclusion: "cancelled" })]).stato, "sconosciuto");
  assert.equal(segnaleCi([corsa({ head_branch: "feature/x" })]), null);
  assert.equal(segnaleCi([]), null);
  assert.equal(segnaleCi([corsa({ id: 7, run_attempt: 2 })]).evento, "ci:7:2");
});

test("segnali: una sorgente che non si legge diventa 'sconosciuto', mai 'ok', e non ferma le altre", async () => {
  const segnali = await raccogliSegnali({
    quando: QUANDO,
    esecuzione: "run:5:1",
    riferimento: "https://github.com/o/r/actions/runs/5",
    esitoHeartbeat: "failure",
    salute: async () => [],
    corse: async () => {
      throw new Error("api");
    },
  });
  assert.deepEqual(segnali.map((s) => [s.fonte, s.stato]), [
    ["technical_heartbeat", "guasto"], ["app_health", "ok"], ["ci_main", "sconosciuto"],
  ]);
  for (const s of segnali) {
    assert.match(s.evento, /^[A-Za-z0-9_:.-]{1,120}$/);
    assert.deepEqual(Object.keys(s).sort(), ["conteggi", "evento", "fonte", "osservato", "riferimento", "stato"]);
  }
});

test("esecuzione periodica: l'intervallo ha limiti; un errore isolato non ferma, errori di fila si", async () => {
  assert.equal(intervalloMs("10"), 600_000);
  for (const v of ["", "0", "4", "1441", "abc", undefined]) assert.equal(intervalloMs(v), null, String(v));
  const esiti = [false, true, false, false, false, true];
  let giri = 0;
  const attese = [];
  const r = await cicloPeriodico({
    giro: async () => {
      const ok = esiti[giri++];
      if (!ok) throw new Error("giro");
    },
    attendi: async (ms) => void attese.push(ms),
    intervallo: 1000,
    maxErroriDiFila: 3,
    continua: () => true,
  });
  assert.deepEqual(r, { esito: "troppi_errori", giri: 5 });
  assert.equal(attese.length, 4);
});

test("esecuzione periodica: la richiesta di arresto chiude fra un giro e l'altro", async () => {
  let giri = 0;
  const r = await cicloPeriodico({
    giro: async () => void giri++,
    attendi: async () => {},
    intervallo: 1000,
    maxErroriDiFila: 3,
    continua: () => giri < 2,
  });
  assert.deepEqual(r, { esito: "arrestato", giri: 2 });
});
