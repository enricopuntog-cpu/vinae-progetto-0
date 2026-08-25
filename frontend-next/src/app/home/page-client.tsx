"use client";

import Link from "next/link";
import { Bell, Search, Wine as WineIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { WineCard } from "@/components/vinea/WineCard";
import { Kpi, SectionTitle } from "@/components/vinea/Layout";
import { LoadingBlock } from "@/components/vinea/States";
import type { Wine } from "@/data/wines";
import { formatEUR } from "@/lib/format";
import { usePhase8 } from "@/lib/phase8/phase8-context";
import { useVinea } from "@/lib/vinea-store";

const AccessRequired = () => (
  <section className="rounded-3xl border bg-card p-8 text-center">
    <h1 className="font-serif text-3xl">La tua home è privata</h1>
    <p className="mt-2 text-sm text-muted-foreground">Accedi per vedere cantina, notifiche e attività collegate al tuo profilo.</p>
    <Button asChild className="mt-5 bg-bordeaux hover:bg-bordeaux/90"><Link href="/accedi">Accedi</Link></Button>
  </section>
);

const ProfileMissing = () => (
  <section className="rounded-3xl border border-oro/40 bg-oro/10 p-8 text-center">
    <h1 className="font-serif text-3xl">Profilo non disponibile</h1>
    <p className="mt-2 text-sm text-muted-foreground">La sessione è attiva, ma il nome del profilo non è leggibile. Completa il profilo o riprova più tardi.</p>
    <Button asChild className="mt-5"><Link href="/completa-profilo">Completa il profilo</Link></Button>
  </section>
);

const HomeContent = ({ annunci, nome }: { annunci: Wine[]; nome: string }) => {
  const { viniCantina, cantinaLoading } = useVinea();
  const { notifications, unreadCount } = usePhase8();
  const valore = viniCantina.reduce((totale, vino) => totale + vino.prezzo * vino.disponibili, 0);
  return (
    <div className="space-y-10">
      <section className="rounded-3xl bg-gradient-to-br from-bordeaux to-antracite p-6 text-crema">
        <p className="text-xs uppercase tracking-[0.3em] text-oro">La tua Vinea</p>
        {/* D6. Il saluto usa il nome del profilo reale, quello di
            `public.profiles.username`: `HomeUtentePageClient` ha gia mostrato
            "Profilo non disponibile" se non era leggibile, quindi qui `nome` non
            e mai un segnaposto. */}
        <h1 className="mt-2 font-serif text-4xl" data-testid="home-saluto">
          Bentornato, {nome}
        </h1>
        <p className="mt-2 text-sm text-crema/80">Dati personali letti dalla sessione e dai servizi collegati.</p>
        <Button asChild variant="outline" className="mt-5 border-crema/40 bg-transparent text-crema hover:bg-crema/10"><Link href="/esplora"><Search className="h-4 w-4" /> Cerca nel catalogo</Link></Button>
      </section>
      <section className="grid gap-3 sm:grid-cols-3">
        <Kpi label="Bottiglie" value={String(viniCantina.reduce((n, vino) => n + vino.disponibili, 0))} hint="in cantina" />
        <Kpi label="Valore indicativo" value={formatEUR(valore)} />
        <Kpi label="Notifiche" value={String(unreadCount)} hint="non lette" />
      </section>
      <section>
        <SectionTitle action={<Link href="/esplora" className="text-sm text-bordeaux hover:underline">Vedi tutto →</Link>}>Annunci recenti</SectionTitle>
        <div className="grid grid-cols-2 gap-4 md:grid-cols-4">{annunci.slice(0, 4).map((wine) => <WineCard key={wine.id} wine={wine} />)}</div>
      </section>
      <section>
        <SectionTitle action={<Link href="/cantina" className="text-sm text-bordeaux hover:underline">Apri cantina →</Link>}><span className="inline-flex items-center gap-2"><WineIcon className="h-5 w-5" /> La tua cantina</span></SectionTitle>
        {cantinaLoading ? <LoadingBlock label="Caricamento Cantina" /> : viniCantina.length ? <div className="grid grid-cols-2 gap-4 md:grid-cols-4">{viniCantina.slice(0, 4).map((wine) => <WineCard key={wine.id} wine={wine} />)}</div> : <p className="rounded-2xl border border-dashed p-6 text-center text-sm text-muted-foreground">La tua Cantina è vuota.</p>}
      </section>
      <section>
        <SectionTitle action={<Link href="/notifiche" className="text-sm text-bordeaux hover:underline">Tutte →</Link>}><span className="inline-flex items-center gap-2"><Bell className="h-5 w-5" /> Notifiche recenti</span></SectionTitle>
        {notifications.length ? <ul className="space-y-2">{notifications.slice(0, 5).map((n) => <li key={n.id} className="rounded-2xl border bg-card p-3 text-sm">{n.body}</li>)}</ul> : <p className="text-sm text-muted-foreground">Nessuna notifica.</p>}
      </section>
    </div>
  );
};

const HomeUtentePageClient = ({ annunci }: { annunci: Wine[] }) => {
  const { authUser, authLoading, authProfileName, authProfileLoading } = useVinea();
  if (authLoading) return <LoadingBlock label="Caricamento sessione" />;
  if (!authUser) return <AccessRequired />;
  if (authProfileLoading) return <LoadingBlock label="Caricamento profilo" />;
  if (!authProfileName) return <ProfileMissing />;
  return <HomeContent annunci={annunci} nome={authProfileName} />;
};

export default HomeUtentePageClient;
