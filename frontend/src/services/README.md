# Services layer

Interfacce TypeScript per i futuri servizi backend. Nessuna implementazione reale:
la demo continua a leggere/scrivere via `src/lib/vinea-store.tsx` (stato locale)
e i mock in `src/data/`.

Quando si migrerà a Next.js + Supabase, ogni interfaccia qui otterrà due
implementazioni:

- `*.mock.ts` — legge da mock (già usata dalla demo)
- `*.supabase.ts` — chiama Supabase / Edge Functions

I componenti dipendono solo dall'interfaccia, mai dall'implementazione.
Vedi `docs/BACKEND_CONTRACTS.md`.
