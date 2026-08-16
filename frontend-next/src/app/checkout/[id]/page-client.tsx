"use client";

import Link from "next/link";
import { ArrowLeft, ArrowRight, CreditCard } from "lucide-react";
import type { Wine } from "@/data/wines";
import { Button } from "@/components/ui/button";
import { BetaActionNotice } from "@/components/vinea/BetaActionNotice";
import { LoadingBlock } from "@/components/vinea/States";
import { useVinea } from "@/lib/vinea-store";
import { CheckoutSummary } from "./checkout-summary";
import { ContattiStep, ConsegnaStep, ImballaggioStep, PagamentoStep } from "./checkout-steps";
import { useBetaCheckout } from "./use-beta-checkout";

const CheckoutFlow = ({ wine, email, proposalId }: { wine: Wine; email: string; proposalId?: string }) => {
  const checkout = useBetaCheckout(wine, email, proposalId);
  const ultimo = checkout.indice === checkout.passi.length - 1;

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
          {checkout.passo === "consegna" && <ConsegnaStep {...checkout} />}
          {checkout.passo === "imballaggio" && <ImballaggioStep {...checkout} />}
          {checkout.passo === "pagamento" && <PagamentoStep {...checkout} />}
          {checkout.bloccato && <BetaActionNotice tipo="pagamento" />}
          {checkout.erroreAzione && <p role="alert" className="rounded-xl border border-red-500/30 bg-red-500/5 p-3 text-sm text-red-700">{checkout.erroreAzione}</p>}
          <div className="flex justify-between gap-3 border-t border-border pt-4">
            <Button variant="outline" onClick={checkout.indietro}><ArrowLeft className="h-4 w-4" /> Indietro</Button>
            {ultimo ? (
              <Button data-testid="checkout-confirm" disabled={checkout.inCorso} onClick={() => void checkout.conferma()} className="bg-bordeaux hover:bg-bordeaux/90"><CreditCard className="h-4 w-4" /> Conferma pagamento</Button>
            ) : (
              <Button data-testid="checkout-next" onClick={checkout.avanti} className="bg-bordeaux hover:bg-bordeaux/90">Continua <ArrowRight className="h-4 w-4" /></Button>
            )}
          </div>
        </div>
        <CheckoutSummary wine={wine} dati={checkout.dati} />
      </div>
    </div>
  );
};

const CheckoutPageClient = ({ wine, proposalId }: { wine: Wine; proposalId?: string }) => {
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
  return <CheckoutFlow wine={wine} email={authUser.email ?? ""} proposalId={proposalId} />;
};

export default CheckoutPageClient;
