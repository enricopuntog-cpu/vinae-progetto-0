"use client";

import { useEffect, useMemo, useState } from "react";
import { getSupabaseClient } from "@/lib/supabase/client";
import { etichettaImballaggio, riassuntoColli } from "@/lib/logistica/etichette";
import { creaLogisticaService, type LogisticaOrdine } from "@/services/logistica-service";
import { scomposizioneAddebito } from "@/lib/orders/seller-status";
import { etichettaClasse, euro } from "@/lib/prezzi/classe";
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
  const centesimi = euro;

  return (
    <section className="rounded-2xl border border-border bg-card p-4">
      <p className="mb-3 text-xs uppercase tracking-wide text-muted-foreground">
        Riepilogo pagamento
      </p>
      <div className="space-y-1.5 text-sm">
        <Riga
          label={
            (ordine.quantita ?? 1) > 1 && ordine.prezzo_unitario_cents
              ? `${ordine.quantita} bottiglie × ${centesimi(ordine.prezzo_unitario_cents)}`
              : "Bottiglia"
          }
          value={centesimi(s.prezzoCents)}
        />
        <Riga label="Servizio Vinea" value={centesimi(s.commissioneCents)} />
        {s.imballaggioCents > 0 && (
          <Riga
            label={ordine.imballaggio_etichetta ?? "Imballaggio"}
            value={centesimi(s.imballaggioCents)}
          />
        )}
        {s.logisticaCents > 0 && (
          <Riga label="Spedizione e servizi accessori" value={centesimi(s.logisticaCents)} />
        )}
        <div className="my-2 h-px bg-border" />
        <Riga label="Totale" value={centesimi(s.addebitoTotaleCents)} bold />
      </div>
      {ordine.venditore_classe === "partner" ? (
        <p className="mt-3 text-xs text-muted-foreground" data-testid="ordine-classe">
          {etichettaClasse("partner")}: condizioni economiche dei Partner, congelate alla creazione
          dell&apos;ordine.
        </p>
      ) : null}

      {s.logisticaCents > 0 ? <ColliOrdine orderId={ordine.id} /> : null}

      {ordine.imballaggio_codice && (
        <p className="mt-3 text-xs text-muted-foreground">
          Consegna alla rete logistica: {ordine.imballaggio_etichetta}
          {ordine.imballaggio_punto_nome ? ` · ${ordine.imballaggio_punto_nome}` : ""}
        </p>
      )}
    </section>
  );
}

/**
 * VP-E: i colli congelati dell'ordine (formato e bottiglie). Una lettura
 * fallita non mostra nulla: l'importo resta quello della riga sopra.
 */
function ColliOrdine({ orderId }: { orderId: string }) {
  const service = useMemo(() => creaLogisticaService(getSupabaseClient()), []);
  const [logistica, setLogistica] = useState<LogisticaOrdine | null>(null);
  useEffect(() => {
    let attivo = true;
    void service.ordine(orderId).then((r) => {
      if (attivo && r.ok) setLogistica(r.data);
    });
    return () => {
      attivo = false;
    };
  }, [service, orderId]);
  if (!logistica || logistica.colli.length === 0) return null;
  return (
    <div className="mt-3 text-xs text-muted-foreground" data-testid="ordine-colli">
      <p>
        {riassuntoColli(logistica.colli)}
        {logistica.destinazione === "pudo" ? " · consegna al punto di ritiro" : ""}
      </p>
      <ul className="mt-1 space-y-0.5">
        {logistica.colli.map((c) => (
          <li key={c.numero}>
            Collo {c.numero}: {etichettaImballaggio(c.packagingFormat)}, {c.bottiglie}{" "}
            {c.bottiglie === 1 ? "bottiglia" : "bottiglie"}
          </li>
        ))}
      </ul>
      {logistica.feePagamentoCents > 0 ? (
        <p className="mt-1" data-testid="ordine-fee-pagamento">
          Di cui costi di pagamento sulla spedizione: {euro(logistica.feePagamentoCents)}
        </p>
      ) : null}
    </div>
  );
}
