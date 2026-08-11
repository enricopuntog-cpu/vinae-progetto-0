-- Fase 9b - verificatore statico, senza fixture applicative.
-- Eseguire dopo 20260810180000_phase_9b_moderation_actions.sql (che a sua volta
-- presuppone le due migrazioni della 9a).
-- Atteso: 26 PASSA, 0 FALLISCE. Non inserisce e non cancella alcun dato.
--
-- STATO DI ESECUZIONE, dichiarato per non ripetere l'errore che la 7e ha
-- misurato. Questa griglia e stata eseguita davvero, su un Postgres 17.10
-- usa-e-getta con la stessa impalcatura di stub della 9a, estesa alle tabelle e
-- alle funzioni che la 9b referenzia (listings, wines, bottle_units,
-- conversations, messages, notifications, public_listings nella forma della 7c).
-- Prima esecuzione: 23 PASSA / 3 FALLISCE. Tutti e tre erano difetti della
-- griglia e nessuno della migrazione — un conteggio di colonne sbagliato a
-- mano, un `like` che leggeva il commento in cui una funzione spiega perche
-- NON usa has_role, e un confronto su `proargtypes`, che e un oidvector con
-- estremo inferiore 0 e quindi non e mai uguale a un array letterale. Terza
-- esecuzione dopo le correzioni: 26 PASSA / 0 FALLISCE.
--
-- Accanto a questa griglia statica e stata eseguita, sullo stesso Postgres, una
-- batteria di 61 sonde comportamentali che impersonano `authenticated`, `anon`,
-- `service_role` e il contesto interno di una funzione SECURITY DEFINER: il gate
-- di moderazione, le transizioni sugli annunci, i due livelli della decisione
-- 7.6b in entrambe le direzioni, e gli invarianti della 9a che devono reggere
-- anche dopo. Esito 61 PASSA / 0 FALLISCE, alla terza esecuzione; le due
-- precedenti hanno trovato tre difetti nelle sonde stesse (nome di variabile
-- psql ricavato dalla colonna e quindi minuscolo, e due sonde che consumavano
-- l'ultimo annuncio attivo del catalogo prima di misurarlo) e nessuno nella
-- migrazione. Quelle sonde non sono versionate qui: dipendono da fixture e la
-- loro autorizzazione e per griglia, non per progetto.
--
-- Quell'esecuzione NON e il progetto reale. Su pijnmcllmfgjmgsvtcej questa
-- griglia non ha mai girato: serve un'autorizzazione esplicita separata, per
-- griglia e non per progetto. Un'impalcatura di stub prova che la griglia e
-- eseguibile e che gli invarianti reggono sulla forma; non prova lo stato del
-- progetto reale.

drop table if exists esiti_9b_static;

create temporary table esiti_9b_static (
  n integer primary key,
  caso text not null,
  esito text not null,
  dettaglio text not null
);

create or replace function pg_temp.registra_9b_static(
  p_n integer,
  p_caso text,
  p_ok boolean,
  p_dettaglio text
)
returns void
language sql
as $$
  insert into esiti_9b_static (n, caso, esito, dettaglio)
  values (
    p_n,
    p_caso,
    case when p_ok then 'PASSA' else 'FALLISCE' end,
    p_dettaglio
  );
$$;

-- ---------------------------------------------------------------------------
-- Struttura
-- ---------------------------------------------------------------------------

select pg_temp.registra_9b_static(
  1,
  'utente_stato esiste con i tre valori della decisione 7.6b',
  (select count(*) = 3 from pg_enum e join pg_type t on t.oid = e.enumtypid
   join pg_namespace n on n.oid = t.typnamespace
   where n.nspname = 'public' and t.typname = 'utente_stato'
     and e.enumlabel in ('attivo', 'sospeso', 'rimosso')),
  'attesi attivo, sospeso, rimosso'
);

select pg_temp.registra_9b_static(
  2,
  'profiles ha lo stato a piu valori e il contatore dei provvedimenti',
  (select count(*) = 4 from information_schema.columns
   where table_schema = 'public' and table_name = 'profiles'
     and column_name in ('stato_utente', 'provvedimenti', 'stato_utente_at',
                         'stato_utente_motivo')),
  'lo stato non e un booleano: e un enum piu un contatore'
);

select pg_temp.registra_9b_static(
  3,
  'listing_stato non e stato alterato: restano i nove valori della 6a',
  (select count(*) = 9 from pg_enum e join pg_type t on t.oid = e.enumtypid
   where t.typname = 'listing_stato'),
  'la 9b usa in_revisione, modifiche_richieste e rifiutato senza aggiungere label'
);

select pg_temp.registra_9b_static(
  4,
  'Decisione 7.8b: nessuna colonna di ricorso e comparsa',
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name in ('audit_log', 'reports', 'report_events')
      and column_name ilike '%ricors%'),
  'il campo esiste nel mock e non viene portato'
);

select pg_temp.registra_9b_static(
  5,
  'Decisione 7.8a: nessuna colonna di SLA o scadenza sulle pratiche',
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name in ('reports', 'report_events')
      and (column_name ilike '%sla%' or column_name ilike '%scadenz%'
           or column_name ilike '%deadline%')),
  'nessuno SLA'
);

select pg_temp.registra_9b_static(
  6,
  'Decisione 7.5: nessuna colonna di assegnazione e comparsa su reports',
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reports'
      and column_name in ('assignee', 'assegnata_a', 'assegnatario')),
  'coda condivisa'
);

-- ---------------------------------------------------------------------------
-- Le sette azioni, distinte
-- ---------------------------------------------------------------------------

select pg_temp.registra_9b_static(
  7,
  'Le sette azioni sono sette funzioni pubbliche distinte',
  (select count(*) = 7 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in (
     'moderazione_info_richieste', 'moderazione_richiesta_modifiche',
     'moderazione_ammonizione', 'moderazione_sospensione',
     'moderazione_rimozione', 'moderazione_ripristino', 'moderazione_chiusura')),
  'non una funzione con parametro azione'
);

select pg_temp.registra_9b_static(
  8,
  'Nessuna funzione di moderazione accetta un parametro di tipo mod_action',
  not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'moderazione\_%'
      and 'public.mod_action'::regtype = any (p.proargtypes::oid[])),
  'un parametro azione riunirebbe sette poteri in un solo GRANT'
);

select pg_temp.registra_9b_static(
  9,
  'Le cinque porte di moderazione sugli annunci esistono',
  (select count(*) = 5 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in (
     'moderazione_annuncio_in_revisione', 'moderazione_annuncio_modifiche_richieste',
     'moderazione_annuncio_rifiuta', 'moderazione_annuncio_sospendi',
     'moderazione_annuncio_ripristina')),
  'in_revisione, modifiche_richieste, rifiutato, sospeso, ripristino'
);

select pg_temp.registra_9b_static(
  10,
  'listing_sospendi non e stata allargata: resta (uuid, text) e SECURITY DEFINER',
  -- `proargtypes` e un oidvector con estremo inferiore 0: confrontarlo con un
  -- array letterale fallisce sui limiti, non sul contenuto. to_regprocedure
  -- confronta la firma senza quel tranello, e restituisce null invece di
  -- sollevare quando la funzione non esiste.
  (select count(*) = 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'listing_sospendi')
  and to_regprocedure('public.listing_sospendi(uuid, text)') is not null
  and (select p.prosecdef from pg_proc p
       where p.oid = to_regprocedure('public.listing_sospendi(uuid, text)')),
  'la sospensione di moderazione e una funzione separata'
);

select pg_temp.registra_9b_static(
  11,
  'Tutte le funzioni pubbliche della 9b sono SECURITY DEFINER',
  (select bool_and(p.prosecdef) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname like 'moderazione\_%'),
  'il gate e dentro la funzione, non nel GRANT'
);

select pg_temp.registra_9b_static(
  12,
  'Tutte le funzioni della 9b hanno search_path fissato',
  (select bool_and(p.proconfig is not null
                   and exists (select 1 from unnest(p.proconfig) c
                               where c like 'search\_path=%'))
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where (n.nspname = 'public' and p.proname like 'moderazione\_%')
      or (n.nspname = 'private' and (p.proname like 'moderazione\_%'
          or p.proname in ('utente_stato_di', 'profiles_stato_utente_guard',
                           'scrittura_social_guard')))),
  'nessuna funzione eredita il search_path del chiamante'
);

select pg_temp.registra_9b_static(
  13,
  'Nessuna funzione della 9b usa public.has_role',
  not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and (p.proname like 'moderazione\_%' or p.proname = 'utente_stato_di')
      -- I commenti di riga vanno tolti prima del confronto: piu di un corpo
      -- *nomina* has_role per spiegare perche non la usa, e un `like` grezzo
      -- leggerebbe la spiegazione come la chiamata.
      and regexp_replace(pg_get_functiondef(p.oid), '--[^\n]*', '', 'g')
          like '%has_role%'),
  'il predicato di moderatore e scritto per esteso, per il motivo documentato nella 9a'
);

-- ---------------------------------------------------------------------------
-- Privilegi
-- ---------------------------------------------------------------------------

select pg_temp.registra_9b_static(
  14,
  'Le dodici porte di moderazione sono eseguibili da authenticated e non da anon',
  (select count(*) = 12 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname like 'moderazione\_%'
     and has_function_privilege('authenticated', p.oid, 'execute')
     and not has_function_privilege('anon', p.oid, 'execute')),
  'il GRANT e la porta, il ruolo admin e il permesso'
);

select pg_temp.registra_9b_static(
  15,
  'Nessun helper private della 9b e eseguibile da un ruolo client',
  not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and (p.proname like 'moderazione\_%'
           or p.proname in ('utente_stato_di', 'profiles_stato_utente_guard',
                            'scrittura_social_guard'))
      and (has_function_privilege('authenticated', p.oid, 'execute')
           or has_function_privilege('anon', p.oid, 'execute'))),
  'gli helper vivono dentro le SECURITY DEFINER, non a portata del client'
);

select pg_temp.registra_9b_static(
  16,
  'Le quattro colonne di moderazione di profiles non sono aggiornabili dal client',
  not (has_column_privilege('authenticated', 'public.profiles', 'stato_utente', 'update')
       or has_column_privilege('authenticated', 'public.profiles', 'provvedimenti', 'update')
       or has_column_privilege('authenticated', 'public.profiles', 'stato_utente_at', 'update')
       or has_column_privilege('authenticated', 'public.profiles', 'stato_utente_motivo', 'update')),
  'senza questo, un sospeso si toglierebbe la sospensione da solo'
);

select pg_temp.registra_9b_static(
  17,
  'Le colonne di profilo modificabili dall''utente restano aggiornabili',
  (has_column_privilege('authenticated', 'public.profiles', 'bio', 'update')
   and has_column_privilege('authenticated', 'public.profiles', 'dob', 'update')
   and has_column_privilege('authenticated', 'public.profiles', 'username', 'update')),
  'la restrizione non e una revoca generale'
);

select pg_temp.registra_9b_static(
  18,
  'L''utente legge il proprio stato_utente',
  has_column_privilege('authenticated', 'public.profiles', 'stato_utente', 'select'),
  'una sospensione illeggibile non si puo spiegare; la RLS limita gia alla propria riga'
);

select pg_temp.registra_9b_static(
  19,
  'my_listing_moderation e leggibile da authenticated e non da anon',
  has_table_privilege('authenticated', 'public.my_listing_moderation', 'select')
  and not has_table_privilege('anon', 'public.my_listing_moderation', 'select'),
  'proiezione a righe proprie del motivo di rifiuto'
);

select pg_temp.registra_9b_static(
  20,
  'stato_motivo resta fuori dal GRANT di colonna di listings',
  not has_column_privilege('authenticated', 'public.listings', 'stato_motivo', 'select')
  and not has_column_privilege('authenticated', 'public.listings', 'stato_aggiornato_da', 'select'),
  'la proiezione esiste proprio perche il GRANT non e stato allargato'
);

select pg_temp.registra_9b_static(
  21,
  'my_listing_moderation non espone stato_aggiornato_da',
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'my_listing_moderation'
      and column_name = 'stato_aggiornato_da'),
  'chi ha deciso e dato di moderazione, come disputes.risolta_da'
);

-- ---------------------------------------------------------------------------
-- Viste
-- ---------------------------------------------------------------------------

select pg_temp.registra_9b_static(
  22,
  'Le viste della 9b sono security_invoker = off con security_barrier',
  (select bool_and(
     coalesce(array_to_string(c.reloptions, ','), '') like '%security_barrier=true%'
     and coalesce(array_to_string(c.reloptions, ','), '') not like '%security_invoker=true%')
   from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'v'
     and c.relname in ('my_listing_moderation', 'public_listings', 'my_reports',
                       'my_report_events')),
  'il filtro sta dentro la vista, dove nessun client puo allargarlo'
);

select pg_temp.registra_9b_static(
  23,
  'public_listings filtra il venditore rimosso e il chiamante rimosso',
  (select pg_get_viewdef('public.public_listings'::regclass) like '%stato_utente%'),
  'decisione 7.6b, secondo livello, in entrambe le direzioni'
);

select pg_temp.registra_9b_static(
  24,
  'public_listings conserva le colonne della 7c, nello stesso ordine',
  (select count(*) = 30 from information_schema.columns
   where table_schema = 'public' and table_name = 'public_listings')
  and (select column_name = 'imballaggio_codice' from information_schema.columns
       where table_schema = 'public' and table_name = 'public_listings'
       order by ordinal_position desc limit 1),
  'create or replace view non riordina: la sostituzione non ha spostato nulla'
);

-- ---------------------------------------------------------------------------
-- Trigger
-- ---------------------------------------------------------------------------

select pg_temp.registra_9b_static(
  25,
  'Il guard delle scritture social e su listings, messages e conversations',
  (select count(*) = 3 from pg_trigger tg
   join pg_class c on c.oid = tg.tgrelid
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and not tg.tgisinternal
     and tg.tgfoid = 'private.scrittura_social_guard()'::regprocedure
     and c.relname in ('listings', 'messages', 'conversations')),
  'un trigger vincola la tabella, non solo la RPC che la scrive oggi'
);

select pg_temp.registra_9b_static(
  26,
  'Il guard dello stato utente e attivo su profiles in UPDATE',
  exists (
    select 1 from pg_trigger tg
    join pg_class c on c.oid = tg.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'profiles'
      and not tg.tgisinternal
      and tg.tgfoid = 'private.profiles_stato_utente_guard()'::regprocedure),
  'il GRANT di colonna non vincola service_role; il trigger si'
);

-- ---------------------------------------------------------------------------
-- Esito
-- ---------------------------------------------------------------------------

select n, caso, esito, dettaglio from esiti_9b_static order by n;

select
  count(*) filter (where esito = 'PASSA') as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*) as totale
from esiti_9b_static;
