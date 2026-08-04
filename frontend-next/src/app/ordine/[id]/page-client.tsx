"use client";

import Link from "next/link";
import { MapPin, ShieldCheck } from "lucide-react";
import { routes } from "@/config/routes";
import { useOrderDetail } from "@/hooks/useOrderDetail";
import {
  ETICHETTE_STATO_COMPRATORE,
  ETICHETTE_STATO_VENDITORE,
  puoConfermare,
  puoPreparare,
  puoRecensire,
  sellerStatusDaOrdine,
} from "@/lib/orders/seller-status";
import { BuyerConfirmPanel } from "@/components/vinea/orders/BuyerConfirmPanel";
import { DisputePanel } from "@/components/vinea/orders/DisputePanel";
import { OrderSummary } from "@/components/vinea/orders/OrderSummary";
import { OrderTimeline } from "@/components/vinea/orders/OrderTimeline";
import { ReviewPanel } from "@/components/vinea/orders/ReviewPanel";
import { SellerPrepPanel } from "@/components/vinea/orders/SellerPrepPanel";

export default function OrdineDetailPageClient({ orderId }: { orderId: string }) {
  const o = useOrderDetail(orderId);

  if (o.stato.fase === "caricamento") {
    return <p className="py-24 text-center text-muted-foreground">Caricamento…</p>;
  }
  if (o.stato.fase === "errore") {
    return (
      <div className="grid place-items-center py-24 text-center">
        <p className="font-serif text-3xl">Ordine non disponibile</p>
        <p className="mt-2 text-sm text-muted-foreground">{o.stato.messaggio}</p>
        <Link href={routes.acquisti} className="mt-4 text-bordeaux underline">
          Vai ai tuoi acquisti
        </Link>
      </div>
    );
  }

  const { ordine, tracking, contestazione, recensione, ruolo } = o.stato.dati;
  const venditore = ruolo === "venditore";
  const etichetta = venditore
    ? ETICHETTE_STATO_VENDITORE[sellerStatusDaOrdine(ordine)]
    : ETICHETTE_STATO_COMPRATORE[ordine.stato];

  return (
    <div className="space-y-6">
      <header className="grid grid-cols-[minmax(0,1fr)_auto] items-start gap-4 sm:flex sm:flex-wrap sm:items-center sm:justify-between">
        <div className="min-w-0">
          <p className="text-xs uppercase tracking-wide text-muted-foreground">
            Ordine · {venditore ? "Vendita" : "Acquisto"}
          </p>
          <h1 className="truncate font-serif text-2xl sm:text-3xl">{ordine.id.slice(0, 8)}</h1>
          <p className="mt-1 text-xs text-muted-foreground">
            Creato il {new Date(ordine.created_at).toLocaleDateString("it-IT")}
          </p>
        </div>
        <span className="rounded-full bg-secondary px-3 py-1 text-xs font-semibold text-antracite">
          {etichetta}
        </span>
      </header>

      <div className="grid gap-6 lg:grid-cols-[1fr_360px]">
        <div className="space-y-6">
          <section className="rounded-2xl border border-border bg-card p-4">
            <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
              <p className="text-xs uppercase tracking-wide text-muted-foreground">Tracking</p>
              {ordine.tracking_number && (
                <p className="text-xs text-muted-foreground">
                  {ordine.corriere} · <b className="text-antracite">{ordine.tracking_number}</b>
                </p>
              )}
            </div>
            <OrderTimeline eventi={tracking} />
          </section>

          {venditore && puoPreparare(ordine.stato) && (
            <SellerPrepPanel
              ordine={ordine}
              inCorso={o.inCorso}
              onPrepara={o.preparaSpedizione}
              onSpedisci={o.segnaSpedito}
              onRicarica={() => void o.ricarica()}
            />
          )}

          {venditore && ordine.stato === "spedito" && (
            <section className="rounded-2xl border border-border bg-card p-4">
              <p className="text-sm font-semibold">Consegna effettuata?</p>
              <p className="mt-1 text-xs text-muted-foreground">
                Dichiararla apre il periodo di verifica del compratore.
              </p>
              <button
                disabled={o.inCorso}
                onClick={() => void o.segnaConsegnato()}
                className="mt-3 rounded-lg bg-bordeaux px-4 py-2 text-sm font-medium text-white hover:bg-bordeaux/90 disabled:opacity-50"
              >
                Segna come consegnato
              </button>
            </section>
          )}

          {!venditore && !contestazione && puoConfermare(ordine) && (
            <BuyerConfirmPanel
              inCorso={o.inCorso}
              onConferma={o.confermaRicezione}
              onContesta={o.apriContestazione}
            />
          )}

          {contestazione && <DisputePanel contestazione={contestazione} />}

          {!venditore && puoRecensire(ordine.stato) && (
            <ReviewPanel esistente={recensione} inCorso={o.inCorso} onInvia={o.recensisci} />
          )}
        </div>

        <aside className="space-y-4 lg:sticky lg:top-24 lg:self-start">
          <OrderSummary ordine={ordine} />

          <section className="rounded-2xl border border-border bg-card p-4">
            <p className="mb-3 text-xs uppercase tracking-wide text-muted-foreground">Consegna</p>
            <p className="text-sm font-semibold">
              {ordine.delivery_mode === "spedizione" ? "Spedizione con corriere" : "Consegna a mano"}
            </p>
            {ordine.imballaggio_punto_nome && (
              <p className="mt-2 flex items-start gap-2 text-xs text-muted-foreground">
                <MapPin className="mt-0.5 h-3 w-3" /> {ordine.imballaggio_punto_nome}
              </p>
            )}
          </section>

          <div className="rounded-2xl border border-oro/40 bg-oro/10 p-3 text-xs">
            <p className="flex items-center gap-1 font-semibold text-oro">
              <ShieldCheck className="h-3.5 w-3.5" /> Protezione acquisti Vinea
            </p>
            <p className="mt-1 text-antracite/80">
              Il pagamento resta a Vinea fino alla tua conferma. In caso di problema puoi aprire una
              contestazione durante il periodo di verifica.
            </p>
          </div>
        </aside>
      </div>
    </div>
  );
}
