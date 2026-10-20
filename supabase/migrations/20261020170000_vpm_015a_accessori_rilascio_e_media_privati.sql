-- VPM-015A, correzione approvata dal titolare: rilascio riservato e foto private.
--
-- Questa migrazione CORREGGE `20261020120000_vpm_015a_accessori_fondazione`,
-- che e gia sul branch remoto e quindi congelata: non la si modifica, la si
-- completa con una successiva.
--
--   [1] La visibilita PUBBLICA del catalogo non la accende piu un admin
--       qualsiasi. Serve il ruolo di rilascio `accessori_release`, assegnabile
--       solo dal service_role (nessuna porta client scrive `user_roles`), e un
--       trigger vincola anche i writer privilegiati: la riga si accende solo
--       dalla porta di rilascio. Spegnere resta consentito a ogni admin
--       (interruttore di emergenza: il verso sicuro non richiede approvazione).
--   [2] Il bucket `accessori-media` diventa PRIVATO. Un percorso noto non apre
--       piu nulla: i byte si leggono solo con una URL firmata, e la firma e
--       concessa da una policy di Storage soltanto (a) all'admin reale, per
--       qualunque oggetto del bucket, oppure (b) a chiunque, per le sole foto
--       di schede PUBBLICATE mentre la visibilita pubblica e accesa.
--
-- Nessuna identita personale o segreto: il rilascio e un ruolo, non una persona.
-- Solo modifiche additive o correttive; nessun dato esistente viene riscritto.

-- ---------------------------------------------------------------------------
-- [1] Rilascio riservato
-- ---------------------------------------------------------------------------

-- Boolean per la UI: dice al chiamante se e un admin reale con il ruolo di
-- rilascio. Risponde solo sul chiamante stesso.
create function private.accessori_puo_rilasciare()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.user_roles ur
    where ur.user_id = (select auth.uid()) and ur.role = 'admin'
  ) and exists (
    select 1 from public.user_roles ur
    where ur.user_id = (select auth.uid()) and ur.role = 'accessori_release'
  );
$$;

revoke execute on function private.accessori_puo_rilasciare() from public, anon, authenticated;

create function private.accessori_rilascio_richiesto()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.accessori_admin_richiesto();
begin
  if not private.accessori_puo_rilasciare() then
    raise exception 'Il rilascio pubblico richiede l''approvazione del titolare.'
      using errcode = '42501', hint = 'rilascio_non_autorizzato';
  end if;
  return v_admin;
end;
$$;

revoke execute on function private.accessori_rilascio_richiesto() from public, anon, authenticated;

-- Vincola ANCHE i writer privilegiati: la riga si porta da spenta a accesa
-- solo se la porta di rilascio ha dichiarato, nella stessa transazione, chi
-- rilascia. Spegnere e sempre consentito. Un writer che vuole accendere da SQL
-- diretto deve dichiararlo apertamente (e restare nel registro): non puo farlo
-- per errore o con un normale ruolo admin.
create function private.accessori_impostazioni_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.visibilita_pubblica and not old.visibilita_pubblica then
    if new.aggiornato_da is null
       or coalesce(current_setting('vinae.accessori_rilascio', true), '')
          <> 'rilascio:' || new.aggiornato_da::text then
      raise exception 'La visibilita pubblica si accende solo dalla porta di rilascio.'
        using errcode = '42501', hint = 'rilascio_non_autorizzato';
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function private.accessori_impostazioni_guard() from public, anon, authenticated;

create trigger accessori_impostazioni_guard
  before update on private.accessori_impostazioni
  for each row execute function private.accessori_impostazioni_guard();

-- Stato per la UI admin: aggiunge `puo_rilasciare`. Stessa firma, stesso tipo.
create or replace function public.accessori_admin_stato()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.accessori_admin_richiesto();
  return jsonb_build_object(
    'visibilita_pubblica', private.accessori_visibili_al_pubblico(),
    'puo_rilasciare', private.accessori_puo_rilasciare()
  );
end;
$$;

-- Stessa firma e stessi grant (authenticated): cambia il controllo. Accendere
-- richiede il rilascio; spegnere richiede soltanto un admin reale.
create or replace function public.accessori_admin_visibilita_imposta(p_attiva boolean, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid;
  v_motivo text := private.partner_motivo_pulito(p_motivo);
begin
  if p_attiva is null then
    raise exception 'Valore non valido.' using errcode = '22023', hint = 'dati_non_validi';
  end if;
  if p_attiva then
    v_admin := private.accessori_rilascio_richiesto();
  else
    v_admin := private.accessori_admin_richiesto();
  end if;
  if v_motivo is null then
    raise exception 'Il cambio di visibilita richiede un motivo.' using errcode = '22023', hint = 'motivo_obbligatorio';
  end if;

  -- Dichiara il rilascio per il trigger di guardia; vale solo in questa transazione.
  perform set_config('vinae.accessori_rilascio', 'rilascio:' || v_admin::text, true);

  update private.accessori_impostazioni
  set visibilita_pubblica = p_attiva, aggiornato_da = v_admin
  where singleton;

  insert into private.accessori_registro (admin_id, azione, oggetto, motivo)
  values (v_admin, case when p_attiva then 'visibilita_accendi' else 'visibilita_spegni' end,
          'visibilita', v_motivo);

  return jsonb_build_object('visibilita_pubblica', p_attiva);
end;
$$;

comment on function public.accessori_admin_visibilita_imposta(boolean, text) is
  'Accende (solo con il ruolo di rilascio accessori_release) o spegne (ogni admin) '
  'la visibilita PUBBLICA del catalogo nel database. Motivo obbligatorio, registrato. '
  'Non sostituisce ne e sostituita dalla flag d''ambiente.';

-- ---------------------------------------------------------------------------
-- [2] Foto realmente private
-- ---------------------------------------------------------------------------
--
-- `public = false`: l'endpoint `/object/public/...` non serve piu il bucket,
-- nemmeno a chi conosce il percorso intero. Restano le URL firmate, che la
-- policy di SELECT sotto concede in due soli casi.

update storage.buckets set public = false where id = 'accessori-media';

-- Vero solo per una foto collegata a una scheda PUBBLICATA, in una categoria
-- attiva, mentre la visibilita pubblica e accesa: la stessa regola delle
-- letture pubbliche. Bozze, archiviate e cataloghi spenti restano admin-only.
create function private.accessorio_media_pubblica(p_percorso text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_percorso is not null
    and private.accessori_visibili_al_pubblico()
    and exists (
      select 1
      from private.accessori a
      join private.accessori_categorie c on c.id = a.categoria_id
      left join private.accessori_categorie g on g.id = c.parent_id
      where a.stato = 'pubblicato'
        and p_percorso = any (a.immagini)
        and c.attiva and (g.id is null or g.attiva)
    );
$$;

revoke all on function private.accessorio_media_pubblica(text) from public;
grant execute on function private.accessorio_media_pubblica(text) to anon, authenticated;

-- La policy di SELECT dell'admin (migrazione precedente) copre l'anteprima di
-- qualunque oggetto; questa copre soltanto le foto pubblicate, per tutti.
create policy "accessori_media_select_pubblicate"
on storage.objects
for select
to anon, authenticated
using (
  bucket_id = 'accessori-media'
  and private.accessorio_media_pubblica(name)
);
