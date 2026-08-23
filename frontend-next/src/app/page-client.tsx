"use client";

import Link from "next/link";
import { ArrowRight, Grape, Search, ShieldCheck, Sparkles, Users } from "lucide-react";
import { WineCard } from "@/components/vinea/WineCard";
import { SectionTitle } from "@/components/vinea/Layout";
import { Button } from "@/components/ui/button";
import type { Wine } from "@/data/wines";
import { wineImages } from "@/lib/wine-images";
import { useVinea } from "@/lib/vinea-store";
import { coverSicura } from "@/lib/phase12/club-cover";
import { clubDaScoprire, clubSeguiti } from "@/lib/phase12/club-home";
import { assiClub } from "@/lib/phase12/club-view";
import { formatInteger } from "@/lib/format";
import type { Club } from "@/services/types";

const REGIONI = [
  "Piemonte",
  "Toscana",
  "Veneto",
  "Sicilia",
  "Friuli-Venezia Giulia",
  "Trentino-Alto Adige",
  "Abruzzo",
  "Emilia-Romagna",
  "Lombardia",
  "Campania",
  "Puglia",
  "Marche",
];

const Hero = ({ guest }: { guest: boolean }) => (
  <section className="relative overflow-hidden rounded-3xl bg-bordeaux text-crema hero-glow">
    <div className="absolute inset-0 opacity-35" style={{ backgroundImage: `url(${wineImages.cellar})`, backgroundSize: "cover" }} />
    <div className="absolute inset-0 bg-gradient-to-r from-bordeaux via-bordeaux/85 to-transparent" />
    <div className="relative max-w-2xl px-6 py-16 md:px-14 md:py-24">
      <p className="text-xs uppercase tracking-[0.3em] text-oro">Vinea Wine Club</p>
      <h1 className="mt-4 font-serif text-4xl leading-tight md:text-6xl">
        Ogni bottiglia ha una storia. <span className="gold-shimmer">Trova la prossima.</span>
      </h1>
      <p className="mt-5 text-crema/85">Compra, vendi e cataloga vini tra appassionati italiani.</p>
      <div className="mt-8 flex flex-wrap gap-3">
        <Button asChild size="lg" className="bg-oro text-antracite hover:bg-oro/90">
          <Link href={guest ? "/registrati" : "/esplora"}>
            {guest ? "Registrati" : "Cerca bottiglie"} <ArrowRight className="h-4 w-4" />
          </Link>
        </Button>
        <Button asChild size="lg" variant="outline" className="border-crema/40 bg-transparent text-crema hover:bg-crema/10">
          <Link href={guest ? "/esplora" : "/cantina"}>{guest ? "Esplora il catalogo" : "Apri la cantina"}</Link>
        </Button>
      </div>
    </div>
  </section>
);

const TrustBar = () => (
  <section className="grid gap-4 md:grid-cols-3">
    {[
      { icon: ShieldCheck, title: "Dati dichiarati", text: "Provenienza e conservazione restano attribuite al venditore." },
      { icon: Grape, title: "Solo vino", text: "Il catalogo è dedicato esclusivamente alle bottiglie di vino." },
      { icon: Sparkles, title: "Beta trasparente", text: "Le azioni non ancora operative sono indicate prima dell'uso." },
    ].map(({ icon: Icon, title, text }) => (
      <div key={title} className="flex gap-3 rounded-2xl border border-border bg-card p-5">
        <span className="grid h-11 w-11 place-items-center rounded-full bg-salvia/15 text-salvia"><Icon className="h-5 w-5" /></span>
        <div><p className="font-serif text-lg font-semibold">{title}</p><p className="text-sm text-muted-foreground">{text}</p></div>
      </div>
    ))}
  </section>
);

const ListingGrid = ({ annunci }: { annunci: Wine[] }) => (
  <section>
    <SectionTitle action={<Link href="/esplora" className="text-sm text-bordeaux hover:underline">Vedi tutto →</Link>}>
      Annunci in evidenza
    </SectionTitle>
    {annunci.length === 0 ? (
      <p className="rounded-2xl border border-dashed p-8 text-center text-sm text-muted-foreground">Nessun annuncio pubblicato al momento.</p>
    ) : (
      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">{annunci.slice(0, 4).map((wine) => <WineCard key={wine.id} wine={wine} />)}</div>
    )}
  </section>
);

// La scheda club della Home non e `ClubCard` di /community, ed e una scelta.
// Quella scheda porta il pulsante Segui, cioe `useClubFollow`, cioe una
// scrittura e uno stato client: montarla qui con `onFollow={null}` avrebbe
// disegnato un pulsante spento, e montarla viva avrebbe portato sulla Home una
// lista da tenere allineata. Qui il club e un collegamento: si segue dentro
// /community o nella sua scheda, dove il resto della conversazione gia sta.
const ClubHomeCard = ({ club }: { club: Club }) => {
  // La cover si convalida in lettura come nella scheda del club: il percorso
  // memorizzato non e fidato e l'origine non si legge mai da lui.
  const cover = coverSicura(club.coverImage, club.ownerId);
  const assi = assiClub(club);

  return (
    <Link
      href={`/community/${club.slug}`}
      className="group flex flex-col overflow-hidden rounded-2xl border border-border bg-card card-lift perf-card"
      data-testid={`home-club-${club.slug}`}
    >
      <div className="relative h-24 bg-antracite">
        {cover && (
          /* eslint-disable-next-line @next/next/no-img-element -- il bucket
             Storage non e fra i domini configurati per next/image, come nella
             scheda del club. */
          <img src={cover} alt="" aria-hidden className="h-full w-full object-cover opacity-70" />
        )}
      </div>
      <div className="flex flex-1 flex-col p-4">
        <h3 className="font-serif text-lg font-semibold group-hover:text-bordeaux">{club.nome}</h3>
        {assi.length > 0 && (
          <div className="mt-1 flex flex-wrap gap-1">
            {assi.map((a) => (
              <span
                key={a}
                className="rounded-full bg-secondary px-2 py-0.5 text-[10px] font-medium text-antracite"
              >
                {a}
              </span>
            ))}
          </div>
        )}
        <p className="mt-2 line-clamp-2 text-sm text-muted-foreground">{club.descrizione}</p>
        <p className="mt-3 flex items-center gap-1 text-xs text-muted-foreground">
          <Users className="h-3.5 w-3.5" /> {formatInteger(club.membri)} membri
        </p>
      </div>
    </Link>
  );
};

const ClubSection = ({
  clubs,
  erroreClub,
  autenticato,
}: {
  clubs: Club[];
  erroreClub: string | null;
  autenticato: boolean;
}) => {
  // Due derivazioni, nessun effetto e nessuno stato: i club arrivano gia letti
  // dal componente server, e la Home non li scrive.
  const seguiti = clubSeguiti(clubs);
  const daScoprire = clubDaScoprire(clubs);

  return (
    <section className="space-y-8" data-testid="home-club">
      <SectionTitle
        action={
          <Link href="/community" className="text-sm text-bordeaux hover:underline">
            Tutti i Club →
          </Link>
        }
      >
        <span className="inline-flex items-center gap-2">
          <Users className="h-5 w-5" /> Club
        </span>
      </SectionTitle>

      {erroreClub ? (
        // Un blocco d'errore intero sarebbe pesante per una sezione secondaria
        // della Home: la sezione dice che non ha letto e lascia la via aperta.
        <p
          className="rounded-2xl border border-dashed p-8 text-center text-sm text-muted-foreground"
          data-testid="home-club-errore"
        >
          Club non disponibili al momento.{" "}
          <Link href="/community" className="text-bordeaux hover:underline">
            Riprova dall&apos;area Club
          </Link>
          .
        </p>
      ) : (
        <>
          {/* La sezione dei seguiti esiste solo con una sessione: a un anonimo
              "non segui ancora nessun Club" direbbe una cosa vera e inutile,
              perche `seguito` per lui e falso per costruzione. */}
          {autenticato && (
            <div data-testid="home-club-seguiti">
              <p className="mb-3 text-xs uppercase tracking-wide text-muted-foreground">
                Club che segui
              </p>
              {seguiti.length === 0 ? (
                <div className="rounded-2xl border border-dashed p-8 text-center">
                  <p className="text-sm text-muted-foreground">
                    Non segui ancora nessun Club.
                  </p>
                  <Button asChild size="sm" className="mt-4 bg-bordeaux hover:bg-bordeaux/90">
                    <Link href="/community">Scopri i Club</Link>
                  </Button>
                </div>
              ) : (
                <div className="grid gap-4 md:grid-cols-3">
                  {seguiti.map((c) => (
                    <ClubHomeCard key={c.slug} club={c} />
                  ))}
                </div>
              )}
            </div>
          )}

          <div data-testid="home-club-scopri">
            <p className="mb-3 text-xs uppercase tracking-wide text-muted-foreground">
              Scopri i Club
            </p>
            {daScoprire.length === 0 ? (
              <p className="rounded-2xl border border-dashed p-8 text-center text-sm text-muted-foreground">
                {clubs.length === 0
                  ? "Nessun Club pubblicato, per ora."
                  : "Segui già tutti i Club pubblicati."}
              </p>
            ) : (
              <div className="grid gap-4 md:grid-cols-3">
                {daScoprire.map((c) => (
                  <ClubHomeCard key={c.slug} club={c} />
                ))}
              </div>
            )}
          </div>
        </>
      )}
    </section>
  );
};

const RegionGrid = () => (
  <section>
    <SectionTitle><span className="inline-flex items-center gap-2"><Search className="h-5 w-5" /> Cerca per regione</span></SectionTitle>
    <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
      {REGIONI.map((regione) => <Link key={regione} href={`/esplora?regione=${encodeURIComponent(regione)}`} className="rounded-2xl border bg-card p-4 font-serif hover:border-bordeaux">{regione}</Link>)}
    </div>
  </section>
);

const HomePageClient = ({
  annunci,
  clubs,
  erroreClub,
  autenticato,
}: {
  annunci: Wine[];
  clubs: Club[];
  erroreClub: string | null;
  // Sessione Supabase reale, risolta dal componente server con getUser(). Non e
  // `ruolo` dello switcher demo, che qui continua a decidere solo le due
  // chiamate all'azione dell'hero: i club sono un dominio gia migrato, e il
  // loro `seguito` viene da auth.uid(), non dal ruolo scelto in un menu.
  autenticato: boolean;
}) => {
  const { ruolo } = useVinea();
  return (
    <div className="space-y-14">
      <Hero guest={ruolo === "guest"} />
      <TrustBar />
      <ListingGrid annunci={annunci} />
      <ClubSection clubs={clubs} erroreClub={erroreClub} autenticato={autenticato} />
      <RegionGrid />
    </div>
  );
};

export default HomePageClient;
