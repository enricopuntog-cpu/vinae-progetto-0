import { FLUSSO_ACCESSO } from "@/lib/auth/link-email-auth";
import { gestoreLinkEmail } from "@/lib/auth/link-email-route";

/**
 * Magic link: `?token_hash=…&type=magiclink`, verificato dal server e valido
 * in qualunque browser. Successo → `next` validato del link (o `/home`);
 * errore → `/accedi` con il motivo. Vedi `lib/auth/link-email-auth.ts`.
 */
export const GET = gestoreLinkEmail(FLUSSO_ACCESSO);
