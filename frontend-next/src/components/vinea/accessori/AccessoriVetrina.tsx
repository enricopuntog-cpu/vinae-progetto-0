import Link from "next/link";
import { Eye, GlassWater, ImageOff, PackageOpen } from "lucide-react";
import type { ReactNode } from "react";
import {
  ETICHETTE_CONDIZIONE,
  ETICHETTE_STATO,
  percorsiAccessori,
  type CategoriaAccessorio,
  type SchedaAccessorio,
} from "@/lib/accessori/accessori";
import type { ModalitaAccessori } from "@/lib/accessori/gate";

/**
 * Superficie pubblica degli Accessori (VPM-015A): indice, categoria e dettaglio.
 *
 * Sono componenti SENZA stato e senza azioni: nessun pulsante di acquisto,
 * nessun prezzo, nessuna disponibilità. È la Beta di un catalogo, e lo dice in
 * ogni pagina. Il test di contratto vieta che da qui si raggiunga un percorso
 * di checkout, ordine, proposta o pagamento.
 */

export function BannerAnteprimaAccessori() {
  return (
    <div
      role="note"
      data-testid="accessori-anteprima"
      className="mb-6 flex items-start gap-3 rounded-xl border border-oro/40 bg-oro/10 px-4 py-3 text-sm text-antracite"
    >
      <Eye className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
      <p>
        <strong>Anteprima riservata agli amministratori.</strong> Le bozze sono visibili solo qui e
        la sezione non è aperta al pubblico finché non viene accesa.
      </p>
    </div>
  );
}

export function AvvisoBetaAccessori() {
  return (
    <p
      data-testid="accessori-avviso-beta"
      className="rounded-xl border border-border bg-crema px-4 py-3 text-sm text-antracite/80"
    >
      Catalogo in versione Beta: gli Accessori sono presentati per essere conosciuti, non sono ancora
      in vendita su Vinea e non è possibile acquistarli o riservarli.
    </p>
  );
}

export function StatoVuotoAccessori({
  titolo,
  messaggio,
  azione,
}: {
  titolo: string;
  messaggio: string;
  azione?: ReactNode;
}) {
  return (
    <div
      role="status"
      data-testid="accessori-vuoto"
      className="flex flex-col items-center rounded-2xl border border-dashed border-border bg-secondary/40 px-6 py-14 text-center"
    >
      <span className="flex h-14 w-14 items-center justify-center rounded-full bg-crema text-bordeaux">
        <GlassWater className="h-7 w-7" aria-hidden />
      </span>
      <h2 className="mt-4 font-serif text-xl font-semibold text-antracite">{titolo}</h2>
      <p className="mt-2 max-w-md text-sm text-antracite/70">{messaggio}</p>
      {azione ? <div className="mt-5">{azione}</div> : null}
    </div>
  );
}

function SegnapostoImmagine() {
  return (
    <div className="flex h-full w-full items-center justify-center bg-secondary/60 text-antracite/40">
      <ImageOff className="h-8 w-8" aria-hidden />
    </div>
  );
}

export function SchedaAccessorioCard({
  scheda,
  stato,
  immagine = null,
}: {
  scheda: SchedaAccessorio;
  /** Solo in anteprima: contrassegna le bozze. */
  stato?: string | null;
  /** URL FIRMATA della prima foto (il bucket e privato); `null` = segnaposto. */
  immagine?: string | null;
}) {
  return (
    <li>
      <Link
        href={percorsiAccessori.scheda(scheda.slug)}
        data-testid="accessorio-card"
        className="group flex h-full flex-col overflow-hidden rounded-2xl border border-border bg-card transition hover:border-bordeaux/40 hover:shadow-sm focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-bordeaux"
      >
        <div className="aspect-[4/3] w-full overflow-hidden bg-secondary/40">
          {immagine ? (
            /* eslint-disable-next-line @next/next/no-img-element -- immagine WebP gia ridotta dal caricamento admin. */
            <img
              src={immagine}
              alt={scheda.nome}
              loading="lazy"
              className="h-full w-full object-cover transition group-hover:scale-[1.02]"
            />
          ) : (
            <SegnapostoImmagine />
          )}
        </div>
        <div className="flex flex-1 flex-col gap-1 p-4">
          <p className="text-xs font-semibold uppercase tracking-[0.14em] text-salvia">
            {scheda.categoria.nome}
          </p>
          <h3 className="font-serif text-lg font-semibold leading-snug text-antracite">
            {scheda.nome}
          </h3>
          {scheda.marchio ? <p className="text-sm text-antracite/70">{scheda.marchio}</p> : null}
          <div className="mt-auto flex flex-wrap gap-2 pt-3 text-xs">
            <span className="rounded-full bg-secondary px-2.5 py-1 text-antracite/80">
              {ETICHETTE_CONDIZIONE[scheda.condizione]}
            </span>
            {stato && stato !== "pubblicato" ? (
              <span className="rounded-full bg-oro/20 px-2.5 py-1 font-medium text-antracite">
                {stato}
              </span>
            ) : null}
          </div>
        </div>
      </Link>
    </li>
  );
}

function ChipCategoria({
  href,
  attiva,
  children,
}: {
  href: string;
  attiva: boolean;
  children: ReactNode;
}) {
  return (
    <Link
      href={href}
      aria-current={attiva ? "page" : undefined}
      className={`whitespace-nowrap rounded-full border px-3.5 py-1.5 text-sm transition ${
        attiva
          ? "border-bordeaux bg-bordeaux text-white"
          : "border-border bg-card text-antracite hover:border-bordeaux/40"
      }`}
    >
      {children}
    </Link>
  );
}

export function NavigazioneCategorieAccessori({
  categorie,
  corrente,
}: {
  categorie: readonly CategoriaAccessorio[];
  corrente: string | null;
}) {
  const principali = categorie.filter((c) => c.genitoreSlug === null);
  const radice = categorie.find((c) => c.slug === corrente)?.genitoreSlug ?? corrente;
  const sottocategorie = categorie.filter((c) => c.genitoreSlug === radice && radice !== null);
  return (
    <nav aria-label="Categorie di accessori" className="space-y-3">
      <div className="-mx-4 flex gap-2 overflow-x-auto px-4 pb-1 md:mx-0 md:flex-wrap md:px-0">
        <ChipCategoria href={percorsiAccessori.indice} attiva={corrente === null}>
          Tutti
        </ChipCategoria>
        {principali.map((c) => (
          <ChipCategoria
            key={c.slug}
            href={percorsiAccessori.categoria(c.slug)}
            attiva={c.slug === corrente || c.slug === radice}
          >
            {c.nome}
          </ChipCategoria>
        ))}
      </div>
      {sottocategorie.length > 0 ? (
        <div className="-mx-4 flex gap-2 overflow-x-auto px-4 pb-1 md:mx-0 md:flex-wrap md:px-0">
          {sottocategorie.map((c) => (
            <ChipCategoria
              key={c.slug}
              href={percorsiAccessori.categoria(c.slug)}
              attiva={c.slug === corrente}
            >
              {c.nome}
            </ChipCategoria>
          ))}
        </div>
      ) : null}
    </nav>
  );
}

export function AccessoriVetrina({
  titolo,
  introduzione,
  categorie,
  schede,
  corrente,
  modalita,
  vuoto,
  immagini = {},
}: {
  titolo: string;
  introduzione: string;
  categorie: readonly CategoriaAccessorio[];
  schede: readonly SchedaAccessorio[];
  corrente: string | null;
  modalita: ModalitaAccessori;
  vuoto: { titolo: string; messaggio: string };
  /** URL firmate delle foto, per percorso (vedi `urlImmagini` del servizio). */
  immagini?: Readonly<Record<string, string>>;
}) {
  return (
    <main id="contenuto-principale" className="mx-auto max-w-6xl px-4 py-8 md:py-12">
      {modalita === "anteprima" ? <BannerAnteprimaAccessori /> : null}
      <header className="mb-6">
        <p className="text-xs font-semibold uppercase tracking-[0.18em] text-salvia">
          Accessori per il vino
        </p>
        <h1 className="mt-1 font-serif text-3xl font-semibold text-antracite md:text-4xl">
          {titolo}
        </h1>
        <p className="mt-2 max-w-2xl text-antracite/75">{introduzione}</p>
      </header>

      <div className="mb-6">
        <AvvisoBetaAccessori />
      </div>

      {categorie.length > 0 ? (
        <div className="mb-8">
          <NavigazioneCategorieAccessori categorie={categorie} corrente={corrente} />
        </div>
      ) : null}

      {schede.length === 0 ? (
        <StatoVuotoAccessori
          titolo={vuoto.titolo}
          messaggio={vuoto.messaggio}
          azione={
            corrente ? (
              <Link
                href={percorsiAccessori.indice}
                className="inline-flex items-center gap-2 text-sm font-medium text-bordeaux underline-offset-4 hover:underline"
              >
                <PackageOpen className="h-4 w-4" aria-hidden /> Vedi tutte le categorie
              </Link>
            ) : null
          }
        />
      ) : (
        <ul className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3" data-testid="accessori-elenco">
          {schede.map((s) => (
            <SchedaAccessorioCard
              key={s.slug}
              scheda={s}
              immagine={immagini[s.immagini[0] ?? ""] ?? null}
              stato={s.stato && s.stato !== "pubblicato" ? ETICHETTE_STATO[s.stato] : null}
            />
          ))}
        </ul>
      )}
    </main>
  );
}

