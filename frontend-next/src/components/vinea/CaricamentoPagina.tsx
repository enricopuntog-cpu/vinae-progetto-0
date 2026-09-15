/** Shell leggera: viene precaricata senza attendere le letture della pagina. */
export function CaricamentoPagina({ titolo }: { titolo: string }) {
  return (
    <section aria-busy="true" aria-label={titolo} className="space-y-6" data-testid="route-loading">
      <h1 className="font-serif text-3xl font-semibold text-antracite">{titolo}</h1>
      <p role="status" className="text-sm text-muted-foreground">Caricamento in corso…</p>
      <div aria-hidden="true" className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {[0, 1, 2].map((i) => (
          <div key={i} className="h-56 rounded-2xl border border-border bg-secondary/60 motion-safe:animate-pulse" />
        ))}
      </div>
    </section>
  );
}
