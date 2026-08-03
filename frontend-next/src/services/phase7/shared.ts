import type { Result } from "@/services/types";

type ServiceError = { code?: string; message?: string };

const readableCodes = new Set(["P0001", "42501", "23505", "22023", "PGRST"]);

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

export const noClient = <T>(): Result<T> => ({
  ok: false,
  error: "Connessione a Supabase non configurata.",
});
