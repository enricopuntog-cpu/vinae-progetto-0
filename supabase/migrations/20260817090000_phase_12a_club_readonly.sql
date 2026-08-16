-- Fase 12a - Club/Community in sola lettura.
--
-- Primo checkpoint della Fase 12. Il perimetro e stretto e va letto per cio
-- che NON contiene: i club esistono come righe reali, chiunque li legge, un
-- utente autenticato li segue e smette di seguirli. Nessun contenuto
-- scrivibile dagli utenti - niente post, niente risposte, niente reazioni,
-- niente sondaggi. Quelli sono il 12b, e in questo file non hanno schema,
-- non hanno una tabella vuota che li aspetta e non hanno un enum che li
-- nomina. Una tabella `club_posts` creata qui "tanto resta vuota" sarebbe
-- gia il 12b: la superficie esiste dal momento in cui esiste la tabella, non
-- dal momento in cui la si popola.
--
-- Le tre regole di esposizione vincolanti dalla 6d-1 si applicano tutte:
--   1. nessun grant di tabella intera a un ruolo che raggiunge righe altrui.
--      `clubs` e leggibile da chiunque, quindi non ha ALCUN grant client e la
--      lettura passa dalla vista. `club_memberships` la RLS la confina alle
--      righe proprie di ogni ruolo client, quindi il grant di tabella e
--      lecito - stesso caso di bottle_units.
--   2. la lettura pubblica passa da una vista security_invoker = off a
--      elenco di colonne chiuso: public_clubs. Una colonna aggiunta domani a
--      `clubs` resta privata finche qualcuno non la elenca li dentro.
--   3. una colonna con una regola di dominio dietro non e scrivibile dal
--      client: `club_memberships.ruolo` resta fuori dal grant di INSERT, e
--      `user_id` pure - arriva da un DEFAULT, non dal client.
--
-- ---------------------------------------------------------------------------
-- PERCHE `clubs` NON HA UNA PORTA DI SCRITTURA PER L'ADMIN
-- ---------------------------------------------------------------------------
-- La forma attesa sarebbe una policy di scrittura su `clubs` con predicato
-- `public.has_role(auth.uid(), 'admin')`. Non regge su questo progetto, e non
-- e una deduzione: e la stessa cosa gia misurata e scritta nella 9a
-- (20260810152000, righe 622-649).
--
-- `public.has_role` e SECURITY INVOKER dalla 20260729235500 e legge
-- public.user_roles, su cui `authenticated` non ha SELECT dalla 6d-1. Una
-- policy RLS valuta il proprio predicato con i privilegi del chiamante, non
-- con quelli del proprietario della tabella: quindi ne `has_role(...)` ne il
-- suo `exists` inlinato su user_roles funzionano dentro una policy. Il
-- risultato non sarebbe "solo l'admin scrive", sarebbe `permission denied for
-- table user_roles` per chiunque, admin compreso. E' esattamente il difetto
-- che wines_insert_staff / wines_update_staff / wines_delete_staff hanno da
-- allora, registrato e deliberatamente non corretto.
--
-- Il trucco della 9a - inlinare il predicato dentro una vista
-- security_invoker = off - risolve la LETTURA, non la scrittura: una vista
-- non e una porta di INSERT.
--
-- Quindi qui `clubs` non riceve alcun grant di scrittura da nessun ruolo
-- client. Chi scrive un club e `service_role` / SQL Editor, cioe il fixture
-- di seed, che e un'autorizzazione a parte. Questo checkpoint e in sola
-- lettura e non ha nessuna schermata da cui un admin crei un club: una porta
-- di scrittura non usata da niente sarebbe superficie in piu senza un
-- chiamante. Quando 12b o 12c ne vorranno una, la forma e quella della regola
-- 3 - una funzione SECURITY DEFINER come unica porta - non una policy.
--
-- ---------------------------------------------------------------------------
-- SOSPENSIONE E RIMOZIONE (decisione 7.6b)
-- ---------------------------------------------------------------------------
-- Seguire un club e una scrittura social, e prende lo stesso guard che la 9b
-- ha messo su listings, messages e conversations. Il guard non cambia di una
-- riga: private.scrittura_social_guard() ha gia il ramo `else auth.uid()` per
-- le tabelle il cui attore non e una colonna della riga, che e questo caso.
-- Simmetricamente, un chiamante `rimosso` non legge public_clubs, come non
-- legge public_listings: il club e superficie sociale, e il secondo
-- provvedimento toglie anche l'accesso in visione.
--
-- Nulla di tutto cio tocca la macchina di pagamento. Il vincolo fissato in 9c
-- - nessun percorso di ordini, pagamenti, contestazioni o payout deve reagire
-- a stato_utente - resta soddisfatto per costruzione: questo file non nomina
-- nessuna di quelle tabelle.

-- ---------------------------------------------------------------------------
-- Tipi
-- ---------------------------------------------------------------------------

-- Un solo valore, e di proposito. La decisione 7.1 della Fase 9 tiene lo scope
-- club della moderazione RINVIATO: non esiste un ruolo `moderator`, si modera
-- con `admin`. Aggiungere qui 'moderatore' vorrebbe dire decidere quella cosa
-- di sfuggita, dentro una migrazione di un altro checkpoint. Aggiungere un
-- valore a un enum in uso richiede una migrazione nuova, ed e esattamente il
-- punto in cui quella decisione va riaperta in sessione.
create type public.club_ruolo as enum ('membro');

comment on type public.club_ruolo is
  'Ruolo dentro un club. Un solo valore in 12a: la decisione 7.1 della Fase 9 '
  'rinvia lo scope club della moderazione, e un secondo valore lo deciderebbe '
  'implicitamente. Ampliarlo e una migrazione nuova, per costruzione.';

-- ---------------------------------------------------------------------------
-- clubs
-- ---------------------------------------------------------------------------

create table public.clubs (
  -- Lo slug e la chiave primaria e non un id tecnico: e gia l'identificativo
  -- che l'URL usa (/community/[slug]) ed e gia quello che porta
  -- notifications.destination_club_slug della Fase 8 e reports.club_slug della
  -- 9a - due colonne che esistono da prima di questa tabella e che finora non
  -- avevano nulla a cui riferirsi. Nessuna FK viene aggiunta a quelle due qui:
  -- sono di fasi chiuse, e ritrovarsi una segnalazione rifiutata perche il suo
  -- club e stato cancellato non e il comportamento di questo checkpoint.
  slug text primary key
    check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(slug) between 2 and 80),
  nome text not null
    check (length(btrim(nome)) between 2 and 120),
  -- I quattro assi con cui /community filtra. Sono opzionali perche un club
  -- per tipologia non ha un territorio e uno per territorio non ha un
  -- produttore: obbligarli produrrebbe stringhe di comodo tipo 'Vari'.
  territorio text check (territorio is null or length(btrim(territorio)) between 2 and 80),
  denominazione text check (denominazione is null or length(btrim(denominazione)) between 2 and 120),
  produttore text check (produttore is null or length(btrim(produttore)) between 2 and 120),
  tipologia text check (tipologia is null or length(btrim(tipologia)) between 2 and 40),
  descrizione text not null
    check (length(btrim(descrizione)) between 10 and 2000),
  -- Elenco ordinato: la scheda del club le mostra numerate, e l'ordine di
  -- inserimento e informazione. Un text[] lo conserva, una tabella figlia
  -- senza colonna d'ordine no.
  -- `null::text` e non `null` nudo: il secondo e di tipo `unknown` e lascia
  -- decidere a una regola di risoluzione quale sia il tipo dell'argomento
  -- polimorfo. E' la stessa classe di difetto del `case` senza cast sugli
  -- enum che la 7c mando in produzione.
  regole text[] not null default '{}'::text[]
    check (array_position(regole, null::text) is null and cardinality(regole) <= 20),
  created_at timestamptz not null default now()
);

comment on table public.clubs is
  'Club Vinea. Lettura pubblica attraverso public_clubs; nessun ruolo client '
  'ha grant su questa tabella, in lettura o in scrittura. Le righe le scrive '
  'service_role (fixture di seed), che e un''autorizzazione separata dal '
  'merge di questa migrazione.';

comment on column public.clubs.regole is
  'Regole del club, in ordine di inserimento. Nessun elemento null, massimo '
  'venti.';

-- Nessun grant a nessun ruolo client, in nessuna direzione. La lettura passa
-- dalla vista; la scrittura non ha porta (vedi l'intestazione).
revoke all on public.clubs from anon, authenticated;

-- La 20260729234000_rls_auto_enable_bootstrap.sql accende gia la RLS su ogni
-- tabella nuova di `public`. La riga esplicita resta per chi legge il file da
-- solo: senza policy e senza grant, `clubs` e chiusa due volte.
alter table public.clubs enable row level security;

-- ---------------------------------------------------------------------------
-- club_memberships
-- ---------------------------------------------------------------------------

create table public.club_memberships (
  -- DEFAULT auth.uid() e non un parametro: il client non ha grant di INSERT
  -- su questa colonna (vedi il grant a colonna sotto), quindi non puo
  -- nominarla nemmeno per sbaglio, e il valore lo mette il server. La policy
  -- with check ripete la stessa cosa perche service_role scavalca i grant ma
  -- non e la strada da cui passa il client. Due lucchetti diversi sulla
  -- stessa porta, di proposito: il grant e cio che regge se domani qualcuno
  -- aggiunge una policy piu larga.
  user_id uuid not null default auth.uid()
    references public.profiles (id) on delete cascade,
  club_slug text not null
    references public.clubs (slug) on delete cascade,
  ruolo public.club_ruolo not null default 'membro',
  created_at timestamptz not null default now(),
  primary key (user_id, club_slug)
);

comment on table public.club_memberships is
  'Chi segue quale club. Un utente vede e scrive soltanto le proprie righe: '
  'l''elenco dei membri di un club non e esposto a nessuno, e public_clubs ne '
  'pubblica il solo conteggio.';

comment on column public.club_memberships.user_id is
  'Riempita dal DEFAULT auth.uid(), mai dal client: non e nel grant di '
  'INSERT. Nessun metodo del servizio accetta un userId.';

comment on column public.club_memberships.ruolo is
  'Colonna di dominio, fuori dal grant di INSERT e senza alcun grant di '
  'UPDATE: il client non la scrive. In 12a ha un solo valore possibile.';

-- La chiave primaria e (user_id, club_slug): il suo indice ha user_id come
-- colonna di testa, quindi "i club che seguo" e gia indicizzato e un indice
-- separato su user_id sarebbe una seconda copia da mantenere a ogni scrittura
-- senza una lettura che la usi. L'indice che manca davvero e quello sull'altra
-- direzione - "quanti seguono questo club" - che la chiave primaria non copre.
create index club_memberships_club_slug_idx
  on public.club_memberships (club_slug);

comment on index public.club_memberships_club_slug_idx is
  'Conteggio membri per club (public_clubs.membri) e, dal 12b, la lettura per '
  'club. La direzione per utente la copre gia l''indice della chiave primaria.';

-- SELECT di tabella e lecito qui: la RLS confina ogni ruolo client alle
-- proprie righe, quindi `authenticated` non raggiunge righe altrui. E' lo
-- stesso caso di bottle_units, non quello di reports.
revoke all on public.club_memberships from anon, authenticated;
grant select on public.club_memberships to authenticated;
-- L'unica colonna che il client nomina. `user_id` viene dal DEFAULT, `ruolo`
-- e `created_at` dai loro.
grant insert (club_slug) on public.club_memberships to authenticated;
grant delete on public.club_memberships to authenticated;
-- Nessun UPDATE, a nessuno: smettere di seguire e una DELETE, e `ruolo` non e
-- del client.

alter table public.club_memberships enable row level security;

create policy "club_memberships_select_own"
  on public.club_memberships for select to authenticated
  using (user_id = (select auth.uid()));

create policy "club_memberships_insert_own"
  on public.club_memberships for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy "club_memberships_delete_own"
  on public.club_memberships for delete to authenticated
  using (user_id = (select auth.uid()));

-- Primo livello della decisione 7.6b. Il guard e quello della 9b, invariato:
-- il suo ramo `else auth.uid()` copre gia le tabelle il cui attore non e una
-- colonna della riga. Un sospeso non segue e non smette di seguire; compra,
-- vende e paga come prima, perche nessun percorso di ordini o pagamenti passa
-- di qui.
create trigger club_memberships_scrittura_social_guard
  before insert on public.club_memberships
  for each row execute function private.scrittura_social_guard();

-- ---------------------------------------------------------------------------
-- public_clubs - la sola lettura dei club
-- ---------------------------------------------------------------------------
--
-- security_invoker = off con elenco di colonne chiuso, come public_listings e
-- come le quattro viste della 9a. Qui la vista non serve solo a chiudere le
-- colonne: serve a pubblicare due cose che la tabella base non ha e che il
-- client non puo calcolarsi da solo.
--
--   `membri`  - conteggio su club_memberships, che nessun client puo leggere
--               oltre le proprie righe. Senza la vista, "1.240 membri" sarebbe
--               un numero che il client non ha modo di ottenere, oppure il
--               prezzo sarebbe aprire in lettura l'elenco di chi segue cosa.
--   `seguito` - lo stato del solo chiamante, da auth.uid() dentro la vista.
--               Toglie un secondo giro di rete e, con esso, la possibilita che
--               le due risposte si contraddicano.
--
-- La vista non prende parametri: i filtri sono scritti dentro e nessun client
-- li rimuove. Il linter Supabase la segnalera come `security_definer_view`, ed
-- e la segnalazione attesa per questo pattern.

create view public.public_clubs
with (security_invoker = off, security_barrier = true)
as
select
  c.slug,
  c.nome,
  c.territorio,
  c.denominazione,
  c.produttore,
  c.tipologia,
  c.descrizione,
  c.regole,
  c.created_at,
  (
    select count(*)
    from public.club_memberships m
    where m.club_slug = c.slug
  )::integer as membri,
  exists (
    select 1
    from public.club_memberships m
    where m.club_slug = c.slug
      and m.user_id = (select auth.uid())
  ) as seguito
from public.clubs c
-- Secondo livello della decisione 7.6b, direzione entrante: un chiamante
-- rimosso non legge la superficie sociale. Per `anon` auth.uid() e nullo, il
-- not exists e vero e la vista non cambia. Stessa forma di public_listings.
where not exists (
  select 1 from public.profiles me
  where me.id = (select auth.uid())
    and me.stato_utente = 'rimosso'
);

comment on view public.public_clubs is
  'Club leggibili da chiunque, con il conteggio dei membri e lo stato di '
  '`seguito` del solo chiamante. Restituisce zero righe a un chiamante '
  'rimosso (decisione 7.6b, secondo livello); un chiamante anonimo non e '
  'toccato e vede seguito = false.';

revoke all on public.public_clubs from anon, authenticated;
grant select on public.public_clubs to anon, authenticated;
