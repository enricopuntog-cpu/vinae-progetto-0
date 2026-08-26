"use client";

import { usePathname, useRouter } from "next/navigation";
import { useEffect } from "react";
import { Button } from "@/components/ui/button";
import { percorsoRelativoSicuro } from "@/lib/auth/origine-redirect";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";
import { useVinea } from "@/lib/vinea-store";

/**
 * Guardia universale sul profilo autenticato. Gli ospiti navigano come prima;
 * una sessione, invece, passa soltanto dopo una lettura riuscita della riga
 * completa. Attesa ed errore coprono il contenuto, senza query locali.
 */
const PERCORSI_CONSENTITI = [
  "/completa-profilo",
  "/accedi",
  "/registrati",
  "/auth",
  "/legale",
];

const percorsoConsentito = (pathname: string) =>
  PERCORSI_CONSENTITI.some((percorso) =>
    pathname === percorso || pathname.startsWith(`${percorso}/`),
  );

export function AgeGate() {
  const pathname = usePathname();
  const router = useRouter();
  const {
    authUser,
    authLoading,
    authStatoEta,
    authRicaricaProfilo,
    authLogout,
  } = useVinea();
  const consentito = percorsoConsentito(pathname);

  useEffect(() => {
    if (authLoading || !authUser || consentito || authStatoEta !== "da_completare") return;

    const next = percorsoRelativoSicuro(pathname) ?? "/home";
    router.replace(`/completa-profilo?${PARAMETRO_NEXT}=${encodeURIComponent(next)}`);
  }, [authUser, authLoading, authStatoEta, consentito, pathname, router]);

  // Le route pubbliche necessarie restano disponibili anche mentre Supabase
  // risolve la sessione. Altrove, finché non sappiamo se il visitatore è un
  // ospite o un utente autenticato, il contenuto resta coperto: altrimenti una
  // sessione persistita vedrebbe per un istante una pagina protetta.
  if (consentito) return null;

  if (authLoading) {
    return (
      <div
        role="status"
        aria-live="polite"
        className="fixed inset-0 z-50 grid place-items-center bg-background/95 p-4"
      >
        <p className="rounded-2xl border border-border bg-card px-5 py-4 text-sm text-muted-foreground shadow-lg">
          Verifica dell&apos;accesso…
        </p>
      </div>
    );
  }

  if (!authUser || authStatoEta === "completo") return null;

  if (authStatoEta === "errore_lettura") {
    return (
      <div
        role="alert"
        aria-live="assertive"
        className="fixed inset-0 z-50 grid place-items-center bg-background/95 p-4"
      >
        <div className="w-full max-w-md rounded-3xl border border-border bg-card p-6 shadow-xl">
          <h2 className="font-serif text-2xl">Non riusciamo a verificare il tuo profilo.</h2>
          <p className="mt-2 text-sm text-muted-foreground">
            Riprova la lettura oppure esci dall&apos;account.
          </p>
          <div className="mt-5 flex flex-col gap-2 sm:flex-row">
            <Button onClick={() => void authRicaricaProfilo()} className="bg-bordeaux hover:bg-bordeaux/90">
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

  return (
    <div
      role="status"
      aria-live="polite"
      className="fixed inset-0 z-50 grid place-items-center bg-background/95 p-4"
    >
      <p className="rounded-2xl border border-border bg-card px-5 py-4 text-sm text-muted-foreground shadow-lg">
        Verifica del profilo…
      </p>
    </div>
  );
}
