"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ArrowLeft, WineOff } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { GalleriaVino } from "@/components/vinea/GalleriaVino";
import { TrustBadge } from "@/components/vinea/TrustBadge";
import { useVinea } from "@/lib/vinea-store";
import { dataDegustazione } from "@/lib/cantina/apertura";

/**
 * La schermata di degustazione di una bottiglia, nei suoi due momenti.
 *
 * È **una** rotta e non due perché è una cosa sola vista prima e dopo: finché la
 * bottiglia è chiusa raccoglie il commento e registra l'apertura, e appena è
 * aperta diventa la pagina che quel commento lo mostra. Separarle avrebbe
 * significato un indirizzo che dopo la conferma non vuol più dire niente, e un
 * secondo indirizzo da costruire per dire la stessa cosa.
 *
 * Il layout della parte «dopo» è quello della scheda annuncio — stessa galleria
 * (lo stesso componente, non una copia), stessa colonna di destra con
 * denominazione, nome, annata e produttore — con al posto di «Compra ora» e
 * «Proponi» il fatto che la bottiglia è stata bevuta e cosa se n'è detto.
 */
export default function DegustazionePageClient({ bottleId }: { bottleId: string }) {
  const router = useRouter();
  const { bottiglieCantina, viniCantina, openBottle, cantinaLoading } = useVinea();

  const bottiglia = useMemo(
    () => bottiglieCantina.find((b) => b.bottleId === bottleId),
    [bottiglieCantina, bottleId],
  );
  const vino = useMemo(
    () =>
      bottiglia
        ? viniCantina.find((w) => (w.wineSlug ?? w.id) === bottiglia.wineVintageId)
        : undefined,
    [viniCantina, bottiglia],
  );

  const [commento, setCommento] = useState("");
  const [inCorso, setInCorso] = useState(false);

  if (cantinaLoading) {
    return <p className="py-16 text-center text-muted-foreground">Carico la bottiglia…</p>;
  }

  // Vale sia per un id inventato sia per una bottiglia di qualcun altro: la
  // Cantina contiene solo le proprie righe, quindi «non è qui» e «non è tua»
  // arrivano allo stesso posto. È corretto che si somiglino — dire a un
  // estraneo *quale* dei due sia significherebbe confermargli che esiste.
  if (!bottiglia || !vino) {
    return (
      <div className="space-y-4 py-16 text-center">
        <p className="font-serif text-2xl">Questa bottiglia non è nella tua cantina.</p>
        <Button variant="outline" asChild>
          <Link href="/cantina">Torna alla Cantina</Link>
        </Button>
      </div>
    );
  }

  const aperta = bottiglia.quantita === 0;

  const registraApertura = async () => {
    setInCorso(true);
    try {
      // `openBottle` ricarica la cantina da sé quando va a buon fine, quindi
      // questa stessa pagina si ridisegna nella sua forma «dopo». Se fallisce,
      // il messaggio arriva dallo store e qui non si naviga da nessuna parte.
      await openBottle(bottleId, commento.trim() || undefined);
    } finally {
      setInCorso(false);
    }
  };

  return (
    <div className="space-y-8">
      <button
        onClick={() => router.push("/cantina")}
        className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-bordeaux"
      >
        <ArrowLeft className="h-4 w-4" /> Cantina
      </button>

      <div className="grid gap-8 md:grid-cols-2">
        <GalleriaVino immagini={vino.immagini} nome={vino.nome} />

        <div>
          <p className="text-xs uppercase tracking-widest text-salvia">{vino.denominazione}</p>
          <h1 className="mt-1 font-serif text-4xl leading-tight">
            {vino.nome} <span className="text-antracite/70">{vino.annata}</span>
          </h1>
          <p className="mt-1 text-lg text-muted-foreground">{vino.produttore}</p>
          <p className="mt-1 text-sm text-muted-foreground">
            {vino.regione} • Formato {vino.formato}
          </p>

          <div className="mt-3 flex flex-wrap gap-1.5">
            <TrustBadge source="venditore" size="sm" />
          </div>

          {aperta ? (
            <BottigliaDegustata bottiglia={bottiglia} />
          ) : (
            <section className="mt-6 rounded-2xl border border-bordeaux/30 bg-bordeaux/5 p-4">
              <h2 className="font-serif text-xl">Com&apos;era?</h2>
              <p className="mt-1 text-sm text-muted-foreground">
                Scrivilo adesso, finché il bicchiere è davanti: il colore, il naso, quanto è
                cambiata nel tempo, con cosa l&apos;hai bevuta e con chi. Resta nella tua cantina
                e non la vede nessun altro.
              </p>

              <div className="mt-4 space-y-1.5">
                <Label htmlFor="commento-degustazione">Nota di degustazione</Label>
                <Textarea
                  id="commento-degustazione"
                  rows={6}
                  value={commento}
                  onChange={(e) => setCommento(e.target.value)}
                  placeholder="Rubino con l'unghia granata. Naso di amarena sotto spirito e cuoio…"
                  data-testid="commento-degustazione"
                />
                <p className="text-xs text-muted-foreground">
                  Puoi anche lasciarla vuota: la bottiglia risulterà comunque degustata.
                </p>
              </div>

              <div className="mt-4 flex flex-wrap gap-2">
                <Button
                  className="bg-bordeaux hover:bg-bordeaux/90"
                  onClick={registraApertura}
                  disabled={inCorso}
                  data-testid="registra-apertura"
                >
                  <WineOff className="mr-1 h-4 w-4" />
                  {inCorso ? "Registro…" : "Registra l'apertura"}
                </Button>
                <Button variant="ghost" asChild disabled={inCorso}>
                  <Link href="/cantina">Non adesso</Link>
                </Button>
              </div>

              <p className="mt-3 text-xs text-muted-foreground">
                Finché non premi, la bottiglia resta chiusa e nella tua cantina.
              </p>
            </section>
          )}
        </div>
      </div>
    </div>
  );
}

/**
 * Il blocco che prende il posto di «Compra ora» e «Proponi».
 *
 * La data è la parte delicata, e ha tre fonti possibili di cui una sola è
 * vera. `degustazione_at` è il giorno in cui la bottiglia è stata aperta
 * davvero, scritto da `bottiglia_apri` e da nessun altro. `apertura_pianificata`
 * è una data *programmata*, scrivibile dal client, che dice quando qualcuno
 * *voleva* aprirla. `updated_at` si muove a ogni modifica e non testimonia
 * niente. Quindi: la prima se c'è, la seconda dichiarando che è quella, e
 * altrimenti nessuna — mai un giorno inventato presentato come il giorno della
 * degustazione. `dataDegustazione` incapsula proprio questa scelta.
 *
 * Le bottiglie aperte prima della migrazione `20260819120000` hanno la prima
 * colonna vuota, perché non esisteva: per loro si continua a ripiegare sulla
 * data programmata, ed è corretto che il testo lo dica.
 *
 * Il commento arriva da `degustazioneNota` e **non** da `personalNotes`. Prima
 * di quella migrazione `bottiglia_apri` scriveva la nota di degustazione sopra
 * `note_personali`, quindi leggerla da lì significava leggere la conseguenza di
 * un difetto: dopo la correzione, `personalNotes` torna a essere la nota di
 * cantina («regalo di Marco») e mostrarla qui la spaccerebbe per un commento
 * che nessuno ha scritto.
 */
function BottigliaDegustata({
  bottiglia,
}: {
  bottiglia: {
    plannedOpenDate?: string;
    degustazioneNota?: string;
    degustazioneAt?: string;
  };
}) {
  const data = dataDegustazione({
    degustazioneAt: bottiglia.degustazioneAt ?? null,
    aperturaPianificata: bottiglia.plannedOpenDate ?? null,
  });

  return (
    <section className="mt-6 rounded-2xl border border-oro/40 bg-oro/10 p-4">
      <p className="text-xs uppercase tracking-wide text-oro">Dalla tua cantina</p>
      <h2 className="mt-1 font-serif text-2xl" data-testid="titolo-degustata">
        {data.testo ? `Bottiglia degustata il ${data.testo}` : "Bottiglia degustata"}
      </h2>
      {data.testo && !data.certa ? (
        <p className="mt-1 text-xs text-muted-foreground">
          È la data che avevi programmato per l&apos;apertura: questa bottiglia è stata aperta
          prima che il giorno esatto venisse registrato.
        </p>
      ) : null}
      {!data.testo ? (
        <p className="mt-1 text-xs text-muted-foreground">
          Di questa bottiglia non è rimasto il giorno dell&apos;apertura.
        </p>
      ) : null}

      {bottiglia.degustazioneNota ? (
        <blockquote
          className="mt-4 whitespace-pre-line border-l-2 border-oro/50 pl-3 text-sm"
          data-testid="commento-degustazione-salvato"
        >
          {bottiglia.degustazioneNota}
        </blockquote>
      ) : (
        <p className="mt-4 text-sm text-muted-foreground">
          Non hai lasciato una nota di degustazione per questa bottiglia.
        </p>
      )}
    </section>
  );
}
