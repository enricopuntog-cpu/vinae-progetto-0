"use client";

import Link from "next/link";
import { ArrowLeft, ArrowRight, CreditCard } from "lucide-react";
import type { Wine } from "@/data/wines";
import { Button } from "@/components/ui/button";
import { BetaActionNotice } from "@/components/vinea/BetaActionNotice";
import { LoadingBlock } from "@/components/vinea/States";
import { useVinea } from "@/lib/vinea-store";
import { CheckoutSummary } from "./checkout-summary";
import { ContattiStep, ImballaggioStep, PagamentoStep } from "./checkout-steps";
import { ConsegnaStep } from "./consegna-step";
import { useBetaCheckout } from "./use-beta-checkout";
import type { PreventivoAnnuncio } from "@/services/preventivo-service";
import type { PreventivoLogistica } from "@/services/logistica-service";
import { bloccoConsegna, logisticaAddebitata, opzioneDestinazione, type BloccoConsegna } from "@/lib/beta/checkout";
import { elencoMancanze } from "@/lib/logistica/etichette";

const CheckoutFlow = ({
  wine,
  email,
  proposalId,
  quantita,
  preventivo,
  bottiglie,
  logistica,
}: {
  wine: Wine;
  email: string;
  proposalId?: string;
  quantita?: number;
  preventivo: PreventivoAnnuncio | null;
  bottiglie: number;
  logistica: PreventivoLogistica | null;
}) => {
  const checkout = useBetaCheckout(wine, email, proposalId, quantita);
  const ultimo = checkout.indice === checkout.passi.length - 1;
  // VP-E + domicilio: la logistica della destinazione scelta (punto di ritiro
  // per più bottiglie, domicilio sempre) entra nel totale solo se ordinabile;
  // senza servizio, tariffa, capability o indirizzi la conferma resta chiusa,
  // come la rifiuterebbe il database (logistica_non_configurata,
  // indirizzo_ritiro_mancante, indirizzo_consegna_mancante).
  const { deliveryMode, destinazione } = checkout.dati;
  const opzione = opzioneDestinazione(logistica, destinazione);
  const logisticaCents = logisticaAddebitata(bottiglie, deliveryMode, opzione, destinazione);
  const blocco = bloccoConsegna(bottiglie, checkout.dati, logistica);

  return (
    <div className="space-y-6 pb-24 md:pb-6">
      <header>
        <p className="text-xs font-semibold uppercase tracking-[0.25em] text-bordeaux">Beta · nessun addebito reale</p>
        <h1 className="font-serif text-3xl md:text-4xl">Checkout</h1>
        <p className="text-sm text-muted-foreground">Passo {checkout.indice + 1} di {checkout.passi.length}</p>
      </header>
      <div className="grid gap-6 lg:grid-cols-[1fr_340px]">
        <div className="space-y-5 rounded-2xl border border-border bg-card p-4 md:p-6">
          {checkout.passo === "contatti" && <ContattiStep {...checkout} />}
          {checkout.passo === "consegna" && (
            <ConsegnaStep {...checkout} logistica={logistica} bottiglie={bottiglie} />
          )}
          {checkout.passo === "imballaggio" && <ImballaggioStep {...checkout} />}
          {checkout.passo === "pagamento" && (
            <PagamentoStep
              {...checkout}
              usaSaldo={checkout.usaSaldo}
              setUsaSaldo={checkout.setUsaSaldo}
            />
          )}
          {blocco ? <AvvisoBloccoConsegna blocco={blocco} bottiglie={bottiglie} domicilio={destinazione === "home"} /> : null}
          {checkout.bloccato && <BetaActionNotice tipo="pagamento" />}
          {checkout.erroreAzione && <p role="alert" className="rounded-xl border border-red-500/30 bg-red-500/5 p-3 text-sm text-red-700">{checkout.erroreAzione}</p>}
          <div className="flex justify-between gap-3 border-t border-border pt-4">
            <Button variant="outline" onClick={checkout.indietro}><ArrowLeft className="h-4 w-4" /> Indietro</Button>
            {ultimo ? (
              <Button data-testid="checkout-confirm" disabled={checkout.inCorso || blocco !== null} onClick={() => void checkout.conferma()} className="bg-bordeaux hover:bg-bordeaux/90"><CreditCard className="h-4 w-4" /> Conferma pagamento</Button>
            ) : (
              <Button data-testid="checkout-next" onClick={checkout.avanti} className="bg-bordeaux hover:bg-bordeaux/90">Continua <ArrowRight className="h-4 w-4" /></Button>
            )}
          </div>
        </div>
        <CheckoutSummary
          wine={wine}
          dati={checkout.dati}
          preventivo={preventivo}
          logistica={logistica}
          logisticaCents={logisticaCents}
          destinazione={destinazione}
        />
      </div>
    </div>
  );
};

const AvvisoBloccoConsegna = ({
  blocco,
  bottiglie,
  domicilio,
}: {
  blocco: BloccoConsegna;
  bottiglie: number;
  domicilio: boolean;
}) => {
  const mancanze = blocco.motivo === "logistica" ? elencoMancanze(blocco.mancanti) : [];
  const titolo =
    blocco.motivo === "ritiro_venditore"
      ? "Il venditore non ha ancora indicato l'indirizzo di ritiro: per ora la spedizione non è possibile."
      : blocco.motivo === "indirizzo_consegna"
        ? "Scegli o aggiungi l'indirizzo di consegna."
        : domicilio
          ? "La consegna a domicilio non è ancora disponibile."
          : `La spedizione di ${bottiglie} bottiglie non è ancora disponibile.`;
  return (
    <div role="alert" className="rounded-xl border border-amber-500/30 bg-amber-500/5 p-3 text-sm" data-testid="checkout-logistica-bloccata">
      <p className="font-medium">{titolo}</p>
      {blocco.motivo === "logistica" ? (
        mancanze.length > 0 ? (
          <ul className="mt-1 list-disc space-y-0.5 pl-5 text-xs text-muted-foreground">
            {mancanze.map((m) => (
              <li key={m}>{m}</li>
            ))}
          </ul>
        ) : (
          <p className="mt-1 text-xs text-muted-foreground">Il preventivo di spedizione non è leggibile in questo momento.</p>
        )
      ) : null}
      {blocco.motivo !== "indirizzo_consegna" ? (
        <p className="mt-1 text-xs text-muted-foreground">
          {blocco.motivo === "ritiro_venditore"
            ? "Puoi scegliere il ritiro concordato."
            : domicilio
            ? "Puoi scegliere il punto di ritiro o il ritiro concordato."
            : "Puoi scegliere il ritiro concordato o acquistare una bottiglia per volta."}
        </p>
      ) : null}
    </div>
  );
};

const CheckoutPageClient = ({
  wine,
  proposalId,
  quantita,
  preventivo,
  bottiglie = 1,
  logistica = null,
}: {
  wine: Wine;
  proposalId?: string;
  quantita?: number;
  preventivo: PreventivoAnnuncio | null;
  bottiglie?: number;
  logistica?: PreventivoLogistica | null;
}) => {
  const { authUser, authLoading } = useVinea();
  if (authLoading) return <LoadingBlock label="Verifica della sessione" />;
  if (!authUser) {
    return (
      <div className="mx-auto max-w-xl rounded-2xl border border-border bg-card p-6 text-center">
        <h1 className="font-serif text-3xl">Accedi per continuare</h1>
        <p className="mt-2 text-sm text-muted-foreground">Il checkout è riservato agli utenti autenticati.</p>
        <Button asChild className="mt-5 bg-bordeaux hover:bg-bordeaux/90"><Link href="/accedi">Vai all'accesso</Link></Button>
      </div>
    );
  }
  return (
    <CheckoutFlow
      wine={wine}
      email={authUser.email ?? ""}
      proposalId={proposalId}
      quantita={quantita}
      preventivo={preventivo}
      bottiglie={bottiglie}
      logistica={logistica}
    />
  );
};

export default CheckoutPageClient;
