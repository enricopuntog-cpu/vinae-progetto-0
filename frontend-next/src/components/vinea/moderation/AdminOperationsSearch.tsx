"use client";

import Link from "next/link";
import { type FormEvent, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { getSupabaseClient } from "@/lib/supabase/client";
import {
  ADMIN_LOOKUP_MIN_LENGTH,
  EMPTY_ADMIN_LOOKUP,
  adminOperationsLookup,
  type AdminListingResult,
  type AdminLookupResults,
  type AdminOrderResult,
  type AdminUserResult,
} from "@/services/phase9/admin-operations-service";

const euro = (cents: number | null) =>
  cents === null
    ? "Non disponibile"
    : new Intl.NumberFormat("it-IT", { style: "currency", currency: "EUR" }).format(cents / 100);

const quando = (iso: string | null) =>
  iso
    ? new Date(iso).toLocaleString("it-IT", { dateStyle: "medium", timeStyle: "short" })
    : "Non disponibile";

const ShortId = ({ value }: { value: string }) => (
  <code className="break-all rounded bg-muted px-1.5 py-0.5 text-xs">{value}</code>
);

const UserCard = ({ result, onReports }: { result: AdminUserResult; onReports: () => void }) => (
  <Card className="space-y-3 p-4" data-testid="admin-user-result">
    <div className="flex flex-wrap items-start justify-between gap-2">
      <div>
        <p className="font-medium">@{result.username}</p>
        <p className="text-xs text-muted-foreground">ID utente <ShortId value={result.id} /></p>
      </div>
      <Badge variant="secondary">{result.role}</Badge>
    </div>
    <dl className="grid gap-2 text-sm sm:grid-cols-2">
      <div><dt className="text-muted-foreground">Iscrizione</dt><dd>{quando(result.createdAt)}</dd></div>
      <div><dt className="text-muted-foreground">Stato</dt><dd>{result.status ?? "Non disponibile"}</dd></div>
      <div><dt className="text-muted-foreground">Annunci</dt><dd>{result.listingCount}</dd></div>
      <div><dt className="text-muted-foreground">Segnalazioni aperte</dt><dd>{result.openReportCount}</dd></div>
    </dl>
    <div className="flex flex-wrap gap-2">
      <Button asChild variant="outline" size="sm"><Link href={`/profilo/${encodeURIComponent(result.username)}`}>Profilo pubblico</Link></Button>
      {result.openReportCount > 0 ? <Button variant="outline" size="sm" onClick={onReports}>Segnalazioni correlate</Button> : null}
    </div>
  </Card>
);

const ListingCard = ({ result, onReports }: { result: AdminListingResult; onReports: () => void }) => (
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
      <div><dt className="text-muted-foreground">Prezzo</dt><dd>{euro(result.priceCents)}</dd></div>
      <div><dt className="text-muted-foreground">Creato</dt><dd>{quando(result.createdAt)}</dd></div>
      <div><dt className="text-muted-foreground">Aggiornato</dt><dd>{quando(result.updatedAt)}</dd></div>
    </dl>
    <div className="flex flex-wrap gap-2">
      {result.slug ? <Button asChild variant="outline" size="sm"><Link href={`/annuncio/${encodeURIComponent(result.slug)}`}>Apri annuncio</Link></Button> : null}
      {result.openReportCount > 0 ? <Button variant="outline" size="sm" onClick={onReports}>Vai alle segnalazioni</Button> : null}
    </div>
  </Card>
);

const OrderCard = ({ result, onDisputes }: { result: AdminOrderResult; onDisputes: () => void }) => (
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
      <div><dt className="text-muted-foreground">Totale</dt><dd>{euro(result.totalCents)}</dd></div>
      <div><dt className="text-muted-foreground">Payout</dt><dd>{result.payoutStatus ?? "Non disponibile"}</dd></div>
      <div><dt className="text-muted-foreground">Creato</dt><dd>{quando(result.createdAt)}</dd></div>
    </dl>
    {result.openDispute ? <Button variant="outline" size="sm" onClick={onDisputes}>Apri contestazione</Button> : null}
  </Card>
);

const ResultGroup = ({ title, count, children }: { title: string; count: number; children: React.ReactNode }) => (
  <section className="space-y-3" aria-labelledby={`admin-results-${title.toLowerCase()}`}>
    <div className="flex items-center gap-2">
      <h3 id={`admin-results-${title.toLowerCase()}`} className="font-serif text-xl">{title}</h3>
      <Badge variant="secondary">{count}</Badge>
    </div>
    {children}
  </section>
);

export const AdminOperationsSearch = ({ onReports, onDisputes }: { onReports: () => void; onDisputes: () => void }) => {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<AdminLookupResults | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const search = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const normalized = query.trim();
    if (normalized.length < ADMIN_LOOKUP_MIN_LENGTH) {
      setResults(null);
      setError("Inserisci almeno 2 caratteri per cercare.");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      setResults(await adminOperationsLookup(getSupabaseClient(), normalized));
    } catch {
      setResults(EMPTY_ADMIN_LOOKUP);
      setError("La ricerca non e disponibile. Riprova.");
    } finally {
      setLoading(false);
    }
  };

  const total = results
    ? results.users.length + results.listings.length + results.orders.length
    : 0;

  return (
    <div className="space-y-6">
      <form onSubmit={search} className="space-y-2" role="search">
        <label htmlFor="admin-operations-query" className="font-medium">Ricerca operativa</label>
        <div className="flex flex-col gap-2 sm:flex-row">
          <input
            id="admin-operations-query"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            className="h-10 min-w-0 flex-1 rounded-md border bg-background px-3 text-sm"
            placeholder="Username, UUID, vino, annuncio o codice ordine"
            autoComplete="off"
          />
          <Button type="submit" disabled={loading}>{loading ? "Ricerca…" : "Cerca"}</Button>
        </div>
        <p className="text-xs text-muted-foreground">Invio esplicito · minimo 2 caratteri · massimo 10 risultati per gruppo.</p>
      </form>

      {error ? <p role="alert" className="rounded-md border border-bordeaux/40 bg-bordeaux/5 p-3 text-sm text-bordeaux">{error}</p> : null}
      {loading ? <p role="status" className="text-sm text-muted-foreground">Ricerca in corso…</p> : null}
      {!loading && results && total === 0 && !error ? <p className="rounded-xl border p-6 text-center text-sm text-muted-foreground">Nessun risultato.</p> : null}

      {!loading && results && total > 0 ? (
        <div className="grid gap-6 xl:grid-cols-3" data-testid="admin-result-groups">
          <ResultGroup title="Utenti" count={results.users.length}>
            {results.users.length === 0 ? <p className="text-sm text-muted-foreground">Nessun utente.</p> : results.users.map((result) => <UserCard key={result.id} result={result} onReports={onReports} />)}
          </ResultGroup>
          <ResultGroup title="Annunci" count={results.listings.length}>
            {results.listings.length === 0 ? <p className="text-sm text-muted-foreground">Nessun annuncio.</p> : results.listings.map((result) => <ListingCard key={result.id} result={result} onReports={onReports} />)}
          </ResultGroup>
          <ResultGroup title="Ordini" count={results.orders.length}>
            {results.orders.length === 0 ? <p className="text-sm text-muted-foreground">Nessun ordine.</p> : results.orders.map((result) => <OrderCard key={result.id} result={result} onDisputes={onDisputes} />)}
          </ResultGroup>
        </div>
      ) : null}
    </div>
  );
};
