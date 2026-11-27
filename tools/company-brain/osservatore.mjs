#!/usr/bin/env bun
// WI-016 — controllo ESTERNO e indipendente dello scheduler. Da eseguire su un esecutore diverso da Supabase (e
// preferibilmente da GitHub), con un login membro SOLO di `brain_monitor_read`. Legge due numeri e basta.
// Uscita: 0 = verde; 1 = rosso (fermo, in ritardo o illeggibile); 2 = non configurato (che NON e un verde).
// Non invia notifiche: il canale di avviso e dell'esecutore che lo lancia, e non e ancora scelto.
//
//   VINEA_OBSERVER_DATABASE_URL=… VINEA_DB_CA_PEM=… bun tools/company-brain/osservatore.mjs
import { opzioniConnessione } from "./lib/connessione.mjs";
import { valutaHeartbeat } from "./lib/osservatore.mjs";

const esci = (codice, corpo) => {
  console.log(JSON.stringify(corpo));
  process.exit(codice);
};

const url = process.env.VINEA_OBSERVER_DATABASE_URL ?? "";
if (!url) esci(2, { esito: "non_configurato" });
const connessione = opzioniConnessione(url);
if (!connessione.ok) esci(2, { esito: "rifiutato", motivo: connessione.motivo });

const scadenza = setTimeout(() => esci(1, { esito: "rosso", motivi: ["lettura_scaduta"] }), 60 * 1000);
try {
  const sql = new Bun.SQL({ ...connessione.opzioni, max: 1, connectionTimeout: 15 });
  const [riga] = await sql`select brain.heartbeat_minimo()::text as h`;
  await sql.end();
  clearTimeout(scadenza);
  const giudizio = valutaHeartbeat(JSON.parse(riga.h));
  esci(giudizio.verde ? 0 : 1, { esito: giudizio.verde ? "verde" : "rosso", motivi: giudizio.motivi });
} catch (errore) {
  clearTimeout(scadenza);
  const codice = String(errore?.errno ?? errore?.code ?? "");
  esci(1, { esito: "rosso", motivi: ["lettura_fallita"], codice: /^[0-9A-Z]{5}$/.test(codice) ? codice : "connessione" });
}
