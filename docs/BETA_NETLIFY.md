# Beta `frontend-next` su Netlify

## Scopo

Questa configurazione pubblica una beta separata e non sostituisce il servizio
legacy in `frontend/` e `backend/`. La beta espone le interfacce IA, checkout e
spedizione fino ai rispettivi confini fail-closed, senza eseguire azioni esterne.

## Stato remoto verificato il 16 agosto 2026

- PR: [#44](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/44),
  pronta e non draft, base `f3f0155`, HEAD pre-documentazione `84b8767`;
- CI: run `31946914430` (#152), conclusione `success`;
- progetto Netlify Free: `timely-lokum-43a12e`, visibilità pubblica per
  produzione e Deploy Preview;
- Deploy Preview: `6a81acfbee2b64c77b28addc`, URL
  `https://deploy-preview-44--timely-lokum-43a12e.netlify.app`;
- redirect Auth temporaneo consentito:
  `https://deploy-preview-44--timely-lokum-43a12e.netlify.app/auth/callback`;
- `AI_ENABLED=false` e `PAYMENTS_ENABLED=false` verificati nei secret delle
  Edge Function Supabase;
- nessun service role, segreto IA o Stripe configurato su Netlify.

La produzione Netlify non contiene ancora la PR #44. Il sito legacy resta
servito e non è stato eseguito alcun cutover.

## Build versionata

Il file `netlify.toml` alla radice imposta:

- base directory `frontend-next`;
- comando `bun run build`;
- publish directory `.next`;
- Bun `1.3.14`;
- Node.js `22`, compatibile con il requisito `>=20.9.0` di Next.js `16.2.12`.

Il runtime `Next.js` è configurato nelle Build settings di Netlify e viene
gestito dal suo adapter OpenNext. Il primo preview, privo del runtime, caricava
la `.next` grezza e restituiva 404; dopo aver impostato il runtime e ripetuto il
deploy senza cache, il preview è diventato operativo. Non si fissa manualmente
`@netlify/plugin-nextjs`.
I metadata usano la variabile Netlify riservata `URL` come base canonica e
ricadono su `http://localhost:3000` fuori dalla piattaforma.

## Matrice applicata

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

## Superfici pubbliche verificate

- Proposte: lettura e invio passano da `proposal-service` e dalle RPC Phase 7.
- Richiesta foto: apre una conversazione Phase 8 e invia un messaggio reale;
  la navigazione avviene soltanto dopo entrambi gli esiti positivi.
- Home: nome, cantina, annunci e notifiche derivano dalla sessione e dai dati
  canonici; nessuna identità o attività personale è precompilata.
- Segnalazioni, ordini, cantina, messaggi e notifiche non hanno un fallback
  pubblico su store locali.
- Preferiti, follow venditore, Club/community, promemoria, preferenze e sfondi
  cantina non persistiti e punti logistici dimostrativi sono rimossi o non
  raggiungibili.

Le tre interfacce IA restano visibili con il gate azioni spento e mostrano un
avviso senza costruire il client IA. Il checkout conserva nel solo stato del
flusso indirizzo, consegna, imballaggio e metodo scelti; il comando finale si
ferma prima del servizio pagamenti. Le funzioni logistiche esterne mostrano il
blocco beta e non producono etichette, prenotazioni o tracking.

## Configurazione remota applicata al preview

Il sito è collegato a `enricopuntog-cpu/vinae-progetto-0`, base
`frontend-next`, branch di produzione `main`, Deploy Preview attivi per le PR
verso `main`. Netlify contiene le variabili pubbliche
`NEXT_PUBLIC_SUPABASE_URL` e `NEXT_PUBLIC_SUPABASE_ANON_KEY` senza che i valori
siano documentati, più la matrice precedente. Le variabili `NEXT_PUBLIC_*`
sono pubbliche per definizione; non autorizzano chiamate e non sostituiscono i
gate server.

Gli smoke desktop e mobile 390×844 hanno verificato home, catalogo reale,
annuncio reale, route private in stato anonimo, callback senza codice e 404 di
`/community`, senza errori console bloccanti o overflow. Il Sommelier e gli
abbinamenti mostrano l'avviso beta prima del client IA; i log Edge Function non
mostrano chiamate `ai-*`, pagamenti o Stripe. Gli smoke autenticati reali sono
`NON ESEGUITO`: non sono state create credenziali, fixture o ruoli.

Dopo il merge restano due operazioni Auth atomiche: aggiungere
`https://timely-lokum-43a12e.netlify.app/auth/callback` e rimuovere esattamente
il callback temporaneo del preview. Un rollback Netlify ripristina il precedente
deploy ma non annulla eventuali dati già scritti su Supabase.

## Smoke autenticato locale

`frontend-next/scripts/beta-local-supabase-mock.ts` espone esclusivamente su
`127.0.0.1:54321` una sessione, un ruolo Admin e un annuncio deterministici.
Il mock conta separatamente ogni tentativo IA, pagamento o logistica tramite
`GET /_counts`; tutti e tre devono restare a zero. Non contiene credenziali,
non sostituisce test RLS e non deve essere usato come backend della beta.
