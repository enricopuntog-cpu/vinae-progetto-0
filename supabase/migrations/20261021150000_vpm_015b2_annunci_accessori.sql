-- VPM-015B2 — Annunci Accessori: fondazione tecnica della futura compravendita.
--
-- Contratto: docs/VPM_015B2_ANNUNCI_ACCESSORI.md. Decisioni del titolare:
--   * margine netto obiettivo Vinea sugli accessori: 10% (1000 bps) per i
--     privati, 15% (1500 bps) per i Partner; vino invariato (800 / 1500);
--   * il venditore indica quanto vuole ricevere; commissione e copertura della
--     fee di pagamento si AGGIUNGONO al prezzo pagato dall'acquirente (come per
--     le bottiglie); base percentuale = prodotti, spedizione esclusa;
--   * da 1 a N pezzi dello stesso accessorio per annuncio, senza vendere tutto;
--   * spedizione a carico dell'acquirente, imballaggio a cura del venditore,
--     nessuna tariffa inventata (senza tariffa reale il preventivo e
--     indisponibile, mai 0).
--
-- NESSUNA VENDITA. Questa migrazione NON crea alcun annuncio acquistabile, ordine,
-- pagamento, checkout, spedizione o trasferimento.
--
-- Che cosa fa:
--   [1] dominio merceologico e margini versionati per dominio e classe
--       (`private.marketplace_margini_dominio`): una riga corrente per
--       dominio e classe, margine accessori 1000/1500 bps. NON duplica i
--       parametri Stripe: li legge da `marketplace_config` (classe del
--       venditore). La formula resta `private.marketplace_totale_cents` e la
--       copertura della fee sulle voci d'ordine
--       `private.pagamento_fee_accessori_cents` (dove "accessori" indica gli
--       importi accessori dell'ordine, NON i gadget enologici), entrambe
--       intatte. `private.preventivo_dominio` e il nucleo unico dei preventivi;
--   [2] interruttore nel database, spento di default, per la preparazione degli
--       annunci (accensione solo con il ruolo di rilascio accessori_release);
--   [3] categorie vendibili, FAIL-CLOSED: una categoria senza regola non si
--       vende (nessun alcolico ne articolo regolamentato per costruzione);
--   [4] `private.annunci_accessori`: annuncio di un accessorio della Cantina,
--       in `private`, senza grant. Stati bozza / in_revisione / ritirato: lo
--       stato "attivo" NON esiste. Un solo annuncio aperto per accessorio;
--       quantita offerta <= quantita posseduta sotto lock dell'accessorio, per
--       ogni writer, anche privilegiato; nessuna colonna di quantita impegnata
--       (e sempre derivata);
--   [5] guardia sugli accessori della Cantina: non si scende sotto la quantita
--       impegnata, non si archivia ne si rimuove un accessorio con un annuncio
--       aperto, non si cambia categoria in revisione;
--   [6] porte `annunci_accessori_*` per il proprietario (solo authenticated) e
--       per gli admin (interruttore). `annunci_accessori_pubblica` risponde
--       sempre "pubblicazione chiusa".
--
-- Che cosa NON fa: nessuna scrittura su listings, orders, payments, proposals,
-- bottle_units, wines; nessuna modifica a migrazioni precedenti, a
-- `marketplace_config`, al checkout o alla formula; nessun grant ad anon;
-- nessuna vista pubblica; nessun ruolo assegnato.

-- ---------------------------------------------------------------------------
-- [1] Dominio merceologico e margini versionati
-- ---------------------------------------------------------------------------

create type public.dominio_merceologico as enum ('vino', 'accessori_enologici');

comment on type public.dominio_merceologico is
  'Dominio merceologico di una vendita. Il vino resta governato da '
  'public.marketplace_config (800 / 1500 bps); gli altri domini hanno il proprio '
  'margine in private.marketplace_margini_dominio. NB: `accessori_enologici` '
  'sono i gadget del catalogo Accessori; gli "accessori" di '
  'private.pagamento_fee_accessori_cents sono gli importi accessori dell''ordine '
  '(imballaggio, trasporto).';

create table private.marketplace_margini_dominio (
  id bigint generated always as identity primary key,
  dominio public.dominio_merceologico not null,
  classe_venditore public.classe_venditore not null,
  -- Punti base: 1000 = 10,00%. Il margine che deve restare a Vinea DOPO la
  -- fee di pagamento di riferimento (stessa semantica di marketplace_config).
  margine_obiettivo_bps integer not null
    check (margine_obiettivo_bps between 0 and 5000),
  valida_da timestamptz not null default now(),
  valida_fino timestamptz,
  nota text check (nota is null or length(nota) between 1 and 500),
  created_at timestamptz not null default now(),
  constraint marketplace_margini_dominio_intervallo
    check (valida_fino is null or valida_fino > valida_da),
  -- Il vino ha la sua configurazione in marketplace_config: una seconda sede
  -- sarebbe una seconda fonte di verita sulle tariffe gia in produzione.
  constraint marketplace_margini_dominio_non_vino
    check (dominio <> 'vino'::public.dominio_merceologico)
);

create unique index marketplace_margini_dominio_una_corrente
  on private.marketplace_margini_dominio (dominio, classe_venditore)
  where valida_fino is null;

comment on table private.marketplace_margini_dominio is
  'VPM-015B2: margine obiettivo versionato per dominio e classe di venditore '
  '(solo domini diversi dal vino). Una riga corrente per coppia; le righe chiuse '
  'sono storico. Fee Stripe di riferimento e finestra di verifica NON stanno '
  'qui: si leggono dalla riga corrente di marketplace_config della stessa '
  'classe, cosi esiste una sola sede per quei parametri. Cambiare un margine = '
  'chiudere la riga corrente e aprirne una nuova; gli ordini futuri congeleranno '
  'i parametri applicati.';

alter table private.marketplace_margini_dominio enable row level security;
revoke all on table private.marketplace_margini_dominio from public, anon, authenticated;

-- Una riga si chiude (valida_fino), non si riscrive ne si cancella: vale anche
-- per i writer privilegiati.
create function private.marketplace_margini_dominio_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op in ('DELETE', 'TRUNCATE') then
    raise exception 'Le tariffe versionate non si cancellano: si chiude la riga corrente.'
      using errcode = '42501', hint = 'tariffa_non_cancellabile';
  end if;
  if new.id <> old.id or new.dominio <> old.dominio
     or new.classe_venditore <> old.classe_venditore
     or new.margine_obiettivo_bps <> old.margine_obiettivo_bps
     or new.valida_da <> old.valida_da then
    raise exception 'Una tariffa versionata non si riscrive: si chiude e se ne apre una nuova.'
      using errcode = '42501', hint = 'tariffa_non_modificabile';
  end if;
  if old.valida_fino is not null and new.valida_fino is distinct from old.valida_fino then
    raise exception 'Una tariffa chiusa non si riapre.'
      using errcode = '42501', hint = 'tariffa_non_modificabile';
  end if;
  return new;
end;
$$;

revoke execute on function private.marketplace_margini_dominio_guard() from public, anon, authenticated;

create trigger marketplace_margini_dominio_guard
  before update or delete on private.marketplace_margini_dominio
  for each row execute function private.marketplace_margini_dominio_guard();
create trigger marketplace_margini_dominio_no_truncate
  before truncate on private.marketplace_margini_dominio
  for each statement execute function private.marketplace_margini_dominio_guard();

insert into private.marketplace_margini_dominio
  (dominio, classe_venditore, margine_obiettivo_bps, nota)
values
  ('accessori_enologici', 'privato', 1000,
   'VPM-015B2: margine netto obiettivo 10% sugli accessori venduti da privati '
   '(decisione del titolare). Base: prezzo dei prodotti, spedizione esclusa.'),
  ('accessori_enologici', 'partner', 1500,
   'VPM-015B2: margine netto obiettivo 15% sugli accessori venduti tramite Vinea '
   'Partner (decisione del titolare). Predisposizione: nessuna vendita Partner attiva.');

-- Lettore: riga corrente di una coppia dominio/classe, nulla se manca (ogni
-- chiamante fallisce chiuso, nessun ripiego su un'altra classe o dominio).
create function private.marketplace_margine_dominio(
  p_dominio public.dominio_merceologico,
  p_classe public.classe_venditore
)
returns private.marketplace_margini_dominio
language sql
stable
security definer
set search_path = ''
as $$
  select * from private.marketplace_margini_dominio
  where valida_fino is null
    and dominio = p_dominio
    and classe_venditore = p_classe
  order by valida_da desc
  limit 1;
$$;

revoke execute on function private.marketplace_margine_dominio(public.dominio_merceologico, public.classe_venditore)
  from public, anon, authenticated;

-- Nucleo unico dei preventivi per dominio. Il VINO usa la stessa riga e la
-- stessa formula del checkout (marketplace_config), quindi il suo risultato
-- coincide con private.preventivo_classe; gli altri domini sostituiscono il
-- solo margine con quello del dominio e restano sulla formula e sui parametri
-- di pagamento della classe.
--
--   totale   = marketplace_totale_cents(subtotale, margine, p, F)
--   commissione = totale - subtotale          (margine Vinea + costo del pagamento)
--   costo del pagamento di riferimento = round(totale * p) + F
--   quota Vinea = totale - costo - subtotale  (>= margine obiettivo * subtotale)
--
-- Con una spedizione nota (A centesimi): la commissione NON cambia (nessuna
-- commissione sulla spedizione), la quota fissa resta una (gia nel totale), e
-- l'acquirente sostiene la fee percentuale che A genera, calcolata da
-- private.pagamento_fee_accessori_cents. Senza A (nessuna tariffa) i campi
-- della spedizione sono nulli: mai zero.
create function private.preventivo_dominio(
  p_dominio public.dominio_merceologico,
  p_classe public.classe_venditore,
  p_prezzo_unitario_cents integer,
  p_quantita integer,
  p_spedizione_cents integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_config public.marketplace_config%rowtype;
  v_margine private.marketplace_margini_dominio%rowtype;
  v_bps integer;
  v_margine_id bigint;
  v_subtotale integer;
  v_totale integer;
  v_costo integer;
  v_copertura integer;
begin
  if p_prezzo_unitario_cents is null or p_prezzo_unitario_cents <= 0
     or p_prezzo_unitario_cents > 10000000
     or p_quantita is null or p_quantita < 1 or p_quantita > 120 then
    raise exception 'Prezzo o quantita non validi.' using errcode = '22023',
      hint = 'preventivo_non_valido';
  end if;
  if p_spedizione_cents is not null and (p_spedizione_cents < 0 or p_spedizione_cents > 1000000) then
    raise exception 'Spedizione non valida.' using errcode = '22023',
      hint = 'preventivo_non_valido';
  end if;
  if p_dominio is null or p_classe is null then
    return null;
  end if;

  v_config := private.marketplace_config_corrente(p_classe);
  if v_config.id is null then
    return null;
  end if;

  if p_dominio = 'vino'::public.dominio_merceologico then
    v_bps := v_config.margine_obiettivo_bps;
    v_margine_id := null;
  else
    v_margine := private.marketplace_margine_dominio(p_dominio, p_classe);
    if v_margine.id is null then
      return null;
    end if;
    v_bps := v_margine.margine_obiettivo_bps;
    v_margine_id := v_margine.id;
  end if;

  v_subtotale := p_prezzo_unitario_cents * p_quantita;
  v_totale := private.marketplace_totale_cents(
    v_subtotale, v_bps,
    v_config.riferimento_stripe_percentuale_bps, v_config.riferimento_stripe_fisso_cents
  );
  v_costo := (round(v_totale::numeric * v_config.riferimento_stripe_percentuale_bps::numeric / 10000::numeric)
              + v_config.riferimento_stripe_fisso_cents::numeric)::integer;

  if p_spedizione_cents is not null then
    v_copertura := private.pagamento_fee_accessori_cents(
      v_subtotale, v_bps,
      v_config.riferimento_stripe_percentuale_bps, v_config.riferimento_stripe_fisso_cents,
      p_spedizione_cents
    );
  end if;

  return jsonb_build_object(
    'dominio', p_dominio,
    'classe', p_classe,
    'configId', v_config.id,
    'margineConfigId', v_margine_id,
    'quantita', p_quantita,
    'prezzoUnitarioCents', p_prezzo_unitario_cents,
    'subtotaleCents', v_subtotale,
    'commissioneCents', v_totale - v_subtotale,
    'totaleCents', v_totale,
    'margineObiettivoBps', v_bps,
    'riferimentoPercentualeBps', v_config.riferimento_stripe_percentuale_bps,
    'riferimentoFissoCents', v_config.riferimento_stripe_fisso_cents,
    'costoPagamentoRiferimentoCents', v_costo,
    'quotaVineaCents', v_totale - v_subtotale - v_costo,
    'spedizioneCents', p_spedizione_cents,
    'coperturaPagamentoSpedizioneCents', v_copertura,
    'addebitoTotaleCents',
      case when p_spedizione_cents is null then null
           else v_totale + p_spedizione_cents + v_copertura end
  );
end;
$$;

comment on function private.preventivo_dominio(public.dominio_merceologico, public.classe_venditore, integer, integer, integer) is
  'VPM-015B2: preventivo economico per dominio e classe, unico nucleo. Vino = '
  'marketplace_config (identico a preventivo_classe); gli altri domini sostituiscono '
  'il margine con private.marketplace_margini_dominio e leggono fee di riferimento '
  'dalla classe. Una sola quota fissa per transazione; nessuna commissione sulla '
  'spedizione; copertura della fee sulla spedizione = pagamento_fee_accessori_cents.';

revoke execute on function private.preventivo_dominio(public.dominio_merceologico, public.classe_venditore, integer, integer, integer)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [2] Interruttore nel database (fail-closed)
-- ---------------------------------------------------------------------------
--
-- `preparazione_attiva` apre la preparazione degli annunci (bozze e revisione).
-- `pubblicazione_attiva` esiste per dichiarare che il blocco B2 NON contiene
-- alcun percorso di pubblicazione commerciale: il vincolo lo tiene a falso, e
-- sara il blocco successivo a sostituirlo.

create table private.annunci_accessori_impostazioni (
  singleton boolean primary key default true,
  preparazione_attiva boolean not null default false,
  pubblicazione_attiva boolean not null default false,
  aggiornato_da uuid references public.profiles (id) on delete restrict,
  updated_at timestamptz not null default now(),
  constraint annunci_accessori_impostazioni_singola check (singleton),
  constraint annunci_accessori_nessuna_pubblicazione check (not pubblicazione_attiva)
);

comment on table private.annunci_accessori_impostazioni is
  'VPM-015B2: una sola riga. preparazione_attiva abilita bozze e revisione degli '
  'annunci Accessori (spenta di default, accensione con ruolo accessori_release). '
  'pubblicazione_attiva e vincolata a falso: nessun percorso di pubblicazione '
  'commerciale esiste in questo blocco.';

alter table private.annunci_accessori_impostazioni enable row level security;
revoke all on table private.annunci_accessori_impostazioni from public, anon, authenticated;

insert into private.annunci_accessori_impostazioni (singleton) values (true);

create trigger annunci_accessori_impostazioni_set_updated_at
  before update on private.annunci_accessori_impostazioni
  for each row execute function extensions.moddatetime('updated_at');

create function private.annunci_accessori_impostazioni_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.preparazione_attiva and not old.preparazione_attiva then
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

revoke execute on function private.annunci_accessori_impostazioni_guard() from public, anon, authenticated;

create trigger annunci_accessori_impostazioni_guard
  before update on private.annunci_accessori_impostazioni
  for each row execute function private.annunci_accessori_impostazioni_guard();
create trigger annunci_accessori_impostazioni_no_delete
  before delete on private.annunci_accessori_impostazioni
  for each row execute function private.accessori_non_si_cancella();
create trigger annunci_accessori_impostazioni_no_truncate
  before truncate on private.annunci_accessori_impostazioni
  for each statement execute function private.accessori_non_si_cancella();

-- Il registro delle azioni admin accoglie anche questo interruttore.
alter table private.accessori_registro drop constraint accessori_registro_oggetto_ammesso;
alter table private.accessori_registro
  add constraint accessori_registro_oggetto_ammesso
  check (oggetto in ('categoria', 'accessorio', 'visibilita', 'cantina_accessori', 'annunci_accessori'));

-- ---------------------------------------------------------------------------
-- [3] Categorie vendibili — fail-closed
-- ---------------------------------------------------------------------------
--
-- Una categoria si vende solo se ha una riga `vendibile`; la sua mancanza vale
-- "no". Le categorie nuove nascono quindi chiuse. Restano chiuse in questo
-- blocco "Set regalo" (puo contenere bevande), "Pulizia" (prodotti chimici) e
-- "Altri accessori" (contenitore generico, non rivisto). Alcolici, articoli
-- regolamentati e sciabole non sono vendibili in nessun caso: questa lista
-- non li prevede e la dichiarazione di conformita del venditore li esclude.

create table private.annunci_accessori_categorie (
  categoria_id uuid primary key references private.accessori_categorie (id) on delete restrict,
  vendibile boolean not null,
  nota text check (nota is null or length(nota) between 1 and 300),
  created_at timestamptz not null default now()
);

comment on table private.annunci_accessori_categorie is
  'VPM-015B2: quali categorie della tassonomia Vinea ammettono un annuncio. '
  'Nessuna riga = non vendibile (fail-closed). Una sottocategoria e vendibile solo '
  'se lo sono anche il suo genitore e lei stessa.';

alter table private.annunci_accessori_categorie enable row level security;
revoke all on table private.annunci_accessori_categorie from public, anon, authenticated;

insert into private.annunci_accessori_categorie (categoria_id, vendibile, nota)
select c.id, true, 'VPM-015B2: attrezzo fisico non alcolico e non regolamentato.'
from private.accessori_categorie c
left join private.accessori_categorie g on g.id = c.parent_id
where coalesce(g.slug, c.slug) in
  ('apertura', 'calici', 'degustazione', 'decanter', 'raffreddamento', 'conservazione', 'espositori');

create function private.annuncio_accessorio_categoria_vendibile(p_categoria uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select r.vendibile
       and (c.parent_id is null or coalesce((
              select rg.vendibile from private.annunci_accessori_categorie rg
              where rg.categoria_id = c.parent_id), false))
    from private.accessori_categorie c
    join private.annunci_accessori_categorie r on r.categoria_id = c.id
    where c.id = p_categoria and c.attiva
  ), false);
$$;

revoke execute on function private.annuncio_accessorio_categoria_vendibile(uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Il venditore: classe e ammissione, dal database
-- ---------------------------------------------------------------------------
--
-- Il percorso degli accessori PERSONALI e dei privati. Un Partner attivo o
-- sospeso non lo usa (classe 'partner', non ammesso): non ottiene ne la tariffa
-- dei privati ne un'esposizione professionale mascherata da personale. Il
-- titolare di un Partner revocato non vende finche Vinea non lo riabilita
-- (decisione del 13 ottobre 2026), stessa regola `venditore_vendite_bloccate`.
-- Un Partner invitato o in verifica e, come per le bottiglie, un privato.

create function private.annuncio_accessorio_venditore(
  p_seller_id uuid,
  out classe public.classe_venditore,
  out ammesso boolean,
  out motivo text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from private.partners p
    where p.titolare_id = p_seller_id
      and p.stato in ('attivo'::public.partner_stato, 'sospeso'::public.partner_stato)
  ) then
    classe := 'partner'; ammesso := false; motivo := 'partner_percorso_non_consentito';
    return;
  end if;
  if private.venditore_vendite_bloccate(p_seller_id) then
    classe := 'privato'; ammesso := false; motivo := 'partner_revocato';
    return;
  end if;
  if private.utente_stato_di(p_seller_id) <> 'attivo'::public.utente_stato then
    classe := 'privato'; ammesso := false; motivo := 'account_non_attivo';
    return;
  end if;
  classe := 'privato'; ammesso := true; motivo := null;
end;
$$;

comment on function private.annuncio_accessorio_venditore(uuid) is
  'VPM-015B2: classe economica e ammissione del venditore di accessori personali, '
  'decise dal database. Mai un argomento del chiamante.';

revoke execute on function private.annuncio_accessorio_venditore(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [4] Annunci Accessori
-- ---------------------------------------------------------------------------

create table private.annunci_accessori (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles (id) on delete cascade,
  -- L'accessorio posseduto e la SOLA fonte di verita di nome, categoria, foto e
  -- quantita posseduta; l'annuncio porta solo cio che e proprio dell'offerta.
  -- La cascata serve alla cancellazione dell'account; la rimozione di un
  -- accessorio con un annuncio aperto e rifiutata dalla guardia [5].
  cantina_accessorio_id uuid not null references private.cantina_accessori (id) on delete cascade,
  stato text not null default 'bozza',
  quantita integer not null,
  prezzo_unitario_cents integer not null,
  condizione text not null,
  descrizione text not null default '',
  -- Dichiarazione del venditore: non e un articolo alcolico ne regolamentato.
  dichiarazione_conforme boolean not null default false,
  -- Dichiarazione facoltativa del collo (per ogni pezzo); serve al preventivo
  -- di spedizione quando esistera una tariffa. L'imballaggio e a cura e a
  -- carico del venditore: nessun costo di scatola e addebitato o rimborsato.
  peso_g integer,
  lunghezza_mm integer,
  larghezza_mm integer,
  altezza_mm integer,
  fragile boolean not null default false,
  inviato_at timestamptz,
  ritirato_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint annunci_accessori_stato_ammesso
    check (stato in ('bozza', 'in_revisione', 'ritirato')),
  constraint annunci_accessori_quantita_forma check (quantita between 1 and 120),
  constraint annunci_accessori_prezzo_forma
    check (prezzo_unitario_cents between 100 and 1000000),
  constraint annunci_accessori_condizione_ammessa
    check (condizione in ('nuovo', 'come_nuovo', 'usato', 'da_collezione')),
  constraint annunci_accessori_descrizione_forma check (length(descrizione) <= 1000),
  constraint annunci_accessori_peso_forma check (peso_g is null or peso_g between 1 and 30000),
  constraint annunci_accessori_misure_forma check (
    (lunghezza_mm is null) = (larghezza_mm is null)
    and (larghezza_mm is null) = (altezza_mm is null)
    and (lunghezza_mm is null or lunghezza_mm between 1 and 1500)
    and (larghezza_mm is null or larghezza_mm between 1 and 1500)
    and (altezza_mm is null or altezza_mm between 1 and 1500)
  ),
  constraint annunci_accessori_ritirato_coerente
    check ((stato = 'ritirato') = (ritirato_at is not null)),
  constraint annunci_accessori_revisione_coerente
    check (stato <> 'in_revisione' or inviato_at is not null)
);

comment on table private.annunci_accessori is
  'VPM-015B2: annuncio di un accessorio posseduto, in preparazione. NON e un annuncio '
  'pubblico e NON e acquistabile: lo stato "attivo" non esiste, nessuna vista o porta '
  'pubblica lo legge, nessuna FK da o verso listings, orders, payments o proposals. '
  'Nessun grant client: si legge e si scrive solo con le porte annunci_accessori_*, '
  'che ricavano il venditore da auth.uid(). La quantita impegnata non e una colonna: '
  'e la somma delle quantita degli annunci aperti dello stesso accessorio.';

create unique index annunci_accessori_uno_aperto
  on private.annunci_accessori (cantina_accessorio_id)
  where stato in ('bozza', 'in_revisione');
create index annunci_accessori_seller_idx
  on private.annunci_accessori (seller_id, stato, created_at desc);

alter table private.annunci_accessori enable row level security;
revoke all on table private.annunci_accessori from public, anon, authenticated;

create trigger annunci_accessori_set_updated_at
  before update on private.annunci_accessori
  for each row execute function extensions.moddatetime('updated_at');

-- Le regole che valgono per ogni writer, anche privilegiato. Ordine dei lock:
-- sempre accessorio della Cantina, poi annuncio.
create function private.annunci_accessori_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item private.cantina_accessori%rowtype;
  v_v record;
  v_altri integer;
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
         ('bozza', 'in_revisione'), ('in_revisione', 'bozza'),
         ('bozza', 'ritirato'), ('in_revisione', 'ritirato')) then
      raise exception 'Passaggio di stato non ammesso.'
        using errcode = '22023', hint = 'transizione_non_ammessa';
    end if;
    if old.stato <> 'bozza' and (
         new.quantita, new.prezzo_unitario_cents, new.condizione, new.descrizione,
         new.dichiarazione_conforme, new.peso_g, new.lunghezza_mm, new.larghezza_mm,
         new.altezza_mm, new.fragile
       ) is distinct from (
         old.quantita, old.prezzo_unitario_cents, old.condizione, old.descrizione,
         old.dichiarazione_conforme, old.peso_g, old.lunghezza_mm, old.larghezza_mm,
         old.altezza_mm, old.fragile
       ) then
      raise exception 'Un annuncio in revisione non si modifica: riportalo in bozza.'
        using errcode = '22023', hint = 'annuncio_non_modificabile';
    end if;
  elsif new.stato <> 'bozza' then
    raise exception 'Un annuncio nasce in bozza.'
      using errcode = '22023', hint = 'annuncio_nasce_bozza';
  end if;

  if new.stato in ('bozza', 'in_revisione') then
    -- Lock dell'accessorio: serializza ogni confronto fra quantita offerta e
    -- quantita posseduta, anche fra sessioni concorrenti.
    select * into v_item from private.cantina_accessori
    where id = new.cantina_accessorio_id for update;
    if v_item.id is null or v_item.owner_id <> new.seller_id then
      raise exception 'Accessorio non trovato.' using errcode = 'P0001', hint = 'non_trovato';
    end if;

    if tg_op = 'INSERT' or new.quantita is distinct from old.quantita then
      if v_item.archiviato_at is not null then
        raise exception 'Un accessorio archiviato non si mette in vendita.'
          using errcode = '22023', hint = 'accessorio_archiviato';
      end if;
      select coalesce(sum(a.quantita), 0) into v_altri
      from private.annunci_accessori a
      where a.cantina_accessorio_id = new.cantina_accessorio_id
        and a.stato in ('bozza', 'in_revisione')
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
    if not private.annuncio_accessorio_categoria_vendibile(v_item.categoria_id) then
      raise exception 'Questa categoria non e ancora vendibile.'
        using errcode = '22023', hint = 'categoria_non_vendibile';
    end if;

    if new.stato = 'in_revisione' and (tg_op = 'INSERT' or old.stato <> 'in_revisione') then
      if not new.dichiarazione_conforme then
        raise exception 'Serve la dichiarazione di conformita.'
          using errcode = '22023', hint = 'dichiarazione_mancante';
      end if;
      if cardinality(v_item.immagini) < 1 then
        raise exception 'Serve almeno una fotografia.'
          using errcode = '22023', hint = 'foto_obbligatoria';
      end if;
      new.inviato_at := coalesce(new.inviato_at, now());
    end if;
    if new.stato = 'bozza' then
      new.inviato_at := null;
    end if;
  elsif new.stato = 'ritirato' and new.ritirato_at is null then
    new.ritirato_at := now();
  end if;

  return new;
end;
$$;

revoke execute on function private.annunci_accessori_guard() from public, anon, authenticated;

create trigger annunci_accessori_guard
  before insert or update on private.annunci_accessori
  for each row execute function private.annunci_accessori_guard();

-- ---------------------------------------------------------------------------
-- [5] Guardia sugli accessori della Cantina
-- ---------------------------------------------------------------------------
--
-- Sull'accessorio posseduto, non sull'annuncio: cosi nessuna porta della
-- Cantina (B1) puo togliere la merce sotto un annuncio aperto. La cancellazione
-- dell'account (profilo gia rimosso) passa libera.

create function private.annunci_accessori_cantina_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_impegnati integer;
  v_in_revisione boolean;
begin
  select coalesce(sum(a.quantita), 0), coalesce(bool_or(a.stato = 'in_revisione'), false)
  into v_impegnati, v_in_revisione
  from private.annunci_accessori a
  where a.cantina_accessorio_id = old.id and a.stato in ('bozza', 'in_revisione');

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
  if new.categoria_id is distinct from old.categoria_id and v_in_revisione then
    raise exception 'L''accessorio ha un annuncio in revisione.'
      using errcode = '22023', hint = 'annuncio_in_revisione';
  end if;
  return new;
end;
$$;

revoke execute on function private.annunci_accessori_cantina_guard() from public, anon, authenticated;

create trigger annunci_accessori_cantina_guard
  before update or delete on private.cantina_accessori
  for each row execute function private.annunci_accessori_cantina_guard();

-- ---------------------------------------------------------------------------
-- Helper delle porte
-- ---------------------------------------------------------------------------

-- Preparazione degli annunci consentita al chiamante: funzione Cantina e
-- interruttore accesi, oppure un admin reale (che puo collaudare in produzione
-- senza accendere nulla al pubblico).
create function private.annunci_accessori_consentita()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (
    private.cantina_accessori_funzione_attiva()
    and coalesce((select i.preparazione_attiva from private.annunci_accessori_impostazioni i), false)
  ) or private.accessori_e_admin();
$$;

revoke execute on function private.annunci_accessori_consentita() from public, anon, authenticated;

create function private.annunci_accessori_intero(
  p_valore jsonb, p_min integer, p_max integer, p_hint text
)
returns integer
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_valore is null or jsonb_typeof(p_valore) <> 'number'
     or (p_valore #>> '{}')::numeric <> trunc((p_valore #>> '{}')::numeric)
     or (p_valore #>> '{}')::numeric not between p_min and p_max then
    raise exception 'Valore non valido.' using errcode = '22023', hint = p_hint;
  end if;
  return (p_valore #>> '{}')::integer;
end;
$$;

revoke execute on function private.annunci_accessori_intero(jsonb, integer, integer, text)
  from public, anon, authenticated;

-- Quantita impegnata dagli annunci aperti di un accessorio (sempre derivata).
create function private.annuncio_accessorio_impegnati(p_cantina_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(a.quantita), 0)::integer
  from private.annunci_accessori a
  where a.cantina_accessorio_id = p_cantina_id and a.stato in ('bozza', 'in_revisione');
$$;

revoke execute on function private.annuncio_accessorio_impegnati(uuid) from public, anon, authenticated;

-- Forma dell'annuncio per il proprietario.
create function private.annuncio_accessorio_json(p_id uuid)
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
    'updated_at', a.updated_at
  )
  from private.annunci_accessori a
  join private.cantina_accessori c on c.id = a.cantina_accessorio_id
  where a.id = p_id;
$$;

revoke execute on function private.annuncio_accessorio_json(uuid) from public, anon, authenticated;

-- Spedizione: nessuna tariffa per gli accessori. Le tariffe commerciali
-- esistenti sono per formato di bottiglia (CHECK sul formato d'imballaggio) e
-- non descrivono un collo di accessori; finche non ne esiste una reale il
-- preventivo e INDISPONIBILE, mai 0 e mai una stima. Questa e l'unica sede del
-- fatto: il blocco che introduce una tariffa per accessori la sostituisce.
create function private.annuncio_accessorio_spedizione()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'disponibile', false,
    'motivi', jsonb_build_array('tariffa_accessori_non_configurata'),
    'pagata_da', 'acquirente',
    'commissione_su_spedizione', false,
    'imballaggio_a_cura_del', 'venditore'
  );
$$;

revoke execute on function private.annuncio_accessorio_spedizione() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [6] Porte del proprietario
-- ---------------------------------------------------------------------------

-- Stato per l'interfaccia. `vendite_attive` e sempre falso in questo blocco.
create function public.annunci_accessori_stato()
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
    'classe', v_v.classe,
    'venditore_ammesso', v_v.ammesso,
    'motivo', v_v.motivo
  );
end;
$$;

comment on function public.annunci_accessori_stato() is
  'Se la preparazione degli annunci Accessori e usabile dal chiamante e se il chiamante e ammesso. vendite_attive e sempre falso.';

create function public.annunci_accessori_elenca(p_ritirati boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
begin
  if not private.annunci_accessori_consentita() then
    return '[]'::jsonb;
  end if;
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

comment on function public.annunci_accessori_elenca(boolean) is
  'Gli annunci Accessori del chiamante (massimo 100), aperti o ritirati. Il venditore viene da auth.uid().';

-- Preventivo autorevole. Prezzo e quantita sono le sole scelte del chiamante:
-- dominio, classe, margine, parametri di pagamento e vendibilita le decide il
-- database. Spedizione e coperture sono nulle senza una tariffa reale.
create function public.annunci_accessori_preventivo(
  p_prezzo_unitario_cents integer,
  p_quantita integer,
  p_cantina_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
  v_v record;
  v_item private.cantina_accessori%rowtype;
  v_disponibili integer;
  v_preventivo jsonb;
begin
  if not private.annunci_accessori_consentita() then
    raise exception 'La preparazione degli annunci non e ancora attiva.'
      using errcode = '42501', hint = 'funzione_non_attiva';
  end if;
  if p_prezzo_unitario_cents is null or p_prezzo_unitario_cents not between 100 and 1000000
     or p_quantita is null or p_quantita not between 1 and 120 then
    raise exception 'Prezzo o quantita non validi.' using errcode = '22023',
      hint = 'preventivo_non_valido';
  end if;

  select * into v_v from private.annuncio_accessorio_venditore(v_uid);

  if p_cantina_id is not null then
    select * into v_item from private.cantina_accessori
    where id = p_cantina_id and owner_id = v_uid;
    if v_item.id is null then
      raise exception 'Accessorio non trovato.' using errcode = 'P0001', hint = 'non_trovato';
    end if;
    -- Disponibili per un annuncio nuovo o per modificare il proprio: la merce
    -- gia impegnata da ALTRI annunci non si riconta come libera.
    v_disponibili := greatest(v_item.quantita - private.annuncio_accessorio_impegnati(v_item.id), 0);
  end if;

  if v_v.ammesso then
    v_preventivo := private.preventivo_dominio(
      'accessori_enologici'::public.dominio_merceologico, v_v.classe,
      p_prezzo_unitario_cents, p_quantita, null);
  end if;

  return jsonb_build_object(
    'dominio', 'accessori_enologici',
    'classe', v_v.classe,
    'venditore_ammesso', v_v.ammesso,
    'motivo', v_v.motivo,
    'vendite_attive', false,
    'disponibili', v_disponibili,
    'preventivo', v_preventivo,
    'spedizione', private.annuncio_accessorio_spedizione()
  );
end;
$$;

comment on function public.annunci_accessori_preventivo(integer, integer, uuid) is
  'Preventivo economico autorevole di un annuncio Accessori (solo authenticated). '
  'Il chiamante sceglie prezzo e quantita; classe, margine e parametri sono del database. '
  'Il preventivo e nullo se il venditore non e ammesso. Nessuna tariffa di spedizione.';

-- Crea (id scelto dal client: il tentativo e ripetibile) o aggiorna una bozza.
create function public.annunci_accessori_salva(p_id uuid, p_dati jsonb)
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
  -- Elenco CHIUSO: classe, margine, commissione, totale, venditore e stato non
  -- sono campi di questa porta e un tentativo e rifiutato, non ignorato.
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

  -- Ordine dei lock: accessorio, poi annuncio.
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

  -- Riletto DOPO il lock dell'accessorio: un tentativo ripetuto con lo stesso
  -- id, concorrente a quello che lo ha creato, ne vede l'esito e lo aggiorna
  -- (idempotenza) invece di crearne un secondo.
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
  if v_esiste and v_old.stato <> 'bozza' then
    raise exception 'Solo una bozza si modifica.' using errcode = '22023', hint = 'annuncio_non_modificabile';
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

  -- Quantita offerta <= quantita non gia impegnata da altri annunci aperti
  -- (anche il trigger lo verifica, per ogni writer).
  select coalesce(sum(a.quantita), 0) into v_altri
  from private.annunci_accessori a
  where a.cantina_accessorio_id = v_cantina and a.stato in ('bozza', 'in_revisione') and a.id <> p_id;
  if v_quantita + v_altri > v_item.quantita then
    raise exception 'Quantita superiore a quella disponibile.'
      using errcode = '22023', hint = 'quantita_non_disponibile';
  end if;

  if not v_esiste then
    if exists (select 1 from private.annunci_accessori a
               where a.cantina_accessorio_id = v_cantina and a.stato in ('bozza', 'in_revisione')) then
      raise exception 'Questo accessorio ha gia un annuncio aperto.'
        using errcode = '22023', hint = 'annuncio_gia_aperto';
    end if;
    if (select count(*) from private.annunci_accessori a
        where a.seller_id = v_uid and a.stato in ('bozza', 'in_revisione')) >= 50 then
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
    update private.annunci_accessori
    set quantita = v_quantita, prezzo_unitario_cents = v_prezzo, condizione = v_condizione,
        descrizione = v_desc, dichiarazione_conforme = v_conforme, peso_g = v_peso,
        lunghezza_mm = v_lung, larghezza_mm = v_larg, altezza_mm = v_alt, fragile = v_fragile
    where id = p_id;
  end if;

  return private.annuncio_accessorio_json(p_id);
end;
$$;

comment on function public.annunci_accessori_salva(uuid, jsonb) is
  'Crea o aggiorna una BOZZA di annuncio Accessori del chiamante. Il venditore viene da '
  'auth.uid(); classe, margine, stato e totali non sono campi ammessi. Non pubblica nulla.';

-- Passaggi di stato del proprietario: bozza <-> in_revisione, e ritiro. Il
-- ritiro e il verso sicuro e resta possibile anche a preparazione spenta.
create function public.annunci_accessori_transizione(p_id uuid, p_a text)
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
  if p_a is null or p_a not in ('bozza', 'in_revisione', 'ritirato') then
    raise exception 'Stato non valido.' using errcode = '22023', hint = 'dati_non_validi';
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
  -- Stato Partner stabile per la durata del passaggio (stessa serializzazione
  -- di checkout e pubblicazione delle bottiglie).
  perform 1 from private.partners p where p.titolare_id = v_uid order by p.id for share;

  select * into v_a from private.annunci_accessori where id = p_id for update;
  if v_a.stato = p_a then
    return private.annuncio_accessorio_json(p_id);
  end if;

  update private.annunci_accessori
  set stato = p_a,
      ritirato_at = case when p_a = 'ritirato' then now() else null end
  where id = p_id;
  return private.annuncio_accessorio_json(p_id);
end;
$$;

comment on function public.annunci_accessori_transizione(uuid, text) is
  'Bozza <-> in_revisione e ritiro di un annuncio Accessori del chiamante. Non esiste uno stato acquistabile.';

-- La pubblicazione commerciale e CHIUSA: per ogni chiamante, sempre. Il blocco
-- che la apre sostituira questa funzione, non un interruttore.
create function public.annunci_accessori_pubblica(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.cantina_accessori_utente();
  raise exception 'La pubblicazione degli annunci Accessori non e ancora aperta.'
    using errcode = '42501', hint = 'pubblicazione_chiusa';
end;
$$;

comment on function public.annunci_accessori_pubblica(uuid) is
  'Rifiuta sempre (pubblicazione_chiusa). Nessun annuncio Accessori diventa pubblico o acquistabile in questo blocco.';

-- ---------------------------------------------------------------------------
-- Porte admin per l'interruttore
-- ---------------------------------------------------------------------------

create function public.annunci_accessori_admin_stato()
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
    'pubblicazione_attiva', false,
    'cantina_funzione_attiva', private.cantina_accessori_funzione_attiva(),
    'puo_rilasciare', private.accessori_puo_rilasciare()
  );
end;
$$;

-- Accendere richiede il ruolo di rilascio; spegnere un admin qualsiasi.
create function public.annunci_accessori_admin_imposta(p_attiva boolean, p_motivo text)
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
  set preparazione_attiva = p_attiva, aggiornato_da = v_admin where singleton;

  insert into private.accessori_registro (admin_id, azione, oggetto, motivo)
  values (v_admin, 'annunci_preparazione' || case when p_attiva then '_accendi' else '_spegni' end,
          'annunci_accessori', v_motivo);

  return jsonb_build_object(
    'preparazione_attiva', coalesce(
      (select i.preparazione_attiva from private.annunci_accessori_impostazioni i), false),
    'pubblicazione_attiva', false
  );
end;
$$;

comment on function public.annunci_accessori_admin_imposta(boolean, text) is
  'Accende (solo con il ruolo di rilascio accessori_release) o spegne (ogni admin) la preparazione degli annunci Accessori. Motivo obbligatorio, registrato. Non esiste un interruttore di pubblicazione.';

-- ---------------------------------------------------------------------------
-- Privilegi di esecuzione: solo authenticated, mai anon
-- ---------------------------------------------------------------------------

revoke all on function public.annunci_accessori_stato() from public, anon, authenticated, service_role;
revoke all on function public.annunci_accessori_elenca(boolean) from public, anon, authenticated, service_role;
revoke all on function public.annunci_accessori_preventivo(integer, integer, uuid) from public, anon, authenticated, service_role;
revoke all on function public.annunci_accessori_salva(uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.annunci_accessori_transizione(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.annunci_accessori_pubblica(uuid) from public, anon, authenticated, service_role;
revoke all on function public.annunci_accessori_admin_stato() from public, anon, authenticated, service_role;
revoke all on function public.annunci_accessori_admin_imposta(boolean, text) from public, anon, authenticated, service_role;

grant execute on function public.annunci_accessori_stato() to authenticated;
grant execute on function public.annunci_accessori_elenca(boolean) to authenticated;
grant execute on function public.annunci_accessori_preventivo(integer, integer, uuid) to authenticated;
grant execute on function public.annunci_accessori_salva(uuid, jsonb) to authenticated;
grant execute on function public.annunci_accessori_transizione(uuid, text) to authenticated;
grant execute on function public.annunci_accessori_pubblica(uuid) to authenticated;
grant execute on function public.annunci_accessori_admin_stato() to authenticated;
grant execute on function public.annunci_accessori_admin_imposta(boolean, text) to authenticated;

notify pgrst, 'reload schema';
