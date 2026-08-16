# Vinea `frontend-next`

Applicazione Next.js App Router di destinazione per la beta Vinea. Il legacy
servito resta in `frontend/` e `backend/`.

## Sviluppo locale

Richiede Bun `1.3.14` e Node.js `22` per allinearsi alla configurazione
Netlify versionata. Copiare `.env.example` in `.env.local` senza inserire
segreti nel repository, quindi eseguire:

```bash
bun install --frozen-lockfile
bun run dev
```

Verifiche locali:

```bash
bun run lint
bun run typecheck
bun test
bun run build
```

## Beta fail-closed

La matrice e i confini operativi sono documentati in
`../docs/BETA_NETLIFY.md` e `../docs/ENVIRONMENT.md`. Le superfici IA e il
checkout possono essere visibili, ma azioni IA, pagamento finale e operazioni
logistiche restano bloccati prima di qualunque provider. Le variabili
`NEXT_PUBLIC_*` non sono autorizzazioni e non devono contenere segreti.

Nessun deploy, modifica Supabase, configurazione Netlify o pubblicazione viene
eseguito dai comandi locali sopra.
