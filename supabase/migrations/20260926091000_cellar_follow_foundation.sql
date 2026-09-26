-- Segui una Cantina — fondazione DB, senza interfaccia.
--
-- CHE COSA SI SEGUE. Si segue **la Cantina di una persona**, non la persona. Non
-- esiste qui un grafo sociale generico: nessun follow-utente, nessun
-- follow-produttore, nessun follow-Club, nessuna coppia «follower/following» da
-- riusare altrove. Il nome delle porte lo dichiara, cosi una futura
-- funzionalita diversa deve chiedere una decisione invece di ereditare questa.
--
-- IL GRAFO E PRIVATO, E DI CHI SEGUE. «Chi seguo» e un dato del follower. Il
-- proprietario della Cantina non riceve l'elenco di chi lo segue, non esiste un
-- contatore pubblico di follower, non esiste una rubrica globale delle Cantine
-- seguite e nessuna RPC accetta un `follower_id`: il follower e sempre
-- `auth.uid()`. Le sole tre forme ammesse sono (a) lo stato di follow di UN
-- proprietario gia noto, (b) la scrittura di follow su UN proprietario gia noto,
-- (c) l'elenco delle Cantine seguite DAL CHIAMANTE.
--
-- LE NOTIFICHE RIUSANO LA FASE 8. Non nasce una seconda tabella di notifiche,
-- non nasce un secondo canale Realtime e non nasce un secondo servizio. Le righe
-- entrano in `public.notifications` e attraversano il trigger esistente
-- `notifications_after_change` verso il topic privato
-- `user:<recipientId>:notifications`, che questa migrazione non tocca.
--
-- NESSUN BACKFILL, IN NESSUNA DIREZIONE. Applicare questa migrazione non crea
-- notifiche per le bottiglie gia pubbliche: la tabella dei follow nasce vuota e
-- il trigger reagisce solo a eventi futuri. Iniziare a seguire oggi non produce
-- notifiche retroattive. Smettere di seguire non cancella lo storico gia
-- ricevuto: ferma solo le notifiche nuove.

create schema if not exists private;

-- ---------------------------------------------------------------------------
-- [1] Il grafo di follow, fuori dalla portata di PostgREST
-- ---------------------------------------------------------------------------

create table private.cellar_follows (
  follower_id uuid not null
    references public.profiles (id) on delete cascade,
  owner_id uuid not null
    references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint cellar_follows_pkey primary key (follower_id, owner_id),
  -- Seguire la propria Cantina non e un gesto con un significato: sarebbe solo
  -- un modo di notificare se stessi. Il CHECK lo chiude anche per uno scrittore
  -- privilegiato, non solo per la RPC.
  constraint cellar_follows_non_se_stessi check (follower_id <> owner_id)
);

comment on table private.cellar_follows is
  'Chi segue la Cantina pubblica di chi. E un dato privato del follower: nessun '
  'contatore pubblico, nessun elenco per il proprietario, nessuna rubrica. Vive '
  'in `private` perche PostgREST non raggiunge quello schema; si legge e si '
  'scrive soltanto con le RPC dedicate e con il trigger di fanout.';
comment on column private.cellar_follows.follower_id is
  'Sempre auth.uid() del chiamante. Nessuna porta accetta questo valore come parametro.';
comment on column private.cellar_follows.owner_id is
  'Proprietario della Cantina seguita. Dev''essere pubblico nel momento del follow; '
  'se smette di esserlo la relazione resta, ma non compare piu nell''elenco e non '
  'genera notifiche fino a quando non torna raggiungibile.';

-- Il fanout parte dal proprietario e legge i suoi follower: e la sola lettura
-- ad alto volume di questa tabella, quindi ha il suo indice. La chiave primaria
-- copre gia il prefisso `follower_id`.
create index cellar_follows_owner_fanout
  on private.cellar_follows (owner_id, follower_id);

-- L'elenco «Le mie Cantine» ordina per (created_at desc, owner_id desc): il
-- cursore e servito da questo indice e non da un sort dell'intera tabella.
create index cellar_follows_follower_cursor
  on private.cellar_follows (follower_id, created_at desc, owner_id desc);

alter table private.cellar_follows enable row level security;

-- Nessuna policy, per la stessa ragione di `private.cellar_public_settings`:
-- anche un GRANT aggiunto per errore resterebbe chiuso. Le funzioni
-- SECURITY DEFINER appartengono al proprietario della tabella e sono le sole
-- porte previste.
revoke all on private.cellar_follows from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [2] Le tre porte del follower — un proprietario noto per volta
-- ---------------------------------------------------------------------------
--
-- Owner sconosciuto, owner non pubblico e owner rimosso danno **la stessa**
-- risposta, cosi la porta non diventa un oracolo sugli stati di moderazione:
-- `false` in lettura, `42501` con lo stesso messaggio in scrittura.

create function public.cantina_seguita_stato(p_owner_id uuid)
returns boolean
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

  -- Il join con `private.profili_pubblici` allinea questa risposta a
  -- `cantine_seguite_page`: se il proprietario non e raggiungibile, l'elenco non
  -- lo mostra e lo stato dice `false`. Quella vista porta con se anche le due
  -- direzioni della decisione 7.6b, quindi un chiamante rimosso legge `false`.
  return exists (
    select 1
    from private.cellar_follows f
      join private.profili_pubblici pp on pp.user_id = f.owner_id
    where f.follower_id = v_uid
      and f.owner_id = p_owner_id
  );
end;
$$;

comment on function public.cantina_seguita_stato(uuid) is
  'Seguo io la Cantina di questo profilo gia noto? Risponde solo per auth.uid(): '
  'non esiste un parametro follower. Un proprietario sconosciuto, non pubblico o '
  'rimosso risponde false, indistinguibile da «non lo seguo».';

revoke all on function public.cantina_seguita_stato(uuid) from public, anon;
grant execute on function public.cantina_seguita_stato(uuid) to authenticated;

create function public.cantina_segui(p_owner_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Devi accedere per seguire una Cantina.' using errcode = '42501';
  end if;
  if p_owner_id is null then
    raise exception 'Cantina non indicata.' using errcode = '22004';
  end if;
  if p_owner_id = v_uid then
    raise exception 'Non puoi seguire la tua Cantina.' using errcode = 'P0001';
  end if;
  if not exists (
    select 1
    from public.profiles p
    where p.id = v_uid
      and p.stato_utente <> 'rimosso'::public.utente_stato
  ) then
    -- Stessa risposta per profilo assente e rimosso: nessun dettaglio interno.
    raise exception 'Profilo non disponibile.' using errcode = '42501';
  end if;
  -- Chi si puo seguire lo decide la sorgente canonica del profilo pubblico, non
  -- un elenco di predicati ricopiato qui. Una Cantina pubblica con **zero**
  -- bottiglie esposte resta seguibile: e proprio il caso in cui il follower
  -- vuole la notifica della prima pubblicazione.
  if not exists (
    select 1 from private.profili_pubblici pp where pp.user_id = p_owner_id
  ) then
    raise exception 'Cantina non disponibile.' using errcode = '42501';
  end if;

  insert into private.cellar_follows (follower_id, owner_id)
  values (v_uid, p_owner_id)
  on conflict (follower_id, owner_id) do nothing;

  return true;
end;
$$;

comment on function public.cantina_segui(uuid) is
  'Inizia a seguire la Cantina di un profilo pubblico gia noto. Il follower e '
  'auth.uid() e non un parametro. Idempotente: seguire due volte non crea due '
  'righe e non muove created_at. Non produce notifiche retroattive.';

revoke all on function public.cantina_segui(uuid) from public, anon;
grant execute on function public.cantina_segui(uuid) to authenticated;

create function public.cantina_smetti_di_seguire(p_owner_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Devi accedere per gestire le Cantine che segui.'
      using errcode = '42501';
  end if;
  if p_owner_id is null then
    raise exception 'Cantina non indicata.' using errcode = '22004';
  end if;

  -- Qui **non** si verifica che il proprietario sia ancora pubblico, ed e
  -- deliberato: chi segue una Cantina che e diventata irraggiungibile deve
  -- comunque poter smettere di seguirla. Togliere una relazione riduce
  -- l'esposizione, quindi non viene chiuso dietro le condizioni che proteggono
  -- una scrittura nuova.
  delete from private.cellar_follows
  where follower_id = v_uid
    and owner_id = p_owner_id;

  -- Il risultato e lo stato finale, non «ho cancellato qualcosa»: smettere due
  -- volte risponde false entrambe le volte senza corrompere nulla.
  return false;
end;
$$;

comment on function public.cantina_smetti_di_seguire(uuid) is
  'Smette di seguire la Cantina di un profilo gia noto. Il follower e auth.uid(). '
  'Idempotente, e ammessa anche quando il proprietario non e piu pubblico. Non '
  'cancella lo storico delle notifiche gia ricevute: ferma solo quelle nuove.';

revoke all on function public.cantina_smetti_di_seguire(uuid) from public, anon;
grant execute on function public.cantina_smetti_di_seguire(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- [3] «Le mie Cantine» — elenco paginato del solo chiamante
-- ---------------------------------------------------------------------------
--
-- Non accetta alcun identificativo di utente: l'unico elenco che esiste e
-- quello del chiamante. Escono soltanto dati che sono gia pubblici del
-- proprietario. NON escono: email, data di nascita, stato di moderazione, dati
-- privati della Cantina, costi, note, posizione fisica, contatore o elenco dei
-- follower, valore privato.

create function public.cantine_seguite_page(
  p_before_created_at timestamptz default null,
  p_before_owner_id uuid default null,
  p_limit integer default 24
)
returns table (
  owner_id uuid,
  username text,
  avatar_url text,
  citta text,
  provincia text,
  followed_at timestamptz,
  bottiglie_pubbliche integer
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
  if private.utente_stato_di(v_uid) = 'rimosso'::public.utente_stato then
    raise exception 'Account rimosso.' using errcode = '42501';
  end if;
  -- Stessa disciplina di cursore di `notifications_page`: le due componenti
  -- arrivano insieme o non arrivano, e il limite ha un tetto dichiarato.
  if p_limit not between 1 and 50
     or ((p_before_created_at is null) <> (p_before_owner_id is null)) then
    raise exception 'Cursore non valido.' using errcode = '22023';
  end if;

  return query
  select
    f.owner_id,
    pp.username,
    pp.avatar_url,
    pp.citta,
    pp.provincia,
    f.created_at as followed_at,
    -- Il conteggio viene dalla sola sorgente canonica: nessun predicato di
    -- pubblicabilita viene ricostruito qui. Zero e un valore legittimo — una
    -- Cantina pubblica ancora vuota resta seguibile ed elencata.
    coalesce(b.bottiglie, 0)::integer as bottiglie_pubbliche
  from private.cellar_follows f
    -- Il join non e decorativo: e il filtro. Un proprietario che non e piu
    -- pubblico sparisce dall'elenco mentre la relazione resta in tabella.
    join private.profili_pubblici pp on pp.user_id = f.owner_id
    left join lateral (
      select count(*) as bottiglie
      from private.cantina_pubblica c
      where c.user_id = f.owner_id
    ) b on true
  where f.follower_id = v_uid
    and (
      p_before_created_at is null
      or (f.created_at, f.owner_id) < (p_before_created_at, p_before_owner_id)
    )
  order by f.created_at desc, f.owner_id desc
  limit p_limit;
end;
$$;

comment on function public.cantine_seguite_page(timestamptz, uuid, integer) is
  'Elenco paginato delle Cantine seguite dal solo auth.uid(). Non accetta alcun '
  'identificativo di utente, quindi non esiste la forma «le Cantine seguite da '
  'qualcun altro». Restituisce solo dati gia pubblici del proprietario: nessun '
  'contatore di follower, nessun dato privato della Cantina, nessun valore. Un '
  'proprietario non piu pubblico non compare.';

revoke all on function public.cantine_seguite_page(timestamptz, uuid, integer)
  from public, anon;
grant execute on function public.cantine_seguite_page(timestamptz, uuid, integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- [4] La destinazione tipizzata `cellar` nelle notifiche esistenti
-- ---------------------------------------------------------------------------
--
-- Nessun URL arbitrario entra nel database: la destinazione e un uuid di
-- profilo, e il percorso `/profilo/<id>/cantina` lo compone il frontend con il
-- suo registro delle rotte. La label 'cellar' dell'enum e stata aggiunta dalla
-- 20260926090000, in un file separato perche PostgreSQL vieta di usare un valore
-- di enum nella stessa transazione che lo aggiunge.

alter table public.notifications
  add column destination_profile_id uuid
    references public.profiles (id) on delete cascade;

comment on column public.notifications.destination_profile_id is
  'Profilo di destinazione quando destination_kind = ''cellar''. Il frontend ne '
  'ricava /profilo/<id>/cantina: nel database non finisce nessun URL. NULL per '
  'ogni altro kind, imposto da notifications_destination_shape.';

-- Il vincolo di forma vive soltanto nella 20260806224517, che e pubblicata e
-- quindi congelata: si sostituisce qui senza toccare quel file, conservando
-- INTATTI tutti i rami precedenti.
--
-- E si aggiunge `else false`, che nella versione della Fase 8 mancava. Un `CASE`
-- senza `else` vale NULL per una label non elencata, e un CHECK che vale NULL
-- non e violato: la label 'cellar' avrebbe attraversato il vincolo senza alcuna
-- verifica, e cosi ogni label futura. Da qui in avanti una destinazione non
-- prevista viene rifiutata invece di essere accolta a forma libera.
alter table public.notifications
  drop constraint notifications_destination_shape;

alter table public.notifications
  add constraint notifications_destination_shape check (
    case destination_kind
      when 'none' then
        destination_conversation_id is null
        and destination_listing_id is null
        and destination_order_id is null
        and destination_club_slug is null
        and destination_profile_id is null
      when 'conversation' then
        destination_conversation_id is not null
        and destination_listing_id is null
        and destination_order_id is null
        and destination_club_slug is null
        and destination_profile_id is null
      when 'listing' then
        destination_conversation_id is null
        and destination_listing_id is not null
        and destination_order_id is null
        and destination_club_slug is null
        and destination_profile_id is null
      when 'order' then
        destination_conversation_id is null
        and destination_listing_id is null
        and destination_order_id is not null
        and destination_club_slug is null
        and destination_profile_id is null
      when 'club' then
        destination_conversation_id is null
        and destination_listing_id is null
        and destination_order_id is null
        and destination_club_slug is not null
        and destination_club_slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
        and destination_profile_id is null
      when 'cellar' then
        destination_conversation_id is null
        and destination_listing_id is null
        and destination_order_id is null
        and destination_club_slug is null
        and destination_profile_id is not null
      else false
    end
  );

-- Il destinatario legge le proprie notifiche dalla RPC, non dalla tabella; la
-- colonna entra comunque nell'elenco chiuso dei GRANT perche tabella e RPC
-- restino d'accordo su che cosa e esposto. Non aggiunge informazione: e lo
-- stesso uuid che la RPC gia restituisce a quello stesso destinatario.
grant select (destination_profile_id) on public.notifications to authenticated;

-- ---------------------------------------------------------------------------
-- [5] notifications_page — estensione additiva della definizione corrente
-- ---------------------------------------------------------------------------
--
-- La definizione in vigore e quella della 20260810180000 (Fase 9b), non quella
-- della Fase 8: ha in piu il rifiuto `42501` per l'account rimosso. Viene
-- riprodotta identica — stessa firma, stessa volatilita, stesso search_path,
-- stesse guardie, stesso cursore, stesso ordinamento — con la sola colonna
-- `destination_profile_id` in coda ai campi di destinazione.
--
-- Serve `drop`, non `create or replace`: PostgreSQL non consente di cambiare il
-- tipo di ritorno di una funzione esistente. Il `drop` porta via i privilegi,
-- quindi vengono ridichiarati subito sotto — dimenticarlo lascerebbe la pagina
-- delle notifiche senza permesso di esecuzione.

drop function if exists public.notifications_page(timestamptz, uuid, integer);

create function public.notifications_page(
  p_before_created_at timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  category public.notification_category,
  event_type text,
  body text,
  destination_kind public.notification_destination_kind,
  destination_conversation_id uuid,
  destination_listing_id uuid,
  destination_order_id uuid,
  destination_club_slug text,
  destination_profile_id uuid,
  read_at timestamptz,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if private.utente_stato_di(v_uid) = 'rimosso' then
    raise exception 'Account rimosso.' using errcode = '42501';
  end if;
  if p_limit not between 1 and 100
     or ((p_before_created_at is null) <> (p_before_id is null)) then
    raise exception 'Cursore non valido.' using errcode = '22023';
  end if;

  return query
  select
    n.id,
    n.category,
    n.event_type,
    n.body,
    n.destination_kind,
    n.destination_conversation_id,
    n.destination_listing_id,
    n.destination_order_id,
    n.destination_club_slug,
    n.destination_profile_id,
    n.read_at,
    n.created_at
  from public.notifications n
  where n.recipient_id = v_uid
    and (
      p_before_created_at is null
      or (n.created_at, n.id) < (p_before_created_at, p_before_id)
    )
  order by n.created_at desc, n.id desc
  limit p_limit;
end;
$$;

comment on function public.notifications_page(timestamptz, uuid, integer) is
  'Pagina delle notifiche del solo auth.uid(), con cursore (created_at, id). '
  'Identica alla definizione della 20260810180000 salvo destination_profile_id '
  'in coda ai campi di destinazione.';

revoke execute on function public.notifications_page(timestamptz, uuid, integer)
  from public, anon;
grant execute on function public.notifications_page(timestamptz, uuid, integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- [6] L'evento: una bottiglia che ENTRA nella Cantina pubblica
-- ---------------------------------------------------------------------------
--
-- ANTI-SPAM. Nel database la visibilita e della singola bottiglia, ma
-- l'interruttore del proprietario scrive tutte le unita di quel vino in un solo
-- UPDATE. Tre unita dello stesso vino esposte insieme devono produrre UNA
-- notifica per destinatario, non tre. La `dedupe_key` e quindi
-- `cellar:<owner>:<wine>:<txid>`:
--
--   * unita diverse dello stesso vino nella stessa transazione collassano, perche
--     owner, vino e txid coincidono;
--   * vini diversi nella stessa transazione restano notifiche distinte;
--   * una pubblicazione vera dello stesso vino in una transazione futura ha un
--     txid nuovo e torna a notificare.
--
-- Non si usa una chiave permanente `owner+vino`: quella zittirebbe per sempre un
-- vino riacquistato ed esposto mesi dopo, che e un evento reale.

create function private.cantina_pubblica_notifica_seguaci(p_bottle_unit_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner     uuid;
  v_wine      uuid;
  v_etichetta text;
  v_username  text;
  v_body      text;
  v_dedupe    text;
begin
  -- (1) L'appartenenza alla superficie pubblica la dichiara la sola sorgente
  -- canonica. Qui non si rilegge `visibilita`, non si ricontrolla `deleted_at`,
  -- `ceduta_at` o `stato`, e non si ricostruisce la visibilita del proprietario:
  -- se la bottiglia non e in questa vista, non e nella Cantina pubblica e non
  -- c'e nulla da annunciare. La vista porta con se anche il filtro sul
  -- proprietario rimosso o non pubblico.
  select
    c.user_id,
    c.wine_id,
    btrim(concat_ws(' ', c.produttore, c.nome, nullif(c.annata::text, '')))
  into v_owner, v_wine, v_etichetta
  from private.cantina_pubblica c
  where c.bottle_unit_id = p_bottle_unit_id;

  if v_owner is null then
    return;
  end if;

  select pp.username into v_username
  from private.profili_pubblici pp
  where pp.user_id = v_owner;

  if v_username is null then
    return;
  end if;

  -- (2) Il corpo esce dal limite di 500 caratteri della tabella per
  -- costruzione, non per troncamento della frase: si accorciano prima le due
  -- parti variabili, cosi la notifica resta una frase intera e un'aggiunta
  -- legittima non fallisce mai per una stringa troppo lunga.
  v_username  := btrim(left(v_username, 80));
  v_etichetta := btrim(left(coalesce(nullif(v_etichetta, ''), 'un vino'), 200));
  v_body := btrim(left(
    v_username || ' ha aggiunto ' || v_etichetta || ' alla sua Cantina.',
    500
  ));

  -- Nel corpo entrano solo produttore, nome e annata, che sono gia pubblicati
  -- dalla Cantina. Non entrano posizione fisica, costo, prezzo di acquisto,
  -- note personali ne quantita privata.
  v_dedupe := 'cellar:' || v_owner::text || ':' || v_wine::text
              || ':' || txid_current()::text;

  -- (3) Destinatari: i follower correnti, esclusi i rimossi secondo la sola
  -- condizione canonica del dominio, ed escluso il proprietario.
  insert into public.notifications (
    recipient_id, category, event_type, body, dedupe_key,
    destination_kind, destination_profile_id
  )
  select
    f.follower_id,
    'community'::public.notification_category,
    'cellar_wine_added',
    v_body,
    v_dedupe,
    'cellar'::public.notification_destination_kind,
    v_owner
  from private.cellar_follows f
  where f.owner_id = v_owner
    and f.follower_id <> v_owner
    and private.utente_stato_di(f.follower_id) <> 'rimosso'::public.utente_stato
  on conflict (recipient_id, dedupe_key) do nothing;
end;
$$;

comment on function private.cantina_pubblica_notifica_seguaci(uuid) is
  'Fanout di una bottiglia entrata nella Cantina pubblica verso i follower '
  'correnti. L''appartenenza la decide private.cantina_pubblica e non predicati '
  'ricopiati. Una notifica per destinatario, proprietario e vino per transazione '
  'di pubblicazione. Nessun backfill e nessun URL nel database.';

revoke all on function private.cantina_pubblica_notifica_seguaci(uuid)
  from public, anon, authenticated;

create function private.bottle_units_cantina_pubblica_fanout()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Solo l'ingresso. Pubblico -> pubblico, pubblico -> privata e gli
  -- aggiornamenti di campi non pertinenti non sono un'aggiunta alla Cantina: il
  -- trigger e limitato alla colonna `visibilita` e il confronto con OLD chiude
  -- il resto.
  if tg_op = 'INSERT' then
    if new.visibilita is distinct from 'cantina_pubblica'::public.bottle_unit_visibilita then
      return null;
    end if;
  else
    if new.visibilita is distinct from 'cantina_pubblica'::public.bottle_unit_visibilita
       or old.visibilita = 'cantina_pubblica'::public.bottle_unit_visibilita then
      return null;
    end if;
  end if;

  perform private.cantina_pubblica_notifica_seguaci(new.id);
  return null;
end;
$$;

comment on function private.bottle_units_cantina_pubblica_fanout() is
  'Riconosce l''ingresso di una bottiglia nella Cantina pubblica: INSERT gia '
  'pubblica, oppure UPDATE privata -> cantina_pubblica. Non reagisce a '
  'pubblico -> pubblico, a pubblico -> privata ne ad altri campi.';

revoke all on function private.bottle_units_cantina_pubblica_fanout()
  from public, anon, authenticated;

create trigger bottle_units_cantina_pubblica_fanout
  after insert or update of visibilita on public.bottle_units
  for each row execute function private.bottle_units_cantina_pubblica_fanout();

-- ---------------------------------------------------------------------------
-- [7] Guardie fail-closed della superficie
-- ---------------------------------------------------------------------------
--
-- Stanno qui e non in una griglia perche una migrazione futura che allarghi
-- questa superficie deve fallire mentre viene applicata, non essere scoperta
-- dopo. La griglia 12k prova il comportamento su dati veri.

do $$
declare
  v_args text;
  v_out  text;
  v_src  text;
begin
  -- Nessuna delle porte accetta un identificativo di utente diverso dal
  -- proprietario della Cantina da guardare: se comparisse un `follower_id`, il
  -- grafo privato smetterebbe di essere privato.
  for v_args in
    select pg_get_function_arguments(p.oid)
    from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'cantina_seguita_stato', 'cantina_segui',
        'cantina_smetti_di_seguire', 'cantine_seguite_page'
      )
  loop
    -- I confini di parola non sono decorativi: senza `\m` il pattern `uid`
    -- troverebbe se stesso dentro il tipo `uuid` e questa guardia fallirebbe
    -- sempre, su ogni firma.
    if v_args ~* '\m(follower[a-z_]*|utente[a-z_]*|user_id|uid)\M' then
      raise exception
        'Invariante: nessuna porta del follow deve accettare un identificativo di follower. Trovato: %',
        v_args;
    end if;
  end loop;

  select pg_get_function_arguments(p.oid)
  into v_args
  from pg_proc p
  where p.oid = 'public.cantine_seguite_page(timestamptz, uuid, integer)'::regprocedure;
  -- Nomi e tipi degli argomenti, non la resa testuale dei DEFAULT: quella e un
  -- dettaglio di formattazione del catalogo e non un invariante del contratto.
  if v_args !~ '\mp_before_created_at timestamp with time zone\M'
     or v_args !~ '\mp_before_owner_id uuid\M'
     or v_args !~ '\mp_limit integer\M' then
    raise exception 'Invariante: la firma di cantine_seguite_page e cambiata: %', v_args;
  end if;

  -- L'elenco delle Cantine seguite non deve far uscire dati privati del
  -- proprietario. La firma e un elenco chiuso, verificato per esclusione.
  v_out := lower(pg_get_function_result(
    'public.cantine_seguite_page(timestamptz, uuid, integer)'::regprocedure));
  if v_out ~ '(email|dob|data_nascita|stato_utente|moderaz|follower|costo|cost_cents|prezzo|note|posizione|valore)' then
    raise exception
      'Invariante: cantine_seguite_page deve restituire soltanto dati pubblici del proprietario. Firma: %',
      v_out;
  end if;

  -- Nessuna rubrica: non deve esistere una porta pubblica che elenchi i
  -- follower di qualcuno o le Cantine seguite da qualcun altro.
  if exists (
    select 1
    from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (
        p.proname ~ '^(cantina_)?follower'
        or p.proname ~ 'cantine_followed'
        or p.proname ~ 'cantina_seguaci'
      )
  ) then
    raise exception
      'Invariante: il grafo di follow non ha una porta pubblica per proprietario.';
  end if;

  -- I ruoli client non toccano la tabella dei follow.
  if has_table_privilege('anon', 'private.cellar_follows',
       'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
     or has_table_privilege('authenticated', 'private.cellar_follows',
       'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER') then
    raise exception
      'Invariante: i ruoli client non devono avere accesso diretto a private.cellar_follows.';
  end if;

  -- Il fanout non deve ricostruire le regole di pubblicabilita.
  select lower(p.prosrc) into v_src
  from pg_proc p
  where p.oid = 'private.cantina_pubblica_notifica_seguaci(uuid)'::regprocedure;
  if v_src !~ 'private\.cantina_pubblica' then
    raise exception
      'Invariante: il fanout deve derivare l''appartenenza da private.cantina_pubblica.';
  end if;
  if v_src ~ 'deleted_at|ceduta_at|acquisition_cost_cents|note_personali' then
    raise exception
      'Invariante: il fanout non deve ricopiare i predicati della Cantina pubblica ne leggere dati privati.';
  end if;
  if v_src !~ 'on conflict' then
    raise exception 'Invariante: il fanout deve restare idempotente sulla dedupe_key.';
  end if;

  -- Il trigger Realtime della Fase 8 resta quello, e resta attaccato: le
  -- notifiche nuove devono passare per l'infrastruttura esistente.
  if not exists (
    select 1
    from pg_trigger t
    where t.tgrelid = 'public.notifications'::regclass
      and t.tgname = 'notifications_after_change'
      and not t.tgisinternal
  ) then
    raise exception
      'Invariante: il trigger Realtime notifications_after_change deve restare attaccato.';
  end if;

  -- Il vincolo di forma copre la nuova destinazione e rifiuta le label ignote.
  select pg_get_constraintdef(c.oid) into v_src
  from pg_constraint c
  where c.conrelid = 'public.notifications'::regclass
    and c.conname = 'notifications_destination_shape';
  if v_src !~* 'cellar' or v_src !~* 'else\s+false' then
    raise exception
      'Invariante: notifications_destination_shape deve coprire cellar e rifiutare le label non elencate.';
  end if;

  -- La pagina delle notifiche conserva firma, privilegi e rifiuto dell'account
  -- rimosso introdotto dalla 20260810180000.
  select lower(p.prosrc) into v_src
  from pg_proc p
  where p.oid = 'public.notifications_page(timestamptz, uuid, integer)'::regprocedure;
  if v_src !~ 'utente_stato_di' or v_src !~ 'destination_profile_id' then
    raise exception
      'Invariante: notifications_page deve conservare il filtro sull''account rimosso ed esporre destination_profile_id.';
  end if;
  if not has_function_privilege(
       'authenticated', 'public.notifications_page(timestamptz, uuid, integer)', 'execute')
     or has_function_privilege(
       'anon', 'public.notifications_page(timestamptz, uuid, integer)', 'execute') then
    raise exception
      'Invariante: notifications_page resta eseguibile da authenticated e non da anon.';
  end if;
end;
$$;

-- Nessuna riga di notifica viene creata da questa migrazione: la verifica e
-- esplicita perche «nessun backfill» e una promessa, e una promessa si misura.
do $$
begin
  if exists (
    select 1 from public.notifications where event_type = 'cellar_wine_added'
  ) then
    raise exception
      'Invariante: questa migrazione non deve creare notifiche per le bottiglie gia pubbliche.';
  end if;
  if exists (select 1 from private.cellar_follows) then
    raise exception 'Invariante: nessun backfill dei follow.';
  end if;
end;
$$;

notify pgrst, 'reload schema';
