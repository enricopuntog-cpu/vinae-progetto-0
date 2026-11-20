"use client";

import { Sparkles } from "lucide-react";
import { AI_UI } from "@/config/features";
import { richiediSommelier, type ContestoUi } from "@/lib/phase10/sommelier-contesto-ui";

/**
 * WI-004 — pulsante contestuale che apre il Sommelier esistente su un contesto.
 *
 * Non chiama nessun servizio e non concede nessun consenso: dice al pannello
 * COSA l'utente vuole consultare. La lettura la fa il server, e per la Cantina
 * serve ancora un gesto esplicito dentro il pannello.
 *
 * Compare solo dove il pannello Sommelier esiste (stessa flag UI del launcher):
 * un pulsante senza nessuno che lo ascolti non deve esistere. Con le azioni AI
 * spente il pannello si apre ugualmente e, all'invio, mostra l'avviso della Beta.
 */
export function ChiediAlSommelier({
  contesto,
  etichetta,
  testId,
  className = "",
}: {
  contesto: ContestoUi;
  etichetta: string;
  testId: string;
  className?: string;
}) {
  if (!AI_UI.sommelier) return null;
  return (
    <button
      type="button"
      data-testid={testId}
      onClick={() => richiediSommelier(contesto)}
      className={`inline-flex items-center gap-1.5 rounded-full border border-bordeaux/30 bg-bordeaux/5 px-3 py-1.5 text-xs font-medium text-bordeaux transition hover:border-bordeaux hover:bg-bordeaux/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-bordeaux/40 ${className}`}
    >
      <Sparkles className="h-3.5 w-3.5" aria-hidden />
      {etichetta}
    </button>
  );
}
