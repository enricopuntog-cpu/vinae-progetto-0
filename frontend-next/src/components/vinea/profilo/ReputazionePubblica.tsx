"use client";

import { useState } from "react";
import { Flag, Star } from "lucide-react";
import { AvatarPersona } from "@/components/vinea/AvatarPersona";
import { ReportDialog } from "@/components/vinea/ReportDialog";
import { getSupabaseClient } from "@/lib/supabase/client";
import { creaPublicProfileService } from "@/services/public-profile-service";
import type { MedieRecensioni, RecensionePubblica } from "@/services/types";

/** Quante ne arrivano a ogni «mostra altre». Deve combaciare con la prima pagina. */
const PER_PAGINA = 10;

const ETICHETTE: ReadonlyArray<[keyof MedieRecensioni, string]> = [
  ["voto", "Generale"],
  ["conformita", "Conformità"],
  ["imballaggio", "Imballaggio"],
  ["comunicazione", "Comunicazione"],
];

/**
 * Le cinque stelle di un punteggio, in sola lettura.
 *
 * Il numero c'è comunque accanto: le stelle sono un riassunto visivo, e chi non
 * le vede — o le vede come cinque icone identiche — legge il valore.
 */
function Stelle({ valore, etichetta }: { valore: number; etichetta: string }) {
  return (
    <span className="inline-flex items-center gap-0.5" aria-label={`${etichetta}: ${valore} su 5`}>
      {[1, 2, 3, 4, 5].map((n) => (
        <Star
          key={n}
          aria-hidden
          className={`h-4 w-4 ${n <= Math.round(valore) ? "fill-oro text-oro" : "text-muted-foreground/40"}`}
        />
      ))}
    </span>
  );
}

function Recensione({ recensione }: { recensione: RecensionePubblica }) {
  return (
    <li className="rounded-2xl border border-border px-4 py-3">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="flex min-w-0 items-center gap-2">
          <AvatarPersona
            avatarUrl={recensione.autore.avatarUrl}
            proprietarioId={recensione.autore.userId}
            alt={`Avatar di ${recensione.autore.username}`}
            className="h-8 w-8 shrink-0"
          />
          <div className="min-w-0">
            <p className="truncate text-sm font-medium">{recensione.autore.username}</p>
            <p className="text-xs text-muted-foreground">
              {new Date(recensione.createdAt).toLocaleDateString("it-IT")}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-1">
          <Stelle valore={recensione.voto} etichetta="Voto generale" />
          {/* La segnalazione riusa la porta canonica: `segnalazione_invia`
              conosce il bersaglio `recensione` dalla Fase 9a. Nessuna coda
              propria, nessun pannello. */}
          <ReportDialog
            targetType="recensione"
            targetId={recensione.id}
            targetLabel={`Recensione di ${recensione.autore.username}`}
            variant="icon"
            trigger={
              <button
                className="rounded-full p-1.5 text-muted-foreground hover:bg-secondary"
                aria-label="Segnala questa recensione"
              >
                <Flag className="h-3.5 w-3.5" aria-hidden />
              </button>
            }
          />
        </div>
      </div>

      <div className="mt-2 flex flex-wrap gap-3 text-xs text-muted-foreground">
        <span>Conformità {recensione.conformita}/5</span>
        <span>Imballaggio {recensione.imballaggio}/5</span>
        <span>Comunicazione {recensione.comunicazione}/5</span>
      </div>

      {recensione.testo && (
        <p className="mt-2 whitespace-pre-wrap text-sm leading-6">{recensione.testo}</p>
      )}

      {recensione.risposta && (
        <div className="mt-3 rounded-xl bg-secondary/60 px-3 py-2">
          <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
            Risposta
          </p>
          <p className="mt-1 whitespace-pre-wrap text-sm leading-6">{recensione.risposta.testo}</p>
        </div>
      )}
    </li>
  );
}

type Props = {
  userId: string;
  /**
   * Il conteggio, sempre presente. `0` è una risposta e va mostrata come tale:
   * «nessuna recensione» è un fatto, non un guasto.
   */
  totali: number;
  /**
   * Le medie, oppure `null` quando non c'è nulla da mediare. Il ramo `null` NON
   * stampa zeri: una media di 0 su 5 sarebbe il giudizio peggiore possibile
   * attribuito a chi non è mai stato recensito.
   */
  medie: MedieRecensioni | null;
  /** La prima pagina, resa dal server: la sezione è leggibile senza JavaScript. */
  iniziali: RecensionePubblica[];
};

/**
 * La reputazione dentro il profilo pubblico che esiste già.
 *
 * Non è una seconda pagina profilo e non è una seconda sorgente: il riepilogo
 * arriva nella stessa riga di `profilo_pubblico`, l'elenco da
 * `recensioni_pubbliche_elenco`. Le medie non si ricalcolano qui — il browser
 * ha al massimo dieci righe, e la media di dieci non è la media di tutte.
 *
 * Vale per chiunque, non per i soli venditori: chi non ha mai pubblicato un
 * annuncio ma ha venduto in passato ha reputazione, e questa sezione è
 * indipendente da «Annunci attivi».
 */
export function ReputazionePubblica({ userId, totali, medie, iniziali }: Props) {
  const [recensioni, setRecensioni] = useState(iniziali);
  const [inCorso, setInCorso] = useState(false);
  const [errore, setErrore] = useState<string | null>(null);

  const restanti = totali - recensioni.length;

  if (totali === 0) {
    return (
      <section aria-labelledby="reputazione" data-testid="reputazione-vuota">
        <h2 id="reputazione" className="font-serif text-2xl font-semibold md:text-3xl">
          Recensioni
        </h2>
        <div className="mt-4 rounded-3xl border border-border bg-card p-6 text-center md:p-8">
          <p className="font-serif text-xl">Nessuna recensione</p>
          <p className="mt-2 text-sm text-muted-foreground">
            Questa persona non ha ancora ricevuto recensioni.
          </p>
        </div>
      </section>
    );
  }

  return (
    <section aria-labelledby="reputazione" data-testid="reputazione">
      <h2 id="reputazione" className="font-serif text-2xl font-semibold md:text-3xl">
        Recensioni
      </h2>

      {medie && (
        <div className="mt-4 rounded-3xl border border-border bg-card p-5 md:p-6">
          <div className="flex flex-wrap items-baseline gap-3">
            <p className="font-serif text-4xl font-semibold" data-testid="media-generale">
              {medie.voto.toFixed(2)}
            </p>
            <Stelle valore={medie.voto} etichetta="Media generale" />
            <p className="text-sm text-muted-foreground" data-testid="totale-recensioni">
              su {totali} {totali === 1 ? "recensione" : "recensioni"}
            </p>
          </div>

          <dl className="mt-4 grid gap-2 sm:grid-cols-3">
            {ETICHETTE.filter(([chiave]) => chiave !== "voto").map(([chiave, etichetta]) => (
              <div key={chiave} className="flex items-center justify-between gap-2 text-sm">
                <dt className="text-muted-foreground">{etichetta}</dt>
                <dd className="font-medium">{medie[chiave].toFixed(2)}</dd>
              </div>
            ))}
          </dl>
        </div>
      )}

      <ul className="mt-4 space-y-3">
        {recensioni.map((r) => (
          <Recensione key={r.id} recensione={r} />
        ))}
      </ul>

      {errore && (
        <p role="alert" className="mt-3 text-sm text-red-700">
          {errore}
        </p>
      )}

      {restanti > 0 && (
        <button
          data-testid="altre-recensioni"
          disabled={inCorso}
          className="mt-4 w-full rounded-2xl border border-border px-4 py-2 text-sm font-medium hover:bg-secondary disabled:opacity-50"
          onClick={async () => {
            setInCorso(true);
            setErrore(null);
            try {
              const servizio = creaPublicProfileService(getSupabaseClient());
              // L'offset è quante ne ho già, non un numero di pagina:
              // l'ordinamento SQL è totale — `(created_at desc, review_id desc)` —
              // quindi non ci sono righe che scavalcano il confine e compaiono
              // due volte.
              const esito = await servizio.recensioni(userId, {
                limite: PER_PAGINA,
                offset: recensioni.length,
              });
              if (!esito.ok) {
                setErrore(esito.error);
                return;
              }
              const nuove = esito.data;
              setRecensioni((precedenti) => {
                const viste = new Set(precedenti.map((r) => r.id));
                return [...precedenti, ...nuove.filter((r) => !viste.has(r.id))];
              });
            } finally {
              setInCorso(false);
            }
          }}
        >
          {inCorso ? "Caricamento…" : `Mostra altre recensioni (${restanti})`}
        </button>
      )}
    </section>
  );
}
