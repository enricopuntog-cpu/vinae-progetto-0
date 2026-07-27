import { createFileRoute, Link } from "@tanstack/react-router";
import { Flag, ArrowLeft, Clock, ShieldCheck } from "lucide-react";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { Button } from "@/components/ui/button";
import { useVinea } from "@/lib/vinea-store";
import {
  MY_REPORTER,
  reportStatusLabel,
  reportStatusTone,
  reportTargetLabel,
  type ReportStatus,
} from "@/data/moderation";

export const Route = createFileRoute("/segnalazioni")({
  head: () => ({
    meta: [
      { title: "Le mie segnalazioni — Vinea" },
      {
        name: "description",
        content: "Cronologia delle segnalazioni inviate e stato di lavorazione.",
      },
      { property: "og:title", content: "Le mie segnalazioni — Vinea" },
      {
        property: "og:description",
        content: "Segui lo stato delle tue segnalazioni al team Vinea (demo).",
      },
      { name: "robots", content: "noindex" },
    ],
  }),
  component: MieSegnalazioni,
});

const filtri: { key: "tutte" | ReportStatus; label: string }[] = [
  { key: "tutte", label: "Tutte" },
  { key: "inviata", label: "Inviate" },
  { key: "in_revisione", label: "In revisione" },
  { key: "info_richieste", label: "Info richieste" },
  { key: "risolta", label: "Risolte" },
  { key: "respinta", label: "Respinte" },
];

function MieSegnalazioni() {
  const { reports } = useVinea();
  const mie = reports.filter((r) => r.reporter === MY_REPORTER);

  return (
    <div className="space-y-6">
      <Link
        to="/profilo"
        className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-bordeaux"
      >
        <ArrowLeft className="h-4 w-4" /> Torna al profilo
      </Link>

      <header className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <h1 className="font-serif text-3xl md:text-4xl">Le mie segnalazioni</h1>
          <p className="text-sm text-muted-foreground">
            Cronologia e stato delle tue segnalazioni al team Vinea.
          </p>
        </div>
        <span className="inline-flex items-center gap-1 rounded-full bg-oro/15 px-2 py-1 text-[10px] font-medium text-oro">
          Demo — nessun invio reale
        </span>
      </header>

      <Tabs defaultValue="tutte">
        <div className="-mx-4 tab-scroll overflow-x-auto px-4 sm:mx-0 sm:px-0">
          <TabsList className="inline-flex w-max min-w-full bg-secondary">
            {filtri.map((f) => (
              <TabsTrigger key={f.key} value={f.key}>
                {f.label}
              </TabsTrigger>
            ))}
          </TabsList>
        </div>

        {filtri.map((f) => {
          const list = f.key === "tutte" ? mie : mie.filter((r) => r.stato === f.key);
          return (
            <TabsContent key={f.key} value={f.key} className="mt-4 space-y-3">
              {list.length === 0 ? (
                <EmptyState />
              ) : (
                list.map((r) => (
                  <article key={r.id} className="rounded-2xl border border-border bg-card p-4">
                    <div className="flex flex-wrap items-start justify-between gap-2">
                      <div className="min-w-0 flex-1">
                        <p className="text-xs uppercase tracking-wide text-muted-foreground">
                          {reportTargetLabel[r.targetType]} · {r.id}
                        </p>
                        <p className="mt-0.5 truncate font-serif text-lg font-semibold">
                          {r.targetLabel}
                        </p>
                        <p className="mt-1 text-sm">
                          Motivo: <b>{r.reason}</b>
                        </p>
                        {r.descrizione && (
                          <p className="mt-1 text-sm text-muted-foreground">{r.descrizione}</p>
                        )}
                      </div>
                      <span
                        className={`shrink-0 rounded-full px-2 py-0.5 text-[11px] font-medium ${reportStatusTone[r.stato]}`}
                      >
                        {reportStatusLabel[r.stato]}
                      </span>
                    </div>

                    <ol className="mt-3 space-y-1.5 border-l border-border pl-4 text-xs">
                      {r.storia.map((h, i) => (
                        <li key={i} className="relative">
                          <span className="absolute -left-[19px] top-1 h-2 w-2 rounded-full bg-bordeaux/70" />
                          <span className="text-muted-foreground">
                            {new Date(h.ts).toLocaleString("it-IT", {
                              day: "2-digit",
                              month: "short",
                              hour: "2-digit",
                              minute: "2-digit",
                            })}
                          </span>
                          <span className="mx-1">·</span>
                          <span>{h.testo}</span>
                          <span className="ml-1 text-muted-foreground">— {h.autore}</span>
                        </li>
                      ))}
                    </ol>

                    <div className="mt-3 flex flex-wrap items-center gap-2 text-[11px] text-muted-foreground">
                      <span className="inline-flex items-center gap-1">
                        <Clock className="h-3 w-3" /> Aggiornata{" "}
                        {new Date(r.updatedAt).toLocaleDateString("it-IT")}
                      </span>
                      {r.assignee && (
                        <span className="inline-flex items-center gap-1">
                          <ShieldCheck className="h-3 w-3" /> {r.assignee}
                        </span>
                      )}
                      {r.clubSlug && (
                        <span className="rounded-full bg-secondary px-2 py-0.5">
                          Club: {r.clubSlug}
                        </span>
                      )}
                    </div>
                  </article>
                ))
              )}
            </TabsContent>
          );
        })}
      </Tabs>
    </div>
  );
}

function EmptyState() {
  return (
    <div className="rounded-2xl border border-dashed border-border bg-card p-10 text-center">
      <div className="mx-auto grid h-12 w-12 place-items-center rounded-full bg-bordeaux/10 text-bordeaux">
        <Flag className="h-5 w-5" />
      </div>
      <p className="mt-3 font-serif text-lg">Nessuna segnalazione</p>
      <p className="mt-1 text-sm text-muted-foreground">
        Le segnalazioni che invii dagli annunci, dai profili o dai messaggi appariranno qui.
      </p>
      <Button asChild variant="outline" className="mt-4">
        <Link to="/esplora">Torna alla ricerca</Link>
      </Button>
    </div>
  );
}
