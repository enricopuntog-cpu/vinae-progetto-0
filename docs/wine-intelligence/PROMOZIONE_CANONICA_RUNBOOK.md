# Promozione canonica — runbook del popolamento incrementale

Stato al 26 novembre 2026: **preparata e provata su dati sintetici, NON eseguita**. Regola `lwin-conservative-v1` in
bozza, promozione e proiezione OFF, 0 vini e 0 produttori canonici in Production. Questo file non autorizza nulla.

L'audit indipendente del 26/11/2026 sulla procedura di `fa88ba8` ha dato **FAIL** (F-01…F-08). La procedura qui
descritta è quella corretta (WI-009): **va rivalidata dalla sessione indipendente** prima di qualunque finestra.

File eseguibili: `tools/wine-catalog/promozione/` (`00`–`05`). Nessun nuovo motore: la promozione è
`catalog.promote_wine_candidates` (lock, ordine, idempotenza, esclusioni, alias, audit invariati).

## 1. Che cosa si approva

| Elemento | Valore (Production, 26/11/2026, dopo `db0a455`) |
|---|---|
| Regola | `lwin-conservative-v1` |
| Impronta corrente (28 funzioni + trigger) | `b87e7b516952bcd5cbda30f4779cc7c2` |
| Digest della vista dei candidati | `b352be426a3a32762fb7fa5140b7ee88` |
| Fonte | `LIVEX-LWIN7`, CC BY 4.0, `authorized` |
| Versione completa | run `1335acaa-72db-45fa-bba0-2dfdca7e545a`, 25/11/2026 20:53 UTC |
| SHA-256 del file | `7669ceab4e815716aa6c90643c117f3da7c7daeaa202ecd3f7cfbc4db7fd488e` |
| Candidati | 159.614 vini, 27.410 produttori distinti, 59 paesi |
| Alias Combined attesi | 4.206 (collegamenti: 6.219 attivi, 2 verso eliminati) |
| Esclusi (Live vino) | 26.099 con un campo essenziale mancante, 48 solo possibile duplicato |

**L'approvazione è irreversibile.** Una regola approvata è immutabile: si può solo ritirare, il ritiro è definitivo e
la sola versione implementata è la `v1`. Se dopo l'approvazione cambia una funzione o un trigger coperto
dall'impronta, la promozione si ferma e serve una migration con una nuova versione di regola. Ogni correzione alla
logica va fatta prima.

**Non esiste una procedura di annullamento** del popolamento: nessun trigger vieta di cancellare righe canoniche, ma
non c'è un percorso previsto né provato per farlo, e il registro eventi è solo in aggiunta. La protezione è la
proiezione spenta (nulla è visibile agli utenti) più un backup recente verificato prima di aprire la finestra.

## 2. Effetti collaterali da conoscere prima

- **Coda del curatore.** Ogni lotto apre le coppie «stesso nome» in `catalog.duplicate_candidates` (tetto 500 per
  tipo e per lotto). A popolamento completo sono attese **11.960 coppie di vini** (2.617 gruppi di omonimi, 7.208
  vini, gruppo più grande 48) e **748 coppie di produttori** con lo stesso nome in paesi diversi. Sono in gran parte
  vini legittimamente distinti: la regola non fonde nulla, e nessuna coppia blocca la promozione.
- I 148 record con possibile duplicato e i 130 rilievi aperti restano fuori o invariati.
- La ricerca non cambia finché la proiezione è spenta.

## 3. Costi misurati

### 3.1 Production, sola lettura (una misura ciascuna)

| Operazione | Durata |
|---|---|
| `promotion_simulation` (ufficiale) | 52,7 s (prima di WI-008: timeout) |
| Aggregazione su `promotion_report` (paesi, omonimi, esclusivi) | 65,8 s |
| `promotion_lot(…, 100, …)`: **lettura fissa di ogni lotto** | **67,3 s** |
| `promotion_logic_fingerprint`, ricalcolata dalla guardia a ogni riga inserita | 2,0 ms |

`source_records`: heap 670 MB per 213.407 righe vive da circa 1,4 KB (2,23 volte i dati vivi), perché l'import
inserisce e poi aggiorna 211.838 righe. `shared_buffers` 224 MB, `work_mem` 2 MB, `statement_timeout` 2 min.

### 3.2 Banco sintetico (runner di CI, run 45776259355, SHA `ef322a6`)

Stesse proporzioni della fonte, stessi file `00`–`05`. **Un runner non è il compute di Production**: la lettura lì
costa circa 18,5 s contro 67,3 s.

| Lotto | Lettura | Scritture | WAL |
|---|---|---|---|
| 100 | 18,5 s | 0,6 s | < 1 MB |
| 1.000, catalogo quasi vuoto | 18,6 s | 2,3–2,5 s | 3 MB |
| 1.000, 156.100 vini già presenti | 15,8 s | 2,6–2,9 s | 8–18 MB |
| 5.000 | 18,4 s | 11,9–12,1 s | 19–22 MB |
| 10.000, da 46.100 a 146.100 vini | 16,1–17,8 s | 20,1–21,2 s | 27–51 MB |

- Le scritture sono **proporzionali al lotto** (circa 2 ms per vino) e **non crescono con il catalogo**.
- Rilevamento duplicati: 0,11 s a 3.600 vini, 0,45 s a 159.614. Alias e registro: trascurabili.
- 25 lotti, circa 0,5 GB di WAL in totale; a fine corsa `wines` 128 MB (indici inclusi), `producers` 14 MB,
  `entity_aliases` 1,4 MB, `duplicate_candidates` 2,3 MB. Attesi quindi circa **150 MB** in più nel database; i dati
  sintetici hanno nomi più corti di quelli veri e meno coppie (6.565 di vini, 0 di produttori).
- **`VACUUM FULL source_records` non è nel piano**: heap da 566 a 285 MB, lettura da 15,95 a 15,82 s. Con i dati in
  cache il costo è CPU. In Production l'effetto sull'I/O non è provato.
- Provati: interruzione a metà lotto senza effetti parziali; `04` la riconosce e lo stesso numero si ripete; lotto
  già confermato rifiutato; oltre `max_batch` rifiutato; a candidati esauriti 0 righe; a finestra chiusa rifiutato;
  alla fine 159.614 vini, 27.410 produttori, 4.206 alias, 0 eccezioni, 0 incoerenze, 0 violazioni di superficie.

## 4. Precondizioni della finestra

1. Esito favorevole della rivalidazione indipendente di WI-009 sullo SHA che si esegue.
2. Impronta: vedi §4.1. Decisione esplicita del founder su regola, impronta **definitiva** e popolamento.
3. `00_stato.sql`: impronta, digest e run uguali a quelli approvati; regola `draft` (o `approved` dopo `01`);
   promozione e proiezione OFF; `max_batch` 1.000; `lock_promozione` vuoto; nessun import in corso; login di import
   `NOLOGIN`; 0 violazioni di superficie. Un valore diverso = ripetere la simulazione.
4. Percorso amministrativo provato nello stesso giorno (§5.1, `verifica_percorso.sql`).
5. Spazio su disco letto dal pannello Supabase (SQL non lo mostra): libero almeno **2 GB** oltre al database. Il tetto
   passato al lotto (`TETTO_DB_BYTE`) è la dimensione attuale più 600 MB, circa quattro volte la crescita attesa.
6. Backup secondo §4.2.
7. Nessun deploy di migration nella finestra; **un solo esecutore**, una persona che la segue dall'inizio alla fine.

### 4.1 Impronta: va riletta dopo la distribuzione di F-07

La migration `20261127100000` (WI-009, ramo `feature/wi-009-impronta-fusione`) estende l'impronta da 28 a 33
funzioni (`merge_state_check`, `merge_authorized`, `revert_authorized`, le due guardie di `duplicate_candidates`) e
ai trigger di `duplicate_candidates`. Non cambia il comportamento della regola: i numeri della simulazione restano.
**Una volta distribuita, il valore `b87e7b51…` del §1 non va più approvato**: si legge il nuovo con `00_stato.sql` e
lo si sottopone al founder. Finché la migration non è distribuita non si apre alcuna finestra.

**Aggiornamento del 26/11/2026 (Production letta dopo il merge, ledger 136):** F-07 è distribuita (`d887194`, impronta
`3b526fac…`, mai approvata) e WI-011 (`ca719f1`) ha modificato `catalog.wines_guard`, coperta dall'impronta. Il valore
corrente è **`64e038526a78f44070a54498fd0ff607`**; il digest della vista resta `b352be426a3a32762fb7fa5140b7ee88`.
Anche `b87e7b51…` e `3b526fac…` **non vanno approvati**. La modifica di `wines_guard` ammette un solo passaggio (LWIN
assente → LWIN ufficiale su un vino nativo con record di fonte valido) e fa parte del delta da rivalidare. Il valore
si rilegge comunque con `00_stato.sql` prima di qualunque decisione.

### 4.3 Procedura unica del founder (F-06 e F-08)

Solo il founder può eseguirla: servono la password del proprietario del database, la chiave `age` offline e il
pannello Supabase. **Nessuna password, chiave o credenziale va in chat o nel repository.** Non si ripristina nulla in
Production e non si apre alcuna finestra.

Una volta sola: installare il client `psql`; scaricare il certificato CA del progetto dal pannello (Database → SSL).

1. **Backup recente:** GitHub → Actions → `Continuity - encrypted offsite backup` → *Run workflow*; attendere
   l'esito verde e annotare l'id del run. (L'ultimo riuscito il 26/11 alle 11:00 UTC è `45806510709`: vale come
   evidenza del meccanismo, non della finestra.)
2. **Archivio:** scaricare da B2 `.age` e `.sha256` di quel run (continuità §«Ripristino da B2») e, su una macchina
   isolata con la chiave offline:
   `.github/scripts/offsite-restore-verify.sh <archivio.age> <chiave-age> <directory-vuota>`.
   Decifra e controlla gli hash; **non tocca alcun database**.
3. **Disco:** pannello Supabase → Compute and Disk: annotare dimensione e spazio libero (servono almeno 2 GB oltre al
   database, 731 MB il 26/11).
4. **Percorso `psql`:** il comando del §5.1 con `verifica_percorso.sql` (circa 4 minuti, sola lettura).
5. **Da riportare:** riga SSL di `\conninfo`, utente, pid uguale all'inizio e alla fine, durata; id del run di
   backup; messaggio finale dello script dell'archivio; numeri del disco.

Restore sintetico (`ripristino.sh`, CI) e restore dell'archivio Production sono prove diverse: la seconda, in un
progetto isolato, resta una decisione di costo.

### 4.2 Backup e ripristino: quale evidenza basta

Non c'è PITR: il ripristino torna all'ultimo backup e perde ciò che è stato scritto dopo. Servono **tutte**:

1. un run di `Continuity - encrypted offsite backup` lanciato a mano **subito prima** della finestra, riuscito
   (esporta ruoli, schema, dati e Storage, carica su B2, riscarica e verifica hash e Object Lock);
2. nel suo log, la data dump completata. Lo schema `catalog` è incluso: gli avvisi di `pg_dump` sui vincoli
   circolari nominano `entity_merges` e `duplicate_candidates`, che esistono solo lì (run 45806510709 del 26/11);
3. `.github/scripts/offsite-restore-verify.sh` sull'archivio di quel run, in una macchina isolata con la chiave
   `age` offline (**solo il founder**: decifratura e hash, nessun database);
4. la prova `ripristino.sh` verde sullo SHA che si esegue (CI, stack effimero): un dump dei soli dati di `catalog`
   popolato si ricarica sopra le migration del commit (`session_replication_role = replica` e `truncate` delle
   righe seminate, in una transazione) con contenuto identico, regola e impronta conservate e promozione che riprende.

**Rischio residuo, non coperto:** il backup B2 reale con il database di oggi (757 MB, 129 migration, catalogo) non è
mai stato ripristinato; l'ultimo restore reale è del 22/09/2026 (60 migration). Un restore completo in un progetto
isolato è una decisione di costo del founder.

## 5. Esecuzione

### 5.1 Percorso amministrativo (vincolante, F-06)

**Mai il connettore MCP né l'editor SQL del pannello per i lotti**: il connettore abbandona un'istruzione di circa
due minuti mentre il backend continua (provato dall'audit). Si usa `psql` dalla sessione amministrativa del
proprietario, via **Session Pooler** (`aws-0-eu-west-1.pooler.supabase.com`, porta **5432**, modo sessione: mai la
6543) oppure con connessione diretta da un ambiente IPv6 già autorizzato. Mai `catalog_import_login`.

- TLS: `sslmode=verify-full` con `sslrootcert` = certificato CA pubblico del progetto.
- Password: solo dal prompt di `psql` o da un file `PGPASSFILE` privato preparato dal proprietario. Mai nella riga di
  comando, in variabili stampate, nel repository o in una chat.
- Keepalive nella stringa di connessione.
- Sempre `-X -v ON_ERROR_STOP=1 -f <file>`. **Non** inviare il file come messaggio unico (`-c`): con `-f` ogni
  istruzione è un messaggio, quindi se il client muore il `COMMIT` non parte.
- Nessun timeout globale cambiato: `03` imposta solo nella propria transazione `statement_timeout` (`{{TIMEOUT}}`,
  `300s`), `transaction_timeout` (lo stesso più 60 s), `idle_in_transaction_session_timeout` (60 s) e
  `client_connection_check_interval` (10 s).

Prova prima della finestra, con lo stesso comando dei lotti:

```powershell
psql "host=aws-0-eu-west-1.pooler.supabase.com port=5432 dbname=postgres user=postgres.pijnmcllmfgjmgsvtcej sslmode=verify-full sslrootcert=C:/percorso/prod-ca.crt keepalives=1 keepalives_idle=30 keepalives_interval=10 keepalives_count=6" -X -v ON_ERROR_STOP=1 -f tools/wine-catalog/promozione/verifica_percorso.sql
```

Superata solo con SSL dichiarato da `\conninfo`, utente proprietario, stesso pid all'inizio e alla fine e circa
240 s senza errori. **Al 26/11/2026 non è stata eseguita**: sul PC non è installato `psql` e la credenziale
amministrativa è solo del proprietario.

### 5.2 Sequenza

1. `01_approva_regola.sql` (una volta; rifiuta se impronta, digest, run o interruttori non coincidono).
2. `02_apri_finestra.sql`: **preflight di sola lettura**. Non accende nulla.
3. Lotto pilota: `03_lotto.sql` con `LIMITE=100`, `NUMERO=1`, `MAX_BATCH_AUTORIZZATO=1000`; poi `04_riconcilia.sql` e
   `00_stato.sql`.
4. Salire solo se il precedente è pulito: **500**, poi **1.000**.
5. Un lotto alla volta. Il lotto è riuscito **solo** con la riga `"esito": "confermato"`, emessa dopo il `COMMIT`
   rileggendo il registro. `04` dopo il pilota, a ogni cambio di dimensione, ogni 10 lotti e alla fine.
6. `05_chiudi_finestra.sql` **sempre**, anche dopo un arresto. Poi `00` e `04`.

**Interruttore.** `promotion_settings.enabled` diventa vero **solo dentro la transazione del singolo lotto**, nello
stesso blocco che lo rispegne: nessun'altra sessione lo vede mai acceso. Processo ucciso, errore, scadenza o
connessione caduta annullano l'intera transazione. `05` resta una rete di sicurezza che spegne e riporta
`max_batch` a 1.000 anche se qualcuno li ha alterati a mano. Modello di accesso: solo il proprietario del database
può scrivere l'interruttore; una chiamata diretta a `promote_wine_candidates` fuori da un lotto risponde «promozione
disattivata», e un interruttore acceso a mano fa fermare il lotto successivo e il preflight.

Valori finali attesi: 159.614 vini, 27.410 produttori, 4.206 alias, 0 eccezioni, ogni voce di `incoerenze` a 0,
coppie aperte intorno a 12.708, `source_records` 212.894, tabelle applicative invariate, promozione e proiezione OFF.

### 5.3 Dimensione dei lotti

`max_batch` resta **1.000** fuori dai lotti.

- Con i numeri di oggi un lotto da 1.000 vale circa 67 s di lettura più le scritture. Se in Production le scritture
  fossero 3–4 volte più lente che sul runner (il rapporto visto in lettura è 2,8–3,6), sarebbero 7–11 s. È
  un'**estrapolazione**, non una misura.
- Solo la lettura, a lotti da 1.000, è 160 × 67 s ≈ **3 ore**. È un conto sulla misura singola, non una promessa di
  durata.
- Oltre 1.000 si passa solo con autorizzazione esplicita del founder, **al massimo 5.000**
  (`MAX_BATCH_AUTORIZZATO=5000`; 10.000 non è ammesso). `03` lo impone: rifiuta oltre 5.000 e senza due lotti da
  1.000 puliti nel registro. Restano all'operatore: salita progressiva, `secondi` previsti per la nuova dimensione
  (lettura più scritture misurate scalate) ≤ 180 s, e memoria, WAL, spazio e salute dell'applicazione nei limiti.
- Nessun `update` manuale di `max_batch`: `03` lo alza solo dentro la propria transazione e lo riporta a 1.000.

### 5.4 Arresti

Automatici (la transazione si annulla per intero): lock della promozione occupato (un solo esecutore); lotto già
registrato; interruttore trovato acceso; dimensione non autorizzata; registro e vini non coincidenti; eccezioni
presenti o nuove; proiezione accesa; database oltre il tetto; vini creati diversi dagli attesi; fonte cambiata;
scadenze della transazione; più quelli della funzione (regola, impronta, digest, fonte autorizzata, import in corso).
Un `lock timeout` (5 s) per un import o una fusione di produttori in corso non ha effetti: si riprova.

Operativi (fermarsi, chiudere con `05`, capire): una voce di `incoerenze` diversa da 0; un lotto oltre 180 s; due lotti
consecutivi con durata cresciuta di oltre il 50%; crescita del database oltre il doppio di quella attesa; avvisi del
pannello su disco, I/O o CPU; errori o rallentamenti dell'applicazione.

### 5.5 Esito incerto e ripresa

Un errore di connessione **non** equivale a un rollback, e una risposta mancante non equivale a un successo. Non
rilanciare. `04_riconcilia.sql` con **lo stesso numero** prende il lock vero della promozione e poi legge il registro
con uno snapshot nuovo: `in_corso` (lock occupato: un lotto può essere ancora aperto) → attendere e ripetere `04`;
`registrato` → passare al numero successivo; `non_registrato` → nessun effetto, si ripete lo stesso numero. Un lotto
già registrato è comunque rifiutato da `03` sotto lo stesso lock. La ripresa dopo qualunque arresto parte da `00` e
`04`: i vini già promossi escono dai candidati, quindi il lotto successivo prende i successivi in ordine di LWIN.
Non c'è una finestra da richiudere a mano; `05` si esegue comunque.

### 5.6 Prove della procedura (CI, stack effimero)

`Wine catalog promotion bench` ha due prove indipendenti: `banco.sh` (159.614 promozioni con i file veri) e
`concorrenza.sh` seguita da `ripristino.sh`. `concorrenza.sh` riprende la coreografia dell'audit e la trasforma in
asserzioni: due esecuzioni dello stesso numero, client chiuso o ucciso, backend terminato, errore SQL, scadenze,
client fermo prima del `COMMIT`, risposta persa, chiamate dirette, interruttore lasciato acceso, lock di import e di
fusione, isolamento di sessione, soglie 1.000 e 5.000. Sulla procedura di `fa88ba8` (run 45831117460): **64 verdi,
38 rosse**; su quella corretta (run 45832544122): **101 verdi, 0 rosse**.

## 6. Prima di accendere la proiezione (decisione separata)

Il popolamento non accende nulla. Restano da fare sul catalogo popolato:

1. **Tempi di ricerca in Production.** Sul banco (159.614 vini): LWIN e Combined 4 ms, esatto 10 ms, omonimi 52 ms,
   solo produttore 17 ms, nessun risultato 8 ms, termine comune 309 ms, **refuso 844 ms, prefisso 1.332 ms, testo
   1.359 ms**. Il wizard aspetta il catalogo canonico **al massimo 1,5 s** e poi lo scarta in silenzio: su un compute
   più lento prefisso, testo e refuso possono superare il tetto. È la prova decisiva, insieme allo
   `statement_timeout` di 8 s per `authenticated`. I nomi sintetici condividono parole molto frequenti.
2. **Piani** sui dati veri (esatto su indice btree, testo su indice trigramma: così sul banco).
3. **Limite per utente**: provato via PostgREST in CI (`wi008d`). Da osservare l'IP con cui le Edge Function si
   presentano all'hook per le RPC di servizio.
4. **AI**: oggi spenta (`ai-sommelier` risponde 503). Il limite è 40 richieste/ora per utente; **non esiste un budget
   condiviso nell'applicazione**: il tetto complessivo è il limite di spesa sul conto del provider, non verificato.
5. **Sommelier con dati veri**: provato solo con database e provider finti; nessuna chiamata a pagamento.
6. **OCR con catalogo popolato**: usa la stessa sorgente di ricerca (test unitari); nessuna prova su foto vere.
7. **Mobile e WebKit**: wizard, scheda e scelta in Cantina provati con catalogo di prova su Chromium desktop, 375 px e
   WebKit (`WI_008_INTEGRAZIONE_CATALOGO.md` §10.6). Da ripetere a mano su un iPhone vero col catalogo popolato.
8. **Marketplace**: nessun annuncio è collegato al catalogo; la scheda lo dichiara. La scelta in Cantina è personale
   (proprietario e vino): non identifica la bottiglia, non collega annunci e non certifica nulla. Proposta e
   approvazione di un collegamento canonico sono un'evoluzione successiva.
