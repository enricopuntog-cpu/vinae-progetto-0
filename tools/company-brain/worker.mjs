#!/usr/bin/env bun
// WI-015 — avvio di un worker del Company Brain (Catalog Manager, Data Quality o Technical Monitor: lo decide la
// CREDENZIALE, non un parametro). Spento per difetto.
//
//   VINEA_WORKER_ENABLED=true VINEA_AGENT_DATABASE_URL=… bun tools/company-brain/worker.mjs [--max 5]
//
// Uscita: una riga JSON con gli esiti; nessun dato del dominio e nessuna credenziale.
import { controllaConnessione } from "./lib/connessione.mjs";
import { databaseDelWorker, eseguiLotto } from "./lib/worker.mjs";

const esci = (codice, corpo) => {
  console.log(JSON.stringify(corpo));
  process.exit(codice);
};

if (process.env.VINEA_WORKER_ENABLED !== "true") esci(2, { esito: "disattivato" });
const url = process.env.VINEA_AGENT_DATABASE_URL ?? "";
const controllo = controllaConnessione(url);
if (!controllo.ok) esci(2, { esito: "rifiutato", motivo: controllo.motivo });

const indice = process.argv.indexOf("--max");
const massimo = indice > 0 ? Number(process.argv[indice + 1]) : 1;

const sql = new Bun.SQL(url, { max: 1, connectionTimeout: 15 });
const scadenza = setTimeout(() => esci(3, { esito: "scaduto" }), 5 * 60 * 1000);
try {
  const giri = await eseguiLotto(databaseDelWorker(sql), massimo);
  clearTimeout(scadenza);
  await sql.end();
  esci(giri.some((g) => g.esito === "errore") ? 1 : 0, { esito: "completato", giri });
} catch (errore) {
  clearTimeout(scadenza);
  const codice = String(errore?.errno ?? errore?.code ?? "");
  esci(1, { esito: "errore", codice: /^[0-9A-Z]{5}$/.test(codice) ? codice : "connessione" });
}
