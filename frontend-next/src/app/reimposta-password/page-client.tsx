"use client";

import Link from "next/link";
import { useState } from "react";
import { Check, KeyRound, ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useVinea } from "@/lib/vinea-store";
import { messaggioErroreAuth, type CodiceErroreAuth } from "@/lib/auth/errori-auth";

/**
 * Reimpostazione della password.
 *
 * Serve tre percorsi che qui sono lo stesso: chi ha dimenticato la password,
 * chi si è registrato con Google e vuole per la prima volta una password
 * Vinea, e chi ne ha una e la sta cambiando dall'area account. Nessuno dei tre
 * deve digitare la password precedente — il secondo non ne ha mai avuta una, e
 * chiederla avrebbe reso questa pagina inutilizzabile proprio per il caso che
 * l'ha resa necessaria. Quello che l'utente prova non è di ricordare un
 * segreto: è di controllare la casella di posta a cui è arrivato il link, e
 * quella prova è la sessione di recupero già aperta da /auth/callback.
 *
 * La lunghezza minima è la stessa della registrazione (6 caratteri): due
 * soglie diverse per la stessa password vorrebbero dire che una delle due
 * pagine mente.
 */

/** Stessa soglia del form di registrazione. Vedi /registrati. */
const LUNGHEZZA_MINIMA_PASSWORD = 6;

export default function ReimpostaPasswordPageClient({
  erroreRientro = null,
}: {
  /**
   * Motivo per cui il link non ha aperto una sessione, deciso da
   * `/auth/callback` e già validato dal server contro il vocabolario chiuso.
   * `null` quando la pagina è stata semplicemente aperta senza sessione.
   */
  erroreRientro?: CodiceErroreAuth | null;
} = {}) {
  const { authUser, authLoading, authAggiornaPasswordNuova } = useVinea();

  const [password, setPassword] = useState("");
  const [conferma, setConferma] = useState("");
  const [inCorso, setInCorso] = useState(false);
  const [errore, setErrore] = useState<CodiceErroreAuth | null>(null);
  const [fatto, setFatto] = useState(false);

  const abbastanzaLunga = password.length >= LUNGHEZZA_MINIMA_PASSWORD;
  const combaciano = conferma.length > 0 && password === conferma;
  const valido = abbastanzaLunga && combaciano;
  /**
   * Il mismatch si mostra solo quando l'utente ha scritto abbastanza da
   * renderlo un fatto e non un'osservazione su una frase a metà.
   */
  const mostraMismatch = conferma.length > 0 && password !== conferma;

  const salva = async () => {
    // Doppio invio: la guardia sta prima di tutto perché il secondo click
    // arriverebbe mentre il primo è ancora in volo, e due updateUser per la
    // stessa intenzione sono due scritture di cui una non è stata chiesta.
    if (inCorso) return;
    if (!valido) return;
    setErrore(null);
    setInCorso(true);
    const esito = await authAggiornaPasswordNuova(password);
    setInCorso(false);
    if (!esito.ok) {
      setErrore(esito.error);
      return;
    }
    // I campi si svuotano appena il salvataggio riesce: non c'è ragione di
    // tenere una password in memoria di un componente che ha finito.
    setPassword("");
    setConferma("");
    setFatto(true);
  };

  if (authLoading) {
    return (
      <div className="mx-auto max-w-md">
        <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
          <p className="text-sm text-muted-foreground">Verifica della sessione…</p>
        </div>
      </div>
    );
  }

  /**
   * Nessuna sessione: il link è scaduto, è già stato usato, oppure la pagina è
   * stata aperta da sola. Sono casi diversi che qui producono la stessa
   * situazione — non c'è nessuno da cui cambiare la password — e la sola cosa
   * utile da offrire è il modo di chiedere un link nuovo.
   *
   * Il messaggio è quello che la callback ha riportato, se ne ha riportato uno:
   * lo scambio fallito e il link mai aperto sono lo stesso vicolo cieco, ma non
   * la stessa frase, e la callback è l'unico punto che sa quale dei due è.
   */
  if (!authUser) {
    return (
      <div className="mx-auto max-w-md space-y-6">
        <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
          <h1 className="font-serif text-2xl md:text-3xl">Link non più valido</h1>
          <p
            role="alert"
            data-testid="recupero-sessione-assente"
            className="mt-4 rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-sm text-bordeaux"
          >
            {messaggioErroreAuth(erroreRientro ?? "sessione-recupero-assente")}
          </p>
          <p className="mt-3 text-sm text-muted-foreground">
            I link per reimpostare la password valgono una sola volta e scadono dopo poco tempo.
          </p>
          <Button asChild className="mt-5 bg-bordeaux hover:bg-bordeaux/90">
            <Link href="/accedi" data-testid="richiedi-nuovo-link">
              Richiedi un nuovo link
            </Link>
          </Button>
        </div>
      </div>
    );
  }

  if (fatto) {
    return (
      <div className="mx-auto max-w-md space-y-6">
        <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
          <h1 className="font-serif text-2xl md:text-3xl">Password aggiornata</h1>
          <div
            role="status"
            data-testid="password-aggiornata"
            className="mt-4 flex items-start gap-3 rounded-2xl border border-border bg-crema p-4"
          >
            <ShieldCheck className="mt-0.5 h-6 w-6 shrink-0 text-bordeaux" aria-hidden />
            <p className="min-w-0 text-sm text-antracite/80">
              Da ora puoi accedere a Vinea con questa password. Se il tuo account usa anche Google,
              quel metodo continua a funzionare.
            </p>
          </div>
          <div className="mt-5 flex flex-col gap-2 sm:flex-row">
            <Button asChild className="bg-bordeaux hover:bg-bordeaux/90">
              <Link href="/account">Vai al tuo account</Link>
            </Button>
            <Button asChild variant="outline">
              <Link href="/home">Vai alla Home</Link>
            </Button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-md space-y-6">
      <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
        <h1 className="font-serif text-2xl md:text-3xl">Imposta una nuova password</h1>
        <p className="mt-2 min-w-0 break-words text-sm text-muted-foreground">
          Stai impostando la password per <b className="break-all">{authUser.email ?? authUser.userId}</b>.
        </p>

        <div className="mt-5 space-y-4">
          <div>
            <Label htmlFor="password-nuova">Nuova password</Label>
            <Input
              id="password-nuova"
              type="password"
              value={password}
              onChange={(e) => {
                setPassword(e.target.value);
                setErrore(null);
              }}
              placeholder={`almeno ${LUNGHEZZA_MINIMA_PASSWORD} caratteri`}
              autoComplete="new-password"
              data-testid="password-nuova"
            />
          </div>
          <div>
            <Label htmlFor="password-conferma">Conferma nuova password</Label>
            <Input
              id="password-conferma"
              type="password"
              value={conferma}
              onChange={(e) => {
                setConferma(e.target.value);
                setErrore(null);
              }}
              placeholder="ripeti la password"
              autoComplete="new-password"
              aria-invalid={mostraMismatch}
              data-testid="password-conferma"
            />
            {mostraMismatch && (
              <p role="alert" data-testid="errore-mismatch" className="mt-1 text-xs text-bordeaux">
                Le due password non coincidono.
              </p>
            )}
          </div>

          {errore && (
            <p
              role="alert"
              data-testid="errore-reimposta"
              className="rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-sm text-bordeaux"
            >
              {messaggioErroreAuth(errore)}
            </p>
          )}

          <Button
            onClick={salva}
            disabled={!valido || inCorso}
            aria-busy={inCorso}
            data-testid="salva-password"
            className="w-full bg-bordeaux hover:bg-bordeaux/90"
          >
            {inCorso ? (
              "Salvataggio…"
            ) : (
              <>
                <Check className="h-4 w-4" /> Salva la password
              </>
            )}
          </Button>

          <p className="flex items-start gap-2 text-xs text-muted-foreground">
            <KeyRound className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden />
            <span>
              La password è custodita da Supabase Auth: Vinea non la conserva né la mostra in
              nessuna pagina.
            </span>
          </p>
        </div>
      </div>
    </div>
  );
}
