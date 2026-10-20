-- VPM-015A — Accessori Vinea: fondazione Beta del catalogo.
--
-- Decisione del titolare: si costruisce la FONDAZIONE della sezione Accessori
-- per il vino (catalogo e bozze, area admin, vetrina dietro interruttore). Non
-- si attiva alcuna vendita: niente prezzo, valuta, varianti, checkout,
-- proposte, ordini, pagamenti, commissioni, IVA, spedizioni.
--
-- Che cosa fa questa migrazione:
--   [1] `private.accessori_categorie`: tassonomia a DUE livelli, estensibile
--       con dati (nessuna enum): categorie e sottocategorie con slug stabile,
--       ordine e stato attivo/disattivo. Seed della sola tassonomia
--       (nessun prodotto, marchio, prezzo o disponibilita);
--   [2] `private.accessori`: schede catalogo DEDICATE, separate da `wines`,
--       `bottle_units` e `listings`: nome, descrizione, categoria, marchio
--       (testo libero), condizione, quantita (interna), attributi (oggetto
--       chiuso di coppie testo), immagini (percorsi nel bucket
--       `accessori-media`), stato bozza -> pubblicato -> archiviato;
--   [3] `private.accessori_impostazioni`: interruttore di visibilita
--       PUBBLICA nel database, spento di default. E la seconda chiave oltre
--       alla flag d'ambiente: la UI e `ACCESSORI_ENABLED` non bastano;
--   [4] `private.accessori_registro`: registro append-only delle azioni admin;
--   [5] bucket Storage `accessori-media` (WebP fino a 2 MB), scrittura e
--       lettura elenco riservate all'admin reale;
--   [6] letture pubbliche (`accessori_categorie_elenca`, `accessori_elenca`,
--       `accessori_dettaglio`): elenco chiuso di colonne, solo schede
--       pubblicate, vuote finche l'interruttore e spento; con
--       `p_anteprima = true` solo un admin reale (bozze incluse, interruttore
--       ignorato);
--   [7] porte admin `accessori_admin_*` per categorie, schede, immagini,
--       stato e interruttore.
--
-- Identita e autorizzazioni: nessun ruolo nuovo. L'admin e `public.user_roles`
-- (`private.partner_admin_richiesto()`), il creatore e `public.profiles`.
-- I Partner NON creano accessori in questo blocco (differito: vedi
-- docs/VPM_015A_ACCESSORI.md).
--
-- Che cosa NON fa: nessuna tabella ne colonna di prezzo, valuta, varianti,
-- dimensioni, peso, fornitore, magazzino fornitore, personalizzazione, IVA o
-- commissione; nessun collegamento a `listings`, `orders`, `payments`,
-- `proposals`, `marketplace_config` o alle classi economiche VP-D; nessuna
-- modifica a migrazioni precedenti.
--
-- Nessuna tabella e nessuna vista e esposta: tutto vive in `private` senza
-- grant ai ruoli client. Le uniche porte sono le funzioni `public.accessori_*`.

-- ---------------------------------------------------------------------------
-- [1] Categorie
-- ---------------------------------------------------------------------------

create table private.accessori_categorie (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid references private.accessori_categorie (id) on delete restrict,
  slug text not null,
  nome text not null,
  descrizione text not null default '',
  ordine integer not null default 100,
  attiva boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accessori_categorie_slug_unico unique (slug),
  constraint accessori_categorie_slug_forma
    check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(slug) between 3 and 60),
  constraint accessori_categorie_nome_forma
    check (length(btrim(nome)) between 2 and 80),
  constraint accessori_categorie_descrizione_forma
    check (length(descrizione) <= 500),
  constraint accessori_categorie_ordine_forma
    check (ordine between 0 and 10000),
  constraint accessori_categorie_non_padre_di_se check (parent_id is distinct from id)
);

comment on table private.accessori_categorie is
  'VPM-015A: tassonomia degli accessori a due livelli (categoria, sottocategoria). '
  'Estensibile con righe, non con enum. Nessun grant client: si legge con '
  'public.accessori_categorie_elenca e si scrive con accessori_admin_categoria_salva.';

create index accessori_categorie_parent_idx on private.accessori_categorie (parent_id);

alter table private.accessori_categorie enable row level security;
revoke all on table private.accessori_categorie from public, anon, authenticated;

create trigger accessori_categorie_set_updated_at
  before update on private.accessori_categorie
  for each row execute function extensions.moddatetime('updated_at');

create function private.accessori_categorie_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_parent private.accessori_categorie%rowtype;
begin
  if tg_op = 'UPDATE' and new.id <> old.id then
    raise exception 'L''identificativo di una categoria non cambia.' using errcode = '42501';
  end if;

  if new.parent_id is not null then
    select * into v_parent from private.accessori_categorie where id = new.parent_id;
    if v_parent.id is null or v_parent.parent_id is not null then
      raise exception 'Le categorie hanno due livelli: il genitore deve essere una categoria di primo livello.'
        using errcode = '22023', hint = 'livello_non_ammesso';
    end if;
    if tg_op = 'UPDATE' and exists (
      select 1 from private.accessori_categorie k where k.parent_id = new.id
    ) then
      raise exception 'Una categoria con sottocategorie resta di primo livello.'
        using errcode = '22023', hint = 'livello_non_ammesso';
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function private.accessori_categorie_guard() from public, anon, authenticated;

create trigger accessori_categorie_guard
  before insert or update on private.accessori_categorie
  for each row execute function private.accessori_categorie_guard();

-- ---------------------------------------------------------------------------
-- [2] Schede catalogo
-- ---------------------------------------------------------------------------

create table private.accessori (
  id uuid primary key default gen_random_uuid(),
  categoria_id uuid not null references private.accessori_categorie (id) on delete restrict,
  slug text not null,
  nome text not null,
  descrizione text not null default '',
  marchio text,
  condizione text not null default 'nuovo',
  -- Informazione interna di catalogo. Non e una disponibilita promessa e non
  -- esce dalle letture pubbliche.
  quantita integer,
  attributi jsonb not null default '{}'::jsonb,
  immagini text[] not null default '{}'::text[],
  stato text not null default 'bozza',
  pubblicato_il timestamptz,
  creato_da uuid not null references public.profiles (id) on delete restrict,
  aggiornato_da uuid references public.profiles (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accessori_slug_unico unique (slug),
  constraint accessori_slug_forma
    check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(slug) between 3 and 80),
  -- `/accessori/categoria/...` e il percorso delle categorie.
  constraint accessori_slug_non_riservato check (slug <> 'categoria'),
  constraint accessori_nome_forma check (length(btrim(nome)) between 2 and 120),
  constraint accessori_descrizione_forma check (length(descrizione) <= 2000),
  constraint accessori_marchio_forma
    check (marchio is null or length(btrim(marchio)) between 1 and 80),
  constraint accessori_condizione_ammessa
    check (condizione in ('nuovo', 'come_nuovo', 'usato', 'da_collezione')),
  constraint accessori_quantita_forma
    check (quantita is null or quantita between 0 and 100000),
  constraint accessori_attributi_oggetto check (jsonb_typeof(attributi) = 'object'),
  constraint accessori_immagini_massimo check (cardinality(immagini) <= 6),
  constraint accessori_stato_ammesso check (stato in ('bozza', 'pubblicato', 'archiviato')),
  constraint accessori_pubblicato_con_data check (stato <> 'pubblicato' or pubblicato_il is not null)
);

comment on table private.accessori is
  'VPM-015A: schede catalogo degli accessori. Entita DEDICATA: nessun legame con '
  'wines, bottle_units, listings, orders o payments. Senza prezzo, valuta, '
  'varianti, dimensioni, peso (differiti). Nessun grant client.';
comment on column private.accessori.quantita is
  'Informazione interna di catalogo, mai esposta dalle letture pubbliche: non e una disponibilita.';
comment on column private.accessori.immagini is
  'Percorsi `<accessorio_id>/<uuid>.webp` nel bucket accessori-media.';

create index accessori_categoria_idx on private.accessori (categoria_id);
create index accessori_stato_idx on private.accessori (stato, pubblicato_il desc);

alter table private.accessori enable row level security;
revoke all on table private.accessori from public, anon, authenticated;

create trigger accessori_set_updated_at
  before update on private.accessori
  for each row execute function extensions.moddatetime('updated_at');

-- Il vincolo vale per ogni scrittore, anche privilegiato: forma di attributi e
-- immagini, macchina a stati, completezza minima per la pubblicazione.
create function private.accessori_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_cat private.accessori_categorie%rowtype;
  v_par private.accessori_categorie%rowtype;
  v_chiave text;
  v_valore jsonb;
  v_n integer := 0;
  v_percorso text;
begin
  if tg_op = 'INSERT' then
    if new.stato <> 'bozza' then
      raise exception 'Una scheda nasce in bozza.' using errcode = '22023', hint = 'stato_iniziale';
    end if;
    new.pubblicato_il := null;
  else
    if new.id <> old.id or new.creato_da <> old.creato_da then
      raise exception 'Identificativo e creatore di una scheda non cambiano.' using errcode = '42501';
    end if;
    if old.pubblicato_il is not null and new.slug <> old.slug then
      raise exception 'L''indirizzo di una scheda gia pubblicata non cambia.'
        using errcode = '22023', hint = 'slug_bloccato';
    end if;
    if new.stato <> old.stato and not (
         (old.stato = 'bozza' and new.stato = 'pubblicato')
      or (old.stato = 'pubblicato' and new.stato in ('bozza', 'archiviato'))
      or (old.stato = 'archiviato' and new.stato = 'bozza')
    ) then
      raise exception 'Transizione di stato non ammessa.'
        using errcode = '22023', hint = 'transizione_non_ammessa';
    end if;
    new.pubblicato_il := old.pubblicato_il;
  end if;

  -- Attributi: al piu 12 coppie, chiave minuscola, valore testo 1..120.
  for v_chiave, v_valore in select key, value from jsonb_each(new.attributi) loop
    v_n := v_n + 1;
    if v_chiave !~ '^[a-z][a-z0-9_]{0,31}$'
       or jsonb_typeof(v_valore) <> 'string'
       or length(btrim(v_valore #>> '{}')) not between 1 and 120 then
      raise exception 'Attributo non valido.' using errcode = '22023', hint = 'attributi_non_validi';
    end if;
  end loop;
  if v_n > 12 then
    raise exception 'Troppi attributi (massimo 12).' using errcode = '22023', hint = 'attributi_non_validi';
  end if;

  -- Immagini: percorsi nella cartella della scheda, senza duplicati.
  if (select count(distinct x) from unnest(new.immagini) x) <> cardinality(new.immagini) then
    raise exception 'Immagini duplicate.' using errcode = '22023', hint = 'immagini_non_valide';
  end if;
  foreach v_percorso in array new.immagini loop
    if v_percorso is null or v_percorso !~ (
      '^' || new.id::text
      || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.webp$'
    ) then
      raise exception 'Percorso immagine non valido.' using errcode = '22023', hint = 'immagini_non_valide';
    end if;
  end loop;

  select * into v_cat from private.accessori_categorie where id = new.categoria_id;
  if v_cat.parent_id is not null then
    select * into v_par from private.accessori_categorie where id = v_cat.parent_id;
  end if;

  if new.stato = 'pubblicato' then
    if length(btrim(new.descrizione)) < 10
       or cardinality(new.immagini) < 1
       or not v_cat.attiva
       or (v_par.id is not null and not v_par.attiva) then
      raise exception 'La scheda non e completa per la pubblicazione.'
        using errcode = '22023', hint = 'pubblicazione_incompleta';
    end if;
    if tg_op = 'INSERT' or old.stato <> 'pubblicato' then
      new.pubblicato_il := now();
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function private.accessori_guard() from public, anon, authenticated;

create trigger accessori_guard
  before insert or update on private.accessori
  for each row execute function private.accessori_guard();

-- ---------------------------------------------------------------------------
-- [3] Interruttore di visibilita pubblica (database)
-- ---------------------------------------------------------------------------

create table private.accessori_impostazioni (
  singleton boolean primary key default true,
  visibilita_pubblica boolean not null default false,
  aggiornato_da uuid references public.profiles (id) on delete restrict,
  updated_at timestamptz not null default now(),
  constraint accessori_impostazioni_singola check (singleton)
);

comment on table private.accessori_impostazioni is
  'VPM-015A: una sola riga. visibilita_pubblica e spenta di default; con essa '
  'spenta le letture pubbliche non restituiscono nulla, qualunque sia la flag '
  'd''ambiente. L''accensione e una decisione del titolare.';

alter table private.accessori_impostazioni enable row level security;
revoke all on table private.accessori_impostazioni from public, anon, authenticated;

insert into private.accessori_impostazioni (singleton, visibilita_pubblica) values (true, false);

create trigger accessori_impostazioni_set_updated_at
  before update on private.accessori_impostazioni
  for each row execute function extensions.moddatetime('updated_at');

-- ---------------------------------------------------------------------------
-- [4] Registro e cancellazione
-- ---------------------------------------------------------------------------

create table private.accessori_registro (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles (id) on delete restrict,
  azione text not null,
  oggetto text not null,
  oggetto_id uuid,
  motivo text,
  created_at timestamptz not null default now(),
  constraint accessori_registro_azione_forma check (length(btrim(azione)) between 1 and 60),
  constraint accessori_registro_oggetto_ammesso
    check (oggetto in ('categoria', 'accessorio', 'visibilita')),
  constraint accessori_registro_motivo_forma
    check (motivo is null or length(btrim(motivo)) between 1 and 500)
);

comment on table private.accessori_registro is
  'VPM-015A: registro append-only delle azioni admin sul catalogo Accessori.';

alter table private.accessori_registro enable row level security;
revoke all on table private.accessori_registro from public, anon, authenticated;

create function private.accessori_registro_immutabile()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Il registro degli Accessori e append-only.' using errcode = '42501';
end;
$$;

revoke execute on function private.accessori_registro_immutabile() from public, anon, authenticated;

create trigger accessori_registro_immutabile
  before update or delete on private.accessori_registro
  for each row execute function private.accessori_registro_immutabile();

-- Nessuna cancellazione di catalogo in questo blocco: si archivia o si
-- disattiva. Vale anche per i privilegiati e per TRUNCATE.
create function private.accessori_non_si_cancella()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Il catalogo Accessori non si cancella: si archivia o si disattiva.'
    using errcode = '42501';
end;
$$;

revoke execute on function private.accessori_non_si_cancella() from public, anon, authenticated;

create trigger accessori_categorie_no_delete
  before delete on private.accessori_categorie
  for each row execute function private.accessori_non_si_cancella();
create trigger accessori_no_delete
  before delete on private.accessori
  for each row execute function private.accessori_non_si_cancella();
create trigger accessori_impostazioni_no_delete
  before delete on private.accessori_impostazioni
  for each row execute function private.accessori_non_si_cancella();

create trigger accessori_categorie_no_truncate
  before truncate on private.accessori_categorie
  for each statement execute function private.accessori_non_si_cancella();
create trigger accessori_no_truncate
  before truncate on private.accessori
  for each statement execute function private.accessori_non_si_cancella();
create trigger accessori_impostazioni_no_truncate
  before truncate on private.accessori_impostazioni
  for each statement execute function private.accessori_non_si_cancella();
create trigger accessori_registro_no_truncate
  before truncate on private.accessori_registro
  for each statement execute function private.accessori_registro_immutabile();

-- ---------------------------------------------------------------------------
-- Seed: SOLO la tassonomia. Nessun prodotto, marchio, prezzo o disponibilita.
-- ---------------------------------------------------------------------------

insert into private.accessori_categorie (slug, nome, descrizione, ordine) values
  ('apertura', 'Apertura', 'Cavatappi e strumenti per aprire e richiudere la bottiglia.', 10),
  ('calici', 'Calici', 'Calici per il vino rosso, bianco e per le bollicine.', 20),
  ('degustazione', 'Degustazione', 'Strumenti e accessori per assaggiare e confrontare i vini.', 30),
  ('decanter', 'Decanter', 'Decanter e aeratori per far respirare il vino.', 40),
  ('raffreddamento', 'Raffreddamento', 'Secchielli e accessori per servire il vino alla giusta temperatura.', 50),
  ('conservazione', 'Conservazione', 'Accessori per conservare le bottiglie, aperte e chiuse.', 60),
  ('espositori', 'Espositori', 'Supporti e portabottiglie per esporre e ordinare le bottiglie.', 70),
  ('pulizia', 'Pulizia', 'Prodotti e strumenti per la cura di calici e decanter.', 80),
  ('set-regalo', 'Set regalo', 'Composizioni di accessori pensate per essere regalate.', 90),
  ('altri-accessori', 'Altri accessori', 'Tutto il resto, in attesa di una categoria propria.', 100);

insert into private.accessori_categorie (parent_id, slug, nome, ordine)
select p.id, v.slug, v.nome, v.ordine
from (values
  ('apertura', 'cavatappi', 'Cavatappi', 10),
  ('apertura', 'tappi-e-chiusure', 'Tappi e chiusure', 20),
  ('calici', 'calici-da-rosso', 'Calici da rosso', 10),
  ('calici', 'calici-da-bianco', 'Calici da bianco', 20),
  ('calici', 'flute-e-bollicine', 'Flute e bollicine', 30),
  ('decanter', 'decanter-da-tavola', 'Decanter da tavola', 10),
  ('decanter', 'aeratori', 'Aeratori', 20),
  ('raffreddamento', 'secchielli', 'Secchielli', 10),
  ('conservazione', 'conservazione-vino-aperto', 'Vino aperto', 10),
  ('espositori', 'portabottiglie', 'Portabottiglie', 10)
) as v (genitore, slug, nome, ordine)
join private.accessori_categorie p on p.slug = v.genitore;

-- ---------------------------------------------------------------------------
-- Helper privati
-- ---------------------------------------------------------------------------

-- Il ruolo admin reale, letto da `public.user_roles` come ogni altra porta
-- admin. Non e un sistema di ruoli nuovo: delega alla porta esistente.
create function private.accessori_admin_richiesto()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select private.partner_admin_richiesto();
$$;

revoke execute on function private.accessori_admin_richiesto() from public, anon, authenticated;

-- Versione booleana, per le policy di Storage (che girano col chiamante).
-- Risponde soltanto sul chiamante: dice a ciascuno se e admin.
create function private.accessori_e_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.user_roles ur
    where ur.user_id = (select auth.uid()) and ur.role = 'admin'
  );
$$;

revoke all on function private.accessori_e_admin() from public, anon;
grant execute on function private.accessori_e_admin() to authenticated;

create function private.accessori_visibili_al_pubblico()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select i.visibilita_pubblica from private.accessori_impostazioni i), false);
$$;

revoke execute on function private.accessori_visibili_al_pubblico() from public, anon, authenticated;

-- L'unico posto che decide i campi di una scheda. La forma pubblica e un
-- ELENCO CHIUSO: un campo aggiunto alla tabella resta privato finche non lo si
-- cita qui. Quantita, stato, creatore e date interne non escono mai al pubblico.
create function private.accessorio_json(p_id uuid, p_admin boolean)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
      'slug', a.slug,
      'nome', a.nome,
      'descrizione', a.descrizione,
      'marchio', a.marchio,
      'condizione', a.condizione,
      'attributi', a.attributi,
      'immagini', to_jsonb(a.immagini),
      'categoria', jsonb_build_object(
        'slug', c.slug,
        'nome', c.nome,
        'genitore_slug', g.slug,
        'genitore_nome', g.nome
      )
    )
    || case when p_admin then jsonb_build_object(
      'id', a.id,
      'categoria_id', a.categoria_id,
      'stato', a.stato,
      'quantita', a.quantita,
      'pubblicato_il', a.pubblicato_il,
      'created_at', a.created_at,
      'updated_at', a.updated_at
    ) else '{}'::jsonb end
  from private.accessori a
  join private.accessori_categorie c on c.id = a.categoria_id
  left join private.accessori_categorie g on g.id = c.parent_id
  where a.id = p_id;
$$;

revoke execute on function private.accessorio_json(uuid, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [5] Storage: bucket `accessori-media`
-- ---------------------------------------------------------------------------
--
-- Pubblico in lettura per percorso, come `partner-vetrine`: il percorso
-- contiene due uuid e nessun ruolo client puo elencare il bucket (SELECT solo
-- all'admin). I percorsi delle bozze sono noti soltanto alle funzioni admin.
-- Solo `image/webp` fino a 2 MB. Nessuna policy di UPDATE: un oggetto non si
-- sovrascrive, si sostituisce con un nome nuovo.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('accessori-media', 'accessori-media', true, 2097152, array['image/webp'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create function private.accessorio_in_gestione(p_accessorio text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_accessorio is null
     or p_accessorio !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return false;
  end if;
  return private.accessori_e_admin()
    and exists (select 1 from private.accessori a where a.id = p_accessorio::uuid);
end;
$$;

revoke all on function private.accessorio_in_gestione(text) from public, anon;
grant execute on function private.accessorio_in_gestione(text) to authenticated;

create function private.accessorio_media_cancellabile(p_percorso text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_percorso is not null
    and private.accessori_e_admin()
    and not exists (select 1 from private.accessori a where p_percorso = any (a.immagini));
$$;

revoke all on function private.accessorio_media_cancellabile(text) from public, anon;
grant execute on function private.accessorio_media_cancellabile(text) to authenticated;

create policy "accessori_media_select_admin"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'accessori-media'
  and private.accessori_e_admin()
);

create policy "accessori_media_insert_admin"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'accessori-media'
  and name ~ (
    '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
    || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
    || '\.webp$'
  )
  and private.accessorio_in_gestione((storage.foldername(name))[1])
);

create policy "accessori_media_delete_admin_non_in_uso"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'accessori-media'
  and private.accessorio_media_cancellabile(name)
);

-- ---------------------------------------------------------------------------
-- [6] Letture pubbliche (e anteprima admin)
-- ---------------------------------------------------------------------------
--
-- `p_anteprima = true` e la sola via per vedere bozze e per ignorare
-- l'interruttore: richiede l'admin reale e altrimenti risponde 42501. Con
-- `false`, o assente, l'interruttore spento restituisce sempre vuoto.

create function public.accessori_categorie_elenca(p_anteprima boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if coalesce(p_anteprima, false) then
    perform private.accessori_admin_richiesto();
  elsif not private.accessori_visibili_al_pubblico() then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'slug', c.slug,
        'nome', c.nome,
        'descrizione', c.descrizione,
        'genitore_slug', g.slug,
        'conteggio', (
          select count(*)
          from private.accessori a
          where (a.categoria_id = c.id
                 or exists (select 1 from private.accessori_categorie k
                            where k.id = a.categoria_id and k.parent_id = c.id))
            and (a.stato = 'pubblicato' or (coalesce(p_anteprima, false) and a.stato = 'bozza'))
        )
      )
      order by coalesce(g.ordine, c.ordine), coalesce(g.slug, c.slug), (g.id is not null), c.ordine, c.nome
    )
    from private.accessori_categorie c
    left join private.accessori_categorie g on g.id = c.parent_id
    where c.attiva and (g.id is null or g.attiva)
  ), '[]'::jsonb);
end;
$$;

comment on function public.accessori_categorie_elenca(boolean) is
  'Categorie attive con il numero di schede visibili. Vuoto finche l''interruttore '
  'di visibilita e spento; p_anteprima solo per l''admin reale.';

create function public.accessori_elenca(
  p_categoria_slug text default null,
  p_anteprima boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if coalesce(p_anteprima, false) then
    perform private.accessori_admin_richiesto();
  elsif not private.accessori_visibili_al_pubblico() then
    return '[]'::jsonb;
  end if;

  if p_categoria_slug is not null and length(p_categoria_slug) > 60 then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(
      private.accessorio_json(s.id, false)
        || case when coalesce(p_anteprima, false)
                then jsonb_build_object('stato', s.stato) else '{}'::jsonb end
      order by s.pubblicato_il desc nulls last, s.nome)
    from (
      select a.id, a.pubblicato_il, a.nome, a.stato
      from private.accessori a
      join private.accessori_categorie c on c.id = a.categoria_id
      left join private.accessori_categorie g on g.id = c.parent_id
      where (a.stato = 'pubblicato' or (coalesce(p_anteprima, false) and a.stato = 'bozza'))
        and c.attiva and (g.id is null or g.attiva)
        and (p_categoria_slug is null or c.slug = p_categoria_slug or g.slug = p_categoria_slug)
      order by a.pubblicato_il desc nulls last, a.nome
      limit 60
    ) s
  ), '[]'::jsonb);
end;
$$;

comment on function public.accessori_elenca(text, boolean) is
  'Schede pubblicate (massimo 60), opzionalmente per categoria o sottocategoria. '
  'Colonne a elenco chiuso: nessuna quantita, nessun id; lo stato compare solo in anteprima admin. Vuoto con interruttore spento.';

create function public.accessori_dettaglio(p_slug text, p_anteprima boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_a private.accessori%rowtype;
begin
  if coalesce(p_anteprima, false) then
    perform private.accessori_admin_richiesto();
  elsif not private.accessori_visibili_al_pubblico() then
    return null;
  end if;

  if p_slug is null or length(p_slug) > 80 then
    return null;
  end if;

  select a.* into v_a
  from private.accessori a
  join private.accessori_categorie c on c.id = a.categoria_id
  left join private.accessori_categorie g on g.id = c.parent_id
  where a.slug = p_slug
    and (a.stato = 'pubblicato' or (coalesce(p_anteprima, false) and a.stato = 'bozza'))
    and c.attiva and (g.id is null or g.attiva);

  if v_a.id is null then
    return null;
  end if;
  return private.accessorio_json(v_a.id, false)
    || case when coalesce(p_anteprima, false)
            then jsonb_build_object('stato', v_a.stato) else '{}'::jsonb end;
end;
$$;

comment on function public.accessori_dettaglio(text, boolean) is
  'Una scheda pubblicata per slug, o null. Stesse regole di accessori_elenca.';

-- ---------------------------------------------------------------------------
-- [7] Porte admin
-- ---------------------------------------------------------------------------

create function public.accessori_admin_stato()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.accessori_admin_richiesto();
  return jsonb_build_object('visibilita_pubblica', private.accessori_visibili_al_pubblico());
end;
$$;

create function public.accessori_admin_categorie_elenca()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.accessori_admin_richiesto();
  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', c.id,
        'genitore_id', c.parent_id,
        'slug', c.slug,
        'nome', c.nome,
        'descrizione', c.descrizione,
        'ordine', c.ordine,
        'attiva', c.attiva,
        'accessori', (select count(*) from private.accessori a where a.categoria_id = c.id)
      )
      order by coalesce(g.ordine, c.ordine), coalesce(g.slug, c.slug), (g.id is not null), c.ordine, c.nome
    )
    from private.accessori_categorie c
    left join private.accessori_categorie g on g.id = c.parent_id
  ), '[]'::jsonb);
end;
$$;

create function public.accessori_admin_categoria_salva(p_id uuid, p_dati jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.accessori_admin_richiesto();
  v_old private.accessori_categorie%rowtype;
  v_chiave text;
  v_genitore uuid;
  v_slug text;
  v_nome text;
  v_desc text;
  v_ordine integer;
  v_attiva boolean;
  v_row private.accessori_categorie%rowtype;
begin
  if p_dati is null or jsonb_typeof(p_dati) <> 'object' then
    raise exception 'Dati non validi.' using errcode = '22023', hint = 'dati_non_validi';
  end if;
  for v_chiave in select jsonb_object_keys(p_dati) loop
    if v_chiave <> all (array['genitore_id', 'slug', 'nome', 'descrizione', 'ordine', 'attiva']) then
      raise exception 'Campo non ammesso.' using errcode = '22023', hint = 'campo_sconosciuto';
    end if;
  end loop;

  if p_id is not null then
    select * into v_old from private.accessori_categorie where id = p_id for update;
    if v_old.id is null then
      raise exception 'Categoria non trovata.' using errcode = 'P0001', hint = 'non_trovato';
    end if;
  end if;

  if p_dati ? 'genitore_id' then
    if jsonb_typeof(p_dati -> 'genitore_id') = 'null' then
      v_genitore := null;
    elsif jsonb_typeof(p_dati -> 'genitore_id') = 'string'
      and (p_dati ->> 'genitore_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      v_genitore := (p_dati ->> 'genitore_id')::uuid;
    else
      raise exception 'Genitore non valido.' using errcode = '22023', hint = 'genitore_non_valido';
    end if;
  else
    v_genitore := v_old.parent_id;
  end if;

  v_slug := case when p_dati ? 'slug' then p_dati ->> 'slug' else v_old.slug end;
  v_nome := case when p_dati ? 'nome' then btrim(p_dati ->> 'nome') else v_old.nome end;
  v_desc := case when p_dati ? 'descrizione' then btrim(coalesce(p_dati ->> 'descrizione', '')) else coalesce(v_old.descrizione, '') end;

  if p_dati ? 'ordine' then
    if jsonb_typeof(p_dati -> 'ordine') <> 'number' then
      raise exception 'Ordine non valido.' using errcode = '22023', hint = 'ordine_non_valido';
    end if;
    if (p_dati ->> 'ordine')::numeric <> trunc((p_dati ->> 'ordine')::numeric)
       or (p_dati ->> 'ordine')::numeric not between 0 and 10000 then
      raise exception 'Ordine non valido.' using errcode = '22023', hint = 'ordine_non_valido';
    end if;
    v_ordine := (p_dati ->> 'ordine')::integer;
  else
    v_ordine := coalesce(v_old.ordine, 100);
  end if;

  if p_dati ? 'attiva' then
    if jsonb_typeof(p_dati -> 'attiva') <> 'boolean' then
      raise exception 'Stato non valido.' using errcode = '22023', hint = 'dati_non_validi';
    end if;
    v_attiva := (p_dati ->> 'attiva')::boolean;
  else
    v_attiva := coalesce(v_old.attiva, true);
  end if;

  if v_slug is null or v_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or length(v_slug) not between 3 and 60 then
    raise exception 'Indirizzo non valido.' using errcode = '22023', hint = 'slug_non_valido';
  end if;
  if v_nome is null or length(v_nome) not between 2 and 80 then
    raise exception 'Nome non valido.' using errcode = '22023', hint = 'nome_non_valido';
  end if;
  if length(v_desc) > 500 then
    raise exception 'Descrizione troppo lunga.' using errcode = '22023', hint = 'descrizione_non_valida';
  end if;

  begin
    if p_id is null then
      insert into private.accessori_categorie (parent_id, slug, nome, descrizione, ordine, attiva)
      values (v_genitore, v_slug, v_nome, v_desc, v_ordine, v_attiva)
      returning * into v_row;
    else
      update private.accessori_categorie
      set parent_id = v_genitore, slug = v_slug, nome = v_nome, descrizione = v_desc,
          ordine = v_ordine, attiva = v_attiva
      where id = p_id
      returning * into v_row;
    end if;
  exception when unique_violation then
    raise exception 'Indirizzo gia in uso.' using errcode = '23505', hint = 'slug_in_uso';
  end;

  insert into private.accessori_registro (admin_id, azione, oggetto, oggetto_id)
  values (v_admin, case when p_id is null then 'categoria_crea' else 'categoria_modifica' end,
          'categoria', v_row.id);

  return jsonb_build_object(
    'id', v_row.id, 'genitore_id', v_row.parent_id, 'slug', v_row.slug, 'nome', v_row.nome,
    'descrizione', v_row.descrizione, 'ordine', v_row.ordine, 'attiva', v_row.attiva);
end;
$$;

create function public.accessori_admin_elenca(p_stato text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.accessori_admin_richiesto();
  if p_stato is not null and p_stato not in ('bozza', 'pubblicato', 'archiviato') then
    raise exception 'Stato non valido.' using errcode = '22023', hint = 'stato_non_valido';
  end if;
  return coalesce((
    select jsonb_agg(private.accessorio_json(s.id, true) order by s.updated_at desc)
    from (
      select a.id, a.updated_at
      from private.accessori a
      where p_stato is null or a.stato = p_stato
      order by a.updated_at desc
      limit 200
    ) s
  ), '[]'::jsonb);
end;
$$;

create function public.accessori_admin_dettaglio(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_a private.accessori%rowtype;
begin
  perform private.accessori_admin_richiesto();
  select * into v_a from private.accessori where id = p_id;
  if v_a.id is null then
    return null;
  end if;
  return private.accessorio_json(v_a.id, true);
end;
$$;

create function public.accessori_admin_salva(p_id uuid, p_dati jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.accessori_admin_richiesto();
  v_old private.accessori%rowtype;
  v_chiave text;
  v_categoria uuid;
  v_slug text;
  v_nome text;
  v_desc text;
  v_marchio text;
  v_condizione text;
  v_quantita integer;
  v_attributi jsonb;
  v_row private.accessori%rowtype;
begin
  if p_dati is null or jsonb_typeof(p_dati) <> 'object' then
    raise exception 'Dati non validi.' using errcode = '22023', hint = 'dati_non_validi';
  end if;
  for v_chiave in select jsonb_object_keys(p_dati) loop
    if v_chiave <> all (array['categoria_id', 'slug', 'nome', 'descrizione', 'marchio',
                              'condizione', 'quantita', 'attributi']) then
      raise exception 'Campo non ammesso.' using errcode = '22023', hint = 'campo_sconosciuto';
    end if;
  end loop;

  if p_id is not null then
    select * into v_old from private.accessori where id = p_id for update;
    if v_old.id is null then
      raise exception 'Scheda non trovata.' using errcode = 'P0001', hint = 'non_trovato';
    end if;
  end if;

  if p_dati ? 'categoria_id' then
    if jsonb_typeof(p_dati -> 'categoria_id') = 'string'
       and (p_dati ->> 'categoria_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      v_categoria := (p_dati ->> 'categoria_id')::uuid;
    else
      raise exception 'Categoria non valida.' using errcode = '22023', hint = 'categoria_obbligatoria';
    end if;
  else
    v_categoria := v_old.categoria_id;
  end if;
  if v_categoria is null or not exists (select 1 from private.accessori_categorie where id = v_categoria) then
    raise exception 'Categoria non valida.' using errcode = '22023', hint = 'categoria_obbligatoria';
  end if;

  v_slug := case when p_dati ? 'slug' then p_dati ->> 'slug' else v_old.slug end;
  v_nome := case when p_dati ? 'nome' then btrim(p_dati ->> 'nome') else v_old.nome end;
  v_desc := case when p_dati ? 'descrizione' then btrim(coalesce(p_dati ->> 'descrizione', '')) else coalesce(v_old.descrizione, '') end;
  v_marchio := case when p_dati ? 'marchio' then nullif(btrim(coalesce(p_dati ->> 'marchio', '')), '') else v_old.marchio end;
  v_condizione := case when p_dati ? 'condizione' then p_dati ->> 'condizione' else coalesce(v_old.condizione, 'nuovo') end;
  v_attributi := case when p_dati ? 'attributi' then p_dati -> 'attributi' else coalesce(v_old.attributi, '{}'::jsonb) end;

  if p_dati ? 'quantita' then
    if jsonb_typeof(p_dati -> 'quantita') = 'null' then
      v_quantita := null;
    else
      if jsonb_typeof(p_dati -> 'quantita') <> 'number' then
        raise exception 'Quantita non valida.' using errcode = '22023', hint = 'quantita_non_valida';
      end if;
      if (p_dati ->> 'quantita')::numeric <> trunc((p_dati ->> 'quantita')::numeric)
         or (p_dati ->> 'quantita')::numeric not between 0 and 100000 then
        raise exception 'Quantita non valida.' using errcode = '22023', hint = 'quantita_non_valida';
      end if;
      v_quantita := (p_dati ->> 'quantita')::integer;
    end if;
  else
    v_quantita := v_old.quantita;
  end if;

  if v_slug is null or v_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
     or length(v_slug) not between 3 and 80 or v_slug = 'categoria' then
    raise exception 'Indirizzo non valido.' using errcode = '22023', hint = 'slug_non_valido';
  end if;
  if v_nome is null or length(v_nome) not between 2 and 120 then
    raise exception 'Nome non valido.' using errcode = '22023', hint = 'nome_non_valido';
  end if;
  if length(v_desc) > 2000 then
    raise exception 'Descrizione troppo lunga.' using errcode = '22023', hint = 'descrizione_non_valida';
  end if;
  if v_marchio is not null and length(v_marchio) > 80 then
    raise exception 'Marchio troppo lungo.' using errcode = '22023', hint = 'marchio_non_valido';
  end if;
  if v_condizione is null or v_condizione not in ('nuovo', 'come_nuovo', 'usato', 'da_collezione') then
    raise exception 'Condizione non valida.' using errcode = '22023', hint = 'condizione_non_valida';
  end if;
  if v_attributi is null or jsonb_typeof(v_attributi) <> 'object' then
    raise exception 'Attributi non validi.' using errcode = '22023', hint = 'attributi_non_validi';
  end if;

  begin
    if p_id is null then
      insert into private.accessori
        (categoria_id, slug, nome, descrizione, marchio, condizione, quantita, attributi, creato_da, aggiornato_da)
      values
        (v_categoria, v_slug, v_nome, v_desc, v_marchio, v_condizione, v_quantita, v_attributi, v_admin, v_admin)
      returning * into v_row;
    else
      update private.accessori
      set categoria_id = v_categoria, slug = v_slug, nome = v_nome, descrizione = v_desc,
          marchio = v_marchio, condizione = v_condizione, quantita = v_quantita,
          attributi = v_attributi, aggiornato_da = v_admin
      where id = p_id
      returning * into v_row;
    end if;
  exception when unique_violation then
    raise exception 'Indirizzo gia in uso.' using errcode = '23505', hint = 'slug_in_uso';
  end;

  insert into private.accessori_registro (admin_id, azione, oggetto, oggetto_id)
  values (v_admin, case when p_id is null then 'accessorio_crea' else 'accessorio_modifica' end,
          'accessorio', v_row.id);

  return private.accessorio_json(v_row.id, true);
end;
$$;

create function public.accessori_admin_immagini_imposta(p_id uuid, p_percorsi text[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.accessori_admin_richiesto();
  v_a private.accessori%rowtype;
  v_percorsi text[] := coalesce(p_percorsi, '{}'::text[]);
  v_percorso text;
  v_row private.accessori%rowtype;
begin
  select * into v_a from private.accessori where id = p_id for update;
  if v_a.id is null then
    raise exception 'Scheda non trovata.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  if cardinality(v_percorsi) > 6 then
    raise exception 'Troppe immagini (massimo 6).' using errcode = '22023', hint = 'immagini_non_valide';
  end if;

  foreach v_percorso in array v_percorsi loop
    -- La forma esatta e il legame con la scheda sono nel trigger; qui si
    -- verifica che l'oggetto esista davvero nel bucket.
    if v_percorso is null or not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'accessori-media' and o.name = v_percorso
    ) then
      raise exception 'Immagine non trovata nel bucket.' using errcode = '22023', hint = 'immagine_assente';
    end if;
  end loop;

  update private.accessori
  set immagini = v_percorsi, aggiornato_da = v_admin
  where id = p_id
  returning * into v_row;

  insert into private.accessori_registro (admin_id, azione, oggetto, oggetto_id)
  values (v_admin, 'accessorio_immagini', 'accessorio', v_row.id);

  return private.accessorio_json(v_row.id, true);
end;
$$;

create function public.accessori_admin_stato_imposta(p_id uuid, p_stato text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.accessori_admin_richiesto();
  v_a private.accessori%rowtype;
  v_row private.accessori%rowtype;
begin
  if p_stato is null or p_stato not in ('bozza', 'pubblicato', 'archiviato') then
    raise exception 'Stato non valido.' using errcode = '22023', hint = 'stato_non_valido';
  end if;
  select * into v_a from private.accessori where id = p_id for update;
  if v_a.id is null then
    raise exception 'Scheda non trovata.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  if v_a.stato = p_stato then
    return private.accessorio_json(v_a.id, true);
  end if;

  update private.accessori set stato = p_stato, aggiornato_da = v_admin
  where id = p_id returning * into v_row;

  insert into private.accessori_registro (admin_id, azione, oggetto, oggetto_id)
  values (v_admin, 'accessorio_stato_' || p_stato, 'accessorio', v_row.id);

  return private.accessorio_json(v_row.id, true);
end;
$$;

create function public.accessori_admin_visibilita_imposta(p_attiva boolean, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.accessori_admin_richiesto();
  v_motivo text := private.partner_motivo_pulito(p_motivo);
begin
  if p_attiva is null then
    raise exception 'Valore non valido.' using errcode = '22023', hint = 'dati_non_validi';
  end if;
  if v_motivo is null then
    raise exception 'Il cambio di visibilita richiede un motivo.' using errcode = '22023', hint = 'motivo_obbligatorio';
  end if;

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
  'Admin: accende o spegne la visibilita PUBBLICA del catalogo nel database. '
  'Motivo obbligatorio, registrato. Non sostituisce ne e sostituita dalla flag d''ambiente.';

-- ---------------------------------------------------------------------------
-- Privilegi di esecuzione
-- ---------------------------------------------------------------------------
--
-- Letture pubbliche: anon e authenticated, con elenco chiuso e interruttore.
-- Porte admin: solo authenticated, e ciascuna ricontrolla il ruolo da se.

revoke all on function public.accessori_categorie_elenca(boolean) from public, anon, authenticated, service_role;
revoke all on function public.accessori_elenca(text, boolean) from public, anon, authenticated, service_role;
revoke all on function public.accessori_dettaglio(text, boolean) from public, anon, authenticated, service_role;
grant execute on function public.accessori_categorie_elenca(boolean) to anon, authenticated;
grant execute on function public.accessori_elenca(text, boolean) to anon, authenticated;
grant execute on function public.accessori_dettaglio(text, boolean) to anon, authenticated;

revoke all on function public.accessori_admin_stato() from public, anon, authenticated, service_role;
revoke all on function public.accessori_admin_categorie_elenca() from public, anon, authenticated, service_role;
revoke all on function public.accessori_admin_categoria_salva(uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.accessori_admin_elenca(text) from public, anon, authenticated, service_role;
revoke all on function public.accessori_admin_dettaglio(uuid) from public, anon, authenticated, service_role;
revoke all on function public.accessori_admin_salva(uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.accessori_admin_immagini_imposta(uuid, text[]) from public, anon, authenticated, service_role;
revoke all on function public.accessori_admin_stato_imposta(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.accessori_admin_visibilita_imposta(boolean, text) from public, anon, authenticated, service_role;
grant execute on function public.accessori_admin_stato() to authenticated;
grant execute on function public.accessori_admin_categorie_elenca() to authenticated;
grant execute on function public.accessori_admin_categoria_salva(uuid, jsonb) to authenticated;
grant execute on function public.accessori_admin_elenca(text) to authenticated;
grant execute on function public.accessori_admin_dettaglio(uuid) to authenticated;
grant execute on function public.accessori_admin_salva(uuid, jsonb) to authenticated;
grant execute on function public.accessori_admin_immagini_imposta(uuid, text[]) to authenticated;
grant execute on function public.accessori_admin_stato_imposta(uuid, text) to authenticated;
grant execute on function public.accessori_admin_visibilita_imposta(boolean, text) to authenticated;
