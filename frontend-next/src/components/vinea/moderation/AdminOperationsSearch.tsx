"use client";

// Le quattro sezioni operative — Utenti, Annunci, Ordini, Club — sono lo stesso
// componente configurato per ambito. Non quattro ricerche indipendenti: una
// sola porta a database, una sola forma di stato (ricerca, caricamento, vuoto,
// errore, risultati, dettaglio), e un solo posto dove correggere un difetto.
//
// Tutto qui e in sola lettura. La BUILD 1 non introduce comandi: ruoli,
// sospensioni, rimborsi e payout restano fuori, e cio che si mostra viene da
// porte che verificano il ruolo reale a database.

import Link from "next/link";
import { type FormEvent, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { getSupabaseClient } from "@/lib/supabase/client";
import {
  ADMIN_LOOKUP_MIN_LENGTH,
  EMPTY_ADMIN_LOOKUP,
  adminOperationsDetail,
  adminOperationsLookup,
  type AdminClubResult,
  type AdminDetail,
  type AdminListingResult,
  type AdminLookupResults,
  type AdminOrderDetail,
  type AdminOrderResult,
  type AdminRelatedReport,
  type AdminScope,
  type AdminUserDetail,
  type AdminUserResult,
} from "@/services/phase9/admin-operations-service";

// Il focus che le sezioni chiedono al pannello. Non basta cambiare scheda: chi
// arriva da un utente con tre segnalazioni deve trovarsi davanti quelle tre,
// non l'intera coda in cui ritrovarle a mano.
export type AdminReportFocus =
  | { kind: "profilo"; id: string; label: string }
  | { kind: "annuncio"; id: string; label: string }
  | { kind: "club"; slug: string; label: string };

export type AdminDisputeFocus = { orderId: string; label: string };

type Props = {
  scope: AdminScope;
  onFocusReports: (focus: AdminReportFocus) => void;
  onFocusDispute: (focus: AdminDisputeFocus) => void;
};

const SCOPE_UX: Record<AdminScope, { titolo: string; etichetta: string; placeholder: string; aiuto: string; vuoto: string }> = {
  utente: {
    titolo: "Utenti",
    etichetta: "Cerca un utente",
    placeholder: "Username oppure UUID utente",
    aiuto: "Username o UUID · minimo 2 caratteri · massimo 10 risultati.",
    vuoto: "Nessun utente.",
  },
  annuncio: {
    titolo: "Annunci",
    etichetta: "Cerca un annuncio",
    placeholder: "UUID annuncio, slug, vino o produttore",
    aiuto: "UUID, slug, vino o produttore · minimo 2 caratteri · massimo 10 risultati.",
    vuoto: "Nessun annuncio.",
  },
  ordine: {
    titolo: "Ordini",
    etichetta: "Cerca un ordine",
    // Il backend cerca gli ordini solo per UUID esatto. Promettere un «codice
    // ordine» sarebbe una ricerca che non puo riuscire.
    placeholder: "UUID ordine (identificativo esatto)",
    aiuto: "Solo UUID esatto: gli ordini non hanno un codice ricercabile.",
    vuoto: "Nessun ordine.",
  },
  club: {
    titolo: "Club",
    etichetta: "Cerca un club",
    placeholder: "Nome oppure slug del club",
    aiuto: "Nome o slug · minimo 2 caratteri · massimo 10 risultati.",
    vuoto: "Nessun club.",
  },
};

const euro = (cents: number | null) =>
  cents === null || cents === undefined
    ? "Non disponibile"
    : new Intl.NumberFormat("it-IT", { style: "currency", currency: "EUR" }).format(cents / 100);

const quando = (iso: string | null) =>
  iso
    ? new Date(iso).toLocaleString("it-IT", { dateStyle: "medium", timeStyle: "short" })
    : "Non disponibile";

const ShortId = ({ value }: { value: string }) => (
  <code className="break-all rounded bg-muted px-1.5 py-0.5 text-xs">{value}</code>
);

const Riga = ({ label, value }: { label: string; value: React.ReactNode }) => (
  <div>
    <dt className="text-muted-foreground">{label}</dt>
    <dd>{value}</dd>
  </div>
);

const ReportsCorrelate = ({ reports }: { reports: AdminRelatedReport[] }) =>
  reports.length === 0 ? null : (
    <div className="space-y-2 border-t pt-3" data-testid="admin-related-reports">
      <p className="text-xs font-medium uppercase text-muted-foreground">Segnalazioni correlate</p>
      <ol className="space-y-1 text-xs text-muted-foreground">
        {reports.map((report) => (
          <li key={report.id}>
            <span className="font-medium">{report.codice}</span> · {report.motivo} · {report.stato} ·{" "}
            {quando(report.createdAt)}
          </li>
        ))}
      </ol>
    </div>
  );

// ---------------------------------------------------------------------------
// Le carte di risultato, una per ambito
// ---------------------------------------------------------------------------

const UserCard = ({ result, onApri }: { result: AdminUserResult; onApri: () => void }) => (
  <Card className="space-y-3 p-4" data-testid="admin-user-result">
    <div className="flex flex-wrap items-start justify-between gap-2">
      <div>
        <p className="font-medium">@{result.username}</p>
        <p className="text-xs text-muted-foreground">ID utente <ShortId value={result.id} /></p>
      </div>
      <Badge variant="secondary">{result.role}</Badge>
    </div>
    <dl className="grid gap-2 text-sm sm:grid-cols-2">
      <Riga label="Iscrizione" value={quando(result.createdAt)} />
      <Riga label="Stato" value={result.status ?? "Non disponibile"} />
      <Riga label="Annunci" value={result.listingCount} />
      <Riga label="Segnalazioni aperte" value={result.openReportCount} />
    </dl>
    <Button variant="outline" size="sm" onClick={onApri}>Apri dettaglio</Button>
  </Card>
);

const ListingCard = ({ result, onApri }: { result: AdminListingResult; onApri: () => void }) => (
  <Card className="space-y-3 p-4" data-testid="admin-listing-result">
    <div className="flex flex-wrap items-start justify-between gap-2">
      <div>
        <p className="font-medium">{result.title}</p>
        <p className="text-sm text-muted-foreground">Venditore: {result.sellerUsername}</p>
      </div>
      <Badge variant="secondary">{result.status ?? "Stato non disponibile"}</Badge>
    </div>
    <p className="text-xs text-muted-foreground">ID annuncio <ShortId value={result.id} /></p>
    <dl className="grid gap-2 text-sm sm:grid-cols-3">
      <Riga label="Prezzo" value={euro(result.priceCents)} />
      <Riga label="Creato" value={quando(result.createdAt)} />
      <Riga label="Aggiornato" value={quando(result.updatedAt)} />
    </dl>
    <Button variant="outline" size="sm" onClick={onApri}>Apri dettaglio</Button>
  </Card>
);

const OrderCard = ({ result, onApri }: { result: AdminOrderResult; onApri: () => void }) => (
  <Card className="space-y-3 p-4" data-testid="admin-order-result">
    <div className="flex flex-wrap items-start justify-between gap-2">
      <div>
        <p className="font-medium">Ordine {result.id.slice(0, 8)}</p>
        <p className="text-sm text-muted-foreground">{result.buyerUsername} → {result.sellerUsername}</p>
      </div>
      <Badge variant="secondary">{result.status ?? "Stato non disponibile"}</Badge>
    </div>
    <p className="text-xs text-muted-foreground">ID ordine <ShortId value={result.id} /></p>
    <dl className="grid gap-2 text-sm sm:grid-cols-3">
      <Riga label="Totale" value={euro(result.totalCents)} />
      <Riga label="Payout" value={result.payoutStatus ?? "Non disponibile"} />
      <Riga label="Creato" value={quando(result.createdAt)} />
    </dl>
    <Button variant="outline" size="sm" onClick={onApri}>Apri dettaglio</Button>
  </Card>
);

const ClubCard = ({ result, onApri }: { result: AdminClubResult; onApri: () => void }) => (
  <Card className="space-y-3 p-4" data-testid="admin-club-result">
    <div className="flex flex-wrap items-start justify-between gap-2">
      <div>
        <p className="font-medium">{result.nome}</p>
        <p className="text-sm text-muted-foreground">/{result.slug}</p>
      </div>
      <Badge variant="secondary">{result.postingMode ?? "Modalita non disponibile"}</Badge>
    </div>
    <dl className="grid gap-2 text-sm sm:grid-cols-2">
      <Riga label="Referente" value={result.ownerUsername ? `@${result.ownerUsername}` : "Non disponibile"} />
      <Riga label="Creato" value={quando(result.createdAt)} />
      <Riga label="Segnalazioni aperte" value={result.openReportCount} />
    </dl>
    <Button variant="outline" size="sm" onClick={onApri}>Apri dettaglio</Button>
  </Card>
);

// ---------------------------------------------------------------------------
// Il dettaglio
// ---------------------------------------------------------------------------

const DettaglioUtente = ({
  entity,
  reports,
  onFocusReports,
}: {
  entity: AdminUserDetail;
  reports: AdminRelatedReport[];
  onFocusReports: (focus: AdminReportFocus) => void;
}) => (
  <Card className="space-y-4 p-5" data-testid="admin-user-detail">
    <div className="flex flex-wrap items-start justify-between gap-2">
      <div>
        <h3 className="font-serif text-2xl">@{entity.username}</h3>
        <p className="text-xs text-muted-foreground">ID utente <ShortId value={entity.id} /></p>
      </div>
      <Badge variant="secondary">{entity.role}</Badge>
    </div>
    <dl className="grid gap-3 text-sm sm:grid-cols-3">
      <Riga label="Stato account" value={entity.status ?? "Non disponibile"} />
      <Riga label="Iscrizione" value={quando(entity.createdAt)} />
      <Riga label="Annunci" value={entity.listingCount} />
      <Riga label="Ordini da acquirente" value={entity.orderCountAsBuyer} />
      <Riga label="Ordini da venditore" value={entity.orderCountAsSeller} />
      <Riga label="Segnalazioni aperte" value={entity.openReportCount} />
    </dl>

    {entity.recentListings.length > 0 ? (
      <div className="space-y-2 border-t pt-3">
        <p className="text-xs font-medium uppercase text-muted-foreground">Annunci recenti</p>
        <ol className="space-y-1 text-sm">
          {entity.recentListings.map((listing) => (
            <li key={listing.id} className="flex flex-wrap items-center gap-2">
              <span>{listing.title}</span>
              <Badge variant="secondary">{listing.status ?? "—"}</Badge>
              {listing.slug ? (
                <Link className="text-xs underline" href={`/annuncio/${encodeURIComponent(listing.slug)}`}>
                  apri
                </Link>
              ) : null}
            </li>
          ))}
        </ol>
      </div>
    ) : null}

    <ReportsCorrelate reports={reports} />

    <div className="flex flex-wrap gap-2 border-t pt-3">
      {/* Il profilo pubblico e indirizzato per UUID, non per username. */}
      <Button asChild variant="outline" size="sm">
        <Link href={`/profilo/${encodeURIComponent(entity.id)}`}>Profilo pubblico</Link>
      </Button>
      {reports.length > 0 ? (
        <Button
          variant="outline"
          size="sm"
          data-testid="admin-focus-user-reports"
          onClick={() => onFocusReports({ kind: "profilo", id: entity.id, label: `@${entity.username}` })}
        >
          Segnalazioni correlate
        </Button>
      ) : null}
    </div>
  </Card>
);

const DettaglioAnnuncio = ({
  entity,
  reports,
  onFocusReports,
}: {
  entity: AdminListingResult;
  reports: AdminRelatedReport[];
  onFocusReports: (focus: AdminReportFocus) => void;
}) => (
  <Card className="space-y-4 p-5" data-testid="admin-listing-detail">
    <div className="flex flex-wrap items-start justify-between gap-2">
      <div>
        <h3 className="font-serif text-2xl">{entity.title}</h3>
        <p className="text-xs text-muted-foreground">ID annuncio <ShortId value={entity.id} /></p>
      </div>
      <Badge variant="secondary">{entity.status ?? "Stato non disponibile"}</Badge>
    </div>
    <dl className="grid gap-3 text-sm sm:grid-cols-3">
      <Riga label="Venditore" value={`@${entity.sellerUsername}`} />
      <Riga label="Slug" value={entity.slug ?? "Non disponibile"} />
      <Riga label="Prezzo" value={euro(entity.priceCents)} />
      <Riga label="Creato" value={quando(entity.createdAt)} />
      <Riga label="Aggiornato" value={quando(entity.updatedAt)} />
      <Riga label="Segnalazioni aperte" value={entity.openReportCount} />
    </dl>

    <ReportsCorrelate reports={reports} />

    <div className="flex flex-wrap gap-2 border-t pt-3">
      {entity.slug ? (
        <Button asChild variant="outline" size="sm">
          <Link href={`/annuncio/${encodeURIComponent(entity.slug)}`}>Apri annuncio</Link>
        </Button>
      ) : null}
      {reports.length > 0 ? (
        <Button
          variant="outline"
          size="sm"
          data-testid="admin-focus-listing-reports"
          onClick={() => onFocusReports({ kind: "annuncio", id: entity.id, label: entity.title })}
        >
          Vai alla segnalazione
        </Button>
      ) : null}
    </div>
  </Card>
);

const DettaglioOrdine = ({
  entity,
  onFocusDispute,
}: {
  entity: AdminOrderDetail;
  onFocusDispute: (focus: AdminDisputeFocus) => void;
}) => (
  <Card className="space-y-4 p-5" data-testid="admin-order-detail">
    <div className="flex flex-wrap items-start justify-between gap-2">
      <div>
        <h3 className="font-serif text-2xl">Ordine {entity.id.slice(0, 8)}</h3>
        <p className="text-xs text-muted-foreground">ID ordine <ShortId value={entity.id} /></p>
      </div>
      <Badge variant="secondary">{entity.status ?? "Stato non disponibile"}</Badge>
    </div>
    <dl className="grid gap-3 text-sm sm:grid-cols-3">
      <Riga label="Acquirente" value={`@${entity.buyerUsername}`} />
      <Riga label="Venditore" value={`@${entity.sellerUsername}`} />
      <Riga label="Totale" value={euro(entity.totalCents)} />
      <Riga label="Stato payout" value={entity.payoutStatus ?? "Non disponibile"} />
      <Riga label="Creato" value={quando(entity.createdAt)} />
      <Riga label="Aggiornato" value={quando(entity.updatedAt)} />
      <Riga label="Contestazione" value={entity.openDispute ? "Aperta" : entity.disputeStatus ?? "Nessuna"} />
      {entity.disputeId ? <Riga label="ID contestazione" value={<ShortId value={entity.disputeId} />} /> : null}
    </dl>

    {/*
      Nessun comando finanziario qui dentro. Rimborsi, incassi, rilascio dei
      compensi e azioni sul provider non appartengono a una sezione di sola
      lettura, e restano fuori dalla BUILD 1 per scelta, non per dimenticanza.
    */}
    <p className="rounded-md border border-dashed p-3 text-xs text-muted-foreground">
      Sezione in sola lettura: da qui non si dispongono movimenti sull&apos;ordine.
    </p>

    {entity.openDispute || entity.disputeId ? (
      <div className="border-t pt-3">
        <Button
          variant="outline"
          size="sm"
          data-testid="admin-focus-order-dispute"
          onClick={() => onFocusDispute({ orderId: entity.id, label: `ordine ${entity.id.slice(0, 8)}` })}
        >
          Apri contestazione
        </Button>
      </div>
    ) : null}
  </Card>
);

const DettaglioClub = ({
  entity,
  reports,
  onFocusReports,
}: {
  entity: AdminClubResult;
  reports: AdminRelatedReport[];
  onFocusReports: (focus: AdminReportFocus) => void;
}) => (
  <Card className="space-y-4 p-5" data-testid="admin-club-detail">
    <div className="flex flex-wrap items-start justify-between gap-2">
      <div>
        <h3 className="font-serif text-2xl">{entity.nome}</h3>
        <p className="text-xs text-muted-foreground">/{entity.slug}</p>
      </div>
      <Badge variant="secondary">{entity.postingMode ?? "Modalita non disponibile"}</Badge>
    </div>
    <dl className="grid gap-3 text-sm sm:grid-cols-3">
      <Riga label="Referente" value={entity.ownerUsername ? `@${entity.ownerUsername}` : "Non disponibile"} />
      <Riga
        label="ID referente"
        value={entity.ownerId ? <ShortId value={entity.ownerId} /> : "Non disponibile"}
      />
      <Riga label="Creato" value={quando(entity.createdAt)} />
      <Riga label="Segnalazioni aperte" value={entity.openReportCount} />
    </dl>

    <ReportsCorrelate reports={reports} />

    <div className="flex flex-wrap gap-2 border-t pt-3">
      <Button asChild variant="outline" size="sm">
        <Link href={`/community/${encodeURIComponent(entity.slug)}`}>Apri club</Link>
      </Button>
      {reports.length > 0 ? (
        <Button
          variant="outline"
          size="sm"
          data-testid="admin-focus-club-reports"
          onClick={() => onFocusReports({ kind: "club", slug: entity.slug, label: entity.nome })}
        >
          Segnalazioni correlate
        </Button>
      ) : null}
    </div>
  </Card>
);

// ---------------------------------------------------------------------------

const risultatiPerScope = (scope: AdminScope, results: AdminLookupResults) => {
  if (scope === "utente") return results.users;
  if (scope === "annuncio") return results.listings;
  if (scope === "ordine") return results.orders;
  return results.clubs;
};

const chiaveRisultato = (scope: AdminScope, result: unknown): string =>
  scope === "club"
    ? (result as AdminClubResult).slug
    : (result as { id: string }).id;

export const AdminOperationsSearch = ({ scope, onFocusReports, onFocusDispute }: Props) => {
  const ux = SCOPE_UX[scope];
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<AdminLookupResults | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [detail, setDetail] = useState<AdminDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [detailError, setDetailError] = useState<string | null>(null);

  const search = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const normalized = query.trim();
    if (normalized.length < ADMIN_LOOKUP_MIN_LENGTH) {
      setResults(null);
      setDetail(null);
      setError("Inserisci almeno 2 caratteri per cercare.");
      return;
    }
    setLoading(true);
    setError(null);
    setDetail(null);
    setDetailError(null);
    try {
      setResults(await adminOperationsLookup(getSupabaseClient(), normalized));
    } catch {
      // L'errore del database non arriva all'operatore cosi com'e: un messaggio
      // di PostgREST direbbe piu della porta di quanto la porta debba dire.
      setResults(EMPTY_ADMIN_LOOKUP);
      setError("La ricerca non e disponibile. Riprova.");
    } finally {
      setLoading(false);
    }
  };

  const apri = async (identificatore: string) => {
    setDetailLoading(true);
    setDetailError(null);
    try {
      setDetail(await adminOperationsDetail(getSupabaseClient(), scope, identificatore));
    } catch {
      setDetail(null);
      setDetailError("Il dettaglio non e disponibile. Riprova.");
    } finally {
      setDetailLoading(false);
    }
  };

  const elenco = results ? risultatiPerScope(scope, results) : [];

  if (detail?.entity) {
    return (
      <div className="space-y-4">
        <Button variant="ghost" size="sm" data-testid="admin-detail-back" onClick={() => setDetail(null)}>
          ← Torna ai risultati
        </Button>
        {detail.tipo === "utente" ? (
          <DettaglioUtente entity={detail.entity} reports={detail.reports} onFocusReports={onFocusReports} />
        ) : null}
        {detail.tipo === "annuncio" ? (
          <DettaglioAnnuncio entity={detail.entity} reports={detail.reports} onFocusReports={onFocusReports} />
        ) : null}
        {detail.tipo === "ordine" ? (
          <DettaglioOrdine entity={detail.entity} onFocusDispute={onFocusDispute} />
        ) : null}
        {detail.tipo === "club" ? (
          <DettaglioClub entity={detail.entity} reports={detail.reports} onFocusReports={onFocusReports} />
        ) : null}
      </div>
    );
  }

  return (
    <div className="space-y-5">
      <form onSubmit={search} className="space-y-2" role="search">
        <label htmlFor={`admin-query-${scope}`} className="font-medium">{ux.etichetta}</label>
        <div className="flex flex-col gap-2 sm:flex-row">
          <input
            id={`admin-query-${scope}`}
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            className="h-10 min-w-0 flex-1 rounded-md border bg-background px-3 text-sm"
            placeholder={ux.placeholder}
            autoComplete="off"
          />
          <Button type="submit" disabled={loading}>{loading ? "Ricerca…" : "Cerca"}</Button>
        </div>
        <p className="text-xs text-muted-foreground">{ux.aiuto}</p>
      </form>

      {error ? (
        <p role="alert" className="rounded-md border border-bordeaux/40 bg-bordeaux/5 p-3 text-sm text-bordeaux">
          {error}
        </p>
      ) : null}
      {detailError ? (
        <p role="alert" className="rounded-md border border-bordeaux/40 bg-bordeaux/5 p-3 text-sm text-bordeaux">
          {detailError}
        </p>
      ) : null}
      {loading ? <p role="status" className="text-sm text-muted-foreground">Ricerca in corso…</p> : null}
      {detailLoading ? <p role="status" className="text-sm text-muted-foreground">Apertura dettaglio…</p> : null}
      {!loading && results && elenco.length === 0 && !error ? (
        <p className="rounded-xl border p-6 text-center text-sm text-muted-foreground">Nessun risultato.</p>
      ) : null}

      {!loading && elenco.length > 0 ? (
        <section className="space-y-3" aria-label={ux.titolo} data-testid={`admin-results-${scope}`}>
          <div className="flex items-center gap-2">
            <h3 className="font-serif text-xl">{ux.titolo}</h3>
            <Badge variant="secondary">{elenco.length}</Badge>
          </div>
          <div className="grid gap-3 lg:grid-cols-2">
            {elenco.map((result) => {
              const chiave = chiaveRisultato(scope, result);
              const onApri = () => void apri(chiave);
              if (scope === "utente") return <UserCard key={chiave} result={result as AdminUserResult} onApri={onApri} />;
              if (scope === "annuncio") return <ListingCard key={chiave} result={result as AdminListingResult} onApri={onApri} />;
              if (scope === "ordine") return <OrderCard key={chiave} result={result as AdminOrderResult} onApri={onApri} />;
              return <ClubCard key={chiave} result={result as AdminClubResult} onApri={onApri} />;
            })}
          </div>
        </section>
      ) : null}
    </div>
  );
};
