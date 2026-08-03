-- BOZZA — NON ESEGUIRE SENZA APPROVAZIONE ESPLICITA IN CHAT ORGANIZZATIVA.
--
-- Riparazione del ledger di bookkeeping delle migrazioni.
-- Progetto interessato: pijnmcllmfgjmgsvtcej.
--
-- COSA FA
--   Riscrive la sola colonna `statements` di sette righe di
--   `supabase_migrations.schema_migrations` che risultano registrate con
--   l'array vuoto. La versione risulta applicata e non conserva alcun SQL,
--   quindi ogni ambiente ricostruito dal ledger (branch Supabase, `db reset`)
--   salta quelle sette versioni senza creare nulla.
--
-- COSA NON FA
--   Nessuna DDL sullo schema applicativo. Nessun `create`, `alter`, `drop`,
--   `grant`, `revoke`. Nessuna scrittura su tabelle di dominio. Il DDL delle
--   sette versioni non viene rieseguito: il progetto reale lo contiene già,
--   ed è proprio per questo che l'assenza nel ledger era invisibile.
--
-- CONTENUTO REGISTRATO
--   Per ciascuna versione, il contenuto verbatim del file gia' tracciato in
--   `supabase/migrations/`, byte per byte, come array a UN SOLO ELEMENTO —
--   lo stesso schema delle cinque versioni registrate dopo il riallineamento
--   di fine luglio (20260729234500, 20260729235500, 20260730140948,
--   20260730162046, 20260731120340). Nessuno split per singola istruzione.
--
--   Differenza dichiarata rispetto alle righe scritte da `apply_migration`:
--   quelle hanno l'intestazione di commento rimossa e non hanno il newline
--   finale. Qui il file entra intero, intestazione e newline compresi. La
--   differenza è inerte per Postgres ed è voluta, per rendere il contenuto
--   registrato verificabile con un confronto di hash contro il file tracciato.
--
-- RIESEGUIBILITÀ
--   Ogni `update` porta la guardia
--     `and coalesce(array_length(statements, 1), 0) = 0`
--   quindi non tocca una riga già popolata e non può sovrascrivere il
--   contenuto delle sette versioni sane. Le sette istruzioni sono indipendenti
--   fra loro: si possono eseguire tutte insieme o una alla volta, e una
--   riesecuzione integrale aggiorna zero righe.
--
-- ATTESO
--   Sezione [0]: sette righe con `caratteri = 0`, le altre sette con contenuto.
--   Sezioni [1]-[7]: `UPDATE 1` ciascuna alla prima esecuzione, `UPDATE 0` poi.
--   Sezione [8]: quattordici righe, nessuna con `caratteri = 0`.
--
-- NON RIPARA la seconda deriva: l'event trigger `ensure_rls` e la funzione
-- `public.rls_auto_enable()` non sono creati da alcun file tracciato e restano
-- assenti da qualunque ambiente ricostruito. Debito registrato in
-- `docs/MIGRATION_PHASE_1_BACKLOG.md`.


-- ---------------------------------------------------------------------------
-- [0] PRE-CONTROLLO — sola lettura. Eseguire prima, e conservarne l'output.
-- ---------------------------------------------------------------------------

select
  version,
  name,
  coalesce(array_length(statements, 1), 0) as elementi,
  coalesce(length(array_to_string(statements, '')), 0) as caratteri
from supabase_migrations.schema_migrations
order by version;


-- ---------------------------------------------------------------------------
-- [1] 20260728193937 listings_catalog
--     file   supabase/migrations/20260728193937_listings_catalog.sql
--     byte   21840
--     sha256 e17d4a8e50ed56903cac50f13964a30d977e06231ff686a43f8a3006fb3f2a99
-- ---------------------------------------------------------------------------

update supabase_migrations.schema_migrations
   set statements = array[
$vinea_ledger_20260728193937$-- Fase 6a — Catalogo vini condiviso, unità fisiche e annunci.
--
-- Tre tabelle, un dominio ciascuna:
--   wines        catalogo condiviso, leggibile da tutti, scrivibile solo da staff
--   bottle_units unità fisica posseduta da un utente (nessuna UI in questa fase)
--   listings     annuncio: un venditore mette in vendita una bottle_unit
--
-- COSA NON C'È QUI, E PERCHÉ. La Fase 6a collega alla UI la sola lettura del
-- marketplace, quindi qui non c'è nessuna via di scrittura dello stato: le
-- funzioni di transizione (bozza → attivo, attivo → sospeso, attivo →
-- scaduto) arrivano in Fase 6b insieme al wizard /vendi e ai metodi di
-- scrittura di ListingService. Fuori anche ordini, proposte e pagamenti
-- (Fase 7), coda di moderazione e audit_log (Fase 9), e tutta la gestione
-- cantina: posizione fisica, ambienti, moduli e preset 3D (vedi "Fase 6c —
-- Cantina" in docs/ROADMAP_V1.md).
--
-- L'enum degli stati è comunque definito completo fin da ora: aggiungere un
-- valore a un enum già in uso richiede una migrazione, definirlo in anticipo
-- no. Finché non esistono le funzioni di transizione, l'unico modo di portare
-- un annuncio ad 'attivo' è un UPDATE eseguito con privilegi di servizio
-- (SQL Editor della dashboard): dal client è impossibile per costruzione,
-- perché `stato` non compare tra i GRANT di colonna più sotto.

-- ---------------------------------------------------------------------------
-- Estensioni
-- ---------------------------------------------------------------------------

-- Già presente dalla Fase 5a (trigger updated_at), ripetuta per idempotenza.
create extension if not exists moddatetime with schema extensions;

-- Ricerca testuale di /esplora: il campo cerca produttore e nome con match
-- parziale ("conterno", "sassic"). Senza pg_trgm un ILIKE '%…%' non è
-- indicizzabile e degrada linearmente al crescere del catalogo.
create extension if not exists pg_trgm with schema extensions;

-- ---------------------------------------------------------------------------
-- wines — catalogo condiviso
-- ---------------------------------------------------------------------------
-- Vino e annata NON sono separati: frontend/docs/DOMAIN_MODEL.md descrive
-- `Wine` come "bottiglia catalogata: id, produttore, denominazione, annata…",
-- e il tipo autoritativo (frontend-next/src/data/wines.ts) ha `annata: number`
-- come campo. Una riga = un produttore + un vino + un'annata. Il vincolo
-- UNIQUE su quella tripletta tiene la porta aperta a una futura separazione
-- wine/wine_vintage senza rendere ambigui i dati esistenti.

create table public.wines (
  id uuid primary key default gen_random_uuid(),
  -- Identificatore pubblico stabile e leggibile ("monfortino-2015"). Serve a
  -- due cose: tenere gli URL leggibili invece di esporre UUID, e fare da
  -- chiave verso i metadati mock ancora non migrati (finestra di bevuta e
  -- abbinamenti cibo vivono in src/data/cellar.ts e sono indicizzati per
  -- slug). Senza slug, un annuncio reale perderebbe silenziosamente il badge
  -- "quando berlo" e la ricerca per abbinamento.
  slug text not null unique
    check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  produttore text not null check (length(trim(produttore)) > 0),
  nome text not null check (length(trim(nome)) > 0),
  annata smallint not null check (annata between 1800 and 2100),
  regione text not null check (length(trim(regione)) > 0),
  denominazione text not null default '',
  tipo text not null
    check (tipo in ('Rosso', 'Bianco', 'Bollicine', 'Rosato', 'Dolce')),
  formato text not null default '0,75 L',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint wines_produttore_nome_annata_key unique (produttore, nome, annata)
);

comment on table public.wines is
  'Catalogo vini condiviso. Una riga = produttore + vino + annata. Leggibile '
  'da chiunque (anche anonimo); scrivibile solo da chi ha ruolo admin o '
  'moderator, verificato via has_role() nelle policy RLS.';
comment on column public.wines.slug is
  'Identificatore pubblico stabile. Usato negli URL e come chiave verso i '
  'metadati ancora mock (finestra di bevuta, abbinamenti) in '
  'frontend-next/src/data/cellar.ts.';
comment on column public.wines.tipo is
  'Vincolato con CHECK e non con un ENUM: la sorgente di verità è l''unione '
  'TypeScript in frontend-next/src/data/wines.ts, e un CHECK si fa evolvere '
  'con una ALTER invece che con una migrazione di tipo.';

create index wines_regione_idx on public.wines (regione);
create index wines_tipo_idx on public.wines (tipo);
create index wines_annata_idx on public.wines (annata);
create index wines_ricerca_trgm_idx
  on public.wines using gin ((produttore || ' ' || nome) extensions.gin_trgm_ops);

create trigger wines_set_updated_at
  before update on public.wines
  for each row
  execute function extensions.moddatetime('updated_at');

-- I privilegi si azzerano prima di concederli. Nei progetti Supabase esistono
-- ALTER DEFAULT PRIVILEGES che assegnano automaticamente ai ruoli anon e
-- authenticated tutti i permessi sulle nuove tabelle di `public`: senza
-- questa revoca, i GRANT mirati più sotto sarebbero decorativi e il client
-- avrebbe comunque UPDATE su ogni colonna.
revoke all on public.wines from anon, authenticated;

grant select on public.wines to anon, authenticated;
-- INSERT/UPDATE/DELETE sono concessi al ruolo `authenticated` ma la policy
-- qui sotto li nega a chiunque non sia staff. Il privilegio da solo non
-- basta: è la RLS con has_role() a decidere. `anon` non ha alcun privilegio
-- di scrittura, quindi un client non autenticato non può nemmeno provarci.
grant insert, update, delete on public.wines to authenticated;

alter table public.wines enable row level security;

create policy "wines_select_public"
  on public.wines for select
  to anon, authenticated
  using (true);

create policy "wines_write_staff"
  on public.wines for all
  to authenticated
  using (
    public.has_role(auth.uid(), 'admin')
    or public.has_role(auth.uid(), 'moderator')
  )
  with check (
    public.has_role(auth.uid(), 'admin')
    or public.has_role(auth.uid(), 'moderator')
  );

-- ---------------------------------------------------------------------------
-- bottle_units — unità fisica posseduta da un utente
-- ---------------------------------------------------------------------------
-- Nessuna UI in questa fase. Esiste perché un annuncio venda una bottiglia
-- identificabile e non un vino generico: è ciò che permette al vincolo
-- "una sola bottiglia, un solo annuncio attivo" di essere applicato dal
-- database invece che sperato dall'applicazione.

create type public.bottle_unit_stato as enum ('chiusa', 'aperta', 'consumata');

comment on type public.bottle_unit_stato is
  'Stato fisico dell''unità. frontend/docs/DOMAIN_MODEL.md elenca '
  '(chiusa, aperta, programmata), ma "programmata" non è uno stato: è la '
  'presenza di una data di apertura pianificata (CellarBottle.plannedOpenDate). '
  'Qui resta il solo stato fisico; la pianificazione arriverà con la Cantina.';

create type public.bottle_unit_visibilita as enum ('privata', 'cantina_pubblica');

comment on type public.bottle_unit_visibilita is
  'Scelta del proprietario su quanto della propria cantina è pubblico. '
  'I valori "in_vendita" e "venduta" del tipo SaleStatus mock NON sono '
  'replicati qui di proposito: sono fatti derivabili da listings, e '
  'duplicarli creerebbe una seconda fonte di verità sullo stesso stato.';

create table public.bottle_units (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid()
    references public.profiles (id) on delete cascade,
  wine_id uuid not null references public.wines (id) on delete restrict,
  stato public.bottle_unit_stato not null default 'chiusa',
  visibilita public.bottle_unit_visibilita not null default 'privata',
  -- Cancellazione logica: un'unità collegata a un annuncio storico non può
  -- sparire senza lasciare l'annuncio orfano.
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.bottle_units is
  'Unità fisica di vino posseduta da un utente. Nessuna interfaccia in Fase '
  '6a: serve solo perché un annuncio venda una bottiglia identificabile. '
  'Posizione fisica, ambienti, moduli e preset 3D arrivano con la Cantina.';

create index bottle_units_owner_idx
  on public.bottle_units (owner_id) where deleted_at is null;
create index bottle_units_wine_idx on public.bottle_units (wine_id);

create trigger bottle_units_set_updated_at
  before update on public.bottle_units
  for each row
  execute function extensions.moddatetime('updated_at');

revoke all on public.bottle_units from anon, authenticated;

grant select on public.bottle_units to anon, authenticated;
grant insert (wine_id, stato, visibilita) on public.bottle_units to authenticated;
grant update (stato, visibilita, deleted_at) on public.bottle_units to authenticated;
-- Nessun DELETE: la rimozione è logica, via deleted_at. Nessun privilegio su
-- owner_id: il proprietario si stabilisce alla creazione (default auth.uid())
-- e non è cedibile da un UPDATE del browser.

alter table public.bottle_units enable row level security;

create policy "bottle_units_select_own"
  on public.bottle_units for select
  to authenticated
  using (owner_id = auth.uid() and deleted_at is null);

create policy "bottle_units_insert_own"
  on public.bottle_units for insert
  to authenticated
  with check (owner_id = auth.uid());

create policy "bottle_units_update_own"
  on public.bottle_units for update
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- La policy che rende visibile un'unità collegata a un annuncio pubblico vive
-- più in basso: dipende da listings, che ancora non esiste.

-- ---------------------------------------------------------------------------
-- listings — annunci
-- ---------------------------------------------------------------------------

create type public.listing_stato as enum (
  'bozza',
  'in_revisione',
  'modifiche_richieste',
  'attivo',
  'riservato',
  'sospeso',
  'scaduto',
  'venduto',
  'rifiutato'
);

comment on type public.listing_stato is
  'Nove stati, identici a ListingStatus in frontend-next/src/data/moderation.ts. '
  'Definiti tutti in Fase 6a benché nessuna transizione sia ancora esposta: '
  'aggiungere un valore a un enum già in uso richiede una migrazione, '
  'definirlo in anticipo no. Le transizioni arrivano in 6b (pubblicazione, '
  'sospensione, scadenza), Fase 7 (riservato, venduto) e Fase 9 '
  '(in_revisione, modifiche_richieste, rifiutato).';

create table public.listings (
  id uuid primary key default gen_random_uuid(),
  -- Come per wines: identificatore d'URL leggibile. Oggi /annuncio/<slug>
  -- mostra "monfortino-2015"; con un UUID nell'URL cambierebbe la forma dei
  -- link senza che nessuno l'abbia chiesto.
  slug text not null unique
    check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  seller_id uuid not null default auth.uid()
    references public.profiles (id) on delete cascade,
  bottle_unit_id uuid not null
    references public.bottle_units (id) on delete restrict,
  stato public.listing_stato not null default 'bozza',

  -- Prezzi in centesimi, interi. Un prezzo in euro come float accumula
  -- errori di rappresentazione appena entra in un calcolo (totali, sconti,
  -- commissioni): il dominio è discreto, il tipo deve esserlo.
  prezzo_cents integer not null check (prezzo_cents > 0),
  prezzo_mercato_cents integer check (prezzo_mercato_cents > 0),

  -- Resta 1 in tutta la Fase 6a e non è modificabile dalla UI. Un annuncio
  -- vende una singola bottle_unit identificabile, quindi la quantità reale è
  -- sempre 1; la colonna esiste perché l'interfaccia attuale stampa "N
  -- bottiglie disponibili" (Wine.disponibili nei dati mock) e toglierla
  -- cambierebbe il testo mostrato all'utente. Diventerà significativa solo
  -- quando la Cantina permetterà di collegare più unità allo stesso annuncio:
  -- a quel punto sarà un conteggio derivato, non un valore digitato. Non è un
  -- residuo dimenticato — vedi "Fase 6c — Cantina" in docs/ROADMAP_V1.md.
  quantita integer not null default 1 check (quantita >= 1),

  condizione text not null default 'Ottimo'
    check (condizione in ('Perfetto', 'Ottimo', 'Buono')),
  conservazione text not null default '',
  storia text not null default '',
  degustazione text not null default '',
  immagini text[] not null default '{}',
  tag text[] not null default '{}',

  published_at timestamptz,
  expires_at timestamptz,

  -- Ultima transizione di stato: chi, quando, perché. Non sostituisce
  -- l'audit_log persistente (Fase 9), ma senza queste tre colonne una
  -- sospensione non lascerebbe alcuna traccia del motivo.
  stato_motivo text,
  stato_aggiornato_da uuid references public.profiles (id) on delete set null,
  stato_aggiornato_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.listings is
  'Annunci del marketplace. Un annuncio vende una singola bottle_unit. Lo '
  'stato non è mai scrivibile dal client: le colonne concesse in UPDATE '
  'escludono `stato`. In Fase 6a nessuna transizione è esposta, quindi solo '
  'un ruolo di servizio può cambiarlo; dalla Fase 6b lo faranno le funzioni '
  'di transizione SECURITY DEFINER.';
comment on column public.listings.prezzo_cents is
  'Prezzo in centesimi di euro. Intero, mai float.';

-- Il vincolo che rende utile bottle_units: la stessa bottiglia fisica non può
-- essere in vendita in due posti insieme. Parziale perché gli stati terminali
-- (venduto, scaduto, sospeso, rifiutato) devono poter coesistere in storico
-- sulla stessa unità.
create unique index listings_una_sola_attiva_per_bottiglia
  on public.listings (bottle_unit_id)
  where stato in ('attivo', 'riservato');

create index listings_seller_idx on public.listings (seller_id);
create index listings_bottle_unit_idx on public.listings (bottle_unit_id);
create index listings_stato_idx on public.listings (stato);
create index listings_prezzo_idx on public.listings (prezzo_cents);
-- Indice del feed pubblico: /esplora ordina per "più recenti" di default e
-- guarda soltanto gli annunci attivi. L'espressione è la stessa esposta dalla
-- vista come `pubblicato_at` — indicizzare la sola published_at servirebbe a
-- poco, visto che resta nulla finché non esistono le transizioni.
create index listings_pubblici_recenti_idx
  on public.listings ((coalesce(published_at, created_at)) desc)
  where stato = 'attivo';

create trigger listings_set_updated_at
  before update on public.listings
  for each row
  execute function extensions.moddatetime('updated_at');

revoke all on public.listings from anon, authenticated;

grant select on public.listings to anon, authenticated;

-- Privilegi per colonna, non per tabella. È qui che si applica davvero la
-- regola "lo stato non lo decide il browser": `stato`, `published_at`,
-- `expires_at`, `seller_id` e le tre colonne di tracciamento non compaiono
-- nella lista, quindi un UPDATE che le tocchi viene rifiutato da PostgreSQL
-- prima ancora di arrivare alla RLS. Nessun booleano di sospensione
-- scrivibile dal client, e nessun trigger da mantenere per difenderlo.
-- In Fase 6b le funzioni di transizione SECURITY DEFINER diventeranno l'unica
-- porta d'accesso a quelle colonne: questa lista non dovrà cambiare.
grant insert (
  slug, bottle_unit_id, prezzo_cents, prezzo_mercato_cents,
  condizione, conservazione, storia, degustazione, immagini, tag
) on public.listings to authenticated;

grant update (
  prezzo_cents, prezzo_mercato_cents,
  condizione, conservazione, storia, degustazione, immagini, tag
) on public.listings to authenticated;

alter table public.listings enable row level security;

create policy "listings_select_pubblici"
  on public.listings for select
  to anon, authenticated
  using (stato = 'attivo');

create policy "listings_select_own"
  on public.listings for select
  to authenticated
  using (seller_id = auth.uid());

-- Si può creare un annuncio solo per una bottiglia che si possiede davvero.
-- Senza questo controllo un utente potrebbe mettere in vendita l'unità di
-- qualcun altro semplicemente indovinandone l'id.
create policy "listings_insert_own"
  on public.listings for insert
  to authenticated
  with check (
    seller_id = auth.uid()
    and exists (
      select 1
      from public.bottle_units bu
      where bu.id = bottle_unit_id
        and bu.owner_id = auth.uid()
        and bu.deleted_at is null
    )
  );

-- Modificabile finché è una bozza o è tornata al venditore per correzioni.
-- Un annuncio già pubblico non si modifica in silenzio sotto gli occhi di chi
-- lo sta guardando: passa prima da una transizione esplicita.
create policy "listings_update_own"
  on public.listings for update
  to authenticated
  using (
    seller_id = auth.uid()
    and stato in ('bozza', 'modifiche_richieste')
  )
  with check (seller_id = auth.uid());

-- ---------------------------------------------------------------------------
-- bottle_units visibili tramite annuncio pubblico
-- ---------------------------------------------------------------------------
-- Definita solo ora perché interroga listings. Isolata in una funzione
-- SECURITY DEFINER per due motivi: evita di valutare la RLS di listings
-- dentro la policy di bottle_units (accoppiamento fragile, a rischio
-- ricorsione se un domani listings dovesse guardare bottle_units), e ricalca
-- il pattern già stabilito da has_role() in Fase 5a.

create or replace function public.bottle_unit_in_annuncio_pubblico(p_bottle_unit_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.listings
    where bottle_unit_id = p_bottle_unit_id
      and stato = 'attivo'
  );
$$;

revoke execute on function public.bottle_unit_in_annuncio_pubblico(uuid) from public;
grant execute on function public.bottle_unit_in_annuncio_pubblico(uuid)
  to anon, authenticated;

create policy "bottle_units_select_via_annuncio_pubblico"
  on public.bottle_units for select
  to anon, authenticated
  using (public.bottle_unit_in_annuncio_pubblico(id));

-- ---------------------------------------------------------------------------
-- public_listings — vista pubblica del marketplace
-- ---------------------------------------------------------------------------
-- Perché una vista e non tre select con embed PostgREST:
--
-- 1. La card di un annuncio mostra nome, città e avatar del venditore, ma la
--    policy `profiles_select_own` della Fase 5a consente di leggere solo il
--    proprio profilo. Senza questa vista un annuncio pubblico non potrebbe
--    mostrare chi vende. frontend/docs/BACKEND_CONTRACTS.md prevedeva
--    "profiles: SELECT pubblica per campi non sensibili": è la Fase 5a ad
--    aver stretto più del contratto, e qui si riallinea.
-- 2. RLS lavora per riga, non per colonna: una policy "tutti leggono
--    profiles" esporrebbe anche `dob`, cioè la data di nascita di ogni
--    utente. La vista sceglie le colonne una per una.
--
-- La vista è `security_invoker = off` (default), quindi valuta con i
-- privilegi del proprietario e scavalca la RLS delle tabelle sottostanti.
-- È deliberato ed è sicuro perché la vista non accetta parametri: il filtro
-- `stato = 'attivo'` è scritto dentro e nessun client può rimuoverlo, e le
-- colonne esposte sono un elenco chiuso. Il linter Supabase segnalerà questa
-- vista come `security_definer_view`: è la segnalazione attesa per questo
-- pattern, non un difetto da correggere silenziosamente.

create view public.public_listings
with (security_invoker = off)
as
select
  l.id,
  l.slug,
  l.prezzo_cents,
  l.prezzo_mercato_cents,
  l.quantita,
  l.condizione,
  l.conservazione,
  l.storia,
  l.degustazione,
  l.immagini,
  l.tag,
  l.published_at,
  l.created_at,
  -- Chiave di ordinamento unica per "più recenti". Finché le transizioni non
  -- esistono (Fase 6b) published_at resta nullo sulle righe create da SQL
  -- Editor: ordinare direttamente su quella colonna metterebbe tutto il
  -- catalogo in coda a se stesso.
  coalesce(l.published_at, l.created_at) as pubblicato_at,
  w.id            as wine_id,
  w.slug          as wine_slug,
  w.produttore,
  w.nome,
  w.annata,
  w.regione,
  w.denominazione,
  w.tipo,
  w.formato,
  -- Colonna di sola ricerca: /esplora cerca su "produttore + nome" come una
  -- stringa sola. Esporla concatenata qui non è cosmetico — PostgreSQL espande
  -- la vista dentro la query, quindi un ILIKE su questa colonna diventa un
  -- ILIKE sull'espressione (produttore || ' ' || nome) e può usare l'indice
  -- GIN trigram definito sopra. Due ILIKE separati su produttore e nome non
  -- lo userebbero.
  w.produttore || ' ' || w.nome as ricerca,
  p.id            as seller_id,
  p.username      as seller_username,
  p.citta         as seller_citta,
  p.avatar_url    as seller_avatar_url
from public.listings l
  join public.bottle_units bu on bu.id = l.bottle_unit_id
  join public.wines w on w.id = bu.wine_id
  join public.profiles p on p.id = l.seller_id
where l.stato = 'attivo';

comment on view public.public_listings is
  'Annunci attivi con vino e venditore già uniti, nella forma che serve a '
  '/esplora e a /annuncio/[slug]. Espone solo campi non sensibili del '
  'profilo venditore (mai dob, esperienza, bio, obiettivi).';

revoke all on public.public_listings from anon, authenticated;
grant select on public.public_listings to anon, authenticated;
$vinea_ledger_20260728193937$
   ]
 where version = '20260728193937'
   and coalesce(array_length(statements, 1), 0) = 0;

-- ---------------------------------------------------------------------------
-- [2] 20260728194500 seed_wines_catalog
--     file   supabase/migrations/20260728194500_seed_wines_catalog.sql
--     byte   2707
--     sha256 e77873bc57520a77ed20e45fdc9108b92755689a051bd87af6ee045280936cae
-- ---------------------------------------------------------------------------

update supabase_migrations.schema_migrations
   set statements = array[
$vinea_ledger_20260728194500$-- Fase 6a — Seed del catalogo condiviso (solo `wines`).
--
-- PERCHÉ ESISTE. Non è un riempitivo per far sembrare popolata una pagina
-- vuota: i metadati che alimentano la finestra di bevuta (DrinkBadge,
-- DrinkWindowSection), gli abbinamenti cibo (FoodPairingSection) e la ricerca
-- "cosa stai preparando" di /esplora vivono ancora in
-- frontend-next/src/data/cellar.ts, indicizzati per slug del vino. Un vino
-- reale con uno slug sconosciuto a quella mappa perde quelle sezioni senza
-- alcun messaggio d'errore. Seminando le otto voci con gli slug già usati dal
-- mock, ciò che l'utente vede resta identico a frontend/.
--
-- COSA NON SEMINA. Nessun annuncio e nessuna bottle_unit: entrambi richiedono
-- un venditore reale in public.profiles, cioè un utente vero in auth.users. I
-- venditori del mock ("Marco B.", "Sofia R.") non sono account e inventarli
-- significherebbe scrivere in produzione righe che fingono di essere persone.
-- Gli annunci nascono da account reali — dal test end-to-end di questa fase
-- ora, dal wizard /vendi in Fase 6b.
--
-- Dati presi da frontend-next/src/data/wines.ts. Solo i campi di catalogo:
-- prezzo, condizione, conservazione, storia, immagini e venditore
-- appartengono all'annuncio, non al vino, e non compaiono qui.

insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato)
values
  ('monfortino-2015',           'Giacomo Conterno',  'Barolo Riserva Monfortino',   2015, 'Piemonte',  'Barolo DOCG',                    'Rosso',     '0,75 L'),
  ('sassicaia-2018',            'Tenuta San Guido',  'Sassicaia',                   2018, 'Toscana',   'Bolgheri Sassicaia DOC',         'Rosso',     '0,75 L'),
  ('tignanello-2019',           'Antinori',          'Tignanello',                  2019, 'Toscana',   'Toscana IGT',                    'Rosso',     '0,75 L'),
  ('dom-perignon-2013',         'Moët & Chandon',    'Dom Pérignon Vintage',        2013, 'Champagne', 'Champagne AOC',                  'Bollicine', '0,75 L'),
  ('ornellaia-2017',            'Ornellaia',         'Ornellaia',                   2017, 'Toscana',   'Bolgheri Superiore DOC',         'Rosso',     '0,75 L'),
  ('biondi-santi-2016',         'Biondi-Santi',      'Brunello di Montalcino',      2016, 'Toscana',   'Brunello di Montalcino DOCG',    'Rosso',     '0,75 L'),
  ('rinaldi-brunate-2018',      'Giuseppe Rinaldi',  'Barolo Brunate',              2018, 'Piemonte',  'Barolo DOCG',                    'Rosso',     '0,75 L'),
  ('cadelbosco-annamaria-2015', 'Ca'' del Bosco',    'Cuvée Annamaria Clementi',    2015, 'Lombardia', 'Franciacorta DOCG',              'Bollicine', '0,75 L')
on conflict (slug) do nothing;
$vinea_ledger_20260728194500$
   ]
 where version = '20260728194500'
   and coalesce(array_length(statements, 1), 0) = 0;

-- ---------------------------------------------------------------------------
-- [3] 20260729112500 listings_write
--     file   supabase/migrations/20260729112500_listings_write.sql
--     byte   22005
--     sha256 cb57762fd108c5921aec49c135c3eaabaffea5f294e9fa353d97ce35555bf317
-- ---------------------------------------------------------------------------

update supabase_migrations.schema_migrations
   set statements = array[
$vinea_ledger_20260729112500$-- Fase 6b — Scrittura degli annunci: creazione, transizioni di stato, storage.
--
-- La Fase 6a ha creato lo schema e ha lasciato fuori ogni via di scrittura
-- dello stato: `stato`, `published_at`, `expires_at` e le colonne di
-- tracciamento non compaiono nei GRANT di colonna, quindi dal browser sono
-- irraggiungibili per costruzione. Questa migrazione apre l'unica porta
-- prevista: quattro funzioni SECURITY DEFINER, ciascuna con un controllo
-- esplicito di proprietà e di stato di partenza.
--
-- COSA RESTA FUORI. Le transizioni di moderazione (in_revisione,
-- modifiche_richieste, rifiutato) sono Fase 9; quelle di vendita (riservato,
-- venduto) sono Fase 7. La lista dei GRANT di colonna della 6a NON cambia:
-- era già stata scritta per non dover cambiare, ed è questa la prova.

-- ---------------------------------------------------------------------------
-- slugifica — da testo libero a identificatore d'URL
-- ---------------------------------------------------------------------------
-- Deve produrre qualcosa che soddisfi il CHECK '^[a-z0-9]+(-[a-z0-9]+)*$' di
-- wines.slug e listings.slug, per qualunque input. Il coalesce finale copre
-- il caso limite di un testo che dopo la normalizzazione non lascia nessun
-- carattere utile (per esempio solo ideogrammi o solo punteggiatura): meglio
-- uno slug generico che una violazione di CHECK in faccia all'utente.
--
-- PERCHÉ translate() E NON L'ESTENSIONE unaccent. Gli accenti vanno tolti —
-- senza, "Château d'Yquem" diventerebbe "ch-teau-d-yquem". La strada ovvia
-- sarebbe unaccent, ma la sua forma a un argomento cerca un dizionario nel
-- search_path corrente, e `create extension if not exists ... with schema
-- extensions` non sposta un'estensione già installata altrove: su un progetto
-- dove unaccent esiste già in un altro schema, il riferimento al dizionario
-- non risolverebbe e la migrazione fallirebbe al primo tentativo. translate()
-- è nel core, non dipende da nessuno schema e copre le lettere che compaiono
-- davvero in produttori e nomi di vino.
-- Le due sostituzioni fuori dalla mappa (ß, æ) ci sono perché translate()
-- lavora carattere per carattere e non può espandere una lettera in due.

create or replace function public.slugifica(p_testo text)
returns text
language sql
immutable
set search_path = public
as $$
  select coalesce(
    nullif(
      trim(both '-' from
        regexp_replace(
          translate(
            lower(replace(replace(coalesce(p_testo, ''), 'ß', 'ss'), 'æ', 'ae')),
            'àáâãäåèéêëìíîïòóôõöøùúûüçñýÿ',
            'aaaaaaeeeeiiiioooooouuuucnyy'
          ),
          '[^a-z0-9]+', '-', 'g'
        )
      ),
      ''
    ),
    'annuncio'
  );
$$;

comment on function public.slugifica(text) is
  'Normalizza testo libero in uno slug conforme al CHECK di wines.slug e '
  'listings.slug. Uso interno delle funzioni di creazione: non è concessa a '
  'nessun ruolo client.';

revoke execute on function public.slugifica(text) from public;

-- ---------------------------------------------------------------------------
-- listing_crea — creazione di un annuncio in bozza
-- ---------------------------------------------------------------------------
-- PERCHÉ UNA FUNZIONE E NON UN INSERT DAL CLIENT. La 6a concede già a
-- `authenticated` l'INSERT sulle colonne di contenuto di listings e su
-- bottle_units, quindi un annuncio su una bottiglia già esistente si potrebbe
-- creare direttamente. Il wizard /vendi però non parte da una bottiglia: parte
-- da testo digitato (produttore, nome, annata), e quel vino può non essere
-- ancora in catalogo. `wines` è scrivibile solo da admin o moderator
-- (policy wines_write_staff), quindi la creazione attraversa un confine di
-- privilegio che il client non può attraversare da solo.
--
-- Da lì seguono due proprietà che una sequenza di tre INSERT dal browser non
-- avrebbe: l'operazione è atomica (niente bottiglia orfana se l'annuncio
-- fallisce) e lo slug lo assegna il server (niente slug scelti o occupati dal
-- client).
--
-- UNA CREAZIONE, UNA BOTTIGLIA NUOVA. Non c'è modo di riusare una bottle_unit
-- esistente perché /vendi in frontend/ non ha nessun selettore di cantina: si
-- descrive una bottiglia, non se ne sceglie una. Quando la Fase 6c porterà la
-- Cantina, "metti in vendita questa bottiglia" diventerà un percorso diverso
-- che passa un bottle_unit_id già noto.

create or replace function public.listing_crea(
  p_produttore text,
  p_nome text,
  p_annata integer,
  p_regione text,
  p_tipo text,
  p_prezzo_cents integer,
  p_condizione text default 'Ottimo',
  p_conservazione text default '',
  p_storia text default '',
  p_immagini text[] default '{}'
)
-- I nomi delle colonne restituite sono prefissati (`annuncio_id`,
-- `annuncio_slug`) e non `id`/`slug`: dentro plpgsql i parametri OUT sono
-- variabili, e chiamarli come colonne delle tabelle toccate qui dentro
-- porterebbe a errori di ambiguità al primo riferimento non qualificato.
returns table (annuncio_id uuid, annuncio_slug text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_wine      uuid;
  v_bottle    uuid;
  v_base      text;
  v_slug      text;
  v_n         integer;
  v_immagine  text;
begin
  if v_uid is null then
    raise exception 'Devi accedere per creare un annuncio.' using errcode = '42501';
  end if;

  -- bottle_units.owner_id e listings.seller_id puntano a profiles, non a
  -- auth.users. Un account senza riga in profiles (trigger handle_new_user non
  -- andato a buon fine) produrrebbe altrimenti una violazione di chiave
  -- esterna grezza, illeggibile per chi la riceve nel wizard.
  if not exists (select 1 from public.profiles p where p.id = v_uid) then
    raise exception 'Il tuo profilo non è ancora completo: completalo prima di pubblicare.'
      using errcode = 'P0001';
  end if;

  -- Validazione. Gli stessi limiti sono anche nel wizard, ma il wizard non è
  -- un confine di fiducia: questa funzione è raggiungibile con una POST
  -- diretta a PostgREST, senza passare da nessuna interfaccia.
  if coalesce(trim(p_produttore), '') = '' then
    raise exception 'Il produttore è obbligatorio.' using errcode = 'P0001';
  end if;
  if coalesce(trim(p_nome), '') = '' then
    raise exception 'Il nome del vino è obbligatorio.' using errcode = 'P0001';
  end if;
  if coalesce(trim(p_regione), '') = '' then
    raise exception 'La regione è obbligatoria.' using errcode = 'P0001';
  end if;
  if p_annata is null or p_annata < 1800 or p_annata > 2100 then
    raise exception 'L''annata deve essere compresa fra 1800 e 2100.' using errcode = 'P0001';
  end if;
  if p_tipo is null or p_tipo not in ('Rosso', 'Bianco', 'Bollicine', 'Rosato', 'Dolce') then
    raise exception 'Tipologia non valida.' using errcode = 'P0001';
  end if;
  if p_condizione is null or p_condizione not in ('Perfetto', 'Ottimo', 'Buono') then
    raise exception 'Condizione non valida.' using errcode = 'P0001';
  end if;
  if p_prezzo_cents is null or p_prezzo_cents <= 0 then
    raise exception 'Il prezzo deve essere maggiore di zero.' using errcode = 'P0001';
  end if;
  if array_length(p_immagini, 1) > 6 then
    raise exception 'Massimo 6 fotografie per annuncio.' using errcode = 'P0001';
  end if;

  -- Le immagini sono percorsi dentro il bucket `annunci`, e ogni utente può
  -- scrivere solo sotto la cartella che porta il proprio id. Senza questo
  -- controllo un annuncio potrebbe puntare al file di un altro utente, o a una
  -- stringa arbitraria che l'interfaccia poi mette dentro un <img src>.
  foreach v_immagine in array coalesce(p_immagini, '{}'::text[]) loop
    if v_immagine !~ ('^' || v_uid::text || '/[0-9a-f-]{36}\.(jpg|jpeg|png|webp|avif)$') then
      raise exception 'Fotografia non valida: %', v_immagine using errcode = 'P0001';
    end if;
  end loop;

  -- Catalogo: si riusa la riga esistente se produttore + nome + annata
  -- coincidono, altrimenti se ne crea una. `on conflict do nothing` seguito da
  -- una select copre la corsa fra due venditori che catalogano lo stesso vino
  -- nello stesso istante.
  select w.id into v_wine
  from public.wines w
  where w.produttore = trim(p_produttore)
    and w.nome = trim(p_nome)
    and w.annata = p_annata::smallint;

  if v_wine is null then
    v_base := public.slugifica(p_produttore || ' ' || p_nome || ' ' || p_annata::text);
    v_slug := v_base;
    v_n := 1;
    while exists (select 1 from public.wines w where w.slug = v_slug) loop
      v_n := v_n + 1;
      v_slug := v_base || '-' || v_n;
    end loop;

    insert into public.wines (slug, produttore, nome, annata, regione, tipo)
    values (v_slug, trim(p_produttore), trim(p_nome), p_annata::smallint, trim(p_regione), p_tipo)
    on conflict (produttore, nome, annata) do nothing
    returning wines.id into v_wine;

    if v_wine is null then
      select w.id into v_wine
      from public.wines w
      where w.produttore = trim(p_produttore)
        and w.nome = trim(p_nome)
        and w.annata = p_annata::smallint;
    end if;
  end if;

  -- Unità fisica. Inserimento minimo: proprietario, vino, stato, visibilità.
  -- Posizione, ambiente, modulo e slot arrivano con la Cantina (Fase 6c).
  insert into public.bottle_units (owner_id, wine_id, stato, visibilita)
  values (v_uid, v_wine, 'chiusa', 'privata')
  returning bottle_units.id into v_bottle;

  -- Slug dell'annuncio. Parte dalla stessa base del vino, così il primo
  -- annuncio di un vino ha l'URL leggibile che ci si aspetta
  -- (/annuncio/tignanello-2019) e i successivi si numerano.
  v_base := public.slugifica(p_produttore || ' ' || p_nome || ' ' || p_annata::text);
  v_slug := v_base;
  v_n := 1;
  while exists (select 1 from public.listings l where l.slug = v_slug) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n;
  end loop;

  -- Fra il controllo di disponibilità dello slug e questo INSERT c'è una
  -- finestra in cui un'altra sessione può prendersi lo stesso slug. È
  -- improbabile e senza conseguenze sui dati (l'unicità regge), ma senza
  -- questo blocco l'utente riceverebbe un 23505 grezzo per un problema che si
  -- risolve riprovando.
  begin
    return query
    insert into public.listings (
      slug, seller_id, bottle_unit_id, stato,
      prezzo_cents, condizione, conservazione, storia, immagini
    )
    values (
      v_slug, v_uid, v_bottle, 'bozza',
      p_prezzo_cents, p_condizione, coalesce(p_conservazione, ''), coalesce(p_storia, ''),
      coalesce(p_immagini, '{}'::text[])
    )
    returning listings.id, listings.slug;
  exception
    when unique_violation then
      raise exception 'Non è stato possibile assegnare un indirizzo univoco all''annuncio. Riprova.'
        using errcode = 'P0001';
  end;
end;
$$;

comment on function public.listing_crea(text, text, integer, text, text, integer, text, text, text, text[]) is
  'Crea vino (se manca), unità fisica e annuncio in stato bozza, in una sola '
  'transazione. Venditore e proprietario sono sempre auth.uid(), mai un '
  'parametro. Non pubblica: la pubblicazione è listing_pubblica().';

revoke execute on function public.listing_crea(text, text, integer, text, text, integer, text, text, text, text[]) from public;
grant execute on function public.listing_crea(text, text, integer, text, text, integer, text, text, text, text[]) to authenticated;

-- ---------------------------------------------------------------------------
-- listing_pubblica — bozza | modifiche_richieste → attivo
-- ---------------------------------------------------------------------------
-- Qui vive la traduzione del vincolo di unicità in un messaggio leggibile.
-- L'indice parziale listings_una_sola_attiva_per_bottiglia scatta soltanto
-- quando una riga entra in ('attivo', 'riservato'), quindi non su una bozza:
-- l'unico punto in cui un utente può incontrarlo è esattamente questo, ed è
-- qui che va intercettato. Senza il blocco EXCEPTION, PostgREST restituirebbe
-- il 23505 grezzo di PostgreSQL, con dentro il nome dell'indice.

create or replace function public.listing_pubblica(p_listing_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_seller uuid;
  v_stato  public.listing_stato;
begin
  if v_uid is null then
    raise exception 'Devi accedere per pubblicare un annuncio.' using errcode = '42501';
  end if;

  select l.seller_id, l.stato into v_seller, v_stato
  from public.listings l
  where l.id = p_listing_id;

  if v_seller is null then
    raise exception 'Annuncio non trovato.' using errcode = 'P0001';
  end if;
  if v_seller is distinct from v_uid then
    raise exception 'Non puoi pubblicare un annuncio che non è tuo.' using errcode = '42501';
  end if;
  if v_stato not in ('bozza', 'modifiche_richieste') then
    raise exception 'Si può pubblicare solo un annuncio in bozza o con modifiche richieste.'
      using errcode = 'P0001';
  end if;

  begin
    update public.listings
    set stato = 'attivo',
        published_at = now(),
        -- Sessanta giorni: è la stessa durata usata dai dati di prova della
        -- 6a. In frontend/ non esiste una scadenza degli annunci, quindi non
        -- c'è un valore da rispettare per parità: questa è una scelta
        -- dichiarata, non una regola ereditata.
        expires_at = now() + interval '60 days',
        stato_motivo = null,
        stato_aggiornato_da = v_uid,
        stato_aggiornato_at = now()
    where id = p_listing_id;
  exception
    when unique_violation then
      raise exception
        'Questa bottiglia ha già un annuncio attivo. Sospendi quello attivo prima di pubblicare questo.'
        using errcode = 'P0001';
  end;
end;
$$;

comment on function public.listing_pubblica(uuid) is
  'Porta un annuncio del venditore da bozza (o modifiche_richieste) ad attivo. '
  'Traduce la violazione dell''indice una-sola-attiva-per-bottiglia in un '
  'messaggio leggibile invece di lasciar passare il 23505.';

revoke execute on function public.listing_pubblica(uuid) from public;
grant execute on function public.listing_pubblica(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- listing_sospendi — attivo → sospeso
-- ---------------------------------------------------------------------------
-- Sospensione da parte del venditore: ritira l'annuncio dalla vista pubblica e
-- libera la bottiglia, che torna a poter avere un annuncio attivo.
--
-- Solo da 'attivo', non da 'riservato': riservato significa che un acquisto è
-- in corso (Fase 7), e sospendere sotto i piedi di chi sta comprando è una
-- decisione di dominio che quella fase deve prendere, non questa.
-- La sospensione decisa da un moderatore è un'altra cosa ancora ed è Fase 9:
-- passerà da una funzione separata che verifica has_role(), non da questa.

create or replace function public.listing_sospendi(
  p_listing_id uuid,
  p_motivo text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_seller uuid;
  v_stato  public.listing_stato;
begin
  if v_uid is null then
    raise exception 'Devi accedere per sospendere un annuncio.' using errcode = '42501';
  end if;

  select l.seller_id, l.stato into v_seller, v_stato
  from public.listings l
  where l.id = p_listing_id;

  if v_seller is null then
    raise exception 'Annuncio non trovato.' using errcode = 'P0001';
  end if;
  if v_seller is distinct from v_uid then
    raise exception 'Non puoi sospendere un annuncio che non è tuo.' using errcode = '42501';
  end if;
  if v_stato <> 'attivo' then
    raise exception 'Si può sospendere solo un annuncio attivo.' using errcode = 'P0001';
  end if;

  update public.listings
  set stato = 'sospeso',
      stato_motivo = nullif(trim(coalesce(p_motivo, '')), ''),
      stato_aggiornato_da = v_uid,
      stato_aggiornato_at = now()
  where id = p_listing_id;
end;
$$;

comment on function public.listing_sospendi(uuid, text) is
  'Sospensione decisa dal venditore sul proprio annuncio attivo. La '
  'sospensione di moderazione è Fase 9 e avrà una funzione separata con '
  'controllo has_role().';

revoke execute on function public.listing_sospendi(uuid, text) from public;
grant execute on function public.listing_sospendi(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- listing_scadi — attivo → scaduto
-- ---------------------------------------------------------------------------
-- Materializza una scadenza già avvenuta: rifiuta di agire se expires_at è nel
-- futuro. Senza quel controllo la funzione sarebbe un "ritira l'annuncio"
-- travestito da scadenza, e lo stato `scaduto` smetterebbe di significare
-- qualcosa di verificabile.
--
-- Non c'è nessuna spazzata automatica su tutti i venditori: richiederebbe uno
-- scheduler (pg_cron o Edge Function) che è lavoro di esercizio, non di questa
-- fase. Finché non esiste, un annuncio oltre la scadenza resta 'attivo' finché
-- qualcuno non chiama questa funzione — vero e da sapere.

create or replace function public.listing_scadi(p_listing_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_seller  uuid;
  v_stato   public.listing_stato;
  v_scadenza timestamptz;
begin
  if v_uid is null then
    raise exception 'Devi accedere per far scadere un annuncio.' using errcode = '42501';
  end if;

  select l.seller_id, l.stato, l.expires_at into v_seller, v_stato, v_scadenza
  from public.listings l
  where l.id = p_listing_id;

  if v_seller is null then
    raise exception 'Annuncio non trovato.' using errcode = 'P0001';
  end if;
  if v_seller is distinct from v_uid then
    raise exception 'Non puoi far scadere un annuncio che non è tuo.' using errcode = '42501';
  end if;
  if v_stato <> 'attivo' then
    raise exception 'Si può far scadere solo un annuncio attivo.' using errcode = 'P0001';
  end if;
  if v_scadenza is null or v_scadenza > now() then
    raise exception 'Questo annuncio non è ancora scaduto.' using errcode = 'P0001';
  end if;

  update public.listings
  set stato = 'scaduto',
      stato_aggiornato_da = v_uid,
      stato_aggiornato_at = now()
  where id = p_listing_id;
end;
$$;

comment on function public.listing_scadi(uuid) is
  'Porta ad esaurito un annuncio la cui expires_at è già passata. Rifiuta se '
  'la scadenza è nel futuro: non è una via di ritiro anticipato.';

revoke execute on function public.listing_scadi(uuid) from public;
grant execute on function public.listing_scadi(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Storage — bucket delle fotografie caricate dai venditori
-- ---------------------------------------------------------------------------
-- Gli asset statici di frontend-next/public/images/ restano dove sono: sono
-- illustrazioni dell'interfaccia, non contenuto caricato da utenti, e non
-- hanno niente da fare in un bucket.
--
-- BUCKET PUBBLICO IN LETTURA. Le fotografie di un annuncio attivo sono
-- visibili a chiunque, anche a un visitatore anonimo: è il prodotto. Renderlo
-- privato costringerebbe a firmare un URL per ogni immagine a ogni render,
-- con URL che scadono e non si possono mettere in cache. La conseguenza da
-- accettare, e che dichiaro: anche le foto di una bozza sono leggibili da chi
-- ne indovina l'URL, che contiene due UUID. Non è un'esposizione della bozza
-- (l'annuncio resta invisibile), è l'esposizione del file.
--
-- LIMITI LATO SERVER. file_size_limit e allowed_mime_types sono applicati dal
-- servizio Storage, non dal browser: un upload che sfora viene rifiutato anche
-- se chi lo invia salta del tutto l'interfaccia.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'annunci',
  'annunci',
  true,
  5242880,                                                   -- 5 MB per file
  array['image/jpeg', 'image/png', 'image/webp', 'image/avif']
)
on conflict (id) do update
set public             = excluded.public,
    file_size_limit    = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Convenzione di percorso: <uid>/<uuid>.<estensione>. La prima cartella è
-- l'identificativo del proprietario, ed è ciò su cui lavorano le policy: si
-- scrive solo dentro casa propria. Il percorso non lo sceglie il browser, lo
-- costruisce il server quando firma l'upload — ma la policy non si fida
-- nemmeno di questo e ricontrolla.

drop policy if exists "annunci_select_pubblica" on storage.objects;
drop policy if exists "annunci_insert_propria_cartella" on storage.objects;
drop policy if exists "annunci_update_propria_cartella" on storage.objects;
drop policy if exists "annunci_delete_propria_cartella" on storage.objects;

create policy "annunci_select_pubblica"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'annunci');

create policy "annunci_insert_propria_cartella"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'annunci'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "annunci_update_propria_cartella"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'annunci'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'annunci'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "annunci_delete_propria_cartella"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'annunci'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );
$vinea_ledger_20260729112500$
   ]
 where version = '20260729112500'
   and coalesce(array_length(statements, 1), 0) = 0;

-- ---------------------------------------------------------------------------
-- [4] 20260729180000 cellar_schema
--     file   supabase/migrations/20260729180000_cellar_schema.sql
--     byte   27402
--     sha256 0b87f381e8c46e7e07b760b0fb157582c670050a022c850a27f1da174ea8be56
-- ---------------------------------------------------------------------------

update supabase_migrations.schema_migrations
   set statements = array[
$vinea_ledger_20260729180000$-- Fase 6c-1 — Cantina: schema, RLS e funzioni di posizionamento.
--
-- Nessuna interfaccia in questa fase. Qui nascono le tabelle che la 6c-2
-- userà per portare /cantina: ambienti, moduli, posizioni fisiche, più i
-- metadati di bevuta che finora vivevano nei dati mock.
--
-- COSA C'È E PERCHÉ, in breve:
--   wines                  guadagna le colonne di wineMeta (finestra di
--                          bevuta, abbinamenti, servizio). Restano di
--                          catalogo: scrivibili solo dallo staff, com'era.
--   bottle_units           guadagna ciò che è personale della singola unità:
--                          data di apertura pianificata, note, override della
--                          finestra, visibilità del prezzo.
--   cellar_environments    l'ambiente fisico (cantina interrata, cantinetta).
--   cellar_modules         scaffali e casse dentro un ambiente.
--   cellar_slots           dove sta una bottiglia. Una riga = una posizione
--                          OCCUPATA (vedi il commento sulla tabella).
--   public_listings        `quantita` diventa derivata invece che colonna.
--
-- La cantina è privata per definizione: ogni policy parte da lì, e l'unica
-- eccezione è la singola bottiglia dichiarata `cantina_pubblica`.

-- ---------------------------------------------------------------------------
-- wines — metadati di bevuta e abbinamenti
-- ---------------------------------------------------------------------------
-- Erano in frontend-next/src/data/cellar.ts, indicizzati per slug. Sono
-- metadati del vino-annata, non della bottiglia di qualcuno: due persone che
-- possiedono lo stesso Monfortino 2015 leggono la stessa finestra di bevuta.
-- Per questo stanno su `wines` e non su `bottle_units`; ciò che è personale
-- (un override, una nota) sta invece sull'unità, più in basso.
--
-- Restano scrivibili solo da admin o moderator: la policy `wines_write_staff`
-- della 6a copre già queste colonne, e il GRANT della 6a è a livello di
-- tabella, quindi non serve toccare nessun privilegio.

create type public.drink_window_fonte as enum (
  'editorial',    -- dato editoriale
  'ai',           -- suggerito dall'IA
  'personal',     -- personalizzato dall'utente
  'owner',        -- dichiarato dal proprietario
  'unavailable'   -- informazione non disponibile
);

create type public.drink_window_affidabilita as enum ('alta', 'media', 'bassa');

alter table public.wines
  add column finestra_inizio smallint check (finestra_inizio between 1800 and 2200),
  add column finestra_fine smallint check (finestra_fine between 1800 and 2200),
  add column apice_inizio smallint check (apice_inizio between 1800 and 2200),
  add column apice_fine smallint check (apice_fine between 1800 and 2200),
  add column finestra_fonte public.drink_window_fonte not null default 'unavailable',
  add column finestra_affidabilita public.drink_window_affidabilita,
  add column finestra_aggiornata_at date,
  add column temperatura_servizio text not null default '',
  add column decantazione_minuti smallint check (decantazione_minuti between 0 and 600),
  add column calice text not null default '',
  add column occasione text not null default '',
  -- Gli abbinamenti sono un elenco di oggetti (categoria, piatto, livello,
  -- note, emoji, keywords[]): una tabella normalizzata sarebbe più rigorosa,
  -- ma questi dati si leggono sempre interi insieme al vino e non si
  -- interrogano mai per campo. jsonb tiene la forma identica al mock, che è
  -- ciò che permette alla 6c-2 di collegare i componenti esistenti senza
  -- riscriverli.
  add column abbinamenti jsonb not null default '[]'::jsonb;

alter table public.wines
  add constraint wines_finestra_ordinata
    check (finestra_inizio is null or finestra_fine is null
           or finestra_fine >= finestra_inizio),
  add constraint wines_apice_ordinato
    check (apice_inizio is null or apice_fine is null
           or apice_fine >= apice_inizio),
  -- L'apice è un intervallo dentro la finestra, non accanto ad essa.
  add constraint wines_apice_dentro_finestra
    check (
      (apice_inizio is null or finestra_inizio is null or apice_inizio >= finestra_inizio)
      and (apice_fine is null or finestra_fine is null or apice_fine <= finestra_fine)
    ),
  add constraint wines_abbinamenti_elenco
    check (jsonb_typeof(abbinamenti) = 'array');

comment on column public.wines.finestra_inizio is
  'Primo anno in cui il vino si considera pronto. Nullo quando la finestra '
  'non è disponibile: in quel caso l''interfaccia mostra "informazione non '
  'disponibile" invece di inventare un intervallo.';
comment on column public.wines.abbinamenti is
  'Elenco di abbinamenti cibo, stessa forma di FoodPairing in '
  'frontend-next/src/data/cellar.ts. Nei dati d''origine lo stesso elenco è '
  'condiviso fra vini dello stesso stile (i rossi strutturati hanno gli '
  'stessi cinque abbinamenti): qui la condivisione si perde e ogni vino porta '
  'la propria copia. È la conseguenza accettata di tenerli come colonna.';

-- I filtri "pronte ora" e "quando berlo" cercano per intervallo di anni.
create index wines_finestra_idx on public.wines (finestra_inizio, finestra_fine);

-- ---------------------------------------------------------------------------
-- bottle_units — ciò che è personale della singola unità
-- ---------------------------------------------------------------------------

create type public.preferenza_evoluzione as enum ('giovane', 'equilibrato', 'evoluto');
create type public.prezzo_visibilita as enum ('visibile', 'riservato');

alter table public.bottle_units
  add column apertura_pianificata date,
  add column note_personali text not null default '',
  add column prezzo_visibilita public.prezzo_visibilita not null default 'visibile',
  -- Override della finestra di bevuta. Colonne piatte e non jsonb perché la
  -- vista "pronte ora" filtra sull'intervallo efficace, cioè
  -- coalesce(override, valore del vino): con jsonb ogni confronto passerebbe
  -- da un cast, e nessun indice sarebbe utilizzabile.
  add column override_finestra_inizio smallint check (override_finestra_inizio between 1800 and 2200),
  add column override_finestra_fine smallint check (override_finestra_fine between 1800 and 2200),
  add column override_apice_inizio smallint check (override_apice_inizio between 1800 and 2200),
  add column override_apice_fine smallint check (override_apice_fine between 1800 and 2200),
  add column override_preferenza public.preferenza_evoluzione,
  add column override_nota text not null default '';

alter table public.bottle_units
  add constraint bottle_units_override_ordinato
    check (override_finestra_inizio is null or override_finestra_fine is null
           or override_finestra_fine >= override_finestra_inizio);

comment on column public.bottle_units.apertura_pianificata is
  'Data in cui il proprietario ha programmato di aprire la bottiglia. '
  'frontend/docs/DOMAIN_MODEL.md elenca "programmata" fra gli stati: non lo '
  'è, è la presenza di questa data. Lo stato fisico resta chiusa/aperta/'
  'consumata, come deciso in 6a.';

-- Queste colonne non hanno regole di dominio dietro: sono scelte personali del
-- proprietario, e la policy bottle_units_update_own è già sufficiente. Si
-- aggiungono quindi ai GRANT di colonna della 6a. `stato` resta fuori, come
-- prima: l'unica colonna con regole è quella, e non si tocca.
grant insert (
  apertura_pianificata, note_personali, prezzo_visibilita,
  override_finestra_inizio, override_finestra_fine,
  override_apice_inizio, override_apice_fine,
  override_preferenza, override_nota
) on public.bottle_units to authenticated;

grant update (
  apertura_pianificata, note_personali, prezzo_visibilita,
  override_finestra_inizio, override_finestra_fine,
  override_apice_inizio, override_apice_fine,
  override_preferenza, override_nota
) on public.bottle_units to authenticated;

-- ---------------------------------------------------------------------------
-- cellar_environments — l'ambiente fisico
-- ---------------------------------------------------------------------------

create type public.env_forma as enum (
  'parete_lineare', 'scaffalatura_modulare', 'cantinetta', 'cassa_legno', 'nicchia_angolare'
);

create type public.env_tema as enum (
  'moderna', 'rustica', 'classica', 'pietra', 'industriale', 'minimal', 'premium', 'casse'
);

create type public.env_materiale as enum (
  'rovere', 'noce', 'metallo', 'pietra', 'mattone', 'cemento', 'vetro', 'legno_grezzo'
);

create type public.env_illuminazione as enum (
  'calda', 'neutra', 'soffusa', 'faretti', 'laterale'
);

create table public.cellar_environments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid()
    references public.profiles (id) on delete cascade,
  nome text not null check (length(trim(nome)) > 0),
  forma public.env_forma not null,
  tema public.env_tema not null,
  materiale public.env_materiale not null,
  illuminazione public.env_illuminazione not null,
  -- In centimetri interi. I dati d'origine usano metri con la virgola
  -- (2.5 m di altezza): un'unità intera più piccola dice la stessa cosa
  -- senza virgola mobile in una misura che finisce dentro un calcolo 3D.
  larghezza_cm integer not null check (larghezza_cm between 10 and 5000),
  altezza_cm integer not null check (altezza_cm between 10 and 5000),
  profondita_cm integer not null check (profondita_cm between 10 and 5000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.cellar_environments is
  'Ambiente fisico di conservazione di un utente. Privato: nessuna policy lo '
  'espone a terzi, nemmeno quando contiene bottiglie dichiarate pubbliche — '
  'ciò che si rende pubblico è la bottiglia, non i mobili di casa propria.';

create index cellar_environments_owner_idx on public.cellar_environments (owner_id);

create trigger cellar_environments_set_updated_at
  before update on public.cellar_environments
  for each row
  execute function extensions.moddatetime('updated_at');

revoke all on public.cellar_environments from anon, authenticated;
grant select on public.cellar_environments to authenticated;
grant insert (nome, forma, tema, materiale, illuminazione,
              larghezza_cm, altezza_cm, profondita_cm)
  on public.cellar_environments to authenticated;
grant update (nome, forma, tema, materiale, illuminazione,
              larghezza_cm, altezza_cm, profondita_cm)
  on public.cellar_environments to authenticated;
grant delete on public.cellar_environments to authenticated;
-- Nessun privilegio su owner_id: il proprietario si stabilisce alla creazione
-- (default auth.uid()) e non è cedibile con un UPDATE dal browser.

alter table public.cellar_environments enable row level security;

create policy "cellar_environments_own"
  on public.cellar_environments for all
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Chi possiede un ambiente / un modulo
-- ---------------------------------------------------------------------------
-- Le policy di cellar_modules e cellar_slots devono risalire al proprietario
-- passando per un'altra tabella. Farlo con una sottoquery dentro la policy
-- significherebbe valutare la RLS di quella tabella dentro la RLS di questa:
-- accoppiamento fragile e a rischio di ricorsione. Si isola in funzioni
-- SECURITY DEFINER, come già fatto in 6a con has_role() e
-- bottle_unit_in_annuncio_pubblico().

create or replace function public.cellar_ambiente_e_mio(p_environment_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.cellar_environments e
    where e.id = p_environment_id
      and e.owner_id = auth.uid()
  );
$$;

revoke execute on function public.cellar_ambiente_e_mio(uuid) from public;
grant execute on function public.cellar_ambiente_e_mio(uuid) to authenticated;

-- La gemella `cellar_modulo_e_mio` sta più in basso, dopo la tabella dei
-- moduli: il corpo di una funzione `language sql` viene validato al momento
-- della creazione, quindi non può nominare una tabella che ancora non esiste.

-- ---------------------------------------------------------------------------
-- cellar_modules — scaffali, casse, cantinette dentro un ambiente
-- ---------------------------------------------------------------------------

create table public.cellar_modules (
  id uuid primary key default gen_random_uuid(),
  environment_id uuid not null
    references public.cellar_environments (id) on delete cascade,
  etichetta text not null check (length(trim(etichetta)) > 0),
  -- Posizione e rotazione dentro l'ambiente, per la vista 3D. Qui la virgola
  -- serve davvero (un modulo sta a -1,6 m dal centro) e numeric la
  -- rappresenta senza gli errori del binario.
  posizione_x numeric(6, 2) not null default 0,
  posizione_y numeric(6, 2) not null default 0,
  posizione_z numeric(6, 2) not null default 0,
  rotazione_y numeric(6, 2) not null default 0,
  righe smallint not null check (righe between 1 and 50),
  colonne smallint not null check (colonne between 1 and 50),
  profondita smallint not null default 1 check (profondita between 1 and 10),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.cellar_modules is
  'Un modulo di stoccaggio dentro un ambiente. `righe` e `colonne` ne '
  'descrivono la geometria: le posizioni disponibili sono righe × colonne e '
  'si calcolano, non si memorizzano (vedi cellar_slots).';

create index cellar_modules_environment_idx on public.cellar_modules (environment_id);

create trigger cellar_modules_set_updated_at
  before update on public.cellar_modules
  for each row
  execute function extensions.moddatetime('updated_at');

revoke all on public.cellar_modules from anon, authenticated;
grant select on public.cellar_modules to authenticated;
grant insert (environment_id, etichetta, posizione_x, posizione_y, posizione_z,
              rotazione_y, righe, colonne, profondita)
  on public.cellar_modules to authenticated;
grant update (etichetta, posizione_x, posizione_y, posizione_z,
              rotazione_y, righe, colonne, profondita)
  on public.cellar_modules to authenticated;
grant delete on public.cellar_modules to authenticated;

alter table public.cellar_modules enable row level security;

create policy "cellar_modules_own"
  on public.cellar_modules for all
  to authenticated
  using (public.cellar_ambiente_e_mio(environment_id))
  with check (public.cellar_ambiente_e_mio(environment_id));

create or replace function public.cellar_modulo_e_mio(p_module_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.cellar_modules m
      join public.cellar_environments e on e.id = m.environment_id
    where m.id = p_module_id
      and e.owner_id = auth.uid()
  );
$$;

revoke execute on function public.cellar_modulo_e_mio(uuid) from public;
grant execute on function public.cellar_modulo_e_mio(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- cellar_slots — dove sta una bottiglia
-- ---------------------------------------------------------------------------
-- UNA RIGA = UNA POSIZIONE OCCUPATA. Nei dati mock gli slot sono materializzati
-- tutti in anticipo (`makeSlots()` genera righe × colonne voci con
-- status: "libero"), ma quelle righe non contengono informazione: sono
-- interamente derivabili dalla geometria del modulo. Materializzarle
-- significherebbe tenere allineate 61 righe per utente a ogni modifica di
-- `righe`/`colonne`, e avere due fonti di verità sulla stessa geometria — la
-- stessa ragione per cui la 6a ha rifiutato di copiare `in_vendita` e
-- `venduta` su bottle_units.
--
-- Qui una posizione libera è semplicemente una coppia (riga, colonna) senza
-- riga corrispondente. `bottle_unit_id` è NOT NULL apposta: rende impossibile
-- inserire uno "slot vuoto" e reintrodurre il problema per sbaglio.
--
-- Il campo `status` del mock ("libero" | "occupato") non esiste per lo stesso
-- motivo: sarebbe la ripetizione di un fatto già scritto.

create table public.cellar_slots (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null references public.cellar_modules (id) on delete cascade,
  bottle_unit_id uuid not null references public.bottle_units (id) on delete cascade,
  riga smallint not null check (riga >= 0),
  colonna smallint not null check (colonna >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Due bottiglie non stanno nello stesso buco.
  constraint cellar_slots_posizione_unica unique (module_id, riga, colonna),
  -- E una bottiglia non sta in due posti insieme.
  constraint cellar_slots_bottiglia_unica unique (bottle_unit_id)
);

comment on table public.cellar_slots is
  'Posizione fisica di una bottiglia dentro un modulo. Una riga esiste solo '
  'se la posizione è occupata: le posizioni libere si ricavano dalla '
  'geometria del modulo (righe × colonne) meno quelle presenti qui.';

create index cellar_slots_module_idx on public.cellar_slots (module_id);

create trigger cellar_slots_set_updated_at
  before update on public.cellar_slots
  for each row
  execute function extensions.moddatetime('updated_at');

-- Nessun privilegio di scrittura al client: riga e colonna vanno verificate
-- contro la geometria del modulo, e la bottiglia contro il suo proprietario.
-- Sono regole, quindi la scrittura passa dalle funzioni più sotto, che sono
-- l'unica porta. Un CHECK non basterebbe: dovrebbe interrogare un'altra
-- tabella, cosa che un CHECK non può fare.
revoke all on public.cellar_slots from anon, authenticated;
grant select on public.cellar_slots to authenticated;

alter table public.cellar_slots enable row level security;

create policy "cellar_slots_select_own"
  on public.cellar_slots for select
  to authenticated
  using (public.cellar_modulo_e_mio(module_id));

-- ---------------------------------------------------------------------------
-- Funzioni di posizionamento
-- ---------------------------------------------------------------------------

-- Riga e colonna sono `integer` e non `smallint` di proposito: PostgREST
-- riceve numeri JSON e risolve la funzione per tipo, e uno smallint nella
-- firma rende la risoluzione fragile. Il restringimento avviene qui dentro,
-- dopo i controlli di intervallo.
create or replace function public.cellar_posiziona(
  p_bottle_unit_id uuid,
  p_module_id uuid,
  p_riga integer,
  p_colonna integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_righe    smallint;
  v_colonne  smallint;
begin
  if v_uid is null then
    raise exception 'Devi accedere per spostare una bottiglia.' using errcode = '42501';
  end if;

  -- La bottiglia dev'essere tua e non cancellata.
  if not exists (
    select 1 from public.bottle_units bu
    where bu.id = p_bottle_unit_id
      and bu.owner_id = v_uid
      and bu.deleted_at is null
  ) then
    raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
  end if;

  -- E il modulo pure.
  select m.righe, m.colonne into v_righe, v_colonne
  from public.cellar_modules m
    join public.cellar_environments e on e.id = m.environment_id
  where m.id = p_module_id
    and e.owner_id = v_uid;

  if v_righe is null then
    raise exception 'Questo scaffale non è nella tua cantina.' using errcode = '42501';
  end if;

  -- Riga e colonna partono da 0, come nei dati d'origine.
  if p_riga is null or p_riga < 0 or p_riga >= v_righe then
    raise exception 'Riga fuori dallo scaffale: ne ha %.', v_righe using errcode = 'P0001';
  end if;
  if p_colonna is null or p_colonna < 0 or p_colonna >= v_colonne then
    raise exception 'Colonna fuori dallo scaffale: ne ha %.', v_colonne using errcode = 'P0001';
  end if;

  -- Spostare una bottiglia già collocata è un aggiornamento, non un secondo
  -- posto: l'unicità su bottle_unit_id lo garantisce, e l'ON CONFLICT lo
  -- rende un'operazione sola invece di "cancella e reinserisci".
  begin
    insert into public.cellar_slots (module_id, bottle_unit_id, riga, colonna)
    values (p_module_id, p_bottle_unit_id, p_riga::smallint, p_colonna::smallint)
    on conflict (bottle_unit_id) do update
      set module_id = excluded.module_id,
          riga      = excluded.riga,
          colonna   = excluded.colonna;
  exception
    when unique_violation then
      raise exception 'In quella posizione c''è già una bottiglia.' using errcode = 'P0001';
  end;
end;
$$;

comment on function public.cellar_posiziona(uuid, uuid, integer, integer) is
  'Colloca o sposta una bottiglia in una posizione dello scaffale. Verifica '
  'che bottiglia e scaffale siano di chi chiama e che la posizione esista '
  'davvero nella geometria del modulo.';

revoke execute on function public.cellar_posiziona(uuid, uuid, integer, integer) from public;
grant execute on function public.cellar_posiziona(uuid, uuid, integer, integer) to authenticated;

create or replace function public.cellar_togli_posizione(p_bottle_unit_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Devi accedere per spostare una bottiglia.' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.bottle_units bu
    where bu.id = p_bottle_unit_id and bu.owner_id = v_uid
  ) then
    raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
  end if;

  delete from public.cellar_slots where bottle_unit_id = p_bottle_unit_id;
end;
$$;

comment on function public.cellar_togli_posizione(uuid) is
  'Toglie una bottiglia dalla sua posizione, lasciandola in cantina senza '
  'collocazione. Non cancella la bottiglia.';

revoke execute on function public.cellar_togli_posizione(uuid) from public;
grant execute on function public.cellar_togli_posizione(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- bottle_units visibili perché dichiarate di cantina pubblica
-- ---------------------------------------------------------------------------
-- La 6a esponeva un'unità solo se collegata a un annuncio attivo. Da qui si
-- aggiunge il secondo caso previsto dal dominio: il proprietario ha deciso che
-- quella bottiglia sta nella sua cantina pubblica. Resta una decisione per
-- singola bottiglia — non esiste un interruttore che renda pubblica l'intera
-- cantina — e non espone né ambienti né moduli né posizioni.

create policy "bottle_units_select_cantina_pubblica"
  on public.bottle_units for select
  to anon, authenticated
  using (visibilita = 'cantina_pubblica' and deleted_at is null);

-- ---------------------------------------------------------------------------
-- listings.quantita — da colonna a valore derivato
-- ---------------------------------------------------------------------------
-- Il commento sulla colonna, scritto in 6a, diceva: "Diventerà significativa
-- solo quando la Cantina permetterà di collegare più unità allo stesso
-- annuncio: a quel punto sarà un conteggio derivato, non un valore digitato."
-- È questo il momento.
--
-- La colonna sparisce invece di restare accanto al conteggio: tenerle entrambe
-- creerebbe due fonti di verità sulla stessa quantità, che è esattamente il
-- difetto che la 6a ha evitato ovunque.
--
-- ONESTÀ SUL VALORE DI OGGI. Il legame annuncio → unità è ancora uno a uno
-- (`listings.bottle_unit_id`), quindi il conteggio vale 1 per ogni annuncio
-- attivo: identico a prima, ed è quello che la prova di regressione verifica.
-- Diventerà maggiore di 1 quando esisterà un legame uno-a-molti, che è lavoro
-- della fase in cui nascerà l'interfaccia per usarlo. La vista intermedia qui
-- sotto esiste perché quel giorno cambi solo lei, e non public_listings.

create view public.listing_bottle_units
with (security_invoker = off)
as
select
  l.id  as listing_id,
  bu.id as bottle_unit_id
from public.listings l
  join public.bottle_units bu on bu.id = l.bottle_unit_id
where bu.deleted_at is null;

comment on view public.listing_bottle_units is
  'Le unità fisiche che un annuncio sta vendendo. Oggi è una per annuncio, '
  'perché il legame è uno a uno; quando diventerà uno-a-molti basterà '
  'cambiare questa vista, e il conteggio in public_listings seguirà.';

-- Nessun privilegio a nessun ruolo client: è una vista di servizio, non
-- un'API. Scavalca la RLS (security_invoker = off), quindi elencherebbe anche
-- le unità collegate a bozze — non contenuti, ma comunque l'esistenza di
-- annunci non pubblici. `public_listings` la legge lo stesso, perché anche lei
-- valuta con i privilegi del proprietario.
revoke all on public.listing_bottle_units from anon, authenticated;

-- La vista si ridefinisce per intero: `create or replace view` non permette di
-- cambiare il tipo o l'origine di una colonna già esposta. Va eliminata PRIMA
-- di togliere `quantita` da listings, altrimenti PostgreSQL rifiuta il DROP
-- COLUMN: la vista dipende da quella colonna.
drop view public.public_listings;

alter table public.listings drop column quantita;

create view public.public_listings
with (security_invoker = off)
as
select
  l.id,
  l.slug,
  l.prezzo_cents,
  l.prezzo_mercato_cents,
  -- Il cast a integer non è cosmetico: count() è bigint, e un bigint viaggia
  -- verso il client con regole di serializzazione diverse da un intero
  -- normale. La colonna prima era `integer` e deve restarlo, altrimenti
  -- l'adattatore TypeScript riceve una forma diversa senza che nessuno
  -- l'abbia chiesto.
  (
    select count(*)
    from public.listing_bottle_units lbu
    where lbu.listing_id = l.id
  )::integer as quantita,
  l.condizione,
  l.conservazione,
  l.storia,
  l.degustazione,
  l.immagini,
  l.tag,
  l.published_at,
  l.created_at,
  coalesce(l.published_at, l.created_at) as pubblicato_at,
  w.id            as wine_id,
  w.slug          as wine_slug,
  w.produttore,
  w.nome,
  w.annata,
  w.regione,
  w.denominazione,
  w.tipo,
  w.formato,
  w.produttore || ' ' || w.nome as ricerca,
  p.id            as seller_id,
  p.username      as seller_username,
  p.citta         as seller_citta,
  p.avatar_url    as seller_avatar_url
from public.listings l
  join public.bottle_units bu on bu.id = l.bottle_unit_id
  join public.wines w on w.id = bu.wine_id
  join public.profiles p on p.id = l.seller_id
where l.stato = 'attivo';

comment on view public.public_listings is
  'Annunci attivi con vino e venditore già uniti, nella forma che serve a '
  '/esplora e a /annuncio/[slug]. Espone solo campi non sensibili del '
  'profilo venditore (mai dob, esperienza, bio, obiettivi). `quantita` è '
  'derivata dal conteggio delle unità collegate, non più una colonna.';

revoke all on public.public_listings from anon, authenticated;
grant select on public.public_listings to anon, authenticated;
$vinea_ledger_20260729180000$
   ]
 where version = '20260729180000'
   and coalesce(array_length(statements, 1), 0) = 0;

-- ---------------------------------------------------------------------------
-- [5] 20260729180500 seed_wine_meta
--     file   supabase/migrations/20260729180500_seed_wine_meta.sql
--     byte   7999
--     sha256 59d0acc600b4cd7515e301b860e96c568b6873d985c8b3f593966b8c3ad8ff77
-- ---------------------------------------------------------------------------

update supabase_migrations.schema_migrations
   set statements = array[
$vinea_ledger_20260729180500$-- Fase 6c-1 — Metadati di bevuta e abbinamenti per gli 8 vini del catalogo.
--
-- Copia diretta di `wineMeta` da frontend-next/src/data/cellar.ts: stessi
-- anni, stesse note, stessi abbinamenti, nessun testo inventato. La chiave è
-- lo slug, la stessa già usata dal seed della 6a.
--
-- Gli elenchi di abbinamenti sono quattro, condivisi per stile fra i vini che
-- se li assomigliano: nel file d'origine sono quattro costanti riusate, qui
-- diventano quattro variabili riusate. La condivisione si perde nel dato
-- salvato — ogni vino porta la propria copia — ed è la conseguenza accettata
-- di tenerli come colonna su `wines` invece che in una tabella a parte.
--
-- I vini creati dai venditori (via listing_crea) restano senza metadati:
-- finestra_fonte vale 'unavailable' e l'interfaccia mostra "informazione non
-- disponibile" invece di inventare un intervallo. È il comportamento che il
-- mock già aveva con DEFAULT_META.

do $migrazione$
declare
  v_rossi_strutturati jsonb := $json$[
    {"categoria":"Brasati e stufati","piatto":"Brasato al Barolo con polenta","livello":"ideale","note":"La struttura tannica bilancia la lunga cottura.","emoji":"🥘","keywords":["brasato","stufato","polenta","stracotto"]},
    {"categoria":"Selvaggina","piatto":"Cinghiale in umido","livello":"ideale","note":"Note terrose in armonia con la selvaggina.","emoji":"🍖","keywords":["cinghiale","cervo","lepre","selvaggina"]},
    {"categoria":"Formaggi stagionati","piatto":"Castelmagno o Parmigiano 36 mesi","livello":"ottimo","note":"Sapidità e persistenza si esaltano.","emoji":"🧀","keywords":["formaggio","parmigiano","pecorino","castelmagno"]},
    {"categoria":"Arrosti","piatto":"Arrosto di manzo alle erbe","livello":"ottimo","note":"Un classico affidabile.","emoji":"🥩","keywords":["arrosto","manzo","roast"]},
    {"categoria":"Funghi","piatto":"Risotto ai porcini","livello":"possibile","note":"L'umami dei funghi trova un buon dialogo.","emoji":"🍄","keywords":["funghi","porcini","risotto"]}
  ]$json$::jsonb;

  v_super_tuscan jsonb := $json$[
    {"categoria":"Grigliata","piatto":"Bistecca alla fiorentina","livello":"ideale","note":"Cabernet e carne rossa: matrimonio classico.","emoji":"🥩","keywords":["bistecca","fiorentina","grigliata","tagliata"]},
    {"categoria":"Selvaggina","piatto":"Filetto di capriolo","livello":"ideale","note":"Grafite e cassis sostengono il selvatico.","emoji":"🍖","keywords":["capriolo","cervo","selvaggina","filetto"]},
    {"categoria":"Formaggi","piatto":"Pecorino toscano stagionato","livello":"ottimo","note":"Rotondità mediterranea.","emoji":"🧀","keywords":["pecorino","formaggio"]},
    {"categoria":"Primi importanti","piatto":"Pappardelle al ragù di cinghiale","livello":"ottimo","note":"Piatto di terra toscano.","emoji":"🍝","keywords":["ragù","pappardelle","pasta","cinghiale"]},
    {"categoria":"Funghi e tartufo","piatto":"Tagliolini al tartufo","livello":"possibile","note":"Se il vino è ben ossigenato.","emoji":"🍄","keywords":["tartufo","tagliolini","funghi"]}
  ]$json$::jsonb;

  v_champagne jsonb := $json$[
    {"categoria":"Crostacei","piatto":"Ostriche e scampi crudi","livello":"ideale","note":"Sapidità e bollicina tagliano la dolcezza iodata.","emoji":"🦪","keywords":["ostriche","scampi","crudi","crostacei"]},
    {"categoria":"Pesce nobile","piatto":"Astice al vapore","livello":"ideale","note":"Eleganza su eleganza.","emoji":"🦞","keywords":["astice","aragosta","pesce"]},
    {"categoria":"Tartare e carpacci","piatto":"Tartare di ricciola agli agrumi","livello":"ottimo","note":"Freschezza vs freschezza.","emoji":"🐟","keywords":["tartare","carpaccio","crudo"]},
    {"categoria":"Aperitivo","piatto":"Focaccia e culatello","livello":"ottimo","note":"Un aperitivo di livello.","emoji":"🥂","keywords":["aperitivo","focaccia","salumi"]},
    {"categoria":"Pasticceria salata","piatto":"Vol au vent al formaggio","livello":"possibile","note":"Con moderazione.","emoji":"🥐","keywords":["pasticceria","salata","vol au vent"]}
  ]$json$::jsonb;

  v_rossi_eleganti jsonb := $json$[
    {"categoria":"Primi al ragù","piatto":"Pici al ragù di chianina","livello":"ideale","note":"Sangiovese e ragù, tradizione toscana.","emoji":"🍝","keywords":["ragù","pici","pasta","sugo"]},
    {"categoria":"Grigliata","piatto":"Costata di manzo","livello":"ideale","note":"Tannino vibrante contro grasso della carne.","emoji":"🥩","keywords":["costata","griglia","manzo"]},
    {"categoria":"Formaggi","piatto":"Pecorino romano","livello":"ottimo","note":"Sapidità e freschezza si equilibrano.","emoji":"🧀","keywords":["pecorino","formaggio"]},
    {"categoria":"Verdure alla brace","piatto":"Melanzane arrostite","livello":"possibile","note":"Piatto vegetariano ma d'impatto.","emoji":"🍆","keywords":["verdure","melanzane","brace"]}
  ]$json$::jsonb;

  v_riga  record;
  v_tocchi int := 0;
begin
  for v_riga in
    select * from (values
      ('monfortino-2015',           2028, 2055, 2032, 2048, 'editorial', 'alta',  '17–18 °C', 120, 'Calice grande Nebbiolo/Borgogna', 'Cena importante, tavola formale',   date '2026-06-01', 'strutturati'),
      ('sassicaia-2018',            2025, 2045, 2028, 2038, 'editorial', 'alta',  '17–18 °C',  90, 'Calice Bordeaux',                'Cena di gala, verticale con amici', date '2026-05-20', 'tuscan'),
      ('tignanello-2019',           2025, 2040, 2027, 2035, 'ai',        'media', '17–18 °C',  60, 'Calice Bordeaux medio',          'Cena importante ma informale',      date '2026-06-10', 'tuscan'),
      ('dom-perignon-2013',         2024, 2040, 2026, 2035, 'editorial', 'alta',  '8–10 °C',    0, 'Tulipano da Champagne',          'Celebrazioni, aperitivi importanti', date '2026-05-01', 'champagne'),
      ('ornellaia-2017',            2024, 2038, 2026, 2034, 'editorial', 'alta',  '17–18 °C',  75, 'Calice Bordeaux',                'Cena importante',                   date '2026-04-15', 'tuscan'),
      ('biondi-santi-2016',         2026, 2050, 2030, 2045, 'editorial', 'alta',  '17–18 °C',  90, 'Calice Sangiovese ampio',        'Cena di grande respiro',            date '2026-03-30', 'eleganti'),
      ('rinaldi-brunate-2018',      2027, 2045, 2030, 2042, 'ai',        'media', '17 °C',     90, 'Calice Nebbiolo',                'Serata tra appassionati',           date '2026-06-15', 'strutturati'),
      ('cadelbosco-annamaria-2015', 2023, 2035, 2025, 2032, 'editorial', 'alta',  '9–11 °C',    0, 'Tulipano ampio',                 'Aperitivo o cena di pesce',         date '2026-05-05', 'champagne')
    ) as t(slug, f_inizio, f_fine, a_inizio, a_fine, fonte, affidabilita,
           temperatura, decantazione, calice, occasione, aggiornato, stile)
  loop
    update public.wines w
    set finestra_inizio       = v_riga.f_inizio::smallint,
        finestra_fine         = v_riga.f_fine::smallint,
        apice_inizio          = v_riga.a_inizio::smallint,
        apice_fine            = v_riga.a_fine::smallint,
        finestra_fonte        = v_riga.fonte::public.drink_window_fonte,
        finestra_affidabilita = v_riga.affidabilita::public.drink_window_affidabilita,
        finestra_aggiornata_at = v_riga.aggiornato,
        temperatura_servizio  = v_riga.temperatura,
        decantazione_minuti   = v_riga.decantazione::smallint,
        calice                = v_riga.calice,
        occasione             = v_riga.occasione,
        abbinamenti           = case v_riga.stile
                                  when 'strutturati' then v_rossi_strutturati
                                  when 'tuscan'      then v_super_tuscan
                                  when 'champagne'   then v_champagne
                                  else                    v_rossi_eleganti
                                end
    where w.slug = v_riga.slug;

    v_tocchi := v_tocchi + 1;
  end loop;

  raise notice 'Metadati applicati a % vini del catalogo.', v_tocchi;
end;
$migrazione$;
$vinea_ledger_20260729180500$
   ]
 where version = '20260729180500'
   and coalesce(array_length(statements, 1), 0) = 0;

-- ---------------------------------------------------------------------------
-- [6] 20260729210000 listing_crea_da_bottiglia
--     file   supabase/migrations/20260729210000_listing_crea_da_bottiglia.sql
--     byte   11704
--     sha256 772165dc5c15cd2f183baa6e7dd5f9cb57696b62a4dd5124c33e9d30d938280e
-- ---------------------------------------------------------------------------

update supabase_migrations.schema_migrations
   set statements = array[
$vinea_ledger_20260729210000$-- ===========================================================================
-- Fase 6c-2 — "Metti in vendita questa bottiglia"
--
-- Dalla Cantina la vendita parte da una bottiglia che esiste già, non da testo
-- digitato. `listing_crea` invece conia sempre una `bottle_unit` nuova: il
-- commento scritto in 6b lo diceva esplicitamente ("quando la Fase 6c porterà
-- la Cantina, 'metti in vendita questa bottiglia' diventerà un percorso
-- diverso che passa un bottle_unit_id già noto"). Questo è quel momento.
--
-- PERCHÉ UN PARAMETRO E NON UNA FUNZIONE NUOVA. Le due vie condividono tutto
-- ciò che conta: validazione di prezzo, condizione e fotografie, generazione
-- dello slug, inserimento dell'annuncio in bozza, gestione della corsa sullo
-- slug. Una `listing_crea_da_bottiglia` separata duplicherebbe quella metà e
-- imporrebbe di tenerla allineata a mano. Cambia solo da dove arriva l'unità
-- fisica, ed è esattamente ciò che un parametro esprime.
--
-- PERCHÉ DROP E NON CREATE OR REPLACE. Aggiungere un parametro cambia la firma
-- della funzione, e `create or replace` non sostituirebbe la vecchia: ne
-- creerebbe una seconda in sovraccarico. PostgREST risolve le RPC per nome dei
-- parametri e con due firme compatibili la scelta diventa ambigua, quindi la
-- vecchia va rimossa prima. Privilegi e commento se ne vanno con lei e si
-- riassegnano più sotto.
--
-- COSA NON CAMBIA. Senza `p_bottle_unit_id` la funzione si comporta come
-- prima, riga per riga: il wizard che descrive una bottiglia da zero continua
-- a coniare vino e unità come in 6b.
-- ===========================================================================

drop function if exists public.listing_crea(
  text, text, integer, text, text, integer, text, text, text, text[]
);

-- I cinque parametri di identificazione prendono un valore predefinito perché
-- nella via "bottiglia esistente" non servono: descrivono il vino, che in quel
-- caso è già deciso e si legge dall'unità. Chiederli comunque significherebbe
-- far riecheggiare al client dati che il server conosce già, e dare
-- l'impressione che passandoli diversi si possa rinominare un vino di
-- catalogo — cosa che la 6b ha già rifiutato per `listing_aggiorna`.
create function public.listing_crea(
  p_produttore text default '',
  p_nome text default '',
  p_annata integer default null,
  p_regione text default '',
  p_tipo text default null,
  p_prezzo_cents integer default null,
  p_condizione text default 'Ottimo',
  p_conservazione text default '',
  p_storia text default '',
  p_immagini text[] default '{}',
  p_bottle_unit_id uuid default null
)
-- I nomi delle colonne restituite sono prefissati (`annuncio_id`,
-- `annuncio_slug`) e non `id`/`slug`: dentro plpgsql i parametri OUT sono
-- variabili, e chiamarli come colonne delle tabelle toccate qui dentro
-- porterebbe a errori di ambiguità al primo riferimento non qualificato.
returns table (annuncio_id uuid, annuncio_slug text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_wine       uuid;
  v_bottle     uuid;
  v_base       text;
  v_slug       text;
  v_n          integer;
  v_immagine   text;
  -- Testo da cui nasce lo slug: dai campi digitati nella via da zero, dal vino
  -- dell'unità nella via che parte da una bottiglia.
  v_etichetta  text;
begin
  if v_uid is null then
    raise exception 'Devi accedere per creare un annuncio.' using errcode = '42501';
  end if;

  -- bottle_units.owner_id e listings.seller_id puntano a profiles, non a
  -- auth.users. Un account senza riga in profiles (trigger handle_new_user non
  -- andato a buon fine) produrrebbe altrimenti una violazione di chiave
  -- esterna grezza, illeggibile per chi la riceve nel wizard.
  if not exists (select 1 from public.profiles p where p.id = v_uid) then
    raise exception 'Il tuo profilo non è ancora completo: completalo prima di pubblicare.'
      using errcode = 'P0001';
  end if;

  -- -------------------------------------------------------------------------
  -- Validazioni comuni alle due vie.
  -- Gli stessi limiti sono anche nel wizard, ma il wizard non è un confine di
  -- fiducia: questa funzione è raggiungibile con una POST diretta a PostgREST,
  -- senza passare da nessuna interfaccia.
  -- -------------------------------------------------------------------------
  if p_condizione is null or p_condizione not in ('Perfetto', 'Ottimo', 'Buono') then
    raise exception 'Condizione non valida.' using errcode = 'P0001';
  end if;
  if p_prezzo_cents is null or p_prezzo_cents <= 0 then
    raise exception 'Il prezzo deve essere maggiore di zero.' using errcode = 'P0001';
  end if;
  if array_length(p_immagini, 1) > 6 then
    raise exception 'Massimo 6 fotografie per annuncio.' using errcode = 'P0001';
  end if;

  -- Le immagini sono percorsi dentro il bucket `annunci`, e ogni utente può
  -- scrivere solo sotto la cartella che porta il proprio id. Senza questo
  -- controllo un annuncio potrebbe puntare al file di un altro utente, o a una
  -- stringa arbitraria che l'interfaccia poi mette dentro un <img src>.
  foreach v_immagine in array coalesce(p_immagini, '{}'::text[]) loop
    if v_immagine !~ ('^' || v_uid::text || '/[0-9a-f-]{36}\.(jpg|jpeg|png|webp|avif)$') then
      raise exception 'Fotografia non valida: %', v_immagine using errcode = 'P0001';
    end if;
  end loop;

  if p_bottle_unit_id is null then
    -- -----------------------------------------------------------------------
    -- Via da zero: il wizard descrive una bottiglia che non esiste ancora.
    -- Identica alla 6b.
    -- -----------------------------------------------------------------------
    if coalesce(trim(p_produttore), '') = '' then
      raise exception 'Il produttore è obbligatorio.' using errcode = 'P0001';
    end if;
    if coalesce(trim(p_nome), '') = '' then
      raise exception 'Il nome del vino è obbligatorio.' using errcode = 'P0001';
    end if;
    if coalesce(trim(p_regione), '') = '' then
      raise exception 'La regione è obbligatoria.' using errcode = 'P0001';
    end if;
    if p_annata is null or p_annata < 1800 or p_annata > 2100 then
      raise exception 'L''annata deve essere compresa fra 1800 e 2100.' using errcode = 'P0001';
    end if;
    if p_tipo is null or p_tipo not in ('Rosso', 'Bianco', 'Bollicine', 'Rosato', 'Dolce') then
      raise exception 'Tipologia non valida.' using errcode = 'P0001';
    end if;

    v_etichetta := trim(p_produttore) || ' ' || trim(p_nome) || ' ' || p_annata::text;

    -- Catalogo: si riusa la riga esistente se produttore + nome + annata
    -- coincidono, altrimenti se ne crea una. `on conflict do nothing` seguito
    -- da una select copre la corsa fra due venditori che catalogano lo stesso
    -- vino nello stesso istante.
    select w.id into v_wine
    from public.wines w
    where w.produttore = trim(p_produttore)
      and w.nome = trim(p_nome)
      and w.annata = p_annata::smallint;

    if v_wine is null then
      v_base := public.slugifica(v_etichetta);
      v_slug := v_base;
      v_n := 1;
      while exists (select 1 from public.wines w where w.slug = v_slug) loop
        v_n := v_n + 1;
        v_slug := v_base || '-' || v_n;
      end loop;

      insert into public.wines (slug, produttore, nome, annata, regione, tipo)
      values (v_slug, trim(p_produttore), trim(p_nome), p_annata::smallint,
              trim(p_regione), p_tipo)
      on conflict (produttore, nome, annata) do nothing
      returning wines.id into v_wine;

      if v_wine is null then
        select w.id into v_wine
        from public.wines w
        where w.produttore = trim(p_produttore)
          and w.nome = trim(p_nome)
          and w.annata = p_annata::smallint;
      end if;
    end if;

    -- Unità fisica. Inserimento minimo: proprietario, vino, stato, visibilità.
    insert into public.bottle_units (owner_id, wine_id, stato, visibilita)
    values (v_uid, v_wine, 'chiusa', 'privata')
    returning bottle_units.id into v_bottle;

  else
    -- -----------------------------------------------------------------------
    -- Via dalla Cantina: la bottiglia esiste già e non se ne conia una nuova.
    -- -----------------------------------------------------------------------
    -- La proprietà si verifica qui e non si delega alla policy
    -- `listings_insert_own`: questa funzione è SECURITY DEFINER, quindi la RLS
    -- su bottle_units non la limita. Senza questo controllo basterebbe
    -- indovinare l'id dell'unità di un altro per metterla in vendita.
    select bu.id, bu.wine_id into v_bottle, v_wine
    from public.bottle_units bu
    where bu.id = p_bottle_unit_id
      and bu.owner_id = v_uid
      and bu.deleted_at is null;

    if v_bottle is null then
      raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
    end if;

    select w.produttore || ' ' || w.nome || ' ' || w.annata::text
    into v_etichetta
    from public.wines w
    where w.id = v_wine;

    -- Nessun controllo sugli annunci già esistenti per questa unità: una bozza
    -- in più non fa danno, e il vincolo "una bottiglia, un solo annuncio
    -- attivo" è un indice parziale sugli stati vivi. Chi lo tocca è
    -- listing_pubblica, che lo traduce in una frase leggibile.
  end if;

  -- -------------------------------------------------------------------------
  -- Annuncio in bozza. Da qui in poi le due vie coincidono.
  -- -------------------------------------------------------------------------
  -- Slug dell'annuncio. Parte dalla stessa base del vino, così il primo
  -- annuncio di un vino ha l'URL leggibile che ci si aspetta
  -- (/annuncio/tignanello-2019) e i successivi si numerano.
  v_base := public.slugifica(v_etichetta);
  v_slug := v_base;
  v_n := 1;
  while exists (select 1 from public.listings l where l.slug = v_slug) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n;
  end loop;

  -- Fra il controllo di disponibilità dello slug e questo INSERT c'è una
  -- finestra in cui un'altra sessione può prendersi lo stesso slug. È
  -- improbabile e senza conseguenze sui dati (l'unicità regge), ma senza
  -- questo blocco l'utente riceverebbe un 23505 grezzo per un problema che si
  -- risolve riprovando.
  begin
    return query
    insert into public.listings (
      slug, seller_id, bottle_unit_id, stato,
      prezzo_cents, condizione, conservazione, storia, immagini
    )
    values (
      v_slug, v_uid, v_bottle, 'bozza',
      p_prezzo_cents, p_condizione, coalesce(p_conservazione, ''), coalesce(p_storia, ''),
      coalesce(p_immagini, '{}'::text[])
    )
    returning listings.id, listings.slug;
  exception
    when unique_violation then
      raise exception 'Non è stato possibile assegnare un indirizzo univoco all''annuncio. Riprova.'
        using errcode = 'P0001';
  end;
end;
$$;

comment on function public.listing_crea(
  text, text, integer, text, text, integer, text, text, text, text[], uuid
) is
  'Crea un annuncio in stato bozza. Senza p_bottle_unit_id conia anche vino '
  '(se manca) e unità fisica, come in Fase 6b. Con p_bottle_unit_id riusa '
  'un''unità già in cantina, dopo averne verificato la proprietà. Venditore e '
  'proprietario sono sempre auth.uid(), mai un parametro. Non pubblica: la '
  'pubblicazione è listing_pubblica().';

revoke execute on function public.listing_crea(
  text, text, integer, text, text, integer, text, text, text, text[], uuid
) from public;
grant execute on function public.listing_crea(
  text, text, integer, text, text, integer, text, text, text, text[], uuid
) to authenticated;
$vinea_ledger_20260729210000$
   ]
 where version = '20260729210000'
   and coalesce(array_length(statements, 1), 0) = 0;

-- ---------------------------------------------------------------------------
-- [7] 20260729230000 security_invariants
--     file   supabase/migrations/20260729230000_security_invariants.sql
--     byte   47896
--     sha256 45c8dfa9ae6ef5a0faf83b88dc7bf5b08ce86bdf22ba5c53ecdfe927692790bc
-- ---------------------------------------------------------------------------

update supabase_migrations.schema_migrations
   set statements = array[
$vinea_ledger_20260729230000$-- ===========================================================================
-- Fase 6d-1 — Confini di autorizzazione e invarianti bottiglia–annuncio.
--
-- Non è una migrazione di dati: le fonti restano quelle di 6a/6b/6c. Qui
-- cambiano policy, privilegi e percorsi di scrittura, e alcuni flussi cambiano
-- di proposito.
--
-- LA REGOLA CHE QUESTA MIGRAZIONE APPLICA OVUNQUE, e che vale da qui in poi:
-- nessun privilegio di lettura su tabella intera verso un ruolo che può
-- raggiungere righe non proprie. Ciò che è pubblico si espone da una vista
-- `security_invoker = off` a elenco chiuso di colonne; ciò che ha una regola
-- dietro passa da una funzione SECURITY DEFINER e non da un UPDATE del browser.
-- È lo stesso pattern con cui la 6a ha tolto `listings.stato` dai GRANT di
-- colonna, esteso alle colonne che nel frattempo sono diventate sensibili.
--
-- ORDINE DI LETTURA E DI ESECUZIONE. Prima si crea tutto ciò che dovrà servire
-- (colonna, funzioni, trigger, indice, viste), poi si concede, e soltanto alla
-- fine si revoca e si sostituiscono le policy. L'ordine inverso lascerebbe, fra
-- una statement e l'altra, una finestra in cui /esplora e /cantina non hanno da
-- dove leggere.
--
-- ATOMICITÀ. Il file non contiene BEGIN/COMMIT espliciti, ed è deliberato:
-- `supabase db push` avvolge già ogni migrazione in una transazione propria, e
-- un COMMIT qui dentro la chiuderebbe prima che la CLI registri la migrazione
-- come applicata. Incollato nel SQL Editor, l'intero contenuto viaggia come un
-- unico messaggio di simple query, che PostgreSQL avvolge in una transazione
-- implicita: se una statement fallisce, tutte tornano indietro. In entrambe le
-- vie l'applicazione è tutto-o-niente.
--
-- RI-ESEGUIBILITÀ. Ogni statement è idempotente — `if not exists` su colonna e
-- indici, `drop … if exists` prima di trigger e policy, `create or replace` su
-- funzioni e viste. Serve perché la garanzia di cui sopra riguarda il database,
-- non l'operatore: un'applicazione interrotta a metà, o rilanciata per scrupolo,
-- non deve lasciare il file bloccato su un «relation already exists» che
-- costringa a modificarlo a mano.
--
-- COSA RESTA FUORI, E PERCHÉ:
--   * Il trasferimento di proprietà della bottiglia al compratore. Non esiste
--     in frontend/ e sarebbe funzionalità nuova. `ceduta_at` nasce qui pronta
--     ad accoglierlo, ma nessuno la legge come "cambio di proprietario".
--   * La funzione che porta un annuncio a 'venduto': è Fase 7. Al suo posto un
--     trigger, che intercetta la transizione da qualunque origine arrivi.
--   * Stripe Connect e KYC. L'abilitazione venditore e l'onboarding del conto
--     di pagamento saranno richiesti prima di qualunque payout reale: qui non
--     c'è nulla che li sostituisca, e il controllo dell'età non è una verifica
--     d'identità.
--   * Lo scheduler che materializza le scadenze. Qui la scadenza si applica in
--     lettura (la proiezione pubblica la esclude); la spazzata periodica resta
--     lavoro schedulato, registrato nel backlog.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- [0] Precondizione del punto G — fallire rumorosamente, non con un 23505
-- ---------------------------------------------------------------------------
-- L'indice unico più sotto estende il vincolo dai due stati vivi a tutti e
-- cinque quelli non terminali. Un indice si crea dopo che i dati esistono, e
-- `listing_crea` fino a oggi ammette esplicitamente più bozze sulla stessa
-- bottiglia: se ce ne sono, la CREATE INDEX fallisce con un 23505 che nomina un
-- indice e non dice cosa fare. Questo blocco lo anticipa con un messaggio che
-- rimanda alla query di bonifica.

do $$
declare
  v_violazioni integer;
begin
  select count(*) into v_violazioni
  from (
    select l.bottle_unit_id
    from public.listings l
    where l.stato in ('bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato')
    group by l.bottle_unit_id
    having count(*) > 1
  ) as duplicati;

  if v_violazioni > 0 then
    raise exception
      'Fase 6d-1: % bottiglie hanno più di un annuncio non terminale. Esegui supabase/tests/6d-1_preflight.sql (rilevamento, bonifica, riverifica) prima di applicare questa migrazione.',
      v_violazioni
      using errcode = 'P0001';
  end if;
end;
$$;


-- ---------------------------------------------------------------------------
-- [1] bottle_units.ceduta_at — il marcatore di uscita dal possesso
-- ---------------------------------------------------------------------------
-- IL BUCO CHE CHIUDE. L'indice parziale della 6a copre ('attivo', 'riservato'):
-- quando un annuncio passa a 'venduto' esce dall'indice, la bottiglia torna
-- libera e il venditore può ripubblicare una bottiglia che ha già venduto.
-- Quel comportamento era voluto per un annuncio scaduto o ritirato — la
-- bottiglia è ancora sua, può rimetterla in vendita — ma non per una vendita
-- conclusa, dove la bottiglia non è più sua.
--
-- Serviva quindi distinguere "l'annuncio è finito" da "la bottiglia se n'è
-- andata", e sono due fatti diversi che vivono su due tabelle diverse.
--
-- COSA NON È. Non è un cambio di proprietario: `owner_id` non si muove, e il
-- compratore non compare da nessuna parte. È una data che dice "questa unità è
-- uscita dal possesso di chi la possedeva", ed è tutto ciò che serve per
-- impedire che venga rivenduta. Il trasferimento vero è debito dichiarato.

alter table public.bottle_units
  add column if not exists ceduta_at timestamptz;

comment on column public.bottle_units.ceduta_at is
  'Data in cui l''unità è uscita dal possesso del proprietario, valorizzata dal '
  'trigger listings_marca_bottiglia_ceduta quando un annuncio entra in '
  '''venduto''. NON è un trasferimento di proprietà: owner_id non cambia e il '
  'compratore non è registrato da nessuna parte — quello è lavoro della Fase 7. '
  'Serve a impedire che una bottiglia già venduta torni in vendita.';

-- L'indice serve al trigger di idoneità e alle letture della cantina, che
-- filtrano sempre insieme "non cancellata" e "non ceduta".
create index if not exists bottle_units_in_possesso_idx
  on public.bottle_units (owner_id)
  where deleted_at is null and ceduta_at is null;


-- ---------------------------------------------------------------------------
-- [2] utente_maggiorenne — il controllo età come confine server-side
-- ---------------------------------------------------------------------------
-- IL CONTROLLO CLIENT NON È UN CONFINE. `AgeGate.tsx` rimanda a
-- /completa-profilo chi ha una sessione e `dob` vuoto, ma è un componente React:
-- ogni funzione di questo schema è raggiungibile con una POST diretta a
-- PostgREST, senza passare da nessuna interfaccia.
--
-- Il buco è reale e ha una data di nascita precisa: la 5b ha tolto il NOT NULL
-- da profiles.dob perché Google e Facebook non forniscono la data e il trigger
-- handle_new_user() falliva al primo accesso social. Da allora un profilo OAuth
-- senza età dichiarata esiste legittimamente — e `listing_crea` controlla che il
-- profilo esista, non che dichiari un'età.
--
-- FAIL-CLOSED. Profilo assente, `dob` nullo, o data che non raggiunge i 18 anni:
-- tutti e tre restituiscono falso. Il CHECK su profiles.dob non basta da solo,
-- proprio perché in PostgreSQL un CHECK con valore NULL vale NULL e passa.
--
-- RESTA UNA DICHIARAZIONE AUTO-RIFERITA, non una verifica documentale. Non
-- sostituisce l'abilitazione venditore né l'onboarding del conto di pagamento,
-- che andranno richiesti prima di qualunque payout reale.

create or replace function public.utente_maggiorenne(p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = p_user_id
      and p.dob is not null
      and p.dob <= (current_date - interval '18 years')
  );
$$;

comment on function public.utente_maggiorenne(uuid) is
  'Vero solo se esiste un profilo con data di nascita dichiarata e almeno 18 '
  'anni compiuti. Fail-closed: profilo mancante o dob nullo restituiscono '
  'falso. Dichiarazione auto-riferita, non verifica d''identità.';

-- Nessun ruolo client la esegue: la usano solo le funzioni di vendita, che sono
-- SECURITY DEFINER e girano con i privilegi del proprietario. Esporla darebbe a
-- chiunque un modo di sapere se un dato utente è maggiorenne.
revoke execute on function public.utente_maggiorenne(uuid) from public;


-- ---------------------------------------------------------------------------
-- [3] Il trigger che valorizza ceduta_at
-- ---------------------------------------------------------------------------
-- PERCHÉ UN TRIGGER E NON LA FUNZIONE DI TRANSIZIONE. La funzione che porta un
-- annuncio a 'venduto' non esiste: le transizioni di vendita ('riservato',
-- 'venduto') sono Fase 7, e scriverle qui significherebbe iniziare quella fase.
-- Un trigger ottiene lo stesso invariante senza costruirla, e lo ottiene meglio:
-- intercetta la transizione da qualunque origine arrivi — oggi un UPDATE da
-- service_role nel SQL Editor, domani la RPC di Fase 7 — invece di dipendere dal
-- fatto che ogni scrittore futuro si ricordi di aggiornare anche l'unità.
--
-- NOTA PER LA FASE 7: questo trigger esiste. La RPC che chiuderà una vendita non
-- deve valorizzare `ceduta_at` per conto suo, o si sovrascriverebbero a vicenda.
--
-- `coalesce(ceduta_at, now())` rende l'operazione idempotente: una seconda
-- scrittura sullo stesso annuncio non sposta la data della prima cessione.

create or replace function public.listings_marca_bottiglia_ceduta()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.stato = 'venduto'
     and (tg_op = 'INSERT' or old.stato is distinct from 'venduto') then
    update public.bottle_units
    set ceduta_at = coalesce(ceduta_at, now())
    where id = new.bottle_unit_id;
  end if;
  return null;
end;
$$;

comment on function public.listings_marca_bottiglia_ceduta() is
  'Valorizza bottle_units.ceduta_at quando un annuncio entra in ''venduto'', da '
  'qualunque origine arrivi l''UPDATE. La Fase 7 deve conoscerne l''esistenza e '
  'non duplicarne l''effetto.';

drop trigger if exists listings_marca_bottiglia_ceduta on public.listings;

create trigger listings_marca_bottiglia_ceduta
  after insert or update of stato on public.listings
  for each row
  execute function public.listings_marca_bottiglia_ceduta();


-- ---------------------------------------------------------------------------
-- [4] Il trigger di idoneità della bottiglia
-- ---------------------------------------------------------------------------
-- PERCHÉ NON UN INDICE. Il vincolo da applicare attraversa due tabelle: lo stato
-- della riga sta in `listings`, l'idoneità della bottiglia in `bottle_units`. Un
-- indice unico vive su una tabella sola e non può leggere l'altra; un CHECK
-- nemmeno, perché non può interrogare una seconda tabella. Resta il trigger.
--
-- È PIÙ FORTE DELLE RPC, non una loro ripetizione. Le funzioni SECURITY DEFINER
-- più sotto controllano le stesse cose, ma servono a produrre un messaggio
-- leggibile prima che l'utente sbatta contro il database. Questo trigger vale
-- anche per chi le RPC non le usa — un UPDATE da service_role, una futura
-- funzione di Fase 7 scritta distrattamente — ed è quindi il posto dove
-- l'invariante è davvero garantito.
--
-- QUANDO NON CONTROLLA. Un annuncio già in regola resta in regola: se né lo
-- stato né la bottiglia cambiano, non c'è niente di nuovo da verificare.
-- Ricontrollare a ogni modifica di prezzo o fotografia renderebbe immodificabile
-- una bozza legittima nel momento in cui il proprietario apre un'altra bottiglia
-- — e, peggio, renderebbe immodificabili le righe storiche già esistenti.

create or replace function public.listings_bottiglia_idonea()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stato   public.bottle_unit_stato;
  v_deleted timestamptz;
  v_ceduta  timestamptz;
begin
  -- Gli stati terminali sono storico: un annuncio venduto, scaduto, sospeso o
  -- rifiutato resta accanto a una bottiglia in qualunque condizione.
  if new.stato not in ('bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato') then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and new.stato = old.stato
     and new.bottle_unit_id = old.bottle_unit_id then
    return new;
  end if;

  select bu.stato, bu.deleted_at, bu.ceduta_at
  into v_stato, v_deleted, v_ceduta
  from public.bottle_units bu
  where bu.id = new.bottle_unit_id;

  if v_stato is null then
    raise exception 'Questa bottiglia non esiste.' using errcode = 'P0001';
  end if;
  if v_deleted is not null then
    raise exception 'Questa bottiglia non è più nella tua cantina.' using errcode = 'P0001';
  end if;
  if v_ceduta is not null then
    raise exception 'Questa bottiglia è già stata venduta: non può tornare in vendita.'
      using errcode = 'P0001';
  end if;
  if v_stato <> 'chiusa' then
    raise exception 'Una bottiglia % non si può mettere in vendita.', v_stato
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

comment on function public.listings_bottiglia_idonea() is
  'Rifiuta ogni annuncio in stato non terminale la cui bottiglia sia aperta, '
  'consumata, cancellata o già ceduta. Vale anche per service_role: è qui che '
  'l''invariante è garantito, le RPC servono al messaggio leggibile.';

drop trigger if exists listings_bottiglia_idonea on public.listings;

create trigger listings_bottiglia_idonea
  before insert or update on public.listings
  for each row
  execute function public.listings_bottiglia_idonea();


-- ---------------------------------------------------------------------------
-- [5] Un annuncio, una bottiglia, un solo annuncio non terminale
-- ---------------------------------------------------------------------------
-- La regola adottata per intero: un annuncio vende una sola bottiglia fisica, e
-- una bottiglia può avere un solo annuncio non terminale.
--
-- L'indice della 6a copriva solo ('attivo', 'riservato'), cioè scattava alla
-- pubblicazione. Restavano possibili due, cinque, venti bozze sulla stessa
-- bottiglia — e `listing_crea` lo diceva esplicitamente ("una bozza in più non
-- fa danno"). Fa danno: il venditore compila due schede della stessa bottiglia,
-- ne pubblica una, e la seconda resta lì a promettere una bottiglia che non c'è
-- più, finché non ci sbatte contro al momento di pubblicarla.
--
-- I quattro stati terminali (sospeso, scaduto, venduto, rifiutato) restano fuori
-- dall'indice: sono storico, e devono poter coesistere in numero qualunque sulla
-- stessa unità.

drop index if exists public.listings_una_sola_attiva_per_bottiglia;

create unique index if not exists listings_un_solo_annuncio_non_terminale
  on public.listings (bottle_unit_id)
  where stato in ('bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato');

comment on index public.listings_un_solo_annuncio_non_terminale is
  'Un annuncio vende una sola bottiglia fisica e una bottiglia ha un solo '
  'annuncio non terminale. Sostituisce listings_una_sola_attiva_per_bottiglia '
  'della 6a, che copriva i soli stati vivi e lasciava passare più bozze.';


-- ---------------------------------------------------------------------------
-- [6] bottiglia_apri — lo stato fisico passa da qui, non da un UPDATE
-- ---------------------------------------------------------------------------
-- La 6a concedeva `update (stato, visibilita, deleted_at)` al client, e
-- `cellar-service.apri()` scriveva `stato = 'aperta'` direttamente. Con
-- l'invariante "non si apre una bottiglia in vendita" quella colonna smette di
-- essere una preferenza personale e diventa una transizione con una regola
-- dietro: stesso trattamento che la 6a ha riservato a `listings.stato`.
--
-- IL LOCK SERVE DAVVERO. Senza, due sessioni possono incrociarsi: una legge
-- "nessun annuncio attivo" mentre l'altra sta pubblicando, e si finisce con una
-- bottiglia aperta in vendita. `listing_pubblica` e `listing_crea` prendono lo
-- stesso lock sulla stessa riga di `bottle_units`, quindi si mettono in coda.

create or replace function public.bottiglia_apri(
  p_bottle_unit_id uuid,
  p_nota text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_owner   uuid;
  v_stato   public.bottle_unit_stato;
  v_deleted timestamptz;
begin
  if v_uid is null then
    raise exception 'Devi accedere per aprire una bottiglia.' using errcode = '42501';
  end if;

  select bu.owner_id, bu.stato, bu.deleted_at
  into v_owner, v_stato, v_deleted
  from public.bottle_units bu
  where bu.id = p_bottle_unit_id
  for update;

  if v_owner is null or v_owner is distinct from v_uid or v_deleted is not null then
    raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
  end if;

  if v_stato = 'aperta' then
    raise exception 'Questa bottiglia è già aperta.' using errcode = 'P0001';
  end if;
  if v_stato = 'consumata' then
    raise exception 'Questa bottiglia è già stata consumata.' using errcode = 'P0001';
  end if;

  -- Il messaggio dice cosa fare, non che cosa è andato storto: chi apre una
  -- bottiglia in vendita non ha sbagliato nulla, ha solo due cose in ordine
  -- sbagliato.
  if exists (
    select 1
    from public.listings l
    where l.bottle_unit_id = p_bottle_unit_id
      and l.stato in ('attivo', 'riservato')
  ) then
    raise exception 'Questa bottiglia è in vendita: sospendi il suo annuncio prima di aprirla.'
      using errcode = 'P0001';
  end if;

  -- PERCHÉ LA NOTA SOSTITUISCE INVECE DI AGGIUNGERSI, e perché non si corregge
  -- qui. Il dialogo che chiama questa funzione ha un campo etichettato «Nota di
  -- degustazione (facoltativa)» che scrive dentro `note_personali`: due cose
  -- diverse nello stesso posto. In frontend/ (cellar-domain.ts, `personalNotes:
  -- nota ?? bottle.personalNotes`) la nota di degustazione sovrascrive la nota
  -- personale, e siccome il dialogo passa sempre una stringa — vuota se non si
  -- scrive niente — aprire una bottiglia senza digitare nulla CANCELLA la nota
  -- personale che c'era.
  --
  -- Il `case` qui sotto è la stessa protezione che la 6c-2 aveva già messo nel
  -- servizio (`if (nota !== undefined && nota !== "")`): una nota vuota non
  -- tocca niente. È l'unico punto in cui frontend-next diverge da frontend/, ed
  -- è una divergenza a favore dei dati.
  --
  -- Far diventare la nota additiva sarebbe invece un cambiamento di
  -- comportamento visibile in entrambi gli stack, cioè un cambiamento di
  -- prodotto dentro una fase di sicurezza. La confusione fra le due note è
  -- registrata come debito dichiarato, insieme a formatEUR.
  update public.bottle_units
  set stato = 'aperta',
      note_personali = case
        when p_nota is null or trim(p_nota) = '' then note_personali
        else p_nota
      end
  where id = p_bottle_unit_id;
end;
$$;

comment on function public.bottiglia_apri(uuid, text) is
  'Porta una bottiglia da chiusa ad aperta, con lock di riga. Rifiuta se '
  'l''unità ha un annuncio attivo o riservato. Sostituisce l''UPDATE diretto su '
  'bottle_units.stato, che dalla 6d-1 non è più concesso al client.';

revoke execute on function public.bottiglia_apri(uuid, text) from public;
grant execute on function public.bottiglia_apri(uuid, text) to authenticated;


-- ---------------------------------------------------------------------------
-- [7] bottiglia_cancella — la rimozione logica, con lo stesso invariante
-- ---------------------------------------------------------------------------
-- Nessuna interfaccia la chiama oggi: in frontend/ non esiste un comando per
-- togliere una bottiglia dalla cantina, e questa fase non lo aggiunge. Esiste
-- perché `deleted_at` esce dai GRANT di colonna insieme a `stato`, e una colonna
-- che nessuno può più scrivere avrebbe bisogno comunque di una porta il giorno
-- in cui quel comando arriverà — con l'invariante già dentro, invece che da
-- aggiungere allora.
--
-- LA POSIZIONE SI LIBERA. Una bottiglia tolta dalla cantina non può continuare a
-- occupare un foro dello scaffale: `cellar_slots` ha un unico su (module_id,
-- riga, colonna), quindi la riga rimasta bloccherebbe quella posizione per
-- sempre, invisibile perché la cantina legge solo le unità non cancellate.

create or replace function public.bottiglia_cancella(p_bottle_unit_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_owner   uuid;
  v_deleted timestamptz;
begin
  if v_uid is null then
    raise exception 'Devi accedere per togliere una bottiglia dalla cantina.'
      using errcode = '42501';
  end if;

  select bu.owner_id, bu.deleted_at
  into v_owner, v_deleted
  from public.bottle_units bu
  where bu.id = p_bottle_unit_id
  for update;

  if v_owner is null or v_owner is distinct from v_uid then
    raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
  end if;
  if v_deleted is not null then
    raise exception 'Questa bottiglia è già stata tolta dalla cantina.' using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.listings l
    where l.bottle_unit_id = p_bottle_unit_id
      and l.stato in ('attivo', 'riservato')
  ) then
    raise exception 'Questa bottiglia è in vendita: sospendi il suo annuncio prima di toglierla dalla cantina.'
      using errcode = 'P0001';
  end if;

  delete from public.cellar_slots where bottle_unit_id = p_bottle_unit_id;

  update public.bottle_units
  set deleted_at = now()
  where id = p_bottle_unit_id;
end;
$$;

comment on function public.bottiglia_cancella(uuid) is
  'Rimozione logica di un''unità, con lock di riga e liberazione della posizione '
  'in cellar_slots. Rifiuta se l''unità ha un annuncio attivo o riservato. '
  'Nessuna interfaccia la chiama: esiste perché deleted_at esce dai GRANT.';

revoke execute on function public.bottiglia_cancella(uuid) from public;
grant execute on function public.bottiglia_cancella(uuid) to authenticated;


-- ---------------------------------------------------------------------------
-- [8] listing_crea — cancello età, idoneità della bottiglia, lock
-- ---------------------------------------------------------------------------
-- Firma invariata rispetto alla 6c-2, quindi `create or replace` basta e non
-- serve il DROP: nessun parametro si aggiunge, nessuna seconda firma nasce, e
-- PostgREST continua a risolvere la RPC come prima.
--
-- Tre cose cambiano nel corpo:
--   1. il controllo dell'età, subito dopo quello del profilo;
--   2. nella via che parte dalla cantina, il lock di riga sull'unità e il
--      rifiuto esplicito di una bottiglia aperta, consumata, cancellata o già
--      ceduta;
--   3. il messaggio leggibile quando la bottiglia ha già un annuncio non
--      terminale — prima quel caso era ammesso e produceva una seconda bozza.

create or replace function public.listing_crea(
  p_produttore text default '',
  p_nome text default '',
  p_annata integer default null,
  p_regione text default '',
  p_tipo text default null,
  p_prezzo_cents integer default null,
  p_condizione text default 'Ottimo',
  p_conservazione text default '',
  p_storia text default '',
  p_immagini text[] default '{}',
  p_bottle_unit_id uuid default null
)
returns table (annuncio_id uuid, annuncio_slug text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_wine       uuid;
  v_bottle     uuid;
  v_base       text;
  v_slug       text;
  v_n          integer;
  v_immagine   text;
  v_etichetta  text;
  v_stato      public.bottle_unit_stato;
  v_deleted    timestamptz;
  v_ceduta     timestamptz;
begin
  if v_uid is null then
    raise exception 'Devi accedere per creare un annuncio.' using errcode = '42501';
  end if;

  if not exists (select 1 from public.profiles p where p.id = v_uid) then
    raise exception 'Il tuo profilo non è ancora completo: completalo prima di pubblicare.'
      using errcode = 'P0001';
  end if;

  -- Il cancello età. Separato dal controllo del profilo perché i due casi si
  -- risolvono in modi diversi: uno manca del tutto, l'altro ha solo un campo da
  -- riempire in /completa-profilo. La navigazione pubblica non passa di qui e
  -- resta disponibile senza data di nascita.
  if not public.utente_maggiorenne(v_uid) then
    raise exception 'Per mettere in vendita devi dichiarare la tua data di nascita ed essere maggiorenne.'
      using errcode = 'P0001';
  end if;

  if p_condizione is null or p_condizione not in ('Perfetto', 'Ottimo', 'Buono') then
    raise exception 'Condizione non valida.' using errcode = 'P0001';
  end if;
  if p_prezzo_cents is null or p_prezzo_cents <= 0 then
    raise exception 'Il prezzo deve essere maggiore di zero.' using errcode = 'P0001';
  end if;
  if array_length(p_immagini, 1) > 6 then
    raise exception 'Massimo 6 fotografie per annuncio.' using errcode = 'P0001';
  end if;

  foreach v_immagine in array coalesce(p_immagini, '{}'::text[]) loop
    if v_immagine !~ ('^' || v_uid::text || '/[0-9a-f-]{36}\.(jpg|jpeg|png|webp|avif)$') then
      raise exception 'Fotografia non valida: %', v_immagine using errcode = 'P0001';
    end if;
  end loop;

  if p_bottle_unit_id is null then
    -- -----------------------------------------------------------------------
    -- Via da zero: il wizard descrive una bottiglia che non esiste ancora.
    -- L'unità nasce qui, 'chiusa' e mai ceduta: nessun controllo di idoneità da
    -- fare, perché non c'è ancora niente che possa essere andato storto.
    -- -----------------------------------------------------------------------
    if coalesce(trim(p_produttore), '') = '' then
      raise exception 'Il produttore è obbligatorio.' using errcode = 'P0001';
    end if;
    if coalesce(trim(p_nome), '') = '' then
      raise exception 'Il nome del vino è obbligatorio.' using errcode = 'P0001';
    end if;
    if coalesce(trim(p_regione), '') = '' then
      raise exception 'La regione è obbligatoria.' using errcode = 'P0001';
    end if;
    if p_annata is null or p_annata < 1800 or p_annata > 2100 then
      raise exception 'L''annata deve essere compresa fra 1800 e 2100.' using errcode = 'P0001';
    end if;
    if p_tipo is null or p_tipo not in ('Rosso', 'Bianco', 'Bollicine', 'Rosato', 'Dolce') then
      raise exception 'Tipologia non valida.' using errcode = 'P0001';
    end if;

    v_etichetta := trim(p_produttore) || ' ' || trim(p_nome) || ' ' || p_annata::text;

    select w.id into v_wine
    from public.wines w
    where w.produttore = trim(p_produttore)
      and w.nome = trim(p_nome)
      and w.annata = p_annata::smallint;

    if v_wine is null then
      v_base := public.slugifica(v_etichetta);
      v_slug := v_base;
      v_n := 1;
      while exists (select 1 from public.wines w where w.slug = v_slug) loop
        v_n := v_n + 1;
        v_slug := v_base || '-' || v_n;
      end loop;

      insert into public.wines (slug, produttore, nome, annata, regione, tipo)
      values (v_slug, trim(p_produttore), trim(p_nome), p_annata::smallint,
              trim(p_regione), p_tipo)
      on conflict (produttore, nome, annata) do nothing
      returning wines.id into v_wine;

      if v_wine is null then
        select w.id into v_wine
        from public.wines w
        where w.produttore = trim(p_produttore)
          and w.nome = trim(p_nome)
          and w.annata = p_annata::smallint;
      end if;
    end if;

    insert into public.bottle_units (owner_id, wine_id, stato, visibilita)
    values (v_uid, v_wine, 'chiusa', 'privata')
    returning bottle_units.id into v_bottle;

  else
    -- -----------------------------------------------------------------------
    -- Via dalla Cantina: la bottiglia esiste già.
    -- -----------------------------------------------------------------------
    -- Il lock si prende qui, prima di qualunque verifica, e regge fino alla fine
    -- della transazione: è ciò che impedisce a un'apertura concorrente di
    -- infilarsi fra il controllo e l'inserimento dell'annuncio.
    select bu.id, bu.wine_id, bu.stato, bu.deleted_at, bu.ceduta_at
    into v_bottle, v_wine, v_stato, v_deleted, v_ceduta
    from public.bottle_units bu
    where bu.id = p_bottle_unit_id
      and bu.owner_id = v_uid
    for update;

    if v_bottle is null or v_deleted is not null then
      raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
    end if;
    if v_ceduta is not null then
      raise exception 'Questa bottiglia è già stata venduta: non può tornare in vendita.'
        using errcode = 'P0001';
    end if;
    if v_stato <> 'chiusa' then
      raise exception 'Una bottiglia % non si può mettere in vendita.', v_stato
        using errcode = 'P0001';
    end if;

    -- La regola nuova della 6d-1. Prima di qui una seconda bozza era ammessa di
    -- proposito; adesso l'indice la rifiuta, e senza questo controllo il
    -- messaggio sarebbe il 23505 col nome dell'indice dentro.
    if exists (
      select 1
      from public.listings l
      where l.bottle_unit_id = v_bottle
        and l.stato in ('bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato')
    ) then
      raise exception 'Questa bottiglia ha già un annuncio in corso: concludilo o ritiralo prima di crearne un altro.'
        using errcode = 'P0001';
    end if;

    select w.produttore || ' ' || w.nome || ' ' || w.annata::text
    into v_etichetta
    from public.wines w
    where w.id = v_wine;
  end if;

  v_base := public.slugifica(v_etichetta);
  v_slug := v_base;
  v_n := 1;
  while exists (select 1 from public.listings l where l.slug = v_slug) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n;
  end loop;

  begin
    return query
    insert into public.listings (
      slug, seller_id, bottle_unit_id, stato,
      prezzo_cents, condizione, conservazione, storia, immagini
    )
    values (
      v_slug, v_uid, v_bottle, 'bozza',
      p_prezzo_cents, p_condizione, coalesce(p_conservazione, ''), coalesce(p_storia, ''),
      coalesce(p_immagini, '{}'::text[])
    )
    returning listings.id, listings.slug;
  exception
    -- Due violazioni diverse arrivano qui con lo stesso SQLSTATE: lo slug
    -- occupato da un'altra sessione fra il controllo e l'INSERT, e l'annuncio
    -- non terminale già esistente sulla bottiglia. Il secondo caso è già stato
    -- intercettato sopra con un messaggio suo; questo resta il ripiego.
    when unique_violation then
      raise exception 'Non è stato possibile creare l''annuncio. Riprova.'
        using errcode = 'P0001';
  end;
end;
$$;

comment on function public.listing_crea(
  text, text, integer, text, text, integer, text, text, text, text[], uuid
) is
  'Crea un annuncio in stato bozza. Senza p_bottle_unit_id conia anche vino (se '
  'manca) e unità fisica; con p_bottle_unit_id riusa un''unità già in cantina, '
  'dopo lock di riga e verifica di proprietà, stato fisico, cancellazione, '
  'cessione e assenza di altri annunci non terminali. Richiede un profilo con '
  'data di nascita dichiarata e maggiore età. Venditore e proprietario sono '
  'sempre auth.uid(). Non pubblica: la pubblicazione è listing_pubblica().';

revoke execute on function public.listing_crea(
  text, text, integer, text, text, integer, text, text, text, text[], uuid
) from public;
grant execute on function public.listing_crea(
  text, text, integer, text, text, integer, text, text, text, text[], uuid
) to authenticated;


-- ---------------------------------------------------------------------------
-- [9] listing_pubblica — la porta verso il pubblico
-- ---------------------------------------------------------------------------
-- È l'altra funzione che rende pubblica una vendita, quindi porta lo stesso
-- cancello età di listing_crea.
--
-- IL RICONTROLLO DELLA BOTTIGLIA NON È RIDONDANTE. Fra la creazione della bozza
-- e la pubblicazione passa tempo reale — il wizard ha più passi, la bozza si può
-- salvare e riprendere il giorno dopo — e in quel tempo la bottiglia può essere
-- stata aperta o tolta dalla cantina. Senza questo controllo si pubblicherebbe
-- un annuncio per una bottiglia che non c'è più.

create or replace function public.listing_pubblica(p_listing_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_seller   uuid;
  v_stato    public.listing_stato;
  v_bottle   uuid;
  v_bu_stato public.bottle_unit_stato;
  v_deleted  timestamptz;
  v_ceduta   timestamptz;
begin
  if v_uid is null then
    raise exception 'Devi accedere per pubblicare un annuncio.' using errcode = '42501';
  end if;

  select l.seller_id, l.stato, l.bottle_unit_id
  into v_seller, v_stato, v_bottle
  from public.listings l
  where l.id = p_listing_id;

  if v_seller is null then
    raise exception 'Annuncio non trovato.' using errcode = 'P0001';
  end if;
  if v_seller is distinct from v_uid then
    raise exception 'Non puoi pubblicare un annuncio che non è tuo.' using errcode = '42501';
  end if;
  if v_stato not in ('bozza', 'modifiche_richieste') then
    raise exception 'Si può pubblicare solo un annuncio in bozza o con modifiche richieste.'
      using errcode = 'P0001';
  end if;

  if not public.utente_maggiorenne(v_uid) then
    raise exception 'Per mettere in vendita devi dichiarare la tua data di nascita ed essere maggiorenne.'
      using errcode = 'P0001';
  end if;

  -- Stesso lock di bottiglia_apri e di listing_crea, sulla stessa riga: è così
  -- che le due transizioni si serializzano invece di incrociarsi.
  select bu.stato, bu.deleted_at, bu.ceduta_at
  into v_bu_stato, v_deleted, v_ceduta
  from public.bottle_units bu
  where bu.id = v_bottle
  for update;

  if v_bu_stato is null or v_deleted is not null then
    raise exception 'La bottiglia di questo annuncio non è più nella tua cantina.'
      using errcode = 'P0001';
  end if;
  if v_ceduta is not null then
    raise exception 'Questa bottiglia è già stata venduta: non può tornare in vendita.'
      using errcode = 'P0001';
  end if;
  if v_bu_stato <> 'chiusa' then
    raise exception 'Questa bottiglia è stata %: non si può più mettere in vendita.', v_bu_stato
      using errcode = 'P0001';
  end if;

  begin
    update public.listings
    set stato = 'attivo',
        published_at = now(),
        -- Sessanta giorni, come dalla 6b. Dalla 6d-1 la scadenza ha un effetto
        -- reale anche prima di essere materializzata: la proiezione pubblica
        -- esclude gli annunci oltre expires_at.
        expires_at = now() + interval '60 days',
        stato_motivo = null,
        stato_aggiornato_da = v_uid,
        stato_aggiornato_at = now()
    where id = p_listing_id;
  exception
    when unique_violation then
      raise exception
        'Questa bottiglia ha già un altro annuncio in corso. Ritira quello prima di pubblicare questo.'
        using errcode = 'P0001';
  end;
end;
$$;

comment on function public.listing_pubblica(uuid) is
  'Porta un annuncio del venditore da bozza (o modifiche_richieste) ad attivo, '
  'dopo cancello età e ricontrollo con lock della bottiglia, che fra la bozza e '
  'la pubblicazione può essere stata aperta o tolta dalla cantina. Traduce la '
  'violazione dell''indice non-terminale in un messaggio leggibile.';

revoke execute on function public.listing_pubblica(uuid) from public;
grant execute on function public.listing_pubblica(uuid) to authenticated;


-- ---------------------------------------------------------------------------
-- [10] public_listings — la scadenza vale in lettura
-- ---------------------------------------------------------------------------
-- Un annuncio con expires_at già passato non deve essere visibile né
-- acquistabile anche se lo stato materializzato è ancora 'attivo'. Fino alla 6c
-- la vista guardava soltanto lo stato, e senza scheduler quello stato resta
-- 'attivo' a tempo indeterminato: bastava non chiamare `listing_scadi` perché un
-- annuncio scaduto restasse in vetrina per sempre.
--
-- La colonna e le sue posizioni non cambiano, quindi `create or replace view`
-- basta e i privilegi già concessi restano.
--
-- LA PRENOTAZIONE DOVRÀ RICONTROLLARE. Questa è una difesa in lettura: dice
-- quali annunci si vedono, non impedisce a nessuno di agire su un id noto. La
-- futura RPC di prenotazione (Fase 7) dovrà verificare la scadenza per conto
-- suo, dentro la transazione che riserva.

create or replace view public.public_listings
with (security_invoker = off)
as
select
  l.id,
  l.slug,
  l.prezzo_cents,
  l.prezzo_mercato_cents,
  (
    select count(*)
    from public.listing_bottle_units lbu
    where lbu.listing_id = l.id
  )::integer as quantita,
  l.condizione,
  l.conservazione,
  l.storia,
  l.degustazione,
  l.immagini,
  l.tag,
  l.published_at,
  l.created_at,
  coalesce(l.published_at, l.created_at) as pubblicato_at,
  w.id            as wine_id,
  w.slug          as wine_slug,
  w.produttore,
  w.nome,
  w.annata,
  w.regione,
  w.denominazione,
  w.tipo,
  w.formato,
  w.produttore || ' ' || w.nome as ricerca,
  p.id            as seller_id,
  p.username      as seller_username,
  p.citta         as seller_citta,
  p.avatar_url    as seller_avatar_url
from public.listings l
  join public.bottle_units bu on bu.id = l.bottle_unit_id
  join public.wines w on w.id = bu.wine_id
  join public.profiles p on p.id = l.seller_id
where l.stato = 'attivo'
  and (l.expires_at is null or l.expires_at > now());

comment on view public.public_listings is
  'Annunci attivi e non scaduti, con vino e venditore già uniti, nella forma che '
  'serve a /esplora e a /annuncio/[slug]. Espone solo campi non sensibili del '
  'profilo venditore (mai dob, esperienza, bio, obiettivi). Dalla 6d-1 è anche '
  'l''unica via con cui un anonimo legge un annuncio: la tabella non è più '
  'raggiungibile.';


-- ---------------------------------------------------------------------------
-- [11] public_bottle_units — le unità pubbliche a colonne scelte
-- ---------------------------------------------------------------------------
-- Prende il posto delle due policy che rendevano leggibile la riga intera di
-- `bottle_units`: quella della 6a per le unità in annuncio attivo, e quella
-- della 6c-1 per le unità dichiarate `cantina_pubblica`.
--
-- COSA ESPONEVANO. Tutta la riga, quindi anche `note_personali`
-- ("regalo di mio padre"), `apertura_pianificata` (quando qualcuno sarà in casa
-- a festeggiare), gli `override_*` della finestra di bevuta e
-- `prezzo_visibilita`. Nulla di tutto ciò serviva a un marketplace: erano
-- leggibili perché il GRANT era di tabella e la RLS lavora per riga, non per
-- colonna.
--
-- COSA ESPONE QUESTA. Sei colonne, elencate una per una. Chi è il proprietario e
-- quale vino è, che sono i due fatti che rendono utile sapere che l'unità
-- esiste; lo stato fisico e la visibilità, che il proprietario ha scelto di
-- rendere pubblici nel momento in cui ha dichiarato la bottiglia; la data di
-- creazione. Ogni colonna aggiunta in futuro resta fuori finché qualcuno non la
-- scrive qui dentro: è il senso di un elenco chiuso.
--
-- NESSUN CONSUMATORE, OGGI. Nessuna interfaccia legge le bottiglie altrui —
-- `cantina_pubblica` compare solo come etichetta derivata dai dati del
-- proprietario. La vista conserva la capacità che le due policy davano, nella
-- forma sicura, invece di toglierla in silenzio.

create or replace view public.public_bottle_units
with (security_invoker = off)
as
select
  bu.id,
  bu.owner_id,
  bu.wine_id,
  bu.stato,
  bu.visibilita,
  bu.created_at
from public.bottle_units bu
where bu.deleted_at is null
  and bu.ceduta_at is null
  and (
    bu.visibilita = 'cantina_pubblica'
    or exists (
      select 1
      from public.listings l
      where l.bottle_unit_id = bu.id
        and l.stato = 'attivo'
        and (l.expires_at is null or l.expires_at > now())
    )
  );

comment on view public.public_bottle_units is
  'Unità fisiche visibili a terzi: quelle in un annuncio attivo e non scaduto, e '
  'quelle dichiarate cantina_pubblica dal proprietario. Elenco chiuso di sei '
  'colonne: mai note_personali, apertura_pianificata, override della finestra, '
  'prezzo_visibilita, né alcuna colonna futura non elencata qui.';

revoke all on public.public_bottle_units from anon, authenticated;
grant select on public.public_bottle_units to anon, authenticated;


-- ===========================================================================
-- Da qui in giù si toglie. Tutto ciò che serve a leggere esiste già sopra.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- [12] Privilegi — bottle_units
-- ---------------------------------------------------------------------------
-- `anon` perde ogni accesso alla tabella: quello che gli serve è nelle due
-- viste, che valutano con i privilegi del proprietario e non hanno bisogno che
-- il chiamante possa leggere le tabelle sottostanti.
revoke all on public.bottle_units from anon;

-- `authenticated` tiene il SELECT di tabella, e non è una dimenticanza:
-- rimosse le due policy pubbliche più sotto, un autenticato raggiunge soltanto
-- le proprie righe (bottle_units_select_own), quindi il grant di tabella non
-- espone nulla di altrui. Il proprietario deve continuare a leggere
-- integralmente le proprie unità — note, override e pianificazioni comprese.
-- L'asimmetria con `listings` dipende da quali righe il ruolo può raggiungere,
-- non da un gusto diverso sulle due tabelle.

-- Lo stato fisico e la cancellazione escono dalle colonne scrivibili: hanno
-- adesso una regola dietro, e le regole passano dalle RPC [6] e [7]. È lo stesso
-- trattamento che la 6a ha riservato a `listings.stato`, applicato alle due
-- colonne che nel frattempo hanno smesso di essere preferenze personali.
revoke insert (stato) on public.bottle_units from authenticated;
revoke update (stato, deleted_at) on public.bottle_units from authenticated;
-- `ceduta_at` non compare in nessun GRANT di colonna e non ce ne sarà uno: la
-- valorizza il trigger [3], che gira con i privilegi del proprietario.


-- ---------------------------------------------------------------------------
-- [13] Privilegi — listings
-- ---------------------------------------------------------------------------
revoke all on public.listings from anon;

-- Il SELECT di tabella se ne va e torna come elenco chiuso di colonne. Non è
-- una ripetizione della RLS: la policy decide quali righe, il privilegio di
-- colonna decide quali campi, e i due confini restano validi indipendentemente.
-- Se un domani una fase aggiungerà una policy che espone righe altrui — la
-- Fase 7 dovrà mostrare al compratore l'annuncio che sta riservando, la Fase 9
-- la coda di moderazione — le colonne qui sotto sono già il limite, e nessuno
-- dovrà ricordarsi di riscriverlo.
revoke select on public.listings from authenticated;

grant select (
  id, slug, seller_id, bottle_unit_id, stato,
  prezzo_cents, prezzo_mercato_cents,
  condizione, conservazione, storia, degustazione, immagini, tag,
  published_at, expires_at, created_at, updated_at
) on public.listings to authenticated;

-- COSA RESTA FUORI, E CHE COSA COSTA. `stato_motivo`, `stato_aggiornato_da` e
-- `stato_aggiornato_at` sono la traccia dell'ultima transizione: perché un
-- moderatore ha rifiutato o sospeso un annuncio, e chi è stato. Non sono
-- leggibili da nessun ruolo client, proprietario compreso.
--
-- Il privilegio di colonna non distingue le righe, quindi "il venditore legge i
-- propri annunci integralmente" e "quelle colonne non sono leggibili da chi non
-- è proprietario" non possono valere insieme dentro un GRANT. Si è scelta la
-- lettura difensiva. Oggi non costa nulla di visibile: la moderazione è Fase 9 e
-- non esiste, nessuna interfaccia mostra quelle colonne. Quando la Fase 9 dovrà
-- mostrare al venditore il motivo di un rifiuto lo farà con una proiezione
-- dedicata alle righe proprie, non riaprendo la tabella.
--
-- `bottle_unit_id` è nell'elenco perché PostgREST ne ha bisogno per risolvere
-- l'embed `bottle_units → listings` che la cantina usa per prezzo, foto e stato
-- di vendita; `id` perché è il filtro di ogni UPDATE di contenuto. I GRANT di
-- INSERT e UPDATE della 6a non si toccano: erano già scritti per non dover
-- cambiare.


-- ---------------------------------------------------------------------------
-- [14] Privilegi — user_roles e has_role
-- ---------------------------------------------------------------------------
-- La 6a/5a concedeva SELECT sull'intera tabella a `authenticated`, con una
-- policy `using (true)`: qualunque utente registrato poteva elencare i ruoli di
-- tutti gli altri, cioè sapere chi sono gli amministratori e i moderatori del
-- sito. È esattamente la mappa che serve a chi cerca un bersaglio.
revoke all on public.user_roles from anon, authenticated;
grant select (user_id, role) on public.user_roles to authenticated;
-- Nessun INSERT/UPDATE/DELETE, come dalla 5a: i ruoli li assegna solo
-- service_role. Nessuna autoassegnazione è possibile, nemmeno sui propri.

-- `has_role` era eseguibile da `anon`. Le policy che la usano
-- (`wines_write_staff`) sono `to authenticated`, quindi nessun anonimo ne ha
-- bisogno, e concederla dava a chiunque un oracolo per verificare se un dato
-- uuid è amministratore.
--
-- La revoca da PUBLIC è quella che conta: `create function` concede EXECUTE a
-- PUBLIC per impostazione predefinita, quindi togliere il grant esplicito ad
-- `anon` senza toccare PUBLIC non avrebbe cambiato nulla.
revoke execute on function public.has_role(uuid, text) from public, anon;
grant execute on function public.has_role(uuid, text) to authenticated;


-- ---------------------------------------------------------------------------
-- [15] Policy — ciò che era pubblico adesso passa dalle viste
-- ---------------------------------------------------------------------------

-- Le due policy che esponevano la riga intera di bottle_units. Sostituite da
-- public_bottle_units [11], che espone sei colonne invece di ventidue.
drop policy if exists "bottle_units_select_via_annuncio_pubblico" on public.bottle_units;
drop policy if exists "bottle_units_select_cantina_pubblica" on public.bottle_units;

-- La lettura pubblica diretta di listings. Sostituita da public_listings [10],
-- che era già l'unica via usata dall'interfaccia: `listing-service.ts` legge la
-- vista, non la tabella. La policy esisteva quindi senza consumatori, ed esponeva
-- expires_at, stato_motivo e stato_aggiornato_da a ogni visitatore anonimo.
drop policy if exists "listings_select_pubblici" on public.listings;
-- `listings_select_own` resta: il venditore continua a leggere i propri annunci,
-- ed è quella policy che tiene in piedi l'embed della cantina.

-- L'enumerazione dei ruoli altrui.
drop policy if exists "user_roles_select_authenticated" on public.user_roles;

drop policy if exists "user_roles_select_own" on public.user_roles;

create policy "user_roles_select_own"
  on public.user_roles for select
  to authenticated
  using (user_id = auth.uid());
$vinea_ledger_20260729230000$
   ]
 where version = '20260729230000'
   and coalesce(array_length(statements, 1), 0) = 0;

-- ---------------------------------------------------------------------------
-- [8] POST-CONTROLLO — sola lettura. Nessuna riga deve avere `caratteri = 0`.
-- ---------------------------------------------------------------------------

select
  version,
  name,
  coalesce(array_length(statements, 1), 0) as elementi,
  coalesce(length(array_to_string(statements, '')), 0) as caratteri,
  encode(sha256(convert_to(array_to_string(statements, ''), 'UTF8')), 'hex') as sha256
from supabase_migrations.schema_migrations
order by version;
