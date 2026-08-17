-- Fase 12b - contenuti dei club scrivibili dagli utenti.
--
-- Secondo checkpoint della Fase 12. La 12a ha dato ai club righe reali e un
-- follow; qui arriva la prima superficie di TESTO PUBBLICO che un utente di
-- Vinea puo scrivere. E' funzionalita nuova, non parita con `frontend/`: la
-- versione servita ha i post in un file mock (src/data/communities.ts) e il
-- pulsante "Crea un post" era un toast dimostrativo. E' ammessa per eccezione
-- esplicita e per nome, la seconda dopo le quattro della Fase 11, ed e
-- inseparabile dalla 12c - nessun contenuto pubblico scrivibile va in
-- produzione senza un modo per segnalarlo (la stessa regola gia valida per la
-- decisione 7.6a, che aveva escluso `post` e `commento` dai bersagli proprio
-- perche i club non avevano schema).
--
-- QUESTO FILE NON VA MERGIATO SENZA I DUE DELLA 12C
--   20260817120500_phase_12c_report_target_enum.sql
--   20260817121000_phase_12c_club_moderation.sql
-- Sono tre file per una ragione di transazione, non tre decisioni: vedi il
-- cappello del secondo.
--
-- ---------------------------------------------------------------------------
-- LE TRE REGOLE DI ESPOSIZIONE (6d-1), applicate una per una
-- ---------------------------------------------------------------------------
--   1. nessun grant di tabella intera a un ruolo che raggiunge righe altrui.
--      `club_posts` e `club_post_risposte` sono leggibili da chiunque, quindi
--      il loro SELECT ad `authenticated` e a ELENCO DI COLONNE CHIUSO e la RLS
--      lo confina alle righe proprie: la lettura pubblica non passa di li, passa
--      dalle viste. `club_post_like` la RLS la confina alle righe proprie di
--      ogni ruolo client, quindi il grant di tabella e lecito - stesso caso di
--      club_memberships e di bottle_units.
--   2. la lettura pubblica passa da viste security_invoker = off a elenco di
--      colonne chiuso: public_club_posts e public_club_post_risposte. Una
--      colonna aggiunta domani a una tabella base resta privata finche
--      qualcuno non la elenca li dentro.
--   3. una colonna con una regola di dominio dietro non e scrivibile dal
--      client: `autore_id` arriva da un DEFAULT ed e fuori dal grant di
--      INSERT; `rimosso_at`, `rimosso_da` e `rimosso_motivo` sono fuori da
--      ogni grant e la loro unica porta arriva con la 12c.
--
-- ---------------------------------------------------------------------------
-- SOSPENSIONE E RIMOZIONE (decisione 7.6b)
-- ---------------------------------------------------------------------------
-- Scrivere un post, rispondere e mettere un like sono scritture social e
-- prendono il guard della 9b, INVARIATO. private.scrittura_social_guard() ha
-- gia il ramo `else auth.uid()` per le tabelle il cui attore non e nominato dal
-- corpo della funzione, ed e questo il caso di tutte e tre. La funzione non
-- viene ridefinita: un `create or replace` su una funzione della 9b per
-- aggiungerci un ramo che non serve rimetterebbe in produzione codice di
-- un'altra fase senza motivo.
--
-- Il secondo livello - che toglie anche l'accesso in visione - sta nelle due
-- viste pubbliche, con la stessa forma di public_clubs e public_listings: un
-- chiamante `rimosso` legge zero righe.
--
-- NESSUNA TABELLA DI ORDINI, PAGAMENTI, CONTESTAZIONI O PAYOUT E NOMINATA IN
-- QUESTO FILE. Il vincolo della 9c e soddisfatto per costruzione, e non per
-- una dichiarazione.

-- ---------------------------------------------------------------------------
-- club_posts
-- ---------------------------------------------------------------------------

create table public.club_posts (
  id uuid primary key default gen_random_uuid(),

  club_slug text not null
    references public.clubs (slug) on delete cascade,

  -- DEFAULT auth.uid() e non un parametro, come club_memberships.user_id in
  -- 12a: il client non ha grant di INSERT su questa colonna, quindi non puo
  -- nominarla nemmeno per sbaglio. La policy `with check` ripete la stessa
  -- cosa perche service_role scavalca i grant. Due lucchetti diversi sulla
  -- stessa porta, di proposito: il grant e cio che regge se domani qualcuno
  -- aggiunge una policy piu larga.
  --
  -- Il riferimento e a public.profiles e non ad auth.users: e la convenzione
  -- di ogni tabella di questo progetto (club_memberships, reports,
  -- bottle_units), e profiles.id e gia la proiezione applicativa di auth.users.
  autore_id uuid not null default auth.uid()
    references public.profiles (id) on delete cascade,

  -- CHECK e non enum, deliberatamente e in controtendenza rispetto al resto
  -- del progetto. I sette valori sono etichette di filtro della UI, copiate da
  -- PostTipo (frontend/src/data/communities.ts:134-135), non gli stati di una
  -- macchina: allargarli e una modifica di prodotto, e con un CHECK e un
  -- drop/add constraint invece della cerimonia che questa stessa fase ha
  -- appena pagato per report_target_tipo (vedi il file dell'enum).
  --
  -- `sondaggio` e fra i sette e NON ha schema di sondaggio: nessuna tabella di
  -- opzioni, nessun voto. E' un post con titolo e corpo come gli altri. Il
  -- valore esiste perche la UI mock lo filtrava; costruire il sondaggio vero
  -- sarebbe funzionalita nuova che nessuna sessione ha chiesto per nome.
  tipo text not null check (tipo in (
    'discussione', 'domanda', 'degustazione', 'confronto',
    'consiglio', 'sondaggio', 'annuncio'
  )),

  titolo text not null
    check (titolo = btrim(titolo) and length(titolo) between 3 and 160),
  corpo text not null
    check (corpo = btrim(corpo) and length(corpo) between 1 and 8000),

  -- I tre allegati facoltativi. Tutti `on delete set null`: un post e una
  -- discussione, e deve sopravvivere alla sparizione di cio a cui rimanda -
  -- lo stesso motivo per cui le cinque foreign key di bersaglio della 9a non
  -- sono `cascade`.
  --
  -- bottle_unit_id: dev'essere una bottiglia dell'autore. Verificato dal
  -- trigger piu sotto, che legge bottle_units e MAI cellar_environments:
  -- l'ambiente di cantina resta privato anche quando la bottiglia che
  -- contiene finisce in un post.
  bottle_unit_id uuid references public.bottle_units (id) on delete set null,
  wine_id uuid references public.wines (id) on delete set null,
  -- listing_id: vedi private.club_post_riferimenti_guard per le due condizioni.
  listing_id uuid references public.listings (id) on delete set null,

  -- Rimozione LOGICA, mai una DELETE fisica: una segnalazione deve
  -- sopravvivere alla rimozione di cio che segnala, o moderare cancellerebbe
  -- la prova del perche.
  --
  -- Queste tre colonne sono della 12b perche le viste pubbliche qui sotto
  -- devono filtrare su `rimosso_at is null` fin dalla prima riga; l'UNICA
  -- PORTA che le scrive arriva con la 12c. La divisione e voluta: la forma del
  -- dato esiste prima della vista che la rispetta, altrimenti ci sarebbe un
  -- momento - dentro lo stesso merge - in cui la vista pubblica non sa cosa
  -- nascondere.
  rimosso_at timestamptz,
  rimosso_da uuid references public.profiles (id) on delete set null,
  rimosso_motivo text
    check (rimosso_motivo is null or length(btrim(rimosso_motivo)) between 1 and 4000),

  created_at timestamptz not null default now(),

  -- Rimosso senza motivo non e uno stato: la 9a impone la motivazione come
  -- vincolo di database su audit_log, e qui vale la stessa cosa sul bersaglio.
  constraint club_posts_rimozione_coerente check (
    (rimosso_at is null) = (rimosso_motivo is null)
  ),
  -- Un post di tipo `annuncio` senza annuncio collegato e un titolo "Vendo…"
  -- che non porta da nessuna parte. Gli altri sei tipi non lo richiedono.
  constraint club_posts_annuncio_ha_listing check (
    tipo <> 'annuncio' or listing_id is not null
  )
);

comment on table public.club_posts is
  'Discussioni di un club. Lettura pubblica attraverso public_club_posts; '
  'nessun ruolo client legge questa tabella oltre le proprie righe. La '
  'rimozione e logica (rimosso_at) e la sua unica porta e in 12c.';

comment on column public.club_posts.autore_id is
  'Riempita dal DEFAULT auth.uid(), mai dal client: non e nel grant di INSERT '
  'e nemmeno in quello di UPDATE. Nessun metodo del servizio accetta un userId.';

comment on column public.club_posts.tipo is
  'Uno dei sette valori di PostTipo del mock. CHECK e non enum: sono etichette '
  'di filtro della UI, non stati di una macchina. `sondaggio` non ha schema di '
  'sondaggio: e un post con titolo e corpo come gli altri.';

comment on column public.club_posts.bottle_unit_id is
  'Bottiglia dell''autore, verificata dal trigger dei riferimenti. La vista '
  'pubblica non ripubblica questo identificativo: espone il VINO, mai l''id '
  'della bottiglia, cosi nessuno correla una cantina fra piu post.';

comment on column public.club_posts.listing_id is
  'Annuncio collegato. Sempre pubblico; in piu, se tipo = ''annuncio'', '
  'dell''autore stesso. Vedi private.club_post_riferimenti_guard.';

comment on column public.club_posts.rimosso_at is
  'Rimozione logica decisa dalla moderazione. Fuori da ogni grant di UPDATE: '
  'l''unica porta e la 12c. Un post rimosso non e leggibile da public_club_posts '
  'e non e piu modificabile dal suo autore.';

-- Il feed di un club legge sempre e solo i post non rimossi, in ordine
-- cronologico inverso: l'indice e parziale su quella condizione perche le
-- righe rimosse non sono mai in nessuna lettura di elenco.
create index club_posts_club_idx
  on public.club_posts (club_slug, created_at desc)
  where rimosso_at is null;

-- La direzione per autore serve alla policy di UPDATE e alla lettura delle
-- proprie righe, rimosse comprese: nessun filtro parziale qui.
create index club_posts_autore_idx
  on public.club_posts (autore_id, created_at desc);

-- Le due colonne che la 12c risolve all'indietro, da segnalazione a bersaglio.
create index club_posts_listing_idx
  on public.club_posts (listing_id) where listing_id is not null;

revoke all on public.club_posts from anon, authenticated;

-- SELECT a elenco di colonne chiuso e non di tabella: `rimosso_da` e
-- `rimosso_motivo` restano fuori, come listings.stato_motivo dalla 6d-1.
-- L'autore vede CHE il suo post e stato rimosso (`rimosso_at`), non da chi ne
-- con che motivazione: quella e una proiezione dedicata, e non e in questo
-- checkpoint. La RLS confina comunque questo SELECT alle righe proprie -
-- la lettura pubblica passa dalla vista.
grant select (
  id, club_slug, autore_id, tipo, titolo, corpo,
  bottle_unit_id, wine_id, listing_id, rimosso_at, created_at
) on public.club_posts to authenticated;

-- Le sette colonne che il client nomina alla creazione. `autore_id`,
-- `created_at` e le tre di rimozione vengono dai loro default o da nessuno.
grant insert (
  club_slug, tipo, titolo, corpo, bottle_unit_id, wine_id, listing_id
) on public.club_posts to authenticated;

-- Solo il testo si corregge. Mai `autore_id`, `club_slug`, `tipo`,
-- `bottle_unit_id`, `wine_id`, `listing_id` dopo la creazione: spostare un post
-- in un altro club o cambiarne l'annuncio collegato dopo che qualcuno lo ha
-- letto o segnalato e un'altra cosa dal correggere un refuso.
grant update (titolo, corpo) on public.club_posts to authenticated;

-- Nessun DELETE, a nessuno: la rimozione e logica e appartiene alla
-- moderazione. La cancellazione del proprio post da parte dell'autore non e in
-- questo checkpoint e non ha porta.

alter table public.club_posts enable row level security;

create policy "club_posts_select_own"
  on public.club_posts for select to authenticated
  using (autore_id = (select auth.uid()));

create policy "club_posts_insert_own"
  on public.club_posts for insert to authenticated
  with check (autore_id = (select auth.uid()));

-- `rimosso_at is null` in entrambi i rami: un post che la moderazione ha
-- rimosso non e piu modificabile dal suo autore. Senza questa condizione un
-- eventuale ripristino restituirebbe al club un testo diverso da quello che il
-- moderatore aveva letto.
create policy "club_posts_update_own"
  on public.club_posts for update to authenticated
  using (autore_id = (select auth.uid()) and rimosso_at is null)
  with check (autore_id = (select auth.uid()) and rimosso_at is null);

-- ---------------------------------------------------------------------------
-- club_post_risposte
-- ---------------------------------------------------------------------------
-- Un solo livello: nessun parent_risposta_id, nessun thread annidato. Non e
-- una semplificazione provvisoria, e il perimetro - un albero di risposte
-- porta con se profondita massima, ordinamento, collasso e una UI che nessuna
-- sessione ha chiesto.

create table public.club_post_risposte (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.club_posts (id) on delete cascade,
  autore_id uuid not null default auth.uid()
    references public.profiles (id) on delete cascade,
  corpo text not null
    check (corpo = btrim(corpo) and length(corpo) between 1 and 4000),

  rimosso_at timestamptz,
  rimosso_da uuid references public.profiles (id) on delete set null,
  rimosso_motivo text
    check (rimosso_motivo is null or length(btrim(rimosso_motivo)) between 1 and 4000),

  created_at timestamptz not null default now(),

  constraint club_post_risposte_rimozione_coerente check (
    (rimosso_at is null) = (rimosso_motivo is null)
  )
);

comment on table public.club_post_risposte is
  'Risposte a una discussione, un solo livello. Lettura pubblica attraverso '
  'public_club_post_risposte. Rimozione logica, porta in 12c.';

create index club_post_risposte_post_idx
  on public.club_post_risposte (post_id, created_at)
  where rimosso_at is null;

create index club_post_risposte_autore_idx
  on public.club_post_risposte (autore_id, created_at desc);

revoke all on public.club_post_risposte from anon, authenticated;

grant select (id, post_id, autore_id, corpo, rimosso_at, created_at)
  on public.club_post_risposte to authenticated;
grant insert (post_id, corpo) on public.club_post_risposte to authenticated;
grant update (corpo) on public.club_post_risposte to authenticated;

alter table public.club_post_risposte enable row level security;

create policy "club_post_risposte_select_own"
  on public.club_post_risposte for select to authenticated
  using (autore_id = (select auth.uid()));

create policy "club_post_risposte_insert_own"
  on public.club_post_risposte for insert to authenticated
  with check (autore_id = (select auth.uid()));

create policy "club_post_risposte_update_own"
  on public.club_post_risposte for update to authenticated
  using (autore_id = (select auth.uid()) and rimosso_at is null)
  with check (autore_id = (select auth.uid()) and rimosso_at is null);

-- ---------------------------------------------------------------------------
-- club_post_like
-- ---------------------------------------------------------------------------
-- Chiave composita e non un id tecnico: mettere due volte il like allo stesso
-- post non e un secondo like, e lo stesso. Il conflitto di chiave primaria e
-- il modo in cui il database lo dice, e l'adapter lo tratta come stato voluto
-- e non come errore - esattamente come 12a fa con il follow.

create table public.club_post_like (
  user_id uuid not null default auth.uid()
    references public.profiles (id) on delete cascade,
  post_id uuid not null references public.club_posts (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);

comment on table public.club_post_like is
  'Chi ha messo mi piace a quale post. Un utente vede e scrive soltanto le '
  'proprie righe: l''elenco di chi ha messo like non e esposto a nessuno, e '
  'public_club_posts ne pubblica il solo conteggio piu lo stato del chiamante.';

-- La chiave primaria ha user_id in testa, quindi "i post a cui ho messo like"
-- e gia indicizzato. Manca l'altra direzione - "quanti like ha questo post" -
-- che e quella che la vista conta.
create index club_post_like_post_idx on public.club_post_like (post_id);

revoke all on public.club_post_like from anon, authenticated;
-- SELECT di tabella lecito: la RLS confina ogni ruolo client alle proprie
-- righe, quindi `authenticated` non raggiunge righe altrui. Stesso caso di
-- club_memberships.
grant select on public.club_post_like to authenticated;
grant insert (post_id) on public.club_post_like to authenticated;
grant delete on public.club_post_like to authenticated;
-- Nessun UPDATE: togliere il like e una DELETE.

alter table public.club_post_like enable row level security;

create policy "club_post_like_select_own"
  on public.club_post_like for select to authenticated
  using (user_id = (select auth.uid()));

create policy "club_post_like_insert_own"
  on public.club_post_like for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy "club_post_like_delete_own"
  on public.club_post_like for delete to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- private.club_post_riferimenti_guard - i tre allegati, piu il rate limit
-- ---------------------------------------------------------------------------
--
-- PERCHE UN TRIGGER E NON UNA RPC. Stessa ragione della 9b: un controllo dentro
-- una funzione vincola quella funzione, un trigger vincola la TABELLA - vale
-- per ogni percorso presente e futuro, service_role compreso. Qui in piu la
-- scrittura e un INSERT diretto con RLS, come il follow della 12a, quindi una
-- RPC non esisterebbe nemmeno.
--
-- PERCHE SECURITY DEFINER. Legge bottle_units e listings, che il chiamante non
-- puo leggere per le righe altrui - ed e proprio delle righe altrui che deve
-- accertarsi. `set search_path = ''` come ogni funzione del progetto.
--
-- LISTING_ID, LE DUE CONDIZIONI E DA DOVE VENGONO. Il brief chiedeva di non
-- assumere quale caso si applichi ma di leggerlo dalla UI mock. I due post di
-- tipo `annuncio` in frontend/src/data/communities.ts sono "Vendo Barolo
-- Brunate 2018" (:179) e "Vendo Magnum Ornellaia 2017" (:265): in entrambi
-- l'autore del post E il venditore, e il post annuncia la PROPRIA vendita.
-- Quindi:
--   1. sempre, per ogni tipo: l'annuncio dev'essere PUBBLICAMENTE VISIBILE.
--      Un post che rimanda a una bozza manderebbe i lettori del club su
--      qualcosa che nessuno di loro puo aprire. La condizione e letta da
--      public_listings e non riscritta a mano, cosi "pubblico" resta definito
--      in un posto solo.
--   2. in piu, se tipo = 'annuncio': dev'essere DELL'AUTORE. Senza questa,
--      "Vendo Magnum Ornellaia" potrebbe puntare all'annuncio di un terzo -
--      pubblicita non richiesta nel caso benevolo, dirottamento di traffico
--      nell'altro.
-- Per gli altri sei tipi listing_id resta un riferimento ("che ne pensate di
-- questa bottiglia in vendita?"), quindi la sola condizione 1.
--
-- Le due condizioni sono verificate all'INSERIMENTO. Un annuncio che dopo
-- viene sospeso o venduto lascia il post con un riferimento che la vista
-- pubblica smette di risolvere - il post resta leggibile e il riquadro
-- dell'annuncio sparisce. Nascondere il post cancellerebbe una discussione per
-- un fatto che riguarda un suo allegato.
--
-- IL RATE LIMIT. Nessuna sessione l'ha chiesto, e non e funzionalita: e la
-- convenzione di ogni scrittura social del progetto - message:send 30/60 e
-- conversation:open 20/60 nella Fase 8, report:submit 10/3600 nella 9a, i tre
-- bucket IA della Fase 10. Una superficie di testo PUBBLICO senza bucket
-- dedicato sarebbe l'unica. Il tetto globale di private.vinea_check_request
-- (120 scritture/minuto su tabella) esiste ma non e un numero scelto per i
-- club. 10/ora e la cadenza di report:submit: un post e scrittura ponderata,
-- non una battuta di chat. E' un valore di sessione, come i tre della Fase 10
-- che una sessione successiva dovette correggere: si riapre su uso osservato.

create or replace function private.club_post_riferimenti_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  -- Solo per un chiamante vero: per service_role auth.uid() e nullo e non
  -- esiste un soggetto da limitare. Il seed non consuma il bucket di nessuno.
  if v_uid is not null then
    perform private.rate_limit_consume('club:post', 'user:' || v_uid::text, 10, 3600);
  end if;

  if new.bottle_unit_id is not null then
    -- `deleted_at is null`: la cantina cancella in logica, e una bottiglia
    -- cancellata non e piu una bottiglia dell'autore.
    if not exists (
      select 1 from public.bottle_units bu
      where bu.id = new.bottle_unit_id
        and bu.owner_id = new.autore_id
        and bu.deleted_at is null
    ) then
      raise exception 'Puoi collegare soltanto una bottiglia della tua cantina.'
        using errcode = '42501';
    end if;
  end if;

  if new.listing_id is not null then
    if not exists (
      select 1 from public.public_listings pl where pl.id = new.listing_id
    ) then
      raise exception 'L''annuncio collegato non e pubblico o non esiste piu.'
        using errcode = 'P0001';
    end if;

    if new.tipo = 'annuncio' and not exists (
      select 1 from public.listings l
      where l.id = new.listing_id and l.seller_id = new.autore_id
    ) then
      raise exception
        'Un post di tipo annuncio puo collegare soltanto un tuo annuncio.'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

comment on function private.club_post_riferimenti_guard() is
  'Verifica i tre allegati di un post e consuma il bucket club:post. La '
  'bottiglia dev''essere dell''autore; l''annuncio dev''essere pubblico e, per '
  'un post di tipo annuncio, anche dell''autore. Legge bottle_units, mai '
  'cellar_environments: l''ambiente di cantina resta privato.';

-- ---------------------------------------------------------------------------
-- private.club_post_immutabile_guard - cosa non cambia dopo la creazione
-- ---------------------------------------------------------------------------
-- Il grant a colonna gia impedisce al client di nominare queste colonne in un
-- UPDATE. Il trigger esiste perche service_role scavalca i grant e perche una
-- policy piu larga scritta domani non deve poter spostare un post in un altro
-- club. E' la stessa forma di private.profiles_stato_utente_guard della 9b.

create or replace function private.club_post_immutabile_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.autore_id is distinct from old.autore_id
     or new.club_slug is distinct from old.club_slug
     or new.tipo is distinct from old.tipo
     or new.bottle_unit_id is distinct from old.bottle_unit_id
     or new.wine_id is distinct from old.wine_id
     or new.listing_id is distinct from old.listing_id
     or new.created_at is distinct from old.created_at then
    raise exception
      'Di un post pubblicato si correggono solo titolo e testo.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

comment on function private.club_post_immutabile_guard() is
  'Congela autore, club, tipo, allegati e data di un post gia pubblicato. Non '
  'SECURITY DEFINER: confronta old e new e solleva, non legge nulla.';

-- ---------------------------------------------------------------------------
-- private.club_post_figlio_guard - risposte e like
-- ---------------------------------------------------------------------------
-- Una sola funzione per le due tabelle, sul modello di
-- private.scrittura_social_guard: il corpo e lo stesso e il bucket lo decide
-- tg_table_name. La riga passa da jsonb per la stessa ragione della 9b - le
-- due tabelle hanno colonne diverse e plpgsql risolve i riferimenti di campo
-- alla compilazione.
--
-- NESSUN BUCKET PER I LIKE. Un like e idempotente (conflitto di chiave
-- primaria) e reversibile: un bucket punirebbe l'uso normale, e il tetto
-- globale di vinea_check_request copre gia il caso patologico. Le risposte
-- hanno 30/ora: rispondere e piu frequente che aprire una discussione.

create or replace function private.club_post_figlio_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_riga jsonb := to_jsonb(new);
  v_post_id uuid := (v_riga->>'post_id')::uuid;
begin
  if tg_table_name = 'club_post_risposte' and v_uid is not null then
    perform private.rate_limit_consume(
      'club:risposta', 'user:' || v_uid::text, 30, 3600
    );
  end if;

  -- Il post dev'esistere e non essere stato rimosso. Senza questo controllo si
  -- risponderebbe a una discussione che la moderazione ha tolto, e la risposta
  -- resterebbe invisibile a chiunque senza che il suo autore lo sappia.
  if not exists (
    select 1 from public.club_posts p
    where p.id = v_post_id and p.rimosso_at is null
  ) then
    raise exception 'Questa discussione non e piu disponibile.'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

comment on function private.club_post_figlio_guard() is
  'Verifica che il post padre esista e non sia stato rimosso, e consuma '
  'club:risposta per le sole risposte. Serve club_post_risposte e '
  'club_post_like con lo stesso corpo, come scrittura_social_guard nella 9b.';

-- ---------------------------------------------------------------------------
-- I trigger
-- ---------------------------------------------------------------------------
-- Primo livello della decisione 7.6b su tutte e tre le tabelle: un sospeso non
-- scrive nei club, ne un post ne una risposta ne un like. Compra, vende e paga
-- come prima, perche nessun percorso di ordini o pagamenti passa di qui.

create trigger club_posts_scrittura_social_guard
  before insert on public.club_posts
  for each row execute function private.scrittura_social_guard();

create trigger club_posts_riferimenti_guard
  before insert on public.club_posts
  for each row execute function private.club_post_riferimenti_guard();

create trigger club_posts_immutabile_guard
  before update on public.club_posts
  for each row execute function private.club_post_immutabile_guard();

create trigger club_post_risposte_scrittura_social_guard
  before insert on public.club_post_risposte
  for each row execute function private.scrittura_social_guard();

create trigger club_post_risposte_figlio_guard
  before insert on public.club_post_risposte
  for each row execute function private.club_post_figlio_guard();

create trigger club_post_like_scrittura_social_guard
  before insert on public.club_post_like
  for each row execute function private.scrittura_social_guard();

create trigger club_post_like_figlio_guard
  before insert on public.club_post_like
  for each row execute function private.club_post_figlio_guard();

-- ---------------------------------------------------------------------------
-- public_club_posts - la lettura pubblica delle discussioni
-- ---------------------------------------------------------------------------
--
-- security_invoker = off con elenco di colonne chiuso, come public_clubs e
-- public_listings. La vista non serve solo a chiudere le colonne: pubblica
-- quattro cose che la tabella base non ha e che il client non puo calcolarsi
-- da solo.
--
--   risposte / mi_piace  conteggi su tabelle che nessun client legge oltre le
--                        proprie righe. Senza la vista, "12 risposte" sarebbe
--                        un numero irrecuperabile, oppure il prezzo sarebbe
--                        aprire in lettura l'elenco di chi ha messo like a
--                        cosa.
--   piaciuto             lo stato del solo chiamante, da auth.uid() dentro la
--                        vista. Toglie un secondo giro di rete e con esso la
--                        possibilita che le due risposte si contraddicano.
--   mio                  se il post e del chiamante: la UI ci decide se
--                        mostrare "Segnala" o no. Non si segnala se stessi.
--
-- IL VINO SI, L'IDENTIFICATIVO DELLA BOTTIGLIA NO. La vista risolve il vino da
-- `wine_id` oppure dalla bottiglia collegata, e non ripubblica
-- `bottle_unit_id`. Cio che l'autore ha reso pubblico e la bottiglia di cui
-- parla, non la chiave con cui la sua cantina la nomina: senza questa
-- distinzione due post dello stesso utente permetterebbero a chiunque di
-- correlare pezzi della sua cantina.

create view public.public_club_posts
with (security_invoker = off, security_barrier = true)
as
select
  p.id,
  p.club_slug,
  p.tipo,
  p.titolo,
  p.corpo,
  p.created_at,

  p.autore_id,
  au.username   as autore_username,
  au.avatar_url as autore_avatar_url,

  -- Il vino di cui il post parla, da wine_id o dalla bottiglia collegata.
  w.slug        as vino_slug,
  w.produttore  as vino_produttore,
  w.nome        as vino_nome,
  w.annata      as vino_annata,

  -- L'annuncio collegato, risolto attraverso public_listings: se nel
  -- frattempo e stato sospeso o venduto, il left join non trova nulla e questi
  -- campi sono nulli. Il post resta.
  p.listing_id,
  pl.slug         as listing_slug,
  pl.prezzo_cents as listing_prezzo_cents,

  (
    select count(*)
    from public.club_post_risposte r
    where r.post_id = p.id and r.rimosso_at is null
  )::integer as risposte,
  (
    select count(*)
    from public.club_post_like l
    where l.post_id = p.id
  )::integer as mi_piace,
  exists (
    select 1
    from public.club_post_like l
    where l.post_id = p.id and l.user_id = (select auth.uid())
  ) as piaciuto,
  (p.autore_id = (select auth.uid())) as mio
from public.club_posts p
  join public.profiles au on au.id = p.autore_id
  left join public.bottle_units bu on bu.id = p.bottle_unit_id
  left join public.wines w on w.id = coalesce(p.wine_id, bu.wine_id)
  left join public.public_listings pl on pl.id = p.listing_id
where p.rimosso_at is null
  -- Secondo livello della decisione 7.6b, direzione entrante: un chiamante
  -- rimosso non legge la superficie sociale. Per `anon` auth.uid() e nullo, il
  -- not exists e vero e la vista non cambia. Stessa forma di public_clubs.
  and not exists (
    select 1 from public.profiles me
    where me.id = (select auth.uid())
      and me.stato_utente = 'rimosso'
  );

comment on view public.public_club_posts is
  'Discussioni leggibili da chiunque, con i conteggi di risposte e like, lo '
  'stato `piaciuto` del solo chiamante e il vino di cui parlano. Non espone '
  'bottle_unit_id. Restituisce zero righe a un chiamante rimosso (7.6b, '
  'secondo livello); un chiamante anonimo non e toccato.';

revoke all on public.public_club_posts from anon, authenticated;
grant select on public.public_club_posts to anon, authenticated;

-- ---------------------------------------------------------------------------
-- public_club_post_risposte
-- ---------------------------------------------------------------------------
-- Il doppio filtro sulla rimozione - della risposta E del post padre - non e
-- ridondante: rimuovere un post deve far sparire la discussione intera dalla
-- lettura pubblica senza dover toccare una per una le sue risposte, che
-- restano al loro posto per l'eventuale ripristino.

create view public.public_club_post_risposte
with (security_invoker = off, security_barrier = true)
as
select
  r.id,
  r.post_id,
  r.corpo,
  r.created_at,
  r.autore_id,
  au.username   as autore_username,
  au.avatar_url as autore_avatar_url,
  (r.autore_id = (select auth.uid())) as mio
from public.club_post_risposte r
  join public.profiles au on au.id = r.autore_id
  join public.club_posts p on p.id = r.post_id
where r.rimosso_at is null
  and p.rimosso_at is null
  and not exists (
    select 1 from public.profiles me
    where me.id = (select auth.uid())
      and me.stato_utente = 'rimosso'
  );

comment on view public.public_club_post_risposte is
  'Risposte leggibili da chiunque. Filtra sia la rimozione della risposta sia '
  'quella del post padre: rimuovere un post fa sparire la discussione intera '
  'senza toccare le sue risposte, che restano per l''eventuale ripristino.';

revoke all on public.public_club_post_risposte from anon, authenticated;
grant select on public.public_club_post_risposte to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Privilegi delle funzioni
-- ---------------------------------------------------------------------------
-- Nessuna delle tre e invocabile da un client: sono corpi di trigger.

revoke execute on function
  private.club_post_riferimenti_guard(),
  private.club_post_immutabile_guard(),
  private.club_post_figlio_guard()
  from public, anon, authenticated;

notify pgrst, 'reload schema';
