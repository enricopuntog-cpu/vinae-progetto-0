import type { DemoRuolo } from "@/lib/store/auth-domain";

type SessioneMinima = { userId: string; email?: string | null };

export const ruoloDaSessione = (
  authUser: SessioneMinima | null,
  ruoli: readonly string[],
): DemoRuolo => {
  if (!authUser) return "guest";
  return ruoli.includes("admin") ? "admin" : "user";
};

/**
 * D10. Il solo predicato che l'Area Admin ha diritto di consultare.
 *
 * Esiste separato da `ruoloDaSessione` perché i due rispondono a domande
 * diverse. `ruoloDaSessione` produce il `DemoRuolo` della shell, che con lo
 * switcher demo acceso viene **sostituito** dal ruolo scelto a mano: è la
 * variabile giusta per decidere che cosa mostrare in una demo, e quella
 * sbagliata per decidere chi entra in moderazione. Questo predicato non passa
 * mai da lì — legge i ruoli reali, e basta.
 *
 * Non è comunque un confine di fiducia: il confine è `user_roles`, letto dalle
 * viste `moderation_*` e dal controllo in testa a ogni RPC di moderazione.
 * Questa funzione decide che cosa il browser mostra a chi non passerà mai quel
 * controllo — cioè evita di presentare come guasta una porta che è chiusa.
 */
export const eAdminReale = (ruoli: readonly string[]): boolean => ruoli.includes("admin");
