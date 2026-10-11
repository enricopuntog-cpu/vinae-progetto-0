import Link from "next/link";

/**
 * Ciò che una superficie Partner mostra quando `classeDelChiamante()` risponde
 * `errore`: non si sa se chi guarda è un privato o il titolare di un Partner,
 * quindi non gli si offre né l'interfaccia del collezionista né quella
 * commerciale. Si chiede di riprovare, senza dettagli del guasto.
 */
export function ClasseNonVerificata({ titolo, riprova }: { titolo: string; riprova: string }) {
  return (
    <div className="mx-auto max-w-xl space-y-4 py-8" data-testid="classe-non-verificata">
      <h1 className="font-serif text-3xl">{titolo}</h1>
      <p role="alert" className="text-muted-foreground">
        Non è stato possibile verificare il tuo profilo in questo momento. Riprova fra qualche
        istante.
      </p>
      <Link href={riprova} className="inline-block text-sm font-medium text-bordeaux underline">
        Riprova
      </Link>
    </div>
  );
}
