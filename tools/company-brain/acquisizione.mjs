#!/usr/bin/env bun
// WI-016 — adattatore di acquisizione per Wine Research. Spento per difetto.
//
//   VINEA_RESEARCH_ENABLED=true VINEA_RESEARCH_DATABASE_URL=… [VINEA_DB_CA_PEM=…] \
//       bun tools/company-brain/acquisizione.mjs --file esportazione.jsonl [--prova]
//
// `--prova` legge e valida il file senza connettersi. Uscita: una riga JSON con soli conteggi, numeri di riga e codici.
// 0 = completato; 1 = interrotto o con righe scartate; 2 = non configurato o rifiutato.
import { createReadStream } from "node:fs";
import { acquisisci, leggiElementi, leggiFileLimitato, percorsoAmmesso } from "./lib/acquisizione.mjs";
import { opzioniConnessione } from "./lib/connessione.mjs";

const esci = (codice, corpo) => {
  console.log(JSON.stringify(corpo));
  process.exit(codice);
};

const indice = process.argv.indexOf("--file");
const percorso = indice > 0 ? process.argv[indice + 1] : "";
if (!percorsoAmmesso(percorso)) esci(2, { esito: "rifiutato", motivo: "serve --file con un percorso locale .jsonl" });

let letto;
try {
  letto = leggiElementi(await leggiFileLimitato(createReadStream(percorso)));
} catch (errore) {
  const motivi = new Map([["troppe_righe", "troppe righe"], ["file_troppo_grande", "file troppo grande"]]);
  esci(2, { esito: "rifiutato", motivo: motivi.get(errore?.message) ?? "file non leggibile" });
}
if (process.argv.includes("--prova")) {
  esci(letto.scartati.length ? 1 : 0, { esito: "prova", validi: letto.elementi.length, scartati: letto.scartati });
}

if (process.env.VINEA_RESEARCH_ENABLED !== "true") esci(2, { esito: "disattivato" });
const connessione = opzioniConnessione(process.env.VINEA_RESEARCH_DATABASE_URL ?? "");
if (!connessione.ok) esci(2, { esito: "rifiutato", motivo: connessione.motivo });
if (letto.elementi.length === 0) esci(letto.scartati.length ? 1 : 0, { esito: "niente_da_inviare", scartati: letto.scartati });

const sql = new Bun.SQL({ ...connessione.opzioni, max: 1, connectionTimeout: 15 });
const scadenza = setTimeout(() => esci(1, { esito: "scaduto" }), 5 * 60 * 1000);
try {
  const esito = await acquisisci(async (lotto) => {
    const [riga] = await sql`select brain.research_ingest(${JSON.stringify(lotto)}::text::jsonb)::text as e`;
    return JSON.parse(riga.e);
  }, letto.elementi);
  clearTimeout(scadenza);
  await sql.end();
  const pulito = esito.esito === "completato" && esito.rifiutati.length === 0 && letto.scartati.length === 0;
  esci(pulito ? 0 : 1, { ...esito, scartati: letto.scartati });
} catch {
  clearTimeout(scadenza);
  esci(1, { esito: "errore", codice: "connessione" });
}
