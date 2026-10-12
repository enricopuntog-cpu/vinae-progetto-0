-- ===========================================================================
-- Vinea Partner + Quantita multiple — Blocco C, parte 1: inventario per unita
-- ===========================================================================
--
-- Ammissione: filone «Vinea Partner + Quantita multiple» (blocchi A-F), deciso
-- dal titolare l'11 ottobre 2026; il Blocco C (quantita multiple per privati e
-- Partner) e stato avviato dal titolare il 12 ottobre 2026. Le migrazioni dei
-- Blocchi A (20261011150000) e B (20261011200000) sono distribuite e congelate.
--
-- DECISIONE ARCHITETTURALE (docs/VP_C_QUANTITA_MULTIPLE.md). Una quantita non
-- e un numero scritto da qualche parte: e il conteggio di righe di
-- `public.bottle_units`, che resta l'UNICA fonte di verita dell'inventario —
-- una riga per bottiglia fisica, con la sua posizione, le sue note, la sua
-- degustazione, il suo costo e il suo storico. Nessuna colonna `quantita`
-- viene aggiunta a una bottiglia, a un vino o a un annuncio: le quantita si
-- derivano contando unita, e un raggruppamento visivo non cancella nulla.
--
-- Questa parte prepara l'inventario; annunci, prenotazioni e ordini
-- multi-unita sono la parte 2 (migrazione successiva).
--
-- Che cosa aggiunge:
--   [1] la classe d'inventario `personale` | `commerciale`;
--   [2] `private.inventario_impostazioni`: due interruttori fail-closed, a
--       `false`, che solo una migrazione futura (VP-D, VP-E) potra accendere;
--   [3] `private.cellar_lotti`: il registro delle aggiunte multiple, con la
--       chiave d'idempotenza che rende innocuo un nuovo tentativo;
--   [4] su `bottle_units`: `formato` per unita (il formato e un attributo
--       fisico della bottiglia, non della scheda vino), `lotto_id`,
--       `inventario`, `partner_id`; guardiano d'immutabilita;
--   [5] `cellar_bottiglie_aggiungi`: N bottiglie identiche in una sola
--       operazione atomica e idempotente nella Cantina personale;
--   [6] `scorte_partner_aggiungi`: N unita nell'inventario commerciale del
--       Partner attivo, separate dal patrimonio personale del titolare;
--   [7] confini fra le due classi nelle porte della Cantina personale
--       (apertura, posizionamento 3D, Cantina pubblica, analitica) e negli
--       annunci (un'unita commerciale non entra in un annuncio finche la
--       parte 2 non ne definisce il percorso).
--
-- Che cosa NON fa, di proposito:
--   - non converte nulla: ogni unita esistente e `personale`, e una
--     classe non cambia mai dopo la nascita dell'unita;
--   - non apre vendite professionali, non tocca `marketplace_config`, il
--     margine dei privati (800 bps) ne i gate del Blocco A/B;
--   - non cambia `cellar_bottiglia_aggiungi` (usata dal frontend distribuito):
--     il formato delle unita che crea viene dal vino, come finora.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- [1] Classe d'inventario
-- ---------------------------------------------------------------------------

create type public.inventario_classe as enum ('personale', 'commerciale');

comment on type public.inventario_classe is
  'Patrimonio personale del titolare dell''account o inventario commerciale '
  'di un Partner. Fissata alla nascita dell''unita, mai convertita.';

-- ---------------------------------------------------------------------------
-- [2] Interruttori del filone, fail-closed
-- ---------------------------------------------------------------------------

create table private.inventario_impostazioni (
  id boolean primary key default true check (id),
  -- Ordini con piu di una bottiglia: dipendono dalla tariffazione logistica
  -- per quantita e colli multipli (VP-E). Finche e false la porta del
  -- checkout rifiuta ogni quantita maggiore di 1.
  ordini_multi_unita boolean not null default false,
  -- Vendita professionale dei prodotti Partner: dipende dal margine 1500 bps e
  -- dal checkout professionale (VP-D). Finche e false nessun prodotto
  -- commerciale diventa acquistabile.
  vendita_partner boolean not null default false,
  aggiornato_at timestamptz not null default now()
);

insert into private.inventario_impostazioni (id) values (true);

comment on table private.inventario_impostazioni is
  'Interruttori del filone VP. Una sola riga. Nessun grant client: si cambiano '
  'solo con una migrazione dei blocchi che soddisfano le dipendenze.';

revoke all on private.inventario_impostazioni from public, anon, authenticated;
alter table private.inventario_impostazioni enable row level security;

create function private.inventario_flag(p_nome text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select case p_nome
      when 'ordini_multi_unita' then i.ordini_multi_unita
      when 'vendita_partner' then i.vendita_partner
    end
    from private.inventario_impostazioni i
    where i.id
  ), false);
$$;

revoke execute on function private.inventario_flag(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [3] Registro delle aggiunte multiple
-- ---------------------------------------------------------------------------

create table private.cellar_lotti (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  inventario public.inventario_classe not null,
  partner_id uuid references private.partners (id) on delete restrict,
  wine_id uuid not null references public.wines (id) on delete restrict,
  formato text not null,
  quantita smallint not null check (quantita between 1 and 120),
  idempotency_key text not null check (
    length(idempotency_key) between 8 and 128
    and idempotency_key ~ '^[A-Za-z0-9._:-]+$'
  ),
  -- Impronta della richiesta: lo stesso tentativo ripetuto torna la stessa
  -- risposta; la stessa chiave con dati diversi e un errore, non un replay.
  impronta text not null check (impronta ~ '^[0-9a-f]{32}$'),
  created_at timestamptz not null default now(),
  constraint cellar_lotti_classe_coerente check (
    (inventario = 'commerciale') = (partner_id is not null)
  ),
  constraint cellar_lotti_chiave_unica unique (owner_id, idempotency_key)
);

comment on table private.cellar_lotti is
  'Un''aggiunta di N bottiglie identiche in una sola operazione. Le bottiglie '
  'restano N righe di bottle_units con lotto_id: il lotto e provenienza, non '
  'una quantita autorevole.';

revoke all on private.cellar_lotti from public, anon, authenticated;
alter table private.cellar_lotti enable row level security;

create index cellar_lotti_owner_idx on private.cellar_lotti (owner_id, created_at desc);

-- ---------------------------------------------------------------------------
-- [4] Colonne nuove dell'unita
-- ---------------------------------------------------------------------------

create function private.formato_valido(p_formato text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_formato in (
    '0,1875 L', '0,375 L', '0,5 L', '0,75 L', '1 L', '1,5 L',
    '3 L', '4,5 L', '5 L', '6 L', '9 L', '12 L', '15 L'
  );
$$;

revoke execute on function private.formato_valido(text) from public, anon, authenticated;

alter table public.bottle_units
  add column formato text,
  add column lotto_id uuid references private.cellar_lotti (id) on delete restrict,
  add column inventario public.inventario_classe not null default 'personale',
  add column partner_id uuid references private.partners (id) on delete restrict;

-- Ogni unita esistente prende il formato del suo vino: e il valore che ogni
-- lettura usava fino a oggi, quindi nessun numero cambia.
update public.bottle_units bu
set formato = coalesce(nullif(btrim(w.formato), ''), '0,75 L')
from public.wines w
where w.id = bu.wine_id;

alter table public.bottle_units
  alter column formato set not null,
  add constraint bottle_units_formato_valido check (
    formato in (
      '0,1875 L', '0,375 L', '0,5 L', '0,75 L', '1 L', '1,5 L',
      '3 L', '4,5 L', '5 L', '6 L', '9 L', '12 L', '15 L'
    )
  ),
  add constraint bottle_units_classe_coerente check (
    (inventario = 'commerciale') = (partner_id is not null)
  ),
  -- Un prodotto commerciale non e una bottiglia della Cantina pubblica di
  -- nessuno: la vetrina del Partner e un'altra cosa.
  add constraint bottle_units_commerciale_privata check (
    inventario = 'personale' or visibilita = 'privata'
  );

comment on column public.bottle_units.formato is
  'Formato fisico della bottiglia. Fissato alla nascita; per le unita create '
  'senza formato esplicito e quello del vino.';
comment on column public.bottle_units.lotto_id is
  'Aggiunta multipla da cui l''unita e nata (private.cellar_lotti), se c''e.';
comment on column public.bottle_units.inventario is
  'personale = patrimonio del titolare dell''account; commerciale = '
  'inventario del Partner partner_id. Immutabile.';

create index bottle_units_lotto_idx on public.bottle_units (lotto_id)
  where lotto_id is not null;
create index bottle_units_raggruppamento_idx
  on public.bottle_units (owner_id, inventario, wine_id, formato)
  where deleted_at is null and ceduta_at is null;

grant select (formato, lotto_id, inventario, partner_id)
  on public.bottle_units to authenticated;

-- Guardiano: completa il formato alla nascita, verifica la classe e rende
-- immutabili identita, provenienza e classe. Vale anche per i ruoli
-- privilegiati: nessuna porta presente o futura converte una bottiglia
-- personale in un prodotto commerciale cambiando una colonna.
create function private.bottle_units_inventario_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_titolare uuid;
begin
  if tg_op = 'INSERT' then
    if new.formato is null then
      select coalesce(nullif(btrim(w.formato), ''), '0,75 L') into new.formato
      from public.wines w where w.id = new.wine_id;
    end if;
    if new.inventario = 'commerciale' then
      select p.titolare_id into v_titolare
      from private.partners p where p.id = new.partner_id;
      if v_titolare is null or v_titolare is distinct from new.owner_id then
        raise exception 'Un prodotto commerciale appartiene al titolare del suo Partner.'
          using errcode = '42501', hint = 'inventario_partner_non_valido';
      end if;
    end if;
    return new;
  end if;

  if new.owner_id is distinct from old.owner_id
     or new.wine_id is distinct from old.wine_id
     or new.formato is distinct from old.formato
     or new.lotto_id is distinct from old.lotto_id
     or new.inventario is distinct from old.inventario
     or new.partner_id is distinct from old.partner_id then
    raise exception 'Proprietario, vino, formato, lotto e classe di una bottiglia non cambiano.'
      using errcode = '42501', hint = 'unita_immutabile';
  end if;
  return new;
end;
$$;

revoke execute on function private.bottle_units_inventario_guard() from public, anon, authenticated;

create trigger bottle_units_inventario_guard
  before insert or update on public.bottle_units
  for each row execute function private.bottle_units_inventario_guard();

-- ---------------------------------------------------------------------------
-- [5] Aggiunta multipla: nucleo comune e porta della Cantina personale
-- ---------------------------------------------------------------------------

-- Nucleo condiviso dalle due porte. Non e esposto: riceve proprietario, classe
-- e Partner gia risolti dalla porta chiamante, che ne risponde.
create function private.inventario_lotto_crea(
  p_owner uuid,
  p_inventario public.inventario_classe,
  p_partner uuid,
  p_produttore text,
  p_nome text,
  p_annata integer,
  p_regione text,
  p_tipo text,
  p_formato text,
  p_quantita integer,
  p_visibilita public.bottle_unit_visibilita,
  p_immagini text[],
  p_acquisition_cost_cents integer,
  p_acquired_at timestamptz,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lotto private.cellar_lotti%rowtype;
  v_impronta text;
  v_wine uuid;
  v_immagine text;
  v_fonte public.bottle_acquisition_fonte;
  v_unita uuid[];
  v_immagini text[] := coalesce(p_immagini, '{}'::text[]);
  v_formato text := btrim(coalesce(p_formato, ''));
begin
  if length(coalesce(p_idempotency_key, '')) not between 8 and 128
     or p_idempotency_key !~ '^[A-Za-z0-9._:-]+$' then
    raise exception 'Richiesta non valida: ripeti l''operazione.'
      using errcode = '22023', hint = 'chiave_idempotenza_non_valida';
  end if;
  if p_quantita is null or p_quantita < 1 or p_quantita > 120 then
    raise exception 'Puoi aggiungere da 1 a 120 bottiglie per volta.'
      using errcode = 'P0001', hint = 'quantita_non_valida';
  end if;
  if not private.formato_valido(v_formato) then
    raise exception 'Formato non valido.' using errcode = 'P0001', hint = 'formato_non_valido';
  end if;
  if p_visibilita not in ('privata', 'cantina_pubblica') then
    raise exception 'Visibilità della bottiglia non valida.' using errcode = 'P0001';
  end if;
  if p_inventario = 'commerciale' and p_visibilita <> 'privata' then
    raise exception 'Un prodotto commerciale non entra nella Cantina pubblica.'
      using errcode = 'P0001';
  end if;
  if array_position(v_immagini, null) is not null
     or (cardinality(v_immagini) > 0 and array_ndims(v_immagini) <> 1) then
    raise exception 'Elenco di fotografie non valido.' using errcode = 'P0001';
  end if;
  if cardinality(v_immagini) > 6 then
    raise exception 'Massimo 6 fotografie per bottiglia.' using errcode = 'P0001';
  end if;

  -- L'impronta copre ogni dato che decide che cosa nasce. Testi normalizzati
  -- come li normalizza il catalogo, per non distinguere due tentativi che
  -- creerebbero la stessa cosa.
  v_impronta := md5(jsonb_build_array(
    p_inventario, p_partner, btrim(coalesce(p_produttore, '')),
    btrim(coalesce(p_nome, '')), p_annata, btrim(coalesce(p_regione, '')),
    p_tipo, v_formato, p_quantita, p_visibilita, v_immagini,
    p_acquisition_cost_cents, extract(epoch from p_acquired_at)
  )::text);

  -- Replay prima di ogni altra cosa: un nuovo tentativo non consuma il limite
  -- di frequenza e non rifa' controlli il cui esito e gia stato scritto.
  select * into v_lotto from private.cellar_lotti
  where owner_id = p_owner and idempotency_key = p_idempotency_key;
  if found then
    if v_lotto.impronta <> v_impronta then
      raise exception 'Questa operazione è già stata registrata con dati diversi.'
        using errcode = 'P0001', hint = 'chiave_idempotenza_riusata';
    end if;
    select array_agg(bu.id order by bu.created_at, bu.id) into v_unita
    from public.bottle_units bu where bu.lotto_id = v_lotto.id;
    return jsonb_build_object(
      'lottoId', v_lotto.id, 'wineId', v_lotto.wine_id, 'formato', v_lotto.formato,
      'quantita', v_lotto.quantita, 'bottleUnitIds', to_jsonb(coalesce(v_unita, '{}'::uuid[])),
      'replay', true
    );
  end if;

  perform private.rate_limit_consume('inventario:lotto', 'user:' || p_owner::text, 30, 60);

  foreach v_immagine in array v_immagini loop
    if v_immagine !~ ('^' || p_owner::text || '/[0-9a-f-]{36}\.(jpg|jpeg|png|webp|avif)$') then
      raise exception 'Fotografia non valida: %', v_immagine using errcode = 'P0001';
    end if;
    if not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'cantina' and o.name = v_immagine
    ) then
      raise exception 'La fotografia non appartiene al bucket privato della Cantina.'
        using errcode = 'P0001';
    end if;
  end loop;

  if p_acquisition_cost_cents is not null then
    if p_acquisition_cost_cents < 0 then
      raise exception 'Il prezzo di acquisto non può essere negativo.' using errcode = 'P0001';
    end if;
    if p_acquisition_cost_cents > 100000000 then
      raise exception 'Il prezzo di acquisto indicato non è plausibile.' using errcode = 'P0001';
    end if;
  end if;
  if p_acquired_at is not null then
    if p_acquired_at > now() then
      raise exception 'La data di acquisto non può essere nel futuro.' using errcode = 'P0001';
    end if;
    if p_acquired_at < timestamptz '1900-01-01' then
      raise exception 'La data di acquisto indicata non è plausibile.' using errcode = 'P0001';
    end if;
  end if;

  v_fonte := case
    when p_acquisition_cost_cents is not null or p_acquired_at is not null
      then 'manuale'::public.bottle_acquisition_fonte
    else 'sconosciuta'::public.bottle_acquisition_fonte
  end;

  v_wine := private.catalogo_risolvi_vino_utente(
    p_produttore, p_nome, p_annata, p_regione, p_tipo
  );

  -- La riga del lotto nasce prima delle unita. Due tentativi concorrenti con
  -- la stessa chiave si serializzano qui: il secondo attende il primo e, se
  -- il primo ha confermato, non inserisce nulla e rilegge.
  insert into private.cellar_lotti (
    owner_id, inventario, partner_id, wine_id, formato, quantita,
    idempotency_key, impronta
  ) values (
    p_owner, p_inventario, p_partner, v_wine, v_formato, p_quantita,
    p_idempotency_key, v_impronta
  )
  on conflict (owner_id, idempotency_key) do nothing
  returning * into v_lotto;

  if v_lotto.id is null then
    return private.inventario_lotto_crea(
      p_owner, p_inventario, p_partner, p_produttore, p_nome, p_annata,
      p_regione, p_tipo, p_formato, p_quantita, p_visibilita, p_immagini,
      p_acquisition_cost_cents, p_acquired_at, p_idempotency_key
    );
  end if;

  with nuove as (
    insert into public.bottle_units (
      owner_id, wine_id, formato, stato, visibilita, immagini,
      acquired_at, acquisition_fonte, acquisition_cost_cents,
      lotto_id, inventario, partner_id
    )
    select
      p_owner, v_wine, v_formato, 'chiusa', p_visibilita, v_immagini,
      coalesce(p_acquired_at, now()), v_fonte, p_acquisition_cost_cents,
      v_lotto.id, p_inventario, p_partner
    from generate_series(1, p_quantita)
    returning id, created_at
  )
  select array_agg(n.id order by n.created_at, n.id) into v_unita from nuove n;

  return jsonb_build_object(
    'lottoId', v_lotto.id, 'wineId', v_wine, 'formato', v_formato,
    'quantita', p_quantita, 'bottleUnitIds', to_jsonb(v_unita),
    'replay', false
  );
end;
$$;

revoke execute on function private.inventario_lotto_crea(
  uuid, public.inventario_classe, uuid, text, text, integer, text, text, text,
  integer, public.bottle_unit_visibilita, text[], integer, timestamptz, text
) from public, anon, authenticated;

create function public.cellar_bottiglie_aggiungi(
  p_produttore text,
  p_nome text,
  p_annata integer,
  p_regione text,
  p_tipo text,
  p_formato text,
  p_quantita integer,
  p_idempotency_key text,
  p_visibilita public.bottle_unit_visibilita default 'privata',
  p_immagini text[] default '{}'::text[],
  p_acquisition_cost_cents integer default null,
  p_acquired_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Devi accedere per aggiungere una bottiglia.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid) then
    raise exception 'Il tuo profilo non è ancora completo.' using errcode = 'P0001';
  end if;

  return private.inventario_lotto_crea(
    v_uid, 'personale', null, p_produttore, p_nome, p_annata, p_regione, p_tipo,
    p_formato, p_quantita, p_visibilita, p_immagini, p_acquisition_cost_cents,
    p_acquired_at, p_idempotency_key
  );
end;
$$;

comment on function public.cellar_bottiglie_aggiungi(
  text, text, integer, text, text, text, integer, text,
  public.bottle_unit_visibilita, text[], integer, timestamptz
) is
  'Aggiunge alla Cantina personale da 1 a 120 bottiglie identiche (stesso vino, '
  'annata e formato) in una sola transazione: N righe di bottle_units con lo '
  'stesso lotto_id. Il costo e per bottiglia. Idempotente per chiave.';

-- ---------------------------------------------------------------------------
-- [6] Scorte commerciali del Partner
-- ---------------------------------------------------------------------------

create function public.scorte_partner_aggiungi(
  p_produttore text,
  p_nome text,
  p_annata integer,
  p_regione text,
  p_tipo text,
  p_formato text,
  p_quantita integer,
  p_idempotency_key text,
  p_immagini text[] default '{}'::text[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_p private.partners%rowtype;
begin
  if v_uid is null then
    raise exception 'Serve una sessione.' using errcode = '42501';
  end if;
  if private.utente_stato_di(v_uid) <> 'attivo'::public.utente_stato then
    raise exception 'Account non abilitato.' using errcode = '42501', hint = 'utente_non_attivo';
  end if;

  -- Lock condiviso: una sospensione concorrente attende la fine di questa
  -- aggiunta, e un'aggiunta concorrente a una sospensione vede lo stato nuovo.
  select * into v_p from private.partners
  where titolare_id = v_uid and stato <> 'revocato'::public.partner_stato
  for share;

  if v_p.id is null then
    raise exception 'Nessun Partner aperto.' using errcode = 'P0001', hint = 'partner_non_trovato';
  end if;
  -- Solo un Partner approvato e attivo prepara il catalogo. Un Partner
  -- sospeso conserva le scorte che ha, ma non ne aggiunge.
  if v_p.stato <> 'attivo'::public.partner_stato then
    raise exception 'Le scorte si aggiungono solo con un Partner attivo.'
      using errcode = 'P0001', hint = 'partner_non_attivo';
  end if;

  return private.inventario_lotto_crea(
    v_uid, 'commerciale', v_p.id, p_produttore, p_nome, p_annata, p_regione,
    p_tipo, p_formato, p_quantita, 'privata', p_immagini, null, null,
    p_idempotency_key
  );
end;
$$;

comment on function public.scorte_partner_aggiungi(
  text, text, integer, text, text, text, integer, text, text[]
) is
  'Aggiunge da 1 a 120 unita identiche all''inventario commerciale del Partner '
  'attivo del chiamante. Le unita restano del titolare (owner_id) ma sono '
  'commerciali e legate al Partner: non compaiono nella Cantina personale, non '
  'si aprono, non hanno posizione 3D ne valore patrimoniale.';

-- ---------------------------------------------------------------------------
-- [7] Confini fra le classi nelle porte esistenti
-- ---------------------------------------------------------------------------

-- Apertura: un prodotto commerciale non si degusta. Il corpo e quello della
-- 20260819120000 con il solo controllo di classe in piu.
create or replace function public.bottiglia_apri(
  p_bottle_unit_id uuid,
  p_nota text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_owner   uuid;
  v_stato   public.bottle_unit_stato;
  v_deleted timestamptz;
  v_ceduta  timestamptz;
  v_classe  public.inventario_classe;
begin
  if v_uid is null then
    raise exception 'Devi accedere per aprire una bottiglia.' using errcode = '42501';
  end if;

  select bu.owner_id, bu.stato, bu.deleted_at, bu.ceduta_at, bu.inventario
  into v_owner, v_stato, v_deleted, v_ceduta, v_classe
  from public.bottle_units bu
  where bu.id = p_bottle_unit_id
  for update;

  if v_owner is null or v_owner is distinct from v_uid or v_deleted is not null then
    raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
  end if;
  if v_classe <> 'personale' then
    raise exception 'Le scorte commerciali non si aprono dalla Cantina.'
      using errcode = 'P0001', hint = 'inventario_commerciale';
  end if;
  if v_ceduta is not null then
    raise exception 'Questa bottiglia è già stata venduta e non è più nella tua cantina.'
      using errcode = 'P0001';
  end if;
  if v_stato = 'aperta' then
    raise exception 'Questa bottiglia è già aperta.' using errcode = 'P0001';
  end if;
  if v_stato = 'consumata' then
    raise exception 'Questa bottiglia è già stata consumata.' using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.listings l
    where l.bottle_unit_id = p_bottle_unit_id
      and l.stato in (
        'bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato'
      )
  ) then
    raise exception
      'Questa bottiglia ha un annuncio in corso: concludilo o ritiralo prima di aprirla.'
      using errcode = 'P0001';
  end if;

  update public.bottle_units
  set stato = 'aperta',
      degustazione_at = now(),
      degustazione_nota = case
        when p_nota is null or trim(p_nota) = '' then degustazione_nota
        else p_nota
      end
  where id = p_bottle_unit_id;
end;
$$;

-- Posizionamento 3D: solo patrimonio personale.
create or replace function public.cellar_posiziona(
  p_bottle_unit_id uuid,
  p_module_id uuid,
  p_riga integer,
  p_colonna integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_owner    uuid;
  v_deleted  timestamptz;
  v_ceduta   timestamptz;
  v_classe   public.inventario_classe;
  v_righe    smallint;
  v_colonne  smallint;
begin
  if v_uid is null then
    raise exception 'Devi accedere per spostare una bottiglia.' using errcode = '42501';
  end if;

  select bu.owner_id, bu.deleted_at, bu.ceduta_at, bu.inventario
  into v_owner, v_deleted, v_ceduta, v_classe
  from public.bottle_units bu
  where bu.id = p_bottle_unit_id
  for update;

  if v_owner is null or v_owner is distinct from v_uid
     or v_deleted is not null or v_ceduta is not null then
    raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
  end if;
  if v_classe <> 'personale' then
    raise exception 'Le scorte commerciali non hanno una posizione in Cantina.'
      using errcode = 'P0001', hint = 'inventario_commerciale';
  end if;

  select m.righe, m.colonne
  into v_righe, v_colonne
  from public.cellar_modules m
    join public.cellar_environments e on e.id = m.environment_id
  where m.id = p_module_id
    and e.owner_id = v_uid;

  if v_righe is null then
    raise exception 'Questo scaffale non è nella tua cantina.' using errcode = '42501';
  end if;
  if p_riga is null or p_riga < 0 or p_riga >= v_righe then
    raise exception 'Riga fuori dallo scaffale: ne ha %.', v_righe using errcode = 'P0001';
  end if;
  if p_colonna is null or p_colonna < 0 or p_colonna >= v_colonne then
    raise exception 'Colonna fuori dallo scaffale: ne ha %.', v_colonne using errcode = 'P0001';
  end if;

  begin
    insert into public.cellar_slots (module_id, bottle_unit_id, riga, colonna)
    values (p_module_id, p_bottle_unit_id, p_riga::smallint, p_colonna::smallint)
    on conflict (bottle_unit_id) do update
      set module_id = excluded.module_id,
          riga = excluded.riga,
          colonna = excluded.colonna;
  exception
    when unique_violation then
      raise exception 'In quella posizione c''è già una bottiglia.' using errcode = 'P0001';
  end;
end;
$$;

-- Cantina pubblica: stesse colonne, ma il formato e quello dell'unita e la
-- classe commerciale e esclusa in modo esplicito (oltre al CHECK di [4]).
create or replace view private.cantina_pubblica
with (security_invoker = off, security_barrier = true)
as
select
  bu.id as bottle_unit_id,
  bu.owner_id as user_id,
  bu.stato as bottiglia_stato,
  bu.created_at as aggiunta_at,
  w.id as wine_id,
  w.slug as wine_slug,
  w.produttore,
  w.nome,
  w.annata,
  w.regione,
  w.denominazione,
  w.tipo,
  bu.formato,
  ann.listing_id,
  ann.listing_slug,
  coalesce(ann.listing_immagini, '{}'::text[]) as listing_immagini
from public.bottle_units bu
  join public.wines w on w.id = bu.wine_id
  join private.profili_pubblici pp on pp.user_id = bu.owner_id
  left join lateral (
    select pl.id as listing_id, pl.slug as listing_slug, pl.immagini as listing_immagini
    from public.listings l
      join public.public_listings pl on pl.id = l.id
    where l.bottle_unit_id = bu.id
    order by pl.pubblicato_at desc, pl.id
    limit 1
  ) ann on true
where bu.visibilita = 'cantina_pubblica'::public.bottle_unit_visibilita
  and bu.inventario = 'personale'::public.inventario_classe
  and bu.deleted_at is null
  and bu.ceduta_at is null
  and bu.stato = any (array['chiusa'::public.bottle_unit_stato, 'aperta'::public.bottle_unit_stato]);

-- Annunci: finche la parte 2 non definisce il percorso dei prodotti Partner,
-- un'unita commerciale non entra in nessun annuncio. Il trigger e quello della
-- 6d-1 con la verifica di classe in piu.
create or replace function public.listings_bottiglia_idonea()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_owner   uuid;
  v_stato   public.bottle_unit_stato;
  v_deleted timestamptz;
  v_ceduta  timestamptz;
  v_classe  public.inventario_classe;
begin
  select bu.owner_id, bu.stato, bu.deleted_at, bu.ceduta_at, bu.inventario
  into v_owner, v_stato, v_deleted, v_ceduta, v_classe
  from public.bottle_units bu
  where bu.id = new.bottle_unit_id;

  if not found then
    raise exception 'Questa bottiglia non esiste.' using errcode = 'P0001';
  end if;

  if v_owner is distinct from new.seller_id then
    raise exception 'Il venditore deve essere il proprietario della bottiglia.'
      using errcode = '42501';
  end if;

  if v_classe <> 'personale' and (
    tg_op = 'INSERT' or new.bottle_unit_id is distinct from old.bottle_unit_id
  ) then
    raise exception 'I prodotti Partner non si mettono in vendita da qui.'
      using errcode = 'P0001', hint = 'partner_vendita_non_disponibile';
  end if;

  if new.stato not in (
    'bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato'
  ) then
    return new;
  end if;

  if v_deleted is not null then
    raise exception 'Questa bottiglia non è più nella tua cantina.'
      using errcode = 'P0001';
  end if;
  if v_ceduta is not null then
    raise exception 'Questa bottiglia è già stata venduta: non può tornare in vendita.'
      using errcode = 'P0001';
  end if;
  if v_stato <> 'chiusa' then
    raise exception 'Una bottiglia % non si può mettere in vendita.', v_stato
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

-- Analitica del patrimonio: solo inventario personale. Il corpo e quello della
-- D3-B (20260826163000) con il filtro di classe e il formato dell'unita.
create or replace function public.cellar_portfolio_analitica()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := auth.uid();
  v_posizioni jsonb;
  v_storico   jsonb;
begin
  if v_uid is null then
    raise exception 'Devi accedere per vedere l''andamento della tua Cantina.'
      using errcode = '42501';
  end if;

  with posseduta as (
    select bu.*
    from public.bottle_units bu
    where bu.owner_id = v_uid
      and bu.inventario = 'personale'
  ),
  acquisto as (
    select
      p.id            as bottle_unit_id,
      o.id            as order_id,
      o.prezzo_cents  as prezzo_venditore_cents,
      pay.amount_cents + o.balance_applied_cents          as pagato_lordo_cents,
      pay.amount_refunded_cents + o.balance_rimborsato_cents as rimborsato_cents,
      case
        when pay.order_id is not null
          then greatest(pay.amount_cents - pay.amount_refunded_cents, 0)
             + greatest(o.balance_applied_cents - o.balance_rimborsato_cents, 0)
        else null
      end                       as esborso_netto_cents,
      o.paid_at
    from posseduta p
    join public.orders o
      on o.buyer_bottle_unit_id = p.id
     and o.buyer_id = v_uid
    left join public.payments pay
      on pay.order_id = o.id
     and pay.stato in ('paid', 'partially_refunded', 'refunded')
     and o.paid_at is not null
  ),
  vendita as (
    select distinct on (p.id)
      p.id           as bottle_unit_id,
      o.id           as order_id,
      o.stato::text  as order_stato,
      po.stato::text as payout_stato,
      case
        when o.balance_released_at is not null then o.prezzo_cents
        when po.stato = 'trasferito' and po.transferred_at is not null
          then po.amount_cents
        else null
      end            as incassato_cents,
      case
        when o.balance_released_at is not null then o.balance_released_at
        when po.stato = 'trasferito' and po.transferred_at is not null
          then po.transferred_at
        else null
      end            as incassato_at
    from posseduta p
    join public.orders o
      on o.seller_bottle_unit_id = p.id
     and o.seller_id = v_uid
    left join public.payouts po
      on po.order_id = o.id
     and po.seller_id = v_uid
    order by
      p.id,
      (o.balance_released_at is not null
       or (po.stato = 'trasferito' and po.transferred_at is not null)) desc nulls last,
      o.created_at desc
  ),
  riferimento as (
    select distinct on (s.wine_id, s.formato)
      s.wine_id, s.formato, s.mediana_cents, s.comparabili, s.observed_at
    from public.wine_reference_snapshots s
    where s.wine_id in (select wine_id from posseduta)
    order by s.wine_id, s.formato, s.observed_at desc, s.created_at desc
  )
  select coalesce(jsonb_agg(riga order by ordinamento, riga->>'bottleUnitId'), '[]'::jsonb)
  into v_posizioni
  from (
    select coalesce(a.paid_at, p.acquired_at) as ordinamento, jsonb_build_object(
      'bottleUnitId',        p.id,
      'wineId',              p.wine_id,
      'wineSlug',            w.slug,
      'produttore',          w.produttore,
      'nome',                w.nome,
      'annata',              w.annata,
      'tipo',                w.tipo,
      'formato',             p.formato,
      'stato',               p.stato::text,
      'acquiredAt',          coalesce(a.paid_at, p.acquired_at),
      'acquisizioneFonte',   case
                               when a.order_id is not null then 'acquisto_vinea'
                               else p.acquisition_fonte::text
                             end,
      'costoManualeCents',   case
                               when a.order_id is not null then null
                               else p.acquisition_cost_cents
                             end,
      'ordineAcquistoId',    a.order_id,
      'acquistoPrezzoVenditoreCents', a.prezzo_venditore_cents,
      'acquistoLordoCents',  a.pagato_lordo_cents,
      'acquistoRimborsoCents', a.rimborsato_cents,
      'acquistoNettoCents',  a.esborso_netto_cents,
      'ordineVenditaId',     v.order_id,
      'venditaStato',        v.order_stato,
      'venditaPayoutStato',  v.payout_stato,
      'venditaIncassoCents', v.incassato_cents,
      'venditaIncassoAt',    v.incassato_at,
      'cedutaAt',            p.ceduta_at,
      'deletedAt',           p.deleted_at,
      'consumedAt',          p.consumed_at,
      'riferimentoCents',    r.mediana_cents,
      'riferimentoComparabili', r.comparabili,
      'riferimentoAt',       r.observed_at
    ) as riga
    from posseduta p
    join public.wines w on w.id = p.wine_id
    left join acquisto a on a.bottle_unit_id = p.id
    left join vendita  v on v.bottle_unit_id = p.id
    left join riferimento r
      on r.wine_id = p.wine_id
     and r.formato = p.formato
  ) as righe;

  select coalesce(jsonb_agg(riga order by ordinamento), '[]'::jsonb)
  into v_storico
  from (
    select s.observed_at as ordinamento, jsonb_build_object(
      'wineId',       s.wine_id,
      'formato',      s.formato,
      'medianaCents', s.mediana_cents,
      'comparabili',  s.comparabili,
      'observedAt',   s.observed_at
    ) as riga
    from public.wine_reference_snapshots s
    where s.wine_id in (
      select bu.wine_id
      from public.bottle_units bu
      where bu.owner_id = v_uid
        and bu.inventario = 'personale'
    )
  ) as serie;

  return jsonb_build_object(
    'generatoAt', now(),
    'posizioni',  coalesce(v_posizioni, '[]'::jsonb),
    'storico',    coalesce(v_storico, '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Privilegi delle porte nuove: nessuna ad anon, nessuna a service_role.
-- ---------------------------------------------------------------------------

revoke all on function public.cellar_bottiglie_aggiungi(
  text, text, integer, text, text, text, integer, text,
  public.bottle_unit_visibilita, text[], integer, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.cellar_bottiglie_aggiungi(
  text, text, integer, text, text, text, integer, text,
  public.bottle_unit_visibilita, text[], integer, timestamptz
) to authenticated;

revoke all on function public.scorte_partner_aggiungi(
  text, text, integer, text, text, text, integer, text, text[]
) from public, anon, authenticated, service_role;
grant execute on function public.scorte_partner_aggiungi(
  text, text, integer, text, text, text, integer, text, text[]
) to authenticated;
