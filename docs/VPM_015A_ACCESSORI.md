# VPM-015A — Accessori Vinea: fondazione Beta

Contratto della fondazione del catalogo Accessori. Stato operativo e verifiche di
produzione stanno in `../CHANGES.log`; la regola durevole è in
`../CONTESTO_IA/03_ARCHITETTURA_REGOLE_DEBITI.md`.

## Perimetro e decisione

Il titolare ha approvato **per nome** la realizzazione di questa fondazione
(eccezione al «nessuna nuova funzionalità durante la migrazione») e **non**
l'attivazione commerciale. VPM-015A costruisce un catalogo e un'area admin;
non attiva vendite, pagamenti, commissioni o spedizioni.

### Correzioni approvate dal titolare (20 ottobre 2026)

Dopo la prima consegna il titolare ha deciso, e questo documento le recepisce:

1. **Pubblicare il catalogo richiede l'approvazione esplicita del titolare.** Un
   admin Vinea ordinario non può attivare la visibilità pubblica
   (sezione «Rilascio controllato dal titolare»).
2. **Le foto delle bozze sono realmente private**: il bucket non è più
   pubblico e un percorso noto non apre nulla (sezione «Foto private»).
3. **Navigazione mobile futura**: Accessori potrà sostituire Home, cinque
   pulsanti, con il marchio come collegamento alla Home. È predisposta e
   spenta; non si accende finché il catalogo non è autorizzato.
4. **«Accessori della cantina» sul profilo utente**: ancora in valutazione,
   **non implementata** in questo task.
5. **Nomenclatura delle categorie**: sarà rivista in seguito. Le categorie sono
   righe, non enum: rinominarle o aggiungerne non richiede una migrazione di
   schema.

Poiché `20261020120000` era già sul branch remoto, è congelata: le correzioni
stanno nella migrazione successiva `20261020170000`.

Gli «accessori» già citati nel codice (`packaging_options`, componenti di
spedizione, imballaggio) sono costi logistici di una transazione di vino. **Non
sono** prodotti enologici del nuovo catalogo e non vengono toccati.

## Architettura

Tutto vive in schema `private`, senza grant ai ruoli client e senza viste. Le
sole porte sono funzioni `public.accessori_*`.

| Oggetto | Ruolo |
|---|---|
| `private.accessori_categorie` | Tassonomia a **due livelli** (categoria → sottocategoria), estensibile con righe, non con enum. Slug stabile, `ordine`, `attiva`. Seed della sola tassonomia. |
| `private.accessori` | Schede catalogo dedicate. Stato `bozza → pubblicato → archiviato` (`archiviato → bozza` per riaprire). |
| `private.accessori_impostazioni` | Una riga. `visibilita_pubblica` **spenta di default**: seconda chiave oltre la flag d'ambiente. |
| `private.accessori_registro` | Registro append-only delle azioni admin. |
| bucket `accessori-media` | **Privato.** Solo `image/webp` fino a 2 MB. Caricamento ed elenco riservati all'admin reale; lettura solo con URL firmata (vedi «Foto private»); percorso `<accessorio>/<uuid>.webp`. |

### Colonne di `private.accessori`

`id`, `categoria_id`, `slug` (3–80, minuscolo, non `categoria`), `nome` (2–120),
`descrizione` (≤ 2000), `marchio` (testo libero ≤ 80), `condizione`
(`nuovo | come_nuovo | usato | da_collezione`), `quantita` (interna, 0–100000),
`attributi` (oggetto chiuso: ≤ 12 coppie testo, chiave `[a-z][a-z0-9_]{0,31}`,
valore 1–120), `immagini` (≤ 6 percorsi), `stato`, `pubblicato_il`,
`creato_da`, `aggiornato_da`, `created_at`, `updated_at`.

### Porte

- Pubbliche (`anon` e `authenticated`, elenco chiuso di campi):
  `accessori_categorie_elenca`, `accessori_elenca`, `accessori_dettaglio`. Con
  l'interruttore spento tornano vuote (`[]`/`null`). Il JSON pubblico ha **8 chiavi**
  (`slug nome descrizione marchio condizione attributi immagini categoria`): mai
  `quantita`, `stato`, `id` o date.
- `p_anteprima = true` (stesse funzioni): solo l'admin reale, bozze incluse,
  interruttore ignorato, con `stato` nel JSON. Altrimenti `42501`.
- Admin (solo `authenticated`, ciascuna ricontrolla il ruolo):
  `accessori_admin_stato`, `_categorie_elenca`, `_categoria_salva`, `_elenca`,
  `_dettaglio`, `_salva`, `_immagini_imposta`, `_stato_imposta`,
  `_visibilita_imposta` (motivo obbligatorio, registrata): **accendere richiede
  il ruolo di rilascio `accessori_release`**, spegnere un admin qualsiasi.
  `accessori_admin_stato` restituisce anche `puo_rilasciare`.
- Tutte le letture sono `stable`, tutte le scritture volatili (modo transazione
  PostgREST); `security definer` con `search_path = ''`.

I trigger vincolano anche i writer privilegiati: nascita solo in bozza,
macchina a stati, slug bloccato dopo la prima pubblicazione, forma di attributi
e immagini, completezza minima per pubblicare (descrizione ≥ 10 caratteri, ≥ 1
immagine, categoria attiva), nessuna `DELETE`/`TRUNCATE` (si archivia o si
disattiva).

## Identità e autorizzazioni riusate

Nessun ruolo e nessun account nuovo. L'admin è `public.user_roles`
(`private.partner_admin_richiesto()`), il creatore è `public.profiles`, la
guardia server di `/admin/accessori` è quella di `/admin/partner`
(`eAdminReale`, mai il selettore demo), le immagini passano da
`preparaImmagineVetrina` (ricodifica WebP nel browser) e il bucket segue il
pattern di `partner-vetrine`.

**I Partner non creano accessori in questo blocco.** Differito a VPM-015B/C.

## Visibilità: tre chiavi, l'approvazione del titolare e l'anteprima

Per mostrare qualcosa al **pubblico** servono tutte e tre:

1. `NEXT_PUBLIC_ACCESSORI_ENABLED=true` — solo navigazione (desktop), non autorizza;
2. `ACCESSORI_ENABLED=true` — gate server delle route; si apre solo se anche (1);
3. `private.accessori_impostazioni.visibilita_pubblica = true` — nel database,
   via `accessori_admin_visibilita_imposta(true, '<motivo>')`, **possibile solo
   a un admin con il ruolo di rilascio** (sezione seguente).

Mancando (1) o (2): 404 (route inesistenti). Mancando (3): `/accessori` mostra
lo stato vuoto, categoria e dettaglio sono 404, nessun dato.

**Anteprima admin** (verifica della Beta senza accendere nulla): un admin reale
che apre `/accessori` vede il catalogo con le bozze e un banner «Anteprima
riservata», qualunque sia lo stato di flag e interruttore. Lo applica anche il
database (`p_anteprima` richiede il ruolo). L'interruttore **non si cambia
senza il ruolo di rilascio**: l'accensione è una decisione del titolare.

## Rilascio controllato dal titolare

**Chiave.** Un ruolo, non una persona: `accessori_release` in
`public.user_roles`. Nessuna identità, email o segreto sta nel codice, nelle
migrazioni o nella configurazione. Il ruolo lo assegna solo chi ha il
`service_role` o l'accesso SQL di produzione (nessuna porta client scrive
`user_roles`): un admin ordinario non può darselo né darlo ad altri. La tabella
è leggibile solo sulla propria riga, quindi il ruolo non rivela chi lo detiene.

**Che cosa vincola.**

- `accessori_admin_visibilita_imposta(true, …)` richiede **admin reale +
  `accessori_release`** (`42501`, hint `rilascio_non_autorizzato`). Spegnere
  (`false`) richiede un admin qualsiasi: il verso sicuro non aspetta
  approvazioni (interruttore di emergenza).
- Un trigger sulla riga delle impostazioni vincola **anche i writer
  privilegiati**: un `UPDATE` diretto che porta la visibilità da spenta a accesa
  è rifiutato se non passa dalla porta di rilascio.
- L'accensione è registrata, in `private.accessori_registro`, con l'utente che
  rilascia, il motivo e la data.
- Il pannello `/admin/accessori` mostra il comando di accensione **solo** a chi
  il database dichiara abilitato (`puo_rilasciare`) e chiede una conferma
  scritta (`PUBBLICA`) e un motivo con il riferimento dell'approvazione. Agli
  altri admin mostra perché non è possibile.

**Procedura di rilascio (da eseguire solo dopo l'approvazione scritta del
titolare).**

1. Il titolare (o chi egli autorizza per iscritto) assegna il ruolo all'account
   admin che rilascerà, da SQL di produzione:
   `insert into public.user_roles (user_id, role) values ('<id account>', 'accessori_release');`.
2. In Netlify si impostano `ACCESSORI_ENABLED=true` e
   `NEXT_PUBLIC_ACCESSORI_ENABLED=true` (la seconda è letta alla build: serve un
   nuovo deploy). Facoltativa e successiva: `NEXT_PUBLIC_ACCESSORI_NAV_MOBILE=true`.
3. Da `/admin/accessori`, pannello «Rilascio pubblico»: motivo con riferimento
   dell'approvazione, parola `PUBBLICA`, «Rendi pubblico il catalogo».
4. Verifica: la riga `visibilita_accendi` nel registro (utente, motivo, data);
   elenco dei titolari del ruolo
   (`select user_id from public.user_roles where role = 'accessori_release';`);
   prove anonime: elenco con le sole schede pubblicate, foto firmata servita,
   percorso `/object/public/` rifiutato.
5. Ritiro: qualsiasi admin dal pannello («Spegni»), o
   `update private.accessori_impostazioni set visibilita_pubblica = false;`.
   Dopo il rilascio il ruolo si può revocare, per tenerlo eccezionale.

**Limite onesto.** Chi ha il `service_role` o l'accesso SQL di produzione è
fiduciario per definizione: può assegnarsi il ruolo, o dichiarare il marcatore di
rilascio nella propria transazione. La protezione è contro gli admin ordinari,
gli errori e le regressioni, non contro il proprietario dell'infrastruttura.

## Foto private

Il bucket `accessori-media` è **privato** (`public = false`): l'endpoint
`/object/public/…` risponde 400 anche a chi conosce il percorso intero. Le foto si
leggono solo con una **URL firmata** (`createSignedUrls`, validità 900 s),
generata sul server per le pagine pubbliche e di anteprima, e nel browser
dell'admin per il pannello. La firma la concede la policy di Storage in due soli
casi:

- l'**admin reale**, per qualunque oggetto del bucket (bozze e anteprima);
- **chiunque**, per le sole foto di una scheda **pubblicata**, in una categoria
  attiva, **mentre la visibilità pubblica è accesa** (`private.accessorio_media_pubblica`,
  la stessa regola delle letture pubbliche).

Con il catalogo spento, o per una bozza, un archiviato o una foto non collegata,
anonimo e utenti ricevono 400 su firma, su `/object/authenticated/` e
sull'elenco. Una scheda ritirata smette di essere firmabile subito; una URL già
emessa resta valida fino alla scadenza (≤ 15 minuti): è il residuo accettato.

## Navigazione mobile (predisposta, spenta)

Con `NEXT_PUBLIC_ACCESSORI_NAV_MOBILE=true` **e** `NEXT_PUBLIC_ACCESSORI_ENABLED=true`
la barra mobile mostra Accessori al posto di Home, nella stessa posizione. Le
posizioni non cambiano: con il Club acceso sono cinque, con il Club spento
quattro, come oggi (la voce Club è già filtrata dalla sua flag). Il marchio
nell'header resta il collegamento alla Home, quindi nessuna destinazione
scompare. Con la flag spenta, la barra è identica a prima, ospite e
autenticato. Non va accesa finché il catalogo non è autorizzato.

Pagine: `/accessori`, `/accessori/categoria/[slug]`, `/accessori/[slug]`,
`/admin/accessori`; tutte `noindex`. Le pagine pubbliche non hanno prezzo,
disponibilità né azioni di acquisto e lo dicono («Catalogo in versione Beta»).

## Assenza di transazioni (verificabile)

- Nessuna FK da o verso `listings`, `orders`, `payments`, `wines`, `bottle_units`:
  griglia 12zh, caso 25.
- Nessuna colonna di prezzo, valuta, importo, IVA, commissione, peso,
  dimensioni, fornitore: caso 26 e test `accessori-contratto.test.ts`.
- Anonimo esegue **solo** le tre letture: caso 27. Nessuna funzione accessori
  cita ordini, pagamenti o annunci.
- Nessun percorso `/checkout`, `/ordine`, `/acquisti`, `/vendite`, `/vendi`,
  `/annuncio` e nessun import da servizi di checkout/ordini/proposte/pagamenti
  nel codice degli Accessori: il test di contratto fa fallire la build.
- Una prova diretta (URL e chiamate dirette) è in `../CHANGES.log`.

## Differito (documentato, non implementato)

Prezzo, valuta, varianti, dimensioni, peso; marchi come entità; attributi
tipizzati per categoria; ricerca, filtri e paginazione oltre 60 schede; Partner
come venditori di accessori; ordinamento manuale delle immagini; traduzioni;
SEO/indicizzazione; checkout, proposte, ordini, pagamenti, spedizioni,
aliquote IVA e commissioni sugli accessori; personalizzazioni e casse su
misura; fornitori e magazzino fornitori; alcolici e articoli regolamentati.

## Prove

- Griglia SQL `supabase/tests/12zh_vpm_015a_accessori.sql` (29 casi, anonimo,
  utente A, utente B, admin; ROLLBACK), registrata in
  `supabase/tests/12g_ci_run.sh` e quindi nel gate `Supabase DB regression`.
- `frontend-next`: parser, modulo, gate (client finti), servizio, contratto
  statico (codice e migrazione). Soglia CI dei test alzata a 2890.
- Verifica nel browser contro uno stack Supabase locale, con flag spente e
  accese, anonimo e admin (vedi `../CHANGES.log`).
- Correzione del 20 ottobre: la griglia 12zh passa a 35 casi (admin ordinario
  rifiutato, ruolo senza admin rifiutato, trigger sui writer privilegiati, titolare
  che accende, bucket privato, foto leggibili solo se pubblicate e acceso,
  spegnimento da admin ordinario) e una prova HTTP reale contro lo stack locale
  (24 controlli: URL pubblica, firma, `/authenticated/`, elenco e scrittura, per
  anonimo, utente, admin e titolare, con percorso noto) — vedi `CHANGES.log`.

## Residuo accettato

- Una URL firmata già emessa per una foto pubblicata resta valida fino a
  scadenza (≤ 900 s) anche se la scheda viene ritirata subito dopo.
- Chi ha `service_role` o SQL di produzione è fiduciario (vedi «Rilascio
  controllato dal titolare»).
- Il ruolo `accessori_release` si assegna a mano: la sua governance è
  organizzativa (chi lo detiene, quando lo si revoca).

## In valutazione, non implementato

- **«Accessori della cantina»** per i profili utente: da valutare dal titolare.
  Non esiste né una tabella né una route; se verrà ammessa serve una decisione
  su proprietà dei dati, visibilità e rapporto con la cantina del vino.
- **Nomenclatura delle categorie**: sarà rivista; si cambia con righe, non con
  una migrazione di schema.

## Decisioni per VPM-015B

1. **Chi vende**: solo Vinea (catalogo curato) o anche i Partner? Cambia il
   modello (`venditore_id`), le RLS e il rapporto con `venditore_classe_di`.
2. **Prezzo e valuta**: colonne dedicate con congelamento sull'ordine, o prezzo
   a listino versionato come `marketplace_config`? Va deciso con FIN.
3. **Commissione e IVA**: classe di aliquota per categoria? Oggi non esiste
   nulla (decisione FIN/LEG).
4. **Disponibilità**: `quantita` interna diventa giacenza prenotabile? Servono
   lotti/inventario come VP-C o un modello semplice per articoli non univoci.
5. **Spedizione**: dimensioni e peso, e come entrano nel preventivo logistico
   multi-collo (VP-E); un accessorio non è una bottiglia.
6. **Alcolici e regolamentati**: perimetro esplicito degli articoli vendibili.
7. **Ordini**: riusare `orders` (con una riga per tipo) o un dominio separato;
   regola di unica scrittura per dominio.

## Impatti da inoltrare

- **LEG**: nuova categoria merceologica; condizioni di vendita, garanzia legale
  e recesso per beni non-vino; esclusione di alcolici/regolamentati; immagini e
  marchi di terzi (diritti, uso del marchio in catalogo).
- **FIN**: nessun impatto economico in 015A. Per 015B: prezzo, IVA, commissione,
  fee di pagamento e logistica per accessori.
- **OPS**: sourcing, magazzino e spedizione di articoli non-vino; imballaggio per
  articoli fragili (calici, decanter); chi inserisce e cura il catalogo.
- **DESIGN**: stati vuoti, schede senza prezzo, fotografia di prodotto (formato,
  sfondo, rapporto), nomi delle categorie e icone; la voce di navigazione desktop
  è dietro flag; la sostituzione di Home sul mobile è predisposta e spenta (icona
  provvisoria `GlassWater`, etichetta «Accessori»).
