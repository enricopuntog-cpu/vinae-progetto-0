import Link from "next/link";
import { ArrowRight, ShoppingBag, Tag, Wine as WineIcon } from "lucide-react";
import { WineThumbnail } from "@/components/vinea/WineThumbnail";
import { routes } from "@/config/routes";
import { badgeStatoBottiglia } from "@/lib/cantina/badge-stato";
import {
  ANTEPRIMA_CANTINA_PUBBLICA,
  indirizzoCantinaPubblica,
} from "@/lib/profilo/cantina-pubblica-vista";
import type { BottigliaCantinaPubblica } from "@/services/types";

/**
 * La Cantina pubblica di una persona, dentro il suo profilo.
 *
 * ## È un'anteprima, e la pagina vera sta altrove
 *
 * Fino alla pagina dedicata questa sezione era la Cantina: mostrava una pagina
 * di bottiglie e finiva lì, senza un seguito. Ora la collezione ha una pagina
 * sua — `/profilo/<id>/cantina` — e questa sezione torna a fare quello che una
 * sezione di profilo deve fare: dire che quella persona ha una Cantina, farne
 * vedere abbastanza da invogliare, e portarci. Poche schede e un collegamento
 * valgono più di una lista lunga dentro il profilo di qualcun altro.
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
 * qui dentro, perché note personali, collocazione nello scaffale, costo
 * d'acquisto e fotografie del bucket privato `cantina` non arrivano fino a
 * questo componente: la barriera è nel database e nel mapper del servizio, non
 * in un `if` del JSX.
 *
 * ## «In vendita»
 *
 * È un collegamento all'annuncio vero, non un prezzo. Cantina e Annunci restano
 * due sezioni distinte del profilo e la stessa bottiglia può comparire in
 * entrambe: qui si dice che esiste un annuncio e si porta lì, là si leggono i
 * termini della vendita da `public_listings`, che ne è la sorgente.
 *
 * ## Perché la scheda e il vuoto si esportano da qui
 *
 * La pagina dedicata disegna le stesse bottiglie e lo stesso vuoto. Sono due
 * pezzi puramente visuali — nessuno stato, nessuna lettura, nessun comando del
 * proprietario — e condividerli è la differenza fra un'anteprima che somiglia
 * alla collezione e due schede che si separano alla prima correzione. Ciò che
 * **non** si condivide è il contenitore: il profilo mostra un assaggio, la
 * pagina dedicata ha vista, pagine e navigazione, e nessuno dei due ha bisogno
 * dei parametri dell'altro.
 */
export function CantinaPubblica({
  profiloId,
  bottiglie,
}: {
  profiloId: string;
  bottiglie: BottigliaCantinaPubblica[];
}) {
  const anteprima = bottiglie.slice(0, ANTEPRIMA_CANTINA_PUBBLICA);

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

      {anteprima.length > 0 ? (
        <>
          <ul className="grid gap-3 sm:grid-cols-2" data-testid="cantina-pubblica-elenco">
            {anteprima.map((bottiglia) => (
              <BottigliaCantinaCard key={bottiglia.id} bottiglia={bottiglia} />
            ))}
          </ul>

          {/*
            Il collegamento c'è quando c'è qualcosa da visitare, e non si
            presenta come «vedi tutte»: non si sa quante siano in tutto, perché
            la porta pubblica non conta e nessuno andrà a contarle con una
            migrazione fatta per una scritta.
          */}
          <div className="mt-4 flex justify-center sm:justify-start">
            <Link
              href={indirizzoCantinaPubblica(profiloId)}
              className="inline-flex items-center gap-2 rounded-full bg-bordeaux px-5 py-2.5 text-sm font-semibold text-crema"
              data-testid="cantina-pubblica-visita"
            >
              Visita la cantina
              <ArrowRight className="h-4 w-4" aria-hidden />
            </Link>
          </div>
        </>
      ) : (
        <CantinaVuota />
      )}
    </section>
  );
}

/**
 * Nessuna bottiglia esposta: uno stato normale, con una frase propria.
 *
 * Non è un guasto e non è un invito a fare qualcosa sul profilo di un altro.
 */
export function CantinaVuota() {
  return (
    <div className="rounded-3xl border border-border bg-card p-6 text-center md:p-8">
      <p className="font-serif text-xl">Cantina riservata</p>
      <p className="mt-2 text-sm text-muted-foreground">
        Questa persona non ha ancora reso pubbliche bottiglie della propria Cantina.
      </p>
    </div>
  );
}

/**
 * Una bottiglia esposta, nelle due forme in cui si guarda una collezione.
 *
 * `elenco` è una riga alta quanto la sua fotografia, che è la forma in cui una
 * Cantina si legge — produttore, nome, annata, uno sotto l'altro. `griglia` è
 * la stessa scheda in verticale, la fotografia sopra: è la forma in cui una
 * collezione si guarda. Un solo componente con due disposizioni e non due
 * componenti, perché ciò che cambia è la disposizione — badge, etichette e
 * collegamenti sono gli stessi, e duplicarli vorrebbe dire correggerli due
 * volte.
 *
 * `compraOra` arriva già deciso da chi disegna la pagina: dipende dal gate dei
 * pagamenti e da chi sta guardando, e nessuna delle due cose è una proprietà
 * della bottiglia.
 */
export function BottigliaCantinaCard({
  bottiglia,
  variante = "elenco",
  compraOra = false,
}: {
  bottiglia: BottigliaCantinaPubblica;
  variante?: "elenco" | "griglia";
  compraOra?: boolean;
}) {
  // La stessa regola dei badge della Cantina privata, presa dal modulo che la
  // tiene: `aperta` ha una pastiglia, `chiusa` no. Riscriverla qui avrebbe
  // creato una seconda definizione di quale stato merita un badge.
  const badgeStato = badgeStatoBottiglia(bottiglia.stato);
  const dettagli = [bottiglia.denominazione, bottiglia.regione].filter(Boolean).join(" · ");
  const aGriglia = variante === "griglia";

  return (
    <li
      className={
        aGriglia
          ? "flex flex-col overflow-hidden rounded-2xl border border-border bg-card"
          : "flex gap-3 rounded-2xl border border-border bg-card p-3"
      }
      data-testid={`cantina-pubblica-scheda-${variante}`}
    >
      <div className={aGriglia ? "relative" : "relative shrink-0"}>
        <WineThumbnail
          src={bottiglia.immagine}
          alt={`${bottiglia.produttore} ${bottiglia.nome}`}
          className={
            aGriglia
              ? "aspect-[4/5] w-full object-cover"
              : "h-24 w-20 rounded-lg object-cover"
          }
          sizes={aGriglia ? "(min-width: 1024px) 240px, (min-width: 640px) 45vw, 88vw" : "80px"}
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

      <div className={`flex min-w-0 flex-1 flex-col ${aGriglia ? "p-3" : ""}`}>
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

          I due comandi sono fratelli e non annidati: una pastiglia dentro
          l'altra sarebbe un controllo interattivo dentro un altro, che nessuno
          sa dove porti.
        */}
        {bottiglia.annuncio && (
          <div className="mt-auto flex flex-wrap items-center gap-1.5 pt-2">
            <Link
              href={bottiglia.annuncio.href}
              className="inline-flex w-fit items-center gap-1 rounded-full bg-bordeaux px-2.5 py-1 text-[11px] font-semibold text-crema"
              data-testid="cantina-pubblica-in-vendita"
            >
              <Tag className="h-3 w-3" aria-hidden />
              In vendita
            </Link>
            {compraOra && (
              <Link
                href={routes.checkout(bottiglia.annuncio.slug)}
                className="inline-flex w-fit items-center gap-1 rounded-full border border-bordeaux px-2.5 py-1 text-[11px] font-semibold text-bordeaux"
                data-testid="cantina-pubblica-compra-ora"
              >
                <ShoppingBag className="h-3 w-3" aria-hidden />
                Compra ora
              </Link>
            )}
          </div>
        )}
      </div>
    </li>
  );
}
