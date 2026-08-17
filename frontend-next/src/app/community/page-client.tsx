"use client";

// Fase 12a - elenco dei club, in sola lettura piu il follow.
//
// Questo file non e la modifica di quello che c'era: la #44 aveva cancellato
// per intero il page-client precedente insieme alla UI mock che conteneva, e
// /community era diventata un notFound(). Filtri, tab e schede riprendono
// quella versione, perche il lavoro di interfaccia era gia stato fatto, ma
// nascono contro ClubService reale invece che contro `@/data/communities` e lo
// store demo.
//
// Cosa e caduto rispetto a quella versione, e perche: copertina, categoria,
// moderatori, "attivi oggi" e bottiglie collegate non sono colonne di 12a.
// Mostrarli avrebbe voluto dire inventare un dato o riesumare il mock, che e
// esattamente cio che la #44 ha tolto dalla beta.
//
// I tab "Discussioni del club" e "Post popolari" non dicono piu "disponibile a
// breve": dalla 12b mostrano le discussioni reali, di TUTTI i club, ordinate
// per data e per popolarita. Qui si legge, si mette like e si segnala; si
// SCRIVE dentro la scheda di un club, perche una discussione ha bisogno di un
// club in cui stare e un menu "in quale?" sarebbe una schermata che nessuno ha
// chiesto.

import Link from "next/link";
import { useMemo, useState } from "react";
import { Search, Users } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { ClubDiscussioni } from "@/components/vinea/ClubDiscussioni";
import { SectionTitle } from "@/components/vinea/Layout";
import { ErrorState } from "@/components/vinea/States";
import { wineImages } from "@/lib/wine-images";
import { formatInteger } from "@/lib/format";
import {
  assiClub,
  ETICHETTE_FILTRO,
  FILTRI_VUOTI,
  filtraClub,
  opzioniFiltro,
  type CampoFiltro,
  type FiltriClub,
} from "@/lib/phase12/club-view";
import { ordinaPerPopolarita } from "@/lib/phase12/club-post-view";
import { useClubFollow } from "@/lib/phase12/use-club-follow";
import type { Club, ClubPost } from "@/services/types";

export default function CommunityHubPageClient({
  iniziali,
  erroreLettura,
  discussioni,
}: {
  iniziali: Club[];
  erroreLettura: string | null;
  discussioni: ClubPost[];
}) {
  // I club arrivano gia letti dal componente server. Lo stato locale esiste
  // solo perche il follow ne sostituisce una riga: non e una seconda copia da
  // tenere allineata con una lettura client.
  const [clubs, setClubs] = useState<Club[]>(iniziali);
  const [filtri, setFiltri] = useState<FiltriClub>(FILTRI_VUOTI);
  const { cambiaFollow, inCorso, error } = useClubFollow();

  const filtrati = useMemo(() => filtraClub(clubs, filtri), [clubs, filtri]);
  const seguiti = useMemo(() => clubs.filter((c) => c.seguito), [clubs]);
  const opzioni = useMemo(
    () =>
      (Object.keys(ETICHETTE_FILTRO) as CampoFiltro[]).map((campo) => ({
        campo,
        valori: opzioniFiltro(clubs, campo),
      })),
    [clubs],
  );

  const aggiorna = (campo: keyof FiltriClub, valore: string) =>
    setFiltri((precedenti) => ({ ...precedenti, [campo]: valore }));

  const onFollow = cambiaFollow
    ? async (club: Club) => {
        const aggiornato = await cambiaFollow(club);
        if (aggiornato) {
          setClubs((precedenti) =>
            precedenti.map((c) => (c.slug === aggiornato.slug ? aggiornato : c)),
          );
        }
      }
    : null;

  return (
    <div className="space-y-10">
      <section className="relative overflow-hidden rounded-3xl bg-antracite text-crema hero-glow">
        <div
          className="absolute inset-0 opacity-40 animate-ken-burns"
          style={{
            backgroundImage: `url(${wineImages.glasses})`,
            backgroundSize: "cover",
            backgroundPosition: "center",
          }}
        />
        <div className="absolute inset-0 bg-gradient-to-r from-antracite via-antracite/80 to-transparent" />
        <div className="hero-grain" aria-hidden />
        <div className="relative flex flex-col gap-4 p-6 md:flex-row md:items-end md:justify-between md:p-10">
          <div className="animate-fade-up">
            <p className="text-xs uppercase tracking-[0.3em] text-oro">Vinea Wine Club</p>
            <h1 className="mt-1 font-serif text-3xl md:text-5xl">
              I <span className="gold-shimmer">Club</span> di Vinea
            </h1>
            <p className="mt-2 max-w-xl text-sm md:text-base text-crema/85">
              Trova la tua tribù di appassionati: territori, denominazioni, produttori e tipologie.
            </p>
          </div>
          <div
            className="relative w-full md:w-80 animate-fade-up"
            style={{ animationDelay: "120ms" }}
          >
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={filtri.testo}
              onChange={(e) => aggiorna("testo", e.target.value)}
              placeholder="Cerca club…"
              aria-label="Cerca club"
              data-testid="club-ricerca"
              className="pl-9 bg-card text-antracite"
            />
          </div>
        </div>
      </section>

      {erroreLettura ? (
        <ErrorState title="Club non disponibili" message={erroreLettura} />
      ) : (
        <>
          <section className="rounded-2xl border border-border bg-card p-4">
            <p className="mb-3 text-xs uppercase tracking-wide text-muted-foreground">Filtri</p>
            <div className="grid gap-3 md:grid-cols-4">
              {opzioni.map(({ campo, valori }) => (
                <label key={campo} className="block">
                  <span className="mb-1 block text-[11px] uppercase tracking-wide text-muted-foreground">
                    {ETICHETTE_FILTRO[campo]}
                  </span>
                  <select
                    value={filtri[campo]}
                    onChange={(e) => aggiorna(campo, e.target.value)}
                    data-testid={`club-filtro-${campo}`}
                    className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
                  >
                    {/* Valore vuoto e non la stringa "Tutti": il filtro spento
                        e l'assenza di un valore, non un valore che vale tutto. */}
                    <option value="">Tutti</option>
                    {valori.map((v) => (
                      <option key={v} value={v}>
                        {v}
                      </option>
                    ))}
                  </select>
                </label>
              ))}
            </div>
          </section>

          {error && <ErrorState title="Operazione non riuscita" message={error} home={false} />}

          {seguiti.length > 0 && (
            <section data-testid="club-seguiti">
              <SectionTitle>Club che segui</SectionTitle>
              <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
                {seguiti.map((c) => (
                  <ClubCard key={c.slug} club={c} onFollow={onFollow} inCorso={inCorso} />
                ))}
              </div>
            </section>
          )}

          <Tabs defaultValue="tutti">
            <TabsList className="bg-secondary">
              <TabsTrigger value="tutti">Tutti ({filtrati.length})</TabsTrigger>
              <TabsTrigger value="discussioni">Discussioni del club</TabsTrigger>
              <TabsTrigger value="popolari">Post popolari</TabsTrigger>
            </TabsList>

            <TabsContent value="tutti" className="mt-4">
              {filtrati.length === 0 ? (
                <div className="rounded-2xl border border-dashed border-border bg-card p-10 text-center text-muted-foreground">
                  {clubs.length === 0
                    ? "Nessun club pubblicato, per ora."
                    : "Nessun club con questi filtri."}
                </div>
              ) : (
                <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3" data-testid="club-elenco">
                  {filtrati.map((c) => (
                    <ClubCard key={c.slug} club={c} onFollow={onFollow} inCorso={inCorso} />
                  ))}
                </div>
              )}
            </TabsContent>

            <TabsContent value="discussioni" className="mt-4">
              {/* Nessuno `clubSlug`: qui non si compone, perche una discussione
                  ha bisogno di un club in cui stare. */}
              <ClubDiscussioni iniziali={discussioni} mostraClub />
            </TabsContent>

            <TabsContent value="popolari" className="mt-4">
              <ClubDiscussioni
                iniziali={discussioni}
                mostraClub
                ordina={ordinaPerPopolarita}
              />
            </TabsContent>
          </Tabs>
        </>
      )}
    </div>
  );
}

// `ClubProssimamente` viveva qui e diceva «disponibile a breve». Non c'e piu
// perche non c'e piu niente da rimandare: i due tab mostrano le discussioni
// vere. Il suo posto lo prende lo stato vuoto di ClubDiscussioni, che e una
// cosa diversa - "non c'e ancora nessuna discussione" invece di "la funzione
// non esiste ancora" - e che invita a scriverne una.

export function ClubCard({
  club,
  onFollow,
  inCorso,
}: {
  club: Club;
  onFollow: ((club: Club) => Promise<void>) | null;
  inCorso: string | null;
}) {
  const attesa = inCorso === club.slug;
  const assi = assiClub(club);

  return (
    <article
      className="group overflow-hidden rounded-2xl border border-border bg-card card-lift perf-card"
      data-testid={`club-card-${club.slug}`}
    >
      <div className="p-4">
        <Link href={`/community/${club.slug}`}>
          <h3 className="font-serif text-lg font-semibold">{club.nome}</h3>
        </Link>
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
        <div className="mt-3 flex items-center justify-between gap-2">
          <p className="flex items-center gap-1 text-xs text-muted-foreground">
            <Users className="h-3.5 w-3.5" /> {formatInteger(club.membri)} membri
          </p>
          <Button
            size="sm"
            variant={club.seguito ? "outline" : "default"}
            disabled={!onFollow || attesa}
            onClick={() => void onFollow?.(club)}
            data-testid={`club-follow-${club.slug}`}
            className={club.seguito ? "" : "bg-bordeaux hover:bg-bordeaux/90"}
          >
            {attesa ? "…" : club.seguito ? "Segui già" : "Segui club"}
          </Button>
        </div>
      </div>
    </article>
  );
}
