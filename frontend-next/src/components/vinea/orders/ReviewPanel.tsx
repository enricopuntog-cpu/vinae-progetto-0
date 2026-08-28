"use client";

import { useRef, useState } from "react";
import { Star } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { ReportDialog } from "@/components/vinea/ReportDialog";
import type {
  EleggibilitaRecensione,
  OrderReviewRecord,
  OrderReviewRispostaRecord,
} from "@/services/types";

/** Il limite del testo è lo stesso del CHECK su `order_reviews.testo`. */
const MAX_TESTO = 2000;
/** Il limite della replica è lo stesso del CHECK su `order_review_risposte.testo`. */
const MAX_RISPOSTA = 1000;

function StelleInput({
  label,
  value,
  onChange,
  disabled,
}: {
  label: string;
  value: number;
  onChange: (n: number) => void;
  disabled: boolean;
}) {
  return (
    <div role="group" aria-label={label}>
      <p className="text-xs text-muted-foreground">{label}</p>
      <div className="mt-1 flex gap-1">
        {[1, 2, 3, 4, 5].map((n) => (
          <button
            key={n}
            type="button"
            disabled={disabled}
            aria-label={`${label}: ${n} su 5`}
            aria-pressed={n === value}
            onClick={() => onChange(n)}
            className="disabled:opacity-50"
          >
            <Star
              aria-hidden
              className={`h-5 w-5 ${n <= value ? "fill-oro text-oro" : "text-muted-foreground"}`}
            />
          </button>
        ))}
      </div>
    </div>
  );
}

function Punteggi({ recensione }: { recensione: OrderReviewRecord }) {
  return (
    <div className="mt-2 flex flex-wrap gap-4 text-xs text-muted-foreground">
      <span>Generale {recensione.voto}/5</span>
      <span>Conformità {recensione.conformita}/5</span>
      <span>Imballaggio {recensione.imballaggio}/5</span>
      <span>Comunicazione {recensione.comunicazione}/5</span>
    </div>
  );
}

/**
 * Il modulo di replica del venditore.
 *
 * Non riceve — e non potrebbe usare — l'identità di chi scrive: la RPC legge
 * `destinatario_id` dalla recensione e rifiuta chiunque altro, compreso
 * l'autore della recensione. Questo componente decide solo se ha senso
 * disegnare il riquadro.
 */
function RispostaForm({
  reviewId,
  inCorso,
  onRispondi,
}: {
  reviewId: string;
  inCorso: boolean;
  onRispondi: (reviewId: string, testo: string) => Promise<string | null>;
}) {
  const [testo, setTesto] = useState("");
  const [errore, setErrore] = useState<string | null>(null);
  const inviando = useRef(false);

  const testoPulito = testo.trim();
  const valido = testoPulito.length >= 1 && testoPulito.length <= MAX_RISPOSTA;

  return (
    <div className="mt-4 border-t border-border pt-4">
      <label htmlFor="risposta-recensione" className="text-sm font-semibold">
        Rispondi pubblicamente
      </label>
      <p className="mt-1 text-xs text-muted-foreground">
        La risposta compare sul tuo profilo insieme alla recensione. Se ne scrive una sola.
      </p>
      <Textarea
        id="risposta-recensione"
        className="mt-2"
        rows={3}
        maxLength={MAX_RISPOSTA}
        value={testo}
        disabled={inCorso}
        aria-invalid={errore !== null}
        aria-describedby={errore ? "risposta-errore" : "risposta-conteggio"}
        onChange={(e) => setTesto(e.target.value)}
        placeholder="La tua risposta…"
      />
      <p id="risposta-conteggio" className="mt-1 text-xs text-muted-foreground">
        {testoPulito.length}/{MAX_RISPOSTA} caratteri.
      </p>
      {errore && (
        <p id="risposta-errore" role="alert" className="mt-2 text-xs text-red-700">
          {errore}
        </p>
      )}
      <Button
        className="mt-3 bg-bordeaux hover:bg-bordeaux/90"
        disabled={inCorso || !valido}
        onClick={async () => {
          // Il secondo invio non parte nemmeno: `inCorso` arriva dal padre dopo
          // un render, e fra il click e quel render c'è una finestra in cui il
          // bottone è ancora abilitato. Il database reggerebbe comunque — c'è
          // una UNIQUE sulla recensione — ma il secondo tentativo tornerebbe
          // come errore «hai già risposto» dopo una replica andata a buon fine.
          if (inviando.current) return;
          inviando.current = true;
          try {
            setErrore(await onRispondi(reviewId, testoPulito));
          } finally {
            inviando.current = false;
          }
        }}
      >
        {inCorso ? "Invio…" : "Pubblica risposta"}
      </Button>
    </div>
  );
}

type Props = {
  /**
   * L'ammissibilità come la calcola il server. `null` quando non è stata letta
   * o non riguarda chi guarda: in quel caso il modulo di scrittura non compare.
   * Non c'è alcuna ricostruzione locale della regola.
   */
  eleggibilita: EleggibilitaRecensione | null;
  esistente: OrderReviewRecord | null;
  risposta: OrderReviewRispostaRecord | null;
  ruolo: "compratore" | "venditore";
  inCorso: boolean;
  onInvia: (r: {
    voto: number;
    conformita: number;
    imballaggio: number;
    comunicazione: number;
    testo?: string | null;
  }) => Promise<string | null>;
  onRispondi: (reviewId: string, testo: string) => Promise<string | null>;
};

/**
 * Le quattro dimensioni di sempre, una recensione per ordine, e — da D9 — la
 * replica del venditore.
 *
 * CHI DECIDE SE SI PUÒ RECENSIRE. Il server, e questo componente non lo
 * ricalcola: riceve `eleggibilita` da `ordini_recensibili` e si limita a
 * disegnarne l'esito. Nascondere il modulo non è comunque un permesso — la RPC
 * rilegge l'ordine con `auth.uid()` a ogni invio — ma mostrarlo quando il
 * server dice di no significherebbe promettere un'azione che fallirà.
 */
export function ReviewPanel({
  eleggibilita,
  esistente,
  risposta,
  ruolo,
  inCorso,
  onInvia,
  onRispondi,
}: Props) {
  const [voto, setVoto] = useState(5);
  const [conformita, setConformita] = useState(5);
  const [imballaggio, setImballaggio] = useState(5);
  const [comunicazione, setComunicazione] = useState(5);
  const [testo, setTesto] = useState("");
  const [errore, setErrore] = useState<string | null>(null);
  const inviando = useRef(false);

  const venditore = ruolo === "venditore";

  if (esistente) {
    return (
      <section
        data-testid="recensione-ordine"
        className="rounded-2xl border border-oro/40 bg-oro/10 p-4"
      >
        <div className="flex flex-wrap items-start justify-between gap-2">
          <p className="text-sm font-semibold">
            {venditore ? "Recensione ricevuta" : "Recensione inviata"}
          </p>
          {/* La segnalazione la offre a chi la recensione l'ha ricevuta: chi
              l'ha scritta non ha nulla da segnalare a sé stesso. Riusa la
              segnalazione canonica — `segnalazione_invia` conosce già il
              bersaglio `recensione` dalla Fase 9a — e non apre una coda
              propria. */}
          {venditore && (
            <ReportDialog
              targetType="recensione"
              targetId={esistente.id}
              targetLabel={`Recensione ${esistente.id.slice(0, 8)}`}
            />
          )}
        </div>
        <Punteggi recensione={esistente} />
        {esistente.testo && <p className="mt-3 text-sm italic">“{esistente.testo}”</p>}

        {risposta ? (
          <div
            data-testid="risposta-recensione"
            className="mt-4 rounded-xl border border-border bg-card p-3"
          >
            <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
              Risposta del venditore
            </p>
            <p className="mt-1 text-sm">{risposta.testo}</p>
          </div>
        ) : venditore ? (
          <RispostaForm reviewId={esistente.id} inCorso={inCorso} onRispondi={onRispondi} />
        ) : null}
      </section>
    );
  }

  // Nessuna recensione. Il modulo compare solo se il server dice che si può, e
  // per il venditore non compare mai: non è lui a recensire.
  if (venditore || !eleggibilita?.eligible) return null;

  const testoPulito = testo.trim();
  const troppoLungo = testoPulito.length > MAX_TESTO;

  return (
    <section data-testid="modulo-recensione" className="rounded-2xl border border-border bg-card p-4">
      <p className="text-sm font-semibold">Lascia una recensione</p>
      <p className="mt-1 text-xs text-muted-foreground">
        Aiuta la community valutando l&apos;esperienza. Si recensisce una volta sola.
      </p>
      <div className="mt-3 grid gap-3 sm:grid-cols-2">
        <StelleInput
          label="Voto generale"
          value={voto}
          onChange={setVoto}
          disabled={inCorso}
        />
        <StelleInput
          label="Conformità descrizione"
          value={conformita}
          onChange={setConformita}
          disabled={inCorso}
        />
        <StelleInput
          label="Imballaggio"
          value={imballaggio}
          onChange={setImballaggio}
          disabled={inCorso}
        />
        <StelleInput
          label="Comunicazione"
          value={comunicazione}
          onChange={setComunicazione}
          disabled={inCorso}
        />
      </div>
      <label htmlFor="recensione-testo" className="sr-only">
        Commento facoltativo
      </label>
      <Textarea
        id="recensione-testo"
        className="mt-3"
        rows={3}
        maxLength={MAX_TESTO}
        value={testo}
        disabled={inCorso}
        aria-invalid={errore !== null || troppoLungo}
        aria-describedby={errore ? "recensione-errore" : "recensione-conteggio"}
        onChange={(e) => setTesto(e.target.value)}
        placeholder="Un commento (facoltativo)…"
      />
      <p id="recensione-conteggio" className="mt-1 text-xs text-muted-foreground">
        {testoPulito.length}/{MAX_TESTO} caratteri.
      </p>
      {errore && (
        <p id="recensione-errore" role="alert" className="mt-2 text-xs text-red-700">
          {errore}
        </p>
      )}
      <Button
        className="mt-3 bg-bordeaux hover:bg-bordeaux/90"
        disabled={inCorso || troppoLungo}
        onClick={async () => {
          // Stessa guardia della replica: `inCorso` è uno stato del padre e
          // arriva un render dopo il click. La UNIQUE su `order_id` regge il
          // doppio invio, ma il secondo tornerebbe come «già recensito» a chi
          // ha appena recensito bene.
          if (inviando.current) return;
          inviando.current = true;
          try {
            setErrore(
              await onInvia({
                voto,
                conformita,
                imballaggio,
                comunicazione,
                testo: testoPulito || null,
              }),
            );
          } finally {
            inviando.current = false;
          }
        }}
      >
        {inCorso ? "Invio…" : "Pubblica recensione"}
      </Button>
    </section>
  );
}
