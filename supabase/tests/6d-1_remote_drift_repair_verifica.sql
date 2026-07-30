-- ============================================================================
-- Fase 6d-1 — verifica unica della repair della deriva remota.
--
-- Eseguire dopo avere applicato, con il sistema di migrazioni e previa
-- approvazione, 20260730140948_security_invariants_remote_drift_repair.sql.
--
-- È una sola query, non modifica dati e restituisce una riga nominata per ogni
-- controllo. Atteso: tutte le righe con esito = PASSA.
--
-- Questa query non sostituisce le due griglie comportamentali:
--   * 6d-1_invarianti_sicurezza.sql       -> 33 PASSA, 0 FALLISCE;
--   * 6d-1_followup_invarianti.sql        -> 11 PASSA, 0 FALLISCE.
-- Gli advisor Supabase vanno riesaminati separatamente dopo il deploy.
-- ============================================================================

with funzioni as (
  select
    p.proname,
    p.oid,
    p.prosecdef,
    coalesce(p.proconfig, array[]::text[]) as proconfig,
    lower(pg_get_functiondef(p.oid)) as definizione
  from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'bottiglia_apri',
      'bottiglia_cancella',
      'listings_bottiglia_idonea',
      'listings_marca_bottiglia_ceduta'
    )
),
metriche as (
  select
    (
      select count(*)
      from supabase_migrations.schema_migrations m
      where m.version = '20260730140948'
    ) as repair_registrata,
    (
      select count(*)
      from (
        select l.bottle_unit_id
        from public.listings l
        where l.stato in (
          'bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato'
        )
        group by l.bottle_unit_id
        having count(*) > 1
      ) duplicati
    ) as annunci_non_terminali_duplicati,
    (
      select count(*)
      from public.listings l
        join public.bottle_units bu on bu.id = l.bottle_unit_id
      where l.stato in (
        'bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato'
      )
        and (
          bu.stato <> 'chiusa'
          or bu.deleted_at is not null
          or bu.ceduta_at is not null
          or bu.owner_id is distinct from l.seller_id
        )
    ) as annunci_con_bottiglia_non_idonea,
    (
      select count(*)
      from public.cellar_slots cs
        join public.bottle_units bu on bu.id = cs.bottle_unit_id
      where bu.deleted_at is not null or bu.ceduta_at is not null
    ) as slot_su_bottiglie_non_possedute,
    (
      select count(*)
      from auth.users u
      where u.email like 'vinea-test-%@example.invalid'
    ) + (
      select count(*)
      from public.profiles p
      where p.username like 'vinea_test_%'
    ) as residui_fixture,
    (
      select count(*)
      from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.prosecdef
        and has_function_privilege('anon', p.oid, 'execute')
    ) as security_definer_eseguibili_da_anon,
    (
      select count(*)
      from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname in (
          'bottiglia_apri',
          'bottiglia_cancella',
          'listing_crea',
          'listing_pubblica',
          'listing_sospendi',
          'listing_scadi',
          'cellar_posiziona',
          'cellar_togli_posizione'
        )
        and has_function_privilege('authenticated', p.oid, 'execute')
    ) as rpc_applicative_authenticated
),
verifiche as (
  select
    10 as ordine,
    'migration_history_repair'::text as controllo,
    (select repair_registrata = 1 from metriche) as ok,
    '1 migrazione registrata'::text as atteso,
    (select repair_registrata::text from metriche) as ottenuto

  union all

  select
    20,
    'bottiglia_apri_definizione_finale',
    exists (
      select 1
      from funzioni f
      where f.proname = 'bottiglia_apri'
        and f.prosecdef
        and f.proconfig @> array['search_path=""']::text[]
        and f.definizione like '%v_ceduta is not null%'
        and f.definizione like '%''bozza'', ''in_revisione'', ''modifiche_richieste'', ''attivo'', ''riservato''%'
        and not has_function_privilege('public', f.oid, 'execute')
        and not has_function_privilege('anon', f.oid, 'execute')
        and has_function_privilege('authenticated', f.oid, 'execute')
    ),
    'ceduta_at + 5 stati; SECURITY DEFINER; search_path vuoto; solo authenticated',
    'vedi esito'

  union all

  select
    30,
    'bottiglia_cancella_definizione_finale',
    exists (
      select 1
      from funzioni f
      where f.proname = 'bottiglia_cancella'
        and f.prosecdef
        and f.proconfig @> array['search_path=""']::text[]
        and f.definizione like '%v_ceduta is not null%'
        and f.definizione like '%''bozza'', ''in_revisione'', ''modifiche_richieste'', ''attivo'', ''riservato''%'
        and not has_function_privilege('public', f.oid, 'execute')
        and not has_function_privilege('anon', f.oid, 'execute')
        and has_function_privilege('authenticated', f.oid, 'execute')
    ),
    'ceduta_at + 5 stati; SECURITY DEFINER; search_path vuoto; solo authenticated',
    'vedi esito'

  union all

  select
    40,
    'listings_bottiglia_idonea_definizione_finale',
    exists (
      select 1
      from funzioni f
      where f.proname = 'listings_bottiglia_idonea'
        and not f.prosecdef
        and f.proconfig @> array['search_path=""']::text[]
        and f.definizione like '%v_owner is distinct from new.seller_id%'
        and not has_function_privilege('public', f.oid, 'execute')
        and not has_function_privilege('anon', f.oid, 'execute')
        and not has_function_privilege('authenticated', f.oid, 'execute')
    ),
    'seller = owner; SECURITY INVOKER; search_path vuoto; nessun ruolo client',
    'vedi esito'

  union all

  select
    50,
    'listings_marca_bottiglia_ceduta_definizione_finale',
    exists (
      select 1
      from funzioni f
      where f.proname = 'listings_marca_bottiglia_ceduta'
        and not f.prosecdef
        and f.proconfig @> array['search_path=""']::text[]
        and f.definizione like '%delete from public.cellar_slots%'
        and not has_function_privilege('public', f.oid, 'execute')
        and not has_function_privilege('anon', f.oid, 'execute')
        and not has_function_privilege('authenticated', f.oid, 'execute')
    ),
    'ceduta_at + rilascio slot; SECURITY INVOKER; nessun ruolo client',
    'vedi esito'

  union all

  select
    60,
    'trigger_repair_presenti_e_abilitati',
    (
      select count(*) = 2
      from pg_trigger t
        join pg_class c on c.oid = t.tgrelid
        join pg_namespace n on n.oid = c.relnamespace
      where not t.tgisinternal
        and n.nspname = 'public'
        and t.tgenabled = 'O'
        and (
          (c.relname = 'listings' and t.tgname = 'listings_bottiglia_idonea')
          or
          (c.relname = 'listings' and t.tgname = 'listings_marca_bottiglia_ceduta')
        )
    ),
    '2 trigger abilitati',
    (
      select count(*)::text
      from pg_trigger t
        join pg_class c on c.oid = t.tgrelid
        join pg_namespace n on n.oid = c.relnamespace
      where not t.tgisinternal
        and n.nspname = 'public'
        and t.tgenabled = 'O'
        and t.tgname in (
          'listings_bottiglia_idonea',
          'listings_marca_bottiglia_ceduta'
        )
    )

  union all

  select
    70,
    'user_roles_select_own_ottimizzata',
    exists (
      select 1
      from pg_policies p
      where p.schemaname = 'public'
        and p.tablename = 'user_roles'
        and p.policyname = 'user_roles_select_own'
        and p.cmd = 'SELECT'
        and p.roles = array['authenticated']::name[]
        and regexp_replace(lower(p.qual), '\s+', '', 'g')
          like '%user_id=(selectauth.uid()%'
    ),
    'user_id = (select auth.uid()) per authenticated',
    coalesce((
      select p.qual
      from pg_policies p
      where p.schemaname = 'public'
        and p.tablename = 'user_roles'
        and p.policyname = 'user_roles_select_own'
    ), 'policy assente')

  union all

  select
    80,
    'security_definer_eseguibili_da_anon',
    (select security_definer_eseguibili_da_anon = 0 from metriche),
    '0',
    (select security_definer_eseguibili_da_anon::text from metriche)

  union all

  select
    90,
    'rpc_applicative_authenticated',
    (select rpc_applicative_authenticated = 8 from metriche),
    '8',
    (select rpc_applicative_authenticated::text from metriche)

  union all

  select
    100,
    'preflight_annunci_non_terminali_duplicati',
    (select annunci_non_terminali_duplicati = 0 from metriche),
    '0',
    (select annunci_non_terminali_duplicati::text from metriche)

  union all

  select
    110,
    'preflight_annunci_con_bottiglia_non_idonea',
    (select annunci_con_bottiglia_non_idonea = 0 from metriche),
    '0',
    (select annunci_con_bottiglia_non_idonea::text from metriche)

  union all

  select
    120,
    'preflight_slot_su_bottiglie_non_possedute',
    (select slot_su_bottiglie_non_possedute = 0 from metriche),
    '0',
    (select slot_su_bottiglie_non_possedute::text from metriche)

  union all

  select
    130,
    'residui_fixture_utenti_e_profili',
    (select residui_fixture = 0 from metriche),
    '0',
    (select residui_fixture::text from metriche)
)
select
  controllo,
  case when ok then 'PASSA' else 'FALLISCE' end as esito,
  atteso,
  ottenuto
from verifiche
order by ordine;
