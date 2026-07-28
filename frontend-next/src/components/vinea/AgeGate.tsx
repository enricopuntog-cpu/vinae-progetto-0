"use client";

import { usePathname, useRouter } from "next/navigation";
import { useEffect } from "react";
import { useVinea } from "@/lib/vinea-store";

/**
 * Guardia di dichiarazione età (Fase 5b, punto 4).
 *
 * Chi entra via Google/Facebook salta il form di registrazione email e con
 * esso il banner età: il profilo esiste senza `dob`. Qui, appena la sessione
 * è nota e il profilo risulta incompleto, si viene rimandati a
 * /completa-profilo prima di poter usare il resto del sito.
 *
 * Volutamente NON blocca gli utenti anonimi: la navigazione da ospite resta
 * quella di sempre, come nelle fasi precedenti. Interviene solo su una
 * sessione autenticata il cui profilo è privo di data di nascita.
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
