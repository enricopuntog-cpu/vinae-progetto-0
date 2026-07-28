"use client";

import { usePathname, useRouter } from "next/navigation";
import { useEffect } from "react";
import { useVinea } from "@/lib/vinea-store";

/**
 * Guardia di dichiarazione età.
 *
 * REGOLA UNIVERSALE, non specifica di un metodo di accesso: qualunque
 * sessione autenticata il cui profilo non ha una data di nascita salvata
 * viene rimandata a /completa-profilo prima di poter usare il resto del
 * sito. Non si guarda mai come l'utente è entrato — email, magic link,
 * Google o Facebook sono trattati allo stesso modo. L'accesso social è
 * semplicemente il caso in cui la cosa capita più spesso, perché salta il
 * form email e con esso il banner età, ma non è l'unico contemplato: dopo
 * che `profiles.dob` è diventata annullabile, un profilo email privo di
 * data ricade nella stessa guardia.
 *
 * Volutamente NON blocca gli utenti anonimi: la navigazione da ospite resta
 * quella di sempre, come nelle fasi precedenti.
 */

// Percorsi raggiungibili anche con il profilo incompleto: la schermata di
// completamento stessa, e le pagine di autenticazione (altrimenti non si
// potrebbe uscire o rientrare con un altro account).
const PERCORSI_CONSENTITI = ["/completa-profilo", "/accedi", "/registrati", "/auth"];

export function AgeGate() {
  const pathname = usePathname();
  const router = useRouter();
  const { authUser, authLoading, authStatoEta } = useVinea();

  useEffect(() => {
    if (authLoading) return;
    if (!authUser) return;
    // "sconosciuto" copre sia la lettura non ancora conclusa sia un errore di
    // lettura: in entrambi i casi non blocchiamo l'utente su un dato che non
    // abbiamo verificato.
    if (authStatoEta !== "da_completare") return;
    if (PERCORSI_CONSENTITI.some((p) => pathname === p || pathname.startsWith(`${p}/`))) return;

    router.replace("/completa-profilo");
  }, [authUser, authLoading, authStatoEta, pathname, router]);

  return null;
}
