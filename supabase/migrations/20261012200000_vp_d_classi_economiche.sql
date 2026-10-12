-- Vinea Partner + Quantita multiple — Blocco D: classi economiche autorevoli.
--
-- Contratto: docs/VP_D_CLASSI_ECONOMICHE.md. Decisioni commerciali del
-- titolare (11 ottobre 2026): margine obiettivo 800 bps per i privati, 1500
-- bps per i Partner professionali (NON 1600: il 16% della specifica del 14
-- settembre e storia). Stessa formula per entrambe le classi
-- (`private.marketplace_totale_cents`, intatta): il venditore indica quanto
-- vuole ricevere, la piattaforma aggiunge la commissione che realizza il
-- margine obiettivo al netto della fee di pagamento di riferimento. Una sola
-- quota fissa per ordine, sul subtotale delle N bottiglie.
--
-- Che cosa fa questa migrazione:
--   [1] il tipo `public.classe_venditore` ('privato', 'partner');
--   [2] `marketplace_config` versionata PER CLASSE: una riga corrente per
--       classe (indice sostituito, forma di `packaging_options`), riga Partner
--       a 1500 bps con i parametri condivisi copiati dalla riga privata;
--   [3] il lettore prende la classe; la versione a zero argomenti e
--       ELIMINATA (un overload che assume 'privato' applicherebbe in silenzio
--       l'8% a un Partner) e i suoi tre chiamanti sono ricreati;
--   [4] `private.venditore_classe_risolvi`: classe e vendibilita di un
--       annuncio decise dal database (annuncio, unita, Partner, titolare), mai
--       dal client; blocco condiviso sulle righe Partner del venditore per
--       serializzarsi con i cambi di stato;
--   [5] `orders.venditore_classe` congelata alla creazione; il gate sugli
--       ordini diventa la verifica di coerenza fra classe, parametri,
--       commissione e inventario, che vincola anche i writer privilegiati;
--       le colonne economiche di un ordine sono immutabili;
--   [6] checkout, pubblicazione e proposte usano il risolutore;
--   [7] preventivi autorevoli (`listing_preventivo`, `preventivo_vendita`) e
--       catalogo del Partner (`prodotti_partner_miei`);
--   [8] viste: `public_marketplace_config` una riga per classe,
--       `public_listings.venditore_classe` in coda e prodotti commerciali
--       visibili solo con Partner attivo, riconciliazione con la classe.
--
-- Che cosa NON fa: non accende `vendita_partner` ne `ordini_multi_unita`
-- (restano false); non tocca `PAYMENTS_ENABLED`, Stripe o payout; non decide
-- la politica del Partner revocato (comportamento corrente preservato, vedi
-- [4]); non modifica ordini esistenti, che restano 'privato'.

-- ---------------------------------------------------------------------------
-- [1] La tassonomia economica, in un posto solo
-- ---------------------------------------------------------------------------

create type public.classe_venditore as enum ('privato', 'partner');

comment on type public.classe_venditore is
  'Classe economica del venditore. NON e una qualifica personale (sommelier, '
  'certificazioni): la decide lo stato Partner e la classe d''inventario '
  'dell''annuncio. Una classe nuova e una label qui piu una riga corrente in '
  'marketplace_config: il risolutore e la formula non cambiano.';

-- ---------------------------------------------------------------------------
-- [2] Una configurazione corrente per classe
-- ---------------------------------------------------------------------------

alter table public.marketplace_config
  add column classe_venditore public.classe_venditore;

-- Le righe esistenti (5% iniziale, 8% del 15 settembre, 8% con 48 ore) sono
-- sempre state la configurazione dei privati: fino a oggi la piattaforma non
-- ha mai venduto per conto di un Partner.
update public.marketplace_config set classe_venditore = 'privato'
where classe_venditore is null;

-- Nessun default: una riga nuova dichiara la sua classe, sempre.
alter table public.marketplace_config
  alter column classe_venditore set not null;

drop index public.marketplace_config_una_corrente;

create unique index marketplace_config_una_corrente_per_classe
  on public.marketplace_config (classe_venditore)
  where valida_fino is null;

comment on table public.marketplace_config is
  'Configurazione di mercato versionata, UNA RIGA CORRENTE PER CLASSE DI '
  'VENDITORE (valida_fino nulla); le righe chiuse restano come storico. I '
  'parametri applicati a un ordine sono congelati sull''ordine e non si '
  'rileggono da qui. REGOLA OPERATIVA: una variazione dei parametri condivisi '
  '(riferimento_* e auto_rilascio_giorni) chiude e riapre TUTTE le righe '
  'correnti nella stessa transazione; righe aperte che divergono su quei '
  'parametri sono un difetto, e la griglia 12zb lo verifica.';

-- La riga Partner: margine 1500 bps; i parametri condivisi sono letti dalla
-- riga privata corrente, non riscritti a mano, cosi la ripetizione non nasce
-- gia divergente. Fallisce rumorosamente se la riga privata corrente manca.
do $$
declare
  v_privata public.marketplace_config%rowtype;
begin
  select * into v_privata from public.marketplace_config
  where valida_fino is null and classe_venditore = 'privato';
  if v_privata.id is null then
    raise exception 'VP-D: configurazione privata corrente mancante, riga Partner non creata.';
  end if;

  insert into public.marketplace_config (
    classe_venditore, margine_obiettivo_bps,
    riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents,
    auto_rilascio_giorni, nota
  ) values (
    'partner', 1500,
    v_privata.riferimento_stripe_percentuale_bps, v_privata.riferimento_stripe_fisso_cents,
    v_privata.auto_rilascio_giorni,
    'VP-D: margine obiettivo 15% per i Partner professionali (decisione del titolare '
    'dell''11 ottobre 2026; il 16% della specifica del 14 settembre e superato). '
    'Fee di riferimento e finestra di verifica copiate dalla riga privata corrente.'
  );
end $$;

-- ---------------------------------------------------------------------------
-- [3] Il lettore prende la classe. Nessun overload a zero argomenti.
-- ---------------------------------------------------------------------------
--
-- I tre chiamanti della versione a zero argomenti (checkout, consegna,
-- preventivo logistico) sono ricreati piu sotto in questa stessa migrazione.

drop function private.marketplace_config_corrente();

create function private.marketplace_config_corrente(p_classe public.classe_venditore)
returns public.marketplace_config
language sql
security definer
set search_path = ''
stable
as $$
  select * from public.marketplace_config
  where valida_fino is null
    and classe_venditore = p_classe
  order by valida_da desc
  limit 1;
$$;

comment on function private.marketplace_config_corrente(public.classe_venditore) is
  'Configurazione corrente di UNA classe. Classe nulla o senza riga aperta: '
  'riga nulla, e ogni chiamante fallisce chiuso (nessun ripiego su un''altra '
  'classe).';

revoke execute on function private.marketplace_config_corrente(public.classe_venditore)
  from public, anon, authenticated;

-- Preventivo economico di una classe, il nucleo condiviso da checkout e
-- preventivi: subtotale = prezzo unitario x quantita, UNA applicazione della
-- formula sul subtotale, quindi una sola quota fissa. Null se la classe non
-- ha una configurazione corrente.
create function private.preventivo_classe(
  p_classe public.classe_venditore,
  p_prezzo_unitario_cents integer,
  p_quantita integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_config public.marketplace_config%rowtype;
  v_subtotale integer;
  v_totale integer;
begin
  if p_prezzo_unitario_cents is null or p_prezzo_unitario_cents <= 0
     or p_prezzo_unitario_cents > 10000000
     or p_quantita is null or p_quantita < 1 or p_quantita > 120 then
    raise exception 'Prezzo o quantità non validi.' using errcode = '22023',
      hint = 'preventivo_non_valido';
  end if;
  if p_classe is null then
    return null;
  end if;
  v_config := private.marketplace_config_corrente(p_classe);
  if v_config.id is null then
    return null;
  end if;
  v_subtotale := p_prezzo_unitario_cents * p_quantita;
  v_totale := private.marketplace_totale_cents(
    v_subtotale, v_config.margine_obiettivo_bps,
    v_config.riferimento_stripe_percentuale_bps, v_config.riferimento_stripe_fisso_cents
  );
  return jsonb_build_object(
    'classe', p_classe,
    'configId', v_config.id,
    'quantita', p_quantita,
    'prezzoUnitarioCents', p_prezzo_unitario_cents,
    'subtotaleCents', v_subtotale,
    'commissioneCents', v_totale - v_subtotale,
    'totaleCents', v_totale,
    'margineObiettivoBps', v_config.margine_obiettivo_bps,
    'riferimentoPercentualeBps', v_config.riferimento_stripe_percentuale_bps,
    'riferimentoFissoCents', v_config.riferimento_stripe_fisso_cents
  );
end;
$$;

revoke execute on function private.preventivo_classe(public.classe_venditore, integer, integer)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [4] La classe di un annuncio, decisa dal database
-- ---------------------------------------------------------------------------
--
-- Fonti: l'annuncio (venditore, classe d'inventario, unita offerte), le
-- unita (Partner di appartenenza), il Partner (titolare, stato), il titolare
-- (stato dell'account) e l'interruttore `vendita_partner`. Nessun argomento
-- del chiamante entra nella decisione.
--
--   prodotto commerciale        -> 'partner'; vendibile solo se il Partner e
--                                  quello delle unita, il venditore ne e il
--                                  titolare, e attivo, l'account e attivo e
--                                  vendita_partner e acceso;
--   annuncio personale di chi
--   ha un Partner attivo o
--   sospeso                     -> 'partner', NON vendibile
--                                  (partner_annuncio_personale): un Partner
--                                  non ottiene la tariffa dei privati
--                                  creando o riusando un annuncio personale;
--   annuncio personale degli
--   altri                       -> 'privato', vendibile.
--
-- Partner revocato (decisione APERTA del titolare, nessuna politica nuova):
-- i suoi prodotti commerciali restano 'partner' e non vendibili per sempre
-- (la classe d'inventario e immutabile); i suoi annunci personali tornano ai
-- percorsi dei privati come prima di VP-D. La revoca e solo amministrativa:
-- il titolare non puo revocarsi per passare all'8%.
--
-- Con p_blocca il risolutore prende FOR SHARE le righe Partner del
-- venditore: un cambio di stato concorrente (che le prende FOR UPDATE)
-- attende la fine della transazione d'acquisto, o la precede e allora il
-- risolutore legge lo stato nuovo. Le letture (preventivi) non bloccano.

create function private.venditore_classe_di(
  p_listing_id uuid,
  out classe public.classe_venditore,
  out vendibile boolean,
  out motivo text,
  out partner_id uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_l public.listings%rowtype;
  v_partner_unita uuid;
  v_p private.partners%rowtype;
  v_aperto private.partners%rowtype;
begin
  select * into v_l from public.listings where id = p_listing_id;
  if v_l.id is null then
    raise exception 'Annuncio non trovato.' using errcode = 'P0001',
      hint = 'annuncio_non_trovato';
  end if;

  select * into v_aperto from private.partners p
  where p.titolare_id = v_l.seller_id
    and p.stato in ('attivo'::public.partner_stato, 'sospeso'::public.partner_stato);

  if v_l.inventario = 'commerciale'::public.inventario_classe then
    classe := 'partner';
    select bu.partner_id into v_partner_unita
    from public.bottle_units bu where bu.id = v_l.bottle_unit_id;
    partner_id := v_partner_unita;

    if v_partner_unita is null or exists (
      select 1 from private.listing_unita m
      join public.bottle_units u on u.id = m.bottle_unit_id
      where m.listing_id = v_l.id and m.ritirata_at is null
        and (u.inventario <> 'commerciale'::public.inventario_classe
             or u.partner_id is distinct from v_partner_unita)
    ) then
      vendibile := false; motivo := 'partner_incoerente'; return;
    end if;

    select * into v_p from private.partners p where p.id = v_partner_unita;
    if v_p.id is null or v_p.titolare_id <> v_l.seller_id then
      vendibile := false; motivo := 'partner_incoerente'; return;
    end if;
    if v_p.stato = 'sospeso'::public.partner_stato then
      vendibile := false; motivo := 'partner_sospeso'; return;
    end if;
    if v_p.stato <> 'attivo'::public.partner_stato then
      vendibile := false; motivo := 'partner_non_attivo'; return;
    end if;
    if private.utente_stato_di(v_l.seller_id) <> 'attivo'::public.utente_stato then
      vendibile := false; motivo := 'titolare_non_attivo'; return;
    end if;
    if not private.inventario_flag('vendita_partner') then
      vendibile := false; motivo := 'partner_vendita_non_disponibile'; return;
    end if;
    vendibile := true; motivo := null; return;
  end if;

  if v_aperto.id is not null then
    classe := 'partner'; vendibile := false;
    motivo := 'partner_annuncio_personale'; partner_id := v_aperto.id;
    return;
  end if;

  classe := 'privato'; vendibile := true; motivo := null; partner_id := null;
end;
$$;

comment on function private.venditore_classe_di(uuid) is
  'VP-D: classe economica e vendibilita di un annuncio, dal database, in sola '
  'lettura (preventivi, catalogo). Il Partner revocato non ha una politica '
  'nuova (decisione aperta): prodotti commerciali mai vendibili, annunci '
  'personali come prima.';

revoke execute on function private.venditore_classe_di(uuid) from public, anon, authenticated;

-- Il momento autorevole (checkout, gate, pubblicazione): blocca FOR SHARE le
-- righe Partner del venditore, poi decide con lo stesso nucleo. L'istruzione
-- che lo chiama prende una nuova istantanea dopo l'eventuale attesa, quindi
-- legge lo stato confermato da chi aveva il blocco.
create function private.venditore_classe_risolvi(
  p_listing_id uuid,
  p_blocca boolean default false,
  out classe public.classe_venditore,
  out vendibile boolean,
  out motivo text,
  out partner_id uuid
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if p_blocca then
    perform 1 from private.partners p
    where p.titolare_id = (select l.seller_id from public.listings l where l.id = p_listing_id)
    order by p.id
    for share;
  end if;
  select d.classe, d.vendibile, d.motivo, d.partner_id
  into classe, vendibile, motivo, partner_id
  from private.venditore_classe_di(p_listing_id) d;
end;
$$;

comment on function private.venditore_classe_risolvi(uuid, boolean) is
  'VP-D: classe e vendibilita al momento autorevole, con le righe Partner del '
  'venditore bloccate FOR SHARE. Unica sorgente per checkout, gate di ordini e '
  'proposte e pubblicazione.';

revoke execute on function private.venditore_classe_risolvi(uuid, boolean)
  from public, anon, authenticated;

-- Il venditore ha un Partner attivo o sospeso (la regola dei blocchi A/B).
create function private.venditore_partner_aperto(p_seller_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from private.partners p
    where p.titolare_id = p_seller_id
      and p.stato in ('attivo'::public.partner_stato, 'sospeso'::public.partner_stato)
  );
$$;

revoke execute on function private.venditore_partner_aperto(uuid) from public, anon, authenticated;

-- Messaggio leggibile di un motivo di non vendibilita.
create function private.venditore_classe_messaggio(p_motivo text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_motivo
    when 'partner_vendita_non_disponibile' then
      'Gli acquisti da Partner Vinea non sono ancora disponibili.'
    when 'partner_sospeso' then
      'Questo Partner Vinea è temporaneamente sospeso: i suoi prodotti non sono acquistabili.'
    when 'partner_non_attivo' then
      'Questo prodotto non è più in vendita.'
    when 'titolare_non_attivo' then
      'Questo prodotto non è acquistabile in questo momento.'
    when 'partner_incoerente' then
      'Questo prodotto non è acquistabile.'
    when 'partner_annuncio_personale' then
      'Gli acquisti da Partner Vinea non sono ancora disponibili.'
    else 'Questo annuncio non è acquistabile.'
  end;
$$;

revoke execute on function private.venditore_classe_messaggio(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [5] Congelamento sull'ordine e coerenza economica
-- ---------------------------------------------------------------------------

alter table public.orders add column venditore_classe public.classe_venditore;

-- Ogni ordine esistente e stato creato con il venditore privato: il gate di
-- VP-A rifiutava qualunque ordine verso un Partner attivo o sospeso e i
-- prodotti commerciali non erano acquistabili.
update public.orders set venditore_classe = 'privato' where venditore_classe is null;

alter table public.orders alter column venditore_classe set not null;

comment on column public.orders.venditore_classe is
  'VP-D: classe economica del venditore al momento della creazione, decisa '
  'dal database e congelata. Spiega margine_obiettivo_bps quando le classi '
  'sono piu di una; nessun percorso la rilegge o la modifica dopo.';

grant select (venditore_classe) on public.orders to authenticated;

-- Gate e verifica di coerenza al momento autorevole della creazione. Vale
-- per ogni writer, anche privilegiato (fixture, service_role, postgres):
--   - l'annuncio deve essere vendibile per la sua classe (stesso hint dei
--     blocchi A/B: partner_checkout_non_disponibile);
--   - la classe dichiarata, se presente, coincide con quella risolta;
--     se assente la scrive il trigger;
--   - per un ordine 'partner' parametri e commissione devono essere quelli
--     della riga Partner corrente applicati con la formula unica: nessun
--     ordine commerciale con l'8% o con una commissione calcolata a mano.
-- Gli ordini 'privato' mantengono il comportamento storico (il checkout li
-- congela dalla riga privata; le fixture storiche scrivono ordini a mano).
create or replace function private.partner_checkout_gate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r record;
  v_cfg public.marketplace_config%rowtype;
begin
  -- Annuncio inesistente: l'ordine fallira sul vincolo di chiave esterna.
  -- Il gate risponde comunque per venditore come nei blocchi A/B, cosi un
  -- venditore Partner non riceve mai un errore diverso da quello del gate.
  if not exists (select 1 from public.listings l where l.id = new.listing_id) then
    if private.venditore_partner_aperto(new.seller_id) then
      raise exception 'Gli acquisti da Partner Vinea non sono ancora disponibili.'
        using errcode = '42501', hint = 'partner_checkout_non_disponibile';
    end if;
    new.venditore_classe := coalesce(new.venditore_classe, 'privato');
    return new;
  end if;

  select * into v_r from private.venditore_classe_risolvi(new.listing_id, true);

  if not v_r.vendibile then
    raise exception '%', private.venditore_classe_messaggio(v_r.motivo)
      using errcode = '42501', hint = 'partner_checkout_non_disponibile',
            detail = coalesce(v_r.motivo, '');
  end if;

  if new.venditore_classe is null then
    new.venditore_classe := v_r.classe;
  elsif new.venditore_classe <> v_r.classe then
    raise exception 'La classe economica dell''ordine non corrisponde al venditore.'
      using errcode = '42501', hint = 'classe_incoerente';
  end if;

  if new.venditore_classe = 'partner' then
    v_cfg := private.marketplace_config_corrente('partner');
    if v_cfg.id is null then
      raise exception 'Configurazione di mercato mancante.' using errcode = 'P0001',
        hint = 'configurazione_classe_mancante';
    end if;
    if new.margine_obiettivo_bps <> v_cfg.margine_obiettivo_bps
       or new.riferimento_stripe_percentuale_bps <> v_cfg.riferimento_stripe_percentuale_bps
       or new.riferimento_stripe_fisso_cents <> v_cfg.riferimento_stripe_fisso_cents
       or new.prezzo_unitario_cents is null
       or new.prezzo_cents <> new.prezzo_unitario_cents * new.quantita
       or new.commissione_cents <> private.marketplace_totale_cents(
            new.prezzo_cents, new.margine_obiettivo_bps,
            new.riferimento_stripe_percentuale_bps, new.riferimento_stripe_fisso_cents
          ) - new.prezzo_cents then
      raise exception 'Le condizioni economiche dell''ordine non sono quelle dei Partner.'
        using errcode = '42501', hint = 'economia_incoerente';
    end if;
  end if;

  return new;
end;
$$;

comment on function private.partner_checkout_gate() is
  'VP-D: gate e coerenza economica dei nuovi ordini (sostituisce i blocchi '
  'A/B/C). Vendibilita e classe dal risolutore; ordini Partner solo con la '
  'riga Partner corrente e la formula unica.';

-- Le condizioni economiche di un ordine non cambiano dopo la creazione,
-- nemmeno per un writer privilegiato: i cambi di parametri, di classe o di
-- stato del Partner non muovono ordini esistenti.
create function private.orders_economia_immutabile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.venditore_classe is distinct from old.venditore_classe
     or new.margine_obiettivo_bps is distinct from old.margine_obiettivo_bps
     or new.riferimento_stripe_percentuale_bps is distinct from old.riferimento_stripe_percentuale_bps
     or new.riferimento_stripe_fisso_cents is distinct from old.riferimento_stripe_fisso_cents
     or new.commissione_cents is distinct from old.commissione_cents
     or new.prezzo_cents is distinct from old.prezzo_cents
     or new.prezzo_unitario_cents is distinct from old.prezzo_unitario_cents
     or new.quantita is distinct from old.quantita
     or new.listing_id is distinct from old.listing_id
     or new.seller_id is distinct from old.seller_id then
    raise exception 'Le condizioni economiche di un ordine non cambiano dopo la creazione.'
      using errcode = '42501', hint = 'ordine_economia_immutabile';
  end if;
  return new;
end;
$$;

revoke execute on function private.orders_economia_immutabile() from public, anon, authenticated;

create trigger orders_economia_immutabile
  before update on public.orders
  for each row execute function private.orders_economia_immutabile();

-- Proposte: stesso risolutore. Una proposta verso un annuncio non vendibile
-- per la sua classe non nasce; quelle gia esistenti non portano comunque a
-- un ordine, perche il checkout rivalida.
create or replace function private.partner_proposta_gate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r record;
begin
  if not exists (select 1 from public.listings l where l.id = new.listing_id) then
    if private.venditore_partner_aperto(new.seller_id) then
      raise exception 'Gli acquisti da Partner Vinea non sono ancora disponibili.'
        using errcode = '42501', hint = 'partner_checkout_non_disponibile';
    end if;
    return new;
  end if;

  select * into v_r from private.venditore_classe_risolvi(new.listing_id, true);
  if not v_r.vendibile then
    raise exception '%', private.venditore_classe_messaggio(v_r.motivo)
      using errcode = '42501', hint = 'partner_checkout_non_disponibile',
            detail = coalesce(v_r.motivo, '');
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- [6] Checkout, consegna, preventivo logistico e pubblicazione
-- ---------------------------------------------------------------------------
--
-- Ricreati dalle definizioni correnti con le sole modifiche VP-D.

create or replace function public.order_checkout_reserve(p_buyer_id uuid, p_listing_id uuid, p_proposal_id uuid, p_delivery_mode public.delivery_mode, p_idempotency_key text, p_quantita integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_listing public.listings%rowtype;
  v_proposal public.proposals%rowtype;
  v_order public.orders%rowtype;
  v_config public.marketplace_config%rowtype;
  v_packaging public.packaging_options%rowtype;
  v_unita uuid[];
  v_q integer;
  v_price integer;
  v_subtotale integer;
  v_totale integer;
  v_commissione integer;
  v_imballaggio integer := 0;
  v_wine_name text;
  v_cls record;
begin
  if p_buyer_id is null or p_listing_id is null
     or length(coalesce(p_idempotency_key, '')) not between 8 and 128
     or p_idempotency_key !~ '^[A-Za-z0-9._:-]+$' then
    raise exception 'Richiesta checkout non valida.' using errcode = '22023';
  end if;
  perform private.rate_limit_consume('checkout', 'user:' || p_buyer_id::text, 10, 60);

  select * into v_order from public.orders
  where buyer_id = p_buyer_id and idempotency_key = p_idempotency_key;
  if found then
    return private.order_checkout_risposta(v_order);
  end if;

  select * into v_listing from public.listings where id = p_listing_id for update;
  if not found then raise exception 'Annuncio non trovato.' using errcode = 'P0001'; end if;

  -- Il lock dell'annuncio serializza i compratori concorrenti. La chiave si
  -- ricontrolla dopo averlo preso: una prima richiesta concorrente potrebbe
  -- avere confermato nel frattempo.
  select * into v_order from public.orders
  where buyer_id = p_buyer_id and idempotency_key = p_idempotency_key;
  if found then
    return private.order_checkout_risposta(v_order);
  end if;

  perform private.listing_scadute_rilascia(v_listing.id);
  select * into v_listing from public.listings where id = p_listing_id;

  if v_listing.expires_at is not null and v_listing.expires_at <= now() then
    raise exception 'Questo annuncio è scaduto.' using errcode = 'P0001';
  end if;
  if v_listing.seller_id = p_buyer_id then
    raise exception 'Non puoi acquistare il tuo annuncio.' using errcode = 'P0001';
  end if;
  -- VP-D: classe e vendibilita dal database, sotto il lock dell'annuncio e
  -- con le righe Partner del venditore bloccate FOR SHARE fino al commit.
  select * into v_cls from private.venditore_classe_risolvi(v_listing.id, true);
  if not v_cls.vendibile then
    raise exception '%', private.venditore_classe_messaggio(v_cls.motivo)
      using errcode = '42501', hint = 'partner_checkout_non_disponibile',
            detail = coalesce(v_cls.motivo, '');
  end if;

  if p_proposal_id is null then
    v_q := coalesce(p_quantita, 1);
    if v_q < 1 or v_q > 24 then
      raise exception 'Puoi acquistare da 1 a 24 bottiglie per ordine.'
        using errcode = '22023', hint = 'quantita_non_valida';
    end if;
    if v_q > 1 and not private.inventario_flag('ordini_multi_unita') then
      raise exception 'Per ora si acquista una bottiglia per volta.'
        using errcode = 'P0001', hint = 'multi_bottiglia_non_disponibile';
    end if;
    if v_listing.stato = 'riservato' then
      raise exception 'Questo annuncio è già riservato.' using errcode = 'P0001';
    end if;
    if v_listing.stato <> 'attivo' then
      raise exception 'Questo annuncio non è disponibile.' using errcode = 'P0001';
    end if;

    -- Le prime N bottiglie disponibili, in ordine d'ingresso nell'annuncio.
    select array_agg(d.bottle_unit_id order by d.aggiunta_at, d.bottle_unit_id)
    into v_unita
    from (
      select m.bottle_unit_id, m.aggiunta_at
      from private.listing_unita m
      join public.bottle_units u on u.id = m.bottle_unit_id
      where m.listing_id = v_listing.id and m.ritirata_at is null
        and u.ceduta_at is null and u.deleted_at is null and u.stato = 'chiusa'
        and u.owner_id = v_listing.seller_id
        and not exists (select 1 from private.listing_allocazioni a
                        where a.bottle_unit_id = m.bottle_unit_id and a.rilasciata_at is null)
      order by m.aggiunta_at, m.bottle_unit_id
      limit v_q
      for update of u
    ) d;

    if coalesce(cardinality(v_unita), 0) = 0 then
      raise exception 'La bottiglia non è disponibile.' using errcode = 'P0001';
    end if;
    if cardinality(v_unita) < v_q then
      raise exception 'Disponibili solo % bottiglie.', cardinality(v_unita)
        using errcode = 'P0001', hint = 'quantita_non_disponibile';
    end if;
    v_price := v_listing.prezzo_cents;
  else
    select * into v_proposal from public.proposals
    where id = p_proposal_id for update;
    if not found or v_proposal.listing_id <> v_listing.id
       or v_proposal.buyer_id <> p_buyer_id or v_proposal.stato <> 'accettata'
       or v_proposal.scadenza <= now()
       or v_listing.stato not in ('attivo', 'riservato') then
      raise exception 'La proposta non è valida per questo checkout.' using errcode = 'P0001';
    end if;
    v_q := v_proposal.quantita;
    if p_quantita is not null and p_quantita <> v_q then
      raise exception 'La quantità non corrisponde alla proposta accettata.'
        using errcode = '22023', hint = 'quantita_non_valida';
    end if;
    if v_q > 1 and not private.inventario_flag('ordini_multi_unita') then
      raise exception 'Per ora si acquista una bottiglia per volta.'
        using errcode = 'P0001', hint = 'multi_bottiglia_non_disponibile';
    end if;

    select array_agg(a.bottle_unit_id order by a.created_at, a.bottle_unit_id)
    into v_unita
    from private.listing_allocazioni a
    join public.bottle_units u on u.id = a.bottle_unit_id
    where a.proposal_id = v_proposal.id and a.order_id is null
      and a.rilasciata_at is null and a.ceduta_at is null
      and u.ceduta_at is null and u.deleted_at is null and u.stato = 'chiusa'
      and u.owner_id = v_listing.seller_id;
    if coalesce(cardinality(v_unita), 0) <> v_q then
      raise exception 'La proposta non è valida per questo checkout.' using errcode = 'P0001';
    end if;
    v_price := coalesce(v_proposal.controproposta_cents, v_proposal.prezzo_proposto_cents);
  end if;

  -- Una sola determinazione economica per l'ordine: il subtotale delle N
  -- bottiglie con la formula e i parametri congelati di sempre, quindi un solo
  -- costo fisso di pagamento.
  v_subtotale := v_price * v_q;
  -- VP-D: la riga della classe risolta, mai un ripiego su un'altra classe.
  v_config := private.marketplace_config_corrente(v_cls.classe);
  if v_config.id is null then
    raise exception 'Configurazione di mercato mancante.' using errcode = 'P0001',
      hint = 'configurazione_classe_mancante';
  end if;
  v_totale := private.marketplace_totale_cents(
    v_subtotale, v_config.margine_obiettivo_bps,
    v_config.riferimento_stripe_percentuale_bps, v_config.riferimento_stripe_fisso_cents
  );
  v_commissione := v_totale - v_subtotale;

  if v_listing.imballaggio_codice is not null then
    select * into v_packaging from public.packaging_options
    where codice = v_listing.imballaggio_codice and valida_fino is null;
    if found then
      v_imballaggio := v_packaging.prezzo_cents;
    end if;
  end if;

  insert into public.orders (
    listing_id, proposal_id, buyer_id, seller_id, seller_bottle_unit_id,
    delivery_mode, quantita, prezzo_unitario_cents, prezzo_cents, margine_obiettivo_bps,
    riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents,
    commissione_cents, currency, idempotency_key, reservation_expires_at,
    imballaggio_codice, imballaggio_provider, imballaggio_etichetta,
    imballaggio_cents, imballaggio_scelto_at, venditore_classe
  ) values (
    v_listing.id, p_proposal_id, p_buyer_id, v_listing.seller_id,
    v_unita[1], p_delivery_mode, v_q, v_price, v_subtotale,
    v_config.margine_obiettivo_bps, v_config.riferimento_stripe_percentuale_bps,
    v_config.riferimento_stripe_fisso_cents, v_commissione, 'eur',
    p_idempotency_key, now() + interval '30 minutes',
    v_packaging.codice, v_packaging.provider, v_packaging.etichetta,
    v_imballaggio, case when v_packaging.codice is not null then now() end,
    v_cls.classe
  ) returning * into v_order;

  insert into public.payments (order_id, amount_cents, currency)
  values (v_order.id, v_order.addebito_totale_cents, v_order.currency);

  if p_proposal_id is null then
    insert into private.listing_allocazioni (
      listing_id, bottle_unit_id, buyer_id, order_id, scadenza
    )
    select v_listing.id, x.u, p_buyer_id, v_order.id, v_order.reservation_expires_at
    from unnest(v_unita) with ordinality as x(u, n)
    order by x.n;
  else
    update private.listing_allocazioni
    set order_id = v_order.id, scadenza = v_order.reservation_expires_at
    where proposal_id = p_proposal_id and order_id is null
      and rilasciata_at is null and ceduta_at is null;
    update public.proposals set stato = 'convertita' where id = p_proposal_id;
  end if;

  perform private.listing_stato_ricalcola(v_listing.id);

  insert into public.order_events (order_id, tipo, payload)
  values (v_order.id, 'checkout_reserved', jsonb_build_object(
    'quantita', v_order.quantita,
    'prezzo_unitario_cents', v_order.prezzo_unitario_cents,
    'commissione_cents', v_order.commissione_cents,
    'margine_obiettivo_bps', v_order.margine_obiettivo_bps,
    'riferimento_stripe_percentuale_bps', v_order.riferimento_stripe_percentuale_bps,
    'riferimento_stripe_fisso_cents', v_order.riferimento_stripe_fisso_cents,
    'imballaggio_codice', v_order.imballaggio_codice,
    'imballaggio_cents', v_order.imballaggio_cents,
    'venditore_classe', v_order.venditore_classe
  ));

  perform private.tracking_registra(v_order.id, 'sistema', 'Ordine ricevuto');

  select w.nome into v_wine_name
  from public.bottle_units bu join public.wines w on w.id = bu.wine_id
  where bu.id = v_unita[1];

  return private.order_checkout_risposta(v_order, v_wine_name);
exception when unique_violation then
  raise exception 'Questo annuncio è già stato prenotato.' using errcode = '23505';
end;
$function$;

create or replace function public.ordine_segna_consegnato(p_order_id uuid)
 RETURNS public.orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_config public.marketplace_config%rowtype;
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;
  perform private.rate_limit_consume('order:delivered', 'user:' || v_uid::text, 30, 60);

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.seller_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;
  if v_order.stato not in ('pagato', 'in_preparazione', 'spedito') then
    raise exception 'Questo ordine non può essere segnato come consegnato.' using errcode = 'P0001';
  end if;

  -- La finestra di verifica si calcola alla consegna con la configurazione
  -- allora in vigore, e da quel momento è una data fissa sulla riga: cambiare
  -- la configurazione non sposta le scadenze già decise.
  -- VP-D: la finestra della classe congelata sull'ordine.
  v_config := private.marketplace_config_corrente(v_order.venditore_classe);
  if v_config.id is null then
    raise exception 'Configurazione di mercato mancante.' using errcode = 'P0001';
  end if;

  update public.orders set
    stato = 'consegnato',
    consegnato_at = now(),
    auto_rilascio_scadenza = now() + make_interval(days => v_config.auto_rilascio_giorni)
  where id = v_order.id returning * into v_order;

  insert into public.order_events (order_id, tipo, payload)
  values (v_order.id, 'consegna_dichiarata', jsonb_build_object(
    'auto_rilascio_scadenza', v_order.auto_rilascio_scadenza,
    'auto_rilascio_giorni', v_config.auto_rilascio_giorni
  ));
  return v_order;
end;
$function$;

create or replace function public.logistics_quote_calcola(p_item_price_cents integer, p_packaging_sku text, p_origin_kind text, p_destination_kind text, p_weight_g integer DEFAULT NULL::integer, p_service_level text DEFAULT 'standard'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_now timestamptz := now();
  v_sku private.logistics_packaging_skus;
  v_config private.logistics_quote_config;
  v_mkt public.marketplace_config;

  v_peso_totale_g integer;
  v_volume_cm3 integer;

  v_rate_base_id uuid;
  v_rate_dest_id uuid;
  v_rate_origin_id uuid;
  v_rate_pudo_dest_id uuid;
  v_provider text;
  v_service text;

  v_transport_standard integer;
  v_packaging integer;
  v_packaging_distribution integer := 0;
  v_technology integer := 0;
  v_other_transactional integer := 0;
  v_buffer integer;
  v_buyer_upgrade integer := 0;
  v_seller_deduction integer := 0;
  v_subtotale integer;
  v_buyer_total integer;
  v_real_cost integer;
  v_commissione integer;
  v_totale_marketplace integer;
  v_quote private.logistics_quotes;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  perform private.rate_limit_consume(
    'logistics:quote', 'user:' || v_uid::text, 60, 60
  );

  if p_item_price_cents is null or p_item_price_cents <= 0 then
    raise exception 'Prezzo della merce non valido.' using errcode = '22023';
  end if;

  if p_origin_kind is null or p_origin_kind not in ('pudo', 'domicilio')
     or p_destination_kind is null or p_destination_kind not in ('pudo', 'domicilio') then
    raise exception 'Rotta non valida.' using errcode = '22023';
  end if;

  if p_weight_g is not null and p_weight_g < 0 then
    raise exception 'Peso non valido.' using errcode = '22023';
  end if;

  -- Versione corrente e attiva dello SKU. «Corrente» non basta: uno SKU
  -- corrente ma disattivato non si può preventivare.
  select * into v_sku
  from private.logistics_packaging_skus
  where sku = p_packaging_sku
    and effective_to is null
    and active
    and effective_from <= v_now;

  if v_sku.id is null then
    raise exception 'Imballaggio non disponibile.' using errcode = 'P0001';
  end if;

  select * into v_config
  from private.logistics_quote_config
  where effective_to is null
    and active
    and effective_from <= v_now;

  if v_config.id is null then
    raise exception 'Configurazione logistica non disponibile.' using errcode = 'P0001';
  end if;

  -- VP-D: questo preventivo logistico generico non conosce un annuncio e
  -- serve la rotta Beta dei privati; la classe e dichiarata, non presunta.
  -- Il checkout non lo usa: un prodotto Partner si preventiva da
  -- `listing_preventivo` e si addebita da `order_checkout_reserve`.
  v_mkt := private.marketplace_config_corrente('privato'::public.classe_venditore);
  if v_mkt.id is null then
    raise exception 'Configurazione marketplace non disponibile.' using errcode = 'P0001';
  end if;

  -- Il peso prudenziale dell'imballaggio si somma sempre: è la ragione per cui
  -- la colonna esiste separata dal peso reale della scatola.
  v_peso_totale_g := coalesce(p_weight_g, 0) + v_sku.peso_prudenziale_g;
  v_volume_cm3 := private.logistics_volume_cm3(
    v_sku.lunghezza_mm, v_sku.larghezza_mm, v_sku.altezza_mm
  );

  -- BASE STANDARD: la rotta PUDO -> PUDO. È il riferimento di tutto il resto,
  -- e fissa fornitore e servizio per i confronti successivi.
  v_rate_base_id := private.logistics_rate_scegli(
    'pudo', 'pudo', p_service_level, v_peso_totale_g, v_volume_cm3, v_now
  );

  if v_rate_base_id is null then
    raise exception 'Tariffa di trasporto non disponibile.' using errcode = 'P0001';
  end if;

  select provider_code, service_code into v_provider, v_service
  from private.logistics_shipping_rates where id = v_rate_base_id;

  v_transport_standard := private.logistics_rate_lordo_cents(v_rate_base_id);

  -- SUPPLEMENTO COMPRATORE: la differenza fra consegnare al domicilio e
  -- consegnare al punto, sullo stesso fornitore e servizio.
  if p_destination_kind = 'domicilio' then
    v_rate_dest_id := private.logistics_rate_scegli(
      'pudo', 'domicilio', p_service_level, v_peso_totale_g, v_volume_cm3,
      v_now, v_provider, v_service
    );

    if v_rate_dest_id is null then
      raise exception 'Tariffa di consegna a domicilio non disponibile.'
        using errcode = 'P0001';
    end if;

    v_buyer_upgrade := greatest(
      0,
      private.logistics_rate_lordo_cents(v_rate_dest_id) - v_transport_standard
    );
    v_rate_pudo_dest_id := v_rate_dest_id;
  else
    v_rate_pudo_dest_id := v_rate_base_id;
  end if;

  -- DEDUZIONE VENDITORE: la differenza fra ritirare al domicilio del venditore
  -- e farlo partire da un punto, a parità di destinazione. Non è un importo che
  -- il compratore paga: è una componente separata, destinata a essere sottratta
  -- al ricavo del venditore quando il checkout la userà (WP7).
  if p_origin_kind = 'domicilio' then
    v_rate_origin_id := private.logistics_rate_scegli(
      'domicilio', p_destination_kind, p_service_level, v_peso_totale_g,
      v_volume_cm3, v_now, v_provider, v_service
    );

    if v_rate_origin_id is null then
      raise exception 'Tariffa di ritiro a domicilio non disponibile.'
        using errcode = 'P0001';
    end if;

    v_seller_deduction := greatest(
      0,
      private.logistics_rate_lordo_cents(v_rate_origin_id)
        - private.logistics_rate_lordo_cents(v_rate_pudo_dest_id)
    );
  end if;

  -- Imballaggio, IVA inclusa.
  v_packaging := v_sku.costo_cents
    + private.logistics_arrotonda_bps(v_sku.costo_cents::bigint, v_sku.vat_bps);

  -- Costi di fulfillment: entrano SOLO quelli dichiarati esplicitamente come
  -- componenti della singola transazione. `min_threshold` / `max_threshold`
  -- delimitano una fascia sul prezzo della merce; `discount_bps` riduce
  -- l'importo dentro la fascia.
  select
    coalesce(sum(c.importo) filter (where c.quote_component = 'packaging_distribution'), 0),
    coalesce(sum(c.importo) filter (where c.quote_component = 'technology'), 0),
    coalesce(sum(c.importo) filter (where c.quote_component = 'other_transactional'), 0)
  into v_packaging_distribution, v_technology, v_other_transactional
  from (
    select
      f.quote_component,
      (
        (f.amount_cents
         - private.logistics_arrotonda_bps(f.amount_cents::bigint, coalesce(f.discount_bps, 0)))
        + private.logistics_arrotonda_bps(
            (f.amount_cents
             - private.logistics_arrotonda_bps(f.amount_cents::bigint, coalesce(f.discount_bps, 0))
            )::bigint,
            f.vat_bps
          )
      ) as importo
    from private.logistics_fulfillment_costs f
    where f.active
      and f.quote_component is not null
      and f.effective_to is null
      and f.effective_from <= v_now
      and f.billing_unit in ('per_unit', 'per_order')
      and (f.provider_code is null or f.provider_code = v_provider)
      and (f.min_threshold is null or p_item_price_cents >= f.min_threshold)
      and (f.max_threshold is null or p_item_price_cents < f.max_threshold)
  ) c;

  -- Il buffer si calcola sul subtotale logistico che non contiene né il
  -- supplemento del compratore né, ovviamente, la commissione di marketplace.
  v_subtotale := v_packaging + v_packaging_distribution + v_transport_standard
    + v_technology + v_other_transactional;

  v_buffer := v_config.buffer_fixed_cents
    + private.logistics_arrotonda_bps(v_subtotale::bigint, v_config.buffer_bps);

  v_buyer_total := v_subtotale + v_buffer + v_buyer_upgrade;

  -- Costo reale: tutto ciò che si paga davvero a qualcuno. Il buffer è margine
  -- della piattaforma, non un costo di fornitura, e resta fuori.
  v_real_cost := v_subtotale + v_buyer_upgrade;

  -- COMMISSIONE DI MARKETPLACE. Non è una seconda formula dell'8%: è la stessa
  -- autorità già distribuita, riletta. E non entra in nessun subtotale
  -- logistico — viaggia accanto, mai dentro.
  v_totale_marketplace := private.marketplace_totale_cents(
    p_item_price_cents,
    v_mkt.margine_obiettivo_bps,
    v_mkt.riferimento_stripe_percentuale_bps,
    v_mkt.riferimento_stripe_fisso_cents
  );
  v_commissione := greatest(0, v_totale_marketplace - p_item_price_cents);

  insert into private.logistics_quotes (
    user_id, item_price_cents, packaging_sku, origin_kind, destination_kind,
    weight_g, volume_cm3, service_level,
    packaging_cents, packaging_distribution_cents, transport_standard_cents,
    technology_cents, other_transactional_cents, logistics_buffer_cents,
    buyer_upgrade_cents, seller_pickup_deduction_cents,
    buyer_logistics_total_cents, real_logistics_cost_cents,
    marketplace_commission_cents, marketplace_margin_bps, currency,
    provider_code, service_code, packaging_version_id, rate_version_id,
    rate_destination_version_id, rate_origin_version_id,
    quote_config_version_id, marketplace_config_id,
    calculated_at, expires_at
  )
  values (
    v_uid, p_item_price_cents, v_sku.sku, p_origin_kind, p_destination_kind,
    v_peso_totale_g, v_volume_cm3, p_service_level,
    v_packaging, v_packaging_distribution, v_transport_standard,
    v_technology, v_other_transactional, v_buffer,
    v_buyer_upgrade, v_seller_deduction,
    v_buyer_total, v_real_cost,
    v_commissione, v_mkt.margine_obiettivo_bps, 'eur',
    v_provider, v_service, v_sku.id, v_rate_base_id,
    v_rate_dest_id, v_rate_origin_id,
    v_config.id, v_mkt.id,
    v_now, v_now + make_interval(secs => v_config.validita_secondi)
  )
  returning * into v_quote;

  return jsonb_build_object(
    'quoteId', v_quote.id,
    'packagingCents', v_quote.packaging_cents,
    'packagingDistributionCents', v_quote.packaging_distribution_cents,
    'transportStandardCents', v_quote.transport_standard_cents,
    'technologyCents', v_quote.technology_cents,
    'otherTransactionalCents', v_quote.other_transactional_cents,
    'logisticsBufferCents', v_quote.logistics_buffer_cents,
    'buyerUpgradeCents', v_quote.buyer_upgrade_cents,
    'sellerPickupDeductionCents', v_quote.seller_pickup_deduction_cents,
    'buyerLogisticsTotalCents', v_quote.buyer_logistics_total_cents,
    'realLogisticsCostCents', v_quote.real_logistics_cost_cents,
    'marketplaceCommissionCents', v_quote.marketplace_commission_cents,
    'marketplaceMarginBps', v_quote.marketplace_margin_bps,
    'currency', v_quote.currency,
    'providerCode', v_quote.provider_code,
    'serviceCode', v_quote.service_code,
    'weightG', v_quote.weight_g,
    'volumeCm3', v_quote.volume_cm3,
    'packagingVersionId', v_quote.packaging_version_id,
    'rateVersionId', v_quote.rate_version_id,
    'rateDestinationVersionId', v_quote.rate_destination_version_id,
    'rateOriginVersionId', v_quote.rate_origin_version_id,
    'quoteConfigVersionId', v_quote.quote_config_version_id,
    'marketplaceConfigId', v_quote.marketplace_config_id,
    'calculatedAt', v_quote.calculated_at,
    'expiresAt', v_quote.expires_at
  );
end;
$function$;

create or replace function public.listing_pubblica(p_listing_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid        uuid := auth.uid();
  v_l          public.listings%rowtype;
  v_n          integer;
  v_ok         integer;
  v_cls        record;
begin
  if v_uid is null then
    raise exception 'Devi accedere per pubblicare un annuncio.' using errcode = '42501';
  end if;

  select * into v_l from public.listings l where l.id = p_listing_id for update;

  if not found then
    raise exception 'Annuncio non trovato.' using errcode = 'P0001';
  end if;
  if v_l.seller_id is distinct from v_uid then
    raise exception 'Non puoi pubblicare un annuncio che non è tuo.' using errcode = '42501';
  end if;
  if v_l.stato not in ('bozza', 'modifiche_richieste') then
    raise exception 'Si può pubblicare solo un annuncio in bozza o con modifiche richieste.'
      using errcode = 'P0001';
  end if;
  -- VP-D: un prodotto commerciale si pubblica solo se vendibile: Partner
  -- delle unita, titolare, Partner attivo, account attivo, vendita_partner.
  if v_l.inventario = 'commerciale' then
    select * into v_cls from private.venditore_classe_risolvi(v_l.id, true);
    if v_cls.motivo = 'partner_vendita_non_disponibile' then
      raise exception 'La pubblicazione dei prodotti Partner non è ancora disponibile.'
        using errcode = 'P0001', hint = 'partner_vendita_non_disponibile';
    elsif not v_cls.vendibile then
      raise exception 'Il prodotto si pubblica solo con il Partner attivo.'
        using errcode = 'P0001', hint = coalesce(v_cls.motivo, 'partner_non_attivo');
    end if;
  end if;

  if not public.utente_maggiorenne(v_uid) then
    raise exception 'Per mettere in vendita devi dichiarare la tua data di nascita ed essere maggiorenne.'
      using errcode = 'P0001';
  end if;

  if v_l.confezione_originale_tipo is null then
    raise exception
      'Prima di pubblicare dichiara la confezione originale del prodotto.'
      using errcode = 'P0001';
  end if;
  if v_l.handoff_venditore is null then
    raise exception
      'Prima di pubblicare dichiara come consegnerai il pacco alla rete logistica.'
      using errcode = 'P0001';
  end if;

  -- Stesso lock di bottiglia_apri, su OGNI bottiglia offerta, in ordine di id
  -- per non incrociarsi con un'altra transazione che le blocchi in ordine.
  select count(*),
         count(*) filter (where bu.stato = 'chiusa' and bu.deleted_at is null
                            and bu.ceduta_at is null and bu.owner_id = v_uid)
  into v_n, v_ok
  from (
    select bu.*
    from private.listing_unita m
    join public.bottle_units bu on bu.id = m.bottle_unit_id
    where m.listing_id = p_listing_id and m.ritirata_at is null
    order by bu.id
    for update of bu
  ) bu;

  if v_n = 0 or v_ok <> v_n then
    raise exception 'Una bottiglia di questo annuncio non si può più mettere in vendita.'
      using errcode = 'P0001';
  end if;

  begin
    update public.listings
    set stato = 'attivo',
        published_at = now(),
        expires_at = now() + interval '60 days',
        stato_motivo = null,
        stato_aggiornato_da = v_uid,
        stato_aggiornato_at = now()
    where id = p_listing_id;
  exception
    when unique_violation then
      raise exception
        'Questa bottiglia ha già un altro annuncio in corso. Ritira quello prima di pubblicare questo.'
        using errcode = 'P0001';
  end;
end;
$function$;

-- La risposta del checkout porta anche la classe congelata.
create or replace function private.order_checkout_risposta(
  p_order public.orders,
  p_wine_name text default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'order_id', p_order.id, 'amount_cents', p_order.addebito_totale_cents,
    'totale_mercato_cents', p_order.totale_cents,
    'prezzo_venditore_cents', p_order.prezzo_cents,
    'prezzo_unitario_cents', p_order.prezzo_unitario_cents,
    'quantita', p_order.quantita,
    'commissione_cents', p_order.commissione_cents,
    'margine_obiettivo_bps', p_order.margine_obiettivo_bps,
    'riferimento_stripe_percentuale_bps', p_order.riferimento_stripe_percentuale_bps,
    'riferimento_stripe_fisso_cents', p_order.riferimento_stripe_fisso_cents,
    'venditore_classe', p_order.venditore_classe,
    'imballaggio_codice', p_order.imballaggio_codice,
    'imballaggio_etichetta', p_order.imballaggio_etichetta,
    'imballaggio_cents', p_order.imballaggio_cents,
    'currency', p_order.currency, 'checkout_url', pay.checkout_url,
    'provider', pay.provider,
    'provider_session_id', pay.provider_session_id,
    'reservation_expires_at', p_order.reservation_expires_at,
    'order_status', p_order.stato, 'payment_status', pay.stato
  ) || case when p_wine_name is null then '{}'::jsonb
            else jsonb_build_object('wine_name', p_wine_name) end
  from (select 1) uno
  left join public.payments pay on pay.order_id = p_order.id;
$$;

revoke execute on function private.order_checkout_risposta(public.orders, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [7] Preventivi autorevoli e catalogo del Partner
-- ---------------------------------------------------------------------------
--
-- L'interfaccia non sceglie l'aliquota: chiede al database il preventivo di
-- un annuncio (o di un prezzo che il venditore sta per chiedere) e mostra
-- cio che riceve. Stessa classe, stessa riga, stessa formula del checkout.
-- Un preventivo non determinabile non ricade sull'8%: `preventivo` e nullo e
-- il motivo lo dice.

create function public.listing_preventivo(
  p_listing_id uuid,
  p_quantita integer default 1,
  p_prezzo_unitario_cents integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_l public.listings%rowtype;
  v_r record;
  v_c record;
  v_q integer := coalesce(p_quantita, 1);
  v_prezzo integer;
  v_venditore boolean;
  v_preventivo jsonb;
  v_motivo text;
  v_imballaggio integer;
begin
  if v_q < 1 or v_q > 24 then
    raise exception 'Puoi preventivare da 1 a 24 bottiglie.' using errcode = '22023',
      hint = 'quantita_non_valida';
  end if;

  select * into v_l from public.listings where id = p_listing_id;
  v_venditore := v_uid is not null and v_l.seller_id = v_uid;
  -- Visibile solo cio che e gia pubblico, oppure il proprio annuncio. Un
  -- annuncio inesistente e uno non visibile rispondono allo stesso modo.
  if v_l.id is null or not (
    v_venditore or exists (select 1 from public.public_listings pl where pl.id = v_l.id)
  ) then
    raise exception 'Annuncio non disponibile.' using errcode = 'P0001',
      hint = 'annuncio_non_trovato';
  end if;

  v_prezzo := coalesce(p_prezzo_unitario_cents, v_l.prezzo_cents);
  select * into v_r from private.venditore_classe_di(v_l.id);
  select * into v_c from private.listing_conteggi(v_l.id);

  if v_r.vendibile or (v_venditore and v_r.motivo = 'partner_vendita_non_disponibile') then
    v_preventivo := private.preventivo_classe(v_r.classe, v_prezzo, v_q);
  end if;

  v_motivo := case
    when not v_r.vendibile then v_r.motivo
    when v_preventivo is null then 'configurazione_mancante'
    when v_l.stato <> 'attivo' or (v_l.expires_at is not null and v_l.expires_at <= now())
      then 'annuncio_non_attivo'
    when v_c.disponibili < v_q then 'quantita_non_disponibile'
    when v_q > 1 and not private.inventario_flag('ordini_multi_unita')
      then 'multi_bottiglia_non_disponibile'
    else null
  end;

  if v_l.imballaggio_codice is not null then
    select po.prezzo_cents into v_imballaggio from public.packaging_options po
    where po.codice = v_l.imballaggio_codice and po.valida_fino is null;
  end if;

  return jsonb_build_object(
    'listingId', v_l.id,
    'classe', v_r.classe,
    'acquistabile', v_motivo is null and not v_venditore,
    'motivo', v_motivo,
    'disponibili', v_c.disponibili,
    'imballaggioCents', v_imballaggio,
    'preventivo', v_preventivo
  );
end;
$$;

comment on function public.listing_preventivo(uuid, integer, integer) is
  'VP-D: preventivo di un annuncio pubblico (o proprio) con la classe e la '
  'configurazione che il checkout userebbe adesso. Il prezzo unitario '
  'facoltativo serve a proposte e controproposte; la classe non e un '
  'parametro. Preventivo nullo quando la classe non e vendibile o manca la '
  'configurazione: nessun ripiego.';

-- Preventivo del venditore prima che l'annuncio esista: quanto paghera
-- l'acquirente per il prezzo che sta per chiedere, con la SUA classe.
create function public.preventivo_vendita(
  p_prezzo_unitario_cents integer,
  p_quantita integer,
  p_inventario public.inventario_classe
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_aperto private.partners%rowtype;
  v_classe public.classe_venditore;
  v_motivo text;
  v_preventivo jsonb;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if p_inventario is null then
    raise exception 'Classe d''inventario mancante.' using errcode = '22023';
  end if;

  select * into v_aperto from private.partners p
  where p.titolare_id = v_uid
    and p.stato in ('attivo'::public.partner_stato, 'sospeso'::public.partner_stato);

  if p_inventario = 'commerciale' then
    if v_aperto.id is null or v_aperto.stato <> 'attivo'::public.partner_stato then
      raise exception 'I prodotti si preparano solo con un Partner attivo.'
        using errcode = 'P0001', hint = 'partner_non_attivo';
    end if;
    v_classe := 'partner';
    if not private.inventario_flag('vendita_partner') then
      v_motivo := 'partner_vendita_non_disponibile';
    end if;
  elsif v_aperto.id is not null then
    -- Annuncio personale di un Partner: non vendibile, nessun prezzo da
    -- mostrare (non e la tariffa dei privati, e non e una vendita Partner).
    return jsonb_build_object(
      'classe', 'partner', 'vendibile', false,
      'motivo', 'partner_annuncio_personale', 'preventivo', null
    );
  else
    v_classe := 'privato';
  end if;

  v_preventivo := private.preventivo_classe(v_classe, p_prezzo_unitario_cents, coalesce(p_quantita, 1));
  if v_preventivo is null then
    v_motivo := coalesce(v_motivo, 'configurazione_mancante');
  end if;

  return jsonb_build_object(
    'classe', v_classe,
    'vendibile', v_motivo is null,
    'motivo', v_motivo,
    'preventivo', v_preventivo
  );
end;
$$;

comment on function public.preventivo_vendita(integer, integer, public.inventario_classe) is
  'VP-D: preventivo per il venditore autenticato, con la classe che il '
  'database gli attribuisce per quella classe d''inventario.';

-- I prodotti commerciali del titolare, con conteggi, stato, vendibilita e il
-- preventivo per una bottiglia. Vuoto per chi non e titolare di un Partner.
create function public.prodotti_partner_miei()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'listingId', l.id,
      'slug', l.slug,
      'stato', l.stato,
      'prezzoCents', l.prezzo_cents,
      'produttore', w.produttore,
      'nome', w.nome,
      'annata', w.annata,
      'tipo', w.tipo,
      'regione', w.regione,
      'formato', bu.formato,
      'immagini', to_jsonb(l.immagini),
      'offerte', c.offerte,
      'disponibili', c.disponibili,
      'riservate', c.riservate,
      'vendute', c.vendute,
      'createdAt', l.created_at,
      'publishedAt', l.published_at,
      'expiresAt', l.expires_at,
      'vendibile', r.vendibile,
      'motivo', r.motivo,
      'preventivoUnitario', private.preventivo_classe('partner', l.prezzo_cents, 1)
    ) order by l.created_at desc, l.id)
    from public.listings l
    join public.bottle_units bu on bu.id = l.bottle_unit_id
    join public.wines w on w.id = bu.wine_id
    cross join lateral private.listing_conteggi(l.id) c
    cross join lateral private.venditore_classe_di(l.id) r
    where l.seller_id = v_uid
      and l.inventario = 'commerciale'::public.inventario_classe
  ), '[]'::jsonb);
end;
$$;

comment on function public.prodotti_partner_miei() is
  'VP-D: catalogo commerciale del titolare (tutti gli stati), con conteggi '
  'per unita e preventivo per bottiglia alla tariffa Partner corrente.';

revoke all on function public.listing_preventivo(uuid, integer, integer) from public, anon, authenticated, service_role;
revoke all on function public.preventivo_vendita(integer, integer, public.inventario_classe) from public, anon, authenticated, service_role;
revoke all on function public.prodotti_partner_miei() from public, anon, authenticated, service_role;
grant execute on function public.listing_preventivo(uuid, integer, integer) to anon, authenticated;
grant execute on function public.preventivo_vendita(integer, integer, public.inventario_classe) to authenticated;
grant execute on function public.prodotti_partner_miei() to authenticated;

-- ---------------------------------------------------------------------------
-- [8] Viste
-- ---------------------------------------------------------------------------

-- Una riga per classe, con la classe in coda (`create or replace view`
-- aggiunge colonne solo alla fine). Chi preventiva filtra sulla classe che
-- `public_listings.venditore_classe` o `listing_preventivo` gli danno.
create or replace view public.public_marketplace_config
with (security_invoker = off, security_barrier = true)
as
select
  c.margine_obiettivo_bps,
  c.riferimento_stripe_percentuale_bps,
  c.riferimento_stripe_fisso_cents,
  c.auto_rilascio_giorni,
  c.classe_venditore
from public.marketplace_config c
where c.valida_fino is null;

comment on view public.public_marketplace_config is
  'Configurazione corrente PER CLASSE DI VENDITORE, a elenco colonne chiuso. '
  'Non e la fonte di cio che viene addebitato, che e congelato sull''ordine; '
  'il preventivo autorevole di un annuncio e listing_preventivo.';

-- `public_listings`: colonne e ordine invariati, `venditore_classe` in coda.
-- Un prodotto commerciale e in vetrina solo se il suo Partner e attivo, il
-- venditore ne e il titolare e vendita_partner e acceso; prima di VP-D
-- bastava l'interruttore, e un Partner sospeso sarebbe rimasto visibile.
create or replace view public.public_listings
with (security_invoker = off, security_barrier = true)
as
select
  l.id,
  l.slug,
  l.prezzo_cents,
  l.prezzo_mercato_cents,
  d.disponibili as quantita,
  l.condizione,
  l.conservazione,
  l.storia,
  l.degustazione,
  l.immagini,
  l.tag,
  l.published_at,
  l.created_at,
  coalesce(l.published_at, l.created_at) as pubblicato_at,
  w.id as wine_id,
  w.slug as wine_slug,
  w.produttore,
  w.nome,
  w.annata,
  w.regione,
  w.denominazione,
  w.tipo,
  bu.formato,
  (w.produttore || ' '::text) || w.nome as ricerca,
  p.id as seller_id,
  p.username as seller_username,
  p.citta as seller_citta,
  p.avatar_url as seller_avatar_url,
  w.provenienza as wine_provenienza,
  l.imballaggio_codice,
  (exists (select 1 from private.certificazioni_valide v
           where v.user_id = p.id and v.tipo = 'identita'::public.certificazione_tipo))
  and (exists (select 1 from private.certificazioni_valide v
               where v.user_id = p.id and v.tipo = 'venditore'::public.certificazione_tipo))
    as seller_verificato,
  l.confezione_originale_tipo,
  l.confezione_originale_foto,
  -- Stessa regola del risolutore, inline: in una vista l'EXECUTE di una
  -- funzione si verifica sul lettore (anon).
  case
    when l.inventario = 'commerciale'::public.inventario_classe then 'partner'::public.classe_venditore
    when exists (select 1 from private.partners pa
                 where pa.titolare_id = l.seller_id
                   and pa.stato in ('attivo'::public.partner_stato, 'sospeso'::public.partner_stato))
      then 'partner'::public.classe_venditore
    else 'privato'::public.classe_venditore
  end as venditore_classe
from public.listings l
  join public.bottle_units bu on bu.id = l.bottle_unit_id
  join public.wines w on w.id = bu.wine_id
  join public.profiles p on p.id = l.seller_id
  cross join lateral (
    select count(*)::integer as disponibili
    from private.listing_unita m
    join public.bottle_units u on u.id = m.bottle_unit_id
    where m.listing_id = l.id and m.ritirata_at is null
      and u.ceduta_at is null and u.deleted_at is null
      and u.stato = 'chiusa'::public.bottle_unit_stato and u.owner_id = l.seller_id
      and not exists (
        select 1 from private.listing_allocazioni a
        where a.bottle_unit_id = m.bottle_unit_id and a.rilasciata_at is null
          and a.ceduta_at is null and a.scadenza > now())
  ) d
where l.stato = 'attivo'::public.listing_stato
  and (l.expires_at is null or l.expires_at > now())
  and bu.stato = 'chiusa'::public.bottle_unit_stato
  and bu.deleted_at is null
  and bu.ceduta_at is null
  and bu.owner_id = l.seller_id
  and d.disponibili > 0
  and (l.inventario = 'personale'::public.inventario_classe
       or (exists (select 1 from private.inventario_impostazioni i
                   where i.id and i.vendita_partner)
           and exists (select 1 from private.partners pa
                       where pa.id = bu.partner_id and pa.titolare_id = l.seller_id
                         and pa.stato = 'attivo'::public.partner_stato)
           and p.stato_utente = 'attivo'::public.utente_stato))
  and p.stato_utente <> 'rimosso'::public.utente_stato
  and not exists (
    select 1 from public.profiles me
    where me.id = (select auth.uid()) and me.stato_utente = 'rimosso'::public.utente_stato
  );

-- Riconciliazione: la classe in coda, per separare i conti delle due classi.
create or replace view public.order_margine_riconciliazione
with (security_invoker = off, security_barrier = true)
as
select
  o.id as order_id,
  o.created_at,
  o.prezzo_cents,
  o.commissione_cents,
  o.totale_cents,
  o.margine_obiettivo_bps,
  o.riferimento_stripe_percentuale_bps,
  o.riferimento_stripe_fisso_cents,
  p.stato as payment_stato,
  round(o.commissione_cents::numeric * 10000::numeric / nullif(o.prezzo_cents, 0)::numeric, 2)
    as commissione_effettiva_bps,
  (round(o.totale_cents::numeric * o.riferimento_stripe_percentuale_bps::numeric / 10000::numeric)
    + o.riferimento_stripe_fisso_cents::numeric)::integer as fee_riferimento_cents,
  (o.totale_cents::numeric
    - round(o.totale_cents::numeric * o.riferimento_stripe_percentuale_bps::numeric / 10000::numeric)
    - o.riferimento_stripe_fisso_cents::numeric - o.prezzo_cents::numeric)::integer
    as margine_proiettato_cents,
  p.fee_stripe_reale_cents,
  o.totale_cents - p.fee_stripe_reale_cents - o.prezzo_cents as margine_reale_cents,
  ((o.totale_cents - p.fee_stripe_reale_cents - o.prezzo_cents)::numeric
    - (o.totale_cents::numeric
       - round(o.totale_cents::numeric * o.riferimento_stripe_percentuale_bps::numeric / 10000::numeric)
       - o.riferimento_stripe_fisso_cents::numeric - o.prezzo_cents::numeric))::integer
    as scarto_cents,
  p.fee_riconciliata_at,
  o.venditore_classe
from public.orders o
  join public.payments p on p.order_id = o.id;

notify pgrst, 'reload schema';
