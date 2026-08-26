"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";
import { Check, Mail, ShieldAlert } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ConsentCheckbox } from "@/components/vinea/ConsentCheckbox";
import { SocialAuthButtons } from "@/components/vinea/SocialAuthButtons";
import { useVinea } from "@/lib/vinea-store";
import { isMaggiorenne } from "@/lib/age";
import { percorsoRelativoSicuro } from "@/lib/auth/origine-redirect";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";
import {
  codiceErroreAuth,
  messaggioErroreAuth,
  type CodiceErroreAuth,
} from "@/lib/auth/errori-auth";

/**
 * Superficie di registrazione. Vale qui la stessa divisione di /accedi: il
 * form email/password e il giro social sono due gesti, e ognuno mostra il
 * proprio errore accanto al proprio pulsante.
 *
 * Chi si registra con Google non dichiara qui la data di nascita — non ce
 * n'è una da chiedere prima di aprire il provider. Il profilo può nascere con
 * `dob` vuoto e sono AgeGate e /completa-profilo a occuparsene, esattamente
 * come prima di D5: qui non si duplica quel controllo.
 */
export default function RegistratiPageClient() {
  const router = useRouter();
  const { authUser, authLoading, authRegistra, authLogin, authLogout } = useVinea();

  const parametri = useSearchParams();
  /** Stesso contratto di /accedi: relativo, validato, altrimenti assente. */
  const next = percorsoRelativoSicuro(parametri.get(PARAMETRO_NEXT));
  const destinazione = next ?? "/home";
  const parametroErrore = parametri.get("errore");
  const erroreRitorno = parametroErrore ? codiceErroreAuth(parametroErrore) : null;
  const erroreSocialIniziale =
    erroreRitorno && erroreRitorno.startsWith("oauth-") ? erroreRitorno : null;
  const erroreRitornoNonSocial = erroreRitorno && !erroreSocialIniziale ? erroreRitorno : null;

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
  const [erroreRegistrazione, setErroreRegistrazione] = useState<CodiceErroreAuth | null>(null);
  const [confermaEmail, setConfermaEmail] = useState(false);
  const [ritornoScartato, setRitornoScartato] = useState(false);
  const ritornoDaMostrare = ritornoScartato ? null : erroreRitornoNonSocial;

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

  const percorsoAccesso = next
    ? `/accedi?${PARAMETRO_NEXT}=${encodeURIComponent(next)}`
    : "/accedi";

  const invia = async () => {
    if (inCorso) return;
    if (!valid) return;
    setRitornoScartato(true);
    setErroreRegistrazione(null);
    setInCorso(true);
    const esito = await authRegistra(
      {
        email: email.trim(),
        password,
        dataNascita: dob,
        username: username.trim(),
      },
      // La conferma via email rientra da /auth/callback: se l'utente stava
      // andando da qualche parte, quel percorso viaggia con il link.
      { superficie: "registrati", next },
    );
    if (!esito.ok) {
      setInCorso(false);
      setErroreRegistrazione(esito.error);
      return;
    }
    if (esito.data.sessioneAttiva) {
      setInCorso(false);
      router.push(destinazione);
      return;
    }
    if (esito.data.confermaEmailRichiesta) {
      setInCorso(false);
      setConfermaEmail(true);
      return;
    }
    // Email già confermata ma nessuna sessione restituita dalla sign up:
    // l'account è utilizzabile subito, quindi completiamo l'accesso con le
    // credenziali appena inserite invece di mostrare un'attesa inesistente.
    const accesso = await authLogin(email.trim(), password);
    setInCorso(false);
    router.push(accesso.ok ? destinazione : percorsoAccesso);
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
              <Link href={destinazione}>{next ? "Continua" : "Vai alla Home"}</Link>
            </Button>
            <Button variant="outline" data-testid="logout" onClick={() => authLogout()}>
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
            <Link href={percorsoAccesso}>Vai all&apos;accesso</Link>
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

        {ritornoDaMostrare && (
          <p
            role="alert"
            data-testid="errore-ritorno"
            className="mt-4 rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-sm text-bordeaux"
          >
            {messaggioErroreAuth(ritornoDaMostrare)}
          </p>
        )}

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
                onChange={(e) => {
                  setEmail(e.target.value);
                  setErroreRegistrazione(null);
                }}
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
                onChange={(e) => {
                  setPassword(e.target.value);
                  setErroreRegistrazione(null);
                }}
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

          <ConsentCheckbox checked={terms} onCheckedChange={setTerms} testId="consenso-termini">
            Accetto i Termini e la Privacy di Vinea.
          </ConsentCheckbox>
          <ConsentCheckbox
            checked={maggiorenne}
            onCheckedChange={setMaggiorenne}
            icon={<ShieldAlert className="h-3.5 w-3.5 text-bordeaux" />}
            testId="consenso-eta"
          >
            Confermo di avere più di 18 anni. Vinea è vietato ai minori di 18 anni.
          </ConsentCheckbox>

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

          {erroreRegistrazione && (
            <p
              role="alert"
              data-testid="errore-registrazione"
              className="rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-sm text-bordeaux"
            >
              {messaggioErroreAuth(erroreRegistrazione)}
            </p>
          )}

          <Button
            onClick={invia}
            disabled={!valid || inCorso}
            aria-busy={inCorso}
            data-testid="crea-account"
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

          <SocialAuthButtons
            etichetta="oppure registrati con"
            superficie="registrati"
            next={next}
            erroreIniziale={erroreSocialIniziale}
          />

          <p className="text-sm text-muted-foreground">
            Hai già un account?{" "}
            <Link href={percorsoAccesso} className="text-bordeaux hover:underline">
              Accedi
            </Link>
            .
          </p>
        </div>
      </div>
    </div>
  );
}
