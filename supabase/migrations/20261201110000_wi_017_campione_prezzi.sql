-- WI-017: stesso perimetro delle porte WI-016 e stesso tetto di 500.
-- Prima i comparabili nella finestra WI-014 (730 giorni esatti), con
-- le vendite prima delle richieste affinché queste non sottraggano il campione.
-- L'enum price_observation_tipo ordina 'richiesta' prima di 'vendita'.

create or replace function public.prezzi_vino_osservazioni(p_wine_slug text, p_formato text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_slug text := left(coalesce(p_wine_slug, ''), 200);
  v_ml integer := catalog.parse_format_ml(left(coalesce(p_formato, ''), 40));
  v_subject record;
begin
  if auth.uid() is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if not coalesce((select s.valutazione_utenti_enabled from private.prezzi_settings s), false)
     or brain.is_suspended('globale', 'tutto') then
    return jsonb_build_object('abilitata', false);
  end if;
  select h.wine_id, h.annata into v_subject from public.wine_price_history h where h.wine_slug = v_slug limit 1;
  if v_subject.wine_id is null or v_subject.annata is null or v_ml is null then
    return jsonb_build_object('abilitata', true, 'soggetto', null, 'osservazioni', '[]'::jsonb);
  end if;
  return jsonb_build_object('abilitata', true,
    'soggetto', jsonb_build_object('vinoId', v_subject.wine_id, 'annata', v_subject.annata, 'formatoMl', v_ml, 'valuta', 'eur'),
    'osservazioni', coalesce((select jsonb_agg(jsonb_build_object('id', 'o' || o.n,
          'tipo', case o.tipo::text when 'vendita' then 'realizzato' else 'richiesto' end,
          'centesimi', o.prezzo_cents, 'valuta', o.valuta, 'osservatoIl', o.observed_at, 'fonte', o.fonte::text,
          'vinoId', o.wine_id, 'annata', o.annata, 'formatoMl', catalog.parse_format_ml(o.formato), 'condizione', null)
          order by o.n)
        from (select h.*, row_number() over (order by h.tipo desc, h.observed_at desc, h.prezzo_cents, h.formato, h.fonte) as n
                from public.wine_price_history h
                   where h.wine_id = v_subject.wine_id and h.annata = v_subject.annata
                     and h.valuta = 'eur'
                     and catalog.parse_format_ml(h.formato) = v_ml
                     and h.observed_at between now() - interval '17520 hours' and now()
                   order by h.tipo desc, h.observed_at desc, h.prezzo_cents, h.formato, h.fonte
                   limit 500) o), '[]'::jsonb));
end;
$$;

create or replace function public.prezzi_admin_osservazioni(p_wine_slug text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  w public.wines%rowtype;
  v_ml integer;
begin
  perform private.catalog_admin_richiedi();
  if not coalesce((select s.valutazione_admin_enabled from private.prezzi_settings s), false) then
    return jsonb_build_object('abilitata', false);
  end if;
  select * into w from public.wines x where x.slug = left(coalesce(p_wine_slug, ''), 200);
  if not found then
    raise exception 'Vino inesistente.' using errcode = 'P0002';
  end if;
  v_ml := catalog.parse_format_ml(w.formato);
  return jsonb_build_object('abilitata', true,
    'vino', jsonb_build_object('produttore', w.produttore, 'nome', w.nome),
    'soggetto', jsonb_build_object('vinoId', w.id, 'annata', w.annata, 'formatoMl', v_ml, 'valuta', 'eur'),
    -- elenco CHIUSO uguale al contratto di acquisizione: `origine_ref` (annuncio o ordine) non esce mai
    'osservazioni', coalesce((select jsonb_agg(jsonb_build_object('id', o.id,
          'tipo', case o.tipo when 'vendita' then 'realizzato' else 'richiesto' end,
          'centesimi', o.prezzo_cents, 'valuta', o.valuta, 'osservatoIl', o.observed_at, 'fonte', o.fonte::text,
          'vinoId', o.wine_id, 'annata', w.annata, 'formatoMl', catalog.parse_format_ml(o.formato), 'condizione', null)
          order by o.tipo desc, o.observed_at desc, o.id)
        from (select p.id, p.tipo, p.prezzo_cents, p.valuta, p.observed_at, p.fonte, p.wine_id, p.formato
                from public.wine_price_observations p
               where p.wine_id = w.id and w.annata is not null
                 and p.valuta = 'eur'
                     and catalog.parse_format_ml(p.formato) = v_ml
                     and p.observed_at between now() - interval '17520 hours' and now()
               order by p.tipo desc, p.observed_at desc, p.id
               limit 500) o),
      '[]'::jsonb));
end;
$$;
