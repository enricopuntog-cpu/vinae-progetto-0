# Fase 7 — verifica del checkpoint locale

Data: 31 luglio 2026. Branch: `migration/phase-7-order-payment-service`.

## Riconciliazione iniziale

- `origin/main` verificato a `3037bf4f8fa5269895bb01a998d85bb5f629cd34`.
- PR #17 verificata come squash-merge; i tre job GitHub Actions risultavano verdi.
- Migration history Supabase letta senza scritture: ultima versione remota
  `20260731120340 catalog_cellar_paths`.
- Nessun SQL remoto, fixture SQL, deploy Edge Function o chiamata Stripe è stato eseguito.

## Smoke Storage autorizzato

Lo smoke non è stato avviato. La sessione del browser Supabase è stata
reindirizzata alla pagina di login, quindi non era disponibile un percorso Auth
Admin/API per eliminare con certezza i due utenti tecnici al termine. Creare gli
utenti con la sola chiave publishable avrebbe violato il requisito di cleanup
totale. Non sono stati creati utenti, oggetti o URL firmati e non è stata fatta
alcuna serie di retry; lo stato del precedente limite Auth non è quindi stato
misurato.

Per riprendere: autenticare la dashboard, eseguire una singola registrazione e,
se risponde `429`, fermarsi. Se riesce, completare upload PNG nel bucket privato
`cantina`, lettura owner, signed URL, rifiuto della lettura diretta con il secondo
JWT, quindi eliminare oggetto e utenti via API amministrativa.

## Verifiche locali

| Controllo | Esito |
|---|---|
| `bun test` | 10 test passati, 0 falliti |
| `bun run typecheck` | passato |
| `bun run lint` | 0 errori; 23 warning preesistenti fuori dalla verticale |
| `bun run build` | passato; Route Handler webhook incluso |
| `git diff --check` | passato |

Docker e Deno non sono disponibili in questa postazione, quindi la migrazione
non è stata applicata a un database locale e la Edge Function non è stata
eseguita. Il deploy successivo deve prima validare la migrazione su un ambiente
isolato, controllare advisor RLS/performance, verificare i grant Data API e solo
poi configurare segreti e Stripe test mode.

## Gate prima di qualunque ambiente remoto

1. Approvazione esplicita separata per applicare la migrazione SQL.
2. Verifica che la versione assegnata dal server coincida con il filename locale
   e nuova lettura della migration history.
3. Approvazione esplicita separata per distribuire `payments-checkout`.
4. `PAYMENTS_ENABLED=false` durante migrazione, deploy e smoke tecnico.
5. Stripe esclusivamente in test mode; nessun pagamento reale e nessun payout.
