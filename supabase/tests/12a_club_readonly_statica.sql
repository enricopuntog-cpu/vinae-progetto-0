-- Fase 12a - verificatore statico dello schema dei club.
-- Eseguire dopo 20260817090000_phase_12a_club_readonly.sql.
-- Atteso: 24 PASSA, 0 FALLISCE. Non inserisce e non cancella alcun dato.
--
-- STATO DI ESECUZIONE. Dichiarato per primo perche e la cosa piu importante
-- che questo file dice di se stesso:
--
--   QUESTA GRIGLIA NON E MAI STATA ESEGUITA. Ne sul progetto reale
--   (pijnmcllmfgjmgsvtcej), ne su un Postgres locale usa-e-getta. Docker non
--   era disponibile nella sessione che l'ha scritta e non e stato avviato
--   altrove.
--
-- La regola del repository e esplicita e vale contro chi la scrive: una
-- griglia versionata e mai eseguita NON e una prova. La 7e ha misurato quanto
-- costa dimenticarlo - la griglia della 7c era rotta in quattro modi, nessuno
-- visibile leggendola, e non avrebbe potuto committare in nessuno scenario,
-- nemmeno con tutti i casi verdi. Gli esiti attesi qui sotto sono quindi
-- TESTO, non risultati, e il "24 PASSA" della riga 3 e una previsione.
--
-- Chi la esegue per primo si aspetti che qualche caso fallisca per un difetto
-- della griglia e non della migrazione, e lo annoti qui come hanno fatto la
-- 9c e la 7e.
--
-- Eseguirla sul progetto reale resta un'autorizzazione esplicita separata,
-- PER GRIGLIA e non per progetto: l'approvazione del merge della migrazione
-- non la comprende. Questa in particolare e in sola lettura sul catalogo
-- (nessun insert, nessun delete), il che la rende meno rischiosa di quelle di
-- Fase 7 e 9 ma non per questo autorizzata.
--
-- CHE COSA MISURA
--   [1] casi 01-06  struttura: tabelle, enum, chiavi, indici, vincoli
--   [2] casi 07-13  privilegi: chi ha grant su cosa, e soprattutto chi non ne ha
--   [3] casi 14-19  RLS: le tre policy proprie e l'assenza di quelle che non
--                   devono esistere
--   [4] casi 20-22  la vista pubblica: security_invoker off, colonne chiuse,
--                   grant
--   [5] casi 23-24  il guard della 7.6b, e la controprova che la macchina di
--                   pagamento non e stata toccata
--
-- CHE COSA NON MISURA
--   * nessun comportamento: nessuna riga viene inserita, quindi il fatto che
--     un utente non possa iscriverne un altro e qui verificato sulla forma
--     (grant + policy) e non esercitato. Serve una griglia comportamentale
--     con fixture, che e un'autorizzazione a parte e non esiste ancora;
--   * niente sull'interfaccia: nessuna schermata e stata aperta contro un
--     database con questa migrazione applicata.

drop table if exists esiti_12a_static;

create temporary table esiti_12a_static (
  n integer primary key,
  caso text not null,
  esito text not null,
  dettaglio text not null
);

create or replace function pg_temp.registra_12a(
  p_n integer,
  p_caso text,
  p_ok boolean,
  p_dettaglio text
)
returns void
language sql
as $$
  insert into esiti_12a_static (n, caso, esito, dettaglio)
  values (
    p_n,
    p_caso,
    case when p_ok then 'PASSA' else 'FALLISCE' end,
    p_dettaglio
  );
$$;

-- ---------------------------------------------------------------------------
-- [1] Struttura
-- ---------------------------------------------------------------------------

select pg_temp.registra_12a(
  1,
  'Le due tabelle della 12a esistono',
  (select count(*) = 2 from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and c.relname in ('clubs', 'club_memberships')),
  'attese clubs e club_memberships'
);

select pg_temp.registra_12a(
  2,
  'La 12a NON crea tabelle di contenuto: niente post, commenti, reazioni',
  not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
      and c.relname in ('club_posts', 'club_commenti', 'club_reazioni',
                        'club_post_reazioni', 'club_sondaggi')),
  'il contenuto e il 12b: una tabella vuota che lo aspetta e gia il 12b'
);

select pg_temp.registra_12a(
  3,
  'club_ruolo esiste e ha una sola etichetta (decisione 7.1 non riaperta)',
  (select count(*) = 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
   where t.typname = 'club_ruolo')
  and exists (
    select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
    where t.typname = 'club_ruolo' and e.enumlabel = 'membro'),
  'un secondo valore deciderebbe di sfuggita lo scope club della moderazione'
);

select pg_temp.registra_12a(
  4,
  'clubs ha lo slug come chiave primaria',
  exists (
    select 1 from pg_constraint con
    join pg_class c on c.oid = con.conrelid
    join pg_attribute a on a.attrelid = c.oid and a.attnum = any (con.conkey)
    where c.relname = 'clubs' and con.contype = 'p' and a.attname = 'slug'
      and array_length(con.conkey, 1) = 1),
  'attesa pk su slug'
);

select pg_temp.registra_12a(
  5,
  'club_memberships ha la chiave primaria composita (user_id, club_slug)',
  (select array_agg(a.attname order by a.attname) = array['club_slug', 'user_id']
   from pg_constraint con
   join pg_class c on c.oid = con.conrelid
   join pg_attribute a on a.attrelid = c.oid and a.attnum = any (con.conkey)
   where c.relname = 'club_memberships' and con.contype = 'p'),
  'la pk e anche cio che rende idempotente un doppio follow'
);

select pg_temp.registra_12a(
  6,
  'Esiste l''indice su club_slug, la direzione che la pk non copre',
  exists (
    select 1 from pg_index i
    join pg_class ic on ic.oid = i.indexrelid
    join pg_class tc on tc.oid = i.indrelid
    where tc.relname = 'club_memberships'
      and ic.relname = 'club_memberships_club_slug_idx'),
  'serve al conteggio membri di public_clubs'
);

-- ---------------------------------------------------------------------------
-- [2] Privilegi
-- ---------------------------------------------------------------------------

select pg_temp.registra_12a(
  7,
  'clubs: nessun privilegio per anon, in nessuna direzione',
  not has_table_privilege('anon', 'public.clubs', 'select')
  and not has_table_privilege('anon', 'public.clubs', 'insert')
  and not has_table_privilege('anon', 'public.clubs', 'update')
  and not has_table_privilege('anon', 'public.clubs', 'delete'),
  'la lettura pubblica passa dalla vista, non dalla tabella'
);

select pg_temp.registra_12a(
  8,
  'clubs: nessun privilegio per authenticated, in nessuna direzione',
  not has_table_privilege('authenticated', 'public.clubs', 'select')
  and not has_table_privilege('authenticated', 'public.clubs', 'insert')
  and not has_table_privilege('authenticated', 'public.clubs', 'update')
  and not has_table_privilege('authenticated', 'public.clubs', 'delete'),
  'nessuna creazione self-service, e nessuna policy admin che non funzionerebbe'
);

select pg_temp.registra_12a(
  9,
  'club_memberships: authenticated legge (la RLS lo confina alle righe proprie)',
  has_table_privilege('authenticated', 'public.club_memberships', 'select'),
  'caso di bottle_units, non di reports'
);

select pg_temp.registra_12a(
  10,
  'club_memberships: INSERT concesso sulla sola colonna club_slug',
  has_column_privilege('authenticated', 'public.club_memberships', 'club_slug', 'insert')
  and not has_column_privilege('authenticated', 'public.club_memberships', 'user_id', 'insert')
  and not has_column_privilege('authenticated', 'public.club_memberships', 'ruolo', 'insert')
  and not has_column_privilege('authenticated', 'public.club_memberships', 'created_at', 'insert'),
  'user_id arriva dal DEFAULT: il client non puo nominarlo nemmeno per sbaglio'
);

select pg_temp.registra_12a(
  11,
  'club_memberships: nessun UPDATE, a nessun ruolo client',
  not has_table_privilege('authenticated', 'public.club_memberships', 'update')
  and not has_table_privilege('anon', 'public.club_memberships', 'update'),
  'smettere di seguire e una DELETE; ruolo non e del client'
);

select pg_temp.registra_12a(
  12,
  'club_memberships: DELETE concesso ad authenticated e non ad anon',
  has_table_privilege('authenticated', 'public.club_memberships', 'delete')
  and not has_table_privilege('anon', 'public.club_memberships', 'delete'),
  'la riga cancellabile la sceglie la RLS'
);

select pg_temp.registra_12a(
  13,
  'club_memberships: anon non legge e non scrive',
  not has_table_privilege('anon', 'public.club_memberships', 'select')
  and not has_table_privilege('anon', 'public.club_memberships', 'insert'),
  'un visitatore anonimo non ha follow da leggere'
);

-- ---------------------------------------------------------------------------
-- [3] RLS
-- ---------------------------------------------------------------------------

select pg_temp.registra_12a(
  14,
  'RLS accesa su entrambe le tabelle',
  (select bool_and(c.relrowsecurity) from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname in ('clubs', 'club_memberships')),
  'la 20260729234000 la accende da sola, la migrazione lo ripete in chiaro'
);

select pg_temp.registra_12a(
  15,
  'clubs non ha alcuna policy: e chiusa due volte, senza grant e senza policy',
  not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'clubs'),
  'una policy senza grant non aprirebbe niente, ma direbbe il falso a chi legge'
);

select pg_temp.registra_12a(
  16,
  'club_memberships ha esattamente tre policy',
  (select count(*) = 3 from pg_policies
   where schemaname = 'public' and tablename = 'club_memberships'),
  'select, insert, delete - e nessuna di update'
);

select pg_temp.registra_12a(
  17,
  'Le tre policy sono per il solo ruolo authenticated',
  (select bool_and(roles = array['authenticated']::name[]) from pg_policies
   where schemaname = 'public' and tablename = 'club_memberships'),
  'nessuna policy tocca anon o public'
);

select pg_temp.registra_12a(
  18,
  'Ogni policy confronta user_id con auth.uid(), e nessuna e permissiva a vuoto',
  (select bool_and(coalesce(qual, with_check) like '%user_id%'
                   and coalesce(qual, with_check) like '%uid()%')
   from pg_policies
   where schemaname = 'public' and tablename = 'club_memberships'),
  'un utente non iscrive un altro: il predicato non ha parametri'
);

select pg_temp.registra_12a(
  19,
  'user_id ha DEFAULT auth.uid()',
  exists (
    select 1 from pg_attrdef d
    join pg_class c on c.oid = d.adrelid
    join pg_attribute a on a.attrelid = c.oid and a.attnum = d.adnum
    where c.relname = 'club_memberships' and a.attname = 'user_id'
      and pg_get_expr(d.adbin, d.adrelid) like '%uid()%'),
  'senza il DEFAULT la colonna sarebbe non-null e nessun client potrebbe scrivere'
);

-- ---------------------------------------------------------------------------
-- [4] La vista pubblica
-- ---------------------------------------------------------------------------

select pg_temp.registra_12a(
  20,
  'public_clubs esiste ed e security_invoker = off',
  exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'public_clubs' and c.relkind = 'v')
  and not coalesce(
    (select (regexp_match(array_to_string(c.reloptions, ','),
                          'security_invoker=(\w+)'))[1] = 'true'
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = 'public_clubs'),
    false),
  'con invoker acceso il conteggio membri leggerebbe con i privilegi del chiamante'
);

select pg_temp.registra_12a(
  21,
  'public_clubs espone undici colonne, elenco chiuso',
  (select count(*) = 11 from information_schema.columns
   where table_schema = 'public' and table_name = 'public_clubs')
  and (select bool_and(column_name in (
        'slug', 'nome', 'territorio', 'denominazione', 'produttore', 'tipologia',
        'descrizione', 'regole', 'created_at', 'membri', 'seguito'))
       from information_schema.columns
       where table_schema = 'public' and table_name = 'public_clubs'),
  'una colonna aggiunta domani a clubs resta privata finche non la si elenca'
);

select pg_temp.registra_12a(
  22,
  'public_clubs e leggibile da anon e authenticated, e non scrivibile',
  has_table_privilege('anon', 'public.public_clubs', 'select')
  and has_table_privilege('authenticated', 'public.public_clubs', 'select')
  and not has_table_privilege('authenticated', 'public.public_clubs', 'insert')
  and not has_table_privilege('authenticated', 'public.public_clubs', 'update'),
  'lettura pubblica, scrittura da nessuna parte'
);

-- ---------------------------------------------------------------------------
-- [5] Decisione 7.6b, e la controprova sui pagamenti
-- ---------------------------------------------------------------------------

select pg_temp.registra_12a(
  23,
  'Il guard delle scritture social della 9b e attaccato a club_memberships',
  exists (
    select 1 from pg_trigger tg
    join pg_class c on c.oid = tg.tgrelid
    join pg_proc p on p.oid = tg.tgfoid
    join pg_namespace pn on pn.oid = p.pronamespace
    where c.relname = 'club_memberships'
      and not tg.tgisinternal
      and pn.nspname = 'private'
      and p.proname = 'scrittura_social_guard'),
  'seguire un club e una scrittura social: stesso guard di listings e messages'
);

select pg_temp.registra_12a(
  24,
  'Nessuna funzione della macchina di pagamento e stata ridefinita dalla 12a',
  not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and p.proname in ('payout_prepara', 'payout_coda', 'payout_registra_esito',
                        'ordine_auto_rilascio_esegui', 'conferma_ricezione',
                        'ordine_contestazione_risolvi')
      and pg_get_functiondef(p.oid) ilike '%club%'),
  'vincolo della 9c: il pagamento non reagisce a nulla di sociale, club compreso'
);

-- ---------------------------------------------------------------------------
-- Esito
-- ---------------------------------------------------------------------------

select n, caso, esito, dettaglio from esiti_12a_static order by n;

select
  count(*) filter (where esito = 'PASSA')    as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*)                                   as totale
from esiti_12a_static;
