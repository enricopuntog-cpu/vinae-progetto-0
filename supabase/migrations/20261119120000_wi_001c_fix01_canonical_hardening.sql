-- WI-001C-FIX-01 — correzioni al catalogo canonico dopo la QA indipendente (D-1 … D-6).
--
-- ADDITIVA: la migration 20261119100000 è stata pubblicata ed è CONGELATA; questa la corregge senza toccarla.
-- Non popola nulla, non attiva la promozione (interruttore spento, regola in bozza), non fonde, non cancella.
--
--   D-1  l'approvazione di una regola è legata alla logica eseguibile (impronta delle funzioni) e alla versione esatta
--        `lwin-conservative-v1`; una regola approvata è immutabile; cambiare il corpo delle funzioni invalida l'approvazione.
--   D-2  `origin = 'manual'` non può portare LWIN né provenienza da source_records (vincolo + nota di provenienza obbligatoria).
--   D-3  la fusione è autorizzata solo per la coppia e la direzione registrate; ogni entità ricorda la fusione che l'ha fusa
--        (`merge_id`); l'annullamento vale solo per QUELLA fusione; serializzazione e rilevazione dei cicli.
--   D-4  i record il cui produttore è ritirato (anche via fusione) non bloccano il lotto: sono tracciati in
--        `promotion_exceptions` e il lotto avanza sugli altri.
--   D-5  LWIN-16 = LWIN-11 + volume (5 cifre, ml); LWIN-18 = LWIN-11 + confezione (2 cifre) + volume (5 cifre, ml)
--        (https://web.liv-ex.com/staticPageContent.do?pageKey=LWIN). LWIN-18 NON ha LWIN-16 come prefisso.
--   D-6  il curatore non scrive più direttamente: SELECT + EXECUTE su porte `SECURITY DEFINER` (search_path vuoto) che
--        verificano esecutore, stato e revisione e registrano l'evento. Nessun superuser, RLS invariata.

-- ---------------------------------------------------------------------------------------------
-- Utilità
-- ---------------------------------------------------------------------------------------------

create or replace function catalog.require_actor(p_actor text)
returns text language plpgsql stable set search_path = '' as $$
begin
  if p_actor is null or length(btrim(p_actor)) = 0 or length(p_actor) > 200 or p_actor ~ '[[:cntrl:]]' then
    raise exception 'catalog: serve un esecutore identificato (1-200 caratteri, senza caratteri di controllo)' using errcode = '22023';
  end if;
  return btrim(p_actor);
end;
$$;

-- Il registro eventi registra anche il ruolo effettivo (SET ROLE) oltre al login: due dati che il testo `actor` non può falsificare.
alter table catalog.canonical_events add column acting_role text default nullif(current_setting('role', true), 'none');

-- ---------------------------------------------------------------------------------------------
-- D-2: manuale ≠ promozione
-- ---------------------------------------------------------------------------------------------

alter table catalog.producers add column provenance_note text;
alter table catalog.wines add column provenance_note text;
alter table catalog.producers add constraint producers_manual_origin check (
  origin <> 'manual' or (natural_key is null and source_id is null and source_record_id is null
                         and length(btrim(coalesce(provenance_note, ''))) > 0));
alter table catalog.wines add constraint wines_manual_origin check (
  origin <> 'manual' or (lwin7 is null and source_id is null and source_record_id is null
                         and length(btrim(coalesce(provenance_note, ''))) > 0));

-- ---------------------------------------------------------------------------------------------
-- D-3: la fusione che governa ogni entità fusa
-- ---------------------------------------------------------------------------------------------

alter table catalog.producers add column merge_id bigint references catalog.entity_merges(id);
alter table catalog.wines add column merge_id bigint references catalog.entity_merges(id);
alter table catalog.producers add constraint producers_merge_state check ((status = 'merged') = (merge_id is not null));
alter table catalog.wines add constraint wines_merge_state check ((status = 'merged') = (merge_id is not null));
create index producers_merge_id_idx on catalog.producers (merge_id) where merge_id is not null;
create index wines_merge_id_idx on catalog.wines (merge_id) where merge_id is not null;

-- La vecchia firma (senza merge_id) lascia il posto a quella esatta.
drop function catalog.merge_authorized(text, uuid, uuid, boolean);

-- Fusione autorizzata = esiste QUELLA riga di fusione, ancora attiva, su un candidato rivisto «same», con la direzione esatta:
-- lato conservato `a` → si conserva producer_a/wine_a e si scarta il b; `b` → viceversa. Il conservato deve essere attivo.
create or replace function catalog.merge_authorized(p_kind text, p_from uuid, p_into uuid, p_merge_id bigint)
returns boolean language sql stable set search_path = '' as $$
  select exists (
    select 1 from catalog.entity_merges m join catalog.duplicate_candidates c on c.id = m.candidate_id
     where m.id = p_merge_id and m.reverted_at is null and c.review_status = 'same'
       and case p_kind
             when 'producer' then (m.kept_side = 'a' and c.producer_a = p_into and c.producer_b = p_from)
                               or (m.kept_side = 'b' and c.producer_b = p_into and c.producer_a = p_from)
             when 'wine' then (m.kept_side = 'a' and c.wine_a = p_into and c.wine_b = p_from)
                           or (m.kept_side = 'b' and c.wine_b = p_into and c.wine_a = p_from)
             else false end
       and case p_kind when 'producer' then (select status from catalog.producers where id = p_into)
                       else (select status from catalog.wines where id = p_into) end = 'active');
$$;

-- Annullamento autorizzato = la riga di fusione che ha fuso l'entità (merge_id) è stata annullata, stessa coppia e direzione.
-- Una fusione annullata in passato non autorizza nulla su un'entità fusa da un'altra fusione.
create or replace function catalog.revert_authorized(p_kind text, p_from uuid, p_into uuid, p_merge_id bigint)
returns boolean language sql stable set search_path = '' as $$
  select exists (
    select 1 from catalog.entity_merges m join catalog.duplicate_candidates c on c.id = m.candidate_id
     where m.id = p_merge_id and m.reverted_at is not null and c.review_status = 'same'
       and case p_kind
             when 'producer' then (m.kept_side = 'a' and c.producer_a = p_into and c.producer_b = p_from)
                               or (m.kept_side = 'b' and c.producer_b = p_into and c.producer_a = p_from)
             when 'wine' then (m.kept_side = 'a' and c.wine_a = p_into and c.wine_b = p_from)
                           or (m.kept_side = 'b' and c.wine_b = p_into and c.wine_a = p_from)
             else false end);
$$;

-- Transizioni di stato ammesse: active → merged (fusione registrata), merged → active (annullamento di quella fusione),
-- active → retired (senza fusioni attive verso l'entità). `retired` è definitivo; merged → merged con altro bersaglio è vietato.
-- Serializzata (advisory lock per tipo) per evitare cicli provocati da fusioni concorrenti su coppie diverse.
create or replace function catalog.merge_state_check(p_kind text, p_id uuid, p_old_status text, p_old_into uuid, p_old_mid bigint,
                                                     p_new_status text, p_new_into uuid, p_new_mid bigint)
returns void language plpgsql set search_path = '' as $$
declare
  v_ok boolean := false;
  v_cycle boolean := false;
begin
  if p_new_status is not distinct from p_old_status and p_new_into is not distinct from p_old_into
     and p_new_mid is not distinct from p_old_mid then
    return;
  end if;
  perform pg_advisory_xact_lock(hashtext('catalog.merge:' || p_kind));
  if p_old_status = 'active' and p_new_status = 'retired' and p_new_into is null and p_new_mid is null then
    if (p_kind = 'producer' and exists (select 1 from catalog.producers c where c.merged_into = p_id))
       or (p_kind = 'wine' and exists (select 1 from catalog.wines c where c.merged_into = p_id)) then
      raise exception 'catalog: un''entità con fusioni attive verso di sé non si ritira' using errcode = '55000';
    end if;
    return;
  end if;
  if p_old_status = 'active' and p_new_status = 'merged' and p_new_into is not null and p_new_mid is not null then
    v_ok := catalog.merge_authorized(p_kind, p_id, p_new_into, p_new_mid);
    if v_ok then
      if p_kind = 'producer' then
        with recursive ch(id, depth) as (
          select p_new_into, 0
          union all
          select p.merged_into, ch.depth + 1 from ch join catalog.producers p on p.id = ch.id
           where p.merged_into is not null and ch.depth < 100)
        select exists (select 1 from ch where ch.id = p_id) into v_cycle;
      else
        with recursive ch(id, depth) as (
          select p_new_into, 0
          union all
          select w.merged_into, ch.depth + 1 from ch join catalog.wines w on w.id = ch.id
           where w.merged_into is not null and ch.depth < 100)
        select exists (select 1 from ch where ch.id = p_id) into v_cycle;
      end if;
      if v_cycle then
        raise exception 'catalog: la fusione creerebbe un ciclo' using errcode = '55000';
      end if;
    end if;
  elsif p_old_status = 'merged' and p_new_status = 'active' and p_new_into is null and p_new_mid is null then
    v_ok := catalog.revert_authorized(p_kind, p_id, p_old_into, p_old_mid);
  end if;
  if not v_ok then
    raise exception 'catalog: lo stato di fusione cambia solo con una fusione registrata e coerente (merge_canonical_entity / revert_canonical_merge)'
      using errcode = '55000';
  end if;
end;
$$;

create or replace function catalog.producers_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.id <> old.id or new.origin <> old.origin or new.natural_key is distinct from old.natural_key
     or new.name <> old.name or new.name_key <> old.name_key or new.created_at <> old.created_at
     or new.source_record_id is distinct from old.source_record_id or new.source_id is distinct from old.source_id
     or new.provenance_note is distinct from old.provenance_note then
    raise exception 'catalog: identità e provenienza di un produttore non sono modificabili' using errcode = '55000';
  end if;
  perform catalog.merge_state_check('producer', old.id, old.status, old.merged_into, old.merge_id, new.status, new.merged_into, new.merge_id);
  return new;
end;
$$;

create or replace function catalog.wines_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.id <> old.id or new.origin <> old.origin or new.lwin7 is distinct from old.lwin7
     or new.producer_id <> old.producer_id or new.name <> old.name or new.name_key <> old.name_key
     or new.created_at <> old.created_at or new.source_record_id is distinct from old.source_record_id
     or new.source_id is distinct from old.source_id or new.provenance_note is distinct from old.provenance_note then
    raise exception 'catalog: identità e provenienza di un vino non sono modificabili' using errcode = '55000';
  end if;
  perform catalog.merge_state_check('wine', old.id, old.status, old.merged_into, old.merge_id, new.status, new.merged_into, new.merge_id);
  return new;
end;
$$;

-- Una fusione nasce solo su un candidato «same», non già fuso, con entrambe le entità attive (e, per i vini, dello stesso produttore).
create or replace function catalog.entity_merges_insert_guard()
returns trigger language plpgsql set search_path = '' as $$
declare
  c catalog.duplicate_candidates%rowtype;
  v_keep uuid;
  v_drop uuid;
begin
  if new.reverted_at is not null or new.reverted_by is not null then
    raise exception 'catalog: una fusione nasce non annullata' using errcode = '55000';
  end if;
  select * into c from catalog.duplicate_candidates where id = new.candidate_id;
  if not found or c.review_status <> 'same' then
    raise exception 'catalog: una fusione richiede un candidato rivisto "same"' using errcode = '55000';
  end if;
  if exists (select 1 from catalog.entity_merges m where m.candidate_id = new.candidate_id and m.reverted_at is null) then
    raise exception 'catalog: candidato già fuso' using errcode = '55000';
  end if;
  if c.producer_a is not null then
    v_keep := case new.kept_side when 'a' then c.producer_a else c.producer_b end;
    v_drop := case new.kept_side when 'a' then c.producer_b else c.producer_a end;
    if (select status from catalog.producers where id = v_keep) is distinct from 'active'
       or (select status from catalog.producers where id = v_drop) is distinct from 'active' then
      raise exception 'catalog: entrambe le entità devono essere attive per la fusione' using errcode = '55000';
    end if;
  else
    v_keep := case new.kept_side when 'a' then c.wine_a else c.wine_b end;
    v_drop := case new.kept_side when 'a' then c.wine_b else c.wine_a end;
    if (select status from catalog.wines where id = v_keep) is distinct from 'active'
       or (select status from catalog.wines where id = v_drop) is distinct from 'active' then
      raise exception 'catalog: entrambe le entità devono essere attive per la fusione' using errcode = '55000';
    end if;
    if (select producer_id from catalog.wines where id = v_keep) <> (select producer_id from catalog.wines where id = v_drop) then
      raise exception 'catalog: due vini di produttori diversi non si fondono (si fondono prima i produttori)' using errcode = '55000';
    end if;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- D-1: regole di promozione legate alla logica eseguibile
-- ---------------------------------------------------------------------------------------------

alter table catalog.promotion_rules add column approved_fingerprint text;
alter table catalog.promotion_rules add column approved_view_digest text;

-- Impronta (md5) del testo eseguibile che realizza la regola: le funzioni di promozione e le loro guardie. Cambiare una riga di
-- una di esse cambia l'impronta; una regola approvata con un'impronta diversa non abilita nulla.
create or replace function catalog.promotion_logic_fingerprint(p_version text)
returns text language sql stable set search_path = '' as $$
  with sigs(s) as (
    select unnest(array[
      'catalog.promote_wine_candidates(text,text,integer,boolean,text)',
      'catalog.promotion_candidates(uuid)',
      'catalog.promotion_batch(uuid,integer)',
      'catalog.promotion_blocked(uuid,integer)',
      'catalog.producer_final(uuid)',
      'catalog.canonical_insert_guard()',
      'catalog.detect_duplicate_candidates(integer)',
      'catalog.fold_text(text)',
      'catalog.promotion_authorized()',
      'catalog.promotion_logic_fingerprint(text)',
      'catalog.promotion_view_digest()',
      'catalog.require_actor(text)',
      'catalog.record_canonical_event(text,text,text,text,jsonb)'])),
  f as (select s, to_regprocedure(s) as fn from sigs)
  select case when p_version = 'lwin-conservative-v1' and (select count(*) = count(fn) from f) then
    md5((select string_agg(f.s || chr(29) || p.prosecdef::text || chr(29) || coalesce(p.proconfig::text, '') || chr(29) || p.prosrc,
                           chr(30) order by f.s)
           from f join pg_catalog.pg_proc p on p.oid = f.fn)) end;
$$;

-- Impronta della vista di candidati su cui la logica si appoggia (costosa: la verifica la fa la promozione una volta per chiamata).
create or replace function catalog.promotion_view_digest()
returns text language sql stable set search_path = '' as $$
  select md5(pg_catalog.pg_get_viewdef('catalog.wine_candidate_report'::regclass, true));
$$;

create or replace function catalog.promotion_rules_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'draft' or new.approved_by is not null or new.approved_at is not null
       or new.approved_fingerprint is not null or new.approved_view_digest is not null then
      raise exception 'catalog: una regola nasce in bozza (l''approvazione è un UPDATE che registra l''impronta della logica)' using errcode = '55000';
    end if;
    return new;
  end if;
  if tg_op = 'DELETE' then
    raise exception 'catalog: le regole di promozione non si cancellano (si ritirano)' using errcode = '55000';
  end if;
  if new.id <> old.id or new.version <> old.version or new.created_at <> old.created_at then
    raise exception 'catalog: identità di una regola non modificabile' using errcode = '55000';
  end if;
  if old.status = 'retired' then
    raise exception 'catalog: una regola ritirata è definitiva' using errcode = '55000';
  end if;
  if old.status = 'approved' then
    if new.status not in ('approved', 'retired') or new.description <> old.description
       or new.approved_by is distinct from old.approved_by or new.approved_at is distinct from old.approved_at
       or new.approved_fingerprint is distinct from old.approved_fingerprint
       or new.approved_view_digest is distinct from old.approved_view_digest then
      raise exception 'catalog: una regola approvata è immutabile (si può solo ritirare)' using errcode = '55000';
    end if;
    return new;
  end if;
  -- bozza
  if new.status = 'approved' then
    new.approved_fingerprint := catalog.promotion_logic_fingerprint(new.version);
    new.approved_view_digest := catalog.promotion_view_digest();
    if new.approved_fingerprint is null then
      raise exception 'catalog: nessuna logica eseguibile corrisponde alla versione % (impossibile approvare)', new.version using errcode = '55000';
    end if;
  elsif new.approved_by is distinct from old.approved_by or new.approved_at is distinct from old.approved_at
        or new.approved_fingerprint is distinct from old.approved_fingerprint or new.approved_view_digest is distinct from old.approved_view_digest then
    raise exception 'catalog: i dati di approvazione si scrivono solo approvando la regola' using errcode = '55000';
  end if;
  return new;
end;
$$;
create trigger promotion_rules_guard before insert or update or delete on catalog.promotion_rules
  for each row execute function catalog.promotion_rules_guard();
alter table catalog.promotion_rules add constraint promotion_rules_fingerprint check (
  status <> 'approved' or (approved_fingerprint is not null and approved_view_digest is not null));

create or replace function catalog.promotion_authorized()
returns boolean language sql stable set search_path = '' as $$
  select coalesce((select enabled from catalog.promotion_settings), false)
     and exists (select 1 from catalog.promotion_rules r
                  where r.version = 'lwin-conservative-v1' and r.status = 'approved' and r.approved_fingerprint is not null
                    and r.approved_fingerprint = catalog.promotion_logic_fingerprint(r.version));
$$;

-- Le righe `promotion` nascono solo con interruttore acceso e regola approvata PER QUESTA logica, e solo da un record di fonte
-- coerente (stessa fonte autorizzata, Live, in ambito vino, non rimosso, identificativo = LWIN-7 del vino).
create or replace function catalog.canonical_insert_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status <> 'active' or new.merged_into is not null or new.merge_id is not null then
    raise exception 'catalog: una riga canonica nasce attiva (la fusione passa da merge_canonical_entity)' using errcode = '55000';
  end if;
  if new.origin = 'promotion' then
    if not catalog.promotion_authorized() then
      raise exception 'catalog: promozione non consentita (interruttore spento o regola non approvata per questa logica)' using errcode = '42501';
    end if;
    if not exists (select 1 from catalog.source_records sr join catalog.sources s on s.id = sr.source_id
                    where sr.id = new.source_record_id and sr.source_id = new.source_id and s.authorization_status = 'authorized'
                      and sr.status = 'Live' and sr.scope = 'wine' and sr.removed_from_source_at is null) then
      raise exception 'catalog: la promozione richiede un record di fonte Live, in ambito vino, di una fonte autorizzata' using errcode = '42501';
    end if;
    -- annidati: plpgsql pianifica ogni espressione solo quando la raggiunge (la riga `producers` non ha `lwin7`, e viceversa)
    if tg_table_name = 'wines' then
      if not exists (select 1 from catalog.source_records sr where sr.id = new.source_record_id and sr.external_id = new.lwin7) then
        raise exception 'catalog: LWIN-7 del vino promosso diverso dall''identificativo del record di fonte' using errcode = '23514';
      end if;
      if (select p.status from catalog.producers p where p.id = new.producer_id) is distinct from 'active' then
        raise exception 'catalog: un vino promosso richiede un produttore attivo' using errcode = '23514';
      end if;
    else
      if left(new.natural_key, length(new.name_key) + 1) is distinct from new.name_key || chr(31) then
        raise exception 'catalog: chiave naturale del produttore incoerente con il nome' using errcode = '23514';
      end if;
    end if;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- D-5: LWIN-16 e LWIN-18 secondo la specifica Liv-ex
-- ---------------------------------------------------------------------------------------------

create or replace function catalog.format_guard()
returns trigger language plpgsql set search_path = '' as $$
declare v_lwin11 text;
begin
  if tg_op = 'UPDATE' then
    raise exception 'catalog: un formato documentato non è modificabile (si registra una nuova riga)' using errcode = '55000';
  end if;
  if new.source_record_id is not null and not exists (
       select 1 from catalog.source_records r where r.id = new.source_record_id and r.source_id = new.source_id) then
    raise exception 'catalog: il record di fonte non appartiene alla fonte indicata' using errcode = '23514';
  end if;
  if new.lwin16 is null and new.lwin18 is null then
    return new;
  end if;
  if new.volume_ml > 99999 then
    raise exception 'catalog: il volume non è esprimibile in 5 cifre (LWIN-16/18)' using errcode = '23514';
  end if;
  select lwin11 into v_lwin11 from catalog.wine_vintages where id = new.vintage_id;
  if v_lwin11 is null then
    raise exception 'catalog: LWIN-16/18 richiedono un''annata con LWIN-11' using errcode = '23514';
  end if;
  -- LWIN-16 = LWIN-11 + volume (5 cifre, ml). Descrive la bottiglia singola.
  if new.lwin16 is not null then
    if left(new.lwin16, 11) <> v_lwin11 then
      raise exception 'catalog: LWIN-16 non coerente con LWIN-11 dell''annata' using errcode = '23514';
    end if;
    if substr(new.lwin16, 12, 5) <> lpad(new.volume_ml::text, 5, '0') then
      raise exception 'catalog: LWIN-16 non coerente con volume_ml' using errcode = '23514';
    end if;
    if new.units_per_pack <> 1 then
      raise exception 'catalog: LWIN-16 non descrive una confezione (units_per_pack deve essere 1; la confezione è LWIN-18)' using errcode = '23514';
    end if;
  end if;
  -- LWIN-18 = LWIN-11 + confezione (2 cifre) + volume (5 cifre, ml). NON ha LWIN-16 come prefisso.
  if new.lwin18 is not null then
    if left(new.lwin18, 11) <> v_lwin11 then
      raise exception 'catalog: LWIN-18 non coerente con LWIN-11 dell''annata' using errcode = '23514';
    end if;
    if new.units_per_pack > 99 or substr(new.lwin18, 12, 2) <> lpad(new.units_per_pack::text, 2, '0') then
      raise exception 'catalog: LWIN-18 non coerente con units_per_pack' using errcode = '23514';
    end if;
    if substr(new.lwin18, 14, 5) <> lpad(new.volume_ml::text, 5, '0') then
      raise exception 'catalog: LWIN-18 non coerente con volume_ml' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- D-4: eccezioni di promozione (record non processabili) senza starvation del lotto
-- ---------------------------------------------------------------------------------------------

create table catalog.promotion_exceptions (
  id bigint generated always as identity primary key,
  source_id uuid not null references catalog.sources(id),
  source_record_id bigint not null references catalog.source_records(id),
  lwin text not null,
  reason text not null check (reason in ('producer_retired')),
  producer_id uuid references catalog.producers(id),
  rule_version text not null,
  detected_at timestamptz not null default now(),
  unique (source_record_id, reason)
);
create index promotion_exceptions_source_idx on catalog.promotion_exceptions (source_id);
create index promotion_exceptions_producer_idx on catalog.promotion_exceptions (producer_id) where producer_id is not null;
create trigger promotion_exceptions_append_only before update or delete on catalog.promotion_exceptions
  for each row execute function catalog.append_only_guard();

-- Produttore effettivo (segue la catena delle fusioni; massimo 20 salti, poi si ferma).
create or replace function catalog.producer_final(p_id uuid)
returns uuid language sql stable set search_path = '' as $$
  with recursive r(id, depth) as (
    select p_id, 0
    union all
    select p.merged_into, r.depth + 1 from r join catalog.producers p on p.id = r.id
     where p.merged_into is not null and r.depth < 20)
  select id from r order by depth desc limit 1;
$$;

-- Candidati alla promozione (stessi requisiti di prima) con, se il produttore esiste già ma NON è attivo (ritirato, anche tramite
-- fusione), l'identificativo del produttore che li blocca. Il lotto salta i bloccati; le eccezioni li tracciano.
create or replace function catalog.promotion_candidates(p_source_id uuid)
returns table (source_record_id bigint, lwin text, producer_name text, wine text, colour text, wine_type text, sub_type text,
               designation text, classification text, territory_id bigint, country text, producer_key text, blocked_producer_id uuid)
language sql stable set search_path = '' as $$
  select sr.id, c.lwin, c.producer_name, c.wine, c.colour, c.wine_type, c.sub_type, c.designation, c.classification,
         c.territory_id, c.country, k.producer_key,
         (select p.id from catalog.producers p
           where p.natural_key = k.producer_key
             and (select f.status from catalog.producers f where f.id = catalog.producer_final(p.id)) is distinct from 'active')
    from catalog.wine_candidate_report c
    join catalog.source_records sr on sr.source_id = c.source_id and sr.external_id = c.lwin
    cross join lateral (select catalog.fold_text(c.producer_name) || chr(31) || coalesce(catalog.fold_text(c.country), '') as producer_key) k
   where c.source_id = p_source_id and c.readiness = 'fields_complete' and c.lwin ~ '^[0-9]{7}$'
     and catalog.fold_text(c.producer_name) is not null and catalog.fold_text(c.wine) is not null
     and not exists (select 1 from catalog.wines w where w.lwin7 = c.lwin);
$$;

create or replace function catalog.promotion_batch(p_source_id uuid, p_limit integer)
returns table (source_record_id bigint, lwin text, producer_name text, wine text, colour text, wine_type text, sub_type text,
               designation text, classification text, territory_id bigint, country text, producer_key text)
language sql stable set search_path = '' as $$
  select b.source_record_id, b.lwin, b.producer_name, b.wine, b.colour, b.wine_type, b.sub_type, b.designation, b.classification,
         b.territory_id, b.country, b.producer_key
    from catalog.promotion_candidates(p_source_id) b
   where b.blocked_producer_id is null
   order by b.lwin
   limit least(greatest(coalesce(p_limit, 1), 1), 10000);
$$;

-- Record bloccati non ancora tracciati (quelli già in `promotion_exceptions` non si riesaminano).
create or replace function catalog.promotion_blocked(p_source_id uuid, p_limit integer)
returns table (source_record_id bigint, lwin text, blocked_producer_id uuid)
language sql stable set search_path = '' as $$
  select b.source_record_id, b.lwin, b.blocked_producer_id
    from catalog.promotion_candidates(p_source_id) b
   where b.blocked_producer_id is not null
     and not exists (select 1 from catalog.promotion_exceptions e where e.source_record_id = b.source_record_id and e.reason = 'producer_retired')
   order by b.lwin
   limit least(greatest(coalesce(p_limit, 1), 1), 10000);
$$;

-- Anteprima: come prima, più i record bloccati da un produttore ritirato (e «eligible» li esclude).
create or replace function catalog.promotion_preview(p_source_code text default 'LIVEX-LWIN7', p_rule_version text default 'lwin-conservative-v1')
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  v_source uuid;
  v_rule_status text;
  v_enabled boolean;
  v_counts jsonb;
  v_producers bigint;
  v_blocked bigint;
begin
  select id into v_source from catalog.sources where code = p_source_code;
  if v_source is null then
    raise exception 'catalog: fonte sconosciuta' using errcode = 'P0002';
  end if;
  select status into v_rule_status from catalog.promotion_rules where version = p_rule_version;
  select enabled into v_enabled from catalog.promotion_settings;

  with b as (
    select r.*, (r.lwin ~ '^[0-9]{7}$') as lwin_ok,
           exists (select 1 from catalog.wines w where w.lwin7 = r.lwin) as promoted
      from catalog.wine_candidate_report r where r.source_id = v_source)
  select jsonb_build_object(
           'live_wine_records', count(*),
           'eligible', count(*) filter (where readiness = 'fields_complete' and lwin_ok and not promoted),
           'already_promoted', count(*) filter (where promoted),
           'blocked_missing_producer', count(*) filter (where 'missing_producer' = any (review_reasons)),
           'blocked_missing_wine_name', count(*) filter (where 'missing_wine_name' = any (review_reasons)),
           'blocked_missing_country', count(*) filter (where 'missing_country' = any (review_reasons)),
           'blocked_possible_duplicate', count(*) filter (where 'possible_duplicate' = any (review_reasons)),
           'blocked_invalid_lwin7', count(*) filter (where not lwin_ok))
    into v_counts from b;

  select count(*) into v_blocked from catalog.promotion_candidates(v_source) where blocked_producer_id is not null;
  v_counts := jsonb_set(v_counts, '{eligible}', to_jsonb((v_counts ->> 'eligible')::bigint - v_blocked));

  select count(distinct catalog.fold_text(r.producer_name) || chr(31) || coalesce(catalog.fold_text(r.country), ''))
    into v_producers
    from catalog.wine_candidate_report r
   where r.source_id = v_source and r.readiness = 'fields_complete' and r.lwin ~ '^[0-9]{7}$'
     and not exists (select 1 from catalog.wines w where w.lwin7 = r.lwin)
     and not exists (select 1 from catalog.producers p
                      where p.natural_key = catalog.fold_text(r.producer_name) || chr(31) || coalesce(catalog.fold_text(r.country), ''));

  return v_counts || jsonb_build_object(
    'blocked_producer_retired', v_blocked,
    'producers_to_create_upper_bound', v_producers,
    'rule_version', p_rule_version, 'rule_status', coalesce(v_rule_status, 'unknown'),
    'promotion_enabled', coalesce(v_enabled, false), 'database_writes', 0);
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- D-6: porte di scrittura SECURITY DEFINER (search_path vuoto). Il curatore non ha più INSERT/UPDATE diretti.
-- ---------------------------------------------------------------------------------------------

create or replace function catalog.detect_duplicate_candidates(p_limit integer default 500)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_p integer;
  v_w integer;
  v_lim integer := least(greatest(coalesce(p_limit, 500), 1), 10000);
begin
  with pairs as (
    select a.id as x, b.id as y from catalog.producers a
      join catalog.producers b on b.name_key = a.name_key and a.id < b.id
     where a.status = 'active' and b.status = 'active'
       and not exists (select 1 from catalog.duplicate_candidates d where d.producer_a = a.id and d.producer_b = b.id)
     order by a.id, b.id limit v_lim),
  ins as (
    insert into catalog.duplicate_candidates (producer_a, producer_b, reason)
    select x, y, 'same_name_key' from pairs
    on conflict do nothing returning 1)
  select count(*) into v_p from ins;
  with pairs as (
    select a.id as x, b.id as y from catalog.wines a
      join catalog.wines b on b.producer_id = a.producer_id and b.name_key = a.name_key and a.id < b.id
     where a.status = 'active' and b.status = 'active'
       and not exists (select 1 from catalog.duplicate_candidates d where d.wine_a = a.id and d.wine_b = b.id)
     order by a.id, b.id limit v_lim),
  ins as (
    insert into catalog.duplicate_candidates (wine_a, wine_b, reason)
    select x, y, 'same_name_key' from pairs
    on conflict do nothing returning 1)
  select count(*) into v_w from ins;
  return jsonb_build_object('producer_pairs_opened', v_p, 'wine_pairs_opened', v_w);
end;
$$;

create or replace function catalog.promote_wine_candidates(
  p_source_code text default 'LIVEX-LWIN7',
  p_rule_version text default 'lwin-conservative-v1',
  p_limit integer default 500,
  p_dry_run boolean default true,
  p_actor text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  c_logic constant text := 'lwin-conservative-v1';
  v_source uuid;
  v_auth text;
  v_actor text;
  v_rule_status text;
  v_rule_fp text;
  v_rule_view text;
  v_enabled boolean;
  v_max integer;
  v_complete uuid;
  v_busy boolean;
  v_producers integer := 0;
  v_wines integer := 0;
  v_aliases integer := 0;
  v_exceptions integer := 0;
  v_dups jsonb;
begin
  select id, authorization_status into v_source, v_auth from catalog.sources where code = p_source_code;
  if v_source is null then
    raise exception 'catalog: fonte sconosciuta' using errcode = 'P0002';
  end if;
  if p_dry_run is not false then
    return catalog.promotion_preview(p_source_code, p_rule_version) || jsonb_build_object('dry_run', true);
  end if;

  perform pg_advisory_xact_lock(hashtext('catalog.promote:' || v_source::text));
  perform pg_advisory_xact_lock(hashtext('catalog.import:' || v_source::text));  -- stesso lock di begin_import_run
  perform pg_advisory_xact_lock(hashtext('catalog.merge:producer'));  -- serializza con fusioni e ritiri di produttori (nessun vino su un produttore appena ritirato)
  v_actor := catalog.require_actor(p_actor);
  -- D-1: la versione richiesta DEVE essere quella che questa logica realizza; la regola deve essere approvata con l'impronta
  -- (funzioni e vista) della logica attuale. Un'altra regola, anche approvata, non abilita il comportamento v1.
  if p_rule_version is distinct from c_logic then
    raise exception 'catalog: la regola % non corrisponde alla logica implementata (%)', p_rule_version, c_logic using errcode = '42501';
  end if;
  select status, approved_fingerprint, approved_view_digest into v_rule_status, v_rule_fp, v_rule_view
    from catalog.promotion_rules where version = c_logic;
  if v_rule_status is distinct from 'approved' then
    raise exception 'catalog: regola di promozione % non approvata (%)', c_logic, coalesce(v_rule_status, 'inesistente') using errcode = '42501';
  end if;
  if v_rule_fp is distinct from catalog.promotion_logic_fingerprint(c_logic) or v_rule_view is distinct from catalog.promotion_view_digest() then
    raise exception 'catalog: la logica eseguibile è cambiata dopo l''approvazione della regola %: serve una nuova approvazione', c_logic using errcode = '42501';
  end if;
  select enabled, max_batch into v_enabled, v_max from catalog.promotion_settings;
  if v_enabled is not true then
    raise exception 'catalog: promozione disattivata (promotion_settings.enabled = false)' using errcode = '42501';
  end if;
  if v_auth <> 'authorized' then
    raise exception 'catalog: fonte non autorizzata (%)', v_auth using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > v_max then
    raise exception 'catalog: limite del lotto fuori intervallo (1..%)', v_max using errcode = '22023';
  end if;
  select complete_run_id, attempt_in_progress into v_complete, v_busy from catalog.complete_versions where source_id = v_source;
  if v_complete is null then
    raise exception 'catalog: nessuna versione completa della fonte da cui promuovere' using errcode = '55000';
  end if;
  if v_busy then
    raise exception 'catalog: import in corso per la fonte: promozione rifiutata' using errcode = '55P03';
  end if;

  -- D-4: i record con produttore ritirato non entrano nel lotto (non lo occupano) e sono tracciati come eccezioni.
  insert into catalog.promotion_exceptions (source_id, source_record_id, lwin, reason, producer_id, rule_version)
  select v_source, x.source_record_id, x.lwin, 'producer_retired', x.blocked_producer_id, c_logic
    from catalog.promotion_blocked(v_source, 10000) x
  on conflict (source_record_id, reason) do nothing;
  get diagnostics v_exceptions = row_count;

  with batch as (select * from catalog.promotion_batch(v_source, p_limit)),
  ins as (
    insert into catalog.producers (name, name_key, country_territory_id, natural_key, origin, source_id, source_record_id)
    select distinct on (b.producer_key) b.producer_name, catalog.fold_text(b.producer_name), t.id, b.producer_key,
           'promotion', v_source, b.source_record_id
      from batch b
      left join catalog.territories t on t.source_id = v_source and t.natural_key = 'country' || chr(31) || b.country
     order by b.producer_key, b.lwin
    on conflict (natural_key) do nothing
    returning 1)
  select count(*) into v_producers from ins;

  with batch as (select * from catalog.promotion_batch(v_source, p_limit)),
  ins as (
    insert into catalog.wines (lwin7, producer_id, name, name_key, colour, wine_type, sub_type, designation, classification,
                               territory_id, origin, source_id, source_record_id)
    select b.lwin, catalog.producer_final(p.id), b.wine, catalog.fold_text(b.wine), b.colour, b.wine_type, b.sub_type,
           b.designation, b.classification, b.territory_id, 'promotion', v_source, b.source_record_id
      from batch b
      join catalog.producers p on p.natural_key = b.producer_key and p.status <> 'retired'
    on conflict (lwin7) do nothing
    returning 1)
  select count(*) into v_wines from ins;

  with ins as (
    insert into catalog.entity_aliases (wine_id, lang, alias, alias_key, kind, source_id, source_record_id)
    select w.id, null, l.from_external_id, l.from_external_id, 'combined_lwin', v_source, sr.id
      from catalog.record_links l
      join catalog.wines w on w.lwin7 = l.final_external_id and w.status = 'active'
      join catalog.source_records sr on sr.source_id = v_source and sr.external_id = l.from_external_id
     where l.source_id = v_source and l.link_state = 'active'
    on conflict do nothing
    returning 1)
  select count(*) into v_aliases from ins;

  v_dups := catalog.detect_duplicate_candidates(500);
  perform catalog.record_canonical_event('promote_wine_candidates', 'source', p_source_code, v_actor,
    jsonb_build_object('rule', c_logic, 'fingerprint', v_rule_fp, 'producers_created', v_producers, 'wines_created', v_wines,
                       'aliases_created', v_aliases, 'exceptions_recorded', v_exceptions, 'limit', p_limit, 'from_run', v_complete));
  return jsonb_build_object('dry_run', false, 'rule_version', c_logic, 'producers_created', v_producers,
                            'wines_created', v_wines, 'combined_aliases_created', v_aliases,
                            'exceptions_recorded', v_exceptions, 'duplicates', v_dups, 'from_run', v_complete);
end;
$$;

create or replace function catalog.review_duplicate_candidate(p_candidate_id bigint, p_decision text, p_reviewer text, p_note text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_actor text := catalog.require_actor(p_reviewer);
begin
  if p_decision is null or p_decision not in ('distinct', 'same', 'dismissed') then
    raise exception 'catalog: decisione non valida (distinct, same, dismissed)' using errcode = '22023';
  end if;
  update catalog.duplicate_candidates
     set review_status = p_decision, reviewed_by = v_actor, reviewed_at = now(), review_note = p_note
   where id = p_candidate_id and review_status = 'open';
  if not found then
    raise exception 'catalog: candidato inesistente o già rivisto' using errcode = 'P0002';
  end if;
  perform catalog.record_canonical_event('review_duplicate_candidate', 'duplicate_candidate', p_candidate_id::text, v_actor,
                                         jsonb_build_object('decision', p_decision));
end;
$$;

-- Candidato aperto a mano (stesso tipo, entrambe attive, coppia ordinata). Nulla si fonde: la revisione decide.
create or replace function catalog.open_duplicate_candidate(p_kind text, p_a uuid, p_b uuid, p_note text, p_actor text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := catalog.require_actor(p_actor);
  v_id bigint;
  v_lo uuid;
  v_hi uuid;
begin
  if p_kind not in ('producer', 'wine') or p_a is null or p_b is null or p_a = p_b then
    raise exception 'catalog: coppia non valida (tipo producer|wine, due entità distinte)' using errcode = '22023';
  end if;
  if p_note is null or length(btrim(p_note)) = 0 then
    raise exception 'catalog: serve una nota che motivi il candidato' using errcode = '22023';
  end if;
  v_lo := least(p_a, p_b);
  v_hi := greatest(p_a, p_b);
  if p_kind = 'producer' then
    if (select count(*) from catalog.producers where id in (v_lo, v_hi) and status = 'active') <> 2 then
      raise exception 'catalog: entrambe le entità devono esistere ed essere attive' using errcode = 'P0002';
    end if;
    insert into catalog.duplicate_candidates (producer_a, producer_b, reason, detail, detected_by)
    values (v_lo, v_hi, 'manual', jsonb_build_object('note', btrim(p_note)), v_actor) returning id into v_id;
  else
    if (select count(*) from catalog.wines where id in (v_lo, v_hi) and status = 'active') <> 2 then
      raise exception 'catalog: entrambe le entità devono esistere ed essere attive' using errcode = 'P0002';
    end if;
    insert into catalog.duplicate_candidates (wine_a, wine_b, reason, detail, detected_by)
    values (v_lo, v_hi, 'manual', jsonb_build_object('note', btrim(p_note)), v_actor) returning id into v_id;
  end if;
  perform catalog.record_canonical_event('open_duplicate_candidate', 'duplicate_candidate', v_id::text, v_actor, jsonb_build_object('kind', p_kind));
  return v_id;
end;
$$;

create or replace function catalog.merge_canonical_entity(p_candidate_id bigint, p_kept_side text, p_reviewer text, p_reason text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  c catalog.duplicate_candidates%rowtype;
  v_actor text := catalog.require_actor(p_reviewer);
  v_kind text;
  v_from uuid;
  v_into uuid;
  v_merge bigint;
  v_n integer;
begin
  if p_reason is null or length(btrim(p_reason)) = 0 then
    raise exception 'catalog: la fusione richiede un motivo' using errcode = '22023';
  end if;
  if p_kept_side is null or p_kept_side not in ('a', 'b') then
    raise exception 'catalog: il lato conservato è a o b' using errcode = '22023';
  end if;
  select * into c from catalog.duplicate_candidates where id = p_candidate_id;
  if not found then
    raise exception 'catalog: candidato inesistente' using errcode = 'P0002';
  end if;
  v_kind := case when c.producer_a is not null then 'producer' else 'wine' end;
  perform pg_advisory_xact_lock(hashtext('catalog.merge:' || v_kind));
  select * into c from catalog.duplicate_candidates where id = p_candidate_id for update;
  if c.review_status <> 'same' then
    raise exception 'catalog: la fusione richiede una revisione "same" registrata (stato: %)', c.review_status using errcode = '55000';
  end if;
  if exists (select 1 from catalog.entity_merges where candidate_id = p_candidate_id and reverted_at is null) then
    raise exception 'catalog: candidato già fuso' using errcode = '55000';
  end if;
  if v_kind = 'producer' then
    v_into := case p_kept_side when 'a' then c.producer_a else c.producer_b end;
    v_from := case p_kept_side when 'a' then c.producer_b else c.producer_a end;
  else
    v_into := case p_kept_side when 'a' then c.wine_a else c.wine_b end;
    v_from := case p_kept_side when 'a' then c.wine_b else c.wine_a end;
  end if;
  insert into catalog.entity_merges (candidate_id, kept_side, decided_by, reason)
  values (p_candidate_id, p_kept_side, v_actor, btrim(p_reason)) returning id into v_merge;
  if v_kind = 'producer' then
    update catalog.producers set status = 'merged', merged_into = v_into, merge_id = v_merge, updated_at = now()
     where id = v_from and status = 'active';
  else
    update catalog.wines set status = 'merged', merged_into = v_into, merge_id = v_merge, updated_at = now()
     where id = v_from and status = 'active';
  end if;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'catalog: entrambe le entità devono essere attive per la fusione' using errcode = '55000';
  end if;
  perform catalog.record_canonical_event('merge_canonical_entity', 'entity_merge', v_merge::text, v_actor,
                                         jsonb_build_object('candidate', p_candidate_id, 'kind', v_kind, 'from', v_from, 'into', v_into, 'kept_side', p_kept_side));
  return v_merge;
end;
$$;

create or replace function catalog.revert_canonical_merge(p_merge_id bigint, p_reviewer text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  m catalog.entity_merges%rowtype;
  c catalog.duplicate_candidates%rowtype;
  v_actor text := catalog.require_actor(p_reviewer);
  v_kind text;
  v_from uuid;
  v_n integer;
begin
  select * into m from catalog.entity_merges where id = p_merge_id;
  if not found or m.reverted_at is not null then
    raise exception 'catalog: fusione inesistente o già annullata' using errcode = 'P0002';
  end if;
  select * into c from catalog.duplicate_candidates where id = m.candidate_id;
  v_kind := case when c.producer_a is not null then 'producer' else 'wine' end;
  perform pg_advisory_xact_lock(hashtext('catalog.merge:' || v_kind));
  select * into m from catalog.entity_merges where id = p_merge_id and reverted_at is null for update;
  if not found then
    raise exception 'catalog: fusione inesistente o già annullata' using errcode = 'P0002';
  end if;
  if v_kind = 'producer' then
    v_from := case m.kept_side when 'a' then c.producer_b else c.producer_a end;
  else
    v_from := case m.kept_side when 'a' then c.wine_b else c.wine_a end;
  end if;
  update catalog.entity_merges set reverted_at = now(), reverted_by = v_actor where id = p_merge_id;
  if v_kind = 'producer' then
    update catalog.producers set status = 'active', merged_into = null, merge_id = null, updated_at = now()
     where id = v_from and status = 'merged' and merge_id = p_merge_id;
  else
    update catalog.wines set status = 'active', merged_into = null, merge_id = null, updated_at = now()
     where id = v_from and status = 'merged' and merge_id = p_merge_id;
  end if;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'catalog: l''entità non risulta più fusa da questa fusione' using errcode = '55000';
  end if;
  perform catalog.record_canonical_event('revert_canonical_merge', 'entity_merge', p_merge_id::text, v_actor,
                                         jsonb_build_object('kind', v_kind, 'entity', v_from));
end;
$$;

create or replace function catalog.retire_canonical_entity(p_kind text, p_id uuid, p_reason text, p_actor text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := catalog.require_actor(p_actor);
  v_n integer;
begin
  if p_reason is null or length(btrim(p_reason)) = 0 then
    raise exception 'catalog: il ritiro richiede un motivo' using errcode = '22023';
  end if;
  if p_kind = 'producer' then
    update catalog.producers set status = 'retired', updated_at = now() where id = p_id and status = 'active';
  elsif p_kind = 'wine' then
    update catalog.wines set status = 'retired', updated_at = now() where id = p_id and status = 'active';
  else
    raise exception 'catalog: tipo di entità non valido (producer, wine)' using errcode = '22023';
  end if;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'catalog: entità inesistente o non attiva' using errcode = 'P0002';
  end if;
  perform catalog.record_canonical_event('retire_canonical_entity', p_kind, p_id::text, v_actor, jsonb_build_object('reason', btrim(p_reason)));
end;
$$;

-- Inserimento MANUALE (D-2): senza LWIN, senza record di fonte, con nota di provenienza obbligatoria.
create or replace function catalog.add_manual_producer(p_name text, p_country_territory_id bigint, p_note text, p_actor text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := catalog.require_actor(p_actor);
  v_key text := catalog.fold_text(p_name);
  v_id uuid;
begin
  if v_key is null then
    raise exception 'catalog: nome del produttore vuoto' using errcode = '22023';
  end if;
  insert into catalog.producers (name, name_key, country_territory_id, origin, provenance_note)
  values (btrim(p_name), v_key, p_country_territory_id, 'manual', p_note) returning id into v_id;
  perform catalog.record_canonical_event('add_manual_producer', 'producer', v_id::text, v_actor, '{}'::jsonb);
  return v_id;
end;
$$;

create or replace function catalog.add_manual_wine(p_producer_id uuid, p_name text, p_colour text, p_wine_type text, p_sub_type text,
  p_designation text, p_classification text, p_territory_id bigint, p_note text, p_actor text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := catalog.require_actor(p_actor);
  v_key text := catalog.fold_text(p_name);
  v_id uuid;
begin
  if v_key is null then
    raise exception 'catalog: nome del vino vuoto' using errcode = '22023';
  end if;
  if (select status from catalog.producers where id = p_producer_id) is distinct from 'active' then
    raise exception 'catalog: il produttore deve esistere ed essere attivo' using errcode = 'P0002';
  end if;
  insert into catalog.wines (producer_id, name, name_key, colour, wine_type, sub_type, designation, classification, territory_id, origin, provenance_note)
  values (p_producer_id, btrim(p_name), v_key, p_colour, p_wine_type, p_sub_type, p_designation, p_classification, p_territory_id, 'manual', p_note)
  returning id into v_id;
  perform catalog.record_canonical_event('add_manual_wine', 'wine', v_id::text, v_actor, '{}'::jsonb);
  return v_id;
end;
$$;

-- Le vecchie firme (senza esecutore, invoker) lasciano il posto a quelle con esecutore e porta definer.
drop function catalog.add_entity_alias(text, uuid, text, text, text, uuid, bigint, text);
drop function catalog.add_wine_vintage(uuid, integer, boolean, text, uuid, bigint, text);
drop function catalog.add_wine_format(uuid, integer, integer, text, text, uuid, bigint, text);
drop function catalog.propose_attribute_claim(text, text, uuid, jsonb, uuid, bigint, text);

create or replace function catalog.add_entity_alias(
  p_entity_type text, p_entity_id uuid, p_lang text, p_alias text, p_kind text default 'variant',
  p_source_id uuid default null, p_source_record_id bigint default null, p_note text default null, p_actor text default null)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := catalog.require_actor(p_actor);
  v_key text := catalog.fold_text(p_alias);
  v_id bigint;
  v_orig text;
begin
  if v_key is null then
    raise exception 'catalog: alias vuoto' using errcode = '22023';
  end if;
  if p_entity_type = 'producer' then
    select name_key into v_orig from catalog.producers where id = p_entity_id;
  elsif p_entity_type = 'wine' then
    select name_key into v_orig from catalog.wines where id = p_entity_id;
  else
    raise exception 'catalog: tipo di entità non valido (producer, wine)' using errcode = '22023';
  end if;
  if v_orig is null then
    raise exception 'catalog: entità inesistente' using errcode = 'P0002';
  end if;
  if (case when p_entity_type = 'producer' then (select status from catalog.producers where id = p_entity_id)
           else (select status from catalog.wines where id = p_entity_id) end) <> 'active' then
    raise exception 'catalog: un alias si aggiunge solo a un''entità attiva' using errcode = '55000';
  end if;
  if v_orig = v_key then
    raise exception 'catalog: l''alias coincide con il nome originale' using errcode = '23514';
  end if;
  insert into catalog.entity_aliases (producer_id, wine_id, lang, alias, alias_key, kind, source_id, source_record_id, provenance_note)
  values (case when p_entity_type = 'producer' then p_entity_id end, case when p_entity_type = 'wine' then p_entity_id end,
          p_lang, btrim(p_alias), v_key, p_kind, p_source_id, p_source_record_id, p_note)
  returning id into v_id;
  perform catalog.record_canonical_event('add_entity_alias', 'entity_alias', v_id::text, v_actor, jsonb_build_object('entity', p_entity_type));
  return v_id;
end;
$$;

create or replace function catalog.add_wine_vintage(p_wine_id uuid, p_vintage_year integer, p_non_vintage boolean default false,
  p_lwin11 text default null, p_source_id uuid default null, p_source_record_id bigint default null, p_note text default null,
  p_actor text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := catalog.require_actor(p_actor);
  v_id uuid;
begin
  insert into catalog.wine_vintages (wine_id, vintage_year, is_non_vintage, lwin11, source_id, source_record_id, provenance_note)
  values (p_wine_id, p_vintage_year, coalesce(p_non_vintage, false), p_lwin11, p_source_id, p_source_record_id, p_note)
  returning id into v_id;
  perform catalog.record_canonical_event('add_wine_vintage', 'wine_vintage', v_id::text, v_actor, '{}'::jsonb);
  return v_id;
end;
$$;

create or replace function catalog.add_wine_format(p_vintage_id uuid, p_volume_ml integer, p_units_per_pack integer default 1,
  p_lwin16 text default null, p_lwin18 text default null, p_source_id uuid default null, p_source_record_id bigint default null,
  p_note text default null, p_actor text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := catalog.require_actor(p_actor);
  v_id uuid;
begin
  insert into catalog.wine_formats (vintage_id, volume_ml, units_per_pack, lwin16, lwin18, source_id, source_record_id, provenance_note)
  values (p_vintage_id, p_volume_ml, coalesce(p_units_per_pack, 1), p_lwin16, p_lwin18, p_source_id, p_source_record_id, p_note)
  returning id into v_id;
  perform catalog.record_canonical_event('add_wine_format', 'wine_format', v_id::text, v_actor, '{}'::jsonb);
  return v_id;
end;
$$;

create or replace function catalog.propose_attribute_claim(p_attribute_key text, p_subject_type text, p_subject_id uuid, p_value jsonb,
  p_source_id uuid, p_source_record_id bigint default null, p_evidence_note text default null, p_actor text default null)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := catalog.require_actor(p_actor);
  v_id bigint;
begin
  if p_subject_type not in ('producer', 'wine', 'vintage', 'format') then
    raise exception 'catalog: tipo di soggetto non valido' using errcode = '22023';
  end if;
  insert into catalog.attribute_claims (attribute_key, producer_id, wine_id, vintage_id, format_id, value, source_id, source_record_id, evidence_note)
  values (p_attribute_key,
          case when p_subject_type = 'producer' then p_subject_id end, case when p_subject_type = 'wine' then p_subject_id end,
          case when p_subject_type = 'vintage' then p_subject_id end, case when p_subject_type = 'format' then p_subject_id end,
          p_value, p_source_id, p_source_record_id, p_evidence_note)
  returning id into v_id;
  perform catalog.record_canonical_event('propose_attribute_claim', 'attribute_claim', v_id::text, v_actor, jsonb_build_object('attribute', p_attribute_key));
  return v_id;
end;
$$;

create or replace function catalog.review_attribute_claim(p_claim_id bigint, p_decision text, p_reviewer text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := catalog.require_actor(p_reviewer);
  v_old bigint;
begin
  if p_decision is null or p_decision not in ('accepted', 'rejected') then
    raise exception 'catalog: decisione non valida (accepted, rejected)' using errcode = '22023';
  end if;
  if p_decision = 'accepted' then
    select o.id into v_old from catalog.attribute_claims o, catalog.attribute_claims n
     where n.id = p_claim_id and o.status = 'accepted' and o.attribute_key = n.attribute_key and o.id <> n.id
       and coalesce(o.producer_id, o.wine_id, o.vintage_id, o.format_id) = coalesce(n.producer_id, n.wine_id, n.vintage_id, n.format_id);
    if v_old is not null then
      update catalog.attribute_claims set status = 'superseded' where id = v_old;
    end if;
  end if;
  update catalog.attribute_claims set status = p_decision, reviewed_by = v_actor, reviewed_at = now()
   where id = p_claim_id and status = 'proposed';
  if not found then
    raise exception 'catalog: rivendicazione inesistente o già revisionata' using errcode = 'P0002';
  end if;
  perform catalog.record_canonical_event('review_attribute_claim', 'attribute_claim', p_claim_id::text, v_actor,
                                         jsonb_build_object('decision', p_decision, 'superseded', v_old));
end;
$$;

create or replace function catalog.propose_wine_link(p_public_wine_id uuid, p_public_wine_slug text, p_vintage_id uuid,
  p_method text, p_proposed_by text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := catalog.require_actor(p_proposed_by);
  v_id bigint;
begin
  if p_method = 'exact_id' then
    raise exception 'catalog: exact_id non disponibile (public.wines non ha un identificativo condiviso)' using errcode = '0A000';
  end if;
  insert into catalog.wine_links (public_wine_id, public_wine_slug, vintage_id, method, proposed_by)
  values (p_public_wine_id, p_public_wine_slug, p_vintage_id, p_method, v_actor)
  returning id into v_id;
  perform catalog.record_canonical_event('propose_wine_link', 'wine_link', v_id::text, v_actor, jsonb_build_object('method', p_method));
  return v_id;
end;
$$;

create or replace function catalog.review_wine_link(p_link_id bigint, p_decision text, p_reviewer text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_actor text := catalog.require_actor(p_reviewer);
begin
  if p_decision = 'activate' then
    update catalog.wine_links set status = 'active', reviewed_by = v_actor, reviewed_at = now()
     where id = p_link_id and status = 'proposed';
  elsif p_decision = 'revoke' then
    update catalog.wine_links set status = 'revoked', revoked_by = v_actor, revoked_at = now()
     where id = p_link_id and status in ('proposed', 'active');
  else
    raise exception 'catalog: decisione non valida (activate, revoke)' using errcode = '22023';
  end if;
  if not found then
    raise exception 'catalog: collegamento inesistente o non nello stato richiesto' using errcode = 'P0002';
  end if;
  perform catalog.record_canonical_event('review_wine_link', 'wine_link', p_link_id::text, v_actor, jsonb_build_object('decision', p_decision));
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- Privilegi: il curatore legge e chiama le porte; non scrive. Funzioni interne non eseguibili dal curatore.
-- ---------------------------------------------------------------------------------------------

revoke all on all functions in schema catalog from public, anon, authenticated, service_role;
revoke all on all tables in schema catalog from anon, authenticated, service_role;

revoke insert, update, delete, truncate on catalog.producers, catalog.wines, catalog.wine_vintages, catalog.wine_formats,
  catalog.entity_aliases, catalog.attribute_claims, catalog.duplicate_candidates, catalog.entity_merges, catalog.wine_links,
  catalog.canonical_events from catalog_curator;
revoke update (status, merged_into, updated_at) on catalog.producers, catalog.wines from catalog_curator;
revoke update (status, reviewed_by, reviewed_at) on catalog.attribute_claims from catalog_curator;
revoke update (review_status, reviewed_by, reviewed_at, review_note) on catalog.duplicate_candidates from catalog_curator;
revoke update (reverted_at, reverted_by) on catalog.entity_merges from catalog_curator;
revoke update (status, reviewed_by, reviewed_at, revoked_by, revoked_at) on catalog.wine_links from catalog_curator;

-- RLS: il curatore può solo leggere (la scrittura passa dalle porte definer, che girano come proprietario)
drop policy curator_all on catalog.producers;
drop policy curator_all on catalog.wines;
drop policy curator_all on catalog.wine_vintages;
drop policy curator_all on catalog.wine_formats;
drop policy curator_all on catalog.entity_aliases;
drop policy curator_all on catalog.attribute_claims;
drop policy curator_all on catalog.duplicate_candidates;
drop policy curator_all on catalog.entity_merges;
drop policy curator_all on catalog.wine_links;
drop policy curator_all on catalog.canonical_events;
create policy curator_read on catalog.producers for select to catalog_curator using (true);
create policy curator_read on catalog.wines for select to catalog_curator using (true);
create policy curator_read on catalog.wine_vintages for select to catalog_curator using (true);
create policy curator_read on catalog.wine_formats for select to catalog_curator using (true);
create policy curator_read on catalog.entity_aliases for select to catalog_curator using (true);
create policy curator_read on catalog.attribute_claims for select to catalog_curator using (true);
create policy curator_read on catalog.duplicate_candidates for select to catalog_curator using (true);
create policy curator_read on catalog.entity_merges for select to catalog_curator using (true);
create policy curator_read on catalog.wine_links for select to catalog_curator using (true);
create policy curator_read on catalog.canonical_events for select to catalog_curator using (true);

alter table catalog.promotion_exceptions enable row level security;
create policy curator_read on catalog.promotion_exceptions for select to catalog_curator using (true);
grant select on catalog.promotion_exceptions to catalog_curator;

grant execute on function
  catalog.fold_text(text),
  catalog.promotion_batch(uuid, integer),
  catalog.promotion_blocked(uuid, integer),
  catalog.promotion_candidates(uuid),
  catalog.producer_final(uuid),
  catalog.promotion_preview(text, text),
  catalog.detect_duplicate_candidates(integer),
  catalog.promote_wine_candidates(text, text, integer, boolean, text),
  catalog.review_duplicate_candidate(bigint, text, text, text),
  catalog.open_duplicate_candidate(text, uuid, uuid, text, text),
  catalog.merge_canonical_entity(bigint, text, text, text),
  catalog.revert_canonical_merge(bigint, text),
  catalog.retire_canonical_entity(text, uuid, text, text),
  catalog.add_manual_producer(text, bigint, text, text),
  catalog.add_manual_wine(uuid, text, text, text, text, text, text, bigint, text, text),
  catalog.add_entity_alias(text, uuid, text, text, text, uuid, bigint, text, text),
  catalog.add_wine_vintage(uuid, integer, boolean, text, uuid, bigint, text, text),
  catalog.add_wine_format(uuid, integer, integer, text, text, uuid, bigint, text, text),
  catalog.propose_attribute_claim(text, text, uuid, jsonb, uuid, bigint, text, text),
  catalog.review_attribute_claim(bigint, text, text),
  catalog.propose_wine_link(uuid, text, uuid, text, text),
  catalog.review_wine_link(bigint, text, text),
  catalog.search_wines(text, integer),
  catalog.wine_sheet(uuid)
  to catalog_curator;
-- il curatore NON registra eventi da sé né chiama le funzioni interne (le porte definer le eseguono come proprietario)
revoke execute on function catalog.record_canonical_event(text, text, text, text, jsonb) from catalog_curator;

comment on function catalog.promote_wine_candidates(text, text, integer, boolean, text) is
  'WI-001C-FIX-01: promozione conservativa. DISATTIVATA di default. Definer: richiede interruttore acceso, regola lwin-conservative-v1 approvata con l''impronta della logica attuale, p_dry_run = false.';
