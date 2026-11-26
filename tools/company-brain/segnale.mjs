#!/usr/bin/env bun
// WI-015 — mittente di UN segnale tecnico verso il Company Brain, con la credenziale ristretta `brain_ingest`.
// Solo identificativo dell'evento, stato, ora, riferimento alla prova e conteggi numerici: nessun log, nessun testo.
// Spento per difetto: senza VINEA_INGEST_DATABASE_URL esce con «non configurato» (codice 0, nessun effetto).
//
//   bun tools/company-brain/segnale.mjs --fonte technical_heartbeat --evento run:123 --stato ok \
//       --osservato 2026-12-01T10:00:00Z --riferimento https://github.com/o/r/actions/runs/123 --conteggi '{"findings":0}'
import { controllaConnessione } from "./lib/connessione.mjs";

export function leggiArgomenti(argv) {
  const valori = {};
  for (let i = 0; i < argv.length; i += 2) {
    if (!argv[i]?.startsWith("--") || argv[i + 1] === undefined) throw new Error("argomenti non validi");
    valori[argv[i].slice(2)] = argv[i + 1];
  }
  const { fonte, evento, stato, osservato } = valori;
  if (!fonte || !evento || !["ok", "degradato", "guasto", "sconosciuto"].includes(stato) || Number.isNaN(Date.parse(osservato))) {
    throw new Error("servono --fonte, --evento, --stato e --osservato validi");
  }
  const conteggi = valori.conteggi ? JSON.parse(valori.conteggi) : {};
  if (Object.values(conteggi).some((v) => typeof v !== "number")) throw new Error("i conteggi accettano solo numeri");
  return { fonte, evento, stato, osservato, riferimento: valori.riferimento ?? null, conteggi };
}

if (import.meta.main) {
  const url = process.env.VINEA_INGEST_DATABASE_URL ?? "";
  if (!url) {
    console.log(JSON.stringify({ esito: "non_configurato" }));
    process.exit(0);
  }
  const controllo = controllaConnessione(url);
  if (!controllo.ok) {
    console.log(JSON.stringify({ esito: "rifiutato", motivo: controllo.motivo }));
    process.exit(2);
  }
  try {
    const s = leggiArgomenti(process.argv.slice(2));
    const sql = new Bun.SQL(url, { max: 1, connectionTimeout: 15 });
    const [riga] = await sql`select brain.ingest_signal(${s.fonte}::text, ${s.evento}::text, ${s.stato}::text,
      ${s.osservato}::timestamptz, ${s.riferimento}::text, ${JSON.stringify(s.conteggi)}::text::jsonb) as esito`;
    await sql.end();
    console.log(JSON.stringify({ esito: riga.esito }));
  } catch (errore) {
    const codice = String(errore?.errno ?? errore?.code ?? "");
    console.log(JSON.stringify({ esito: "errore", codice: /^[0-9A-Z]{5}$/.test(codice) ? codice : "invio" }));
    process.exit(1);
  }
}
