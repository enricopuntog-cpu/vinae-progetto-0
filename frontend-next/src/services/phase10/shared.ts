// Fase 10 — utilita condivise dell'adapter AI.
//
// AiService restituisce Result<T>, come ListingService, OrderService e le altre
// interfacce successive alla convenzione Result. Non segue ModerationService,
// che solleva: quella e piu vecchia della convenzione ed e stata implementata
// cosi' com'era, non presa a modello.

import type { Result } from "@/services/types";

type ServiceError = { code?: string; message?: string };

// Gli stessi codici che la Fase 7 e la Fase 8 considerano leggibili: sono
// quelli che le porte sollevano di proposito con un messaggio destinato
// all'utente.
const readableCodes = new Set(["P0001", "42501", "23505", "22023", "PGRST"]);

export const aiError = <T>(operation: string, error: ServiceError): Result<T> => {
  console.error(`[Phase10] ${operation} fallita`, { code: error.code });
  return {
    ok: false,
    error:
      error.code && readableCodes.has(error.code) && error.message
        ? error.message
        : "Non e stato possibile completare l'operazione. Riprova.",
  };
};

export const noClient = <T>(): Result<T> => ({
  ok: false,
  error: "Connessione a Supabase non configurata.",
});

/**
 * Messaggio da mostrare quando la Edge Function risponde con uno status noto.
 *
 * La decisione 7.5 tiene la mappatura del legacy — 503 fornitore giu', 502
 * risposta inutilizzabile — e il corpo che la function restituisce porta gia'
 * un `error` generico e mai il messaggio del fornitore. Qui non si riscrive
 * quel messaggio: si copre solo il caso in cui non ci sia corpo, che e' quello
 * che succede quando a rispondere e' il gateway e non noi.
 */
export const messaggioDaStatus = (status: number, corpo: unknown): string => {
  const dalCorpo = corpo && typeof corpo === "object" && "error" in corpo
    ? String((corpo as { error?: unknown }).error ?? "")
    : "";
  if (dalCorpo) return dalCorpo;
  if (status === 401) return "Sessione non valida: accedi per usare le funzioni AI.";
  if (status === 403) return "Accesso non consentito.";
  if (status === 429) return "Limite temporaneo delle funzioni AI raggiunto.";
  if (status === 503) return "Il servizio AI non e al momento disponibile.";
  if (status === 502) return "Il servizio AI ha restituito un formato non valido.";
  // 504 senza corpo e' il gateway della piattaforma, non noi: la 7.5 tiene il
  // timeout applicativo un ordine di grandezza sotto proprio per non finire
  // qui, ma se ci si finisce va detto che non e' distinguibile.
  return "Il servizio AI non ha risposto in tempo.";
};

/**
 * Un evento dello stream SSE del Sommelier. Sono i tre che la function emette:
 * un frammento, la chiusura, oppure un errore generico.
 */
export type SommelierEvento =
  | { delta: string }
  | { done: true }
  | { error: string };

/**
 * Divide un buffer SSE nei suoi eventi completi e restituisce il resto non
 * ancora terminato. Esportata perche' e' la parte che decide se un troncamento
 * viene visto come tale, e va provata senza rete.
 */
export const dividiEventiSse = (
  buffer: string,
): { eventi: SommelierEvento[]; resto: string } => {
  const parti = buffer.split("\n\n");
  const resto = parti.pop() ?? "";
  const eventi: SommelierEvento[] = [];
  for (const parte of parti) {
    const riga = parte.trim();
    if (!riga.startsWith("data:")) continue;
    try {
      eventi.push(JSON.parse(riga.slice(5).trim()) as SommelierEvento);
    } catch {
      // Un evento malformato in mezzo allo stream non interrompe la lettura:
      // si scarta e si prosegue, come fa la function con le righe del
      // fornitore.
    }
  }
  return { eventi, resto };
};
