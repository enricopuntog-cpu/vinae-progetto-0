"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { ArrowRight, ShoppingBag, Store } from "lucide-react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { routes } from "@/config/routes";
import { formatEUR } from "@/lib/format";
import {
  ETICHETTE_STATO_COMPRATORE,
  ETICHETTE_STATO_VENDITORE,
  sellerStatusDaOrdine,
} from "@/lib/orders/seller-status";
import { getSupabaseClient } from "@/lib/supabase/client";
import { createOrderService } from "@/services/phase7/order-service";
import type { OrderRecord } from "@/services/types";

/** Le stesse schede di frontend/, nello stesso ordine. */
const TAB_COMPRATORE = [
  "tutti",
  "in_attesa_pagamento",
  "pagato",
  "in_preparazione",
  "spedito",
  "consegnato",
  "completato",
  "contestato",
  "rimborsato",
] as const;

const TAB_VENDITORE = [
  "tutti",
  "nuovo",
  "da_preparare",
  "da_spedire",
  "spedito",
  "consegnato",
  "completato",
  "contestato",
] as const;

/**
 * La lista che carica da sé i propri ordini. Resta la porta di `/acquisti`,
 * dove nessun altro blocco della pagina ha bisogno delle stesse righe.
 *
 * `/vendite` non passa più di qui: la dashboard legge gli ordini una volta sola
 * per i KPI e i grafici, e consegna quelle righe a `OrderListView`. Due
 * componenti che chiedono a PostgREST lo stesso elenco nello stesso istante
 * sono due elenchi che possono anche divergere.
 */
export function OrderList({ lato }: { lato: "acquisti" | "vendite" }) {
  const venditore = lato === "vendite";
  const [ordini, setOrdini] = useState<OrderRecord[] | null>(null);
  const [errore, setErrore] = useState<string | null>(null);

  useEffect(() => {
    const servizio = createOrderService(getSupabaseClient());
    let vivo = true;
    void (venditore ? servizio.vendite() : servizio.acquisti()).then((esito) => {
      if (!vivo) return;
      if (esito.ok) setOrdini(esito.data);
      else setErrore(esito.error);
    });
    return () => {
      vivo = false;
    };
  }, [venditore]);

  return <OrderListView lato={lato} ordini={ordini} errore={errore} />;
}

/**
 * Le schede, il filtro e le righe, su ordini che qualcun altro ha già letto.
 *
 * `ordini === null` è il caricamento, non «nessun ordine»: la distinzione
 * esisteva già nella versione che faceva la fetch da sé e sopravvive qui,
 * perché una lista vuota mostrata durante il caricamento direbbe al venditore
 * che non ha venduto niente.
 */
export function OrderListView({
  lato,
  ordini,
  errore,
}: {
  lato: "acquisti" | "vendite";
  ordini: OrderRecord[] | null;
  errore: string | null;
}) {
  const venditore = lato === "vendite";
  const [tab, setTab] = useState<string>("tutti");

  const schede = venditore ? TAB_VENDITORE : TAB_COMPRATORE;

  const filtrati = useMemo(() => {
    if (!ordini) return [];
    if (tab === "tutti") return ordini;
    return ordini.filter((o) =>
      venditore ? sellerStatusDaOrdine(o) === tab : o.stato === tab,
    );
  }, [ordini, tab, venditore]);

  const etichetta = (o: OrderRecord) =>
    venditore
      ? ETICHETTE_STATO_VENDITORE[sellerStatusDaOrdine(o)]
      : ETICHETTE_STATO_COMPRATORE[o.stato];

  if (errore) {
    return <p className="py-16 text-center text-sm text-muted-foreground">{errore}</p>;
  }
  if (!ordini) {
    return <p className="py-16 text-center text-muted-foreground">Caricamento…</p>;
  }

  return (
    <Tabs value={tab} onValueChange={setTab}>
      <div className="-mx-4 overflow-x-auto px-4 sm:mx-0 sm:px-0">
        <TabsList className="inline-flex w-max min-w-full bg-secondary">
          {schede.map((s) => (
            <TabsTrigger key={s} value={s}>
              {s === "tutti"
                ? "Tutti"
                : venditore
                  ? ETICHETTE_STATO_VENDITORE[s as keyof typeof ETICHETTE_STATO_VENDITORE]
                  : ETICHETTE_STATO_COMPRATORE[s as keyof typeof ETICHETTE_STATO_COMPRATORE]}
            </TabsTrigger>
          ))}
        </TabsList>
      </div>

      <TabsContent value={tab} className="mt-4">
        {filtrati.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-border bg-card p-10 text-center">
            {venditore ? (
              <Store className="mx-auto h-8 w-8 text-muted-foreground" />
            ) : (
              <ShoppingBag className="mx-auto h-8 w-8 text-muted-foreground" />
            )}
            <p className="mt-2 font-serif text-xl">Nessun ordine in questa categoria</p>
          </div>
        ) : (
          <ul className="space-y-2">
            {filtrati.map((o) => (
              <li key={o.id}>
                <Link
                  href={routes.ordine(o.id)}
                  className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-3 rounded-2xl border border-border bg-card p-3 transition hover:shadow-sm"
                >
                  <div className="min-w-0">
                    <p className="truncate font-serif font-semibold">{o.id.slice(0, 8)}</p>
                    <p className="truncate text-xs text-muted-foreground">
                      {new Date(o.created_at).toLocaleDateString("it-IT")}
                    </p>
                    <p className="text-xs text-bordeaux">
                      {formatEUR((venditore ? o.prezzo_cents : o.addebito_totale_cents) / 100)}
                    </p>
                  </div>
                  <div className="flex flex-col items-end gap-1">
                    <span className="whitespace-nowrap rounded-full bg-secondary px-2 py-0.5 text-[10px] font-semibold">
                      {etichetta(o)}
                    </span>
                    <ArrowRight className="h-4 w-4 text-muted-foreground" />
                  </div>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </TabsContent>
    </Tabs>
  );
}
