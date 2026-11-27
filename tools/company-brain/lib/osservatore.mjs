// WI-016 — giudizio dell'osservatore INDIPENDENTE sull'heartbeat del brain (`brain.heartbeat_minimo()`).
// Un controllo che non si legge o che ha una forma inattesa e rosso: l'assenza di prove non e un verde.

export const SOGLIE = { giroMinuti: 30, sentinelMinuti: 120 };

export function valutaHeartbeat(lettura, soglie = SOGLIE) {
  const motivi = [];
  const controlla = (chiave, limite, mai, ritardo) => {
    const v = lettura?.[chiave];
    if (v === null) motivi.push(mai);
    else if (!Number.isInteger(v) || v < 0) motivi.push("lettura_non_valida");
    else if (v > limite) motivi.push(ritardo);
  };
  controlla("minuti_dall_ultimo_giro", soglie.giroMinuti, "scheduler_mai_eseguito", "scheduler_in_ritardo");
  controlla("minuti_dall_ultima_sentinel", soglie.sentinelMinuti, "sentinel_mai_eseguita", "sentinel_in_ritardo");
  return { verde: motivi.length === 0, motivi: [...new Set(motivi)] };
}
