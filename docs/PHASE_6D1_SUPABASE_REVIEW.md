# Fase 6d-1 — Revisione Supabase sul database reale

Data della verifica: 29 luglio 2026  
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

### Griglia originale aggiornata

- 33 test superati;
- 0 test falliti;
- nessuna fixture residua.

Le attese sono state aggiornate perché:

- il messaggio delle RPC copre ora qualsiasi annuncio non terminale;
- una bottiglia ceduta non è più leggibile nella cantina del venditore.

### Regressione follow-up

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

## Nota sull'atomicità del SQL Editor

Non bisogna basare l'atomicità sull'assunzione che il SQL Editor invii sempre
un intero file come un'unica simple query. Le migrazioni definitive devono
essere applicate con la CLI o con il sistema di migrazioni, che gestisce
transazione e cronologia. L'idempotenza resta una protezione utile, ma non
sostituisce un processo di deploy riproducibile.

## Stato finale

La Fase 6d-1 è verificata sul database collegato. Non rende l'intero progetto
production-ready: pagamenti, ordini, messaggi, moderazione e AI appartengono
alle fasi successive.
