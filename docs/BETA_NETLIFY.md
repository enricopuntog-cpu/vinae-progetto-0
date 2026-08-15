# Beta `frontend-next` su Netlify

## Scopo

Questa configurazione prepara una beta separata e non sostituisce il servizio
legacy in `frontend/` e `backend/`. Non crea un sito Netlify, non esegue deploy
e non modifica Supabase. La beta espone le interfacce IA, checkout e spedizione
fino ai rispettivi confini locali, senza eseguire azioni esterne.

## Build versionata

Il file `netlify.toml` alla radice imposta:

- base directory `frontend-next`;
- comando `bun run build`;
- publish directory `.next`;
- Bun `1.3.14`;
- Node.js `22`, compatibile con il requisito `>=20.9.0` di Next.js `16.2.12`.

Il runtime moderno Next.js viene rilevato automaticamente da Netlify e gestito
dal suo adapter OpenNext. Non si fissa manualmente `@netlify/plugin-nextjs`.
I metadata usano la variabile Netlify riservata `URL` come base canonica e
ricadono su `http://localhost:3000` fuori dalla piattaforma.

## Matrice futura

| Variabile | Default sicuro | Beta prevista | Destinazione |
|---|---:|---:|---|
| `NEXT_PUBLIC_AI_UI_ENABLED` | `false` | `true` | build + runtime Next |
| `NEXT_PUBLIC_AI_ACTIONS_ENABLED` | `false` | `false` | build + runtime Next |
| `AI_ENABLED` | `false` | `false` | Edge Function Supabase |
| `NEXT_PUBLIC_PHASE_7_PAYMENTS_ENABLED` | `false` | `true` | build + runtime Next |
| `NEXT_PUBLIC_PAYMENT_ACTIONS_ENABLED` | `false` | `false` | build + runtime Next |
| `PAYMENTS_ENABLED` | `false` | `false` | Edge Function/Route Handler |
| `NEXT_PUBLIC_PACKAGING_ENABLED` | `false` | `true` | build + runtime Next |
| `PACKAGING_ENABLED` | `false` | `false` | server |
| `NEXT_PUBLIC_DEMO_UI_ENABLED` | `false` | `false` | build + runtime Next |

Le variabili `NEXT_PUBLIC_*` sono visibili nel browser e regolano soltanto
l'esperienza utente. I gate server restano autoritativi e fail-closed.

## Configurazione remota futura

Prima di qualsiasi deploy autorizzato servono, come gate distinti:

1. creare il sito su sottodominio `netlify.app` e collegare il solo target
   `frontend-next`;
2. impostare URL e chiave publishable Supabase nei contesti Build e Functions,
   senza inserire mai service role o segreti nel repository;
3. aggiungere l'URL beta alle redirect URL di Supabase Auth;
4. applicare la matrice precedente lasciando azioni IA, pagamenti e packaging
   reali spente;
5. verificare `noindex,nofollow`, Auth e rollback prima della pubblicazione.

Le Edge Function, i secret e le allowlist non vengono configurati da questo
checkpoint. Un rollback Netlify ripristina il precedente deploy ma non annulla
eventuali dati già scritti su Supabase.

## Smoke autenticato locale

`frontend-next/scripts/beta-local-supabase-mock.ts` espone esclusivamente su
`127.0.0.1:54321` una sessione, un ruolo Admin e un annuncio deterministici.
Il mock conta separatamente ogni tentativo IA, pagamento o logistica tramite
`GET /_counts`; tutti e tre devono restare a zero. Non contiene credenziali,
non sostituisce test RLS e non deve essere usato come backend della beta.
