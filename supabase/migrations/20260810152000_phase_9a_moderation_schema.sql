-- Fase 9a - schema di moderazione, audit persistente e code in lettura.
--
-- Prima fase in cui un ruolo legge righe che non sono sue. Le tre regole di
-- esposizione vincolanti dalla 6d-1 si applicano tutte:
--   1. nessun grant di tabella intera a un ruolo che raggiunge righe altrui:
--      reports, report_events e audit_log non hanno alcun grant client;
--   2. ogni lettura allargata passa da una vista security_invoker = off a
--      elenco di colonne chiuso, dove il filtro sta dentro la vista;
--   3. ogni colonna con una regola di dominio dietro ha una funzione
--      SECURITY DEFINER come unica porta.
--
-- Il client non scrive in nessuna tabella di questa fase. Le azioni di
-- moderazione (le sette RPC) sono il checkpoint 9b: qui esistono lo schema,
-- il registro e la porta di scrittura dell'audit, perche un registro
-- append-only che nasce dopo le azioni che dovrebbe registrare nasce gia
-- incompleto.
--
-- Decisioni organizzative del 10 agosto 2026 recepite da questo file:
--   7.1  modera chi ha il ruolo `admin`; nessun ruolo `moderator`.
--   7.2  nessuna porta di assegnazione ruoli: i moderatori si creano fuori banda.
--   7.3  audit_log senza retention: nessuna cancellazione, mai.
--   7.4  segnalante tracciato verso il moderatore, mai verso il segnalato.
--   7.5  nessuna assegnazione delle pratiche: coda condivisa.
--   7.6a `post` e `commento` esclusi: cinque tipi di bersaglio, non sette.
--   7.8b nessun campo `ricorso`: resta dichiaratamente non portato.

-- ---------------------------------------------------------------------------
-- Tipi
-- ---------------------------------------------------------------------------

-- Cinque valori, non i sette di frontend/src/data/moderation.ts:22-33.
-- `post` e `commento` sono esclusi finche i club non hanno schema Supabase
-- (decisione 7.6a): un bersaglio che non puo essere risolto in una riga non e
-- un bersaglio, e accettarlo senza riferimento avrebbe reso l'id un campo di
-- testo libero.
create type public.report_target_tipo as enum (
  'annuncio',
  'profilo',
  'messaggio',
  'conversazione',
  'recensione'
);

comment on type public.report_target_tipo is
  'Bersagli segnalabili. Cinque dei sette del mock: post e commento sono '
  'esclusi per la decisione 7.6a finche i club non hanno schema Supabase. '
  'Aggiungere un valore a un enum in uso richiede una migrazione nuova.';

-- Identici a ReportStatus in frontend/src/data/moderation.ts:63-71.
create type public.report_stato as enum (
  'inviata',
  'in_revisione',
  'info_richieste',
  'risolta',
  'respinta'
);

-- Identici a Priorita in frontend/src/data/moderation.ts:81.
create type public.report_priorita as enum ('bassa', 'media', 'alta');

-- Identiche a ModAction in frontend/src/data/moderation.ts:185-192.
create type public.mod_action as enum (
  'richiesta_modifiche',
  'ammonizione',
  'sospensione',
  'rimozione',
  'ripristino',
  'chiusura',
  'info_richieste'
);

-- Identico ad AuditEntry.scope in frontend/src/data/moderation.ts:218.
-- `club` esiste nell'enum ma nessuna riga puo ancora nascere con quel valore:
-- i club non hanno schema. E la stessa scelta gia fatta per listing_stato in
-- 6a, dove i tre valori di moderazione esistevano prima delle transizioni.
create type public.mod_scope as enum ('piattaforma', 'club');

-- ---------------------------------------------------------------------------
-- report_reasons - l'elenco chiuso dei motivi, per tipo di bersaglio
-- ---------------------------------------------------------------------------
-- Nel mock e un Record<ReportTargetType, string[]>
-- (frontend/src/data/moderation.ts:35-61) validato solo dal client. Qui e una
-- tabella con una foreign key da reports: il motivo fuori elenco non e un
-- messaggio d'errore, e una violazione di vincolo.

create table public.report_reasons (
  target_tipo public.report_target_tipo not null,
  motivo text not null,
  ordine smallint not null,
  primary key (target_tipo, motivo)
);

comment on table public.report_reasons is
  'Elenco chiuso dei motivi di segnalazione per tipo di bersaglio, da '
  'frontend/src/data/moderation.ts:35-61. E la sorgente del menu del client e '
  'insieme il vincolo referenziale di reports.motivo: le due cose non possono '
  'divergere. Non contiene righe di alcun utente, quindi il grant di tabella '
  'intera non viola la prima regola di esposizione.';

insert into public.report_reasons (target_tipo, motivo, ordine) values
  ('annuncio', 'Annuncio sospetto o possibile falso', 1),
  ('annuncio', 'Foto non veritiere o riciclate', 2),
  ('annuncio', 'Descrizione ingannevole', 3),
  ('annuncio', 'Prezzo anomalo', 4),
  ('annuncio', 'Contenuto vietato o pericoloso', 5),
  ('annuncio', 'Annuncio duplicato', 6),
  ('profilo', 'Identita sospetta', 1),
  ('profilo', 'Comportamento scorretto', 2),
  ('profilo', 'Comunicazione offensiva', 3),
  ('profilo', 'Sospetta frode', 4),
  ('profilo', 'Account impersonatore', 5),
  ('messaggio', 'Contenuto offensivo', 1),
  ('messaggio', 'Tentativo di truffa', 2),
  ('messaggio', 'Richiesta di pagamento fuori piattaforma', 3),
  ('messaggio', 'Spam o pubblicita non richiesta', 4),
  ('conversazione', 'Molestie ripetute', 1),
  ('conversazione', 'Truffa in corso', 2),
  ('conversazione', 'Comunicazione offensiva', 3),
  ('recensione', 'Recensione falsa', 1),
  ('recensione', 'Contenuto diffamatorio', 2),
  ('recensione', 'Fuori tema rispetto all''ordine', 3);

-- ---------------------------------------------------------------------------
-- reports - le segnalazioni
-- ---------------------------------------------------------------------------
-- Modello di riferimento: il tipo Report (frontend/src/data/moderation.ts:89-106),
-- con le tre differenze imposte dal passaggio a un database reale.
--
-- Il bersaglio e polimorfico ma non e una coppia (tipo, id) senza vincolo: con
-- `post` e `commento` fuori perimetro tutti e cinque i bersagli residui hanno
-- una tabella con chiave uuid, quindi ciascuno ha la sua colonna nullable e il
-- suo vincolo referenziale. Il CHECK di esclusivita garantisce che sia
-- valorizzata esattamente quella coerente con target_tipo.
--
-- Tutte le foreign key di bersaglio sono `on delete set null`, non `cascade`:
-- una segnalazione deve sopravvivere alla rimozione di cio che segnala,
-- altrimenti moderare un contenuto cancellerebbe la prova del perche.
-- target_label conserva la descrizione leggibile al momento della
-- segnalazione ed e cio che resta quando il riferimento si annulla.

create table public.reports (
  id uuid primary key default gen_random_uuid(),

  -- Codice leggibile in stile SEG-2026-0001. E un'etichetta derivata da una
  -- sequenza, non la chiave: il mock lo generava con Math.random()
  -- (frontend/src/lib/store/moderation-domain.ts:44), che in un database e
  -- una collisione che aspetta.
  codice text not null unique,

  target_tipo public.report_target_tipo not null,
  target_label text not null check (length(btrim(target_label)) between 1 and 200),

  target_listing_id uuid references public.listings (id) on delete set null,
  target_profile_id uuid references public.profiles (id) on delete set null,
  target_message_id uuid references public.messages (id) on delete set null,
  target_conversation_id uuid references public.conversations (id) on delete set null,
  target_review_id uuid references public.order_reviews (id) on delete set null,

  motivo text not null,
  descrizione text not null default '' check (length(descrizione) <= 4000),

  -- Stesso tetto delle foto di disputes (7c): otto.
  foto text[] not null default '{}' check (cardinality(foto) <= 8),

  stato public.report_stato not null default 'inviata',

  -- Derivata da private.report_priorita_da_motivo, mai inviata dal client.
  priorita public.report_priorita not null,

  -- Il segnalante e un utente, non la stringa MY_REPORTER del mock
  -- (frontend/src/data/moderation.ts:406). Leggibile dal moderatore
  -- (decisione 7.4), mai dal segnalato: nessuna proiezione di questa fase
  -- espone reporter_id verso il bersaglio.
  reporter_id uuid not null references public.profiles (id) on delete cascade,

  -- Nessuna colonna di assegnazione: decisione 7.5, coda condivisa fra tutti
  -- i moderatori. Il mock aveva `assignee`
  -- (frontend/src/lib/store/moderation-domain.ts:98-115); qui non esiste, e
  -- non esiste nemmeno la RPC che la scriverebbe.

  club_slug text check (club_slug is null or club_slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint reports_motivo_fk
    foreign key (target_tipo, motivo)
    references public.report_reasons (target_tipo, motivo)
    on update cascade,

  -- Esattamente un riferimento di bersaglio, coerente con target_tipo.
  constraint reports_target_esclusivo check (
    (case when target_listing_id is not null then 1 else 0 end)
    + (case when target_profile_id is not null then 1 else 0 end)
    + (case when target_message_id is not null then 1 else 0 end)
    + (case when target_conversation_id is not null then 1 else 0 end)
    + (case when target_review_id is not null then 1 else 0 end)
    <= 1
  ),
  constraint reports_target_coerente check (
    case target_tipo
      when 'annuncio' then target_profile_id is null and target_message_id is null
        and target_conversation_id is null and target_review_id is null
      when 'profilo' then target_listing_id is null and target_message_id is null
        and target_conversation_id is null and target_review_id is null
      when 'messaggio' then target_listing_id is null and target_profile_id is null
        and target_conversation_id is null and target_review_id is null
      when 'conversazione' then target_listing_id is null and target_profile_id is null
        and target_message_id is null and target_review_id is null
      when 'recensione' then target_listing_id is null and target_profile_id is null
        and target_message_id is null and target_conversation_id is null
    end
  )
);

comment on table public.reports is
  'Segnalazioni degli utenti. Nessun grant client: si scrive solo da '
  'public.segnalazione_invia e si legge solo dalle viste moderation_report_queue '
  '(moderatore) e my_reports (segnalante). reporter_id e visibile al moderatore '
  'per la decisione 7.4 e non compare in nessuna proiezione raggiungibile dal '
  'segnalato.';
comment on column public.reports.priorita is
  'Derivata sul server da private.report_priorita_da_motivo. Regola di dominio, '
  'quindi non un valore che il client invia: replica priorityFromReason in '
  'frontend/src/data/moderation.ts:108-120.';
comment on column public.reports.codice is
  'Etichetta leggibile derivata da una sequenza. Non e la chiave.';

create sequence public.reports_codice_seq as bigint start 1;

create index reports_stato_priorita_idx
  on public.reports (stato, priorita desc, created_at desc);
create index reports_reporter_idx
  on public.reports (reporter_id, created_at desc);

-- ---------------------------------------------------------------------------
-- report_events - storia visibile e note interne, due sequenze separate
-- ---------------------------------------------------------------------------
-- Nel mock sono due array distinti sullo stesso oggetto
-- (frontend/src/data/moderation.ts:104-105) e la separazione e solo
-- strutturale. Qui e un confine di privilegio: `visibile = false` non
-- raggiunge nessuna proiezione che il segnalante possa leggere. E lo stesso
-- motivo per cui disputes.risolta_da e fuori dal grant della 7c.

create table public.report_events (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.reports (id) on delete cascade,
  visibile boolean not null,
  testo text not null check (length(btrim(testo)) between 1 and 4000),

  -- Chi ha scritto la voce. Nullo per le voci generate dal sistema
  -- ("Segnalazione ricevuta"), che nel mock avevano autore "Moderazione".
  autore_id uuid references public.profiles (id) on delete set null,
  autore_etichetta text not null check (length(btrim(autore_etichetta)) between 1 and 120),

  created_at timestamptz not null default now()
);

comment on table public.report_events is
  'Storia della pratica. visibile = true e la storia che il segnalante legge; '
  'visibile = false sono le note interne, che nessuna proiezione raggiungibile '
  'dal segnalante espone.';

create index report_events_report_idx
  on public.report_events (report_id, created_at, id);

-- ---------------------------------------------------------------------------
-- audit_log - il registro append-only
-- ---------------------------------------------------------------------------
-- Una riga per azione di moderazione compiuta, mai modificata e mai
-- cancellata. Nessuna retention: decisione 7.3, nessuna cancellazione mai.
-- Questa e la ragione per cui le tre colonne di traccia su listings
-- (stato_motivo, stato_aggiornato_da, stato_aggiornato_at) non bastano:
-- quelle conservano solo l'ultima transizione e vengono sovrascritte.
--
-- L'attore e conservato due volte: attore_id come riferimento e
-- attore_username come istantanea al momento del fatto. Un registro che perde
-- il nome di chi ha agito quando quel profilo viene cancellato non e un
-- registro. Il riferimento si annulla, l'istantanea resta.

create table public.audit_log (
  id uuid primary key default gen_random_uuid(),
  ts timestamptz not null default now(),

  attore_id uuid references public.profiles (id) on delete set null,
  attore_username text not null check (length(btrim(attore_username)) between 1 and 120),

  scope public.mod_scope not null default 'piattaforma',
  club_slug text check (club_slug is null or club_slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),

  azione public.mod_action not null,

  target_tipo public.report_target_tipo not null,
  target_id uuid,
  target_label text not null check (length(btrim(target_label)) between 1 and 200),

  -- Obbligatoria come vincolo di database, non solo lato client: il mock la
  -- imponeva in frontend/src/hooks/useModerationActions.ts:63, cioe in un
  -- punto che un chiamante diverso dalla UI non attraversa.
  motivazione text not null check (length(btrim(motivazione)) between 1 and 4000),

  -- Valorizzata solo per `sospensione`, come nel mock
  -- (frontend/src/hooks/useModerationActions.ts:69).
  durata text check (durata is null or length(btrim(durata)) between 1 and 120),

  report_id uuid references public.reports (id) on delete set null,

  -- Nessuna colonna `ricorso`: decisione 7.8b. Il campo esiste in AuditEntry
  -- (frontend/src/data/moderation.ts:224) ma nessuna interfaccia di frontend/
  -- lo scrive, quindi portarlo sarebbe stata funzionalita nuova.

  constraint audit_log_scope_club check (
    (scope = 'club') = (club_slug is not null)
  ),
  constraint audit_log_durata_solo_sospensione check (
    durata is null or azione = 'sospensione'
  )
);

comment on table public.audit_log is
  'Registro append-only delle azioni di moderazione. Nessun UPDATE e nessun '
  'DELETE, per nessun ruolo incluso service_role: il trigger sotto li rifiuta, '
  'perche un append-only che dipende solo dai GRANT resta append-only finche '
  'qualcuno non aggiunge un GRANT. Nessuna retention (decisione 7.3).';

create index audit_log_ts_idx on public.audit_log (ts desc, id desc);
create index audit_log_target_idx on public.audit_log (target_tipo, target_id, ts desc);

-- Append-only imposto dal database, non dai privilegi.
-- Non SECURITY DEFINER: solleva e basta, non legge nulla e non ha bisogno di
-- privilegi altrui. E la stessa forma di private.messages_immutable() (Fase 8).
create or replace function private.audit_log_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception
    'audit_log e append-only: % non e ammesso su public.audit_log.', tg_op
    using errcode = '42501';
end;
$$;

comment on function private.audit_log_append_only() is
  'Rifiuta UPDATE e DELETE su public.audit_log per ogni ruolo, service_role '
  'compreso. Un trigger e l''unico modo di esprimere questo invariante: i '
  'GRANT non vincolano il proprietario della tabella.';

create trigger audit_log_no_update
  before update on public.audit_log
  for each row execute function private.audit_log_append_only();

create trigger audit_log_no_delete
  before delete on public.audit_log
  for each row execute function private.audit_log_append_only();

-- Anche il TRUNCATE, che non passa dai trigger di riga.
create trigger audit_log_no_truncate
  before truncate on public.audit_log
  for each statement execute function private.audit_log_append_only();

-- ---------------------------------------------------------------------------
-- Privilegi sulle tabelle: nessun grant client sulle tre tabelle di dominio
-- ---------------------------------------------------------------------------
-- Prima regola di esposizione: una tabella le cui righe sono raggiungibili da
-- un ruolo che non ne e proprietario non ha grant di tabella intera. Qui non
-- ha nemmeno un grant di colonna: ogni lettura passa dalle viste piu sotto,
-- dove il filtro e scritto dentro e nessun client puo allargarlo.

alter table public.reports enable row level security;
alter table public.report_events enable row level security;
alter table public.audit_log enable row level security;
alter table public.report_reasons enable row level security;

revoke all on public.reports,
  public.report_events,
  public.audit_log,
  public.report_reasons
  from public, anon, authenticated;

revoke all on sequence public.reports_codice_seq from public, anon, authenticated;

-- report_reasons e l'unica eccezione, e non e un'eccezione alla regola: non
-- contiene righe di alcun utente, quindi non esiste il concetto di "riga
-- altrui". E il menu dei motivi, identico per tutti.
grant select (target_tipo, motivo, ordine) on public.report_reasons to authenticated, anon;

create policy report_reasons_select_tutti
  on public.report_reasons for select
  to authenticated, anon
  using (true);

-- Nessuna policy su reports, report_events e audit_log. RLS attiva senza
-- policy significa zero righe per ogni ruolo client, che e esattamente cio
-- che si vuole: le viste security_invoker = off leggono con i privilegi del
-- proprietario e non attraversano queste policy.

-- ---------------------------------------------------------------------------
-- Priorita derivata dal motivo
-- ---------------------------------------------------------------------------
-- Replica priorityFromReason (frontend/src/data/moderation.ts:108-120). E una
-- regola di dominio: sta sul server e il client non la invia. `immutable`
-- perche dipende solo dall'argomento.

create or replace function private.report_priorita_da_motivo(p_motivo text)
returns public.report_priorita
language sql
immutable
set search_path = ''
as $$
  select case
    when lower(coalesce(p_motivo, '')) like any (array[
      '%truff%', '%frod%', '%pagament%', '%molest%'
    ]) then 'alta'::public.report_priorita
    when lower(coalesce(p_motivo, '')) like any (array[
      '%offens%', '%falsa%', '%veritier%', '%ingannev%'
    ]) then 'media'::public.report_priorita
    else 'bassa'::public.report_priorita
  end;
$$;

comment on function private.report_priorita_da_motivo(text) is
  'Priorita derivata dal testo del motivo, come priorityFromReason in '
  'frontend/src/data/moderation.ts:108-120. Ogni ramo del case e castato '
  'esplicitamente all''enum: un case fra due letterali si risolve a text e '
  'text->enum non ha conversione implicita (42804, difetto della 7c).';

-- ---------------------------------------------------------------------------
-- private.audit_registra - l'unica porta di scrittura dell'audit
-- ---------------------------------------------------------------------------
-- Esiste in 9a benche le sette azioni siano 9b: il registro deve esistere
-- prima della prima azione, non insieme. Non e concessa a nessun ruolo client;
-- le RPC di moderazione della 9b la chiameranno dall'interno.

create or replace function private.audit_registra(
  p_attore_id uuid,
  p_azione public.mod_action,
  p_target_tipo public.report_target_tipo,
  p_target_id uuid,
  p_target_label text,
  p_motivazione text,
  p_durata text default null,
  p_report_id uuid default null,
  p_scope public.mod_scope default 'piattaforma',
  p_club_slug text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_username text;
  v_id uuid;
begin
  if p_attore_id is null then
    raise exception 'Attore richiesto per una riga di audit.' using errcode = '22023';
  end if;

  if length(btrim(coalesce(p_motivazione, ''))) = 0 then
    raise exception 'Motivazione obbligatoria.' using errcode = '22023';
  end if;

  select pr.username into v_username
  from public.profiles pr
  where pr.id = p_attore_id;

  if v_username is null then
    raise exception 'Attore non trovato.' using errcode = 'P0001';
  end if;

  insert into public.audit_log (
    attore_id, attore_username, scope, club_slug, azione,
    target_tipo, target_id, target_label, motivazione, durata, report_id
  ) values (
    p_attore_id, v_username, p_scope, p_club_slug, p_azione,
    p_target_tipo, p_target_id, btrim(p_target_label), btrim(p_motivazione),
    nullif(btrim(coalesce(p_durata, '')), ''), p_report_id
  )
  returning id into v_id;

  return v_id;
end;
$$;

comment on function private.audit_registra is
  'Unica porta di scrittura di public.audit_log. Nessun INSERT dal client, '
  'mai. Conserva attore_username come istantanea perche il registro sopravviva '
  'alla cancellazione del profilo dell''attore.';

-- ---------------------------------------------------------------------------
-- public.segnalazione_invia - la porta di scrittura del segnalante
-- ---------------------------------------------------------------------------
-- Unico ingresso di una segnalazione. Il client non invia ne priorita ne
-- stato ne identita: le prime due sono regole di dominio, la terza viene da
-- auth.uid(). Il rate limit riusa l'infrastruttura della Fase 7: senza, la
-- segnalazione e una porta di scrittura al ritmo che il client decide.

create or replace function public.segnalazione_invia(
  p_target_tipo public.report_target_tipo,
  p_target_id uuid,
  p_target_label text,
  p_motivo text,
  p_descrizione text default '',
  p_foto text[] default '{}',
  p_club_slug text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_priorita public.report_priorita;
  v_codice text;
  v_id uuid;
  v_esiste boolean;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  perform private.rate_limit_consume('report:submit', 'user:' || v_uid::text, 10, 3600);

  if length(btrim(coalesce(p_target_label, ''))) = 0 then
    raise exception 'Etichetta del bersaglio richiesta.' using errcode = '22023';
  end if;

  if cardinality(coalesce(p_foto, '{}')) > 8 then
    raise exception 'Massimo otto foto per segnalazione.' using errcode = '22023';
  end if;

  -- Il motivo deve appartenere all'elenco chiuso del tipo di bersaglio. Il
  -- vincolo referenziale lo imporrebbe comunque; questo controllo esiste per
  -- restituire un errore leggibile invece di una violazione di foreign key.
  if not exists (
    select 1 from public.report_reasons rr
    where rr.target_tipo = p_target_tipo and rr.motivo = p_motivo
  ) then
    raise exception 'Motivo non ammesso per questo tipo di bersaglio.'
      using errcode = '22023';
  end if;

  -- Il bersaglio deve esistere davvero. Senza questo controllo la foreign key
  -- fallirebbe con un messaggio di database, e un bersaglio inesistente
  -- entrerebbe comunque in coda quando l'id e nullo.
  v_esiste := case p_target_tipo
    when 'annuncio' then exists (select 1 from public.listings l where l.id = p_target_id)
    when 'profilo' then exists (select 1 from public.profiles pr where pr.id = p_target_id)
    when 'messaggio' then exists (select 1 from public.messages m where m.id = p_target_id)
    when 'conversazione' then exists (select 1 from public.conversations c where c.id = p_target_id)
    when 'recensione' then exists (select 1 from public.order_reviews r where r.id = p_target_id)
  end;

  if not coalesce(v_esiste, false) then
    raise exception 'Bersaglio non trovato.' using errcode = 'P0001';
  end if;

  -- Non ci si segnala da soli.
  if p_target_tipo = 'profilo' and p_target_id = v_uid then
    raise exception 'Non e possibile segnalare il proprio profilo.'
      using errcode = '22023';
  end if;

  -- Una pratica aperta per bersaglio e per segnalante: il doppione non e un
  -- errore dell'utente, e rumore in coda.
  if exists (
    select 1 from public.reports r
    where r.reporter_id = v_uid
      and r.target_tipo = p_target_tipo
      and coalesce(
        r.target_listing_id, r.target_profile_id, r.target_message_id,
        r.target_conversation_id, r.target_review_id
      ) = p_target_id
      and r.stato in ('inviata', 'in_revisione', 'info_richieste')
  ) then
    raise exception 'Hai gia una segnalazione aperta su questo contenuto.'
      using errcode = 'P0001';
  end if;

  v_priorita := private.report_priorita_da_motivo(p_motivo);
  v_codice := 'SEG-' || to_char(now(), 'YYYY') || '-'
    || lpad(nextval('public.reports_codice_seq')::text, 4, '0');

  insert into public.reports (
    codice, target_tipo, target_label,
    target_listing_id, target_profile_id, target_message_id,
    target_conversation_id, target_review_id,
    motivo, descrizione, foto, priorita, reporter_id, club_slug
  ) values (
    v_codice, p_target_tipo, btrim(p_target_label),
    case when p_target_tipo = 'annuncio' then p_target_id end,
    case when p_target_tipo = 'profilo' then p_target_id end,
    case when p_target_tipo = 'messaggio' then p_target_id end,
    case when p_target_tipo = 'conversazione' then p_target_id end,
    case when p_target_tipo = 'recensione' then p_target_id end,
    p_motivo, btrim(coalesce(p_descrizione, '')), coalesce(p_foto, '{}'),
    v_priorita, v_uid, p_club_slug
  )
  returning id into v_id;

  insert into public.report_events (report_id, visibile, testo, autore_id, autore_etichetta)
  values (v_id, true, 'Segnalazione ricevuta', null, 'Moderazione');

  return v_id;
end;
$$;

comment on function public.segnalazione_invia is
  'Unica porta di ingresso di una segnalazione. Identita da auth.uid(), '
  'priorita derivata sul server, motivo vincolato all''elenco chiuso, '
  'bersaglio verificato esistente, rate limit 10/ora per utente.';

-- ---------------------------------------------------------------------------
-- Proiezioni di lettura
-- ---------------------------------------------------------------------------
-- Tutte security_invoker = off con elenco di colonne chiuso: il filtro sta
-- dentro la vista, dove nessun client puo allargarlo, e una colonna aggiunta
-- domani alla tabella base resta privata finche qualcuno non la elenca.
--
-- PERCHE IL PREDICATO E INLINATO E NON public.has_role().
-- La scelta ovvia sarebbe `public.has_role((select auth.uid()), 'admin')`.
-- Non regge, ed e stato misurato prima di scrivere questo file, non dedotto.
-- public.has_role e SECURITY INVOKER dalla 20260729235500 e legge
-- public.user_roles; su questo progetto `authenticated` NON ha select su
-- public.user_roles (has_table_privilege dice false: il grant di tabella e
-- stato chiuso dalla 6d-1). La funzione non viene inlinata dal pianificatore:
-- esegue come il chiamante, e da `permission denied for table user_roles`.
-- Il risultato non sarebbe una coda vuota, sarebbe un errore a ogni lettura.
--
-- Un helper in `private` con SECURITY DEFINER non risolve: il privilegio
-- EXECUTE di una funzione e verificato sul chiamante e non sul proprietario
-- della vista, quindi andrebbe concesso ad `authenticated`, cioe messo a
-- portata di ogni client. Provato anche quello: `permission denied for
-- function`.
--
-- Il predicato inlinato nel corpo della vista invece funziona, perche con
-- security_invoker = off il riferimento a user_roles e verificato con i
-- privilegi del proprietario della vista. Nessuna concessione nuova, nessuna
-- funzione nuova, e il filtro resta scritto dentro la vista dove nessun
-- client puo allargarlo — che e esattamente la seconda regola di esposizione.
--
-- Nota per chi legge dopo: public.has_role resta rotta per un chiamante
-- `authenticated` anche fuori da questa fase (le policy wines_insert_staff,
-- wines_update_staff e wines_delete_staff la usano e falliscono allo stesso
-- modo). Fallisce chiusa, quindi non e un buco; e un difetto di funzionalita
-- di un dominio diverso e non viene corretto qui.

-- [1] Coda segnalazioni - solo per chi ha il ruolo admin (decisione 7.1).
create or replace view public.moderation_report_queue
with (security_invoker = off, security_barrier = true) as
  select
    r.id,
    r.codice,
    r.target_tipo,
    r.target_label,
    coalesce(
      r.target_listing_id, r.target_profile_id, r.target_message_id,
      r.target_conversation_id, r.target_review_id
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

comment on view public.moderation_report_queue is
  'Coda condivisa delle segnalazioni (decisione 7.5: nessuna assegnazione). '
  'Visibile solo a chi ha il ruolo admin. Espone reporter_id e '
  'reporter_username per la decisione 7.4: il moderatore vede chi ha segnalato, '
  'il segnalato non raggiunge questa vista.';

-- [2] Storia e note di una pratica, lato moderatore: entrambe.
create or replace view public.moderation_report_events
with (security_invoker = off, security_barrier = true) as
  select
    e.id,
    e.report_id,
    e.visibile,
    e.testo,
    e.autore_etichetta,
    e.created_at
  from public.report_events e
  where exists (
    select 1 from public.user_roles ur
    where ur.user_id = (select auth.uid()) and ur.role = 'admin'
  );

comment on view public.moderation_report_events is
  'Storia visibile e note interne insieme, per il solo moderatore. La '
  'controparte lato segnalante e my_report_events, che filtra visibile = true.';

-- [3] Le mie segnalazioni - lato segnalante.
-- Non espone reporter_id (e sempre se stesso) ne alcuna nota interna.
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
  where r.reporter_id = (select auth.uid());

comment on view public.my_reports is
  'Le segnalazioni del chiamante, per la schermata "Le mie segnalazioni". '
  'Nessuna nota interna e nessun dato di moderazione.';

-- [4] La storia visibile delle proprie pratiche.
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
    and r.reporter_id = (select auth.uid());

comment on view public.my_report_events is
  'Solo le voci con visibile = true e solo delle proprie pratiche. Le note '
  'interne non hanno alcun percorso verso il segnalante.';

-- [5] Coda contestazioni - proiezione in sola lettura su disputes.
-- La Fase 9 non scrive logica di risoluzione: ordine_contestazione_apri e
-- ordine_contestazione_risolvi restano le uniche porte, con la firma che
-- hanno oggi. Questa vista risolve il solo problema che la 7c ha lasciato
-- aperto: le policy di disputes mostrano a ciascun cliente le proprie righe e
-- non esiste una lettura elencabile per un moderatore.
-- risolta_da e fuori dal grant client di disputes (7c) e qui rientra: chi ha
-- deciso la pratica e dato di moderazione, e questa vista e raggiungibile
-- solo da un moderatore.
create or replace view public.moderation_dispute_queue
with (security_invoker = off, security_barrier = true) as
  select
    d.id,
    d.order_id,
    d.aperta_da,
    ap.username as aperta_da_username,
    o.seller_id,
    sp.username as seller_username,
    d.motivo,
    d.descrizione,
    d.foto,
    d.stato,
    d.esito_nota,
    d.risolta_da,
    d.apertura_at,
    d.chiusura_at,
    o.stato as ordine_stato,
    o.payout_stato as ordine_payout_stato,
    o.totale_cents,
    o.addebito_totale_cents
  from public.disputes d
  join public.orders o on o.id = d.order_id
  join public.profiles ap on ap.id = d.aperta_da
  join public.profiles sp on sp.id = o.seller_id
  where exists (
    select 1 from public.user_roles ur
    where ur.user_id = (select auth.uid()) and ur.role = 'admin'
  );

comment on view public.moderation_dispute_queue is
  'Coda contestazioni in sola lettura per il moderatore. Non duplica logica: '
  'la risoluzione resta ordine_contestazione_risolvi, stessa firma. Espone '
  'risolta_da, che e fuori dal grant client di disputes proprio perche e dato '
  'di moderazione.';

-- [6] Elenco audit.
create or replace view public.moderation_audit_log
with (security_invoker = off, security_barrier = true) as
  select
    a.id,
    a.ts,
    a.attore_username,
    a.scope,
    a.club_slug,
    a.azione,
    a.target_tipo,
    a.target_id,
    a.target_label,
    a.motivazione,
    a.durata,
    a.report_id
  from public.audit_log a
  where exists (
    select 1 from public.user_roles ur
    where ur.user_id = (select auth.uid()) and ur.role = 'admin'
  );

comment on view public.moderation_audit_log is
  'Registro di moderazione in lettura, per il solo moderatore. attore_id non '
  'e esposto: attore_username e l''istantanea che il registro conserva ed e '
  'cio che il pannello mostra.';

-- Le viste sono di sola lettura per i client. Nessuna e concessa ad anon:
-- nessuna riga di moderazione ha un lettore anonimo.
revoke all on
  public.moderation_report_queue,
  public.moderation_report_events,
  public.my_reports,
  public.my_report_events,
  public.moderation_dispute_queue,
  public.moderation_audit_log
  from public, anon, authenticated;

grant select on
  public.moderation_report_queue,
  public.moderation_report_events,
  public.my_reports,
  public.my_report_events,
  public.moderation_dispute_queue,
  public.moderation_audit_log
  to authenticated;

-- ---------------------------------------------------------------------------
-- Privilegi sulle funzioni
-- ---------------------------------------------------------------------------

revoke execute on function
  private.audit_log_append_only(),
  private.report_priorita_da_motivo(text),
  private.audit_registra(
    uuid, public.mod_action, public.report_target_tipo, uuid, text, text,
    text, uuid, public.mod_scope, text
  )
  from public, anon, authenticated;

revoke execute on function public.segnalazione_invia(
  public.report_target_tipo, uuid, text, text, text, text[], text
) from public, anon;

grant execute on function public.segnalazione_invia(
  public.report_target_tipo, uuid, text, text, text, text[], text
) to authenticated;

notify pgrst, 'reload schema';
