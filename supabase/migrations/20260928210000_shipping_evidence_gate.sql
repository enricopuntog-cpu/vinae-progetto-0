-- ===========================================================================
-- WP3 — Prova di spedizione e cancello di preparazione
-- ===========================================================================
--
-- IL DIFETTO CHE QUESTA MIGRAZIONE CHIUDE.
-- `public.ordine_segna_spedito`, nella versione effettiva della 7c
-- (20260804160000_phase_7c_delivery_packaging.sql), accetta un ordine in
-- `pagato` oltre che in `in_preparazione`. Un venditore poteva quindi portare
-- un ordine pagato a `spedito` senza aver mai aperto la preparazione, senza
-- checklist e senza una sola fotografia. Il cancello esisteva soltanto
-- nell'interfaccia, che non e un confine di fiducia.
--
-- Nello stesso passaggio `orders.imballaggio_foto` era un `text[]` libero
-- scritto da `ordine_prepara_spedizione`: qualunque stringa passata come
-- `p_foto` diventava una «prova». Nessun tipo, nessun autore, nessun istante,
-- nessuno storico delle sostituzioni.
--
-- COSA DIVENTA AUTORITATIVO.
--   * `private.order_shipping_evidence` — l'archivio strutturato e versionato
--     delle prove. Una sola prova CORRENTE per (ordine, tipo); la precedente
--     non si cancella, diventa `superseded_at`.
--   * `orders.imballaggio_foto` — resta, ma come PROIEZIONE di compatibilita
--     dei soli percorsi correnti. Non e piu una fonte di verita e non accetta
--     piu percorsi dall'esterno.
--   * `orders.preparazione_confermata_at` — il venditore ha soddisfatto il
--     contratto di preparazione. NON significa etichetta generata, collo
--     consegnato al corriere o tracking avviato.
--   * `private.ordine_spedizione_pronta(uuid)` — il cancello riusabile. E la
--     porta che il futuro adattatore logistico (`createShipment` /
--     `generateLabel`) dovra interrogare PRIMA di creare una spedizione: la
--     spedizione non si crea per un ordine che questa funzione dichiara non
--     pronto.
--
-- COSA QUESTA MIGRAZIONE NON FA, DELIBERATAMENTE.
-- Nessun fornitore logistico, nessun QR, nessuna etichetta, nessun PUDO reale,
-- nessuna API di tracking, nessun prezzo logistico, nessuna assicurazione.
-- Nessuna riga economica cambia: pagamenti, payout, saldo, commissione,
-- `totale_cents`, `addebito_totale_cents`, `imballaggio_cents` e
-- `packaging_options` non sono toccati. `listings.imballaggio_codice` non e
-- toccato.
--
-- NESSUN BACKFILL. Gli ordini gia `spedito`, `consegnato`, `completato`,
-- `contestato`, `rimborsato` o `annullato` restano validi senza
-- `preparazione_confermata_at` e continuano a leggersi. Il cancello vale per
-- chi deve ancora ENTRARE in `spedito`: un ordine oggi `pagato` non salta piu
-- direttamente a spedito, ed e voluto.

create schema if not exists private;

-- ===========================================================================
-- PARTE A — la colonna di conferma sull'ordine
-- ===========================================================================

alter table public.orders
  add column preparazione_confermata_at timestamptz;

comment on column public.orders.preparazione_confermata_at is
  'Istante in cui il venditore ha soddisfatto il contratto di preparazione '
  'corrente: checklist canonica completa piu prova CORRENTE del collo finale. '
  'Non significa etichetta generata, collo affidato al corriere o tracking '
  'avviato. Si azzera se la preparazione torna incompleta (prova sostituita, '
  'checklist salvata parziale) finche l''ordine non e spedito. Scritta solo da '
  'public.ordine_prepara_spedizione e azzerata da '
  'public.ordine_spedizione_prova_registra: non esiste grant di UPDATE ai '
  'ruoli client.';

-- Il grant di lettura di public.orders e a elenco chiuso: una colonna nuova
-- resta privata finche non viene aggiunta qui.
grant select (preparazione_confermata_at) on public.orders to authenticated;

-- ===========================================================================
-- PARTE B — l'archivio strutturato delle prove
-- ===========================================================================
--
-- Vive in `private` perche PostgREST non raggiunge quello schema: nessun
-- client legge o scrive questa tabella, nemmeno il venditore proprietario. Si
-- entra solo dalle porte di questa migrazione. Lo storico completo (comprese
-- le prove sostituite) resta qui per la fase contestazioni, che dovra poterlo
-- consultare; la lettura del venditore vede solo le correnti.

create table private.order_shipping_evidence (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  uploader_id uuid not null,
  evidence_kind text not null
    check (evidence_kind in ('collo_finale', 'interno_pre_chiusura')),
  storage_path text not null unique,
  created_at timestamptz not null default now(),
  superseded_at timestamptz
);

comment on table private.order_shipping_evidence is
  'Prove fotografiche della preparazione, versionate. CORRENTE = '
  'superseded_at is null. La sostituzione non cancella: marca la precedente e '
  'inserisce la nuova, cosi lo storico resta completo e verificabile. '
  'Autorita delle prove di spedizione; orders.imballaggio_foto ne e solo la '
  'proiezione corrente.';
comment on column private.order_shipping_evidence.uploader_id is
  'Sempre auth.uid() del venditore al momento della registrazione: nessuna '
  'porta accetta questo valore come parametro.';
comment on column private.order_shipping_evidence.evidence_kind is
  '`collo_finale` (collo chiuso, OBBLIGATORIA per spedire) oppure '
  '`interno_pre_chiusura` (interno prima della chiusura, facoltativa).';
comment on column private.order_shipping_evidence.storage_path is
  'Percorso nel bucket privato `dispute-evidence`, formato '
  '<order_id>/<uploader_id>/<uuid>.webp. Unico: lo stesso oggetto non puo '
  'essere depositato due volte, nemmeno su ordini diversi.';

-- Una sola prova corrente per tipo. L'indice parziale e il vincolo vero: non
-- dipende dal fatto che la RPC ricordi di marcare la precedente.
create unique index order_shipping_evidence_corrente_uniq
  on private.order_shipping_evidence (order_id, evidence_kind)
  where superseded_at is null;

create index order_shipping_evidence_order_idx
  on private.order_shipping_evidence (order_id);

alter table private.order_shipping_evidence enable row level security;

-- Nessuna policy: RLS attiva senza policy nega tutto ai ruoli non privilegiati.
-- I revoke sotto chiudono anche la strada del privilegio di tabella.
revoke all on private.order_shipping_evidence from public, anon, authenticated;

-- ===========================================================================
-- PARTE C — Storage: stesso bucket privato delle contestazioni
-- ===========================================================================
--
-- PERCHE NON UN SECONDO BUCKET. Prova di preparazione e prova di contestazione
-- finiscono nello stesso fascicolo dello stesso ordine: due sistemi di Storage
-- con due formati di percorso, due politiche e due TTL renderebbero
-- impossibile mostrarle insieme senza riconciliarle a mano. Il bucket
-- `dispute-evidence` conserva nome storico, resta privato, resta a 5 MiB e
-- solo `image/webp`, e il formato del percorso non cambia.
--
-- La policy di INSERT si estende del minimo indispensabile: un ramo in piu per
-- il venditore che sta preparando. I due rami delle contestazioni sono
-- riportati identici.

drop policy if exists dispute_evidence_participant_insert on storage.objects;
create policy dispute_evidence_participant_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'dispute-evidence'
  and split_part(name, '/', 2) = (select auth.uid())::text
  and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.webp$'
  and exists (
    select 1 from public.orders o
    where o.id::text = split_part(name, '/', 1)
      and (
        (
          (select auth.uid()) = o.buyer_id
          and o.consegnato_at is not null
          and now() <= o.consegnato_at + interval '48 hours'
          and not exists (
            select 1 from public.disputes d where d.order_id = o.id
          )
        )
        or (
          (select auth.uid()) = o.seller_id
          and exists (
            select 1 from public.disputes d
            where d.order_id = o.id
              and d.stato in ('aperta', 'in_valutazione')
              and d.venditore_risposta_at is null
              and now() <= d.venditore_scadenza_at
          )
        )
        or (
          -- WP3: prova di preparazione. Solo il venditore di QUESTO ordine, e
          -- solo finche l'ordine non e spedito. Il compratore, un estraneo,
          -- `anon` e il venditore di un altro ordine restano fuori: il primo
          -- per il ramo, gli altri per il confronto su `split_part(name,'/',2)`
          -- e per la RLS di public.orders.
          (select auth.uid()) = o.seller_id
          and o.stato in ('pagato', 'in_preparazione')
        )
      )
  )
);

-- ---------------------------------------------------------------------------
-- Immutabilita: una prova depositata non si cancella dal client
-- ---------------------------------------------------------------------------
-- Estende private.prova_contestazione_depositata (20260923160000) alle prove
-- di spedizione, CORRENTI O SOSTITUITE: una prova sostituita resta citata
-- dallo storico, quindi il suo oggetto deve continuare a esistere. Il
-- caricamento non ancora registrato resta cancellabile dal suo autore, che e
-- l'unico modo di ripulire un tentativo andato storto.

create or replace function private.prova_ordine_depositata(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.disputes d
    where p_name = any (d.foto) or p_name = any (d.venditore_foto)
  ) or exists (
    select 1
    from private.order_shipping_evidence e
    where e.storage_path = p_name
  );
$$;

comment on function private.prova_ordine_depositata(text) is
  'Vero se il percorso e citato da una contestazione (prova del compratore o '
  'del venditore) oppure registrato come prova di spedizione, corrente o '
  'sostituita. Serve alla policy di DELETE di Storage, che gira a privilegi '
  'del chiamante: per questo — unica fra gli helper privati di questa '
  'migrazione — ha EXECUTE per `authenticated`. Restituisce solo un booleano.';

revoke all on function private.prova_ordine_depositata(text) from public, anon;
grant execute on function private.prova_ordine_depositata(text) to authenticated;

drop policy if exists dispute_evidence_owner_delete on storage.objects;
create policy dispute_evidence_owner_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'dispute-evidence'
  and split_part(name, '/', 2) = (select auth.uid())::text
  and not private.prova_ordine_depositata(name)
);

comment on function private.prova_contestazione_depositata(text) is
  'Vero se il percorso e citato da una contestazione. La policy di DELETE non '
  'la usa piu — le serve private.prova_ordine_depositata, piu larga — ma la '
  'policy di SELECT si: e esattamente il confine del fascicolo che si apre al '
  'compratore quando una prova viene depositata in contestazione.';

-- ---------------------------------------------------------------------------
-- Riservatezza: il compratore non vede la preparazione del venditore
-- ---------------------------------------------------------------------------
-- DIFETTO CHIUSO QUI. La policy di SELECT distribuita (20260923160000) dice
-- «admin, oppure compratore o venditore dell'ordine nominato dal primo
-- segmento del percorso». Finche nel bucket c'erano solo prove di
-- contestazione era la regola giusta: una prova di contestazione nasce per
-- essere letta dalla controparte. Riusare lo stesso bucket per le prove di
-- preparazione, senza toccare questa policy, avrebbe dato al compratore le
-- fotografie dell'imballaggio nel momento stesso del caricamento — prima di
-- qualunque contestazione, e per ogni ordine.
--
-- Non sarebbe stato nemmeno un accesso difficile: `orders.imballaggio_foto`
-- e leggibile dalle parti dell'ordine e contiene i percorsi esatti. Il
-- percorso non e un segreto e non va usato come controllo: e questa policy a
-- dover negare.
--
-- La regola nuova, per ramo:
--   admin      — invariato, vede tutto il bucket;
--   venditore  — invariato, vede tutto il fascicolo del proprio ordine;
--   compratore — vede i propri caricamenti, e in piu solo cio che e stato
--                depositato in contestazione (`disputes.foto` /
--                `venditore_foto`). E l'eccezione dichiarata: una prova di
--                spedizione depositata come prova di parte smette di essere
--                riservata e segue le regole del fascicolo di contestazione.
--   estraneo   — nessun ramo lo nomina;
--   anon       — la policy e `to authenticated`.
--
-- Il ramo del compratore copre anche l'oggetto caricato ma non ancora
-- registrato: non essendo depositato in nessuna contestazione, resta invisibile
-- anche nella finestra fra `upload` e `ordine_spedizione_prova_registra`.
--
-- Il ramo admin resta fuori dalla sottoquery sugli ordini, come lo aveva messo
-- la 20260923160000: dentro, un admin che non sia parte dell'ordine non
-- passerebbe la RLS di `public.orders`.

drop policy if exists dispute_evidence_participants_select on storage.objects;
create policy dispute_evidence_participants_select
on storage.objects for select to authenticated
using (
  bucket_id = 'dispute-evidence'
  and (
    public.has_role((select auth.uid()), 'admin')
    or exists (
      select 1 from public.orders o
      where o.id::text = split_part(name, '/', 1)
        and (
          (select auth.uid()) = o.seller_id
          or (
            (select auth.uid()) = o.buyer_id
            and (
              split_part(name, '/', 2) = (select auth.uid())::text
              or private.prova_contestazione_depositata(name)
            )
          )
        )
    )
  )
);

-- ===========================================================================
-- PARTE D — la checklist canonica
-- ===========================================================================
--
-- Sei dichiarazioni di sicurezza dell'imballaggio, non quattro voci
-- fotografiche: le fotografie ora sono prove registrate, non caselle. La
-- sesta vale anche quando una confezione originale non esiste — e una
-- dichiarazione «non applicabile ma rispettata». Le istruzioni specifiche per
-- cofanetto/cassa sono di un pacchetto successivo: qui non si dipende ancora
-- da `confezione_originale_tipo`.

create or replace function private.imballaggio_checklist_voci()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array[
    'bottiglia_immobilizzata',
    'nessun_movimento',
    'protezione_tutti_lati',
    'cartone_esterno_integro',
    'chiusura_adeguata',
    'confezione_originale_protetta'
  ]::text[];
$$;

comment on function private.imballaggio_checklist_voci() is
  'Gli ID canonici della checklist di imballaggio. Unica definizione lato '
  'database: il frontend ne rende le etichette, non ne decide l''elenco.';

create or replace function private.imballaggio_checklist_completa(p_checklist jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_voci text[] := private.imballaggio_checklist_voci();
  v_totale integer;
  v_distinti integer;
  v_spuntate integer;
begin
  if p_checklist is null or jsonb_typeof(p_checklist) <> 'array' then
    return false;
  end if;

  select
    count(*),
    count(distinct e->>'id'),
    count(*) filter (where e->>'id' = any (v_voci) and e->'done' = 'true'::jsonb)
  into v_totale, v_distinti, v_spuntate
  from jsonb_array_elements(p_checklist) e;

  -- Esattamente le sei voci canoniche, ciascuna una volta, tutte a true. Un ID
  -- inventato non soddisfa il cancello nemmeno se si aggiunge alle sei: la
  -- checklist completa e quella, non «quella piu qualcosa».
  return v_totale = array_length(v_voci, 1)
     and v_distinti = array_length(v_voci, 1)
     and v_spuntate = array_length(v_voci, 1);
end;
$$;

comment on function private.imballaggio_checklist_completa(jsonb) is
  'Vero solo se la checklist contiene esattamente i sei ID canonici, ciascuno '
  'una volta, tutti con done = true (booleano JSON, non la stringa "true"). '
  'Una checklist parziale resta salvabile: non e completa, e quindi non '
  'conferma la preparazione.';

-- ===========================================================================
-- PARTE E — proiezione e stato della preparazione
-- ===========================================================================

create or replace function private.ordine_prove_correnti(p_order_id uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    array_agg(e.storage_path order by e.evidence_kind),
    '{}'::text[]
  )
  from private.order_shipping_evidence e
  where e.order_id = p_order_id
    and e.superseded_at is null;
$$;

comment on function private.ordine_prove_correnti(uuid) is
  'I percorsi delle sole prove CORRENTI, in ordine di tipo. E la sorgente di '
  'orders.imballaggio_foto: quella colonna non si scrive piu da un parametro.';

create or replace function private.ordine_prova_corrente_esiste(
  p_order_id uuid, p_evidence_kind text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.order_shipping_evidence e
    join public.orders o on o.id = e.order_id
    where e.order_id = p_order_id
      and e.evidence_kind = p_evidence_kind
      and e.superseded_at is null
      -- La prova deve appartenere al venditore corrente dell'ordine: una prova
      -- caricata da chiunque altro non tiene aperto il cancello.
      and e.uploader_id = o.seller_id
  );
$$;

-- ---------------------------------------------------------------------------
-- Il cancello riusabile
-- ---------------------------------------------------------------------------
-- Fail-closed e senza accesso client: e la funzione che
-- public.ordine_segna_spedito interroga oggi e che il futuro adattatore
-- logistico dovra interrogare prima di `createShipment`/`generateLabel`.

create or replace function private.ordine_spedizione_pronta(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.orders o
    where o.id = p_order_id
      and o.stato = 'in_preparazione'
      and o.preparazione_confermata_at is not null
      and private.imballaggio_checklist_completa(o.imballaggio_checklist)
      and private.ordine_prova_corrente_esiste(o.id, 'collo_finale')
      and exists (
        select 1 from public.payments p
        where p.order_id = o.id and p.stato = 'paid'
      )
  );
$$;

comment on function private.ordine_spedizione_pronta(uuid) is
  'Cancello di prontezza alla spedizione: ordine in preparazione, preparazione '
  'confermata, checklist canonica completa, prova CORRENTE del collo finale '
  'caricata dal venditore dell''ordine, pagamento incassato. Falso in ogni '
  'altro caso, compreso l''ordine inesistente. Nessun ruolo client la esegue: '
  'la si attraversa dalle porte di dominio. Il futuro adattatore logistico '
  'deve chiamarla PRIMA di creare una spedizione reale.';

revoke all on function private.imballaggio_checklist_voci(),
  private.imballaggio_checklist_completa(jsonb),
  private.ordine_prove_correnti(uuid),
  private.ordine_prova_corrente_esiste(uuid, text),
  private.ordine_spedizione_pronta(uuid)
  from public, anon, authenticated;

-- ===========================================================================
-- PARTE F — registrazione e sostituzione di una prova
-- ===========================================================================

create or replace function public.ordine_spedizione_prova_registra(
  p_order_id uuid,
  p_evidence_kind text,
  p_storage_path text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_sostituita boolean := false;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  perform private.rate_limit_consume('order:evidence', 'user:' || v_uid::text, 30, 60);

  if p_evidence_kind is null
    or p_evidence_kind not in ('collo_finale', 'interno_pre_chiusura') then
    raise exception 'Tipo di prova non valido.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.seller_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;

  -- Dopo `spedito` le prove non si aggiungono, non si sostituiscono e non si
  -- cancellano: il fascicolo e chiuso.
  if v_order.stato not in ('pagato', 'in_preparazione') then
    raise exception 'Questo ordine non accetta piu prove di preparazione.'
      using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.payments p
    where p.order_id = v_order.id and p.stato = 'paid'
  ) then
    raise exception 'Il pagamento di questo ordine non risulta incassato.'
      using errcode = 'P0001';
  end if;

  -- Il percorso deve essere di QUESTO ordine e di QUESTO caricatore: la stessa
  -- forma usata dalle prove di contestazione.
  if coalesce(p_storage_path, '') !~ (
    '^' || v_order.id::text || '/' || v_uid::text
    || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.webp$'
  ) then
    raise exception 'Percorso della fotografia non valido.' using errcode = '22023';
  end if;

  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'dispute-evidence' and o.name = p_storage_path
  ) then
    raise exception 'Fotografia non trovata.' using errcode = 'P0001';
  end if;

  -- Sostituzione: la precedente non si cancella, si marca.
  update private.order_shipping_evidence
  set superseded_at = now()
  where order_id = v_order.id
    and evidence_kind = p_evidence_kind
    and superseded_at is null;
  v_sostituita := found;

  insert into private.order_shipping_evidence (
    order_id, uploader_id, evidence_kind, storage_path
  ) values (
    v_order.id, v_uid, p_evidence_kind, p_storage_path
  );

  -- La proiezione di compatibilita segue le sole correnti. La conferma decade:
  -- cambiare una prova dopo aver confermato significa riconfermare.
  update public.orders set
    imballaggio_foto = private.ordine_prove_correnti(v_order.id),
    preparazione_confermata_at = null
  where id = v_order.id
  returning * into v_order;

  -- Audit su public.order_events, senza URL firmati, senza token e senza il
  -- percorso: il tipo e il fatto della sostituzione bastano.
  insert into public.order_events (order_id, tipo, payload)
  values (
    v_order.id,
    'shipping_evidence_registered',
    jsonb_build_object('evidence_kind', p_evidence_kind, 'replaced', v_sostituita)
  );

  return jsonb_build_object(
    'order_id', v_order.id,
    'evidence_kind', p_evidence_kind,
    'replaced', v_sostituita,
    'preparazione_confermata_at', null
  );
end;
$$;

comment on function public.ordine_spedizione_prova_registra(uuid, text, text) is
  'Registra o sostituisce la prova fotografica di un tipo. Solo il venditore '
  'dell''ordine, solo su ordine pagato o in preparazione, solo su un oggetto '
  'davvero presente nel bucket privato e con il percorso di quell''ordine e di '
  'quel caricatore. La prova precedente dello stesso tipo non si cancella: '
  'diventa sostituita. Azzera preparazione_confermata_at.';

-- ===========================================================================
-- PARTE G — lettura delle prove correnti
-- ===========================================================================

create or replace function public.ordine_spedizione_prove(p_order_id uuid)
returns table (
  evidence_kind text,
  storage_path text,
  created_at timestamptz
)
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

  if not exists (
    select 1 from public.orders o
    where o.id = p_order_id and o.seller_id = v_uid
  ) and not public.has_role(v_uid, 'admin') then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;

  return query
    select e.evidence_kind, e.storage_path, e.created_at
    from private.order_shipping_evidence e
    where e.order_id = p_order_id
      and e.superseded_at is null
    order by e.evidence_kind;
end;
$$;

comment on function public.ordine_spedizione_prove(uuid) is
  'Le sole prove CORRENTI di un ordine, a elenco di colonne chiuso, per il '
  'venditore dell''ordine e per l''amministrazione. Non per il compratore e '
  'non per un estraneo. Lo storico delle prove sostituite resta nello schema '
  'privato: lo leggera il dominio contestazioni, non questa porta.';

-- ===========================================================================
-- PARTE H — preparazione: la checklist non deposita piu fotografie
-- ===========================================================================
--
-- Firma invariata: i contratti gia distribuiti (servizio frontend, griglie)
-- continuano a chiamarla com'e. Cambia la semantica di sicurezza di `p_foto`,
-- che non e piu una sorgente di percorsi. Le prove correnti si DERIVANO
-- dall'archivio privato; se `p_foto` arriva non vuoto, ogni suo elemento deve
-- essere un percorso gia registrato come corrente, altrimenti la chiamata
-- fallisce. Mandare `{"qualunque-stringa"}` non crea piu una prova.

create or replace function public.ordine_prepara_spedizione(
  p_order_id uuid,
  p_checklist jsonb default '[]'::jsonb,
  p_foto text[] default '{}'
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_correnti text[];
  v_estranee text[];
  v_completa boolean;
  v_collo boolean;
  v_conferma timestamptz;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  perform private.rate_limit_consume('order:prepare', 'user:' || v_uid::text, 30, 60);

  if p_checklist is null or jsonb_typeof(p_checklist) <> 'array'
     or jsonb_array_length(p_checklist) > 12 then
    raise exception 'Checklist di imballaggio non valida.' using errcode = '22023';
  end if;
  if cardinality(coalesce(p_foto, '{}')) > 8 then
    raise exception 'Troppe foto di imballaggio.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.seller_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;
  if v_order.stato not in ('pagato', 'in_preparazione') then
    raise exception 'Questo ordine non è in preparazione.' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.payments p
    where p.order_id = v_order.id and p.stato = 'paid'
  ) then
    raise exception 'Il pagamento di questo ordine non risulta incassato.'
      using errcode = 'P0001';
  end if;

  v_correnti := private.ordine_prove_correnti(v_order.id);

  -- `p_foto` non deposita: al massimo conferma cio che e gia registrato.
  select coalesce(array_agg(f), '{}'::text[])
  into v_estranee
  from unnest(coalesce(p_foto, '{}')) f
  where f is null or not (f = any (v_correnti));
  if cardinality(v_estranee) > 0 then
    raise exception
      'Le prove di spedizione si registrano con ordine_spedizione_prova_registra.'
      using errcode = '22023';
  end if;

  v_completa := private.imballaggio_checklist_completa(p_checklist);
  v_collo := private.ordine_prova_corrente_esiste(v_order.id, 'collo_finale');

  -- Conferma idempotente: se la preparazione e gia conforme l'istante non si
  -- sposta; se un requisito manca la conferma decade e va rifatta.
  if v_completa and v_collo then
    v_conferma := coalesce(v_order.preparazione_confermata_at, now());
  else
    v_conferma := null;
  end if;

  update public.orders set
    stato = 'in_preparazione',
    preparazione_avviata_at = coalesce(v_order.preparazione_avviata_at, now()),
    imballaggio_checklist = p_checklist,
    imballaggio_foto = v_correnti,
    preparazione_confermata_at = v_conferma
  where id = v_order.id
  returning * into v_order;

  if not exists (
    select 1 from public.tracking_events t
    where t.order_id = v_order.id
      and t.tipo = 'info'
      and t.titolo = 'In preparazione dal venditore'
  ) then
    perform private.tracking_registra(
      v_order.id, 'info', 'In preparazione dal venditore'
    );
  end if;

  insert into public.order_events (order_id, tipo, payload)
  values (
    v_order.id,
    'preparazione_avviata',
    jsonb_build_object('voci_checklist', jsonb_array_length(p_checklist))
  );

  if v_conferma is not null then
    insert into public.order_events (order_id, tipo, payload)
    values (
      v_order.id,
      'shipping_preparation_confirmed',
      jsonb_build_object(
        'voci_checklist', jsonb_array_length(p_checklist),
        'has_final_evidence', true
      )
    );
  end if;

  return v_order;
end;
$$;

comment on function public.ordine_prepara_spedizione(uuid, jsonb, text[]) is
  'Apre o aggiorna la preparazione. La checklist parziale resta salvabile; la '
  'preparazione si conferma solo con i sei ID canonici tutti spuntati e la '
  'prova CORRENTE del collo finale. `p_foto` non deposita percorsi: puo solo '
  'ripetere prove gia registrate, e orders.imballaggio_foto viene comunque '
  'riscritta dall''archivio privato.';

-- ===========================================================================
-- PARTE I — segna spedito: il bypass si chiude qui
-- ===========================================================================
--
-- Il corpo e quello della 7c, con una sola differenza sostanziale: `pagato`
-- non e piu uno stato di partenza ammesso, e `in_preparazione` passa solo
-- attraverso il cancello di prontezza. Le validazioni di corriere e tracking
-- restano prima, dove erano: un tracking malformato continua a fallire con
-- 22023 a prescindere dallo stato.

create or replace function public.ordine_segna_spedito(
  p_order_id uuid,
  p_corriere text,
  p_tracking_number text
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  perform private.rate_limit_consume('order:ship', 'user:' || v_uid::text, 30, 60);

  if length(trim(coalesce(p_corriere, ''))) not between 2 and 60 then
    raise exception 'Corriere non valido.' using errcode = '22023';
  end if;
  if coalesce(p_tracking_number, '') !~ '^[A-Za-z0-9._-]{4,64}$' then
    raise exception 'Numero di tracking non valido.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.seller_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;

  if v_order.stato <> 'in_preparazione' then
    raise exception 'Apri la preparazione prima di segnare l''ordine come spedito.'
      using errcode = 'P0001';
  end if;

  if not private.ordine_spedizione_pronta(v_order.id) then
    raise exception
      'Preparazione non confermata: servono la checklist completa e la foto del collo finale.'
      using errcode = 'P0001';
  end if;

  update public.orders set
    stato = 'spedito',
    spedito_at = now(),
    corriere = trim(p_corriere),
    tracking_number = p_tracking_number,
    preparazione_avviata_at = coalesce(v_order.preparazione_avviata_at, now())
  where id = v_order.id
  returning * into v_order;

  perform private.tracking_registra(
    v_order.id, 'spedizione', 'Spedito',
    v_order.corriere || ' — ' || v_order.tracking_number
  );

  insert into public.order_events (order_id, tipo, payload)
  values (
    v_order.id,
    'spedizione_dichiarata',
    jsonb_build_object('corriere', v_order.corriere)
  );

  return v_order;
end;
$$;

comment on function public.ordine_segna_spedito(uuid, text, text) is
  'Dichiarazione manuale di spedizione. Non accetta piu un ordine `pagato`: '
  'solo `in_preparazione`, e solo se private.ordine_spedizione_pronta e vera. '
  'Non genera etichette, QR o tracking reali e non chiama alcun fornitore.';

-- ===========================================================================
-- PARTE L — privilegi
-- ===========================================================================
--
-- `create or replace` non tocca i privilegi: ordine_prepara_spedizione e
-- ordine_segna_spedito conservano quelli della 7c. Qui si chiudono solo le due
-- porte nuove.

revoke execute on function public.ordine_spedizione_prova_registra(uuid, text, text),
  public.ordine_spedizione_prove(uuid)
  from public, anon;
grant execute on function public.ordine_spedizione_prova_registra(uuid, text, text),
  public.ordine_spedizione_prove(uuid)
  to authenticated;

notify pgrst, 'reload schema';
