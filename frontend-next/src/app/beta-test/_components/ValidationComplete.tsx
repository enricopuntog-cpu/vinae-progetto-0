import type { ReactNode } from "react";
import Link from "next/link";
import { CheckCircle2, ClipboardList, ExternalLink } from "lucide-react";

// `action` è il comando esplicito «Nuovo tester» del QV2, fornito dal client:
// la schermata finale resta priva di handler e tracciamento propri.
export function ValidationComplete({ qv2 = false, action }: { qv2?: boolean; action?: ReactNode }) {
  return (
    <section className="mx-auto max-w-xl rounded-3xl border border-salvia/40 bg-card p-6 text-center md:p-10" aria-labelledby="validation-complete-title">
      <span className="mx-auto grid h-16 w-16 place-items-center rounded-full bg-salvia/15 text-salvia"><CheckCircle2 className="h-8 w-8" aria-hidden /></span>
      <p className="mt-5 text-xs font-semibold uppercase tracking-[0.18em] text-bordeaux">Test completato</p>
      <h1 id="validation-complete-title" className="mt-2 font-serif text-3xl font-semibold md:text-4xl">Grazie per aver provato Vinea</h1>
      <p className="mt-4 text-sm leading-6 text-muted-foreground">Le simulazioni sono concluse. Non è stato creato alcun annuncio, ordine, pagamento o invio.</p>
      {qv2 ? (
        <>
          <p className="mt-4 text-sm leading-6 text-muted-foreground">Il questionario online è stato completato. Grazie per il feedback.</p>
          {action}
        </>
      ) : (
        <div className="mt-6 flex items-start gap-3 rounded-2xl border border-border bg-crema p-4 text-left">
          <ClipboardList className="mt-0.5 h-5 w-5 shrink-0 text-bordeaux" aria-hidden />
          <p className="text-sm">Ora completa il questionario cartaceo consegnato per il test. Non inserire feedback o dati personali in questa pagina.</p>
        </div>
      )}
      <Link href="/" target="_blank" rel="noopener noreferrer" className="mt-6 inline-flex min-h-11 items-center gap-1 text-sm font-medium text-bordeaux hover:underline">
        Continua a esplorare Vinea <ExternalLink className="h-4 w-4" aria-hidden /><span className="sr-only"> (si apre in una nuova scheda)</span>
      </Link>
    </section>
  );
}
