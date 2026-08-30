import type { Metadata } from "next";
import { AzioneIndietro } from "@/components/vinea/AzioneIndietro";

export const metadata: Metadata = {
  title: "Centro legale — Vinea Wine Club",
  description: "Informazioni su termini, privacy e requisito di età di Vinea.",
};

export default function Page() {
  return (
    <div className="mx-auto max-w-3xl space-y-8">
      <header>
        {/* Il Centro legale è una deviazione: ci si arriva dal footer, dal gate
            dell'età e dalla registrazione, e da tutti e tre si vuole tornare
            dov'era rimasto il discorso. Il ritorno sta in un componente client
            a sé perché questa pagina resta un Server Component: qui non c'è
            sessione, non c'è store e non deve arrivarci ora. */}
        <AzioneIndietro className="-ml-2 mb-3" />
        <h1 className="font-serif text-3xl font-semibold text-bordeaux md:text-4xl">
          Centro legale
        </h1>
        <nav aria-label="Sezioni legali" className="mt-4 flex flex-wrap gap-3 text-sm">
          <a href="#termini" className="text-bordeaux underline-offset-2 hover:underline">
            Termini di utilizzo
          </a>
          <a href="#privacy" className="text-bordeaux underline-offset-2 hover:underline">
            Privacy
          </a>
          <a href="#eta" className="text-bordeaux underline-offset-2 hover:underline">
            Requisito di età
          </a>
        </nav>
      </header>

      <section id="termini" className="scroll-mt-24 rounded-3xl border border-border bg-card p-5 md:p-8">
        <h2 className="font-serif text-2xl">Termini di utilizzo</h2>
        <p className="mt-3 text-sm text-muted-foreground">
          Il testo definitivo sarà pubblicato prima del lancio pubblico.
        </p>
      </section>

      <section id="privacy" className="scroll-mt-24 rounded-3xl border border-border bg-card p-5 md:p-8">
        <h2 className="font-serif text-2xl">Privacy</h2>
        <p className="mt-3 text-sm text-muted-foreground">
          Il testo definitivo sarà pubblicato prima del lancio pubblico.
        </p>
      </section>

      <section id="eta" className="scroll-mt-24 rounded-3xl border border-border bg-card p-5 md:p-8">
        <h2 className="font-serif text-2xl">Requisito di età</h2>
        <p className="mt-3 text-sm text-muted-foreground">Vinea è riservato ai maggiorenni.</p>
        <p className="mt-2 text-sm text-muted-foreground">
          La data di nascita è dichiarata dall&apos;utente. In questa fase non sono richiesti
          documenti.
        </p>
      </section>
    </div>
  );
}
