"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useRef, useState } from "react";
import { Building2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { LoadingBlock } from "@/components/vinea/States";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";
import { tokenDaFrammento } from "@/lib/partner/partner";
import { getSupabaseClient } from "@/lib/supabase/client";
import { creaPartnerService } from "@/services/partner-service";

/**
 * Accettazione di un invito Partner.
 *
 * Il token arriva nel frammento (`#t=`), che il browser non manda al server.
 * Appena letto viene tolto dall'indirizzo (resta solo in sessionStorage di
 * questa scheda) così non rimane nella cronologia né in uno screenshot, e
 * sopravvive al giro accedi → ritorno qui nella stessa scheda.
 *
 * Il client non decide se l'invito vale: lo dice `partner_invito_accetta`,
 * che confronta l'email confermata dell'account con quella dell'invito.
 */

const CHIAVE_SESSIONE = "vinea.partner.invito";
const PERCORSO = "/partner/invito";
const ACCEDI = `/accedi?${PARAMETRO_NEXT}=${encodeURIComponent(PERCORSO)}`;
const REGISTRATI = `/registrati?${PARAMETRO_NEXT}=${encodeURIComponent(PERCORSO)}`;

const leggiSessione = (): string | null => {
  try {
    return sessionStorage.getItem(CHIAVE_SESSIONE);
  } catch {
    return null;
  }
};

const scriviSessione = (token: string | null) => {
  try {
    if (token) sessionStorage.setItem(CHIAVE_SESSIONE, token);
    else sessionStorage.removeItem(CHIAVE_SESSIONE);
  } catch {
    // Storage non disponibile: il token resta solo in memoria.
  }
};

type Fase =
  | { tipo: "caricamento" }
  | { tipo: "senza-token" }
  | { tipo: "senza-sessione" }
  | { tipo: "pronto"; email: string | null }
  | { tipo: "errore"; testo: string };

export function PartnerInvitoClient() {
  const router = useRouter();
  const client = useMemo(() => getSupabaseClient(), []);
  const servizio = useMemo(() => creaPartnerService(client), [client]);
  const token = useRef<string | null>(null);
  const [fase, setFase] = useState<Fase>({ tipo: "caricamento" });
  const [inCorso, setInCorso] = useState(false);

  useEffect(() => {
    const dalFrammento = tokenDaFrammento(window.location.hash);
    if (dalFrammento) {
      scriviSessione(dalFrammento);
      window.history.replaceState(null, "", PERCORSO);
    }
    token.current = dalFrammento ?? leggiSessione();

    let attivo = true;
    void (async () => {
      if (!token.current) {
        if (attivo) setFase({ tipo: "senza-token" });
        return;
      }
      const utente = client ? (await client.auth.getUser()).data.user : null;
      if (!attivo) return;
      setFase(utente ? { tipo: "pronto", email: utente.email ?? null } : { tipo: "senza-sessione" });
    })();
    return () => {
      attivo = false;
    };
  }, [client]);

  const accetta = async () => {
    if (!token.current || inCorso) return;
    setInCorso(true);
    const esito = await servizio.accettaInvito(token.current);
    if (esito.ok) {
      scriviSessione(null);
      router.push("/partner");
      return;
    }
    setFase({ tipo: "errore", testo: esito.error });
    setInCorso(false);
  };

  return (
    <section className="mx-auto max-w-xl rounded-2xl border border-border bg-card p-6">
      <h1 className="flex items-center gap-2 font-serif text-3xl">
        <Building2 className="size-7" aria-hidden /> Invito Vinea Partner
      </h1>

      {fase.tipo === "caricamento" ? <LoadingBlock /> : null}

      {fase.tipo === "senza-token" ? (
        <p className="mt-4 text-muted-foreground">
          Il link d&apos;invito non è completo. Riaprilo dal messaggio che hai ricevuto da Vinea,
          copiandolo per intero.
        </p>
      ) : null}

      {fase.tipo === "senza-sessione" ? (
        <div className="mt-4 space-y-4">
          <p className="text-muted-foreground">
            Per accettare l&apos;invito accedi, o registrati, con l&apos;indirizzo email a cui è stato
            inviato. Se ti registri ora, conferma l&apos;email e poi riapri il link d&apos;invito.
          </p>
          <div className="flex flex-wrap gap-2">
            <Button asChild>
              <Link href={ACCEDI}>Accedi</Link>
            </Button>
            <Button asChild variant="outline">
              <Link href={REGISTRATI}>Registrati</Link>
            </Button>
          </div>
        </div>
      ) : null}

      {fase.tipo === "pronto" ? (
        <div className="mt-4 space-y-4">
          <p className="text-muted-foreground">
            Accettando, l&apos;account{fase.email ? <strong> {fase.email}</strong> : null} diventa
            l&apos;amministratore della tua attività su Vinea. Potrai poi inserire i dati
            aziendali e inviarli alla verifica: l&apos;attivazione la decide Vinea.
          </p>
          <Button onClick={() => void accetta()} disabled={inCorso}>
            Accetta l&apos;invito
          </Button>
        </div>
      ) : null}

      {fase.tipo === "errore" ? (
        <div className="mt-4 space-y-4">
          <p role="alert" className="text-destructive">
            {fase.testo}
          </p>
          <Button asChild variant="outline">
            <Link href="/partner">Vai all&apos;area Partner</Link>
          </Button>
        </div>
      ) : null}
    </section>
  );
}
