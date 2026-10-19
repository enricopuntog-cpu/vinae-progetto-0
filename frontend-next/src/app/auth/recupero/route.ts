import { FLUSSO_RECUPERO } from "@/lib/auth/link-email-auth";
import { gestoreLinkEmail } from "@/lib/auth/link-email-route";

/**
 * Link di recupero password: `?token_hash=…&type=recovery`, verificato dal
 * server e valido in qualunque browser. Successo → `/reimposta-password` con la
 * sessione di recupero nei cookie; errore → stessa pagina con il motivo.
 * Vedi `lib/auth/link-email-auth.ts`.
 */
export const GET = gestoreLinkEmail(FLUSSO_RECUPERO);
