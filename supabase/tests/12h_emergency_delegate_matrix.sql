-- Matrice di privilegi del ruolo `emergency_delegate` (12h).
--
-- Prova che il delegato di emergenza abbia SOLO la capability di continuita:
-- pubblicare, modificare e ritirare il banner globale con URL della pagina di
-- stato, lasciando audit append-only. Per tutto il resto deve comportarsi
-- esattamente come un utente normale.
--
-- Esecuzione: SOLO su uno stack Supabase locale o su un branch usa e getta.
-- Il guard rifiuta qualunque database con un utente Auth reale (email non
-- `.test`): sulla produzione fallisce prima di scrivere. Tutto avviene in una
-- transazione chiusa da ROLLBACK: utenti, ruoli, segnalazione, Club e banner
-- di prova non sopravvivono all'esecuzione, nemmeno in caso di errore.
-- Nel gate CI la esegue `12g_ci_run.sh` prima delle fixture 12g.
--
-- Identita (prefisso 12ab0000-...):
--   01 admin   02 emergency_delegate   03 utente normale   04 proprietario dati
--   anon       nessun sub
-- Output: una riga per invariante `id, descrizione, passed, detail`; tutte
-- devono avere passed = t.

begin;

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12h: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  '00000000-0000-0000-0000-000000000000',
  ('12ab0000-0000-4000-8000-00000000000' || n)::uuid,
  'authenticated', 'authenticated',
  'u0' || n || '@grid-12h.test', '', now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('username', 'grid12h_u0' || n, 'dob', '1985-01-01'),
  now(), now(), '', '', '', ''
from generate_series(1, 4) as n;

insert into public.user_roles (user_id, role) values
  ('12ab0000-0000-4000-8000-000000000001', 'admin'),
  ('12ab0000-0000-4000-8000-000000000002', 'emergency_delegate');

-- Dati posseduti dall'utente 04: una segnalazione e una proposta Club in
-- attesa. Solo l'admin deve vederle nelle code; delegato e utente normale no.
insert into public.reports (
  codice, target_tipo, target_label, target_profile_id, motivo, priorita, reporter_id
)
select 'R-12H-0001', 'profilo', 'Profilo di prova 12h',
  '12ab0000-0000-4000-8000-000000000001', r.motivo, 'media',
  '12ab0000-0000-4000-8000-000000000004'
from public.report_reasons r
where r.target_tipo = 'profilo'
order by r.motivo
limit 1;

insert into public.clubs (slug, nome, descrizione, owner_id, approval_status)
values ('grid-12h-club', 'Club 12h', 'Proposta di prova della griglia 12h',
  '12ab0000-0000-4000-8000-000000000004', 'in_attesa');

create temp table esiti_12h (
  id int primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

-- Esegue p_sql come p_role con sub p_uid e restituisce 'ok' o lo SQLSTATE.
-- Con p_keep = false gli effetti sono annullati (savepoint), cosi ogni prova
-- negativa o di confronto e indipendente dalle altre.
create function pg_temp.prova(
  p_uid uuid, p_role text, p_sql text, p_keep boolean default false
) returns text
language plpgsql as $f$
declare v text;
begin
  begin
    perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
    perform set_config('request.jwt.claims',
      jsonb_build_object('sub', p_uid, 'role', p_role)::text, true);
    execute format('set local role %I', p_role);
    execute p_sql;
    execute 'reset role';
    if not p_keep then
      raise exception using errcode = 'P0001', message = '__12h_ok__';
    end if;
    v := 'ok';
  exception when others then
    v := case when sqlerrm = '__12h_ok__' then 'ok' else sqlstate end;
  end;
  execute 'reset role';
  return v;
end $f$;

-- Conta le righe di una relazione viste da p_role/p_uid, o lo SQLSTATE.
create function pg_temp.conta(p_uid uuid, p_role text, p_rel text)
returns text
language plpgsql as $f$
declare v bigint;
begin
  begin
    perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
    perform set_config('request.jwt.claims',
      jsonb_build_object('sub', p_uid, 'role', p_role)::text, true);
    execute format('set local role %I', p_role);
    execute format('select count(*) from %s', p_rel) into v;
    execute 'reset role';
    return v::text;
  exception when others then
    return sqlstate;
  end;
end $f$;

-- Chiamata con argomenti NULL tipizzati: nessuna ambiguita tra overload.
create function pg_temp.chiamata_nulla(p_oid oid)
returns text
language sql stable as $f$
  select format('select %s(%s)', p_oid::regproc::text, coalesce((
    select string_agg(format('null::%s', format_type(t, null)), ', ' order by o)
    from unnest((select proargtypes::oid[] from pg_proc where oid = p_oid))
      with ordinality as a(t, o)
  ), ''));
$f$;

do $$
declare
  c_admin constant uuid := '12ab0000-0000-4000-8000-000000000001';
  c_deleg constant uuid := '12ab0000-0000-4000-8000-000000000002';
  c_user  constant uuid := '12ab0000-0000-4000-8000-000000000003';
  c_msg   constant text := 'Prova 12h: servizio in verifica, aggiornamenti sulla pagina di stato.';
  c_url   constant text := 'https://status.vineawineclub.com';
  v text; v2 text; v3 text; v_n bigint; v_m bigint; v_list text;
begin
  -- 1-3. Catalogo: il ruolo compare in una sola porta e nessun controllo di
  -- ruolo e generico.
  select string_agg(n.nspname || '.' || p.proname, ', ' order by 1) into v_list
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname not in ('pg_catalog', 'information_schema')
    and p.prokind = 'f' and p.prosrc ilike '%emergency_delegate%';
  select count(*) into v_n from pg_policies
  where coalesce(qual, '') || coalesce(with_check, '') ilike '%emergency_delegate%';
  select count(*) into v_m from pg_views
  where schemaname not in ('pg_catalog', 'information_schema')
    and definition ilike '%emergency_delegate%';
  insert into esiti_12h values (1,
    'emergency_delegate compare solo in public.incident_notice_set',
    v_list = 'public.incident_notice_set' and v_n = 0 and v_m = 0,
    format('funzioni=%s policy=%s viste=%s', coalesce(v_list, '-'), v_n, v_m));

  select string_agg(n.nspname || '.' || p.proname, ', ') into v_list
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and p.prokind = 'f'
    and p.prosrc ilike '%user_roles%'
    and p.prosrc !~* 'role\s*=\s*''(admin|moderator|seller_enabled|emergency_delegate)'''
    and p.prosrc !~* 'has_role\('
    and not (n.nspname = 'public' and p.proname = 'has_role');
  -- has_role e il predicato parametrico: ogni suo uso deve passare un ruolo
  -- letterale, mai un'espressione.
  select count(*) into v_m from (
    select p.prosrc as src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private') and p.prokind = 'f'
    union all
    select coalesce(qual, '') || ' ' || coalesce(with_check, '') from pg_policies
    union all
    select definition from pg_views where schemaname = 'public'
  ) s, regexp_matches(s.src, 'has_role\(([^,]+),\s*([^)]*)\)', 'g') m
  where m[2] !~ '^''[a-z_]+''(::text)?$';
  select count(*) into v_n from pg_policies
  where coalesce(qual, '') || coalesce(with_check, '') ilike '%user_roles%'
    and coalesce(qual, '') || coalesce(with_check, '') !~* '''(admin|moderator|seller_enabled)'''
    and not (tablename = 'user_roles');
  insert into esiti_12h values (2,
    'nessun controllo di ruolo generico su user_roles (qualsiasi ruolo = privilegio)',
    v_list is null and v_n = 0 and v_m = 0,
    format('funzioni=%s policy=%s has_role_non_letterali=%s',
      coalesce(v_list, '-'), v_n, v_m));

  select string_agg(p.proname, ', ') into v_list
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f'
    and (has_function_privilege('authenticated', p.oid, 'execute')
      or has_function_privilege('anon', p.oid, 'execute'))
    and p.prosrc ~* '(insert\s+into|update|delete\s+from)\s+public\.user_roles';
  insert into esiti_12h values (3,
    'nessuna RPC per anon/authenticated scrive user_roles',
    v_list is null, coalesce(v_list, 'nessuna'));

  -- 4. Nessun grant di scrittura diretto sulle tabelle sensibili.
  select string_agg(t || ':' || priv, ', ') into v_list
  from unnest(array['public.user_roles', 'public.incident_notices',
    'public.incident_notice_events', 'public.marketplace_config',
    'public.payments', 'public.payouts', 'public.orders',
    'public.dispute_admin_notes', 'public.dispute_decisions']) t,
    unnest(array['insert', 'update', 'delete']) priv
  where has_table_privilege('authenticated', t, priv)
     or has_table_privilege('anon', t, priv);
  insert into esiti_12h values (4,
    'nessuna scrittura diretta su ruoli, banner, config commerciale, pagamenti, note',
    v_list is null, coalesce(v_list, 'nessun grant'));

  -- 5-8. Positivi del delegato: pubblica, modifica, ritira; audit append.
  v := pg_temp.prova(c_deleg, 'authenticated', format(
    'select public.incident_notice_set(%L, %L, %L, true)', 'incidente', c_msg, c_url), true);
  v2 := pg_temp.conta(null, 'anon', 'public.public_incident_notice where status_url = '
    || quote_literal(c_url));
  insert into esiti_12h values (5,
    'delegato pubblica il banner con URL della status page, visibile ad anon',
    v = 'ok' and v2 = '1', format('rpc=%s anon_vede=%s', v, v2));

  v := pg_temp.prova(c_deleg, 'authenticated', format(
    'select public.incident_notice_set(%L, %L, %L, true)', 'degrado',
    c_msg || ' Aggiornamento.', c_url), true);
  v2 := pg_temp.conta(null, 'anon', 'public.public_incident_notice where kind = ''degrado''');
  insert into esiti_12h values (6, 'delegato modifica il banner',
    v = 'ok' and v2 = '1', format('rpc=%s anon_vede=%s', v, v2));

  v := pg_temp.prova(c_deleg, 'authenticated', format(
    'select public.incident_notice_set(%L, %L, %L, false)', 'degrado', c_msg, c_url), true);
  v2 := pg_temp.conta(null, 'anon', 'public.public_incident_notice');
  insert into esiti_12h values (7, 'delegato ritira il banner',
    v = 'ok' and v2 = '0', format('rpc=%s anon_vede=%s', v, v2));

  select count(*) into v_n from public.incident_notice_events where actor_id = c_deleg;
  select count(*) into v_m from public.incident_notice_events
    where actor_id = c_deleg and active is false;
  insert into esiti_12h values (8,
    'ogni azione del delegato lascia una riga di audit con il suo id',
    v_n = 3 and v_m = 1, format('eventi=%s ritiri=%s', v_n, v_m));

  -- 9. Audit append-only anche per il proprietario del database.
  v := 'no-deny';
  begin
    update public.incident_notice_events set message = 'x' where actor_id = c_deleg;
  exception when insufficient_privilege then v := '42501';
  end;
  v2 := 'no-deny';
  begin
    delete from public.incident_notice_events where actor_id = c_deleg;
  exception when insufficient_privilege then v2 := '42501';
  end;
  insert into esiti_12h values (9,
    'registro incidenti append-only (UPDATE/DELETE rifiutati anche al proprietario)',
    v = '42501' and v2 = '42501', format('update=%s delete=%s', v, v2));

  -- 10. Validazione server-side resta attiva per il delegato.
  v := pg_temp.prova(c_deleg, 'authenticated', format(
    'select public.incident_notice_set(%L, %L, %L, true)', 'incidente', c_msg,
    'http://status.vineawineclub.com'));
  v2 := pg_temp.prova(c_deleg, 'authenticated', format(
    'select public.incident_notice_set(%L, %L, null, true)', 'amministrazione', c_msg));
  insert into esiti_12h values (10,
    'URL non HTTPS e tipo sconosciuto rifiutati anche al delegato',
    v = '22023' and v2 = '22023', format('http=%s tipo=%s', v, v2));

  -- 11. Controlli di autorizzazione della porta.
  v := pg_temp.prova(c_admin, 'authenticated', format(
    'select public.incident_notice_set(%L, %L, null, true)', 'manutenzione', c_msg));
  v2 := pg_temp.prova(c_user, 'authenticated', format(
    'select public.incident_notice_set(%L, %L, null, true)', 'manutenzione', c_msg));
  v3 := pg_temp.prova(null, 'anon', format(
    'select public.incident_notice_set(%L, %L, null, true)', 'manutenzione', c_msg));
  insert into esiti_12h values (11,
    'banner: admin ok, utente normale e anon rifiutati',
    v = 'ok' and v2 = '42501' and v3 = '42501',
    format('admin=%s utente=%s anon=%s', v, v2, v3));

  -- 12. Accesso diretto alle tabelle del banner negato al delegato.
  v := pg_temp.prova(c_deleg, 'authenticated', 'select count(*) from public.incident_notice_events');
  v2 := pg_temp.prova(c_deleg, 'authenticated',
    'update public.incident_notices set active = false');
  v3 := pg_temp.prova(c_deleg, 'authenticated', format(
    'insert into public.incident_notice_events (actor_id, kind, message, active) values (%L, %L, %L, true)',
    c_deleg, 'incidente', c_msg));
  insert into esiti_12h values (12,
    'delegato senza accesso diretto a tabella banner e registro',
    v = '42501' and v2 = '42501' and v3 = '42501',
    format('select_eventi=%s update_banner=%s insert_eventi=%s', v, v2, v3));

  -- 13. Il delegato legge solo il proprio ruolo (gate di /continuita).
  v := pg_temp.conta(c_deleg, 'authenticated',
    'public.user_roles where role = ''emergency_delegate''');
  v2 := pg_temp.conta(c_deleg, 'authenticated', 'public.user_roles');
  v3 := pg_temp.conta(c_user, 'authenticated', 'public.user_roles');
  insert into esiti_12h values (13,
    'delegato legge solo il proprio ruolo; utente normale nessuno',
    v = '1' and v2 = '1' and v3 = '0',
    format('proprio=%s visibili=%s utente=%s', v, v2, v3));

  -- 14. Nessuna auto-promozione o gestione ruoli.
  v := pg_temp.prova(c_deleg, 'authenticated', format(
    'insert into public.user_roles (user_id, role) values (%L, %L)', c_deleg, 'admin'));
  v2 := pg_temp.prova(c_deleg, 'authenticated', format(
    'insert into public.user_roles (user_id, role) values (%L, %L)', c_user, 'emergency_delegate'));
  v3 := pg_temp.prova(c_deleg, 'authenticated', 'delete from public.user_roles');
  insert into esiti_12h values (14,
    'delegato non si promuove admin, non nomina altri delegati, non rimuove ruoli',
    v = '42501' and v2 = '42501' and v3 = '42501',
    format('self_admin=%s nomina=%s delete=%s', v, v2, v3));

  -- 15. Colonne di moderazione del profilo e config commerciale.
  v := pg_temp.prova(c_deleg, 'authenticated',
    'update public.profiles set stato_utente = stato_utente');
  v2 := pg_temp.prova(c_deleg, 'authenticated',
    'update public.marketplace_config set nota = nota');
  v3 := pg_temp.prova(c_deleg, 'authenticated', 'select count(*) from public.dispute_admin_notes');
  insert into esiti_12h values (15,
    'delegato non tocca stato utente, config commerciale, note private contestazioni',
    v = '42501' and v2 = '42501' and v3 = '42501',
    format('stato_utente=%s config=%s note=%s', v, v2, v3));
end $$;

-- 16. Ogni RPC protetta da un controllo admin (diretto o via helper) rifiuta
-- il delegato con 42501, mentre l'admin supera il controllo (controllo
-- positivo: la negazione dipende dal ruolo, non da dati mancanti).
with helper as (
  select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.prokind = 'f'
    and p.prosrc ~* '(has_role\([^,]+,\s*''admin''|role\s*=\s*''admin'')'
), porte as (
  select p.oid, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f'
    and p.proname <> 'incident_notice_set'
    and has_function_privilege('authenticated', p.oid, 'execute')
    and (p.prosrc ~* '(has_role\([^,]+,\s*''admin''|role\s*=\s*''admin'')'
      or exists (select 1 from helper h where p.prosrc ~ ('private\.' || h.proname || '\(')))
), esiti as (
  select proname,
    pg_temp.prova('12ab0000-0000-4000-8000-000000000002', 'authenticated', pg_temp.chiamata_nulla(oid)) d,
    pg_temp.prova('12ab0000-0000-4000-8000-000000000001', 'authenticated', pg_temp.chiamata_nulla(oid)) m
  from porte
)
insert into esiti_12h
select 16,
  'ogni RPC riservata agli admin rifiuta il delegato (42501) e non l''admin',
  count(*) >= 17 and count(*) filter (where d = '42501' and m <> '42501') = count(*),
  format('porte=%s negate_al_delegato=%s eccezioni=%s', count(*),
    count(*) filter (where d = '42501' and m <> '42501'),
    coalesce(string_agg(proname || ':' || d || '/' || m, ', ')
      filter (where not (d = '42501' and m <> '42501')), 'nessuna'))
from esiti;

-- 17. Su tutte le altre RPC eseguibili da authenticated il delegato ha lo
-- stesso esito di un utente normale.
with rpc as (
  select p.oid, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f'
    and p.prorettype <> 'trigger'::regtype
    and p.proname <> 'incident_notice_set'
    and has_function_privilege('authenticated', p.oid, 'execute')
), esiti as (
  select proname,
    pg_temp.prova('12ab0000-0000-4000-8000-000000000002', 'authenticated', pg_temp.chiamata_nulla(oid)) d,
    pg_temp.prova('12ab0000-0000-4000-8000-000000000003', 'authenticated', pg_temp.chiamata_nulla(oid)) u
  from rpc
)
insert into esiti_12h
select 17,
  'su ogni altra RPC il delegato ha lo stesso esito di un utente normale',
  count(*) >= 80 and count(*) filter (where d is distinct from u) = 0,
  format('rpc=%s differenze=%s', count(*),
    coalesce(string_agg(proname || ':' || d || '/' || u, ', ')
      filter (where d is distinct from u), 'nessuna'))
from esiti;

-- 18. Su ogni tabella/vista leggibile da authenticated il delegato vede
-- quanto un utente normale; l'admin vede in piu le code seminate.
with rel as (
  select format('%I.%I', n.nspname, c.relname) r
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'storage') and c.relkind in ('r', 'v', 'm', 'p')
    and has_table_privilege('authenticated', c.oid, 'select')
), esiti as (
  select r,
    pg_temp.conta('12ab0000-0000-4000-8000-000000000002', 'authenticated', r) d,
    pg_temp.conta('12ab0000-0000-4000-8000-000000000003', 'authenticated', r) u,
    pg_temp.conta('12ab0000-0000-4000-8000-000000000001', 'authenticated', r) m
  from rel
)
insert into esiti_12h
select 18,
  'su ogni tabella/vista il delegato vede quanto un utente normale',
  count(*) >= 40
    and count(*) filter (where d is distinct from u) = 0
    and bool_and(m = '1') filter (where r in (
      'public.moderation_report_queue', 'public.moderation_club_proposals'))
    and bool_and(d = '0') filter (where r in (
      'public.moderation_report_queue', 'public.moderation_club_proposals')),
  format('relazioni=%s differenze=%s code_admin(m)=%s', count(*),
    coalesce(string_agg(r || ':' || d || '/' || u, ', ')
      filter (where d is distinct from u), 'nessuna'),
    string_agg(r || '=' || m, ', ') filter (where r in (
      'public.moderation_report_queue', 'public.moderation_club_proposals')))
from esiti;

select id, descrizione, passed, detail from esiti_12h order by id;

rollback;
