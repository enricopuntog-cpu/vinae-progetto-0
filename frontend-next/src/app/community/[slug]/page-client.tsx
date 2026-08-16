"use client";

// Fase 12a - scheda di un club, in sola lettura piu il follow.
//
// Il club arriva gia letto dal componente server, che ha anche gia deciso il
// 404: qui non c'e nessun `notFound()`, a differenza della versione precedente
// alla #44, dove il client rileggeva il mock e decideva da capo. Un componente
// client non e il posto in cui si stabilisce lo stato HTTP di una pagina.
//
// Rispetto a quella versione cadono il pannello moderatori, gli "utenti
// attivi", le bottiglie collegate e l'elenco dei post con i suoi filtri per
// tipo: i primi tre non sono colonne di 12a, l'ultimo e contenuto scritto
// dagli utenti, cioe il 12b. Il pulsante "Crea un post" non torna: era un
// toast dimostrativo, e in un ambiente che scrive davvero un pulsante che
// finge e peggio di un pulsante assente.
//
// Restano il riquadro delle regole - che e una colonna vera - e i due tab
// vuoti che dichiarano cosa manca.

import Link from "next/link";
import { useState } from "react";
import { ArrowLeft, Users } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { ErrorState } from "@/components/vinea/States";
import { formatInteger } from "@/lib/format";
import { assiClub } from "@/lib/phase12/club-view";
import { useClubFollow } from "@/lib/phase12/use-club-follow";
import type { Club } from "@/services/types";
import { ClubProssimamente } from "../page-client";

export default function CommunityDetailPageClient({ iniziale }: { iniziale: Club }) {
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
            <ClubProssimamente testo="Le discussioni del club" />
          </TabsContent>
          <TabsContent value="popolari" className="mt-4">
            <ClubProssimamente testo="I post popolari" />
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
