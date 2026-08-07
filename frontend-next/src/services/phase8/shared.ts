import type { PageCursor, Result } from "@/services/types";

type ServiceError = { code?: string; message?: string };

const readableCodes = new Set(["P0001", "42501", "22023", "PGRST"]);

export const phase8Error = <T>(operation: string, error: ServiceError): Result<T> => {
  console.error(`[Phase8] ${operation} fallita`, { code: error.code });
  return {
    ok: false,
    error:
      error.code && readableCodes.has(error.code) && error.message
        ? error.message
        : "Non e stato possibile completare l'operazione. Riprova.",
  };
};

export const pageCursor = <T extends { id: string; createdAt: string }>(
  rows: T[],
  limit: number,
): PageCursor | null => {
  const last = rows.at(-1);
  return rows.length === limit && last ? { id: last.id, createdAt: last.createdAt } : null;
};

export const noPhase8Client = <T>(): Result<T> => ({
  ok: false,
  error: "Connessione a Supabase non configurata.",
});
