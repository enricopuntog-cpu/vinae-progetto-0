-- ===========================================================================
-- Certificazioni di profilo - fondazione della fiducia
-- ===========================================================================
--
-- IL PROBLEMA CHE CHIUDE. `public.profiles` contiene soltanto dichiarazioni
-- dell'utente: nome, citta, presentazione, esperienza, avatar e `dob`. Il
-- CHECK sulla data di nascita impone >= 18 anni lato server ma resta una
-- dichiarazione, non un accertamento d'identita - lo dice gia il commento
-- della 5a. Nulla, in tutto il repository, distingue oggi "questa persona ha
-- scritto un nome" da "qualcuno di fidato ha verificato chi e".
--
-- Per questo `ListingService.rigaAWine()` scrive `venditore.verificato =
-- false` a mano, e il badge "Verificato" di WineCard non si e mai acceso: non
-- esisteva una sorgente. Questa migrazione crea quella sorgente, e la crea in
-- modo che il badge possa accendersi SOLO per un fatto vero.
--
-- ---------------------------------------------------------------------------
-- TRE STATI DIVERSI, CHE NON DEVONO COLLASSARE UNO SULL'ALTRO
-- ---------------------------------------------------------------------------
--
--   EMAIL CONFERMATA     e' un fatto tecnico e Supabase Auth lo possiede gia:
--                        `auth.users.email_confirmed_at`. NON viene copiato
--                        qui, e non e' una dimenticanza - duplicarlo darebbe
--                        due scrittori allo stesso fatto, che questo
--                        repository vieta. Il prodotto lo legge dalla sua
--                        fonte, e vale quel che vale: prova il controllo di
--                        una casella di posta, nient'altro.
--
--   IDENTITA' VERIFICATA e' una certificazione forte. Dice che una fonte
--                        fidata ha accertato chi e' la persona. Oggi quella
--                        fonte NON ESISTE: nessun provider KYC e' stato
--                        scelto, e sceglierlo non e' una decisione tecnica.
--                        Questa migrazione non crea nessuna riga.
--
--   VENDITORE VERIFICATO e' la certificazione che il compratore legge. Non
--                        deriva dall'email, non deriva dal profilo completo,
--                        non deriva dall'anzianita dell'account. Richiede
--                        l'identita, e il vincolo e' scritto qui sotto in un
--                        trigger, non in una convenzione.
--
-- La regola che tiene insieme le tre righe: il badge pubblico e' un'affermazione
-- fatta a chi sta per pagare. Un falso positivo qui non e' un difetto grafico.
--
-- ---------------------------------------------------------------------------
-- CHE COSA NON C'E'
-- ---------------------------------------------------------------------------
--
-- Nessun documento, nessuna scansione, nessun numero di documento, nessun
-- selfie, nessun dato biometrico, nessun bucket, nessuna colonna di testo
-- libero in cui qualcuno possa depositarli domani. La tabella contiene ESITI,
-- mai prove: chi, che tipo, da quale specie di fonte, da quando, fino a
-- quando. Un dato KYC che non viene raccolto non puo' trapelare.
--
-- Nessun provider, nessuna chiave API, nessuna chiamata HTTP, nessun webhook,
-- nessun cron, nessun costo. `public.certificazione_fonte` esiste perche' un
-- domani si possa distinguere una verifica interna da una di un fornitore
-- esterno senza rifare il modello, ma oggi ha UNA sola label e nessun nome di
-- fornitore compare in questo file. E' la stessa forma provider-agnostica
-- della 1A, e per la stessa ragione.
--
-- ---------------------------------------------------------------------------
-- FAIL-CLOSED PER COSTRUZIONE
-- ---------------------------------------------------------------------------
--
--   1. l'utente non ha ALCUN privilegio sulla tabella: ne' lettura ne'
--      scrittura, per `anon` e per `authenticated`. La RLS e' attiva e non
--      esiste una sola policy. E' la forma di `wine_price_observations`;
--   2. l'utente non puo' autocertificarsi nemmeno per una via privilegiata:
--      il trigger rifiuta ogni riga in cui la sessione che scrive coincide
--      con la persona certificata. Vincola anche una futura RPC di back
--      office, perche' sta in un trigger e non in una funzione che qualcuno
--      puo' non chiamare;
--   3. `venditore` senza `identita` valida viene rifiutato in scrittura dal
--      trigger, E non viene comunque mai proiettato in lettura: le due viste
--      pretendono entrambe le certificazioni valide. Se domani l'identita
--      scade o viene revocata, il badge si spegne da solo;
--   4. il CHECK sulla fonte rifiuta a livello di riga qualunque origine
--      diversa da quella interna, e lega anche `service_role`. Accendere un
--      fornitore richiede tre atti espliciti in una migrazione nuova - label,
--      vincolo, via d'ingresso - e nessuno dei tre puo' accadere per merge.
--
-- Nessun backfill. La tabella nasce vuota e resta vuota finche' una decisione
-- fuori da questo file non certifica qualcuno davvero. In produzione, dopo
-- questa migrazione, `seller_verificato` e' `false` per tutti gli annunci -
-- cioe' esattamente quello che il codice affermava prima, ma ora perche' e'
-- vero e non perche' e' cablato.

-- ---------------------------------------------------------------------------
-- [1] Tipi
-- ---------------------------------------------------------------------------

-- Lo schema esiste dalla 6d-2a; la riga sta qui per la stessa ragione per cui
-- sta nella 7, cioe' perche' questo file non dipenda dall'ordine di lettura.
create schema if not exists private;

create type public.certificazione_tipo as enum ('identita', 'venditore');

comment on type public.certificazione_tipo is
  'Specie di certificazione forte di profilo. `identita`: una fonte fidata ha '
  'accertato chi e la persona. `venditore`: la persona e abilitata a vendere '
  'come venditore verificato, e richiede `identita`. La conferma email NON e '
  'qui: appartiene ad auth.users.email_confirmed_at.';

create type public.certificazione_fonte as enum ('verifica_interna_vinea');

comment on type public.certificazione_fonte is
  'Specie di fonte che ha prodotto la certificazione. Una sola label oggi. '
  'Esiste per poter distinguere domani una fonte esterna senza rifare il '
  'modello: nessun fornitore e stato scelto e nessun nome di fornitore '
  'compare in questa migrazione.';

-- ---------------------------------------------------------------------------
-- [2] La tabella - esiti, mai prove
-- ---------------------------------------------------------------------------

create table public.profile_certifications (
  user_id uuid not null references auth.users (id) on delete cascade,
  tipo public.certificazione_tipo not null,
  fonte public.certificazione_fonte not null,
  rilasciata_at timestamptz not null default now(),
  -- NULL = non scade. Stessa convenzione di `listings.expires_at`. Una
  -- certificazione scaduta smette di essere proiettata senza che nessuno
  -- debba cancellare la riga: la revoca esplicita resta il DELETE.
  scade_at timestamptz,
  primary key (user_id, tipo),
  constraint profile_certifications_scadenza_dopo_rilascio
    check (scade_at is null or scade_at > rilasciata_at),
  -- Fail-closed [4]: oggi l'enum ha una sola label, quindi il vincolo e
  -- soddisfatto da chiunque; se domani ne acquistasse una esterna, le righe
  -- di quella fonte resterebbero rifiutate finche una migrazione successiva
  -- non toglie deliberatamente il vincolo. Vincola anche service_role.
  constraint profile_certifications_solo_fonti_interne
    check (fonte = 'verifica_interna_vinea'::public.certificazione_fonte)
);

comment on table public.profile_certifications is
  'Certificazioni forti di profilo. Contiene esiti, mai prove: nessun '
  'documento, nessun identificativo di documento, nessun dato KYC e nessuna '
  'colonna di testo libero. Nessun privilegio per anon e authenticated; RLS '
  'attiva e zero policy. Si legge solo attraverso public.my_certifications '
  '(propria) e public.public_listings.seller_verificato (pubblica).';

comment on column public.profile_certifications.scade_at is
  'Fine validita. NULL significa senza scadenza. Una certificazione scaduta '
  'non viene proiettata da nessuna delle due viste.';

-- RLS attiva, zero policy: `anon` e `authenticated` non arrivano alla tabella
-- in nessun modo. Le due viste sono `security_invoker = off` e la leggono
-- come proprietarie, esattamente come `wine_price_history` legge
-- `wine_price_observations`.
alter table public.profile_certifications enable row level security;

revoke all on public.profile_certifications from anon, authenticated;

-- `service_role` NON viene revocato, ed e deliberato: e la chiave di back
-- office, l'unica via per certificare davvero qualcuno finche non esiste un
-- percorso applicativo. Non e un buco - resta comunque vincolata dal trigger
-- [4] e dal CHECK sulla fonte, che non guardano il ruolo.

-- ---------------------------------------------------------------------------
-- [3] Il predicato di validita, in un posto solo
-- ---------------------------------------------------------------------------
--
-- Il trigger e le due viste devono rispondere alla stessa domanda: "questa
-- certificazione vale adesso?". Scriverla tre volte significa che un giorno
-- una delle tre dira qualcosa di diverso - tipicamente quella che dimentica la
-- scadenza, cioe' quella che accende il badge di troppo.
--
-- E' una VISTA e non una funzione, ed e' una scelta di sicurezza precisa. In
-- una vista `security_invoker = off` la sostituzione di privilegi vale per le
-- tabelle e le viste che compaiono nell'albero della query, NON per il corpo
-- di una funzione chiamata nella target list: quella eseguirebbe con i
-- privilegi del chiamante. Una funzione qui avrebbe due esiti, entrambi
-- sbagliati - restituire sempre `false` a un visitatore anonimo, oppure
-- pretendere un EXECUTE ad `anon` su una funzione che sonda lo stato di
-- verifica di qualunque uuid. Una vista annidata non ha nessuno dei due
-- problemi: `public_listings` la legge come proprietaria, e lei legge la
-- tabella come proprietaria a sua volta.

-- Valida = gia cominciata E non ancora finita. Le due meta servono davvero:
-- il CHECK impedisce che la fine preceda l'inizio, ma NON impedisce di
-- collocare l'intero intervallo nel futuro. Senza il primo predicato una riga
-- con `rilasciata_at` a domani sarebbe valida oggi, cioe' una certificazione
-- accenderebbe il badge prima di essere stata emessa.
--
-- Le parentesi attorno alla seconda meta non sono ornamentali: `and` lega piu
-- stretto di `or`, quindi togliendole il predicato diventerebbe
-- `(rilasciata_at <= now() and scade_at is null) or scade_at > now()` e
-- qualunque riga non scaduta tornerebbe valida a prescindere dall'inizio -
-- esattamente il difetto che questa riga chiude.
create view private.certificazioni_valide as
select
  c.user_id,
  c.tipo
from public.profile_certifications c
where c.rilasciata_at <= now()
  and (c.scade_at is null or c.scade_at > now());

comment on view private.certificazioni_valide is
  'Certificazioni forti gia in vigore e non ancora scadute: una riga datata nel '
  'futuro non vale oggi. Unico luogo in cui la validita e '
  'definita: la leggono il trigger di scrittura e le due proiezioni. Nessun '
  'privilegio per anon e authenticated, che pure hanno USAGE sullo schema.';

revoke all on private.certificazioni_valide from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [4] Il guardiano - vincola anche chi scrive con privilegi
-- ---------------------------------------------------------------------------

create or replace function private.profile_certifications_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Nessuno certifica se stesso. `auth.uid()` e nullo per service_role e per
  -- SQL diretto, quindi il back office passa; una futura RPC chiamata da una
  -- sessione autenticata non puo invece emettere una certificazione a proprio
  -- nome, qualunque ruolo abbia chi la chiama.
  if (select auth.uid()) is not null and (select auth.uid()) = new.user_id then
    raise exception
      'Una certificazione non puo essere emessa dalla stessa sessione che ne e oggetto.'
      using errcode = '42501';
  end if;

  -- `venditore` pretende `identita` valida nello stesso istante. Il controllo
  -- e ripetuto in lettura dalle due viste: qui impedisce di scrivere lo stato
  -- incoerente, li impedisce di mostrarlo se l'identita decade dopo.
  if new.tipo = 'venditore'::public.certificazione_tipo then
    if not exists (
      select 1
      from private.certificazioni_valide v
      where v.user_id = new.user_id
        and v.tipo = 'identita'::public.certificazione_tipo
    ) then
      raise exception
        'La certificazione venditore richiede una certificazione identita valida.'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

comment on function private.profile_certifications_guard() is
  'Vincoli che devono valere anche per uno scrittore privilegiato: nessuna '
  'autocertificazione, e nessun `venditore` senza `identita` valida.';

revoke execute on function private.profile_certifications_guard()
  from public, anon, authenticated;

create trigger profile_certifications_guard
  before insert or update on public.profile_certifications
  for each row
  execute function private.profile_certifications_guard();

-- ---------------------------------------------------------------------------
-- [5] La proiezione personale - /account
-- ---------------------------------------------------------------------------
--
-- Stessa forma di `public.my_reports` della 9a: `security_invoker = off`,
-- filtro su `auth.uid()` dentro la definizione, elenco chiuso di colonne.
-- Restituisce SOLO booleani derivati: nemmeno la persona interessata legge da
-- qui la fonte o le date, perche' non le servono per sapere a che punto e' e
-- perche' una colonna aggiunta domani alla tabella base resta privata finche'
-- qualcuno non la nomina qui.
--
-- La conferma email non compare: la possiede Supabase Auth e il prodotto la
-- legge da li.

create view public.my_certifications
with (security_invoker = off, security_barrier = true)
as
select
  p.id as user_id,
  exists (
    select 1
    from private.certificazioni_valide v
    where v.user_id = p.id
      and v.tipo = 'identita'::public.certificazione_tipo
  ) as identita_verificata,
  (
    exists (
      select 1
      from private.certificazioni_valide v
      where v.user_id = p.id
        and v.tipo = 'identita'::public.certificazione_tipo
    )
    and exists (
      select 1
      from private.certificazioni_valide v
      where v.user_id = p.id
        and v.tipo = 'venditore'::public.certificazione_tipo
    )
  ) as venditore_verificato
from public.profiles p
where p.id = (select auth.uid());

comment on view public.my_certifications is
  'Certificazioni forti della sola persona collegata, come booleani derivati. '
  'Zero righe per un chiamante anonimo. Non espone email, dob, documenti, '
  'fonte ne date.';

revoke all on public.my_certifications from anon, authenticated;
grant select on public.my_certifications to authenticated;

-- ---------------------------------------------------------------------------
-- [6] La proiezione pubblica - il badge del catalogo
-- ---------------------------------------------------------------------------
--
-- Definizione ripresa dalla 9b (riga 286) con UNA colonna in coda.
-- `create or replace view` esige che le colonne preesistenti restino identiche,
-- nello stesso ordine: nulla e stato rinominato, mosso o tolto, e i quattro
-- predicati della 9b sono invariati.
--
-- `seller_verificato` e' un booleano derivato e non un dato del venditore: la
-- vista non espone e non puo esporre email, `dob`, fonte, date di rilascio o
-- qualunque cosa somigli a un documento. Chi guarda il catalogo vede una sola
-- cosa - se c'e o non c'e una certificazione forte valida in questo momento.

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
  l.imballaggio_codice,
  (
    exists (
      select 1
      from private.certificazioni_valide v
      where v.user_id = p.id
        and v.tipo = 'identita'::public.certificazione_tipo
    )
    and exists (
      select 1
      from private.certificazioni_valide v
      where v.user_id = p.id
        and v.tipo = 'venditore'::public.certificazione_tipo
    )
  ) as seller_verificato
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
  'livello). Un chiamante anonimo non e toccato. Da questa migrazione porta '
  'anche `seller_verificato`: booleano derivato, vero solo con certificazione '
  'identita E venditore entrambe valide adesso.';

revoke all on public.public_listings from anon, authenticated;
grant select on public.public_listings to anon, authenticated;
