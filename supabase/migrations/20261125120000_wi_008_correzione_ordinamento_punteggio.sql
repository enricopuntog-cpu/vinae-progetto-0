-- WI-008 — correzione 01 della ricerca canonica (la migration 20261125110000 è già stata pubblicata sul ramo, quindi è congelata).
--
-- Difetto: nei livelli 1 (identificativo) e 2 (esatto) il punteggio è una COSTANTE ('1000', '100'); `order by (100) desc` è letto da
-- PostgreSQL come POSIZIONE di colonna e fallisce con «ORDER BY position 100 is not in select list» (trovato dalla griglia wi007b nel gate
-- DB, prima di ogni distribuzione). Ora l'ordine usa l'ALIAS di uscita `punteggio` (mai una posizione). Per il resto la funzione è
-- identica a quella di 20261125110000: ranking esatto senza tetto di scansione prima dell'ordine, 40 ricerche/min per identità,
-- stessi privilegi (solo authenticated e service_role).

create or replace function public.vini_canonici_cerca(
  p_produttore text default ''::text,
  p_nome text default ''::text,
  p_limite integer default 15,
  p_codice text default null::text
) returns table(
  fonte text, vino_id uuid, lwin7 text, produttore text, nome text, paese text, territorio text, territorio_tipo text,
  denominazione text, tipo text, colore text, punteggio integer, livello text, fonte_nome text, fonte_licenza text,
  attribuzione text)
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  c_stop constant text[] := array[
    'il','lo','la','gli','le','un','una','di','del','dello','della','dei','degli','delle',
    'de','da','the','of','et','and','en','des','du','docg','doc','igt','igp','dop','aoc','aop'];
  c_filler constant text[] := array[
    'azienda','agricola','az','agr','societa','soc','cantina','cantine','tenuta','tenute',
    'fattoria','casa','vinicola','cascina','cooperativa','srl','spa','ss','domaine','chateau',
    'bodega','weingut','vigneti','vignaioli'];
  c_limite_utente constant integer := 40;
  c_limite_servizio constant integer := 600;
  v_qp text := public.vini_normalizza(left(p_produttore, 120));
  v_qn text := public.vini_normalizza(left(p_nome, 120));
  v_qk text;
  v_limite integer := least(greatest(coalesce(p_limite, 15), 1), 20);
  v_codice text := nullif(regexp_replace(left(coalesce(p_codice, ''), 40), '[^0-9]', '', 'g'), '');
  v_uid uuid := auth.uid();
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
  -- Interruttore spento (default) o assente: nulla è pubblico e nulla viene consumato.
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

  -- Limite per identità (WI-008): l'identità viene dal token, mai da parametri. Una richiesta valida lo consuma.
  if v_uid is not null then
    perform private.rate_limit_consume('ricerca-canonica', 'user:' || v_uid::text, c_limite_utente, 60);
  else
    perform private.rate_limit_consume('ricerca-canonica', 'service', c_limite_servizio, 60);
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
    -- L'ordine (punteggio, search_key, lwin7, id) si applica all'INSIEME COMPLETO delle corrispondenze e il tetto
    -- delle righe richieste viene DOPO: nessun limite di scansione precede l'ordinamento.
    execute format($q$
      select coalesce(jsonb_agg(to_jsonb(r) order by r.ord), '[]'::jsonb) from (
        select c.*, %3$s as livello_n,
               row_number() over (order by c.punteggio desc, c.search_key, c.lwin7, c.vino_id) as ord
        from (
          select w.id as vino_id, w.lwin7, w.search_key, p.name as produttore, w.name as nome,
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
          order by punteggio desc, w.search_key, w.lwin7, w.id
          limit %5$s
        ) c
        order by ord
      ) r$q$, v_score, v_where, v_tier, v_seen, v_limite - jsonb_array_length(v_acc))
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
$function$;

comment on function public.vini_canonici_cerca(text, text, integer, text) is
  'WI-008. Ricerca canonica: ranking esatto (nessun tetto di scansione prima dell''ordinamento), limite di 40 ricerche al minuto '
  'per utente (service_role: 600), spenta con l''interruttore della proiezione pubblica. VOLATILE perché consuma un contatore.';

-- Privilegi invariati (rivisti, non ampliati): CREATE OR REPLACE li conserva; qui sono dichiarati di nuovo per essere certi.
revoke all on function public.vini_canonici_cerca(text, text, integer, text) from public, anon;
grant execute on function public.vini_canonici_cerca(text, text, integer, text) to authenticated, service_role;
