// WI-016 — dai controlli che i workflow GIA eseguono ai segnali del Company Brain. Solo stato, ora, riferimento e
// conteggi: nessun log, nessun corpo di risposta. Una sorgente che non si legge e «sconosciuto», mai «ok».

const segnale = (fonte, evento, stato, osservato, riferimento) => ({ fonte, evento, stato, osservato, riferimento, conteggi: {} });

/** `trovati` sono i codici di `checkLiveness` del controllo tecnico esistente. */
export function segnaleSalute(trovati, quando, evento = `salute:${quando.getTime()}`, riferimento = null) {
  const stato = trovati.length === 0 ? "ok" : trovati.every((c) => c === "next_invalid_health") ? "degradato" : "guasto";
  return segnale("app_health", evento, stato, quando.toISOString(), riferimento);
}

/** L'ultima corsa CONCLUSA della CI su `main`; senza corse non esiste un segnale. */
export function segnaleCi(corse) {
  const ultima = (Array.isArray(corse) ? corse : [])
    .filter((c) => c.head_branch === "main" && c.status === "completed")
    .sort((a, b) => Date.parse(b.updated_at) - Date.parse(a.updated_at))[0];
  if (!ultima) return null;
  const stato = ultima.conclusion === "success" ? "ok" : ultima.conclusion === "failure" || ultima.conclusion === "timed_out" ? "guasto" : "sconosciuto";
  return segnale("ci_main", `ci:${ultima.id}:${ultima.run_attempt}`, stato, ultima.updated_at, ultima.html_url);
}

const STATO_JOB = { success: "ok", failure: "guasto" };

export async function raccogliSegnali({ quando, esecuzione, riferimento, esitoHeartbeat, salute, corse }) {
  const ora = quando.toISOString();
  const segnali = [
    segnale("technical_heartbeat", `heartbeat:${esecuzione}`, STATO_JOB[esitoHeartbeat] ?? "sconosciuto", ora, riferimento),
  ];
  try {
    segnali.push(segnaleSalute(await salute(), quando, `salute:${esecuzione}`, riferimento));
  } catch {
    segnali.push(segnale("app_health", `salute:${esecuzione}`, "sconosciuto", ora, riferimento));
  }
  try {
    const ci = segnaleCi(await corse());
    if (ci) segnali.push(ci);
  } catch {
    segnali.push(segnale("ci_main", `ci:${esecuzione}`, "sconosciuto", ora, riferimento));
  }
  return segnali;
}
