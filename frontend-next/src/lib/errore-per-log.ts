/**
 * Cosa di un errore può finire nei log: un codice, mai l'oggetto intero. `message`, `details` e
 * `hint` di PostgREST riportano valori delle righe, e un testo arrivato da una query string può
 * contenere ritorni a capo che falsificano le righe di log (GAP-018).
 */
const CODICE_AMMESSO = /^[A-Za-z0-9_.-]{1,40}$/;

const campo = (errore: object, nome: string): unknown => (errore as Record<string, unknown>)[nome];

export const codiceErrore = (errore: unknown): string => {
  if (errore === null || typeof errore !== "object") return "sconosciuto";
  for (const nome of ["code", "statusCode", "status", "name"]) {
    const valore = campo(errore, nome);
    if (typeof valore === "number") return String(valore);
    if (typeof valore === "string" && CODICE_AMMESSO.test(valore)) return valore;
  }
  return "sconosciuto";
};
