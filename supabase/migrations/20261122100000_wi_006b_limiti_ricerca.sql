-- WI-006B (correzione 01) — limiti di lavoro di `vini_cerca`.
--
-- Additiva: sostituisce SOLO il corpo di `public.vini_cerca` (stessa firma, stesse colonne, stessi
-- grant, stessa visibilità). La migration 20261121100000 resta com'è (già distribuita).
--
-- Cosa cambia:
--   1. `p_formato` è troncato a 40 caratteri come gli altri input (prima era l'unico testo pubblico
--      senza tetto: finiva intero in un letterale SQL e nel confronto di ordinamento).
--   2. Tetto alle righe ESAMINATE, distinto dal tetto ai risultati. Il limite a 20 righe non limitava
--      il lavoro: un termine molto comune («Barolo») faceva rileggere, calcolare e ordinare tutti i vini
--      che lo contengono (~20.000 su 200.000, ~900 ms). Ora ogni livello legge al massimo
--      `c_esame` (2.000) candidati dall'indice. Il ranking resta quello di prima, ma sul sottoinsieme
--      letto: con un termine che trova più di 2.000 vini l'ordine fra i 2.000 non è garantito
--      globale. Limite noto e accettato: a quel punto la domanda è troppo generica per
--      identificare un vino e l'utente deve aggiungere produttore o nome; il wizard non perde la
--      via manuale. Sotto i 2.000 candidati (ogni domanda ragionevole) nulla cambia.
--   3. Resta il limite di piattaforma: `statement_timeout` dei ruoli (anon 3 s, authenticated 8 s)
--      interrompe una query che sfugge a ogni tetto, senza toccare disponibilità degli altri utenti.
--
-- Nessun nuovo privilegio, nessuna policy toccata, nessun indice nuovo.

create or replace function public.vini_cerca(
  p_produttore text default '',
  p_nome text default '',
  p_annata integer default null,
  p_formato text default null,
  p_limite integer default 15,
  p_codice text default null
)
returns table (
  fonte text,
  vino_id uuid,
  slug text,
  produttore text,
  nome text,
  annata integer,
  formato text,
  regione text,
  denominazione text,
  tipo text,
  annunci integer,
  punteggio integer,
  livello text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  -- Tetto alle righe esaminate per livello (non ai risultati: quelli sono v_limite, al massimo 20).
  c_esame constant integer := 2000;
  c_stop constant text[] := array[
    'il','lo','la','gli','le','un','una','di','del','dello','della','dei','degli','delle',
    'de','da','the','of','et','and','en','des','du','docg','doc','igt','igp','dop','aoc','aop'];
  c_filler constant text[] := array[
    'azienda','agricola','az','agr','societa','soc','cantina','cantine','tenuta','tenute',
    'fattoria','casa','vinicola','cascina','cooperativa','srl','spa','ss','domaine','chateau',
    'bodega','weingut','vigneti','vignaioli'];
  -- Identità dal token, mai da un parametro. Nulla per `anon`.
  v_uid_lit text := coalesce(quote_literal(auth.uid()::text) || '::uuid', 'null::uuid');
  -- Tetto agli input prima di normalizzare: un anonimo non puo far lavorare il trigramma su stringhe enormi.
  v_qp text := public.vini_normalizza(left(p_produttore, 120));
  v_qn text := public.vini_normalizza(left(p_nome, 120));
  v_qk text;
  v_limite integer := least(greatest(coalesce(p_limite, 15), 1), 20);
  v_slug text := nullif(lower(btrim(left(coalesce(p_codice, ''), 80))), '');
  v_tp text[];
  v_tn text[];
  v_tok text[];
  v_pred text;
  v_where text;
  v_score text;
  v_acc jsonb := '[]'::jsonb;
  v_seen text[] := array[]::text[];
  v_rows jsonb;
  v_tier integer;
  v_annata text := coalesce(p_annata::text, 'null');
  v_formato text := coalesce(quote_literal(left(p_formato, 40)), 'null');
  v_esatto boolean := false;
  v_soglia_prec text;
begin
  -- Parole significative: almeno 3 caratteri, senza articoli, sigle di
  -- denominazione, anni (l'annata è un campo a parte); per il produttore anche
  -- senza le parole che qualificano senza identificare («Tenuta», «Domaine»).
  select coalesce(array_agg(distinct t), array[]::text[]) into v_tp
    from unnest(string_to_array(v_qp, ' ')) t
    where length(t) >= 3 and t <> all (c_stop) and t <> all (c_filler) and t !~ '^(19|20)[0-9]{2}$';
  select coalesce(array_agg(distinct t), array[]::text[]) into v_tn
    from unnest(string_to_array(v_qn, ' ')) t
    where length(t) >= 3 and t <> all (c_stop) and t !~ '^(19|20)[0-9]{2}$' and t <> all (v_tp);
  v_tok := (v_tp || v_tn)[1:6];
  v_qk := btrim(v_qp || ' ' || v_qn);

  if v_slug is null and coalesce(array_length(v_tok, 1), 0) = 0 then
    return;
  end if;

  v_pred := (select string_agg(format('{k} like %L', '%' || t || '%'), ' and ') from unnest(v_tok) t);

  for v_tier in 1..4 loop
    exit when jsonb_array_length(v_acc) >= v_limite;
    if v_tier = 1 then
      continue when v_slug is null;
      v_score := '1000';
      v_where := format('w.slug = %L', v_slug);
    elsif v_tier = 2 then
      continue when v_qp = '' and v_qn = '';
      v_score := '100';
      v_where := concat_ws(' and ',
        case when v_qp <> '' then format('{kp} = %L', v_qp) end,
        case when v_qn <> '' then format('{kn} = %L', v_qn) end);
    elsif v_tier = 3 then
      continue when v_pred is null;
      v_score := format('case when {kp} like %L and {kn} like %L then 90 else 60 end', v_qp || '%', v_qn || '%');
      v_where := v_pred;
    else
      -- Trigramma solo se serve: mai quando un identificativo o un nome esatto
      -- ha già risposto, e solo con pochi risultati dai livelli precedenti.
      continue when v_esatto or jsonb_array_length(v_acc) >= 5 or length(v_qk) < 4;
      v_score := format('round(extensions.similarity({k}, %L) * 50)::int', v_qk);
      v_where := format('{k} operator(extensions.%%) %L', v_qk);
    end if;
    v_score := replace(replace(replace(v_score,
      '{kp}', 'public.vini_normalizza(w.produttore)'),
      '{kn}', 'public.vini_normalizza(w.nome)'),
      '{k}', 'public.vini_normalizza(w.produttore || '' '' || w.nome)');
    v_where := replace(replace(replace(v_where,
      '{kp}', 'public.vini_normalizza(w.produttore)'),
      '{kn}', 'public.vini_normalizza(w.nome)'),
      '{k}', 'public.vini_normalizza(w.produttore || '' '' || w.nome)');

    -- Livello 4: soglia 0,4 invece del default 0,3 (su 200.000 vini a 0,3 una
    -- domanda lunga dava ~3.600 candidati da rileggere; a 0,4 restano i refusi
    -- singoli). Non è un attributo di funzione (permesso negato a chi non è
    -- superuser): si imposta localmente e si ripristina subito dopo.
    if v_tier = 4 then
      perform extensions.similarity('a', 'a');
      v_soglia_prec := current_setting('pg_trgm.similarity_threshold', true);
      perform set_config('pg_trgm.similarity_threshold', '0.4', true);
    end if;

    -- `c`: candidati per testo, con l'indice. Poi due rami:
    --   catalogo  → solo ciò che l'utente può vedere in `wines` (stessa regola delle policy);
    --   annunci   → i vini di annunci pubblici attivi, tramite la vista `public_listings`.
    -- Un vino presente in entrambe le fonti con lo stesso formato conta una volta
    -- (vince il catalogo); l'ordine è totale e riproducibile.
    execute format($q$
      with c as materialized (
        select w.id, w.slug, w.produttore, w.nome, w.annata::int as annata, w.formato, w.regione,
               w.denominazione, w.tipo, w.provenienza, w.creato_da, (%1$s) as punteggio
        from public.wines w where %2$s limit %9$s
      ),
      x as (
        select 'catalogo_vinea'::text as fonte, c.id as vino_id, c.slug, c.produttore, c.nome, c.annata,
               c.formato, c.regione, c.denominazione, c.tipo, 0 as annunci, c.punteggio
        from c
        where c.provenienza = 'staff'
           or (%3$s is not null and c.provenienza = 'utente'
               and (c.creato_da = %3$s
                    or exists (select 1 from public.bottle_units bu
                               where bu.wine_id = c.id and bu.owner_id = %3$s
                                 and bu.deleted_at is null and bu.ceduta_at is null)))
        union all
        select 'annunci_vinea'::text, c.id, c.slug, c.produttore, c.nome, c.annata,
               pl.formato, c.regione, c.denominazione, c.tipo, count(*)::int, c.punteggio
        from c join public.public_listings pl on pl.wine_id = c.id
        group by c.id, c.slug, c.produttore, c.nome, c.annata, pl.formato, c.regione,
                 c.denominazione, c.tipo, c.punteggio
      )
      select coalesce(jsonb_agg(to_jsonb(r) order by r.ord), '[]'::jsonb) from (
        select u.*, %4$s as livello_n,
               row_number() over (order by u.punteggio desc,
                 (u.annata = %5$s::int) desc nulls last, (u.formato = %6$s::text) desc nulls last,
                 u.produttore, u.nome, u.annata, u.slug, u.fonte) as ord
        from (
          select distinct on (x.vino_id, x.formato) x.*
          from x
          where not ((x.vino_id::text || '|' || coalesce(x.formato, '')) = any (%7$L::text[]))
          order by x.vino_id, x.formato, case x.fonte when 'catalogo_vinea' then 0 else 1 end
        ) u
        order by ord
        limit %8$s
      ) r$q$, v_score, v_where, v_uid_lit, v_tier, v_annata, v_formato, v_seen,
              v_limite - jsonb_array_length(v_acc), c_esame)
    into v_rows;
    if v_tier = 4 then
      perform set_config('pg_trgm.similarity_threshold', coalesce(nullif(v_soglia_prec, ''), '0.3'), true);
    end if;

    if v_tier <= 2 and jsonb_array_length(v_rows) > 0 then
      v_esatto := true;
    end if;
    v_acc := v_acc || v_rows;
    v_seen := v_seen || array(
      select (e ->> 'vino_id') || '|' || coalesce(e ->> 'formato', '')
      from jsonb_array_elements(v_rows) e);
  end loop;

  return query
    select x.fonte, x.vino_id, x.slug, x.produttore, x.nome, x.annata, x.formato, x.regione,
           x.denominazione, x.tipo, x.annunci, x.punteggio,
           case x.livello_n when 1 then 'identificativo' when 2 then 'esatto'
             when 3 then case when x.punteggio >= 90 then 'prefisso' else 'testo' end
             else 'simile' end
    from jsonb_to_recordset(v_acc) as x(
      fonte text, vino_id uuid, slug text, produttore text, nome text, annata integer,
      formato text, regione text, denominazione text, tipo text, annunci integer,
      punteggio integer, livello_n integer, ord bigint)
    order by x.livello_n, x.ord;
end;
$$;

comment on function public.vini_cerca(text, text, integer, text, integer, text) is
  'WI-006B. Ricerca vini ordinata per pertinenza lato server, al massimo 20 righe, al massimo 2.000 candidati '
  'esaminati per livello. SECURITY DEFINER con visibilita esplicita equivalente alle policy di wines (provata '
  'dalla griglia wi006b) e alla vista public_listings; identita da auth.uid(). Sola lettura, non legge catalog.*.';

revoke all on function public.vini_cerca(text, text, integer, text, integer, text) from public;
grant execute on function public.vini_cerca(text, text, integer, text, integer, text)
  to anon, authenticated, service_role;
