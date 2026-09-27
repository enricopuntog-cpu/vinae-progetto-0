"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { MapPin, Wine } from "lucide-react";
import { AvatarPersona } from "@/components/vinea/AvatarPersona";
import { EmptyState, ErrorState, LoadingBlock } from "@/components/vinea/States";
import { routes } from "@/config/routes";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";
import { getSupabaseClient } from "@/lib/supabase/client";
import { useVinea } from "@/lib/vinea-store";
import {
  CANTINE_SEGUITE_PER_PAGINA,
  RICHIESTA_PER_PAGINA,
  creaCellarFollowService,
} from "@/services/cellar-follow-service";
import type { CantinaSeguita, CursoreCantinaSeguita } from "@/services/types";

/** Dove torna chi deve prima accedere. Scritto, non dedotto da un dato in arrivo. */
const PERCORSO_ACCESSO = `/accedi?${PARAMETRO_NEXT}=%2Fcantine-seguite`;

/**
 * Una Cantina seguita, come scheda.
 *
 * Mostra l'identità pubblica e quante bottiglie sono esposte, e nient'altro:
 * `cantine_seguite_page` restituisce sette colonne e nessuna di esse è privata —
 * niente email, niente valore, niente stato di moderazione, niente conteggio di
 * chi altro la segue. Non c'è un `if` che li nasconda, perché non arrivano.
 */
function SchedaCantinaSeguita({ cantina }: { cantina: CantinaSeguita }) {
  const localita = [cantina.citta, cantina.provincia].filter(Boolean).join(", ");
  const nome = cantina.username || "Cantina senza nome";

  return (
    <li className="flex flex-col rounded-3xl border border-border bg-card p-4">
      <div className="flex items-center gap-3">
        <AvatarPersona
          avatarUrl={cantina.avatarUrl}
          proprietarioId={cantina.ownerId}
          alt={`Avatar di ${nome}`}
          className="h-12 w-12 shrink-0"
        />
        <div className="min-w-0 flex-1">
          <p className="break-words font-medium">{nome}</p>
          {localita && (
            <p className="mt-0.5 flex items-center gap-1 text-sm text-muted-foreground">
              <MapPin className="h-3.5 w-3.5 shrink-0" aria-hidden />
              {localita}
            </p>
          )}
        </div>
      </div>

      <p className="mt-3 flex items-center gap-1.5 text-sm text-muted-foreground">
        <Wine className="h-4 w-4 shrink-0" aria-hidden />
        {/*
         * Zero bottiglie è una risposta, non un dato mancante: una Cantina
         * pubblica ancora vuota resta seguita e resta in elenco. Nasconderla
         * farebbe sparire proprio la Cantina che si segue per aspettare la prima
         * pubblicazione.
         */}
        {cantina.bottigliePubbliche === 0
          ? "Nessuna bottiglia pubblica al momento"
          : cantina.bottigliePubbliche === 1
            ? "1 bottiglia pubblica"
            : `${cantina.bottigliePubbliche} bottiglie pubbliche`}
      </p>

      <Link
        href={routes.cantinaPubblica(cantina.ownerId)}
        // Il nome della Cantina sta nel collegamento: «Visita la Cantina» da solo,
        // ripetuto ventiquattro volte, non dice a quale porta.
        aria-label={`Visita la Cantina di ${nome}`}
        className="mt-4 inline-flex items-center justify-center rounded-full border border-border px-3 py-1.5 text-sm font-medium hover:bg-secondary"
      >
        Visita la Cantina
      </Link>
    </li>
  );
}

/**
 * L'elenco caricato, con scritto dentro di chi è.
 *
 * `utenteId` non è un dato da mostrare: è ciò che rende la vista una
 * derivazione. Un elenco che porta l'identificativo di un'altra persona non si
 * mostra, e non serve un effetto che lo ripulisca a ogni cambio di sessione —
 * ripulire un risultato derivato appartiene a una derivazione, mai a un effetto
 * (la stessa lezione di `lib/phase12/club-view.ts` e di `/esplora`).
 */
type Elenco = {
  utenteId: string;
  cantine: CantinaSeguita[];
  inCorso: boolean;
  errore: string | null;
  altraPagina: boolean;
};

/**
 * Nessun elenco per questa persona: quindi la prima pagina sta arrivando.
 *
 * `inCorso: true` è deliberato. Con `false` il primo disegno — quello prima che
 * l'effetto parta — mostrerebbe «Non segui ancora nessuna Cantina» a chi invece
 * ne segue ventiquattro.
 */
const IN_ATTESA: Elenco = {
  utenteId: "",
  cantine: [],
  inCorso: true,
  errore: null,
  altraPagina: false,
};

/** Chi è il destinatario legittimo della prossima risposta. Vedi `SeguiCantinaButton`. */
type Lettore = { utenteId: string };

/**
 * «Le mie Cantine».
 *
 * ## Otto stati, e nessuno che si sovrapponga a un altro
 *
 * Sessione ignota, sessione assente, prima pagina in arrivo, prima pagina
 * fallita, elenco vuoto, elenco, pagina successiva in arrivo, pagina successiva
 * fallita. L'ultimo è quello che si sbaglia più facilmente: un errore sul
 * «mostra altre» **non** porta via le Cantine già a schermo, perché quelle sono
 * arrivate e sono ancora valide.
 *
 * ## Paginazione a cursore, senza conteggi
 *
 * Si chiedono venticinque righe e se ne mostrano ventiquattro: la
 * venticinquesima non è una Cantina in più, è la risposta alla domanda «esiste
 * una pagina dopo». Il cursore della prossima richiesta esce dall'ultima riga
 * **mostrata**, non dall'ultima ricevuta — sarebbe la riga di sonda, e salterebbe
 * una Cantina a ogni pagina.
 *
 * Nessun conteggio totale: `cantine_seguite_page` non lo restituisce e un
 * `count(*)` sarebbe una seconda lettura che può divergere dalla prima.
 *
 * ## Nessun grafo pubblico, in nessuna direzione
 *
 * Questa pagina risponde solo alla domanda «quali Cantine seguo io». La domanda
 * opposta — chi segue una Cantina, e quante persone — non ha una porta che la
 * esponga, e questa pagina non ne è il primo passo.
 */
export function CantineSeguitePageClient() {
  const { authUser, authLoading } = useVinea();
  const [elenco, setElenco] = useState<Elenco>(IN_ATTESA);
  const lettoreRef = useRef<Lettore | null>(null);
  const utenteId = authUser?.userId ?? null;

  // L'elenco dell'altra persona non si mostra: qui, e non dentro un effetto.
  const vista = utenteId !== null && elenco.utenteId === utenteId ? elenco : IN_ATTESA;

  const leggi = useCallback(async (token: Lettore, cursore: CursoreCantinaSeguita | null) => {
    const esito = await creaCellarFollowService(getSupabaseClient()).pagina({
      cursore,
      limite: RICHIESTA_PER_PAGINA,
    });

    // Una risposta che appartiene a un'altra sessione non entra in elenco.
    if (lettoreRef.current !== token) return;

    setElenco((precedente) => {
      const base = precedente.utenteId === token.utenteId ? precedente : IN_ATTESA;

      if (!esito.ok) {
        // L'elenco già a schermo resta: non è diventato falso perché una
        // richiesta successiva è stata rifiutata.
        return { ...base, utenteId: token.utenteId, inCorso: false, errore: esito.error };
      }

      const ricevute = esito.data;
      // La riga di sonda non si mostra e non entra nel cursore.
      const daMostrare = ricevute.slice(0, CANTINE_SEGUITE_PER_PAGINA);
      // Difesa d'interfaccia: il cursore è stretto e non dovrebbe ripetere
      // nulla, ma una Cantina duplicata romperebbe le `key` di React, e una riga
      // vista due volte è meno grave di un elenco che smette di aggiornarsi.
      const viste = new Set(base.cantine.map((c) => c.ownerId));
      return {
        utenteId: token.utenteId,
        cantine:
          cursore === null
            ? daMostrare
            : [...base.cantine, ...daMostrare.filter((c) => !viste.has(c.ownerId))],
        inCorso: false,
        errore: null,
        altraPagina: ricevute.length > CANTINE_SEGUITE_PER_PAGINA,
      };
    });
  }, []);

  useEffect(() => {
    if (!utenteId) {
      // Uscita, o mai entrato: la risposta ancora in volo non ha più un
      // destinatario. Nessuno `setState` qui — la vista è già derivata.
      lettoreRef.current = null;
      return;
    }

    const token: Lettore = { utenteId };
    lettoreRef.current = token;
    void leggi(token, null);
  }, [leggi, utenteId]);

  const riparti = useCallback(() => {
    const token = lettoreRef.current;
    if (!token) return;
    setElenco({ ...IN_ATTESA, utenteId: token.utenteId });
    void leggi(token, null);
  }, [leggi]);

  const mostraAltre = useCallback(() => {
    const token = lettoreRef.current;
    const ultima = vista.cantine[vista.cantine.length - 1];
    // Il cursore esce dall'ultima riga **mostrata**: entrambi i termini insieme,
    // perché la funzione SQL rifiuta con `22023` un istante senza il suo
    // identificativo.
    if (!token || !ultima || vista.inCorso) return;
    setElenco((precedente) => ({ ...precedente, inCorso: true, errore: null }));
    void leggi(token, { followedAt: ultima.followedAt, ownerId: ultima.ownerId });
  }, [leggi, vista]);

  if (authLoading) return <LoadingBlock label="Verifica dell'accesso" />;

  if (!authUser) {
    return (
      <div className="space-y-6">
        <Intestazione />
        <EmptyState
          title="Accedi per vedere le Cantine che segui"
          message="Le Cantine che segui sono private: compaiono solo a te, dopo l'accesso."
          action={
            <Link
              href={PERCORSO_ACCESSO}
              className="inline-flex items-center rounded-full bg-bordeaux px-4 py-2 text-sm font-medium text-white hover:bg-bordeaux/90"
            >
              Vai all&apos;accesso
            </Link>
          }
        />
      </div>
    );
  }

  const { cantine, inCorso, errore, altraPagina } = vista;

  if (inCorso && cantine.length === 0 && errore === null) {
    return (
      <div className="space-y-6">
        <Intestazione />
        <LoadingBlock label="Caricamento delle Cantine che segui" />
      </div>
    );
  }

  // Prima pagina fallita: non c'è nessun elenco da preservare, quindi qui
  // l'errore prende la pagina — con un «Riprova» che riparte dalla prima.
  if (errore && cantine.length === 0) {
    return (
      <div className="space-y-6">
        <Intestazione />
        <ErrorState message={errore} onRetry={riparti} />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <Intestazione />

      {cantine.length === 0 ? (
        <EmptyState
          title="Non segui ancora nessuna Cantina"
          message="Quando trovi una Cantina che ti interessa, premi «Segui» sulla sua pagina: la ritrovi qui."
          icon={Wine}
          action={
            <Link
              href={routes.ricerca}
              className="inline-flex items-center rounded-full border border-border px-4 py-2 text-sm font-medium hover:bg-secondary"
            >
              Esplora Vinea
            </Link>
          }
        />
      ) : (
        <>
          <ul aria-busy={inCorso} className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {cantine.map((cantina) => (
              <SchedaCantinaSeguita key={cantina.ownerId} cantina={cantina} />
            ))}
          </ul>

          {/* L'errore della pagina successiva sta qui sotto, accanto al comando
              che lo ha prodotto, e l'elenco sopra resta intatto. */}
          {errore && (
            <p role="alert" className="text-sm text-red-700">
              {errore}
            </p>
          )}

          {/* Il comando sparisce quando non c'è una pagina dopo: non resta
              disabilitato a suggerire che ci sia altro. */}
          {altraPagina && (
            <button
              type="button"
              onClick={mostraAltre}
              disabled={inCorso}
              data-testid="altre-cantine-seguite"
              className="w-full rounded-2xl border border-border px-4 py-2 text-sm font-medium hover:bg-secondary disabled:opacity-50"
            >
              {inCorso ? "Caricamento…" : "Mostra altre"}
            </button>
          )}
        </>
      )}
    </div>
  );
}

function Intestazione() {
  return (
    <header>
      <h1 className="font-serif text-3xl md:text-4xl">Le mie Cantine</h1>
      <p className="mt-1 text-muted-foreground">Le Cantine che segui</p>
    </header>
  );
}
