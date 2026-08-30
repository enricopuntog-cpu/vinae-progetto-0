-- Segnalazione diretta dei Club dentro il dominio di moderazione esistente.

insert into public.report_reasons (target_tipo, motivo, ordine) values
  ('club', 'contenuto_non_conforme', 1),
  ('club', 'comportamento_scorretto', 2),
  ('club', 'spam', 3),
  ('club', 'altro', 4);

alter table public.reports drop constraint reports_target_coerente;

alter table public.reports
  add constraint reports_target_coerente check (
    case target_tipo
      when 'annuncio' then target_profile_id is null and target_message_id is null
        and target_conversation_id is null and target_review_id is null
        and target_post_id is null and target_risposta_id is null
      when 'profilo' then target_listing_id is null and target_message_id is null
        and target_conversation_id is null and target_review_id is null
        and target_post_id is null and target_risposta_id is null
      when 'messaggio' then target_listing_id is null and target_profile_id is null
        and target_conversation_id is null and target_review_id is null
        and target_post_id is null and target_risposta_id is null
      when 'conversazione' then target_listing_id is null and target_profile_id is null
        and target_message_id is null and target_review_id is null
        and target_post_id is null and target_risposta_id is null
      when 'recensione' then target_listing_id is null and target_profile_id is null
        and target_message_id is null and target_conversation_id is null
        and target_post_id is null and target_risposta_id is null
      when 'post' then target_listing_id is null and target_profile_id is null
        and target_message_id is null and target_conversation_id is null
        and target_review_id is null and target_risposta_id is null
      when 'commento' then target_listing_id is null and target_profile_id is null
        and target_message_id is null and target_conversation_id is null
        and target_review_id is null and target_post_id is null
      when 'club' then target_listing_id is null and target_profile_id is null
        and target_message_id is null and target_conversation_id is null
        and target_review_id is null and target_post_id is null
        and target_risposta_id is null and club_slug is not null
      else false
    end
  );

create function public.segnalazione_club_invia(
  p_club_slug text,
  p_motivo text,
  p_descrizione text default ''
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_club_slug text;
  v_club_nome text;
  v_club_owner_id uuid;
  v_descrizione text := btrim(coalesce(p_descrizione, ''));
  v_priorita public.report_priorita;
  v_codice text;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  if not exists (select 1 from public.profiles pr where pr.id = v_uid) then
    raise exception 'Profilo richiesto per inviare una segnalazione.'
      using errcode = '42501';
  end if;

  perform private.rate_limit_consume(
    'report:submit',
    'user:' || v_uid::text,
    10,
    3600
  );

  select c.slug, c.nome, c.owner_id
  into v_club_slug, v_club_nome, v_club_owner_id
  from public.clubs c
  where c.slug = btrim(coalesce(p_club_slug, ''));

  if v_club_slug is null then
    raise exception 'Club non trovato.' using errcode = 'P0001';
  end if;

  if v_club_owner_id = v_uid then
    raise exception 'Non e possibile segnalare il proprio Club.'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.report_reasons rr
    where rr.target_tipo = 'club'::public.report_target_tipo
      and rr.motivo = p_motivo
  ) then
    raise exception 'Motivo non ammesso per questo tipo di bersaglio.'
      using errcode = '22023';
  end if;

  if length(v_descrizione) > 4000 then
    raise exception 'La descrizione non puo superare 4000 caratteri.'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.reports r
    where r.reporter_id = v_uid
      and r.target_tipo = 'club'::public.report_target_tipo
      and r.club_slug = v_club_slug
      and r.stato in ('inviata', 'in_revisione', 'info_richieste')
  ) then
    raise exception 'Hai gia una segnalazione aperta su questo Club.'
      using errcode = 'P0001';
  end if;

  v_priorita := private.report_priorita_da_motivo(p_motivo);
  v_codice := 'SEG-' || to_char(now(), 'YYYY') || '-'
    || lpad(nextval('public.reports_codice_seq')::text, 4, '0');

  insert into public.reports (
    codice,
    target_tipo,
    target_label,
    motivo,
    descrizione,
    foto,
    priorita,
    reporter_id,
    club_slug
  ) values (
    v_codice,
    'club'::public.report_target_tipo,
    v_club_nome,
    p_motivo,
    v_descrizione,
    '{}',
    v_priorita,
    v_uid,
    v_club_slug
  )
  returning id into v_id;

  insert into public.report_events (
    report_id,
    visibile,
    testo,
    autore_id,
    autore_etichetta
  ) values (
    v_id,
    true,
    'Segnalazione ricevuta',
    null,
    'Moderazione'
  );

  return v_id;
end;
$$;

comment on function public.segnalazione_club_invia(text, text, text) is
  'Ingresso dedicato alle segnalazioni dirette dei Club. Risolve slug, nome e '
  'proprietario dal database e inserisce la pratica nel dominio reports esistente.';

revoke all on function public.segnalazione_club_invia(text, text, text)
  from public, anon, service_role;

grant execute on function public.segnalazione_club_invia(text, text, text)
  to authenticated;

notify pgrst, 'reload schema';
