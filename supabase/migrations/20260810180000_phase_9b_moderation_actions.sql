-- ===========================================================================
-- Fase 9b - azioni di moderazione, sospensione utente a due livelli
-- ===========================================================================
--
-- Il 9a ha portato lo schema, l'audit append-only e le code in sola lettura.
-- Qui arriva la scrittura: le sette azioni di moderazione, le transizioni di
-- stato sugli annunci decise da un moderatore, e l'enforcement della
-- sospensione utente della decisione 7.6b.
--
-- COSA QUESTA MIGRAZIONE NON FA, E PERCHE.
-- Non tocca `public.has_role()`, che resta inservibile per un chiamante
-- `authenticated` (motivo per esteso nel 9a, righe 622-648): la coda
-- `wines_insert_staff`/`wines_update_staff`/`wines_delete_staff` e fuori
-- perimetro. Non tocca `bottle_units.visibilita` ne l'enum
-- `bottle_unit_visibilita`, residui inerti che appartengono al cutover della
-- Fase 11. Non introduce SLA (decisione 7.8a) ne alcun campo di ricorso
-- (decisione 7.8b). Non allarga `public.listing_sospendi(uuid, text)`, che
-- resta la sospensione decisa dal venditore sul proprio annuncio `attivo`.
--
-- IL PREDICATO DI MODERATORE.
-- Come nel 9a non passa da `public.has_role()`: e l'`exists` su
-- `public.user_roles` scritto per esteso. Qui vive dentro
-- `private.moderazione_attore()`, che le RPC chiamano dall'interno del proprio
-- corpo SECURITY DEFINER. La differenza con il 9a e il contesto, non il
-- predicato: in una vista il riferimento a `user_roles` e verificato con i
-- privilegi del proprietario solo grazie a `security_invoker = off`, mentre in
-- una funzione SECURITY DEFINER lo e per costruzione. In entrambi i casi
-- nessun ruolo client acquista un privilegio su `user_roles`, ed e questo il
-- punto: `private.moderazione_attore()` non e concessa a nessuno.

-- ===========================================================================
-- PARTE A - lo stato utente su profiles
-- ===========================================================================
--
-- Decisione 7.6b: due livelli, quindi uno stato a piu valori e non un
-- booleano, piu un contatore che distingue il primo provvedimento dal secondo.
-- Lo storico non e una tabella nuova: e `public.audit_log`, che dalla 9a
-- registra ogni azione con attore, bersaglio e motivazione ed e append-only per
-- trigger. Il contatore su `profiles` e la proiezione veloce di quello storico,
-- ed e cio su cui la regola decide; il registro resta la prova.

create type public.utente_stato as enum ('attivo', 'sospeso', 'rimosso');

comment on type public.utente_stato is
  'Stato di moderazione di un utente. `sospeso` e il primo provvedimento della '
  'decisione 7.6b: blocca le sole scritture social. `rimosso` e il secondo: '
  'toglie anche l''accesso in visione. La compravendita non passa da qui.';

alter table public.profiles
  add column stato_utente public.utente_stato not null default 'attivo',
  add column provvedimenti integer not null default 0 check (provvedimenti >= 0),
  add column stato_utente_at timestamptz,
  add column stato_utente_motivo text
    check (stato_utente_motivo is null
           or length(btrim(stato_utente_motivo)) between 1 and 4000);

comment on column public.profiles.stato_utente is
  'Stato di moderazione. Scrivibile solo dalle funzioni di moderazione: il '
  'GRANT di UPDATE del client non contiene questa colonna e il trigger '
  'profiles_stato_utente_guard rifiuta la scrittura anche a service_role.';
comment on column public.profiles.provvedimenti is
  'Numero cumulativo di provvedimenti subiti. Decide il livello: al primo '
  'l''utente diventa `sospeso`, dal secondo `rimosso`. Un ripristino non lo '
  'azzera, altrimenti il secondo provvedimento non sarebbe mai il secondo.';

-- Terza regola di esposizione: una colonna che ha una regola di dominio dietro
-- non e scrivibile dal client. `grant select, update on public.profiles to
-- authenticated` (Fase 5a) e un GRANT di tabella intera su UPDATE: senza questa
-- restrizione un utente sospeso potrebbe togliersi la sospensione da solo con
-- un UPDATE sulla propria riga, che la policy profiles_update_own consente.
-- L'elenco sotto e esattamente cio che il profilo pubblico contiene oggi meno
-- le quattro colonne di moderazione; `updated_at` resta fuori perche lo scrive
-- il trigger moddatetime, `id` e `created_at` perche non si riscrivono.
revoke update on public.profiles from authenticated;
grant update (
  username, bio, citta, provincia, esperienza, avatar_url, dob, obiettivi
) on public.profiles to authenticated;

-- Il SELECT di tabella resta: la policy profiles_select_own limita ogni ruolo
-- client alla propria riga, quindi nessuno raggiunge righe che non possiede e
-- la prima regola di esposizione non e in gioco. Che l'utente veda il proprio
-- stato_utente e voluto: una sospensione che l'interessato non puo leggere e
-- una sospensione che non si puo spiegare.

-- Il GRANT ristretto vincola i ruoli client; non vincola `service_role`, che ha
-- privilegi propri. Il trigger sotto chiude anche quello, con la stessa forma
-- di private.messages_immutable() della Fase 8: dentro una funzione SECURITY
-- DEFINER di proprieta di postgres `current_user` e postgres, mentre una
-- scrittura diretta di service_role, authenticated o anon porta il proprio
-- nome e viene rifiutata.
create or replace function private.profiles_stato_utente_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.stato_utente is distinct from old.stato_utente
     or new.provvedimenti is distinct from old.provvedimenti
     or new.stato_utente_at is distinct from old.stato_utente_at
     or new.stato_utente_motivo is distinct from old.stato_utente_motivo then
    if current_user not in ('postgres', 'supabase_admin') then
      raise exception
        'Lo stato di moderazione di un profilo si cambia solo dalle funzioni di moderazione.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

comment on function private.profiles_stato_utente_guard() is
  'Le quattro colonne di moderazione di public.profiles non sono scrivibili da '
  'un ruolo client ne da service_role. Un GRANT di colonna non basta: '
  'service_role non e vincolato dai GRANT del client.';

create trigger profiles_stato_utente_guard
  before update on public.profiles
  for each row execute function private.profiles_stato_utente_guard();

-- ===========================================================================
-- PARTE B - helper privati
-- ===========================================================================

-- L'attore, se e un moderatore. Solleva invece di restituire false: ogni
-- chiamante di questa funzione sta per scrivere, e un `false` silenzioso in
-- quel punto diventa un ramo dimenticato.
create or replace function private.moderazione_attore()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  -- Decisione 7.1: il moderatore e il ruolo `admin` esistente, non un ruolo
  -- nuovo. Predicato scritto per esteso e non public.has_role(): vedi il
  -- cappello di questo file.
  if not exists (
    select 1 from public.user_roles ur
    where ur.user_id = v_uid and ur.role = 'admin'
  ) then
    raise exception 'Azione riservata alla moderazione.' using errcode = '42501';
  end if;

  return v_uid;
end;
$$;

comment on function private.moderazione_attore() is
  'Ritorna l''uid del chiamante se ha il ruolo admin, altrimenti solleva. '
  'Unico punto in cui il predicato di moderatore e scritto, per tutte le RPC '
  'della 9b.';

-- Stato di moderazione di un utente, leggibile da dentro le funzioni e i
-- trigger senza dipendere dalle policy di profiles.
create or replace function private.utente_stato_di(p_uid uuid)
returns public.utente_stato
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select p.stato_utente from public.profiles p where p.id = p_uid),
    'attivo'::public.utente_stato
  );
$$;

comment on function private.utente_stato_di(uuid) is
  'Stato di moderazione di un utente. `attivo` anche per un uid sconosciuto: '
  'un profilo che non esiste non e un utente sospeso, e il chiamante ha gia i '
  'propri controlli di esistenza.';

-- ===========================================================================
-- PARTE C - enforcement, primo livello: le scritture social
-- ===========================================================================
--
-- Decisione 7.6b, primo provvedimento: bloccate le sole scritture social -
-- creazione annunci e invio messaggi. La compravendita resta invariata:
-- nessun percorso di `orders`, `payments`, `disputes` o `payouts` e toccato
-- qui, e un utente sospeso continua a poter comprare, vendere cio che ha gia
-- pubblicato, pagare ed essere pagato.
--
-- PERCHE UN TRIGGER E NON UN CONTROLLO DENTRO listing_crea E message_send.
-- Un controllo dentro le RPC vincolerebbe quelle RPC. Un trigger vincola la
-- tabella: vale per ogni percorso presente e futuro, service_role compreso, e
-- non obbliga a riscrivere per intero quattro funzioni grandi di altre fasi
-- solo per aggiungerci una riga. L'eccezione sollevata dal trigger attraversa
-- la funzione SECURITY DEFINER e arriva al client con il proprio messaggio.

create or replace function private.scrittura_social_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- La riga passa da jsonb e non da `new.<colonna>`: lo stesso corpo serve tre
  -- tabelle con colonne diverse, e plpgsql risolve i riferimenti di campo alla
  -- compilazione. `new.seller_id` in un trigger su public.messages non sarebbe
  -- un ramo che non viene percorso, sarebbe un errore di compilazione.
  v_riga jsonb := to_jsonb(new);
  v_attore uuid;
  v_stato public.utente_stato;
begin
  v_attore := case tg_table_name
    when 'listings' then (v_riga->>'seller_id')::uuid
    when 'messages' then (v_riga->>'sender_id')::uuid
    else auth.uid()
  end;

  -- I messaggi di sistema non hanno mittente e non sono una scrittura social.
  if tg_table_name = 'messages' and coalesce(v_riga->>'kind', '') <> 'user' then
    return new;
  end if;

  if v_attore is null then
    return new;
  end if;

  v_stato := private.utente_stato_di(v_attore);

  if v_stato = 'sospeso' then
    raise exception
      'Account sospeso: non puoi pubblicare annunci ne scrivere messaggi.'
      using errcode = '42501';
  elsif v_stato = 'rimosso' then
    raise exception 'Account rimosso.' using errcode = '42501';
  end if;

  return new;
end;
$$;

comment on function private.scrittura_social_guard() is
  'Primo livello della decisione 7.6b. Blocca l''inserimento di annunci, di '
  'messaggi utente e l''apertura di conversazioni per un utente sospeso o '
  'rimosso. Ordini e pagamenti non passano da qui, per decisione.';

create trigger listings_scrittura_social_guard
  before insert on public.listings
  for each row execute function private.scrittura_social_guard();

create trigger messages_scrittura_social_guard
  before insert on public.messages
  for each row execute function private.scrittura_social_guard();

-- L'apertura di una conversazione e il primo contatto, e nella Fase 8 genera
-- un evento verso la controparte: lasciarla aperta a un sospeso significa
-- lasciargli un canale di notifica che i messaggi gli negano. Qui l'attore non
-- e una colonna della riga - `conversations` ha due partecipanti e nessun
-- iniziatore - quindi il guard usa auth.uid(), che dentro una SECURITY
-- DEFINER continua a leggere il claim del chiamante.
create trigger conversations_scrittura_social_guard
  before insert on public.conversations
  for each row execute function private.scrittura_social_guard();

-- ===========================================================================
-- PARTE D - enforcement, secondo livello: la lettura
-- ===========================================================================
--
-- Decisione 7.6b, secondo provvedimento: rimozione completa, incluso l'accesso
-- in visione. Ha due direzioni e vanno distinte.
--
-- USCENTE - cio che l'utente rimosso mostra agli altri sparisce: i suoi
-- annunci escono da public_listings. Al primo livello restano visibili, ed e
-- scritto nella decisione.
--
-- ENTRANTE - cio che l'utente rimosso puo leggere. Il perimetro e la
-- superficie sociale: catalogo pubblico, conversazioni, messaggi, notifiche.
-- Resta leggibile la superficie contrattuale (ordini, pagamenti, contestazioni)
-- e per una ragione precisa: la decisione toglie la compravendita
-- dall'enforcement al primo livello, e un ordine in corso che diventa
-- illeggibile a meta strada non e una rimozione, e un pagamento sospeso senza
-- che nessuno l'abbia deciso. Questa lettura del confine e dichiarata qui
-- perche sia visibile e reversibile, non nascosta in un ramo.

-- [D.1] Il catalogo pubblico. Definizione ripresa dalla 7c (riga 500) con due
-- predicati in coda. `create or replace view` esige l'elenco di colonne
-- identico e nello stesso ordine: nulla e stato aggiunto, rinominato o mosso.
create or replace view public.public_listings
with (security_invoker = off, security_barrier = true)
as
select
  l.id,
  l.slug,
  l.prezzo_cents,
  l.prezzo_mercato_cents,
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
  p.avatar_url    as seller_avatar_url,
  w.provenienza   as wine_provenienza,
  l.imballaggio_codice
from public.listings l
  join public.bottle_units bu on bu.id = l.bottle_unit_id
  join public.wines w on w.id = bu.wine_id
  join public.profiles p on p.id = l.seller_id
where l.stato = 'attivo'
  and (l.expires_at is null or l.expires_at > now())
  and bu.stato = 'chiusa'
  and bu.deleted_at is null
  and bu.ceduta_at is null
  and bu.owner_id = l.seller_id
  -- Uscente: gli annunci di un venditore rimosso escono dal catalogo.
  and p.stato_utente <> 'rimosso'
  -- Entrante: un chiamante rimosso non legge il catalogo. Per `anon`
  -- auth.uid() e nullo, il not exists e vero e la vista non cambia.
  and not exists (
    select 1 from public.profiles me
    where me.id = (select auth.uid())
      and me.stato_utente = 'rimosso'
  );

comment on view public.public_listings is
  'Catalogo pubblico. Dalla 9b esclude gli annunci di un venditore rimosso e '
  'restituisce zero righe a un chiamante rimosso (decisione 7.6b, secondo '
  'livello). Un chiamante anonimo non e toccato.';

-- [D.2] Le proiezioni del segnalante della 9a. Stessa forma, con il predicato
-- di lettura in coda. Le quattro viste di moderazione non lo ricevono: sono
-- gia filtrate sul ruolo admin, e un moderatore rimosso e un problema di
-- assegnazione dei ruoli, che la decisione 7.2 tiene fuori banda.
create or replace view public.my_reports
with (security_invoker = off, security_barrier = true) as
  select
    r.id,
    r.codice,
    r.target_tipo,
    r.target_label,
    r.motivo,
    r.descrizione,
    r.foto,
    r.stato,
    r.priorita,
    r.club_slug,
    r.created_at,
    r.updated_at
  from public.reports r
  where r.reporter_id = (select auth.uid())
    and not exists (
      select 1 from public.profiles me
      where me.id = (select auth.uid())
        and me.stato_utente = 'rimosso'
    );

create or replace view public.my_report_events
with (security_invoker = off, security_barrier = true) as
  select
    e.id,
    e.report_id,
    e.testo,
    e.autore_etichetta,
    e.created_at
  from public.report_events e
  join public.reports r on r.id = e.report_id
  where e.visibile
    and r.reporter_id = (select auth.uid())
    and not exists (
      select 1 from public.profiles me
      where me.id = (select auth.uid())
        and me.stato_utente = 'rimosso'
    );

-- [D.3] Le porte di lettura della Fase 8. Sono SECURITY DEFINER, quindi qui il
-- controllo puo chiamare private.utente_stato_di senza concedere EXECUTE a
-- nessuno. Corpo identico a quello della Fase 8: cambia solo il blocco di
-- guardia in testa.

create or replace function public.conversations_page(
  p_before_activity_at timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 30
)
returns table (
  conversation_id uuid,
  listing_id uuid,
  listing_slug text,
  listing_price_cents integer,
  order_id uuid,
  counterpart_id uuid,
  counterpart_username text,
  counterpart_avatar_url text,
  wine_name text,
  wine_image text,
  order_status text,
  writable boolean,
  last_message_id uuid,
  last_message_at timestamptz,
  last_message_preview text,
  unread_count bigint,
  activity_at timestamptz,
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
  if p_limit not between 1 and 50
     or ((p_before_activity_at is null) <> (p_before_id is null)) then
    raise exception 'Cursore non valido.' using errcode = '22023';
  end if;

  return query
  select
    c.id,
    c.listing_id,
    l.slug,
    l.prezzo_cents,
    c.order_id,
    counterpart.id,
    counterpart.username,
    counterpart.avatar_url,
    w.produttore || ' ' || w.nome,
    coalesce(l.immagini[1], ''),
    o.stato::text,
    private.conversation_is_writable(c.id),
    c.last_message_id,
    c.last_message_at,
    lm.body,
    (
      select count(*)
      from public.messages unread
      where unread.conversation_id = c.id
        and unread.sender_id is distinct from v_uid
        and (
          cp.last_read_created_at is null
          or (unread.created_at, unread.id) >
            (cp.last_read_created_at, cp.last_read_message_id)
        )
    ),
    coalesce(c.last_message_at, c.created_at),
    c.created_at
  from public.conversations c
  join public.conversation_participants cp
    on cp.conversation_id = c.id and cp.user_id = v_uid
  join public.profiles counterpart
    on counterpart.id = case
      when c.participant_low = v_uid then c.participant_high
      else c.participant_low
    end
  join public.listings l on l.id = c.listing_id
  join public.bottle_units bu on bu.id = l.bottle_unit_id
  join public.wines w on w.id = bu.wine_id
  left join public.orders o on o.id = c.order_id
  left join public.messages lm on lm.id = c.last_message_id
  where p_before_activity_at is null
     or (coalesce(c.last_message_at, c.created_at), c.id)
          < (p_before_activity_at, p_before_id)
  order by coalesce(c.last_message_at, c.created_at) desc, c.id desc
  limit p_limit;
end;
$$;

create or replace function public.messages_page(
  p_conversation_id uuid,
  p_before_created_at timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  conversation_id uuid,
  sender_id uuid,
  kind public.message_kind,
  body text,
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
  if not exists (
    select 1
    from public.conversations c
    where c.id = p_conversation_id
      and v_uid in (c.participant_low, c.participant_high)
  ) then
    raise exception 'Conversazione non trovata.' using errcode = '42501';
  end if;

  return query
  select m.id, m.conversation_id, m.sender_id, m.kind, m.body, m.created_at
  from public.messages m
  where m.conversation_id = p_conversation_id
    and (
      p_before_created_at is null
      or (m.created_at, m.id) < (p_before_created_at, p_before_id)
    )
  order by m.created_at desc, m.id desc
  limit p_limit;
end;
$$;

create or replace function public.notifications_page(
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

-- Il contatore non solleva: e letto dal badge di ogni pagina e un'eccezione la
-- trasformerebbe in un errore permanente della cornice. Per un utente rimosso
-- vale zero, che e la stessa cosa che vede chi non ha notifiche.
create or replace function public.notifications_unread_count()
returns bigint
language sql
security definer
set search_path = ''
stable
as $$
  select case
    when auth.uid() is null then 0::bigint
    when private.utente_stato_di(auth.uid()) = 'rimosso' then 0::bigint
    else count(*)
  end
  from public.notifications n
  where n.recipient_id = auth.uid()
    and n.read_at is null;
$$;

-- ===========================================================================
-- PARTE E - le transizioni di stato degli annunci decise dalla moderazione
-- ===========================================================================
--
-- Le tre label mancanti dell'enum public.listing_stato - in_revisione,
-- modifiche_richieste, rifiutato - esistono dalla 6a e nessuna transizione le
-- raggiungeva. Nessuna label nuova viene aggiunta qui.
--
-- `riservato` e `venduto` sono intoccabili da ogni funzione di questa fase: c'e
-- un ordine in corso o concluso sopra, e spostarlo da sotto e una decisione
-- economica che questa fase non prende. E la stessa ragione per cui
-- listing_sospendi rifiuta `riservato` dalla 6b.

create or replace function private.moderazione_annuncio_transizione(
  p_attore uuid,
  p_listing_id uuid,
  p_stato public.listing_stato,
  p_azione public.mod_action,
  p_motivazione text,
  p_ammessi public.listing_stato[],
  p_report_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stato public.listing_stato;
  v_slug text;
  v_bottle uuid;
begin
  if length(btrim(coalesce(p_motivazione, ''))) = 0 then
    raise exception 'Motivazione obbligatoria.' using errcode = '22023';
  end if;

  select l.stato, l.slug, l.bottle_unit_id
    into v_stato, v_slug, v_bottle
  from public.listings l
  where l.id = p_listing_id
  for update;

  if not found then
    raise exception 'Annuncio non trovato.' using errcode = 'P0001';
  end if;

  if v_stato in ('riservato', 'venduto') then
    raise exception
      'Un annuncio con un ordine in corso o concluso non si modera da qui.'
      using errcode = 'P0001';
  end if;

  if not (v_stato = any (p_ammessi)) then
    raise exception 'Transizione non ammessa da %.', v_stato using errcode = 'P0001';
  end if;

  -- listings_un_solo_annuncio_non_terminale copre gli stati non terminali:
  -- riportare in vita un annuncio quando un altro ha gia preso la bottiglia
  -- violerebbe l'indice. Meglio un messaggio che una 23505.
  if p_stato in ('bozza', 'in_revisione', 'modifiche_richieste', 'attivo')
     and exists (
       select 1 from public.listings altro
       where altro.bottle_unit_id = v_bottle
         and altro.id <> p_listing_id
         and altro.stato in ('bozza', 'in_revisione', 'modifiche_richieste',
                             'attivo', 'riservato')
     ) then
    raise exception 'La bottiglia ha gia un altro annuncio non terminale.'
      using errcode = 'P0001';
  end if;

  update public.listings
  set stato = p_stato,
      stato_motivo = btrim(p_motivazione),
      stato_aggiornato_da = p_attore,
      stato_aggiornato_at = now(),
      published_at = case
        when p_stato = 'attivo' then coalesce(published_at, now())
        else published_at
      end
  where id = p_listing_id;

  perform private.audit_registra(
    p_attore_id => p_attore,
    p_azione => p_azione,
    p_target_tipo => 'annuncio'::public.report_target_tipo,
    p_target_id => p_listing_id,
    p_target_label => v_slug,
    p_motivazione => p_motivazione,
    p_report_id => p_report_id
  );
end;
$$;

comment on function private.moderazione_annuncio_transizione is
  'Motore condiviso delle transizioni di moderazione su un annuncio: verifica '
  'lo stato di partenza, rifiuta riservato e venduto, scrive la traccia sulle '
  'tre colonne di listings e registra la riga di audit. Le funzioni pubbliche '
  'sotto sono distinte per azione, non parametrizzate su un''azione.';

-- Le quattro porte pubbliche. Distinte per azione, come le sette del report:
-- una funzione con un parametro `azione` sarebbe un solo GRANT per quattro
-- poteri diversi.

create or replace function public.moderazione_annuncio_in_revisione(
  p_listing_id uuid,
  p_motivazione text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.moderazione_annuncio_transizione(
    private.moderazione_attore(), p_listing_id,
    'in_revisione'::public.listing_stato,
    'richiesta_modifiche'::public.mod_action,
    p_motivazione,
    array['bozza', 'modifiche_richieste', 'attivo', 'sospeso']::public.listing_stato[]
  );
end;
$$;

create or replace function public.moderazione_annuncio_modifiche_richieste(
  p_listing_id uuid,
  p_motivazione text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.moderazione_annuncio_transizione(
    private.moderazione_attore(), p_listing_id,
    'modifiche_richieste'::public.listing_stato,
    'richiesta_modifiche'::public.mod_action,
    p_motivazione,
    array['bozza', 'in_revisione', 'attivo']::public.listing_stato[]
  );
end;
$$;

create or replace function public.moderazione_annuncio_rifiuta(
  p_listing_id uuid,
  p_motivazione text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.moderazione_annuncio_transizione(
    private.moderazione_attore(), p_listing_id,
    'rifiutato'::public.listing_stato,
    'rimozione'::public.mod_action,
    p_motivazione,
    array['bozza', 'in_revisione', 'modifiche_richieste', 'attivo',
          'sospeso']::public.listing_stato[]
  );
end;
$$;

-- La sospensione di moderazione che la 6b aveva rinviato alla Fase 9. Non
-- allarga public.listing_sospendi, che resta del proprietario e del solo stato
-- `attivo`: qui il gate e il ruolo admin e gli stati ammessi sono altri.
create or replace function public.moderazione_annuncio_sospendi(
  p_listing_id uuid,
  p_motivazione text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.moderazione_annuncio_transizione(
    private.moderazione_attore(), p_listing_id,
    'sospeso'::public.listing_stato,
    'sospensione'::public.mod_action,
    p_motivazione,
    array['bozza', 'in_revisione', 'modifiche_richieste',
          'attivo']::public.listing_stato[]
  );
end;
$$;

comment on function public.moderazione_annuncio_sospendi(uuid, text) is
  'Sospensione decisa da un moderatore. Funzione separata da '
  'public.listing_sospendi, che resta del venditore e del solo stato attivo: '
  'il commento della 6b (20260729112500, riga 333) prometteva esattamente '
  'questo.';

create or replace function public.moderazione_annuncio_ripristina(
  p_listing_id uuid,
  p_motivazione text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.moderazione_annuncio_transizione(
    private.moderazione_attore(), p_listing_id,
    'attivo'::public.listing_stato,
    'ripristino'::public.mod_action,
    p_motivazione,
    array['in_revisione', 'modifiche_richieste', 'sospeso',
          'rifiutato']::public.listing_stato[]
  );
end;
$$;

-- ===========================================================================
-- PARTE F - il provvedimento sull'utente, due livelli
-- ===========================================================================

create or replace function private.moderazione_utente_provvedimento(
  p_attore uuid,
  p_profile_id uuid,
  p_motivazione text,
  p_durata text default null,
  p_report_id uuid default null,
  p_forza_rimozione boolean default false
)
returns public.utente_stato
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stato public.utente_stato;
  v_n integer;
  v_username text;
  v_nuovo public.utente_stato;
begin
  if length(btrim(coalesce(p_motivazione, ''))) = 0 then
    raise exception 'Motivazione obbligatoria.' using errcode = '22023';
  end if;

  select p.stato_utente, p.provvedimenti, p.username
    into v_stato, v_n, v_username
  from public.profiles p
  where p.id = p_profile_id
  for update;

  if not found then
    raise exception 'Profilo non trovato.' using errcode = 'P0001';
  end if;

  if p_attore = p_profile_id then
    raise exception 'Un moderatore non applica un provvedimento a se stesso.'
      using errcode = '22023';
  end if;

  if v_stato = 'rimosso' then
    raise exception 'Utente gia rimosso.' using errcode = 'P0001';
  end if;

  -- Il livello lo decide il contatore, non lo stato corrente: un ripristino
  -- riporta lo stato ad `attivo` e lascia il contatore dov'e, quindi il
  -- provvedimento successivo resta il secondo. Entrambi i rami del case sono
  -- castati all'enum: un case fra due letterali si risolve a text e text->enum
  -- non ha conversione implicita (42804, difetto della 7c).
  v_nuovo := case
    when p_forza_rimozione or v_n >= 1 then 'rimosso'::public.utente_stato
    else 'sospeso'::public.utente_stato
  end;

  update public.profiles
  set stato_utente = v_nuovo,
      provvedimenti = v_n + 1,
      stato_utente_at = now(),
      stato_utente_motivo = btrim(p_motivazione)
  where id = p_profile_id;

  perform private.audit_registra(
    p_attore_id => p_attore,
    p_azione => case
      when v_nuovo = 'rimosso' then 'rimozione'::public.mod_action
      else 'sospensione'::public.mod_action
    end,
    p_target_tipo => 'profilo'::public.report_target_tipo,
    p_target_id => p_profile_id,
    p_target_label => v_username,
    p_motivazione => p_motivazione,
    p_durata => case
      when v_nuovo = 'sospeso' then p_durata
      else null
    end,
    p_report_id => p_report_id
  );

  return v_nuovo;
end;
$$;

comment on function private.moderazione_utente_provvedimento is
  'Enforcement della decisione 7.6b. Primo provvedimento: `sospeso`, che '
  'blocca le sole scritture social. Dal secondo: `rimosso`, che toglie anche '
  'la lettura. Il contatore non si azzera con il ripristino, altrimenti il '
  'secondo provvedimento non sarebbe mai il secondo.';

create or replace function private.moderazione_utente_ripristina(
  p_attore uuid,
  p_profile_id uuid,
  p_motivazione text,
  p_report_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stato public.utente_stato;
  v_username text;
begin
  if length(btrim(coalesce(p_motivazione, ''))) = 0 then
    raise exception 'Motivazione obbligatoria.' using errcode = '22023';
  end if;

  select p.stato_utente, p.username into v_stato, v_username
  from public.profiles p
  where p.id = p_profile_id
  for update;

  if not found then
    raise exception 'Profilo non trovato.' using errcode = 'P0001';
  end if;
  if v_stato = 'attivo' then
    raise exception 'Utente gia attivo.' using errcode = 'P0001';
  end if;

  update public.profiles
  set stato_utente = 'attivo'::public.utente_stato,
      stato_utente_at = now(),
      stato_utente_motivo = btrim(p_motivazione)
  where id = p_profile_id;

  perform private.audit_registra(
    p_attore_id => p_attore,
    p_azione => 'ripristino'::public.mod_action,
    p_target_tipo => 'profilo'::public.report_target_tipo,
    p_target_id => p_profile_id,
    p_target_label => v_username,
    p_motivazione => p_motivazione,
    p_report_id => p_report_id
  );
end;
$$;

-- ===========================================================================
-- PARTE G - le sette azioni di moderazione su una pratica
-- ===========================================================================
--
-- Sette funzioni distinte e non una con parametro azione: un solo GRANT
-- EXECUTE su una funzione parametrica concederebbe insieme l'ammonizione e la
-- rimozione, e il giorno in cui i poteri andranno separati non ci sarebbe piu
-- niente da separare. Il costo e sette firme; il beneficio e che ciascuna e
-- concedibile e revocabile da sola.
--
-- Ogni azione fa quattro cose nella stessa transazione: applica l'effetto sul
-- bersaglio, sposta lo stato della pratica, scrive la voce di storia (visibile
-- al segnalante) e l'eventuale nota interna (mai visibile al segnalante), e
-- registra la riga di audit. La motivazione e obbligatoria come vincolo di
-- database: il NOT NULL con CHECK su audit_log.motivazione della 9a, piu il
-- controllo in testa a ciascun motore.

create or replace function private.moderazione_pratica(
  p_report_id uuid,
  p_stato_pratica public.report_stato,
  p_motivazione text,
  p_nota_interna text,
  p_testo_visibile text
)
returns public.reports
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attore uuid := private.moderazione_attore();
  v_report public.reports;
  v_username text;
begin
  if length(btrim(coalesce(p_motivazione, ''))) = 0 then
    raise exception 'Motivazione obbligatoria.' using errcode = '22023';
  end if;

  select * into v_report
  from public.reports r
  where r.id = p_report_id
  for update;

  if not found then
    raise exception 'Segnalazione non trovata.' using errcode = 'P0001';
  end if;
  if v_report.stato in ('risolta', 'respinta') then
    raise exception 'Questa pratica e gia chiusa.' using errcode = 'P0001';
  end if;

  update public.reports
  set stato = p_stato_pratica,
      updated_at = now()
  where id = p_report_id
  returning * into v_report;

  select pr.username into v_username
  from public.profiles pr where pr.id = v_attore;

  insert into public.report_events
    (report_id, visibile, testo, autore_id, autore_etichetta)
  values
    (p_report_id, true, p_testo_visibile, v_attore, 'Moderazione');

  if length(btrim(coalesce(p_nota_interna, ''))) > 0 then
    insert into public.report_events
      (report_id, visibile, testo, autore_id, autore_etichetta)
    values
      (p_report_id, false, btrim(p_nota_interna), v_attore,
       coalesce(v_username, 'Moderazione'));
  end if;

  return v_report;
end;
$$;

comment on function private.moderazione_pratica is
  'Parte comune delle sette azioni: verifica il moderatore, blocca una pratica '
  'gia chiusa, sposta lo stato, scrive la voce visibile e l''eventuale nota '
  'interna. L''effetto sul bersaglio e la riga di audit restano a ciascuna '
  'azione, perche sono cio che le distingue.';

-- Il bersaglio di una pratica, risolto una volta sola.
create or replace function private.moderazione_bersaglio(p_report public.reports)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    p_report.target_listing_id, p_report.target_profile_id,
    p_report.target_message_id, p_report.target_conversation_id,
    p_report.target_review_id
  );
$$;

-- [1] info_richieste - si chiede altro al segnalante. Nessun effetto sul
-- bersaglio: e l'unica azione che lascia la pratica aperta e in attesa.
create or replace function public.moderazione_info_richieste(
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
begin
  v_report := private.moderazione_pratica(
    p_report_id,
    'info_richieste'::public.report_stato,
    p_motivazione, p_nota_interna,
    'Sono state richieste ulteriori informazioni'
  );

  perform private.audit_registra(
    p_attore_id => (select auth.uid()),
    p_azione => 'info_richieste'::public.mod_action,
    p_target_tipo => v_report.target_tipo,
    p_target_id => private.moderazione_bersaglio(v_report),
    p_target_label => v_report.target_label,
    p_motivazione => p_motivazione,
    p_report_id => p_report_id
  );
end;
$$;

-- [2] richiesta_modifiche - la pratica entra in revisione e, se il bersaglio e
-- un annuncio, l'annuncio passa a `modifiche_richieste`, dove la policy
-- listings_update_own gia consente al venditore di correggerlo.
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

-- [3] ammonizione - un avvertimento. Non incrementa il contatore dei
-- provvedimenti: il contatore decide il livello di sospensione, e
-- un'ammonizione che portasse alla rimozione al secondo richiamo sarebbe una
-- regola diversa da quella decisa.
create or replace function public.moderazione_ammonizione(
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
begin
  v_report := private.moderazione_pratica(
    p_report_id,
    'risolta'::public.report_stato,
    p_motivazione, p_nota_interna,
    'E stata inviata un''ammonizione'
  );

  perform private.audit_registra(
    p_attore_id => (select auth.uid()),
    p_azione => 'ammonizione'::public.mod_action,
    p_target_tipo => v_report.target_tipo,
    p_target_id => private.moderazione_bersaglio(v_report),
    p_target_label => v_report.target_label,
    p_motivazione => p_motivazione,
    p_report_id => p_report_id
  );
end;
$$;

-- [4] sospensione. Su un profilo applica il provvedimento a due livelli; su un
-- annuncio lo sospende. Su un bersaglio di altro tipo resta la sola riga di
-- audit: sospendere un messaggio non significa nulla, e inventarne un
-- significato qui sarebbe funzionalita nuova.
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

-- [5] rimozione. Su un profilo e la rimozione completa, senza passare dal
-- primo livello: e l'azione piu grave e non e un secondo grado automatico.
-- Su un annuncio e `rifiutato`.
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

-- [6] ripristino. Riporta l'utente ad `attivo` (senza azzerare il contatore) o
-- l'annuncio ad `attivo`.
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

-- [7] chiusura - la segnalazione non ha seguito. La pratica finisce
-- `respinta`, che e l'unico esito che non implica un provvedimento.
create or replace function public.moderazione_chiusura(
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
begin
  v_report := private.moderazione_pratica(
    p_report_id,
    'respinta'::public.report_stato,
    p_motivazione, p_nota_interna,
    'La segnalazione e stata chiusa senza provvedimenti'
  );

  perform private.audit_registra(
    p_attore_id => (select auth.uid()),
    p_azione => 'chiusura'::public.mod_action,
    p_target_tipo => v_report.target_tipo,
    p_target_id => private.moderazione_bersaglio(v_report),
    p_target_label => v_report.target_label,
    p_motivazione => p_motivazione,
    p_report_id => p_report_id
  );
end;
$$;

-- ===========================================================================
-- PARTE H - il motivo del rifiuto, a righe proprie
-- ===========================================================================
--
-- `stato_motivo`, `stato_aggiornato_da` e `stato_aggiornato_at` sono fuori dal
-- GRANT di colonna di public.listings dalla 20260729230000 (riga 1015): non le
-- legge nessun ruolo client, proprietario compreso. Senza una proiezione, un
-- venditore vede il proprio annuncio passare a `rifiutato` e non puo sapere
-- perche.
--
-- La vista non allarga il GRANT su listings: stesso schema di my_reports della
-- 9a, security_invoker = off ed elenco di colonne chiuso.
-- `stato_aggiornato_da` non c'e: chi ha deciso e dato di moderazione, come
-- disputes.risolta_da, e vive nelle proiezioni del moderatore.

create or replace view public.my_listing_moderation
with (security_invoker = off, security_barrier = true) as
  select
    l.id as listing_id,
    l.slug,
    l.stato,
    l.stato_motivo,
    l.stato_aggiornato_at
  from public.listings l
  where l.seller_id = (select auth.uid())
    and l.stato_motivo is not null;

comment on view public.my_listing_moderation is
  'Il motivo dell''ultima transizione di stato, per i soli annunci del '
  'chiamante. Esiste perche stato_motivo non e nel GRANT di colonna di '
  'listings e senza questa proiezione un rifiuto sarebbe senza spiegazione. '
  'Non espone stato_aggiornato_da, che e dato di moderazione.';

-- ===========================================================================
-- PARTE I - privilegi
-- ===========================================================================

revoke all on public.my_listing_moderation from public, anon, authenticated;
grant select on public.my_listing_moderation to authenticated;

revoke execute on function
  private.profiles_stato_utente_guard(),
  private.scrittura_social_guard(),
  private.moderazione_attore(),
  private.utente_stato_di(uuid),
  private.moderazione_bersaglio(public.reports),
  private.moderazione_annuncio_transizione(
    uuid, uuid, public.listing_stato, public.mod_action, text,
    public.listing_stato[], uuid
  ),
  private.moderazione_utente_provvedimento(uuid, uuid, text, text, uuid, boolean),
  private.moderazione_utente_ripristina(uuid, uuid, text, uuid),
  private.moderazione_pratica(
    uuid, public.report_stato, text, text, text
  )
  from public, anon, authenticated;

-- Le sette azioni e le cinque porte sugli annunci: concesse ad `authenticated`
-- perche PostgREST possa invocarle, ma ciascuna verifica il ruolo admin al
-- proprio interno. Il GRANT e la porta, non il permesso.
revoke execute on function
  public.moderazione_info_richieste(uuid, text, text),
  public.moderazione_richiesta_modifiche(uuid, text, text),
  public.moderazione_ammonizione(uuid, text, text),
  public.moderazione_sospensione(uuid, text, text, text),
  public.moderazione_rimozione(uuid, text, text),
  public.moderazione_ripristino(uuid, text, text),
  public.moderazione_chiusura(uuid, text, text),
  public.moderazione_annuncio_in_revisione(uuid, text),
  public.moderazione_annuncio_modifiche_richieste(uuid, text),
  public.moderazione_annuncio_rifiuta(uuid, text),
  public.moderazione_annuncio_sospendi(uuid, text),
  public.moderazione_annuncio_ripristina(uuid, text)
  from public, anon;

grant execute on function
  public.moderazione_info_richieste(uuid, text, text),
  public.moderazione_richiesta_modifiche(uuid, text, text),
  public.moderazione_ammonizione(uuid, text, text),
  public.moderazione_sospensione(uuid, text, text, text),
  public.moderazione_rimozione(uuid, text, text),
  public.moderazione_ripristino(uuid, text, text),
  public.moderazione_chiusura(uuid, text, text),
  public.moderazione_annuncio_in_revisione(uuid, text),
  public.moderazione_annuncio_modifiche_richieste(uuid, text),
  public.moderazione_annuncio_rifiuta(uuid, text),
  public.moderazione_annuncio_sospendi(uuid, text),
  public.moderazione_annuncio_ripristina(uuid, text)
  to authenticated;

notify pgrst, 'reload schema';
