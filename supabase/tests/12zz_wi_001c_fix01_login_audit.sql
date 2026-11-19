-- WI-001C-FIX-01 — griglia 12zz: audit del LOGIN di connessione dell'importatore su RUOLI REALI (I-2).
--
-- SOLO stack Supabase locale/effimero. Tutto vive nella transazione (ruoli compresi) e sparisce con ROLLBACK; nessun accesso a
-- database remoti, nessuna password. Il testo della query è IDENTICO a LOGIN_AUDIT_SQL di tools/wine-catalog/lib/cloud-guards.mjs
-- (un test Node lo verifica): qui è provato contro un vero grafo di appartenenze; il lato JavaScript (evaluateLoginAudit) trasforma
-- l'esito in rifiuto ed è provato in tools/wine-catalog/test/cloud-fix01.test.mjs.
--
-- Prova: un login dedicato raggiunge SOLO catalog_loader; appartenenza indiretta (anche a tre salti), ruoli con poteri, ADMIN OPTION,
-- grant diretti (schema, tabella, funzione), proprietà di oggetti e login inesistente sono tutti visibili all'audit.
begin;

\set ON_ERROR_STOP on

create temp table esiti_12zz (id text, descrizione text, passed boolean, detail text);
grant all on esiti_12zz to public;

create function pg_temp.rec(p_id text, p_desc text, p_ok boolean, p_detail text default '')
returns void language sql as
$$ insert into esiti_12zz values (p_id, p_desc, coalesce(p_ok, false), p_detail) $$;

create function pg_temp.audit(name) returns jsonb language sql as
$q$with recursive me as (
  select oid, rolname, rolsuper, rolbypassrls, rolcreaterole, rolcreatedb, rolreplication, rolcanlogin from pg_roles where rolname = $1::name
), reach(roleid, admin, depth) as (
  select m.roleid, m.admin_option, 1 from pg_auth_members m join me on m.member = me.oid
  union
  select m.roleid, m.admin_option or r.admin, r.depth + 1 from reach r join pg_auth_members m on m.member = r.roleid where r.depth < 20
)
select jsonb_build_object(
  'login_found', exists (select 1 from me),
  'login_can_login', coalesce((select rolcanlogin from me), false),
  'login_powers', coalesce((select rolsuper or rolbypassrls or rolcreaterole or rolcreatedb or rolreplication from me), false),
  'reachable', coalesce((select jsonb_agg(distinct x.rolname order by x.rolname) from reach r join pg_roles x on x.oid = r.roleid), '[]'::jsonb),
  'powerful', coalesce((select jsonb_agg(distinct x.rolname order by x.rolname) from reach r join pg_roles x on x.oid = r.roleid
                         where x.rolsuper or x.rolbypassrls or x.rolcreaterole or x.rolcreatedb or x.rolreplication), '[]'::jsonb),
  'admin_over', coalesce((select jsonb_agg(distinct x.rolname order by x.rolname) from reach r join pg_roles x on x.oid = r.roleid where r.admin), '[]'::jsonb),
  'direct_grants',
    (select count(*) from pg_class c cross join lateral aclexplode(c.relacl) a, me where a.grantee = me.oid)
  + (select count(*) from pg_proc p cross join lateral aclexplode(p.proacl) a, me where a.grantee = me.oid)
  + (select count(*) from pg_namespace n cross join lateral aclexplode(n.nspacl) a, me where a.grantee = me.oid)
  + (select count(*) from pg_attribute t cross join lateral aclexplode(t.attacl) a, me where t.attacl is not null and a.grantee = me.oid)
  + (select count(*) from pg_database d cross join lateral aclexplode(d.datacl) a, me where a.grantee = me.oid and a.privilege_type <> 'CONNECT'),
  'owned_objects',
    (select count(*) from pg_class c, me where c.relowner = me.oid)
  + (select count(*) from pg_proc p, me where p.proowner = me.oid)
  + (select count(*) from pg_namespace n, me where n.nspowner = me.oid)
  + (select count(*) from pg_database d, me where d.datdba = me.oid),
  'db_create', coalesce(case when exists (select 1 from me) then has_database_privilege($1::name, current_database(), 'CREATE') end, false),
  'public_create', coalesce(case when exists (select 1 from me) then has_schema_privilege($1::name, 'public', 'CREATE') end, false),
  'catalog_create', coalesce(case when exists (select 1 from me) then has_schema_privilege($1::name, 'catalog', 'CREATE') end, false)
) as audit$q$;

-- ruoli di prova (NOLOGIN dove non serve; i login sono solo fixture della transazione)
create role fx12zz_ok login;
create role fx12zz_mid nologin;
create role fx12zz_indirect login;
create role fx12zz_deep login;
create role fx12zz_a nologin;
create role fx12zz_b nologin;
create role fx12zz_power nologin createdb;
create role fx12zz_viapower login;
create role fx12zz_admin login;
create role fx12zz_grants login;
create role fx12zz_fn login;
create role fx12zz_owner login;
create role fx12zz_createdb login createdb;

grant catalog_loader to fx12zz_ok;
-- indiretta: login → mid → catalog_curator
grant catalog_loader to fx12zz_indirect;
grant fx12zz_mid to fx12zz_indirect;
grant catalog_curator to fx12zz_mid;
-- a tre salti: login → a → b → catalog_curator
grant catalog_loader to fx12zz_deep;
grant fx12zz_a to fx12zz_deep;
grant fx12zz_b to fx12zz_a;
grant catalog_curator to fx12zz_b;
-- ruolo con poteri raggiunto per via indiretta
grant catalog_loader to fx12zz_viapower;
grant fx12zz_power to fx12zz_viapower;
-- ADMIN OPTION sul caricatore
grant catalog_loader to fx12zz_admin with admin option;
-- grant diretti al login
grant catalog_loader to fx12zz_grants;
grant usage on schema catalog to fx12zz_grants;
grant select on catalog.sources to fx12zz_grants;
grant catalog_loader to fx12zz_fn;
grant execute on function catalog.fold_text(text) to fx12zz_fn;
-- proprietà
grant catalog_loader to fx12zz_owner;
create table public.fx12zz_owned (id int);
create temp table fx12zz_flags (k text primary key, v boolean);
grant all on fx12zz_flags to public;
-- cambiare proprietario richiede di poter assumere il ruolo di destinazione: sul ruolo non superuser di alcuni stack (PostgreSQL 16+,
-- CREATEROLE senza SET) può non essere consentito. In quel caso il caso A08 è segnalato come non applicabile, non come fallito.
do $$ begin
  alter table public.fx12zz_owned owner to fx12zz_owner;
  insert into fx12zz_flags values ('owner_changed', true);
exception when insufficient_privilege then insert into fx12zz_flags values ('owner_changed', false); end $$;

do $$
declare
  a jsonb;
begin
  a := pg_temp.audit('fx12zz_ok');
  perform pg_temp.rec('A01', 'login dedicato: raggiunge SOLO catalog_loader, nessun potere, nessun grant diretto, nessuna proprietà, nessuna creazione',
    a -> 'login_found' = 'true'::jsonb and a -> 'reachable' = '["catalog_loader"]'::jsonb and a -> 'powerful' = '[]'::jsonb
    and a -> 'admin_over' = '[]'::jsonb and (a ->> 'direct_grants')::int = 0 and (a ->> 'owned_objects')::int = 0
    and a -> 'login_powers' = 'false'::jsonb and a -> 'public_create' = 'false'::jsonb and a -> 'catalog_create' = 'false'::jsonb, a::text);

  a := pg_temp.audit('fx12zz_indirect');
  perform pg_temp.rec('A02', 'appartenenza INDIRETTA (login → intermedio → catalog_curator): catalog_curator è raggiungibile e visibile all''audit',
    a -> 'reachable' @> '["catalog_curator", "fx12zz_mid", "catalog_loader"]'::jsonb, a::text);

  a := pg_temp.audit('fx12zz_deep');
  perform pg_temp.rec('A03', 'appartenenza a TRE salti (login → a → b → catalog_curator) visibile all''audit',
    a -> 'reachable' @> '["catalog_curator", "fx12zz_a", "fx12zz_b"]'::jsonb, a::text);

  a := pg_temp.audit('fx12zz_viapower');
  perform pg_temp.rec('A04', 'ruolo con CREATEDB raggiunto per via indiretta: segnalato come ruolo con poteri',
    a -> 'powerful' @> '["fx12zz_power"]'::jsonb, a::text);

  a := pg_temp.audit('fx12zz_admin');
  perform pg_temp.rec('A05', 'ADMIN OPTION su catalog_loader: il login potrebbe concedere il ruolo ad altri (escalation) ed è segnalato',
    a -> 'admin_over' = '["catalog_loader"]'::jsonb, a::text);

  a := pg_temp.audit('fx12zz_grants');
  perform pg_temp.rec('A06', 'grant diretti al login (USAGE sullo schema catalog, SELECT su una tabella): contati e segnalati',
    (a ->> 'direct_grants')::int >= 2, a::text);

  a := pg_temp.audit('fx12zz_fn');
  perform pg_temp.rec('A07', 'EXECUTE concesso direttamente al login su una funzione: contato', (a ->> 'direct_grants')::int >= 1, a::text);

  a := pg_temp.audit('fx12zz_owner');
  perform pg_temp.rec('A08', 'oggetti posseduti dal login: contati (il proprietario ha tutti i privilegi sull''oggetto)',
    (a ->> 'owned_objects')::int >= 1 or not (select v from fx12zz_flags where k = 'owner_changed'), a::text);

  a := pg_temp.audit('fx12zz_createdb');
  perform pg_temp.rec('A09', 'login con CREATEDB: login_powers = true', a -> 'login_powers' = 'true'::jsonb, a::text);

  a := pg_temp.audit('fx12zz_inesistente');
  perform pg_temp.rec('A10', 'login inesistente: login_found = false (l''importazione si rifiuta)', a -> 'login_found' = 'false'::jsonb, a::text);

  a := pg_temp.audit('catalog_loader');
  perform pg_temp.rec('A11', 'il ruolo catalog_loader stesso (NOLOGIN) non è un login ammesso: login_can_login = false', a -> 'login_can_login' = 'false'::jsonb, a::text);

  a := pg_temp.audit('catalog_curator');
  perform pg_temp.rec('A12', 'catalog_curator non raggiunge catalog_loader: un login curatore non è un caricatore', not (a -> 'reachable' @> '["catalog_loader"]'::jsonb), a::text);
end $$;

-- conteggio atteso: nessun caso saltato in silenzio
select pg_temp.rec('A13', 'la griglia ha eseguito tutti i 12 casi A01..A12', (select count(*) from esiti_12zz) = 12);

select id, descrizione, passed, detail from esiti_12zz order by id;

rollback;
