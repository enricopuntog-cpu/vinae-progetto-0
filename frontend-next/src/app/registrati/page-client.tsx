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

  // La data di nascita è obbligatoria (`dob !== ""`) e deve superare
  // `isMaggiorenne` (`dobError === null`): chi ha meno di 18 anni non può
  // inviare. Una casella «confermo di avere 18 anni» accanto a una data già
  // dichiarata non aggiungeva nulla a questo — chiedeva due volte lo stesso
  // fatto e la seconda risposta non arrivava da nessuna parte: al provider
  // viaggia `dataNascita`, e la barriera che conta è il CHECK su
  // `profiles.dob`. Vedi `src/lib/age.ts`.
  const valid =
    username.trim().length >= 3 &&
    email.includes("@") &&
    password.length >= 6 &&
    dob !== "" &&
    dobError === null &&
    terms;

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

          {/*
            Una sola casella per entrambe le strade. Il consenso è la condizione
            per creare un account su Vinea, non una formalità del form email:
            chi arriva da Google crea un account esattamente come chi compila i
            campi qui sopra, quindi la stessa accettazione vale per entrambi e
            il testo lo dice. Una seconda casella accanto ai pulsanti social
            avrebbe chiesto due volte la stessa cosa lasciando aperta la domanda
            su quale delle due risposte fosse quella vincolante.
          */}
          <ConsentCheckbox checked={terms} onCheckedChange={setTerms} testId="consenso-termini">
            Accetto i{" "}
            <Link href="/legale#termini" className="text-bordeaux underline-offset-2 hover:underline">
              Termini
            </Link>{" "}
            e la{" "}
            <Link href="/legale#privacy" className="text-bordeaux underline-offset-2 hover:underline">
              Privacy
            </Link>{" "}
            di Vinea. Vale per la creazione dell&apos;account con qualsiasi metodo, email o
            Google.
          </ConsentCheckbox>
          {/*
            Dichiarazione auto-riferita, non verifica documentale: nessun documento
            viene richiesto o caricato. Il controllo 18+ è applicato sia lato client
            (isMaggiorenne sulla data qui sopra) sia lato server dal CHECK su
            profiles.dob. Richiede validazione legale prima del lancio pubblico
            reale — vedi "Cosa NON è ancora deciso" in docs/ROADMAP_V1.md.
          */}
          <p className="flex items-start gap-2 rounded-xl border border-oro/30 bg-oro/5 p-3 text-xs text-antracite/80">
            <ShieldAlert className="mt-0.5 h-3.5 w-3.5 shrink-0 text-bordeaux" aria-hidden />
            <span>
              Vinea è riservato ai maggiorenni. L&apos;età viene <b>dichiarata da te</b> con la data
              di nascita: non chiediamo né verifichiamo documenti in questa fase.
            </span>
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
            consensoMancante={
              terms
                ? null
                : "Accetta Termini e Privacy qui sopra per registrarti con Google."
            }
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
