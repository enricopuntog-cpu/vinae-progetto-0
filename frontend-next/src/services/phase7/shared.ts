import type { Result } from "@/services/types";

type ServiceError = { code?: string; message?: string };

// `reauth_required` arriva come `rate_limit_exceeded` nel 12b: un `raise sqlstate
// 'PGRST'` con un messaggio JSON che PostgREST traduce in `code` + testo
// italiano scritto per l'utente (qui 403, vedi
// private.autenticazione_recente_richiedi).
const readableCodes = new Set(["P0001", "42501", "23505", "22023", "PGRST", "reauth_required"]);

export const serviceError = <T>(operation: string, error: ServiceError): Result<T> => {
  console.error(`[Phase7] ${operation} fallita`, { code: error.code });
  return {
    ok: false,
    error:
      error.code && readableCodes.has(error.code) && error.message
        ? error.message
        : "Non è stato possibile completare l'operazione. Riprova.",
  };
};

/**
 * Il saldo di questa famiglia è reso su /account, e lì il nome del provider non
 * è un'informazione per chi legge: è un dettaglio di installazione. Resta il
 * fatto — adesso non si può — senza la mappa di come è fatto il sistema.
 */
export const noClient = <T>(): Result<T> => ({
  ok: false,
  error: "Il servizio non è disponibile in questo momento. Riprova fra qualche istante.",
});
