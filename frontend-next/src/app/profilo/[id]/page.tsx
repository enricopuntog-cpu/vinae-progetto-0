import Link from "next/link";
import { MapPin } from "lucide-react";
import { notFound } from "next/navigation";
import { AvatarPersona } from "@/components/vinea/AvatarPersona";
import { WineCard } from "@/components/vinea/WineCard";
import { esperienzaLabels } from "@/data/onboarding";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { creaPublicProfileService } from "@/services/public-profile-service";

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const client = await getSupabaseServerClient();
  const service = creaPublicProfileService(client);
  const esitoProfilo = await service.profilo(id);

  if (!esitoProfilo.ok) {
    return (
      <div className="mx-auto max-w-3xl">
        <section className="rounded-3xl border border-border bg-card p-6 text-center md:p-10">
          <h1 className="font-serif text-3xl">Profilo non disponibile</h1>
          <p className="mx-auto mt-3 max-w-lg text-sm text-muted-foreground">
            Non è stato possibile caricare questo profilo. Riprova fra poco.
          </p>
          <Link href="/esplora" className="mt-5 inline-block text-sm font-medium text-bordeaux underline">
            Esplora gli annunci
          </Link>
        </section>
      </div>
    );
  }

  if (!esitoProfilo.data) notFound();

  const profilo = esitoProfilo.data;
  const localita = [profilo.citta, profilo.provincia].filter(Boolean).join(", ");
  const esitoAnnunci = await service.annunciAttivi(id);
  const annunci = esitoAnnunci.ok ? esitoAnnunci.data : [];

  return (
    <div className="mx-auto max-w-3xl space-y-8">
      <section className="rounded-3xl border border-border bg-card p-6 md:p-10">
        <div className="flex flex-col items-center gap-5 text-center sm:flex-row sm:items-start sm:text-left">
          <AvatarPersona
            avatarUrl={profilo.avatarUrl}
            proprietarioId={profilo.userId}
            alt={`Avatar di ${profilo.username}`}
            className="h-24 w-24 shrink-0 md:h-28 md:w-28"
          />
          <div className="min-w-0 flex-1">
            <h1 className="break-words font-serif text-3xl font-semibold md:text-4xl">
              {profilo.username}
            </h1>
            <p className="mt-2 text-sm font-medium text-salvia">
              {esperienzaLabels[profilo.esperienza]}
            </p>
            {localita && (
              <p className="mt-2 flex items-center justify-center gap-1.5 text-sm text-muted-foreground sm:justify-start">
                <MapPin className="h-4 w-4 shrink-0" aria-hidden />
                {localita}
              </p>
            )}
          </div>
        </div>

        {profilo.bio && (
          <div className="mt-7 border-t border-border pt-6">
            <h2 className="font-serif text-xl font-semibold">Su di me</h2>
            <p className="mt-2 whitespace-pre-wrap text-sm leading-6 text-muted-foreground">
              {profilo.bio}
            </p>
          </div>
        )}
      </section>

      <section aria-labelledby="annunci-attivi">
        <div className="mb-4 flex items-end justify-between gap-4">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.18em] text-salvia">
              In vendita
            </p>
            <h2 id="annunci-attivi" className="mt-1 font-serif text-2xl font-semibold md:text-3xl">
              Annunci attivi
            </h2>
          </div>
        </div>

        {annunci.length > 0 ? (
          <div className="grid gap-3 sm:grid-cols-2">
            {annunci.map((annuncio) => (
              <WineCard key={annuncio.id} wine={annuncio} variant="list" />
            ))}
          </div>
        ) : (
          <div className="rounded-3xl border border-border bg-card p-6 text-center md:p-8">
            <p className="font-serif text-xl">Nessun annuncio attivo</p>
            <p className="mt-2 text-sm text-muted-foreground">
              Questa persona non ha annunci disponibili in questo momento.
            </p>
          </div>
        )}
      </section>
    </div>
  );
}
