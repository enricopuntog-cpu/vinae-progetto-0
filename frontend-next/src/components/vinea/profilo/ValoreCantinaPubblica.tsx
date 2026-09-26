import { ValoreNelTempo } from "@/components/vinea/ValoreNelTempo";
import { presentaValoreCantinaPubblica } from "@/lib/cantina/valore-pubblico";
import type { ValoreCantinaPubblica as DatiValoreCantinaPubblica } from "@/services/types";

/**
 * Il valore di riferimento della Cantina pubblica di una persona.
 *
 * ## Esiste solo se il proprietario l'ha scelto
 *
 * Il componente non decide se comparire: la pagina lo rende soltanto quando
 * `visibile === true`, e quando è `false` non c'è né questo blocco né un
 * segnaposto che dica «il valore è nascosto». La differenza conta. Un
 * segnaposto trasformerebbe una scelta privata in un fatto pubblico —
 * «questa persona ha deciso di non mostrarlo» — e la discrezione del
 * proprietario dipende dal silenzio, non da un avviso gentile.
 *
 * ## Che cosa mostra, e che cosa non può mostrare
 *
 * Riceve `ValoreCantinaPubblica`, cioè l'allowlist chiusa di
 * `public.cantina_pubblica_valore(uuid)`: un totale di riferimento, due
 * conteggi, una copertura, una serie. **Non riceve `AnaliticaPortafoglio`** e
 * non è un'omissione da correggere: quella è la contabilità del proprietario —
 * capitale noto, incassi trasferiti, performance, posizioni con costo — e non
 * ha una porta che la esponga a un visitatore. Qui non c'è nessun `if` che la
 * nasconda, perché non arriva.
 *
 * ## Una stima, e detta come tale
 *
 * Il numero è la somma delle mediane Vinea delle sole bottiglie esposte: non è
 * un prezzo di vendita, non è il patrimonio di nessuno, non è una performance.
 * Con copertura parziale il totale riguarda le sole posizioni con riferimento,
 * e la frase di copertura lo dichiara: le altre non valgono zero, non sono in
 * quel totale.
 */
export function ValoreCantinaPubblica({ valore }: { valore: DatiValoreCantinaPubblica }) {
  const v = presentaValoreCantinaPubblica(valore);

  return (
    <section
      aria-labelledby="valore-cantina-pubblica"
      className="rounded-3xl border border-border bg-card"
      data-testid="valore-cantina-pubblica"
    >
      <div className="p-5 md:p-6">
        <h2 id="valore-cantina-pubblica" className="font-serif text-2xl">
          Valore di riferimento
        </h2>

        {v.valore === null ? (
          <>
            <p className="mt-3 text-base font-medium">
              Valore di riferimento non ancora disponibile
            </p>
            <p className="mt-1 text-sm text-muted-foreground">{v.assenza}</p>
            <p className="mt-1 text-sm text-muted-foreground">{v.copertura}</p>
          </>
        ) : (
          <>
            {/* `break-words` e non una larghezza fissa: a 375 px un totale a sei
                cifre deve andare a capo, non uscire dalla card. */}
            <p className="mt-3 break-words font-serif text-4xl text-bordeaux">{v.valore}</p>
            <p className="mt-2 text-sm text-muted-foreground">{v.copertura}</p>
            {v.parziale && (
              <p
                role="note"
                className="mt-3 rounded-xl border border-dashed border-border bg-secondary/40 p-3 text-sm text-muted-foreground"
              >
                Copertura parziale: le bottiglie senza riferimento non sono contate come
                zero, semplicemente non entrano nel totale.
              </p>
            )}
          </>
        )}

        <p className="mt-4 text-xs text-muted-foreground">
          Stima basata sui riferimenti Vinea disponibili per le bottiglie esposte. Non
          rappresenta un prezzo di vendita.
        </p>
      </div>

      {/* Lo storico riguarda la collezione esposta **adesso**, valutata sugli
          snapshot realmente osservati: non ricostruisce quali bottiglie fossero
          pubbliche in passato, e il sottotitolo del grafico non promette altro. */}
      <div className="border-t border-border p-5 md:p-6">
        <ValoreNelTempo serie={v.serie} incorniciato={false} />
      </div>
    </section>
  );
}
