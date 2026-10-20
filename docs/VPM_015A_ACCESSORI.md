# VPM-015A — Accessori Vinea: fondazione Beta

Contratto della fondazione del catalogo Accessori. Stato operativo e verifiche di
produzione stanno in `../CHANGES.log`; la regola durevole è in
`../CONTESTO_IA/03_ARCHITETTURA_REGOLE_DEBITI.md`.

## Perimetro e decisione

Il titolare ha approvato **per nome** la realizzazione di questa fondazione
(eccezione al «nessuna nuova funzionalità durante la migrazione») e **non**
l'attivazione commerciale. VPM-015A costruisce un catalogo e un'area admin;
non attiva vendite, pagamenti, commissioni o spedizioni.

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
| bucket `accessori-media` | Solo `image/webp` fino a 2 MB. Caricamento ed elenco riservati all'admin reale; percorso `<accessorio>/<uuid>.webp`. |

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
  `_visibilita_imposta` (motivo obbligatorio, registrata).
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

## Visibilità: tre chiavi più l'anteprima

Per mostrare qualcosa al **pubblico** servono tutte e tre:

1. `NEXT_PUBLIC_ACCESSORI_ENABLED=true` — solo navigazione (desktop), non autorizza;
2. `ACCESSORI_ENABLED=true` — gate server delle route; si apre solo se anche (1);
3. `private.accessori_impostazioni.visibilita_pubblica = true` — nel database,
   via `accessori_admin_visibilita_imposta(true, '<motivo>')`.

Mancando (1) o (2): 404 (route inesistenti). Mancando (3): `/accessori` mostra
lo stato vuoto, categoria e dettaglio sono 404, nessun dato.

**Anteprima admin** (verifica della Beta senza accendere nulla): un admin reale
che apre `/accessori` vede il catalogo con le bozze e un banner «Anteprima
riservata», qualunque sia lo stato di flag e interruttore. Lo applica anche il
database (`p_anteprima` richiede il ruolo). L'interruttore **non si cambia
dalla UI**: l'accensione è una decisione del titolare.

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

## Residuo accettato

Il bucket `accessori-media` è pubblico per percorso, come `partner-vetrine`: i
byte di un'immagine sono raggiungibili da chi conosce il percorso, che contiene
due uuid casuali e compare solo alle funzioni admin finché la scheda non è
pubblicata. Nessun ruolo client può elencare il bucket.

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
  sfondo, rapporto), nomi delle categorie e icone; la voce di navigazione è solo
  desktop e dietro flag.
