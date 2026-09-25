import Link from "next/link";
import { ChevronLeft, ChevronRight, Grid2X2, List } from "lucide-react";
import { PAGAMENTI_UI_ABILITATI } from "@/config/features";
import {
  etichettaConteggio,
  indirizzoCantinaPubblica,
  type VistaCollezione,
} from "@/lib/profilo/cantina-pubblica-vista";
import type { BottigliaCantinaPubblica } from "@/services/types";
import { BottigliaCantinaCard, CantinaVuota } from "./CantinaPubblica";

/**
 * Il corpo della pagina Cantina pubblica: collezione, viste e pagine.
 *
 * Il componente non legge niente e non conosce il dominio della Cantina del
 * proprietario. Riceve la proiezione pubblica già validata e la disegna. Vista
 * e pagina sono collegamenti, non stato client: indietro/avanti del browser,
 * apertura in una nuova scheda e condivisione dell'indirizzo funzionano senza
 * JavaScript dedicato.
 */
export function CollezionePubblica({
  profiloId,
  bottiglie,
  vista,
  pagina,
  altraPagina,
  profiloProprio,
}: {
  profiloId: string;
  bottiglie: BottigliaCantinaPubblica[];
  vista: VistaCollezione;
  pagina: number;
  altraPagina: boolean;
  profiloProprio: boolean;
}) {
  const mostraCompraOra = PAGAMENTI_UI_ABILITATI && !profiloProprio;
  const classiSelezione = "bg-bordeaux text-crema";
  const classiRiposo = "text-muted-foreground hover:text-foreground";

  return (
    <section aria-labelledby="bottiglie-cantina-pubblica">
      <div className="mb-5 flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-salvia">
            La collezione
          </p>
          <h2 id="bottiglie-cantina-pubblica" className="mt-1 font-serif text-2xl font-semibold">
            Bottiglie in esposizione
          </h2>
          <p className="mt-1 text-sm text-muted-foreground" data-testid="cantina-pubblica-conteggio">
            {etichettaConteggio(bottiglie.length, pagina, altraPagina)}
          </p>
        </div>

        <div
          className="inline-flex rounded-full border border-border bg-card p-1"
          role="group"
          aria-label="Vista della collezione"
          data-testid="cantina-pubblica-selettore-vista"
        >
          <Link
            href={indirizzoCantinaPubblica(profiloId, { vista: "griglia", pagina })}
            className={`inline-flex items-center gap-1.5 rounded-full px-3 py-2 text-sm font-medium ${
              vista === "griglia" ? classiSelezione : classiRiposo
            }`}
            aria-current={vista === "griglia" ? "page" : undefined}
            aria-label="Mostra come griglia"
          >
            <Grid2X2 className="h-4 w-4" aria-hidden />
            <span className="hidden sm:inline">Griglia</span>
          </Link>
          <Link
            href={indirizzoCantinaPubblica(profiloId, { vista: "elenco", pagina })}
            className={`inline-flex items-center gap-1.5 rounded-full px-3 py-2 text-sm font-medium ${
              vista === "elenco" ? classiSelezione : classiRiposo
            }`}
            aria-current={vista === "elenco" ? "page" : undefined}
            aria-label="Mostra come elenco"
          >
            <List className="h-4 w-4" aria-hidden />
            <span className="hidden sm:inline">Elenco</span>
          </Link>
        </div>
      </div>

      {bottiglie.length > 0 ? (
        <ul
          className={
            vista === "griglia"
              ? "grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3"
              : "grid grid-cols-1 gap-3"
          }
          data-testid={`cantina-pubblica-vista-${vista}`}
        >
          {bottiglie.map((bottiglia) => (
            <BottigliaCantinaCard
              key={bottiglia.id}
              bottiglia={bottiglia}
              variante={vista}
              compraOra={mostraCompraOra}
            />
          ))}
        </ul>
      ) : pagina === 1 ? (
        <CantinaVuota />
      ) : (
        <div className="rounded-3xl border border-border bg-card p-6 text-center md:p-8">
          <p className="font-serif text-xl">Nessuna bottiglia in questa pagina</p>
          <p className="mt-2 text-sm text-muted-foreground">
            Torna alla pagina precedente per continuare a visitare la collezione.
          </p>
        </div>
      )}

      {(pagina > 1 || altraPagina) && (
        <nav
          className="mt-8 flex flex-wrap items-center justify-between gap-3"
          aria-label="Pagine della collezione"
          data-testid="cantina-pubblica-paginazione"
        >
          {pagina > 1 ? (
            <Link
              href={indirizzoCantinaPubblica(profiloId, { vista, pagina: pagina - 1 })}
              className="inline-flex items-center gap-1.5 rounded-full border border-border bg-card px-4 py-2 text-sm font-medium"
              rel="prev"
            >
              <ChevronLeft className="h-4 w-4" aria-hidden />
              Pagina precedente
            </Link>
          ) : (
            <span aria-hidden />
          )}

          {altraPagina && (
            <Link
              href={indirizzoCantinaPubblica(profiloId, { vista, pagina: pagina + 1 })}
              className="inline-flex items-center gap-1.5 rounded-full bg-bordeaux px-4 py-2 text-sm font-semibold text-crema"
              rel="next"
            >
              Pagina successiva
              <ChevronRight className="h-4 w-4" aria-hidden />
            </Link>
          )}
        </nav>
      )}
    </section>
  );
}
