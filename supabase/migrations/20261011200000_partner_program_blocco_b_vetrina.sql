-- ===========================================================================
-- Vinea Partner — Blocco B: vetrina pubblica del Partner
-- ===========================================================================
--
-- Ammissione: filone «Vinea Partner + Quantita multiple» (blocchi A-F), deciso
-- dal titolare l'11 ottobre 2026 e registrato in docs/ROADMAP_V1.md. Questo
-- file realizza soltanto il Blocco B. La migrazione del Blocco A
-- (20261011150000) e distribuita e congelata: qui non si riscrive nessuno dei
-- suoi oggetti, salvo ampliare di una voce il CHECK degli eventi di audit.
--
-- Decisione di prodotto: il profilo pubblico del titolare di un Partner ATTIVO
-- e la vetrina commerciale. Non esiste un secondo sito ne una seconda pagina:
-- `/profilo/<id>` legge `vetrina_partner_pubblica(<id>)` e, se risponde, si
-- presenta come vetrina. La classe la decide il database dallo stato del
-- Partner, mai il client e mai le qualifiche personali.
--
-- Che cosa aggiunge:
--   [1] l'evento di audit `vetrina_aggiornata`;
--   [2] `private.partner_vetrine`: contenuti della vetrina (presentazione,
--       descrizione, logo, copertina, fino a quattro fotografie), separati
--       dall'identita aziendale dichiarata, che resta congelata alla consegna;
--   [3] il bucket pubblico `partner-vetrine`, solo WebP fino a 2 MB, con
--       caricamento limitato alla cartella `<titolare>/<partner>/` del
--       titolare di un Partner modificabile, nessuna sovrascrittura e
--       cancellazione solo dei file propri non in uso;
--   [4] le porte `vetrina_partner_mia`, `vetrina_partner_salva` (titolare),
--       `vetrina_partner_pubblica` (chiunque, una riga per uuid, solo Partner
--       attivi) e `acquisto_da_venditore_disponibile` (specchio del gate);
--   [5] un gate sulle proposte d'acquisto gemello di quello sugli ordini.
--
-- Che cosa NON fa, di proposito:
--   - non espone partita IVA, ragione sociale, indirizzo della sede, email
--     commerciale, motivi amministrativi ne documenti: la proiezione pubblica
--     e un elenco chiuso di colonne;
--   - non apre il checkout professionale, non tocca `marketplace_config`,
--     `order_checkout_reserve` ne il gate sugli ordini del Blocco A;
--   - non decide il caso `revocato` per la vendita privata (decisione del
--     titolare, prima dei blocchi commerciali): i due gate restano su
--     `attivo` e `sospeso`, esattamente come il Blocco A;
--   - non introduce quantita, giacenze o un secondo catalogo: i prodotti
--     della vetrina sono gli annunci gia pubblici del titolare
--     (`public.public_listings`); quantita e disponibilita sono il Blocco C;
--   - non introduce link esterni: nessuna funzione approvata li prevede.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- [1] Audit: un evento in piu
-- ---------------------------------------------------------------------------

alter table private.partner_eventi
  drop constraint partner_eventi_evento_forma;

alter table private.partner_eventi
  add constraint partner_eventi_evento_forma check (evento in (
    'invito_creato', 'invito_usato', 'invito_revocato',
    'partner_creato', 'dati_aggiornati', 'stato_cambiato',
    'vetrina_aggiornata'
  ));

-- ---------------------------------------------------------------------------
-- [2] Contenuti della vetrina
-- ---------------------------------------------------------------------------

-- Un percorso di media appartiene a UNA vetrina: cartella del titolare,
-- sottocartella del Partner, nome canonico. La forma e la stessa delle cover
-- dei Club (`<uid>/<uuid>.webp`) con un livello in piu.
create function private.partner_media_percorso_valido(
  p_percorso text,
  p_titolare uuid,
  p_partner uuid
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_percorso is not null
    and p_titolare is not null
    and p_partner is not null
    and p_percorso ~ (
      '^' || p_titolare::text || '/' || p_partner::text
      || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.webp$'
    );
$$;

revoke execute on function private.partner_media_percorso_valido(text, uuid, uuid)
  from public, anon, authenticated;

create table private.partner_vetrine (
  partner_id uuid primary key references private.partners (id) on delete restrict,
  presentazione text,
  descrizione text,
  logo_path text,
  copertina_path text,
  foto_paths text[] not null default '{}'::text[],
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint partner_vetrine_presentazione_forma check (
    presentazione is null
    or (presentazione = btrim(presentazione) and length(presentazione) between 1 and 160)),
  constraint partner_vetrine_descrizione_forma check (
    descrizione is null
    or (descrizione = btrim(descrizione) and length(descrizione) between 1 and 2000)),
  constraint partner_vetrine_foto_forma check (
    cardinality(foto_paths) <= 4
    and array_position(foto_paths, null) is null
    and (cardinality(foto_paths) = 0 or array_ndims(foto_paths) = 1))
);

comment on table private.partner_vetrine is
  'Contenuti della vetrina pubblica di un Partner, scritti dal titolare. '
  'Separati da private.partners: l identita dichiarata si congela alla '
  'consegna, la vetrina resta curabile. Pubblica solo per i Partner attivi '
  'tramite vetrina_partner_pubblica(uuid). Nessun grant client.';

alter table private.partner_vetrine enable row level security;
revoke all on private.partner_vetrine from public, anon, authenticated;

-- Guardiano: stessa forma di private.partners_guard. Il marcatore
-- `titolare:vetrina:<partner_id>` lo apre solo vetrina_partner_salva.
create function private.partner_vetrine_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_porta text := private.partner_porta_corrente();
  v_titolare uuid;
  v_stato public.partner_stato;
  v_percorsi text[];
  v_percorso text;
begin
  if tg_op = 'DELETE' then
    raise exception 'Una vetrina Partner non si cancella.' using errcode = '42501';
  end if;

  if v_porta <> 'titolare:vetrina:' || new.partner_id::text then
    raise exception 'Una vetrina Partner si modifica solo con vetrina_partner_salva.'
      using errcode = '42501';
  end if;

  if tg_op = 'UPDATE' and (new.partner_id, new.created_at) is distinct from (old.partner_id, old.created_at) then
    raise exception 'Identita della vetrina immutabile.' using errcode = '42501';
  end if;

  select p.titolare_id, p.stato into v_titolare, v_stato
  from private.partners p where p.id = new.partner_id;

  if v_stato is null or v_stato not in ('invitato'::public.partner_stato,
                                        'in_verifica'::public.partner_stato,
                                        'attivo'::public.partner_stato) then
    raise exception 'Vetrina non modificabile in questo stato del Partner.'
      using errcode = '42501';
  end if;

  v_percorsi := array_remove(array[new.logo_path, new.copertina_path] || new.foto_paths, null);
  foreach v_percorso in array v_percorsi loop
    if not private.partner_media_percorso_valido(v_percorso, v_titolare, new.partner_id) then
      raise exception 'Percorso di media non valido per questa vetrina.' using errcode = '42501';
    end if;
  end loop;
  if cardinality(v_percorsi) <> (select count(distinct x) from unnest(v_percorsi) x) then
    raise exception 'Lo stesso file non si usa due volte nella vetrina.' using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    new.created_at := now();
  end if;
  new.updated_at := now();
  return new;
end;
$$;

revoke execute on function private.partner_vetrine_guard() from public, anon, authenticated;

create trigger partner_vetrine_guard
  before insert or update or delete on private.partner_vetrine
  for each row execute function private.partner_vetrine_guard();

create trigger partner_vetrine_no_truncate
  before truncate on private.partner_vetrine
  for each statement execute function private.partner_no_truncate();

-- Audit: solo i nomi dei campi cambiati, mai i testi ne i percorsi.
create function private.partner_vetrine_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_campi text[] := array[]::text[];
begin
  if tg_op = 'INSERT' then
    if new.presentazione is not null then v_campi := array_append(v_campi, 'presentazione'::text); end if;
    if new.descrizione is not null then v_campi := array_append(v_campi, 'descrizione'::text); end if;
    if new.logo_path is not null then v_campi := array_append(v_campi, 'logo'::text); end if;
    if new.copertina_path is not null then v_campi := array_append(v_campi, 'copertina'::text); end if;
    if cardinality(new.foto_paths) > 0 then v_campi := array_append(v_campi, 'foto'::text); end if;
  else
    if new.presentazione is distinct from old.presentazione then v_campi := array_append(v_campi, 'presentazione'::text); end if;
    if new.descrizione is distinct from old.descrizione then v_campi := array_append(v_campi, 'descrizione'::text); end if;
    if new.logo_path is distinct from old.logo_path then v_campi := array_append(v_campi, 'logo'::text); end if;
    if new.copertina_path is distinct from old.copertina_path then v_campi := array_append(v_campi, 'copertina'::text); end if;
    if new.foto_paths is distinct from old.foto_paths then v_campi := array_append(v_campi, 'foto'::text); end if;
  end if;

  if cardinality(v_campi) > 0 then
    insert into private.partner_eventi (partner_id, evento, attore_id, porta, dettagli)
    values (new.partner_id, 'vetrina_aggiornata', auth.uid(), private.partner_porta_tipo(),
            jsonb_build_object('campi', to_jsonb(v_campi)));
  end if;
  return null;
end;
$$;

revoke execute on function private.partner_vetrine_audit() from public, anon, authenticated;

create trigger partner_vetrine_audit
  after insert or update on private.partner_vetrine
  for each row execute function private.partner_vetrine_audit();

-- ---------------------------------------------------------------------------
-- [3] Storage: bucket `partner-vetrine`
-- ---------------------------------------------------------------------------
--
-- Pubblico come `club-covers`, `annunci` e `avatar-profili`: le immagini di
-- una vetrina pubblica si servono senza firma. Un percorso contiene due uuid e
-- un nome casuale, e nessun ruolo client puo elencare le cartelle altrui
-- (SELECT solo sulla propria). Chi non e Partner attivo non ha una vetrina
-- che li citi: la proiezione pubblica [4] e l'unica fonte dei percorsi.
--
-- Solo `image/webp` fino a 2 MB, imposti dallo Storage: il client ricodifica
-- ogni immagine prima del caricamento. Nessuna policy di UPDATE: un oggetto
-- non si sovrascrive, si sostituisce con un nome nuovo.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('partner-vetrine', 'partner-vetrine', true, 2097152, array['image/webp'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Le policy di Storage girano a privilegi del chiamante e non leggono
-- `private.partners`: queste due funzioni rispondono solo sul chiamante.
create function private.partner_vetrina_cartella_del_chiamante(p_partner text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  -- La policy le passa un segmento di percorso, testo arbitrario finche la
  -- regex non l'ha confermato: il cast si protegge qui.
  if p_partner is null
     or p_partner !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return false;
  end if;

  return exists (
    select 1
    from private.partners p
    where p.id = p_partner::uuid
      and p.titolare_id = (select auth.uid())
      and p.stato in ('invitato'::public.partner_stato,
                      'in_verifica'::public.partner_stato,
                      'attivo'::public.partner_stato)
  ) and private.utente_stato_di((select auth.uid())) = 'attivo'::public.utente_stato;
end;
$$;

comment on function private.partner_vetrina_cartella_del_chiamante(text) is
  'Vero se il Partner indicato e del chiamante, e in uno stato con vetrina '
  'modificabile e il chiamante non e sospeso o rimosso. Serve alla policy di '
  'caricamento del bucket partner-vetrine. Non accetta un titolare.';

revoke all on function private.partner_vetrina_cartella_del_chiamante(text) from public, anon;
grant execute on function private.partner_vetrina_cartella_del_chiamante(text) to authenticated;

create function private.partner_media_cancellabile_dal_chiamante(p_percorso text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_percorso is not null
    and split_part(p_percorso, '/', 1) = (select auth.uid())::text
    and not exists (
      select 1
      from private.partner_vetrine v
      where v.logo_path = p_percorso
         or v.copertina_path = p_percorso
         or p_percorso = any (v.foto_paths)
    );
$$;

comment on function private.partner_media_cancellabile_dal_chiamante(text) is
  'Vero se il file e nella cartella del chiamante e nessuna vetrina lo usa. '
  'Serve alla policy di cancellazione del bucket partner-vetrine: un file in '
  'uso si toglie prima dalla vetrina, poi si cancella.';

revoke all on function private.partner_media_cancellabile_dal_chiamante(text) from public, anon;
grant execute on function private.partner_media_cancellabile_dal_chiamante(text) to authenticated;

create policy "partner_vetrine_select_propria_cartella"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'partner-vetrine'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "partner_vetrine_insert_propria_cartella"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'partner-vetrine'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and name ~ (
    '^' || (select auth.uid())::text
    || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
    || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
    || '\.webp$'
  )
  and private.partner_vetrina_cartella_del_chiamante((storage.foldername(name))[2])
);

create policy "partner_vetrine_delete_propria_non_in_uso"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'partner-vetrine'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and private.partner_media_cancellabile_dal_chiamante(name)
);

-- ---------------------------------------------------------------------------
-- [4] Porte
-- ---------------------------------------------------------------------------

-- Proiezione pubblicabile: elenco chiuso. Una colonna aggiunta a
-- private.partners o a private.partner_vetrine resta privata finche non
-- viene aggiunta qui di proposito.
create function private.partner_vetrina_json(p private.partners, v private.partner_vetrine)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'partner_id', p.id,
    'titolare_id', p.titolare_id,
    'nome_commerciale', p.nome_commerciale,
    'tipologia', p.tipologia,
    'sede_citta', p.sede_citta,
    'sede_provincia', p.sede_provincia,
    'paese', p.paese,
    'attivo_dal', p.attivo_dal,
    'presentazione', v.presentazione,
    'descrizione', v.descrizione,
    'logo_path', v.logo_path,
    'copertina_path', v.copertina_path,
    'foto_paths', coalesce(to_jsonb(v.foto_paths), '[]'::jsonb),
    'aggiornata_at', v.updated_at
  );
$$;

revoke execute on function private.partner_vetrina_json(private.partners, private.partner_vetrine)
  from public, anon, authenticated;

-- Il titolare legge la propria vetrina in ogni stato (anche sospeso o
-- revocato, in sola lettura), con la cartella di caricamento.
create function public.vetrina_partner_mia()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_p private.partners%rowtype;
  v_v private.partner_vetrine%rowtype;
begin
  if v_uid is null then
    raise exception 'Serve una sessione.' using errcode = '42501';
  end if;

  select * into v_p
  from private.partners p
  where p.titolare_id = v_uid
  order by (p.stato = 'revocato'::public.partner_stato), p.created_at desc
  limit 1;

  if v_p.id is null then
    return null;
  end if;

  select * into v_v from private.partner_vetrine where partner_id = v_p.id;

  return private.partner_vetrina_json(v_p, v_v) || jsonb_build_object(
    'stato', v_p.stato,
    'modificabile', v_p.stato in ('invitato'::public.partner_stato,
                                  'in_verifica'::public.partner_stato,
                                  'attivo'::public.partner_stato)
                    and private.utente_stato_di(v_uid) = 'attivo'::public.utente_stato,
    'cartella', v_uid::text || '/' || v_p.id::text
  );
end;
$$;

comment on function public.vetrina_partner_mia() is
  'Solo il titolare. Vetrina del proprio Partner piu recente, con stato, '
  'modificabilita e cartella di caricamento. null senza Partner.';

-- Salvataggio completo e atomico della vetrina: testi e riferimenti ai media
-- gia caricati. Il client carica prima i file nuovi, poi chiama questa porta,
-- poi cancella i file che non usa piu (la policy lo consente solo per quelli).
create function public.vetrina_partner_salva(
  p_presentazione text,
  p_descrizione text,
  p_logo text,
  p_copertina text,
  p_foto text[]
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_p private.partners%rowtype;
  v_presentazione text := nullif(btrim(coalesce(p_presentazione, '')), '');
  v_descrizione text := nullif(btrim(coalesce(p_descrizione, '')), '');
  v_logo text := nullif(btrim(coalesce(p_logo, '')), '');
  v_copertina text := nullif(btrim(coalesce(p_copertina, '')), '');
  v_foto text[] := coalesce(p_foto, '{}'::text[]);
  v_percorsi text[];
  v_percorso text;
begin
  if v_uid is null then
    raise exception 'Serve una sessione.' using errcode = '42501';
  end if;
  if private.utente_stato_di(v_uid) <> 'attivo'::public.utente_stato then
    raise exception 'Account non abilitato a pubblicare contenuti.'
      using errcode = '42501', hint = 'utente_non_attivo';
  end if;

  select * into v_p from private.partners
  where titolare_id = v_uid and stato <> 'revocato'::public.partner_stato
  for update;

  if v_p.id is null then
    raise exception 'Nessun Partner aperto.' using errcode = 'P0001', hint = 'partner_non_trovato';
  end if;
  if v_p.stato not in ('invitato'::public.partner_stato,
                       'in_verifica'::public.partner_stato,
                       'attivo'::public.partner_stato) then
    raise exception 'La vetrina non e modificabile in questo stato.'
      using errcode = 'P0001', hint = 'vetrina_non_modificabile';
  end if;

  if v_presentazione is not null and length(v_presentazione) > 160 then
    raise exception 'Presentazione troppo lunga (massimo 160 caratteri).'
      using errcode = '22023', hint = 'presentazione_lunga';
  end if;
  if v_descrizione is not null and length(v_descrizione) > 2000 then
    raise exception 'Descrizione troppo lunga (massimo 2000 caratteri).'
      using errcode = '22023', hint = 'descrizione_lunga';
  end if;
  if array_position(v_foto, null) is not null
     or (cardinality(v_foto) > 0 and array_ndims(v_foto) <> 1) then
    raise exception 'Elenco di fotografie non valido.' using errcode = '22023', hint = 'media_non_valido';
  end if;
  if cardinality(v_foto) > 4 then
    raise exception 'Al massimo quattro fotografie.' using errcode = '22023', hint = 'troppe_foto';
  end if;

  v_percorsi := array_remove(array[v_logo, v_copertina] || v_foto, null);
  if cardinality(v_percorsi) <> (select count(distinct x) from unnest(v_percorsi) x) then
    raise exception 'Lo stesso file non si usa due volte nella vetrina.'
      using errcode = '22023', hint = 'media_duplicato';
  end if;

  foreach v_percorso in array v_percorsi loop
    if not private.partner_media_percorso_valido(v_percorso, v_uid, v_p.id) then
      raise exception 'Immagine non valida: deve essere un file della tua vetrina.'
        using errcode = '22023', hint = 'media_non_valido';
    end if;
    if not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'partner-vetrine'
        and o.name = v_percorso
        and coalesce(o.metadata ->> 'mimetype', '') = 'image/webp'
    ) then
      raise exception 'Immagine non trovata: caricala di nuovo.'
        using errcode = 'P0001', hint = 'media_non_trovato';
    end if;
  end loop;

  perform set_config('vinea.partner_porta', 'titolare:vetrina:' || v_p.id::text, true);
  insert into private.partner_vetrine as v
    (partner_id, presentazione, descrizione, logo_path, copertina_path, foto_paths)
  values (v_p.id, v_presentazione, v_descrizione, v_logo, v_copertina, v_foto)
  on conflict (partner_id) do update set
    presentazione = excluded.presentazione,
    descrizione = excluded.descrizione,
    logo_path = excluded.logo_path,
    copertina_path = excluded.copertina_path,
    foto_paths = excluded.foto_paths;
  perform set_config('vinea.partner_porta', '', true);

  return public.vetrina_partner_mia();
end;
$$;

comment on function public.vetrina_partner_salva(text, text, text, text, text[]) is
  'Solo il titolare di un Partner invitato, in verifica o attivo, con account '
  'attivo. Salva testi e riferimenti ai media gia caricati nella propria '
  'cartella del bucket partner-vetrine; verifica forma, quantita, unicita ed '
  'esistenza di ogni file.';

-- Lettura pubblica: un uuid di profilo, al piu una vetrina. Solo Partner
-- attivi, e solo se il profilo e pubblicamente visibile secondo
-- private.profili_pubblici (stesse regole di profilo_pubblico, nelle due
-- direzioni). Nessun elenco: non esiste una chiamata che restituisca due
-- vetrine.
create function public.vetrina_partner_pubblica(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select private.partner_vetrina_json(p, v)
  from private.partners p
  left join private.partner_vetrine v on v.partner_id = p.id
  where p.titolare_id = p_user_id
    and p.stato = 'attivo'::public.partner_stato
    and exists (select 1 from private.profili_pubblici pp where pp.user_id = p_user_id)
  limit 1;
$$;

comment on function public.vetrina_partner_pubblica(uuid) is
  'Vetrina pubblica del Partner attivo di un profilo, o null. Elenco chiuso '
  'di colonne (private.partner_vetrina_json): nessuna partita IVA, ragione '
  'sociale, indirizzo, email, motivo o stato amministrativo.';

-- Specchio del gate sugli ordini, per non mostrare un acquisto destinato a
-- fallire. Non e un'autorita: l'autorita restano i trigger su orders e
-- proposals. Non dice se il Partner e attivo o sospeso.
create function public.acquisto_da_venditore_disponibile(p_seller_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (
    select 1 from private.partners p
    where p.titolare_id = p_seller_id
      and p.stato in ('attivo'::public.partner_stato, 'sospeso'::public.partner_stato)
  );
$$;

comment on function public.acquisto_da_venditore_disponibile(uuid) is
  'false se il venditore e un Partner attivo o sospeso: stesso predicato di '
  'private.partner_checkout_gate. Solo per l interfaccia; i gate restano '
  'l autorita.';

do $$
declare
  v_firma text;
begin
  foreach v_firma in array array[
    'public.vetrina_partner_mia()',
    'public.vetrina_partner_salva(text, text, text, text, text[])',
    'public.vetrina_partner_pubblica(uuid)',
    'public.acquisto_da_venditore_disponibile(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_firma);
  end loop;
end $$;

grant execute on function public.vetrina_partner_mia() to authenticated;
grant execute on function public.vetrina_partner_salva(text, text, text, text, text[]) to authenticated;
grant execute on function public.vetrina_partner_pubblica(uuid) to anon, authenticated;
grant execute on function public.acquisto_da_venditore_disponibile(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- [5] Gate sulle proposte
-- ---------------------------------------------------------------------------
--
-- Una proposta verso un Partner attivo o sospeso non potrebbe mai diventare un
-- ordine (gate del Blocco A): aprirla lascerebbe una trattativa senza uscita.
-- Stesso predicato e stesso hint del gate sugli ordini; non tocca proposte
-- esistenti, compratori Partner, Partner non attivi, privati.

create function private.partner_proposta_gate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from private.partners p
    where p.titolare_id = new.seller_id
      and p.stato in ('attivo'::public.partner_stato, 'sospeso'::public.partner_stato)
  ) then
    raise exception 'Gli acquisti da Partner Vinea non sono ancora disponibili.'
      using errcode = '42501', hint = 'partner_checkout_non_disponibile';
  end if;
  return new;
end;
$$;

comment on function private.partner_proposta_gate() is
  'Blocco B Partner: nessuna nuova proposta con venditore Partner attivo o '
  'sospeso, gemello di private.partner_checkout_gate.';

revoke execute on function private.partner_proposta_gate() from public, anon, authenticated;

create trigger proposals_partner_gate
  before insert on public.proposals
  for each row execute function private.partner_proposta_gate();

notify pgrst, 'reload schema';
