"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { useVinea } from "@/lib/vinea-store";
import type { OAuthProvider } from "@/services/types";

/**
 * Pulsanti di accesso Google e Facebook (Fase 5b), condivisi da /registrati e
 * /accedi: con OAuth registrazione e accesso sono lo stesso gesto, cambia solo
 * l'etichetta introduttiva.
 *
 * Nessun Client ID o Secret qui: vivono solo nella dashboard Supabase, il
 * codice nomina soltanto il provider.
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

function FacebookIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-4 w-4" aria-hidden focusable="false">
      <path
        fill="#1877F2"
        d="M24 12.07C24 5.4 18.63 0 12 0S0 5.4 0 12.07C0 18.1 4.39 23.1 10.13 24v-8.44H7.08v-3.49h3.05V9.41c0-3.02 1.79-4.69 4.53-4.69 1.31 0 2.68.24 2.68.24v2.95h-1.51c-1.49 0-1.96.93-1.96 1.89v2.27h3.33l-.53 3.49h-2.8V24C19.61 23.1 24 18.1 24 12.07Z"
      />
    </svg>
  );
}

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

      <div className="grid gap-2 sm:grid-cols-2">
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
        <Button
          variant="outline"
          onClick={() => avvia("facebook")}
          disabled={inCorso !== null}
          data-testid="oauth-facebook"
          className="w-full"
        >
          <FacebookIcon />
          {inCorso === "facebook" ? "Apertura Facebook…" : "Facebook"}
        </Button>
      </div>
    </div>
  );
}
