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
- La 6d-1 è in `main` tramite PR #14; il branch di verifica post-merge registra
  33/33, 11/11, verifier storico 13/13 e residui fixture zero.
- Il merge non equivale ad autorizzazione o prova delle fixture remote.
- La Fase 6d-2a è in `main` tramite PR #17 al merge squash `3037bf4`; lo smoke
  Storage del bucket `cantina` non è compreso nel merge e resta aperto.
- La Fase 7 è in `main` tramite PR #18 al merge squash `2a47952`, la Fase 7b
  tramite PR #19 al merge squash `5e6b8e4`.
- «Integrata» qui significa anche «distribuita»: l'integrazione GitHub di
  Supabase applica migrazioni e Edge Function al merge su `main`, da sola.
  Verificato in lettura il 4 agosto 2026 — entrambe le migrazioni sono a ledger
  (diciassette righe) e `payments-checkout`, `connect-onboarding` e
  `payouts-release` sono `ACTIVE`. Il contenuto applicato è quello a netto
  garantito, non la prima bozza a percentuale piatta.
- «Distribuita» non significa «percorsa», ed è questa la distinzione da tenere:
  le tabelle di denaro sono a **zero righe**, `marketplace_config` ha la sola
  riga iniziale, nessun percorso UI raggiunge onboarding, checkout, conferma o
  contestazione, `PAYMENTS_ENABLED` resta `false` e nessuna chiamata a Stripe è
  mai stata fatta, nemmeno in test mode. Dettaglio in
  [`../docs/ROADMAP_V1.md`](../docs/ROADMAP_V1.md), sezione «Distribuita non
  vuol dire percorsa».
- La migrazione di Fase 7b **dipende** da quella di Fase 7: sul progetto reale
  l'ordine è stato rispettato dalle versioni, ma in qualsiasi ambiente nuovo
  applicarla per prima fallisce, perché estende tabelle e RPC che l'altra crea.
- Il ruolo `seller_enabled` ha una sorgente autoritativa dalla 7b, ma il gate
  sulla creazione di annunci è deliberatamente spento.
- Le fasi 8–11 non sono iniziate.
- La vecchia app resta quella servita.
- Auth reale e ruoli demo coesistono intenzionalmente.
- Facebook OAuth non è “da finire nel codice”: è disabilitato per un problema
  di configurazione/provider esterno.

## Se il lavoro riguarda Supabase

1. Leggere integralmente la skill Supabase disponibile nell'ambiente.
2. Leggere le migrazioni precedenti del dominio.
3. Trattare lo schema remoto come dato esterno da verificare, non come
   identico al repository.
4. Preparare una nuova migrazione additiva. Un file già pushato almeno una
   volta non si modifica più in place, nemmeno in bozza e nemmeno se nessun
   database reale lo ha eseguito: vale la regola 11 di
   [`03_ARCHITETTURA_REGOLE_DEBITI.md`](03_ARCHITETTURA_REGOLE_DEBITI.md).
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
- Per la 6d-2a verificare anche 33/33, 11/11, 13/13 e residui fixture zero.
- Creare un branch dedicato partendo da `main` aggiornato.
- Non portare due fasi avanti insieme sullo stesso dominio.
- Definire parità e fuori-scope prima di scrivere codice.
- A ogni checkpoint eseguire lint/typecheck/test/build pertinenti.
- Fare commit piccoli e descrittivi.
- Aprire una PR draft; non fare merge autonomamente.

## Handoff specifico alla Fase 6d-2a

La Fase 6d-2a deve:

- distinguere in modo autoritativo il catalogo curato dallo staff dai vini
  inseriti dagli utenti;
- separare aggiunta privata, aggiunta pubblica e vendita da bottiglia esistente;
- rendere atomica la creazione dell'ambiente e del modulo iniziale;
- collegare alla home soltanto dati reali della Cantina;
- preservare gli invarianti, i privilegi e le viste chiuse introdotti dalla
  6d-1;
- fermarsi prima di qualsiasi SQL remoto e chiedere conferma esplicita.

Il gate post-merge 6d-1 è stato documentato e approvato, e la fase è stata
consegnata: questo elenco resta come descrizione di ciò che la 6d-2a ha dovuto
garantire, non come lavoro da avviare.

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

La fase è integrata e copre schema, rate limiting condiviso, Edge Function,
webhook, adapter e il trasferimento della proprietà al compratore tramite
`orders.buyer_bottle_unit_id`. Questo elenco resta come descrizione di ciò che
la Fase 7 ha dovuto garantire, non come lavoro da avviare.

## Handoff specifico alla Fase 7b

La Fase 7b è integrata. Ciò che una nuova chat deve sapere prima di toccarne il
codice:

- la commissione è un rincaro a netto garantito, non una percentuale scelta, e
  la formula vive in `private.marketplace_totale_cents` e in nessun altro posto;
- sull'ordine sono congelati i tre parametri oltre al risultato: un ordine
  vecchio deve restare spiegabile dopo che la configurazione è cambiata;
- i fondi restano alla piattaforma perché l'addebito non porta `transfer_data`
  né `on_behalf_of`. Aggiungerli spegnerebbe l'intera trattenuta senza che
  nessun test lo dica;
- la fee davvero trattenuta si misura e non decide nulla;
- il gate `seller_enabled` sulla creazione di annunci è spento di proposito.

## Gate chiusi dal merge, non da un'autorizzazione

`apply_migration` di Fase 7 e Fase 7b e il deploy delle tre Edge Function erano
elencati qui come gate aperti. Non lo sono più, e nessuno li ha autorizzati: li
ha chiusi il merge, tramite l'integrazione GitHub. Il riallineamento dei filename
cade con loro, perché le versioni a ledger coincidono già con i nomi dei file.

## Gate ancora aperti, in ordine

1. esecuzione delle griglie `7_ordini_pagamenti.sql` (16 casi) e
   `7b_connect_marketplace.sql` (23 casi), che creano e cancellano fixture
   remote e richiedono un'autorizzazione esplicita;
2. decidere dove sta il gate di autorizzazione, dato che la regola scritta
   presidia `supabase db push` e il percorso reale è il merge su `main`;
3. smoke Storage del bucket `cantina`, aperto dalla 6d-2a e indipendente.

Nessuno dei tre è autorizzato.

## Cosa aggiornare alla fine di una fase

- `CHANGES.log`, con le quattro intestazioni esatte e `NEXT STEPS` a tre voci;
- `docs/ROADMAP_V1.md`;
- `docs/MIGRATION_PHASE_1_BACKLOG.md`;
- documenti di sicurezza/ambiente se toccati;
- questa cartella:
  - stato attuale;
  - storia della fase;
  - indice PR;
  - `context-manifest.json`.
