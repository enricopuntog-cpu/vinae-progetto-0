"use client";

// Fase 9a - "Le mie segnalazioni", sola lettura.
//
// Controparte di frontend/src/routes/segnalazioni.tsx. Una differenza
// sostanziale rispetto al mock: li il filtro era `reporter === MY_REPORTER`
// applicato in memoria (riga 44), qui non esiste alcun filtro applicativo. La
// vista my_reports confronta reporter_id con auth.uid(), quindi non c'e un
// elenco piu grande da restringere: il client riceve gia solo le proprie
// pratiche.
//
// Le note interne non compaiono e non sono filtrate qui: my_report_events non
// le restituisce affatto.

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import {
  EmptyState,
  ErrorState,
  LoadingBlock,
  OfflineState,
  useOnline,
} from "@/components/vinea/States";
import { usePhase9Moderation } from "@/lib/phase9/use-phase9-moderation";
import { reportStatusLabel, reportStatusTone, reportTargetLabel } from "@/data/moderation";
import type { Report } from "@/data/moderation";

const data = (iso: string) =>
  new Date(iso).toLocaleString("it-IT", { dateStyle: "medium", timeStyle: "short" });

const Pratica = ({ report }: { report: Report }) => (
  <Card className="space-y-3 p-4">
    <div className="flex flex-wrap items-start justify-between gap-2">
      <div>
        <p className="font-medium">{report.targetLabel}</p>
        <p className="text-sm text-muted-foreground">
          {reportTargetLabel[report.targetType]} · {report.reason}
        </p>
      </div>
      <Badge className={reportStatusTone[report.stato]}>{reportStatusLabel[report.stato]}</Badge>
    </div>

    {report.descrizione ? <p className="text-sm">{report.descrizione}</p> : null}

    <p className="text-xs text-muted-foreground">Inviata il {data(report.createdAt)}</p>

    {report.storia.length > 0 ? (
      <ol className="space-y-1 border-l pl-3 text-xs text-muted-foreground">
        {report.storia.map((voce) => (
          <li key={`${voce.ts}-${voce.testo}`}>
            <span className="font-medium">{voce.autore}</span> · {voce.testo}
            <span className="ml-1 opacity-70">({data(voce.ts)})</span>
          </li>
        ))}
      </ol>
    ) : null}
  </Card>
);

export const MyReportsPageClient = () => {
  const online = useOnline();
  const { mieSegnalazioni, loading, error, reload } = usePhase9Moderation();

  if (!online && mieSegnalazioni.length === 0) return <OfflineState onRetry={() => void reload()} />;
  if (loading && mieSegnalazioni.length === 0) {
    return <LoadingBlock label="Caricamento segnalazioni" />;
  }
  if (error && mieSegnalazioni.length === 0) {
    return <ErrorState message={error} onRetry={() => void reload()} />;
  }

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="font-serif text-3xl md:text-4xl">Le mie segnalazioni</h1>
          <p className="text-muted-foreground">
            {mieSegnalazioni.length === 1
              ? "1 pratica"
              : `${mieSegnalazioni.length} pratiche`}
          </p>
        </div>
        <Button variant="outline" onClick={() => void reload()} disabled={!online}>
          Aggiorna
        </Button>
      </header>

      {mieSegnalazioni.length === 0 ? (
        <EmptyState
          title="Nessuna segnalazione"
          message="Quando segnali un annuncio, un profilo o un messaggio, la pratica compare qui."
        />
      ) : (
        <div className="space-y-3">
          {mieSegnalazioni.map((report) => (
            <Pratica key={report.id} report={report} />
          ))}
        </div>
      )}
    </div>
  );
};
