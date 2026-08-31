"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { useVinea } from "@/lib/vinea-store";
import { messaggioErroreAuth, type CodiceErroreAuth } from "@/lib/auth/errori-auth";
import type { SuperficieAuth } from "@/lib/auth/ritorno-auth";
import type { OAuthProvider } from "@/services/types";

/**
 * Pulsanti di accesso social (Fase 5b), condivisi da /registrati e /accedi.
 *
 * Con OAuth registrazione e accesso sono lo stesso gesto tecnico, ma non sono
 * la stessa promessa: chi è su /registrati sta creando un account, chi è su
 * /accedi sta rientrando nel suo. Fino a D5 il pulsante diceva "Google" a
 * entrambi e la differenza viveva solo nel testo del separatore sopra — cioè
 * nell'unica parte che si legge per ultima. Ora l'etichetta la decide
 * `superficie`, che è lo stesso valore che accompagna il giro dal provider e
 * riporta un eventuale errore sulla pagina giusta.
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

/** L'etichetta dice che cosa sta per succedere, non quale marchio si apre. */
const ETICHETTA_GOOGLE: Record<SuperficieAuth, string> = {
  accedi: "Continua con Google",
  registrati: "Registrati con Google",
};

export function SocialAuthButtons({
  etichetta,
  superficie,
  next,
  erroreIniziale = null,
  consensoMancante = null,
}: {
  /** Testo del separatore sopra i pulsanti. */
  etichetta: string;
  /** Pagina che ospita i pulsanti: decide copy e ritorno d'errore. */
  superficie: SuperficieAuth;
  /** Destinazione richiesta dall'utente, già validata dalla pagina. */
  next?: string | null;
  /**
   * Errore di un tentativo social **precedente**, riportato dalla callback
   * nell'URL. Vive qui e non nel riquadro del form perché è di questo gesto:
   * un fallimento di Google mostrato sotto il campo password è un errore che
   * accusa la cosa sbagliata.
   */
  erroreIniziale?: CodiceErroreAuth | null;
  /**
   * Motivo per cui il gesto non può partire adesso, deciso dalla superficie
   * ospite. `null` significa nessun impedimento.
   *
   * Su /registrati vale l'accettazione di Termini e Privacy: la casella è una
   * sola e sta nel form, perché il consenso riguarda la **creazione
   * dell'account**, non il metodo scelto per crearlo. Duplicarla accanto ai
   * pulsanti social vorrebbe dire chiedere due volte lo stesso fatto e poi
   * doversi chiedere quale delle due risposte conta.
   *
   * Su /accedi resta `null`: rientrare in un account già creato non è il
   * momento in cui si accettano di nuovo i termini.
   */
  consensoMancante?: string | null;
}) {
  const { authAccediConOAuth } = useVinea();
  const [avvio, setAvvio] = useState<OAuthProvider | null>(null);
  const [errore, setErrore] = useState<CodiceErroreAuth | null>(null);
  /**
   * L'errore che arriva dall'URL appartiene al tentativo di prima. Resta finché
   * l'utente non ne comincia un altro, e da quel momento non torna: `scartato`
   * è ciò che impedisce a un errore superato di riapparire perché il parametro
   * nell'indirizzo, quello, è ancora lì.
   */
  const [scartato, setScartato] = useState(false);
  const daMostrare = errore ?? (scartato ? null : erroreIniziale);
  const bloccato = consensoMancante !== null;

  const avvia = async (provider: OAuthProvider) => {
    if (avvio) return;
    // Il pulsante è già `disabled`, ma la guardia sta anche qui: `disabled` è
    // una proprietà del DOM, e ciò che non deve succedere non è che il click
    // passi — è che il giro dal provider parta senza il consenso.
    if (bloccato) return;
    setScartato(true);
    setErrore(null);
    setAvvio(provider);
    const esito = await authAccediConOAuth(provider, { superficie, next });
    // In caso di successo il browser sta già navigando verso il provider, non
    // c'è nulla da ripristinare. Se è fallito, riabilitiamo i pulsanti così
    // il retry è immediato e l'errore mostrato è azionabile.
    if (!esito.ok) {
      setErrore(esito.error);
      setAvvio(null);
    }
  };

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-3">
        <span className="h-px flex-1 bg-border" />
        <span className="text-xs uppercase tracking-wide text-muted-foreground">{etichetta}</span>
        <span className="h-px flex-1 bg-border" />
      </div>

      {daMostrare && (
        <p
          role="alert"
          data-testid="errore-oauth"
          className="rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-sm text-bordeaux"
        >
          {messaggioErroreAuth(daMostrare)}
        </p>
      )}

      <div className="grid gap-2">
        <Button
          variant="outline"
          onClick={() => avvia("google")}
          disabled={avvio !== null || bloccato}
          aria-busy={avvio === "google"}
          aria-describedby={bloccato ? "social-consenso-mancante" : undefined}
          data-testid="oauth-google"
          className="w-full"
        >
          <GoogleIcon />
          {avvio === "google" ? "Apertura Google…" : ETICHETTA_GOOGLE[superficie]}
        </Button>
        {bloccato && (
          <p
            id="social-consenso-mancante"
            data-testid="social-consenso-mancante"
            className="text-xs text-muted-foreground"
          >
            {consensoMancante}
          </p>
        )}
      </div>
    </div>
  );
}
