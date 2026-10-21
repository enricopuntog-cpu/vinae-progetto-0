-- VPM-015B3 — Annunci Accessori: pubblicazione automatica con moderazione
-- successiva (fondazione). NESSUNA VENDITA.
--
-- Contratto: docs/VPM_015B3_PUBBLICAZIONE_ACCESSORI.md. Decisione del titolare:
-- gli annunci conformi si pubblicano da soli, senza approvazione preventiva; la
-- moderazione opera dopo (segnalazioni e controlli amministrativi). La decisione
-- riguarda il MODELLO, non il rilascio: questa migrazione lascia tutto spento.
--
--   * `pubblicazione_attiva` (spenta di default) si accende solo col ruolo
--     `accessori_release`; nessun ruolo e assegnato qui;
--   * nessuna categoria e pubblicabile (tabella separata da `vendibile`, che
--     resta un filtro di PREPARAZIONE; nessun backfill);
--   * "visibile" non e "acquistabile": nessun ordine, checkout, pagamento,
--     prenotazione, payout o spedizione, e nessuno stato acquistabile;
--   * la moderazione estende quella esistente (reports, audit_log, mod_action,
--     ruolo admin): un bersaglio in piu, nessun sistema parallelo.
--
-- Che cosa fa:
--   [1] stati: bozza / pubblicato / modifiche_richieste / oscurato / ritirato.
--       `in_revisione` (B2) non e piu uno stato: i dati esistenti tornano in
--       bozza, nessuna bozza e cancellata;
--   [2] interruttore di pubblicazione e categorie pubblicabili (fail-closed);
--   [3] snapshot pubblico dell'annuncio (nome, marchio, categoria, riferimenti
--       alle foto), separato dai dati privati della Cantina;
--   [4] guardia unica sulle transizioni, valida per OGNI writer;
--   [5] letture pubbliche (solo annunci pubblicati e ammessi) e policy Storage
--       sulle sole foto dello snapshot;
--   [6] moderazione: bersaglio `annuncio_accessorio`, segnalazione, motore di
--       oscuramento/richiesta modifiche/ripristino, porte admin;
--   [7] porte del venditore (pubblica, aggiorna, ritira) e dell'admin.
--
-- Non tocca: listings, orders, payments, proposals, bottle_units, wines,
-- marketplace_config, il checkout. Nessuna migrazione precedente e modificata.

-- ---------------------------------------------------------------------------
-- [1] Stati
-- ---------------------------------------------------------------------------

-- Nessuna bozza e cancellata: l'invio in revisione non esiste piu, quindi le
-- righe in attesa tornano bozza. Avviene PRIMA di sostituire la guardia.
alter table private.annunci_accessori disable trigger annunci_accessori_guard;
update private.annunci_accessori
set stato = 'bozza', inviato_at = null
where stato = 'in_revisione';
alter table private.annunci_accessori enable trigger annunci_accessori_guard;

alter table private.annunci_accessori drop constraint annunci_accessori_stato_ammesso;
alter table private.annunci_accessori drop constraint annunci_accessori_revisione_coerente;
alter table private.annunci_accessori
  add constraint annunci_accessori_stato_ammesso
  check (stato in ('bozza', 'pubblicato', 'modifiche_richieste', 'oscurato', 'ritirato'));

alter table private.annunci_accessori
  add column pubblicato_at timestamptz,
  -- Aumenta a ogni aggiornamento controllato di un annuncio pubblicato; ogni
  -- aumento rifa lo snapshot.
  add column versione integer not null default 0,
  -- Esito della moderazione. `provvedimento` resta sull'annuncio oscurato e,
  -- se il venditore lo ritira, sull'annuncio ritirato: e cio che impedisce di
  -- ricrearlo per eludere la rimozione.
  add column provvedimento text,
  add column stato_motivo text,
  add column stato_aggiornato_da uuid references public.profiles (id) on delete set null,
  add column stato_aggiornato_at timestamptz,
  add column oscurato_at timestamptz,
  add column stato_prima text,
  -- Impronta del contenuto al momento della richiesta di modifiche: un annuncio
  -- non torna pubblico se il contenuto non e cambiato.
  add column hash_richiesta text;

alter table private.annunci_accessori
  add constraint annunci_accessori_provvedimento_ammesso
    check (provvedimento is null or provvedimento in ('sospensione', 'rimozione')),
  add constraint annunci_accessori_provvedimento_stato
    check (provvedimento is null or stato in ('oscurato', 'ritirato')),
  add constraint annunci_accessori_oscurato_coerente
    check (stato <> 'oscurato' or (provvedimento is not null and stato_motivo is not null
                                   and oscurato_at is not null and stato_prima is not null)),
  add constraint annunci_accessori_stato_prima_ammesso
    check (stato_prima is null or stato_prima in ('pubblicato', 'modifiche_richieste')),
  add constraint annunci_accessori_motivo_forma
    check (stato_motivo is null or length(btrim(stato_motivo)) between 1 and 4000),
  add constraint annunci_accessori_pubblicato_coerente
    check (stato <> 'pubblicato' or pubblicato_at is not null);

comment on column private.annunci_accessori.stato is
  'bozza (privata, modificabile), pubblicato (visibile se release e categoria lo '
  'consentono), modifiche_richieste (non visibile: il venditore corregge), oscurato '
  '(non visibile: solo l''amministrazione lo riapre), ritirato (terminale). Nessuno '
  'stato e acquistabile.';

-- Un solo annuncio aperto per accessorio: "aperto" e tutto cio che non e ritirato.
-- Un annuncio oscurato continua a impegnare l'accessorio: chi e stato rimosso non
-- lo ricrea per aggirare il provvedimento.
drop index private.annunci_accessori_uno_aperto;
create unique index annunci_accessori_uno_aperto
  on private.annunci_accessori (cantina_accessorio_id)
  where stato <> 'ritirato';

create index annunci_accessori_pubblicati_idx
  on private.annunci_accessori (pubblicato_at desc) where stato = 'pubblicato';

-- ---------------------------------------------------------------------------
-- [2] Interruttore di pubblicazione e categorie pubblicabili
-- ---------------------------------------------------------------------------

alter table private.annunci_accessori_impostazioni
  drop constraint annunci_accessori_nessuna_pubblicazione;

comment on column private.annunci_accessori_impostazioni.pubblicazione_attiva is
  'VPM-015B3: consente di pubblicare e rende leggibili al pubblico gli annunci gia '
  'pubblicati. Spenta di default. Accensione solo con il ruolo accessori_release e '
  'il marcatore transazionale; spegnerla rende invisibili gli annunci subito.';

create or replace function private.annunci_accessori_impostazioni_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (new.preparazione_attiva and not old.preparazione_attiva)
     or (new.pubblicazione_attiva and not old.pubblicazione_attiva) then
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

alter table private.accessori_registro drop constraint accessori_registro_oggetto_ammesso;
alter table private.accessori_registro
  add constraint accessori_registro_oggetto_ammesso
  check (oggetto in ('categoria', 'accessorio', 'visibilita', 'cantina_accessori',
                     'annunci_accessori', 'annunci_pubblicazione', 'categoria_pubblicabile'));

-- Pubblicazione aperta: cantina, preparazione e pubblicazione accese. Una
-- qualunque spenta chiude le nuove pubblicazioni e le letture pubbliche.
create function private.annunci_accessori_pubblicazione_aperta()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.cantina_accessori_funzione_attiva()
    and coalesce((select i.preparazione_attiva and i.pubblicazione_attiva
                  from private.annunci_accessori_impostazioni i), false);
$$;

revoke execute on function private.annunci_accessori_pubblicazione_aperta() from public, anon, authenticated;

-- Categorie ammesse alla PUBBLICAZIONE. Non e `vendibile` (filtro di preparazione
-- delle bozze): nessun backfill, nessuna riga per default, nessuna categoria
-- nuova autorizzata. Nessuna riga = non pubblicabile.
create table private.annunci_accessori_categorie_pubblicabili (
  categoria_id uuid primary key references private.accessori_categorie (id) on delete restrict,
  pubblicabile boolean not null,
  approvata_da uuid not null references public.profiles (id) on delete restrict,
  nota text check (nota is null or length(btrim(nota)) between 1 and 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table private.annunci_accessori_categorie_pubblicabili is
  'VPM-015B3: categorie esplicitamente approvate dal titolare (ruolo accessori_release) '
  'per la pubblicazione automatica. Fail-closed: nessuna riga, nessuna pubblicazione. '
  'Una sottocategoria e pubblicabile solo se lo e anche il genitore.';

alter table private.annunci_accessori_categorie_pubblicabili enable row level security;
revoke all on table private.annunci_accessori_categorie_pubblicabili from public, anon, authenticated;

create trigger annunci_accessori_categorie_pubblicabili_updated_at
  before update on private.annunci_accessori_categorie_pubblicabili
  for each row execute function extensions.moddatetime('updated_at');
create trigger annunci_accessori_categorie_pubblicabili_no_delete
  before delete on private.annunci_accessori_categorie_pubblicabili
  for each row execute function private.accessori_non_si_cancella();
create trigger annunci_accessori_categorie_pubblicabili_no_truncate
  before truncate on private.annunci_accessori_categorie_pubblicabili
  for each statement execute function private.accessori_non_si_cancella();

-- Pubblicabile = vendibile alla preparazione (una categoria che B2 tiene chiusa
-- non si apre MAI) + riga approvata + genitore approvato.
create function private.annuncio_accessorio_categoria_pubblicabile(p_categoria uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.annuncio_accessorio_categoria_vendibile(p_categoria)
    and coalesce((
      select r.pubblicabile
        and (c.parent_id is null or coalesce((
               select rg.pubblicabile from private.annunci_accessori_categorie_pubblicabili rg
               where rg.categoria_id = c.parent_id), false))
      from private.accessori_categorie c
      join private.annunci_accessori_categorie_pubblicabili r on r.categoria_id = c.id
      where c.id = p_categoria
    ), false);
$$;

revoke execute on function private.annuncio_accessorio_categoria_pubblicabile(uuid)
  from public, anon, authenticated;

-- Vincola ANCHE i writer privilegiati: si approva solo dalla porta di rilascio,
-- solo una categoria che B2 ammette alla preparazione, solo con il genitore gia
-- approvato. Revocare e sempre consentito.
create function private.annunci_accessori_categorie_pubblicabili_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_parent uuid;
begin
  if new.pubblicabile and (tg_op = 'INSERT' or not old.pubblicabile) then
    if coalesce(current_setting('vinae.accessori_rilascio', true), '')
       <> 'rilascio:' || new.approvata_da::text then
      raise exception 'Una categoria si approva solo dalla porta di rilascio.'
        using errcode = '42501', hint = 'rilascio_non_autorizzato';
    end if;
    if not private.annuncio_accessorio_categoria_vendibile(new.categoria_id) then
      raise exception 'Questa categoria non e ammessa nemmeno alla preparazione.'
        using errcode = '22023', hint = 'categoria_non_approvabile';
    end if;
    select c.parent_id into v_parent from private.accessori_categorie c where c.id = new.categoria_id;
    if v_parent is not null and not coalesce((
         select r.pubblicabile from private.annunci_accessori_categorie_pubblicabili r
         where r.categoria_id = v_parent), false) then
      raise exception 'Approva prima la categoria genitore.'
        using errcode = '22023', hint = 'categoria_genitore_non_approvata';
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function private.annunci_accessori_categorie_pubblicabili_guard()
  from public, anon, authenticated;

create trigger annunci_accessori_categorie_pubblicabili_guard
  before insert or update on private.annunci_accessori_categorie_pubblicabili
  for each row execute function private.annunci_accessori_categorie_pubblicabili_guard();

-- Filtro tecnico MINIMO e dichiarato (non un giudice del contenuto): termini che
-- indicano gli articoli esclusi esplicitamente dal titolare. Alcolici e articoli
-- regolamentati restano esclusi dal gate di categoria e dalla dichiarazione del
-- venditore; questo elenco intercetta solo i casi nominati e inequivocabili.
create function private.annuncio_accessorio_testo_vietato(p_testo text)
returns text
language sql
immutable
set search_path = ''
as $$
  select t
  from unnest(array[
    'sciabol', 'sabrage', 'sabre', 'armi da fuoco', 'arma da fuoco', 'pistola', 'fucile',
    'munizion'
  ]) as t
  where lower(coalesce(p_testo, '')) like '%' || t || '%'
  limit 1;
$$;

revoke execute on function private.annuncio_accessorio_testo_vietato(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [3] Snapshot pubblico
-- ---------------------------------------------------------------------------
--
-- Il pubblico legge SOLO lo snapshot (piu i campi dell'offerta, congelati mentre
-- l'annuncio e pubblicato). Mai la Cantina: `note_private`, descrizione privata,
-- quantita posseduta e legame col catalogo non vi compaiono. Le foto non sono
-- copiate: lo snapshot custodisce i percorsi nel bucket privato, e i file
-- restano cancellabili a ritiro avvenuto o con l'account.

create table private.annunci_accessori_snapshot (
  annuncio_id uuid primary key references private.annunci_accessori (id) on delete cascade,
  versione integer not null,
  nome text not null,
  marchio text,
  categoria_id uuid not null references private.accessori_categorie (id) on delete restrict,
  immagini text[] not null,
  created_at timestamptz not null default now(),
  aggiornato_at timestamptz not null default now(),
  constraint annunci_accessori_snapshot_nome_forma check (length(btrim(nome)) between 2 and 120),
  constraint annunci_accessori_snapshot_immagini
    check (cardinality(immagini) between 1 and 4)
);

comment on table private.annunci_accessori_snapshot is
  'VPM-015B3: istantanea pubblicabile dell''annuncio (nome, marchio, categoria, '
  'percorsi delle foto). Scritta solo da private.annuncio_accessorio_snapshot_rileva '
  'dopo le verifiche della guardia; una modifica privata della Cantina non la altera.';

alter table private.annunci_accessori_snapshot enable row level security;
revoke all on table private.annunci_accessori_snapshot from public, anon, authenticated;

create function private.annunci_accessori_snapshot_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    -- Cancellazione dell'account: l'annuncio non esiste piu. Altrimenti mai.
    if exists (select 1 from private.annunci_accessori a where a.id = old.annuncio_id) then
      raise exception 'Lo snapshot non si cancella da solo.'
        using errcode = '42501', hint = 'snapshot_protetto';
    end if;
    return old;
  end if;
  if coalesce(current_setting('vinae.annuncio_accessorio_snapshot', true), '')
     <> 'ok:' || new.annuncio_id::text then
    raise exception 'Lo snapshot si scrive solo alla pubblicazione.'
      using errcode = '42501', hint = 'snapshot_protetto';
  end if;
  return new;
end;
$$;

revoke execute on function private.annunci_accessori_snapshot_guard() from public, anon, authenticated;

create trigger annunci_accessori_snapshot_guard
  before insert or update or delete on private.annunci_accessori_snapshot
  for each row execute function private.annunci_accessori_snapshot_guard();
create trigger annunci_accessori_snapshot_no_truncate
  before truncate on private.annunci_accessori_snapshot
  for each statement execute function private.accessori_non_si_cancella();

create function private.annuncio_accessorio_snapshot_rileva(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_a private.annunci_accessori%rowtype;
  v_item private.cantina_accessori%rowtype;
begin
  select * into v_a from private.annunci_accessori where id = p_id;
  select * into v_item from private.cantina_accessori where id = v_a.cantina_accessorio_id;
  if v_a.id is null or v_item.id is null then
    raise exception 'Annuncio non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  perform set_config('vinae.annuncio_accessorio_snapshot', 'ok:' || p_id::text, true);
  insert into private.annunci_accessori_snapshot (annuncio_id, versione, nome, marchio, categoria_id, immagini)
  values (p_id, v_a.versione, v_item.nome, v_item.marchio, v_item.categoria_id, v_item.immagini)
  on conflict (annuncio_id) do update
    set versione = excluded.versione, nome = excluded.nome, marchio = excluded.marchio,
        categoria_id = excluded.categoria_id, immagini = excluded.immagini,
        aggiornato_at = now();
  perform set_config('vinae.annuncio_accessorio_snapshot', '', true);
end;
$$;

revoke execute on function private.annuncio_accessorio_snapshot_rileva(uuid) from public, anon, authenticated;

-- Impronta del contenuto (offerta + dati della Cantina che finiscono nello snapshot).
create function private.annuncio_accessorio_contenuto_hash(
  p_quantita integer, p_prezzo integer, p_condizione text, p_descrizione text,
  p_peso integer, p_l integer, p_w integer, p_h integer, p_fragile boolean,
  p_nome text, p_marchio text, p_immagini text[]
)
returns text
language sql
immutable
set search_path = ''
as $$
  select md5(concat_ws('|', p_quantita, p_prezzo, p_condizione, p_descrizione, p_peso, p_l,
                       p_w, p_h, p_fragile, p_nome, coalesce(p_marchio, ''),
                       array_to_string(p_immagini, ',')));
$$;

revoke execute on function private.annuncio_accessorio_contenuto_hash(
  integer, integer, text, text, integer, integer, integer, integer, boolean, text, text, text[])
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [4] Guardia unica sulle transizioni (ogni writer, anche privilegiato)
-- ---------------------------------------------------------------------------
--
-- Marcatori transazionali (set_config locale, scritti solo dalle porte):
--   vinae.annuncio_accessorio_moderazione = 'ok:<id>'  azioni dell'amministrazione
--   vinae.annuncio_accessorio_aggiorna    = 'ok:<id>'  aggiornamento controllato
-- Senza il primo nessuno oscura, richiede modifiche o riapre un annuncio, e nessun
-- campo di moderazione cambia. Entrare in `pubblicato` richiede SEMPRE, qui
-- dentro, tutti i requisiti: interruttore, venditore, categoria, dichiarazione,
-- foto, termini, anti-elusione, prezzo calcolabile.

create or replace function private.annunci_accessori_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item private.cantina_accessori%rowtype;
  v_snap private.annunci_accessori_snapshot%rowtype;
  v_v record;
  v_altri integer;
  v_mod boolean := coalesce(current_setting('vinae.annuncio_accessorio_moderazione', true), '')
                   = 'ok:' || new.id::text;
  v_agg boolean := coalesce(current_setting('vinae.annuncio_accessorio_aggiorna', true), '')
                   = 'ok:' || new.id::text;
  v_cambio boolean := false;
  v_entra boolean := false;
  v_ripristino boolean := false;
  v_nome text;
  v_marchio text;
  v_cat uuid;
  v_imm text[];
  v_termine text;
begin
  if tg_op = 'UPDATE' then
    if new.id <> old.id or new.seller_id <> old.seller_id
       or new.cantina_accessorio_id <> old.cantina_accessorio_id then
      raise exception 'Identificativo, venditore e accessorio non cambiano.'
        using errcode = '42501', hint = 'annuncio_immutabile';
    end if;
    if old.stato = 'ritirato' then
      raise exception 'Un annuncio ritirato non si modifica.'
        using errcode = '22023', hint = 'annuncio_ritirato';
    end if;
    if new.stato <> old.stato and (old.stato, new.stato) not in (
         ('bozza', 'pubblicato'), ('bozza', 'ritirato'),
         ('pubblicato', 'bozza'), ('pubblicato', 'ritirato'),
         ('pubblicato', 'modifiche_richieste'), ('pubblicato', 'oscurato'),
         ('modifiche_richieste', 'pubblicato'), ('modifiche_richieste', 'ritirato'),
         ('modifiche_richieste', 'oscurato'),
         ('oscurato', 'pubblicato'), ('oscurato', 'modifiche_richieste'),
         ('oscurato', 'ritirato')) then
      raise exception 'Passaggio di stato non ammesso.'
        using errcode = '22023', hint = 'transizione_non_ammessa';
    end if;
    -- Oscurare, chiedere modifiche e riaprire sono atti dell'amministrazione.
    if new.stato <> old.stato and not v_mod and (
         new.stato = 'oscurato'
         or (old.stato = 'oscurato' and new.stato <> 'ritirato')
         or (old.stato = 'pubblicato' and new.stato = 'modifiche_richieste')) then
      raise exception 'Questo passaggio e riservato alla moderazione.'
        using errcode = '42501', hint = 'moderazione_riservata';
    end if;
    if not v_mod and (
         new.provvedimento, new.stato_motivo, new.stato_aggiornato_da, new.stato_aggiornato_at,
         new.oscurato_at, new.stato_prima, new.hash_richiesta
       ) is distinct from (
         old.provvedimento, old.stato_motivo, old.stato_aggiornato_da, old.stato_aggiornato_at,
         old.oscurato_at, old.stato_prima, old.hash_richiesta
       ) then
      raise exception 'Gli esiti della moderazione non si scrivono da qui.'
        using errcode = '42501', hint = 'moderazione_riservata';
    end if;

    v_cambio := (
      new.quantita, new.prezzo_unitario_cents, new.condizione, new.descrizione,
      new.dichiarazione_conforme, new.peso_g, new.lunghezza_mm, new.larghezza_mm,
      new.altezza_mm, new.fragile
    ) is distinct from (
      old.quantita, old.prezzo_unitario_cents, old.condizione, old.descrizione,
      old.dichiarazione_conforme, old.peso_g, old.lunghezza_mm, old.larghezza_mm,
      old.altezza_mm, old.fragile
    );
    -- L'offerta si modifica in bozza e in modifiche_richieste; da pubblicato solo
    -- con l'aggiornamento controllato (che rifa lo snapshot).
    if v_cambio and not (
         old.stato in ('bozza', 'modifiche_richieste')
         or (old.stato = 'pubblicato' and new.stato = 'pubblicato' and v_agg)) then
      raise exception 'Questo annuncio non si modifica in questo stato.'
        using errcode = '22023', hint = 'annuncio_non_modificabile';
    end if;

    if old.stato = 'pubblicato' and new.stato = 'pubblicato' and v_agg then
      new.versione := old.versione + 1;
    elsif new.versione is distinct from old.versione then
      raise exception 'La versione la gestisce il sistema.'
        using errcode = '42501', hint = 'annuncio_immutabile';
    end if;

    v_entra := new.stato = 'pubblicato' and (old.stato <> 'pubblicato' or v_agg);
    v_ripristino := old.stato = 'oscurato' and new.stato = 'pubblicato';
  else
    if new.stato <> 'bozza' then
      raise exception 'Un annuncio nasce in bozza.'
        using errcode = '22023', hint = 'annuncio_nasce_bozza';
    end if;
    new.versione := 0;
    if new.provvedimento is not null or new.stato_motivo is not null
       or new.stato_aggiornato_da is not null or new.stato_aggiornato_at is not null
       or new.oscurato_at is not null or new.stato_prima is not null
       or new.hash_richiesta is not null or new.pubblicato_at is not null then
      raise exception 'Un annuncio nasce senza esiti di moderazione.'
        using errcode = '42501', hint = 'moderazione_riservata';
    end if;
  end if;

  new.inviato_at := null;

  if new.stato <> 'ritirato' and (tg_op = 'INSERT' or v_cambio or v_entra) then
    -- Ordine dei lock: sempre accessorio della Cantina, poi annuncio.
    select * into v_item from private.cantina_accessori
    where id = new.cantina_accessorio_id for update;
    if v_item.id is null or v_item.owner_id <> new.seller_id then
      raise exception 'Accessorio non trovato.' using errcode = 'P0001', hint = 'non_trovato';
    end if;

    if tg_op = 'INSERT' or v_entra or new.quantita is distinct from old.quantita then
      if v_item.archiviato_at is not null then
        raise exception 'Un accessorio archiviato non si mette in vendita.'
          using errcode = '22023', hint = 'accessorio_archiviato';
      end if;
      select coalesce(sum(a.quantita), 0) into v_altri
      from private.annunci_accessori a
      where a.cantina_accessorio_id = new.cantina_accessorio_id
        and a.stato <> 'ritirato'
        and a.id <> new.id;
      if new.quantita + v_altri > v_item.quantita then
        raise exception 'Quantita superiore a quella disponibile.'
          using errcode = '22023', hint = 'quantita_non_disponibile';
      end if;
    end if;

    select * into v_v from private.annuncio_accessorio_venditore(new.seller_id);
    if not v_v.ammesso then
      raise exception 'Questo venditore non puo preparare annunci di accessori.'
        using errcode = '42501', hint = v_v.motivo;
    end if;

    if not v_ripristino
       and not private.annuncio_accessorio_categoria_vendibile(v_item.categoria_id) then
      raise exception 'Questa categoria non e ancora vendibile.'
        using errcode = '22023', hint = 'categoria_non_vendibile';
    end if;

    if v_entra then
      -- Requisiti della pubblicazione automatica. Sono qui, non solo nella porta:
      -- valgono per ogni writer.
      if not private.annunci_accessori_pubblicazione_aperta() then
        raise exception 'La pubblicazione degli annunci Accessori non e ancora aperta.'
          using errcode = '42501', hint = 'pubblicazione_chiusa';
      end if;

      if v_ripristino then
        -- Riapertura da parte dell'amministrazione: vale cio che ha giudicato,
        -- cioe lo snapshot, non le modifiche successive della Cantina.
        select * into v_snap from private.annunci_accessori_snapshot where annuncio_id = new.id;
        if v_snap.annuncio_id is null then
          raise exception 'Snapshot mancante.' using errcode = '22023', hint = 'snapshot_mancante';
        end if;
        v_nome := v_snap.nome; v_marchio := v_snap.marchio;
        v_cat := v_snap.categoria_id; v_imm := v_snap.immagini;
      else
        v_nome := v_item.nome; v_marchio := v_item.marchio;
        v_cat := v_item.categoria_id; v_imm := v_item.immagini;
      end if;

      if not private.annuncio_accessorio_categoria_pubblicabile(v_cat) then
        raise exception 'Questa categoria non e ammessa alla pubblicazione.'
          using errcode = '22023', hint = 'categoria_non_pubblicabile';
      end if;
      if not new.dichiarazione_conforme then
        raise exception 'Serve la dichiarazione di conformita.'
          using errcode = '22023', hint = 'dichiarazione_mancante';
      end if;
      if cardinality(v_imm) < 1 then
        raise exception 'Serve almeno una fotografia.'
          using errcode = '22023', hint = 'foto_obbligatoria';
      end if;
      v_termine := private.annuncio_accessorio_testo_vietato(
        concat_ws(' ', v_nome, v_marchio, new.descrizione));
      if v_termine is not null then
        raise exception 'Il contenuto contiene un articolo non ammesso.'
          using errcode = '22023', hint = 'contenuto_non_ammesso';
      end if;

      -- Anti-elusione: nessun nuovo annuncio per un accessorio gia oggetto di un
      -- provvedimento, ne per lo stesso articolo (stesso venditore, nome e
      -- categoria) entro 90 giorni da una rimozione.
      if exists (
           select 1 from private.annunci_accessori x
           where x.cantina_accessorio_id = new.cantina_accessorio_id
             and x.id <> new.id and x.provvedimento is not null)
         or exists (
           select 1 from private.annunci_accessori x
           join private.cantina_accessori xc on xc.id = x.cantina_accessorio_id
           where x.seller_id = new.seller_id
             and x.cantina_accessorio_id <> new.cantina_accessorio_id
             and x.provvedimento = 'rimozione'
             and x.oscurato_at > now() - interval '90 days'
             and lower(btrim(xc.nome)) = lower(btrim(v_nome))
             and xc.categoria_id = v_cat) then
        raise exception 'Questo articolo e stato rimosso da Vinea e non si ripubblica da qui.'
          using errcode = '42501', hint = 'ripubblicazione_bloccata';
      end if;

      -- Dopo una richiesta di modifiche si torna pubblici solo cambiando
      -- davvero qualcosa (la riapertura dell'amministrazione e esente).
      if tg_op = 'UPDATE' and old.stato = 'modifiche_richieste' and not v_mod
         and old.hash_richiesta is not null
         and old.hash_richiesta = private.annuncio_accessorio_contenuto_hash(
               new.quantita, new.prezzo_unitario_cents, new.condizione, new.descrizione,
               new.peso_g, new.lunghezza_mm, new.larghezza_mm, new.altezza_mm, new.fragile,
               v_nome, v_marchio, v_imm) then
        raise exception 'Modifica l''annuncio come richiesto prima di ripubblicarlo.'
          using errcode = '22023', hint = 'modifiche_non_effettuate';
      end if;

      -- Il prezzo pubblico lo calcola il database: senza margine nessun annuncio.
      if private.preventivo_dominio(
           'accessori_enologici'::public.dominio_merceologico, v_v.classe,
           new.prezzo_unitario_cents, 1, null) is null then
        raise exception 'Il prezzo non e calcolabile.'
          using errcode = '22023', hint = 'preventivo_non_disponibile';
      end if;

      if tg_op = 'UPDATE' and old.stato = 'pubblicato' then
        new.pubblicato_at := old.pubblicato_at;
      elsif v_ripristino then
        new.pubblicato_at := coalesce(old.pubblicato_at, now());
      else
        new.pubblicato_at := now();
      end if;
    end if;
  end if;

  if new.stato = 'ritirato' and new.ritirato_at is null then
    new.ritirato_at := now();
  end if;

  return new;
end;
$$;

revoke execute on function private.annunci_accessori_guard() from public, anon, authenticated;

-- Lo snapshot segue la pubblicazione nella stessa transazione, per ogni writer.
-- Non si rifa nella riapertura da oscurato: l'amministrazione ha giudicato quello.
create function private.annunci_accessori_snapshot_aggiorna()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.stato = 'pubblicato' and old.stato <> 'oscurato'
     and (old.stato <> 'pubblicato' or new.versione <> old.versione) then
    perform private.annuncio_accessorio_snapshot_rileva(new.id);
  end if;
  return null;
end;
$$;

revoke execute on function private.annunci_accessori_snapshot_aggiorna() from public, anon, authenticated;

create trigger annunci_accessori_snapshot_aggiorna
  after update on private.annunci_accessori
  for each row execute function private.annunci_accessori_snapshot_aggiorna();

-- Rete di sicurezza: a fine transazione un annuncio pubblicato ha il suo snapshot.
create function private.annunci_accessori_snapshot_presente()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.stato = 'pubblicato' and not exists (
       select 1 from private.annunci_accessori_snapshot s where s.annuncio_id = new.id) then
    raise exception 'Un annuncio pubblicato ha sempre il suo snapshot.'
      using errcode = '23514', hint = 'snapshot_mancante';
  end if;
  return null;
end;
$$;

revoke execute on function private.annunci_accessori_snapshot_presente() from public, anon, authenticated;

create constraint trigger annunci_accessori_snapshot_presente
  after insert or update on private.annunci_accessori
  deferrable initially deferred
  for each row execute function private.annunci_accessori_snapshot_presente();

-- Guardia sugli accessori della Cantina: "aperto" e tutto cio che non e ritirato.
create or replace function private.annunci_accessori_cantina_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_impegnati integer;
  v_non_bozza boolean;
begin
  select coalesce(sum(a.quantita), 0),
         coalesce(bool_or(a.stato in ('pubblicato', 'modifiche_richieste', 'oscurato')), false)
  into v_impegnati, v_non_bozza
  from private.annunci_accessori a
  where a.cantina_accessorio_id = old.id and a.stato <> 'ritirato';

  if tg_op = 'DELETE' then
    if v_impegnati > 0 and exists (select 1 from public.profiles p where p.id = old.owner_id) then
      raise exception 'Ritira prima l''annuncio di questo accessorio.'
        using errcode = '22023', hint = 'annuncio_aperto';
    end if;
    return old;
  end if;

  if new.archiviato_at is not null and old.archiviato_at is null and v_impegnati > 0 then
    raise exception 'Ritira prima l''annuncio di questo accessorio.'
      using errcode = '22023', hint = 'annuncio_aperto';
  end if;
  if new.quantita < old.quantita and v_impegnati > new.quantita then
    raise exception 'La quantita e inferiore a quella messa in vendita.'
      using errcode = '22023', hint = 'quantita_sotto_impegnata';
  end if;
  if new.categoria_id is distinct from old.categoria_id and v_non_bozza then
    raise exception 'L''accessorio ha un annuncio pubblicato o in moderazione.'
      using errcode = '22023', hint = 'annuncio_pubblicato';
  end if;
  return new;
end;
$$;

-- Quantita impegnata: tutti gli annunci aperti (non ritirati) dell'accessorio.
create or replace function private.annuncio_accessorio_impegnati(p_cantina_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(a.quantita), 0)::integer
  from private.annunci_accessori a
  where a.cantina_accessorio_id = p_cantina_id and a.stato <> 'ritirato';
$$;

-- ---------------------------------------------------------------------------
-- [5] Letture pubbliche e Storage
-- ---------------------------------------------------------------------------

-- L'annuncio e visibile al pubblico solo se: pubblicazione aperta, stato
-- pubblicato, snapshot presente, categoria ancora pubblicabile, venditore ancora
-- ammesso e profilo visibile. Un solo punto: letture e firme Storage lo usano.
create function private.annuncio_accessorio_visibile(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.annunci_accessori_pubblicazione_aperta() and exists (
    select 1
    from private.annunci_accessori a
    join private.annunci_accessori_snapshot s on s.annuncio_id = a.id
    where a.id = p_id
      and a.stato = 'pubblicato'
      and private.annuncio_accessorio_categoria_pubblicabile(s.categoria_id)
      and (select v.ammesso from private.annuncio_accessorio_venditore(a.seller_id) v)
      and exists (select 1 from private.profili_pubblici pp where pp.user_id = a.seller_id)
  );
$$;

revoke execute on function private.annuncio_accessorio_visibile(uuid) from public, anon, authenticated;

-- Forma pubblica: ELENCO CHIUSO. Non contiene note, descrizione privata, quantita
-- posseduta, id della Cantina, id del venditore ne il prezzo richiesto dal
-- venditore: solo il prezzo che vedrebbe l'acquirente (spedizione esclusa).
create function private.annuncio_accessorio_pubblico_json(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', a.id,
    'nome', s.nome,
    'marchio', s.marchio,
    'categoria', jsonb_build_object('slug', c.slug, 'nome', c.nome, 'genitore', g.nome),
    'condizione', a.condizione,
    'quantita', a.quantita,
    'descrizione', a.descrizione,
    'foto', to_jsonb(s.immagini),
    'prezzo_acquirente_cents',
      (private.preventivo_dominio('accessori_enologici'::public.dominio_merceologico,
                                  'privato'::public.classe_venditore,
                                  a.prezzo_unitario_cents, 1, null) ->> 'totaleCents')::integer,
    'pubblicato_at', a.pubblicato_at,
    'aggiornato_at', s.aggiornato_at,
    'venditore', jsonb_build_object('username', pp.username, 'avatar_url', pp.avatar_url),
    'acquistabile', false
  )
  from private.annunci_accessori a
  join private.annunci_accessori_snapshot s on s.annuncio_id = a.id
  join private.accessori_categorie c on c.id = s.categoria_id
  left join private.accessori_categorie g on g.id = c.parent_id
  join private.profili_pubblici pp on pp.user_id = a.seller_id
  where a.id = p_id and private.annuncio_accessorio_visibile(a.id);
$$;

revoke execute on function private.annuncio_accessorio_pubblico_json(uuid) from public, anon, authenticated;

create function public.annunci_accessori_pubblici_elenca(
  p_categoria text default null,
  p_limite integer default 24,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_limite integer := least(greatest(coalesce(p_limite, 24), 1), 60);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
begin
  if not private.annunci_accessori_pubblicazione_aperta() then
    return '[]'::jsonb;
  end if;
  if p_categoria is not null and p_categoria !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    return '[]'::jsonb;
  end if;
  return coalesce((
    select jsonb_agg(private.annuncio_accessorio_pubblico_json(s.id) order by s.pubblicato_at desc, s.id)
    from (
      select a.id, a.pubblicato_at
      from private.annunci_accessori a
      join private.annunci_accessori_snapshot sn on sn.annuncio_id = a.id
      join private.accessori_categorie c on c.id = sn.categoria_id
      left join private.accessori_categorie g on g.id = c.parent_id
      where a.stato = 'pubblicato'
        and (p_categoria is null or c.slug = p_categoria or g.slug = p_categoria)
        and private.annuncio_accessorio_visibile(a.id)
      order by a.pubblicato_at desc, a.id
      limit v_limite offset v_offset
    ) s
  ), '[]'::jsonb);
end;
$$;

comment on function public.annunci_accessori_pubblici_elenca(text, integer, integer) is
  'VPM-015B3: annunci Accessori visibili al pubblico (pubblicati, categoria approvata, venditore ammesso, pubblicazione aperta). Vuoto a pubblicazione chiusa. Nessun dato privato. Non e un percorso d''acquisto.';

create function public.annunci_accessori_pubblico_dettaglio(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_id is null then
    return null;
  end if;
  return private.annuncio_accessorio_pubblico_json(p_id);
end;
$$;

comment on function public.annunci_accessori_pubblico_dettaglio(uuid) is
  'VPM-015B3: un annuncio Accessori visibile al pubblico, oppure null. Non e un percorso d''acquisto.';

-- Storage: il bucket `cantina-accessori-foto` resta PRIVATO. Una firma e concessa
-- solo (a) al proprietario per la propria cartella (B1), (b) per le foto di un
-- accessorio esposto (B1), (c) per le foto dello snapshot di un annuncio
-- VISIBILE, (d) a un admin reale per le foto degli annunci in moderazione.
create function private.annuncio_accessorio_media_pubblica(p_percorso text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_percorso is not null and exists (
    select 1 from private.annunci_accessori_snapshot s
    where p_percorso = any (s.immagini) and private.annuncio_accessorio_visibile(s.annuncio_id)
  );
$$;

revoke all on function private.annuncio_accessorio_media_pubblica(text) from public;
grant execute on function private.annuncio_accessorio_media_pubblica(text) to anon, authenticated;

create function private.annuncio_accessorio_media_moderabile(p_percorso text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_percorso is not null and private.accessori_e_admin() and exists (
    select 1 from private.annunci_accessori_snapshot s
    join private.annunci_accessori a on a.id = s.annuncio_id
    where p_percorso = any (s.immagini) and a.stato <> 'ritirato'
  );
$$;

revoke all on function private.annuncio_accessorio_media_moderabile(text) from public, anon;
grant execute on function private.annuncio_accessorio_media_moderabile(text) to authenticated;

create policy "cantina_accessori_media_select_annunci_pubblicati"
on storage.objects
for select
to anon, authenticated
using (
  bucket_id = 'cantina-accessori-foto'
  and private.annuncio_accessorio_media_pubblica(name)
);

create policy "cantina_accessori_media_select_annunci_moderazione"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'cantina-accessori-foto'
  and private.annuncio_accessorio_media_moderabile(name)
);

-- Un file citato dallo snapshot di un annuncio non ritirato non si cancella.
create or replace function private.cantina_accessorio_media_cancellabile(p_percorso text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_percorso is not null
    and not exists (select 1 from private.cantina_accessori a where p_percorso = any (a.immagini))
    and not exists (
      select 1 from private.annunci_accessori_snapshot s
      join private.annunci_accessori an on an.id = s.annuncio_id
      where p_percorso = any (s.immagini) and an.stato <> 'ritirato'
    );
$$;

-- ---------------------------------------------------------------------------
-- [6] Moderazione: bersaglio, segnalazione, motore, porte
-- ---------------------------------------------------------------------------

alter table public.reports
  add column target_annuncio_accessorio_id uuid
    references private.annunci_accessori (id) on delete set null;

comment on column public.reports.target_annuncio_accessorio_id is
  'Bersaglio quando target_tipo = ''annuncio_accessorio''. on delete set null: la '
  'segnalazione sopravvive all''annuncio (target_label ne conserva il nome).';

create index reports_target_annuncio_accessorio_idx
  on public.reports (target_annuncio_accessorio_id) where target_annuncio_accessorio_id is not null;

alter table public.reports drop constraint reports_target_esclusivo;
alter table public.reports drop constraint reports_target_coerente;

alter table public.reports
  add constraint reports_target_esclusivo check (
    (case when target_listing_id is not null then 1 else 0 end)
    + (case when target_profile_id is not null then 1 else 0 end)
    + (case when target_message_id is not null then 1 else 0 end)
    + (case when target_conversation_id is not null then 1 else 0 end)
    + (case when target_review_id is not null then 1 else 0 end)
    + (case when target_post_id is not null then 1 else 0 end)
    + (case when target_risposta_id is not null then 1 else 0 end)
    + (case when target_annuncio_accessorio_id is not null then 1 else 0 end)
    <= 1
  );

alter table public.reports
  add constraint reports_target_coerente check (
    case target_tipo
      when 'annuncio' then target_profile_id is null and target_message_id is null
        and target_conversation_id is null and target_review_id is null
        and target_post_id is null and target_risposta_id is null
        and target_annuncio_accessorio_id is null
      when 'profilo' then target_listing_id is null and target_message_id is null
        and target_conversation_id is null and target_review_id is null
        and target_post_id is null and target_risposta_id is null
        and target_annuncio_accessorio_id is null
      when 'messaggio' then target_listing_id is null and target_profile_id is null
        and target_conversation_id is null and target_review_id is null
        and target_post_id is null and target_risposta_id is null
        and target_annuncio_accessorio_id is null
      when 'conversazione' then target_listing_id is null and target_profile_id is null
        and target_message_id is null and target_review_id is null
        and target_post_id is null and target_risposta_id is null
        and target_annuncio_accessorio_id is null
      when 'recensione' then target_listing_id is null and target_profile_id is null
        and target_message_id is null and target_conversation_id is null
        and target_post_id is null and target_risposta_id is null
        and target_annuncio_accessorio_id is null
      when 'post' then target_listing_id is null and target_profile_id is null
        and target_message_id is null and target_conversation_id is null
        and target_review_id is null and target_risposta_id is null
        and target_annuncio_accessorio_id is null
      when 'commento' then target_listing_id is null and target_profile_id is null
        and target_message_id is null and target_conversation_id is null
        and target_review_id is null and target_post_id is null
        and target_annuncio_accessorio_id is null
      when 'club' then target_listing_id is null and target_profile_id is null
        and target_message_id is null and target_conversation_id is null
        and target_review_id is null and target_post_id is null
        and target_risposta_id is null and club_slug is not null
        and target_annuncio_accessorio_id is null
      when 'annuncio_accessorio' then target_listing_id is null and target_profile_id is null
        and target_message_id is null and target_conversation_id is null
        and target_review_id is null and target_post_id is null
        and target_risposta_id is null and club_slug is null
      else false
    end
  );

insert into public.report_reasons (target_tipo, motivo, ordine) values
  ('annuncio_accessorio', 'Articolo alcolico o regolamentato', 1),
  ('annuncio_accessorio', 'Articolo vietato o pericoloso', 2),
  ('annuncio_accessorio', 'Foto non veritiere o riciclate', 3),
  ('annuncio_accessorio', 'Descrizione ingannevole', 4),
  ('annuncio_accessorio', 'Prezzo anomalo', 5),
  ('annuncio_accessorio', 'Annuncio duplicato', 6),
  ('annuncio_accessorio', 'Articolo contraffatto o frode', 7);

-- Un articolo vietato o regolamentato non e una segnalazione di priorita bassa.
-- Aggiunge un solo criterio (`regolament`, assente dai motivi gia in uso); gli
-- altri restano identici.
create or replace function private.report_priorita_da_motivo(p_motivo text)
returns public.report_priorita
language sql
immutable
set search_path = ''
as $$
  select case
    when lower(coalesce(p_motivo, '')) like any (array[
      '%truff%', '%frod%', '%pagament%', '%molest%', '%regolament%'
    ]) then 'alta'::public.report_priorita
    when lower(coalesce(p_motivo, '')) like any (array[
      '%offens%', '%falsa%', '%veritier%', '%ingannev%'
    ]) then 'media'::public.report_priorita
    else 'bassa'::public.report_priorita
  end;
$$;

create or replace function private.moderazione_bersaglio(p_report public.reports)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    p_report.target_listing_id, p_report.target_profile_id,
    p_report.target_message_id, p_report.target_conversation_id,
    p_report.target_review_id, p_report.target_post_id,
    p_report.target_risposta_id, p_report.target_annuncio_accessorio_id
  );
$$;

create or replace view public.moderation_report_queue
with (security_invoker = off, security_barrier = true) as
  select
    r.id,
    r.codice,
    r.target_tipo,
    r.target_label,
    coalesce(
      r.target_listing_id, r.target_profile_id, r.target_message_id,
      r.target_conversation_id, r.target_review_id,
      r.target_post_id, r.target_risposta_id, r.target_annuncio_accessorio_id
    ) as target_id,
    r.motivo,
    r.descrizione,
    r.foto,
    r.stato,
    r.priorita,
    r.reporter_id,
    rp.username as reporter_username,
    r.club_slug,
    r.created_at,
    r.updated_at
  from public.reports r
  join public.profiles rp on rp.id = r.reporter_id
  where exists (
    select 1 from public.user_roles ur
    where ur.user_id = (select auth.uid()) and ur.role = 'admin'
  );

-- Segnalazione: solo utenti autenticati con profilo. Una porta anonima sarebbe
-- una porta di spam senza identita ne rate limit per utente: non esiste.
create function public.segnalazione_annuncio_accessorio_invia(
  p_id uuid,
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
  v_seller uuid;
  v_nome text;
  v_descrizione text := btrim(coalesce(p_descrizione, ''));
  v_priorita public.report_priorita;
  v_codice text;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles pr where pr.id = v_uid) then
    raise exception 'Profilo richiesto per inviare una segnalazione.' using errcode = '42501';
  end if;

  perform private.rate_limit_consume('report:submit', 'user:' || v_uid::text, 10, 3600);

  -- Si segnala solo cio che si puo vedere: un annuncio non visibile e "non trovato".
  if p_id is null or not private.annuncio_accessorio_visibile(p_id) then
    raise exception 'Annuncio non trovato.' using errcode = 'P0001';
  end if;
  select a.seller_id, s.nome into v_seller, v_nome
  from private.annunci_accessori a
  join private.annunci_accessori_snapshot s on s.annuncio_id = a.id
  where a.id = p_id;
  if v_seller = v_uid then
    raise exception 'Non e possibile segnalare il proprio annuncio.' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.report_reasons rr
    where rr.target_tipo = 'annuncio_accessorio'::public.report_target_tipo and rr.motivo = p_motivo
  ) then
    raise exception 'Motivo non ammesso per questo tipo di bersaglio.' using errcode = '22023';
  end if;
  if length(v_descrizione) > 4000 then
    raise exception 'La descrizione non puo superare 4000 caratteri.' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.reports r
    where r.reporter_id = v_uid
      and r.target_tipo = 'annuncio_accessorio'::public.report_target_tipo
      and r.target_annuncio_accessorio_id = p_id
      and r.stato in ('inviata', 'in_revisione', 'info_richieste')
  ) then
    raise exception 'Hai gia una segnalazione aperta su questo annuncio.' using errcode = 'P0001';
  end if;

  v_priorita := private.report_priorita_da_motivo(p_motivo);
  v_codice := 'SEG-' || to_char(now(), 'YYYY') || '-'
    || lpad(nextval('public.reports_codice_seq')::text, 4, '0');

  insert into public.reports (
    codice, target_tipo, target_label, target_annuncio_accessorio_id,
    motivo, descrizione, foto, priorita, reporter_id
  ) values (
    v_codice, 'annuncio_accessorio'::public.report_target_tipo, v_nome, p_id,
    p_motivo, v_descrizione, '{}', v_priorita, v_uid
  )
  returning id into v_id;

  insert into public.report_events (report_id, visibile, testo, autore_id, autore_etichetta)
  values (v_id, true, 'Segnalazione ricevuta', null, 'Moderazione');

  return v_id;
end;
$$;

comment on function public.segnalazione_annuncio_accessorio_invia(uuid, text, text) is
  'Segnalazione di un annuncio Accessori visibile. Solo authenticated (nessuna porta anonima: serve l''identita per il rate limit e l''antiabuso). Entra nel dominio reports esistente.';

-- Motore unico dei provvedimenti. Le porte (azioni sulla pratica e porta diretta)
-- lo chiamano dopo avere verificato il moderatore; lui verifica lo stato, scrive
-- l'esito con il marcatore, registra l'audit e avvisa il venditore.
create function private.moderazione_annuncio_accessorio_transizione(
  p_attore uuid,
  p_id uuid,
  p_azione public.mod_action,
  p_motivazione text,
  p_report_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cantina uuid;
  v_a private.annunci_accessori%rowtype;
  v_item private.cantina_accessori%rowtype;
  v_snap private.annunci_accessori_snapshot%rowtype;
  v_motivo text := btrim(coalesce(p_motivazione, ''));
  v_label text;
  v_testo text;
begin
  if length(v_motivo) = 0 then
    raise exception 'Motivazione obbligatoria.' using errcode = '22023';
  end if;
  if p_azione not in ('sospensione'::public.mod_action, 'rimozione'::public.mod_action,
                      'richiesta_modifiche'::public.mod_action, 'ripristino'::public.mod_action) then
    raise exception 'Azione non gestita per questo bersaglio.' using errcode = 'P0001';
  end if;

  select a.cantina_accessorio_id into v_cantina from private.annunci_accessori a where a.id = p_id;
  if v_cantina is null then
    raise exception 'Annuncio non trovato.' using errcode = 'P0001';
  end if;
  -- Stesso ordine dei lock del venditore: accessorio, poi annuncio.
  select * into v_item from private.cantina_accessori where id = v_cantina for update;
  select * into v_a from private.annunci_accessori where id = p_id for update;
  select * into v_snap from private.annunci_accessori_snapshot where annuncio_id = p_id;

  perform set_config('vinae.annuncio_accessorio_moderazione', 'ok:' || p_id::text, true);

  if p_azione in ('sospensione'::public.mod_action, 'rimozione'::public.mod_action) then
    if v_a.stato = 'oscurato' and v_a.provvedimento = 'sospensione'
       and p_azione = 'rimozione'::public.mod_action then
      -- La sospensione si aggrava in rimozione senza riaprire nulla.
      update private.annunci_accessori
      set provvedimento = 'rimozione', stato_motivo = v_motivo,
          stato_aggiornato_da = p_attore, stato_aggiornato_at = now()
      where id = p_id;
    elsif v_a.stato in ('pubblicato', 'modifiche_richieste') then
      update private.annunci_accessori
      set stato = 'oscurato',
          provvedimento = case when p_azione = 'rimozione'::public.mod_action
                               then 'rimozione' else 'sospensione' end,
          stato_prima = v_a.stato, stato_motivo = v_motivo,
          stato_aggiornato_da = p_attore, stato_aggiornato_at = now(), oscurato_at = now()
      where id = p_id;
    else
      raise exception 'Transizione non ammessa da %.', v_a.stato using errcode = 'P0001';
    end if;
    v_testo := 'Un tuo annuncio di accessori e stato oscurato da Vinea. Apri la Cantina per leggere il motivo.';
  elsif p_azione = 'richiesta_modifiche'::public.mod_action then
    if v_a.stato <> 'pubblicato' then
      raise exception 'Transizione non ammessa da %.', v_a.stato using errcode = 'P0001';
    end if;
    update private.annunci_accessori
    set stato = 'modifiche_richieste', stato_motivo = v_motivo,
        stato_aggiornato_da = p_attore, stato_aggiornato_at = now(),
        hash_richiesta = private.annuncio_accessorio_contenuto_hash(
          v_a.quantita, v_a.prezzo_unitario_cents, v_a.condizione, v_a.descrizione,
          v_a.peso_g, v_a.lunghezza_mm, v_a.larghezza_mm, v_a.altezza_mm, v_a.fragile,
          v_snap.nome, v_snap.marchio, v_snap.immagini)
    where id = p_id;
    v_testo := 'Vinea ha richiesto modifiche a un tuo annuncio di accessori. Apri la Cantina per i dettagli.';
  else
    if v_a.stato = 'oscurato' then
      update private.annunci_accessori
      set stato = v_a.stato_prima, provvedimento = null, oscurato_at = null, stato_prima = null,
          stato_motivo = v_motivo, stato_aggiornato_da = p_attore, stato_aggiornato_at = now()
      where id = p_id;
    elsif v_a.stato = 'modifiche_richieste' then
      update private.annunci_accessori
      set stato = 'pubblicato', stato_motivo = v_motivo,
          stato_aggiornato_da = p_attore, stato_aggiornato_at = now(), hash_richiesta = null
      where id = p_id;
    else
      raise exception 'Transizione non ammessa da %.', v_a.stato using errcode = 'P0001';
    end if;
    v_testo := 'Un tuo annuncio di accessori e stato riaperto da Vinea.';
  end if;

  perform set_config('vinae.annuncio_accessorio_moderazione', '', true);

  v_label := left(coalesce(v_snap.nome, v_item.nome), 200);
  perform private.audit_registra(
    p_attore_id => p_attore,
    p_azione => p_azione,
    p_target_tipo => 'annuncio_accessorio'::public.report_target_tipo,
    p_target_id => p_id,
    p_target_label => v_label,
    p_motivazione => v_motivo,
    p_report_id => p_report_id
  );

  insert into public.notifications (recipient_id, category, event_type, body, dedupe_key)
  values (v_a.seller_id, 'marketplace', 'accessori_annuncio_moderato', v_testo,
          'accessori-mod:' || p_id::text || ':' || gen_random_uuid()::text)
  on conflict (recipient_id, dedupe_key) do nothing;
end;
$$;

revoke execute on function private.moderazione_annuncio_accessorio_transizione(
  uuid, uuid, public.mod_action, text, uuid) from public, anon, authenticated;

-- Le quattro azioni sulla pratica che agiscono sul bersaglio. Corpi identici a
-- quelli della 9b/12c; cambia solo il ramo nuovo. Firme e GRANT invariati.
create or replace function public.moderazione_richiesta_modifiche(
  p_report_id uuid,
  p_motivazione text,
  p_nota_interna text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_report public.reports;
  v_attore uuid;
begin
  v_report := private.moderazione_pratica(
    p_report_id,
    'in_revisione'::public.report_stato,
    p_motivazione, p_nota_interna,
    'Sono state richieste modifiche al contenuto segnalato'
  );
  v_attore := (select auth.uid());

  if v_report.target_tipo = 'annuncio' and v_report.target_listing_id is not null then
    perform private.moderazione_annuncio_transizione(
      v_attore, v_report.target_listing_id,
      'modifiche_richieste'::public.listing_stato,
      'richiesta_modifiche'::public.mod_action,
      p_motivazione,
      array['bozza', 'in_revisione', 'attivo']::public.listing_stato[],
      p_report_id
    );
  elsif v_report.target_tipo = 'annuncio_accessorio'
        and v_report.target_annuncio_accessorio_id is not null then
    perform private.moderazione_annuncio_accessorio_transizione(
      v_attore, v_report.target_annuncio_accessorio_id,
      'richiesta_modifiche'::public.mod_action, p_motivazione, p_report_id
    );
  else
    perform private.audit_registra(
      p_attore_id => v_attore,
      p_azione => 'richiesta_modifiche'::public.mod_action,
      p_target_tipo => v_report.target_tipo,
      p_target_id => private.moderazione_bersaglio(v_report),
      p_target_label => v_report.target_label,
      p_motivazione => p_motivazione,
      p_report_id => p_report_id
    );
  end if;
end;
$$;

create or replace function public.moderazione_sospensione(
  p_report_id uuid,
  p_motivazione text,
  p_durata text default null,
  p_nota_interna text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_report public.reports;
  v_attore uuid;
begin
  v_report := private.moderazione_pratica(
    p_report_id,
    'risolta'::public.report_stato,
    p_motivazione, p_nota_interna,
    'Il contenuto segnalato e stato sospeso'
  );
  v_attore := (select auth.uid());

  if v_report.target_tipo = 'profilo' and v_report.target_profile_id is not null then
    perform private.moderazione_utente_provvedimento(
      v_attore, v_report.target_profile_id, p_motivazione, p_durata, p_report_id
    );
  elsif v_report.target_tipo = 'annuncio' and v_report.target_listing_id is not null then
    perform private.moderazione_annuncio_transizione(
      v_attore, v_report.target_listing_id,
      'sospeso'::public.listing_stato,
      'sospensione'::public.mod_action,
      p_motivazione,
      array['bozza', 'in_revisione', 'modifiche_richieste',
            'attivo']::public.listing_stato[],
      p_report_id
    );
  elsif v_report.target_tipo = 'annuncio_accessorio'
        and v_report.target_annuncio_accessorio_id is not null then
    perform private.moderazione_annuncio_accessorio_transizione(
      v_attore, v_report.target_annuncio_accessorio_id,
      'sospensione'::public.mod_action, p_motivazione, p_report_id
    );
  else
    perform private.audit_registra(
      p_attore_id => v_attore,
      p_azione => 'sospensione'::public.mod_action,
      p_target_tipo => v_report.target_tipo,
      p_target_id => private.moderazione_bersaglio(v_report),
      p_target_label => v_report.target_label,
      p_motivazione => p_motivazione,
      p_durata => p_durata,
      p_report_id => p_report_id
    );
  end if;
end;
$$;

create or replace function public.moderazione_rimozione(
  p_report_id uuid,
  p_motivazione text,
  p_nota_interna text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_report public.reports;
  v_attore uuid;
begin
  v_report := private.moderazione_pratica(
    p_report_id,
    'risolta'::public.report_stato,
    p_motivazione, p_nota_interna,
    'Il contenuto segnalato e stato rimosso'
  );
  v_attore := (select auth.uid());

  if v_report.target_tipo = 'profilo' and v_report.target_profile_id is not null then
    perform private.moderazione_utente_provvedimento(
      v_attore, v_report.target_profile_id, p_motivazione, null, p_report_id,
      true
    );
  elsif v_report.target_tipo = 'annuncio' and v_report.target_listing_id is not null then
    perform private.moderazione_annuncio_transizione(
      v_attore, v_report.target_listing_id,
      'rifiutato'::public.listing_stato,
      'rimozione'::public.mod_action,
      p_motivazione,
      array['bozza', 'in_revisione', 'modifiche_richieste', 'attivo',
            'sospeso']::public.listing_stato[],
      p_report_id
    );
  elsif v_report.target_tipo in ('post', 'commento') then
    perform private.moderazione_contenuto_club_transizione(
      v_attore, v_report, true, 'rimozione'::public.mod_action, p_motivazione
    );
  elsif v_report.target_tipo = 'annuncio_accessorio'
        and v_report.target_annuncio_accessorio_id is not null then
    perform private.moderazione_annuncio_accessorio_transizione(
      v_attore, v_report.target_annuncio_accessorio_id,
      'rimozione'::public.mod_action, p_motivazione, p_report_id
    );
  else
    perform private.audit_registra(
      p_attore_id => v_attore,
      p_azione => 'rimozione'::public.mod_action,
      p_target_tipo => v_report.target_tipo,
      p_target_id => private.moderazione_bersaglio(v_report),
      p_target_label => v_report.target_label,
      p_motivazione => p_motivazione,
      p_report_id => p_report_id
    );
  end if;
end;
$$;

create or replace function public.moderazione_ripristino(
  p_report_id uuid,
  p_motivazione text,
  p_nota_interna text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_report public.reports;
  v_attore uuid;
begin
  v_report := private.moderazione_pratica(
    p_report_id,
    'risolta'::public.report_stato,
    p_motivazione, p_nota_interna,
    'Il contenuto segnalato e stato ripristinato'
  );
  v_attore := (select auth.uid());

  if v_report.target_tipo = 'profilo' and v_report.target_profile_id is not null then
    perform private.moderazione_utente_ripristina(
      v_attore, v_report.target_profile_id, p_motivazione, p_report_id
    );
  elsif v_report.target_tipo = 'annuncio' and v_report.target_listing_id is not null then
    perform private.moderazione_annuncio_transizione(
      v_attore, v_report.target_listing_id,
      'attivo'::public.listing_stato,
      'ripristino'::public.mod_action,
      p_motivazione,
      array['in_revisione', 'modifiche_richieste', 'sospeso',
            'rifiutato']::public.listing_stato[],
      p_report_id
    );
  elsif v_report.target_tipo in ('post', 'commento') then
    perform private.moderazione_contenuto_club_transizione(
      v_attore, v_report, false, 'ripristino'::public.mod_action, p_motivazione
    );
  elsif v_report.target_tipo = 'annuncio_accessorio'
        and v_report.target_annuncio_accessorio_id is not null then
    perform private.moderazione_annuncio_accessorio_transizione(
      v_attore, v_report.target_annuncio_accessorio_id,
      'ripristino'::public.mod_action, p_motivazione, p_report_id
    );
  else
    perform private.audit_registra(
      p_attore_id => v_attore,
      p_azione => 'ripristino'::public.mod_action,
      p_target_tipo => v_report.target_tipo,
      p_target_id => private.moderazione_bersaglio(v_report),
      p_target_label => v_report.target_label,
      p_motivazione => p_motivazione,
      p_report_id => p_report_id
    );
  end if;
end;
$$;

-- Porta diretta dell'amministrazione, senza una segnalazione: oscuramento
-- immediato, richiesta di modifiche, ripristino. Stesso motore delle azioni
-- sulla pratica.
create function public.annunci_accessori_admin_modera(p_id uuid, p_azione text, p_motivazione text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attore uuid := private.moderazione_attore();
  v_azione public.mod_action;
begin
  v_azione := case p_azione
    when 'oscura' then 'sospensione'::public.mod_action
    when 'rimuovi' then 'rimozione'::public.mod_action
    when 'richiedi_modifiche' then 'richiesta_modifiche'::public.mod_action
    when 'ripristina' then 'ripristino'::public.mod_action
  end;
  if v_azione is null then
    raise exception 'Azione non valida.' using errcode = '22023', hint = 'dati_non_validi';
  end if;
  perform private.moderazione_annuncio_accessorio_transizione(v_attore, p_id, v_azione, p_motivazione, null);
end;
$$;

comment on function public.annunci_accessori_admin_modera(uuid, text, text) is
  'Provvedimento diretto su un annuncio Accessori (oscura, rimuovi, richiedi_modifiche, ripristina). Solo admin; motivazione obbligatoria; audit_log e notifica al venditore.';

create function public.annunci_accessori_admin_elenca(p_filtro text default 'tutti', p_limite integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_limite integer := least(greatest(coalesce(p_limite, 50), 1), 100);
  v_filtro text := coalesce(p_filtro, 'tutti');
begin
  perform private.accessori_admin_richiesto();
  if v_filtro not in ('tutti', 'pubblicati', 'segnalati', 'oscurati', 'modifiche') then
    raise exception 'Filtro non valido.' using errcode = '22023', hint = 'dati_non_validi';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'id', x.id, 'stato', x.stato, 'provvedimento', x.provvedimento,
        'nome', x.nome, 'venditore', x.username, 'quantita', x.quantita,
        'prezzo_unitario_cents', x.prezzo_unitario_cents, 'versione', x.versione,
        'pubblicato_at', x.pubblicato_at, 'segnalazioni_aperte', x.aperte,
        'segnalazioni_totali', x.totali) order by x.aperte desc, x.pubblicato_at desc, x.id)
    from (
      select a.id, a.stato, a.provvedimento, s.nome, pr.username, a.quantita,
             a.prezzo_unitario_cents, a.versione, a.pubblicato_at,
             (select count(*) from public.reports r
              where r.target_annuncio_accessorio_id = a.id
                and r.stato in ('inviata', 'in_revisione', 'info_richieste'))::integer as aperte,
             (select count(*) from public.reports r
              where r.target_annuncio_accessorio_id = a.id)::integer as totali
      from private.annunci_accessori a
      join private.annunci_accessori_snapshot s on s.annuncio_id = a.id
      join public.profiles pr on pr.id = a.seller_id
      where a.stato in ('pubblicato', 'modifiche_richieste', 'oscurato')
        and (v_filtro = 'tutti'
             or (v_filtro = 'pubblicati' and a.stato = 'pubblicato')
             or (v_filtro = 'oscurati' and a.stato = 'oscurato')
             or (v_filtro = 'modifiche' and a.stato = 'modifiche_richieste')
             or (v_filtro = 'segnalati' and exists (
                   select 1 from public.reports r
                   where r.target_annuncio_accessorio_id = a.id
                     and r.stato in ('inviata', 'in_revisione', 'info_richieste'))))
      order by aperte desc, a.pubblicato_at desc, a.id
      limit v_limite
    ) x
  ), '[]'::jsonb);
end;
$$;

comment on function public.annunci_accessori_admin_elenca(text, integer) is
  'Annunci Accessori pubblicati, in modifica o oscurati, con le segnalazioni (filtri: tutti, pubblicati, segnalati, oscurati, modifiche). Solo admin.';

create function public.annunci_accessori_admin_dettaglio(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_res jsonb;
begin
  perform private.accessori_admin_richiesto();
  select jsonb_build_object(
    'id', a.id, 'stato', a.stato, 'provvedimento', a.provvedimento,
    'stato_motivo', a.stato_motivo, 'stato_aggiornato_at', a.stato_aggiornato_at,
    'versione', a.versione, 'pubblicato_at', a.pubblicato_at,
    'venditore', pr.username, 'venditore_stato', pr.stato_utente,
    'nome', s.nome, 'marchio', s.marchio, 'categoria', c.nome,
    'condizione', a.condizione, 'quantita', a.quantita, 'descrizione', a.descrizione,
    'prezzo_unitario_cents', a.prezzo_unitario_cents, 'foto', to_jsonb(s.immagini),
    'visibile', private.annuncio_accessorio_visibile(a.id),
    'segnalazioni', coalesce((
      select jsonb_agg(jsonb_build_object(
          'id', r.id, 'codice', r.codice, 'motivo', r.motivo, 'descrizione', r.descrizione,
          'stato', r.stato, 'priorita', r.priorita, 'created_at', r.created_at)
        order by r.created_at desc)
      from public.reports r where r.target_annuncio_accessorio_id = a.id), '[]'::jsonb),
    'storico', coalesce((
      select jsonb_agg(jsonb_build_object(
          'azione', l.azione, 'attore', l.attore_username, 'motivazione', l.motivazione, 'ts', l.ts)
        order by l.ts desc)
      from public.audit_log l
      where l.target_tipo = 'annuncio_accessorio' and l.target_id = a.id), '[]'::jsonb)
  ) into v_res
  from private.annunci_accessori a
  join private.annunci_accessori_snapshot s on s.annuncio_id = a.id
  join private.accessori_categorie c on c.id = s.categoria_id
  join public.profiles pr on pr.id = a.seller_id
  where a.id = p_id;
  return v_res;
end;
$$;

comment on function public.annunci_accessori_admin_dettaglio(uuid) is
  'Dettaglio per la moderazione: snapshot, offerta, segnalazioni e storico delle decisioni. Mai note private. Solo admin.';

-- ---------------------------------------------------------------------------
-- [7] Porte del venditore e dell'amministrazione
-- ---------------------------------------------------------------------------

-- Forma dell'annuncio per il proprietario: aggiunge stato di pubblicazione ed
-- esito della moderazione (motivo comprensibile; mai chi ha deciso).
create or replace function private.annuncio_accessorio_json(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', a.id,
    'cantina_id', a.cantina_accessorio_id,
    'stato', a.stato,
    'quantita', a.quantita,
    'prezzo_unitario_cents', a.prezzo_unitario_cents,
    'condizione', a.condizione,
    'descrizione', a.descrizione,
    'conforme', a.dichiarazione_conforme,
    'spedizione', jsonb_build_object(
      'peso_g', a.peso_g,
      'lunghezza_mm', a.lunghezza_mm,
      'larghezza_mm', a.larghezza_mm,
      'altezza_mm', a.altezza_mm,
      'fragile', a.fragile
    ),
    'posseduti', c.quantita,
    'impegnati', private.annuncio_accessorio_impegnati(c.id),
    'disponibili', greatest(c.quantita - private.annuncio_accessorio_impegnati(c.id), 0),
    'foto', cardinality(c.immagini),
    'inviato_at', a.inviato_at,
    'ritirato_at', a.ritirato_at,
    'created_at', a.created_at,
    'updated_at', a.updated_at,
    'pubblicato_at', a.pubblicato_at,
    'versione', a.versione,
    'pubblico', private.annuncio_accessorio_visibile(a.id),
    'moderazione', case when a.stato in ('modifiche_richieste', 'oscurato') then
      jsonb_build_object('provvedimento', a.provvedimento, 'motivo', a.stato_motivo,
                         'aggiornato_at', a.stato_aggiornato_at)
      else null end
  )
  from private.annunci_accessori a
  join private.cantina_accessori c on c.id = a.cantina_accessorio_id
  where a.id = p_id;
$$;

create or replace function public.annunci_accessori_stato()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
  v_v record;
begin
  select * into v_v from private.annuncio_accessorio_venditore(v_uid);
  return jsonb_build_object(
    'abilitata', private.annunci_accessori_consentita(),
    'vendite_attive', false,
    'pubblicazione_aperta', private.annunci_accessori_pubblicazione_aperta(),
    'classe', v_v.classe,
    'venditore_ammesso', v_v.ammesso,
    'motivo', v_v.motivo
  );
end;
$$;

-- Gli annunci sono dati del proprietario: li vede sempre, anche a preparazione
-- spenta (altrimenti non saprebbe perche un annuncio e stato oscurato).
create or replace function public.annunci_accessori_elenca(p_ritirati boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
begin
  return coalesce((
    select jsonb_agg(private.annuncio_accessorio_json(s.id) order by s.created_at desc, s.id)
    from (
      select a.id, a.created_at
      from private.annunci_accessori a
      where a.seller_id = v_uid
        and ((a.stato = 'ritirato') = coalesce(p_ritirati, false))
      order by a.created_at desc, a.id
      limit 100
    ) s
  ), '[]'::jsonb);
end;
$$;

-- Salva: crea o aggiorna una bozza, corregge un annuncio con modifiche
-- richieste, oppure AGGIORNA in modo controllato un annuncio pubblicato (la
-- guardia incrementa la versione e rifa lo snapshot; i requisiti si ricontrollano).
create or replace function public.annunci_accessori_salva(p_id uuid, p_dati jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
  v_chiave text;
  v_old private.annunci_accessori%rowtype;
  v_item private.cantina_accessori%rowtype;
  v_cantina uuid;
  v_quantita integer;
  v_prezzo integer;
  v_condizione text;
  v_desc text;
  v_conforme boolean;
  v_peso integer;
  v_lung integer;
  v_larg integer;
  v_alt integer;
  v_fragile boolean;
  v_v record;
  v_altri integer;
  v_esiste boolean;
begin
  if p_id is null or p_dati is null or jsonb_typeof(p_dati) <> 'object' then
    raise exception 'Dati non validi.' using errcode = '22023', hint = 'dati_non_validi';
  end if;
  for v_chiave in select jsonb_object_keys(p_dati) loop
    if v_chiave <> all (array['cantina_id', 'quantita', 'prezzo_unitario_cents', 'condizione',
                              'descrizione', 'conforme', 'peso_g', 'lunghezza_mm',
                              'larghezza_mm', 'altezza_mm', 'fragile']) then
      raise exception 'Campo non ammesso.' using errcode = '22023', hint = 'campo_sconosciuto';
    end if;
  end loop;

  if not private.annunci_accessori_consentita() then
    raise exception 'La preparazione degli annunci non e ancora attiva.'
      using errcode = '42501', hint = 'funzione_non_attiva';
  end if;

  select a.cantina_accessorio_id into v_cantina
  from private.annunci_accessori a where a.id = p_id and a.seller_id = v_uid;
  v_esiste := v_cantina is not null;
  if not v_esiste then
    if exists (select 1 from private.annunci_accessori a where a.id = p_id) then
      raise exception 'Annuncio non trovato.' using errcode = 'P0001', hint = 'non_trovato';
    end if;
    if p_dati ? 'cantina_id'
       and jsonb_typeof(p_dati -> 'cantina_id') = 'string'
       and (p_dati ->> 'cantina_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      v_cantina := (p_dati ->> 'cantina_id')::uuid;
    else
      raise exception 'Scegli l''accessorio.' using errcode = '22023', hint = 'accessorio_obbligatorio';
    end if;
  elsif p_dati ? 'cantina_id' and (p_dati ->> 'cantina_id') is distinct from v_cantina::text then
    raise exception 'L''accessorio di un annuncio non cambia.' using errcode = '22023', hint = 'annuncio_immutabile';
  end if;

  select * into v_item from private.cantina_accessori
  where id = v_cantina and owner_id = v_uid for update;
  if v_item.id is null then
    raise exception 'Accessorio non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;

  select * into v_old from private.annunci_accessori where id = p_id for update;
  if v_old.id is not null then
    if v_old.seller_id <> v_uid then
      raise exception 'Annuncio non trovato.' using errcode = 'P0001', hint = 'non_trovato';
    end if;
    if v_old.cantina_accessorio_id <> v_cantina then
      raise exception 'L''accessorio di un annuncio non cambia.' using errcode = '22023', hint = 'annuncio_immutabile';
    end if;
    v_esiste := true;
  elsif v_esiste then
    raise exception 'Annuncio non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  if v_esiste and v_old.stato not in ('bozza', 'modifiche_richieste', 'pubblicato') then
    raise exception 'Questo annuncio non si modifica in questo stato.'
      using errcode = '22023', hint = 'annuncio_non_modificabile';
  end if;

  select * into v_v from private.annuncio_accessorio_venditore(v_uid);
  if not v_v.ammesso then
    raise exception 'Non puoi preparare annunci di accessori.'
      using errcode = '42501', hint = v_v.motivo;
  end if;
  if v_item.archiviato_at is not null then
    raise exception 'Un accessorio archiviato non si mette in vendita.'
      using errcode = '22023', hint = 'accessorio_archiviato';
  end if;
  if not private.annuncio_accessorio_categoria_vendibile(v_item.categoria_id) then
    raise exception 'Questa categoria non e ancora vendibile.'
      using errcode = '22023', hint = 'categoria_non_vendibile';
  end if;

  v_quantita := case when p_dati ? 'quantita'
    then private.annunci_accessori_intero(p_dati -> 'quantita', 1, 120, 'quantita_non_valida')
    else v_old.quantita end;
  v_prezzo := case when p_dati ? 'prezzo_unitario_cents'
    then private.annunci_accessori_intero(p_dati -> 'prezzo_unitario_cents', 100, 1000000, 'prezzo_non_valido')
    else v_old.prezzo_unitario_cents end;
  if v_quantita is null then
    raise exception 'Indica la quantita.' using errcode = '22023', hint = 'quantita_non_valida';
  end if;
  if v_prezzo is null then
    raise exception 'Indica il prezzo.' using errcode = '22023', hint = 'prezzo_non_valido';
  end if;

  v_condizione := case when p_dati ? 'condizione' then p_dati ->> 'condizione'
    else coalesce(v_old.condizione, v_item.condizione) end;
  if v_condizione is null or v_condizione not in ('nuovo', 'come_nuovo', 'usato', 'da_collezione') then
    raise exception 'Condizione non valida.' using errcode = '22023', hint = 'condizione_non_valida';
  end if;

  v_desc := case when p_dati ? 'descrizione'
    then private.cantina_accessori_testo(p_dati -> 'descrizione', 0, 1000, 'descrizione_non_valida')
    else coalesce(v_old.descrizione, '') end;

  if p_dati ? 'conforme' then
    if jsonb_typeof(p_dati -> 'conforme') <> 'boolean' then
      raise exception 'Dichiarazione non valida.' using errcode = '22023', hint = 'dichiarazione_non_valida';
    end if;
    v_conforme := (p_dati ->> 'conforme')::boolean;
  else
    v_conforme := coalesce(v_old.dichiarazione_conforme, false);
  end if;

  v_peso := case when not (p_dati ? 'peso_g') then v_old.peso_g
    when jsonb_typeof(p_dati -> 'peso_g') = 'null' then null
    else private.annunci_accessori_intero(p_dati -> 'peso_g', 1, 30000, 'spedizione_non_valida') end;
  v_lung := case when not (p_dati ? 'lunghezza_mm') then v_old.lunghezza_mm
    when jsonb_typeof(p_dati -> 'lunghezza_mm') = 'null' then null
    else private.annunci_accessori_intero(p_dati -> 'lunghezza_mm', 1, 1500, 'spedizione_non_valida') end;
  v_larg := case when not (p_dati ? 'larghezza_mm') then v_old.larghezza_mm
    when jsonb_typeof(p_dati -> 'larghezza_mm') = 'null' then null
    else private.annunci_accessori_intero(p_dati -> 'larghezza_mm', 1, 1500, 'spedizione_non_valida') end;
  v_alt := case when not (p_dati ? 'altezza_mm') then v_old.altezza_mm
    when jsonb_typeof(p_dati -> 'altezza_mm') = 'null' then null
    else private.annunci_accessori_intero(p_dati -> 'altezza_mm', 1, 1500, 'spedizione_non_valida') end;
  if (v_lung is null) <> (v_larg is null) or (v_larg is null) <> (v_alt is null) then
    raise exception 'Indica tutte e tre le misure o nessuna.' using errcode = '22023', hint = 'spedizione_non_valida';
  end if;
  if p_dati ? 'fragile' then
    if jsonb_typeof(p_dati -> 'fragile') <> 'boolean' then
      raise exception 'Valore non valido.' using errcode = '22023', hint = 'spedizione_non_valida';
    end if;
    v_fragile := (p_dati ->> 'fragile')::boolean;
  else
    v_fragile := coalesce(v_old.fragile, false);
  end if;

  select coalesce(sum(a.quantita), 0) into v_altri
  from private.annunci_accessori a
  where a.cantina_accessorio_id = v_cantina and a.stato <> 'ritirato' and a.id <> p_id;
  if v_quantita + v_altri > v_item.quantita then
    raise exception 'Quantita superiore a quella disponibile.'
      using errcode = '22023', hint = 'quantita_non_disponibile';
  end if;

  if not v_esiste then
    if exists (select 1 from private.annunci_accessori a
               where a.cantina_accessorio_id = v_cantina and a.stato <> 'ritirato') then
      raise exception 'Questo accessorio ha gia un annuncio aperto.'
        using errcode = '22023', hint = 'annuncio_gia_aperto';
    end if;
    if (select count(*) from private.annunci_accessori a
        where a.seller_id = v_uid and a.stato <> 'ritirato') >= 50 then
      raise exception 'Hai raggiunto il numero massimo di annunci aperti.'
        using errcode = '22023', hint = 'limite_raggiunto';
    end if;
    insert into private.annunci_accessori
      (id, seller_id, cantina_accessorio_id, quantita, prezzo_unitario_cents, condizione,
       descrizione, dichiarazione_conforme, peso_g, lunghezza_mm, larghezza_mm, altezza_mm, fragile)
    values
      (p_id, v_uid, v_cantina, v_quantita, v_prezzo, v_condizione,
       v_desc, v_conforme, v_peso, v_lung, v_larg, v_alt, v_fragile);
  else
    if v_old.stato = 'pubblicato' then
      perform set_config('vinae.annuncio_accessorio_aggiorna', 'ok:' || p_id::text, true);
    end if;
    update private.annunci_accessori
    set quantita = v_quantita, prezzo_unitario_cents = v_prezzo, condizione = v_condizione,
        descrizione = v_desc, dichiarazione_conforme = v_conforme, peso_g = v_peso,
        lunghezza_mm = v_lung, larghezza_mm = v_larg, altezza_mm = v_alt, fragile = v_fragile
    where id = p_id;
    perform set_config('vinae.annuncio_accessorio_aggiorna', '', true);
  end if;

  return private.annuncio_accessorio_json(p_id);
end;
$$;

-- Pubblica: sostituisce la porta che rifiutava sempre. Nessuna approvazione
-- preventiva; la guardia verifica tutti i requisiti (interruttore, categoria,
-- venditore, foto, dichiarazione, quantita, anti-elusione).
create or replace function public.annunci_accessori_pubblica(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
  v_cantina uuid;
  v_a private.annunci_accessori%rowtype;
begin
  if not private.annunci_accessori_pubblicazione_aperta() then
    raise exception 'La pubblicazione degli annunci Accessori non e ancora aperta.'
      using errcode = '42501', hint = 'pubblicazione_chiusa';
  end if;
  if not private.annunci_accessori_consentita() then
    raise exception 'La preparazione degli annunci non e ancora attiva.'
      using errcode = '42501', hint = 'funzione_non_attiva';
  end if;

  select a.cantina_accessorio_id into v_cantina
  from private.annunci_accessori a where a.id = p_id and a.seller_id = v_uid;
  if v_cantina is null then
    raise exception 'Annuncio non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  perform 1 from private.cantina_accessori c where c.id = v_cantina for update;
  perform 1 from private.partners p where p.titolare_id = v_uid order by p.id for share;

  select * into v_a from private.annunci_accessori where id = p_id for update;
  if v_a.stato = 'pubblicato' then
    return private.annuncio_accessorio_json(p_id);
  end if;
  if v_a.stato not in ('bozza', 'modifiche_richieste') then
    raise exception 'Questo annuncio non si pubblica da qui.'
      using errcode = '22023', hint = 'transizione_non_ammessa';
  end if;

  update private.annunci_accessori set stato = 'pubblicato' where id = p_id;
  return private.annuncio_accessorio_json(p_id);
end;
$$;

comment on function public.annunci_accessori_pubblica(uuid) is
  'Pubblica un annuncio Accessori del chiamante senza approvazione preventiva, se interruttore, categoria, venditore e requisiti lo consentono (la guardia li verifica per ogni writer). Pubblicare NON rende l''annuncio acquistabile.';

-- Transizioni del venditore: ritiro (sempre possibile), ritorno in bozza di un
-- annuncio pubblicato. "In revisione" non esiste piu; da modifiche_richieste si
-- torna pubblici solo correggendo e ripubblicando, mai passando dalla bozza.
create or replace function public.annunci_accessori_transizione(p_id uuid, p_a text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
  v_cantina uuid;
  v_a private.annunci_accessori%rowtype;
begin
  if p_a is null or p_a not in ('bozza', 'ritirato') then
    raise exception 'Passaggio non ammesso.' using errcode = '22023', hint = 'transizione_non_ammessa';
  end if;
  if p_a <> 'ritirato' and not private.annunci_accessori_consentita() then
    raise exception 'La preparazione degli annunci non e ancora attiva.'
      using errcode = '42501', hint = 'funzione_non_attiva';
  end if;

  select a.cantina_accessorio_id into v_cantina
  from private.annunci_accessori a where a.id = p_id and a.seller_id = v_uid;
  if v_cantina is null then
    raise exception 'Annuncio non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  perform 1 from private.cantina_accessori c where c.id = v_cantina for update;
  perform 1 from private.partners p where p.titolare_id = v_uid order by p.id for share;

  select * into v_a from private.annunci_accessori where id = p_id for update;
  if v_a.stato = p_a then
    return private.annuncio_accessorio_json(p_id);
  end if;
  if v_a.stato = 'ritirato' then
    raise exception 'Un annuncio ritirato non si modifica.'
      using errcode = '22023', hint = 'annuncio_ritirato';
  end if;
  if p_a = 'bozza' and v_a.stato <> 'pubblicato' then
    raise exception 'Passaggio non ammesso.' using errcode = '22023', hint = 'transizione_non_ammessa';
  end if;

  update private.annunci_accessori
  set stato = p_a,
      ritirato_at = case when p_a = 'ritirato' then now() else null end
  where id = p_id;
  return private.annuncio_accessorio_json(p_id);
end;
$$;

comment on function public.annunci_accessori_transizione(uuid, text) is
  'Ritira un annuncio Accessori del chiamante (sempre) o riporta in bozza uno pubblicato. Non esiste uno stato acquistabile.';

-- Admin: interruttore di pubblicazione e categorie pubblicabili.
create or replace function public.annunci_accessori_admin_stato()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.accessori_admin_richiesto();
  return jsonb_build_object(
    'preparazione_attiva', coalesce(
      (select i.preparazione_attiva from private.annunci_accessori_impostazioni i), false),
    'pubblicazione_attiva', coalesce(
      (select i.pubblicazione_attiva from private.annunci_accessori_impostazioni i), false),
    'cantina_funzione_attiva', private.cantina_accessori_funzione_attiva(),
    'puo_rilasciare', private.accessori_puo_rilasciare(),
    'categorie_pubblicabili', (
      select count(*) from private.annunci_accessori_categorie_pubblicabili where pubblicabile)
  );
end;
$$;

create function public.annunci_accessori_admin_pubblicazione_imposta(p_attiva boolean, p_motivo text)
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
    raise exception 'Il cambio di interruttore richiede un motivo.' using errcode = '22023', hint = 'motivo_obbligatorio';
  end if;

  perform set_config('vinae.accessori_rilascio', 'rilascio:' || v_admin::text, true);
  update private.annunci_accessori_impostazioni
  set pubblicazione_attiva = p_attiva, aggiornato_da = v_admin where singleton;
  perform set_config('vinae.accessori_rilascio', '', true);

  insert into private.accessori_registro (admin_id, azione, oggetto, motivo)
  values (v_admin, 'annunci_pubblicazione' || case when p_attiva then '_accendi' else '_spegni' end,
          'annunci_pubblicazione', v_motivo);

  return jsonb_build_object(
    'preparazione_attiva', coalesce(
      (select i.preparazione_attiva from private.annunci_accessori_impostazioni i), false),
    'pubblicazione_attiva', coalesce(
      (select i.pubblicazione_attiva from private.annunci_accessori_impostazioni i), false)
  );
end;
$$;

comment on function public.annunci_accessori_admin_pubblicazione_imposta(boolean, text) is
  'Accende (solo con il ruolo di rilascio accessori_release) o spegne (ogni admin) la pubblicazione degli annunci Accessori. Motivo obbligatorio, registrato. Spegnere rende subito invisibili gli annunci pubblicati.';

create function public.annunci_accessori_admin_categorie_pubblicazione()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.accessori_admin_richiesto();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'id', c.id, 'slug', c.slug, 'nome', c.nome, 'genitore_slug', g.slug,
        'vendibile', private.annuncio_accessorio_categoria_vendibile(c.id),
        'pubblicabile', private.annuncio_accessorio_categoria_pubblicabile(c.id),
        'approvata', coalesce(r.pubblicabile, false))
      order by coalesce(g.ordine, c.ordine), g.slug nulls first, c.ordine, c.slug)
    from private.accessori_categorie c
    left join private.accessori_categorie g on g.id = c.parent_id
    left join private.annunci_accessori_categorie_pubblicabili r on r.categoria_id = c.id
    where c.attiva
  ), '[]'::jsonb);
end;
$$;

create function public.annunci_accessori_admin_categoria_pubblicabile_imposta(
  p_categoria uuid, p_pubblicabile boolean, p_motivo text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid;
  v_motivo text := private.partner_motivo_pulito(p_motivo);
begin
  if p_categoria is null or p_pubblicabile is null then
    raise exception 'Valore non valido.' using errcode = '22023', hint = 'dati_non_validi';
  end if;
  if p_pubblicabile then
    v_admin := private.accessori_rilascio_richiesto();
  else
    v_admin := private.accessori_admin_richiesto();
  end if;
  if v_motivo is null then
    raise exception 'Il cambio richiede un motivo.' using errcode = '22023', hint = 'motivo_obbligatorio';
  end if;
  if not exists (select 1 from private.accessori_categorie c where c.id = p_categoria and c.attiva) then
    raise exception 'Categoria non trovata.' using errcode = 'P0001', hint = 'non_trovato';
  end if;

  perform set_config('vinae.accessori_rilascio', 'rilascio:' || v_admin::text, true);
  insert into private.annunci_accessori_categorie_pubblicabili (categoria_id, pubblicabile, approvata_da, nota)
  values (p_categoria, p_pubblicabile, v_admin, v_motivo)
  on conflict (categoria_id) do update
    set pubblicabile = excluded.pubblicabile, approvata_da = excluded.approvata_da, nota = excluded.nota;
  perform set_config('vinae.accessori_rilascio', '', true);

  insert into private.accessori_registro (admin_id, azione, oggetto, oggetto_id, motivo)
  values (v_admin, 'categoria_pubblicabile' || case when p_pubblicabile then '_approva' else '_revoca' end,
          'categoria_pubblicabile', p_categoria, v_motivo);

  return jsonb_build_object('categoria_id', p_categoria,
    'pubblicabile', private.annuncio_accessorio_categoria_pubblicabile(p_categoria));
end;
$$;

comment on function public.annunci_accessori_admin_categoria_pubblicabile_imposta(uuid, boolean, text) is
  'Approva (solo con il ruolo di rilascio) o revoca (ogni admin) una categoria per la pubblicazione. Una categoria non vendibile alla preparazione non si approva mai. Revocare nasconde subito gli annunci della categoria.';

-- ---------------------------------------------------------------------------
-- Privilegi di esecuzione
-- ---------------------------------------------------------------------------

revoke all on function public.annunci_accessori_pubblici_elenca(text, integer, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.annunci_accessori_pubblico_dettaglio(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.segnalazione_annuncio_accessorio_invia(uuid, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.annunci_accessori_admin_modera(uuid, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.annunci_accessori_admin_elenca(text, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.annunci_accessori_admin_dettaglio(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.annunci_accessori_admin_pubblicazione_imposta(boolean, text)
  from public, anon, authenticated, service_role;
revoke all on function public.annunci_accessori_admin_categorie_pubblicazione()
  from public, anon, authenticated, service_role;
revoke all on function public.annunci_accessori_admin_categoria_pubblicabile_imposta(uuid, boolean, text)
  from public, anon, authenticated, service_role;

-- Le sole letture pubbliche: vuote a pubblicazione chiusa, nessun dato privato.
grant execute on function public.annunci_accessori_pubblici_elenca(text, integer, integer) to anon, authenticated;
grant execute on function public.annunci_accessori_pubblico_dettaglio(uuid) to anon, authenticated;

grant execute on function public.segnalazione_annuncio_accessorio_invia(uuid, text, text) to authenticated;
grant execute on function public.annunci_accessori_admin_modera(uuid, text, text) to authenticated;
grant execute on function public.annunci_accessori_admin_elenca(text, integer) to authenticated;
grant execute on function public.annunci_accessori_admin_dettaglio(uuid) to authenticated;
grant execute on function public.annunci_accessori_admin_pubblicazione_imposta(boolean, text) to authenticated;
grant execute on function public.annunci_accessori_admin_categorie_pubblicazione() to authenticated;
grant execute on function public.annunci_accessori_admin_categoria_pubblicabile_imposta(uuid, boolean, text) to authenticated;

notify pgrst, 'reload schema';
