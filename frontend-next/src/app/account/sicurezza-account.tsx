"use client";

import { useState } from "react";
import { KeyRound, Mail } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useVinea } from "@/lib/vinea-store";
import { messaggioErroreAuth, type CodiceErroreAuth } from "@/lib/auth/errori-auth";

/**
 * Sicurezza dell'account: un solo gesto, impostare o cambiare la password.
 *
 * PERCHÉ NON C'È IL CAMPO "PASSWORD ATTUALE". Un account nato con Google non
 * ha mai avuto una password Vinea, quindi non può digitarne una vecchia. E
 * questa pagina non ha modo onesto di sapere quale dei due casi ha davanti:
 * l'unico indizio disponibile lato client sarebbe il provider dell'identità,
 * che è un'euristica — un account può averne più d'una, e averla acquisita
 * dopo. Invece di indovinare, il gesto è lo stesso per tutti: un link alla
 * propria casella di posta, che è la prova che vale in entrambi i casi.
 *
 * Per la stessa ragione la CTA dice "Imposta o cambia": non promette di sapere
 * se una password esiste già.
 *
 * Niente reset amministrativo e nessun privilegio elevato: la richiesta parte
 * dalla sessione dell'utente per il proprio indirizzo, e la password nuova la
 * scrive lui su /reimposta-password.
 */
export default function SicurezzaAccount() {
  const { authUser, authInviaRecuperoPassword } = useVinea();

  const [inCorso, setInCorso] = useState(false);
  const [inviato, setInviato] = useState(false);
  const [errore, setErrore] = useState<CodiceErroreAuth | null>(null);

  const email = authUser?.email ?? null;

  const richiedi = async () => {
    if (inCorso || !email) return;
    setErrore(null);
    setInCorso(true);
    const esito = await authInviaRecuperoPassword(email);
    setInCorso(false);
    if (!esito.ok) {
      setErrore(esito.error);
      return;
    }
    setInviato(true);
  };

  return (
    <div className="rounded-3xl border border-border bg-card p-5 md:p-6">
      <div className="flex items-start gap-3">
        <KeyRound className="mt-0.5 h-5 w-5 shrink-0 text-bordeaux" aria-hidden />
        <div className="min-w-0">
          <h2 className="font-serif text-xl">Sicurezza</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Riceverai un link alla tua email per impostare o modificare la password. Funziona anche
            se ti sei registrato con Google.
          </p>
        </div>
      </div>

      {email ? (
        <div className="mt-4 space-y-3">
          {inviato ? (
            <p
              role="status"
              data-testid="sicurezza-link-inviato"
              className="flex items-start gap-3 rounded-2xl border border-border bg-crema p-4 text-sm text-antracite/80"
            >
              <Mail className="mt-0.5 h-5 w-5 shrink-0 text-bordeaux" aria-hidden />
              {/* L'indirizzo è quello della sessione: nominarlo non rivela nulla
                  che chi legge non sappia già, e conferma dove guardare. */}
              <span className="min-w-0 break-words">
                Abbiamo inviato il link a <b className="break-all">{email}</b>. Aprilo per scegliere
                la nuova password; se non lo trovi, controlla la cartella spam.
              </span>
            </p>
          ) : null}

          {errore && (
            <p
              role="alert"
              data-testid="sicurezza-errore"
              className="rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-sm text-bordeaux"
            >
              {messaggioErroreAuth(errore)}
            </p>
          )}

          <Button
            variant="outline"
            onClick={richiedi}
            disabled={inCorso}
            aria-busy={inCorso}
            data-testid="imposta-cambia-password"
            className="w-full sm:w-auto"
          >
            {inCorso
              ? "Invio del link…"
              : inviato
                ? "Invia di nuovo il link"
                : "Imposta o cambia password"}
          </Button>
        </div>
      ) : (
        // Senza email non c'è dove mandare il link. Non è un guasto da
        // segnalare come errore: è uno stato dell'account, e si dice così.
        <p className="mt-4 text-sm text-muted-foreground" data-testid="sicurezza-senza-email">
          Il tuo account non ha un indirizzo email associato, quindi non è possibile inviare il
          link di reimpostazione.
        </p>
      )}
    </div>
  );
}
