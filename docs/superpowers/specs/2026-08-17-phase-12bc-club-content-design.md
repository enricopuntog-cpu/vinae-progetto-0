# Fase 12b + 12c — contenuti dei club e loro moderazione

Data: 17 agosto 2026. Branch `migration/phase-12bc-club-content`, sopra `e2132ee`
(squash della PR #48, checkpoint 12a).

Questo documento registra le decisioni prese prima di scrivere il codice, e in
particolare le quattro che la sessione di coordinamento ha delegato alla lettura
del progetto invece di fissarle. Non è un riassunto del diff: è ciò che il diff
non può dire di sé.

---

## 1. Perché 12b e 12c sono un merge solo

La 12b introduce **testo pubblico scrivibile dagli utenti**. La 12c introduce il
modo di segnalarlo e rimuoverlo. Mergiare la 12b da sola aprirebbe una finestra —
di durata ignota, perché dipende da quando la 12c viene approvata — in cui
chiunque pubblica su una superficie pubblica e nessuno può segnalare quello che
legge. È la stessa regola che la decisione **7.6a** ha già applicato al contrario:
la Fase 9 ha *escluso* `post` e `commento` dai bersagli segnalabili proprio perché
i club non avevano schema. Ora che lo schema arriva, i due lati arrivano insieme.

Conseguenza operativa: **una sola PR draft**, e la 12b non è mergiabile da sola in
nessuna circostanza, nemmeno se la 12c avesse un problema. Se la 12c va rifatta,
si rifà dentro la stessa PR.

## 2. L'ammissione per nome

La scrittura di contenuti nei club è **funzionalità nuova**, non parità con
`frontend/`: in `frontend/` i post sono `frontend/src/data/communities.ts`, un file
mock, e il pulsante «Crea un post» era un toast dimostrativo. È ammessa **per
eccezione esplicita e per nome**, ed è la seconda ammissione del genere dopo le
quattro della Fase 11 (7.3a, 7.3b, 7.12, 7.13). Il testo integrale
dell'ammissione è registrato in `CLAUDE.md`, accanto a quelle, e in `CHANGES.log`.

«Niente funzionalità nuove durante la migrazione» **non è decaduta**: continua a
valere per tutto ciò che una sessione non ha chiesto per nome. In particolare non
sono ammessi da questa eccezione — e infatti non ci sono — sondaggi con opzioni
votabili, notifiche su risposta, menzioni, allegati, thread annidati.

---

## 3. Le quattro decisioni delegate alla lettura

### 3.1 `report_target_tipo` è un enum, non un check constraint

Il brief chiedeva di «estendere il check constraint di `report_target_tipo`».
Non è un check constraint: è un **enum**
(`supabase/migrations/20260810152000_phase_9a_moderation_schema.sql:36`). La
differenza non è terminologica e decide la forma della migrazione.

In PostgreSQL 12+ `ALTER TYPE ... ADD VALUE` può stare dentro un blocco di
transazione, ma **il valore nuovo non è utilizzabile nella stessa transazione che
lo aggiunge**. Supabase applica ogni file di migrazione nella propria transazione.
Quindi aggiungere `'post'` e `'commento'` e usarli — in un `insert into
report_reasons`, in un `check`, dentro un `case` di funzione — nello stesso file è
un errore a tempo di applicazione, non uno stile discutibile.

**Tre file, non uno**, e il secondo esiste solo per essere una transazione a sé:

| file | contenuto |
|---|---|
| `20260817120000_phase_12b_club_content.sql` | le tre tabelle, RLS, viste, guard |
| `20260817120500_phase_12c_report_target_enum.sql` | **solo** i due `add value` |
| `20260817121000_phase_12c_club_moderation.sql` | tutto ciò che *usa* i due valori |

### 3.2 Il buco che l'estensione dell'enum apre da sola

`reports_target_coerente` è un `case target_tipo ... end` **senza ramo `else`**
(9a righe 200-212). Un `case` senza `else` che non trova corrispondenza restituisce
`NULL`, e un `CHECK` il cui predicato vale `NULL` **passa**: `NULL` non è `false`.

Quindi il solo `alter type ... add value`, senza altro, renderebbe una segnalazione
di tipo `post` libera di portare `target_listing_id` valorizzato — il vincolo di
esclusività che protegge i cinque bersagli esistenti smetterebbe di dire qualcosa
sui due nuovi. Non è un difetto scoperto leggendo il codice nuovo: è un difetto che
il codice nuovo *crea* nel codice vecchio, e va chiuso nella stessa migrazione che
lo apre. La 12c ridefinisce entrambi i vincoli con i rami espliciti per i due
valori nuovi e le due colonne nuove.

Stessa classe di problema, stessi punti da toccare: `v_esiste` in
`segnalazione_invia` (9a:549) è anch'esso un `case` senza `else`, ma lì il difetto
**fallisce chiuso** (`coalesce(v_esiste, false)` → «Bersaglio non trovato»), quindi
è una funzionalità mancante e non un buco. Va comunque esteso, o `post` e
`commento` sarebbero segnalabili in teoria e mai in pratica.

### 3.3 `listing_id`: quando è mio e quando è pubblico

Il brief chiedeva di non assumere, ma di guardare come la UI mock trattava il tipo
`annuncio`. I due post di quel tipo in `frontend/src/data/communities.ts` sono:

- `d3` — «**Vendo** Barolo Brunate 2018 — G. Rinaldi», «Bottiglia allocata
  direttamente in cantina. Doppio pezzo.»
- `d10` — «**Vendo** Magnum Ornellaia 2017», «Bottiglia della verticale personale.»

In entrambi l'autore del post è **il venditore**, e il post è l'annuncio della
*propria* vendita. Il mock porta un `wineId` (`rinaldi-brunate-2018`), cioè un
riferimento al catalogo, non a un annuncio: la colonna `listing_id` non ha un
precedente nel mock e la sua semantica va decisa qui.

**Decisione, in due condizioni sovrapposte:**

1. `listing_id`, quando valorizzato, deve puntare a un annuncio **pubblicamente
   visibile** — cioè presente in `public_listings` (`stato = 'attivo'` e non
   scaduto). Vale per ogni tipo di post. Un post che rimanda a una bozza manderebbe
   i lettori del club su qualcosa che nessuno di loro può aprire.
2. **In più**, se `tipo = 'annuncio'`, l'annuncio dev'essere **dell'autore del
   post**. È la lettura del mock: si annuncia la propria vendita, non quella di un
   altro. Senza questa condizione «Vendo Magnum Ornellaia 2017» potrebbe puntare
   all'annuncio di un terzo, che è pubblicità non richiesta nel caso benevolo e
   dirottamento di traffico in quello no.

Per gli altri sei tipi `listing_id` resta un **riferimento** («che ne pensate di
questa bottiglia in vendita?»), quindi la sola condizione 1.

Nota di durata: le due condizioni sono verificate **all'inserimento**. Un annuncio
che dopo viene sospeso o venduto lascia il post con un riferimento che la vista
pubblica smette di risolvere. È voluto: la vista fa `left join` su
`public_listings`, quindi il post resta leggibile e il riquadro dell'annuncio
sparisce. L'alternativa — nascondere il post — cancellerebbe una discussione per un
fatto che riguarda un suo allegato.

### 3.4 `tipo` come `check`, non come enum

Il progetto usa enum quasi ovunque (`club_ruolo`, `listing_stato`,
`report_target_tipo`). Qui il brief chiede esplicitamente un `check`, e la richiesta
regge per una ragione propria: i sette valori sono **etichette di filtro della UI**,
copiate da `PostTipo` (`frontend/src/data/communities.ts:134-135`), non stati di una
macchina. Allargarli è una modifica di prodotto, e con un `check` è un
`alter table ... drop constraint / add constraint` invece della cerimonia
dell'enum descritta in §3.1 — che è esattamente il costo che questa fase ha appena
pagato per `report_target_tipo`.

`sondaggio` è fra i sette valori e **non ha schema di sondaggio**: nessuna tabella
di opzioni, nessun voto. È un post con un titolo e un corpo, come gli altri. Il
valore esiste perché la UI mock lo filtrava; costruire il sondaggio vero sarebbe
funzionalità nuova che nessuna sessione ha chiesto per nome.

---

## 4. Il guard delle scritture social esiste già, e non è solo sui club

Cercato prima di scrivere, come chiesto: `private.scrittura_social_guard()` è
definita in **9b** (`20260810180000:196`) e montata su `public.listings`,
`public.messages`, `public.conversations` — e, dalla 12a, su
`public.club_memberships`. Non è quindi un guard «trovato solo su
`club_memberships`»: è il guard generale del primo livello della decisione 7.6b, e i
club ne sono l'ultimo arrivato.

Si applica **invariato** alle tre tabelle nuove. Il suo `case tg_table_name` ha già
il ramo `else auth.uid()` per le tabelle il cui attore non è nominato dal corpo
della funzione, ed è questo il caso: `club_posts.autore_id`,
`club_post_risposte.autore_id` e `club_post_like.user_id` arrivano tutte da
`DEFAULT auth.uid()`. **La funzione non viene ridefinita** — un `create or replace`
su una funzione della 9b per aggiungerci un ramo che non serve sarebbe rimettere in
produzione codice di un'altra fase senza motivo.

Simmetricamente, il secondo livello (rimozione, che toglie anche l'accesso in
visione) è nelle due viste pubbliche, con la stessa forma di `public_clubs` e
`public_listings`: un chiamante `rimosso` legge zero righe.

**Nessuna tabella di ordini, pagamenti, contestazioni o payout è nominata in
nessuno dei tre file.** Il vincolo della 9c è soddisfatto per costruzione, e una
riga della griglia lo verifica invece di dichiararlo.

## 5. Rate limit: perché c'è, benché nessuno l'abbia chiesto

Non è funzionalità: è la convenzione di ogni scrittura social del progetto —
`message:send` 30/60 e `conversation:open` 20/60 (Fase 8), `report:submit` 10/3600
(9a), i tre bucket IA della Fase 10. Una superficie di **testo pubblico** senza
bucket dedicato sarebbe l'unica.

Esiste già un tetto globale: `private.vinea_check_request` limita ogni chiamante
PostgREST a 120 scritture/minuto su tabella. Non basta come unica difesa su un muro
pubblico, e 120 post al minuto non è un numero che qualcuno abbia scelto per i club.

- `club:post` — **10 / 3600**, la cadenza di `report:submit`: un post è scrittura
  ponderata, non una battuta di chat.
- `club:risposta` — **30 / 3600**. Rispondere è più frequente che aprire.
- **nessun bucket per i like.** Un like è idempotente (conflitto di chiave
  primaria) e reversibile; un bucket punirebbe l'uso normale e il tetto globale
  copre già il caso patologico.

I tre numeri sono **valori di sessione**, come i tre della Fase 10 che una sessione
successiva dovette correggere: si riaprono su uso osservato, non su aritmetica.

Il bucket vive dentro il trigger `SECURITY DEFINER` che già serve per i controlli
incrociati, e non dentro una RPC: così vincola **ogni** percorso presente e futuro,
`service_role` compreso — la stessa ragione per cui la 9b scelse un trigger invece
di un controllo dentro `listing_crea`.

## 6. La rimozione è una colonna, e la porta arriva dalla 12c

`rimosso_at`, `rimosso_da`, `rimosso_motivo` sono **colonne della 12b**, fuori da
ogni `GRANT` client, e le due viste pubbliche filtrano `rimosso_at is null` dalla
prima riga. La **porta** che le scrive è della 12c. La divisione è voluta: la forma
del dato deve esistere prima della vista che la rispetta, altrimenti esisterebbe un
momento — dentro lo stesso merge — in cui la vista pubblica non sa cosa nascondere.

**Non è una `DELETE` fisica**, per la stessa ragione per cui le cinque foreign key
di bersaglio della 9a sono `on delete set null`: una segnalazione deve sopravvivere
alla rimozione di ciò che segnala, o moderare cancellerebbe la prova del perché.

Le due azioni non sono RPC nuove: sono **rami nuovi dentro
`moderazione_rimozione` e `moderazione_ripristino`**, che già scelgono l'effetto sul
`target_tipo` della pratica e che oggi, per `post` e `commento`, cadrebbero nel ramo
`else` scrivendo l'audit **senza rimuovere niente**. È la stessa forma con cui la 9c
allargò il perimetro. Non vengono aggiunte porte «rimuovi questo post» per
bersaglio: non avrebbero chiamante — il pannello di moderazione della Fase 9 non è
mai stato esercitato sul progetto reale — e la 12a ha già fissato che una porta di
scrittura senza chiamante è superficie in più.

## 7. Cosa questa fase non fa, di proposito

- **Nessuna cancellazione del proprio post da parte dell'autore.** Il brief elenca
  le porte di scrittura e non la comprende. L'`UPDATE` è limitato a `titolo` e
  `corpo`, che è ciò che serve per correggere un refuso.
- **Nessuna notifica** su risposta o like, benché la Fase 8 abbia
  `notifications.destination_club_slug` che aspetta dai tempi suoi.
- **Nessun ruolo `moderatore` di club.** La decisione 7.1 della Fase 9 tiene lo
  scope club rinviato, e `club_ruolo` resta a un solo valore.
- **Nessun thread annidato**: un solo livello, come da brief. `club_post_risposte`
  non ha `parent_risposta_id`.
- **Nessuna esecuzione di SQL sul progetto Supabase reale.** Le tre migrazioni sono
  testo in attesa di autorizzazione esplicita e separata; la griglia versionata è
  testo e non un risultato, con la stessa dichiarazione della 12a.

## 8. Un difetto preesistente, trovato e non corretto

`report_reasons` della 9a contiene i motivi **senza accenti** (`'Identita
sospetta'`, 9a:107) mentre `frontend-next/src/data/moderation.ts:46` invia
`"Identità sospetta"`. Il controllo di elenco chiuso in `segnalazione_invia`
confronta le due stringhe, quindi quella segnalazione fallirebbe con «Motivo non
ammesso per questo tipo di bersaglio». Riguarda `profilo` e almeno altri motivi
accentati, non `post` e `commento` — i cui sette motivi non hanno accenti in
nessuna delle due copie, e sono copiati carattere per carattere da
`data/moderation.ts:57-58`.

È un difetto della Fase 9, in un percorso che questa fase non tocca. Correggerlo
qui vorrebbe dire modificare i motivi di quattro bersagli dentro una PR sui club, e
la correzione è una migrazione che aggiorna righe esistenti — cioè esattamente il
tipo di cosa che va vista da sola. Registrato qui e nel report della PR.
