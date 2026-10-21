import Link from "next/link";
import { ArrowLeft, ChevronLeft, ChevronRight, Flag, ImageOff, Info, Store } from "lucide-react";
import { ReportDialog } from "@/components/vinea/ReportDialog";
import { Button } from "@/components/ui/button";
import { ETICHETTE_CONDIZIONE, percorsiAccessori } from "@/lib/accessori/accessori";
import type { ModalitaAccessori } from "@/lib/accessori/gate";
import {
  TESTI_VETRINA_ANNUNCI,
  percorsiAnnunciAccessori,
  type AnnuncioPubblico,
} from "@/lib/accessori-vendita/annunci-pubblici";
import { euro } from "@/lib/prezzi/classe";
import { BannerAnteprimaAccessori, StatoVuotoAccessori } from "@/components/vinea/accessori/AccessoriVetrina";

/**
 * Vetrina pubblica degli annunci Accessori (VPM-015B3): elenco e dettaglio.
 *
 * Componenti di sola lettura. NON c'è alcun pulsante d'acquisto, di prenotazione
 * o di pagamento, e nessun collegamento al checkout: ogni pagina dice che gli
 * acquisti non sono ancora disponibili. L'unica azione è «Segnala annuncio», che
 * entra nel sistema di moderazione esistente (richiede l'accesso: nessuna porta
 * anonima, per non aprire un canale di spam).
 */

export function AvvisoAcquistiNonDisponibili() {
  return (
    <p
      role="note"
      data-testid="annunci-avviso-acquisti"
      className="flex items-start gap-2 rounded-xl border border-oro/40 bg-oro/10 px-4 py-3 text-sm text-antracite"
    >
      <Info className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
      <span>
        <strong>Gli acquisti non sono ancora disponibili.</strong> Gli annunci sono una vetrina: non è
        possibile comprare, prenotare o pagare un accessorio.
      </span>
    </p>
  );
}

function ImmagineAnnuncio({ url, alt, priorita = false }: { url: string | null; alt: string; priorita?: boolean }) {
  // Proporzioni 4:5 e `object-contain`: gli oggetti verticali (calici, decanter,
  // cavatappi) non vengono ritagliati.
  return (
    <div className="aspect-[4/5] w-full overflow-hidden rounded-xl bg-secondary/50">
      {url ? (
        /* eslint-disable-next-line @next/next/no-img-element -- URL firmata a tempo del bucket privato. */
        <img
          src={url}
          alt={alt}
          loading={priorita ? "eager" : "lazy"}
          className="h-full w-full object-contain"
        />
      ) : (
        <div className="flex h-full w-full items-center justify-center text-antracite/40">
          <ImageOff className="h-8 w-8" aria-label="Immagine non disponibile" />
        </div>
      )}
    </div>
  );
}

export function SchedaAnnuncioPubblicoCard({
  annuncio,
  immagine,
}: {
  annuncio: AnnuncioPubblico;
  immagine: string | null;
}) {
  return (
    <li>
      <Link
        href={percorsiAnnunciAccessori.annuncio(annuncio.id)}
        data-testid="annuncio-pubblico-card"
        className="group flex h-full flex-col gap-3 rounded-2xl border border-border bg-card p-3 transition hover:border-bordeaux/40 hover:shadow-sm focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-bordeaux"
      >
        <ImmagineAnnuncio url={immagine} alt={annuncio.nome} />
        <div className="flex flex-1 flex-col gap-1 px-1 pb-1">
          <p className="text-xs font-semibold uppercase tracking-[0.14em] text-salvia">
            {annuncio.categoria.nome}
          </p>
          <h3 className="font-serif text-lg font-semibold leading-snug text-antracite">{annuncio.nome}</h3>
          {annuncio.marchio ? <p className="text-sm text-antracite/70">{annuncio.marchio}</p> : null}
          <div className="mt-auto flex flex-wrap items-center gap-2 pt-2 text-xs">
            <span className="rounded-full bg-secondary px-2.5 py-1 text-antracite/80">
              {ETICHETTE_CONDIZIONE[annuncio.condizione]}
            </span>
            <span className="rounded-full bg-secondary px-2.5 py-1 text-antracite/80">
              {annuncio.quantita === 1 ? "1 pezzo" : `${annuncio.quantita} pezzi`}
            </span>
          </div>
          <p className="pt-1 text-sm text-antracite">
            <span className="font-semibold">{euro(annuncio.prezzoAcquirenteCents)}</span>{" "}
            <span className="text-xs text-antracite/60">a pezzo, spedizione esclusa</span>
          </p>
          <p className="text-xs text-antracite/60" data-testid="card-non-acquistabile">
            Non ancora acquistabile
          </p>
        </div>
      </Link>
    </li>
  );
}

export function AnnunciVetrina({
  annunci,
  immagini,
  modalita,
  pagina,
  haAltri,
}: {
  annunci: readonly AnnuncioPubblico[];
  immagini: Readonly<Record<string, string>>;
  modalita: ModalitaAccessori;
  pagina: number;
  haAltri: boolean;
}) {
  return (
    <main id="contenuto-principale" className="mx-auto max-w-6xl px-4 py-8 md:py-12">
      {modalita === "anteprima" ? <BannerAnteprimaAccessori /> : null}
      <nav aria-label="Percorso" className="mb-5 text-sm text-antracite/70">
        <Link href={percorsiAccessori.indice} className="inline-flex items-center gap-1 hover:text-bordeaux">
          <ArrowLeft className="h-4 w-4" aria-hidden /> Accessori
        </Link>
      </nav>
      <header className="mb-6">
        <p className="text-xs font-semibold uppercase tracking-[0.18em] text-salvia">Accessori per il vino</p>
        <h1 className="mt-1 font-serif text-3xl font-semibold text-antracite md:text-4xl">
          {TESTI_VETRINA_ANNUNCI.titolo}
        </h1>
        <p className="mt-2 max-w-2xl text-antracite/75">{TESTI_VETRINA_ANNUNCI.introduzione}</p>
      </header>

      <div className="mb-6 space-y-3">
        <AvvisoAcquistiNonDisponibili />
        <p className="text-xs text-antracite/60">{TESTI_VETRINA_ANNUNCI.avvisoModerazione}</p>
      </div>

      {annunci.length === 0 ? (
        <StatoVuotoAccessori
          titolo={TESTI_VETRINA_ANNUNCI.vuotoTitolo}
          messaggio={TESTI_VETRINA_ANNUNCI.vuotoMessaggio}
        />
      ) : (
        <ul className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3" data-testid="annunci-pubblici-elenco">
          {annunci.map((a) => (
            <SchedaAnnuncioPubblicoCard key={a.id} annuncio={a} immagine={immagini[a.foto[0] ?? ""] ?? null} />
          ))}
        </ul>
      )}

      {pagina > 1 || haAltri ? (
        <nav aria-label="Pagine" className="mt-6 flex items-center justify-between gap-3">
          {pagina > 1 ? (
            <Button asChild variant="outline">
              <Link href={`${percorsiAnnunciAccessori.indice}?pagina=${pagina - 1}`}>
                <ChevronLeft aria-hidden /> Precedenti
              </Link>
            </Button>
          ) : (
            <span />
          )}
          {haAltri ? (
            <Button asChild variant="outline">
              <Link href={`${percorsiAnnunciAccessori.indice}?pagina=${pagina + 1}`}>
                Successivi <ChevronRight aria-hidden />
              </Link>
            </Button>
          ) : null}
        </nav>
      ) : null}
    </main>
  );
}

export function DettaglioAnnuncioPubblico({
  annuncio,
  immagini,
  modalita,
  autenticato,
}: {
  annuncio: AnnuncioPubblico;
  immagini: Readonly<Record<string, string>>;
  modalita: ModalitaAccessori;
  /** Sessione presente: senza, la segnalazione rimanda all'accesso (nessuna porta anonima). */
  autenticato: boolean;
}) {
  const urls = annuncio.foto.map((p) => immagini[p] ?? null);
  const accedi = `/accedi?next=${encodeURIComponent(percorsiAnnunciAccessori.annuncio(annuncio.id))}`;
  const { categoria } = annuncio;

  return (
    <main id="contenuto-principale" className="mx-auto max-w-5xl px-4 py-8 md:py-12">
      {modalita === "anteprima" ? <BannerAnteprimaAccessori /> : null}

      <nav aria-label="Percorso" className="mb-5 flex flex-wrap items-center gap-1 text-sm text-antracite/70">
        <Link href={percorsiAccessori.indice} className="inline-flex items-center gap-1 hover:text-bordeaux">
          <ArrowLeft className="h-4 w-4" aria-hidden /> Accessori
        </Link>
        <span aria-hidden>/</span>
        <Link href={percorsiAnnunciAccessori.indice} className="hover:text-bordeaux">
          Annunci
        </Link>
        <span aria-hidden>/</span>
        <span aria-current="page">{categoria.nome}</span>
      </nav>

      <article className="grid gap-8 md:grid-cols-2">
        <div className="space-y-3">
          <ImmagineAnnuncio url={urls[0] ?? null} alt={annuncio.nome} priorita />
          {urls.length > 1 ? (
            <ul className="grid grid-cols-4 gap-2" aria-label="Altre immagini">
              {urls.slice(1).map((u, i) => (
                <li key={annuncio.foto[i + 1]}>
                  <ImmagineAnnuncio url={u} alt={`${annuncio.nome}, dettaglio ${i + 2}`} />
                </li>
              ))}
            </ul>
          ) : null}
        </div>

        <div className="space-y-5">
          <header>
            <p className="text-xs font-semibold uppercase tracking-[0.18em] text-salvia">
              {categoria.genitore ? `${categoria.genitore} · ` : ""}
              {categoria.nome}
            </p>
            <h1 className="mt-1 font-serif text-3xl font-semibold leading-tight text-antracite">{annuncio.nome}</h1>
            {annuncio.marchio ? <p className="mt-1 text-antracite/75">{annuncio.marchio}</p> : null}
            <div className="mt-3 flex flex-wrap gap-2 text-xs">
              <span className="rounded-full bg-secondary px-2.5 py-1 text-antracite/80">
                {ETICHETTE_CONDIZIONE[annuncio.condizione]}
              </span>
              <span className="rounded-full bg-secondary px-2.5 py-1 text-antracite/80">
                {annuncio.quantita === 1 ? "1 pezzo offerto" : `${annuncio.quantita} pezzi offerti`}
              </span>
            </div>
          </header>

          <section aria-labelledby="annuncio-prezzo" className="rounded-xl border border-border bg-card p-4">
            <h2 id="annuncio-prezzo" className="text-sm font-semibold text-antracite/70">
              Prezzo indicativo
            </h2>
            <p className="mt-1 font-serif text-2xl font-semibold text-antracite" data-testid="annuncio-prezzo">
              {euro(annuncio.prezzoAcquirenteCents)}
            </p>
            <p className="text-xs text-antracite/60">{TESTI_VETRINA_ANNUNCI.avvisoPrezzo}</p>
          </section>

          <AvvisoAcquistiNonDisponibili />

          {annuncio.descrizione ? (
            <p className="whitespace-pre-line leading-relaxed text-antracite/85">{annuncio.descrizione}</p>
          ) : null}

          <p className="flex items-center gap-2 text-sm text-antracite/75">
            <Store className="h-4 w-4" aria-hidden /> Proposto da <strong>{annuncio.venditore.username}</strong>
          </p>

          <section aria-labelledby="annuncio-segnala" className="border-t border-border pt-4">
            <h2 id="annuncio-segnala" className="sr-only">
              Segnalazioni
            </h2>
            <p className="mb-2 text-xs text-antracite/60">{TESTI_VETRINA_ANNUNCI.avvisoModerazione}</p>
            {autenticato ? (
              <ReportDialog
                targetType="annuncio_accessorio"
                targetId={annuncio.id}
                targetLabel={annuncio.nome}
                trigger={
                  <Button type="button" variant="outline" size="sm" data-testid="segnala-annuncio">
                    <Flag aria-hidden /> Segnala annuncio
                  </Button>
                }
              />
            ) : (
              <Button asChild variant="outline" size="sm">
                <Link href={accedi} data-testid="segnala-annuncio-accedi">
                  <Flag aria-hidden /> Accedi per segnalare l&apos;annuncio
                </Link>
              </Button>
            )}
          </section>
        </div>
      </article>
    </main>
  );
}
