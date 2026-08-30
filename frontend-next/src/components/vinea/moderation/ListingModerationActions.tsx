"use client";

// Le azioni dirette su un annuncio, condivise fra il dialogo della pratica e la
// scheda Annunci delle Operazioni Admin.
//
// Nessuna porta nuova: il comando e sempre `moderazione_annuncio_*` attraverso
// `transizioneAnnuncio` del controller di Fase 9, la stessa che il dialogo della
// segnalazione usa gia. Qui c'e solo la parte che mancava — quali transizioni
// proporre, come chiederne conferma e cosa dire quando la rilettura fallisce.

import { useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Phase9Error } from "@/services/phase9/shared";
import type { TransizioneAnnuncio } from "@/services/phase9/supabase-moderation-service";

// Gli stati di partenza sono quelli dichiarati dalle cinque porte SQL
// (20260810180000, parte E): ogni funzione pubblica passa al motore il proprio
// array di stati ammessi, e il motore rifiuta comunque `riservato` e `venduto`.
// Ripeterli qui non allarga nulla — un pulsante in piu verrebbe respinto dal
// database — ma evita di proporre un comando destinato a fallire.
const ORIGINI: Record<TransizioneAnnuncio, readonly string[]> = {
  in_revisione: ["bozza", "modifiche_richieste", "attivo", "sospeso"],
  modifiche_richieste: ["bozza", "in_revisione", "attivo"],
  sospeso: ["bozza", "in_revisione", "modifiche_richieste", "attivo"],
  rifiutato: ["bozza", "in_revisione", "modifiche_richieste", "attivo", "sospeso"],
  attivo: ["in_revisione", "modifiche_richieste", "sospeso", "rifiutato"],
};

// L'ordine di presentazione va dal provvedimento piu lieve al piu grave, con il
// ripristino in fondo: e l'ordine in cui si decide, non quello alfabetico.
const ORDINE: readonly TransizioneAnnuncio[] = [
  "in_revisione",
  "modifiche_richieste",
  "sospeso",
  "rifiutato",
  "attivo",
];

export const transizioniAmmesse = (stato: string | null | undefined): TransizioneAnnuncio[] =>
  stato ? ORDINE.filter((transizione) => ORIGINI[transizione].includes(stato)) : [];

export const TRANSIZIONE_UX: Record<
  TransizioneAnnuncio,
  { nome: string; effetto: string; cta: string; fatto: string; sensibile: boolean }
> = {
  in_revisione: {
    nome: "Metti in revisione",
    effetto: "L'annuncio torna in revisione e non e piu acquistabile finche non viene riattivato.",
    cta: "Metti in revisione",
    fatto: "Annuncio messo in revisione.",
    sensibile: false,
  },
  modifiche_richieste: {
    nome: "Richiedi modifiche",
    effetto: "L'annuncio passa in «modifiche richieste»: il venditore vede la motivazione e puo correggerlo.",
    cta: "Richiedi modifiche",
    fatto: "Modifiche richieste al venditore.",
    sensibile: false,
  },
  sospeso: {
    nome: "Sospendi",
    effetto: "L'annuncio viene sospeso e sparisce dal catalogo pubblico.",
    cta: "Conferma sospensione",
    fatto: "Annuncio sospeso.",
    sensibile: true,
  },
  rifiutato: {
    nome: "Rimuovi dal catalogo",
    effetto: "L'annuncio passa a «rifiutato» e resta fuori dal catalogo finche non viene ripristinato.",
    cta: "Conferma rimozione",
    fatto: "Annuncio rimosso dal catalogo.",
    sensibile: true,
  },
  attivo: {
    nome: "Ripristina",
    effetto: "L'annuncio torna attivo e visibile nel catalogo.",
    cta: "Conferma ripristino",
    fatto: "Annuncio ripristinato.",
    sensibile: false,
  },
};

// Phase9Error ferma gia il messaggio grezzo di Postgres: qui si aggiunge solo
// la lettura dei codici che le RPC sollevano di proposito, perche «non sei
// autorizzato» e «lo stato e cambiato sotto le mani» chiedono due reazioni
// diverse all'operatore.
export const messaggioAzione = (errore: unknown): string => {
  if (errore instanceof Phase9Error) {
    if (errore.code === "42501") return "Non hai i permessi per eseguire questa azione.";
    if (errore.code === "22023") return "Una motivazione e obbligatoria.";
    // P0001 copre anche stato cambiato o pratica gia chiusa. Il messaggio della
    // porta non raggiunge la UI: resta mediato per non esporre dettagli SQL.
    if (errore.code === "P0001") {
      return "Lo stato e cambiato oppure la pratica e gia chiusa. Aggiorna i dati e riprova.";
    }
    return "Azione non riuscita. Aggiorna i dati e riprova.";
  }
  return "Azione non riuscita. Controlla la connessione e riprova.";
};

type Props = {
  listingId: string;
  /** Lo stato corrente dell'annuncio; da qui si deriva cosa e proponibile. */
  stato: string | null;
  /** La chiave dell'azione in volo nel controller, per fermare il doppio invio. */
  inCorso: string | null;
  /** Null quando il servizio non e disponibile: senza porta non ci sono comandi. */
  onTransizione:
    | ((listingId: string, transizione: TransizioneAnnuncio, motivazione: string) => Promise<void>)
    | null;
  /** Rilegge la scheda dopo l'azione. Vero se la rilettura e riuscita. */
  onAggiorna: () => Promise<boolean>;
};

export const ListingModerationActions = ({
  listingId,
  stato,
  inCorso,
  onTransizione,
  onAggiorna,
}: Props) => {
  const [scelta, setScelta] = useState<TransizioneAnnuncio | null>(null);
  const [motivazione, setMotivazione] = useState("");
  const [errore, setErrore] = useState<string | null>(null);
  const [esito, setEsito] = useState<string | null>(null);
  const [invio, setInvio] = useState(false);
  // Il `ref` chiude la finestra fra il click e il primo render disabilitato: lo
  // stato React non e ancora aggiornato quando arriva il secondo click.
  const invioLocale = useRef(false);

  const ammesse = transizioniAmmesse(stato);
  const occupato = invio || inCorso !== null;
  const pronta = motivazione.trim().length > 0;

  const esegui = async () => {
    if (!scelta || !onTransizione || !pronta || occupato || invioLocale.current) return;
    invioLocale.current = true;
    setInvio(true);
    setErrore(null);
    setEsito(null);
    try {
      await onTransizione(listingId, scelta, motivazione);
    } catch (e) {
      // La scrittura non e passata: il dialogo resta aperto con il testo gia
      // scritto, cosi chi riprova non lo riscrive.
      setErrore(messaggioAzione(e));
      invioLocale.current = false;
      setInvio(false);
      return;
    }

    // Da qui in poi la scrittura e avvenuta. Un aggiornamento fallito e un
    // problema di lettura: ripetere la mutazione la eseguirebbe due volte, e su
    // una sospensione due volte non e come una volta.
    let aggiornato = false;
    try {
      aggiornato = await onAggiorna();
    } catch {
      aggiornato = false;
    }
    setEsito(
      aggiornato
        ? TRANSIZIONE_UX[scelta].fatto
        : "Azione eseguita, aggiornamento dei dati non riuscito. Ricarica la scheda.",
    );
    setScelta(null);
    setMotivazione("");
    invioLocale.current = false;
    setInvio(false);
  };

  const chiudi = () => {
    if (occupato) return;
    setScelta(null);
    setErrore(null);
  };

  return (
    <div className="space-y-3 border-t pt-3" data-testid="admin-listing-actions">
      <p className="text-xs font-medium uppercase text-muted-foreground">Azioni sull&apos;annuncio</p>

      {esito ? (
        <p role="status" data-testid="admin-listing-action-esito" className="rounded-md border p-2 text-xs">
          {esito}
        </p>
      ) : null}

      {!onTransizione ? (
        <p className="text-xs text-muted-foreground" data-testid="admin-listing-actions-unavailable">
          Le azioni non sono disponibili in questa configurazione.
        </p>
      ) : ammesse.length === 0 ? (
        <p className="text-xs text-muted-foreground" data-testid="admin-listing-actions-none">
          Nessuna transizione di moderazione e ammessa nello stato attuale.
        </p>
      ) : (
        <div className="flex flex-wrap gap-2">
          {ammesse.map((transizione) => (
            <Button
              key={transizione}
              variant="outline"
              size="sm"
              data-testid={`admin-listing-action-${transizione}`}
              disabled={occupato}
              onClick={() => {
                setScelta(transizione);
                setErrore(null);
                setEsito(null);
                setMotivazione("");
              }}
            >
              {TRANSIZIONE_UX[transizione].nome}
            </Button>
          ))}
        </div>
      )}

      {/*
        Nessun comando oltre le cinque transizioni: cancellazione, «venduto»,
        «riservato», compensi e movimenti sull'ordine non passano da qui, e il
        motore SQL rifiuta comunque un annuncio venduto o riservato.
      */}
      <p className="text-xs text-muted-foreground">
        Da qui si cambia solo la visibilita dell&apos;annuncio: nessuna azione su ordini, compensi o account.
      </p>

      {scelta ? (
        <Dialog open onOpenChange={(aperto) => !aperto && chiudi()}>
          <DialogContent className="max-w-lg" data-testid="admin-listing-action-dialog">
            <DialogHeader>
              <DialogTitle className="font-serif text-xl">{TRANSIZIONE_UX[scelta].nome}</DialogTitle>
            </DialogHeader>

            <div className="space-y-3 text-sm">
              <p>{TRANSIZIONE_UX[scelta].effetto}</p>
              {TRANSIZIONE_UX[scelta].sensibile ? (
                <p
                  className="rounded-md border border-bordeaux/40 bg-bordeaux/5 p-2 text-xs text-bordeaux"
                  data-testid="admin-listing-action-warning"
                >
                  Il venditore vede la motivazione. Conferma solo se la decisione e presa.
                </p>
              ) : null}

              <div>
                <Label htmlFor="admin-listing-motivazione">Motivazione (obbligatoria)</Label>
                <Textarea
                  id="admin-listing-motivazione"
                  data-testid="admin-listing-action-motivazione"
                  rows={3}
                  value={motivazione}
                  onChange={(e) => setMotivazione(e.target.value)}
                  placeholder="Spiega la decisione presa"
                  className="mt-1"
                  disabled={occupato}
                />
              </div>

              {errore ? (
                <p
                  role="alert"
                  data-testid="admin-listing-action-error"
                  className="rounded-md border border-bordeaux/40 bg-bordeaux/5 p-2 text-xs text-bordeaux"
                >
                  {errore}
                </p>
              ) : null}
            </div>

            <DialogFooter className="gap-2">
              <Button variant="ghost" onClick={chiudi} disabled={occupato}>
                Annulla
              </Button>
              <Button
                data-testid="admin-listing-action-confirm"
                disabled={!pronta || occupato}
                onClick={() => void esegui()}
              >
                {occupato ? "Esecuzione…" : TRANSIZIONE_UX[scelta].cta}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      ) : null}
    </div>
  );
};
