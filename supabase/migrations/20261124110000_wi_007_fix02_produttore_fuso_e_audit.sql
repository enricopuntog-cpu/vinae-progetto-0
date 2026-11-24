-- WI-007-FIX-02 — due correzioni dalla revisione indipendente su 44fdfda (24 novembre 2026).
-- Additiva: 20261122130000 e 20261124100000 sono già pubblicate e restano byte-identiche.
--
-- 1. `public.vini_canonici_cerca`: i vini ATTIVI di un produttore FUSO (status 'merged', `wines.producer_id` non viene
--    riassegnato dalla fusione) uscivano da ogni livello di ricerca perché la porta chiedeva `produttore.status = 'active'`.
--    Ora il produttore si risolve sul produttore EFFETTIVO (catena `merged_into`, `catalog.producer_final`, la stessa
--    che usa il rilevamento dei duplicati) e deve essere attivo: un produttore ritirato, o fuso in uno ritirato, resta
--    escluso. Nome e paese mostrati sono quelli del produttore effettivo. Limite dichiarato: `wines.search_key` è
--    calcolata all'inserimento (identità immutabile) e conserva il nome del produttore di allora, quindi il vino fuso si
--    trova ancora con il vecchio nome; il nome del produttore effettivo trova i suoi vini originari.
--    Corpo identico alla 20261122130000 salvo il join; privilegi e commento riaffermati.
-- 3. Trigger `wines_search_key` → `wines_a_search_key`: i trigger BEFORE INSERT partono in ordine alfabetico e il primo nome
--    partiva DOPO `wines_insert_guard`, quindi poteva riscrivere una colonna dopo la convalida della guardia (oggi solo
--    `search_key`). Rinominato perché scatti PRIMA e la guardia convalidi la riga definitiva. Solo il nome cambia (il
--    corpo, `search_path` e privilegi restano); nessuna riga di dati coinvolta.
-- 2. `catalog.surface_audit()`: l'euristica «nessuna scrittura» della classe curator_report riconosce anche
--    `update <tabella> [as] <alias> set` e cerca le funzioni volatili in catalog, private e public. Difesa in profondità: il
--    presidio reale resta la volatilità STABLE (PostgreSQL rifiuta il DML in una funzione non volatile).

create or replace function public.vini_canonici_cerca(
  p_produttore text default '',
  p_nome text default '',
  p_limite integer default 15,
  p_codice text default null
)
returns table (
  fonte text,
  vino_id uuid,
  lwin7 text,
  produttore text,
  nome text,
  paese text,
  territorio text,
  territorio_tipo text,
  denominazione text,
  tipo text,
  colore text,
  punteggio integer,
  livello text,
  fonte_nome text,
  fonte_licenza text,
  attribuzione text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c_esame constant integer := 2000;
  c_stop constant text[] := array[
    'il','lo','la','gli','le','un','una','di','del','dello','della','dei','degli','delle',
    'de','da','the','of','et','and','en','des','du','docg','doc','igt','igp','dop','aoc','aop'];
  c_filler constant text[] := array[
    'azienda','agricola','az','agr','societa','soc','cantina','cantine','tenuta','tenute',
    'fattoria','casa','vinicola','cascina','cooperativa','srl','spa','ss','domaine','chateau',
    'bodega','weingut','vigneti','vignaioli'];
  v_qp text := public.vini_normalizza(left(p_produttore, 120));
  v_qn text := public.vini_normalizza(left(p_nome, 120));
  v_qk text;
  v_limite integer := least(greatest(coalesce(p_limite, 15), 1), 20);
  v_codice text := nullif(regexp_replace(left(coalesce(p_codice, ''), 40), '[^0-9]', '', 'g'), '');
  v_tp text[];
  v_tn text[];
  v_tok text[];
  v_where text;
  v_score text;
  v_acc jsonb := '[]'::jsonb;
  v_seen uuid[] := array[]::uuid[];
  v_rows jsonb;
  v_tier integer;
  v_esatto boolean := false;
  v_soglia_prec text;
begin
  -- Interruttore spento (default) o assente: nulla è pubblico.
  if not coalesce((select s.enabled from catalog.public_projection_settings s), false) then
    return;
  end if;

  select coalesce(array_agg(distinct t), array[]::text[]) into v_tp
    from unnest(string_to_array(v_qp, ' ')) t
    where length(t) >= 3 and t <> all (c_stop) and t <> all (c_filler) and t !~ '^(19|20)[0-9]{2}$';
  select coalesce(array_agg(distinct t), array[]::text[]) into v_tn
    from unnest(string_to_array(v_qn, ' ')) t
    where length(t) >= 3 and t <> all (c_stop) and t !~ '^(19|20)[0-9]{2}$' and t <> all (v_tp);
  v_tok := (v_tp || v_tn)[1:6];
  v_qk := btrim(v_qp || ' ' || v_qn);

  if v_codice is null and coalesce(array_length(v_tok, 1), 0) = 0 then
    return;
  end if;

  for v_tier in 1..4 loop
    exit when jsonb_array_length(v_acc) >= v_limite;
    if v_tier = 1 then
      -- Identificativo LWIN-7 (anche di un record Combined, risolto sul vino di destinazione).
      continue when v_codice is null or length(v_codice) <> 7;
      v_score := '1000';
      -- Un solo `IN` su due rami indicizzati (btree su lwin7, indice parziale sugli alias): con un `OR`
      -- il piano ricadeva sulla scansione sequenziale dei vini.
      -- Il Combined si risolve sul vino di destinazione seguendo le fusioni (al massimo 20 passi) SOLO a
      -- partire dall'alias cercato: `catalog.wine_resolution` calcolerebbe la chiusura di tutti i vini.
      v_where := format('w.id in (select x.id from catalog.wines x where x.lwin7 = %1$L '
                        'union select t.cur from (with recursive r(cur, depth) as ('
                        'select a.wine_id, 0 from catalog.entity_aliases a '
                        'where a.kind = ''combined_lwin'' and a.alias_key = %1$L and a.wine_id is not null '
                        'union all select m.merged_into, r.depth + 1 from r '
                        'join catalog.wines m on m.id = r.cur where m.merged_into is not null and r.depth < 20) '
                        'select cur from r) t)', v_codice);
    elsif v_tier = 2 then
      continue when v_qp = '' or v_qn = '';
      v_score := '100';
      v_where := format('w.search_key = %L', v_qk);
    elsif v_tier = 3 then
      continue when coalesce(array_length(v_tok, 1), 0) = 0;
      v_score := format('case when w.search_key like %L then 90 else 60 end', v_qk || '%');
      v_where := (select string_agg(format('w.search_key like %L', '%' || t || '%'), ' and ') from unnest(v_tok) t);
    else
      continue when v_esatto or jsonb_array_length(v_acc) >= 5 or length(v_qk) < 4;
      v_score := format('round(extensions.similarity(w.search_key, %L) * 50)::int', v_qk);
      v_where := format('w.search_key operator(extensions.%%) %L', v_qk);
    end if;

    if v_tier = 4 then
      perform extensions.similarity('a', 'a');
      v_soglia_prec := current_setting('pg_trgm.similarity_threshold', true);
      perform set_config('pg_trgm.similarity_threshold', '0.4', true);
    end if;

    -- Solo vini promossi, attivi, con produttore attivo. Visibilità scritta qui, mai da parametri.
    execute format($q$
      select coalesce(jsonb_agg(to_jsonb(r) order by r.ord), '[]'::jsonb) from (
        select c.*, %3$s as livello_n,
               row_number() over (order by c.punteggio desc, c.produttore, c.nome, c.lwin7, c.vino_id) as ord
        from (
          select w.id as vino_id, w.lwin7, p.name as produttore, w.name as nome,
                 cp.name as paese, t.name as territorio, t.kind as territorio_tipo,
                 w.designation as denominazione, w.wine_type as tipo, w.colour as colore,
                 (%1$s) as punteggio, s.name as fonte_nome, s.license as fonte_licenza,
                 s.attribution_text as attribuzione
          from catalog.wines w
          join catalog.producers p0 on p0.id = w.producer_id
          join catalog.producers p on p.id = case when p0.status = 'merged' then catalog.producer_final(p0.id) else p0.id end
                                  and p.status = 'active'
          left join catalog.territories cp on cp.id = p.country_territory_id
          left join catalog.territories t on t.id = w.territory_id
          join catalog.sources s on s.id = w.source_id and s.authorization_status = 'authorized'
          where w.status = 'active' and w.origin = 'promotion' and (%2$s)
            and not (w.id = any (%4$L::uuid[]))
          limit %6$s
        ) c
        order by ord
        limit %5$s
      ) r$q$, v_score, v_where, v_tier, v_seen, v_limite - jsonb_array_length(v_acc), c_esame)
    into v_rows;

    if v_tier = 4 then
      perform set_config('pg_trgm.similarity_threshold', coalesce(nullif(v_soglia_prec, ''), '0.3'), true);
    end if;
    if v_tier <= 2 and jsonb_array_length(v_rows) > 0 then
      v_esatto := true;
    end if;
    v_acc := v_acc || v_rows;
    v_seen := v_seen || array(select (e ->> 'vino_id')::uuid from jsonb_array_elements(v_rows) e);
  end loop;

  return query
    select 'catalogo_canonico'::text, x.vino_id, x.lwin7, x.produttore, x.nome, x.paese, x.territorio,
           x.territorio_tipo, x.denominazione, x.tipo, x.colore, x.punteggio,
           case x.livello_n when 1 then 'identificativo' when 2 then 'esatto'
             when 3 then case when x.punteggio >= 90 then 'prefisso' else 'testo' end
             else 'simile' end,
           x.fonte_nome, x.fonte_licenza, x.attribuzione
    from jsonb_to_recordset(v_acc) as x(
      vino_id uuid, lwin7 text, produttore text, nome text, paese text, territorio text,
      territorio_tipo text, denominazione text, tipo text, colore text, punteggio integer,
      fonte_nome text, fonte_licenza text, attribuzione text, livello_n integer, ord bigint)
    order by x.livello_n, x.ord;
end;
$$;

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
                   and k.prosrc ~* '(^|[^a-z_])(insert[[:space:]]+into|update[[:space:]]+(only[[:space:]]+)?[a-z_."]+([[:space:]]+(as[[:space:]]+)?[a-z_]+)?[[:space:]]+set|delete[[:space:]]+from|truncate)([^a-z_]|$)'
                  then 'rapporto SECURITY DEFINER con istruzioni di scrittura nel corpo' end,
             case when k.kind = 'curator_report'
                   and exists (select 1 from pg_catalog.pg_proc q
                                where q.pronamespace in ('catalog'::regnamespace, 'private'::regnamespace, 'public'::regnamespace)
                                  and q.provolatile = 'v'
                                  and position(q.pronamespace::pg_catalog.regnamespace::text || '.' || q.proname || '(' in k.prosrc) > 0)
                  then 'rapporto SECURITY DEFINER che chiama una funzione volatile (schemi catalog, private o public)' end,
             case when k.kind = 'curator_read' and k.provolatile = 'v' then 'funzione volatile eseguibile dal curatore ma non porta SECURITY DEFINER (scriverebbe con i suoi privilegi)' end,
             case when k.kind = 'loader_door' and k.cur_x then 'funzione del caricatore eseguibile dal curatore' end) as why
      from k)
  select v.sig, v.kind, (v.why = '' or w.sig is not null),
         case when w.sig is not null and v.why <> '' then 'ECCEZIONE (' || w.motive || '): ' || v.why else v.why end
    from v left join waivers w on w.sig = v.sig
   order by v.sig;
$$;

alter trigger wines_search_key on catalog.wines rename to wines_a_search_key;

comment on function public.vini_canonici_cerca(text, text, integer, text) is
  'WI-007. Ricerca sui vini del catalogo canonico PROMOSSI (origine promotion, attivi, fonte autorizzata, produttore effettivo '
  'attivo), solo se catalog.public_projection_settings.enabled. SECURITY DEFINER con elenco chiuso di colonne enologiche, '
  'provenienza e attribuzione. Al massimo 20 righe e 2.000 candidati per livello. EXECUTE a authenticated e service_role (non '
  'ad anon: WI-007-FIX-01). Non espone catalog.*, nessun prezzo, nessun dato personale.';

revoke all on function public.vini_canonici_cerca(text, text, integer, text) from public, anon;
grant execute on function public.vini_canonici_cerca(text, text, integer, text) to authenticated, service_role;

comment on function catalog.surface_audit() is
  'WI-001C-FIX-02 + WI-007-FIX-01/02: classifica ogni funzione dello schema catalog dal catalogo di sistema e verifica le regole di '
  'ogni classe (porte del curatore, rapporti definer di sola lettura, letture invoker, porte del caricatore, interne). Solo proprietario.';
revoke all on function catalog.surface_audit() from public, anon, authenticated, service_role, catalog_curator, catalog_loader;

notify pgrst, 'reload schema';
