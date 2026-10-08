"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import { ArrowLeft, Download, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Progress } from "@/components/ui/progress";
import { EmptyState, ErrorState, LoadingBlock } from "@/components/vinea/States";
import {
  Qv2DistributionsSection,
  Qv2FunnelCard,
  Qv2KpiSection,
  Qv2ParticipantDetailSheet,
  Qv2TesterTable,
} from "@/components/vinea/market-validation/Qv2AdminPanels";
import {
  EMPTY_MARKET_VALIDATION_ADMIN_SUMMARY,
  buildMarketValidationParticipantsCsv,
  formatPercentage,
  parseMarketValidationParticipantFilter,
  percentage,
  type MarketValidationAdminSummary,
  type MarketValidationParticipantFilter,
} from "@/lib/market-validation/admin-analytics";
import {
  EMPTY_QV2_ADMIN_SUMMARY,
  EMPTY_QV2_DISTRIBUTIONS,
  QV2_ADMIN_PAGE_SIZE,
  buildQv2ParticipantsCsv,
  type Qv2AdminParticipant,
  type Qv2AdminSummary,
  type Qv2CohortFilter,
  type Qv2Distributions,
} from "@/lib/market-validation/questionnaire-admin";
import { getSupabaseClient } from "@/lib/supabase/client";
import {
  loadAllMarketValidationAdminParticipants,
  loadMarketValidationAdminSummary,
} from "@/services/market-validation-admin-service";
import {
  loadAllQv2AdminParticipants,
  loadQv2AdminDistributions,
  loadQv2AdminParticipants,
  loadQv2AdminSummary,
} from "@/services/market-validation-questionnaire-admin-service";
import type { MarketValidationParticipantCode } from "@/services/types";

type FunnelStep = { label: string; value: number };

const COHORT_OPTIONS: ReadonlyArray<{ value: Qv2CohortFilter; label: string }> = [
  { value: null, label: "Tutti" },
  { value: "qv2", label: "QV2" },
  { value: "legacy", label: "Legacy" },
];

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

const downloadCsv = (content: string, filename: string) => {
  const blob = new Blob([content], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
};

export function MarketValidationAdminClient() {
  const [summary, setSummary] = useState<MarketValidationAdminSummary>(
    EMPTY_MARKET_VALIDATION_ADMIN_SUMMARY,
  );
  const [qv2Summary, setQv2Summary] = useState<Qv2AdminSummary>(EMPTY_QV2_ADMIN_SUMMARY);
  const [distributions, setDistributions] = useState<Qv2Distributions>(EMPTY_QV2_DISTRIBUTIONS);
  const [participants, setParticipants] = useState<Qv2AdminParticipant[]>([]);
  const [total, setTotal] = useState(0);
  const [offset, setOffset] = useState(0);
  const [cohort, setCohort] = useState<Qv2CohortFilter>(null);
  const cohortRef = useRef<Qv2CohortFilter>(null);
  const [filterInput, setFilterInput] = useState("");
  const [activeFilter, setActiveFilter] = useState<MarketValidationParticipantFilter>(null);
  const [filterError, setFilterError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [loaded, setLoaded] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [exporting, setExporting] = useState(false);
  const [detailCode, setDetailCode] = useState<MarketValidationParticipantCode | null>(null);

  const load = useCallback(async (filter: MarketValidationParticipantFilter) => {
    setLoading(true);
    setError(null);
    try {
      const client = getSupabaseClient();
      const [nextSummary, nextQv2Summary, nextDistributions, page] = await Promise.all([
        loadMarketValidationAdminSummary(client),
        loadQv2AdminSummary(client),
        loadQv2AdminDistributions(client),
        loadQv2AdminParticipants(client, {
          participantCode: filter,
          cohort: cohortRef.current,
          limit: QV2_ADMIN_PAGE_SIZE,
          offset: 0,
        }),
      ]);
      setSummary(nextSummary);
      setQv2Summary(nextQv2Summary);
      setDistributions(nextDistributions);
      setParticipants(page.participants);
      setTotal(page.total);
      setOffset(0);
      setLoaded(true);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Non è stato possibile caricare le analytics.");
    } finally {
      setLoading(false);
    }
  }, []);

  // Cambio pagina o coorte: ricarica soltanto l'elenco, con gli stessi filtri.
  const loadPage = async (nextCohort: Qv2CohortFilter, nextOffset: number) => {
    setLoading(true);
    setError(null);
    try {
      const page = await loadQv2AdminParticipants(getSupabaseClient(), {
        participantCode: activeFilter,
        cohort: nextCohort,
        limit: QV2_ADMIN_PAGE_SIZE,
        offset: nextOffset,
      });
      setParticipants(page.participants);
      setTotal(page.total);
      setOffset(nextOffset);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Non è stato possibile caricare i tester.");
    } finally {
      setLoading(false);
    }
  };

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

  const changeCohort = (nextCohort: Qv2CohortFilter) => {
    cohortRef.current = nextCohort;
    setCohort(nextCohort);
    void loadPage(nextCohort, 0);
  };

  const exportCsv = async () => {
    if (exporting) return;
    setExporting(true);
    setError(null);
    try {
      const rows = await loadAllQv2AdminParticipants(getSupabaseClient(), {
        participantCode: activeFilter,
        cohort,
      });
      const scope = activeFilter ?? (cohort ? `${cohort}` : "completo");
      downloadCsv(buildQv2ParticipantsCsv(rows), `market-validation-qv2-${scope}.csv`);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Esportazione non riuscita.");
    } finally {
      setExporting(false);
    }
  };

  // Export MV3 originale, conservato per continuità con le analisi già fatte.
  const exportLegacyCsv = async () => {
    if (exporting) return;
    setExporting(true);
    setError(null);
    try {
      const rows = await loadAllMarketValidationAdminParticipants(getSupabaseClient(), activeFilter);
      downloadCsv(
        buildMarketValidationParticipantsCsv(rows),
        activeFilter ? `market-validation-${activeFilter}.csv` : "market-validation-participants.csv",
      );
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

  const favoriteCodes = qv2Summary.qv2.favoriteAdded + qv2Summary.legacy.favoriteAdded;
  const pageEnd = offset + participants.length;

  return (
    <div className="space-y-8">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <Button asChild variant="ghost" size="sm" className="mb-2 -ml-3">
            <Link href="/admin"><ArrowLeft /> Operazioni Admin</Link>
          </Button>
          <h1 className="font-serif text-3xl md:text-4xl">Market Validation</h1>
          <p className="max-w-3xl text-muted-foreground">
            Dati pseudonimi per codice partecipante, in sola lettura. Nessuna capability, UUID di sessione,
            metadata o informazione personale è esposta.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button variant="outline" onClick={() => void load(activeFilter)} disabled={loading}>
            <RefreshCw className={loading ? "animate-spin" : ""} /> Aggiorna
          </Button>
          <Button onClick={() => void exportCsv()} disabled={!loaded || loading || exporting}>
            <Download /> {exporting ? "Esportazione…" : "Esporta CSV completo"}
          </Button>
          <Button variant="ghost" onClick={() => void exportLegacyCsv()} disabled={!loaded || loading || exporting}>
            <Download /> CSV MV3
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
              {qv2Summary.qv2.started === 0 ? (
                <EmptyState
                  title="Nessun questionario QV2 avviato."
                  message="KPI e funnel del questionario compariranno dopo il primo test QV2 reale. I test legacy restano nelle statistiche del percorso."
                />
              ) : (
                <div className="space-y-4">
                  <Qv2KpiSection summary={qv2Summary} />
                  <Qv2FunnelCard summary={qv2Summary} />
                </div>
              )}

              <section aria-labelledby="mv-kpi-title" className="space-y-3">
                <div>
                  <h2 id="mv-kpi-title" className="font-serif text-2xl">Statistiche del percorso</h2>
                  <p className="text-sm text-muted-foreground">
                    Tutti i codici, legacy e QV2. Il completamento qui è la Core Beta (beta_completed), non la Market
                    Validation completa.
                  </p>
                </div>
                <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
                  <KpiCard value={summary.testersStarted} label="Tester avviati" />
                  <KpiCard value={summary.testersCompleted} label="Core Beta completata" />
                  <KpiCard value={formatPercentage(summary.completionRate)} label="Tasso di completamento core" />
                  <KpiCard value={summary.totalSessions} label="Sessioni totali" />
                  <KpiCard value={summary.uniqueCodes} label="Codici unici" />
                </div>
                <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
                  <KpiCard
                    value={qv2Summary.legacy.codes}
                    label="Tester legacy"
                    detail="Guida senza questionario: fuori dai denominatori QV2"
                  />
                  <KpiCard
                    value={qv2Summary.legacy.coreCompleted}
                    label="Core completata (legacy)"
                    detail={`${formatPercentage(qv2Summary.legacy.coreCompletionRate)} dei tester legacy`}
                  />
                  <KpiCard
                    value={favoriteCodes}
                    label="Preferito aggiunto"
                    detail={`${formatPercentage(percentage(favoriteCodes, qv2Summary.allCodes))} dei codici`}
                  />
                  <KpiCard
                    value={summary.buyer.shippingCostViewed}
                    label="Costo spedizione visualizzato"
                    detail={`${formatPercentage(percentage(summary.buyer.shippingCostViewed, summary.testersStarted))} dei tester avviati`}
                  />
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

              <Qv2DistributionsSection distributions={distributions} />
            </>
          )}

          <section aria-labelledby="mv-participants-title" className="space-y-4">
            <div>
              <h2 id="mv-participants-title" className="font-serif text-2xl">Tester</h2>
              <p className="text-sm text-muted-foreground">
                Una riga per codice. Per un codice QV2 contano solo la sessione del questionario e le sue risposte; un
                codice legacy somma tutti i tentativi e i rientri, come nelle analytics MV3. Apri un codice per
                confrontare risposte e comportamento.
              </p>
            </div>
            <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
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
                <Button type="submit" variant="outline">Cerca</Button>
                <Button type="button" variant="ghost" onClick={resetFilter} disabled={activeFilter === null && filterInput === ""}>
                  Reimposta
                </Button>
              </form>
              <div role="group" aria-label="Coorte" className="flex gap-1">
                {COHORT_OPTIONS.map((option) => (
                  <Button
                    key={option.label}
                    type="button"
                    size="sm"
                    variant={cohort === option.value ? "default" : "outline"}
                    aria-pressed={cohort === option.value}
                    disabled={loading}
                    onClick={() => changeCohort(option.value)}
                  >
                    {option.label}
                  </Button>
                ))}
              </div>
            </div>

            {participants.length === 0 ? (
              <EmptyState
                title={activeFilter ? `Nessun dato per ${activeFilter}.` : "Nessun tester per questo filtro."}
                message={activeFilter || cohort ? "Reimposta i filtri per vedere tutti i codici." : undefined}
              />
            ) : (
              <>
                <Card>
                  <CardContent className="p-0">
                    <Qv2TesterTable participants={participants} onOpen={setDetailCode} />
                  </CardContent>
                </Card>
                <nav aria-label="Paginazione tester" className="flex flex-wrap items-center justify-between gap-2 text-sm">
                  <span className="text-muted-foreground">
                    Righe {offset + 1}–{pageEnd} di {total}
                  </span>
                  <div className="flex gap-2">
                    <Button
                      variant="outline"
                      size="sm"
                      disabled={loading || offset === 0}
                      onClick={() => void loadPage(cohort, Math.max(0, offset - QV2_ADMIN_PAGE_SIZE))}
                    >
                      Precedente
                    </Button>
                    <Button
                      variant="outline"
                      size="sm"
                      disabled={loading || pageEnd >= total}
                      onClick={() => void loadPage(cohort, offset + QV2_ADMIN_PAGE_SIZE)}
                    >
                      Successiva
                    </Button>
                  </div>
                </nav>
              </>
            )}
          </section>

          <Qv2ParticipantDetailSheet participantCode={detailCode} onClose={() => setDetailCode(null)} />
        </>
      ) : null}
    </div>
  );
}
