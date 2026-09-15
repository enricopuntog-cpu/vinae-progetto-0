# Aliquota differenziata per classe di venditore — documento di progettazione

> **Documento di sola progettazione. Nessuna riga di codice, nessuna migrazione,
> nessun SQL applicato.** L'SQL della §9 è mostrato perché sia discutibile, non
> perché sia pronto: non esiste come file sotto `supabase/migrations/`, non è
> stato eseguito da nessuna parte e non deve esserlo prima di una decisione
> separata.
>
> **Ammissione.** «Nessuna funzionalità nuova durante la migrazione» resta in
> vigore. L'aliquota differenziata per venditori professionali è ammessa **per
> eccezione esplicita e per nome** da Enrico il **14 settembre 2026**, come già
> avvenuto per le quattro funzionalità della Fase 11 e per la 12b+12c.
> L'ammissione riguarda la **progettazione**; l'implementazione richiede una
> decisione separata — e, a differenza della vetrina, dipende da un prerequisito
> esterno che nessuna quantità di codice chiude: §12.
>
> **Stato di riferimento.** Righe di codice di `origin/main` al commit
> `0a226aa`. Stato di produzione letto in sola lettura sul progetto
> `pijnmcllmfgjmgsvtcej` il **15 settembre 2026**.

---

## 1. L'obiettivo e l'ostacolo

**L'obiettivo.** In prospettiva i venditori professionali avranno un margine
obiettivo del **16%** contro l'**8%** dei privati.

**L'ostacolo, misurato.** `public.marketplace_config` ammette **una sola riga
corrente**, e non per convenzione: è garantito da un indice unico su
espressione, in
[`20260803150000_phase_7b_stripe_connect_marketplace.sql:71`](../supabase/migrations/20260803150000_phase_7b_stripe_connect_marketplace.sql):

```sql
create unique index marketplace_config_una_corrente
  on public.marketplace_config ((valida_fino is null))
  where valida_fino is null;
```

L'espressione indicizzata è **costante** su tutte le righe che l'indice vede —
per quelle righe `valida_fino is null` vale sempre `true` — quindi la seconda
riga aperta viola l'unicità qualunque cosa contenga. Una tariffa per classe di
venditore non ci sta: non è una questione di spazio nella riga, è una questione
di quante righe possono essere aperte insieme, e la risposta oggi è una.

L'indice appartiene a una migrazione distribuita e **congelata**. Congelata
significa che il file non si modifica; non significa che l'oggetto non si possa
sostituire. Un `drop index` seguito da un `create unique index` in una
migrazione **nuova** è la procedura corretta e non viola il congelamento: è la
stessa disciplina con cui la 7c ha sostituito `order_checkout_reserve` della 7b
senza toccarne il file.

---

## 2. Che cosa NON è il problema

Vale la pena toglierlo di mezzo subito, perché è la parte che sembra difficile.

**Il congelamento sull'ordine è già risolto, e non va progettato.**
`public.orders` ha già le colonne `margine_obiettivo_bps`,
`riferimento_stripe_percentuale_bps`, `riferimento_stripe_fisso_cents` e
`commissione_cents`, scritte alla creazione da `order_checkout_reserve` e mai
più toccate. Quelle colonne significano «i parametri che hanno prodotto questo
ordine» — **non si chiedono da dove vengano**. Se il risolutore le riempie con
la riga professionale invece che con quella privata, l'ordine è congelato
esattamente come prima, con lo stesso meccanismo e con le stesse garanzie.

Ne segue una cosa importante per il confronto: **nessuna delle due strade
introduce un nuovo congelamento, e nessuna delle due lo indebolisce.** Il
criterio «come si preserva l'invariante del congelamento» non discrimina fra A e
B, e sarebbe disonesto presentarlo come se lo facesse. Discrimina invece il
modo in cui le due strade rendono *leggibile* l'ordine dopo: §6.1.

---

## 3. Strada A — una riga di configurazione per classe

Il modello: `marketplace_config` guadagna una colonna `classe_venditore`,
l'indice a riga unica viene sostituito da un indice **a riga unica per classe**,
e il lettore prende la classe come parametro.

```sql
create type public.classe_venditore as enum ('privato', 'professionale');

alter table public.marketplace_config
  add column classe_venditore public.classe_venditore not null
    default 'privato'::public.classe_venditore;

drop index public.marketplace_config_una_corrente;

create unique index marketplace_config_una_corrente_per_classe
  on public.marketplace_config (classe_venditore)
  where valida_fino is null;
```

**Questa forma esiste già in produzione.** Non è un'invenzione di questo
documento: `public.packaging_options`, introdotta dalla 7c e distribuita, è una
configurazione versionata con esattamente questo indice —

```sql
create unique index packaging_options_corrente_idx
  on public.packaging_options (codice) where valida_fino is null;
```

— e con la stessa semantica: una riga corrente **per chiave**, lo storico
nell'intera tabella, la lettura pubblica da una vista a elenco colonne chiuso.
Scegliere la strada A significa applicare a `marketplace_config` la forma che il
progetto ha già scelto, misurato e distribuito per il listino degli imballaggi.

Il lettore cambia firma:

```sql
create or replace function private.marketplace_config_corrente(
  p_classe public.classe_venditore
)
returns public.marketplace_config
```

e **la versione a zero argomenti va eliminata**, non mantenuta come comodità. Un
overload che assume `'privato'` è un difetto latente: un chiamante che dimentica
di passare la classe non fallirebbe, applicherebbe silenziosamente l'8% a un
professionale. Fallire rumorosamente è l'unico comportamento accettabile in un
percorso che decide un addebito. Il chiamante è uno solo —
[`20260804160000_phase_7c_delivery_packaging.sql:762`](../supabase/migrations/20260804160000_phase_7c_delivery_packaging.sql)
— e `order_checkout_reserve` va comunque ricreata.

---

## 4. Strada B — colonne aggiuntive sulla riga corrente

Il modello: la riga resta una, e guadagna un secondo margine.

```sql
alter table public.marketplace_config
  add column margine_obiettivo_professionale_bps integer not null default 1600
    check (margine_obiettivo_professionale_bps between 0 and 5000);
```

L'indice `marketplace_config_una_corrente` non si tocca. Il lettore non cambia
firma: restituisce la riga intera come fa oggi, e la scelta di quale colonna
usare si sposta dentro `order_checkout_reserve`:

```sql
  v_margine := case when v_classe = 'professionale'
                    then v_config.margine_obiettivo_professionale_bps
                    else v_config.margine_obiettivo_bps end;
```

La strada B ha un pregio reale e va detto per primo, perché è quello che la
rende una candidata seria e non un uomo di paglia: **i tre parametri condivisi
restano condivisi per costruzione.** `riferimento_stripe_percentuale_bps`,
`riferimento_stripe_fisso_cents` e `auto_rilascio_giorni` descrivono il costo
del pagamento e la finestra di verifica, che non dipendono da chi vende. Sotto B
è **impossibile** che il valore visto da un professionale differisca da quello
visto da un privato. Sotto A ogni classe ne porta una copia, e due copie che
devono coincidere sono due copie che un giorno non coincidono.

---

## 5. Il problema che nessuna delle due strade risolve da sola

Va isolato perché è il costo vero del cambiamento, e perché è **identico** nelle
due strade sotto un aspetto e diverso sotto un altro.

`public.public_marketplace_config` è una vista **concessa in lettura a `anon` e
`authenticated`**. Serve alla UI per calcolare un preventivo prima che l'ordine
esista. Con due aliquote in vigore, quella vista non può più rispondere «il
margine è N» senza sapere di chi.

**Sotto A la vista cambia forma.** Se `marketplace_config` ha due righe aperte,
la vista ne restituisce due, e il consumatore esistente si rompe. Non
ipoteticamente: in
[`frontend-next/src/services/phase7/marketplace-config-service.ts:29`](../frontend-next/src/services/phase7/marketplace-config-service.ts)
la lettura termina con `.maybeSingle()`, che con due righe restituisce un errore
PostgREST invece di un valore. È un **fallimento rumoroso**, il che è la cosa
giusta — meglio un errore che un preventivo calcolato con l'aliquota sbagliata —
ma significa che la migrazione e la modifica di `frontend-next/` devono essere
lo stesso cambiamento, non due.

**Sotto B la vista cambia contenuto, non forma.** Resta una riga, con una
colonna in più. Il consumatore non si rompe: continua a leggere quattro colonne
e a ottenere l'aliquota **privata**. Se l'annuncio che sta preventivando è di un
professionale, mostra un totale sbagliato **senza alcun errore**. È un
fallimento silenzioso, ed è peggio.

**In entrambi i casi serve una seconda cosa, ed è quella che costa.** Per
preventivare correttamente, il client deve sapere **a quale classe appartiene il
venditore dell'annuncio che sta guardando**. Oggi non può saperlo:
`public.public_listings` espone `seller_id`, `seller_username`, `seller_citta`,
`seller_avatar_url` e nient'altro di rilevante. Serve una colonna
`venditore_classe` in coda a quella vista — `create or replace view` consente di
aggiungere colonne alla fine, mai di riordinarle, e la 7c ha già usato quella
possibilità per `imballaggio_codice`.

Questa non è una perdita di riservatezza da soppesare: **è un obbligo.** Il
Digital Services Act, per le piattaforme che permettono a consumatori di
concludere contratti a distanza con **operatori commerciali**, richiede proprio
che l'interfaccia renda riconoscibile chi sta vendendo. Rendere pubblica la
classe del venditore non è un effetto collaterale sgradito della tariffa
differenziata: è una cosa che andrà fatta comunque nel momento in cui si
ammettono venditori professionali. Vedi §12.

---

## 6. Il confronto, sui quattro criteri richiesti

### 6.1 Come si preserva l'invariante del congelamento

**Pari, con una differenza di leggibilità.** Come scritto in §2, entrambe le
strade scrivono il valore risolto nelle colonne già esistenti di `orders`, e
l'ordine resta congelato con lo stesso meccanismo.

La differenza è che l'ordine, dopo, **non dice più perché** ha quel margine. Con
un'unica aliquota, `margine_obiettivo_bps = 800` era spiegazione sufficiente.
Con due, `1600` lascia aperta la domanda «perché a costui il 16%?», e la risposta
— la classe del venditore al momento della vendita — non è ricostruibile
guardando il profilo, perché la classe può essere cambiata nel frattempo.

**Entrambe le strade devono quindi congelare anche la classe**:

```sql
alter table public.orders
  add column venditore_classe public.classe_venditore not null
    default 'privato'::public.classe_venditore;
```

È esattamente l'argomento che la 7b usa per congelare i tre parametri e non solo
il risultato: «senza di essi un ordine vecchio non è più spiegabile una volta
che la configurazione è cambiata». Qui l'oggetto che cambia non è la
configurazione ma il venditore, e la conseguenza è la stessa.

Nota che sotto la strada B questa colonna richiede comunque il tipo enum
`classe_venditore`, che B non avrebbe altrimenti bisogno di creare. Il vantaggio
di B di «non introdurre una tassonomia» si assottiglia: la tassonomia serve
comunque sull'ordine.

### 6.2 Come si determina in modo autoritativo la classe, senza che il client possa influenzarla

**Ortogonale alle due strade: il meccanismo è identico.** Va progettato bene una
volta sola, e non è l'argomento che sceglie fra A e B.

Il progetto ha già **due** precedenti, e sono di forza diversa.

**Precedente forte — `seller_enabled`.** Il ruolo non è un flag che qualcuno
assegna: è una conseguenza. `private.seller_enabled_sync()` è un **trigger** su
`seller_payout_accounts` che scrive `public.user_roles` quando il fornitore
dichiara insieme `charges_enabled` e `payouts_enabled`, e lo revoca appena una
delle due decade. Il commento della 7b spiega perché è un trigger e non una RPC:
«così vincola anche `service_role`, che delle RPC può fare a meno».

**Precedente fortissimo — il verdetto delle qualifiche.**
`20260827160000_d1_professional_qualifications.sql` impedisce il passaggio a
`approvata` con un trigger che rifiuta la transizione **a meno che la sessione
non porti un marcatore impostato con `set local` dentro la transazione
dell'unica porta di review**. Ne segue che nessuna sessione autenticata può
approvarsi, e **nemmeno `service_role` con una `UPDATE` diretta**.

**Il disegno proposto**, che prende dal primo la forma e dal secondo la
severità:

- un ruolo `venditore_professionale` in `public.user_roles`. La tabella è già
  «separata dal profilo per anti-escalation», non ha alcun `grant insert/update/
  delete` verso `authenticated`, e ha RLS attiva;
- **nessun** percorso client per ottenerlo. Si scrive solo da una porta
  `SECURITY DEFINER` concessa al solo `service_role`, che rifiuta ogni chiamata
  che porti con sé un `auth.uid()` — la forma della porta di review;
- un trigger su `user_roles` che rifiuta l'inserimento di quel ruolo specifico
  senza il marcatore di sessione, così che neppure una `UPDATE` privilegiata
  possa promuovere un venditore;
- la lettura al checkout avviene con `public.has_role(v_listing.seller_id,
  'venditore_professionale')`.

**Due avvertenze da non perdere.**

*La prima è una regola della costituzione:* `public.has_role()` non va usata
dentro una policy RLS a privilegio del chiamante quando il chiamante non ha
`SELECT` su `user_roles`. Qui non è quel caso — la chiamata avviene dentro
`order_checkout_reserve`, che è `SECURITY DEFINER`, e per di più
`authenticated` ha `grant select on public.user_roles`. È lecito, e va scritto
esplicitamente perché un implementatore futuro non ci inciampi in senso
contrario.

*La seconda è una correzione.* **`public.professional_qualifications` non è la
sorgente giusta**, e l'omonimia è ingannevole. Quella tabella contiene
*qualifiche professionali di una persona* — un diploma da sommelier,
un'iscrizione a un albo, un attestato — e il suo stesso file dice che non
esiste una tassonomia chiusa dei titoli. Un venditore professionale è invece un
**operatore commerciale**: una partita IVA, un'attività di vendita, un soggetto
con obblighi. Le due cose non coincidono e non devono collassare l'una
sull'altra: un appassionato con un diploma da sommelier che vende due bottiglie
l'anno non è un operatore commerciale, e pagherebbe il 16% per errore di
modello. Lo stesso file delle qualifiche fa già questa distinzione fra
`profile_certifications` e sé stesso, con le stesse parole: «non sono la stessa
affermazione».

**Il client non può influenzarla** perché non esiste un percorso in cui il
client dica qualcosa sulla classe: non è un parametro di
`order_checkout_reserve`, non è una colonna scrivibile, non è un ruolo
auto-assegnabile, e il risolutore legge il `seller_id` **dall'annuncio già
bloccato**, non da un argomento.

### 6.3 Un venditore che cambia classe mentre ha ordini in corso

**Pari fra le due strade, e già risolto dall'architettura esistente.**

Gli ordini già creati **non si muovono**, qualunque cosa accada alla classe: i
parametri sono congelati su `orders`, il compratore è già stato addebitato
`payments.amount_cents`, e nessun percorso li rilegge. Questo vale per ogni
stato successivo alla creazione — pagamento, consegna, verifica, rilascio,
contestazione, rimborso. Non serve alcun trattamento speciale, e **progettarne
uno sarebbe un errore**.

Il caso limite apparente — un ordine in `in_attesa_pagamento` con la finestra di
prenotazione di 30 minuti ancora aperta — non è un'eccezione: l'ordine
**esiste**, quindi è già congelato, e la sessione di checkout presso il
fornitore porta già l'importo.

Il caso limite **vero** è un altro, e va detto: un annuncio pubblicato quando il
venditore era privato, guardato da un compratore che vede il preventivo all'8%,
e acquistato dopo che il venditore è diventato professionale. Il compratore paga
un totale più alto di quello che gli era stato mostrato.

Non è un difetto del congelamento — è un difetto del **preventivo**, e ha già
oggi la stessa forma per qualunque modifica di `marketplace_config`. Le
mitigazioni sono di prodotto, non di schema:

1. il preventivo va letto al momento del rendering, non memorizzato in cache
   lunga;
2. `order_checkout_reserve` restituisce già `amount_cents`,
   `prezzo_venditore_cents` e `commissione_cents` **prima** che il compratore
   paghi: la schermata di conferma deve mostrare quei numeri, che sono
   l'autorità, e non quelli del preventivo;
3. un cambio di classe è un evento raro e volontario: si può richiedere che
   avvenga quando il venditore non ha annunci in stato `riservato`.

Una differenza fra le strade esiste, ed è piccola: sotto A il preventivo può
essere corretto perché la vista sa distinguere le classi; sotto B il preventivo
resta strutturalmente sbagliato per i professionali finché non si aggiunge
comunque una colonna alla vista, cioè finché non si fa il lavoro che A impone
subito. **B non evita quel lavoro: lo rimanda, e nel frattempo sbaglia in
silenzio.**

### 6.4 Quale rende più semplice una terza classe

**A, senza confronto.** È il criterio su cui le due strade divergono di più.

Terza classe sotto **A**:

```sql
alter type public.classe_venditore add value 'associazione';

insert into public.marketplace_config (classe_venditore, margine_obiettivo_bps, ...)
values ('associazione', 1200, ...);
```

Una label e una riga. **Il risolutore non cambia**: `where classe_venditore =
v_classe and valida_fino is null` continua a funzionare. La vista non cambia. La
griglia guadagna casi, non forme.

Terza classe sotto **B**:

- una colonna nuova, `margine_obiettivo_associazione_bps`, con il suo `check`;
- un ramo nuovo nel `case` dentro `order_checkout_reserve`, che va ricreata;
- una colonna nuova nella vista pubblica, e il consumatore che deve saperla
  scegliere;
- una riga nuova in ogni documento che elenca le colonne.

Sotto A aggiungere una classe è un **dato**. Sotto B è una **migrazione di
schema** che tocca la configurazione, la funzione di checkout e la superficie
pubblica. La differenza cresce con il numero di classi e non decresce mai.

C'è un secondo aspetto, più sottile. Sotto B il nome della colonna **incorpora
la tassonomia di prodotto dentro lo schema**. È precisamente ciò che la
migrazione delle qualifiche ha rifiutato di fare, e con un argomento che vale
identico qui: un elenco chiuso di specie scritto in una migrazione tecnica «è
una decisione di prodotto presa dentro una migrazione tecnica, e sarebbe
sbagliata il giorno in cui si presenta il primo caso che non vi rientra». Sotto A
la tassonomia sta in un `enum` — che resta una decisione di prodotto, ma
dichiarata in un posto solo, con un nome, e ampliabile senza toccare la forma di
nulla.

### 6.5 Il quadro

| Criterio | Strada A — riga per classe | Strada B — colonne aggiuntive |
| --- | --- | --- |
| Congelamento sull'ordine | Invariato. Richiede `orders.venditore_classe`. | Invariato. Richiede `orders.venditore_classe` **e quindi l'enum comunque**. |
| Determinazione della classe | Identica. Ruolo + trigger + porta `service_role`. | Identica. |
| Cambio di classe con ordini in corso | Nessun effetto sugli ordini esistenti. | Nessun effetto sugli ordini esistenti. |
| Parametri condivisi (`riferimento_*`, `auto_rilascio_giorni`) | **Duplicati per classe.** Possono divergere. È il punto debole di A. | **Condivisi per costruzione.** È il punto forte di B. |
| Vista pubblica | Si rompe rumorosamente. Va cambiata insieme al client. | Continua a funzionare **sbagliando in silenzio** per i professionali. |
| Terza classe | Una label e una riga. | Una colonna, un ramo, una vista, una funzione ricreata. |
| Forma già in produzione nel repository | **Sì**: `packaging_options_corrente_idx`. | No. |
| Rischio operativo tipico | Chiudere una riga senza riaprirla lascia una classe senza configurazione. | Un consumatore dimentica di scegliere la colonna giusta. |
| Come si manifesta quel rischio | `order_checkout_reserve` solleva «Configurazione di mercato mancante»: **fail-closed**. | Addebito calcolato con l'aliquota sbagliata: **fail-open**. |

---

## 7. Raccomandazione

**Strada A — una riga di configurazione per classe di venditore.**

Tre ragioni, in ordine di peso.

**1. I modi in cui A si rompe sono rumorosi; quelli di B sono silenziosi.**
È l'ultima riga della tabella, ed è la ragione decisiva in un dominio dove
l'errore è un addebito sbagliato. Sotto A, dimenticare di aprire la riga di una
classe fa fallire il checkout con un messaggio esplicito, e il fallimento
avviene **prima** che qualcuno paghi. Sotto B, dimenticare di leggere la colonna
giusta produce un ordine perfettamente valido con l'aliquota sbagliata, che
nessuno nota finché non lo si cerca. Il progetto ha appena passato una giornata
a correggere un parametro che dichiarava un margine del 5% e ne realizzava uno
del 4,38% senza che nulla segnalasse niente: è esattamente la classe di difetto
che B rende più probabile.

**2. Una terza classe costa un dato, non una migrazione.** L'ipotesi «una terza
classe» non è remota: enoteche, associazioni, cantine e importatori sono
categorie diverse con economie diverse, e il documento di ammissione parla già
di *classi*, al plurale implicito. Sotto A quel futuro costa una `insert`.

**3. La forma è già in produzione e già misurata.** `packaging_options` usa
esattamente `unique (chiave) where valida_fino is null` dal 4 agosto 2026.
Scegliere A non introduce un modello nuovo nel progetto: estende a
`marketplace_config` quello che il progetto ha già scelto per l'altra sua
configurazione versionata. Scegliere B introdurrebbe un secondo modello per lo
stesso problema.

**Il punto debole di A va però mitigato, non ignorato.** I parametri condivisi
duplicati per classe possono divergere. Due mitigazioni, entrambe economiche:

- **regola operativa, resa esplicita nel commento della tabella**: una
  variazione di `riferimento_*` o di `auto_rilascio_giorni` chiude e riapre
  **tutte** le righe correnti nella stessa transazione. È già la disciplina con
  cui è stata scritta la migrazione dell'8%, estesa a N righe invece che a una;
- **un caso di griglia** che afferma che tutte le righe aperte concordano sui
  tre parametri condivisi, così che una divergenza si veda prima del rilascio.

Un `constraint trigger` differito che imponga l'invariante a livello di database
sarebbe possibile — la 7c ne usa uno per `orders_contestazione_ha_pratica` — ma
**non lo raccomando in partenza**: un giorno potrebbe essere legittimo che una
classe abbia una finestra di verifica diversa, e un vincolo che vieta ciò che il
prodotto potrebbe volere costa più di quanto protegga. La griglia dice la stessa
cosa senza chiudere la porta.

---

## 8. Che cosa comporta implementarla, per intero

Perché la raccomandazione sia una decisione e non un'opinione, ecco l'elenco
completo di ciò che va toccato. Non è breve, ed è giusto vederlo prima.

| Oggetto | Intervento |
| --- | --- |
| `public.classe_venditore` | Tipo enum nuovo. |
| `public.marketplace_config` | Colonna `classe_venditore`; indice sostituito; riga professionale aperta. |
| `private.marketplace_config_corrente()` | Firma cambiata; versione a zero argomenti **eliminata**. |
| `public.public_marketplace_config` | Ricreata con `classe_venditore` in coda. **Cambio incompatibile per i consumatori.** |
| `public.public_listings` | Ricreata con `venditore_classe` in coda. |
| `public.orders` | Colonna `venditore_classe` congelata alla creazione. |
| `public.order_checkout_reserve` | Ricreata dalla versione 7c: risolve la classe, legge la riga giusta, congela la classe. |
| `public.user_roles` | Ruolo `venditore_professionale`; trigger di protezione; porta `service_role`. |
| `public.order_margine_riconciliazione` | `venditore_classe` in coda, per poter separare i conti economici. |
| `frontend-next/src/services/phase7/marketplace-config-service.ts` | **Obbligatorio e simultaneo**: `.maybeSingle()` non sopravvive a due righe. |
| Superfici di preventivo in `frontend-next/` | Devono leggere la classe dell'annuncio e scegliere la riga. |
| `supabase/tests/` | Griglia nuova, con corsa di controllo. |
| Documentazione economica | `ROADMAP_V1.md`, `MIGRATION_PHASE_1_BACKLOG.md`, `CONTESTO_IA/01_STATO_ATTUALE.md`. |

**Questo elenco tocca `frontend-next/`**, che è escluso dal perimetro della
sessione che ha prodotto questo documento e che quindi non è stato modificato.
L'implementazione non può però essere solo di database: una migrazione applicata
senza la modifica del servizio lascia il preventivo in errore per tutti,
professionali e privati.

---

## 9. L'SQL proposto per la strada A — mostrato, non applicato

> **Questo blocco non è un file di migrazione.** Non esiste sotto
> `supabase/migrations/`, non è stato eseguito su nessun database, e il suo
> `timestamp` è un segnaposto.
>
> Nota su `alter type ... add value`: PostgreSQL **non** consente di usare una
> label di enum appena aggiunta nella stessa transazione in cui è stata creata.
> Per questo il tipo è creato per intero con entrambe le label, e una terza
> classe futura richiederà due migrazioni separate o un `add value` in una
> migrazione che non la usa.

```sql
-- supabase/migrations/AAAAMMGGhhmmss_aliquota_per_classe_venditore.sql  [PROPOSTA]

begin;

-- ---------------------------------------------------------------------------
-- 1. La tassonomia, in un posto solo
-- ---------------------------------------------------------------------------

create type public.classe_venditore as enum ('privato', 'professionale');

comment on type public.classe_venditore is
  'Classe economica del venditore. NON è una qualifica professionale della '
  'persona (public.professional_qualifications): è la natura commerciale di '
  'chi vende. Un appassionato con un diploma da sommelier resta privato.';

-- ---------------------------------------------------------------------------
-- 2. Una riga corrente per classe
-- ---------------------------------------------------------------------------

alter table public.marketplace_config
  add column classe_venditore public.classe_venditore not null
    default 'privato'::public.classe_venditore;

-- Le righe esistenti — quella iniziale chiusa e quella dell'8% corrente —
-- diventano righe della classe 'privato'. È ciò che sono sempre state: fino a
-- oggi la piattaforma mette in contatto solo privati.

drop index public.marketplace_config_una_corrente;

-- Stessa forma di packaging_options_corrente_idx: una riga aperta PER CHIAVE.
create unique index marketplace_config_una_corrente_per_classe
  on public.marketplace_config (classe_venditore)
  where valida_fino is null;

comment on table public.marketplace_config is
  'Configurazione di mercato versionata, UNA RIGA CORRENTE PER CLASSE DI '
  'VENDITORE; le righe chiuse restano come storico. I parametri applicati a un '
  'ordine sono congelati sull''ordine stesso e non si rileggono da qui. '
  'REGOLA OPERATIVA: una variazione dei parametri condivisi — riferimento_* e '
  'auto_rilascio_giorni — chiude e riapre TUTTE le righe correnti nella stessa '
  'transazione. Righe aperte che divergono su quei tre parametri sono un '
  'difetto, non una configurazione.';

-- La riga della classe professionale. I tre parametri condivisi sono ripetuti
-- identici a quelli della riga privata corrente, letti da lì e non riscritti a
-- mano: è l'unico modo perché la ripetizione non diventi una divergenza già
-- alla nascita.
insert into public.marketplace_config (
  classe_venditore, margine_obiettivo_bps,
  riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents,
  auto_rilascio_giorni, valida_da, nota
)
select
  'professionale'::public.classe_venditore, 1600,
  c.riferimento_stripe_percentuale_bps, c.riferimento_stripe_fisso_cents,
  c.auto_rilascio_giorni, now(),
  'Margine obiettivo 16% per i venditori professionali. I tre parametri '
  'condivisi sono copiati dalla riga privata corrente: descrivono il costo del '
  'pagamento e la finestra di verifica, che non dipendono da chi vende.'
from public.marketplace_config c
where c.valida_fino is null
  and c.classe_venditore = 'privato'::public.classe_venditore;

-- ---------------------------------------------------------------------------
-- 3. Il lettore prende la classe. Nessun overload a zero argomenti.
-- ---------------------------------------------------------------------------

drop function private.marketplace_config_corrente();

create or replace function private.marketplace_config_corrente(
  p_classe public.classe_venditore
)
returns public.marketplace_config
language sql
security definer
set search_path = ''
stable
as $$
  select * from public.marketplace_config
  where valida_fino is null
    and classe_venditore = p_classe
  order by valida_da desc
  limit 1;
$$;

revoke execute on function
  private.marketplace_config_corrente(public.classe_venditore)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Il ruolo, e la porta che lo scrive
-- ---------------------------------------------------------------------------

create or replace function private.venditore_classe(p_seller_id uuid)
returns public.classe_venditore
language sql
security definer
set search_path = ''
stable
as $$
  select case
    when exists (
      select 1 from public.user_roles r
      where r.user_id = p_seller_id
        and r.role = 'venditore_professionale'
    )
    then 'professionale'::public.classe_venditore
    else 'privato'::public.classe_venditore
  end;
$$;

revoke execute on function private.venditore_classe(uuid)
  from public, anon, authenticated;

-- Il ruolo non è auto-assegnabile e non è assegnabile con una UPDATE diretta:
-- il trigger pretende il marcatore di sessione che solo la porta imposta. È la
-- forma del verdetto delle qualifiche professionali (20260827160000).
create or replace function private.venditore_professionale_guardia()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role = 'venditore_professionale'
     and coalesce(current_setting('vinea.classe_venditore_porta', true), '') <> 'si' then
    raise exception
      'Il ruolo venditore_professionale si assegna solo dalla porta dedicata.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger user_roles_venditore_professionale_guardia
  before insert or update on public.user_roles
  for each row execute function private.venditore_professionale_guardia();

create or replace function public.venditore_classe_imposta(
  p_seller_id uuid,
  p_professionale boolean
)
returns public.classe_venditore
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- La porta è per l'esecutore fidato: una chiamata che porta con sé
  -- un'identità di sessione non è quella, ed è rifiutata.
  if auth.uid() is not null then
    raise exception 'Porta riservata all''esecutore fidato.' using errcode = '42501';
  end if;

  perform set_config('vinea.classe_venditore_porta', 'si', true);

  if coalesce(p_professionale, false) then
    insert into public.user_roles (user_id, role)
    values (p_seller_id, 'venditore_professionale')
    on conflict (user_id, role) do nothing;
  else
    delete from public.user_roles
    where user_id = p_seller_id and role = 'venditore_professionale';
  end if;

  return private.venditore_classe(p_seller_id);
end;
$$;

revoke execute on function public.venditore_classe_imposta(uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.venditore_classe_imposta(uuid, boolean)
  to service_role;

-- ---------------------------------------------------------------------------
-- 5. Il congelamento della classe sull'ordine
-- ---------------------------------------------------------------------------

alter table public.orders
  add column venditore_classe public.classe_venditore not null
    default 'privato'::public.classe_venditore;

comment on column public.orders.venditore_classe is
  'Classe del venditore al momento della creazione, congelata. Senza di essa '
  'un margine del 16% non sarebbe più spiegabile il giorno in cui il venditore '
  'cambia classe. Nessun percorso la rilegge dopo la creazione.';

grant select (venditore_classe) on public.orders to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Le viste pubbliche
-- ---------------------------------------------------------------------------
--
-- CAMBIO INCOMPATIBILE: la vista restituisce ora una riga PER CLASSE. Il
-- consumatore in frontend-next/src/services/phase7/marketplace-config-service.ts
-- usa .maybeSingle() e fallisce con due righe. È un fallimento rumoroso e
-- voluto, ma la modifica del servizio deve far parte dello stesso cambiamento.

create or replace view public.public_marketplace_config
with (security_invoker = off, security_barrier = true)
as
select
  c.margine_obiettivo_bps,
  c.riferimento_stripe_percentuale_bps,
  c.riferimento_stripe_fisso_cents,
  c.auto_rilascio_giorni,
  -- In coda: `create or replace view` consente di aggiungere colonne alla
  -- fine, mai di rinominarle o riordinarle.
  c.classe_venditore
from public.marketplace_config c
where c.valida_fino is null;

comment on view public.public_marketplace_config is
  'Configurazione corrente PER CLASSE DI VENDITORE, a elenco colonne chiuso. '
  'Una riga per classe: chi preventiva deve filtrare sulla classe del '
  'venditore dell''annuncio, esposta da public_listings.venditore_classe. Non '
  'è la fonte di ciò che viene addebitato, che è congelato sull''ordine.';

-- public_listings guadagna la classe in coda. Non è un'esposizione da
-- soppesare: rendere riconoscibile chi vende come operatore commerciale è un
-- obbligo, non una scelta. Vedi §12 del documento di progettazione.
--
-- [la vista va ricreata per intero dalla versione 7c, con
--  `private.venditore_classe(l.seller_id) as venditore_classe` in coda]

-- ---------------------------------------------------------------------------
-- 7. order_checkout_reserve: risolve la classe e la congela
-- ---------------------------------------------------------------------------
--
-- Ricreata per intero dalla versione 7c. Cambiano tre punti:
--
--   (a)  v_classe := private.venditore_classe(v_listing.seller_id);
--        v_config := private.marketplace_config_corrente(v_classe);
--
--        `v_listing` è già sotto `for update`: il seller_id non viene da un
--        argomento del chiamante.
--
--   (b)  l'INSERT into public.orders guadagna `venditore_classe` con `v_classe`;
--
--   (c)  il payload di order_events 'checkout_reserved' guadagna
--        'venditore_classe'.
--
-- Il controllo `if v_config.id is null then raise ... 'Configurazione di
-- mercato mancante.'` resta e diventa MOLTO più importante: è ciò che rende
-- fail-closed una classe rimasta senza riga aperta.

commit;
```

---

## 10. La griglia che servirebbe

Forma già usata da `supabase/tests/marketplace_config_margine_otto.sql`, con
**corsa di controllo prima della migrazione**.

| # | Caso |
| --- | --- |
| 01 | Esiste esattamente **una** riga aperta per classe, e le classi aperte sono due. |
| 02 | L'indice `marketplace_config_una_corrente` non esiste più; esiste `marketplace_config_una_corrente_per_classe`. |
| 03 | Una seconda riga aperta della **stessa** classe viene rifiutata dall'indice. |
| 04 | Una riga aperta di una **terza** classe sarebbe accettata — cioè il modello è estensibile. |
| 05 | Le righe storiche già esistenti sono `classe_venditore = 'privato'`. |
| 06 | Le due righe aperte **concordano** su `riferimento_stripe_percentuale_bps`, `riferimento_stripe_fisso_cents`, `auto_rilascio_giorni`. È la mitigazione del punto debole della strada A. |
| 07 | La riga professionale ha `margine_obiettivo_bps = 1600`; la privata `800`. |
| 08 | `private.marketplace_config_corrente()` a zero argomenti **non esiste più**. |
| 09 | `private.marketplace_config_corrente('professionale')` restituisce la riga professionale. |
| 10 | `public.public_marketplace_config` espone **cinque** colonne e **due** righe. |
| 11 | Un ordine da venditore privato congela `800` e `venditore_classe = 'privato'`. |
| 12 | Un ordine da venditore professionale congela `1600` e `'professionale'`. |
| 13 | Su 4500 cents: privato → 4990; professionale → totale calcolato con 1600 bps e la stessa formula, **senza** che `marketplace_totale_cents` sia stata toccata. |
| 14 | Il venditore diventa professionale **dopo** la creazione di un ordine: l'ordine non si muove, in nessuna delle sue colonne economiche. |
| 15 | Il venditore torna privato: idem. |
| 16 | `authenticated` non può inserire `venditore_professionale` in `user_roles` (nessun grant). |
| 17 | Una `INSERT` diretta di `service_role` in `user_roles` **senza** la porta viene rifiutata dal trigger con `42501`. |
| 18 | `venditore_classe_imposta` chiamata con un `auth.uid()` presente solleva `42501`. |
| 19 | Chiudere la riga privata senza riaprirla fa fallire il checkout di un venditore privato con «Configurazione di mercato mancante»: **fail-closed misurato**, non dichiarato. |
| 20 | `public_listings` espone `venditore_classe` e il valore corrisponde al ruolo del venditore. |

---

## 11. Domande ancora aperte

**11.1 Chi decide chi è professionale, e con quale prova?** La porta tecnica è
progettata; il processo no. Serve una dichiarazione del venditore? Una partita
IVA verificata? Una soglia di volume oltre la quale la classificazione è
obbligatoria per legge indipendentemente dalla volontà dell'interessato? La
terza ipotesi è la più insidiosa, perché renderebbe la classificazione un
obbligo della piattaforma e non una scelta del venditore. **Decisione di Enrico,
informata dal §12.**

**11.2 Il 16% si applica anche agli annunci già pubblicati?** Progettato qui:
sì, dal momento della classificazione in avanti, perché la classe si legge al
checkout. L'alternativa — applicare il 16% solo agli annunci pubblicati dopo la
classificazione — richiederebbe di congelare la classe sull'**annuncio** e non
sul venditore. È la stessa domanda della §13.2 del documento sulla vetrina, e
converrebbe rispondere alle due nello stesso modo.

**11.3 L'aliquota della vetrina è anch'essa per classe?** Con la strada A la
risposta è gratuita: `vetrina_bps` vivrebbe sulla riga, quindi sarebbe per
classe automaticamente, e occorre **decidere** se sia ciò che si vuole o se le
due righe debbano portare lo stesso valore. Sotto la strada B servirebbe una
colonna in più. Vedi
[Vetrina a successo §13.5](VETRINA_A_SUCCESSO_SPEC.md).

**11.4 Che cosa succede al Club e alla reputazione?** Un venditore professionale
dentro una comunità nata fra privati cambia il tono del prodotto prima ancora
che l'economia. Fuori dal perimetro di questo documento, ma non fuori dalla
decisione.

**11.5 Il margine del 16% è netto dopo la fee, come quello dell'8%?** Sì per
costruzione: `margine_obiettivo_bps` entra nella stessa formula, che non viene
toccata. Va però verificato che il rincaro risultante sia commercialmente
sostenibile per un professionale — su 45,00 € il compratore pagherebbe circa
53,90 € invece di 49,90 €, e la differenza è visibile. **È una verifica
commerciale, non tecnica**, e va fatta prima di fissare il numero.

---

## 12. Dipendenza esterna: gli obblighi del Digital Services Act

**Registrata come dipendenza esterna e non come lavoro tecnico. Non viene
risolta qui.**

Oggi Vinea mette in contatto **soltanto privati**. Gli obblighi che il
Regolamento (UE) 2022/2065 — Digital Services Act — impone alle piattaforme che
permettono ai consumatori di concludere contratti a distanza con **operatori
commerciali** non si applicano, per il semplice fatto che quegli operatori non
ci sono.

**Ammettere venditori professionali li attiva.** In particolare:

- **articolo 30 — tracciabilità degli operatori commerciali**: prima di
  consentire l'uso della piattaforma, vanno raccolte e, per quanto possibile,
  verificate una serie di informazioni sull'operatore (identificazione, recapiti,
  estremi del conto di pagamento, registro di iscrizione, autocertificazione di
  conformità), e non è consentito lasciarlo operare finché le informazioni sono
  incomplete o inattendibili;
- **articolo 31 — conformità fin dalla progettazione**: l'interfaccia deve
  permettere all'operatore di fornire le informazioni precontrattuali dovute al
  consumatore, e la piattaforma deve compiere sforzi ragionevoli per verificare
  che siano disponibili;
- **articolo 32 — diritto all'informazione**: se la piattaforma viene a
  conoscenza di un prodotto illegale offerto da un operatore, deve informare i
  consumatori che lo hanno acquistato.

**Due note per chi raccoglierà le risposte.**

*Sovrapposizione con Stripe Connect, parziale.* I dati che l'articolo 30
richiede somigliano a quelli che Stripe raccoglie per il proprio KYC e che
alimentano `public.seller_payout_accounts`. **Non sono la stessa cosa**: la
raccolta di Stripe serve a Stripe, la piattaforma ne riceve solo i tre booleani
`charges_enabled`, `payouts_enabled` e `details_submitted`, e quei booleani non
dicono nulla su registro di iscrizione o autocertificazione. Assumere che «se
Stripe l'ha abilitato allora l'articolo 30 è soddisfatto» sarebbe un errore, e
va scritto perché è l'errore naturale da commettere.

*Conseguenza tecnica già visibile.* L'articolo 31 e, più in generale, l'obbligo
di rendere riconoscibile chi vende, rendono la colonna `venditore_classe` di
`public_listings` (§5, §9) **non una scelta ma un requisito**. È l'unico punto
in cui la dipendenza esterna e il disegno tecnico si incontrano già oggi, e va
tenuto presente: se il DSA impone comunque di dichiarare la classe, l'argomento
di riservatezza contro la strada A perde il suo ultimo appiglio.

**Conseguenza operativa:** finché queste risposte non esistono, la tariffa
differenziata può essere progettata — questo documento — ma **la classe
professionale non può essere assegnata a nessuno**. Il prerequisito è esterno e
precede l'implementazione, non la segue. `PAYMENTS_ENABLED` resta `false` e
questo documento non lo tocca in alcun modo.
