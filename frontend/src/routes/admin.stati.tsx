import { createFileRoute, Link } from "@tanstack/react-router";
import { useState } from "react";
import { ArrowLeft, FlaskConical } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { useVinea } from "@/lib/vinea-store";
import {
  EmptyState,
  ErrorState,
  OfflineState,
  NoResultsState,
  PermissionDeniedState,
  NotFoundState,
  SuccessConfirmation,
  SafeImage,
  AiStatusPanel,
  CardGridSkeleton,
  LineSkeleton,
  LoadingBlock,
  listingActionCopy,
  proposalEdgeCases,
  type AiState,
} from "@/components/vinea/States";
import { listingStatusLabel, listingStatusTone, type ListingStatus } from "@/data/moderation";

export const Route = createFileRoute("/admin/stati")({
  component: StatiDemo,
});

function StatiDemo() {
  const { ruolo } = useVinea();
  const [ai, setAi] = useState<AiState>("attesa");

  if (ruolo !== "admin") {
    return (
      <div className="mx-auto max-w-3xl px-4 py-10">
        <PermissionDeniedState
          title="Solo per amministratori"
          message="Attiva la modalità Admin dal menu profilo per accedere agli strumenti dimostrativi."
          action={
            <Button asChild variant="outline">
              <Link to="/profilo">Vai al profilo</Link>
            </Button>
          }
        />
      </div>
    );
  }

  const listingStates: ListingStatus[] = [
    "bozza",
    "in_revisione",
    "modifiche_richieste",
    "attivo",
    "riservato",
    "venduto",
    "sospeso",
    "rifiutato",
    "scaduto",
  ];

  return (
    <div className="mx-auto max-w-6xl px-4 py-8">
      <div className="mb-6 flex items-center justify-between">
        <div>
          <Link
            to="/admin"
            className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-bordeaux"
          >
            <ArrowLeft className="h-4 w-4" /> Torna al pannello
          </Link>
          <h1 className="mt-2 font-serif text-3xl">Stati demo</h1>
          <p className="text-sm text-muted-foreground">
            Anteprima degli stati riutilizzabili. Non modifica i dati mock.
          </p>
        </div>
        <span className="inline-flex items-center gap-1 rounded-full bg-oro/15 px-3 py-1 text-xs text-antracite">
          <FlaskConical className="h-3.5 w-3.5" /> Strumento dimostrativo
        </span>
      </div>

      <Tabs defaultValue="generici">
        <TabsList className="flex flex-wrap">
          <TabsTrigger value="generici">Generici</TabsTrigger>
          <TabsTrigger value="caricamento">Caricamento</TabsTrigger>
          <TabsTrigger value="ia">Stati IA</TabsTrigger>
          <TabsTrigger value="annunci">Annunci</TabsTrigger>
          <TabsTrigger value="ordini">Ordini &amp; proposte</TabsTrigger>
          <TabsTrigger value="immagini">Immagini</TabsTrigger>
        </TabsList>

        <TabsContent value="generici" className="mt-6 grid gap-4 md:grid-cols-2">
          <EmptyState
            title="Nessuna bottiglia in cantina"
            message="Aggiungi la tua prima bottiglia per iniziare."
          />
          <NoResultsState query="Barolo 1990" onReset={() => {}} />
          <ErrorState onRetry={() => {}} />
          <OfflineState onRetry={() => {}} />
          <PermissionDeniedState />
          <SuccessConfirmation title="Operazione completata" message="Tutto in ordine." />
          <NotFoundState />
        </TabsContent>

        <TabsContent value="caricamento" className="mt-6 space-y-6">
          <LoadingBlock label="Caricamento risultati" />
          <div>
            <p className="mb-2 text-sm font-semibold">Righe skeleton</p>
            <LineSkeleton lines={4} />
          </div>
          <div>
            <p className="mb-2 text-sm font-semibold">Griglia bottiglie</p>
            <CardGridSkeleton count={3} />
          </div>
        </TabsContent>

        <TabsContent value="ia" className="mt-6 space-y-4">
          <div className="flex flex-wrap gap-2">
            {(["attesa", "elaborazione", "conferma", "completata", "fallita"] as AiState[]).map(
              (s) => (
                <Button
                  key={s}
                  size="sm"
                  variant={ai === s ? "default" : "outline"}
                  onClick={() => setAi(s)}
                >
                  {s}
                </Button>
              ),
            )}
          </div>
          <AiStatusPanel
            state={ai}
            titolo="Riconoscimento etichetta"
            onConferma={() => setAi("completata")}
            onRitenta={() => setAi("elaborazione")}
            onManuale={() => setAi("attesa")}
          />
        </TabsContent>

        <TabsContent value="annunci" className="mt-6 grid gap-3 md:grid-cols-2">
          {listingStates.map((s) => (
            <div key={s} className="rounded-2xl border border-border bg-card p-4">
              <div className="flex items-center justify-between">
                <p className="font-serif text-lg">{listingActionCopy[s].titolo}</p>
                <span
                  className={`rounded-full px-2 py-0.5 text-[10px] font-medium ${listingStatusTone[s]}`}
                >
                  {listingStatusLabel[s]}
                </span>
              </div>
              <p className="mt-1 text-xs text-muted-foreground">Azioni disponibili:</p>
              <ul className="mt-1 list-disc pl-4 text-sm">
                {listingActionCopy[s].azioni.map((a) => (
                  <li key={a}>{a}</li>
                ))}
              </ul>
            </div>
          ))}
        </TabsContent>

        <TabsContent value="ordini" className="mt-6 grid gap-3 md:grid-cols-2">
          {proposalEdgeCases.map((e) => (
            <div key={e.id} className="rounded-2xl border border-border bg-card p-4">
              <p className="font-serif text-base font-semibold">{e.label}</p>
              <p className="mt-1 text-sm text-muted-foreground">{e.desc}</p>
            </div>
          ))}
        </TabsContent>

        <TabsContent value="immagini" className="mt-6 grid gap-4 sm:grid-cols-3">
          <div>
            <p className="mb-2 text-xs text-muted-foreground">URL rotto</p>
            <SafeImage
              src="/immagine-rotta.jpg"
              alt=""
              className="aspect-square w-full rounded-xl object-cover"
            />
          </div>
          <div>
            <p className="mb-2 text-xs text-muted-foreground">Nessuna foto</p>
            <SafeImage
              src=""
              alt=""
              className="aspect-square w-full rounded-xl object-cover"
              fallbackLabel="Nessuna foto caricata"
            />
          </div>
          <div>
            <p className="mb-2 text-xs text-muted-foreground">Modello 3D non disponibile</p>
            <div
              role="img"
              aria-label="Vista 3D non disponibile"
              className="grid aspect-square w-full place-items-center rounded-xl border border-dashed border-border bg-secondary text-xs text-muted-foreground"
            >
              Vista 3D non disponibile
            </div>
          </div>
        </TabsContent>
      </Tabs>
    </div>
  );
}
