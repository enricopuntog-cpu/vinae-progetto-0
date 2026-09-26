import Link from "next/link";
import { ArrowLeft, MapPin, Settings } from "lucide-react";
import { notFound } from "next/navigation";
import { AvatarPersona } from "@/components/vinea/AvatarPersona";
import { CollezionePubblica } from "@/components/vinea/profilo/CollezionePubblica";
import { ValoreCantinaPubblica } from "@/components/vinea/profilo/ValoreCantinaPubblica";
import { routes } from "@/config/routes";
import {
  finestraCollezione,
  indirizzoProfiloPubblico,
  paginaCollezione,
  paginaDiBottiglie,
  vistaCollezione,
} from "@/lib/profilo/cantina-pubblica-vista";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { creaPublicProfileService } from "@/services/public-profile-service";

export const metadata = { title: "Cantina pubblica — Vinea" };

/**
 * La Cantina pubblica dedicata di una persona.
 *
 * Il profilo viene letto e validato prima della collezione. È la porta già
 * esistente che decide se quella persona è pubblicamente raggiungibile: la
 * route annidata non deduce l'esistenza di un profilo dalle sue bottiglie e non
 * distingue fra profilo assente, nascosto o moderato. Solo dopo passa alla
 * stessa `cantinaPubblica` usata dall'anteprima, con una finestra più ampia.
 *
 * Il valore di riferimento è una lettura in più, e volutamente fragile: parte
 * insieme alla collezione e può mancare senza conseguenze. Se il proprietario
 * non l'ha attivato il blocco non esiste — nemmeno come segnaposto, perché un
 * «valore nascosto» racconterebbe la scelta che doveva restare privata — e se la
 * lettura fallisce si comporta allo stesso modo: la Cantina e le bottiglie
 * restano, e un guasto del valore non diventa una collezione non disponibile.
 */
export default async function Page({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ vista?: string | string[]; pagina?: string | string[] }>;
}) {
  const [{ id }, query] = await Promise.all([params, searchParams]);
  const vista = vistaCollezione(query.vista);
  const pagina = paginaCollezione(query.pagina);
  const client = await getSupabaseServerClient();
  const service = creaPublicProfileService(client);
  const esitoProfilo = await service.profilo(id);

  if (!esitoProfilo.ok) return <ProfiloNonDisponibile />;
  if (!esitoProfilo.data) notFound();

  const profilo = esitoProfilo.data;
  const localita = [profilo.citta, profilo.provincia].filter(Boolean).join(", ");
  const utente = client ? (await client.auth.getUser()).data.user : null;
  const profiloProprio = utente?.id === profilo.userId;
  /*
   * Il valore parte adesso e si attende dopo: due letture indipendenti che
   * viaggiano insieme, non una in fila all'altra. Deliberatamente NON un
   * `Promise.all`: là un rifiuto porta via entrambe, e qui l'intero punto è che
   * un guasto del valore non tocchi la collezione.
   */
  const promessaValore = service.valoreCantinaPubblica(id);
  const esitoCantina = await service.cantinaPubblica(id, finestraCollezione(pagina));

  if (!esitoCantina.ok) {
    return (
      <div className="mx-auto max-w-5xl space-y-6">
        <IntestazioneCantina
          avatarUrl={profilo.avatarUrl}
          username={profilo.username}
          userId={profilo.userId}
          localita={localita}
          profiloProprio={profiloProprio}
        />
        <section className="rounded-3xl border border-border bg-card p-6 text-center md:p-10">
          <h2 className="font-serif text-2xl">Cantina non disponibile</h2>
          <p className="mx-auto mt-3 max-w-lg text-sm text-muted-foreground">
            Non è stato possibile caricare la collezione. Riprova fra poco.
          </p>
        </section>
      </div>
    );
  }

  const collezione = paginaDiBottiglie(esitoCantina.data);
  const esitoValore = await promessaValore;
  /*
   * Fail closed, in una riga sola. Una lettura fallita e una preferenza
   * disattivata portano allo stesso posto — nessun blocco — e non a un avviso
   * che dica quale dei due è: sarebbe un oracolo su una scelta privata, e un
   * guasto non deve diventare una pagina «Cantina non disponibile».
   */
  const valore = esitoValore.ok && esitoValore.data.visibile ? esitoValore.data : null;

  return (
    <div className="mx-auto max-w-5xl space-y-8">
      <IntestazioneCantina
        avatarUrl={profilo.avatarUrl}
        username={profilo.username}
        userId={profilo.userId}
        localita={localita}
        profiloProprio={profiloProprio}
      />
      {valore && <ValoreCantinaPubblica valore={valore} />}
      <CollezionePubblica
        profiloId={profilo.userId}
        bottiglie={collezione.bottiglie}
        vista={vista}
        pagina={pagina}
        altraPagina={collezione.altraPagina}
        profiloProprio={profiloProprio}
      />
    </div>
  );
}

function ProfiloNonDisponibile() {
  return (
    <div className="mx-auto max-w-3xl">
      <section className="rounded-3xl border border-border bg-card p-6 text-center md:p-10">
        <h1 className="font-serif text-3xl">Profilo non disponibile</h1>
        <p className="mx-auto mt-3 max-w-lg text-sm text-muted-foreground">
          Non è stato possibile caricare questo profilo. Riprova fra poco.
        </p>
        <Link href={routes.ricerca} className="mt-5 inline-block text-sm font-medium text-bordeaux underline">
          Esplora gli annunci
        </Link>
      </section>
    </div>
  );
}

function IntestazioneCantina({
  avatarUrl,
  username,
  userId,
  localita,
  profiloProprio,
}: {
  avatarUrl: string;
  username: string;
  userId: string;
  localita: string;
  profiloProprio: boolean;
}) {
  return (
    <header className="rounded-3xl border border-border bg-card p-5 sm:p-7">
      <div className="flex flex-col gap-5 sm:flex-row sm:items-center">
        <AvatarPersona
          avatarUrl={avatarUrl}
          proprietarioId={userId}
          alt={`Avatar di ${username}`}
          className="h-20 w-20 shrink-0"
        />
        <div className="min-w-0 flex-1">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-salvia">
            Cantina pubblica
          </p>
          <h1 className="mt-1 break-words font-serif text-3xl font-semibold md:text-4xl">
            La cantina di {username}
          </h1>
          {localita && (
            <p className="mt-2 flex items-center gap-1.5 text-sm text-muted-foreground">
              <MapPin className="h-4 w-4 shrink-0" aria-hidden />
              {localita}
            </p>
          )}
        </div>
      </div>

      <div className="mt-5 flex flex-wrap items-center gap-3 border-t border-border pt-4">
        <Link
          href={indirizzoProfiloPubblico(userId)}
          className="inline-flex items-center gap-1.5 text-sm font-medium text-bordeaux underline"
        >
          <ArrowLeft className="h-4 w-4" aria-hidden />
          Torna al profilo
        </Link>
        {profiloProprio && (
          <Link
            href={routes.cantina}
            className="inline-flex items-center gap-1.5 rounded-full border border-border px-3 py-1.5 text-sm font-medium"
          >
            <Settings className="h-4 w-4" aria-hidden />
            Gestisci la mia cantina
          </Link>
        )}
      </div>
    </header>
  );
}
