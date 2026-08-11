-- ===========================================================================
-- Fase 10b — lo storico del Sommelier
-- ===========================================================================
--
-- Decisione 7.2 = A, 11 agosto 2026: lo storico vive in una tabella Postgres.
-- La motivazione registrata è di prodotto — un consulente a cui si torna a
-- parlare deve ricordare la conversazione — e nessuna persistenza sarebbe stata
-- un peggioramento rispetto a `frontend/`, dove lo storico sopravvive alla
-- ricarica.
--
-- Il modello da riprodurre è `MongoChatRepository` (`backend/repositories.py:189-230`),
-- che realizza tre requisiti in tre righe:
--
--   * ownership       indice unico `(owner_id, session_id)`        (`:194`)
--   * tetto messaggi  `$push` con `$slice: -max_messages`          (`:223`)
--   * TTL             indice `expireAfterSeconds=0` su expires_at  (`:195`)
--
-- Postgres non ha l'equivalente del terzo, e `pg_cron` è **escluso** dalla
-- decisione 1a della Fase 7d — escluso, non rinviato.
--
-- ---------------------------------------------------------------------------
-- COME SI APPLICA IL TTL, e perché è scritto qui invece che sottinteso
-- ---------------------------------------------------------------------------
--
-- Deciso l'11 agosto 2026: **scadenza applicata in lettura**. La vista filtra su
-- `expires_at`, e per il v0 **non esiste nessuna cancellazione fisica**.
--
-- Va detto per esteso, perché è la parte scomoda della decisione: **le righe
-- scadute restano in tabella.** Non vengono più lette da nessuno — né dal
-- proprietario né dalla function, che legge la stessa vista — ma occupano spazio
-- finché non arriverà una pulizia che oggi nessuno ha scritto. È una decisione
-- consapevole, non un buco: delle tre strade praticabili è l'unica la cui
-- obiezione si può **dichiarare** invece di subirla. La cancellazione
-- opportunistica alla scrittura non scade mai una conversazione abbandonata,
-- cioè esattamente il caso che un TTL dovrebbe coprire; un secondo job GitHub
-- Actions aggiungerebbe uno schedulatore a uno che è a 18 run su 18 in
-- `failure`. Aggiungere la pulizia più avanti non cambia questo schema.
--
-- ---------------------------------------------------------------------------
-- ESPOSIZIONE
-- ---------------------------------------------------------------------------
--
-- Le tre regole vincolanti dalla 6d-1 si applicano tutte:
--
--   * nessun `GRANT` di lettura sulla tabella base, a nessun ruolo client. RLS
--     è accesa **senza policy**, quindi la tabella è chiusa a `anon` e
--     `authenticated` come lo sono `reports`, `report_events` e `audit_log`;
--   * la lettura passa da una vista `security_invoker = off` a colonne chiuse,
--     dove il filtro è scritto dentro e nessun client può allargarlo;
--   * la scrittura ha una regola di dominio dietro — tetto messaggi, scadenza,
--     proprietario — quindi non è scrivibile dal client e ottiene delle
--     `SECURITY DEFINER` come unica porta.
--
-- Il filtro della vista è su **(owner_id, session_id)** e mai sul solo
-- `session_id`. Non è un dettaglio: il `session_id` lo sceglie il client — è un
-- `Math.random()` in `localStorage` (`frontend/src/components/vinea/SommelierChat.tsx:12-25`)
-- — quindi indovinarne uno è alla portata di chiunque. `owner_id` viene invece
-- da `auth.uid()` dentro la vista, dove il client non arriva.

set local check_function_bodies = off;

-- ---------------------------------------------------------------------------
-- Parametri, dagli stessi valori del legacy
-- ---------------------------------------------------------------------------
-- `SOMMELIER_MAX_MESSAGES=100`, `SOMMELIER_HISTORY_TTL_DAYS=30`
-- (`backend/.env.example:34-35`). Sono costanti nel corpo delle funzioni e non
-- colonne di configurazione: cambiarli è una migrazione, che è esattamente il
-- grado di attrito che meritano.

create type public.sommelier_ruolo as enum ('utente', 'sommelier');

create table public.sommelier_messaggi (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references auth.users(id) on delete cascade,
  -- Stessi estremi e stesso alfabeto di `ChatRequest.session_id`
  -- (`backend/ai_routes.py:43`): il vincolo è nel database e non solo nel
  -- validatore, perché la porta di scrittura è raggiungibile anche da
  -- `service_role`.
  session_id  text not null
    check (session_id ~ '^[A-Za-z0-9_-]{4,64}$'),
  ruolo       public.sommelier_ruolo not null,
  -- 2000 per il messaggio dell'utente (`backend/ai_routes.py:44`), 8000 per la
  -- risposta (`SOMMELIER_MAX_RESPONSE_CHARS`): il tetto della colonna è il più
  -- alto dei due, quello per ruolo lo applica la porta di scrittura.
  contenuto   text not null
    check (length(contenuto) between 1 and 8000),
  created_at  timestamptz not null default now(),
  -- L'ordine della conversazione, e la ragione per cui non basta `created_at`.
  -- Le due righe di uno scambio nascono nella stessa istruzione, quindi hanno
  -- lo **stesso** `now()`: ordinare per tempo lascerebbe indeterminato se la
  -- domanda venga prima della risposta, e un pareggio spezzato dall'uuid
  -- casuale della chiave primaria e' peggio che indeterminato — e' variabile.
  -- Lo stesso pareggio rende non deterministico quali righe cadono quando
  -- scatta il tetto. Una identity monotona chiude entrambe le cose.
  ordinale    bigint generated always as identity,
  -- Non `default`: lo scrive la porta, che è l'unica che conosce la finestra.
  expires_at  timestamptz not null
);

comment on table public.sommelier_messaggi is
  'Fase 10b. Storico della chat Sommelier. Chiusa a ogni ruolo client: si legge '
  'da public.my_sommelier_messages e si scrive dalle sole porte SECURITY DEFINER. '
  'Le righe con expires_at nel passato non sono piu leggibili ma NON vengono '
  'cancellate: nel v0 non esiste pulizia fisica, per decisione dell 11 agosto 2026.';

-- L'equivalente dell'indice unico Mongo su `(owner_id, session_id)`: qui non è
-- unico perché una conversazione è più righe, ma è la chiave di accesso di ogni
-- lettura e di ogni scrittura.
create index sommelier_messaggi_conversazione_idx
  on public.sommelier_messaggi (owner_id, session_id, ordinale);

-- Serve alla pulizia futura, quando arriverà: senza, sarebbe una scansione
-- completa su una tabella che per costruzione non viene mai potata.
create index sommelier_messaggi_expires_idx
  on public.sommelier_messaggi (expires_at);

alter table public.sommelier_messaggi enable row level security;
alter table public.sommelier_messaggi force row level security;

-- Nessuna policy, di proposito: RLS accesa e senza policy significa chiusa a
-- ogni ruolo client. È la forma già adottata dalla 9a per `reports`,
-- `report_events` e `audit_log`.
revoke all on public.sommelier_messaggi from anon, authenticated;

-- ---------------------------------------------------------------------------
-- La lettura: vista a colonne chiuse, filtro dentro
-- ---------------------------------------------------------------------------
--
-- `owner_id` non compare fra le colonne esposte: è il filtro, non un dato da
-- restituire, e una colonna che non esce non può essere confrontata da un
-- client per scoprire di chi è una conversazione.

create view public.my_sommelier_messages
with (security_invoker = off, security_barrier = true)
as
select
  m.session_id,
  m.ruolo,
  m.contenuto,
  m.created_at,
  -- Esposto di proposito: e' la sola colonna con cui il client puo' ordinare
  -- la conversazione senza ambiguita', perche' `created_at` pareggia dentro
  -- ogni scambio.
  m.ordinale
from public.sommelier_messaggi m
where m.owner_id = (select auth.uid())
  -- Il TTL, applicato qui e in nessun altro posto.
  and m.expires_at > now()
  -- Decisione 7.9: il secondo provvedimento della 7.6b toglie anche la visione,
  -- e il Sommelier è una superficie di consultazione. Stessa forma di predicato
  -- della 9c (`supabase/migrations/20260810210000_phase_9_rimosso_blocca_commercio.sql:166-170`).
  -- Il primo provvedimento — `sospeso` — non compare: blocca le sole scritture
  -- social e non tocca l'AI.
  and not exists (
    select 1
    from public.profiles me
    where me.id = (select auth.uid())
      and me.stato_utente = 'rimosso'
  );

comment on view public.my_sommelier_messages is
  'Fase 10b. Storico della propria chat Sommelier, filtrato su (owner_id, session_id): '
  'owner_id viene da auth.uid() dentro la vista e non e esposto. Applica anche il TTL '
  'e il secondo provvedimento della 7.6b.';

revoke all on public.my_sommelier_messages from anon, authenticated;
-- Solo `authenticated`: un anonimo non ha uno storico, e dargli il `GRANT`
-- significherebbe fargli restituire zero righe invece di un errore, cioè
-- nascondere un difetto di configurazione.
grant select on public.my_sommelier_messages to authenticated;

-- ---------------------------------------------------------------------------
-- La lettura della function: una porta a parte, non la vista
-- ---------------------------------------------------------------------------
--
-- `ai-sommelier` deve rileggere le ultime battute per costruire il contesto,
-- ma con il client di servizio `auth.uid()` è nullo: la vista restituirebbe
-- zero righe, e una conversazione senza memoria sarebbe un difetto silenzioso —
-- funziona, risponde, e ha perso il punto della decisione 7.2.
--
-- Perché una porta e non `select` diretta sulla tabella: la tabella base è
-- leggibile da `service_role` solo per via delle default privileges del
-- progetto, cioè per una configurazione che vive fuori da questi file. Una
-- funzione concessa esplicitamente dice chi legge, e continua a dirlo se quelle
-- default privileges cambiano.
--
-- Applica lo stesso TTL della vista: la function non deve poter leggere righe
-- che al proprietario sono già scadute.

create or replace function private.sommelier_contesto_leggi(
  p_owner_id   uuid,
  p_session_id text,
  p_limite     integer
)
returns table (ruolo public.sommelier_ruolo, contenuto text, created_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select m.ruolo, m.contenuto, m.created_at
  from (
    select m2.ruolo, m2.contenuto, m2.created_at, m2.ordinale
    from public.sommelier_messaggi m2
    where m2.owner_id = p_owner_id
      and m2.session_id = p_session_id
      and m2.expires_at > now()
    order by m2.ordinale desc
    limit greatest(coalesce(p_limite, 12), 0)
  ) m
  order by m.ordinale asc;
$$;

create or replace function public.sommelier_contesto_leggi(
  p_owner_id   uuid,
  p_session_id text,
  p_limite     integer
)
returns table (ruolo public.sommelier_ruolo, contenuto text, created_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select * from private.sommelier_contesto_leggi($1, $2, $3);
$$;

revoke execute on function public.sommelier_contesto_leggi(uuid, text, integer)
  from public, anon, authenticated;
grant execute on function public.sommelier_contesto_leggi(uuid, text, integer)
  to service_role;

-- ---------------------------------------------------------------------------
-- La scrittura: la porta della Edge Function
-- ---------------------------------------------------------------------------
--
-- Chi chiama è `ai-sommelier` con il client di servizio, perché è l'unico punto
-- che ha lo stream concluso. `auth.uid()` lì è nullo, quindi il proprietario è
-- un parametro — ed è per questo che la funzione è concessa a `service_role` e
-- a nessun altro, esattamente come `public.rate_limit_consume`
-- (`supabase/migrations/20260731135455_phase_7_order_payment_service.sql:157-160`).
--
-- Registra **lo scambio**, non il singolo messaggio, perché è così che il
-- legacy tiene la coppia coerente (`backend/repositories.py:204-227`): o entrano
-- entrambi o non entra niente.

create or replace function private.sommelier_scambio_registra(
  p_owner_id   uuid,
  p_session_id text,
  p_domanda    text,
  p_risposta   text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_max_messaggi constant integer := 100;   -- SOMMELIER_MAX_MESSAGES
  v_ttl          constant interval := interval '30 days';  -- SOMMELIER_HISTORY_TTL_DAYS
  v_scadenza     timestamptz := now() + v_ttl;
  v_domanda      text := btrim(coalesce(p_domanda, ''));
  v_risposta     text := btrim(coalesce(p_risposta, ''));
  v_totale       integer;
begin
  if p_owner_id is null then
    raise exception 'Proprietario richiesto.' using errcode = '22023';
  end if;
  if p_session_id !~ '^[A-Za-z0-9_-]{4,64}$' then
    raise exception 'Identificativo di sessione non valido.' using errcode = '22023';
  end if;
  if length(v_domanda) = 0 or length(v_domanda) > 2000 then
    raise exception 'Messaggio non valido.' using errcode = '22023';
  end if;
  if length(v_risposta) = 0 or length(v_risposta) > 8000 then
    raise exception 'Risposta non valida.' using errcode = '22023';
  end if;

  -- Decisione 7.9, secondo punto di controllo. Il primo è nella Edge Function,
  -- dove l'identità è appena stata stabilita; questo esiste perché un controllo
  -- che vive solo nel codice applicativo è un controllo che si perde alla
  -- prossima porta che qualcuno aggiunge.
  if exists (
    select 1 from public.profiles p
    where p.id = p_owner_id and p.stato_utente = 'rimosso'
  ) then
    raise exception 'Accesso non consentito.' using errcode = '42501';
  end if;

  insert into public.sommelier_messaggi (owner_id, session_id, ruolo, contenuto, expires_at)
  values
    (p_owner_id, p_session_id, 'utente',    v_domanda,  v_scadenza),
    (p_owner_id, p_session_id, 'sommelier', v_risposta, v_scadenza);

  -- Come `$set: {expires_at: ...}` sul documento intero: usare la conversazione
  -- la tiene viva tutta, non solo le ultime due righe. Senza, la coda scadrebbe
  -- sotto una conversazione ancora in corso.
  update public.sommelier_messaggi
     set expires_at = v_scadenza
   where owner_id = p_owner_id
     and session_id = p_session_id
     and expires_at <> v_scadenza;

  -- L'equivalente di `$slice: -max_messages` (`backend/repositories.py:223`):
  -- si tengono le ultime `v_max_messaggi` e si cancellano le più vecchie.
  --
  -- L'ordine è `ordinale` e non `created_at`, ed è una correzione che solo
  -- l'esecuzione della griglia ha trovato: le due righe di uno scambio nascono
  -- nella stessa istruzione, quindi condividono `now()`, e in un caso di prova
  -- che scriveva sessanta scambi in una transazione sola **tutte e centoventi**
  -- le righe avevano lo stesso istante. Il pareggio veniva spezzato dall'uuid
  -- casuale della chiave primaria, quindi le venti righe cancellate erano un
  -- sottoinsieme arbitrario invece delle venti più vecchie — e uno scambio
  -- poteva restare monco, con la risposta senza la sua domanda.
  delete from public.sommelier_messaggi m
   where m.owner_id = p_owner_id
     and m.session_id = p_session_id
     and m.ordinale not in (
       select m2.ordinale
       from public.sommelier_messaggi m2
       where m2.owner_id = p_owner_id
         and m2.session_id = p_session_id
       order by m2.ordinale desc
       limit v_max_messaggi
     );

  select count(*) into v_totale
  from public.sommelier_messaggi m
  where m.owner_id = p_owner_id and m.session_id = p_session_id;
  return v_totale;
end;
$$;

create or replace function public.sommelier_scambio_registra(
  p_owner_id   uuid,
  p_session_id text,
  p_domanda    text,
  p_risposta   text
)
returns integer
language sql
security definer
set search_path = ''
as $$
  select private.sommelier_scambio_registra($1, $2, $3, $4);
$$;

revoke execute on function public.sommelier_scambio_registra(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.sommelier_scambio_registra(uuid, text, text, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- La cancellazione: la porta del browser
-- ---------------------------------------------------------------------------
--
-- Questa invece la chiama il proprietario, quindi prende il proprio
-- identificativo da `auth.uid()` e non lo accetta come parametro. È la
-- differenza che rende impossibile cancellare la conversazione di un altro
-- passando il suo uuid.

create or replace function public.sommelier_storico_cancella(p_session_id text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_cancellati integer;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if p_session_id !~ '^[A-Za-z0-9_-]{4,64}$' then
    raise exception 'Identificativo di sessione non valido.' using errcode = '22023';
  end if;

  -- Un utente rimosso non legge il proprio storico; cancellarlo è comunque
  -- consentito, perché è una richiesta di rimozione dei propri dati e negarla
  -- sarebbe un effetto che nessuna decisione ha chiesto.
  delete from public.sommelier_messaggi m
   where m.owner_id = v_uid
     and m.session_id = p_session_id;

  get diagnostics v_cancellati = row_count;
  return v_cancellati;
end;
$$;

revoke execute on function public.sommelier_storico_cancella(text)
  from public, anon;
grant execute on function public.sommelier_storico_cancella(text) to authenticated;
