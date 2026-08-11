-- Fase 9a - verificatore statico, senza fixture applicative.
-- Eseguire dopo 20260810152000_phase_9a_moderation_schema.sql e
-- 20260810152500_phase_9a_drop_public_bottle_units.sql.
-- Atteso: 28 PASSA, 0 FALLISCE. Non inserisce e non cancella alcun dato.
--
-- STATO DI ESECUZIONE, dichiarato per non ripetere l'errore che la 7e ha
-- misurato. Questa griglia e stata eseguita davvero, su un Postgres 17.10
-- usa-e-getta con un'impalcatura di stub che replica i privilegi reali dei tre
-- ruoli client — in particolare il fatto che `authenticated` NON ha select su
-- public.user_roles. Prima esecuzione: 27 PASSA, 1 FALLISCE, e il caso 26 era
-- un difetto della griglia (confronto sbagliato su proconfig) e non della
-- migrazione. Seconda esecuzione dopo la correzione: 28 PASSA.
--
-- Quell'esecuzione NON e il progetto reale. Su pijnmcllmfgjmgsvtcej questa
-- griglia non ha mai girato: serve un'autorizzazione esplicita separata, per
-- griglia e non per progetto. Un'impalcatura di stub prova che la griglia e
-- eseguibile e che gli invarianti reggono sulla forma; non prova lo stato del
-- progetto reale.

drop table if exists esiti_9a_static;

create temporary table esiti_9a_static (
  n integer primary key,
  caso text not null,
  esito text not null,
  dettaglio text not null
);

create or replace function pg_temp.registra_9a_static(
  p_n integer,
  p_caso text,
  p_ok boolean,
  p_dettaglio text
)
returns void
language sql
as $$
  insert into esiti_9a_static (n, caso, esito, dettaglio)
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

select pg_temp.registra_9a_static(
  1,
  'Le quattro tabelle della 9a esistono',
  (select count(*) = 4 from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and c.relname in ('reports', 'report_events', 'audit_log', 'report_reasons')),
  'attese reports, report_events, audit_log, report_reasons'
);

select pg_temp.registra_9a_static(
  2,
  'I cinque enum della 9a esistono',
  (select count(*) = 5 from pg_type t join pg_namespace n on n.oid = t.typnamespace
   where n.nspname = 'public' and t.typtype = 'e'
     and t.typname in ('report_target_tipo', 'report_stato', 'report_priorita',
                       'mod_action', 'mod_scope')),
  'attesi 5 enum'
);

select pg_temp.registra_9a_static(
  3,
  'Decisione 7.6a: report_target_tipo ha 5 etichette e non contiene post/commento',
  (select count(*) = 5 from pg_enum e join pg_type t on t.oid = e.enumtypid
   where t.typname = 'report_target_tipo')
  and not exists (
    select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
    where t.typname = 'report_target_tipo' and e.enumlabel in ('post', 'commento')),
  'attese annuncio, profilo, messaggio, conversazione, recensione'
);

select pg_temp.registra_9a_static(
  4,
  'mod_action ha le sette azioni del mock',
  (select count(*) = 7 from pg_enum e join pg_type t on t.oid = e.enumtypid
   where t.typname = 'mod_action'
     and e.enumlabel in ('richiesta_modifiche', 'ammonizione', 'sospensione',
                         'rimozione', 'ripristino', 'chiusura', 'info_richieste')),
  'attese 7 azioni'
);

select pg_temp.registra_9a_static(
  5,
  'listing_stato non e stato alterato: restano i nove valori della 6a',
  (select count(*) = 9 from pg_enum e join pg_type t on t.oid = e.enumtypid
   where t.typname = 'listing_stato'),
  'i tre valori di moderazione esistevano gia, la 9a non aggiunge etichette'
);

select pg_temp.registra_9a_static(
  6,
  'RLS abilitata su tutte e quattro le tabelle',
  (select count(*) = 4 from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relrowsecurity
     and c.relname in ('reports', 'report_events', 'audit_log', 'report_reasons')),
  'attese 4 tabelle con relrowsecurity = true'
);

-- ---------------------------------------------------------------------------
-- Prima regola di esposizione: nessun grant di tabella a chi raggiunge righe altrui
-- ---------------------------------------------------------------------------

select pg_temp.registra_9a_static(
  7,
  'Regola 1: reports, report_events e audit_log non hanno alcun grant client',
  not exists (
    select 1 from information_schema.role_table_grants
    where grantee in ('anon', 'authenticated', 'PUBLIC') and table_schema = 'public'
      and table_name in ('reports', 'report_events', 'audit_log')),
  'attesi 0 grant di tabella per anon e authenticated'
);

select pg_temp.registra_9a_static(
  8,
  'Regola 1: nemmeno un grant di colonna sulle tre tabelle di dominio',
  not exists (
    select 1 from information_schema.column_privileges
    where grantee in ('anon', 'authenticated', 'PUBLIC') and table_schema = 'public'
      and table_name in ('reports', 'report_events', 'audit_log')),
  'attesi 0 grant di colonna: ogni lettura passa dalle viste'
);

select pg_temp.registra_9a_static(
  9,
  'reports, report_events e audit_log non hanno alcuna policy',
  not exists (
    select 1 from pg_policy p join pg_class c on c.oid = p.polrelid
    where c.relname in ('reports', 'report_events', 'audit_log')),
  'RLS attiva senza policy: zero righe per ogni ruolo client'
);

select pg_temp.registra_9a_static(
  10,
  'report_reasons e leggibile a colonne chiuse da authenticated e anon',
  (select count(distinct grantee) = 2 from information_schema.column_privileges
   where table_schema = 'public' and table_name = 'report_reasons'
     and grantee in ('anon', 'authenticated') and privilege_type = 'SELECT')
  and not exists (
    select 1 from information_schema.column_privileges
    where table_schema = 'public' and table_name = 'report_reasons'
      and grantee in ('anon', 'authenticated') and privilege_type <> 'SELECT'),
  'e il menu dei motivi: nessuna riga di alcun utente, sola lettura'
);

-- ---------------------------------------------------------------------------
-- audit_log: append-only e decisioni 7.3 / 7.8b
-- ---------------------------------------------------------------------------

select pg_temp.registra_9a_static(
  11,
  'audit_log ha i tre trigger che rifiutano UPDATE, DELETE e TRUNCATE',
  (select count(*) = 3 from pg_trigger
   where tgrelid = 'public.audit_log'::regclass and not tgisinternal
     and tgname in ('audit_log_no_update', 'audit_log_no_delete', 'audit_log_no_truncate')),
  'append-only imposto dal database, non dai soli GRANT'
);

select pg_temp.registra_9a_static(
  12,
  'I tre trigger sono BEFORE, quindi bloccano prima di scrivere',
  (select bool_and((tgtype & 2) = 2) from pg_trigger
   where tgrelid = 'public.audit_log'::regclass and not tgisinternal),
  'tgtype bit 1 = BEFORE'
);

select pg_temp.registra_9a_static(
  13,
  'Decisione 7.8b: audit_log non ha la colonna ricorso',
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'audit_log' and column_name = 'ricorso'),
  'il campo esiste in AuditEntry ma nessuna interfaccia di frontend/ lo scrive'
);

select pg_temp.registra_9a_static(
  14,
  'La motivazione e obbligatoria come vincolo di database',
  (select is_nullable = 'NO' from information_schema.columns
   where table_schema = 'public' and table_name = 'audit_log' and column_name = 'motivazione')
  and exists (
    select 1 from pg_constraint
    where conrelid = 'public.audit_log'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%motivazione%'),
  'nel mock era un controllo del client (useModerationActions.ts:63)'
);

select pg_temp.registra_9a_static(
  15,
  'La durata e ammessa solo sull''azione sospensione',
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.audit_log'::regclass
      and conname = 'audit_log_durata_solo_sospensione'),
  'come nel mock, che passa durata solo per sospensione'
);

-- ---------------------------------------------------------------------------
-- reports: decisioni 7.4 / 7.5 e integrita del bersaglio
-- ---------------------------------------------------------------------------

select pg_temp.registra_9a_static(
  16,
  'Decisione 7.5: reports non ha alcuna colonna di assegnazione',
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reports'
      and column_name in ('assignee', 'assignee_id', 'assegnata_a', 'assegnatario_id')),
  'coda condivisa fra tutti i moderatori, nessuna presa in carico'
);

select pg_temp.registra_9a_static(
  17,
  'Il motivo e vincolato all''elenco chiuso da una foreign key',
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.reports'::regclass and contype = 'f'
      and confrelid = 'public.report_reasons'::regclass),
  'il motivo fuori elenco e una violazione di vincolo, non un messaggio'
);

select pg_temp.registra_9a_static(
  18,
  'I due CHECK di coerenza del bersaglio esistono',
  (select count(*) = 2 from pg_constraint
   where conrelid = 'public.reports'::regclass
     and conname in ('reports_target_esclusivo', 'reports_target_coerente')),
  'esattamente un riferimento, coerente con target_tipo'
);

select pg_temp.registra_9a_static(
  19,
  'I cinque riferimenti di bersaglio sono ON DELETE SET NULL, mai CASCADE',
  (select count(*) = 5 from pg_constraint
   where conrelid = 'public.reports'::regclass and contype = 'f'
     and confdeltype = 'n'
     and conname <> 'reports_motivo_fk'),
  'una segnalazione sopravvive alla rimozione di cio che segnala'
);

select pg_temp.registra_9a_static(
  20,
  'L''elenco chiuso contiene 21 motivi sui cinque tipi di bersaglio',
  (select count(*) = 21 from public.report_reasons)
  and (select count(distinct target_tipo) = 5 from public.report_reasons),
  'identici a reportReasons in frontend/src/data/moderation.ts:35-61, meno post e commento'
);

-- ---------------------------------------------------------------------------
-- Seconda regola di esposizione: le viste
-- ---------------------------------------------------------------------------

select pg_temp.registra_9a_static(
  21,
  'Le sei proiezioni esistono e sono tutte security_invoker = off',
  (select count(*) = 6 from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'v'
     and c.relname in ('moderation_report_queue', 'moderation_report_events',
                       'my_reports', 'my_report_events',
                       'moderation_dispute_queue', 'moderation_audit_log')
     and c.reloptions @> array['security_invoker=off']),
  'il filtro sta dentro la vista, dove nessun client puo allargarlo'
);

select pg_temp.registra_9a_static(
  22,
  'Nessuna proiezione di moderazione e leggibile da anon',
  not exists (
    select 1 from information_schema.role_table_grants
    where grantee = 'anon' and table_schema = 'public'
      and table_name in ('moderation_report_queue', 'moderation_report_events',
                         'my_reports', 'my_report_events',
                         'moderation_dispute_queue', 'moderation_audit_log')),
  'nessuna riga di moderazione ha un lettore anonimo'
);

select pg_temp.registra_9a_static(
  23,
  'Decisione 7.4: il moderatore vede il segnalante, il segnalante non compare in my_reports',
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'moderation_report_queue'
      and column_name in ('reporter_id', 'reporter_username'))
  and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'my_reports'
      and column_name = 'reporter_id'),
  'tracciata verso il moderatore, mai verso il segnalato'
);

select pg_temp.registra_9a_static(
  24,
  'my_report_events non espone la colonna visibile e filtra le note interne',
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'my_report_events'
      and column_name = 'visibile')
  and pg_get_viewdef('public.my_report_events'::regclass) ilike '%visibile%',
  'la colonna non e esposta ma e usata come filtro dentro la vista'
);

select pg_temp.registra_9a_static(
  25,
  'Nessuna vista della 9a chiama public.has_role',
  not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'v'
      and c.relname like any (array['moderation_%', 'my_report%'])
      and pg_get_viewdef(c.oid) ilike '%has_role%'),
  'has_role e SECURITY INVOKER e authenticated non ha select su user_roles: '
  'darebbe permission denied a ogni lettura, non una coda vuota'
);

-- ---------------------------------------------------------------------------
-- Terza regola di esposizione: le porte di scrittura
-- ---------------------------------------------------------------------------

select pg_temp.registra_9a_static(
  26,
  'segnalazione_invia e SECURITY DEFINER con search_path chiuso ed e concessa solo ad authenticated',
  -- proconfig conserva il valore virgolettato: e {"search_path=\"\""}, non
  -- {search_path=}. Il confronto sbagliato faceva fallire questo caso su una
  -- funzione corretta, ed e stato trovato eseguendo la griglia.
  (select p.prosecdef and p.proconfig @> array['search_path=""']
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'segnalazione_invia')
  and has_function_privilege('authenticated',
        'public.segnalazione_invia(public.report_target_tipo, uuid, text, text, text, text[], text)',
        'execute')
  and not has_function_privilege('anon',
        'public.segnalazione_invia(public.report_target_tipo, uuid, text, text, text, text[], text)',
        'execute'),
  'unica porta di ingresso di una segnalazione'
);

-- ---------------------------------------------------------------------------
-- Decisione 7.7
-- ---------------------------------------------------------------------------

select pg_temp.registra_9a_static(
  27,
  'Decisione 7.7: public_bottle_units non esiste piu',
  not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'public_bottle_units'),
  'rimossa insieme alla cantina pubblica per singola bottiglia'
);

select pg_temp.registra_9a_static(
  28,
  'Nessuna policy di bottle_units espone righe a un non proprietario',
  not exists (
    select 1 from pg_policy p join pg_class c on c.oid = p.polrelid
    where c.relname = 'bottle_units'
      and pg_get_expr(p.polqual, p.polrelid) not ilike '%owner_id%'),
  'la vista era l''ultimo percorso pubblico verso una bottle_unit'
);

-- ---------------------------------------------------------------------------
-- Esito
-- ---------------------------------------------------------------------------

select n, caso, esito, dettaglio from esiti_9a_static order by n;

select
  count(*) filter (where esito = 'PASSA') as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*) as totale
from esiti_9a_static;
