-- WI-006B — motore di ricerca dei vini: normalizzazione, indici e RPC `vini_cerca`.
--
-- Additiva: nessuna tabella, vista, policy o grant esistente viene modificato.
-- Aggiunge due funzioni e due indici su `public.wines`.
--
-- PERCHÉ UNA RPC. WI-006A filtrava con ILIKE di PostgREST: nessun ranking sul
-- server (il tetto alfabetico poteva tagliare il vino giusto), nessuna piega
-- degli accenti, un solo refuso per parola. Qui il database trova e ordina i
-- candidati e il client riceve al massimo 20 righe già ordinate per pertinenza.
--
-- PERCHÉ SECURITY DEFINER (e non INVOKER). Provato con EXPLAIN su 20.000 e
-- 200.000 vini: con SECURITY INVOKER, per `anon`/`authenticated` la tabella ha
-- RLS e il planner NON può usare un indice per una condizione che chiama una
-- funzione non *leakproof* (marcarla tale richiede superuser): risultato,
-- scansione sequenziale di tutta `wines` per ogni ricerca (~230 ms a 20.000
-- righe, lineare oltre). Quindi la funzione legge come proprietario ma applica
-- ESPLICITAMENTE la stessa visibilità delle policy di `wines`:
--   • schede `staff`: tutti, anche anonimi;
--   • schede `utente`: solo chi le ha create o ne possiede ancora una bottiglia
--     (stessa condizione di `wines_select_own_user`), mai per `anon`;
--   • vini di annunci attivi e pubblici: tramite la vista `public_listings`
--     (che ha già i suoi filtri), per tutti.
-- L'equivalenza con la RLS è provata a ogni corsa dalla griglia `wi006b`
-- (insieme visibile via RPC ⊆ insieme visibile con SELECT diretta sotto RLS +
-- annunci pubblici) e dalla prova a due utenti su PostgREST. Se una policy di
-- `wines` cambia, la griglia diventa rossa.
--
-- La funzione non scrive, non legge `catalog.*` (schema privato), verifica
-- l'identità con `auth.uid()` (mai da un parametro), ha `search_path` vuoto,
-- tutti i nomi qualificati, nessun EXECUTE a PUBLIC. Ogni valore che entra nel
-- testo SQL dinamico è un letterale quotato (`%L`) dopo normalizzazione a
-- [a-z0-9 ]; le parole cercate non possono contenere caratteri speciali di LIKE.
--
-- STRATEGIA (ogni livello esclude ciò che i precedenti hanno già restituito;
-- si ferma appena i risultati bastano):
--   1. identificativo esatto (slug)
--   2. produttore e nome esatti, normalizzati (accenti, maiuscole, punteggiatura)
--   3. tutte le parole significative contenute (indice trigramma); prefisso > contiene
--   4. similarità trigramma, solo se i livelli precedenti hanno dato meno di 5 vini
--
-- Normalizzazione con translate(), non con l'estensione unaccent: stessa scelta
-- di `slugifica` (20260729112500), indipendente dallo schema in cui unaccent
-- è installata.

create or replace function public.vini_normalizza(p_testo text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select btrim(regexp_replace(
    translate(
      lower(replace(replace(replace(replace(replace(coalesce(p_testo, ''), 'ß', 'ss'), 'Æ', 'ae'), 'æ', 'ae'), 'Œ', 'oe'), 'œ', 'oe')),
      'àáâãäåāèéêëēìíîïīòóôõöøōùúûüūçćčñńýÿšśžźżłđ',
      'aaaaaaaeeeeeiiiiiooooooouuuuuccc' || 'nnyyssz' || 'zzld'
    ),
    '[^a-z0-9]+', ' ', 'g'
  ));
$$;

comment on function public.vini_normalizza(text) is
  'WI-006B. Chiave di confronto: minuscole, senza accenti, solo [a-z0-9] separati da uno spazio. '
  'Pura e immutabile (usata dagli indici di wines e da vini_cerca). Non esposta ad anon.';

-- EXECUTE ad authenticated (non ad anon): le espressioni degli indici su wines sono valutate con i
-- privilegi di chi scrive la riga, e admin/moderator inseriscono schede staff come authenticated
-- (policy wines_insert_staff). Senza questo grant ogni INSERT/UPDATE di produttore o nome fallirebbe con 42501.
-- E una funzione pura: nessun dato, nessun effetto.
revoke all on function public.vini_normalizza(text) from public, anon;
grant execute on function public.vini_normalizza(text) to authenticated, service_role;

-- Ricerca per prefisso/contenuto con accenti e maiuscole piegati (trigramma) e
-- uguaglianza produttore+nome normalizzata (btree). L'indice esistente
-- `wines_ricerca_trgm_idx` (testo grezzo, usato da /esplora) resta invariato.
create index wines_norm_trgm_idx
  on public.wines
  using gin ((public.vini_normalizza(produttore || ' ' || nome)) extensions.gin_trgm_ops);

create index wines_norm_prod_nome_idx
  on public.wines ((public.vini_normalizza(produttore)), (public.vini_normalizza(nome)));

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
  v_formato text := coalesce(quote_literal(p_formato), 'null');
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
        from public.wines w where %2$s
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
              v_limite - jsonb_array_length(v_acc))
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
  'WI-006B. Ricerca vini ordinata per pertinenza lato server, al massimo 20 righe. SECURITY DEFINER '
  'con visibilita esplicita equivalente alle policy di wines (provata dalla griglia wi006b) e alla '
  'vista public_listings; identita da auth.uid(). Sola lettura, non legge catalog.*.';

revoke all on function public.vini_cerca(text, text, integer, text, integer, text) from public;
grant execute on function public.vini_cerca(text, text, integer, text, integer, text)
  to anon, authenticated, service_role;
