"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { Check, Plus } from "lucide-react";
import { toast } from "sonner";
import { routes } from "@/config/routes";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";
import {
  STATO_INIZIALE,
  TOAST_NON_SEGUITA,
  TOAST_SEGUITA,
  azioneFollow,
  descrizioneFollow,
  etichettaFollow,
  followAbilitato,
  followOccupato,
  statoDaEsitoIniziale,
  statoDaEsitoMutazione,
  statoInMutazione,
  type StatoFollow,
} from "@/lib/cantina/segui-cantina-stato";
import { getSupabaseClient } from "@/lib/supabase/client";
import { useVinea } from "@/lib/vinea-store";
import { creaCellarFollowService } from "@/services/cellar-follow-service";

/**
 * Il comando «Segui» nell'intestazione di una Cantina pubblica.
 *
 * ## Che cosa riceve, e perché così poco
 *
 * `ownerId` e `profiloProprio`, e nient'altro. Il primo è già pubblico — sta
 * nell'URL della pagina — e il secondo è un booleano che la pagina resa dal
 * server ha già calcolato confrontando `auth.getUser()` con il proprietario del
 * profilo. Nessun dato privato attraversa il confine server/client per far
 * funzionare questo bottone: non gli serve l'email di nessuno, non gli serve lo
 * stato di moderazione del profilo, non gli serve il valore della Cantina.
 *
 * ## Il proprietario non lo vede affatto
 *
 * Con `profiloProprio === true` il componente non rende niente — non un comando
 * disabilitato, non «non puoi seguire la tua Cantina». Il database rifiuta quel
 * gesto con `P0001` e la barriera resta là; qui la scelta è non porre la domanda.
 * Un comando disabilitato con quella spiegazione sarebbe rumore su una pagina
 * che per il proprietario ha già il suo comando, «Gestisci la mia cantina».
 *
 * ## L'anonimo vede l'invito ma non chiama il database
 *
 * Senza sessione il comando è un `Link` a `/accedi` con il ritorno a questa
 * stessa Cantina: nessuna RPC parte, perché le tre porte richiedono
 * `authenticated` e una chiamata da anonimo produrrebbe `42501`, cioè un errore
 * mostrato a chi non ha sbagliato nulla. È lo stesso `PARAMETRO_NEXT` usato dagli
 * altri cancelli dell'app, e la destinazione la valida `percorsoRelativoSicuro`
 * all'arrivo.
 *
 * ## Nessuno stato falso, in nessun istante
 *
 * Le transizioni stanno in `lib/cantina/segui-cantina-stato.ts`, dove sono
 * verificabili: in attesa il comando dice «Verifica…», su lettura fallita dice
 * «Segui non disponibile» e **non** «Segui», e su scrittura rifiutata torna
 * esattamente dov'era. Qui restano soltanto l'effetto, le due chiamate e la
 * guardia contro le risposte in ritardo.
 *
 * ## Un guasto qui non porta via la pagina
 *
 * Il componente non rende `null` sull'errore e non solleva: la Cantina, il
 * valore, la collezione e il marketplace continuano a funzionare senza di lui.
 */
export function SeguiCantinaButton({
  ownerId,
  profiloProprio,
}: {
  ownerId: string;
  profiloProprio: boolean;
}) {
  const { authUser, authLoading } = useVinea();
  const [stato, setStato] = useState<StatoFollow>(STATO_INIZIALE);

  /**
   * Chi è il destinatario legittimo della prossima risposta.
   *
   * Stessa guardia di `real-auth-domain.ts`: fra la chiamata e la risposta
   * l'utente può uscire, rientrare o rientrare come qualcun altro. Senza questo
   * confronto la risposta della sessione precedente scriverebbe «Seguita» nella
   * sessione corrente — che è lo stato di un altro utente mostrato a questo.
   */
  type Lettore = { userId: string; ownerId: string };
  const lettoreRef = useRef<Lettore | null>(null);

  const utenteId = authUser?.userId ?? null;

  useEffect(() => {
    // Il proprietario non legge nulla: non c'è comando da popolare.
    if (profiloProprio) {
      lettoreRef.current = null;
      return;
    }

    if (!utenteId) {
      // Uscita, o mai entrato. Lo stato torna all'inizio invece di conservare la
      // risposta di prima: quella riguardava una persona che non è più qui.
      lettoreRef.current = null;
      setStato(STATO_INIZIALE);
      return;
    }

    const token: Lettore = { userId: utenteId, ownerId };
    lettoreRef.current = token;
    setStato(STATO_INIZIALE);

    let annullato = false;
    void creaCellarFollowService(getSupabaseClient())
      .stato(ownerId)
      .then((esito) => {
        // Tre condizioni e non una: il componente può essere già smontato, la
        // sessione può essere cambiata, e una seconda lettura può essere partita.
        if (annullato || lettoreRef.current !== token) return;
        setStato(statoDaEsitoIniziale(esito));
      });

    return () => {
      annullato = true;
      // Invalida anche una mutazione partita da questa resa: il suo callback non
      // usa `annullato`, perché può partire dopo la lettura iniziale.
      if (lettoreRef.current === token) lettoreRef.current = null;
    };
  }, [ownerId, profiloProprio, utenteId]);

  const premi = useCallback(() => {
    const azione = azioneFollow(stato);
    // Non è una difesa ridondante rispetto a `disabled`: uno stato in volo o
    // ignoto non sa quale delle due scritture mandare, e mandarne una a caso
    // sarebbe peggio del click perduto.
    if (azione === null || !utenteId) return;

    const token = lettoreRef.current;
    if (!token || token.userId !== utenteId || token.ownerId !== ownerId) return;
    setStato(statoInMutazione(stato));

    const servizio = creaCellarFollowService(getSupabaseClient());
    void (azione === "segui" ? servizio.segui(ownerId) : servizio.smetti(ownerId)).then((esito) => {
      if (lettoreRef.current !== token) return;

      setStato((precedente) => statoDaEsitoMutazione(precedente, esito));

      if (!esito.ok) {
        // La frase arriva già mediata dal servizio: il codice PostgreSQL e il
        // nome della funzione restano nei log.
        toast.error(esito.error);
        return;
      }
      // Il toast racconta lo stato che il **database** ha dichiarato, non quello
      // che il click sperava.
      toast.success(esito.data ? TOAST_SEGUITA : TOAST_NON_SEGUITA);
    });
  }, [ownerId, stato, utenteId]);

  if (profiloProprio) return null;

  // Finché la sessione non è nota non si mostra né l'invito ad accedere né il
  // comando: sarebbero due risposte diverse alla stessa domanda, e una delle due
  // lampeggerebbe via un istante dopo.
  if (authLoading) {
    return (
      <span
        className="inline-flex items-center gap-1.5 rounded-full border border-border px-3 py-1.5 text-sm text-muted-foreground"
        aria-busy="true"
        data-testid="segui-cantina-attesa"
      >
        Verifica…
      </span>
    );
  }

  if (!authUser) {
    return (
      <Link
        href={`/accedi?${PARAMETRO_NEXT}=${encodeURIComponent(routes.cantinaPubblica(ownerId))}`}
        className="inline-flex items-center gap-1.5 rounded-full border border-border px-3 py-1.5 text-sm font-medium hover:bg-secondary"
        data-testid="segui-cantina-accedi"
      >
        <Plus className="h-4 w-4" aria-hidden />
        Segui
      </Link>
    );
  }

  const seguita = stato.fase === "seguita" || (stato.fase === "in_corso" && stato.seguita);

  return (
    <button
      type="button"
      onClick={premi}
      disabled={!followAbilitato(stato)}
      aria-busy={followOccupato(stato)}
      aria-pressed={stato.fase === "seguita" || stato.fase === "non_seguita" ? seguita : undefined}
      aria-label={descrizioneFollow(stato)}
      title={descrizioneFollow(stato)}
      data-testid="segui-cantina"
      data-stato={stato.fase}
      className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-sm font-medium disabled:opacity-50 ${
        seguita ? "border-bordeaux bg-bordeaux/10 text-bordeaux" : "border-border hover:bg-secondary"
      }`}
    >
      {/* L'icona accompagna la parola, non la sostituisce: lo stato resta
          leggibile senza distinguere un bordo pieno da un bordo vuoto. */}
      {seguita ? <Check className="h-4 w-4" aria-hidden /> : <Plus className="h-4 w-4" aria-hidden />}
      {etichettaFollow(stato)}
    </button>
  );
}
