#!/usr/bin/env bun
// WI-016 — raccoglie heartbeat tecnico, salute dell'applicazione e stato della CI di main e li consegna al brain con la
// credenziale ristretta `brain_ingest`. Spento per difetto: senza VINEA_INGEST_DATABASE_URL non legge e non invia nulla.
// Uscita: 0 = consegnati o non configurato (dichiarato); 1 = almeno un segnale non consegnato; 2 = rifiutato.
import { checkLiveness, createApi } from "../../.github/scripts/technical-heartbeat.mjs";
import { opzioniConnessione } from "./lib/connessione.mjs";
import { inviaSegnale } from "./lib/invio.mjs";
import { raccogliSegnali } from "./lib/segnali.mjs";

const esci = (codice, corpo) => {
  console.log(JSON.stringify(corpo));
  process.exit(codice);
};

const url = process.env.VINEA_INGEST_DATABASE_URL ?? "";
if (!url) esci(0, { esito: "non_configurato" });
const connessione = opzioniConnessione(url);
if (!connessione.ok) esci(2, { esito: "rifiutato", motivo: connessione.motivo });

const scadenza = setTimeout(() => esci(1, { esito: "scaduto" }), 90 * 1000);
const env = process.env;
const riferimento = env.GITHUB_REPOSITORY && env.GITHUB_RUN_ID
  ? `https://github.com/${env.GITHUB_REPOSITORY}/actions/runs/${env.GITHUB_RUN_ID}`
  : null;
const segnali = await raccogliSegnali({
  quando: new Date(),
  esecuzione: `run:${env.GITHUB_RUN_ID ?? Date.now()}:${env.GITHUB_RUN_ATTEMPT ?? 1}`,
  riferimento,
  esitoHeartbeat: env.HEARTBEAT_RESULT ?? "",
  salute: () => checkLiveness(),
  corse: async () => (await createApi(env)("GET", "/actions/workflows/ci.yml/runs?branch=main&per_page=10")).workflow_runs,
});

const esiti = [];
try {
  const sql = new Bun.SQL({ ...connessione.opzioni, max: 1, connectionTimeout: 15 });
  for (const s of segnali) {
    try {
      esiti.push({ fonte: s.fonte, stato: s.stato, esito: await inviaSegnale(sql, s) });
    } catch (errore) {
      const codice = String(errore?.errno ?? errore?.code ?? "");
      esiti.push({ fonte: s.fonte, stato: s.stato, errore: /^[0-9A-Z]{5}$/.test(codice) ? codice : "invio" });
    }
  }
  await sql.end();
} catch {
  clearTimeout(scadenza);
  esci(1, { esito: "errore", codice: "connessione" });
}
clearTimeout(scadenza);
esci(esiti.some((e) => e.errore) ? 1 : 0, { esito: "completato", segnali: esiti });
