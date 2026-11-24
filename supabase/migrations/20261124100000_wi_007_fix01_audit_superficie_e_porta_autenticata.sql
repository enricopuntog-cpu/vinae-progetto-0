-- WI-007-FIX-01 — correzioni emerse dalla verifica sul nuovo HEAD (24 novembre 2026).
-- Additiva: la migration 20261122130000 (già pubblicata su GitHub) resta byte-identica e congelata.
--
-- 1. `catalog.surface_audit()` (WI-001C-FIX-02, migration 20261119140000, congelata) trattava come violazione ogni
--    lettura SECURITY DEFINER eseguibile dal curatore. Il fix P1 dell'audit WI-007 ha reso definer
--    `catalog.promotion_simulation` (il curatore non legge `import_findings`, riservata al caricatore, né
--    `public_projection_settings`, né esegue `promotion_logic_fingerprint`: la simulazione ne restituisce solo conteggi
--    e impronte). Risultato: 12zy 243/246 e 12zs 152/153 sul nuovo HEAD. Invece di indebolire l'audit o allargare i
--    privilegi del curatore, l'audit riconosce una classe ESPLICITA e STRETTA, `curator_report`:
--      - eseguibile dal curatore, SECURITY DEFINER, NON volatile (stable/immutable);
--      - search_path vuoto, nessun EXECUTE a PUBLIC/anon/authenticated/service_role, non eseguibile dal caricatore;
--      - nel corpo nessuna istruzione DML/TRUNCATE e nessuna chiamata a una funzione VOLATILE dello schema catalog.
--    Le altre classi sono invariate: curator_door resta l'unico modo di scrivere, curator_read resta invoker non volatile.
--
-- 2. `public.vini_canonici_cerca`: revocato EXECUTE ad `anon`. Nessun consumatore anonimo esiste (il wizard /vendi
--    interroga con la sessione del venditore) e le letture non passano dal limite R-RL-01 (l'hook esce per le
--    transazioni di sola lettura), quindi la porta anonima era l'unica superficie costosa (livello «simile» 87 ms a
--    200.000 vini) esposta senza identità. Restano authenticated e service_role. Riaprire ad anon è una decisione
--    separata (richiede un limite per identità, non disponibile oggi per le letture).

create or replace function catalog.surface_audit()
returns table (fn text, kind text, ok boolean, why text)
language sql stable set search_path = '' as $$
  with f as (
    select p.oid, p.oid::pg_catalog.regprocedure::text as sig, p.prosecdef, p.provolatile, p.prosrc, p.proconfig,
           has_function_privilege('catalog_curator', p.oid, 'EXECUTE') as cur_x,
           has_function_privilege('catalog_loader', p.oid, 'EXECUTE') as ldr_x,
           (has_function_privilege('anon', p.oid, 'EXECUTE') or has_function_privilege('authenticated', p.oid, 'EXECUTE')
            or has_function_privilege('service_role', p.oid, 'EXECUTE')
            or exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0)) as client_x
      from pg_catalog.pg_proc p
     where p.pronamespace = 'catalog'::regnamespace
       and not exists (select 1 from pg_catalog.pg_depend d where d.objid = p.oid and d.deptype = 'e')),
  k as (
    select f.*, case when f.cur_x and f.prosecdef and f.provolatile = 'v' then 'curator_door'
                     when f.cur_x and f.prosecdef then 'curator_report'
                     when f.cur_x then 'curator_read'
                     when f.ldr_x then 'loader_door'
                     else 'internal' end as kind
      from f),
  waivers(sig, motive) as (select null::text, null::text where false),
  v as (
    select k.sig, k.kind,
           concat_ws('; ',
             case when k.client_x then 'eseguibile da PUBLIC/anon/authenticated/service_role' end,
             case when not exists (select 1 from unnest(coalesce(k.proconfig, '{}'::text[])) c where c in ('search_path=""', 'search_path=')) then 'search_path non vuoto' end,
             case when k.kind = 'curator_door' and k.ldr_x then 'porta del curatore eseguibile anche dal caricatore' end,
             case when k.kind = 'curator_door' and k.prosrc not like '%catalog.require_actor(%' then 'porta senza esecutore obbligatorio (require_actor)' end,
             case when k.kind = 'curator_door' and k.prosrc not like '%catalog.record_canonical_event(%' then 'porta senza evento di audit (record_canonical_event)' end,
             case when k.kind = 'curator_report' and k.ldr_x then 'rapporto del curatore eseguibile anche dal caricatore' end,
             case when k.kind = 'curator_report'
                   and k.prosrc ~* '(^|[^a-z_])(insert[[:space:]]+into|update[[:space:]]+[a-z_."]+[[:space:]]+set|delete[[:space:]]+from|truncate)([^a-z_]|$)'
                  then 'rapporto SECURITY DEFINER con istruzioni di scrittura nel corpo' end,
             case when k.kind = 'curator_report'
                   and exists (select 1 from pg_catalog.pg_proc q
                                where q.pronamespace = 'catalog'::regnamespace and q.provolatile = 'v'
                                  and position('catalog.' || q.proname || '(' in k.prosrc) > 0)
                  then 'rapporto SECURITY DEFINER che chiama una funzione volatile dello schema catalog' end,
             case when k.kind = 'curator_read' and k.provolatile = 'v' then 'funzione volatile eseguibile dal curatore ma non porta SECURITY DEFINER (scriverebbe con i suoi privilegi)' end,
             case when k.kind = 'loader_door' and k.cur_x then 'funzione del caricatore eseguibile dal curatore' end) as why
      from k)
  select v.sig, v.kind, (v.why = '' or w.sig is not null),
         case when w.sig is not null and v.why <> '' then 'ECCEZIONE (' || w.motive || '): ' || v.why else v.why end
    from v left join waivers w on w.sig = v.sig
   order by v.sig;
$$;

comment on function catalog.surface_audit() is
  'WI-001C-FIX-02 + WI-007-FIX-01: classifica ogni funzione dello schema catalog dal catalogo di sistema e verifica le regole di '
  'ogni classe (porte del curatore, rapporti definer di sola lettura, letture invoker, porte del caricatore, interne). Solo proprietario.';

-- CREATE OR REPLACE conserva proprietario e privilegi: riaffermati per chiarezza (nessun ruolo applicativo).
revoke all on function catalog.surface_audit() from public, anon, authenticated, service_role, catalog_curator, catalog_loader;

-- Porta di ricerca canonica: solo sessioni identificate (authenticated) e service_role.
revoke execute on function public.vini_canonici_cerca(text, text, integer, text) from anon;

comment on function public.vini_canonici_cerca(text, text, integer, text) is
  'WI-007. Ricerca sui vini del catalogo canonico PROMOSSI (origine promotion, attivi, fonte autorizzata), solo se '
  'catalog.public_projection_settings.enabled. SECURITY DEFINER con elenco chiuso di colonne enologiche, provenienza e '
  'attribuzione. Al massimo 20 righe e 2.000 candidati per livello. EXECUTE a authenticated e service_role (non ad anon: '
  'WI-007-FIX-01). Non espone catalog.*, nessun prezzo, nessun dato personale.';

notify pgrst, 'reload schema';
