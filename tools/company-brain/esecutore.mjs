#!/usr/bin/env bun
// WI-016 — esecuzione AUTONOMA di un worker su un ospite qualunque: un lotto ogni N minuti, finche non lo si ferma.
// Predisposto e NON distribuito: nessun ospite e stato scelto. Spento per difetto.
//
//   VINEA_WORKER_ENABLED=true VINEA_AGENT_DATABASE_URL=… VINEA_DB_CA_PEM=… VINEA_WORKER_INTERVAL_MINUTES=15 \
//       bun tools/company-brain/esecutore.mjs
//
// Nessuna chiamata AI e nessuna chiave amministrativa. Se l'esecutore muore, Sentinel lo vede quando restano task in
// coda che nessuno chiede (`esecutore_assente`); l'ospite lo vede perche il processo esce con codice 1.
import { cicloPeriodico, intervalloMs } from "./lib/ciclo.mjs";
import { opzioniConnessione } from "./lib/connessione.mjs";
import { databaseDelWorker, eseguiLotto } from "./lib/worker.mjs";

const dire = (corpo) => console.log(JSON.stringify(corpo));
const esci = (codice, corpo) => {
  dire(corpo);
  process.exit(codice);
};

if (process.env.VINEA_WORKER_ENABLED !== "true") esci(2, { esito: "disattivato" });
const intervallo = intervalloMs(process.env.VINEA_WORKER_INTERVAL_MINUTES);
if (intervallo === null) esci(2, { esito: "rifiutato", motivo: "VINEA_WORKER_INTERVAL_MINUTES da 5 a 1440" });
const connessione = opzioniConnessione(process.env.VINEA_AGENT_DATABASE_URL ?? "");
if (!connessione.ok) esci(2, { esito: "rifiutato", motivo: connessione.motivo });

let attivo = true;
let sveglia = () => {};
for (const segnale of ["SIGINT", "SIGTERM"]) {
  process.on(segnale, () => {
    attivo = false;
    sveglia();
  });
}

const esito = await cicloPeriodico({
  continua: () => attivo,
  intervallo,
  attendi: (ms) =>
    new Promise((risolvi) => {
      const timer = setTimeout(risolvi, ms);
      sveglia = () => {
        clearTimeout(timer);
        risolvi();
      };
    }),
  // una connessione per giro: fra un giro e l'altro non resta nessuna sessione aperta
  giro: async () => {
    const sql = new Bun.SQL({ ...connessione.opzioni, max: 1, connectionTimeout: 15 });
    let scadenza;
    try {
      const giri = await Promise.race([
        eseguiLotto(databaseDelWorker(sql), 5),
        new Promise((_, rifiuta) => {
          scadenza = setTimeout(() => rifiuta(new Error("scaduto")), 4 * 60 * 1000);
        }),
      ]);
      dire({ esito: "giro", giri });
      if (giri.some((g) => g.esito === "errore")) throw new Error("task_in_errore");
    } catch (errore) {
      const codice = String(errore?.errno ?? errore?.code ?? "");
      dire({ esito: "giro_fallito", codice: /^[0-9A-Z]{5}$/.test(codice) ? codice : "giro" });
      throw errore;
    } finally {
      clearTimeout(scadenza);
      await sql.end().catch(() => {});
    }
  },
});
esci(esito.esito === "arrestato" ? 0 : 1, esito);
