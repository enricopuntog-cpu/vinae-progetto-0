-- ===========================================================================
-- D3-B — Contabilità della Cantina, valore nel tempo, performance netta
-- ===========================================================================
--
-- Questa migrazione è ADDITIVA. Non tocca checkout, pagamenti, payout runner,
-- scheduler, né la semantica di D3-A. Aggiunge cinque cose, in quest'ordine:
--
--   [1] I fatti di acquisizione su bottle_units (quando, da dove, a quanto).
--   [2] Il timestamp autoritativo di consumo, oggi inesistente.
--   [3] L'estensione dell'unico scrittore di Cantina, senza overload ambigui.
--   [4] Gli snapshot globali del riferimento Vinea per (vino, formato),
--       SOLO in avanti.
--   [5] L'unica porta di lettura owner-only dell'analitica di portafoglio.
--
-- Tre regole attraversano tutto il file e vanno lette prima del resto.
--
-- REGOLA 1 — NULL è "sconosciuto", 0 è "zero euro".
-- `acquisition_cost_cents` è nullable di proposito. Una bottiglia legacy non ha
-- un costo: non ne ha uno pari a zero, non ne ha uno stimato, non ne ha uno
-- dedotto dal prezzo di un annuncio. Ha NULL. Chi legge deve escluderla dal
-- calcolo e contarla nella copertura, mai sommarla come zero. Zero resta un
-- valore lecito e distinto: un regalo è costato davvero zero.
--
-- REGOLA 2 — L'origine Vinea non si scrive, si deriva.
-- Quando un pagamento si regola, il percorso ordini crea la bottle_unit
-- dell'acquirente e la lega a `orders.buyer_bottle_unit_id`. Quel legame è già
-- la verità, ed è scritto da codice che questa migrazione non ha il permesso di
-- modificare. Duplicarlo in una colonna enum qui creerebbe una seconda
-- sorgente, che prima o poi divergerebbe. Perciò l'enum di provenienza ha due
-- sole etichette — `sconosciuta` e `manuale` — e l'acquisto Vinea è derivato in
-- lettura dal legame con l'ordine. Per la stessa ragione un'unità nata da un
-- acquisto Vinea non riceve mai un costo manuale: l'importo economico è già
-- nel pagamento, e sommarli lo conterebbe due volte.
--
-- REGOLA 3 — Lo storico del riferimento nasce oggi.
-- Non esiste alcuna serie storica del riferimento Vinea prima di questa
-- migrazione, e non è ricostruibile: le osservazioni di Price Intelligence 1A
-- sono i singoli prezzi richiesti, non la mediana dei comparabili attivi a una
-- certa data, e reggerle all'indietro produrrebbe una curva inventata. La
-- migrazione crea perciò UN SOLO snapshot per vino/formato, quello corrente,
-- con `observed_at = now()`. Prima di quel punto lo storico non è "vuoto": è
-- non disponibile, ed è un'informazione diversa che la UI deve dire.
--
-- Riferimenti: docs/ROADMAP_V1.md, CLAUDE.md (invarianti PostgreSQL), e la
-- migrazione 20260824120000 di Price Intelligence 1A, di cui questo file imita
-- deliberatamente la forma append-only.


-- ---------------------------------------------------------------------------
-- [1] I fatti di acquisizione
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public'
      and t.typname = 'bottle_acquisition_fonte'
  ) then
    create type public.bottle_acquisition_fonte as enum (
      'sconosciuta',
      'manuale'
    );
  end if;
end;
$$;

comment on type public.bottle_acquisition_fonte is
  'Come Vinea è venuta a sapere del costo di acquisizione di una bottiglia. '
  '`sconosciuta`: nessuno l''ha mai dichiarato, e il costo resta NULL. '
  '`manuale`: il proprietario l''ha dichiarato aggiungendola in Cantina. '
  'L''acquisto su Vinea NON è un''etichetta di questo enum: si deriva dal '
  'legame orders.buyer_bottle_unit_id, che è già la sorgente autorevole.';

alter table public.bottle_units
  add column if not exists acquired_at timestamptz,
  add column if not exists acquisition_fonte public.bottle_acquisition_fonte
    not null default 'sconosciuta',
  add column if not exists acquisition_cost_cents integer;

-- Le bottiglie che esistevano prima di questa migrazione non hanno un costo e
-- non ne riceveranno uno: restano `sconosciuta` con costo NULL. Ricevono però
-- una data di acquisizione, perché `created_at` è la sola data reale che
-- Vinea possiede su di loro ed è una data di ingresso in Cantina onesta.
-- Non è una stima: è il momento in cui la bottiglia è comparsa.
update public.bottle_units
set acquired_at = created_at
where acquired_at is null;

alter table public.bottle_units
  alter column acquired_at set default now();

alter table public.bottle_units
  alter column acquired_at set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'bottle_units_acquisition_cost_non_negativo'
      and conrelid = 'public.bottle_units'::regclass
  ) then
    alter table public.bottle_units
      add constraint bottle_units_acquisition_cost_non_negativo
      check (
        acquisition_cost_cents is null
        or (acquisition_cost_cents >= 0 and acquisition_cost_cents <= 100000000)
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'bottle_units_acquired_at_plausibile'
      and conrelid = 'public.bottle_units'::regclass
  ) then
    alter table public.bottle_units
      add constraint bottle_units_acquired_at_plausibile
      check (acquired_at >= timestamptz '1900-01-01');
  end if;
end;
$$;

comment on column public.bottle_units.acquired_at is
  'Quando la bottiglia è entrata nel possesso del proprietario. Per le unità '
  'preesistenti vale created_at, l''unica data reale disponibile. Il futuro è '
  'rifiutato dal trigger di ciclo di vita, non da un CHECK, perché now() non è '
  'immutabile.';
comment on column public.bottle_units.acquisition_fonte is
  'Provenienza del dato di costo, non provenienza della bottiglia. Vedi il '
  'commento del tipo: l''acquisto Vinea si deriva dall''ordine.';
comment on column public.bottle_units.acquisition_cost_cents is
  'Costo di acquisizione dichiarato, in centesimi. NULL significa SCONOSCIUTO '
  'e non zero: chi calcola deve escludere la bottiglia e contarla nella '
  'copertura. Resta NULL per le unità nate da un acquisto Vinea, il cui '
  'importo vive nel pagamento.';

-- Le colonne nuove non entrano in nessun GRANT di scrittura client: si passa
-- dalla RPC. `bottle_units` ha già solo `grant update (stato, visibilita,
-- deleted_at)`, quindi non c'è nulla da revocare, ma l'asserzione qui sotto
-- rende il fatto verificabile e fa fallire la migrazione se un giorno
-- qualcuno allargasse quel grant senza accorgersene.
do $$
declare
  v_colonne text;
begin
  select string_agg(distinct c.column_name, ', ' order by c.column_name)
  into v_colonne
  from information_schema.column_privileges c
  where c.table_schema = 'public'
    and c.table_name = 'bottle_units'
    and c.privilege_type in ('INSERT', 'UPDATE')
    and c.grantee in ('anon', 'authenticated')
    and c.column_name in (
      'acquired_at', 'acquisition_fonte', 'acquisition_cost_cents'
    );

  if v_colonne is not null then
    raise exception
      'I fatti di acquisizione non devono essere scrivibili dal client: %',
      v_colonne
      using errcode = 'P0001';
  end if;
end;
$$;


-- ---------------------------------------------------------------------------
-- [2] Il consumo ha finalmente una data
-- ---------------------------------------------------------------------------
--
-- Fino a oggi `stato = 'consumata'` era l'unica traccia del consumo: uno stato
-- senza data, che non dice quando la bottiglia è uscita dal portafoglio. Per
-- una serie storica del valore quella data è indispensabile, perché una
-- bottiglia consumata smette di essere posseduta da quel momento — non da
-- sempre e non da oggi.
--
-- Consumo, cessione e cancellazione restano tre cose diverse e non si
-- sovrascrivono: `consumed_at` è il consumo, `ceduta_at` la vendita conclusa,
-- `deleted_at` la rimozione del dato. Una bottiglia consumata non ha prodotto
-- incasso; una ceduta sì, ma solo se il payout è stato trasferito; una
-- cancellata non è né l'una né l'altra: resta visibile soltanto al proprietario
-- nel modello analitico per chiudere correttamente lo storico a `deleted_at`, ma
-- il modulo puro la esclude dalle posizioni correnti.

alter table public.bottle_units
  add column if not exists consumed_at timestamptz;

comment on column public.bottle_units.consumed_at is
  'Quando la bottiglia è stata consumata. Scritto una volta sola dal trigger '
  'alla prima transizione verso `consumata` e mai riscritto. Non è ceduta_at '
  '(vendita) né deleted_at (rimozione del dato).';

create or replace function private.bottle_units_ciclo_di_vita()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Una data di acquisizione nel futuro renderebbe negativa qualsiasi durata di
  -- possesso e farebbe comparire punti nel domani sul grafico. Si rifiuta,
  -- invece di correggerla in silenzio.
  if new.acquired_at > now() then
    raise exception 'La data di acquisto non può essere nel futuro.'
      using errcode = 'P0001';
  end if;

  if tg_op = 'INSERT' then
    -- `consumed_at` non è mai un input, neppure per uno scrittore privilegiato.
    -- Se la prima riga nasce già consumata, il solo fatto autorevole disponibile
    -- è questo INSERT e la data nasce adesso; in ogni altro stato resta NULL.
    new.consumed_at := case
      when new.stato = 'consumata' then now()
      else null
    end;
    return new;
  end if;

  -- Set-once. Se il consumo era già datato, quella data vince su qualsiasi
  -- valore in arrivo: un UPDATE successivo non riscrive la storia. Se invece è
  -- la prima transizione verso `consumata`, la data nasce adesso.
  if old.consumed_at is not null then
    new.consumed_at := old.consumed_at;
  elsif new.stato = 'consumata' and old.stato is distinct from 'consumata' then
    new.consumed_at := now();
  else
    new.consumed_at := old.consumed_at;
  end if;

  -- `acquired_at` non è nei grant client e non deve muoversi da sola.
  new.acquired_at := old.acquired_at;

  return new;
end;
$$;

comment on function private.bottle_units_ciclo_di_vita() is
  'Datazione set-once del consumo e difesa della data di acquisizione. '
  'Non tocca ceduta_at, che resta del trigger di vendita.';

revoke execute on function private.bottle_units_ciclo_di_vita()
  from public, anon, authenticated;

drop trigger if exists bottle_units_ciclo_di_vita on public.bottle_units;
create trigger bottle_units_ciclo_di_vita
  before insert or update on public.bottle_units
  for each row
  execute function private.bottle_units_ciclo_di_vita();


-- ---------------------------------------------------------------------------
-- [3] Lo scrittore di Cantina accetta prezzo e data di acquisto
-- ---------------------------------------------------------------------------
--
-- Aggiungere due parametri con DEFAULT a una funzione esistente NON è una
-- `create or replace`: cambia la firma, e PostgreSQL si ritroverebbe due
-- funzioni omonime. PostgREST, che risolve per nome, davanti a due candidate
-- compatibili con sette argomenti nominali risponderebbe PGRST203 e la
-- Cantina smetterebbe di accettare bottiglie. Si elimina quindi la vecchia
-- firma e se ne crea UNA sola: il chiamante legacy che passa sette parametri
-- continua a funzionare perché i due nuovi hanno un default.

drop function if exists public.cellar_bottiglia_aggiungi(
  text, text, integer, text, text, public.bottle_unit_visibilita, text[]
);

create function public.cellar_bottiglia_aggiungi(
  p_produttore text,
  p_nome text,
  p_annata integer,
  p_regione text,
  p_tipo text,
  p_visibilita public.bottle_unit_visibilita default 'privata',
  p_immagini text[] default '{}',
  p_acquisition_cost_cents integer default null,
  p_acquired_at timestamptz default null
)
returns table (bottle_unit_id uuid, wine_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := auth.uid();
  v_wine      uuid;
  v_bottle    uuid;
  v_immagine  text;
  v_fonte     public.bottle_acquisition_fonte;
  v_acquisito timestamptz;
begin
  if v_uid is null then
    raise exception 'Devi accedere per aggiungere una bottiglia.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid) then
    raise exception 'Il tuo profilo non è ancora completo.'
      using errcode = 'P0001';
  end if;
  if p_visibilita not in ('privata', 'cantina_pubblica') then
    raise exception 'Visibilità della bottiglia non valida.' using errcode = 'P0001';
  end if;
  if array_length(p_immagini, 1) > 6 then
    raise exception 'Massimo 6 fotografie per bottiglia.' using errcode = 'P0001';
  end if;

  foreach v_immagine in array coalesce(p_immagini, '{}'::text[]) loop
    if v_immagine !~ ('^' || v_uid::text || '/[0-9a-f-]{36}\.(jpg|jpeg|png|webp|avif)$') then
      raise exception 'Fotografia non valida: %', v_immagine using errcode = 'P0001';
    end if;
    if not exists (
      select 1
      from storage.objects o
      where o.bucket_id = 'cantina'
        and o.name = v_immagine
    ) then
      raise exception 'La fotografia non appartiene al bucket privato della Cantina.'
        using errcode = 'P0001';
    end if;
  end loop;

  -- Il costo è facoltativo, ma se arriva dev'essere un costo. Un valore
  -- negativo non è un dato incerto da accogliere e correggere dopo: è un dato
  -- impossibile, e passerebbe nel calcolo della performance invertendone il
  -- segno. Si rifiuta con un messaggio leggibile invece di lasciare emergere
  -- il testo del CHECK.
  if p_acquisition_cost_cents is not null then
    if p_acquisition_cost_cents < 0 then
      raise exception 'Il prezzo di acquisto non può essere negativo.'
        using errcode = 'P0001';
    end if;
    if p_acquisition_cost_cents > 100000000 then
      raise exception 'Il prezzo di acquisto indicato non è plausibile.'
        using errcode = 'P0001';
    end if;
  end if;

  if p_acquired_at is not null then
    if p_acquired_at > now() then
      raise exception 'La data di acquisto non può essere nel futuro.'
        using errcode = 'P0001';
    end if;
    if p_acquired_at < timestamptz '1900-01-01' then
      raise exception 'La data di acquisto indicata non è plausibile.'
        using errcode = 'P0001';
    end if;
  end if;

  v_acquisito := coalesce(p_acquired_at, now());

  -- Entrambi i rami sono castati: un CASE di letterali stringa si risolve come
  -- `text` e assegnarlo a una colonna enum solleva 42804. Vedi CLAUDE.md.
  v_fonte := case
    when p_acquisition_cost_cents is not null or p_acquired_at is not null
      then 'manuale'::public.bottle_acquisition_fonte
    else 'sconosciuta'::public.bottle_acquisition_fonte
  end;

  v_wine := private.catalogo_risolvi_vino_utente(
    p_produttore, p_nome, p_annata, p_regione, p_tipo
  );

  insert into public.bottle_units (
    owner_id, wine_id, stato, visibilita, immagini,
    acquired_at, acquisition_fonte, acquisition_cost_cents
  )
  values (
    v_uid, v_wine, 'chiusa', p_visibilita, coalesce(p_immagini, '{}'::text[]),
    v_acquisito, v_fonte, p_acquisition_cost_cents
  )
  returning id into v_bottle;

  return query select v_bottle, v_wine;
end;
$$;

comment on function public.cellar_bottiglia_aggiungi(
  text, text, integer, text, text, public.bottle_unit_visibilita, text[],
  integer, timestamptz
) is
  'Aggiunge una bottle_unit privata o di cantina pubblica senza creare un '
  'annuncio. Owner e autore derivano da auth.uid(); le foto restano nel '
  'bucket privato cantina. Prezzo e data di acquisto sono facoltativi: '
  'omessi, la provenienza del costo resta `sconosciuta` e il costo NULL.';

revoke execute on function public.cellar_bottiglia_aggiungi(
  text, text, integer, text, text, public.bottle_unit_visibilita, text[],
  integer, timestamptz
) from public, anon;
grant execute on function public.cellar_bottiglia_aggiungi(
  text, text, integer, text, text, public.bottle_unit_visibilita, text[],
  integer, timestamptz
) to authenticated;

-- Se restasse più di una funzione con questo nome, PostgREST non saprebbe
-- quale chiamare. L'asserzione fa fallire la migrazione invece di lasciare
-- scoprire l'ambiguità al primo utente che aggiunge una bottiglia.
do $$
declare
  v_n integer;
begin
  select count(*) into v_n
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'cellar_bottiglia_aggiungi';

  if v_n <> 1 then
    raise exception
      'cellar_bottiglia_aggiungi deve avere una sola firma, trovate %.', v_n
      using errcode = 'P0001';
  end if;
end;
$$;


-- ---------------------------------------------------------------------------
-- [4] Lo storico del riferimento Vinea, solo in avanti
-- ---------------------------------------------------------------------------
--
-- Il riferimento è quello di D3-A e non un altro: mediana dei prezzi richiesti
-- degli annunci ATTIVI, stesso vino, stesso formato, almeno tre comparabili.
-- Sotto la soglia non c'è una stima meno affidabile: non c'è un riferimento.
-- `prezzo_mercato_cents`, il prezzo del singolo annuncio e l'ultima
-- osservazione grezza non sono e non diventano un valore di portafoglio.
--
-- Gli snapshot sono GLOBALI per (wine_id, formato) e non per utente: il
-- riferimento è una proprietà del vino sul mercato interno, non della cantina
-- di qualcuno. Duplicarli per proprietario moltiplicherebbe le righe per il
-- numero di possessori e li farebbe divergere.

create table if not exists public.wine_reference_snapshots (
  id uuid primary key default gen_random_uuid(),

  wine_id uuid not null,

  -- Copiato come in Price Intelligence 1A: `wines.formato` ha un default e non
  -- è nella chiave di unicità del vino, quindi può cambiare. Uno snapshot
  -- ricalcolato con il formato di oggi mescolerebbe serie diverse.
  formato text not null check (length(trim(formato)) > 0),

  -- NULL = il riferimento non è disponibile a questo istante, perché i
  -- comparabili sono scesi sotto la soglia. È un'informazione, non un buco:
  -- senza questa riga la serie continuerebbe a mostrare l'ultimo valore valido
  -- come se fosse ancora vero.
  mediana_cents integer check (mediana_cents is null or mediana_cents > 0),
  minimo_cents  integer check (minimo_cents is null or minimo_cents > 0),
  massimo_cents integer check (massimo_cents is null or massimo_cents > 0),

  comparabili integer not null check (comparabili >= 0),

  valuta text not null default 'EUR' check (valuta = 'EUR'),

  observed_at timestamptz not null default now(),
  created_at  timestamptz not null default now(),

  constraint wine_reference_snapshots_soglia check (
    (comparabili >= 3 and mediana_cents is not null
      and minimo_cents is not null and massimo_cents is not null)
    or
    (comparabili < 3 and mediana_cents is null
      and minimo_cents is null and massimo_cents is null)
  ),
  constraint wine_reference_snapshots_range check (
    mediana_cents is null
    or (minimo_cents <= mediana_cents and mediana_cents <= massimo_cents)
  )
);

comment on table public.wine_reference_snapshots is
  'Storico SOLO IN AVANTI del riferimento Vinea per vino e formato. Una riga '
  'nasce quando il riferimento cambia davvero, mai a intervalli e mai '
  'all''apertura di una pagina. Non esiste alcuna riga anteriore alla '
  'migrazione che ha creato la tabella: lo storico precedente non è vuoto, è '
  'non disponibile.';
comment on column public.wine_reference_snapshots.mediana_cents is
  'Mediana dei prezzi richiesti degli annunci attivi comparabili. NULL quando '
  'i comparabili sono meno di tre: riferimento non disponibile, non zero.';
comment on column public.wine_reference_snapshots.comparabili is
  'Quanti annunci attivi hanno prodotto questo snapshot. Sotto tre la mediana '
  'è NULL per costruzione (vincolo _soglia).';

create index if not exists wine_reference_snapshots_serie_idx
  on public.wine_reference_snapshots (wine_id, formato, observed_at desc);

alter table public.wine_reference_snapshots enable row level security;

-- Nessun accesso diretto dal client, in nessun ruolo. Lo storico si legge
-- soltanto dalla porta di analitica del blocco [5], che filtra per
-- proprietario. RLS attiva senza policy chiude anche la strada a un GRANT
-- aggiunto per distrazione.
revoke all on public.wine_reference_snapshots from public, anon, authenticated;

create or replace function private.wine_reference_snapshots_append_only()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'Lo storico del riferimento è solo in aggiunta: % rifiutato.',
    tg_op
    using errcode = 'P0001';
end;
$$;

revoke execute on function private.wine_reference_snapshots_append_only()
  from public, anon, authenticated;

drop trigger if exists wine_reference_snapshots_no_update
  on public.wine_reference_snapshots;
create trigger wine_reference_snapshots_no_update
  before update on public.wine_reference_snapshots
  for each row execute function private.wine_reference_snapshots_append_only();

drop trigger if exists wine_reference_snapshots_no_delete
  on public.wine_reference_snapshots;
create trigger wine_reference_snapshots_no_delete
  before delete on public.wine_reference_snapshots
  for each row execute function private.wine_reference_snapshots_append_only();

drop trigger if exists wine_reference_snapshots_no_truncate
  on public.wine_reference_snapshots;
create trigger wine_reference_snapshots_no_truncate
  before truncate on public.wine_reference_snapshots
  for each statement execute function private.wine_reference_snapshots_append_only();


-- L'unico scrittore. Ricalcola il riferimento corrente di un vino e lo
-- registra SOLO se è diverso dall'ultimo registrato: senza questo confronto
-- ogni modifica irrilevante di un annuncio genererebbe una riga, e la serie
-- diventerebbe un registro di eventi invece che una storia di valori.
create or replace function private.wine_reference_snapshot_registra(
  p_wine_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_formato    text;
  v_n          integer;
  v_mediana    integer;
  v_minimo     integer;
  v_massimo    integer;
  v_ultimo     public.wine_reference_snapshots%rowtype;
begin
  if p_wine_id is null then
    return;
  end if;

  select coalesce(nullif(btrim(w.formato), ''), '0,75 L')
  into v_formato
  from public.wines w
  where w.id = p_wine_id;

  if v_formato is null then
    return;
  end if;

  -- Stessa semantica del modulo puro di D3-A: solo `attivo`, un prezzo per
  -- annuncio, mediana con arrotondamento a intero. `percentile_cont` restituisce
  -- l'elemento centrale su un numero dispari e la media dei due centrali su un
  -- numero pari, che è esattamente ciò che fa medianaCents().
  select
    count(*)::integer,
    round(percentile_cont(0.5) within group (order by l.prezzo_cents))::integer,
    min(l.prezzo_cents),
    max(l.prezzo_cents)
  into v_n, v_mediana, v_minimo, v_massimo
  from public.listings l
  join public.bottle_units bu on bu.id = l.bottle_unit_id
  where bu.wine_id = p_wine_id
    and l.stato = 'attivo';

  v_n := coalesce(v_n, 0);

  if v_n < 3 then
    v_mediana := null;
    v_minimo  := null;
    v_massimo := null;
  end if;

  select *
  into v_ultimo
  from public.wine_reference_snapshots s
  where s.wine_id = p_wine_id
    and s.formato = v_formato
  order by s.observed_at desc, s.created_at desc
  limit 1;

  if found then
    if v_ultimo.comparabili = v_n
       and v_ultimo.mediana_cents is not distinct from v_mediana
       and v_ultimo.minimo_cents is not distinct from v_minimo
       and v_ultimo.massimo_cents is not distinct from v_massimo then
      return;
    end if;
  elsif v_n < 3 then
    -- Non c'è ancora storia e non c'è ancora riferimento. Aprire la serie con
    -- una riga vuota direbbe "misurato, non disponibile" dove la verità è
    -- "mai misurato".
    return;
  end if;

  insert into public.wine_reference_snapshots (
    wine_id, formato, mediana_cents, minimo_cents, massimo_cents,
    comparabili, observed_at
  )
  values (
    p_wine_id, v_formato, v_mediana, v_minimo, v_massimo, v_n, now()
  );
end;
$$;

comment on function private.wine_reference_snapshot_registra(uuid) is
  'Unico scrittore dello storico del riferimento. Registra solo un cambiamento '
  'reale del riferimento corrente. Non è una RPC client.';

revoke execute on function private.wine_reference_snapshot_registra(uuid)
  from public, anon, authenticated;


create or replace function private.listings_riferimento_sync()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_wine   uuid;
  v_bottle uuid;
begin
  -- Il vino si prende dalla bottiglia dell'annuncio. Su DELETE la riga NEW non
  -- è assegnata e leggerne un campo solleverebbe un errore, quindi il ramo si
  -- sceglie sull'operazione e non con un coalesce.
  if tg_op = 'DELETE' then
    v_bottle := old.bottle_unit_id;
  else
    v_bottle := new.bottle_unit_id;
  end if;

  select bu.wine_id
  into v_wine
  from public.bottle_units bu
  where bu.id = v_bottle;

  perform private.wine_reference_snapshot_registra(v_wine);

  return null;
end;
$$;

comment on function private.listings_riferimento_sync() is
  'Ricalcola il riferimento del vino quando un annuncio entra o esce da '
  '`attivo` o ne cambia il prezzo. La decisione se scrivere sta nello '
  'scrittore, che confronta con l''ultimo snapshot.';

revoke execute on function private.listings_riferimento_sync()
  from public, anon, authenticated;

drop trigger if exists listings_riferimento_sync on public.listings;
create trigger listings_riferimento_sync
  after insert or delete on public.listings
  for each row
  execute function private.listings_riferimento_sync();

drop trigger if exists listings_riferimento_sync_update on public.listings;
create trigger listings_riferimento_sync_update
  after update of stato, prezzo_cents on public.listings
  for each row
  when (
    old.stato is distinct from new.stato
    or old.prezzo_cents is distinct from new.prezzo_cents
  )
  execute function private.listings_riferimento_sync();


-- Snapshot iniziale: SOLO lo stato corrente, con `observed_at = now()`.
-- Nessuna riga datata all'indietro. Se oggi un vino non ha tre comparabili
-- attivi, non riceve alcuna riga e il suo storico comincerà il giorno in cui
-- il riferimento esisterà davvero.
do $$
declare
  v_wine uuid;
begin
  for v_wine in
    select distinct bu.wine_id
    from public.listings l
    join public.bottle_units bu on bu.id = l.bottle_unit_id
    where l.stato = 'attivo'
  loop
    perform private.wine_reference_snapshot_registra(v_wine);
  end loop;
end;
$$;


-- ---------------------------------------------------------------------------
-- [5] La porta di lettura dell'analitica di portafoglio
-- ---------------------------------------------------------------------------
--
-- Una sola chiamata restituisce tutto ciò che serve alla Cantina: le posizioni
-- del proprietario autenticato e lo storico del riferimento dei suoi vini.
-- È un'unica porta di proposito — una query per bottiglia o una per punto del
-- grafico sarebbe un N+1 su una pagina che si apre sempre.
--
-- Owner-only, senza eccezioni: `auth.uid()` è l'unico filtro di proprietà, non
-- arriva dal chiamante e non è sostituibile con un parametro. `anon` non ha
-- l'EXECUTE. Il client non vede mai `service_role`.
--
-- La funzione è SECURITY DEFINER perché deve leggere `payments` e `payouts`,
-- su cui l'utente non ha i grant necessari per riga e colonna. Proprio per
-- questo restituisce un elenco chiuso di campi, e non le righe di quelle
-- tabelle: nessuna colonna di pagamento nuova diventerà visibile da sola.
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
    -- Le righe cancellate restano nel modello owner-only: `deleted_at` è un
    -- confine storico reale e serve a mostrare che la posizione era eleggibile
    -- prima della rimozione. Sarà il modulo puro a escluderle dal valore corrente
    -- e a chiuderne la serie in quel momento, senza confondere cancellazione,
    -- vendita e consumo.
  ),
  acquisto as (
    -- Acquisto su Vinea. L'uscita di cassa dell'acquirente è quanto ha pagato
    -- meno quanto gli è stato rimborsato: un rimborso RIDUCE l'esborso, e
    -- ignorarlo gonfierebbe il capitale investito e schiaccerebbe la
    -- performance. Il prezzo del venditore e il totale addebitato restano
    -- distinti e riportati a parte: non sono la stessa grandezza.
    select
      p.id            as bottle_unit_id,
      o.id            as order_id,
      o.prezzo_cents  as prezzo_venditore_cents,
      pay.amount_cents          as pagato_lordo_cents,
      pay.amount_refunded_cents as rimborsato_cents,
      case
        when pay.order_id is not null
          then greatest(pay.amount_cents - pay.amount_refunded_cents, 0)
        else null
      end                       as esborso_netto_cents,
      o.paid_at
    from posseduta p
    join public.orders o
      on o.buyer_bottle_unit_id = p.id
     and o.buyer_id = v_uid
    left join public.payments pay
      on pay.order_id = o.id
     -- Una riga di checkout non è ancora un esborso. L'importo diventa un fatto
     -- economico solo dopo il pagamento firmato; gli stati di rimborso restano
     -- validi perché riducono quel fatto, fino anche a zero. `paid_at` chiude il
     -- caso impossibile di una riga payment promossa senza ordine pagato.
     and pay.stato in ('paid', 'partially_refunded', 'refunded')
     and o.paid_at is not null
  ),
  vendita as (
    -- Incasso realizzato. Non è `orders.prezzo_cents`, che è il prezzo
    -- richiesto e non il denaro arrivato; non è un payout previsto o
    -- trattenuto. È l'importo effettivamente trasferito, e solo quando lo
    -- stato lo dice, la data lo conferma e il payout è intestato a chi legge.
    --
    -- `seller_bottle_unit_id` non è unico: una bottiglia annullata e rimessa in
    -- vendita ha più ordini. Senza `distinct on` la stessa bottiglia
    -- comparirebbe più volte fra le posizioni e il suo riferimento verrebbe
    -- sommato due volte. Vince l'ordine che ha prodotto un incasso davvero
    -- trasferito; a parità, il più recente.
    select distinct on (p.id)
      p.id           as bottle_unit_id,
      o.id           as order_id,
      o.stato::text  as order_stato,
      po.stato::text as payout_stato,
      case
        when po.stato = 'trasferito' and po.transferred_at is not null
          then po.amount_cents
        else null
      end            as incassato_cents,
      case
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
      (po.stato = 'trasferito' and po.transferred_at is not null) desc nulls last,
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
      'formato',             coalesce(nullif(btrim(w.formato), ''), '0,75 L'),
      'stato',               p.stato::text,
      -- Per una bottiglia comprata su Vinea l'acquisizione economica avviene al
      -- pagamento autorevole dell'ordine. Per le altre resta il fatto manuale o
      -- legacy della bottiglia.
      'acquiredAt',          coalesce(a.paid_at, p.acquired_at),
      -- `acquisto_vinea` è DERIVATO dal legame con l'ordine e non letto da una
      -- colonna: l'ordine è la sorgente autorevole, la colonna enum non la
      -- duplica. Vedi la REGOLA 2 in testa al file.
      'acquisizioneFonte',   case
                               when a.order_id is not null then 'acquisto_vinea'
                               else p.acquisition_fonte::text
                             end,
      -- Il costo manuale è deliberatamente azzerato a NULL quando la bottiglia
      -- viene da un acquisto Vinea: l'importo economico è già nel pagamento, e
      -- sommarli lo conterebbe due volte.
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
      -- NULL significa che per questo vino/formato non esiste ancora alcuno
      -- snapshot reale. Zero resta riservato a una misurazione avvenuta con zero
      -- comparabili dopo l'apertura della serie.
      'riferimentoComparabili', r.comparabili,
      'riferimentoAt',       r.observed_at
    ) as riga
    from posseduta p
    join public.wines w on w.id = p.wine_id
    left join acquisto a on a.bottle_unit_id = p.id
    left join vendita  v on v.bottle_unit_id = p.id
    left join riferimento r
      on r.wine_id = p.wine_id
     and r.formato = coalesce(nullif(btrim(w.formato), ''), '0,75 L')
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
    )
  ) as serie;

  return jsonb_build_object(
    'generatoAt', now(),
    'posizioni',  coalesce(v_posizioni, '[]'::jsonb),
    'storico',    coalesce(v_storico, '[]'::jsonb)
  );
end;
$$;

comment on function public.cellar_portfolio_analitica() is
  'Unica porta di lettura dell''analitica di Cantina del proprietario '
  'autenticato: posizioni con costo, esborso, incasso trasferito, ciclo di '
  'vita e riferimento corrente, più lo storico del riferimento dei suoi vini. '
  'Owner-only via auth.uid(); nessun parametro di proprietà; elenco di campi '
  'chiuso perché legge pagamenti e payout in SECURITY DEFINER.';

revoke execute on function public.cellar_portfolio_analitica()
  from public, anon;
grant execute on function public.cellar_portfolio_analitica() to authenticated;
