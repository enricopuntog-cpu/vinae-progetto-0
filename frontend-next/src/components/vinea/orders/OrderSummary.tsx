"use client";

import { formatEUR } from "@/lib/format";
import { scomposizioneAddebito } from "@/lib/orders/seller-status";
import type { OrderRecord } from "@/services/types";

function Riga({ label, value, bold }: { label: string; value: string; bold?: boolean }) {
  return (
    <div className={`flex items-baseline justify-between gap-2 ${bold ? "font-serif text-lg" : ""}`}>
      <span className="text-antracite">{label}</span>
      <span className={`font-medium ${bold ? "text-bordeaux" : ""}`}>{value}</span>
    </div>
  );
}

/**
 * Il riepilogo di quanto è stato addebitato.
 *
 * I numeri arrivano **congelati dall'ordine** e non vengono ricalcolati qui:
 * la commissione è quella decisa alla creazione con i parametri di allora, e
 * l'imballaggio è quello del listino di allora. Ricalcolare in pagina
 * significherebbe mostrare un ordine vecchio con il listino nuovo.
 *
 * L'imballaggio è una **riga separata**, fuori dal calcolo della commissione:
 * `totale_cents` resta la base di mercato della 7b, `addebito_totale_cents` è
 * ciò che il compratore paga davvero. Con l'imballaggio a zero — il seed di
 * questa fase — le due cifre coincidono e la riga non compare.
 */
export function OrderSummary({ ordine }: { ordine: OrderRecord }) {
  const s = scomposizioneAddebito(ordine);
  const centesimi = (v: number) => formatEUR(v / 100);

  return (
    <section className="rounded-2xl border border-border bg-card p-4">
      <p className="mb-3 text-xs uppercase tracking-wide text-muted-foreground">
        Riepilogo pagamento
      </p>
      <div className="space-y-1.5 text-sm">
        <Riga label="Bottiglia" value={centesimi(s.prezzoCents)} />
        <Riga label="Servizio Vinea" value={centesimi(s.commissioneCents)} />
        {s.imballaggioCents > 0 && (
          <Riga
            label={ordine.imballaggio_etichetta ?? "Imballaggio"}
            value={centesimi(s.imballaggioCents)}
          />
        )}
        <div className="my-2 h-px bg-border" />
        <Riga label="Totale" value={centesimi(s.addebitoTotaleCents)} bold />
      </div>

      {ordine.imballaggio_codice && (
        <p className="mt-3 text-xs text-muted-foreground">
          Consegna alla rete logistica: {ordine.imballaggio_etichetta}
          {ordine.imballaggio_punto_nome ? ` · ${ordine.imballaggio_punto_nome}` : ""}
        </p>
      )}
    </section>
  );
}
