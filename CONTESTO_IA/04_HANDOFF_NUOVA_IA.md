# Handoff operativo per una nuova IA

## Prompt iniziale consigliato

> Lavora sul repository Vinea. Prima di proporre modifiche leggi
> `AGENTS.md`, poi tutti i file in `CONTESTO_IA/` nell'ordine indicato dal
> README, quindi verifica con Git lo stato corrente. Non assumere che
> `frontend-next/` sia in produzione. Non toccare `main`, non applicare
> migrazioni Supabase remote senza mostrare l'SQL e ottenere conferma
> esplicita, non iniziare una fase successiva senza approvazione. Conserva le
> modifiche locali non tue.

## Checklist prima di lavorare

1. Leggere `AGENTS.md` se presente.
2. Leggere `CONTESTO_IA/README.md` e i file successivi.
3. Eseguire:

   ```powershell
   git status --short --branch
   git remote -v
   git log --oneline --decorate -20
   git diff --stat origin/main...HEAD
   ```

4. Controllare `docs/ROADMAP_V1.md` e il ticket della fase nel backlog.
5. Identificare la versione da modificare:
   - bug dell'app servita: `frontend/` o `backend/`;
   - lavoro di migrazione approvato: `frontend-next/` o `supabase/`.
6. Cercare modifiche locali non proprie e non sovrascriverle.
7. Verificare che il branch non sia `main`.

## Stato da non reinterpretare

- La Fase 4 è assorbita nella Fase 3.
- Le fasi 6a, 6b, 6c-1, 6c-2 sono sotto-fasi deliberate, non duplicati di
  prodotto.
- La 6d-1 non è ancora in `main`.
- Le fasi 7–11 non sono iniziate.
- La vecchia app resta quella servita.
- Auth reale e ruoli demo coesistono intenzionalmente.
- Facebook OAuth non è “da finire nel codice”: è disabilitato per un problema
  di configurazione/provider esterno.

## Se il lavoro riguarda Supabase

1. Leggere integralmente la skill Supabase disponibile nell'ambiente.
2. Leggere le migrazioni precedenti del dominio.
3. Trattare lo schema remoto come dato esterno da verificare, non come
   identico al repository.
4. Preparare una nuova migrazione additiva; non riscrivere file già applicati.
5. Aggiungere/aggiornare RLS, privilegi, test e documentazione.
6. Fermarsi prima di applicare sul progetto reale.
7. Mostrare l'SQL esatto e chiedere conferma in sessione.
8. Dopo l'applicazione, verificare cronologia migrazioni e catalogo effettivo.
9. Chiedere una conferma separata prima di test che creano/cancellano fixture.
10. Se l'API assegna la versione, riallineare il filename locale alla history.

La repair `supabase/migrations/20260730140948_security_invariants_remote_drift_repair.sql`
è stata applicata il 30 luglio 2026. La query
`supabase/tests/6d-1_remote_drift_repair_verifica.sql` restituisce 13/13
`PASSA`; le griglie `6d-1_invarianti_sicurezza.sql` e
`6d-1_followup_invarianti.sql` restano pendenti perché richiedono autorizzazione
esplicita per le fixture remote.

## Se il lavoro riguarda una nuova fase

- Accertare che la fase precedente sia integrata e approvata.
- Creare un branch dedicato partendo da `main` aggiornato.
- Non portare due fasi avanti insieme sullo stesso dominio.
- Definire parità e fuori-scope prima di scrivere codice.
- A ogni checkpoint eseguire lint/typecheck/test/build pertinenti.
- Fare commit piccoli e descrittivi.
- Aprire una PR draft; non fare merge autonomamente.

## Handoff specifico alla Fase 7

La Fase 7 deve:

- implementare ordini, proposte e pagamenti dietro le interfacce esistenti;
- ricavare prezzo, valuta, venditore e stock lato server;
- ricontrollare scadenza, stato e bottiglia nella stessa transazione;
- sapere che `listings_marca_bottiglia_ceduta` valorizza già `ceduta_at`;
- trasferire o creare correttamente l'unità del compratore senza far
  riapparire quella ceduta nella cantina del venditore;
- progettare Stripe Connect/KYC prima di denaro reale;
- colmare il rate limiting delle RPC prima di esporre pagamenti.

Non avviare questa fase finché 6d-1 e la deriva remota non sono chiuse e
approvate.

## Cosa aggiornare alla fine di una fase

- `docs/ROADMAP_V1.md`;
- `docs/MIGRATION_PHASE_1_BACKLOG.md`;
- documenti di sicurezza/ambiente se toccati;
- questa cartella:
  - stato attuale;
  - storia della fase;
  - indice PR;
  - `context-manifest.json`.
