-- WI-016E — Wine Research: errore di dominio distinto dal rifiuto di autorizzazione.
--
-- La matrice 12h chiama ogni porta riservata agli admin con argomenti vuoti: il delegato deve
-- ricevere 42501, l'admin no. catalog.research_submit rispondeva 42501 anche per una fonte non
-- autorizzata o senza diritti dichiarati, cioè per un dato in ingresso rifiutato a un chiamante
-- già autorizzato. 42501 resta riservato a «chi sei»; qui diventa P0001, il codice di dominio
-- che il pannello del catalogo mostra con il suo messaggio. Le fonti restano fail-closed:
-- cambiano soltanto i due codici d'errore. La migration C è distribuita e non si modifica.

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
  if v_claim is not null then
    return v_claim;
  end if;
  v_claim := catalog.propose_attribute_claim(p_attribute, p_subject_type, p_subject_id, p_value, s.id, null,
    left('Ricerca: ' || v_reference, 1000), v_actor);
  insert into catalog.research_provenance (claim_id, reference, retrieved_at, confidence, rights, submitted_by)
  values (v_claim, v_reference, p_retrieved_at, p_confidence, left(v_rights, 500), v_actor);
  perform brain.enqueue_task('ricerca.verifica', 'Informazione di ricerca da verificare n. ' || v_claim::text, 3,
    jsonb_build_object('rivendicazione_id', v_claim), 'ricerca:' || v_claim::text, true, null);
  return v_claim;
end;
$$;

revoke all on function catalog.research_submit(text, text, uuid, text, jsonb, text, timestamptz, integer, text)
  from public, anon, authenticated, service_role, catalog_curator, catalog_loader;
