-- A20 - Segnalazioni e reclami end-to-end.
--
-- Griglia distruttiva solo sulle fixture A20, racchiusa anche in una transazione.
-- Non e stata eseguita sul progetto reale.
--
-- STATO BUILD 2026-08-30:
--   DB GRID = NON VERIFICATO LOCALMENTE

\set ON_ERROR_STOP on

begin;

create temporary table esiti_reporting_reclami (
  n integer primary key,
  caso text not null,
  esito text not null,
  dettaglio text not null default ''
);

create temporary table reporting_reclami_risultati (
  chiave text primary key,
  esito text not null,
  id uuid
);

create or replace function pg_temp.registra(
  p_n integer,
  p_caso text,
  p_ok boolean,
  p_dettaglio text default ''
) returns void language sql as $$
  insert into esiti_reporting_reclami (n, caso, esito, dettaglio)
  values (p_n, p_caso, case when p_ok then 'PASSA' else 'FALLISCE' end, p_dettaglio);
$$;

create or replace function pg_temp.impersona(p_uid uuid, p_ruolo text)
returns void language plpgsql as $$
begin
  perform set_config('vinea.uid', coalesce(p_uid::text, ''), true);
  perform set_config(
    'request.jwt.claims',
    case
      when p_uid is null then '{}'
      else json_build_object('sub', p_uid, 'role', p_ruolo)::text
    end,
    true
  );
  execute format('set local role %I', p_ruolo);
end;
$$;

create or replace function pg_temp.esegui(
  p_chiave text,
  p_sql text,
  p_uid uuid default null,
  p_ruolo text default 'authenticated'
) returns text language plpgsql as $$
declare
  v_esito text;
begin
  perform pg_temp.impersona(p_uid, p_ruolo);
  begin
    execute p_sql;
    v_esito := 'NESSUN_ERRORE';
  exception when others then
    v_esito := sqlstate || '|' || sqlerrm;
  end;
  reset role;
  insert into reporting_reclami_risultati (chiave, esito)
  values (p_chiave, v_esito)
  on conflict (chiave) do update set esito = excluded.esito;
  return v_esito;
end;
$$;

create or replace function pg_temp.esegui_id(
  p_chiave text,
  p_sql text,
  p_uid uuid,
  p_ruolo text default 'authenticated'
) returns text language plpgsql as $$
declare
  v_esito text;
  v_id uuid;
begin
  perform pg_temp.impersona(p_uid, p_ruolo);
  begin
    execute p_sql into v_id;
    v_esito := 'NESSUN_ERRORE';
  exception when others then
    v_esito := sqlstate || '|' || sqlerrm;
  end;
  reset role;
  insert into reporting_reclami_risultati (chiave, esito, id)
  values (p_chiave, v_esito, v_id)
  on conflict (chiave) do update set esito = excluded.esito, id = excluded.id;
  return v_esito;
end;
$$;

create or replace function pg_temp.esito(p_chiave text)
returns text language sql stable as $$
  select esito from reporting_reclami_risultati where chiave = p_chiave;
$$;

create or replace function pg_temp.rif(p_chiave text)
returns uuid language sql stable as $$
  select id from reporting_reclami_risultati where chiave = p_chiave;
$$;

create or replace function pg_temp.leggi(
  p_sql text,
  p_uid uuid default null,
  p_ruolo text default 'postgres'
) returns text language plpgsql as $$
declare
  v_risultato text;
begin
  perform pg_temp.impersona(p_uid, p_ruolo);
  execute p_sql into v_risultato;
  reset role;
  return v_risultato;
end;
$$;

-- Fixture isolate. Gli UUID e lo slug A20 sono riservati a questa griglia.
do $fixture$
declare
  v_wine uuid;
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    ('a2000000-0000-0000-0000-000000000001', 'a20-owner@vinea.test', '{"username":"a20_owner"}'::jsonb),
    ('a2000000-0000-0000-0000-000000000002', 'a20-reporter@vinea.test', '{"username":"a20_reporter"}'::jsonb),
    ('a2000000-0000-0000-0000-000000000003', 'a20-other@vinea.test', '{"username":"a20_other"}'::jsonb),
    ('a2000000-0000-0000-0000-000000000004', 'a20-admin@vinea.test', '{"username":"a20_admin"}'::jsonb);

  insert into public.user_roles (user_id, role)
  values ('a2000000-0000-0000-0000-000000000004', 'admin');

  insert into public.clubs (slug, nome, descrizione, territorio, tipologia, owner_id)
  values (
    'a20-club-reporting',
    'A20 Club Canonico',
    'Fixture della griglia segnalazioni.',
    'Piemonte',
    'Rosso',
    'a2000000-0000-0000-0000-000000000001'
  );

  select id into v_wine from public.wines order by created_at limit 1;
  if v_wine is null then
    raise exception 'La griglia A20 richiede almeno un vino del catalogo di bootstrap.';
  end if;

  insert into public.bottle_units (id, owner_id, wine_id)
  values (
    'a2000000-0000-0000-0000-000000000010',
    'a2000000-0000-0000-0000-000000000001',
    v_wine
  );

  insert into public.listings
    (id, slug, seller_id, bottle_unit_id, stato, prezzo_cents, published_at)
  values (
    'a2000000-0000-0000-0000-000000000011',
    'a20-annuncio-reporting',
    'a2000000-0000-0000-0000-000000000001',
    'a2000000-0000-0000-0000-000000000010',
    'attivo',
    12000,
    now()
  );

  insert into public.club_posts
    (id, club_slug, autore_id, tipo, titolo, corpo)
  values (
    'a2000000-0000-0000-0000-000000000012',
    'a20-club-reporting',
    'a2000000-0000-0000-0000-000000000001',
    'discussione',
    'Post A20',
    'Contenuto della fixture.'
  );

  insert into public.club_post_risposte
    (id, post_id, autore_id, corpo)
  values (
    'a2000000-0000-0000-0000-000000000013',
    'a2000000-0000-0000-0000-000000000012',
    'a2000000-0000-0000-0000-000000000003',
    'Risposta A20.'
  );
end
$fixture$;

-- 01: l'anonimo non attraversa la porta SECURITY DEFINER.
select pg_temp.esegui(
  'anon_club',
  $$select public.segnalazione_club_invia('a20-club-reporting', 'spam', '')$$,
  null,
  'anon'
);
select pg_temp.registra(
  1,
  'Un anonimo non segnala un Club',
  pg_temp.esito('anon_club') like '42501|%',
  'auth.uid() e il grant della funzione negano entrambi il percorso anonimo'
);

-- 02-06: tutti i bersagli pubblici usano le porte autorevoli esistenti.
select pg_temp.esegui_id(
  'report_listing',
  format(
    $$select public.segnalazione_invia('annuncio', %L, 'Annuncio A20', %L, '', '{}', null)$$,
    'a2000000-0000-0000-0000-000000000011',
    (select motivo from public.report_reasons where target_tipo = 'annuncio' order by ordine limit 1)
  ),
  'a2000000-0000-0000-0000-000000000002'
);
select pg_temp.registra(2, 'Un annuncio si segnala con il suo UUID reale',
  pg_temp.esito('report_listing') = 'NESSUN_ERRORE', 'segnalazione_invia resta la porta congelata');

select pg_temp.esegui_id(
  'report_profile',
  format(
    $$select public.segnalazione_invia('profilo', %L, 'a20_owner', %L, '', '{}', null)$$,
    'a2000000-0000-0000-0000-000000000001',
    (select motivo from public.report_reasons where target_tipo = 'profilo' order by ordine limit 1)
  ),
  'a2000000-0000-0000-0000-000000000002'
);
select pg_temp.registra(3, 'Un profilo si segnala con il suo user UUID reale',
  pg_temp.esito('report_profile') = 'NESSUN_ERRORE', 'nessun target utente sintetico');

select pg_temp.esegui_id(
  'report_club',
  $$select public.segnalazione_club_invia('a20-club-reporting', 'spam', 'Descrizione A20')$$,
  'a2000000-0000-0000-0000-000000000002'
);
select pg_temp.registra(4, 'Un Club si segnala con lo slug reale',
  pg_temp.esito('report_club') = 'NESSUN_ERRORE', 'porta stretta dedicata al solo Club diretto');

select pg_temp.esegui_id(
  'report_post',
  $$select public.segnalazione_invia('post', 'a2000000-0000-0000-0000-000000000012', 'Post A20', 'Disinformazione', '', '{}', 'a20-club-reporting')$$,
  'a2000000-0000-0000-0000-000000000002'
);
select pg_temp.registra(5, 'Un post Club si segnala con il suo UUID reale',
  pg_temp.esito('report_post') = 'NESSUN_ERRORE', 'regressione del percorso Fase 12c');

select pg_temp.esegui_id(
  'report_comment',
  $$select public.segnalazione_invia('commento', 'a2000000-0000-0000-0000-000000000013', 'Risposta A20', 'Spam', '', '{}', 'a20-club-reporting')$$,
  'a2000000-0000-0000-0000-000000000001'
);
select pg_temp.esegui(
  'club_invalid_reason',
  $$select public.segnalazione_club_invia('a20-club-reporting', 'Motivo inesistente', '')$$,
  'a2000000-0000-0000-0000-000000000002'
);
select pg_temp.registra(6, 'Commento reale e motivi Club chiusi restano verificati',
  pg_temp.esito('report_comment') = 'NESSUN_ERRORE'
  and pg_temp.esito('club_invalid_reason') like '22023|Motivo non ammesso%',
  'regressione Fase 12c e validazione sulla tabella report_reasons');

-- 07-09: esistenza e ownership restano risolte dal database.
select pg_temp.esegui(
  'club_missing',
  $$select public.segnalazione_club_invia('club-inesistente-a20', 'spam', '')$$,
  'a2000000-0000-0000-0000-000000000002'
);
select pg_temp.registra(7, 'Un Club inesistente non puo essere segnalato',
  pg_temp.esito('club_missing') like 'P0001|Club non trovato.%',
  'slug risolto esclusivamente dalla tabella clubs');

select pg_temp.esegui(
  'profile_self',
  format(
    $$select public.segnalazione_invia('profilo', %L, 'Me stesso', %L, '', '{}', null)$$,
    'a2000000-0000-0000-0000-000000000002',
    (select motivo from public.report_reasons where target_tipo = 'profilo' order by ordine limit 1)
  ),
  'a2000000-0000-0000-0000-000000000002'
);
select pg_temp.registra(8, 'Un profilo non segnala se stesso',
  pg_temp.esito('profile_self') like '22023|%', 'self-report verificato server-side');

select pg_temp.esegui(
  'club_owner',
  $$select public.segnalazione_club_invia('a20-club-reporting', 'spam', '')$$,
  'a2000000-0000-0000-0000-000000000001'
);
select pg_temp.registra(9, 'Il proprietario non segnala il proprio Club',
  pg_temp.esito('club_owner') like '22023|%', 'owner_id risolto dalla riga canonica');

-- 10: una seconda pratica attiva dello stesso reporter e bersaglio e respinta.
select pg_temp.esegui(
  'club_duplicate',
  $$select public.segnalazione_club_invia('a20-club-reporting', 'altro', '')$$,
  'a2000000-0000-0000-0000-000000000002'
);
select pg_temp.registra(10, 'Il doppione attivo sullo stesso Club e respinto',
  pg_temp.esito('club_duplicate') like 'P0001|Hai gia una segnalazione aperta%',
  'stati attivi: inviata, in_revisione, info_richieste');

-- 11-13: la coda Admin accetta un Club senza fabbricare UUID e pubblica metadati canonici.
select pg_temp.registra(11, 'La coda Club e visibile solo all Admin reale',
  pg_temp.leggi(
    format($$select count(*)::text from public.moderation_report_queue where id = %L$$, pg_temp.rif('report_club')),
    'a2000000-0000-0000-0000-000000000004',
    'authenticated'
  ) = '1'
  and pg_temp.leggi(
    $$select count(*)::text from public.moderation_report_queue$$,
    'a2000000-0000-0000-0000-000000000002',
    'authenticated'
  ) = '0',
  'riuso della coda esistente con porta role-scoped');

select pg_temp.registra(12, 'La coda Admin lascia nullo target_id per un Club diretto',
  pg_temp.leggi(
    format($$select (target_id is null)::text from public.moderation_report_queue where id = %L$$, pg_temp.rif('report_club')),
    'a2000000-0000-0000-0000-000000000004',
    'authenticated'
  ) = 'true',
  'nessun UUID sintetico');

select pg_temp.registra(13, 'Slug e label del Club sono quelli canonici del database',
  pg_temp.leggi(
    format($$select club_slug || '/' || target_label from public.reports where id = %L$$, pg_temp.rif('report_club'))
  ) = 'a20-club-reporting/A20 Club Canonico',
  'il client non fornisce target_label alla RPC Club');

-- 14-16: proiezioni private del reporter, eventi visibili e dati interni separati.
select pg_temp.registra(14, 'Le mie segnalazioni mostra al reporter solo le proprie pratiche',
  pg_temp.leggi(
    $$select (count(*) = 4)::text from public.my_reports$$,
    'a2000000-0000-0000-0000-000000000002',
    'authenticated'
  ) = 'true',
  'annuncio, profilo, Club e post appartengono allo stesso reporter');

select pg_temp.registra(15, 'Un altro utente non vede le pratiche del reporter',
  pg_temp.leggi(
    $$select count(*)::text from public.my_reports$$,
    'a2000000-0000-0000-0000-000000000003',
    'authenticated'
  ) = '0',
  'ownership applicata nella vista privata');

insert into public.report_events
  (report_id, visibile, testo, autore_id, autore_etichetta)
values
  (pg_temp.rif('report_club'), false, 'NOTA INTERNA A20',
   'a2000000-0000-0000-0000-000000000004', 'Moderazione');

select pg_temp.registra(16, 'Eventi interni e audit non entrano nella vista del reporter',
  pg_temp.leggi(
    format($$select count(*)::text from public.my_report_events where report_id = %L and testo = 'NOTA INTERNA A20'$$, pg_temp.rif('report_club')),
    'a2000000-0000-0000-0000-000000000002',
    'authenticated'
  ) = '0'
  and not exists (
    select 1 from information_schema.role_table_grants
    where table_schema = 'public' and table_name = 'audit_log'
      and grantee in ('anon', 'authenticated') and privilege_type = 'SELECT'
  ),
  'note interne e audit restano fuori dalla proiezione privata');

-- 17-18: nessuna DML diretta e privilegi della nuova porta ridotti al minimo.
select pg_temp.esegui(
  'direct_dml',
  $$insert into public.reports (codice, target_tipo, target_label, motivo, priorita, reporter_id, club_slug)
    values ('SEG-A20-DML', 'club', 'falso', 'spam', 'bassa',
            'a2000000-0000-0000-0000-000000000002', 'a20-club-reporting')$$,
  'a2000000-0000-0000-0000-000000000002'
);
select pg_temp.registra(17, 'Il client non inserisce direttamente in reports',
  pg_temp.esito('direct_dml') like '42501|permission denied%', 'scrittura solo via RPC controllata');

select pg_temp.registra(18, 'La RPC Club e chiusa a PUBLIC, anon e service_role',
  has_function_privilege('authenticated', 'public.segnalazione_club_invia(text,text,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.segnalazione_club_invia(text,text,text)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.segnalazione_club_invia(text,text,text)', 'EXECUTE'),
  'solo authenticated riceve EXECUTE');

-- 19: regressione D9. La porta congelata conserva il ramo recensione e il suo
-- bersaglio reale; questa BUILD non crea una seconda funzione ne una seconda coda.
select pg_temp.registra(19, 'Il percorso D9 delle recensioni resta nella RPC autorevole',
  exists (
    select 1 from public.report_reasons
    where target_tipo = 'recensione'
  )
  and exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'segnalazione_invia'
      and pg_get_functiondef(p.oid) ilike '%target_review_id%'
      and pg_get_functiondef(p.oid) ilike '%order_reviews%'
  ),
  'controprova strutturale sul percorso gia verificato dalla griglia D9');

-- Pulizia esplicita oltre al ROLLBACK finale, quindi verifica dei residui.
delete from public.reports
where reporter_id in (
  'a2000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000002',
  'a2000000-0000-0000-0000-000000000003'
);
delete from public.club_post_risposte where id = 'a2000000-0000-0000-0000-000000000013';
delete from public.club_posts where id = 'a2000000-0000-0000-0000-000000000012';
delete from public.listings where id = 'a2000000-0000-0000-0000-000000000011';
delete from public.bottle_units where id = 'a2000000-0000-0000-0000-000000000010';
delete from public.clubs where slug = 'a20-club-reporting';
delete from public.user_roles where user_id = 'a2000000-0000-0000-0000-000000000004';
delete from auth.users where id::text like 'a2000000-0000-0000-0000-00000000000%';

select pg_temp.registra(20, 'La pulizia non lascia residui A20',
  not exists (select 1 from public.reports where target_label like '%A20%')
  and not exists (select 1 from public.clubs where slug = 'a20-club-reporting')
  and not exists (select 1 from public.listings where id = 'a2000000-0000-0000-0000-000000000011')
  and not exists (select 1 from auth.users where id::text like 'a2000000-0000-0000-0000-00000000000%'),
  'pulizia esplicita; il rollback finale e una seconda cintura');

select n, caso, esito, dettaglio
from esiti_reporting_reclami
order by n;

select
  count(*) filter (where esito = 'PASSA') as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*) as totale
from esiti_reporting_reclami;

rollback;
