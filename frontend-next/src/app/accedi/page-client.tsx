"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";
import { LogIn, Mail, Wand2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SocialAuthButtons } from "@/components/vinea/SocialAuthButtons";
import { useVinea } from "@/lib/vinea-store";
import { percorsoRelativoSicuro } from "@/lib/auth/origine-redirect";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";
import {
  codiceErroreAuth,
  messaggioErroreAuth,
  type CodiceErroreAuth,
} from "@/lib/auth/errori-auth";

/**
 * Superficie di accesso: password, magic link e social convivono qui.
 *
 * Tre gesti sulla stessa schermata vogliono tre stati separati. Fino a D5 ce
 * n'era uno solo — un booleano `inCorso` e un `authError` di dominio — e la
 * conseguenza si vedeva: chiedere il magic link disabilitava il pulsante
 * Google, e un rifiuto di Google compariva sotto il campo password come se la
 * password fosse sbagliata. Ora ogni operazione dice il proprio nome
 * (`inCorso`) e ogni errore vive accanto al pulsante che lo ha prodotto.
 *
 * Dell'errore che torna dalla callback nell'URL si sa **da quale gesto viene**,
 * perché il codice lo dice: i codici `oauth-*` appartengono al giro social e
 * scendono nel riquadro di quel gruppo di pulsanti; gli altri riguardano il
 * viaggio di ritorno (nessun code da scambiare, scambio fallito) e stanno in
 * cima, dove non accusano nessun campo.
 */
export default function AccediPageClient() {
  const router = useRouter();
  const { authUser, authLoading, authLogin, authInviaMagicLink, authLogout } = useVinea();

  const parametri = useSearchParams();
  /**
   * Dove l'utente stava andando prima di essere mandato qui. Solo percorsi
   * relativi: `percorsoRelativoSicuro` è la stessa funzione che difende la
   * callback, quindi un URL assoluto o `//altrove` non diventa una
   * destinazione né qui né là.
   */
  const next = percorsoRelativoSicuro(parametri.get(PARAMETRO_NEXT));
  const destinazione = next ?? "/home";
  // Il parametro è testo che arriva dall'indirizzo: vale solo se è una delle
  // voci del vocabolario applicativo, altrimenti è un errore generico.
  const parametroErrore = parametri.get("errore");
  const erroreRitorno = parametroErrore ? codiceErroreAuth(parametroErrore) : null;
  const erroreSocialIniziale =
    erroreRitorno && erroreRitorno.startsWith("oauth-") ? erroreRitorno : null;
  const erroreRitornoNonSocial = erroreRitorno && !erroreSocialIniziale ? erroreRitorno : null;

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  /** Quale operazione è davvero in corso, non «una qualsiasi». */
  const [inCorso, setInCorso] = useState<"password" | "magic-link" | null>(null);
  const [errorePassword, setErrorePassword] = useState<CodiceErroreAuth | null>(null);
  const [erroreMagicLink, setErroreMagicLink] = useState<CodiceErroreAuth | null>(null);
  const [magicLinkInviato, setMagicLinkInviato] = useState(false);
  /**
   * L'errore nell'URL appartiene al tentativo precedente e il parametro resta
   * nell'indirizzo anche dopo: senza questo, ricomincerebbe a mostrarsi appena
   * un nuovo tentativo pulisce il proprio errore.
   */
  const [ritornoScartato, setRitornoScartato] = useState(false);
  const ritornoDaMostrare = ritornoScartato ? null : erroreRitornoNonSocial;

  const emailValida = email.includes("@");
  const passwordValida = password.length >= 6;

  const aggiornaEmail = (valore: string) => {
    setEmail(valore);
    // L'errore riguardava le credenziali di prima: da qui in poi non le
    // descrive più.
    setErrorePassword(null);
    setErroreMagicLink(null);
  };

  const aggiornaPassword = (valore: string) => {
    setPassword(valore);
    setErrorePassword(null);
  };

  const accedi = async () => {
    if (inCorso) return;
    if (!emailValida || !passwordValida) return;
    setRitornoScartato(true);
    setErrorePassword(null);
    setInCorso("password");
    const esito = await authLogin(email.trim(), password);
    setInCorso(null);
    if (!esito.ok) {
      setErrorePassword(esito.error);
      return;
    }
    router.push(destinazione);
  };

  const magicLink = async () => {
    if (inCorso) return;
    if (!emailValida) return;
    setRitornoScartato(true);
    setErroreMagicLink(null);
    setInCorso("magic-link");
    // La destinazione viaggia con il link: chi rientra dalla posta torna dove
    // stava andando, non su una Home che non aveva chiesto.
    const esito = await authInviaMagicLink(email.trim(), { superficie: "accedi", next });
    setInCorso(null);
    if (!esito.ok) {
      setErroreMagicLink(esito.error);
      return;
    }
    setMagicLinkInviato(true);
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

  if (authUser) {
    return (
      <div className="mx-auto max-w-md space-y-6">
        <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
          <h1 className="font-serif text-2xl md:text-3xl">Sei autenticato</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Account attivo: <b>{authUser.email ?? authUser.userId}</b>.
          </p>
          <div className="mt-5 flex flex-col gap-2 sm:flex-row">
            {/*
              Nessun redirect automatico: chi arriva qui con una sessione
              spesso ci arriva per uscirne o per cambiare account, e portarlo
              via di forza gli toglie proprio il pulsante che cercava. La
              destinazione richiesta resta però la meta proposta.
            */}
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

  if (magicLinkInviato) {
    return (
      <div className="mx-auto max-w-md space-y-6">
        <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
          <h1 className="font-serif text-2xl md:text-3xl">Link inviato</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Abbiamo inviato un link di accesso a <b>{email}</b>. Aprilo da questo browser per
            entrare.
          </p>
          <div className="mt-5 flex items-start gap-3 rounded-2xl border border-border bg-crema p-4">
            <Mail className="mt-0.5 h-6 w-6 shrink-0 text-bordeaux" />
            <p className="min-w-0 text-sm text-antracite/80">
              Se non trovi il messaggio, controlla la cartella spam.
            </p>
          </div>
          <Button
            variant="outline"
            className="mt-5"
            onClick={() => {
              setMagicLinkInviato(false);
              setErroreMagicLink(null);
            }}
          >
            Torna all&apos;accesso
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-md space-y-6">
      <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
        <h1 className="font-serif text-2xl md:text-3xl">Accedi a Vinea</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Usa email e password, oppure ricevi un link di accesso senza password.
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
          <div>
            <Label htmlFor="email">Email</Label>
            <Input
              id="email"
              type="email"
              value={email}
              onChange={(e) => aggiornaEmail(e.target.value)}
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
              onChange={(e) => aggiornaPassword(e.target.value)}
              placeholder="almeno 6 caratteri"
              autoComplete="current-password"
            />
          </div>

          {errorePassword && (
            <p
              role="alert"
              data-testid="errore-password"
              className="rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-sm text-bordeaux"
            >
              {messaggioErroreAuth(errorePassword)}
            </p>
          )}

          <Button
            onClick={accedi}
            disabled={!emailValida || !passwordValida || inCorso !== null}
            aria-busy={inCorso === "password"}
            data-testid="accedi-password"
            className="w-full bg-bordeaux hover:bg-bordeaux/90"
          >
            {inCorso === "password" ? (
              "Accesso…"
            ) : (
              <>
                <LogIn className="h-4 w-4" /> Accedi
              </>
            )}
          </Button>

          <div className="flex items-center gap-3">
            <span className="h-px flex-1 bg-border" />
            <span className="text-xs uppercase tracking-wide text-muted-foreground">oppure</span>
            <span className="h-px flex-1 bg-border" />
          </div>

          {erroreMagicLink && (
            <p
              role="alert"
              data-testid="errore-magic-link"
              className="rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-sm text-bordeaux"
            >
              {messaggioErroreAuth(erroreMagicLink)}
            </p>
          )}

          <Button
            variant="outline"
            onClick={magicLink}
            disabled={!emailValida || inCorso !== null}
            aria-busy={inCorso === "magic-link"}
            data-testid="accedi-magic-link"
            className="w-full"
          >
            <Wand2 className="h-4 w-4" />
            {inCorso === "magic-link" ? "Invio del link…" : "Inviami un link di accesso"}
          </Button>

          <SocialAuthButtons
            etichetta="oppure accedi con"
            superficie="accedi"
            next={next}
            erroreIniziale={erroreSocialIniziale}
          />

          <p className="text-sm text-muted-foreground">
            Non hai un account?{" "}
            <Link
              href={next ? `/registrati?${PARAMETRO_NEXT}=${encodeURIComponent(next)}` : "/registrati"}
              className="text-bordeaux hover:underline"
            >
              Registrati
            </Link>
            .
          </p>
        </div>
      </div>
    </div>
  );
}
