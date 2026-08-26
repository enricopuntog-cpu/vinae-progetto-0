"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";
import { Check, ShieldAlert } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ConsentCheckbox } from "@/components/vinea/ConsentCheckbox";
import { useVinea } from "@/lib/vinea-store";
import { percorsoRelativoSicuro } from "@/lib/auth/origine-redirect";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";
import { isMaggiorenne } from "@/lib/age";

/**
 * Completamento profilo dopo il primo accesso social (Fase 5b, punto 4).
 *
 * Chi entra con Google o Facebook non passa dal form di registrazione email e
 * quindi non vede né il banner di dichiarazione età né la richiesta di consenso
 * introdotti in Fase 5a: il profilo esiste senza data di nascita, con un nome
 * utente assegnato d'ufficio dal trigger `handle_new_user()` e senza che
 * nessuno gli abbia mai chiesto di accettare Termini e Privacy. Questa
 * schermata chiude tutti e tre i punti prima di dare accesso al resto del sito,
 * riusando le stesse parole del form email.
 *
 * UNA SCRITTURA SOLA, non tre. Nome utente e data di nascita partono nella
 * stessa istruzione (`authAggiornaProfilo`), così non esiste uno stato
 * intermedio in cui l'età è dichiarata e il nome no — o viceversa, con l'utente
 * rimandato qui da AgeGate a rifare metà lavoro.
 *
 * Come in Fase 5a: dichiarazione AUTO-RIFERITA, nessun documento richiesto o
 * caricato, e il CHECK su profiles.dob resta la barriera autoritativa lato
 * server. Richiede validazione legale prima del lancio pubblico reale — vedi
 * "Cosa NON è ancora deciso" in docs/ROADMAP_V1.md.
 */
export default function CompletaProfiloPageClient() {
  const router = useRouter();
  const parametri = useSearchParams();
  const next = percorsoRelativoSicuro(parametri.get(PARAMETRO_NEXT));
  const destinazione = next ?? "/home";
  const {
    authUser,
    authLoading,
    authError,
    authStatoEta,
    authProfilo,
    authProfileLoading,
    authRicaricaProfilo,
    authAggiornaProfilo,
    authLogout,
  } = useVinea();

  const [dob, setDob] = useState("");
  const [dobError, setDobError] = useState<string | null>(null);
  const [maggiorenne, setMaggiorenne] = useState(false);
  const [terms, setTerms] = useState(false);
  const [inCorso, setInCorso] = useState(false);
  // Il nome di partenza è quello che il trigger ha assegnato; finché l'utente
  // non tocca il campo si mostra quello. Derivato e non copiato in stato da un
  // effect: una setState sincrona dentro un effect è ciò che la regola
  // `set-state-in-effect` di Next 16 rifiuta, e qui non serve.
  const [usernameModificato, setUsernameModificato] = useState<string | null>(null);
  const username = usernameModificato ?? authProfilo?.username ?? "";

  const aggiornaDob = (value: string) => {
    setDob(value);
    if (!value) {
      setDobError(null);
      return;
    }
    setDobError(
      isMaggiorenne(value, new Date()) ? null : "Devi avere almeno 18 anni per usare Vinea.",
    );
  };

  const valid =
    username.trim().length >= 3 && dob !== "" && dobError === null && maggiorenne && terms;

  const salva = async () => {
    if (!valid) return;
    setInCorso(true);
    // Un'unica operazione coerente: se il nome utente è già preso, l'errore di
    // unicità respinge l'intera istruzione e la data di nascita non viene
    // scritta a metà.
    const esito = await authAggiornaProfilo({ username: username.trim(), dob });
    setInCorso(false);
    if (esito.ok) router.push(destinazione);
  };

  if (authLoading) {
    return (
      <div className="mx-auto max-w-2xl">
        <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
          <p className="text-sm text-muted-foreground">Verifica della sessione…</p>
        </div>
      </div>
    );
  }

  if (!authUser) {
    return (
      <div className="mx-auto max-w-2xl space-y-6">
        <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
          <h1 className="font-serif text-2xl md:text-3xl">Serve prima l&apos;accesso</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Questa pagina completa un profilo già autenticato.
          </p>
          <Button asChild className="mt-5 bg-bordeaux hover:bg-bordeaux/90">
            {/*
              Con `?next=`: questa pagina completa un profilo già autenticato,
              quindi chi arriva senza sessione deve poterci tornare subito dopo
              averla aperta, senza ripassare da un'altra pagina.
            */}
            <Link href={`/accedi?${PARAMETRO_NEXT}=%2Fcompleta-profilo`}>
              Vai all&apos;accesso
            </Link>
          </Button>
        </div>
      </div>
    );
  }

  if (authStatoEta === "in_verifica") {
    return (
      <div className="mx-auto max-w-2xl">
        <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
          <p className="text-sm text-muted-foreground">Verifica del profilo…</p>
        </div>
      </div>
    );
  }

  if (authStatoEta === "errore_lettura") {
    return (
      <div className="mx-auto max-w-2xl space-y-6">
        <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
          <h1 className="font-serif text-2xl md:text-3xl">
            Non riusciamo a verificare il tuo profilo.
          </h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Riprova la lettura oppure esci dall&apos;account.
          </p>
          <div className="mt-5 flex flex-col gap-2 sm:flex-row">
            <Button
              onClick={() => void authRicaricaProfilo()}
              className="bg-bordeaux hover:bg-bordeaux/90"
            >
              Riprova
            </Button>
            <Button variant="outline" onClick={() => void authLogout()}>
              Esci
            </Button>
          </div>
        </div>
      </div>
    );
  }

  if (authStatoEta === "completo") {
    return (
      <div className="mx-auto max-w-2xl space-y-6">
        <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
          <h1 className="font-serif text-2xl md:text-3xl">Profilo già completo</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            La tua data di nascita è già stata dichiarata.
          </p>
          <div className="mt-5 flex flex-col gap-2 sm:flex-row">
            <Button asChild className="bg-bordeaux hover:bg-bordeaux/90">
              <Link href={destinazione}>{next ? "Continua" : "Vai alla Home"}</Link>
            </Button>
            <Button asChild variant="outline">
              <Link href="/account">Modifica il profilo</Link>
            </Button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
        <h1 className="font-serif text-2xl md:text-3xl">Ancora un passaggio</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Hai effettuato l&apos;accesso come <b>{authUser.email ?? authUser.userId}</b>. Scegli
          come vuoi farti chiamare e confermaci la tua data di nascita: Vinea è riservato ai
          maggiorenni.
        </p>

        <div className="mt-5 space-y-4">
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <Label htmlFor="username">Nome utente</Label>
              <Input
                id="username"
                value={username}
                onChange={(e) => setUsernameModificato(e.target.value)}
                placeholder={authProfileLoading ? "Caricamento…" : "es. elena_r"}
                autoComplete="username"
                disabled={authProfileLoading}
              />
              <p className="mt-1 text-xs text-muted-foreground">
                Ne abbiamo scelto uno per te: puoi cambiarlo adesso o più avanti dal tuo profilo.
              </p>
            </div>
            <div>
              <Label htmlFor="dob">Data di nascita</Label>
              <Input
                id="dob"
                type="date"
                value={dob}
                onChange={(e) => aggiornaDob(e.target.value)}
              />
              {dobError && <p className="mt-1 text-xs text-bordeaux">{dobError}</p>}
            </div>
          </div>

          <ConsentCheckbox checked={terms} onCheckedChange={setTerms} testId="consenso-termini">
            Accetto i{" "}
            <Link href="/legale#termini" className="text-bordeaux underline-offset-2 hover:underline">
              Termini
            </Link>{" "}
            e la{" "}
            <Link href="/legale#privacy" className="text-bordeaux underline-offset-2 hover:underline">
              Privacy
            </Link>{" "}
            di Vinea.
          </ConsentCheckbox>
          <ConsentCheckbox
            checked={maggiorenne}
            onCheckedChange={setMaggiorenne}
            icon={<ShieldAlert className="h-3.5 w-3.5 text-bordeaux" />}
            testId="consenso-eta"
          >
            Confermo di avere almeno 18 anni. Vinea è vietato ai minori di 18 anni.
          </ConsentCheckbox>

          <p className="rounded-xl border border-oro/30 bg-oro/5 p-3 text-xs text-antracite/80">
            L&apos;età viene <b>dichiarata da te</b>: non chiediamo né verifichiamo documenti in
            questa fase.
          </p>

          {authError && (
            <p className="rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-sm text-bordeaux">
              {authError}
            </p>
          )}

          <div className="flex flex-col gap-2 sm:flex-row">
            <Button
              onClick={salva}
              disabled={!valid || inCorso}
              className="bg-bordeaux hover:bg-bordeaux/90"
            >
              {inCorso ? (
                "Salvataggio…"
              ) : (
                <>
                  <Check className="h-4 w-4" /> Conferma e continua
                </>
              )}
            </Button>
            <Button variant="outline" onClick={() => authLogout()}>
              Esci
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
