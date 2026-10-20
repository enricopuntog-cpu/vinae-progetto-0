-- VPM-015B1 — Cantina Accessori: gli accessori posseduti dai singoli utenti.
--
-- Decisione del titolare: ogni utente puo tenere nella propria Cantina anche gli
-- accessori che possiede (cavatappi, calici, decanter...), sul modello della
-- Cantina delle bottiglie. NON si attiva alcuna vendita, alcun checkout, alcun
-- pagamento: "esposto" non significa "in vendita".
--
-- Che cosa fa questa migrazione:
--   [1] `private.cantina_accessori`: inventario PERSONALE, una riga per tipo di
--       accessorio con una quantita (gli accessori non hanno uno stato per
--       singolo pezzo come le bottiglie). Proprietario dal contesto
--       autenticato, categoria come FK sulla tassonomia `accessori_categorie`
--       (rinominare una categoria non rompe i legami), condizione, foto,
--       visibilita `privata` | `cantina_pubblica` (stesso lessico delle
--       bottiglie), archiviazione. Nasce SEMPRE privata;
--   [2] `private.cantina_accessori_impostazioni`: due interruttori nel
--       database, entrambi spenti di default e vincolati al ruolo di rilascio
--       `accessori_release` per l'accensione: la FUNZIONE personale e la
--       VISIBILITA' degli accessori esposti. Sono distinti dall'interruttore
--       del catalogo centrale (`accessori_impostazioni`), che non si tocca;
--   [3] bucket Storage PRIVATO `cantina-accessori-foto`: il proprietario legge
--       e scrive solo la propria cartella; chiunque puo firmare solo le foto di
--       accessori ESPOSTI mentre funzione e visibilita sono accese;
--   [4] proiezione pubblicabile `private.cantina_accessori_pubblica` (vista
--       chiusa) e porta `public.cantina_accessori_pubblica_profilo(uuid, ...)`:
--       un profilo per volta, elenco chiuso di campi, mai note private;
--   [5] porte del proprietario `cantina_accessori_*` e porte admin per gli
--       interruttori; la tassonomia e leggibile per l'inserimento anche con il
--       catalogo commerciale spento, senza aprirne bozze o visibilita.
--
-- Che cosa NON fa: nessun accessorio in `wines`, `bottle_units`,
-- `cellar_slots`; nessun prezzo, valuta, annuncio, ordine, pagamento,
-- commissione; nessuna scrittura sul catalogo `private.accessori` (il legame
-- facoltativo e una sola FK in lettura); nessuna modifica a migrazioni
-- precedenti. Il solo ritocco a un oggetto esistente e il vincolo
-- `accessori_registro_oggetto_ammesso`, esteso per registrare gli interruttori.
--
-- Nessuna tabella e nessuna vista e esposta: tutto vive in `private`. Le sole
-- porte sono le funzioni `public.cantina_accessori_*`.

-- ---------------------------------------------------------------------------
-- [1] Inventario personale
-- ---------------------------------------------------------------------------

create table private.cantina_accessori (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  categoria_id uuid not null references private.accessori_categorie (id) on delete restrict,
  -- Legame facoltativo con una scheda del catalogo Vinea: solo un riferimento,
  -- non crea ne modifica prodotti. Se la scheda sparisce il legame cade.
  catalogo_id uuid references private.accessori (id) on delete set null,
  nome text not null,
  descrizione text not null default '',
  marchio text,
  condizione text not null default 'nuovo',
  quantita integer not null default 1,
  -- Mai pubbliche: non compaiono in alcuna proiezione.
  note_private text not null default '',
  immagini text[] not null default '{}'::text[],
  visibilita text not null default 'privata',
  archiviato_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cantina_accessori_nome_forma check (length(btrim(nome)) between 2 and 120),
  constraint cantina_accessori_descrizione_forma check (length(descrizione) <= 1000),
  constraint cantina_accessori_note_forma check (length(note_private) <= 1000),
  constraint cantina_accessori_marchio_forma
    check (marchio is null or length(btrim(marchio)) between 1 and 80),
  constraint cantina_accessori_condizione_ammessa
    check (condizione in ('nuovo', 'come_nuovo', 'usato', 'da_collezione')),
  constraint cantina_accessori_quantita_forma check (quantita between 1 and 999),
  constraint cantina_accessori_immagini_massimo check (cardinality(immagini) <= 4),
  constraint cantina_accessori_visibilita_ammessa
    check (visibilita in ('privata', 'cantina_pubblica')),
  constraint cantina_accessori_archiviato_privato
    check (archiviato_at is null or visibilita = 'privata')
);

comment on table private.cantina_accessori is
  'VPM-015B1: accessori posseduti dai singoli utenti (Cantina Accessori). Entita '
  'DEDICATA: nessun legame con wines, bottle_units, cellar_slots, listings, orders '
  'o payments. Nessun grant client: si legge e si scrive solo con le porte '
  'public.cantina_accessori_*, che ricavano il proprietario da auth.uid().';
comment on column private.cantina_accessori.note_private is
  'Note del proprietario. Mai esposte, nemmeno per un accessorio esposto.';
comment on column private.cantina_accessori.immagini is
  'Percorsi `<owner_id>/<accessorio_id>/<uuid>.webp` nel bucket privato cantina-accessori-foto.';

create index cantina_accessori_owner_idx
  on private.cantina_accessori (owner_id, archiviato_at, created_at desc);
create index cantina_accessori_categoria_idx on private.cantina_accessori (categoria_id);
create index cantina_accessori_catalogo_idx
  on private.cantina_accessori (catalogo_id) where catalogo_id is not null;
create index cantina_accessori_esposti_idx
  on private.cantina_accessori (owner_id) where visibilita = 'cantina_pubblica';

alter table private.cantina_accessori enable row level security;
revoke all on table private.cantina_accessori from public, anon, authenticated;

create trigger cantina_accessori_set_updated_at
  before update on private.cantina_accessori
  for each row execute function extensions.moddatetime('updated_at');

-- Le regole che valgono anche per i writer privilegiati.
create function private.cantina_accessori_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_cat record;
  v_percorso text;
  v_forma text;
begin
  if tg_op = 'UPDATE' and (new.id <> old.id or new.owner_id <> old.owner_id) then
    raise exception 'Identificativo e proprietario non cambiano.' using errcode = '42501';
  end if;

  -- Categoria: della tassonomia Vinea, attiva, e foglia (la sottocategoria e
  -- obbligatoria dove esiste). Si controlla alla creazione e al cambio: un
  -- accessorio gia presente non diventa non modificabile se l'admin disattiva
  -- poi la sua categoria.
  if tg_op = 'INSERT' or new.categoria_id is distinct from old.categoria_id then
    select c.id, c.attiva, c.parent_id, g.attiva as genitore_attivo
      into v_cat
    from private.accessori_categorie c
    left join private.accessori_categorie g on g.id = c.parent_id
    where c.id = new.categoria_id;

    if v_cat.id is null or not v_cat.attiva
       or (v_cat.parent_id is not null and not coalesce(v_cat.genitore_attivo, false)) then
      raise exception 'Categoria non valida.' using errcode = '22023', hint = 'categoria_non_valida';
    end if;
    if v_cat.parent_id is null and exists (
      select 1 from private.accessori_categorie k
      where k.parent_id = new.categoria_id and k.attiva
    ) then
      raise exception 'Scegli anche la sottocategoria.' using errcode = '22023', hint = 'sottocategoria_obbligatoria';
    end if;
  end if;

  -- Legame col catalogo: solo una scheda pubblicata; mai creata da qui.
  if new.catalogo_id is not null
     and (tg_op = 'INSERT' or new.catalogo_id is distinct from old.catalogo_id) then
    if not exists (
      select 1 from private.accessori a where a.id = new.catalogo_id and a.stato = 'pubblicato'
    ) then
      raise exception 'Scheda del catalogo non valida.' using errcode = '22023', hint = 'catalogo_non_valido';
    end if;
  end if;

  -- Foto: solo nella cartella `<proprietario>/<accessorio>/` e di forma esatta.
  if tg_op = 'INSERT' or new.immagini is distinct from old.immagini then
    v_forma := '^' || new.owner_id::text || '/' || new.id::text
      || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.webp$';
    foreach v_percorso in array new.immagini loop
      if v_percorso is null or v_percorso !~ v_forma then
        raise exception 'Percorso immagine non valido.' using errcode = '22023', hint = 'immagini_non_valide';
      end if;
    end loop;
    if cardinality(new.immagini) <> (select count(distinct x) from unnest(new.immagini) as x) then
      raise exception 'Immagini duplicate.' using errcode = '22023', hint = 'immagini_non_valide';
    end if;
  end if;

  -- Nasce privata, e si espone solo con una scelta esplicita del proprietario:
  -- la porta dichiara la scelta nella stessa transazione, un UPDATE diretto no.
  if tg_op = 'INSERT' then
    if new.visibilita <> 'privata' then
      raise exception 'Un accessorio nasce privato.' using errcode = '42501', hint = 'esposizione_non_autorizzata';
    end if;
  else
    if new.archiviato_at is not null then
      new.visibilita := 'privata';
    end if;
    if new.visibilita = 'cantina_pubblica' and old.visibilita <> 'cantina_pubblica' then
      if coalesce(current_setting('vinae.cantina_accessori_espone', true), '')
         <> 'espone:' || new.owner_id::text || ':' || new.id::text then
        raise exception 'L''esposizione richiede la scelta esplicita del proprietario.'
          using errcode = '42501', hint = 'esposizione_non_autorizzata';
      end if;
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function private.cantina_accessori_guard() from public, anon, authenticated;

create trigger cantina_accessori_guard
  before insert or update on private.cantina_accessori
  for each row execute function private.cantina_accessori_guard();

-- ---------------------------------------------------------------------------
-- [2] Interruttori nel database (fail-closed)
-- ---------------------------------------------------------------------------
--
-- Tre cose restano separate:
--   * visibilita pubblica del CATALOGO centrale -> private.accessori_impostazioni
--   * FUNZIONE personale Cantina Accessori      -> funzione_attiva
--   * VISIBILITA' degli accessori esposti       -> visibilita_pubblica
-- Spenti di default. Accendere richiede il ruolo di rilascio; spegnere e
-- consentito a ogni admin (il verso sicuro non richiede approvazione).

create table private.cantina_accessori_impostazioni (
  singleton boolean primary key default true,
  funzione_attiva boolean not null default false,
  visibilita_pubblica boolean not null default false,
  aggiornato_da uuid references public.profiles (id) on delete restrict,
  updated_at timestamptz not null default now(),
  constraint cantina_accessori_impostazioni_singola check (singleton)
);

comment on table private.cantina_accessori_impostazioni is
  'VPM-015B1: una sola riga. funzione_attiva accende la Cantina Accessori personale; '
  'visibilita_pubblica consente la lettura pubblica degli accessori esposti. Entrambe '
  'spente di default; l''accensione e una decisione del titolare (ruolo accessori_release).';

alter table private.cantina_accessori_impostazioni enable row level security;
revoke all on table private.cantina_accessori_impostazioni from public, anon, authenticated;

insert into private.cantina_accessori_impostazioni (singleton) values (true);

create trigger cantina_accessori_impostazioni_set_updated_at
  before update on private.cantina_accessori_impostazioni
  for each row execute function extensions.moddatetime('updated_at');

create function private.cantina_accessori_impostazioni_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (new.funzione_attiva and not old.funzione_attiva)
     or (new.visibilita_pubblica and not old.visibilita_pubblica) then
    if new.aggiornato_da is null
       or coalesce(current_setting('vinae.accessori_rilascio', true), '')
          <> 'rilascio:' || new.aggiornato_da::text then
      raise exception 'L''accensione si fa solo dalla porta di rilascio.'
        using errcode = '42501', hint = 'rilascio_non_autorizzato';
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function private.cantina_accessori_impostazioni_guard() from public, anon, authenticated;

create trigger cantina_accessori_impostazioni_guard
  before update on private.cantina_accessori_impostazioni
  for each row execute function private.cantina_accessori_impostazioni_guard();

create trigger cantina_accessori_impostazioni_no_delete
  before delete on private.cantina_accessori_impostazioni
  for each row execute function private.accessori_non_si_cancella();
create trigger cantina_accessori_impostazioni_no_truncate
  before truncate on private.cantina_accessori_impostazioni
  for each statement execute function private.accessori_non_si_cancella();

-- Il registro delle azioni admin accoglie anche gli interruttori della Cantina.
alter table private.accessori_registro drop constraint accessori_registro_oggetto_ammesso;
alter table private.accessori_registro
  add constraint accessori_registro_oggetto_ammesso
  check (oggetto in ('categoria', 'accessorio', 'visibilita', 'cantina_accessori'));

-- ---------------------------------------------------------------------------
-- Helper privati
-- ---------------------------------------------------------------------------

-- Il proprietario e SEMPRE l'utente autenticato: nessuna porta riceve un id
-- proprietario dal browser.
create function private.cantina_accessori_utente()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'Accesso richiesto.' using errcode = '42501', hint = 'non_autenticato';
  end if;
  return v_uid;
end;
$$;

revoke execute on function private.cantina_accessori_utente() from public, anon, authenticated;

create function private.cantina_accessori_funzione_attiva()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select i.funzione_attiva from private.cantina_accessori_impostazioni i), false);
$$;

revoke execute on function private.cantina_accessori_funzione_attiva() from public, anon, authenticated;

-- Funzione usabile dal chiamante: accesa per tutti, oppure un admin reale (che
-- puo cosi verificarla in produzione prima dell'accensione). Per gli altri, spenta.
create function private.cantina_accessori_consentita()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.cantina_accessori_funzione_attiva() or private.accessori_e_admin();
$$;

revoke execute on function private.cantina_accessori_consentita() from public, anon, authenticated;

-- Il catalogo e collegabile dal chiamante solo se e visibile al pubblico (o se
-- e un admin reale in collaudo). Helper a parte: la porta dell'utente comune
-- non deve citare i controlli admin, che identificano le porte riservate.
create function private.cantina_accessori_catalogo_collegabile()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.accessori_visibili_al_pubblico() or private.accessori_e_admin();
$$;

revoke execute on function private.cantina_accessori_catalogo_collegabile() from public, anon, authenticated;

-- Lettura pubblica degli esposti: funzione E visibilita accese.
create function private.cantina_accessori_esposti_visibili()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select i.funzione_attiva and i.visibilita_pubblica
    from private.cantina_accessori_impostazioni i
  ), false);
$$;

revoke execute on function private.cantina_accessori_esposti_visibili() from public, anon, authenticated;

create function private.cantina_accessori_testo(p_valore jsonb, p_min integer, p_max integer, p_hint text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_testo text;
begin
  if p_valore is null or jsonb_typeof(p_valore) = 'null' then
    v_testo := '';
  elsif jsonb_typeof(p_valore) <> 'string' then
    raise exception 'Testo non valido.' using errcode = '22023', hint = p_hint;
  else
    v_testo := btrim(p_valore #>> '{}');
  end if;
  -- Niente caratteri di controllo (tranne a capo e tabulazione nei testi lunghi).
  if v_testo ~ '[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]' then
    raise exception 'Testo non valido.' using errcode = '22023', hint = p_hint;
  end if;
  if length(v_testo) < p_min or length(v_testo) > p_max then
    raise exception 'Testo non valido.' using errcode = '22023', hint = p_hint;
  end if;
  return v_testo;
end;
$$;

revoke execute on function private.cantina_accessori_testo(jsonb, integer, integer, text) from public, anon, authenticated;

-- Forma del proprietario: l'unico posto che decide i campi che lui rivede.
create function private.cantina_accessorio_json(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', a.id,
    'nome', a.nome,
    'descrizione', a.descrizione,
    'marchio', a.marchio,
    'condizione', a.condizione,
    'quantita', a.quantita,
    'note', a.note_private,
    'immagini', to_jsonb(a.immagini),
    'visibilita', a.visibilita,
    'archiviato', a.archiviato_at is not null,
    'catalogo_slug', k.slug,
    'categoria', jsonb_build_object(
      'id', c.id,
      'slug', c.slug,
      'nome', c.nome,
      'genitore_id', g.id,
      'genitore_slug', g.slug,
      'genitore_nome', g.nome
    ),
    'created_at', a.created_at,
    'updated_at', a.updated_at
  )
  from private.cantina_accessori a
  join private.accessori_categorie c on c.id = a.categoria_id
  left join private.accessori_categorie g on g.id = c.parent_id
  left join private.accessori k on k.id = a.catalogo_id and k.stato = 'pubblicato'
  where a.id = p_id;
$$;

revoke execute on function private.cantina_accessorio_json(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [4] Proiezione pubblicabile
-- ---------------------------------------------------------------------------
--
-- L'ALLOWLIST E QUESTA LISTA DI COLONNE. Restano fuori: `note_private`,
-- `catalogo_id`, `archiviato_at`, `visibilita`, le date di aggiornamento e
-- ogni colonna aggiunta domani. Il join con `private.profili_pubblici` porta
-- la regola a due direzioni del profilo (un profilo rimosso non espone nulla).
-- Solo accessori ESPOSTI e NON archiviati.

create view private.cantina_accessori_pubblica
with (security_invoker = off, security_barrier = true)
as
select
  a.id          as accessorio_id,
  a.owner_id    as user_id,
  a.nome,
  a.descrizione,
  a.marchio,
  a.condizione,
  a.quantita,
  a.immagini,
  a.created_at  as aggiunto_at,
  c.slug        as categoria_slug,
  c.nome        as categoria_nome,
  g.nome        as genitore_nome
from private.cantina_accessori a
  join private.accessori_categorie c on c.id = a.categoria_id
  left join private.accessori_categorie g on g.id = c.parent_id
  join private.profili_pubblici pp on pp.user_id = a.owner_id
where a.visibilita = 'cantina_pubblica'
  and a.archiviato_at is null;

comment on view private.cantina_accessori_pubblica is
  'Proiezione pubblicabile degli accessori esposti di un profilo visibile. Nessun '
  'privilegio per anon/authenticated: la sola porta e '
  'public.cantina_accessori_pubblica_profilo(uuid, int, int, boolean).';

revoke all on private.cantina_accessori_pubblica from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [3] Storage: bucket PRIVATO `cantina-accessori-foto`
-- ---------------------------------------------------------------------------
--
-- `public = false`: nessun percorso, nemmeno noto, si serve senza firma. La
-- firma la concede la policy di SELECT: al proprietario per la propria
-- cartella; a chiunque per le sole foto di accessori ESPOSTI e non archiviati
-- mentre funzione e visibilita sono accese. Il limite di tempo delle URL gia
-- firmate (900 s) resta: spegnere la visibilita ferma le NUOVE letture.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('cantina-accessori-foto', 'cantina-accessori-foto', false, 2097152, array['image/webp'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- L'accessorio nella cartella esiste ed e del chiamante, e la funzione e usabile.
create function private.cantina_accessorio_proprio(p_accessorio text)
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
  return (select auth.uid()) is not null
    and private.cantina_accessori_consentita()
    and exists (
      select 1 from private.cantina_accessori a
      where a.id = p_accessorio::uuid and a.owner_id = (select auth.uid())
    );
end;
$$;

revoke all on function private.cantina_accessorio_proprio(text) from public, anon;
grant execute on function private.cantina_accessorio_proprio(text) to authenticated;

create function private.cantina_accessorio_media_cancellabile(p_percorso text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_percorso is not null
    and not exists (select 1 from private.cantina_accessori a where p_percorso = any (a.immagini));
$$;

revoke all on function private.cantina_accessorio_media_cancellabile(text) from public, anon;
grant execute on function private.cantina_accessorio_media_cancellabile(text) to authenticated;

create function private.cantina_accessorio_media_pubblica(p_percorso text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_percorso is not null
    and private.cantina_accessori_esposti_visibili()
    and exists (
      select 1 from private.cantina_accessori_pubblica v
      where p_percorso = any (v.immagini)
    );
$$;

revoke all on function private.cantina_accessorio_media_pubblica(text) from public;
grant execute on function private.cantina_accessorio_media_pubblica(text) to anon, authenticated;

create policy "cantina_accessori_media_select_proprie"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'cantina-accessori-foto'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "cantina_accessori_media_select_esposte"
on storage.objects
for select
to anon, authenticated
using (
  bucket_id = 'cantina-accessori-foto'
  and private.cantina_accessorio_media_pubblica(name)
);

create policy "cantina_accessori_media_insert_proprie"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'cantina-accessori-foto'
  and name ~ (
    '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
    || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
    || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
    || '\.webp$'
  )
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and private.cantina_accessorio_proprio((storage.foldername(name))[2])
);

create policy "cantina_accessori_media_delete_proprie_non_in_uso"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'cantina-accessori-foto'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and private.cantina_accessorio_media_cancellabile(name)
);

-- ---------------------------------------------------------------------------
-- [5] Porte del proprietario
-- ---------------------------------------------------------------------------

-- Stato per la UI: nessun dato altrui, solo gli interruttori che riguardano
-- il chiamante. `abilitata` decide se la sezione compare.
create function public.cantina_accessori_stato()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.cantina_accessori_utente();
  return jsonb_build_object(
    'abilitata', private.cantina_accessori_consentita(),
    'esposti_visibili', private.cantina_accessori_esposti_visibili()
  );
end;
$$;

comment on function public.cantina_accessori_stato() is
  'Se la Cantina Accessori e usabile dal chiamante e se gli esposti sono ora visibili al pubblico.';

-- Tassonomia per l'inserimento: attiva, a due livelli, indipendente
-- dall'interruttore del catalogo commerciale. Non espone schede, bozze o conteggi.
create function public.cantina_accessori_categorie_elenca()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.cantina_accessori_utente();
  if not private.cantina_accessori_consentita() then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'slug', p.slug,
        'nome', p.nome,
        'sottocategorie', coalesce((
          select jsonb_agg(
            jsonb_build_object('id', k.id, 'slug', k.slug, 'nome', k.nome)
            order by k.ordine, k.nome)
          from private.accessori_categorie k
          where k.parent_id = p.id and k.attiva
        ), '[]'::jsonb)
      )
      order by p.ordine, p.nome)
    from private.accessori_categorie p
    where p.parent_id is null and p.attiva
  ), '[]'::jsonb);
end;
$$;

comment on function public.cantina_accessori_categorie_elenca() is
  'Tassonomia attiva (due livelli) per l''inserimento personale. Solo authenticated; '
  'non dipende dall''interruttore del catalogo e non espone schede.';

create function public.cantina_accessori_elenca(p_archiviati boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
begin
  if not private.cantina_accessori_consentita() then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(private.cantina_accessorio_json(s.id) order by s.created_at desc, s.id)
    from (
      select a.id, a.created_at
      from private.cantina_accessori a
      where a.owner_id = v_uid
        and ((a.archiviato_at is not null) = coalesce(p_archiviati, false))
      order by a.created_at desc, a.id
      limit 300
    ) s
  ), '[]'::jsonb);
end;
$$;

comment on function public.cantina_accessori_elenca(boolean) is
  'Gli accessori del chiamante (massimo 300), attivi o archiviati. Il proprietario viene da auth.uid().';

-- Crea (id nuovo, scelto dal client per rendere il tentativo ripetibile) o
-- aggiorna. Un id che appartiene ad altri risponde come un id inesistente.
create function public.cantina_accessori_salva(p_id uuid, p_dati jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
  v_old private.cantina_accessori%rowtype;
  v_chiave text;
  v_categoria uuid;
  v_nome text;
  v_desc text;
  v_marchio text;
  v_condizione text;
  v_quantita integer;
  v_note text;
  v_catalogo uuid;
  v_row private.cantina_accessori%rowtype;
  v_esiste boolean;
begin
  if p_id is null then
    raise exception 'Dati non validi.' using errcode = '22023', hint = 'dati_non_validi';
  end if;
  if p_dati is null or jsonb_typeof(p_dati) <> 'object' then
    raise exception 'Dati non validi.' using errcode = '22023', hint = 'dati_non_validi';
  end if;
  for v_chiave in select jsonb_object_keys(p_dati) loop
    if v_chiave <> all (array['categoria_id', 'nome', 'descrizione', 'marchio', 'condizione',
                              'quantita', 'note', 'catalogo_slug']) then
      raise exception 'Campo non ammesso.' using errcode = '22023', hint = 'campo_sconosciuto';
    end if;
  end loop;

  if not private.cantina_accessori_consentita() then
    raise exception 'La Cantina Accessori non e ancora attiva.' using errcode = '42501', hint = 'funzione_non_attiva';
  end if;

  select * into v_old from private.cantina_accessori where id = p_id for update;
  v_esiste := v_old.id is not null;
  if v_esiste and v_old.owner_id <> v_uid then
    raise exception 'Accessorio non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  if v_esiste and v_old.archiviato_at is not null then
    raise exception 'Un accessorio archiviato non si modifica: ripristinalo prima.'
      using errcode = '22023', hint = 'archiviato';
  end if;

  if p_dati ? 'categoria_id' then
    if jsonb_typeof(p_dati -> 'categoria_id') = 'string'
       and (p_dati ->> 'categoria_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      v_categoria := (p_dati ->> 'categoria_id')::uuid;
    else
      raise exception 'Categoria non valida.' using errcode = '22023', hint = 'categoria_non_valida';
    end if;
  else
    v_categoria := v_old.categoria_id;
  end if;
  if v_categoria is null then
    raise exception 'Scegli la categoria.' using errcode = '22023', hint = 'categoria_obbligatoria';
  end if;

  v_nome := case when p_dati ? 'nome'
    then private.cantina_accessori_testo(p_dati -> 'nome', 2, 120, 'nome_non_valido')
    else v_old.nome end;
  if v_nome is null then
    raise exception 'Nome non valido.' using errcode = '22023', hint = 'nome_non_valido';
  end if;
  v_desc := case when p_dati ? 'descrizione'
    then private.cantina_accessori_testo(p_dati -> 'descrizione', 0, 1000, 'descrizione_non_valida')
    else coalesce(v_old.descrizione, '') end;
  v_note := case when p_dati ? 'note'
    then private.cantina_accessori_testo(p_dati -> 'note', 0, 1000, 'note_non_valide')
    else coalesce(v_old.note_private, '') end;
  v_marchio := case when p_dati ? 'marchio'
    then nullif(private.cantina_accessori_testo(p_dati -> 'marchio', 0, 80, 'marchio_non_valido'), '')
    else v_old.marchio end;

  v_condizione := case when p_dati ? 'condizione' then p_dati ->> 'condizione'
    else coalesce(v_old.condizione, 'nuovo') end;
  if v_condizione is null or v_condizione not in ('nuovo', 'come_nuovo', 'usato', 'da_collezione') then
    raise exception 'Condizione non valida.' using errcode = '22023', hint = 'condizione_non_valida';
  end if;

  if p_dati ? 'quantita' then
    if jsonb_typeof(p_dati -> 'quantita') <> 'number'
       or (p_dati ->> 'quantita')::numeric <> trunc((p_dati ->> 'quantita')::numeric)
       or (p_dati ->> 'quantita')::numeric not between 1 and 999 then
      raise exception 'Quantita non valida.' using errcode = '22023', hint = 'quantita_non_valida';
    end if;
    v_quantita := (p_dati ->> 'quantita')::integer;
  else
    v_quantita := coalesce(v_old.quantita, 1);
  end if;

  -- Legame facoltativo: solo lettura del catalogo, solo schede pubblicate e
  -- visibili al chiamante. Null scollega.
  if p_dati ? 'catalogo_slug' then
    if jsonb_typeof(p_dati -> 'catalogo_slug') = 'null' then
      v_catalogo := null;
    elsif jsonb_typeof(p_dati -> 'catalogo_slug') <> 'string' then
      raise exception 'Scheda del catalogo non valida.' using errcode = '22023', hint = 'catalogo_non_valido';
    else
      select a.id into v_catalogo
      from private.accessori a
      where a.slug = (p_dati ->> 'catalogo_slug')
        and a.stato = 'pubblicato'
        and private.cantina_accessori_catalogo_collegabile();
      if v_catalogo is null then
        raise exception 'Scheda del catalogo non valida.' using errcode = '22023', hint = 'catalogo_non_valido';
      end if;
    end if;
  else
    v_catalogo := v_old.catalogo_id;
  end if;

  if not v_esiste then
    if (select count(*) from private.cantina_accessori a where a.owner_id = v_uid) >= 300 then
      raise exception 'Hai raggiunto il numero massimo di accessori.' using errcode = '22023', hint = 'limite_raggiunto';
    end if;
    insert into private.cantina_accessori
      (id, owner_id, categoria_id, catalogo_id, nome, descrizione, marchio, condizione, quantita, note_private)
    values
      (p_id, v_uid, v_categoria, v_catalogo, v_nome, v_desc, v_marchio, v_condizione, v_quantita, v_note)
    returning * into v_row;
  else
    update private.cantina_accessori
    set categoria_id = v_categoria, catalogo_id = v_catalogo, nome = v_nome, descrizione = v_desc,
        marchio = v_marchio, condizione = v_condizione, quantita = v_quantita, note_private = v_note
    where id = p_id
    returning * into v_row;
  end if;

  return private.cantina_accessorio_json(v_row.id);
end;
$$;

comment on function public.cantina_accessori_salva(uuid, jsonb) is
  'Crea o aggiorna un accessorio del chiamante. Il proprietario viene da auth.uid(); '
  'nasce privato; la categoria deve essere una foglia attiva della tassonomia Vinea.';

create function public.cantina_accessori_immagini_imposta(p_id uuid, p_percorsi text[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
  v_a private.cantina_accessori%rowtype;
  v_percorsi text[] := coalesce(p_percorsi, '{}'::text[]);
  v_percorso text;
begin
  if not private.cantina_accessori_consentita() then
    raise exception 'La Cantina Accessori non e ancora attiva.' using errcode = '42501', hint = 'funzione_non_attiva';
  end if;
  select * into v_a from private.cantina_accessori where id = p_id and owner_id = v_uid for update;
  if v_a.id is null then
    raise exception 'Accessorio non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  if cardinality(v_percorsi) > 4 then
    raise exception 'Troppe immagini (massimo 4).' using errcode = '22023', hint = 'immagini_non_valide';
  end if;
  -- La forma esatta e il legame con proprietario e accessorio sono nel trigger;
  -- qui si verifica che l'oggetto esista davvero nel bucket.
  foreach v_percorso in array v_percorsi loop
    if v_percorso is null or not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'cantina-accessori-foto' and o.name = v_percorso
    ) then
      raise exception 'Immagine non trovata nel bucket.' using errcode = '22023', hint = 'immagine_assente';
    end if;
  end loop;

  update private.cantina_accessori set immagini = v_percorsi where id = p_id;
  return private.cantina_accessorio_json(p_id);
end;
$$;

-- L'esposizione e una scelta esplicita. Tornare privata e sempre consentito,
-- anche a funzione spenta: il verso sicuro non richiede alcuna condizione.
create function public.cantina_accessori_visibilita_imposta(p_id uuid, p_visibilita text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
  v_a private.cantina_accessori%rowtype;
begin
  if p_visibilita is null or p_visibilita not in ('privata', 'cantina_pubblica') then
    raise exception 'Visibilita non valida.' using errcode = '22023', hint = 'visibilita_non_valida';
  end if;
  select * into v_a from private.cantina_accessori where id = p_id and owner_id = v_uid for update;
  if v_a.id is null then
    raise exception 'Accessorio non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  if p_visibilita = 'cantina_pubblica' then
    if not private.cantina_accessori_consentita() then
      raise exception 'La Cantina Accessori non e ancora attiva.' using errcode = '42501', hint = 'funzione_non_attiva';
    end if;
    if v_a.archiviato_at is not null then
      raise exception 'Un accessorio archiviato non si espone.' using errcode = '22023', hint = 'archiviato';
    end if;
    perform set_config('vinae.cantina_accessori_espone', 'espone:' || v_uid::text || ':' || p_id::text, true);
  end if;

  update private.cantina_accessori set visibilita = p_visibilita where id = p_id;
  return private.cantina_accessorio_json(p_id);
end;
$$;

-- Archiviare riporta l'accessorio a privato (lo fa anche il trigger).
create function public.cantina_accessori_archivia(p_id uuid, p_archivia boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
  v_a private.cantina_accessori%rowtype;
begin
  if p_archivia is null then
    raise exception 'Valore non valido.' using errcode = '22023', hint = 'dati_non_validi';
  end if;
  select * into v_a from private.cantina_accessori where id = p_id and owner_id = v_uid for update;
  if v_a.id is null then
    raise exception 'Accessorio non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;

  update private.cantina_accessori
  set archiviato_at = case when p_archivia then coalesce(v_a.archiviato_at, now()) else null end,
      visibilita = case when p_archivia then 'privata' else v_a.visibilita end
  where id = p_id;
  return private.cantina_accessorio_json(p_id);
end;
$$;

-- Rimozione definitiva dell'accessorio del chiamante. Restituisce i percorsi
-- delle foto, ora non piu referenziate, che il proprietario puo cancellare dal
-- bucket con la propria policy.
create function public.cantina_accessori_rimuovi(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
  v_a private.cantina_accessori%rowtype;
begin
  select * into v_a from private.cantina_accessori where id = p_id and owner_id = v_uid for update;
  if v_a.id is null then
    raise exception 'Accessorio non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  delete from private.cantina_accessori where id = p_id;
  return jsonb_build_object('rimosso', true, 'percorsi', to_jsonb(v_a.immagini));
end;
$$;

-- ---------------------------------------------------------------------------
-- [4] La porta pubblica: un profilo per volta
-- ---------------------------------------------------------------------------
--
-- Un solo `uuid`, nessun filtro di ricerca: chi chiama deve gia sapere di chi
-- guarda il profilo. Vuota finche funzione E visibilita non sono accese;
-- `p_anteprima = true` e solo per l'admin reale e ignora gli interruttori. Il
-- limite lo decide il database (48).

create function public.cantina_accessori_pubblica_profilo(
  p_user_id uuid,
  p_limit integer default 12,
  p_offset integer default 0,
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
  elsif not private.cantina_accessori_esposti_visibili() then
    return '[]'::jsonb;
  end if;
  if p_user_id is null then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', s.accessorio_id,
        'nome', s.nome,
        'descrizione', s.descrizione,
        'marchio', s.marchio,
        'condizione', s.condizione,
        'quantita', s.quantita,
        'immagini', to_jsonb(s.immagini),
        'categoria_slug', s.categoria_slug,
        'categoria_nome', s.categoria_nome,
        'genitore_nome', s.genitore_nome
      )
      order by s.genitore_nome nulls last, s.categoria_nome, s.nome, s.accessorio_id)
    from (
      select v.*
      from private.cantina_accessori_pubblica v
      where v.user_id = p_user_id
      order by v.genitore_nome nulls last, v.categoria_nome, v.nome, v.accessorio_id
      limit least(greatest(coalesce(p_limit, 12), 1), 48)
      offset greatest(coalesce(p_offset, 0), 0)
    ) s
  ), '[]'::jsonb);
end;
$$;

comment on function public.cantina_accessori_pubblica_profilo(uuid, integer, integer, boolean) is
  'Accessori ESPOSTI di UN profilo noto. Vuota con interruttori spenti. Elenco chiuso: '
  'nessuna nota privata, nessun id proprietario, nessun legame col catalogo.';

-- ---------------------------------------------------------------------------
-- Porte admin per gli interruttori
-- ---------------------------------------------------------------------------

create function public.cantina_accessori_admin_stato()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.accessori_admin_richiesto();
  return jsonb_build_object(
    'funzione_attiva', private.cantina_accessori_funzione_attiva(),
    'visibilita_pubblica', coalesce(
      (select i.visibilita_pubblica from private.cantina_accessori_impostazioni i), false),
    'catalogo_visibile', private.accessori_visibili_al_pubblico(),
    'puo_rilasciare', private.accessori_puo_rilasciare()
  );
end;
$$;

-- Accendere richiede il ruolo di rilascio; spegnere un admin qualsiasi.
create function public.cantina_accessori_admin_imposta(p_interruttore text, p_attiva boolean, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid;
  v_motivo text := private.partner_motivo_pulito(p_motivo);
begin
  if p_attiva is null or p_interruttore is null
     or p_interruttore not in ('funzione', 'visibilita_pubblica') then
    raise exception 'Valore non valido.' using errcode = '22023', hint = 'dati_non_validi';
  end if;
  if p_attiva then
    v_admin := private.accessori_rilascio_richiesto();
  else
    v_admin := private.accessori_admin_richiesto();
  end if;
  if v_motivo is null then
    raise exception 'Il cambio di interruttore richiede un motivo.' using errcode = '22023', hint = 'motivo_obbligatorio';
  end if;

  perform set_config('vinae.accessori_rilascio', 'rilascio:' || v_admin::text, true);

  if p_interruttore = 'funzione' then
    update private.cantina_accessori_impostazioni
    set funzione_attiva = p_attiva, aggiornato_da = v_admin where singleton;
  else
    update private.cantina_accessori_impostazioni
    set visibilita_pubblica = p_attiva, aggiornato_da = v_admin where singleton;
  end if;

  insert into private.accessori_registro (admin_id, azione, oggetto, motivo)
  values (v_admin, 'cantina_' || p_interruttore || case when p_attiva then '_accendi' else '_spegni' end,
          'cantina_accessori', v_motivo);

  return jsonb_build_object(
    'funzione_attiva', private.cantina_accessori_funzione_attiva(),
    'visibilita_pubblica', coalesce(
      (select i.visibilita_pubblica from private.cantina_accessori_impostazioni i), false)
  );
end;
$$;

comment on function public.cantina_accessori_admin_imposta(text, boolean, text) is
  'Accende (solo con il ruolo di rilascio accessori_release) o spegne (ogni admin) la '
  'funzione personale o la visibilita pubblica degli accessori esposti. Motivo obbligatorio, registrato.';

-- ---------------------------------------------------------------------------
-- Privilegi di esecuzione
-- ---------------------------------------------------------------------------

revoke all on function public.cantina_accessori_stato() from public, anon, authenticated, service_role;
revoke all on function public.cantina_accessori_categorie_elenca() from public, anon, authenticated, service_role;
revoke all on function public.cantina_accessori_elenca(boolean) from public, anon, authenticated, service_role;
revoke all on function public.cantina_accessori_salva(uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.cantina_accessori_immagini_imposta(uuid, text[]) from public, anon, authenticated, service_role;
revoke all on function public.cantina_accessori_visibilita_imposta(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.cantina_accessori_archivia(uuid, boolean) from public, anon, authenticated, service_role;
revoke all on function public.cantina_accessori_rimuovi(uuid) from public, anon, authenticated, service_role;
revoke all on function public.cantina_accessori_pubblica_profilo(uuid, integer, integer, boolean) from public, anon, authenticated, service_role;
revoke all on function public.cantina_accessori_admin_stato() from public, anon, authenticated, service_role;
revoke all on function public.cantina_accessori_admin_imposta(text, boolean, text) from public, anon, authenticated, service_role;

grant execute on function public.cantina_accessori_stato() to authenticated;
grant execute on function public.cantina_accessori_categorie_elenca() to authenticated;
grant execute on function public.cantina_accessori_elenca(boolean) to authenticated;
grant execute on function public.cantina_accessori_salva(uuid, jsonb) to authenticated;
grant execute on function public.cantina_accessori_immagini_imposta(uuid, text[]) to authenticated;
grant execute on function public.cantina_accessori_visibilita_imposta(uuid, text) to authenticated;
grant execute on function public.cantina_accessori_archivia(uuid, boolean) to authenticated;
grant execute on function public.cantina_accessori_rimuovi(uuid) to authenticated;
grant execute on function public.cantina_accessori_pubblica_profilo(uuid, integer, integer, boolean) to anon, authenticated;
grant execute on function public.cantina_accessori_admin_stato() to authenticated;
grant execute on function public.cantina_accessori_admin_imposta(text, boolean, text) to authenticated;

notify pgrst, 'reload schema';
