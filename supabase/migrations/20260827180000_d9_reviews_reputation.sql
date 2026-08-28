-- D9 - Recensioni e reputazione.
--
-- La fondazione esiste dalla 7c: `public.order_reviews` con UNIQUE(order_id),
-- le quattro dimensioni 1..5, il testo a 2000 e `ordine_recensisci` come unica
-- porta di scrittura. Questa migrazione NON crea un secondo sistema di
-- recensioni: estende quello, e aggiunge le tre cose che mancavano perche' una
-- recensione diventi reputazione pubblica.
--
-- [1] La regola di ammissibilita' scritta UNA VOLTA, in `private`, e letta sia
--     dalla porta di scrittura sia dal modello di lettura. Finche' vivevano in
--     due posti, «recensibile» in interfaccia e «recensibile» nel database
--     potevano divergere senza che nulla lo segnalasse.
--
-- [2] La proiezione pubblica. La 7c aveva scritto, sopra
--     `order_reviews_destinatario_idx`, che la vista di reputazione «NON esiste
--     in questa fase». L'indice era gia' quello giusto e viene usato ora.
--
-- [3] La risposta del destinatario. Una sola per recensione, dal solo
--     destinatario, derivato dalla riga e mai dal client.
--
-- CHE COSA NON C'E', E NON E' UNA DIMENTICANZA
--
-- Nessuna modifica o cancellazione di una recensione da parte di chi la scrive.
-- Nessun thread: `order_review_risposte` ha UNIQUE(review_id), quindi la forma
-- «commenti» non e' raggiungibile nemmeno per errore. Nessun pannello di
-- moderazione: `reports.target_review_id` e il ramo `recensione` di
-- `segnalazione_invia` esistono dalla 9a e dalla 12c e bastano - questa
-- migrazione non li tocca.
--
-- Nessun nuovo valore di `notification_destination_kind`: una recensione nasce
-- da un ordine, e `'order'` esiste dalla Fase 8. Aggiungere un'etichetta a un
-- enum in uso avrebbe richiesto due migrazioni invece di una, per la regola
-- ricordata dalla 12c.

-- ---------------------------------------------------------------------------
-- [1] La regola di ammissibilita', in un posto solo
-- ---------------------------------------------------------------------------
--
-- `completato` e' la finalita' canonica del ciclo di vita degli ordini: ci si
-- arriva da `ordine_conferma_ricezione` (7b), dal rilascio automatico e da una
-- contestazione chiusa con esito `risolta` (7f). Non viene inventato nulla di
-- nuovo, e non viene aggiunto nessuno stato.
--
-- `contestato_at is null` non e' ridondante benche' oggi `ordine_contesta`
-- sposti sempre anche `stato` a `contestato`. E' difesa in profondita' sulla
-- colonna che il resto del dominio tratta gia' come autorita': la 7c scrive che
-- «il flag resta l'autorita'» e su di esso filtrano `ordine_auto_rilascio_esegui`,
-- `payout_coda` e `payout_prepara`. Se un percorso futuro accendesse il flag
-- senza toccare lo stato, una recensione definitiva su una pratica aperta
-- resterebbe comunque impossibile.

create or replace function private.recensione_ammessa(
  p_stato public.order_stato,
  p_contestato_at timestamptz
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_stato = 'completato'::public.order_stato
     and p_contestato_at is null;
$$;

comment on function private.recensione_ammessa(public.order_stato, timestamptz) is
  'Ordine concluso in modo definitivo e senza contestazione aperta. Unica '
  'definizione di «recensibile» del repository: la legge la porta di scrittura '
  'ordine_recensisci e la legge il modello di lettura ordini_recensibili, '
  'quindi interfaccia e database non possono divergere.';

-- ---------------------------------------------------------------------------
-- [2] La risposta del destinatario
-- ---------------------------------------------------------------------------
--
-- UNIQUE(review_id) e' la forma del dominio, non un vincolo di comodo: una
-- recensione ha al massimo una replica. Non c'e' `parent_id`, non c'e'
-- `autore_ruolo`, non c'e' nulla che permetta di costruirci sopra una
-- discussione.
--
-- `autore_id` esiste benche' sia sempre uguale a `order_reviews.destinatario_id`:
-- e' cio' che rende la riga leggibile da sola e verificabile da un vincolo, e la
-- funzione che scrive lo deriva dalla recensione - mai dal chiamante.

create table public.order_review_risposte (
  id         uuid primary key default gen_random_uuid(),
  review_id  uuid not null unique
    references public.order_reviews (id) on delete cascade,
  autore_id  uuid not null references public.profiles (id) on delete restrict,
  testo      text not null
    check (testo = btrim(testo) and length(testo) between 1 and 1000),
  created_at timestamptz not null default now()
);

comment on table public.order_review_risposte is
  'Replica pubblica del destinatario a una recensione. Una per recensione '
  '(UNIQUE), scritta solo da public.recensione_rispondi, che deriva l''autore '
  'dalla recensione. Nessun GRANT di scrittura verso i ruoli client.';

create index order_review_risposte_autore_idx
  on public.order_review_risposte (autore_id, created_at desc);

alter table public.order_review_risposte enable row level security;
revoke all on public.order_review_risposte from public, anon, authenticated;

-- Lettura alle sole parti dell'ordine, esattamente come `order_reviews`: e' cio'
-- che serve alla pagina dell'ordine. Il pubblico legge le repliche da
-- `recensioni_pubbliche_elenco`, che non passa da qui.
grant select on public.order_review_risposte to authenticated;

create policy order_review_risposte_participants_select
  on public.order_review_risposte for select to authenticated
  using (exists (
    select 1
    from public.order_reviews r
    join public.orders o on o.id = r.order_id
    where r.id = review_id
      and (select auth.uid()) in (o.buyer_id, o.seller_id)
  ));

-- ---------------------------------------------------------------------------
-- [3] La porta di scrittura della recensione, indurita
-- ---------------------------------------------------------------------------
--
-- Rispetto alla 7c cambiano tre cose e nessun contratto:
--
-- (a) `for update` sulla riga dell'ordine. Due richieste concorrenti sullo
--     stesso ordine si serializzano qui, quindi il controllo «esiste gia' una
--     recensione» e l'INSERT non possono piu' intrecciarsi. La UNIQUE resta la
--     difesa definitiva e ora ha anche un gestore: chi perde la corsa riceve lo
--     stesso P0001 di chi arriva secondo un minuto dopo, non un 23505 grezzo.
--
-- (b) l'ammissibilita' passa da `private.recensione_ammessa`.
--
-- (c) la notifica al destinatario, idempotente per costruzione.

create or replace function public.ordine_recensisci(
  p_order_id      uuid,
  p_voto          smallint,
  p_conformita    smallint,
  p_imballaggio   smallint,
  p_comunicazione smallint,
  p_testo         text default null
)
returns public.order_reviews
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_review public.order_reviews%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  perform private.rate_limit_consume('order:review', 'user:' || v_uid::text, 10, 60);

  if p_voto not between 1 and 5 or p_conformita not between 1 and 5
     or p_imballaggio not between 1 and 5 or p_comunicazione not between 1 and 5 then
    raise exception 'Punteggio fuori scala.' using errcode = '22023';
  end if;
  if p_testo is not null and length(p_testo) > 2000 then
    raise exception 'Testo della recensione troppo lungo.' using errcode = '22023';
  end if;

  -- (a) La riga si blocca prima di essere letta: da qui in poi nessun'altra
  -- transazione puo' attraversare lo stesso controllo sullo stesso ordine.
  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.buyer_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;

  -- Il compratore non e' il venditore per `orders_parti_distinte`, quindi
  -- l'autorecensione non e' raggiungibile: `destinatario_id` viene da
  -- `v_order.seller_id` e `order_reviews_parti_distinte` la rifiuterebbe
  -- comunque. Nessuna delle due colonne arriva dal client.
  if not private.recensione_ammessa(v_order.stato, v_order.contestato_at) then
    raise exception 'Si recensisce solo un ordine concluso e senza contestazione aperta.'
      using errcode = 'P0001';
  end if;

  if exists (select 1 from public.order_reviews r where r.order_id = p_order_id) then
    raise exception 'Questo ordine e gia stato recensito.' using errcode = 'P0001';
  end if;

  begin
    insert into public.order_reviews (
      order_id, autore_id, destinatario_id,
      voto, conformita, imballaggio, comunicazione, testo
    ) values (
      p_order_id, v_uid, v_order.seller_id,
      p_voto, p_conformita, p_imballaggio, p_comunicazione,
      nullif(btrim(coalesce(p_testo, '')), '')
    ) returning * into v_review;
  exception when unique_violation then
    -- La UNIQUE resta l'ultima parola. Tradurla nello stesso errore del
    -- controllo sopra rende il risultato deterministico: chi ritenta non
    -- distingue «esisteva gia'» da «e' arrivato un istante prima di me».
    raise exception 'Questo ordine e gia stato recensito.' using errcode = 'P0001';
  end;

  -- (c) Il venditore viene avvisato. `dedupe_key` e' la recensione, che e' unica
  -- per ordine: un replay non produce una seconda notifica.
  insert into public.notifications (
    recipient_id, category, event_type, body, dedupe_key,
    destination_kind, destination_order_id
  ) values (
    v_review.destinatario_id,
    'marketplace',
    'review_received',
    'Hai ricevuto una nuova recensione.',
    'review:' || v_review.id::text,
    'order',
    p_order_id
  )
  on conflict (recipient_id, dedupe_key) do nothing;

  return v_review;
end;
$$;

comment on function public.ordine_recensisci(uuid, smallint, smallint, smallint, smallint, text) is
  'Unica porta di scrittura di una recensione. Autore e destinatario sono '
  'derivati dall''ordine, mai ricevuti dal chiamante. Una sola recensione per '
  'ordine, garantita dal blocco di riga e dalla UNIQUE. Avvisa il destinatario '
  'con una notifica deduplicata sulla recensione.';

revoke execute on function
  public.ordine_recensisci(uuid, smallint, smallint, smallint, smallint, text)
  from public, anon;
grant execute on function
  public.ordine_recensisci(uuid, smallint, smallint, smallint, smallint, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- [4] La porta di scrittura della replica
-- ---------------------------------------------------------------------------
--
-- Stessa forma della recensione: blocco di riga, identita' derivata, UNIQUE come
-- difesa definitiva, notifica deduplicata.
--
-- Il blocco e' sulla RECENSIONE e non sull'ordine, perche' e' la recensione ad
-- avere al massimo una replica.

create or replace function public.recensione_rispondi(
  p_review_id uuid,
  p_testo     text
)
returns public.order_review_risposte
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_review public.order_reviews%rowtype;
  v_risposta public.order_review_risposte%rowtype;
  v_testo text := btrim(coalesce(p_testo, ''));
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  perform private.rate_limit_consume('review:reply', 'user:' || v_uid::text, 10, 60);

  if length(v_testo) not between 1 and 1000 then
    raise exception 'La risposta deve avere fra 1 e 1000 caratteri.'
      using errcode = '22023';
  end if;

  select * into v_review from public.order_reviews where id = p_review_id for update;
  -- «Non trovata» e «non e' tua» sono lo stesso messaggio: distinguerli direbbe
  -- a un estraneo che quell'identificativo esiste.
  if not found or v_review.destinatario_id <> v_uid then
    raise exception 'Recensione non trovata.' using errcode = '42501';
  end if;

  if exists (
    select 1 from public.order_review_risposte rr where rr.review_id = p_review_id
  ) then
    raise exception 'Hai gia risposto a questa recensione.' using errcode = 'P0001';
  end if;

  begin
    insert into public.order_review_risposte (review_id, autore_id, testo)
    values (p_review_id, v_uid, v_testo)
    returning * into v_risposta;
  exception when unique_violation then
    raise exception 'Hai gia risposto a questa recensione.' using errcode = 'P0001';
  end;

  -- L'autore della recensione viene avvisato, sull'ordine da cui la recensione
  -- e' nata: e' la superficie dove la vede.
  insert into public.notifications (
    recipient_id, category, event_type, body, dedupe_key,
    destination_kind, destination_order_id
  ) values (
    v_review.autore_id,
    'marketplace',
    'review_reply_received',
    'Hai ricevuto una risposta alla tua recensione.',
    'review-reply:' || v_risposta.id::text,
    'order',
    v_review.order_id
  )
  on conflict (recipient_id, dedupe_key) do nothing;

  return v_risposta;
end;
$$;

comment on function public.recensione_rispondi(uuid, text) is
  'Replica del destinatario a una recensione. Il chiamante deve essere '
  'order_reviews.destinatario_id, letto dalla riga: l''autore non e un '
  'parametro. Una sola replica per recensione. Avvisa l''autore della '
  'recensione con una notifica deduplicata sulla replica.';

revoke execute on function public.recensione_rispondi(uuid, text) from public, anon;
grant execute on function public.recensione_rispondi(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- [5] Il modello di lettura dell'ammissibilita', per il proprietario
-- ---------------------------------------------------------------------------
--
-- Il browser non deve ricostruire la regola: la chiede. Una sola chiamata
-- copre tutti gli ordini di chi la fa - stessa cardinalita' dell'elenco di
-- `/acquisti`, quindi nessun N+1 e nessuna chiamata per riga.
--
-- `security definer` con il filtro `buyer_id = auth.uid()` scritto dentro: non
-- c'e' parametro con cui chiedere gli ordini di qualcun altro, quindi non c'e'
-- enumerazione. `stable`, perche' non scrive.
--
-- `motivo` e' grossolano di proposito. I tre valori dicono a chi guarda perche'
-- non c'e' il bottone, e nessuno di essi e' un dato che il compratore non abbia
-- gia': lo stato del proprio ordine lo legge dalla riga.

create or replace function public.ordini_recensibili()
returns table (
  order_id         uuid,
  eligible         boolean,
  already_reviewed boolean,
  review_id        uuid,
  motivo           text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    o.id,
    private.recensione_ammessa(o.stato, o.contestato_at) and r.id is null,
    r.id is not null,
    r.id,
    case
      when r.id is not null then 'gia_recensito'
      when o.contestato_at is not null
        or o.stato = 'contestato'::public.order_stato then 'contestato'
      when private.recensione_ammessa(o.stato, o.contestato_at) then 'recensibile'
      else 'non_concluso'
    end
  from public.orders o
  left join public.order_reviews r on r.order_id = o.id
  where o.buyer_id = (select auth.uid());
$$;

comment on function public.ordini_recensibili() is
  'Ammissibilita di recensione per gli ordini di CHI CHIAMA, in una sola '
  'lettura. Nessun parametro: non esiste modo di chiedere gli ordini di terzi. '
  'Non espone alcun campo privato dell''ordine - solo identificativo, i due '
  'booleani, l''identificativo della recensione e un motivo grossolano.';

revoke execute on function public.ordini_recensibili() from public, anon;
grant execute on function public.ordini_recensibili() to authenticated;

-- ---------------------------------------------------------------------------
-- [6] La proiezione pubblica delle recensioni
-- ---------------------------------------------------------------------------
--
-- Stessa forma di `private.profili_pubblici`: vista `security_invoker = off` a
-- colonne dichiarate una per una, nello schema `private` perche' PostgREST non
-- deve arrivarci - sarebbe l'elenco di tutte le recensioni della piattaforma.
-- Si legge solo attraverso le due funzioni sotto.
--
-- L'ELENCO CHIUSO. Escono: identificativo della recensione, i quattro
-- punteggi, il testo, la data, l'identita' pubblica dell'autore e l'eventuale
-- replica. NON esce `order_id`, e non e' un filtro da ricordarsi di applicare:
-- la colonna non c'e' nella vista. Con essa restano fuori prezzi, commissioni,
-- payout, indirizzi, pagamenti, rimborsi e contestazioni, che stanno tutti su
-- tabelle che questa vista non nomina.
--
-- 7.6b in entrambe le direzioni, come `profili_pubblici`: una recensione scritta
-- da chi e' stato rimosso non e' pubblica, quella ricevuta da chi e' stato
-- rimosso nemmeno - il suo profilo non esiste piu' - e un chiamante rimosso non
-- legge questa superficie.

create view private.recensioni_pubbliche
with (security_invoker = off, security_barrier = true)
as
select
  r.id              as review_id,
  r.destinatario_id,
  r.voto,
  r.conformita,
  r.imballaggio,
  r.comunicazione,
  r.testo,
  r.created_at,
  a.id              as autore_id,
  a.username        as autore_username,
  a.avatar_url      as autore_avatar_url,
  rr.testo          as risposta_testo,
  rr.created_at     as risposta_created_at
from public.order_reviews r
join public.profiles a on a.id = r.autore_id
join public.profiles d on d.id = r.destinatario_id
left join public.order_review_risposte rr on rr.review_id = r.id
where a.stato_utente <> 'rimosso'::public.utente_stato
  and d.stato_utente <> 'rimosso'::public.utente_stato
  and not exists (
    select 1 from public.profiles me
    where me.id = (select auth.uid())
      and me.stato_utente = 'rimosso'::public.utente_stato
  );

comment on view private.recensioni_pubbliche is
  'Recensioni pubblicamente visibili, con l''elenco chiuso delle colonne '
  'ammesse e l''identita pubblica dell''autore. Sta in `private` perche non '
  'deve essere raggiungibile da PostgREST: sarebbe l''elenco di tutte le '
  'recensioni della piattaforma. Non contiene order_id, quindi nessun dato '
  'dell''ordine puo trapelare da qui.';

revoke all on private.recensioni_pubbliche from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [7] L'aggregato pubblico
-- ---------------------------------------------------------------------------
--
-- SEMANTICA DELLO ZERO. Con nessuna recensione il conteggio e' 0 e le quattro
-- medie sono NULL, non 0. Una media di zero su cinque e' un giudizio pessimo, e
-- mostrarlo a chi non e' mai stato recensito sarebbe affermare qualcosa che
-- nessuno ha misurato. `avg()` su un insieme vuoto restituisce NULL da solo:
-- non c'e' un `coalesce` da NON scrivere, c'e' un `coalesce` da non aggiungere.
--
-- Le medie sono calcolate qui e non nel browser: sono l'aggregato di righe che
-- il browser non ha e non deve avere, e ricalcolarle da una pagina di dieci
-- recensioni darebbe un numero diverso a ogni scorrimento.

create or replace function public.reputazione_pubblica(p_user_id uuid)
returns table (
  recensioni_totali    integer,
  media_voto           numeric,
  media_conformita     numeric,
  media_imballaggio    numeric,
  media_comunicazione  numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    count(*)::integer,
    round(avg(v.voto)::numeric, 2),
    round(avg(v.conformita)::numeric, 2),
    round(avg(v.imballaggio)::numeric, 2),
    round(avg(v.comunicazione)::numeric, 2)
  from private.recensioni_pubbliche v
  where v.destinatario_id = p_user_id;
$$;

comment on function public.reputazione_pubblica(uuid) is
  'Aggregato pubblico di reputazione di UNA persona. Con zero recensioni '
  'restituisce conteggio 0 e quattro medie NULL: l''assenza di misura non '
  'diventa un voto. Le medie sono autoritative qui, non ricalcolabili dal '
  'client, che non ha le righe.';

revoke all on function public.reputazione_pubblica(uuid) from public;
grant execute on function public.reputazione_pubblica(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- [8] L'elenco pubblico, paginato
-- ---------------------------------------------------------------------------
--
-- Ordinamento su `(created_at desc, review_id desc)`: la seconda chiave rende
-- l'ordine totale, quindi due recensioni nello stesso istante non possono
-- scambiarsi di posto fra una pagina e la successiva e comparire due volte o
-- sparire. L'indice `order_reviews_destinatario_idx` della 7c serve esattamente
-- questa lettura.
--
-- Il limite e' tagliato a 50 nel corpo: un parametro che arriva dal browser non
-- decide quanto lavoro fa il database.

create or replace function public.recensioni_pubbliche_elenco(
  p_user_id uuid,
  p_limit   integer default 10,
  p_offset  integer default 0
)
returns table (
  review_id           uuid,
  voto                smallint,
  conformita          smallint,
  imballaggio         smallint,
  comunicazione       smallint,
  testo               text,
  created_at          timestamptz,
  autore_id           uuid,
  autore_username     text,
  autore_avatar_url   text,
  risposta_testo      text,
  risposta_created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    v.review_id, v.voto, v.conformita, v.imballaggio, v.comunicazione,
    v.testo, v.created_at,
    v.autore_id, v.autore_username, v.autore_avatar_url,
    v.risposta_testo, v.risposta_created_at
  from private.recensioni_pubbliche v
  where v.destinatario_id = p_user_id
  order by v.created_at desc, v.review_id desc
  limit least(greatest(coalesce(p_limit, 10), 1), 50)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

comment on function public.recensioni_pubbliche_elenco(uuid, integer, integer) is
  'Pagina di recensioni pubbliche ricevute da UNA persona. Ordine totale su '
  '(created_at desc, review_id desc), quindi la paginazione e stabile. Limite '
  'tagliato a 50 nel corpo. Nessuna colonna dell''ordine: la vista sorgente non '
  'ne contiene.';

revoke all on function public.recensioni_pubbliche_elenco(uuid, integer, integer) from public;
grant execute on function public.recensioni_pubbliche_elenco(uuid, integer, integer)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- [9] La reputazione dentro il profilo pubblico gia' esistente
-- ---------------------------------------------------------------------------
--
-- Non nasce una seconda pagina profilo e non nasce una seconda chiamata: il
-- riepilogo arriva nella STESSA riga che la pagina legge gia'. L'elenco delle
-- recensioni resta separato perche' e' paginato, come lo sono gli annunci
-- attivi per la loro ragione.
--
-- Vale la nota della 20260827160500: `create or replace function` non puo'
-- cambiare il tipo di ritorno di una funzione `returns table (...)`, quindi il
-- DROP e' obbligato e i GRANT vanno riscritti. Le nove colonne gia' in
-- contratto restano identiche, nello stesso ordine e con gli stessi tipi; le
-- due nuove si aggiungono in coda.
--
-- `recensioni_medie` e' un jsonb NULL quando non c'e' nessuna recensione, e non
-- un oggetto di zeri: e' la stessa scelta di [7], portata fin dove la pagina la
-- legge. `recensioni_totali` e' invece sempre un numero, 0 compreso - «nessuna
-- recensione» e' un fatto misurato, a differenza di una media che non esiste.

drop function if exists public.profilo_pubblico(uuid);

create function public.profilo_pubblico(p_user_id uuid)
returns table (
  user_id uuid,
  username text,
  bio text,
  citta text,
  provincia text,
  esperienza text,
  avatar_url text,
  professionista_verificato boolean,
  qualifiche_professionali jsonb,
  recensioni_totali integer,
  recensioni_medie jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    v.user_id,
    v.username,
    v.bio,
    v.citta,
    v.provincia,
    v.esperienza,
    v.avatar_url,
    exists (
      select 1
      from private.qualifiche_professionali_valide q
      where q.user_id = v.user_id
    ) as professionista_verificato,
    coalesce(
      (
        select jsonb_agg(
                 jsonb_build_object(
                   'titolo', q.titolo,
                   'ente_emittente', q.ente_emittente,
                   'paese', q.paese,
                   'issued_on', q.issued_on,
                   'expires_on', q.expires_on
                 )
                 order by q.issued_on desc nulls last, q.titolo
               )
        from private.qualifiche_professionali_valide q
        where q.user_id = v.user_id
      ),
      '[]'::jsonb
    ) as qualifiche_professionali,
    rep.recensioni_totali,
    -- NULL, non un oggetto di zeri: con zero recensioni non c'e' nessuna media
    -- da mostrare, e inventarne una a 0/5 sarebbe un giudizio.
    case
      when rep.recensioni_totali > 0 then jsonb_build_object(
        'voto', rep.media_voto,
        'conformita', rep.media_conformita,
        'imballaggio', rep.media_imballaggio,
        'comunicazione', rep.media_comunicazione
      )
    end as recensioni_medie
  from private.profili_pubblici v
  cross join lateral public.reputazione_pubblica(v.user_id) rep
  where v.user_id = p_user_id;
$$;

comment on function public.profilo_pubblico(uuid) is
  'Profilo pubblico di una persona. Le nove colonne del contratto precedente '
  'restano invariate; in coda arrivano il numero di recensioni ricevute e le '
  'quattro medie, NULL quando non ce ne sono. Le recensioni in se sono '
  'paginate a parte da recensioni_pubbliche_elenco. Una riga per uuid: nessun '
  'N+1 e nessuna sonda su terzi.';

revoke all on function public.profilo_pubblico(uuid) from public;
grant execute on function public.profilo_pubblico(uuid) to anon, authenticated;

notify pgrst, 'reload schema';
