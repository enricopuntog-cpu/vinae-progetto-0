-- Fase 6a — Catalogo vini condiviso, unità fisiche e annunci.
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
