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
- La Fase 6d-2a è in `main` tramite PR #17 al merge squash `3037bf4`. Lo smoke
  Storage del bucket `cantina` non era compreso nel merge ed è stato **chiuso il 5
  agosto 2026** con la Fase 7e, in dieci passi tutti con l'esito atteso. La
  **griglia** 6d-2a resta invece non eseguita: sono due cose diverse.
- **Una griglia versionata e mai eseguita non è una prova.** La 7e l'ha misurato:
  la griglia 7c era rotta in quattro punti, nessuno visibile leggendo il file, e non
  poteva committare in nessuno scenario. Alla prima esecuzione reale ha dato 21
  PASSA e 1 FALLISCE, e quel FALLISCE era un difetto della migrazione con una
  conseguenza sul denaro. Vale per ogni griglia ancora senza esito.
- La Fase 7f ha corretto quel difetto e la griglia 7c ora dà **22 PASSA / 0
  FALLISCE** sul progetto reale, residui a zero su 26 controlli. La regola di tipo che
  ne deriva è al capitolo «Regole di tipo che hanno già rotto il denaro una volta» di
  [`03_ARCHITETTURA_REGOLE_DEBITI.md`](03_ARCHITETTURA_REGOLE_DEBITI.md), e va letta
  prima di scrivere qualunque `update` verso una colonna enum.
- **Il gestore `exception when others` di una griglia non conserva gli esiti già
  registrati.** Un blocco PL/pgSQL con clausola `exception` è una sottotransazione:
  catturare l'errore annulla tutto ciò che il blocco ha scritto, la tabella degli
  esiti compresa. Misurato: 1 riga superstite contro 4 con la guardia dentro il caso.
  Chi aggiunge robustezza a una griglia deve metterla **per caso**, con la
  registrazione fuori dalla sottotransazione. La 7c è fatta così; la 7b non ancora.
- La Fase 7 è in `main` tramite PR #18 al merge squash `2a47952`, la Fase 7b
  tramite PR #19 al merge squash `5e6b8e4`, la Fase 7c tramite PR #21 al merge
  squash `471b529`, la Fase 7d tramite PR #22 al merge squash `306952f`, la
  correzione di `ARCHITECTURE.md` tramite PR #24 al merge squash `d8503af`, la
  Fase 7e tramite PR #23 al merge squash `6b5b219`, la Fase 7f tramite PR #25 al
  merge squash `491e10d` e la Fase 7g tramite PR #26 al merge squash `f9c53e0`.
  La Fase 8 è nella draft PR #27; la Preview `jggjaqcdbcbxdxhnggio` è verde e
  ha superato griglie 20/20 e 23/23, concorrenza 5/5 e cleanup a zero. Produzione
  resta alla Fase 7f.
- «Integrata» qui significa anche «distribuita»: l'integrazione GitHub di
  Supabase applica migrazioni e Edge Function al merge su `main`, da sola.
  Verificato in lettura il 5 agosto 2026 — il ledger è a **diciannove righe**, le
  migrazioni di 7, 7b e 7c ci sono tutte, e `payments-checkout`,
  `connect-onboarding` e `payouts-release` sono `ACTIVE`. Il contenuto applicato è
  quello a netto garantito, non la prima bozza a percentuale piatta. La
  diciannovesima riga appartiene alla Fase 7f, ora in `main`: è l'unica
  applicata per via diretta e non dal merge.
- La Fase 7d **non ha scritto SQL**: ha chiuso decisioni. Le sue conseguenze
  vincolanti sono al capitolo dedicato di
  [`03_ARCHITETTURA_REGOLE_DEBITI.md`](03_ARCHITETTURA_REGOLE_DEBITI.md) —
  scheduler esterno e non `pg_cron`, scheduler acceso prima dei pagamenti,
  «protezione» fuori dal modello Supabase, e nessun valore nuovo in
  `public.payment_stato` per il tetto ai tentativi della fee.
- Il merge su `main` non richiede più il click manuale del committente, ma
  richiede ancora **l'approvazione esplicita in sessione**, è **solo squash**, e
  pretende come ultimo commit della PR l'aggiornamento di `CHANGES.log`,
  `CLAUDE.md` e di questa cartella allo stato che quella PR produce.
- «Distribuita» non significa «percorsa», ed è questa la distinzione da tenere:
  le tabelle di denaro sono a **zero righe**, `marketplace_config` ha la sola
  riga iniziale, nessun percorso UI raggiunge onboarding o checkout; conferma e
  contestazione hanno percorsi ordine reali. `PAYMENTS_ENABLED` resta `false` e
  nessuna chiamata a Stripe è mai stata fatta, nemmeno in test mode. Dettaglio in
  [`../docs/ROADMAP_V1.md`](../docs/ROADMAP_V1.md), sezione «Distribuita non
  vuol dire percorsa».
- La migrazione di Fase 7b **dipende** da quella di Fase 7: sul progetto reale
  l'ordine è stato rispettato dalle versioni, ma in qualsiasi ambiente nuovo
  applicarla per prima fallisce, perché estende tabelle e RPC che l'altra crea.
- Il ruolo `seller_enabled` ha una sorgente autoritativa dalla 7b, ma il gate
  sulla creazione di annunci è deliberatamente spento.
- La Fase 8 è pubblicata in draft e verificata su Preview; Dashboard Realtime,
  smoke autenticato, ready-for-review e merge restano aperti. Le fasi 9–11 non
  sono iniziate.
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

## Come creare un utente di test autenticabile (procedura verificata)

Serve per gli smoke Storage e per qualunque prova che richieda un JWT reale. La
via dell'API Auth **non funziona su questo progetto**: il limite dell'SMTP
incorporato è project-wide e produce un `429` che né il piano né un IP diverso
spostano. La via che ha funzionato il 5 agosto 2026, senza `service_role` e senza
SMTP proprio:

1. `insert into auth.users` con
   `encrypted_password = extensions.crypt('…', extensions.gen_salt('bf'))` —
   `pgcrypto` sta nello schema `extensions`, non in `public` — ed
   `email_confirmed_at = now()`;
2. `POST /auth/v1/token?grant_type=password` con la sola chiave pubblica. Non
   spedisce email, quindi non incontra il limite SMTP.

**Due cose non ovvie, scoperte eseguendo e non ragionando.** Senza di esse il primo
tentativo risponde `500 unexpected_failure`, e la causa esatta arriva dai log di
Auth, non da un'ipotesi:

- serve **una riga in `auth.identities`**. I 5 utenti reali del progetto ne hanno
  una, quelli creati in SQL no, e senza di essa GoTrue non autentica;
- le quattro colonne token `confirmation_token`, `recovery_token`,
  `email_change_token_new` ed `email_change` vanno messe a **stringa vuota, non a
  `NULL`**: sono `varchar(255)` e non `text`, e GoTrue le scansiona in `string` non
  nullable.

`phone` invece **resta `NULL`**: per GoTrue è nullable e ha un indice unico che due
stringhe vuote violerebbero.

La pulizia va fatta nello stesso ordine inverso, e va verificata: dopo lo smoke del
5 agosto 2026 `auth.users`, `auth.identities` e `public.profiles` sono tornati a 5
righe, che è la linea di base reale del progetto.

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
   remote e richiedono un'autorizzazione esplicita. **Non autorizzate**:
   l'autorizzazione data per la griglia 7c non le copre, perché è per griglia e
   non per progetto;
2. decidere dove sta il gate di autorizzazione, dato che la regola scritta
   presidia `supabase db push` e il percorso reale è il merge su `main`;
3. chiudere gli ultimi gate della Fase 8: configurazione Realtime e smoke
   autenticato sulla Preview, poi approvazione distinta per ready-for-review e
   merge squash; produzione non è mai implicita.

Lo smoke Storage del bucket `cantina`, che questo elenco portava come terza voce,
è stato eseguito e chiuso il 5 agosto 2026; la sua registrazione arriva con la
PR #23.

## Cosa aggiornare alla fine di una fase

Non «alla fine»: **prima del merge**, come ultimo commit della PR. Dopo lo squash
il branch non c'è più e l'aggiornamento richiederebbe una PR a parte.

- `CHANGES.log`, con le quattro intestazioni esatte e `NEXT STEPS` a tre voci;
- `CLAUDE.md`, se la fase ha prodotto regole o invarianti vincolanti;
- `docs/ROADMAP_V1.md`;
- `docs/MIGRATION_PHASE_1_BACKLOG.md`;
- documenti di sicurezza/ambiente se toccati;
- questa cartella:
  - stato attuale;
  - storia della fase;
  - indice PR;
  - `context-manifest.json`.

Con i fatti veri di quella PR — numero, cosa cambia, cosa resta aperto — non con
un riassunto generico.
