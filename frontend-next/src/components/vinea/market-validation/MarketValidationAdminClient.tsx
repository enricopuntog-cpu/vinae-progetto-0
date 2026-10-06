"use client";

import Link from "next/link";
import { useCallback, useEffect, useState, type FormEvent } from "react";
import { ArrowLeft, Download, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Progress } from "@/components/ui/progress";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { EmptyState, ErrorState, LoadingBlock } from "@/components/vinea/States";
import {
  EMPTY_MARKET_VALIDATION_ADMIN_SUMMARY,
  MARKET_VALIDATION_ADMIN_PAGE_SIZE,
  buildMarketValidationParticipantsCsv,
  formatPercentage,
  parseMarketValidationParticipantFilter,
  percentage,
  type MarketValidationAdminParticipant,
  type MarketValidationAdminSummary,
  type MarketValidationParticipantFilter,
} from "@/lib/market-validation/admin-analytics";
import { getSupabaseClient } from "@/lib/supabase/client";
import {
  loadAllMarketValidationAdminParticipants,
  loadMarketValidationAdminParticipants,
  loadMarketValidationAdminSummary,
} from "@/services/market-validation-admin-service";

type FunnelStep = { label: string; value: number };

const dateTime = (value: string | null): string =>
  value
    ? new Date(value).toLocaleString("it-IT", {
        dateStyle: "medium",
        timeStyle: "short",
      })
    : "—";

function KpiCard({ value, label, detail }: { value: string | number; label: string; detail?: string }) {
  return (
    <Card>
      <CardContent className="p-4">
        <span className="block text-3xl font-semibold">{value}</span>
        <span className="text-sm text-muted-foreground">{label}</span>
        {detail ? <span className="mt-1 block text-xs text-muted-foreground">{detail}</span> : null}
      </CardContent>
    </Card>
  );
}

function Funnel({ title, description, steps }: { title: string; description: string; steps: FunnelStep[] }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="font-serif text-2xl">{title}</CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {steps.map((step, index) => {
          const previous = index === 0 ? step.value : steps[index - 1].value;
          const rate = index === 0 ? 100 : percentage(step.value, previous);
          return (
            <div key={step.label} className="space-y-1.5">
              <div className="flex flex-wrap items-baseline justify-between gap-2 text-sm">
                <span className="font-medium">{step.label}</span>
                <span>
                  {step.value} codici · {index === 0 ? "base" : `${formatPercentage(rate)} dal passaggio precedente`}
                </span>
              </div>
              <Progress value={rate} aria-label={`${step.label}: ${step.value} codici, ${formatPercentage(rate)}`} />
            </div>
          );
        })}
      </CardContent>
    </Card>
  );
}

function ParticipantsTable({ participants }: { participants: MarketValidationAdminParticipant[] }) {
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Codice</TableHead>
          <TableHead>Sessioni</TableHead>
          <TableHead>Primo avvio</TableHead>
          <TableHead>Ultimo avvio</TableHead>
          <TableHead>Ultimo completamento</TableHead>
          <TableHead>Completato</TableHead>
          <TableHead>Marketplace</TableHead>
          <TableHead>Annuncio</TableHead>
          <TableHead>Preferito</TableHead>
          <TableHead>Checkout</TableHead>
          <TableHead>Shipping</TableHead>
          <TableHead>Buyer completato</TableHead>
          <TableHead>Vendita avviata</TableHead>
          <TableHead>Foto provata</TableHead>
          <TableHead>Vendita completata</TableHead>
          <TableHead>AI preview</TableHead>
          <TableHead>AI interesse</TableHead>
          <TableHead>Club</TableHead>
          <TableHead>Test completato</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {participants.map((participant) => (
          <TableRow key={participant.participantCode}>
            <TableCell className="font-semibold">{participant.participantCode}</TableCell>
            <TableCell>{participant.sessionsCount}</TableCell>
            <TableCell className="whitespace-nowrap">{dateTime(participant.firstStartedAt)}</TableCell>
            <TableCell className="whitespace-nowrap">{dateTime(participant.lastStartedAt)}</TableCell>
            <TableCell className="whitespace-nowrap">{dateTime(participant.lastCompletedAt)}</TableCell>
            <TableCell>{participant.completed ? "Sì" : "No"}</TableCell>
            <TableCell>{participant.marketplaceViewed}</TableCell>
            <TableCell>{participant.demoListingViewed}</TableCell>
            <TableCell>{participant.favoriteAdded}</TableCell>
            <TableCell>{participant.checkoutStarted}</TableCell>
            <TableCell>{participant.shippingCostViewed}</TableCell>
            <TableCell>{participant.checkoutBetaCompleted}</TableCell>
            <TableCell>{participant.sellStarted}</TableCell>
            <TableCell>{participant.sellPhotoSelected}</TableCell>
            <TableCell>{participant.sellCompleted}</TableCell>
            <TableCell>{participant.aiPreviewViewed}</TableCell>
            <TableCell>{participant.aiInterestClicked}</TableCell>
            <TableCell>{participant.clubViewed}</TableCell>
            <TableCell>{participant.betaCompleted}</TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

export function MarketValidationAdminClient() {
  const [summary, setSummary] = useState<MarketValidationAdminSummary>(
    EMPTY_MARKET_VALIDATION_ADMIN_SUMMARY,
  );
  const [participants, setParticipants] = useState<MarketValidationAdminParticipant[]>([]);
  const [filterInput, setFilterInput] = useState("");
  const [activeFilter, setActiveFilter] = useState<MarketValidationParticipantFilter>(null);
  const [filterError, setFilterError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [loaded, setLoaded] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [exporting, setExporting] = useState(false);

  const load = useCallback(async (filter: MarketValidationParticipantFilter) => {
    setLoading(true);
    setError(null);
    try {
      const client = getSupabaseClient();
      const [nextSummary, nextParticipants] = await Promise.all([
        loadMarketValidationAdminSummary(client),
        loadMarketValidationAdminParticipants(client, {
          participantCode: filter,
          limit: MARKET_VALIDATION_ADMIN_PAGE_SIZE,
          offset: 0,
        }),
      ]);
      setSummary(nextSummary);
      setParticipants(nextParticipants);
      setLoaded(true);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Non è stato possibile caricare le analytics.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load(null);
  }, [load]);

  const applyFilter = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const parsed = parseMarketValidationParticipantFilter(filterInput);
    if (parsed === undefined) {
      setFilterError("Usa un codice da V001 a V999.");
      return;
    }
    setFilterError(null);
    setActiveFilter(parsed);
    setFilterInput(parsed ?? "");
    void load(parsed);
  };

  const resetFilter = () => {
    setFilterInput("");
    setFilterError(null);
    setActiveFilter(null);
    void load(null);
  };

  const exportCsv = async () => {
    if (exporting) return;
    setExporting(true);
    setError(null);
    try {
      const rows = await loadAllMarketValidationAdminParticipants(
        getSupabaseClient(),
        activeFilter,
      );
      const blob = new Blob([buildMarketValidationParticipantsCsv(rows)], {
        type: "text/csv;charset=utf-8",
      });
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = activeFilter
        ? `market-validation-${activeFilter}.csv`
        : "market-validation-participants.csv";
      document.body.append(anchor);
      anchor.click();
      anchor.remove();
      URL.revokeObjectURL(url);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Esportazione non riuscita.");
    } finally {
      setExporting(false);
    }
  };

  const buyerSteps: FunnelStep[] = [
    { label: "Started", value: summary.buyer.started },
    { label: "Marketplace visualizzato", value: summary.buyer.marketplaceViewed },
    { label: "Annuncio demo visualizzato", value: summary.buyer.demoListingViewed },
    { label: "Checkout avviato", value: summary.buyer.checkoutStarted },
    { label: "Costo spedizione visualizzato", value: summary.buyer.shippingCostViewed },
    { label: "Checkout beta completato", value: summary.buyer.checkoutBetaCompleted },
  ];
  const sellerSteps: FunnelStep[] = [
    { label: "Started", value: summary.seller.started },
    { label: "Vendita avviata", value: summary.seller.sellStarted },
    { label: "Vendita completata", value: summary.seller.sellCompleted },
  ];

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <Button asChild variant="ghost" size="sm" className="mb-2 -ml-3">
            <Link href="/admin"><ArrowLeft /> Operazioni Admin</Link>
          </Button>
          <h1 className="font-serif text-3xl md:text-4xl">Market Validation</h1>
          <p className="max-w-3xl text-muted-foreground">
            Conteggi aggregati per codice partecipante. Nessuna capability, UUID di sessione,
            metadata o informazione personale è esposta.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button variant="outline" onClick={() => void load(activeFilter)} disabled={loading}>
            <RefreshCw className={loading ? "animate-spin" : ""} /> Aggiorna
          </Button>
          <Button onClick={() => void exportCsv()} disabled={!loaded || loading || exporting}>
            <Download /> {exporting ? "Esportazione…" : "Esporta CSV"}
          </Button>
        </div>
      </header>

      {error && !loaded ? (
        <ErrorState message={error} onRetry={() => void load(activeFilter)} home={false} />
      ) : null}
      {loading && !loaded ? <LoadingBlock label="Caricamento analytics Market Validation" /> : null}
      {error && loaded ? (
        <p role="alert" className="rounded-md border border-bordeaux/40 bg-bordeaux/5 p-3 text-sm text-bordeaux">
          {error}
        </p>
      ) : null}

      {loaded ? (
        <>
          {summary.testersStarted === 0 ? (
            <EmptyState title="Nessun test registrato." message="Le analytics compariranno dopo il primo avvio valido." />
          ) : (
            <>
              <section aria-labelledby="mv-kpi-title" className="space-y-3">
                <h2 id="mv-kpi-title" className="font-serif text-2xl">KPI</h2>
                <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
                  <KpiCard value={summary.testersStarted} label="Tester avviati" />
                  <KpiCard value={summary.testersCompleted} label="Tester completati" />
                  <KpiCard value={formatPercentage(summary.completionRate)} label="Tasso di completamento" />
                  <KpiCard value={summary.totalSessions} label="Sessioni totali" />
                  <KpiCard value={summary.uniqueCodes} label="Codici unici" />
                </div>
              </section>

              <section className="grid gap-4 xl:grid-cols-2" aria-label="Funnel Market Validation">
                <Funnel
                  title="Funnel Buyer"
                  description="Le percentuali sono step-to-step: ogni passaggio usa come denominatore quello immediatamente precedente."
                  steps={buyerSteps}
                />
                <Funnel
                  title="Funnel Seller"
                  description="Il percorso principale esclude la foto, che è una prova facoltativa e viene misurata separatamente."
                  steps={sellerSteps}
                />
              </section>

              <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4" aria-label="Metriche secondarie">
                <KpiCard
                  value={summary.seller.sellPhotoSelected}
                  label="Ha provato ad aggiungere una foto"
                  detail={`${formatPercentage(percentage(summary.seller.sellPhotoSelected, summary.seller.started))} dei tester avviati`}
                />
                <KpiCard value={summary.ai.previewViewed} label="Preview AI visualizzate" />
                <KpiCard
                  value={summary.ai.interestClicked}
                  label="Interesse AI dichiarato"
                  detail={`${formatPercentage(summary.ai.interestRate)} · Interesse dichiarato dopo aver visto la preview`}
                />
                <KpiCard
                  value={summary.club.viewed}
                  label="Club visualizzato"
                  detail={`${formatPercentage(summary.club.viewedRate)} dei tester avviati`}
                />
              </section>
            </>
          )}

          <section aria-labelledby="mv-participants-title" className="space-y-4">
            <div>
              <h2 id="mv-participants-title" className="font-serif text-2xl">Partecipanti</h2>
              <p className="text-sm text-muted-foreground">
                Una riga per codice; i conteggi sommano tutti i tentativi e i rientri del codice.
              </p>
            </div>
            <form onSubmit={applyFilter} className="flex max-w-xl flex-col gap-2 sm:flex-row sm:items-start">
              <div className="flex-1">
                <label htmlFor="participant-code" className="sr-only">Codice partecipante</label>
                <Input
                  id="participant-code"
                  value={filterInput}
                  onChange={(event) => setFilterInput(event.target.value)}
                  placeholder="V001"
                  autoComplete="off"
                  aria-invalid={filterError !== null}
                  aria-describedby={filterError ? "participant-code-error" : undefined}
                />
                {filterError ? <p id="participant-code-error" className="mt-1 text-sm text-bordeaux">{filterError}</p> : null}
              </div>
              <Button type="submit" variant="outline">Filtra</Button>
              <Button type="button" variant="ghost" onClick={resetFilter} disabled={activeFilter === null && filterInput === ""}>
                Reimposta
              </Button>
            </form>

            {participants.length === 0 ? (
              <EmptyState
                title={activeFilter ? `Nessun dato per ${activeFilter}.` : "Nessun test registrato."}
                message={activeFilter ? "Reimposta il filtro per vedere tutti i codici." : undefined}
              />
            ) : (
              <Card>
                <CardContent className="p-0">
                  <ParticipantsTable participants={participants} />
                </CardContent>
              </Card>
            )}
          </section>
        </>
      ) : null}
    </div>
  );
}
