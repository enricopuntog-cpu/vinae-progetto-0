"use client";

import { Check, Circle } from "lucide-react";
import {
  MESSAGGIO_PASSWORD_TROPPO_LUNGA,
  REGOLE_GENERATORE_PASSWORD,
  REQUISITI_PASSWORD,
  valutaPassword,
} from "@/lib/auth/requisiti-password";

/**
 * Attributi comuni del campo «nuova password» nelle tre superfici.
 *
 * - `autoComplete="new-password"`: i password manager propongono di generare e
 *   salvare, non di riempire con una password già esistente.
 * - `passwordrules`: il generatore di Safari produce una password che rispetta
 *   la policy. Non è nei tipi di React, quindi passa come attributo libero.
 * - `aria-describedby`: lo screen reader legge i requisiti insieme al campo.
 *
 * Nessun gestore `onPaste`/`onCopy`: incollare una password generata è il
 * comportamento che vogliamo, non un rischio da impedire.
 */
export const attributiPasswordNuova = (idRequisiti: string) =>
  ({
    autoComplete: "new-password",
    "aria-describedby": idRequisiti,
    passwordrules: REGOLE_GENERATORE_PASSWORD,
  }) as const;

/**
 * Lista dei cinque requisiti, aggiornata a ogni carattere digitato o incollato.
 *
 * Ogni voce dice il proprio stato con il testo e non solo con il colore: la
 * spunta e il cerchio sono decorativi, «soddisfatto»/«da soddisfare» è letto
 * dagli screen reader. Il riepilogo «N di 5» è una regione `polite`, così chi
 * non vede la lista sa quando la password è pronta senza essere interrotto a
 * ogni tasto da cinque annunci.
 */
export function RequisitiPassword({
  password,
  id,
  titolo = "La password deve contenere:",
}: {
  password: string;
  /** Collegato con `aria-describedby` al campo password. */
  id: string;
  titolo?: string;
}) {
  const valutazione = valutaPassword(password);
  return (
    <div id={id} data-testid="requisiti-password" className="mt-2 space-y-1.5">
      <p className="text-xs text-muted-foreground">{titolo}</p>
      <ul className="grid gap-1 sm:grid-cols-2">
        {valutazione.requisiti.map((r) => (
          <li
            key={r.id}
            data-testid={`requisito-${r.id}`}
            data-soddisfatto={r.soddisfatto ? "true" : "false"}
            className={`flex min-w-0 items-start gap-1.5 text-xs ${
              r.soddisfatto ? "text-emerald-800" : "text-muted-foreground"
            }`}
          >
            {r.soddisfatto ? (
              <Check className="mt-px h-3.5 w-3.5 shrink-0" aria-hidden />
            ) : (
              <Circle className="mt-px h-3.5 w-3.5 shrink-0" aria-hidden />
            )}
            <span className="min-w-0 break-words">
              {r.etichetta}
              <span className="sr-only">{r.soddisfatto ? ": soddisfatto" : ": da soddisfare"}</span>
            </span>
          </li>
        ))}
      </ul>
      <p className="sr-only" aria-live="polite" data-testid="requisiti-riepilogo">
        {`Requisiti soddisfatti: ${valutazione.soddisfatti} di ${REQUISITI_PASSWORD.length}.`}
      </p>
      {valutazione.troppoLunga && (
        <p role="alert" data-testid="password-troppo-lunga" className="text-xs text-bordeaux">
          {MESSAGGIO_PASSWORD_TROPPO_LUNGA}
        </p>
      )}
    </div>
  );
}
