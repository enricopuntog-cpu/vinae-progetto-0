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

export default function AccediPageClient() {
  const router = useRouter();
  const { authUser, authLoading, authError, authClearError, authLogin, authInviaMagicLink, authLogout } =
    useVinea();

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [inCorso, setInCorso] = useState(false);
  const [magicLinkInviato, setMagicLinkInviato] = useState(false);

  // Errore riportato da /auth/callback quando il flusso OAuth non si completa
  // (provider che rifiuta, code exchange fallito, callback senza code).
  const erroreCallback = useSearchParams().get("errore");
  const erroreDaMostrare = authError ?? erroreCallback;

  const emailValida = email.includes("@");
  const passwordValida = password.length >= 6;

  const accedi = async () => {
    if (!emailValida || !passwordValida) return;
    setInCorso(true);
    const esito = await authLogin(email.trim(), password);
    setInCorso(false);
    if (esito.ok) router.push("/home");
  };

  const magicLink = async () => {
    if (!emailValida) return;
    setInCorso(true);
    const esito = await authInviaMagicLink(email.trim());
    setInCorso(false);
    if (esito.ok) setMagicLinkInviato(true);
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
            <Button asChild className="bg-bordeaux hover:bg-bordeaux/90">
              <Link href="/home">Vai alla Home</Link>
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
              authClearError();
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

        <div className="mt-5 space-y-4">
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
              autoComplete="current-password"
            />
          </div>

          {erroreDaMostrare && (
            <p className="rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-sm text-bordeaux">
              {erroreDaMostrare}
            </p>
          )}

          <Button
            onClick={accedi}
            disabled={!emailValida || !passwordValida || inCorso}
            className="w-full bg-bordeaux hover:bg-bordeaux/90"
          >
            {inCorso ? (
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

          <Button
            variant="outline"
            onClick={magicLink}
            disabled={!emailValida || inCorso}
            className="w-full"
          >
            <Wand2 className="h-4 w-4" /> Inviami un link di accesso
          </Button>

          <SocialAuthButtons etichetta="oppure accedi con" />

          <p className="text-sm text-muted-foreground">
            Non hai un account?{" "}
            <Link href="/registrati" className="text-bordeaux hover:underline">
              Registrati
            </Link>
            .
          </p>
        </div>
      </div>
    </div>
  );
}
