-- WI-012 — gestione del catalogo dal sito: porte di amministrazione.
--
-- Nessuna seconda autenticazione: il ruolo reale `admin` di `public.user_roles`, verificato in ogni porta. Nessun
-- privilegio nuovo sulle tabelle: le porte sono SECURITY DEFINER, chiamano le funzioni del curatore già esistenti con
-- un esecutore identificato (`admin:<uuid>`), quindi ogni modifica lascia il proprio evento in `canonical_events`.
-- Le liste sono paginate sul server (al massimo 50 righe).
--
-- Deliberatamente NON esposti al web: fusioni e loro annullamento, ritiro definitivo di un'entità, regola e
-- interruttori di promozione, proiezione pubblica, acquisizione delle proposte e budget AI.

create or replace function private.catalog_admin_richiedi()
returns text language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null or not exists (select 1 from public.user_roles ur where ur.user_id = v_uid and ur.role = 'admin') then
    raise exception 'Operazione non autorizzata.' using errcode = '42501';
  end if;
  return 'admin:' || v_uid::text;
end;
$$;
revoke all on function private.catalog_admin_richiedi() from public, anon, authenticated, service_role;

create or replace function private.catalog_admin_pagina(p_pagina integer, p_per_pagina integer,
  out righe integer, out salto integer)
language sql immutable set search_path = '' as $$
  select least(greatest(coalesce(p_per_pagina, 20), 1), 50),
         (least(greatest(coalesce(p_pagina, 1), 1), 10000) - 1) * least(greatest(coalesce(p_per_pagina, 20), 1), 50);
$$;
revoke all on function private.catalog_admin_pagina(integer, integer) from public, anon, authenticated, service_role;

-- Un testo di ricerca diventa parole normalizzate: `%` e `_` non sopravvivono alla normalizzazione.
create or replace function private.catalog_admin_parole(p_testo text)
returns text[] language sql immutable set search_path = '' as $$
  select coalesce((array_agg(t))[1:6], array[]::text[])
    from unnest(string_to_array(public.vini_normalizza(left(p_testo, 120)), ' ')) t
   where length(t) >= 2;
$$;
revoke all on function private.catalog_admin_parole(text) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- Letture
-- ---------------------------------------------------------------------------------------------
create or replace function public.catalogo_admin_riepilogo()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.catalog_admin_richiedi();
  return jsonb_build_object(
    'vini', (select jsonb_build_object(
        'canonici', count(*), 'attivi', count(*) filter (where status = 'active'),
        'nativi', count(*) filter (where origin = 'manual'),
        'nativi_pubblicati', count(*) filter (where native_published_at is not null and status = 'active'),
        'senza_lwin', count(*) filter (where lwin7 is null and status = 'active')) from catalog.wines),
    'produttori', (select count(*) from catalog.producers),
    'proposte', (select jsonb_build_object(
        'aperte', count(*) filter (where status = 'aperta'),
        'aperte_identita_nuove', count(*) filter (where status = 'aperta' and match_kind = 'sconosciuto'),
        'aperte_ambigue', count(*) filter (where status = 'aperta' and match_kind = 'ambiguo'),
        'totali', count(*)) from catalog.contributions),
    'da_decidere', jsonb_build_object(
        'duplicati', (select count(*) from catalog.duplicate_candidates where review_status = 'open'),
        'attributi', (select count(*) from catalog.attribute_claims where status = 'proposed'),
        'collegamenti', (select count(*) from catalog.wine_links where status = 'proposed')),
    'fonte', jsonb_build_object(
        'record', (select count(*) from catalog.source_records),
        'ultima_importazione', (select jsonb_build_object('stato', r.status, 'iniziata', r.started_at,
              'conclusa', r.finished_at, 'righe', r.rows_read)
            from catalog.import_runs r order by r.seq desc limit 1),
        'rilievi_import', (select count(*) from catalog.import_findings)),
    'interruttori', jsonb_build_object(
        'regola', (select r.status from catalog.promotion_rules r where r.version = 'lwin-conservative-v1'),
        'promozione', (select s.enabled from catalog.promotion_settings s),
        'proiezione_pubblica', (select s.enabled from catalog.public_projection_settings s),
        'proposte_utenti', (select s.user_proposals_enabled from catalog.intake_settings s),
        'acquisizione_annunci', (select s.listing_harvest_enabled from catalog.intake_settings s),
        'chiusura_automatica_note', (select s.auto_close_known_enabled from catalog.intake_settings s)));
end;
$$;

create or replace function public.catalogo_admin_vini(p_testo text default '', p_stato text default null,
  p_origine text default null, p_pagina integer default 1, p_per_pagina integer default 20)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_page record;
  v_words text[] := private.catalog_admin_parole(p_testo);
  v_code text := nullif(btrim(coalesce(p_testo, '')), '');
  v_where text := 'true';
  v_total bigint;
  v_rows jsonb;
begin
  perform private.catalog_admin_richiedi();
  select * into v_page from private.catalog_admin_pagina(p_pagina, p_per_pagina);
  if v_code ~ '^[0-9]{7}$' then
    v_where := format('w.lwin7 = %L', v_code);
  elsif cardinality(v_words) > 0 then
    v_where := (select string_agg(format('w.search_key like %L', '%' || t || '%'), ' and ') from unnest(v_words) t);
  end if;
  if p_stato is not null then
    if p_stato not in ('active', 'merged', 'retired') then
      raise exception 'Filtro di stato non valido.' using errcode = '22023';
    end if;
    v_where := v_where || format(' and w.status = %L', p_stato);
  end if;
  if p_origine is not null then
    if p_origine not in ('promotion', 'manual') then
      raise exception 'Filtro di origine non valido.' using errcode = '22023';
    end if;
    v_where := v_where || format(' and w.origin = %L', p_origine);
  end if;
  -- Il conteggio si ferma a 1.001: oltre, la pagina dice «più di 1.000» invece di contare centinaia di migliaia di righe.
  execute format('select count(*) from (select 1 from catalog.wines w where %s limit 1001) x', v_where) into v_total;
  execute format($q$
    select coalesce(jsonb_agg(to_jsonb(r) order by r.nome_ordine, r.id), '[]'::jsonb) from (
      select w.id, w.lwin7, w.name as nome, p.name as produttore, w.origin as origine, w.status as stato,
             w.native_published_at is not null as pubblicato, w.updated_at as aggiornato, w.search_key as nome_ordine
        from catalog.wines w join catalog.producers p on p.id = w.producer_id
       where %s order by w.search_key, w.id limit %s offset %s) r$q$, v_where, v_page.righe, v_page.salto)
  into v_rows;
  return jsonb_build_object('totale', least(v_total, 1000), 'oltre', v_total > 1000, 'righe', v_rows);
end;
$$;

create or replace function public.catalogo_admin_vino(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v jsonb;
begin
  perform private.catalog_admin_richiedi();
  select jsonb_build_object(
    'id', w.id, 'nome', w.name, 'lwin7', w.lwin7, 'origine', w.origin, 'stato', w.status, 'confluito_in', w.merged_into,
    'colore', w.colour, 'tipo', w.wine_type, 'sottotipo', w.sub_type, 'denominazione', w.designation,
    'classificazione', w.classification, 'nota_provenienza', w.provenance_note,
    'pubblicato_il', w.native_published_at, 'creato', w.created_at,
    'territorio', (select jsonb_build_object('id', t.id, 'nome', t.name, 'tipo', t.kind) from catalog.territories t where t.id = w.territory_id),
    'fonte', (select jsonb_build_object('codice', s.code, 'nome', s.name, 'autorizzazione', s.authorization_status)
                from catalog.sources s where s.id = w.source_id),
    'produttore', (select jsonb_build_object('id', p.id, 'nome', p.name, 'stato', p.status, 'origine', p.origin)
                     from catalog.producers p where p.id = w.producer_id),
    'annate', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'anno', a.vintage_year, 'non_millesimato', a.is_non_vintage,
                 'lwin11', a.lwin11, 'nota', a.provenance_note,
                 'formati', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'ml', f.volume_ml, 'pezzi', f.units_per_pack)
                              order by f.volume_ml, f.units_per_pack) from catalog.wine_formats f where f.vintage_id = a.id), '[]'::jsonb))
               order by a.vintage_year desc nulls last) from catalog.wine_vintages a where a.wine_id = w.id), '[]'::jsonb),
    'attributi', coalesce((select jsonb_agg(to_jsonb(c) order by c.id desc) from (
        select c.id, c.attribute_key as attributo, c.value as valore, c.status as stato, c.evidence_note as evidenza,
               s.name as fonte, s.authorization_status as fonte_autorizzazione, c.reviewed_by as revisore,
               c.reviewed_at as rivisto, c.created_at as creato
          from catalog.attribute_claims c join catalog.sources s on s.id = c.source_id
         where c.wine_id = w.id
            or c.vintage_id in (select a.id from catalog.wine_vintages a where a.wine_id = w.id)
         order by c.id desc limit 50) c), '[]'::jsonb),
    'alias', coalesce((select jsonb_agg(jsonb_build_object('alias', e.alias, 'tipo', e.kind) order by e.id)
                 from (select * from catalog.entity_aliases e where e.wine_id = w.id order by e.id limit 50) e), '[]'::jsonb),
    'collegamenti', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'vino_app', l.public_wine_slug, 'annata_id', l.vintage_id,
                 'metodo', l.method, 'stato', l.status) order by l.id desc)
                 from catalog.wine_links l join catalog.wine_vintages a on a.id = l.vintage_id where a.wine_id = w.id), '[]'::jsonb),
    'proposte', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'stato', c.status, 'origine', c.first_origin)
                 order by c.id desc) from (select * from catalog.contributions c where c.resolved_wine_id = w.id
                 order by c.id desc limit 20) c), '[]'::jsonb),
    'storico', coalesce((select jsonb_agg(to_jsonb(h) order by h.id desc) from (
        select e.id, e.action as azione, e.entity_type as entita, e.actor as esecutore, e.detail as dettaglio, e.created_at as quando
          from catalog.canonical_events e
         where e.entity_ref = w.id::text
            or (e.entity_type = 'wine_vintage' and e.entity_ref in (select a.id::text from catalog.wine_vintages a where a.wine_id = w.id))
         order by e.id desc limit 50) h), '[]'::jsonb))
    into v from catalog.wines w where w.id = p_id;
  return v;
end;
$$;

create or replace function public.catalogo_admin_proposte(p_stato text default 'aperta', p_pagina integer default 1,
  p_per_pagina integer default 20)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_page record;
begin
  perform private.catalog_admin_richiedi();
  select * into v_page from private.catalog_admin_pagina(p_pagina, p_per_pagina);
  if p_stato is null or p_stato not in ('aperta', 'collegata', 'creata', 'rifiutata', 'duplicata', 'gia_collegata', 'ritirata') then
    raise exception 'Filtro di stato non valido.' using errcode = '22023';
  end if;
  -- Nessun identificativo di chi ha proposto: alla revisione servono i dati del vino, non la persona.
  return jsonb_build_object(
    'totale', (select count(*) from catalog.contributions c where c.status = p_stato),
    'righe', coalesce((select jsonb_agg(to_jsonb(r) order by r.ultima desc, r.id desc) from (
      select c.id, c.identity as dati, c.first_origin as origine, c.trust as affidabilita, c.match_kind as corrispondenza,
             c.missing_fields as mancanti, c.status as stato, c.submissions_count as invii, c.created_at as creata,
             c.last_seen_at as ultima, c.review_note as nota, c.resolved_wine_id as vino_risolto,
             (select coalesce(jsonb_agg(
                       cand || coalesce((select jsonb_build_object('produttore', p.name, 'nome', w.name, 'lwin7_attuale', w.lwin7,
                                                                   'origine', w.origin)
                                           from catalog.wines w join catalog.producers p on p.id = w.producer_id
                                          where w.id = (cand ->> 'wine_id')::uuid),
                                        (select jsonb_build_object('produttore', sr.payload ->> 'producer_name', 'nome', sr.payload ->> 'wine',
                                                                   'paese', sr.country)
                                           from catalog.source_records sr where sr.id = (cand ->> 'source_record_id')::bigint),
                                        '{}'::jsonb)), '[]'::jsonb)
                from jsonb_array_elements(c.match_candidates) cand) as candidati
        from catalog.contributions c
       where c.status = p_stato
       order by c.last_seen_at desc, c.id desc limit v_page.righe offset v_page.salto) r), '[]'::jsonb));
end;
$$;

create or replace function public.catalogo_admin_code(p_pagina integer default 1, p_per_pagina integer default 20)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_page record;
begin
  perform private.catalog_admin_richiedi();
  select * into v_page from private.catalog_admin_pagina(p_pagina, p_per_pagina);
  return jsonb_build_object(
    'duplicati', coalesce((select jsonb_agg(to_jsonb(r) order by r.id) from (
        select d.id, d.reason as motivo, case when d.wine_a is null then 'producer' else 'wine' end as tipo,
               coalesce((select p.name || ' — ' || w.name || coalesce(' · LWIN ' || w.lwin7, '') from catalog.wines w
                           join catalog.producers p on p.id = w.producer_id where w.id = d.wine_a),
                        (select p.name from catalog.producers p where p.id = d.producer_a)) as primo,
               coalesce((select p.name || ' — ' || w.name || coalesce(' · LWIN ' || w.lwin7, '') from catalog.wines w
                           join catalog.producers p on p.id = w.producer_id where w.id = d.wine_b),
                        (select p.name from catalog.producers p where p.id = d.producer_b)) as secondo,
               d.wine_a as vino_a, d.wine_b as vino_b
          from catalog.duplicate_candidates d where d.review_status = 'open'
         order by d.id limit v_page.righe offset v_page.salto) r), '[]'::jsonb),
    'duplicati_totale', (select count(*) from catalog.duplicate_candidates d where d.review_status = 'open'),
    'attributi', coalesce((select jsonb_agg(to_jsonb(r) order by r.id) from (
        select c.id, c.attribute_key as attributo, c.value as valore, c.evidence_note as evidenza, s.name as fonte,
               coalesce(c.wine_id, (select a.wine_id from catalog.wine_vintages a where a.id = c.vintage_id)) as vino_id,
               (select cur.value from catalog.attribute_claims cur
                 where cur.status = 'accepted' and cur.attribute_key = c.attribute_key
                   and coalesce(cur.producer_id, cur.wine_id, cur.vintage_id, cur.format_id)
                     = coalesce(c.producer_id, c.wine_id, c.vintage_id, c.format_id) limit 1) as valore_attuale
          from catalog.attribute_claims c join catalog.sources s on s.id = c.source_id
         where c.status = 'proposed' order by c.id limit v_page.righe offset v_page.salto) r), '[]'::jsonb),
    'attributi_totale', (select count(*) from catalog.attribute_claims c where c.status = 'proposed'),
    'collegamenti', coalesce((select jsonb_agg(to_jsonb(r) order by r.id) from (
        select l.id, l.public_wine_slug as vino_app, l.method as metodo, a.wine_id as vino_id, a.vintage_year as anno,
               p.name as produttore, w.name as nome,
               (select pw.produttore || ' — ' || pw.nome || ' ' || pw.annata::text from public.wines pw where pw.id = l.public_wine_id) as descrizione_app
          from catalog.wine_links l
          join catalog.wine_vintages a on a.id = l.vintage_id
          join catalog.wines w on w.id = a.wine_id
          join catalog.producers p on p.id = w.producer_id
         where l.status = 'proposed' order by l.id limit v_page.righe offset v_page.salto) r), '[]'::jsonb),
    'collegamenti_totale', (select count(*) from catalog.wine_links l where l.status = 'proposed'));
end;
$$;

create or replace function public.catalogo_admin_storico(p_pagina integer default 1, p_per_pagina integer default 30)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_page record;
begin
  perform private.catalog_admin_richiedi();
  select * into v_page from private.catalog_admin_pagina(p_pagina, p_per_pagina);
  return coalesce((select jsonb_agg(to_jsonb(r) order by r.id desc) from (
    select e.id, e.action as azione, e.entity_type as entita, e.entity_ref as riferimento, e.actor as esecutore,
           e.detail as dettaglio, e.created_at as quando
      from catalog.canonical_events e order by e.id desc limit v_page.righe offset v_page.salto) r), '[]'::jsonb);
end;
$$;

create or replace function public.catalogo_admin_fonti()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.catalog_admin_richiedi();
  return jsonb_build_object(
    'fonti', coalesce((select jsonb_agg(jsonb_build_object('codice', s.code, 'nome', s.name, 'licenza', s.license,
                 'autorizzazione', s.authorization_status, 'verificata_il', s.verified_at) order by s.code)
               from catalog.sources s), '[]'::jsonb),
    'importazioni', coalesce((select jsonb_agg(to_jsonb(r) order by r.seq desc) from (
        select i.seq, i.status as stato, i.started_at as iniziata, i.finished_at as conclusa, i.rows_read as righe,
               i.counts as conteggi, n.file_name as file, n.file_sha256 as impronta_file, i.importer_version as importatore
          from catalog.import_runs i join catalog.import_snapshots n on n.id = i.snapshot_id
         order by i.seq desc limit 10) r), '[]'::jsonb),
    'conflitti_lwin_nativi', coalesce((select jsonb_agg(to_jsonb(x)) from catalog.lwin_native_conflicts(50) x), '[]'::jsonb));
end;
$$;

create or replace function public.catalogo_admin_territori(p_testo text)
returns table (id bigint, nome text, tipo text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare v_key text := catalog.fold_text(left(p_testo, 80));
begin
  perform private.catalog_admin_richiedi();
  if v_key is null or length(v_key) < 2 then
    return;
  end if;
  return query
    select t.id, t.name, t.kind from catalog.territories t
     where t.name_key like replace(replace(replace(v_key, '\', '\\'), '%', '\%'), '_', '\_') || '%'
     order by length(t.name_key), t.name_key, t.id limit 20;
end;
$$;

-- Ricerca nella fonte LWIN (per chiave esatta «produttore nome» o per codice): serve a non creare un nativo che esiste già.
create or replace function public.catalogo_admin_cerca_fonte(p_testo text)
returns table (source_record_id bigint, lwin7 text, produttore text, nome text, paese text, stato text, canonico uuid)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_text text := btrim(coalesce(p_testo, ''));
  v_key text := public.vini_normalizza(left(p_testo, 200));
begin
  perform private.catalog_admin_richiedi();
  if v_text ~ '^[0-9]{7}$' then
    return query
      select r.id, r.external_id, r.payload ->> 'producer_name', r.payload ->> 'wine', r.country, r.status,
             (select w.id from catalog.wines w where w.lwin7 = r.external_id)
        from catalog.sources s join catalog.source_records r on r.source_id = s.id and r.external_id = v_text
       limit 10;
  elsif length(v_key) >= 4 then
    return query
      select r.id, r.external_id, r.payload ->> 'producer_name', r.payload ->> 'wine', r.country, r.status,
             (select w.id from catalog.wines w where w.lwin7 = r.external_id)
        from catalog.source_records r
       where r.status = 'Live' and r.scope = 'wine'
         and public.vini_normalizza(coalesce(r.payload ->> 'producer_name', '') || ' ' || coalesce(r.payload ->> 'wine', '')) = v_key
       order by r.external_id limit 20;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- Scritture
-- ---------------------------------------------------------------------------------------------
-- Controllo dei duplicati prima di creare un vino nativo: stesso nome canonico o record LWIN con la stessa chiave
-- richiedono una conferma esplicita e motivata. La somiglianza non basta mai a fondere.
create or replace function private.catalog_admin_nuovo_vino(p_data jsonb, p_note text, p_actor text)
returns uuid language plpgsql volatile security definer set search_path = '' as $$
declare
  v_producer uuid := nullif(p_data ->> 'produttore_id', '')::uuid;
  v_producer_name text;
  v_key text;
  v_wine uuid;
begin
  if p_note is null or length(btrim(p_note)) = 0 then
    raise exception 'La nota di provenienza è obbligatoria.' using errcode = '22023';
  end if;
  if v_producer is null then
    if nullif(btrim(coalesce(p_data ->> 'produttore', '')), '') is null then
      raise exception 'Indica il produttore.' using errcode = '22023';
    end if;
    -- Stesso nome normalizzato di un produttore attivo: si sceglie quello, o si conferma che è un altro.
    if exists (select 1 from catalog.producers p where p.status = 'active'
                 and p.name_key = catalog.fold_text(p_data ->> 'produttore'))
       and not coalesce((p_data ->> 'conferma_produttore_distinto')::boolean, false) then
      raise exception 'Esiste già un produttore con questo nome: selezionalo oppure conferma che è un altro.' using errcode = '23505';
    end if;
    v_producer := catalog.add_manual_producer(p_data ->> 'produttore', nullif(p_data ->> 'paese_territorio_id', '')::bigint,
                                              p_note, p_actor);
  end if;
  select p.name into v_producer_name from catalog.producers p where p.id = v_producer;
  v_key := public.vini_normalizza(coalesce(v_producer_name, '') || ' ' || coalesce(p_data ->> 'nome', ''));
  if not coalesce((p_data ->> 'conferma_non_duplicato')::boolean, false) then
    if exists (select 1 from catalog.wines w where w.status = 'active' and w.search_key = v_key) then
      raise exception 'Esiste già un vino canonico con lo stesso nome: collegalo oppure conferma che è un altro.' using errcode = '23505';
    end if;
    if exists (select 1 from catalog.source_records r where r.status = 'Live' and r.scope = 'wine'
                 and public.vini_normalizza(coalesce(r.payload ->> 'producer_name', '') || ' ' || coalesce(r.payload ->> 'wine', '')) = v_key) then
      raise exception 'La fonte LWIN ha un vino con lo stesso nome: verificalo prima di crearne uno nativo.' using errcode = '23505';
    end if;
  end if;
  v_wine := catalog.add_manual_wine(v_producer, p_data ->> 'nome', nullif(p_data ->> 'colore', ''), nullif(p_data ->> 'tipo', ''),
              null, nullif(p_data ->> 'denominazione', ''), nullif(p_data ->> 'classificazione', ''),
              nullif(p_data ->> 'territorio_id', '')::bigint, p_note, p_actor);
  return v_wine;
end;
$$;
revoke all on function private.catalog_admin_nuovo_vino(jsonb, text, text) from public, anon, authenticated, service_role;

-- Annata: nasce solo se qualcuno la dichiara. Se c'è già, si riusa.
create or replace function private.catalog_admin_annata(p_wine uuid, p_year integer, p_non_vintage boolean, p_note text, p_actor text)
returns uuid language plpgsql volatile security definer set search_path = '' as $$
declare v_id uuid;
begin
  if p_year is null and not coalesce(p_non_vintage, false) then
    return null;
  end if;
  select a.id into v_id from catalog.wine_vintages a
   where a.wine_id = p_wine and ((p_year is not null and a.vintage_year = p_year)
                                 or (coalesce(p_non_vintage, false) and a.is_non_vintage));
  if v_id is null then
    v_id := catalog.add_wine_vintage(p_wine, p_year, coalesce(p_non_vintage, false), null, null, null, p_note, p_actor);
  end if;
  return v_id;
end;
$$;
revoke all on function private.catalog_admin_annata(uuid, integer, boolean, text, text) from public, anon, authenticated, service_role;

create or replace function private.catalog_admin_formato(p_vintage uuid, p_ml integer, p_note text, p_actor text)
returns uuid language plpgsql volatile security definer set search_path = '' as $$
declare v_id uuid;
begin
  if p_vintage is null or p_ml is null then
    return null;
  end if;
  select f.id into v_id from catalog.wine_formats f where f.vintage_id = p_vintage and f.volume_ml = p_ml and f.units_per_pack = 1;
  if v_id is null then
    v_id := catalog.add_wine_format(p_vintage, p_ml, 1, null, null, null, null, p_note, p_actor);
  end if;
  return v_id;
end;
$$;
revoke all on function private.catalog_admin_formato(uuid, integer, text, text) from public, anon, authenticated, service_role;

create or replace function public.catalogo_admin_proposta_decidi(p_id bigint, p_decisione text, p_dati jsonb default '{}'::jsonb,
  p_nota text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor text := private.catalog_admin_richiedi();
  c catalog.contributions%rowtype;
  v_data jsonb := coalesce(p_dati, '{}'::jsonb);
  v_note text := nullif(btrim(coalesce(p_nota, '')), '');
  v_provenance text;
  v_wine uuid;
  v_vintage uuid;
  v_format uuid;
  v_status text;
  v_year integer;
  v_nv boolean;
  v_ml integer;
  v_link bigint;
  v_public record;
begin
  -- La riga resta bloccata: due decisioni concorrenti sulla stessa proposta non passano entrambe.
  select * into c from catalog.contributions where id = p_id for update;
  if not found or c.status <> 'aperta' then
    raise exception 'La proposta non esiste o è già stata decisa.' using errcode = 'P0002';
  end if;
  if p_decisione is null or p_decisione not in ('rifiuta', 'duplicata', 'collega', 'crea') then
    raise exception 'Decisione non valida.' using errcode = '22023';
  end if;
  if p_decisione in ('rifiuta', 'duplicata') then
    if v_note is null then
      raise exception 'Il motivo è obbligatorio.' using errcode = '22023';
    end if;
    v_status := case p_decisione when 'rifiuta' then 'rifiutata' else 'duplicata' end;
  else
    v_provenance := coalesce(v_note, 'Proposta ' || c.id || ' (' || c.first_origin || ', ' || c.trust || ') approvata dal curatore.');
    if p_decisione = 'collega' then
      v_wine := nullif(v_data ->> 'wine_id', '')::uuid;
      if not exists (select 1 from catalog.wines w where w.id = v_wine and w.status = 'active') then
        raise exception 'Scegli un vino canonico attivo.' using errcode = 'P0002';
      end if;
      v_status := 'collegata';
    else
      -- i dati proposti valgono come punto di partenza; il curatore può correggerli prima di creare
      v_wine := private.catalog_admin_nuovo_vino(
        jsonb_build_object('produttore', c.identity ->> 'produttore', 'nome', c.identity ->> 'nome',
                           'tipo', c.identity ->> 'tipo', 'denominazione', c.identity ->> 'denominazione')
        || (v_data - array['wine_id', 'crea_annata', 'collega_vino_app']), v_provenance, v_actor);
      v_status := 'creata';
    end if;
    -- Annata e formato: solo se la proposta li dichiara E il curatore non li ha esclusi. Nessuna annata inventata.
    if coalesce((v_data ->> 'crea_annata')::boolean, true) then
      v_year := (c.identity ->> 'annata')::integer;
      v_nv := coalesce((c.identity ->> 'non_millesimato')::boolean, false);
      v_ml := (c.identity ->> 'formato_ml')::integer;
      v_vintage := private.catalog_admin_annata(v_wine, v_year, v_nv, v_provenance, v_actor);
      v_format := private.catalog_admin_formato(v_vintage, v_ml, v_provenance, v_actor);
    end if;
    -- Collegamento applicativo: si PROPONE soltanto; l'attivazione è una seconda decisione.
    if coalesce((v_data ->> 'collega_vino_app')::boolean, false) and v_vintage is not null then
      select w.id, w.slug into v_public
        from catalog.contribution_submissions s join public.wines w on w.id = s.public_wine_id
       where s.contribution_id = c.id
         and not exists (select 1 from catalog.wine_links l where l.public_wine_id = w.id and l.status in ('proposed', 'active'))
       order by s.id limit 1;
      if v_public.id is not null then
        v_link := catalog.propose_wine_link(v_public.id, v_public.slug, v_vintage, 'manual', v_actor);
      end if;
    end if;
  end if;
  update catalog.contributions
     set status = v_status, resolved_wine_id = v_wine, resolved_vintage_id = v_vintage, resolved_format_id = v_format,
         reviewed_by = v_actor, reviewed_at = now(), review_note = v_note
   where id = c.id;
  perform catalog.record_canonical_event('review_contribution', 'contribution', c.id::text, v_actor,
    jsonb_build_object('decisione', p_decisione, 'wine_id', v_wine, 'vintage_id', v_vintage, 'link_id', v_link));
  return jsonb_build_object('stato', v_status, 'wine_id', v_wine, 'vintage_id', v_vintage, 'format_id', v_format,
                            'collegamento_proposto', v_link);
end;
$$;

-- Le altre modifiche: elenco CHIUSO di azioni, ciascuna sulle funzioni del curatore.
create or replace function public.catalogo_admin_azione(p_azione text, p_dati jsonb default '{}'::jsonb, p_nota text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor text := private.catalog_admin_richiedi();
  v_data jsonb := coalesce(p_dati, '{}'::jsonb);
  v_note text := nullif(btrim(coalesce(p_nota, '')), '');
  v_id uuid;
  v_num bigint;
  v_source uuid;
  v_public record;
begin
  if p_azione = 'nuovo_vino' then
    v_id := private.catalog_admin_nuovo_vino(v_data, v_note, v_actor);
    return jsonb_build_object('id', v_id);
  elsif p_azione = 'annata' then
    if v_note is null then raise exception 'La nota di provenienza è obbligatoria.' using errcode = '22023'; end if;
    v_id := private.catalog_admin_annata((v_data ->> 'wine_id')::uuid, (v_data ->> 'anno')::integer,
              coalesce((v_data ->> 'non_millesimato')::boolean, false), v_note, v_actor);
    if v_id is null then raise exception 'Indica un anno oppure «non millesimato».' using errcode = '22023'; end if;
    return jsonb_build_object('id', v_id);
  elsif p_azione = 'formato' then
    if v_note is null then raise exception 'La nota di provenienza è obbligatoria.' using errcode = '22023'; end if;
    v_id := private.catalog_admin_formato((v_data ->> 'vintage_id')::uuid, (v_data ->> 'ml')::integer, v_note, v_actor);
    if v_id is null then raise exception 'Annata e volume sono necessari.' using errcode = '22023'; end if;
    return jsonb_build_object('id', v_id);
  elsif p_azione in ('pubblica', 'ritira_pubblicazione') then
    perform catalog.set_native_publication((v_data ->> 'wine_id')::uuid, p_azione = 'pubblica', v_note, v_actor);
    return jsonb_build_object('ok', true);
  elsif p_azione = 'assegna_lwin' then
    perform catalog.assign_official_lwin((v_data ->> 'wine_id')::uuid, v_data ->> 'lwin7', v_note, v_actor);
    return jsonb_build_object('ok', true);
  elsif p_azione = 'attributo_proponi' then
    if v_note is null then raise exception 'Indica l''evidenza del dato.' using errcode = '22023'; end if;
    select s.id into v_source from catalog.sources s where s.code = 'VINEA-CURATORE' and s.authorization_status = 'authorized';
    if v_source is null then raise exception 'La fonte del curatore non è autorizzata.' using errcode = '42501'; end if;
    v_num := catalog.propose_attribute_claim(v_data ->> 'attributo', v_data ->> 'soggetto', (v_data ->> 'soggetto_id')::uuid,
               v_data -> 'valore', v_source, null, v_note, v_actor);
    return jsonb_build_object('id', v_num);
  elsif p_azione = 'attributo_decidi' then
    perform catalog.review_attribute_claim((v_data ->> 'id')::bigint, v_data ->> 'decisione', v_actor);
    return jsonb_build_object('ok', true);
  elsif p_azione = 'collegamento_proponi' then
    select w.id, w.slug into v_public from public.wines w where w.slug = v_data ->> 'vino_app';
    if v_public.id is null then raise exception 'Vino dell''applicazione inesistente.' using errcode = 'P0002'; end if;
    v_num := catalog.propose_wine_link(v_public.id, v_public.slug, (v_data ->> 'vintage_id')::uuid, 'manual', v_actor);
    return jsonb_build_object('id', v_num);
  elsif p_azione = 'collegamento_decidi' then
    perform catalog.review_wine_link((v_data ->> 'id')::bigint, v_data ->> 'decisione', v_actor);
    return jsonb_build_object('ok', true);
  elsif p_azione = 'duplicato_apri' then
    v_num := catalog.open_duplicate_candidate('wine', (v_data ->> 'a')::uuid, (v_data ->> 'b')::uuid, v_note, v_actor);
    return jsonb_build_object('id', v_num);
  elsif p_azione = 'duplicato_decidi' then
    perform catalog.review_duplicate_candidate((v_data ->> 'id')::bigint, v_data ->> 'decisione', v_actor, v_note);
    return jsonb_build_object('ok', true);
  elsif p_azione = 'acquisisci_annunci' then
    -- rispetta l'interruttore `listing_harvest_enabled`, che dal web non si accende
    return catalog.harvest_listings(coalesce((v_data ->> 'limite')::integer, 100), v_actor);
  end if;
  raise exception 'Azione non prevista.' using errcode = '22023';
end;
$$;

revoke all on function
  public.catalogo_admin_riepilogo(),
  public.catalogo_admin_vini(text, text, text, integer, integer),
  public.catalogo_admin_vino(uuid),
  public.catalogo_admin_proposte(text, integer, integer),
  public.catalogo_admin_code(integer, integer),
  public.catalogo_admin_storico(integer, integer),
  public.catalogo_admin_fonti(),
  public.catalogo_admin_territori(text),
  public.catalogo_admin_cerca_fonte(text),
  public.catalogo_admin_proposta_decidi(bigint, text, jsonb, text),
  public.catalogo_admin_azione(text, jsonb, text)
  from public, anon, authenticated, service_role;
grant execute on function
  public.catalogo_admin_riepilogo(),
  public.catalogo_admin_vini(text, text, text, integer, integer),
  public.catalogo_admin_vino(uuid),
  public.catalogo_admin_proposte(text, integer, integer),
  public.catalogo_admin_code(integer, integer),
  public.catalogo_admin_storico(integer, integer),
  public.catalogo_admin_fonti(),
  public.catalogo_admin_territori(text),
  public.catalogo_admin_cerca_fonte(text),
  public.catalogo_admin_proposta_decidi(bigint, text, jsonb, text),
  public.catalogo_admin_azione(text, jsonb, text)
  to authenticated;

notify pgrst, 'reload schema';
