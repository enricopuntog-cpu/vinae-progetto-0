-- VPM-018-DB-GRID-02 (griglia 12zv): controllo globale di ogni funzione SECURITY DEFINER
-- di `public` e `private` (GAP-010).
--
-- Le griglie di dominio controllano le funzioni del proprio dominio: nessuna vedeva una
-- funzione nuova di un altro. Qui gli elenchi sono chiusi per `anon` e per `private`, e il rosso
-- obbliga a dichiarare una porta nuova. Le oltre 250 porte di `public` per `authenticated` non
-- hanno un elenco: per loro il caso 14 vieta un parametro che indichi un altro utente, salvo
-- quelle dichiarate. Vale solo per lo stack effimero: la griglia crea funzioni di prova.
--
-- SOLO stack Supabase locale/effimero. I controlli negativi creano funzioni di prova nella
-- transazione: spariscono con ROLLBACK.
--
-- Caso «LIMITE NOTO»: descrive un difetto documentato in docs/VPM_018_DB_GRID_02.md, non una
-- proprieta' desiderata. Quando viene corretto il caso diventa rosso e va aggiornato.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email is null or email not like '%.test') then
    raise exception 'Guard 12zv: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12zv (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12zv (id, descrizione, passed, detail)
  values (p_id, p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

-- Perimetro unico: funzioni nostre, non quelle di un'estensione.
create temp view definer_12zv as
  select p.oid, n.nspname as schema, p.oid::regprocedure::text as firma, p.proconfig, p.proacl, p.proowner
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where p.prosecdef
    and n.nspname in ('public', 'private')
    and not exists (select 1 from pg_depend d
                    where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e');

create function pg_temp.senza_search_path() returns text[] language sql as $f$
  select coalesce(array_agg(firma order by firma), '{}') from definer_12zv d
  where not exists (select 1 from unnest(coalesce(d.proconfig, '{}')) c where c like 'search_path=%');
$f$;

create function pg_temp.search_path_non_vuoto() returns text[] language sql as $f$
  select coalesce(array_agg(firma order by firma), '{}') from definer_12zv d
  where exists (select 1 from unnest(coalesce(d.proconfig, '{}')) c
                where c like 'search_path=%' and c <> 'search_path=""');
$f$;

create function pg_temp.a_public(p_schema text) returns text[] language sql as $f$
  select coalesce(array_agg(firma order by firma), '{}') from definer_12zv d
  where d.schema = p_schema
    and exists (select 1 from aclexplode(coalesce(d.proacl, acldefault('f', d.proowner))) a
                where a.grantee = 0 and a.privilege_type = 'EXECUTE');
$f$;

create function pg_temp.eseguibili(p_ruolo text, p_schema text) returns text[] language sql as $f$
  select coalesce(array_agg(firma order by firma), '{}') from definer_12zv d
  where d.schema = p_schema and has_function_privilege(p_ruolo, d.oid, 'EXECUTE');
$f$;

-- Confronto fra elenchi: il dettaglio dice cosa manca e cosa e' in piu'.
create function pg_temp.differenza(p_trovati text[], p_attesi text[]) returns text language sql as $f$
  select concat_ws(' | ',
    'in piu: ' || nullif(array_to_string(array(select unnest(p_trovati) except select unnest(p_attesi) order by 1), ', '), ''),
    'mancanti: ' || nullif(array_to_string(array(select unnest(p_attesi) except select unnest(p_trovati) order by 1), ', '), ''));
$f$;

create function pg_temp.confronta(p_id integer, p_descrizione text, p_trovati text[], p_attesi text[])
returns void language sql as $f$
  select pg_temp.registra(p_id, p_descrizione,
    (select array_agg(x order by x) from unnest(p_trovati) x) is not distinct from
    (select array_agg(x order by x) from unnest(p_attesi) x),
    pg_temp.differenza(p_trovati, p_attesi));
$f$;

-- 1. Il perimetro non e' vuoto: altrimenti tutto il resto passerebbe a vuoto.
select pg_temp.registra(1, 'perimetro: almeno 400 funzioni SECURITY DEFINER esaminate',
  (select count(*) from definer_12zv) >= 400, (select count(*)::text from definer_12zv));

-- 2-3. search_path.
select pg_temp.confronta(2, 'ogni funzione ha un search_path fissato',
  pg_temp.senza_search_path(), '{}');
select pg_temp.confronta(3, 'search_path non vuoto solo nell''elenco chiuso',
  pg_temp.search_path_non_vuoto(),
  array['club_crea(text,text,text[],text,text)', 'handle_new_user()', 'rls_auto_enable()']);

-- 4. Quell'elenco resta sicuro solo se i ruoli client non possono creare oggetti negli schemi.
select pg_temp.registra(4, 'anon e authenticated non creano oggetti in public e private',
  not (has_schema_privilege('anon', 'public', 'CREATE') or has_schema_privilege('authenticated', 'public', 'CREATE')
       or has_schema_privilege('anon', 'private', 'CREATE') or has_schema_privilege('authenticated', 'private', 'CREATE')));

-- 5-6. EXECUTE a PUBLIC.
select pg_temp.confronta(5, 'nessuna funzione di public e eseguibile da PUBLIC',
  pg_temp.a_public('public'), '{}');
select pg_temp.confronta(6, 'LIMITE NOTO R-DB-01: in private solo queste 7 hanno EXECUTE a PUBLIC',
  pg_temp.a_public('private'),
  array['private.club_post_owner_only_guard()', 'private.club_risposta_owner_only_guard()',
        'private.disputes_invariante()', 'private.orders_tracking_sync()', 'private.seller_enabled_sync()',
        'private.sommelier_contesto_leggi(uuid,text,integer)',
        'private.sommelier_scambio_registra(uuid,text,text,text)']);

-- 7-9. Elenchi chiusi per ruolo. In `private` non esposto da PostgREST, ma lo schema concede USAGE.
select pg_temp.confronta(7, 'private eseguibile da anon: elenco chiuso',
  pg_temp.eseguibili('anon', 'private'),
  array['private.accessorio_media_pubblica(text)', 'private.annuncio_accessorio_media_pubblica(text)',
        'private.cantina_accessorio_media_pubblica(text)', 'private.vinea_check_request()',
        'private.club_post_owner_only_guard()', 'private.club_risposta_owner_only_guard()',
        'private.disputes_invariante()', 'private.orders_tracking_sync()', 'private.seller_enabled_sync()',
        'private.sommelier_contesto_leggi(uuid,text,integer)',
        'private.sommelier_scambio_registra(uuid,text,text,text)']);

select pg_temp.confronta(8, 'private eseguibile da authenticated: elenco chiuso',
  pg_temp.eseguibili('authenticated', 'private'),
  array['private.accessori_e_admin()', 'private.accessori_prova_caricamento_ammesso(text)',
        'private.accessori_prova_lettura_ammessa(text)', 'private.accessorio_in_gestione(text)',
        'private.accessorio_media_cancellabile(text)', 'private.accessorio_media_pubblica(text)',
        'private.annuncio_accessorio_media_moderabile(text)', 'private.annuncio_accessorio_media_pubblica(text)',
        'private.cantina_accessorio_media_cancellabile(text)', 'private.cantina_accessorio_media_pubblica(text)',
        'private.cantina_accessorio_proprio(text)', 'private.partner_media_cancellabile_dal_chiamante(text)',
        'private.partner_vetrina_cartella_del_chiamante(text)', 'private.prova_contestazione_depositata(text)',
        'private.prova_ordine_depositata(text)', 'private.qualifica_in_bozza_del_chiamante(text)',
        'private.vinea_check_request()',
        'private.club_post_owner_only_guard()', 'private.club_risposta_owner_only_guard()',
        'private.disputes_invariante()', 'private.orders_tracking_sync()', 'private.seller_enabled_sync()',
        'private.sommelier_contesto_leggi(uuid,text,integer)',
        'private.sommelier_scambio_registra(uuid,text,text,text)']);

select pg_temp.confronta(9, 'public eseguibile da anon: elenco chiuso',
  pg_temp.eseguibili('anon', 'public'),
  array['accessori_categorie_elenca(boolean)', 'accessori_dettaglio(text,boolean)', 'accessori_disponibilita(uuid)',
        'accessori_elenca(text,boolean)', 'accessori_venditore_pubblico(uuid)', 'acquisto_da_venditore_disponibile(uuid)',
        'annunci_accessori_pubblici_elenca(text,integer,integer)', 'annunci_accessori_pubblico_dettaglio(uuid)',
        'annuncio_accessorio_logistica_preventivo(uuid,integer,text,boolean)',
        'beta_validation_event_record(uuid,text,text,text,jsonb)', 'beta_validation_qv2_answer(uuid,text,text,jsonb)',
        'beta_validation_qv2_finish_post(uuid,text)', 'beta_validation_qv2_finish_pre(uuid,text)',
        'beta_validation_qv2_read(uuid,text)', 'beta_validation_qv2_start(text)', 'beta_validation_session_start(text,text)',
        'cantina_accessori_pubblica_profilo(uuid,integer,integer,boolean)', 'cantina_pubblica_profilo(uuid,integer,integer)',
        'cantina_pubblica_valore(uuid)', 'inventario_capacita()', 'listing_logistica_preventivo(uuid,integer,integer)',
        'listing_preventivo(uuid,integer,integer)', 'mercato_configurazione()', 'profilo_pubblico(uuid)',
        'recensioni_pubbliche_elenco(uuid,integer,integer)', 'reputazione_pubblica(uuid)',
        'vetrina_partner_catalogo(uuid)', 'vetrina_partner_pubblica(uuid)']);

-- 14. Porte per i ruoli client con un parametro che indica un utente: elenco chiuso. Sono letture
-- pubbliche di un profilo o gesti verso un altro utente. Il sospetto da fermare e' una porta che
-- accetta il proprietario dal client invece di leggerlo da auth.uid().
create function pg_temp.con_parametro_utente() returns text[] language sql as $f$
  select coalesce(array_agg(d.firma order by d.firma), '{}')
  from definer_12zv d join pg_proc p on p.oid = d.oid
  where d.schema = 'public'
    and (has_function_privilege('anon', d.oid, 'EXECUTE') or has_function_privilege('authenticated', d.oid, 'EXECUTE'))
    and exists (select 1 from unnest(p.proargnames) a
                where a ~* '^p_(owner|user|utente|proprietario|titolare|profilo|acquirente|venditore|buyer|seller)(_id)?$');
$f$;
select pg_temp.confronta(14, 'porte client con un parametro utente: elenco chiuso',
  pg_temp.con_parametro_utente(),
  array['acquisto_da_venditore_disponibile(uuid)', 'cantina_accessori_pubblica_profilo(uuid,integer,integer,boolean)',
        'cantina_pubblica_profilo(uuid,integer,integer)', 'cantina_pubblica_valore(uuid)', 'cantina_segui(uuid)',
        'cantina_seguita_stato(uuid)', 'cantina_smetti_di_seguire(uuid)', 'club_moderatore_imposta(text,uuid,boolean)',
        'profilo_pubblico(uuid)', 'recensioni_pubbliche_elenco(uuid,integer,integer)', 'reputazione_pubblica(uuid)',
        'vetrina_partner_pubblica(uuid)']);

-- 15. Viste con i privilegi del proprietario: elenco chiuso, lo stesso di
-- CONTESTO_IA/03_ARCHITETTURA_REGOLE_DEBITI.md (GAP-024).
select pg_temp.confronta(15, 'viste di public con i privilegi del proprietario: elenco chiuso',
  (select coalesce(array_agg(c.relname::text), '{}') from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where c.relkind = 'v' and n.nspname = 'public'
     and not coalesce(c.reloptions::text[] && array['security_invoker=on', 'security_invoker=true'], false)
     and not exists (select 1 from pg_depend d where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e')),
  array['club_external_links_visible', 'club_management_clubs', 'club_management_events_visible', 'club_management_members',
        'club_management_moderators', 'club_membership_request_queue', 'club_rule_versions_visible', 'dispute_case_timeline',
        'listing_bottle_units', 'moderation_audit_log', 'moderation_club_proposals', 'moderation_dispute_admin_notes',
        'moderation_dispute_queue', 'moderation_dispute_shipping_evidence', 'moderation_dispute_tracking',
        'moderation_report_events', 'moderation_report_queue', 'my_certifications', 'my_club_membership_requests',
        'my_listing_moderation', 'my_report_events', 'my_reports', 'my_sommelier_messages', 'order_margine_riconciliazione',
        'public_club_external_links', 'public_club_post_risposte', 'public_club_posts', 'public_clubs', 'public_incident_notice',
        'public_listings', 'public_marketplace_config', 'public_packaging_options', 'public_partners',
        'visible_club_governance_events', 'wine_price_history']);

-- 10-13. Controlli negativi: una funzione non conforme viene vista. Senza, una griglia che non
-- legge nulla sarebbe verde.
create function public.prova_12zv_senza() returns int language sql security definer as 'select 1';
revoke all on function public.prova_12zv_senza() from public, anon, authenticated;
select pg_temp.registra(10, 'controllo negativo: funzione senza search_path rilevata',
  'prova_12zv_senza()' = any (pg_temp.senza_search_path()));

create function public.prova_12zv_largo() returns int language sql security definer set search_path = public as 'select 1';
revoke all on function public.prova_12zv_largo() from public, anon, authenticated;
select pg_temp.registra(11, 'controllo negativo: search_path largo rilevato',
  'prova_12zv_largo()' = any (pg_temp.search_path_non_vuoto()));

create function public.prova_12zv_public() returns int language sql security definer set search_path = '' as 'select 1';
grant execute on function public.prova_12zv_public() to public;
select pg_temp.registra(12, 'controllo negativo: EXECUTE a PUBLIC rilevato',
  'prova_12zv_public()' = any (pg_temp.a_public('public')));

create function public.prova_12zv_anon() returns int language sql security definer set search_path = '' as 'select 1';
revoke all on function public.prova_12zv_anon() from public, authenticated;
grant execute on function public.prova_12zv_anon() to anon;
select pg_temp.registra(13, 'controllo negativo: porta nuova per anon rilevata',
  'prova_12zv_anon()' = any (pg_temp.eseguibili('anon', 'public')));

-- Il confronto che regge i casi 2, 3 e 5-9 sa dire «diverso», in entrambi i versi.
select pg_temp.confronta(1000, 'prova interna', array['a'], array['a', 'b']);
select pg_temp.confronta(1001, 'prova interna', array['a', 'b'], array['a']);
select pg_temp.confronta(1002, 'prova interna', array['b', 'a'], array['a', 'b']);
select pg_temp.registra(16, 'controllo negativo: il confronto vede mancanti e in piu, non l''ordine',
  not (select passed from esiti_12zv where id = 1000)
  and not (select passed from esiti_12zv where id = 1001)
  and (select passed from esiti_12zv where id = 1002));
delete from esiti_12zv where id >= 1000;

-- ACL NULL: e' il default di una funzione in `private`, il caso di R-DB-01.
create function private.prova_12zv_acl_nulla() returns int language sql security definer set search_path = '' as 'select 1';
select pg_temp.registra(17, 'controllo negativo: funzione di private con ACL NULL vista a PUBLIC',
  'private.prova_12zv_acl_nulla()' = any (pg_temp.a_public('private')));

-- Il numero dei casi: togliere un caso non deve lasciare il gate verde.
select pg_temp.registra(18, 'la griglia ha esattamente 18 casi',
  (select count(*) from esiti_12zv) = 17, (select count(*)::text from esiti_12zv));

select id, descrizione, passed, detail from esiti_12zv order by id;

rollback;
