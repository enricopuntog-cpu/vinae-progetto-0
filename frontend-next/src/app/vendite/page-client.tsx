"use client";

/**
 * La dashboard del venditore.
 *
 * `/vendite` mostrava soltanto `OrderList`. Continua a mostrarla — la gestione
 * degli ordini è rimasta dov'era, con le stesse schede e la stessa derivazione
 * di `sellerStatusDaOrdine` — ma sopra ci sono ora il riepilogo, gli annunci
 * del venditore e due letture dell'andamento.
 *
 * **Una sola lettura degli ordini.** I KPI, i due grafici e la lista lavorano
 * tutti sullo stesso array caricato qui: `OrderListView` riceve le righe invece
 * di richiederle. Nessun numero in cima alla pagina può contraddire la lista in
 * fondo, perché non esiste una seconda risposta con cui contraddirla.
 *
 * Nessuna azione nuova sul ciclo di vita: le schede annuncio linkano alla
 * pagina di gestione che esiste già, dove `ListingOwnerActions` decide da sé
 * cosa è pubblicabile, modificabile o sospendibile.
 */

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { Bar, BarChart, CartesianGrid, XAxis, YAxis } from "recharts";
import { Loader2, PackageCheck, Store, Tag } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
  type ChartConfig,
} from "@/components/ui/chart";
import { Kpi, SectionTitle } from "@/components/vinea/Layout";
import { OrderListView } from "@/components/vinea/orders/OrderList";
import { routes } from "@/config/routes";
import { formatEUR, formatInteger } from "@/lib/format";
import { ETICHETTE_STATO_VENDITORE } from "@/lib/orders/seller-status";
import {
  andamentoMensile,
  andamentoVuoto,
  distribuzionePerStato,
  ordinaAnnunciPerGestione,
  riepilogoVenditore,
} from "@/lib/vendite/dashboard";
import { getSupabaseClient } from "@/lib/supabase/client";
import {
  createListingService,
  ETICHETTA_STATO,
  type AnnuncioProprietario,
} from "@/services/listing-service";
import { createOrderService } from "@/services/phase7/order-service";
import type { OrderRecord } from "@/services/types";

/** Quanti annunci la dashboard mostra prima di rimandare al catalogo completo. */
const ANNUNCI_IN_VETRINA = 6;

const CONFIG_STATI: ChartConfig = {
  ordini: { label: "Ordini", color: "var(--bordeaux)" },
};

// «Di cui oggi completati» e non «Completati»: entrambe le serie sono
// raggruppate per mese di *ricezione*, quindi la barra dorata di marzo è la
// quota degli ordini di marzo che oggi risulta chiusa — non i completamenti
// avvenuti a marzo. Quel secondo numero richiederebbe un istante di
// completamento che il client non può leggere.
const CONFIG_ANDAMENTO: ChartConfig = {
  ordini: { label: "Ricevuti", color: "var(--bordeaux)" },
  completati: { label: "Di cui oggi completati", color: "var(--oro)" },
};

export default function VenditePageClient() {
  const [ordini, setOrdini] = useState<OrderRecord[] | null>(null);
  const [erroreOrdini, setErroreOrdini] = useState<string | null>(null);
  const [annunci, setAnnunci] = useState<AnnuncioProprietario[] | null>(null);

  useEffect(() => {
    const client = getSupabaseClient();
    let vivo = true;

    void Promise.all([
      createOrderService(client).vendite(),
      createListingService(client).mieiAnnunci(),
    ]).then(([esitoOrdini, mieiAnnunci]) => {
      if (!vivo) return;
      if (esitoOrdini.ok) setOrdini(esitoOrdini.data);
      else setErroreOrdini(esitoOrdini.error);
      setAnnunci(mieiAnnunci);
    });

    return () => {
      vivo = false;
    };
  }, []);

  const caricamento = ordini === null && erroreOrdini === null;

  const righe = useMemo(() => ordini ?? [], [ordini]);
  const schede = useMemo(() => annunci ?? [], [annunci]);

  const riepilogo = useMemo(() => riepilogoVenditore(righe, schede), [righe, schede]);
  const distribuzione = useMemo(() => distribuzionePerStato(righe), [righe]);

  // L'orologio si legge una volta sola, al montaggio: `andamentoMensile` vuole
  // un istante e non deve riceverne uno nuovo a ogni render, o la finestra si
  // ricalcolerebbe senza motivo.
  const [adesso] = useState(() => new Date());
  const andamento = useMemo(() => andamentoMensile(righe, adesso), [righe, adesso]);

  const inVetrina = useMemo(
    () => ordinaAnnunciPerGestione(schede).slice(0, ANNUNCI_IN_VETRINA),
    [schede],
  );

  const datiStati = useMemo(
    () =>
      distribuzione.map((fetta) => ({
        etichetta: ETICHETTE_STATO_VENDITORE[fetta.stato],
        ordini: fetta.ordini,
      })),
    [distribuzione],
  );

  const intestazione = (
    <header className="flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 className="font-serif text-3xl md:text-4xl">Le mie vendite</h1>
        <p className="text-muted-foreground">
          Annunci, ordini e andamento della tua attività su Vinea.
        </p>
      </div>
      <Button asChild className="bg-bordeaux hover:bg-bordeaux/90">
        <Link href={routes.vendi}>
          <Tag className="h-4 w-4" /> Metti in vendita
        </Link>
      </Button>
    </header>
  );

  // Finché gli ordini non sono arrivati non si mostra nessun numero. Un KPI a
  // zero non è un caricamento: è un'affermazione, e per chi ha davvero venduto
  // sarebbe falsa per il tempo di una risposta di rete.
  if (caricamento) {
    return (
      <div className="space-y-6">
        {intestazione}
        <p className="py-16 text-center text-sm text-muted-foreground">
          <Loader2 className="mx-auto mb-2 h-5 w-5 animate-spin text-bordeaux" />
          Carico la tua attività…
        </p>
      </div>
    );
  }

  // Stessa ragione: senza sessione `vendite()` risponde «Autenticazione
  // richiesta», e la pagina non ha nulla di vero da riassumere. Il messaggio è
  // quello che `/vendite` mostrava già prima della dashboard.
  if (erroreOrdini !== null) {
    return (
      <div className="space-y-6">
        {intestazione}
        <OrderListView lato="vendite" ordini={null} errore={erroreOrdini} />
      </div>
    );
  }

  return (
    <div className="space-y-8">
      {intestazione}

      {/* -- Riepilogo ------------------------------------------------------ */}
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Kpi
          label="Annunci attivi"
          value={formatInteger(riepilogo.annunciAttivi)}
          hint={`su ${formatInteger(schede.length)} in totale`}
        />
        <Kpi
          label="Da gestire"
          value={formatInteger(riepilogo.ordiniDaGestire)}
          hint="Ordini in attesa di un tuo gesto"
        />
        <Kpi
          label="Vendite completate"
          value={formatInteger(riepilogo.venditeCompletate)}
          hint="Ordini chiusi come completati"
        />
        <Kpi
          label="Valore completate"
          value={formatEUR(riepilogo.valoreVenditeCompletateCents / 100)}
          // Non è un incassato e non è un payout: è il prezzo venditore
          // congelato sugli ordini completati. Il rilascio dei fondi è un'altra
          // cosa e vive nella 7b.
          hint="Prezzo venditore, non un incassato"
        />
      </div>

      {/* -- Andamento attività --------------------------------------------- */}
      {righe.length > 0 && (
        <section>
          <SectionTitle>Andamento attività</SectionTitle>
          <div className="grid gap-4 lg:grid-cols-2">
            <div className="rounded-2xl border border-border bg-card p-4">
              <p className="text-xs uppercase tracking-wide text-muted-foreground">
                Ordini per stato
              </p>
              <ChartContainer config={CONFIG_STATI} className="mt-3 aspect-[16/9] w-full">
                <BarChart data={datiStati} margin={{ left: 4, right: 4, top: 8 }}>
                  <CartesianGrid vertical={false} />
                  <XAxis
                    dataKey="etichetta"
                    tickLine={false}
                    axisLine={false}
                    tickMargin={8}
                    interval={0}
                    angle={-30}
                    textAnchor="end"
                    height={64}
                  />
                  <YAxis allowDecimals={false} tickLine={false} axisLine={false} width={28} />
                  <ChartTooltip content={<ChartTooltipContent />} />
                  <Bar dataKey="ordini" fill="var(--color-ordini)" radius={[6, 6, 0, 0]} />
                </BarChart>
              </ChartContainer>
            </div>

            <div className="rounded-2xl border border-border bg-card p-4">
              <p className="text-xs uppercase tracking-wide text-muted-foreground">
                Ordini ricevuti per mese
              </p>
              {andamentoVuoto(andamento) ? (
                <p className="py-10 text-center text-sm text-muted-foreground">
                  Nessun ordine negli ultimi sei mesi.
                </p>
              ) : (
                <ChartContainer config={CONFIG_ANDAMENTO} className="mt-3 aspect-[16/9] w-full">
                  <BarChart data={andamento} margin={{ left: 4, right: 4, top: 8 }}>
                    <CartesianGrid vertical={false} />
                    <XAxis
                      dataKey="etichetta"
                      tickLine={false}
                      axisLine={false}
                      tickMargin={8}
                      interval={0}
                    />
                    <YAxis allowDecimals={false} tickLine={false} axisLine={false} width={28} />
                    <ChartTooltip content={<ChartTooltipContent />} />
                    <Bar dataKey="ordini" fill="var(--color-ordini)" radius={[6, 6, 0, 0]} />
                    <Bar dataKey="completati" fill="var(--color-completati)" radius={[6, 6, 0, 0]} />
                  </BarChart>
                </ChartContainer>
              )}
              {/* Il mese è quello in cui l'ordine è nato: non esiste una
                  colonna di completamento leggibile dal client. */}
              <p className="mt-2 text-xs text-muted-foreground">
                Raggruppati per mese di ricezione dell&apos;ordine. La seconda barra è la quota di
                quegli ordini che oggi risulta completata, non i completamenti avvenuti in quel
                mese.
              </p>
            </div>
          </div>
        </section>
      )}

      {/* -- I miei annunci -------------------------------------------------- */}
      <section>
        <SectionTitle
          action={
            schede.length > ANNUNCI_IN_VETRINA ? (
              <span className="text-sm text-muted-foreground">
                {formatInteger(inVetrina.length)} di {formatInteger(schede.length)}
              </span>
            ) : undefined
          }
        >
          I miei annunci
        </SectionTitle>

        {inVetrina.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-border bg-card p-10 text-center">
            <Store className="mx-auto h-8 w-8 text-muted-foreground" />
            <p className="mt-2 font-serif text-xl">Nessun annuncio</p>
            <p className="mt-1 text-sm text-muted-foreground">
              Le bottiglie in vendita partono dalla tua cantina.
            </p>
            <Button asChild className="mt-4 bg-bordeaux hover:bg-bordeaux/90">
              <Link href={routes.vendi}>Metti in vendita</Link>
            </Button>
          </div>
        ) : (
          <ul className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
            {inVetrina.map((annuncio) => (
              <li key={annuncio.wine.listingId}>
                <Link
                  // `detailHref` è opzionale su `Wine` perché una bottiglia di
                  // cantina senza annuncio non ha pagina; qui l'annuncio c'è
                  // sempre, e il ripiego ricompone lo stesso percorso dallo
                  // slug — la stessa forma usata da `/esplora`.
                  href={annuncio.wine.detailHref ?? routes.annuncio(annuncio.wine.id)}
                  className="flex h-full items-center gap-3 rounded-2xl border border-border bg-card p-3 transition hover:shadow-sm"
                >
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={annuncio.wine.immagini[0]}
                    alt=""
                    className="h-16 w-12 shrink-0 rounded-lg object-cover"
                  />
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-serif font-semibold">{annuncio.wine.nome}</p>
                    <p className="truncate text-xs text-muted-foreground">
                      {annuncio.wine.produttore} · {annuncio.wine.annata}
                    </p>
                    <p className="mt-1 text-sm font-semibold text-bordeaux">
                      {formatEUR(annuncio.wine.prezzo)}
                    </p>
                  </div>
                  <span className="shrink-0 self-start whitespace-nowrap rounded-full bg-secondary px-2 py-0.5 text-[10px] font-semibold">
                    {ETICHETTA_STATO[annuncio.stato]}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>

      {/* -- Vendite --------------------------------------------------------- */}
      <section>
        <SectionTitle
          action={
            <span className="inline-flex items-center gap-1 text-sm text-muted-foreground">
              <PackageCheck className="h-4 w-4" />
              {formatInteger(righe.length)} ordini
            </span>
          }
        >
          Vendite
        </SectionTitle>
        <OrderListView lato="vendite" ordini={ordini} errore={erroreOrdini} />
      </section>
    </div>
  );
}
