// WI-015 — il ciclo di un worker: presa → contesto → analisi → evidenze → proposta (o chiusura consentita).
// L'identita e la sessione del database: qui non si passa nessun nome di agente. Un errore restituisce il task con
// `successo = false` (tentativi limitati dal database) e nel brain finisce solo il codice dell'errore.
import { ANALISI } from "./analisi.mjs";

const codice = (errore) => {
  const grezzo = String(errore?.errno ?? errore?.code ?? "");
  return /^[0-9A-Z]{5}$/.test(grezzo) ? grezzo : "worker";
};

export async function eseguiUnGiro(db, { leaseSecondi = 300, analisi = ANALISI } = {}) {
  const presa = await db.claim(leaseSecondi);
  if (!presa) return { esito: "niente_da_fare" };
  const { task_id: task, lease_token: lease, task_type: tipo } = presa;
  try {
    const analizza = analisi[tipo];
    if (!analizza) throw new Error("tipo_non_gestito");
    const risultato = analizza(await db.context(task, lease));
    for (const e of risultato.evidenze) await db.evidence(task, lease, e.tipo, e.dettaglio);
    if (risultato.chiusura) {
      await db.closeIfAllowed(task, lease);
      return { esito: "chiuso_per_regola", task, tipo };
    }
    const stato = await db.finish(task, lease, true, risultato.proposta);
    return { esito: stato, task, tipo };
  } catch (errore) {
    try {
      await db.finish(task, lease, false, null);
    } catch {
      // lease gia scaduto o agente disabilitato: il database rimettera il task in coda
    }
    return { esito: "errore", task, tipo, codice: codice(errore) };
  }
}

/** Al massimo `massimo` task; si ferma alla coda vuota o al primo errore (nessun ciclo di ritentativi). */
export async function eseguiLotto(db, massimo = 1, opzioni = {}) {
  const limite = Math.min(Math.max(Math.trunc(massimo) || 1, 1), 20);
  const giri = [];
  for (let i = 0; i < limite; i++) {
    const giro = await eseguiUnGiro(db, opzioni);
    if (giro.esito === "niente_da_fare") break;
    giri.push(giro);
    if (giro.esito === "errore") break;
  }
  return giri;
}

/** Adattatore sul client SQL di Bun (`new Bun.SQL(url)`): sole chiamate alle porte dell'agente. */
export function databaseDelWorker(sql) {
  const json = (v) => (typeof v === "string" ? JSON.parse(v) : v);
  return {
    claim: async (secondi) => (await sql`select * from brain.claim_task(${secondi}::integer)`)[0] ?? null,
    context: async (task, lease) =>
      json((await sql`select brain.agent_context(${task}::uuid, ${lease}::uuid)::text as c`)[0].c),
    evidence: async (task, lease, tipo, dettaglio) => {
      await sql`select brain.add_evidence(${task}::uuid, ${lease}::uuid, ${tipo}::text, ${JSON.stringify(dettaglio)}::text::jsonb)`;
    },
    finish: async (task, lease, successo, proposta) =>
      (await sql`select brain.finish_task(${task}::uuid, ${lease}::uuid, ${successo}::boolean,
        ${proposta === null ? null : JSON.stringify(proposta)}::text::jsonb) as s`)[0].s,
    closeIfAllowed: async (task, lease) => {
      await sql`select brain.close_if_allowed(${task}::uuid, ${lease}::uuid)`;
    },
  };
}
