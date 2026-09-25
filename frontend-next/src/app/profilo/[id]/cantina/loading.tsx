export default function Loading() {
  return (
    <div className="mx-auto max-w-5xl space-y-8" aria-busy="true" aria-label="Caricamento Cantina pubblica">
      <div className="h-44 animate-pulse rounded-3xl border border-border bg-card" />
      <div className="space-y-5">
        <div className="h-16 animate-pulse rounded-2xl bg-muted" />
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: 6 }, (_, indice) => (
            <div key={indice} className="h-80 animate-pulse rounded-2xl border border-border bg-card" />
          ))}
        </div>
      </div>
    </div>
  );
}
