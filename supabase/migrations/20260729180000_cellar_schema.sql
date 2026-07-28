-- Fase 6c-1 — Cantina: schema, RLS e funzioni di posizionamento.
--
-- Nessuna interfaccia in questa fase. Qui nascono le tabelle che la 6c-2
-- userà per portare /cantina: ambienti, moduli, posizioni fisiche, più i
-- metadati di bevuta che finora vivevano nei dati mock.
--
-- COSA C'È E PERCHÉ, in breve:
--   wines                  guadagna le colonne di wineMeta (finestra di
--                          bevuta, abbinamenti, servizio). Restano di
--                          catalogo: scrivibili solo dallo staff, com'era.
--   bottle_units           guadagna ciò che è personale della singola unità:
--                          data di apertura pianificata, note, override della
--                          finestra, visibilità del prezzo.
--   cellar_environments    l'ambiente fisico (cantina interrata, cantinetta).
--   cellar_modules         scaffali e casse dentro un ambiente.
--   cellar_slots           dove sta una bottiglia. Una riga = una posizione
--                          OCCUPATA (vedi il commento sulla tabella).
--   public_listings        `quantita` diventa derivata invece che colonna.
--
-- La cantina è privata per definizione: ogni policy parte da lì, e l'unica
-- eccezione è la singola bottiglia dichiarata `cantina_pubblica`.

-- ---------------------------------------------------------------------------
-- wines — metadati di bevuta e abbinamenti
-- ---------------------------------------------------------------------------
-- Erano in frontend-next/src/data/cellar.ts, indicizzati per slug. Sono
-- metadati del vino-annata, non della bottiglia di qualcuno: due persone che
-- possiedono lo stesso Monfortino 2015 leggono la stessa finestra di bevuta.
-- Per questo stanno su `wines` e non su `bottle_units`; ciò che è personale
-- (un override, una nota) sta invece sull'unità, più in basso.
--
-- Restano scrivibili solo da admin o moderator: la policy `wines_write_staff`
-- della 6a copre già queste colonne, e il GRANT della 6a è a livello di
-- tabella, quindi non serve toccare nessun privilegio.

create type public.drink_window_fonte as enum (
  'editorial',    -- dato editoriale
  'ai',           -- suggerito dall'IA
  'personal',     -- personalizzato dall'utente
  'owner',        -- dichiarato dal proprietario
  'unavailable'   -- informazione non disponibile
);

create type public.drink_window_affidabilita as enum ('alta', 'media', 'bassa');

alter table public.wines
  add column finestra_inizio smallint check (finestra_inizio between 1800 and 2200),
  add column finestra_fine smallint check (finestra_fine between 1800 and 2200),
  add column apice_inizio smallint check (apice_inizio between 1800 and 2200),
  add column apice_fine smallint check (apice_fine between 1800 and 2200),
  add column finestra_fonte public.drink_window_fonte not null default 'unavailable',
  add column finestra_affidabilita public.drink_window_affidabilita,
  add column finestra_aggiornata_at date,
  add column temperatura_servizio text not null default '',
  add column decantazione_minuti smallint check (decantazione_minuti between 0 and 600),
  add column calice text not null default '',
  add column occasione text not null default '',
  -- Gli abbinamenti sono un elenco di oggetti (categoria, piatto, livello,
  -- note, emoji, keywords[]): una tabella normalizzata sarebbe più rigorosa,
  -- ma questi dati si leggono sempre interi insieme al vino e non si
  -- interrogano mai per campo. jsonb tiene la forma identica al mock, che è
  -- ciò che permette alla 6c-2 di collegare i componenti esistenti senza
  -- riscriverli.
  add column abbinamenti jsonb not null default '[]'::jsonb;

alter table public.wines
  add constraint wines_finestra_ordinata
    check (finestra_inizio is null or finestra_fine is null
           or finestra_fine >= finestra_inizio),
  add constraint wines_apice_ordinato
    check (apice_inizio is null or apice_fine is null
           or apice_fine >= apice_inizio),
  -- L'apice è un intervallo dentro la finestra, non accanto ad essa.
  add constraint wines_apice_dentro_finestra
    check (
      (apice_inizio is null or finestra_inizio is null or apice_inizio >= finestra_inizio)
      and (apice_fine is null or finestra_fine is null or apice_fine <= finestra_fine)
    ),
  add constraint wines_abbinamenti_elenco
    check (jsonb_typeof(abbinamenti) = 'array');

comment on column public.wines.finestra_inizio is
  'Primo anno in cui il vino si considera pronto. Nullo quando la finestra '
  'non è disponibile: in quel caso l''interfaccia mostra "informazione non '
  'disponibile" invece di inventare un intervallo.';
comment on column public.wines.abbinamenti is
  'Elenco di abbinamenti cibo, stessa forma di FoodPairing in '
  'frontend-next/src/data/cellar.ts. Nei dati d''origine lo stesso elenco è '
  'condiviso fra vini dello stesso stile (i rossi strutturati hanno gli '
  'stessi cinque abbinamenti): qui la condivisione si perde e ogni vino porta '
  'la propria copia. È la conseguenza accettata di tenerli come colonna.';

-- I filtri "pronte ora" e "quando berlo" cercano per intervallo di anni.
create index wines_finestra_idx on public.wines (finestra_inizio, finestra_fine);

-- ---------------------------------------------------------------------------
-- bottle_units — ciò che è personale della singola unità
-- ---------------------------------------------------------------------------

create type public.preferenza_evoluzione as enum ('giovane', 'equilibrato', 'evoluto');
create type public.prezzo_visibilita as enum ('visibile', 'riservato');

alter table public.bottle_units
  add column apertura_pianificata date,
  add column note_personali text not null default '',
  add column prezzo_visibilita public.prezzo_visibilita not null default 'visibile',
  -- Override della finestra di bevuta. Colonne piatte e non jsonb perché la
  -- vista "pronte ora" filtra sull'intervallo efficace, cioè
  -- coalesce(override, valore del vino): con jsonb ogni confronto passerebbe
  -- da un cast, e nessun indice sarebbe utilizzabile.
  add column override_finestra_inizio smallint check (override_finestra_inizio between 1800 and 2200),
  add column override_finestra_fine smallint check (override_finestra_fine between 1800 and 2200),
  add column override_apice_inizio smallint check (override_apice_inizio between 1800 and 2200),
  add column override_apice_fine smallint check (override_apice_fine between 1800 and 2200),
  add column override_preferenza public.preferenza_evoluzione,
  add column override_nota text not null default '';

alter table public.bottle_units
  add constraint bottle_units_override_ordinato
    check (override_finestra_inizio is null or override_finestra_fine is null
           or override_finestra_fine >= override_finestra_inizio);

comment on column public.bottle_units.apertura_pianificata is
  'Data in cui il proprietario ha programmato di aprire la bottiglia. '
  'frontend/docs/DOMAIN_MODEL.md elenca "programmata" fra gli stati: non lo '
  'è, è la presenza di questa data. Lo stato fisico resta chiusa/aperta/'
  'consumata, come deciso in 6a.';

-- Queste colonne non hanno regole di dominio dietro: sono scelte personali del
-- proprietario, e la policy bottle_units_update_own è già sufficiente. Si
-- aggiungono quindi ai GRANT di colonna della 6a. `stato` resta fuori, come
-- prima: l'unica colonna con regole è quella, e non si tocca.
grant insert (
  apertura_pianificata, note_personali, prezzo_visibilita,
  override_finestra_inizio, override_finestra_fine,
  override_apice_inizio, override_apice_fine,
  override_preferenza, override_nota
) on public.bottle_units to authenticated;

grant update (
  apertura_pianificata, note_personali, prezzo_visibilita,
  override_finestra_inizio, override_finestra_fine,
  override_apice_inizio, override_apice_fine,
  override_preferenza, override_nota
) on public.bottle_units to authenticated;

-- ---------------------------------------------------------------------------
-- cellar_environments — l'ambiente fisico
-- ---------------------------------------------------------------------------

create type public.env_forma as enum (
  'parete_lineare', 'scaffalatura_modulare', 'cantinetta', 'cassa_legno', 'nicchia_angolare'
);

create type public.env_tema as enum (
  'moderna', 'rustica', 'classica', 'pietra', 'industriale', 'minimal', 'premium', 'casse'
);

create type public.env_materiale as enum (
  'rovere', 'noce', 'metallo', 'pietra', 'mattone', 'cemento', 'vetro', 'legno_grezzo'
);

create type public.env_illuminazione as enum (
  'calda', 'neutra', 'soffusa', 'faretti', 'laterale'
);

create table public.cellar_environments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid()
    references public.profiles (id) on delete cascade,
  nome text not null check (length(trim(nome)) > 0),
  forma public.env_forma not null,
  tema public.env_tema not null,
  materiale public.env_materiale not null,
  illuminazione public.env_illuminazione not null,
  -- In centimetri interi. I dati d'origine usano metri con la virgola
  -- (2.5 m di altezza): un'unità intera più piccola dice la stessa cosa
  -- senza virgola mobile in una misura che finisce dentro un calcolo 3D.
  larghezza_cm integer not null check (larghezza_cm between 10 and 5000),
  altezza_cm integer not null check (altezza_cm between 10 and 5000),
  profondita_cm integer not null check (profondita_cm between 10 and 5000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.cellar_environments is
  'Ambiente fisico di conservazione di un utente. Privato: nessuna policy lo '
  'espone a terzi, nemmeno quando contiene bottiglie dichiarate pubbliche — '
  'ciò che si rende pubblico è la bottiglia, non i mobili di casa propria.';

create index cellar_environments_owner_idx on public.cellar_environments (owner_id);

create trigger cellar_environments_set_updated_at
  before update on public.cellar_environments
  for each row
  execute function extensions.moddatetime('updated_at');

revoke all on public.cellar_environments from anon, authenticated;
grant select on public.cellar_environments to authenticated;
grant insert (nome, forma, tema, materiale, illuminazione,
              larghezza_cm, altezza_cm, profondita_cm)
  on public.cellar_environments to authenticated;
grant update (nome, forma, tema, materiale, illuminazione,
              larghezza_cm, altezza_cm, profondita_cm)
  on public.cellar_environments to authenticated;
grant delete on public.cellar_environments to authenticated;
-- Nessun privilegio su owner_id: il proprietario si stabilisce alla creazione
-- (default auth.uid()) e non è cedibile con un UPDATE dal browser.

alter table public.cellar_environments enable row level security;

create policy "cellar_environments_own"
  on public.cellar_environments for all
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Chi possiede un ambiente / un modulo
-- ---------------------------------------------------------------------------
-- Le policy di cellar_modules e cellar_slots devono risalire al proprietario
-- passando per un'altra tabella. Farlo con una sottoquery dentro la policy
-- significherebbe valutare la RLS di quella tabella dentro la RLS di questa:
-- accoppiamento fragile e a rischio di ricorsione. Si isola in funzioni
-- SECURITY DEFINER, come già fatto in 6a con has_role() e
-- bottle_unit_in_annuncio_pubblico().

create or replace function public.cellar_ambiente_e_mio(p_environment_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.cellar_environments e
    where e.id = p_environment_id
      and e.owner_id = auth.uid()
  );
$$;

revoke execute on function public.cellar_ambiente_e_mio(uuid) from public;
grant execute on function public.cellar_ambiente_e_mio(uuid) to authenticated;

-- La gemella `cellar_modulo_e_mio` sta più in basso, dopo la tabella dei
-- moduli: il corpo di una funzione `language sql` viene validato al momento
-- della creazione, quindi non può nominare una tabella che ancora non esiste.

-- ---------------------------------------------------------------------------
-- cellar_modules — scaffali, casse, cantinette dentro un ambiente
-- ---------------------------------------------------------------------------

create table public.cellar_modules (
  id uuid primary key default gen_random_uuid(),
  environment_id uuid not null
    references public.cellar_environments (id) on delete cascade,
  etichetta text not null check (length(trim(etichetta)) > 0),
  -- Posizione e rotazione dentro l'ambiente, per la vista 3D. Qui la virgola
  -- serve davvero (un modulo sta a -1,6 m dal centro) e numeric la
  -- rappresenta senza gli errori del binario.
  posizione_x numeric(6, 2) not null default 0,
  posizione_y numeric(6, 2) not null default 0,
  posizione_z numeric(6, 2) not null default 0,
  rotazione_y numeric(6, 2) not null default 0,
  righe smallint not null check (righe between 1 and 50),
  colonne smallint not null check (colonne between 1 and 50),
  profondita smallint not null default 1 check (profondita between 1 and 10),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.cellar_modules is
  'Un modulo di stoccaggio dentro un ambiente. `righe` e `colonne` ne '
  'descrivono la geometria: le posizioni disponibili sono righe × colonne e '
  'si calcolano, non si memorizzano (vedi cellar_slots).';

create index cellar_modules_environment_idx on public.cellar_modules (environment_id);

create trigger cellar_modules_set_updated_at
  before update on public.cellar_modules
  for each row
  execute function extensions.moddatetime('updated_at');

revoke all on public.cellar_modules from anon, authenticated;
grant select on public.cellar_modules to authenticated;
grant insert (environment_id, etichetta, posizione_x, posizione_y, posizione_z,
              rotazione_y, righe, colonne, profondita)
  on public.cellar_modules to authenticated;
grant update (etichetta, posizione_x, posizione_y, posizione_z,
              rotazione_y, righe, colonne, profondita)
  on public.cellar_modules to authenticated;
grant delete on public.cellar_modules to authenticated;

alter table public.cellar_modules enable row level security;

create policy "cellar_modules_own"
  on public.cellar_modules for all
  to authenticated
  using (public.cellar_ambiente_e_mio(environment_id))
  with check (public.cellar_ambiente_e_mio(environment_id));

create or replace function public.cellar_modulo_e_mio(p_module_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.cellar_modules m
      join public.cellar_environments e on e.id = m.environment_id
    where m.id = p_module_id
      and e.owner_id = auth.uid()
  );
$$;

revoke execute on function public.cellar_modulo_e_mio(uuid) from public;
grant execute on function public.cellar_modulo_e_mio(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- cellar_slots — dove sta una bottiglia
-- ---------------------------------------------------------------------------
-- UNA RIGA = UNA POSIZIONE OCCUPATA. Nei dati mock gli slot sono materializzati
-- tutti in anticipo (`makeSlots()` genera righe × colonne voci con
-- status: "libero"), ma quelle righe non contengono informazione: sono
-- interamente derivabili dalla geometria del modulo. Materializzarle
-- significherebbe tenere allineate 61 righe per utente a ogni modifica di
-- `righe`/`colonne`, e avere due fonti di verità sulla stessa geometria — la
-- stessa ragione per cui la 6a ha rifiutato di copiare `in_vendita` e
-- `venduta` su bottle_units.
--
-- Qui una posizione libera è semplicemente una coppia (riga, colonna) senza
-- riga corrispondente. `bottle_unit_id` è NOT NULL apposta: rende impossibile
-- inserire uno "slot vuoto" e reintrodurre il problema per sbaglio.
--
-- Il campo `status` del mock ("libero" | "occupato") non esiste per lo stesso
-- motivo: sarebbe la ripetizione di un fatto già scritto.

create table public.cellar_slots (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null references public.cellar_modules (id) on delete cascade,
  bottle_unit_id uuid not null references public.bottle_units (id) on delete cascade,
  riga smallint not null check (riga >= 0),
  colonna smallint not null check (colonna >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Due bottiglie non stanno nello stesso buco.
  constraint cellar_slots_posizione_unica unique (module_id, riga, colonna),
  -- E una bottiglia non sta in due posti insieme.
  constraint cellar_slots_bottiglia_unica unique (bottle_unit_id)
);

comment on table public.cellar_slots is
  'Posizione fisica di una bottiglia dentro un modulo. Una riga esiste solo '
  'se la posizione è occupata: le posizioni libere si ricavano dalla '
  'geometria del modulo (righe × colonne) meno quelle presenti qui.';

create index cellar_slots_module_idx on public.cellar_slots (module_id);

create trigger cellar_slots_set_updated_at
  before update on public.cellar_slots
  for each row
  execute function extensions.moddatetime('updated_at');

-- Nessun privilegio di scrittura al client: riga e colonna vanno verificate
-- contro la geometria del modulo, e la bottiglia contro il suo proprietario.
-- Sono regole, quindi la scrittura passa dalle funzioni più sotto, che sono
-- l'unica porta. Un CHECK non basterebbe: dovrebbe interrogare un'altra
-- tabella, cosa che un CHECK non può fare.
revoke all on public.cellar_slots from anon, authenticated;
grant select on public.cellar_slots to authenticated;

alter table public.cellar_slots enable row level security;

create policy "cellar_slots_select_own"
  on public.cellar_slots for select
  to authenticated
  using (public.cellar_modulo_e_mio(module_id));

-- ---------------------------------------------------------------------------
-- Funzioni di posizionamento
-- ---------------------------------------------------------------------------

-- Riga e colonna sono `integer` e non `smallint` di proposito: PostgREST
-- riceve numeri JSON e risolve la funzione per tipo, e uno smallint nella
-- firma rende la risoluzione fragile. Il restringimento avviene qui dentro,
-- dopo i controlli di intervallo.
create or replace function public.cellar_posiziona(
  p_bottle_unit_id uuid,
  p_module_id uuid,
  p_riga integer,
  p_colonna integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_righe    smallint;
  v_colonne  smallint;
begin
  if v_uid is null then
    raise exception 'Devi accedere per spostare una bottiglia.' using errcode = '42501';
  end if;

  -- La bottiglia dev'essere tua e non cancellata.
  if not exists (
    select 1 from public.bottle_units bu
    where bu.id = p_bottle_unit_id
      and bu.owner_id = v_uid
      and bu.deleted_at is null
  ) then
    raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
  end if;

  -- E il modulo pure.
  select m.righe, m.colonne into v_righe, v_colonne
  from public.cellar_modules m
    join public.cellar_environments e on e.id = m.environment_id
  where m.id = p_module_id
    and e.owner_id = v_uid;

  if v_righe is null then
    raise exception 'Questo scaffale non è nella tua cantina.' using errcode = '42501';
  end if;

  -- Riga e colonna partono da 0, come nei dati d'origine.
  if p_riga is null or p_riga < 0 or p_riga >= v_righe then
    raise exception 'Riga fuori dallo scaffale: ne ha %.', v_righe using errcode = 'P0001';
  end if;
  if p_colonna is null or p_colonna < 0 or p_colonna >= v_colonne then
    raise exception 'Colonna fuori dallo scaffale: ne ha %.', v_colonne using errcode = 'P0001';
  end if;

  -- Spostare una bottiglia già collocata è un aggiornamento, non un secondo
  -- posto: l'unicità su bottle_unit_id lo garantisce, e l'ON CONFLICT lo
  -- rende un'operazione sola invece di "cancella e reinserisci".
  begin
    insert into public.cellar_slots (module_id, bottle_unit_id, riga, colonna)
    values (p_module_id, p_bottle_unit_id, p_riga::smallint, p_colonna::smallint)
    on conflict (bottle_unit_id) do update
      set module_id = excluded.module_id,
          riga      = excluded.riga,
          colonna   = excluded.colonna;
  exception
    when unique_violation then
      raise exception 'In quella posizione c''è già una bottiglia.' using errcode = 'P0001';
  end;
end;
$$;

comment on function public.cellar_posiziona(uuid, uuid, integer, integer) is
  'Colloca o sposta una bottiglia in una posizione dello scaffale. Verifica '
  'che bottiglia e scaffale siano di chi chiama e che la posizione esista '
  'davvero nella geometria del modulo.';

revoke execute on function public.cellar_posiziona(uuid, uuid, integer, integer) from public;
grant execute on function public.cellar_posiziona(uuid, uuid, integer, integer) to authenticated;

create or replace function public.cellar_togli_posizione(p_bottle_unit_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Devi accedere per spostare una bottiglia.' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.bottle_units bu
    where bu.id = p_bottle_unit_id and bu.owner_id = v_uid
  ) then
    raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
  end if;

  delete from public.cellar_slots where bottle_unit_id = p_bottle_unit_id;
end;
$$;

comment on function public.cellar_togli_posizione(uuid) is
  'Toglie una bottiglia dalla sua posizione, lasciandola in cantina senza '
  'collocazione. Non cancella la bottiglia.';

revoke execute on function public.cellar_togli_posizione(uuid) from public;
grant execute on function public.cellar_togli_posizione(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- bottle_units visibili perché dichiarate di cantina pubblica
-- ---------------------------------------------------------------------------
-- La 6a esponeva un'unità solo se collegata a un annuncio attivo. Da qui si
-- aggiunge il secondo caso previsto dal dominio: il proprietario ha deciso che
-- quella bottiglia sta nella sua cantina pubblica. Resta una decisione per
-- singola bottiglia — non esiste un interruttore che renda pubblica l'intera
-- cantina — e non espone né ambienti né moduli né posizioni.

create policy "bottle_units_select_cantina_pubblica"
  on public.bottle_units for select
  to anon, authenticated
  using (visibilita = 'cantina_pubblica' and deleted_at is null);

-- ---------------------------------------------------------------------------
-- listings.quantita — da colonna a valore derivato
-- ---------------------------------------------------------------------------
-- Il commento sulla colonna, scritto in 6a, diceva: "Diventerà significativa
-- solo quando la Cantina permetterà di collegare più unità allo stesso
-- annuncio: a quel punto sarà un conteggio derivato, non un valore digitato."
-- È questo il momento.
--
-- La colonna sparisce invece di restare accanto al conteggio: tenerle entrambe
-- creerebbe due fonti di verità sulla stessa quantità, che è esattamente il
-- difetto che la 6a ha evitato ovunque.
--
-- ONESTÀ SUL VALORE DI OGGI. Il legame annuncio → unità è ancora uno a uno
-- (`listings.bottle_unit_id`), quindi il conteggio vale 1 per ogni annuncio
-- attivo: identico a prima, ed è quello che la prova di regressione verifica.
-- Diventerà maggiore di 1 quando esisterà un legame uno-a-molti, che è lavoro
-- della fase in cui nascerà l'interfaccia per usarlo. La vista intermedia qui
-- sotto esiste perché quel giorno cambi solo lei, e non public_listings.

create view public.listing_bottle_units
with (security_invoker = off)
as
select
  l.id  as listing_id,
  bu.id as bottle_unit_id
from public.listings l
  join public.bottle_units bu on bu.id = l.bottle_unit_id
where bu.deleted_at is null;

comment on view public.listing_bottle_units is
  'Le unità fisiche che un annuncio sta vendendo. Oggi è una per annuncio, '
  'perché il legame è uno a uno; quando diventerà uno-a-molti basterà '
  'cambiare questa vista, e il conteggio in public_listings seguirà.';

-- Nessun privilegio a nessun ruolo client: è una vista di servizio, non
-- un'API. Scavalca la RLS (security_invoker = off), quindi elencherebbe anche
-- le unità collegate a bozze — non contenuti, ma comunque l'esistenza di
-- annunci non pubblici. `public_listings` la legge lo stesso, perché anche lei
-- valuta con i privilegi del proprietario.
revoke all on public.listing_bottle_units from anon, authenticated;

-- La vista si ridefinisce per intero: `create or replace view` non permette di
-- cambiare il tipo o l'origine di una colonna già esposta. Va eliminata PRIMA
-- di togliere `quantita` da listings, altrimenti PostgreSQL rifiuta il DROP
-- COLUMN: la vista dipende da quella colonna.
drop view public.public_listings;

alter table public.listings drop column quantita;

create view public.public_listings
with (security_invoker = off)
as
select
  l.id,
  l.slug,
  l.prezzo_cents,
  l.prezzo_mercato_cents,
  -- Il cast a integer non è cosmetico: count() è bigint, e un bigint viaggia
  -- verso il client con regole di serializzazione diverse da un intero
  -- normale. La colonna prima era `integer` e deve restarlo, altrimenti
  -- l'adattatore TypeScript riceve una forma diversa senza che nessuno
  -- l'abbia chiesto.
  (
    select count(*)
    from public.listing_bottle_units lbu
    where lbu.listing_id = l.id
  )::integer as quantita,
  l.condizione,
  l.conservazione,
  l.storia,
  l.degustazione,
  l.immagini,
  l.tag,
  l.published_at,
  l.created_at,
  coalesce(l.published_at, l.created_at) as pubblicato_at,
  w.id            as wine_id,
  w.slug          as wine_slug,
  w.produttore,
  w.nome,
  w.annata,
  w.regione,
  w.denominazione,
  w.tipo,
  w.formato,
  w.produttore || ' ' || w.nome as ricerca,
  p.id            as seller_id,
  p.username      as seller_username,
  p.citta         as seller_citta,
  p.avatar_url    as seller_avatar_url
from public.listings l
  join public.bottle_units bu on bu.id = l.bottle_unit_id
  join public.wines w on w.id = bu.wine_id
  join public.profiles p on p.id = l.seller_id
where l.stato = 'attivo';

comment on view public.public_listings is
  'Annunci attivi con vino e venditore già uniti, nella forma che serve a '
  '/esplora e a /annuncio/[slug]. Espone solo campi non sensibili del '
  'profilo venditore (mai dob, esperienza, bio, obiettivi). `quantita` è '
  'derivata dal conteggio delle unità collegate, non più una colonna.';

revoke all on public.public_listings from anon, authenticated;
grant select on public.public_listings to anon, authenticated;
