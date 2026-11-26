# Promozione canonica — runbook del popolamento incrementale

Stato al 26 novembre 2026: **preparata e provata su dati sintetici, NON eseguita**. Regola `lwin-conservative-v1` in
bozza, promozione e proiezione OFF, 0 vini e 0 produttori canonici in Production. Questo file non autorizza nulla.

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

1. Decisione esplicita del founder su regola e popolamento, con i valori del §1.
2. `00_stato.sql`: impronta, digest e run uguali al §1; regola `draft`; promozione e proiezione OFF; nessun import in
   corso; login di import `NOLOGIN`; 0 violazioni di superficie. Un valore diverso = ripetere la simulazione.
3. Spazio su disco letto dal pannello Supabase (SQL non lo mostra): libero almeno **2 GB** oltre al database. Il tetto
   passato al lotto (`TETTO_DB_BYTE`) è la dimensione attuale più 600 MB, cioè quattro volte la crescita attesa.
4. Backup recente con verifica di ripristino (`docs/CONTINUITY_AND_BACKUP_RUNBOOK.md`).
5. Nessun deploy di migration nella finestra; una persona che la segue dall'inizio alla chiusura.

## 5. Esecuzione

Sessione amministrativa del proprietario (la stessa delle migration). **Mai** `catalog_import_login`, nessun timeout
globale cambiato: `03_lotto.sql` imposta `statement_timeout` solo nella propria transazione (`{{TIMEOUT}}` = `300s`).
Il percorso usato deve reggere istruzioni di alcuni minuti: la via MCP è stata osservata reggere 67 s, oltre non è
provato. Se la connessione cade, l'esito è **incerto** e si usa `04`.

1. `01_approva_regola.sql` (una volta; rifiuta se impronta, digest, run o interruttori non coincidono).
2. `02_apri_finestra.sql`.
3. Lotto pilota: `03_lotto.sql` con `LIMITE=100`, `NUMERO=1`; poi `04_riconcilia.sql` e `00_stato.sql`.
4. Salire solo se il precedente è pulito: **500**, poi **1.000** (il `max_batch` attuale).
5. Un lotto alla volta; `04` dopo il pilota, a ogni cambio di dimensione, ogni 10 lotti e alla fine.
6. `05_chiudi_finestra.sql` **sempre**, anche dopo un arresto. Poi `00` e `04`.

Valori finali attesi: 159.614 vini, 27.410 produttori, 4.206 alias, 0 eccezioni, ogni voce di `incoerenze` a 0,
coppie aperte intorno a 12.708, `source_records` 212.894, tabelle applicative invariate, proiezione OFF.

### 5.1 Dimensione dei lotti

`max_batch` resta **1.000**. Non va alzato automaticamente: il vincolo del database ammette 10.000, ma il valore si
decide sulle misure del pilota.

- Con i numeri di oggi un lotto da 1.000 vale circa 67 s di lettura più le scritture. Se in Production le scritture
  fossero 3–4 volte più lente che sul runner (il rapporto visto in lettura è 2,8–3,6), sarebbero 7–11 s. È
  un'**estrapolazione**, non una misura.
- Solo la lettura, a lotti da 1.000, è 160 × 67 s ≈ **3 ore**. È un conto sulla misura singola, non una promessa di
  durata.
- A 5.000 (32 lotti) o 10.000 (16 lotti) la lettura si ammortizza, ma un lotto da 10.000 supererebbe
  presumibilmente i 2 minuti. Si passa oltre 1.000 solo se: è autorizzato nella decisione; due lotti da 1.000 sono
  puliti; `secondi` previsti per la nuova dimensione (lettura + scritture misurate scalate) ≤ 180 s, cioè il 60% di
  `300s`. Il cambio è un `update catalog.promotion_settings set max_batch = …` esplicito e annotato, riportato a
  1.000 alla chiusura.

### 5.2 Arresti

Automatici (la transazione si annulla per intero): lotto già registrato; registro e vini non coincidenti; eccezioni
presenti o nuove; proiezione accesa; database oltre il tetto; vini creati diversi dagli attesi; fonte cambiata; più
quelli della funzione (regola, impronta, digest, interruttore, fonte autorizzata, import in corso, `max_batch`).

Operativi (fermarsi, chiudere con `05`, capire): una voce di `incoerenze` diversa da 0; un lotto oltre 180 s; due lotti
consecutivi con durata cresciuta di oltre il 50%; crescita del database oltre il doppio di quella attesa; avvisi del
pannello su disco, I/O o CPU; errori o rallentamenti dell'applicazione.

### 5.3 Esito incerto e ripresa

Non rilanciare. `04_riconcilia.sql` con **lo stesso numero**: `in_corso` → attendere; `registrato` → passare al numero
successivo; `non_registrato` → il lotto non ha avuto effetti, si ripete lo stesso numero. La ripresa dopo qualunque
arresto parte da `00` e `04`: i vini già promossi escono dai candidati, quindi il lotto successivo prende i successivi
in ordine di LWIN.

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
7. **Mobile e WebKit**: vedi `WI_008_INTEGRAZIONE_CATALOGO.md` §10.
8. **Marketplace**: nessun annuncio è collegato al catalogo; la scheda lo dichiara. La scelta in Cantina è personale
   (proprietario e vino): non identifica la bottiglia, non collega annunci e non certifica nulla. Proposta e
   approvazione di un collegamento canonico sono un'evoluzione successiva.
