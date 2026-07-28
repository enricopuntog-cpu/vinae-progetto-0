"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { useVinea } from "@/lib/vinea-store";
import type { OAuthProvider } from "@/services/types";

/**
 * Pulsanti di accesso social (Fase 5b), condivisi da /registrati e /accedi:
 * con OAuth registrazione e accesso sono lo stesso gesto, cambia solo
 * l'etichetta introduttiva.
 *
 * Nessun Client ID o Secret qui: vivono solo nella dashboard Supabase, il
 * codice nomina soltanto il provider.
 *
 * Facebook rimandato a data da destinarsi, non bloccante per questa fase: la
 * dashboard di Facebook for Developers non salva le modifiche ai campi App
 * Domains / Valid OAuth Redirect URIs (bug/limite lato loro, non risolvibile
 * da qui), quindi il provider è stato disabilitato lato Supabase per non
 * lasciare un pulsante rotto in produzione. Il pulsante è rimosso dalla UI di
 * conseguenza — tenerlo visibile con il provider disabilitato sarebbe
 * comunque un pulsante rotto, solo con un errore diverso. `accediConOAuth`
 * resta provider-agnostico e `signInWithFacebook` resta in AuthService: per
 * riattivare basta far funzionare la dashboard Facebook, riabilitare il
 * provider su Supabase, e riaggiungere qui il bottone rimosso.
 */

// Loghi inline come SVG: nessuna richiesta di rete e nessun asset da servire.
function GoogleIcon() {
  return (
    <svg viewBox="0 0 18 18" className="h-4 w-4" aria-hidden focusable="false">
      <path
        fill="#4285F4"
        d="M17.64 9.2c0-.64-.06-1.25-.16-1.84H9v3.48h4.84a4.14 4.14 0 0 1-1.8 2.72v2.26h2.92c1.71-1.57 2.68-3.89 2.68-6.62Z"
      />
      <path
        fill="#34A853"
        d="M9 18c2.43 0 4.47-.8 5.96-2.18l-2.92-2.26c-.81.54-1.84.86-3.04.86-2.34 0-4.32-1.58-5.03-3.7H1.96v2.34A8.99 8.99 0 0 0 9 18Z"
      />
      <path
        fill="#FBBC05"
        d="M3.97 10.72a5.41 5.41 0 0 1 0-3.44V4.94H1.96a9 9 0 0 0 0 8.12l2.01-2.34Z"
      />
      <path
        fill="#EA4335"
        d="M9 3.58c1.32 0 2.5.45 3.44 1.35l2.58-2.59C13.46.89 11.43 0 9 0A8.99 8.99 0 0 0 1.96 4.94l2.01 2.34C4.68 5.16 6.66 3.58 9 3.58Z"
      />
    </svg>
  );
}

// FacebookIcon rimossa insieme al bottone: riaggiungerla da qui se il
// provider viene riattivato (vedi commento sopra). Ultima versione nel
// controllo versione di questo file.

export function SocialAuthButtons({ etichetta }: { etichetta: string }) {
  const { authAccediConOAuth } = useVinea();
  const [inCorso, setInCorso] = useState<OAuthProvider | null>(null);

  const avvia = async (provider: OAuthProvider) => {
    setInCorso(provider);
    const esito = await authAccediConOAuth(provider);
    // In caso di successo il browser sta già navigando verso il provider, non
    // c'è nulla da ripristinare. Se è fallito, riabilitiamo i pulsanti così
    // l'errore mostrato dalla pagina è azionabile.
    if (!esito.ok) setInCorso(null);
  };

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-3">
        <span className="h-px flex-1 bg-border" />
        <span className="text-xs uppercase tracking-wide text-muted-foreground">{etichetta}</span>
        <span className="h-px flex-1 bg-border" />
      </div>

      <div className="grid gap-2">
        <Button
          variant="outline"
          onClick={() => avvia("google")}
          disabled={inCorso !== null}
          data-testid="oauth-google"
          className="w-full"
        >
          <GoogleIcon />
          {inCorso === "google" ? "Apertura Google…" : "Google"}
        </Button>
      </div>
    </div>
  );
}
