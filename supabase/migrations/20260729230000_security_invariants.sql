-- ===========================================================================
-- Fase 6d-1 — Confini di autorizzazione e invarianti bottiglia–annuncio.
--
-- Non è una migrazione di dati: le fonti restano quelle di 6a/6b/6c. Qui
-- cambiano policy, privilegi e percorsi di scrittura, e alcuni flussi cambiano
-- di proposito.
--
-- LA REGOLA CHE QUESTA MIGRAZIONE APPLICA OVUNQUE, e che vale da qui in poi:
-- nessun privilegio di lettura su tabella intera verso un ruolo che può
-- raggiungere righe non proprie. Ciò che è pubblico si espone da una vista
-- `security_invoker = off` a elenco chiuso di colonne; ciò che ha una regola
-- dietro passa da una funzione SECURITY DEFINER e non da un UPDATE del browser.
-- È lo stesso pattern con cui la 6a ha tolto `listings.stato` dai GRANT di
-- colonna, esteso alle colonne che nel frattempo sono diventate sensibili.
--
-- ORDINE DI LETTURA E DI ESECUZIONE. Prima si crea tutto ciò che dovrà servire
-- (colonna, funzioni, trigger, indice, viste), poi si concede, e soltanto alla
-- fine si revoca e si sostituiscono le policy. L'ordine inverso lascerebbe, fra
-- una statement e l'altra, una finestra in cui /esplora e /cantina non hanno da
-- dove leggere.
--
-- ATOMICITÀ. Il file non contiene BEGIN/COMMIT espliciti, ed è deliberato:
-- `supabase db push` avvolge già ogni migrazione in una transazione propria, e
-- un COMMIT qui dentro la chiuderebbe prima che la CLI registri la migrazione
-- come applicata. Incollato nel SQL Editor, l'intero contenuto viaggia come un
-- unico messaggio di simple query, che PostgreSQL avvolge in una transazione
-- implicita: se una statement fallisce, tutte tornano indietro. In entrambe le
-- vie l'applicazione è tutto-o-niente.
--
-- RI-ESEGUIBILITÀ. Ogni statement è idempotente — `if not exists` su colonna e
-- indici, `drop … if exists` prima di trigger e policy, `create or replace` su
-- funzioni e viste. Serve perché la garanzia di cui sopra riguarda il database,
-- non l'operatore: un'applicazione interrotta a metà, o rilanciata per scrupolo,
-- non deve lasciare il file bloccato su un «relation already exists» che
-- costringa a modificarlo a mano.
--
-- COSA RESTA FUORI, E PERCHÉ:
--   * Il trasferimento di proprietà della bottiglia al compratore. Non esiste
--     in frontend/ e sarebbe funzionalità nuova. `ceduta_at` nasce qui pronta
--     ad accoglierlo, ma nessuno la legge come "cambio di proprietario".
--   * La funzione che porta un annuncio a 'venduto': è Fase 7. Al suo posto un
--     trigger, che intercetta la transizione da qualunque origine arrivi.
--   * Stripe Connect e KYC. L'abilitazione venditore e l'onboarding del conto
--     di pagamento saranno richiesti prima di qualunque payout reale: qui non
--     c'è nulla che li sostituisca, e il controllo dell'età non è una verifica
--     d'identità.
--   * Lo scheduler che materializza le scadenze. Qui la scadenza si applica in
--     lettura (la proiezione pubblica la esclude); la spazzata periodica resta
--     lavoro schedulato, registrato nel backlog.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- [0] Precondizione del punto G — fallire rumorosamente, non con un 23505
-- ---------------------------------------------------------------------------
-- L'indice unico più sotto estende il vincolo dai due stati vivi a tutti e
-- cinque quelli non terminali. Un indice si crea dopo che i dati esistono, e
-- `listing_crea` fino a oggi ammette esplicitamente più bozze sulla stessa
-- bottiglia: se ce ne sono, la CREATE INDEX fallisce con un 23505 che nomina un
-- indice e non dice cosa fare. Questo blocco lo anticipa con un messaggio che
-- rimanda alla query di bonifica.

do $$
declare
  v_violazioni integer;
begin
  select count(*) into v_violazioni
  from (
    select l.bottle_unit_id
    from public.listings l
    where l.stato in ('bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato')
    group by l.bottle_unit_id
    having count(*) > 1
  ) as duplicati;

  if v_violazioni > 0 then
    raise exception
      'Fase 6d-1: % bottiglie hanno più di un annuncio non terminale. Esegui supabase/tests/6d-1_preflight.sql (rilevamento, bonifica, riverifica) prima di applicare questa migrazione.',
      v_violazioni
      using errcode = 'P0001';
  end if;
end;
$$;


-- ---------------------------------------------------------------------------
-- [1] bottle_units.ceduta_at — il marcatore di uscita dal possesso
-- ---------------------------------------------------------------------------
-- IL BUCO CHE CHIUDE. L'indice parziale della 6a copre ('attivo', 'riservato'):
-- quando un annuncio passa a 'venduto' esce dall'indice, la bottiglia torna
-- libera e il venditore può ripubblicare una bottiglia che ha già venduto.
-- Quel comportamento era voluto per un annuncio scaduto o ritirato — la
-- bottiglia è ancora sua, può rimetterla in vendita — ma non per una vendita
-- conclusa, dove la bottiglia non è più sua.
--
-- Serviva quindi distinguere "l'annuncio è finito" da "la bottiglia se n'è
-- andata", e sono due fatti diversi che vivono su due tabelle diverse.
--
-- COSA NON È. Non è un cambio di proprietario: `owner_id` non si muove, e il
-- compratore non compare da nessuna parte. È una data che dice "questa unità è
-- uscita dal possesso di chi la possedeva", ed è tutto ciò che serve per
-- impedire che venga rivenduta. Il trasferimento vero è debito dichiarato.

alter table public.bottle_units
  add column if not exists ceduta_at timestamptz;

comment on column public.bottle_units.ceduta_at is
  'Data in cui l''unità è uscita dal possesso del proprietario, valorizzata dal '
  'trigger listings_marca_bottiglia_ceduta quando un annuncio entra in '
  '''venduto''. NON è un trasferimento di proprietà: owner_id non cambia e il '
  'compratore non è registrato da nessuna parte — quello è lavoro della Fase 7. '
  'Serve a impedire che una bottiglia già venduta torni in vendita.';

-- L'indice serve al trigger di idoneità e alle letture della cantina, che
-- filtrano sempre insieme "non cancellata" e "non ceduta".
create index if not exists bottle_units_in_possesso_idx
  on public.bottle_units (owner_id)
  where deleted_at is null and ceduta_at is null;


-- ---------------------------------------------------------------------------
-- [2] utente_maggiorenne — il controllo età come confine server-side
-- ---------------------------------------------------------------------------
-- IL CONTROLLO CLIENT NON È UN CONFINE. `AgeGate.tsx` rimanda a
-- /completa-profilo chi ha una sessione e `dob` vuoto, ma è un componente React:
-- ogni funzione di questo schema è raggiungibile con una POST diretta a
-- PostgREST, senza passare da nessuna interfaccia.
--
-- Il buco è reale e ha una data di nascita precisa: la 5b ha tolto il NOT NULL
-- da profiles.dob perché Google e Facebook non forniscono la data e il trigger
-- handle_new_user() falliva al primo accesso social. Da allora un profilo OAuth
-- senza età dichiarata esiste legittimamente — e `listing_crea` controlla che il
-- profilo esista, non che dichiari un'età.
--
-- FAIL-CLOSED. Profilo assente, `dob` nullo, o data che non raggiunge i 18 anni:
-- tutti e tre restituiscono falso. Il CHECK su profiles.dob non basta da solo,
-- proprio perché in PostgreSQL un CHECK con valore NULL vale NULL e passa.
--
-- RESTA UNA DICHIARAZIONE AUTO-RIFERITA, non una verifica documentale. Non
-- sostituisce l'abilitazione venditore né l'onboarding del conto di pagamento,
-- che andranno richiesti prima di qualunque payout reale.

create or replace function public.utente_maggiorenne(p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = p_user_id
      and p.dob is not null
      and p.dob <= (current_date - interval '18 years')
  );
$$;

comment on function public.utente_maggiorenne(uuid) is
  'Vero solo se esiste un profilo con data di nascita dichiarata e almeno 18 '
  'anni compiuti. Fail-closed: profilo mancante o dob nullo restituiscono '
  'falso. Dichiarazione auto-riferita, non verifica d''identità.';

-- Nessun ruolo client la esegue: la usano solo le funzioni di vendita, che sono
-- SECURITY DEFINER e girano con i privilegi del proprietario. Esporla darebbe a
-- chiunque un modo di sapere se un dato utente è maggiorenne.
revoke execute on function public.utente_maggiorenne(uuid) from public;


-- ---------------------------------------------------------------------------
-- [3] Il trigger che valorizza ceduta_at
-- ---------------------------------------------------------------------------
-- PERCHÉ UN TRIGGER E NON LA FUNZIONE DI TRANSIZIONE. La funzione che porta un
-- annuncio a 'venduto' non esiste: le transizioni di vendita ('riservato',
-- 'venduto') sono Fase 7, e scriverle qui significherebbe iniziare quella fase.
-- Un trigger ottiene lo stesso invariante senza costruirla, e lo ottiene meglio:
-- intercetta la transizione da qualunque origine arrivi — oggi un UPDATE da
-- service_role nel SQL Editor, domani la RPC di Fase 7 — invece di dipendere dal
-- fatto che ogni scrittore futuro si ricordi di aggiornare anche l'unità.
--
-- NOTA PER LA FASE 7: questo trigger esiste. La RPC che chiuderà una vendita non
-- deve valorizzare `ceduta_at` per conto suo, o si sovrascriverebbero a vicenda.
--
-- `coalesce(ceduta_at, now())` rende l'operazione idempotente: una seconda
-- scrittura sullo stesso annuncio non sposta la data della prima cessione.

create or replace function public.listings_marca_bottiglia_ceduta()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.stato = 'venduto'
     and (tg_op = 'INSERT' or old.stato is distinct from 'venduto') then
    update public.bottle_units
    set ceduta_at = coalesce(ceduta_at, now())
    where id = new.bottle_unit_id;
  end if;
  return null;
end;
$$;

comment on function public.listings_marca_bottiglia_ceduta() is
  'Valorizza bottle_units.ceduta_at quando un annuncio entra in ''venduto'', da '
  'qualunque origine arrivi l''UPDATE. La Fase 7 deve conoscerne l''esistenza e '
  'non duplicarne l''effetto.';

drop trigger if exists listings_marca_bottiglia_ceduta on public.listings;

create trigger listings_marca_bottiglia_ceduta
  after insert or update of stato on public.listings
  for each row
  execute function public.listings_marca_bottiglia_ceduta();


-- ---------------------------------------------------------------------------
-- [4] Il trigger di idoneità della bottiglia
-- ---------------------------------------------------------------------------
-- PERCHÉ NON UN INDICE. Il vincolo da applicare attraversa due tabelle: lo stato
-- della riga sta in `listings`, l'idoneità della bottiglia in `bottle_units`. Un
-- indice unico vive su una tabella sola e non può leggere l'altra; un CHECK
-- nemmeno, perché non può interrogare una seconda tabella. Resta il trigger.
--
-- È PIÙ FORTE DELLE RPC, non una loro ripetizione. Le funzioni SECURITY DEFINER
-- più sotto controllano le stesse cose, ma servono a produrre un messaggio
-- leggibile prima che l'utente sbatta contro il database. Questo trigger vale
-- anche per chi le RPC non le usa — un UPDATE da service_role, una futura
-- funzione di Fase 7 scritta distrattamente — ed è quindi il posto dove
-- l'invariante è davvero garantito.
--
-- QUANDO NON CONTROLLA. Un annuncio già in regola resta in regola: se né lo
-- stato né la bottiglia cambiano, non c'è niente di nuovo da verificare.
-- Ricontrollare a ogni modifica di prezzo o fotografia renderebbe immodificabile
-- una bozza legittima nel momento in cui il proprietario apre un'altra bottiglia
-- — e, peggio, renderebbe immodificabili le righe storiche già esistenti.

create or replace function public.listings_bottiglia_idonea()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stato   public.bottle_unit_stato;
  v_deleted timestamptz;
  v_ceduta  timestamptz;
begin
  -- Gli stati terminali sono storico: un annuncio venduto, scaduto, sospeso o
  -- rifiutato resta accanto a una bottiglia in qualunque condizione.
  if new.stato not in ('bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato') then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and new.stato = old.stato
     and new.bottle_unit_id = old.bottle_unit_id then
    return new;
  end if;

  select bu.stato, bu.deleted_at, bu.ceduta_at
  into v_stato, v_deleted, v_ceduta
  from public.bottle_units bu
  where bu.id = new.bottle_unit_id;

  if v_stato is null then
    raise exception 'Questa bottiglia non esiste.' using errcode = 'P0001';
  end if;
  if v_deleted is not null then
    raise exception 'Questa bottiglia non è più nella tua cantina.' using errcode = 'P0001';
  end if;
  if v_ceduta is not null then
    raise exception 'Questa bottiglia è già stata venduta: non può tornare in vendita.'
      using errcode = 'P0001';
  end if;
  if v_stato <> 'chiusa' then
    raise exception 'Una bottiglia % non si può mettere in vendita.', v_stato
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

comment on function public.listings_bottiglia_idonea() is
  'Rifiuta ogni annuncio in stato non terminale la cui bottiglia sia aperta, '
  'consumata, cancellata o già ceduta. Vale anche per service_role: è qui che '
  'l''invariante è garantito, le RPC servono al messaggio leggibile.';

drop trigger if exists listings_bottiglia_idonea on public.listings;

create trigger listings_bottiglia_idonea
  before insert or update on public.listings
  for each row
  execute function public.listings_bottiglia_idonea();


-- ---------------------------------------------------------------------------
-- [5] Un annuncio, una bottiglia, un solo annuncio non terminale
-- ---------------------------------------------------------------------------
-- La regola adottata per intero: un annuncio vende una sola bottiglia fisica, e
-- una bottiglia può avere un solo annuncio non terminale.
--
-- L'indice della 6a copriva solo ('attivo', 'riservato'), cioè scattava alla
-- pubblicazione. Restavano possibili due, cinque, venti bozze sulla stessa
-- bottiglia — e `listing_crea` lo diceva esplicitamente ("una bozza in più non
-- fa danno"). Fa danno: il venditore compila due schede della stessa bottiglia,
-- ne pubblica una, e la seconda resta lì a promettere una bottiglia che non c'è
-- più, finché non ci sbatte contro al momento di pubblicarla.
--
-- I quattro stati terminali (sospeso, scaduto, venduto, rifiutato) restano fuori
-- dall'indice: sono storico, e devono poter coesistere in numero qualunque sulla
-- stessa unità.

drop index if exists public.listings_una_sola_attiva_per_bottiglia;

create unique index if not exists listings_un_solo_annuncio_non_terminale
  on public.listings (bottle_unit_id)
  where stato in ('bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato');

comment on index public.listings_un_solo_annuncio_non_terminale is
  'Un annuncio vende una sola bottiglia fisica e una bottiglia ha un solo '
  'annuncio non terminale. Sostituisce listings_una_sola_attiva_per_bottiglia '
  'della 6a, che copriva i soli stati vivi e lasciava passare più bozze.';


-- ---------------------------------------------------------------------------
-- [6] bottiglia_apri — lo stato fisico passa da qui, non da un UPDATE
-- ---------------------------------------------------------------------------
-- La 6a concedeva `update (stato, visibilita, deleted_at)` al client, e
-- `cellar-service.apri()` scriveva `stato = 'aperta'` direttamente. Con
-- l'invariante "non si apre una bottiglia in vendita" quella colonna smette di
-- essere una preferenza personale e diventa una transizione con una regola
-- dietro: stesso trattamento che la 6a ha riservato a `listings.stato`.
--
-- IL LOCK SERVE DAVVERO. Senza, due sessioni possono incrociarsi: una legge
-- "nessun annuncio attivo" mentre l'altra sta pubblicando, e si finisce con una
-- bottiglia aperta in vendita. `listing_pubblica` e `listing_crea` prendono lo
-- stesso lock sulla stessa riga di `bottle_units`, quindi si mettono in coda.

create or replace function public.bottiglia_apri(
  p_bottle_unit_id uuid,
  p_nota text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_owner   uuid;
  v_stato   public.bottle_unit_stato;
  v_deleted timestamptz;
begin
  if v_uid is null then
    raise exception 'Devi accedere per aprire una bottiglia.' using errcode = '42501';
  end if;

  select bu.owner_id, bu.stato, bu.deleted_at
  into v_owner, v_stato, v_deleted
  from public.bottle_units bu
  where bu.id = p_bottle_unit_id
  for update;

  if v_owner is null or v_owner is distinct from v_uid or v_deleted is not null then
    raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
  end if;

  if v_stato = 'aperta' then
    raise exception 'Questa bottiglia è già aperta.' using errcode = 'P0001';
  end if;
  if v_stato = 'consumata' then
    raise exception 'Questa bottiglia è già stata consumata.' using errcode = 'P0001';
  end if;

  -- Il messaggio dice cosa fare, non che cosa è andato storto: chi apre una
  -- bottiglia in vendita non ha sbagliato nulla, ha solo due cose in ordine
  -- sbagliato.
  if exists (
    select 1
    from public.listings l
    where l.bottle_unit_id = p_bottle_unit_id
      and l.stato in ('attivo', 'riservato')
  ) then
    raise exception 'Questa bottiglia è in vendita: sospendi il suo annuncio prima di aprirla.'
      using errcode = 'P0001';
  end if;

  -- PERCHÉ LA NOTA SOSTITUISCE INVECE DI AGGIUNGERSI, e perché non si corregge
  -- qui. Il dialogo che chiama questa funzione ha un campo etichettato «Nota di
  -- degustazione (facoltativa)» che scrive dentro `note_personali`: due cose
  -- diverse nello stesso posto. In frontend/ (cellar-domain.ts, `personalNotes:
  -- nota ?? bottle.personalNotes`) la nota di degustazione sovrascrive la nota
  -- personale, e siccome il dialogo passa sempre una stringa — vuota se non si
  -- scrive niente — aprire una bottiglia senza digitare nulla CANCELLA la nota
  -- personale che c'era.
  --
  -- Il `case` qui sotto è la stessa protezione che la 6c-2 aveva già messo nel
  -- servizio (`if (nota !== undefined && nota !== "")`): una nota vuota non
  -- tocca niente. È l'unico punto in cui frontend-next diverge da frontend/, ed
  -- è una divergenza a favore dei dati.
  --
  -- Far diventare la nota additiva sarebbe invece un cambiamento di
  -- comportamento visibile in entrambi gli stack, cioè un cambiamento di
  -- prodotto dentro una fase di sicurezza. La confusione fra le due note è
  -- registrata come debito dichiarato, insieme a formatEUR.
  update public.bottle_units
  set stato = 'aperta',
      note_personali = case
        when p_nota is null or trim(p_nota) = '' then note_personali
        else p_nota
      end
  where id = p_bottle_unit_id;
end;
$$;

comment on function public.bottiglia_apri(uuid, text) is
  'Porta una bottiglia da chiusa ad aperta, con lock di riga. Rifiuta se '
  'l''unità ha un annuncio attivo o riservato. Sostituisce l''UPDATE diretto su '
  'bottle_units.stato, che dalla 6d-1 non è più concesso al client.';

revoke execute on function public.bottiglia_apri(uuid, text) from public;
grant execute on function public.bottiglia_apri(uuid, text) to authenticated;


-- ---------------------------------------------------------------------------
-- [7] bottiglia_cancella — la rimozione logica, con lo stesso invariante
-- ---------------------------------------------------------------------------
-- Nessuna interfaccia la chiama oggi: in frontend/ non esiste un comando per
-- togliere una bottiglia dalla cantina, e questa fase non lo aggiunge. Esiste
-- perché `deleted_at` esce dai GRANT di colonna insieme a `stato`, e una colonna
-- che nessuno può più scrivere avrebbe bisogno comunque di una porta il giorno
-- in cui quel comando arriverà — con l'invariante già dentro, invece che da
-- aggiungere allora.
--
-- LA POSIZIONE SI LIBERA. Una bottiglia tolta dalla cantina non può continuare a
-- occupare un foro dello scaffale: `cellar_slots` ha un unico su (module_id,
-- riga, colonna), quindi la riga rimasta bloccherebbe quella posizione per
-- sempre, invisibile perché la cantina legge solo le unità non cancellate.

create or replace function public.bottiglia_cancella(p_bottle_unit_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_owner   uuid;
  v_deleted timestamptz;
begin
  if v_uid is null then
    raise exception 'Devi accedere per togliere una bottiglia dalla cantina.'
      using errcode = '42501';
  end if;

  select bu.owner_id, bu.deleted_at
  into v_owner, v_deleted
  from public.bottle_units bu
  where bu.id = p_bottle_unit_id
  for update;

  if v_owner is null or v_owner is distinct from v_uid then
    raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
  end if;
  if v_deleted is not null then
    raise exception 'Questa bottiglia è già stata tolta dalla cantina.' using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.listings l
    where l.bottle_unit_id = p_bottle_unit_id
      and l.stato in ('attivo', 'riservato')
  ) then
    raise exception 'Questa bottiglia è in vendita: sospendi il suo annuncio prima di toglierla dalla cantina.'
      using errcode = 'P0001';
  end if;

  delete from public.cellar_slots where bottle_unit_id = p_bottle_unit_id;

  update public.bottle_units
  set deleted_at = now()
  where id = p_bottle_unit_id;
end;
$$;

comment on function public.bottiglia_cancella(uuid) is
  'Rimozione logica di un''unità, con lock di riga e liberazione della posizione '
  'in cellar_slots. Rifiuta se l''unità ha un annuncio attivo o riservato. '
  'Nessuna interfaccia la chiama: esiste perché deleted_at esce dai GRANT.';

revoke execute on function public.bottiglia_cancella(uuid) from public;
grant execute on function public.bottiglia_cancella(uuid) to authenticated;


-- ---------------------------------------------------------------------------
-- [8] listing_crea — cancello età, idoneità della bottiglia, lock
-- ---------------------------------------------------------------------------
-- Firma invariata rispetto alla 6c-2, quindi `create or replace` basta e non
-- serve il DROP: nessun parametro si aggiunge, nessuna seconda firma nasce, e
-- PostgREST continua a risolvere la RPC come prima.
--
-- Tre cose cambiano nel corpo:
--   1. il controllo dell'età, subito dopo quello del profilo;
--   2. nella via che parte dalla cantina, il lock di riga sull'unità e il
--      rifiuto esplicito di una bottiglia aperta, consumata, cancellata o già
--      ceduta;
--   3. il messaggio leggibile quando la bottiglia ha già un annuncio non
--      terminale — prima quel caso era ammesso e produceva una seconda bozza.

create or replace function public.listing_crea(
  p_produttore text default '',
  p_nome text default '',
  p_annata integer default null,
  p_regione text default '',
  p_tipo text default null,
  p_prezzo_cents integer default null,
  p_condizione text default 'Ottimo',
  p_conservazione text default '',
  p_storia text default '',
  p_immagini text[] default '{}',
  p_bottle_unit_id uuid default null
)
returns table (annuncio_id uuid, annuncio_slug text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_wine       uuid;
  v_bottle     uuid;
  v_base       text;
  v_slug       text;
  v_n          integer;
  v_immagine   text;
  v_etichetta  text;
  v_stato      public.bottle_unit_stato;
  v_deleted    timestamptz;
  v_ceduta     timestamptz;
begin
  if v_uid is null then
    raise exception 'Devi accedere per creare un annuncio.' using errcode = '42501';
  end if;

  if not exists (select 1 from public.profiles p where p.id = v_uid) then
    raise exception 'Il tuo profilo non è ancora completo: completalo prima di pubblicare.'
      using errcode = 'P0001';
  end if;

  -- Il cancello età. Separato dal controllo del profilo perché i due casi si
  -- risolvono in modi diversi: uno manca del tutto, l'altro ha solo un campo da
  -- riempire in /completa-profilo. La navigazione pubblica non passa di qui e
  -- resta disponibile senza data di nascita.
  if not public.utente_maggiorenne(v_uid) then
    raise exception 'Per mettere in vendita devi dichiarare la tua data di nascita ed essere maggiorenne.'
      using errcode = 'P0001';
  end if;

  if p_condizione is null or p_condizione not in ('Perfetto', 'Ottimo', 'Buono') then
    raise exception 'Condizione non valida.' using errcode = 'P0001';
  end if;
  if p_prezzo_cents is null or p_prezzo_cents <= 0 then
    raise exception 'Il prezzo deve essere maggiore di zero.' using errcode = 'P0001';
  end if;
  if array_length(p_immagini, 1) > 6 then
    raise exception 'Massimo 6 fotografie per annuncio.' using errcode = 'P0001';
  end if;

  foreach v_immagine in array coalesce(p_immagini, '{}'::text[]) loop
    if v_immagine !~ ('^' || v_uid::text || '/[0-9a-f-]{36}\.(jpg|jpeg|png|webp|avif)$') then
      raise exception 'Fotografia non valida: %', v_immagine using errcode = 'P0001';
    end if;
  end loop;

  if p_bottle_unit_id is null then
    -- -----------------------------------------------------------------------
    -- Via da zero: il wizard descrive una bottiglia che non esiste ancora.
    -- L'unità nasce qui, 'chiusa' e mai ceduta: nessun controllo di idoneità da
    -- fare, perché non c'è ancora niente che possa essere andato storto.
    -- -----------------------------------------------------------------------
    if coalesce(trim(p_produttore), '') = '' then
      raise exception 'Il produttore è obbligatorio.' using errcode = 'P0001';
    end if;
    if coalesce(trim(p_nome), '') = '' then
      raise exception 'Il nome del vino è obbligatorio.' using errcode = 'P0001';
    end if;
    if coalesce(trim(p_regione), '') = '' then
      raise exception 'La regione è obbligatoria.' using errcode = 'P0001';
    end if;
    if p_annata is null or p_annata < 1800 or p_annata > 2100 then
      raise exception 'L''annata deve essere compresa fra 1800 e 2100.' using errcode = 'P0001';
    end if;
    if p_tipo is null or p_tipo not in ('Rosso', 'Bianco', 'Bollicine', 'Rosato', 'Dolce') then
      raise exception 'Tipologia non valida.' using errcode = 'P0001';
    end if;

    v_etichetta := trim(p_produttore) || ' ' || trim(p_nome) || ' ' || p_annata::text;

    select w.id into v_wine
    from public.wines w
    where w.produttore = trim(p_produttore)
      and w.nome = trim(p_nome)
      and w.annata = p_annata::smallint;

    if v_wine is null then
      v_base := public.slugifica(v_etichetta);
      v_slug := v_base;
      v_n := 1;
      while exists (select 1 from public.wines w where w.slug = v_slug) loop
        v_n := v_n + 1;
        v_slug := v_base || '-' || v_n;
      end loop;

      insert into public.wines (slug, produttore, nome, annata, regione, tipo)
      values (v_slug, trim(p_produttore), trim(p_nome), p_annata::smallint,
              trim(p_regione), p_tipo)
      on conflict (produttore, nome, annata) do nothing
      returning wines.id into v_wine;

      if v_wine is null then
        select w.id into v_wine
        from public.wines w
        where w.produttore = trim(p_produttore)
          and w.nome = trim(p_nome)
          and w.annata = p_annata::smallint;
      end if;
    end if;

    insert into public.bottle_units (owner_id, wine_id, stato, visibilita)
    values (v_uid, v_wine, 'chiusa', 'privata')
    returning bottle_units.id into v_bottle;

  else
    -- -----------------------------------------------------------------------
    -- Via dalla Cantina: la bottiglia esiste già.
    -- -----------------------------------------------------------------------
    -- Il lock si prende qui, prima di qualunque verifica, e regge fino alla fine
    -- della transazione: è ciò che impedisce a un'apertura concorrente di
    -- infilarsi fra il controllo e l'inserimento dell'annuncio.
    select bu.id, bu.wine_id, bu.stato, bu.deleted_at, bu.ceduta_at
    into v_bottle, v_wine, v_stato, v_deleted, v_ceduta
    from public.bottle_units bu
    where bu.id = p_bottle_unit_id
      and bu.owner_id = v_uid
    for update;

    if v_bottle is null or v_deleted is not null then
      raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
    end if;
    if v_ceduta is not null then
      raise exception 'Questa bottiglia è già stata venduta: non può tornare in vendita.'
        using errcode = 'P0001';
    end if;
    if v_stato <> 'chiusa' then
      raise exception 'Una bottiglia % non si può mettere in vendita.', v_stato
        using errcode = 'P0001';
    end if;

    -- La regola nuova della 6d-1. Prima di qui una seconda bozza era ammessa di
    -- proposito; adesso l'indice la rifiuta, e senza questo controllo il
    -- messaggio sarebbe il 23505 col nome dell'indice dentro.
    if exists (
      select 1
      from public.listings l
      where l.bottle_unit_id = v_bottle
        and l.stato in ('bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato')
    ) then
      raise exception 'Questa bottiglia ha già un annuncio in corso: concludilo o ritiralo prima di crearne un altro.'
        using errcode = 'P0001';
    end if;

    select w.produttore || ' ' || w.nome || ' ' || w.annata::text
    into v_etichetta
    from public.wines w
    where w.id = v_wine;
  end if;

  v_base := public.slugifica(v_etichetta);
  v_slug := v_base;
  v_n := 1;
  while exists (select 1 from public.listings l where l.slug = v_slug) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n;
  end loop;

  begin
    return query
    insert into public.listings (
      slug, seller_id, bottle_unit_id, stato,
      prezzo_cents, condizione, conservazione, storia, immagini
    )
    values (
      v_slug, v_uid, v_bottle, 'bozza',
      p_prezzo_cents, p_condizione, coalesce(p_conservazione, ''), coalesce(p_storia, ''),
      coalesce(p_immagini, '{}'::text[])
    )
    returning listings.id, listings.slug;
  exception
    -- Due violazioni diverse arrivano qui con lo stesso SQLSTATE: lo slug
    -- occupato da un'altra sessione fra il controllo e l'INSERT, e l'annuncio
    -- non terminale già esistente sulla bottiglia. Il secondo caso è già stato
    -- intercettato sopra con un messaggio suo; questo resta il ripiego.
    when unique_violation then
      raise exception 'Non è stato possibile creare l''annuncio. Riprova.'
        using errcode = 'P0001';
  end;
end;
$$;

comment on function public.listing_crea(
  text, text, integer, text, text, integer, text, text, text, text[], uuid
) is
  'Crea un annuncio in stato bozza. Senza p_bottle_unit_id conia anche vino (se '
  'manca) e unità fisica; con p_bottle_unit_id riusa un''unità già in cantina, '
  'dopo lock di riga e verifica di proprietà, stato fisico, cancellazione, '
  'cessione e assenza di altri annunci non terminali. Richiede un profilo con '
  'data di nascita dichiarata e maggiore età. Venditore e proprietario sono '
  'sempre auth.uid(). Non pubblica: la pubblicazione è listing_pubblica().';

revoke execute on function public.listing_crea(
  text, text, integer, text, text, integer, text, text, text, text[], uuid
) from public;
grant execute on function public.listing_crea(
  text, text, integer, text, text, integer, text, text, text, text[], uuid
) to authenticated;


-- ---------------------------------------------------------------------------
-- [9] listing_pubblica — la porta verso il pubblico
-- ---------------------------------------------------------------------------
-- È l'altra funzione che rende pubblica una vendita, quindi porta lo stesso
-- cancello età di listing_crea.
--
-- IL RICONTROLLO DELLA BOTTIGLIA NON È RIDONDANTE. Fra la creazione della bozza
-- e la pubblicazione passa tempo reale — il wizard ha più passi, la bozza si può
-- salvare e riprendere il giorno dopo — e in quel tempo la bottiglia può essere
-- stata aperta o tolta dalla cantina. Senza questo controllo si pubblicherebbe
-- un annuncio per una bottiglia che non c'è più.

create or replace function public.listing_pubblica(p_listing_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_seller   uuid;
  v_stato    public.listing_stato;
  v_bottle   uuid;
  v_bu_stato public.bottle_unit_stato;
  v_deleted  timestamptz;
  v_ceduta   timestamptz;
begin
  if v_uid is null then
    raise exception 'Devi accedere per pubblicare un annuncio.' using errcode = '42501';
  end if;

  select l.seller_id, l.stato, l.bottle_unit_id
  into v_seller, v_stato, v_bottle
  from public.listings l
  where l.id = p_listing_id;

  if v_seller is null then
    raise exception 'Annuncio non trovato.' using errcode = 'P0001';
  end if;
  if v_seller is distinct from v_uid then
    raise exception 'Non puoi pubblicare un annuncio che non è tuo.' using errcode = '42501';
  end if;
  if v_stato not in ('bozza', 'modifiche_richieste') then
    raise exception 'Si può pubblicare solo un annuncio in bozza o con modifiche richieste.'
      using errcode = 'P0001';
  end if;

  if not public.utente_maggiorenne(v_uid) then
    raise exception 'Per mettere in vendita devi dichiarare la tua data di nascita ed essere maggiorenne.'
      using errcode = 'P0001';
  end if;

  -- Stesso lock di bottiglia_apri e di listing_crea, sulla stessa riga: è così
  -- che le due transizioni si serializzano invece di incrociarsi.
  select bu.stato, bu.deleted_at, bu.ceduta_at
  into v_bu_stato, v_deleted, v_ceduta
  from public.bottle_units bu
  where bu.id = v_bottle
  for update;

  if v_bu_stato is null or v_deleted is not null then
    raise exception 'La bottiglia di questo annuncio non è più nella tua cantina.'
      using errcode = 'P0001';
  end if;
  if v_ceduta is not null then
    raise exception 'Questa bottiglia è già stata venduta: non può tornare in vendita.'
      using errcode = 'P0001';
  end if;
  if v_bu_stato <> 'chiusa' then
    raise exception 'Questa bottiglia è stata %: non si può più mettere in vendita.', v_bu_stato
      using errcode = 'P0001';
  end if;

  begin
    update public.listings
    set stato = 'attivo',
        published_at = now(),
        -- Sessanta giorni, come dalla 6b. Dalla 6d-1 la scadenza ha un effetto
        -- reale anche prima di essere materializzata: la proiezione pubblica
        -- esclude gli annunci oltre expires_at.
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
$$;

comment on function public.listing_pubblica(uuid) is
  'Porta un annuncio del venditore da bozza (o modifiche_richieste) ad attivo, '
  'dopo cancello età e ricontrollo con lock della bottiglia, che fra la bozza e '
  'la pubblicazione può essere stata aperta o tolta dalla cantina. Traduce la '
  'violazione dell''indice non-terminale in un messaggio leggibile.';

revoke execute on function public.listing_pubblica(uuid) from public;
grant execute on function public.listing_pubblica(uuid) to authenticated;


-- ---------------------------------------------------------------------------
-- [10] public_listings — la scadenza vale in lettura
-- ---------------------------------------------------------------------------
-- Un annuncio con expires_at già passato non deve essere visibile né
-- acquistabile anche se lo stato materializzato è ancora 'attivo'. Fino alla 6c
-- la vista guardava soltanto lo stato, e senza scheduler quello stato resta
-- 'attivo' a tempo indeterminato: bastava non chiamare `listing_scadi` perché un
-- annuncio scaduto restasse in vetrina per sempre.
--
-- La colonna e le sue posizioni non cambiano, quindi `create or replace view`
-- basta e i privilegi già concessi restano.
--
-- LA PRENOTAZIONE DOVRÀ RICONTROLLARE. Questa è una difesa in lettura: dice
-- quali annunci si vedono, non impedisce a nessuno di agire su un id noto. La
-- futura RPC di prenotazione (Fase 7) dovrà verificare la scadenza per conto
-- suo, dentro la transazione che riserva.

create or replace view public.public_listings
with (security_invoker = off)
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
  p.avatar_url    as seller_avatar_url
from public.listings l
  join public.bottle_units bu on bu.id = l.bottle_unit_id
  join public.wines w on w.id = bu.wine_id
  join public.profiles p on p.id = l.seller_id
where l.stato = 'attivo'
  and (l.expires_at is null or l.expires_at > now());

comment on view public.public_listings is
  'Annunci attivi e non scaduti, con vino e venditore già uniti, nella forma che '
  'serve a /esplora e a /annuncio/[slug]. Espone solo campi non sensibili del '
  'profilo venditore (mai dob, esperienza, bio, obiettivi). Dalla 6d-1 è anche '
  'l''unica via con cui un anonimo legge un annuncio: la tabella non è più '
  'raggiungibile.';


-- ---------------------------------------------------------------------------
-- [11] public_bottle_units — le unità pubbliche a colonne scelte
-- ---------------------------------------------------------------------------
-- Prende il posto delle due policy che rendevano leggibile la riga intera di
-- `bottle_units`: quella della 6a per le unità in annuncio attivo, e quella
-- della 6c-1 per le unità dichiarate `cantina_pubblica`.
--
-- COSA ESPONEVANO. Tutta la riga, quindi anche `note_personali`
-- ("regalo di mio padre"), `apertura_pianificata` (quando qualcuno sarà in casa
-- a festeggiare), gli `override_*` della finestra di bevuta e
-- `prezzo_visibilita`. Nulla di tutto ciò serviva a un marketplace: erano
-- leggibili perché il GRANT era di tabella e la RLS lavora per riga, non per
-- colonna.
--
-- COSA ESPONE QUESTA. Sei colonne, elencate una per una. Chi è il proprietario e
-- quale vino è, che sono i due fatti che rendono utile sapere che l'unità
-- esiste; lo stato fisico e la visibilità, che il proprietario ha scelto di
-- rendere pubblici nel momento in cui ha dichiarato la bottiglia; la data di
-- creazione. Ogni colonna aggiunta in futuro resta fuori finché qualcuno non la
-- scrive qui dentro: è il senso di un elenco chiuso.
--
-- NESSUN CONSUMATORE, OGGI. Nessuna interfaccia legge le bottiglie altrui —
-- `cantina_pubblica` compare solo come etichetta derivata dai dati del
-- proprietario. La vista conserva la capacità che le due policy davano, nella
-- forma sicura, invece di toglierla in silenzio.

create or replace view public.public_bottle_units
with (security_invoker = off)
as
select
  bu.id,
  bu.owner_id,
  bu.wine_id,
  bu.stato,
  bu.visibilita,
  bu.created_at
from public.bottle_units bu
where bu.deleted_at is null
  and bu.ceduta_at is null
  and (
    bu.visibilita = 'cantina_pubblica'
    or exists (
      select 1
      from public.listings l
      where l.bottle_unit_id = bu.id
        and l.stato = 'attivo'
        and (l.expires_at is null or l.expires_at > now())
    )
  );

comment on view public.public_bottle_units is
  'Unità fisiche visibili a terzi: quelle in un annuncio attivo e non scaduto, e '
  'quelle dichiarate cantina_pubblica dal proprietario. Elenco chiuso di sei '
  'colonne: mai note_personali, apertura_pianificata, override della finestra, '
  'prezzo_visibilita, né alcuna colonna futura non elencata qui.';

revoke all on public.public_bottle_units from anon, authenticated;
grant select on public.public_bottle_units to anon, authenticated;


-- ===========================================================================
-- Da qui in giù si toglie. Tutto ciò che serve a leggere esiste già sopra.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- [12] Privilegi — bottle_units
-- ---------------------------------------------------------------------------
-- `anon` perde ogni accesso alla tabella: quello che gli serve è nelle due
-- viste, che valutano con i privilegi del proprietario e non hanno bisogno che
-- il chiamante possa leggere le tabelle sottostanti.
revoke all on public.bottle_units from anon;

-- `authenticated` tiene il SELECT di tabella, e non è una dimenticanza:
-- rimosse le due policy pubbliche più sotto, un autenticato raggiunge soltanto
-- le proprie righe (bottle_units_select_own), quindi il grant di tabella non
-- espone nulla di altrui. Il proprietario deve continuare a leggere
-- integralmente le proprie unità — note, override e pianificazioni comprese.
-- L'asimmetria con `listings` dipende da quali righe il ruolo può raggiungere,
-- non da un gusto diverso sulle due tabelle.

-- Lo stato fisico e la cancellazione escono dalle colonne scrivibili: hanno
-- adesso una regola dietro, e le regole passano dalle RPC [6] e [7]. È lo stesso
-- trattamento che la 6a ha riservato a `listings.stato`, applicato alle due
-- colonne che nel frattempo hanno smesso di essere preferenze personali.
revoke insert (stato) on public.bottle_units from authenticated;
revoke update (stato, deleted_at) on public.bottle_units from authenticated;
-- `ceduta_at` non compare in nessun GRANT di colonna e non ce ne sarà uno: la
-- valorizza il trigger [3], che gira con i privilegi del proprietario.


-- ---------------------------------------------------------------------------
-- [13] Privilegi — listings
-- ---------------------------------------------------------------------------
revoke all on public.listings from anon;

-- Il SELECT di tabella se ne va e torna come elenco chiuso di colonne. Non è
-- una ripetizione della RLS: la policy decide quali righe, il privilegio di
-- colonna decide quali campi, e i due confini restano validi indipendentemente.
-- Se un domani una fase aggiungerà una policy che espone righe altrui — la
-- Fase 7 dovrà mostrare al compratore l'annuncio che sta riservando, la Fase 9
-- la coda di moderazione — le colonne qui sotto sono già il limite, e nessuno
-- dovrà ricordarsi di riscriverlo.
revoke select on public.listings from authenticated;

grant select (
  id, slug, seller_id, bottle_unit_id, stato,
  prezzo_cents, prezzo_mercato_cents,
  condizione, conservazione, storia, degustazione, immagini, tag,
  published_at, expires_at, created_at, updated_at
) on public.listings to authenticated;

-- COSA RESTA FUORI, E CHE COSA COSTA. `stato_motivo`, `stato_aggiornato_da` e
-- `stato_aggiornato_at` sono la traccia dell'ultima transizione: perché un
-- moderatore ha rifiutato o sospeso un annuncio, e chi è stato. Non sono
-- leggibili da nessun ruolo client, proprietario compreso.
--
-- Il privilegio di colonna non distingue le righe, quindi "il venditore legge i
-- propri annunci integralmente" e "quelle colonne non sono leggibili da chi non
-- è proprietario" non possono valere insieme dentro un GRANT. Si è scelta la
-- lettura difensiva. Oggi non costa nulla di visibile: la moderazione è Fase 9 e
-- non esiste, nessuna interfaccia mostra quelle colonne. Quando la Fase 9 dovrà
-- mostrare al venditore il motivo di un rifiuto lo farà con una proiezione
-- dedicata alle righe proprie, non riaprendo la tabella.
--
-- `bottle_unit_id` è nell'elenco perché PostgREST ne ha bisogno per risolvere
-- l'embed `bottle_units → listings` che la cantina usa per prezzo, foto e stato
-- di vendita; `id` perché è il filtro di ogni UPDATE di contenuto. I GRANT di
-- INSERT e UPDATE della 6a non si toccano: erano già scritti per non dover
-- cambiare.


-- ---------------------------------------------------------------------------
-- [14] Privilegi — user_roles e has_role
-- ---------------------------------------------------------------------------
-- La 6a/5a concedeva SELECT sull'intera tabella a `authenticated`, con una
-- policy `using (true)`: qualunque utente registrato poteva elencare i ruoli di
-- tutti gli altri, cioè sapere chi sono gli amministratori e i moderatori del
-- sito. È esattamente la mappa che serve a chi cerca un bersaglio.
revoke all on public.user_roles from anon, authenticated;
grant select (user_id, role) on public.user_roles to authenticated;
-- Nessun INSERT/UPDATE/DELETE, come dalla 5a: i ruoli li assegna solo
-- service_role. Nessuna autoassegnazione è possibile, nemmeno sui propri.

-- `has_role` era eseguibile da `anon`. Le policy che la usano
-- (`wines_write_staff`) sono `to authenticated`, quindi nessun anonimo ne ha
-- bisogno, e concederla dava a chiunque un oracolo per verificare se un dato
-- uuid è amministratore.
--
-- La revoca da PUBLIC è quella che conta: `create function` concede EXECUTE a
-- PUBLIC per impostazione predefinita, quindi togliere il grant esplicito ad
-- `anon` senza toccare PUBLIC non avrebbe cambiato nulla.
revoke execute on function public.has_role(uuid, text) from public, anon;
grant execute on function public.has_role(uuid, text) to authenticated;


-- ---------------------------------------------------------------------------
-- [15] Policy — ciò che era pubblico adesso passa dalle viste
-- ---------------------------------------------------------------------------

-- Le due policy che esponevano la riga intera di bottle_units. Sostituite da
-- public_bottle_units [11], che espone sei colonne invece di ventidue.
drop policy if exists "bottle_units_select_via_annuncio_pubblico" on public.bottle_units;
drop policy if exists "bottle_units_select_cantina_pubblica" on public.bottle_units;

-- La lettura pubblica diretta di listings. Sostituita da public_listings [10],
-- che era già l'unica via usata dall'interfaccia: `listing-service.ts` legge la
-- vista, non la tabella. La policy esisteva quindi senza consumatori, ed esponeva
-- expires_at, stato_motivo e stato_aggiornato_da a ogni visitatore anonimo.
drop policy if exists "listings_select_pubblici" on public.listings;
-- `listings_select_own` resta: il venditore continua a leggere i propri annunci,
-- ed è quella policy che tiene in piedi l'embed della cantina.

-- L'enumerazione dei ruoli altrui.
drop policy if exists "user_roles_select_authenticated" on public.user_roles;

drop policy if exists "user_roles_select_own" on public.user_roles;

create policy "user_roles_select_own"
  on public.user_roles for select
  to authenticated
  using (user_id = auth.uid());
