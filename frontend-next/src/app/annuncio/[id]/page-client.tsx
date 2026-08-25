"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import {
  ArrowLeft,
  MapPin,
  ShieldCheck,
  Star,
  Truck,
  // Alias per non collidere con il tipo di dominio Wine, come già in
  // app/home/page-client.tsx.
  Wine as WineIcon,
  ThermometerSun,
  WineOff,
  Flag,
  type LucideIcon,
} from "lucide-react";
import type { Wine } from "@/data/wines";
import { AvatarPersona } from "@/components/vinea/AvatarPersona";
import { useVinea, formatEUR } from "@/lib/vinea-store";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
  DialogFooter,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { DrinkWindowSection } from "@/components/vinea/DrinkWindow";
import { FoodPairingSection } from "@/components/vinea/FoodPairing";
import { TrustBadge, TrustLegend } from "@/components/vinea/TrustBadge";
import { ReportDialog } from "@/components/vinea/ReportDialog";
import { ListingContactActions } from "@/components/vinea/ListingContactActions";
import { ProposalAction } from "@/components/vinea/ProposalAction";
import { ListingOwnerActions } from "@/components/vinea/ListingOwnerActions";
import { GalleriaVino } from "@/components/vinea/GalleriaVino";
import { AperturaBottiglia } from "@/components/vinea/AperturaBottiglia";
import { PriceIntelligencePanel } from "@/components/vinea/PriceIntelligencePanel";
import type { VistaPriceIntelligence } from "@/lib/price-intelligence/insights";
import type { AnnuncioProprietario } from "@/services/listing-service";
import { PAGAMENTI_UI_ABILITATI } from "@/config/features";

export default function AnnuncioDetailPageClient({
  wine,
  correlati,
  proprio,
  vistaPrezzi,
}: {
  wine: Wine;
  correlati: Wine[];
  /**
   * Valorizzato solo quando chi guarda è il venditore: la pagina lato server lo
   * ottiene dalla lettura filtrata dalla RLS, non da un confronto fatto qui.
   */
  proprio?: AnnuncioProprietario | null;
  /** Price Intelligence 1B, già calcolata sul server. */
  vistaPrezzi: VistaPriceIntelligence;
}) {
  const router = useRouter();
  const listingId = wine.listingId ?? wine.id;
  const sonoIlVenditore = Boolean(proprio);

  // Calcolati una volta sola perché la scheda venditore li usa due volte, e
  // perché la condizione dev'essere una: o esiste il profilo e allora sono
  // linkabili sia l'avatar sia il nome, o non esiste e non lo è nessuno dei due.
  const profiloVenditore = wine.venditore.userId ? `/profilo/${wine.venditore.userId}` : null;
  // La persona si disegna con la foundation chiusa, che finisce sulla
  // silhouette e non sulle iniziali: `inizialiDa()` è rimasto alla schermata
  // profilo e non è più il fondo della catena. Qui passa il riferimento —
  // `avatar` è già un URL ricomposto e il resolver lo rifiuterebbe — insieme
  // all'`userId`, che è ciò che rende una foto attribuibile a questa persona e
  // non a un'altra.
  const avatarVenditore = (
    <AvatarPersona
      avatarUrl={wine.venditore.avatarRef}
      proprietarioId={wine.venditore.userId}
      className="h-12 w-12"
    />
  );

  return (
    <div className="space-y-8">
      <button
        onClick={() => router.back()}
        className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-bordeaux"
      >
        <ArrowLeft className="h-4 w-4" /> Indietro
      </button>

      <div className="grid gap-8 md:grid-cols-2">
        {/* La galleria è un componente a sé da quando la pagina di degustazione
            ha avuto bisogno della stessa: due copie si sarebbero separate alla
            prima correzione. */}
        <GalleriaVino immagini={wine.immagini} nome={wine.nome} />

        {/* Info */}
        <div>
          <p className="text-xs uppercase tracking-widest text-salvia">{wine.denominazione}</p>
          <h1 className="mt-1 font-serif text-4xl leading-tight">
            {wine.nome} <span className="text-antracite/70">{wine.annata}</span>
          </h1>
          <p className="mt-1 text-lg text-muted-foreground">{wine.produttore}</p>

          {/* Trust badges: chi ha attestato cosa */}
          <div className="mt-3 flex flex-wrap gap-1.5">
            {wine.venditore.verificato && <TrustBadge source="piattaforma" size="sm" />}
            <TrustBadge source="venditore" size="sm" />
          </div>

          {/*
            Qui accanto al prezzo c'era `prezzoMercato` barrato. È sparito con
            la 1B, e non per ordine: quel numero era un campo che il venditore
            scriveva da sé, senza fonte e senza verifica, e barrato accanto al
            prezzo richiesto diceva «costerebbe di più altrove» con l'autorità
            di un dato di mercato che non aveva. Il riferimento ora sta nel
            pannello Price Intelligence più in basso, dove porta con sé quanti
            annunci lo sostengono e da dove viene.

            La colonna, il mapping in ListingService e il campo su `Wine`
            restano dove sono: questo task toglie una superficie di lettura, non
            un contratto.
          */}
          <div className="mt-4">
            <p className="font-serif text-4xl font-semibold text-bordeaux">
              {formatEUR(wine.prezzo)}
            </p>
          </div>
          <p className="mt-1 text-xs text-muted-foreground">
            {wine.disponibili} {wine.disponibili === 1 ? "bottiglia disponibile" : "bottiglie disponibili"} • Formato {wine.formato}
          </p>

          {/*
            Al venditore la propria scheda mostra i comandi di gestione al posto
            di quelli d'acquisto. Non è solo ordine: comprare da sé, trattare
            con sé e segnalarsi non sono azioni che il database accetterebbe, e
            un pulsante che porta a un rifiuto è peggio di un pulsante assente.
          */}
          {sonoIlVenditore && proprio ? (
            <div className="mt-6">
              <ListingOwnerActions annuncio={proprio} />
            </div>
          ) : (
            <>
              <div
                className={`mt-6 grid gap-2 ${PAGAMENTI_UI_ABILITATI ? "grid-cols-3" : "grid-cols-1"}`}
              >
                {PAGAMENTI_UI_ABILITATI ? (
                  <Button
                    className="col-span-2 bg-bordeaux hover:bg-bordeaux/90"
                    onClick={() => router.push(`/checkout/${wine.id}`)}
                  >
                    Compra ora
                  </Button>
                ) : null}
                <ProposalAction listingId={listingId} listingSlug={wine.id} prezzo={wine.prezzo} />
              </div>

              <ListingContactActions listingId={listingId} />
              <div className="mt-2">
                <ReportDialog
                  targetType="annuncio"
                  targetId={listingId}
                  targetLabel={`${wine.nome} ${wine.annata} — ${wine.venditore.nome}`}
                  trigger={
                    <Button variant="ghost" className="text-muted-foreground hover:text-bordeaux">
                      <Flag className="h-4 w-4" /> Segnala annuncio
                    </Button>
                  }
                />
              </div>
            </>
          )}

          {/* Venditore */}
          <div className="mt-6 rounded-2xl border border-border bg-card p-4">
            <div className="flex items-center gap-3">
              {/* Il profilo pubblico si raggiunge solo quando dietro la scheda
                  c'è davvero una persona: `userId` arriva da `public_listings`
                  e sui dati dimostrativi non esiste. Senza di lui la scheda
                  resta esattamente com'era — nessun link inventato verso una
                  pagina che risponderebbe "profilo non disponibile".

                  L'avatar continua a disegnarsi come prima. Il valore che
                  arriva qui è già passato da `avatarSicuro()` nel mapper, e le
                  iniziali sono il fondo della catena della stessa foundation:
                  sostituirlo con un secondo resolver non aggiungerebbe una
                  difesa, toglierebbe soltanto la foto ai dati dimostrativi. */}
              {profiloVenditore ? (
                <Link
                  href={profiloVenditore}
                  aria-label={`Profilo di ${wine.venditore.nome}`}
                  className="shrink-0 rounded-full focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                  data-testid="annuncio-venditore-avatar"
                >
                  {avatarVenditore}
                </Link>
              ) : (
                avatarVenditore
              )}
              <div className="min-w-0 flex-1">
                <p className="flex items-center gap-1 font-semibold">
                  {profiloVenditore ? (
                    <Link
                      href={profiloVenditore}
                      className="hover:underline"
                      data-testid="annuncio-venditore-username"
                    >
                      {wine.venditore.nome}
                    </Link>
                  ) : (
                    wine.venditore.nome
                  )}
                  {/* Fuori dal link di proposito: la spunta è un attestato sul
                      venditore, non una parte del suo nome, e non è ciò che
                      decide se il profilo è raggiungibile. */}
                  {wine.venditore.verificato && <ShieldCheck className="h-4 w-4 text-salvia" />}
                </p>
                <p className="flex items-center gap-1 text-xs text-muted-foreground">
                  <MapPin className="h-3 w-3" /> {wine.venditore.citta}
                  {wine.venditore.valutazioni > 0 ? (
                    <>
                      {" • "}
                      <Star className="h-3 w-3 fill-oro text-oro" /> {wine.venditore.rating} (
                      {wine.venditore.valutazioni})
                    </>
                  ) : null}
                </p>
              </div>
            </div>
          </div>

          <div className="mt-4">
            <TrustLegend />
          </div>

          <MyBottleActions wineId={wine.wineSlug ?? wine.id} nomeVino={wine.nome} />
        </div>
      </div>

      {/* Price Intelligence: subito sotto il blocco principale, prima delle
          sezioni secondarie. Chi ha appena letto il prezzo richiesto trova qui
          il contesto per giudicarlo — o l'ammissione che il contesto non c'è
          ancora. */}
      <PriceIntelligencePanel vista={vistaPrezzi} />

      {/* Quando berlo + abbinamenti. Indicizzati per vino, non per annuncio:
          su dati reali `id` è lo slug dell'annuncio e non troverebbe nulla. */}
      <div className="grid gap-6 lg:grid-cols-2">
        <DrinkWindowSection wineId={wine.wineSlug ?? wine.id} />
        <FoodPairingSection wineId={wine.wineSlug ?? wine.id} />
      </div>

      {/* Servizio, storia, degustazione */}
      <Tabs defaultValue="storia" className="mt-4">
        <TabsList className="bg-secondary">
          <TabsTrigger value="storia">Storia</TabsTrigger>
          <TabsTrigger value="degustazione">Degustazione</TabsTrigger>
          <TabsTrigger value="dettagli">Servizio e dettagli</TabsTrigger>
        </TabsList>
        <TabsContent value="storia" className="mt-4 rounded-2xl border border-border bg-card p-6">
          <p className="text-base leading-relaxed">{wine.storia}</p>
        </TabsContent>
        <TabsContent
          value="degustazione"
          className="mt-4 rounded-2xl border border-border bg-card p-6"
        >
          <p className="text-base leading-relaxed">{wine.degustazione}</p>
        </TabsContent>
        <TabsContent
          value="dettagli"
          className="mt-4 grid gap-3 rounded-2xl border border-border bg-card p-6 md:grid-cols-2"
        >
          <Info icon={WineIcon} label="Tipologia" value={wine.tipo} />
          <Info icon={MapPin} label="Regione" value={wine.regione} />
          <Info icon={ThermometerSun} label="Conservazione" value={wine.conservazione} />
          <Info icon={Truck} label="Condizione" value={wine.condizione} />
        </TabsContent>
      </Tabs>

      {/* Suggeriti */}
      {correlati.length > 0 && (
        <section>
          <h2 className="mb-4 font-serif text-2xl">Potrebbero interessarti</h2>
          <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
            {correlati.map((w) => (
              <Link
                key={w.id}
                href={`/annuncio/${w.id}`}
                className="group overflow-hidden rounded-xl border border-border bg-card"
              >
                <img
                  src={w.immagini[0]}
                  alt=""
                  className="aspect-square w-full object-cover transition group-hover:scale-105"
                />
                <div className="p-3">
                  <p className="truncate font-serif text-sm font-semibold">
                    {w.nome} {w.annata}
                  </p>
                  <p className="text-sm font-semibold text-bordeaux">{formatEUR(w.prezzo)}</p>
                </div>
              </Link>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}

function Info({ icon: Icon, label, value }: { icon: LucideIcon; label: string; value: string }) {
  return (
    <div className="flex items-start gap-3">
      <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-salvia/15 text-salvia">
        <Icon className="h-4 w-4" />
      </span>
      <div>
        <p className="text-xs uppercase text-muted-foreground">{label}</p>
        <p className="text-sm">{value}</p>
      </div>
    </div>
  );
}

/**
 * Il pannello "Nella tua cantina", ora su bottiglie reali (Fase 6c-2).
 *
 * DUE CAMBIAMENTI VISIBILI, entrambi conseguenza dei dati veri e non di una
 * scelta di design:
 *
 * - Prima compariva a chiunque, anche a chi non aveva mai fatto accesso: le
 *   bottiglie erano un elenco costante uguale per tutti. Ora compare solo a chi
 *   possiede davvero quella bottiglia.
 * - Il conteggio non è più la `quantita` di una pila ma il numero delle proprie
 *   unità ancora chiuse di quel vino. Stessa domanda, stessa risposta: nel mock
 *   una riga rappresentava N bottiglie, qui N righe rappresentano N bottiglie.
 *
 * L'apertura agisce sulla prima unità ancora chiusa, che è l'equivalente esatto
 * del decremento di una pila.
 */
function MyBottleActions({ wineId, nomeVino }: { wineId: string; nomeVino: string }) {
  const { bottiglieCantina, scheduleOpen } = useVinea();
  const mie = bottiglieCantina.filter((b) => b.wineVintageId === wineId);
  const [when, setWhen] = useState("");
  if (mie.length === 0) return null;

  const chiuse = mie.filter((b) => b.quantita > 0);
  // Quella su cui agiscono i comandi: la prima ancora chiusa, o comunque una.
  const bottle = chiuse[0] ?? mie[0];
  const disponibili = chiuse.length;
  const pianificata = mie.find((b) => b.plannedOpenDate)?.plannedOpenDate;

  return (
    <div className="mt-4 rounded-2xl border border-oro/40 bg-oro/10 p-4">
      <p className="text-xs uppercase tracking-wide text-oro">Nella tua cantina</p>
      <p className="mt-1 text-sm">
        {disponibili} {disponibili === 1 ? "bottiglia" : "bottiglie"} disponibili
        {pianificata ? ` · apertura pianificata ${pianificata}` : ""}
      </p>
      <div className="mt-3 flex flex-wrap gap-2">
        {/*
          Prima qui c'era un dialogo solo, che raccoglieva la nota e chiamava
          `bottiglia_apri` subito. Su una bottiglia in vendita finiva
          nell'eccezione della RPC — corretta, ma arrivata dopo il gesto e senza
          una via d'uscita. `AperturaBottiglia` decide prima se la strada è
          libera, se passa per la rimozione dell'annuncio o se non passa affatto,
          e porta il commento sulla schermata di degustazione, che è dove la nota
          ha lo spazio per essere scritta davvero.
        */}
        <AperturaBottiglia bottiglia={bottle} nomeVino={nomeVino} />
        <Dialog>
          <DialogTrigger asChild>
            <Button size="sm" variant="outline">
              Programma apertura
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle className="font-serif text-xl">Programma apertura</DialogTitle>
            </DialogHeader>
            <Input type="date" value={when} onChange={(e) => setWhen(e.target.value)} />
            <DialogFooter>
              <Button
                disabled={!when}
                className="bg-bordeaux hover:bg-bordeaux/90"
                onClick={() => scheduleOpen(bottle.bottleId, when)}
              >
                Salva
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
        <Button asChild size="sm" variant="ghost">
          <Link href="/cantina">Sposta nella cantina</Link>
        </Button>
      </div>
    </div>
  );
}
