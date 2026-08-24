"use client";

/**
 * Il riquadro «Prezzo suggerito Vinea» del passo Prezzo di /vendi.
 *
 * Non calcola: riceve già deciso da `@/lib/price-intelligence/smart-sell-price`,
 * che a sua volta compone la 1B. Qui c'è solo come dirlo, e come dirlo è
 * vincolato:
 *
 *   * si dice «prezzo suggerito Vinea». Mai «quotazione», mai «valore reale»,
 *     mai «prezzo garantito», mai «AI price»: sono quattro modi di promettere
 *     che la bottiglia varrà quella cifra, e la mediana di tre annunci non lo
 *     promette;
 *   * si dice «Dati interni Vinea», sempre e in chiaro. Nessuna fonte esterna è
 *     accesa — nessuna chiave, nessuna chiamata, nessun costo;
 *   * si dice «copertura dati» e non «affidabilità»: dice quanti dati ci sono,
 *     non quanto siano giusti.
 *
 * E soprattutto: qui non parte niente da solo. Il numero sta nel riquadro
 * finché l'utente non clicca «Usa questo prezzo». Un suggerimento che si
 * scrivesse da sé nel campo sarebbe il prezzo di Vinea con la firma del
 * venditore.
 */

import { Info, Tag } from "lucide-react";
import { Button } from "@/components/ui/button";
import { formatEUR } from "@/lib/format";
import type { SmartSellPrice } from "@/lib/price-intelligence/smart-sell-price";

const euro = (cents: number) => formatEUR(cents / 100);

function Riquadro({
  children,
  tono = "neutro",
}: {
  children: React.ReactNode;
  tono?: "neutro" | "oro";
}) {
  return (
    <div
      data-testid="smart-sell-price"
      className={
        tono === "oro"
          ? "rounded-xl border border-oro/40 bg-oro/10 p-4"
          : "rounded-xl border border-dashed border-border bg-secondary/40 p-4"
      }
    >
      {children}
    </div>
  );
}

export function SmartSellPricePanel({
  suggerimento,
  inCorso,
  onUsaPrezzo,
}: {
  /** `null` finché la lettura non è tornata. */
  suggerimento: SmartSellPrice | null;
  inCorso: boolean;
  onUsaPrezzo: () => void;
}) {
  if (inCorso || suggerimento === null) {
    return (
      <Riquadro>
        <p className="text-sm text-muted-foreground">Cerco annunci comparabili…</p>
      </Riquadro>
    );
  }

  // Lettura fallita. Nessun numero di ripiego, nessun errore tecnico in
  // pagina, nessun blocco: il campo prezzo qui sotto funziona esattamente come
  // prima e questo riquadro è l'unica cosa che manca.
  if (suggerimento.stato === "non_disponibile") {
    return (
      <Riquadro>
        <p className="flex items-center gap-2 text-sm">
          <Info className="h-4 w-4 text-salvia" aria-hidden />
          Suggerimento di prezzo non disponibile in questo momento.
        </p>
        <p className="mt-1 text-xs text-muted-foreground">
          Puoi inserire il prezzo manualmente qui sotto.
        </p>
      </Riquadro>
    );
  }

  if (suggerimento.stato === "insufficiente") {
    return (
      <Riquadro>
        <p className="flex items-center gap-2 text-sm font-medium">
          <Info className="h-4 w-4 text-salvia" aria-hidden />
          Dati insufficienti per suggerire un prezzo
        </p>
        <p className="mt-1 text-xs text-muted-foreground">
          {suggerimento.comparabili === 0
            ? "Nessun annuncio attivo comparabile"
            : `${suggerimento.comparabili} ${suggerimento.comparabili === 1 ? "annuncio attivo comparabile" : "annunci attivi comparabili"}`}
          : servono almeno {suggerimento.soglia} annunci dello stesso vino e formato. Il prezzo lo
          decidi tu qui sotto.
        </p>
        <p className="mt-2 text-[11px] text-muted-foreground">Fonte: Dati interni Vinea</p>
      </Riquadro>
    );
  }

  return (
    <Riquadro tono="oro">
      <p className="flex items-center gap-2 text-xs uppercase tracking-wide text-muted-foreground">
        <Tag className="h-4 w-4 text-oro" aria-hidden />
        Prezzo suggerito Vinea
      </p>
      <p
        className="mt-1 font-serif text-3xl font-semibold text-bordeaux"
        data-testid="smart-sell-price-valore"
      >
        {euro(suggerimento.medianaCents)}
      </p>
      <div className="mt-1 space-y-0.5 text-xs text-muted-foreground">
        <p>
          Mediana di {suggerimento.comparabili} annunci comparabili
        </p>
        <p>
          Range {euro(suggerimento.minimoCents)} – {euro(suggerimento.massimoCents)}
        </p>
        <p>Copertura dati: {suggerimento.copertura.etichetta}</p>
        <p>Fonte: Dati interni Vinea</p>
      </div>
      <Button
        type="button"
        size="sm"
        variant="outline"
        className="mt-3"
        data-testid="smart-sell-price-usa"
        onClick={onUsaPrezzo}
      >
        Usa questo prezzo
      </Button>
      <p className="mt-2 text-[11px] text-muted-foreground">
        Il campo qui sotto resta tuo: il suggerimento non lo compila da solo.
      </p>
    </Riquadro>
  );
}
