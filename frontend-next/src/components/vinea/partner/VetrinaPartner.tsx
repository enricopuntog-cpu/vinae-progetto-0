import Link from "next/link";
import { BadgeCheck, Building2, MapPin, MessageCircle, Store, Users } from "lucide-react";
import type { ReactNode } from "react";
import { AvatarPersona } from "@/components/vinea/AvatarPersona";
import { ReportDialog } from "@/components/vinea/ReportDialog";
import { ReputazionePubblica } from "@/components/vinea/profilo/ReputazionePubblica";
import { AcquistiPartnerNonDisponibili } from "@/components/vinea/partner/AcquistiPartnerNonDisponibili";
import { routes } from "@/config/routes";
import { etichettaTipologia, localitaVetrina, urlMediaVetrina } from "@/lib/partner/vetrina";
import type {
  ClubDelTitolare,
  ProdottoVetrina,
  ProfiloPubblico,
  RecensionePubblica,
  VetrinaPartnerPubblica,
} from "@/services/types";

/**
 * La vetrina pubblica di un Partner attivo: è il suo profilo, non una seconda
 * pagina. La rende `/profilo/[id]` dal server quando
 * `vetrina_partner_pubblica(id)` risponde; per tutti gli altri profili la
 * pagina resta quella di sempre.
 *
 * Due identità, tenute distinte di proposito. L'ATTIVITÀ (nome commerciale,
 * badge «Partner Vinea», informazioni commerciali, catalogo) viene dalla
 * proiezione pubblica del Partner. La PERSONA titolare (username, avatar,
 * qualifiche professionali, recensioni ricevute) viene da `profilo_pubblico`,
 * e la pagina dice chiaramente che le recensioni sono state ricevute
 * dall'account come venditore privato: non diventano reputazione dell'attività.
 *
 * Il catalogo è vuoto fino al Blocco C: gli annunci personali del titolare
 * non sono prodotti dell'attività e la vetrina non li riceve.
 *
 * Nessun dato amministrativo qui: partita IVA, ragione sociale, indirizzo ed
 * email non arrivano dal database, quindi non c'è nulla da nascondere.
 */

const formatoMese = (iso: string | null) =>
  iso ? new Date(iso).toLocaleDateString("it-IT", { month: "long", year: "numeric" }) : null;

function iniziali(nome: string): string {
  const parole = nome.trim().split(/\s+/).filter(Boolean);
  return (parole[0]?.[0] ?? "V").concat(parole[1]?.[0] ?? "").toUpperCase();
}

function Sezione({
  id,
  occhiello,
  titolo,
  children,
}: {
  id: string;
  occhiello?: string;
  titolo: string;
  children: ReactNode;
}) {
  return (
    <section aria-labelledby={id}>
      {occhiello ? (
        <p className="text-xs font-semibold uppercase tracking-[0.18em] text-salvia">{occhiello}</p>
      ) : null}
      <h2 id={id} className="mt-1 font-serif text-2xl font-semibold md:text-3xl">
        {titolo}
      </h2>
      <div className="mt-4">{children}</div>
    </section>
  );
}

export function VetrinaPartner({
  vetrina,
  titolare,
  club,
  recensioni,
  profiloProprio,
  catalogo = [],
}: {
  vetrina: VetrinaPartnerPubblica;
  titolare: ProfiloPubblico;
  club: ClubDelTitolare[];
  recensioni: RecensionePubblica[];
  profiloProprio: boolean;
  /** VP-C: prodotti commerciali pubblicati, mai annunci personali. */
  catalogo?: ProdottoVetrina[];
}) {
  const media = (p: string | null) => urlMediaVetrina(p, vetrina.titolareId, vetrina.partnerId);
  const copertina = media(vetrina.copertinaPath);
  const logo = media(vetrina.logoPath);
  const foto = vetrina.fotoPaths.map(media).filter((u): u is string => u !== null);
  const tipologia = etichettaTipologia(vetrina.tipologia);
  const localita = localitaVetrina(vetrina.sedeCitta, vetrina.sedeProvincia);
  const dal = formatoMese(vetrina.attivoDal);

  const informazioni: Array<[string, string]> = [];
  if (tipologia) informazioni.push(["Tipologia", tipologia]);
  if (localita) informazioni.push(["Sede", localita]);
  informazioni.push(["Paese", vetrina.paese === "IT" ? "Italia" : vetrina.paese]);
  if (dal) informazioni.push(["Partner Vinea dal", dal]);

  return (
    <div className="mx-auto max-w-4xl space-y-10" data-testid="vetrina-partner">
      <section className="overflow-hidden rounded-3xl border border-border bg-card">
        <div className="relative aspect-[16/9] max-h-80 w-full bg-antracite sm:aspect-[21/9]">
          {copertina ? (
            /* eslint-disable-next-line @next/next/no-img-element -- il bucket
               Storage non è fra i domini di next/image (come per le cover dei
               Club); l'immagine è già ricodificata in WebP alle misure giuste. */
            <img
              src={copertina}
              alt={`Copertina di ${vetrina.nomeCommerciale}`}
              className="h-full w-full object-cover"
              data-testid="vetrina-copertina"
            />
          ) : (
            <div
              className="h-full w-full bg-gradient-to-br from-bordeaux via-antracite to-antracite"
              aria-hidden
              data-testid="vetrina-copertina-assente"
            />
          )}
        </div>

        <div className="relative px-5 pb-6 sm:px-8 md:pb-8">
          {/* Solo il logo sale sulla copertina: il nome resta sotto, sul fondo
              chiaro, leggibile qualunque immagine il titolare scelga. */}
          <div className="flex flex-col items-center gap-4 text-center sm:flex-row sm:items-end sm:text-left">
            <div className="-mt-12 h-24 w-24 shrink-0 overflow-hidden rounded-2xl border-4 border-card bg-crema shadow-md sm:-mt-14 sm:h-28 sm:w-28">
              {logo ? (
                /* eslint-disable-next-line @next/next/no-img-element -- vedi copertina. */
                <img
                  src={logo}
                  alt={`Logo di ${vetrina.nomeCommerciale}`}
                  className="h-full w-full object-cover"
                  data-testid="vetrina-logo"
                />
              ) : (
                <div
                  className="flex h-full w-full items-center justify-center bg-bordeaux font-serif text-3xl font-semibold text-crema"
                  aria-hidden
                  data-testid="vetrina-logo-assente"
                >
                  {iniziali(vetrina.nomeCommerciale)}
                </div>
              )}
            </div>
            <div className="min-w-0 flex-1 pb-1">
              <h1 className="break-words font-serif text-3xl font-semibold md:text-4xl">
                {vetrina.nomeCommerciale}
              </h1>
              {/*
                Il badge è della classe commerciale, non della persona: non va
                confuso con «Qualifica professionale verificata», che è un
                titolo del titolare e sta nella sua sezione più sotto.
              */}
              <p className="mt-2 flex flex-wrap items-center justify-center gap-2 sm:justify-start">
                <span
                  className="inline-flex items-center gap-1.5 rounded-full bg-bordeaux px-3 py-1 text-sm font-medium text-crema"
                  data-testid="badge-partner-vinea"
                >
                  <Store className="h-4 w-4 shrink-0" aria-hidden />
                  Partner Vinea · Venditore professionale
                </span>
                {tipologia ? (
                  <span className="inline-flex items-center gap-1 text-sm text-muted-foreground">
                    <Building2 className="h-4 w-4 shrink-0" aria-hidden />
                    {tipologia}
                  </span>
                ) : null}
                {localita ? (
                  <span className="inline-flex items-center gap-1 text-sm text-muted-foreground">
                    <MapPin className="h-4 w-4 shrink-0" aria-hidden />
                    {localita}
                  </span>
                ) : null}
              </p>
            </div>
          </div>

          {vetrina.presentazione ? (
            <p className="mt-6 font-serif text-xl leading-snug text-antracite/90" data-testid="vetrina-presentazione">
              {vetrina.presentazione}
            </p>
          ) : null}
          {profiloProprio ? (
            <p className="mt-4 text-sm">
              <Link href="/partner" className="font-medium text-bordeaux underline">
                Modifica la vetrina
              </Link>
            </p>
          ) : null}
        </div>
      </section>

      {vetrina.descrizione || foto.length > 0 ? (
        <Sezione id="vetrina-attivita" occhiello="Chi siamo" titolo="L'attività">
          {vetrina.descrizione ? (
            <p className="whitespace-pre-wrap text-sm leading-6 text-muted-foreground md:text-base md:leading-7">
              {vetrina.descrizione}
            </p>
          ) : null}
          {foto.length > 0 ? (
            <ul
              className={`grid gap-3 ${foto.length === 1 ? "grid-cols-1" : "grid-cols-2"} ${vetrina.descrizione ? "mt-6" : ""}`}
              data-testid="vetrina-foto"
            >
              {foto.map((url, i) => (
                <li key={url} className="overflow-hidden rounded-2xl bg-secondary">
                  {/* eslint-disable-next-line @next/next/no-img-element -- vedi copertina. */}
                  <img
                    src={url}
                    alt={`Fotografia ${i + 1} di ${foto.length} di ${vetrina.nomeCommerciale}`}
                    loading="lazy"
                    className="aspect-[4/3] h-full w-full object-cover"
                  />
                </li>
              ))}
            </ul>
          ) : null}
        </Sezione>
      ) : null}

      <Sezione id="vetrina-informazioni" titolo="Informazioni commerciali">
        <dl className="grid gap-x-6 gap-y-3 rounded-3xl border border-border bg-card p-6 sm:grid-cols-2">
          {informazioni.map(([etichetta, valore]) => (
            <div key={etichetta} className="min-w-0">
              <dt className="text-xs uppercase tracking-wide text-muted-foreground">{etichetta}</dt>
              <dd className="break-words">{valore}</dd>
            </div>
          ))}
        </dl>
      </Sezione>

      <Sezione id="vetrina-catalogo" occhiello="Prodotti" titolo="Catalogo">
        <AcquistiPartnerNonDisponibili className="mb-4" />
        {/*
          VP-C: il catalogo legge solo prodotti commerciali pubblicati del
          Partner (`vetrina_partner_catalogo`); gli annunci personali del
          titolare non si presentano come merce dell'attività. Finché la
          vendita Partner non apre la pubblicazione, è vuoto.
        */}
        {catalogo.length > 0 ? (
          <ul className="grid gap-3 sm:grid-cols-2" data-testid="vetrina-catalogo">
            {catalogo.map((p) => (
              <li key={p.listingId}>
                <Link
                  href={`/annuncio/${p.slug}`}
                  className="block rounded-2xl border border-border bg-card p-4 transition hover:border-bordeaux/40"
                >
                  <p className="text-xs uppercase tracking-wide text-salvia">{p.produttore}</p>
                  <p className="font-serif font-semibold">
                    {p.nome} {p.annata}
                  </p>
                  <p className="text-xs text-muted-foreground">
                    {p.formato} · {p.disponibili} {p.disponibili === 1 ? "bottiglia" : "bottiglie"}
                  </p>
                </Link>
              </li>
            ))}
          </ul>
        ) : (
        <div
          className="rounded-3xl border border-border bg-card p-6 text-center md:p-8"
          data-testid="vetrina-catalogo-vuoto"
        >
          <p className="font-serif text-xl">Catalogo in preparazione</p>
          <p className="mt-2 text-sm text-muted-foreground">
            I prodotti di questa attività compariranno qui quando la pubblicazione dei prodotti
            Partner sarà aperta.
          </p>
        </div>
        )}
        {/*
          La messaggistica Vinea oggi apre una conversazione solo a partire da
          un annuncio (`conversations.listing_id` è obbligatorio): il contatto
          diretto dalla vetrina è un requisito differito, dichiarato qui invece
          di un pulsante che non porterebbe da nessuna parte.
        */}
        <p className="mt-4 flex gap-2 text-sm text-muted-foreground" data-testid="vetrina-contatto">
          <MessageCircle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
          Il contatto diretto con l&apos;attività tramite i messaggi Vinea arriverà insieme al
          catalogo dei prodotti.
        </p>
      </Sezione>

      {club.length > 0 ? (
        <Sezione id="vetrina-club" occhiello="Community" titolo="I Club dell'attività">
          <ul className="grid gap-3 sm:grid-cols-2" data-testid="vetrina-club">
            {club.map((c) => (
              <li key={c.slug}>
                <Link
                  href={routes.clubDettaglio(c.slug)}
                  className="flex items-center gap-3 rounded-2xl border border-border bg-card p-4 transition-colors hover:border-bordeaux focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                >
                  <Users className="h-5 w-5 shrink-0 text-bordeaux" aria-hidden />
                  <span className="min-w-0">
                    <span className="block truncate font-medium">{c.nome}</span>
                    {c.territorio ? (
                      <span className="block truncate text-xs text-muted-foreground">{c.territorio}</span>
                    ) : null}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        </Sezione>
      ) : null}

      <Sezione id="vetrina-titolare" titolo="Il titolare su Vinea">
        <div className="rounded-3xl border border-border bg-card p-6">
          <div className="flex items-center gap-4">
            <AvatarPersona
              avatarUrl={titolare.avatarUrl}
              proprietarioId={titolare.userId}
              alt={`Avatar di ${titolare.username}`}
              className="h-14 w-14 shrink-0"
            />
            <div className="min-w-0">
              <p className="break-words font-medium">{titolare.username}</p>
              <p className="text-sm text-muted-foreground">Gestisce questa attività su Vinea</p>
            </div>
          </div>
          {titolare.qualificheProfessionali.length > 0 ? (
            <div className="mt-5 border-t border-border pt-4">
              <p className="inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2.5 py-1 text-sm font-medium text-emerald-800">
                <BadgeCheck className="h-4 w-4 shrink-0" aria-hidden />
                Qualifica professionale verificata del titolare
              </p>
              <ul className="mt-3 space-y-2" data-testid="qualifiche-titolare">
                {titolare.qualificheProfessionali.map((q) => (
                  <li
                    key={`${q.titolo}-${q.enteEmittente}-${q.issuedOn ?? ""}`}
                    className="rounded-2xl border border-border px-4 py-3"
                  >
                    <p className="break-words text-sm font-medium">{q.titolo}</p>
                    <p className="break-words text-xs text-muted-foreground">
                      {q.enteEmittente}
                      {q.paese ? ` · ${q.paese}` : ""}
                      {q.issuedOn ? ` · ${q.issuedOn.slice(0, 4)}` : ""}
                    </p>
                  </li>
                ))}
              </ul>
            </div>
          ) : null}
          {!profiloProprio ? (
            <div className="mt-4">
              <ReportDialog targetType="profilo" targetId={titolare.userId} targetLabel={vetrina.nomeCommerciale} />
            </div>
          ) : null}
        </div>
      </Sezione>

      <div className="space-y-3">
        <p className="text-sm text-muted-foreground" data-testid="nota-recensioni-titolare">
          Le recensioni qui sotto sono state ricevute dall&apos;account di {titolare.username} su
          Vinea, anche per vendite tra privati: non sono recensioni di acquisti dall&apos;attività.
        </p>
        <ReputazionePubblica
          userId={titolare.userId}
          totali={titolare.recensioniTotali}
          medie={titolare.recensioniMedie}
          iniziali={recensioni}
        />
      </div>
    </div>
  );
}
