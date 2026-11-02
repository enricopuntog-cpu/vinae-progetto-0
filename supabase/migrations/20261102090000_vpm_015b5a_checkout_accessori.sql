-- VPM-015B5A — Checkout Accessori privati e inventario transazionale.
--
-- Contratto: docs/VPM_015B5A_CHECKOUT_ACCESSORI.md. Costruita su VPM-015B2/B3
-- (annunci, quantita, moderazione) e VPM-015B4 (preventivo logistico CONGELATO
-- a uso unico): il checkout consuma il preventivo, non ricalcola nulla.
--
-- NESSUN PAGAMENTO REALE. Questa migrazione non chiama Stripe, non crea sessioni
-- di pagamento, non addebita nulla e non crea spedizioni. Il "pagamento" e una
-- funzione PRIVATA e simulata (`private.accessori_ordine_segna_pagato`) che
-- nessun ruolo client puo eseguire: il blocco B5B la sostituira con la conferma
-- di un webhook firmato.
--
-- Quando una quantita e prenotata, venduta, torna disponibile (modello esatto):
--   * PRENOTATA al checkout: nasce un ordine `in_attesa_pagamento` con scadenza
--     (15 minuti, parametro). Nessuna colonna di quantita viene toccata: la
--     disponibilita e SEMPRE derivata
--         disponibili = annuncio.quantita - somma(ordini in attesa non scaduti)
--     quindi non esistono sottrazioni anticipate e non puo esserci un doppio
--     conteggio;
--   * VENDUTA alla conferma del pagamento: nella stessa transazione, sotto lock
--     di accessorio -> annuncio -> ordine, l'ordine diventa `pagato` e la
--     quantita dell'annuncio e quella posseduta in Cantina scendono entrambe di
--     N (una sola volta, perche l'ordine esce da `in_attesa_pagamento`);
--   * DI NUOVO DISPONIBILE senza scrivere alcuna quantita: annullamento
--     dell'acquirente, scadenza, o annuncio che smette di essere pubblicato
--     (oscurato, modifiche richieste, ritirato, riportato in bozza). L'ordine
--     esce da `in_attesa_pagamento` e la formula sopra lo riconta.
--
-- Esempio: 6 calici in Cantina, 4 in annuncio, 2 acquistati ->
--   prenotazione: cantina 6, annuncio 4, disponibili 2;
--   vendita:      cantina 4, annuncio 2, disponibili 2;
--   annullo/scadenza prima del pagamento: cantina 6, annuncio 4, disponibili 4.
--
-- Che cosa fa:
--   [1] interruttore `checkout_attivo` (spento) e durata della prenotazione;
--   [2] Cantina: un accessorio esaurito resta come riga archiviata a quantita 0;
--   [3] ordini Accessori (`private.accessori_ordini`), importi e condizioni
--       congelati dal preventivo, guardia di immutabilita e transizioni;
--   [4] guardie sull'annuncio: la vendita confermata (marcatore) e l'unica che
--       scende senza i controlli di pubblicazione; il venditore non scende sotto
--       le quantita prenotate; un annuncio non piu pubblicato libera le
--       prenotazioni;
--   [5] checkout, annullamento, lettura, elenco, disponibilita, interruttore.
--
-- Che cosa NON fa: nessuna scrittura su orders, payments, listings, proposals,
-- bottle_units; nessuna modifica a `marketplace_config`, alle aliquote del vino
-- o alle tariffe; nessun carrello multi-venditore o misto vino/accessori;
-- nessun domicilio (B4: non ordinabile); nessun payout; nessun vettore.

-- ---------------------------------------------------------------------------
-- [0] Registro
-- ---------------------------------------------------------------------------

alter table private.accessori_registro drop constraint accessori_registro_oggetto_ammesso;
alter table private.accessori_registro
  add constraint accessori_registro_oggetto_ammesso
  check (oggetto in ('categoria', 'accessorio', 'visibilita', 'cantina_accessori',
                     'annunci_accessori', 'annunci_pubblicazione', 'categoria_pubblicabile',
                     'annunci_logistica', 'logistica_tariffa', 'annunci_checkout'));

-- ---------------------------------------------------------------------------
-- [1] Interruttore e parametri
-- ---------------------------------------------------------------------------

create table private.accessori_checkout_impostazioni (
  singleton boolean primary key default true check (singleton),
  checkout_attivo boolean not null default false,
  prenotazione_min integer not null default 15,
  versione integer not null default 1,
  aggiornato_da uuid references public.profiles (id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint accessori_checkout_prenotazione_forma check (prenotazione_min between 5 and 60)
);

insert into private.accessori_checkout_impostazioni (singleton) values (true);

comment on table private.accessori_checkout_impostazioni is
  'VPM-015B5A: interruttore e durata della prenotazione del checkout Accessori. Spento di '
  'default; l''accensione richiede il ruolo accessori_release e il marcatore transazionale.';

alter table private.accessori_checkout_impostazioni enable row level security;
revoke all on table private.accessori_checkout_impostazioni from public, anon, authenticated;

create function private.accessori_checkout_impostazioni_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Le impostazioni del checkout non si cancellano.' using errcode = '42501';
  end if;
  if new.checkout_attivo and not old.checkout_attivo then
    if new.aggiornato_da is null
       or coalesce(current_setting('vinae.accessori_rilascio', true), '')
          <> 'rilascio:' || new.aggiornato_da::text then
      raise exception 'L''accensione si fa solo dalla porta di rilascio.'
        using errcode = '42501', hint = 'rilascio_non_autorizzato';
    end if;
  end if;
  new.versione := old.versione + 1;
  new.updated_at := now();
  return new;
end;
$$;

revoke execute on function private.accessori_checkout_impostazioni_guard() from public, anon, authenticated;

create trigger accessori_checkout_impostazioni_guard
  before update on private.accessori_checkout_impostazioni
  for each row execute function private.accessori_checkout_impostazioni_guard();
create trigger accessori_checkout_impostazioni_no_delete
  before delete on private.accessori_checkout_impostazioni
  for each row execute function private.accessori_checkout_impostazioni_guard();

-- Checkout utilizzabile: interruttore acceso E logistica aperta (che a sua volta
-- richiede cantina, preparazione, pubblicazione e logistica accese).
create function private.accessori_checkout_aperto()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.accessori_logistica_aperta()
    and coalesce((select i.checkout_attivo from private.accessori_checkout_impostazioni i), false);
$$;

revoke execute on function private.accessori_checkout_aperto() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [2] Cantina: accessorio esaurito
-- ---------------------------------------------------------------------------
--
-- Vendere l'ultimo pezzo porta la quantita posseduta a 0. Una riga a 0 e
-- ammessa solo se archiviata (non si espone, non si vende, non compare).

alter table private.cantina_accessori drop constraint cantina_accessori_quantita_forma;
alter table private.cantina_accessori
  add constraint cantina_accessori_quantita_forma check (quantita between 0 and 999),
  add constraint cantina_accessori_esaurito_archiviato
    check (quantita >= 1 or archiviato_at is not null);

-- ---------------------------------------------------------------------------
-- [3] Ordini Accessori
-- ---------------------------------------------------------------------------

create table private.accessori_ordini (
  id uuid primary key,
  buyer_id uuid not null references public.profiles (id) on delete restrict,
  seller_id uuid not null references public.profiles (id) on delete restrict,
  -- Riferimenti senza chiave esterna: l'ordine sopravvive alla cancellazione di
  -- annuncio, accessorio e preventivo (che cadono a cascata con l'account).
  annuncio_id uuid not null,
  cantina_accessorio_id uuid not null,
  preventivo_id uuid not null,
  chiave_idempotenza text not null,
  stato text not null default 'in_attesa_pagamento',
  -- Articolo congelato (snapshot dell'annuncio pubblicato al checkout).
  articolo_nome text not null,
  articolo_marchio text,
  articolo_condizione text not null,
  -- Economia congelata dal preventivo B4 (mai ricalcolata, mai dal browser).
  quantita integer not null,
  prezzo_unitario_cents integer not null,
  prezzo_cents integer not null,
  commissione_cents integer not null,
  copertura_pagamento_cents integer not null,
  logistica_cents integer not null,
  assicurazione_cents integer not null default 0,
  totale_acquirente_cents integer not null,
  currency text not null default 'eur',
  venditore_classe public.classe_venditore not null,
  margine_obiettivo_bps integer not null,
  riferimento_percentuale_bps integer not null,
  riferimento_fisso_cents integer not null,
  -- Logistica congelata (punto di ritiro: il servizio e il piano restano interni).
  destinazione text not null default 'punto_ritiro',
  colli integer not null,
  pezzi_per_collo integer not null,
  logistica_config_versione integer not null,
  logistica_dettaglio jsonb not null,
  -- Ciclo di vita.
  creato_at timestamptz not null default now(),
  scade_at timestamptz not null,
  stato_aggiornato_at timestamptz not null default now(),
  motivo_chiusura text,
  pagato_at timestamptz,
  pagamento_modo text,
  constraint accessori_ordini_stato_ammesso
    check (stato in ('in_attesa_pagamento', 'pagato', 'annullato', 'scaduto')),
  constraint accessori_ordini_chiave_forma
    check (length(chiave_idempotenza) between 8 and 128 and chiave_idempotenza ~ '^[A-Za-z0-9._:-]+$'),
  constraint accessori_ordini_quantita_forma check (quantita between 1 and 120),
  constraint accessori_ordini_importi_forma check (
    prezzo_unitario_cents > 0 and prezzo_cents > 0 and commissione_cents >= 0
    and copertura_pagamento_cents >= 0 and logistica_cents >= 0
    and assicurazione_cents between 0 and logistica_cents and totale_acquirente_cents > 0),
  constraint accessori_ordini_subtotale check (prezzo_cents = prezzo_unitario_cents * quantita),
  constraint accessori_ordini_totale
    check (totale_acquirente_cents = prezzo_cents + commissione_cents
                                    + copertura_pagamento_cents + logistica_cents),
  constraint accessori_ordini_valuta check (currency = 'eur'),
  constraint accessori_ordini_destinazione check (destinazione = 'punto_ritiro'),
  constraint accessori_ordini_colli_forma check (colli >= 1 and pezzi_per_collo >= 1),
  constraint accessori_ordini_acquirente_diverso check (buyer_id <> seller_id),
  constraint accessori_ordini_scadenza check (scade_at > creato_at),
  constraint accessori_ordini_pagato_coerente
    check ((stato = 'pagato') = (pagato_at is not null)
           and (pagato_at is null) = (pagamento_modo is null)
           and (pagamento_modo is null or pagamento_modo = 'simulato')),
  constraint accessori_ordini_chiusura_coerente
    check ((stato in ('annullato', 'scaduto')) = (motivo_chiusura is not null)
           and (motivo_chiusura is null
                or motivo_chiusura in ('acquirente', 'scadenza', 'annuncio_non_disponibile')))
);

comment on table private.accessori_ordini is
  'VPM-015B5A: ordine Accessori (un annuncio, un venditore, 1-120 pezzi). Importi, articolo e '
  'logistica congelati dal preventivo B4. Nessun grant client. Nessun pagamento reale: lo stato '
  '`pagato` si raggiunge solo con la funzione privata simulata. Una prenotazione e un ordine '
  '`in_attesa_pagamento` non scaduto.';

-- Un acquirente ha al massimo una prenotazione aperta per annuncio: un doppio
-- click con chiavi diverse non crea due prenotazioni.
create unique index accessori_ordini_una_prenotazione_aperta
  on private.accessori_ordini (buyer_id, annuncio_id) where stato = 'in_attesa_pagamento';
create unique index accessori_ordini_chiave_unica
  on private.accessori_ordini (buyer_id, chiave_idempotenza);
create unique index accessori_ordini_preventivo_unico
  on private.accessori_ordini (preventivo_id);
create index accessori_ordini_prenotazioni_idx
  on private.accessori_ordini (annuncio_id, scade_at) where stato = 'in_attesa_pagamento';
create index accessori_ordini_seller_idx on private.accessori_ordini (seller_id, creato_at desc);
create index accessori_ordini_buyer_idx on private.accessori_ordini (buyer_id, creato_at desc);

alter table private.accessori_ordini enable row level security;
revoke all on table private.accessori_ordini from public, anon, authenticated;

-- Regole valide per ogni writer, anche privilegiato.
create function private.accessori_ordini_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_transizione boolean;
begin
  if tg_op = 'TRUNCATE' then
    raise exception 'Gli ordini Accessori non si svuotano.' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then
    if coalesce(current_setting('vinae.accessori_ordini_pulizia', true), '') <> 'on' then
      raise exception 'Un ordine Accessori non si cancella.'
        using errcode = '42501', hint = 'ordine_non_cancellabile';
    end if;
    return old;
  end if;
  if tg_op = 'INSERT' then
    if coalesce(current_setting('vinae.accessori_ordine_crea', true), '') <> 'crea:' || new.id::text then
      raise exception 'Un ordine nasce solo dal checkout.'
        using errcode = '42501', hint = 'creazione_non_autorizzata';
    end if;
    if new.stato <> 'in_attesa_pagamento' then
      raise exception 'Un ordine nasce in attesa di pagamento.'
        using errcode = '22023', hint = 'ordine_nasce_in_attesa';
    end if;
    return new;
  end if;

  -- UPDATE: solo stato e relativi campi cambiano; il resto e congelato.
  if (to_jsonb(new) - 'stato' - 'stato_aggiornato_at' - 'motivo_chiusura' - 'pagato_at' - 'pagamento_modo')
     <> (to_jsonb(old) - 'stato' - 'stato_aggiornato_at' - 'motivo_chiusura' - 'pagato_at' - 'pagamento_modo') then
    raise exception 'Le condizioni di un ordine non cambiano.'
      using errcode = '42501', hint = 'ordine_immutabile';
  end if;
  if new.stato is distinct from old.stato then
    if old.stato <> 'in_attesa_pagamento' then
      raise exception 'Un ordine chiuso non si riapre.'
        using errcode = '22023', hint = 'ordine_chiuso';
    end if;
    v_transizione := coalesce(current_setting('vinae.accessori_ordine_transizione', true), '')
                     = 'ok:' || new.id::text;
    if not v_transizione then
      raise exception 'Lo stato di un ordine cambia solo dalle porte dell''ordine.'
        using errcode = '42501', hint = 'transizione_non_autorizzata';
    end if;
    new.stato_aggiornato_at := now();
  elsif (new.motivo_chiusura, new.pagato_at, new.pagamento_modo)
        is distinct from (old.motivo_chiusura, old.pagato_at, old.pagamento_modo) then
    raise exception 'Le condizioni di un ordine non cambiano.'
      using errcode = '42501', hint = 'ordine_immutabile';
  end if;
  return new;
end;
$$;

revoke execute on function private.accessori_ordini_guard() from public, anon, authenticated;

create trigger accessori_ordini_guard
  before insert or update or delete on private.accessori_ordini
  for each row execute function private.accessori_ordini_guard();
create trigger accessori_ordini_no_truncate
  before truncate on private.accessori_ordini
  for each statement execute function private.accessori_ordini_guard();

-- ---------------------------------------------------------------------------
-- Disponibilita e scadenze (sempre derivate)
-- ---------------------------------------------------------------------------

-- Pezzi prenotati da ordini in attesa non scaduti.
create function private.accessori_prenotati(p_annuncio uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(o.quantita), 0)::integer
  from private.accessori_ordini o
  where o.annuncio_id = p_annuncio
    and o.stato = 'in_attesa_pagamento'
    and o.scade_at > now();
$$;

revoke execute on function private.accessori_prenotati(uuid) from public, anon, authenticated;

create function private.accessori_disponibili(p_annuncio uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select greatest(
    coalesce((select a.quantita from private.annunci_accessori a
              where a.id = p_annuncio and a.stato <> 'ritirato'), 0)
    - private.accessori_prenotati(p_annuncio), 0)::integer;
$$;

revoke execute on function private.accessori_disponibili(uuid) from public, anon, authenticated;

-- Chiude le prenotazioni scadute (di un annuncio o di tutti). Non e necessaria
-- alla correttezza (la disponibilita ignora le scadute): rende lo stato leggibile.
create function private.accessori_prenotazioni_scadute_chiudi(p_annuncio uuid default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o record;
  v_n integer := 0;
begin
  for v_o in
    select o.id from private.accessori_ordini o
    where o.stato = 'in_attesa_pagamento' and o.scade_at <= now()
      and (p_annuncio is null or o.annuncio_id = p_annuncio)
    order by o.id
    for update skip locked
  loop
    perform set_config('vinae.accessori_ordine_transizione', 'ok:' || v_o.id::text, true);
    update private.accessori_ordini
    set stato = 'scaduto', motivo_chiusura = 'scadenza'
    where id = v_o.id;
    v_n := v_n + 1;
  end loop;
  perform set_config('vinae.accessori_ordine_transizione', '', true);
  return v_n;
end;
$$;

revoke execute on function private.accessori_prenotazioni_scadute_chiudi(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [4] Guardie sull'annuncio
-- ---------------------------------------------------------------------------

-- La guardia di B3 con UN ramo in piu: la vendita confermata (marcatore
-- `vinae.accessori_vendita` = 'ok:<annuncio>') puo solo scendere di quantita, o
-- ritirare l'annuncio esaurito, senza i controlli di pubblicazione e senza
-- toccare versione e snapshot. Il pagamento e gia avvenuto: la moderazione o un
-- interruttore spento non devono poter bloccare l'incasso (CLAUDE.md, Money).
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
  v_vend boolean := coalesce(current_setting('vinae.accessori_vendita', true), '')
                    = 'ok:' || new.id::text;
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
    -- VPM-015B5A: vendita confermata. Solo meno pezzi, oppure il ritiro
    -- dell'annuncio esaurito (quantita invariata); nient'altro cambia. Nessun
    -- controllo di pubblicazione o moderazione: il pagamento e gia avvenuto.
    if v_vend then
      if (to_jsonb(new) - 'quantita' - 'stato' - 'ritirato_at' - 'updated_at')
         <> (to_jsonb(old) - 'quantita' - 'stato' - 'ritirato_at' - 'updated_at')
         or not (
           (new.stato = old.stato and new.quantita < old.quantita and new.quantita >= 1)
           or (new.stato = 'ritirato' and new.quantita = old.quantita)) then
        raise exception 'Una vendita confermata cambia solo i pezzi o ritira l''annuncio esaurito.'
          using errcode = '42501', hint = 'vendita_non_valida';
      end if;
      if new.stato = 'ritirato' then
        new.ritirato_at := coalesce(new.ritirato_at, now());
      end if;
      return new;
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

-- Il venditore non scende sotto i pezzi prenotati (a una vendita confermata il
-- controllo non si applica: la prenotazione che si conferma esce dal conteggio).
create function private.accessori_quantita_riservata_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prenotati integer;
begin
  if new.quantita < old.quantita
     and coalesce(current_setting('vinae.accessori_vendita', true), '') <> 'ok:' || new.id::text then
    v_prenotati := private.accessori_prenotati(new.id);
    if new.quantita < v_prenotati then
      raise exception 'Ci sono pezzi prenotati da acquirenti: la quantita non scende sotto % per ora.', v_prenotati
        using errcode = '22023', hint = 'quantita_prenotata';
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function private.accessori_quantita_riservata_guard() from public, anon, authenticated;

create trigger accessori_quantita_riservata_guard
  before update of quantita on private.annunci_accessori
  for each row execute function private.accessori_quantita_riservata_guard();

-- Un annuncio che smette di essere pubblicato libera le prenotazioni non pagate.
-- Gli ordini gia pagati non si toccano.
create function private.accessori_riserve_rilascia_annuncio()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o record;
begin
  for v_o in
    select o.id from private.accessori_ordini o
    where o.annuncio_id = new.id and o.stato = 'in_attesa_pagamento'
    order by o.id
    for update
  loop
    perform set_config('vinae.accessori_ordine_transizione', 'ok:' || v_o.id::text, true);
    update private.accessori_ordini
    set stato = 'annullato', motivo_chiusura = 'annuncio_non_disponibile'
    where id = v_o.id;
  end loop;
  perform set_config('vinae.accessori_ordine_transizione', '', true);
  return null;
end;
$$;

revoke execute on function private.accessori_riserve_rilascia_annuncio() from public, anon, authenticated;

create trigger accessori_riserve_rilascia_annuncio
  after update of stato on private.annunci_accessori
  for each row
  when (old.stato = 'pubblicato' and new.stato is distinct from old.stato)
  execute function private.accessori_riserve_rilascia_annuncio();

-- ---------------------------------------------------------------------------
-- [5] JSON dell'ordine
-- ---------------------------------------------------------------------------

-- Forma verso il browser. Mai il margine, mai il servizio o la tariffa, mai
-- identificativi di Cantina. Il venditore vede il prezzo che incassa e il nome
-- pubblico dell'acquirente, non il resto.
create function private.accessori_ordine_json(o private.accessori_ordini, p_ruolo text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', o.id,
    'stato', case when o.stato = 'in_attesa_pagamento' and o.scade_at <= now()
                  then 'scaduto' else o.stato end,
    'annuncioId', o.annuncio_id,
    'ruolo', p_ruolo,
    'articolo', jsonb_build_object(
      'nome', o.articolo_nome, 'marchio', o.articolo_marchio, 'condizione', o.articolo_condizione),
    'quantita', o.quantita,
    'prezzo', jsonb_build_object(
      'unitarioCents', o.prezzo_unitario_cents, 'quantita', o.quantita,
      'subtotaleCents', o.prezzo_cents),
    'commissione', jsonb_build_object('cents', o.commissione_cents),
    'pagamento', jsonb_build_object('coperturaSuLogisticaCents', o.copertura_pagamento_cents),
    'logistica', jsonb_build_object(
      'trasportoCents', o.logistica_cents - o.assicurazione_cents,
      'assicurazioneCents', o.assicurazione_cents,
      'totaleCents', o.logistica_cents,
      'colli', o.colli, 'pezziPerCollo', o.pezzi_per_collo,
      'destinazione', o.destinazione),
    'totaleAcquirenteCents', o.totale_acquirente_cents,
    'valuta', o.currency,
    'creatoAt', o.creato_at,
    'scadeAt', o.scade_at,
    'pagatoAt', o.pagato_at,
    'motivoChiusura', o.motivo_chiusura,
    'pagamentoSimulato', coalesce(o.pagamento_modo = 'simulato', false)
  ) || case when p_ruolo = 'acquirente' then
      jsonb_build_object('venditore',
        (select jsonb_build_object('username', pp.username)
         from private.profili_pubblici pp where pp.user_id = o.seller_id))
    else
      jsonb_build_object('acquirente',
        (select jsonb_build_object('username', pp.username)
         from private.profili_pubblici pp where pp.user_id = o.buyer_id),
        'ricevi', jsonb_build_object('cents', o.prezzo_cents))
    end;
$$;

revoke execute on function private.accessori_ordine_json(private.accessori_ordini, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Pagamento simulato (PRIVATO) e vendita
-- ---------------------------------------------------------------------------

-- Conferma la vendita. Nessun ruolo client la esegue; il blocco B5B la chiamera
-- da un webhook firmato, i test da un writer privilegiato. Idempotente.
-- Ordine dei lock: accessorio della Cantina -> annuncio -> ordine.
create function private.accessori_ordine_segna_pagato(p_ordine uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  o private.accessori_ordini%rowtype;
  a private.annunci_accessori%rowtype;
  c private.cantina_accessori%rowtype;
begin
  select * into o from private.accessori_ordini where id = p_ordine;
  if o.id is null then
    raise exception 'Ordine non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  select * into c from private.cantina_accessori
  where id = o.cantina_accessorio_id for update;
  select * into a from private.annunci_accessori where id = o.annuncio_id for update;
  select * into o from private.accessori_ordini where id = p_ordine for update;

  if o.stato = 'pagato' then
    return private.accessori_ordine_json(o, 'acquirente');
  end if;
  if o.stato <> 'in_attesa_pagamento' then
    raise exception 'Questo ordine non e piu pagabile.'
      using errcode = '22023', hint = 'ordine_non_pagabile';
  end if;
  if o.scade_at <= now() then
    raise exception 'La prenotazione e scaduta.'
      using errcode = '22023', hint = 'prenotazione_scaduta';
  end if;
  if a.id is null or c.id is null or a.quantita < o.quantita or c.quantita < o.quantita then
    raise exception 'Inventario incoerente: la vendita non si applica.'
      using errcode = '23514', hint = 'inventario_incoerente';
  end if;

  -- L'ordine esce da "in attesa" PRIMA di toccare l'annuncio: cosi il rilascio
  -- delle prenotazioni di un annuncio esaurito non lo annulla.
  perform set_config('vinae.accessori_ordine_transizione', 'ok:' || o.id::text, true);
  update private.accessori_ordini
  set stato = 'pagato', pagato_at = now(), pagamento_modo = 'simulato'
  where id = o.id returning * into o;
  perform set_config('vinae.accessori_ordine_transizione', '', true);

  perform set_config('vinae.accessori_vendita', 'ok:' || a.id::text, true);
  if a.quantita = o.quantita then
    -- Esaurito: l'annuncio si chiude; la sua quantita resta com'era (storia).
    update private.annunci_accessori set stato = 'ritirato' where id = a.id;
  else
    update private.annunci_accessori set quantita = quantita - o.quantita where id = a.id;
  end if;
  perform set_config('vinae.accessori_vendita', '', true);

  update private.cantina_accessori
  set quantita = quantita - o.quantita,
      archiviato_at = case when quantita - o.quantita = 0 then now() else archiviato_at end,
      visibilita = case when quantita - o.quantita = 0 then 'privata' else visibilita end
  where id = c.id;

  return private.accessori_ordine_json(o, 'acquirente');
end;
$$;

comment on function private.accessori_ordine_segna_pagato(uuid) is
  'VPM-015B5A: conferma (simulata) del pagamento e applica la vendita: ordine pagato, annuncio e '
  'Cantina scendono di N, una sola volta. Non eseguibile da alcun ruolo client.';

revoke execute on function private.accessori_ordine_segna_pagato(uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Porte
-- ---------------------------------------------------------------------------

-- Disponibilita pubblica di un annuncio visibile (anon e authenticated).
create function public.accessori_disponibilita(p_annuncio uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_annuncio is null or not private.annuncio_accessorio_visibile(p_annuncio) then
    return jsonb_build_object('disponibili', 0, 'prenotabile', false,
                              'motivo', 'annuncio_non_disponibile');
  end if;
  return jsonb_build_object(
    'disponibili', private.accessori_disponibili(p_annuncio),
    'prenotabile', private.accessori_checkout_aperto()
                   and private.accessori_disponibili(p_annuncio) > 0,
    'motivo', case when not private.accessori_checkout_aperto() then 'checkout_non_attivo'
                   when private.accessori_disponibili(p_annuncio) = 0 then 'esaurito' end);
end;
$$;

comment on function public.accessori_disponibilita(uuid) is
  'VPM-015B5A: pezzi ancora prenotabili di un annuncio Accessori visibile (quantita - prenotazioni attive).';

-- Checkout: prenota. Il browser passa SOLO il preventivo congelato B4 e una
-- chiave di idempotenza: annuncio, quantita, venditore, prezzo, commissione,
-- logistica e destinazione vengono dal preventivo e dal database.
create function public.accessori_checkout_crea(p_preventivo_id uuid, p_chiave text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
  q private.accessori_logistica_preventivi%rowtype;
  a private.annunci_accessori%rowtype;
  s private.annunci_accessori_snapshot%rowtype;
  o private.accessori_ordini%rowtype;
  v_cid uuid;
  v_id uuid := gen_random_uuid();
  v_eco jsonb;
  v_piano jsonb;
  v_cfg private.accessori_checkout_impostazioni%rowtype;
  v_lcfg private.accessori_logistica_impostazioni%rowtype;
  v_v record;
  v_disp integer;
  v_check jsonb;
begin
  if p_preventivo_id is null or length(coalesce(p_chiave, '')) not between 8 and 128
     or p_chiave !~ '^[A-Za-z0-9._:-]+$' then
    raise exception 'Richiesta di checkout non valida.' using errcode = '22023', hint = 'richiesta_non_valida';
  end if;
  perform private.rate_limit_consume('accessori_checkout:crea', 'user:' || v_uid::text, 10, 60);

  -- Ripetizione (stessa chiave, oppure stesso preventivo): la stessa risposta,
  -- senza lock e senza altri effetti. Vale anche a checkout chiuso.
  select * into o from private.accessori_ordini where buyer_id = v_uid and chiave_idempotenza = p_chiave;
  if o.id is not null then
    if o.preventivo_id <> p_preventivo_id then
      raise exception 'Questa chiave appartiene a un altro ordine.'
        using errcode = '22023', hint = 'chiave_riusata';
    end if;
    return private.accessori_ordine_json(o, 'acquirente');
  end if;
  select * into o from private.accessori_ordini where buyer_id = v_uid and preventivo_id = p_preventivo_id;
  if o.id is not null then
    return private.accessori_ordine_json(o, 'acquirente');
  end if;

  if not private.accessori_checkout_aperto() then
    raise exception 'Il checkout degli Accessori non e attivo.'
      using errcode = '42501', hint = 'checkout_non_attivo';
  end if;

  if private.utente_stato_di(v_uid) <> 'attivo'::public.utente_stato then
    raise exception 'Il tuo account non puo acquistare ora.'
      using errcode = '42501', hint = 'account_non_attivo';
  end if;

  select * into q from private.accessori_logistica_preventivi where id = p_preventivo_id and buyer_id = v_uid;
  if q.id is null then
    raise exception 'Preventivo non trovato.' using errcode = 'P0001', hint = 'preventivo_non_trovato';
  end if;

  -- Lock: accessorio della Cantina -> annuncio. Il lock dell'accessorio
  -- serializza i compratori concorrenti dello stesso articolo.
  select a0.cantina_accessorio_id into v_cid from private.annunci_accessori a0 where a0.id = q.annuncio_id;
  if v_cid is null then
    raise exception 'Annuncio non disponibile.' using errcode = 'P0001', hint = 'annuncio_non_disponibile';
  end if;
  perform 1 from private.cantina_accessori where id = v_cid for update;
  select * into a from private.annunci_accessori where id = q.annuncio_id for update;

  -- La ripetizione si ricontrolla dopo i lock: una richiesta concorrente potrebbe
  -- aver confermato nel frattempo.
  select * into o from private.accessori_ordini
  where buyer_id = v_uid and (chiave_idempotenza = p_chiave or preventivo_id = p_preventivo_id);
  if o.id is not null then
    if o.preventivo_id <> p_preventivo_id then
      raise exception 'Questa chiave appartiene a un altro ordine.'
        using errcode = '22023', hint = 'chiave_riusata';
    end if;
    return private.accessori_ordine_json(o, 'acquirente');
  end if;

  if a.id is null or not private.annuncio_accessorio_visibile(a.id) then
    raise exception 'Annuncio non disponibile.' using errcode = 'P0001', hint = 'annuncio_non_disponibile';
  end if;
  perform private.accessori_prenotazioni_scadute_chiudi(a.id);
  if a.seller_id = v_uid then
    raise exception 'Non si acquista il proprio annuncio.' using errcode = '42501', hint = 'proprio_annuncio';
  end if;
  select * into v_v from private.annuncio_accessorio_venditore(a.seller_id);
  if v_v.ammesso is not true then
    raise exception 'Questo venditore non puo vendere ora.' using errcode = '42501', hint = 'venditore_non_ammesso';
  end if;

  if exists (select 1 from private.accessori_ordini x
             where x.buyer_id = v_uid and x.annuncio_id = a.id and x.stato = 'in_attesa_pagamento') then
    raise exception 'Hai gia una prenotazione aperta per questo annuncio: annullala o completala.'
      using errcode = '23505', hint = 'prenotazione_aperta';
  end if;

  v_disp := private.accessori_disponibili(a.id);
  if v_disp < q.quantita then
    raise exception 'Disponibili solo % pezzi.', v_disp
      using errcode = 'P0001', hint = 'quantita_non_disponibile', detail = v_disp::text;
  end if;

  -- Il preventivo congelato: verificato e consumato (uso unico) qui, nella
  -- stessa transazione dell'ordine. Un errore annulla tutto.
  v_check := private.accessori_logistica_preventivo_consuma(q.id, v_uid, a.id, q.quantita);

  v_eco := q.dettaglio -> 'interno' -> 'economia';
  v_piano := q.dettaglio -> 'interno' -> 'piano';
  if v_eco is null or v_piano is null
     or (v_eco ->> 'subtotaleCents')::integer <> a.prezzo_unitario_cents * q.quantita
     or (v_eco ->> 'addebitoTotaleCents')::integer <> q.addebito_totale_cents
     or (v_eco ->> 'addebitoTotaleCents')::integer
        <> (v_eco ->> 'subtotaleCents')::integer + (v_eco ->> 'commissioneCents')::integer
           + (v_eco ->> 'coperturaPagamentoSpedizioneCents')::integer + q.logistica_cents then
    raise exception 'Il preventivo non e coerente.' using errcode = '23514', hint = 'preventivo_incoerente';
  end if;

  select * into s from private.annunci_accessori_snapshot where annuncio_id = a.id;
  select * into v_cfg from private.accessori_checkout_impostazioni;
  select * into v_lcfg from private.accessori_logistica_impostazioni;

  perform set_config('vinae.accessori_ordine_crea', 'crea:' || v_id::text, true);
  insert into private.accessori_ordini (
    id, buyer_id, seller_id, annuncio_id, cantina_accessorio_id, preventivo_id, chiave_idempotenza,
    articolo_nome, articolo_marchio, articolo_condizione,
    quantita, prezzo_unitario_cents, prezzo_cents, commissione_cents, copertura_pagamento_cents,
    logistica_cents, assicurazione_cents, totale_acquirente_cents, venditore_classe,
    margine_obiettivo_bps, riferimento_percentuale_bps, riferimento_fisso_cents,
    colli, pezzi_per_collo, logistica_config_versione, logistica_dettaglio, scade_at)
  values (
    v_id, v_uid, a.seller_id, a.id, a.cantina_accessorio_id, q.id, p_chiave,
    s.nome, s.marchio, a.condizione,
    q.quantita, a.prezzo_unitario_cents, (v_eco ->> 'subtotaleCents')::integer,
    (v_eco ->> 'commissioneCents')::integer, (v_eco ->> 'coperturaPagamentoSpedizioneCents')::integer,
    q.logistica_cents, q.assicurazione_cents, q.addebito_totale_cents, v_v.classe,
    (v_eco ->> 'margineObiettivoBps')::integer, (v_eco ->> 'riferimentoPercentualeBps')::integer,
    (v_eco ->> 'riferimentoFissoCents')::integer,
    (v_piano ->> 'colliTotali')::integer, (v_piano ->> 'pezziPerCollo')::integer,
    v_lcfg.versione, q.dettaglio -> 'interno',
    now() + make_interval(mins => v_cfg.prenotazione_min))
  returning * into o;
  perform set_config('vinae.accessori_ordine_crea', '', true);

  return private.accessori_ordine_json(o, 'acquirente');
exception when unique_violation then
  -- Una corsa fra due richieste dello stesso acquirente: l'indice unico ha
  -- vinto. Nessun nome di vincolo verso il browser.
  raise exception 'Hai gia una prenotazione per questo annuncio: annullala o completala.'
    using errcode = '23505', hint = 'prenotazione_aperta';
end;
$$;

comment on function public.accessori_checkout_crea(uuid, text) is
  'VPM-015B5A: prenota N pezzi consumando il preventivo congelato B4. Solo authenticated; importi, '
  'venditore e quantita vengono dal database. Idempotente per chiave e per preventivo. Nessun pagamento.';

-- Annullamento da parte dell'acquirente (prima del pagamento). Idempotente.
create function public.accessori_ordine_annulla(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
  o private.accessori_ordini%rowtype;
begin
  perform private.rate_limit_consume('accessori_checkout:annulla', 'user:' || v_uid::text, 20, 60);
  select * into o from private.accessori_ordini where id = p_id and buyer_id = v_uid for update;
  if o.id is null then
    raise exception 'Ordine non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  if o.stato = 'pagato' then
    raise exception 'Un ordine pagato non si annulla da qui.'
      using errcode = '22023', hint = 'ordine_pagato';
  end if;
  if o.stato = 'in_attesa_pagamento' then
    perform set_config('vinae.accessori_ordine_transizione', 'ok:' || o.id::text, true);
    update private.accessori_ordini
    set stato = case when scade_at <= now() then 'scaduto' else 'annullato' end,
        motivo_chiusura = case when scade_at <= now() then 'scadenza' else 'acquirente' end
    where id = o.id returning * into o;
    perform set_config('vinae.accessori_ordine_transizione', '', true);
  end if;
  return private.accessori_ordine_json(o, 'acquirente');
end;
$$;

comment on function public.accessori_ordine_annulla(uuid) is
  'VPM-015B5A: l''acquirente annulla la propria prenotazione non pagata; i pezzi tornano disponibili.';

-- Lettura: acquirente (completa) o venditore (senza dati dell'acquirente).
create function public.accessori_ordine_leggi(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
  o private.accessori_ordini%rowtype;
begin
  select * into o from private.accessori_ordini where id = p_id and (buyer_id = v_uid or seller_id = v_uid);
  if o.id is null then
    raise exception 'Ordine non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  perform private.accessori_prenotazioni_scadute_chiudi(o.annuncio_id);
  select * into o from private.accessori_ordini where id = p_id;
  return private.accessori_ordine_json(o, case when o.buyer_id = v_uid then 'acquirente' else 'venditore' end);
end;
$$;

comment on function public.accessori_ordine_leggi(uuid) is
  'VPM-015B5A: l''ordine, solo alle sue due parti. Ogni parte vede solo il proprio lato.';

create function public.accessori_ordini_elenca(p_ruolo text default 'acquisti', p_limite integer default 30)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
  v_limite integer := least(greatest(coalesce(p_limite, 30), 1), 60);
begin
  if p_ruolo not in ('acquisti', 'vendite') then
    raise exception 'Valore non valido.' using errcode = '22023', hint = 'dati_non_validi';
  end if;
  return coalesce((
    select jsonb_agg(private.accessori_ordine_json(o, case when p_ruolo = 'acquisti' then 'acquirente' else 'venditore' end)
                     order by o.creato_at desc)
    from private.accessori_ordini o
    where o.id in (
      select x.id from private.accessori_ordini x
      where (p_ruolo = 'acquisti' and x.buyer_id = v_uid) or (p_ruolo = 'vendite' and x.seller_id = v_uid)
      order by x.creato_at desc
      limit v_limite)
  ), '[]'::jsonb);
end;
$$;

comment on function public.accessori_ordini_elenca(text, integer) is
  'VPM-015B5A: ordini Accessori del chiamante come acquirente o come venditore (massimo 60).';

-- Admin ---------------------------------------------------------------------

create function public.accessori_checkout_admin_stato()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cfg private.accessori_checkout_impostazioni%rowtype;
begin
  perform private.accessori_admin_richiesto();
  select * into v_cfg from private.accessori_checkout_impostazioni;
  return jsonb_build_object(
    'checkout_attivo', v_cfg.checkout_attivo,
    'logistica_aperta', private.accessori_logistica_aperta(),
    'checkout_aperto', private.accessori_checkout_aperto(),
    'prenotazione_min', v_cfg.prenotazione_min,
    'versione', v_cfg.versione,
    'puo_rilasciare', private.accessori_puo_rilasciare(),
    'prenotazioni_aperte', (select count(*) from private.accessori_ordini o
                            where o.stato = 'in_attesa_pagamento' and o.scade_at > now()),
    'ordini_pagati', (select count(*) from private.accessori_ordini o where o.stato = 'pagato')
  );
end;
$$;

comment on function public.accessori_checkout_admin_stato() is
  'VPM-015B5A: stato del checkout Accessori per l''admin.';

create function public.accessori_checkout_admin_imposta(p_attivo boolean, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid;
  v_motivo text := private.partner_motivo_pulito(p_motivo);
begin
  if p_attivo is null then
    raise exception 'Valore non valido.' using errcode = '22023', hint = 'dati_non_validi';
  end if;
  if p_attivo then
    v_admin := private.accessori_rilascio_richiesto();
  else
    v_admin := private.accessori_admin_richiesto();
  end if;
  if v_motivo is null then
    raise exception 'Il cambio di interruttore richiede un motivo.'
      using errcode = '22023', hint = 'motivo_obbligatorio';
  end if;

  perform set_config('vinae.accessori_rilascio', 'rilascio:' || v_admin::text, true);
  update private.accessori_checkout_impostazioni
  set checkout_attivo = p_attivo, aggiornato_da = v_admin where singleton;
  perform set_config('vinae.accessori_rilascio', '', true);

  insert into private.accessori_registro (admin_id, azione, oggetto, motivo)
  values (v_admin, 'checkout' || case when p_attivo then '_accendi' else '_spegni' end,
          'annunci_checkout', v_motivo);
  return public.accessori_checkout_admin_stato();
end;
$$;

comment on function public.accessori_checkout_admin_imposta(boolean, text) is
  'VPM-015B5A: accende (solo accessori_release) o spegne (ogni admin) il checkout Accessori. Motivo obbligatorio, registrato.';

-- ---------------------------------------------------------------------------
-- Privilegi
-- ---------------------------------------------------------------------------

revoke all on function public.accessori_disponibilita(uuid) from public, anon, authenticated, service_role;
revoke all on function public.accessori_checkout_crea(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.accessori_ordine_annulla(uuid) from public, anon, authenticated, service_role;
revoke all on function public.accessori_ordine_leggi(uuid) from public, anon, authenticated, service_role;
revoke all on function public.accessori_ordini_elenca(text, integer) from public, anon, authenticated, service_role;
revoke all on function public.accessori_checkout_admin_stato() from public, anon, authenticated, service_role;
revoke all on function public.accessori_checkout_admin_imposta(boolean, text) from public, anon, authenticated, service_role;

grant execute on function public.accessori_disponibilita(uuid) to anon, authenticated;
grant execute on function public.accessori_checkout_crea(uuid, text) to authenticated;
grant execute on function public.accessori_ordine_annulla(uuid) to authenticated;
grant execute on function public.accessori_ordine_leggi(uuid) to authenticated;
grant execute on function public.accessori_ordini_elenca(text, integer) to authenticated;
grant execute on function public.accessori_checkout_admin_stato() to authenticated;
grant execute on function public.accessori_checkout_admin_imposta(boolean, text) to authenticated;

-- Le funzioni private non sono porte: nessun ruolo client, nemmeno service_role.
do $$
declare
  v_f record;
begin
  for v_f in
    select p.oid::regprocedure as firma
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and (p.proname like 'accessori_checkout%'
           or p.proname like 'accessori_ordin%'
           or p.proname in ('accessori_prenotati', 'accessori_disponibili',
                            'accessori_prenotazioni_scadute_chiudi',
                            'accessori_quantita_riservata_guard',
                            'accessori_riserve_rilascia_annuncio',
                            'annunci_accessori_guard'))
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_f.firma);
  end loop;
end $$;
