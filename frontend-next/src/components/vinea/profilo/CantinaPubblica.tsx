import Link from "next/link";
import { Tag, Wine as WineIcon } from "lucide-react";
import { WineThumbnail } from "@/components/vinea/WineThumbnail";
import { badgeStatoBottiglia } from "@/lib/cantina/badge-stato";
import type { BottigliaCantinaPubblica } from "@/services/types";

/**
 * La Cantina pubblica di una persona, dentro il suo profilo.
 *
 * ## Perché non è `WineCard`
 *
 * `WineCard` è la scheda di un **annuncio**: ha un prezzo, una condizione, un
 * badge «in vendita», e la sua `DetailLink` porta a `/annuncio/<slug>`. Una
 * bottiglia esposta in Cantina può non essere in vendita affatto — è il caso
 * normale — e forzarla dentro quella scheda avrebbe costretto a inventare un
 * prezzo, o a passare uno zero che l'interfaccia avrebbe stampato come «0 €».
 * Meglio una scheda piccola che dice solo ciò che si sa.
 *
 * ## Che cosa mostra, e che cosa non potrebbe mostrare
 *
 * Solo i campi di `BottigliaCantinaPubblica`, cioè solo ciò che
 * `public.cantina_pubblica_profilo` restituisce. Non c'è niente da nascondere
 * qui dentro, perché note personali, posizione nello scaffale, costo d'acquisto
 * e fotografie del bucket privato `cantina` non arrivano fino a questo
 * componente: la barriera è nel database e nel mapper del servizio, non in un
 * `if` del JSX.
 *
 * ## «In vendita»
 *
 * È un collegamento all'annuncio vero, non un prezzo. Cantina e Annunci restano
 * due sezioni distinte del profilo e la stessa bottiglia può comparire in
 * entrambe: qui si dice che esiste un annuncio e si porta lì, là si leggono i
 * termini della vendita da `public_listings`, che ne è la sorgente.
 */
export function CantinaPubblica({ bottiglie }: { bottiglie: BottigliaCantinaPubblica[] }) {
  return (
    <section aria-labelledby="cantina-pubblica">
      <div className="mb-4">
        <p className="text-xs font-semibold uppercase tracking-[0.18em] text-salvia">
          In esposizione
        </p>
        <h2 id="cantina-pubblica" className="mt-1 font-serif text-2xl font-semibold md:text-3xl">
          Cantina pubblica
        </h2>
      </div>

      {bottiglie.length > 0 ? (
        <ul className="grid gap-3 sm:grid-cols-2" data-testid="cantina-pubblica-elenco">
          {bottiglie.map((bottiglia) => (
            <BottigliaCard key={bottiglia.id} bottiglia={bottiglia} />
          ))}
        </ul>
      ) : (
        <div className="rounded-3xl border border-border bg-card p-6 text-center md:p-8">
          <p className="font-serif text-xl">Cantina riservata</p>
          <p className="mt-2 text-sm text-muted-foreground">
            Questa persona non ha ancora reso pubbliche bottiglie della propria Cantina.
          </p>
        </div>
      )}
    </section>
  );
}

function BottigliaCard({ bottiglia }: { bottiglia: BottigliaCantinaPubblica }) {
  // La stessa regola dei badge della Cantina privata, presa dal modulo che la
  // tiene: `aperta` ha una pastiglia, `chiusa` no. Riscriverla qui avrebbe
  // creato una seconda definizione di quale stato merita un badge.
  const badgeStato = badgeStatoBottiglia(bottiglia.stato);
  const dettagli = [bottiglia.denominazione, bottiglia.regione].filter(Boolean).join(" · ");

  return (
    <li className="flex gap-3 rounded-2xl border border-border bg-card p-3">
      <div className="relative shrink-0">
        <WineThumbnail
          src={bottiglia.immagine}
          alt={`${bottiglia.produttore} ${bottiglia.nome}`}
          className="h-24 w-20 rounded-lg object-cover"
          sizes="80px"
        />
        {badgeStato && (
          <span
            className={`absolute bottom-1 left-1 inline-flex items-center gap-1 rounded-full px-1.5 py-0.5 text-[9px] font-semibold shadow ${badgeStato.classi}`}
            data-testid="cantina-pubblica-badge-aperta"
          >
            <WineIcon className="h-2.5 w-2.5" aria-hidden /> {badgeStato.testo}
          </span>
        )}
      </div>

      <div className="flex min-w-0 flex-1 flex-col">
        <p className="truncate text-xs uppercase tracking-wide text-salvia">
          {bottiglia.produttore}
        </p>
        <p className="font-serif text-base font-semibold break-words">
          {bottiglia.nome} {bottiglia.annata}
        </p>
        {dettagli && <p className="mt-0.5 truncate text-xs text-muted-foreground">{dettagli}</p>}
        <p className="mt-0.5 text-xs text-muted-foreground">
          {bottiglia.tipo} · {bottiglia.formato}
        </p>

        {/*
          Il collegamento esiste solo quando esiste l'annuncio. Non c'è un ramo
          «non in vendita» con una scritta grigia: una bottiglia in Cantina non
          è in vendita per definizione, e dirlo su ognuna sarebbe rumore.
        */}
        {bottiglia.annuncio && (
          <Link
            href={bottiglia.annuncio.href}
            className="mt-auto inline-flex w-fit items-center gap-1 rounded-full bg-bordeaux px-2.5 py-1 text-[11px] font-semibold text-crema"
            data-testid="cantina-pubblica-in-vendita"
          >
            <Tag className="h-3 w-3" aria-hidden />
            In vendita
          </Link>
        )}
      </div>
    </li>
  );
}
