import { Loader2 } from "lucide-react";
import {
  percentualeDaBps,
  messaggioVenditoreNonAmmesso,
  type PreventivoAnnuncioAccessori,
} from "@/lib/accessori-vendita/annunci-accessori";
import { euro } from "@/lib/prezzi/classe";

/**
 * Riepilogo economico di un annuncio Accessori, come lo dà il database.
 *
 * Non ricalcola nulla: ogni importo arriva dal preventivo autorevole
 * (`annunci_accessori_preventivo`), che usa la stessa formula e gli stessi
 * parametri di pagamento del mercato delle bottiglie. Distingue ciò che riceve
 * il venditore, la commissione Vinea, la copertura del costo di pagamento e la
 * spedizione (oggi senza tariffa: «non disponibile», mai 0 €).
 */

export type StatoRiepilogo =
  | { tipo: "vuoto" }
  | { tipo: "caricamento" }
  | { tipo: "errore"; messaggio: string }
  | { tipo: "pronto"; dati: PreventivoAnnuncioAccessori };

export function RiepilogoEconomico({ stato }: { stato: StatoRiepilogo }) {
  return (
    <section
      aria-labelledby="riepilogo-economico-titolo"
      aria-live="polite"
      data-testid="riepilogo-economico"
      className="space-y-3 rounded-xl border border-border bg-secondary/40 p-4"
    >
      <h3 id="riepilogo-economico-titolo" className="font-serif text-base font-semibold">
        Riepilogo economico
      </h3>
      <Corpo stato={stato} />
    </section>
  );
}

function Corpo({ stato }: { stato: StatoRiepilogo }) {
  if (stato.tipo === "vuoto") {
    return (
      <p className="text-sm text-muted-foreground">
        Indica quantità e prezzo: qui vedrai quanto ricevi e quanto pagherebbe l&apos;acquirente.
      </p>
    );
  }
  if (stato.tipo === "caricamento") {
    return (
      <p className="flex items-center gap-2 text-sm text-muted-foreground" role="status">
        <Loader2 className="h-4 w-4 animate-spin" aria-hidden /> Calcolo il riepilogo…
      </p>
    );
  }
  if (stato.tipo === "errore") {
    return (
      <p role="alert" className="text-sm text-bordeaux">
        {stato.messaggio}
      </p>
    );
  }

  const { dati } = stato;
  if (!dati.venditoreAmmesso || !dati.preventivo) {
    return (
      <p role="status" className="text-sm text-muted-foreground">
        {messaggioVenditoreNonAmmesso(dati.motivo) ?? "Il riepilogo non è disponibile in questo momento."}
      </p>
    );
  }

  const p = dati.preventivo;
  const pezzi = p.quantita === 1 ? "1 pezzo" : `${p.quantita} pezzi`;
  return (
    <>
      <dl className="grid grid-cols-[1fr_auto] gap-x-4 gap-y-2 text-sm">
        <dt>
          Tu ricevi
          <span className="block text-xs text-muted-foreground">
            {pezzi} × {euro(p.prezzoUnitarioCents)}
          </span>
        </dt>
        <dd className="text-right font-medium tabular-nums" data-testid="riepilogo-ricevi">
          {euro(p.subtotaleCents)}
        </dd>

        <dt>
          Commissione Vinea
          <span className="block text-xs text-muted-foreground">
            Obiettivo netto {percentualeDaBps(p.margineObiettivoBps)} del prezzo, dopo i costi di pagamento
          </span>
        </dt>
        <dd className="text-right tabular-nums" data-testid="riepilogo-commissione">
          {euro(p.quotaVineaCents)}
        </dd>

        <dt>
          Copertura costi di pagamento
          <span className="block text-xs text-muted-foreground">
            Stima: {percentualeDaBps(p.riferimentoPercentualeBps)} + {euro(p.riferimentoFissoCents)} fissi, una sola
            volta per ordine
          </span>
        </dt>
        <dd className="text-right tabular-nums" data-testid="riepilogo-pagamento">
          {euro(p.costoPagamentoCents)}
        </dd>

        <dt className="border-t border-border pt-2 font-medium">
          Prezzo per l&apos;acquirente
          <span className="block text-xs font-normal text-muted-foreground">Spedizione esclusa</span>
        </dt>
        <dd className="border-t border-border pt-2 text-right font-semibold tabular-nums" data-testid="riepilogo-totale">
          {euro(p.totaleCents)}
        </dd>

        <dt>
          Spedizione
          <span className="block text-xs text-muted-foreground">A carico dell&apos;acquirente</span>
        </dt>
        <dd className="text-right text-muted-foreground" data-testid="riepilogo-spedizione">
          Preventivo non disponibile
        </dd>
      </dl>
      <p className="text-xs text-muted-foreground">
        La commissione non si applica alla spedizione. Quando esisterà una tariffa, la spedizione sarà calcolata e
        mostrata prima dell&apos;acquisto; l&apos;imballaggio lo prepari tu e non ha costi aggiuntivi.
      </p>
    </>
  );
}
