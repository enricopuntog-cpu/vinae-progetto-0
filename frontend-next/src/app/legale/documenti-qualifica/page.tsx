import type { Metadata } from "next";
import Link from "next/link";
import { AzioneIndietro } from "@/components/vinea/AzioneIndietro";

/**
 * Perché chiediamo un documento di qualifica.
 *
 * Una pagina, non un tooltip. Chi sta per caricare la foto di un diploma sta
 * per consegnare un documento personale a un sito che non conosce ancora: la
 * risposta a «dove finisce» deve essere leggibile per intero, linkabile e
 * raggiungibile anche prima di iniziare, non nascosta dietro un punto
 * interrogativo di dodici pixel.
 *
 * QUI SI DESCRIVE SOLO CIÒ CHE IL CODICE FA DAVVERO. Non c'è un periodo di
 * conservazione dichiarato, perché nel prodotto non è implementato; non ci sono
 * certificazioni, perché non ne esistono; non c'è nessun fornitore di verifica
 * automatica nominato, perché nessuno è attivo. Promettere una di queste tre
 * cose qui sarebbe scriverla per la prima volta in una pagina legale.
 *
 * Server Component: nessuna sessione, nessuno store, nessun dato dell'utente.
 */

export const metadata: Metadata = {
  title: "Perché chiediamo questo documento — Vinea Wine Club",
  description:
    "Come Vinea usa i documenti caricati per verificare una qualifica professionale: non sono pubblici e non sono visibili ad altri utenti.",
};

const Sezione = ({
  id,
  titolo,
  children,
}: {
  id: string;
  titolo: string;
  children: React.ReactNode;
}) => (
  <section
    id={id}
    className="scroll-mt-24 rounded-3xl border border-border bg-card p-5 md:p-8"
  >
    <h2 className="font-serif text-2xl">{titolo}</h2>
    <div className="mt-3 space-y-3 text-sm text-muted-foreground">{children}</div>
  </section>
);

export default function Page() {
  return (
    <div className="mx-auto max-w-3xl space-y-8" data-testid="privacy-documenti-qualifica">
      <header>
        <AzioneIndietro className="-ml-2 mb-3" />
        <h1 className="font-serif text-3xl font-semibold text-bordeaux md:text-4xl">
          Perché chiediamo questo documento
        </h1>
        <p className="mt-3 text-sm text-muted-foreground">
          Quando dichiari una qualifica professionale — sommelier, enologo, agronomo e simili —
          ti chiediamo di allegare una foto o un PDF del titolo. Questa pagina spiega a cosa
          serve, chi lo vede e cosa compare sul tuo profilo pubblico.
        </p>
        <p className="mt-3 text-sm">
          <Link href="/legale" className="text-bordeaux underline-offset-2 hover:underline">
            Torna al Centro legale
          </Link>
        </p>
      </header>

      <Sezione id="a-cosa-serve" titolo="A cosa serve">
        <p>
          La foto o il PDF servono a verificare la qualifica che hai dichiarato: senza un
          documento, il titolo resterebbe un&apos;affermazione scritta da chiunque. Vinea non
          rilascia qualifiche e non le certifica: legge il documento rilasciato da un ente terzo
          e conferma, o non conferma, che corrisponda a quanto hai scritto.
        </p>
        <p>
          Accettiamo PDF, JPEG e PNG. Puoi allegare più di un documento a una stessa qualifica, e
          finché la richiesta è in bozza puoi rimuoverli o eliminare del tutto la bozza.
        </p>
      </Sezione>

      <Sezione id="non-pubblicato" titolo="Non viene pubblicato">
        <p>
          <strong className="text-foreground">
            I documenti che carichi non vengono pubblicati sul tuo profilo.
          </strong>{" "}
          Non sono visibili agli altri utenti, non compaiono negli annunci, non sono scaricabili
          da nessuna pagina pubblica e non vengono mostrati a chi visita il tuo profilo.
        </p>
        <p>
          Sono conservati in un&apos;area privata, separata dalle pagine pubbliche del sito.
          Nemmeno il percorso interno del file diventa pubblico: le pagine pubbliche non hanno
          proprio un campo che possa contenerlo.
        </p>
        <p>
          Anche il numero o riferimento della credenziale, se lo inserisci, resta privato: lo
          rivedi tu nella tua area account e non compare da nessuna parte sul profilo pubblico.
        </p>
      </Sezione>

      <Sezione id="cosa-appare" titolo="Cosa appare sul profilo pubblico">
        <p>
          Sul profilo pubblico possono comparire soltanto i dati di una qualifica{" "}
          <strong className="text-foreground">approvata e non scaduta</strong>: il titolo,
          l&apos;ente che l&apos;ha rilasciata e il paese. Nient&apos;altro.
        </p>
        <p>
          Una qualifica in bozza, in verifica, non approvata o ritirata non compare. Una
          qualifica approvata che scade smette di comparire dal giorno successivo alla scadenza.
        </p>
        <p>
          Non compaiono mai: i documenti allegati, il numero o riferimento della credenziale, e
          nessun dettaglio di come la verifica è stata svolta.
        </p>
      </Sezione>

      <Sezione id="controllo" titolo="Cosa puoi fare tu">
        <p>
          Finché la richiesta è in <strong className="text-foreground">bozza</strong> puoi
          modificarne i dati, rimuovere un documento allegato oppure eliminare la bozza: in
          quest&apos;ultimo caso i documenti vengono rimossi dall&apos;archivio privato e la
          bozza sparisce.
        </p>
        <p>
          Dopo l&apos;invio i dati e i documenti restano come sono, perché sono quelli su cui la
          verifica si basa. Puoi però ritirare la richiesta: smette di comparire nel tuo elenco e
          non viene esaminata.
        </p>
      </Sezione>
    </div>
  );
}
