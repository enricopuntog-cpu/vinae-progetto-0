"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Check, ShieldAlert } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Checkbox } from "@/components/ui/checkbox";
import { useVinea } from "@/lib/vinea-store";
import { isMaggiorenne } from "@/lib/age";

/**
 * Completamento profilo dopo il primo accesso social (Fase 5b, punto 4).
 *
 * Chi entra con Google o Facebook non passa dal form di registrazione email e
 * quindi non vede il banner di dichiarazione età introdotto in Fase 5a: il
 * profilo esiste senza data di nascita. Questa schermata la richiede prima di
 * dare accesso al resto del sito, riusando la stessa logica e le stesse
 * parole del form email.
 *
 * Come in Fase 5a: dichiarazione AUTO-RIFERITA, nessun documento richiesto o
 * caricato, e il CHECK su profiles.dob resta la barriera autoritativa lato
 * server. Richiede validazione legale prima del lancio pubblico reale — vedi
 * "Cosa NON è ancora deciso" in docs/ROADMAP_V1.md.
 */
export default function CompletaProfiloPageClient() {
  const router = useRouter();
  const { authUser, authLoading, authError, authStatoEta, authSalvaDataNascita, authLogout } =
    useVinea();

  const [dob, setDob] = useState("");
  const [dobError, setDobError] = useState<string | null>(null);
  const [maggiorenne, setMaggiorenne] = useState(false);
  const [inCorso, setInCorso] = useState(false);

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

  const valid = dob !== "" && dobError === null && maggiorenne;

  const salva = async () => {
    if (!valid) return;
    setInCorso(true);
    const esito = await authSalvaDataNascita(dob);
    setInCorso(false);
    if (esito.ok) router.push("/home");
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
            <Link href="/accedi">Vai all&apos;accesso</Link>
          </Button>
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
          <Button asChild className="mt-5 bg-bordeaux hover:bg-bordeaux/90">
            <Link href="/home">Vai alla Home</Link>
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
        <h1 className="font-serif text-2xl md:text-3xl">Ancora un passaggio</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Hai effettuato l&apos;accesso come <b>{authUser.email ?? authUser.userId}</b>. Vinea è
          riservato ai maggiorenni: confermaci la tua data di nascita per continuare.
        </p>

        <div className="mt-5 space-y-4">
          <div className="sm:max-w-xs">
            <Label htmlFor="dob">Data di nascita</Label>
            <Input id="dob" type="date" value={dob} onChange={(e) => aggiornaDob(e.target.value)} />
            {dobError && <p className="mt-1 text-xs text-bordeaux">{dobError}</p>}
          </div>

          <label className="flex items-start gap-2 text-sm">
            <Checkbox
              checked={maggiorenne}
              onCheckedChange={(v) => setMaggiorenne(v === true)}
              className="mt-0.5"
            />
            <span className="flex items-center gap-1">
              <ShieldAlert className="h-3.5 w-3.5 text-bordeaux" /> Confermo di essere maggiorenne.
              Vinea è vietato ai minori di 18 anni.
            </span>
          </label>

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
