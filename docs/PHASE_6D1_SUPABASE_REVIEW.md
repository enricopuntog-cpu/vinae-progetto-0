# Fase 6d-1 — Revisione Supabase sul database reale

Data della verifica iniziale: 29 luglio 2026

Ultimo riesame: 30 luglio 2026

Progetto Supabase: `pijnmcllmfgjmgsvtcej` (`vinea wine club`)

Branch Git: `hardening/phase-6d-1-security-invariants`

## Esito

La migrazione originale `20260729230000_security_invariants.sql` era già
presente nello schema del database, contrariamente a quanto indicato nel
riepilogo precedente, ma non era registrata nella cronologia delle migrazioni.

La struttura iniziale era valida nelle sue scelte principali, ma non chiudeva
tutta la superficie di sicurezza dichiarata. Sono state applicate due
migrazioni additive, senza modificare retroattivamente il file già eseguito:

- `20260729234500_security_invariants_followup.sql`;
- `20260729235500_security_helper_invoker.sql`.

La cronologia del database è stata riallineata ai tre nomi presenti nel
repository:

| Versione | Nome |
| --- | --- |
| `20260729230000` | `security_invariants` |
| `20260729234500` | `security_invariants_followup` |
| `20260729235500` | `security_helper_invoker` |

## Riesame del 30 luglio 2026: deriva remota

Le tre versioni risultano ancora registrate, ma il catalogo attivo non
corrisponde più allo stato finale del follow-up:

- `bottiglia_apri` e `bottiglia_cancella` sono tornate alle definizioni base:
  non leggono `ceduta_at`, controllano soltanto annunci `attivo`/`riservato` e
  hanno `search_path = public`;
- `listings_bottiglia_idonea` non verifica
  `listings.seller_id = bottle_units.owner_id` ed è tornata
  `SECURITY DEFINER` con `search_path = public`;
- `listings_marca_bottiglia_ceduta` valorizza `ceduta_at`, ma non elimina lo
  slot, ed è tornata `SECURITY DEFINER` con `search_path = public`;
- `user_roles_select_own` usa di nuovo `user_id = auth.uid()`.

Il trigger speculare `bottle_units_preserva_annuncio_non_terminale`, i tre
trigger registrati e gli helper della migrazione `20260729235500` sono invece
presenti nella forma attesa. La combinazione dimostra una **deriva delle
definizioni**, non una migration history mancante: porzioni della migrazione
base sono state riapplicate o ripristinate dopo il follow-up, senza un replay
coerente della cronologia. I cataloghi PostgreSQL non permettono di attribuire
con certezza quale operazione o strumento abbia eseguito la sovrascrittura.

È stata preparata, ma **non applicata**, la migrazione additiva:

- `20260730153957_security_invariants_remote_drift_repair.sql`.

La repair non modifica dati applicativi, ripristina le quattro funzioni e la
policy, rende espliciti `search_path` e privilegi e può essere riapplicata in
sicurezza. Richiede approvazione esplicita in sessione prima del deploy remoto.

## Cosa era corretto

- indice univoco sugli annunci non terminali per singola bottiglia;
- controllo server-side della maggiore età nel flusso di pubblicazione;
- RPC atomiche per creazione, pubblicazione, apertura e rimozione;
- proiezioni pubbliche a elenco chiuso per annunci e bottiglie;
- rimozione dell'accesso diretto anonimo alle tabelle private;
- separazione fra stato fisico della bottiglia e stato dell'annuncio;
- test nel ruolo `anon`, necessari per verificare realmente la quantità
  calcolata attraverso la catena delle viste;
- istruzioni ri-eseguibili per colonne, indici, trigger e policy.

## Problemi trovati e corretti

### Privilegi delle funzioni

Revocare `EXECUTE` da `PUBLIC` non era sufficiente: i privilegi predefiniti del
progetto avevano già creato grant espliciti per `anon` e `authenticated`.

Correzioni:

- nessuna funzione `SECURITY DEFINER` è più eseguibile da `anon`;
- gli helper e i trigger non sono più chiamabili direttamente dai ruoli client;
- solo otto RPC applicative restano eseguibili da `authenticated`;
- `has_role`, `cellar_ambiente_e_mio` e `cellar_modulo_e_mio` ora sono
  `SECURITY INVOKER`;
- i privilegi predefiniti delle nuove funzioni sono stati irrigiditi.

### Integrità bottiglia–annuncio

Il controllo iniziale agiva soltanto quando cambiava un annuncio. Un aggiornamento
server-side diretto della bottiglia poteva quindi lasciare una bozza o un
annuncio in revisione collegati a una bottiglia aperta, cancellata o ceduta.

Correzioni:

- trigger speculare su `bottle_units`;
- blocco per tutti gli stati non terminali:
  `bozza`, `in_revisione`, `modifiche_richieste`, `attivo`, `riservato`;
- verifica obbligatoria `seller_id = owner_id`;
- una bottiglia ceduta non può essere aperta, rimossa o ricollocata.

### Vendita conclusa

La vendita valorizzava `ceduta_at`, ma non liberava l'eventuale posizione fisica.

Correzione:

- la transizione a `venduto` valorizza `ceduta_at` in modo idempotente e
  rimuove lo slot della bottiglia.

### Privacy e RLS

Correzioni:

- le unità cedute non compaiono più nella cantina del precedente proprietario;
- `has_role` risponde soltanto per l'utente corrente;
- le policy usano la forma `(select auth.uid())`;
- le policy staff sul catalogo sono separate per `INSERT`, `UPDATE` e `DELETE`;
- è stata eliminata la policy Storage che consentiva di elencare tutto il
  bucket pubblico degli annunci;
- è stato aggiunto l'indice della chiave esterna
  `listings.stato_aggiornato_da`.

## Test eseguiti

### Stato corrente del riesame

I risultati remoti comunicati e usati come baseline della repair sono:

- griglia principale: **31 PASSA, 2 FALLISCE**;
- griglia follow-up: **7 PASSA, 4 FALLISCE**;
- fixture utente residue: **0**.

Le sei anomalie corrispondono alle cinque definizioni derivate elencate sopra.
Le query read-only di preflight rieseguite il 30 luglio restituiscono zero per:

- annunci non terminali duplicati;
- annunci non terminali con bottiglia non idonea o proprietario discordante;
- slot su bottiglie cancellate o cedute;
- utenti di test residui.

La Fase 6d-1 non è conclusa finché, dopo l'applicazione approvata della repair,
le due griglie non restituiscono rispettivamente **33/33** e **11/11**.

### Esito storico del 29 luglio — griglia originale

- 33 test superati;
- 0 test falliti;
- nessuna fixture residua.

Le attese sono state aggiornate perché:

- il messaggio delle RPC copre ora qualsiasi annuncio non terminale;
- una bottiglia ceduta non è più leggibile nella cantina del venditore.

### Esito storico del 29 luglio — regressione follow-up

File: `supabase/tests/6d-1_followup_invarianti.sql`

- 11 test superati;
- 0 test falliti.

Copertura:

- blocco di apertura e rimozione con annuncio in bozza;
- protezione bidirezionale tramite trigger;
- rifiuto del mismatch venditore/proprietario;
- impossibilità di enumerare il ruolo di un altro utente;
- cessione e liberazione dello slot;
- esclusione RLS della bottiglia ceduta;
- blocco di apertura, cancellazione e posizionamento dopo la vendita.

### Controlli statici sul database

| Controllo | Risultato |
| --- | ---: |
| Fixture utente residue | 0 |
| Funzioni `SECURITY DEFINER` eseguibili da anon | 0 |
| Helper RLS ancora `SECURITY DEFINER` | 0 |
| RPC applicative abilitate per authenticated | 8 |
| Duplicati di annunci non terminali | 0 |
| Annunci non terminali con bottiglia non idonea | 0 |
| Mismatch venditore/proprietario | 0 |
| Slot collegati a bottiglie cancellate o cedute | 0 |

## Advisor Supabase

### Riesame corrente

Prima della repair gli advisor riportano:

- `auth_rls_initplan` su `user_roles_select_own`, direttamente causato dal
  ritorno a `auth.uid()` senza `select`;
- le due viste `public_listings` e `public_bottle_units` come
  `security_definer_view`;
- le otto RPC applicative come funzioni `SECURITY DEFINER` eseguibili da
  `authenticated`;
- **Leaked Password Protection** disabilitata;
- indici non ancora usati su un database privo di traffico rappresentativo.

Il primo avviso deve sparire dopo la repair. Gli advisor Security e Performance
devono essere rieseguiti dopo il deploy; non sono ancora un esito finale.

### Eccezioni accettate e documentate

`public_listings` e `public_bottle_units` sono viste con privilegi del
proprietario. Sono proiezioni a colonne esplicite, hanno
`security_barrier = true` e non concedono accesso alle tabelle sottostanti.

La scelta è intenzionale: una vista `security_invoker` non potrebbe mostrare le
righe pubbliche senza concedere anche accesso alle colonne private della stessa
tabella. Deve essere rivalutata prima del cutover finale, ma non va
"corretta" automaticamente soltanto per spegnere il lint.

Le otto RPC applicative restano `SECURITY DEFINER` perché realizzano
transizioni atomiche che i client non possono eseguire con aggiornamenti
diretti. Ognuna verifica `auth.uid()`, proprietà e stato e usa
`search_path = ''`.

### Azioni ancora aperte

- abilitare **Leaked Password Protection** dalla configurazione Supabase Auth
  prima della beta pubblica;
- riesaminare gli indici segnalati come inutilizzati dopo avere traffico
  rappresentativo. Il database è nuovo: rimuoverli ora sarebbe prematuro;
- automatizzare queste griglie in CI con un database Supabase effimero.

## Rischi e rollback della repair

La repair non contiene DML applicativo. I rischi operativi sono limitati ai
lock DDL brevi necessari per sostituire funzioni, ricreare due trigger e
ricreare una policy; il deploy va comunque eseguito in una finestra controllata
e seguito immediatamente dalle verifiche.

Se la migrazione fallisce dentro il sistema di migrazioni, la transazione deve
essere lasciata in rollback e non va registrata manualmente come applicata. Se
un problema emerge dopo il commit, il rollback non richiede bonifica dati:
le definizioni precedenti sono già state catturate con `pg_get_functiondef` e
`pg_policies`. Ripristinarle riaprirebbe però le vulnerabilità note, quindi la
strategia preferita è una correzione **roll-forward**. Un eventuale rollback
d'emergenza deve essere una nuova migrazione limitata alle quattro definizioni
e alla policy catturate; non si deve modificare né rieseguire integralmente una
migrazione storica.

## Nota sull'atomicità del SQL Editor

Non bisogna basare l'atomicità sull'assunzione che il SQL Editor invii sempre
un intero file come un'unica simple query. Le migrazioni definitive devono
essere applicate con la CLI o con il sistema di migrazioni, che gestisce
transazione e cronologia. L'idempotenza resta una protezione utile, ma non
sostituisce un processo di deploy riproducibile.

## Stato finale

La repair è pronta per revisione locale, ma non è stata applicata al database
collegato. La Fase 6d-1 resta **aperta**: non va dichiarata conclusa e non si
avvia la Fase 6d-2 o la Fase 7 finché deploy approvato, 33/33, 11/11, preflight,
assenza di fixture e advisor riesaminati non sono tutti documentati.
