-- WI-017: nessuna conferma senza task. La transazione annulla anche la
-- prenotazione/registrazione locale se la coda non accetta il lavoro.
alter table catalog.research_provenance
  drop constraint research_provenance_pkey,
  add primary key (claim_id, reference);

create or replace function catalog.research_submit(p_source_code text, p_subject_type text, p_subject_id uuid,
  p_attribute text, p_value jsonb, p_reference text, p_retrieved_at timestamptz, p_confidence integer, p_actor text)
returns bigint language plpgsql volatile set search_path = '' as $$
declare
  v_actor text := catalog.require_actor(p_actor);
  s catalog.sources%rowtype;
  v_rights text;
  v_reference text := btrim(coalesce(p_reference, ''));
  v_claim bigint;
begin
  select * into s from catalog.sources x where x.code = p_source_code;
  -- fail-closed: senza autorizzazione verificata e diritti dichiarati la fonte non si usa
  if not found or s.authorization_status <> 'authorized' or s.verified_at is null then
    raise exception 'catalog: fonte non autorizzata per la ricerca' using errcode = 'P0001';
  end if;
  v_rights := coalesce(nullif(btrim(coalesce(s.license, '')), ''), nullif(btrim(coalesce(s.attribution_text, '')), ''));
  if v_rights is null then
    raise exception 'catalog: la fonte non dichiara diritti di utilizzo' using errcode = 'P0001';
  end if;
  if length(v_reference) not between 3 and 500 or v_reference ~ '[[:cntrl:]<>@]'
     or (v_reference ~* '^[a-z]+://' and v_reference !~* '^https://') then
    raise exception 'catalog: riferimento della fonte non valido' using errcode = '22023';
  end if;
  if p_retrieved_at is null or p_retrieved_at > clock_timestamp() + interval '5 minutes'
     or p_retrieved_at < clock_timestamp() - interval '5 years' then
    raise exception 'catalog: data di acquisizione non valida' using errcode = '22023';
  end if;
  if p_confidence is null or p_confidence not between 1 and 5 then
    raise exception 'catalog: attendibilità da 1 a 5' using errcode = '22023';
  end if;
  if p_value is null or jsonb_typeof(p_value) = 'null' or octet_length(p_value::text) > 4000
     or p_value::text ~* '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}' then
    raise exception 'catalog: valore non ammesso' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('catalog.research:' || coalesce(p_subject_id::text, '') || ':' || coalesce(p_attribute, ''), 0));
  select c.id into v_claim from catalog.attribute_claims c
   where c.attribute_key = p_attribute and c.source_id = s.id and c.value = p_value and c.status = 'proposed'
     and coalesce(c.producer_id, c.wine_id, c.vintage_id, c.format_id) = p_subject_id
   limit 1;
  if v_claim is null then
    v_claim := catalog.propose_attribute_claim(p_attribute, p_subject_type, p_subject_id, p_value, s.id, null,
      left('Ricerca: ' || v_reference, 1000), v_actor);
  end if;
  insert into catalog.research_provenance (claim_id, reference, retrieved_at, confidence, rights, submitted_by)
  values (v_claim, v_reference, p_retrieved_at, p_confidence, left(v_rights, 500), v_actor)
  on conflict (claim_id, reference) do nothing;
  if brain.enqueue_task('ricerca.verifica', 'Informazione di ricerca da verificare n. ' || v_claim::text, 3,
    jsonb_build_object('rivendicazione_id', v_claim), 'ricerca:' || v_claim::text, true, null) is null then
    raise exception 'Coda ricerca temporaneamente piena.' using errcode = '53400';
  end if;
  return v_claim;
end;
$$;

create or replace function catalog.research_context(p_claim bigint)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'rivendicazione_id', c.id, 'attributo', c.attribute_key, 'stato', c.status, 'valore', c.value,
    'fonte', jsonb_build_object('codice', s.code, 'affidabilita', s.trust_tier, 'autorizzata', s.authorization_status = 'authorized'),
    'provenienza', (select jsonb_build_object('riferimento', p.reference, 'acquisita', p.retrieved_at, 'attendibilita', p.confidence)
                      from catalog.research_provenance p where p.claim_id = c.id
                     order by p.created_at, p.reference limit 1),
    'riferimenti', coalesce((select jsonb_agg(x.reference order by x.created_at, x.reference)
                      from (select p.reference, p.created_at from catalog.research_provenance p where p.claim_id = c.id
                            order by p.created_at, p.reference limit 20) x), '[]'::jsonb),
    'accettata', (select jsonb_build_object('id', a.id, 'valore', a.value, 'fonte', x.code, 'affidabilita', x.trust_tier)
                    from catalog.attribute_claims a join catalog.sources x on x.id = a.source_id
                   where a.attribute_key = c.attribute_key and a.status = 'accepted'
                     and coalesce(a.producer_id, a.wine_id, a.vintage_id, a.format_id)
                       = coalesce(c.producer_id, c.wine_id, c.vintage_id, c.format_id)),
    'altre_proposte', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'valore', o.value, 'fonte', x.code,
                          'affidabilita', x.trust_tier) order by o.id)
                      from (select * from catalog.attribute_claims q
                             where q.attribute_key = c.attribute_key and q.status = 'proposed' and q.id <> c.id
                               and coalesce(q.producer_id, q.wine_id, q.vintage_id, q.format_id)
                                 = coalesce(c.producer_id, c.wine_id, c.vintage_id, c.format_id)
                             order by q.id limit 10) o
                      join catalog.sources x on x.id = o.source_id), '[]'::jsonb))
    from catalog.attribute_claims c join catalog.sources s on s.id = c.source_id
   where c.id = p_claim;
$$;

create or replace function public.cellar_verifica_autenticita_richiedi(p_bottle_unit_id uuid, p_anomalie text[], p_consenso boolean)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  v_anomalie text[];
  v_esito text := 'gia_aperta';
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if not public.cellar_verifica_autenticita_disponibile() then
    raise exception 'Le richieste di verifica non sono attive.' using errcode = 'P0001';
  end if;
  if p_consenso is not true then
    raise exception 'Serve il tuo consenso per richiedere una verifica.' using errcode = 'P0001';
  end if;
  -- un solo messaggio per «non esiste» e «non è tua»
  if not exists (select 1 from public.bottle_units b
                  where b.id = p_bottle_unit_id and b.owner_id = v_uid and b.deleted_at is null and b.ceduta_at is null) then
    raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
  end if;
  select array_agg(distinct a order by a) into v_anomalie from unnest(p_anomalie) a;
  if v_anomalie is null then
    raise exception 'Indica almeno un segnale da verificare.' using errcode = '22023';
  end if;
  select r.id into v_id from private.autenticita_richieste r where r.bottle_unit_id = p_bottle_unit_id and r.stato <> 'chiusa';
  if v_id is null then
    perform private.rate_limit_consume('autenticita', 'user:' || v_uid::text, 3, 86400);
    begin
      insert into private.autenticita_richieste (owner_id, bottle_unit_id, anomalie)
      values (v_uid, p_bottle_unit_id, v_anomalie) returning id into v_id;
    exception
      when check_violation then
        raise exception 'Segnale non riconosciuto.' using errcode = '22023';
      when unique_violation then
        return 'gia_aperta';
    end;
    v_esito := 'ricevuta';
  end if;
  -- nel bus solo il riferimento opaco: nessun proprietario, nessuna bottiglia
  if brain.enqueue_task('autenticita.verifica', 'Richiesta di verifica di una bottiglia', 2,
    jsonb_build_object('richiesta_id', v_id), 'autenticita:' || v_id::text, true, null) is null then
    raise exception 'Coda verifiche temporaneamente piena.' using errcode = '53400';
  end if;
  return v_esito;
end;
$$;
