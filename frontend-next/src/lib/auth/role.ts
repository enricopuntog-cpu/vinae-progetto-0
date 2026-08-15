import type { DemoRuolo } from "@/lib/store/auth-domain";

type SessioneMinima = { userId: string; email?: string | null };

export const ruoloDaSessione = (
  authUser: SessioneMinima | null,
  ruoli: readonly string[],
): DemoRuolo => {
  if (!authUser) return "guest";
  return ruoli.includes("admin") ? "admin" : "user";
};
