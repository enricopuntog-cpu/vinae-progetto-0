"use client";

// Fase 12a - scheda di un club, in sola lettura piu il follow.
//
// Il club arriva gia letto dal componente server, che ha anche gia deciso il
// 404: qui non c'e nessun `notFound()`, a differenza della versione precedente
// alla #44, dove il client rileggeva il mock e decideva da capo. Un componente
// client non e il posto in cui si stabilisce lo stato HTTP di una pagina.
//
// Rispetto a quella versione cadono il pannello moderatori, gli "utenti
// attivi" e le bottiglie collegate: non sono colonne della 12a e non lo sono
// diventate con la 12b. Il pulsante "Crea un post" del mock non torna con quel
// nome ne con quel comportamento - era un toast dimostrativo. Torna la cosa
// vera: «Apri una discussione», che scrive su club_posts.
//
// I due tab non dicono piu "disponibile a breve". Mostrano le discussioni reali
// del club, ciascuna con il proprio "Segnala": e la 12c, che non e una
// rifinitura ma la condizione a cui la scrittura e stata ammessa.

import Link from "next/link";
import { useState } from "react";
import { ArrowLeft, Users } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { ClubDiscussioni } from "@/components/vinea/ClubDiscussioni";
import { ErrorState } from "@/components/vinea/States";
import { formatInteger } from "@/lib/format";
import { assiClub } from "@/lib/phase12/club-view";
import { ordinaPerPopolarita } from "@/lib/phase12/club-post-view";
import { useClubFollow } from "@/lib/phase12/use-club-follow";
import type { Club, ClubPost } from "@/services/types";

export default function CommunityDetailPageClient({
  iniziale,
  discussioni,
}: {
  iniziale: Club;
  discussioni: ClubPost[];
}) {
  const [club, setClub] = useState<Club>(iniziale);
  const { cambiaFollow, inCorso, error } = useClubFollow();
  const attesa = inCorso === club.slug;
  const assi = assiClub(club);

  const onFollow = async () => {
    if (!cambiaFollow) return;
    const aggiornato = await cambiaFollow(club);
    if (aggiornato) setClub(aggiornato);
  };

  return (
    <div className="space-y-8">
      <Link
        href="/community"
        className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground"
      >
        <ArrowLeft className="h-4 w-4" /> Scopri altri club
      </Link>

      <section className="relative overflow-hidden rounded-3xl bg-antracite text-crema hero-glow">
        <div className="hero-grain" aria-hidden />
        <div className="relative flex flex-col gap-4 p-6 md:p-10">
          <div className="flex flex-wrap gap-2">
            <span className="w-fit rounded-full bg-crema/20 px-3 py-1 text-xs">Club</span>
            {assi.map((a) => (
              <span key={a} className="w-fit rounded-full bg-crema/10 px-3 py-1 text-xs">
                {a}
              </span>
            ))}
          </div>
          <h1 className="font-serif text-3xl md:text-5xl">{club.nome}</h1>
          <p className="max-w-2xl text-crema/85">{club.descrizione}</p>
          <p className="flex items-center gap-1 text-sm">
            <Users className="h-4 w-4" /> {formatInteger(club.membri)} membri
          </p>
          <div className="flex flex-wrap gap-2">
            <Button
              onClick={() => void onFollow()}
              disabled={!cambiaFollow || attesa}
              data-testid={`club-follow-${club.slug}`}
              className={
                club.seguito
                  ? "bg-crema text-antracite hover:bg-crema/90"
                  : "bg-oro text-antracite hover:bg-oro/90"
              }
            >
              {attesa ? "…" : club.seguito ? "Segui già" : "Segui club"}
            </Button>
            <Button
              asChild
              variant="outline"
              className="border-crema/40 bg-transparent text-crema hover:bg-crema/10"
            >
              <Link href="/community">Scopri altri club</Link>
            </Button>
          </div>
        </div>
      </section>

      {error && <ErrorState title="Operazione non riuscita" message={error} home={false} />}

      <div className="grid gap-6 lg:grid-cols-[1fr_320px]">
        <Tabs defaultValue="discussioni">
          <TabsList className="bg-secondary">
            <TabsTrigger value="discussioni">Discussioni del club</TabsTrigger>
            <TabsTrigger value="popolari">Post popolari</TabsTrigger>
          </TabsList>
          <TabsContent value="discussioni" className="mt-4">
            <ClubDiscussioni iniziali={discussioni} clubSlug={club.slug} />
          </TabsContent>
          <TabsContent value="popolari" className="mt-4">
            {/* Stesse righe, altro ordine: `ordinaPerPopolarita` lavora su una
                copia, cosi i due tab non si spostano l'ordine a vicenda. Non
                c'e una seconda lettura, perche non c'e un secondo insieme. */}
            <ClubDiscussioni
              iniziali={discussioni}
              clubSlug={club.slug}
              ordina={ordinaPerPopolarita}
            />
          </TabsContent>
        </Tabs>

        <aside className="space-y-4">
          <div className="rounded-2xl border border-border bg-card p-4" data-testid="club-regole">
            <p className="font-serif text-lg font-semibold">Regole</p>
            {club.regole.length === 0 ? (
              <p className="mt-2 text-sm text-muted-foreground">
                Questo club non ha ancora pubblicato le sue regole.
              </p>
            ) : (
              <ol className="mt-2 list-decimal space-y-1 pl-4 text-sm">
                {club.regole.map((r) => (
                  <li key={r}>{r}</li>
                ))}
              </ol>
            )}
          </div>
        </aside>
      </div>
    </div>
  );
}
