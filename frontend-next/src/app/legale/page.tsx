import type { Metadata } from "next";
import { AzioneIndietro } from "@/components/vinea/AzioneIndietro";
import {
  cookie, identitaLegale, privacy, statoLegale, termini, versioneLegale,
  type CapitoloLegale,
} from "@/lib/legal/contenuti";

export const metadata: Metadata = {
  title: "Privacy, termini e cookie — Vinea Wine Club",
  description: "Centro legale della beta Vinea: dati personali, termini di utilizzo, cookie e documenti di qualifica.",
};

const linkClass = "text-bordeaux underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-4";

function Capitoli({ contenuti }: { contenuti: readonly CapitoloLegale[] }) {
  return (
    <div className="mt-6 space-y-7 text-sm leading-7 text-antracite/90">
      {contenuti.map((capitolo) => (
        <div key={capitolo.titolo} className="space-y-3 break-words">
          <h3 className="text-base font-semibold text-bordeaux">{capitolo.titolo}</h3>
          {capitolo.paragrafi.map((testo) => <p key={testo}>{testo}</p>)}
        </div>
      ))}
    </div>
  );
}

export default function Page() {
  return (
    <div className="mx-auto max-w-3xl space-y-8 pb-8" data-testid="centro-legale">
      <header>
        <AzioneIndietro className="-ml-2 mb-3" />
        <p className="text-xs font-semibold uppercase tracking-widest text-bordeaux/70">Vinea Wine Club</p>
        <h1 className="mt-2 font-serif text-3xl font-semibold text-bordeaux md:text-4xl">Centro legale</h1>
        <p className="mt-3 text-sm leading-6 text-muted-foreground">Come funziona la beta, quali dati utilizziamo e come puoi controllarli.</p>
        <p className="mt-2 text-xs text-muted-foreground">Versione del {versioneLegale}</p>
        <nav aria-label="Sezioni legali" className="mt-5 flex flex-wrap gap-x-5 gap-y-3 text-sm">
          <a href="#privacy" className={linkClass}>Privacy</a>
          <a href="#termini" className={linkClass}>Termini di utilizzo</a>
          <a href="#cookie" className={linkClass}>Cookie</a>
          <a href="#eta" className={linkClass}>Requisito di età</a>
          <a href="#contatti" className={linkClass}>Contatti</a>
          <a href="/legale/documenti-qualifica" className={linkClass}>Documenti di qualifica</a>
        </nav>
      </header>

      {statoLegale === "bozza" && (
        <aside aria-label="Stato dei documenti" className="rounded-2xl border border-oro/50 bg-oro/10 p-5 text-sm leading-6">
          <h2 className="font-semibold text-bordeaux">Bozza per revisione — dati da completare</h2>
          <p className="mt-2">
            I testi descrivono la beta. Prima della pubblicazione definitiva devono essere
            completati l&apos;identità e i recapiti del titolare, il calendario di conservazione
            e la verifica dei contratti e dei trasferimenti dei fornitori.
            Questa versione non attesta il completamento di tali adempimenti.
          </p>
        </aside>
      )}

      <section id="contatti" className="scroll-mt-24 rounded-3xl border border-border bg-card p-5 md:p-8">
        <h2 className="font-serif text-2xl text-bordeaux">Titolare e contatti</h2>
        <dl className="mt-4 space-y-3 text-sm leading-6">
          <div><dt className="font-semibold">Titolare del trattamento e gestore della beta</dt><dd>{identitaLegale.nome || "Nome completo o ragione sociale da inserire"}</dd></div>
          <div><dt className="font-semibold">Indirizzo di contatto</dt><dd>{identitaLegale.indirizzo || "Indirizzo da inserire"}</dd></div>
          <div><dt className="font-semibold">Privacy, assistenza e reclami</dt><dd>
            {identitaLegale.email ? <a href={`mailto:${identitaLegale.email}`} className={linkClass}>{identitaLegale.email}</a> : "Email da inserire"}
          </dd></div>
        </dl>
      </section>

      <section id="privacy" className="scroll-mt-24 rounded-3xl border border-border bg-card p-5 md:p-8">
        <h2 className="font-serif text-2xl text-bordeaux">Informativa privacy</h2>
        <p className="mt-2 text-sm text-muted-foreground">Informazioni ai sensi degli articoli 13 e 14 del Regolamento (UE) 2016/679.</p>
        <Capitoli contenuti={privacy} />
        <p className="mt-5 text-sm"><a href="https://www.garanteprivacy.it" className={linkClass}>Garante per la protezione dei dati personali</a></p>
      </section>

      <section id="termini" className="scroll-mt-24 rounded-3xl border border-border bg-card p-5 md:p-8">
        <h2 className="font-serif text-2xl text-bordeaux">Termini di utilizzo</h2>
        <Capitoli contenuti={termini} />
      </section>

      <section id="cookie" className="scroll-mt-24 rounded-3xl border border-border bg-card p-5 md:p-8">
        <h2 className="font-serif text-2xl text-bordeaux">Informativa cookie</h2>
        <Capitoli contenuti={cookie} />
        <p className="mt-5 text-sm"><a href="https://www.garanteprivacy.it/faq/cookie" className={linkClass}>Approfondimento del Garante sui cookie</a></p>
      </section>

      <section id="eta" className="scroll-mt-24 rounded-3xl border border-border bg-card p-5 md:p-8">
        <h2 className="font-serif text-2xl text-bordeaux">Requisito di età</h2>
        <p className="mt-3 text-sm leading-7">Vinea è riservato ai maggiorenni.</p>
        <p className="mt-2 text-sm leading-7">
          La data di nascita è dichiarata dall&apos;utente. In questa fase non sono richiesti
          documenti per il controllo dell&apos;età. I documenti professionali sono richiesti
          soltanto a chi presenta una qualifica: <a href="/legale/documenti-qualifica" className={linkClass}>leggi l&apos;informativa dedicata</a>.
        </p>
      </section>
    </div>
  );
}
