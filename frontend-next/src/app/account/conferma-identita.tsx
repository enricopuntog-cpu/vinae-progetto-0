"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { messaggioErroreAuth } from "@/lib/auth/errori-auth";
import {
  ETICHETTA_PROVIDER,
  PERCORSO_RITORNO_RIAUTENTICAZIONE,
  nessunMetodoRiautenticazione,
  type MetodiRiautenticazione,
} from "@/lib/auth/riautenticazione";
import { supabaseAuthService } from "@/services/auth-service";
import type { OAuthProvider } from "@/services/types";

/**
 * Conferma d'identità prima di un prelievo (step-up auth).
 *
 * Il controllo vero è nel database: questo modale serve solo a far aprire una
 * sessione nuova nel modo che l'utente ha davvero a disposizione. Chi è entrato
 * con Google o Facebook non ha una password da digitare, quindi le prove
 * offerte si leggono dalle identità collegate all'account, non si indovinano.
 * Con più identità ne basta una.
 *
 * Il ramo OAuth esce dalla pagina e rientra su /account: l'importo andrà
 * reinserito, e lo si dice prima invece di provare a trascinarlo attraverso il
 * redirect.
 */
type Props = {
  aperto: boolean;
  onChiudi: () => void;
  /** Chiamata dopo una conferma con password riuscita: ripete la richiesta. */
  onConfermata: () => void;
};

type Stato =
  | { fase: "caricamento" }
  | { fase: "pronto"; metodi: MetodiRiautenticazione }
  | { fase: "errore" };

const MESSAGGIO_PASSWORD_ERRATA = "Password non corretta. Controllala e riprova.";

export default function ConfermaIdentita({ aperto, onChiudi, onConfermata }: Props) {
  const [stato, setStato] = useState<Stato>({ fase: "caricamento" });
  const [password, setPassword] = useState("");
  const [errore, setErrore] = useState<string | null>(null);
  const [inCorso, setInCorso] = useState(false);

  useEffect(() => {
    if (!aperto) return;
    let attivo = true;
    supabaseAuthService
      .metodiRiautenticazione()
      .then((metodi) => {
        if (!attivo) return;
        setStato(metodi ? { fase: "pronto", metodi } : { fase: "errore" });
      })
      .catch(() => {
        if (attivo) setStato({ fase: "errore" });
      });
    return () => {
      attivo = false;
    };
  }, [aperto]);

  const chiudi = () => {
    setPassword("");
    setErrore(null);
    setStato({ fase: "caricamento" });
    onChiudi();
  };

  const confermaConPassword = async (evento: React.FormEvent) => {
    evento.preventDefault();
    if (password === "") {
      setErrore("Inserisci la password del tuo account Vinea.");
      return;
    }
    setInCorso(true);
    setErrore(null);
    const esito = await supabaseAuthService.riautenticaConPassword(password);
    setInCorso(false);
    if (!esito.ok) {
      // L'email non la sceglie l'utente qui: «email o password» sarebbe un
      // indizio sbagliato. Resta nel modale, con il campo pronto a riprovare.
      setErrore(
        esito.error === "credenziali-non-valide"
          ? MESSAGGIO_PASSWORD_ERRATA
          : messaggioErroreAuth(esito.error),
      );
      return;
    }
    setPassword("");
    setStato({ fase: "caricamento" });
    onConfermata();
  };

  const confermaConProvider = async (provider: OAuthProvider) => {
    setInCorso(true);
    setErrore(null);
    const esito = await supabaseAuthService.accediConOAuth(provider, {
      next: PERCORSO_RITORNO_RIAUTENTICAZIONE,
    });
    // Se va a buon fine il browser sta già lasciando la pagina.
    if (!esito.ok) {
      setInCorso(false);
      setErrore(messaggioErroreAuth(esito.error));
    }
  };

  return (
    <Dialog open={aperto} onOpenChange={(v) => (v ? undefined : chiudi())}>
      <DialogContent className="max-w-md" data-testid="conferma-identita">
        <DialogHeader>
          <DialogTitle className="font-serif text-xl">Conferma la tua identità</DialogTitle>
          <DialogDescription>
            Per sicurezza, prima di un prelievo ti chiediamo di confermare che sei tu. Serve
            solo se non hai effettuato l’accesso negli ultimi 15 minuti.
          </DialogDescription>
        </DialogHeader>

        {stato.fase === "caricamento" && (
          <p className="text-sm text-muted-foreground">Un momento…</p>
        )}

        {stato.fase === "errore" && (
          <p className="text-sm text-red-700">
            Non è stato possibile leggere il tuo account. Esci e rientra, poi riprova il prelievo.
          </p>
        )}

        {stato.fase === "pronto" && nessunMetodoRiautenticazione(stato.metodi) && (
          <p className="text-sm text-red-700">
            Non troviamo un modo per confermare la tua identità da qui. Esci e rientra, poi
            riprova il prelievo.
          </p>
        )}

        {stato.fase === "pronto" && stato.metodi.password && (
          <form className="space-y-3" onSubmit={confermaConPassword}>
            <p className="text-sm">
              Account: <span className="font-medium">{stato.metodi.email}</span>
            </p>
            <label className="block text-sm font-medium" htmlFor="conferma-password">
              Password
            </label>
            <input
              id="conferma-password"
              type="password"
              autoComplete="current-password"
              autoFocus
              value={password}
              onChange={(e) => {
                setPassword(e.target.value);
                setErrore(null);
              }}
              disabled={inCorso}
              aria-invalid={errore !== null}
              aria-describedby={errore ? "conferma-errore" : undefined}
              className="w-full rounded-xl border border-border bg-background px-3 py-2 text-sm"
            />
            <Button type="submit" size="sm" disabled={inCorso} className="w-full">
              {inCorso ? "Verifica in corso…" : "Conferma e preleva"}
            </Button>
          </form>
        )}

        {stato.fase === "pronto" && stato.metodi.oauth.length > 0 && (
          <div className="space-y-2">
            {stato.metodi.password && (
              <p className="text-center text-xs text-muted-foreground">oppure</p>
            )}
            {stato.metodi.oauth.map((provider) => (
              <Button
                key={provider}
                type="button"
                variant="outline"
                size="sm"
                className="w-full"
                disabled={inCorso}
                onClick={() => confermaConProvider(provider)}
              >
                Conferma con {ETICHETTA_PROVIDER[provider]}
              </Button>
            ))}
            <p className="text-xs text-muted-foreground">
              Verrai portato su {stato.metodi.oauth.map((p) => ETICHETTA_PROVIDER[p]).join(" o ")} e
              poi di nuovo al tuo saldo: dovrai reinserire l’importo del prelievo.
            </p>
          </div>
        )}

        {errore && (
          <p id="conferma-errore" role="alert" className="text-sm text-red-700">
            {errore}
          </p>
        )}

        <DialogFooter>
          <Button type="button" variant="ghost" size="sm" onClick={chiudi} disabled={inCorso}>
            Annulla
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
