"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Check, Mail, ShieldAlert } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Checkbox } from "@/components/ui/checkbox";
import { useVinea } from "@/lib/vinea-store";
import { isMaggiorenne } from "@/lib/age";

export default function RegistratiPageClient() {
  const router = useRouter();
  const { authUser, authLoading, authError, authRegistra, authLogout } = useVinea();

  const [username, setUsername] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [dob, setDob] = useState("");
  // Errore di età calcolato nell'onChange (event handler) e non derivato in
  // render: leggere la data odierna durante il render sarebbe una lettura
  // impura secondo le regole del React Compiler.
  const [dobError, setDobError] = useState<string | null>(null);
  const [terms, setTerms] = useState(false);
  const [maggiorenne, setMaggiorenne] = useState(false);
  const [inCorso, setInCorso] = useState(false);
  const [confermaEmail, setConfermaEmail] = useState(false);

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
    username.trim().length >= 3 &&
    email.includes("@") &&
    password.length >= 6 &&
    dob !== "" &&
    dobError === null &&
    terms &&
    maggiorenne;

  const invia = async () => {
    if (!valid) return;
    setInCorso(true);
    const esito = await authRegistra({
      email: email.trim(),
      password,
      dataNascita: dob,
      username: username.trim(),
    });
    setInCorso(false);
    if (!esito.ok) return;
    if (esito.data.sessioneAttiva) {
      router.push("/home");
      return;
    }
    setConfermaEmail(true);
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

  if (authUser) {
    return (
      <div className="mx-auto max-w-2xl space-y-6">
        <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
          <h1 className="font-serif text-2xl md:text-3xl">Hai già un account attivo</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Sei autenticato come <b>{authUser.email ?? authUser.userId}</b>.
          </p>
          <div className="mt-5 flex flex-col gap-2 sm:flex-row">
            <Button asChild className="bg-bordeaux hover:bg-bordeaux/90">
              <Link href="/home">Vai alla Home</Link>
            </Button>
            <Button variant="outline" onClick={() => authLogout()}>
              Esci
            </Button>
          </div>
        </div>
      </div>
    );
  }

  if (confermaEmail) {
    return (
      <div className="mx-auto max-w-2xl space-y-6">
        <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
          <h1 className="font-serif text-2xl md:text-3xl">Controlla la posta</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Abbiamo inviato un link di conferma a <b>{email}</b>. Aprilo per attivare l&apos;account,
            poi torna qui per accedere.
          </p>
          <div className="mt-5 flex items-start gap-3 rounded-2xl border border-border bg-crema p-4">
            <Mail className="mt-0.5 h-6 w-6 shrink-0 text-bordeaux" />
            <p className="min-w-0 text-sm text-antracite/80">
              Se non trovi il messaggio, controlla la cartella spam.
            </p>
          </div>
          <Button asChild className="mt-5 bg-bordeaux hover:bg-bordeaux/90">
            <Link href="/accedi">Vai all&apos;accesso</Link>
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
        <h1 className="font-serif text-2xl md:text-3xl">Crea il tuo account</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Ti serve un&apos;email valida: riceverai un link di conferma prima di poter accedere.
        </p>

        <div className="mt-5 space-y-4">
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <Label htmlFor="username">Nome utente</Label>
              <Input
                id="username"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                placeholder="es. elena_r"
                autoComplete="username"
              />
            </div>
            <div>
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="nome@esempio.it"
                autoComplete="email"
              />
            </div>
            <div>
              <Label htmlFor="password">Password</Label>
              <Input
                id="password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="almeno 6 caratteri"
                autoComplete="new-password"
              />
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

          <label className="flex items-start gap-2 text-sm">
            <Checkbox
              checked={terms}
              onCheckedChange={(v) => setTerms(v === true)}
              className="mt-0.5"
            />
            <span>Accetto i Termini e la Privacy di Vinea.</span>
          </label>
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

          {/*
            Dichiarazione auto-riferita, non verifica documentale: nessun documento
            viene richiesto o caricato. Il controllo 18+ è applicato sia qui lato
            client (isMaggiorenne) sia lato server dal CHECK su profiles.dob.
            Richiede validazione legale prima del lancio pubblico reale — vedi
            "Cosa NON è ancora deciso" in docs/ROADMAP_V1.md.
          */}
          <p className="rounded-xl border border-oro/30 bg-oro/5 p-3 text-xs text-antracite/80">
            L&apos;età viene <b>dichiarata da te</b>: non chiediamo né verifichiamo documenti in
            questa fase.
          </p>

          {authError && (
            <p className="rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-sm text-bordeaux">
              {authError}
            </p>
          )}

          <Button
            onClick={invia}
            disabled={!valid || inCorso}
            className="w-full bg-bordeaux hover:bg-bordeaux/90 sm:w-auto"
          >
            {inCorso ? (
              "Creazione account…"
            ) : (
              <>
                <Check className="h-4 w-4" /> Crea account
              </>
            )}
          </Button>

          <p className="text-sm text-muted-foreground">
            Hai già un account?{" "}
            <Link href="/accedi" className="text-bordeaux hover:underline">
              Accedi
            </Link>
            .
          </p>
        </div>
      </div>
    </div>
  );
}
