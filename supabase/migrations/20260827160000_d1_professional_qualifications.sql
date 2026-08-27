-- ===========================================================================
-- Qualifiche professionali - dominio completo (D1)
-- ===========================================================================
--
-- CHE COSA CHIUDE. La 20260825180000 (profilo pubblico) ha scritto, in un
-- commento che vale come impegno, che «la spunta che il profilo mostrera' un
-- giorno dipendera' da qualifiche professionali approvate, che sono un dominio
-- non ancora aperto». Questo file apre quel dominio, e lo apre per intero:
-- il modello, le prove private, il ciclo di vita, il confine di verifica, la
-- sorgente unica della spunta e la proiezione pubblica.
--
-- ---------------------------------------------------------------------------
-- PERCHE' UNA TABELLA NUOVA E NON `profile_certifications`
-- ---------------------------------------------------------------------------
--
-- `public.profile_certifications` (20260825120000, congelata e distribuita)
-- e' un'altra cosa, e la differenza non e' di nomenclatura:
--
--   * contiene ESITI e mai PROVE - lo dichiara nel proprio commento, e la
--     scelta era giusta per un dominio KYC che nessuno aveva deciso di aprire.
--     Qui le prove servono: una qualifica professionale si verifica leggendo
--     un documento, e senza documento non c'e' niente da verificare;
--   * ha `primary key (user_id, tipo)`, cioe' AL PIU' UNA riga per specie.
--     Una persona ha piu' qualifiche professionali - un diploma, un'iscrizione
--     a un albo, un attestato - e devono coesistere. Riusare quella tabella
--     avrebbe significato o cambiarne la chiave primaria (vietato: e' una
--     migrazione distribuita) o costringere il dominio nuovo dentro una forma
--     che lo nega;
--   * non ha un ciclo di vita. Una riga o c'e' o non c'e': non esiste bozza,
--     non esiste invio, non esiste rifiuto. Il dominio nuovo e' invece fatto
--     quasi interamente del percorso fra quegli stati.
--
-- Quella tabella, i suoi tipi, la sua vista `private.certificazioni_valide`,
-- `public.my_certifications` e `public_listings.seller_verificato` restano
-- ESATTAMENTE come sono. Questo file non li legge, non li scrive, non li
-- rinomina e non ne cambia il significato. Convivono: uno dice «una fonte
-- fidata ha accertato chi e' questa persona», l'altro dice «questa persona ha
-- una qualifica professionale approvata». Non sono la stessa affermazione e
-- non devono collassare l'una sull'altra.
--
-- ---------------------------------------------------------------------------
-- IL VERDETTO NON PASSA MAI DAL BROWSER
-- ---------------------------------------------------------------------------
--
-- E' l'invariante centrale del file, e non e' affidata a una convenzione ne'
-- al fatto che nessuna RPC concessa al client la offra. Il passaggio a
-- `approvata` o `rifiutata` e' rifiutato da un TRIGGER a meno che la sessione
-- non porti il marcatore che solo `professional_qualification_review_apply`
-- imposta, `set local`, dentro la propria transazione. Ne segue che:
--
--   * nessuna sessione autenticata puo' approvarsi, qualunque ruolo abbia;
--   * nemmeno `service_role` con una UPDATE diretta puo' emettere un verdetto,
--     perche' il marcatore non c'e';
--   * l'unica via e' la porta di review, che a sua volta e' concessa al solo
--     `service_role` e rifiuta ogni chiamata che porti con se' un `auth.uid()`.
--
-- ---------------------------------------------------------------------------
-- FAIL-CLOSED SUL FORNITORE
-- ---------------------------------------------------------------------------
--
-- Nessun fornitore di intelligenza artificiale viene scelto, nominato,
-- configurato o contattato qui. Non c'e' una chiave, non c'e' un URL, non c'e'
-- un cron, non c'e' un job. Le colonne `provider` e `model` sono testo
-- nullabile e nessun valore compare in questa migrazione.
--
-- La conseguenza operativa e' precisa e va scritta: finche' nessun worker
-- fidato chiama la porta di review, NESSUNA qualifica viene mai approvata da
-- sola. Lo stato di riposo del sistema e' «inviata, in attesa», non
-- «approvata». Il fallimento del fornitore - non configurato, irraggiungibile,
-- incerto - non produce un badge.
--
-- ---------------------------------------------------------------------------
-- CHE COSA QUESTO FILE NON FA
-- ---------------------------------------------------------------------------
--
-- Non tocca `public.profiles`, `public.listings`, `public_listings`,
-- `public.profile_certifications` e i ruoli. Non crea nessun elenco di
-- persone. Non scrive nessuna riga di dominio. Non aggiunge `seller_verificato`
-- da nessuna parte e non lo usa come sorgente di niente: la spunta nuova ha
-- una sorgente nuova, dichiarata in [10] e in nessun altro posto.

create schema if not exists private;

-- ---------------------------------------------------------------------------
-- [1] Tipi
-- ---------------------------------------------------------------------------

create type public.qualifica_professionale_stato as enum (
  'bozza',
  'inviata',
  'approvata',
  'rifiutata',
  'ritirata'
);

comment on type public.qualifica_professionale_stato is
  'Ciclo di vita di una qualifica professionale. `bozza`: in compilazione, '
  'modificabile dal titolare. `inviata`: consegnata alla verifica, dati e '
  'documenti congelati. `approvata` / `rifiutata`: esito, scrivibile solo '
  'dalla porta di review. `ritirata`: il titolare ha rinunciato prima '
  'dell''esito. Da `approvata`, `rifiutata` e `ritirata` non si esce.';

create type public.qualifica_review_verdetto as enum (
  'approved',
  'rejected',
  'inconclusive'
);

comment on type public.qualifica_review_verdetto is
  'Esito strutturato di una verifica. `inconclusive` esiste perche una '
  'verifica incerta deve poter essere registrata SENZA muovere la qualifica: '
  'senza questa label il chiamante sarebbe costretto a scegliere fra approvare '
  'e rifiutare cio che non ha capito.';

-- ---------------------------------------------------------------------------
-- [2] La qualifica
-- ---------------------------------------------------------------------------
--
-- Nessuna tassonomia chiusa di titoli, e non e' pigrizia. Un enum di specie
-- professionali - sommelier, enologo, agronomo, distributore - sarebbe una
-- decisione di prodotto presa dentro una migrazione tecnica, e sarebbe sbagliata
-- il giorno in cui si presenta la prima qualifica estera che non vi rientra.
-- Il titolo e l'ente sono testo dichiarato dall'interessato: nessuno dei due e'
-- creduto sulla parola, perche' entrambi diventano pubblici SOLO dopo che una
-- verifica ha letto il documento e ha detto di si'.
--
-- NESSUN VINCOLO DI UNICITA' SU (user_id, ...). Piu' qualifiche per la stessa
-- persona sono il caso normale, non l'eccezione: un unique qui - anche solo su
-- (user_id, titolo) - trasformerebbe una seconda iscrizione in un errore.

create table public.professional_qualifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  titolo text not null,
  ente_emittente text not null,
  paese text,
  -- PRIVATO, e resta privato in ogni proiezione pubblica: e' il numero di
  -- iscrizione, di tessera o di attestato. Serve a chi verifica per confrontare
  -- il documento con un registro; non serve a chi guarda un profilo, e
  -- pubblicarlo esporrebbe un identificativo personale su una pagina aperta.
  credential_reference text,
  issued_on date,
  -- NULL = non scade. Stessa convenzione di `listings.expires_at` e di
  -- `profile_certifications.scade_at`.
  expires_on date,
  stato public.qualifica_professionale_stato not null
    default 'bozza'::public.qualifica_professionale_stato,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint professional_qualifications_titolo_forma
    check (btrim(titolo) <> '' and length(titolo) <= 160),
  constraint professional_qualifications_ente_forma
    check (btrim(ente_emittente) <> '' and length(ente_emittente) <= 160),
  -- ISO 3166-1 alpha-2. Un campo libero avrebbe prodotto «Italia», «IT»,
  -- «italy» e «ITA» nella stessa colonna, cioe' un dato pubblico che non si
  -- puo' confrontare con niente.
  constraint professional_qualifications_paese_forma
    check (paese is null or paese ~ '^[A-Z]{2}$'),
  constraint professional_qualifications_credential_forma
    check (
      credential_reference is null
      or (btrim(credential_reference) <> '' and length(credential_reference) <= 120)
    ),
  constraint professional_qualifications_scadenza_dopo_emissione
    check (expires_on is null or issued_on is null or expires_on >= issued_on),

  -- Coerenza fra stato e marcature temporali. Non e' ornamentale: e' cio che
  -- impedisce a una riga di dichiararsi approvata senza essere mai stata
  -- inviata, e vincola anche uno scrittore privilegiato.
  constraint professional_qualifications_coerenza_stato
    check (
      case stato
        when 'bozza'::public.qualifica_professionale_stato
          then submitted_at is null and reviewed_at is null
        when 'inviata'::public.qualifica_professionale_stato
          then submitted_at is not null and reviewed_at is null
        when 'ritirata'::public.qualifica_professionale_stato
          then reviewed_at is null
        else submitted_at is not null and reviewed_at is not null
      end
    )
);

comment on table public.professional_qualifications is
  'Qualifiche professionali dichiarate dagli iscritti, piu di una per persona. '
  'Nessun privilegio per anon e authenticated: RLS attiva, policy di sola '
  'lettura del titolare come difesa in profondita, e nessun GRANT che permetta '
  'a PostgREST di raggiungere la tabella. Si scrive solo attraverso le RPC '
  'professional_qualification_*; il verdetto solo attraverso la porta di review.';

comment on column public.professional_qualifications.credential_reference is
  'Riferimento della credenziale (numero di iscrizione, di tessera, di '
  'attestato). PRIVATO: nessuna proiezione pubblica lo espone, in nessuno '
  'stato, nemmeno per una qualifica approvata.';

comment on column public.professional_qualifications.expires_on is
  'Fine validita. NULL significa senza scadenza. Una qualifica scaduta resta '
  'approvata nello storico ma smette di essere pubblica e smette di accendere '
  'la spunta, senza che nessuno debba cancellarla.';

create index professional_qualifications_user_idx
  on public.professional_qualifications (user_id, created_at desc);

-- L'indice che serve alla spunta: le sole righe approvate, che sono la
-- minoranza e l'unica che la proiezione pubblica legge.
create index professional_qualifications_approvate_idx
  on public.professional_qualifications (user_id)
  where stato = 'approvata'::public.qualifica_professionale_stato;

alter table public.professional_qualifications enable row level security;

revoke all on public.professional_qualifications from public, anon, authenticated;

-- Difesa in profondita. Non esiste oggi un GRANT che porti PostgREST fin qui:
-- la policy non serve a nessun percorso attivo. Serve al giorno in cui
-- qualcuno concedesse quel GRANT senza rileggere questo file - da quel momento
-- il titolare leggerebbe le proprie righe e nessuno leggerebbe quelle altrui,
-- invece che tutti tutte.
create policy professional_qualifications_select_own
  on public.professional_qualifications
  for select
  to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- [3] I documenti - metadati qui, contenuto nel bucket privato
-- ---------------------------------------------------------------------------
--
-- `storage_path` non e' un URL e non diventa mai pubblico. Il bucket e'
-- privato ([4]): senza una sessione che superi la policy di lettura, conoscere
-- il percorso non serve a niente. Resta comunque fuori da ogni proiezione
-- pubblica, perche' un percorso contiene due identificativi e dice quante
-- prove ha depositato una persona.

create table public.professional_qualification_documents (
  id uuid primary key default gen_random_uuid(),
  qualification_id uuid not null
    references public.professional_qualifications (id) on delete cascade,
  owner_id uuid not null references auth.users (id) on delete cascade,
  storage_path text not null unique,
  mime_type text not null,
  size_bytes bigint not null,
  created_at timestamptz not null default now(),

  constraint professional_qualification_documents_mime
    check (mime_type in ('application/pdf', 'image/jpeg', 'image/png')),
  -- Lo stesso limite del bucket, ripetuto qui perche' il bucket vincola
  -- l'oggetto e questo vincola la riga: chi registrasse un metadato senza
  -- passare da Storage troverebbe comunque il tetto.
  constraint professional_qualification_documents_size
    check (size_bytes > 0 and size_bytes <= 10485760),
  -- IL PERCORSO E' LEGATO ALLA RIGA, non alla buona volonta del chiamante.
  -- `<owner_uuid>/<qualification_uuid>/<file_uuid>.<ext>`: entrambi gli
  -- identificativi sono colonne di QUESTA riga, quindi un percorso che nomina
  -- la cartella di un'altra persona o di un'altra qualifica non e' registrabile,
  -- e non lo e' nemmeno per uno scrittore privilegiato.
  constraint professional_qualification_documents_percorso_legato
    check (
      storage_path ~ (
        '^' || owner_id::text
        || '/' || qualification_id::text
        || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
        || '\.(pdf|jpg|jpeg|png)$'
      )
    ),
  -- Estensione e tipo dichiarato devono dire la stessa cosa: un `.pdf`
  -- registrato come `image/png` sarebbe un modo di far leggere a chi verifica
  -- qualcosa di diverso da quello che il nome promette.
  constraint professional_qualification_documents_estensione_coerente
    check (
      (mime_type = 'application/pdf' and storage_path ~ '\.pdf$')
      or (mime_type = 'image/jpeg' and storage_path ~ '\.(jpg|jpeg)$')
      or (mime_type = 'image/png' and storage_path ~ '\.png$')
    )
);

comment on table public.professional_qualification_documents is
  'Metadati delle prove di una qualifica. Il contenuto sta nel bucket privato '
  '`professional-qualifications`. `storage_path` non e mai pubblico. Nessun '
  'privilegio per anon e authenticated; si scrive solo attraverso '
  'professional_qualification_document_register / _delete.';

create index professional_qualification_documents_qualifica_idx
  on public.professional_qualification_documents (qualification_id);

alter table public.professional_qualification_documents enable row level security;

revoke all on public.professional_qualification_documents from public, anon, authenticated;

create policy professional_qualification_documents_select_own
  on public.professional_qualification_documents
  for select
  to authenticated
  using (owner_id = (select auth.uid()));

-- Il proprietario del documento e' il proprietario della qualifica. E' un
-- vincolo fra tabelle, quindi vive in un trigger e non in un CHECK, e vincola
-- anche chi scrive con privilegi.
create or replace function private.professional_qualification_documents_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
  v_stato public.qualifica_professionale_stato;
begin
  select q.user_id, q.stato
    into v_owner, v_stato
  from public.professional_qualifications q
  where q.id = new.qualification_id;

  if v_owner is null then
    raise exception 'Qualifica inesistente.' using errcode = '23503';
  end if;

  if v_owner <> new.owner_id then
    raise exception 'Il documento non appartiene al titolare della qualifica.'
      using errcode = '42501';
  end if;

  -- Le prove si depositano mentre la qualifica e' ancora in bozza. Dopo
  -- l'invio l'insieme delle prove e' esattamente quello che la verifica ha
  -- letto: aggiungerne una dopo cambierebbe l'oggetto del giudizio.
  if v_stato <> 'bozza'::public.qualifica_professionale_stato then
    raise exception 'I documenti si allegano solo mentre la qualifica e in bozza.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

comment on function private.professional_qualification_documents_guard() is
  'Vincoli fra documento e qualifica che devono valere anche per uno scrittore '
  'privilegiato: stesso titolare, e deposito ammesso solo in bozza.';

revoke execute on function private.professional_qualification_documents_guard()
  from public, anon, authenticated;

create trigger professional_qualification_documents_guard
  before insert on public.professional_qualification_documents
  for each row
  execute function private.professional_qualification_documents_guard();

-- ---------------------------------------------------------------------------
-- [4] Il bucket privato
-- ---------------------------------------------------------------------------
--
-- `public = false`, e la differenza rispetto ad `avatar-profili` non e' una
-- preferenza: un avatar e' fatto per essere visto, un attestato professionale
-- e' un documento personale. Un bucket pubblico avrebbe reso il contenuto
-- leggibile a chiunque conoscesse il percorso, senza alcuna sessione.

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'professional-qualifications',
  'professional-qualifications',
  false,
  10485760,
  array['application/pdf', 'image/jpeg', 'image/png']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- La porta che le policy di Storage possono attraversare.
--
-- Una policy su `storage.objects` viene valutata con i privilegi del
-- chiamante, e `authenticated` non ha e non deve avere SELECT su
-- `public.professional_qualifications`: una sottoquery scritta direttamente
-- nella policy fallirebbe con «permission denied», cioe' negherebbe il
-- caricamento a tutti. E' la stessa forma di problema che CLAUDE.md descrive
-- per `has_role()` dentro una policy a privilegi del chiamante, e si risolve
-- con la stessa arma: una porta `security definer`, stretta.
--
-- La funzione non prende un proprietario: usa `auth.uid()`. Non esiste quindi
-- una chiamata che risponda su una qualifica altrui, e concederla ad
-- `authenticated` non rivela niente che il chiamante non sappia gia.
create or replace function private.qualifica_in_bozza_del_chiamante(p_qualification_id text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  -- La policy applica questa funzione al secondo segmento del percorso, che e'
  -- testo arbitrario finche' la regex non lo ha confermato. SQL non garantisce
  -- l'ordine di valutazione dei predicati di un AND, quindi il cast deve essere
  -- protetto qui e non sperare di essere raggiunto dopo la regex.
  if p_qualification_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return false;
  end if;

  return exists (
    select 1
    from public.professional_qualifications q
    where q.id = p_qualification_id::uuid
      and q.user_id = (select auth.uid())
      and q.stato = 'bozza'::public.qualifica_professionale_stato
  );
end;
$$;

comment on function private.qualifica_in_bozza_del_chiamante(text) is
  'Vero se la qualifica indicata esiste, appartiene al chiamante ed e ancora '
  'in bozza. Serve alle policy di Storage, che girano a privilegi del '
  'chiamante e non possono leggere la tabella. Non accetta un proprietario: '
  'risponde solo sul chiamante.';

revoke all on function private.qualifica_in_bozza_del_chiamante(text) from public, anon;
grant execute on function private.qualifica_in_bozza_del_chiamante(text) to authenticated;

-- Caricamento: cartella del chiamante, sottocartella di una PROPRIA qualifica
-- ancora in bozza, nome di file canonico.
create policy "qualifiche_professionali_insert_propria_cartella"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'professional-qualifications'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and name ~ (
    '^' || (select auth.uid())::text
    || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
    || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
    || '\.(pdf|jpg|jpeg|png)$'
  )
  and private.qualifica_in_bozza_del_chiamante((storage.foldername(name))[2])
);

-- Lettura: soltanto la propria cartella. `anon` non compare fra i ruoli, e il
-- bucket non e' pubblico: per un visitatore non esiste alcun percorso.
create policy "qualifiche_professionali_select_propria_cartella"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'professional-qualifications'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

-- Cancellazione: solo mentre la qualifica e' in bozza. Dopo l'invio la prova
-- e' congelata - e' l'oggetto su cui qualcuno sta per dare un giudizio, e
-- lasciarla sfilare significherebbe poter far verificare un documento e poi
-- sostituirlo.
create policy "qualifiche_professionali_delete_bozza"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'professional-qualifications'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and private.qualifica_in_bozza_del_chiamante((storage.foldername(name))[2])
);

-- Nessuna policy di UPDATE, deliberatamente: un oggetto non si sovrascrive.
-- Sostituire una prova significa cancellarla in bozza e caricarne un'altra,
-- che lascia traccia in `professional_qualification_documents`.

-- ---------------------------------------------------------------------------
-- [5] Il guardiano del ciclo di vita
-- ---------------------------------------------------------------------------
--
-- Qui vive l'invariante centrale del file. Il trigger non guarda il ruolo di
-- chi scrive: guarda la transizione e il marcatore di transazione. Ne segue che
-- lega allo stesso modo una sessione autenticata, `service_role`, una futura
-- RPC scritta male e una UPDATE eseguita a mano nella console SQL.

create or replace function private.professional_qualifications_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_da public.qualifica_professionale_stato := old.stato;
  v_a public.qualifica_professionale_stato := new.stato;
begin
  if new.user_id <> old.user_id then
    raise exception 'Una qualifica non cambia titolare.' using errcode = '42501';
  end if;

  -- [a] Dati sostanziali congelati appena la qualifica esce dalla bozza.
  -- Comprende il caso «approvata e poi ritoccata», che sarebbe il modo piu
  -- semplice di trasformare un badge ottenuto per una cosa in un badge che ne
  -- dichiara un'altra.
  if v_da <> 'bozza'::public.qualifica_professionale_stato then
    if (new.titolo, new.ente_emittente, new.paese, new.credential_reference,
        new.issued_on, new.expires_on)
       is distinct from
       (old.titolo, old.ente_emittente, old.paese, old.credential_reference,
        old.issued_on, old.expires_on)
    then
      raise exception 'Una qualifica inviata non e piu modificabile.'
        using errcode = '42501';
    end if;
  end if;

  -- [b] Transizioni ammesse. Gli stati terminali non hanno uscite: una
  -- qualifica rifiutata non si «riapre», se ne presenta un'altra.
  if v_a <> v_da then
    if not (
      (v_da = 'bozza'::public.qualifica_professionale_stato
        and v_a in ('inviata'::public.qualifica_professionale_stato,
                    'ritirata'::public.qualifica_professionale_stato))
      or (v_da = 'inviata'::public.qualifica_professionale_stato
        and v_a in ('approvata'::public.qualifica_professionale_stato,
                    'rifiutata'::public.qualifica_professionale_stato,
                    'ritirata'::public.qualifica_professionale_stato))
    ) then
      raise exception 'Transizione di stato non ammessa: da % a %.', v_da, v_a
        using errcode = '42501';
    end if;
  end if;

  -- [c] IL VERDETTO. Solo la porta di review, che imposta il marcatore
  -- `set local` dentro la propria transazione, puo produrre un esito. Nessun
  -- ruolo e' esentato: `service_role` che aggiornasse la riga a mano trova
  -- questo stesso rifiuto.
  if v_a in ('approvata'::public.qualifica_professionale_stato,
             'rifiutata'::public.qualifica_professionale_stato)
     and v_a <> v_da
  then
    if coalesce(current_setting('vinea.pq_review', true), '') <> 'on' then
      raise exception
        'Un esito di verifica si scrive solo attraverso professional_qualification_review_apply.'
        using errcode = '42501';
    end if;
  end if;

  -- [d] `reviewed_at` e' una marcatura di esito, non un campo. Si muove solo
  -- insieme all'esito.
  if new.reviewed_at is distinct from old.reviewed_at
     and v_a not in ('approvata'::public.qualifica_professionale_stato,
                     'rifiutata'::public.qualifica_professionale_stato)
  then
    raise exception 'reviewed_at si imposta solo con un esito di verifica.'
      using errcode = '42501';
  end if;

  -- [e] `submitted_at` non si riscrive: e' la data in cui quella qualifica e
  -- stata consegnata, e resta quella anche dopo l'esito.
  if old.submitted_at is not null and new.submitted_at is distinct from old.submitted_at then
    raise exception 'submitted_at non si riscrive.' using errcode = '42501';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

comment on function private.professional_qualifications_guard() is
  'Ciclo di vita autoritativo. Congela i dati dopo l invio, ammette solo le '
  'transizioni dichiarate, e rifiuta ogni passaggio ad approvata/rifiutata che '
  'non provenga dalla porta di review - anche se a scrivere e service_role.';

revoke execute on function private.professional_qualifications_guard()
  from public, anon, authenticated;

create trigger professional_qualifications_guard
  before update on public.professional_qualifications
  for each row
  execute function private.professional_qualifications_guard();

-- ---------------------------------------------------------------------------
-- [6] Le porte del titolare
-- ---------------------------------------------------------------------------
--
-- Nessun GRANT di INSERT, UPDATE o DELETE sulle due tabelle: il client non ha
-- una scrittura diretta da cui difendersi. Ogni RPC risolve l'identita con
-- `auth.uid()` e non accetta un proprietario come parametro - non c'e' un
-- `p_user_id` da manomettere in nessuna delle firme che seguono.

create or replace function public.professional_qualification_create(
  p_titolo text,
  p_ente_emittente text,
  p_paese text default null,
  p_credential_reference text default null,
  p_issued_on date default null,
  p_expires_on date default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Serve una sessione.' using errcode = '42501';
  end if;

  insert into public.professional_qualifications (
    user_id, titolo, ente_emittente, paese, credential_reference,
    issued_on, expires_on
  )
  values (
    v_uid,
    btrim(p_titolo),
    btrim(p_ente_emittente),
    nullif(btrim(upper(coalesce(p_paese, ''))), ''),
    nullif(btrim(coalesce(p_credential_reference, '')), ''),
    p_issued_on,
    p_expires_on
  )
  returning id into v_id;

  return v_id;
end;
$$;

comment on function public.professional_qualification_create(
  text, text, text, text, date, date) is
  'Apre una bozza di qualifica intestata al chiamante. Non accetta un '
  'proprietario: l identita e auth.uid(). Lo stato iniziale e sempre bozza.';

revoke all on function public.professional_qualification_create(
  text, text, text, text, date, date) from public, anon;
grant execute on function public.professional_qualification_create(
  text, text, text, text, date, date) to authenticated;

create or replace function public.professional_qualification_update(
  p_id uuid,
  p_titolo text,
  p_ente_emittente text,
  p_paese text default null,
  p_credential_reference text default null,
  p_issued_on date default null,
  p_expires_on date default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_stato public.qualifica_professionale_stato;
begin
  if v_uid is null then
    raise exception 'Serve una sessione.' using errcode = '42501';
  end if;

  -- Il lock serve: fra la lettura dello stato e la UPDATE puo passare un
  -- invio concorrente della stessa persona da un'altra scheda.
  select q.stato into v_stato
  from public.professional_qualifications q
  where q.id = p_id and q.user_id = v_uid
  for update;

  if v_stato is null then
    raise exception 'Qualifica non trovata.' using errcode = 'P0001';
  end if;

  if v_stato <> 'bozza'::public.qualifica_professionale_stato then
    raise exception 'Solo una bozza si puo modificare.' using errcode = '42501';
  end if;

  update public.professional_qualifications q
  set titolo = btrim(p_titolo),
      ente_emittente = btrim(p_ente_emittente),
      paese = nullif(btrim(upper(coalesce(p_paese, ''))), ''),
      credential_reference = nullif(btrim(coalesce(p_credential_reference, '')), ''),
      issued_on = p_issued_on,
      expires_on = p_expires_on
  where q.id = p_id;
end;
$$;

comment on function public.professional_qualification_update(
  uuid, text, text, text, text, date, date) is
  'Riscrive una PROPRIA bozza. Rifiuta qualunque altro stato: dopo l invio i '
  'dati sono l oggetto di un giudizio e non si toccano piu.';

revoke all on function public.professional_qualification_update(
  uuid, text, text, text, text, date, date) from public, anon;
grant execute on function public.professional_qualification_update(
  uuid, text, text, text, text, date, date) to authenticated;

-- Registrazione di una prova gia caricata nel bucket.
--
-- L'ordine e' deliberato: prima l'oggetto in Storage, poi il metadato. Se la
-- registrazione fallisce resta un oggetto orfano in una cartella privata, che
-- non e' raggiungibile da nessuna proiezione e che il titolare puo cancellare
-- finche' la qualifica e' in bozza. L'ordine opposto avrebbe prodotto il
-- difetto grave e non quello innocuo: un metadato che promette una prova che
-- non esiste, e un invio che passa con zero documenti veri.
create or replace function public.professional_qualification_document_register(
  p_qualification_id uuid,
  p_storage_path text,
  p_mime_type text,
  p_size_bytes bigint
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_stato public.qualifica_professionale_stato;
  v_meta jsonb;
  v_mime text;
  v_size bigint;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Serve una sessione.' using errcode = '42501';
  end if;

  select q.stato into v_stato
  from public.professional_qualifications q
  where q.id = p_qualification_id and q.user_id = v_uid
  for update;

  if v_stato is null then
    raise exception 'Qualifica non trovata.' using errcode = 'P0001';
  end if;

  if v_stato <> 'bozza'::public.qualifica_professionale_stato then
    raise exception 'I documenti si allegano solo mentre la qualifica e in bozza.'
      using errcode = '42501';
  end if;

  -- LA PROVA DEVE ESISTERE DAVVERO. Senza questa lettura, «invio con almeno un
  -- documento» sarebbe soddisfatto da una riga di metadati inventata, e la
  -- verifica riceverebbe una qualifica senza niente da leggere.
  select o.metadata into v_meta
  from storage.objects o
  where o.bucket_id = 'professional-qualifications'
    and o.name = p_storage_path;

  if not found then
    raise exception 'Il documento non risulta caricato.' using errcode = 'P0001';
  end if;

  -- Dimensione e tipo li dichiara Storage, non il chiamante: i parametri sono
  -- il ripiego per un backend che non li avesse annotati, e i CHECK della
  -- tabella valgono comunque su entrambe le strade.
  v_mime := coalesce(nullif(v_meta ->> 'mimetype', ''), p_mime_type);
  v_size := coalesce((v_meta ->> 'size')::bigint, p_size_bytes);

  insert into public.professional_qualification_documents (
    qualification_id, owner_id, storage_path, mime_type, size_bytes
  )
  values (p_qualification_id, v_uid, p_storage_path, v_mime, v_size)
  returning id into v_id;

  return v_id;
end;
$$;

comment on function public.professional_qualification_document_register(
  uuid, text, text, bigint) is
  'Registra una prova gia presente nel bucket privato. Verifica che l oggetto '
  'esista e ne legge tipo e dimensione da Storage; il percorso resta legato a '
  'titolare e qualifica dal CHECK di riga.';

revoke all on function public.professional_qualification_document_register(
  uuid, text, text, bigint) from public, anon;
grant execute on function public.professional_qualification_document_register(
  uuid, text, text, bigint) to authenticated;

create or replace function public.professional_qualification_document_delete(
  p_document_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_stato public.qualifica_professionale_stato;
begin
  if v_uid is null then
    raise exception 'Serve una sessione.' using errcode = '42501';
  end if;

  select q.stato into v_stato
  from public.professional_qualification_documents d
    join public.professional_qualifications q on q.id = d.qualification_id
  where d.id = p_document_id and d.owner_id = v_uid
  for update of q;

  if v_stato is null then
    raise exception 'Documento non trovato.' using errcode = 'P0001';
  end if;

  if v_stato <> 'bozza'::public.qualifica_professionale_stato then
    raise exception 'Le prove di una qualifica inviata non si rimuovono.'
      using errcode = '42501';
  end if;

  delete from public.professional_qualification_documents d
  where d.id = p_document_id;
end;
$$;

comment on function public.professional_qualification_document_delete(uuid) is
  'Rimuove il metadato di una PROPRIA prova, solo mentre la qualifica e in '
  'bozza. L oggetto in Storage si cancella a parte, e la policy di delete '
  'applica la stessa condizione.';

revoke all on function public.professional_qualification_document_delete(uuid)
  from public, anon;
grant execute on function public.professional_qualification_document_delete(uuid)
  to authenticated;

create or replace function public.professional_qualification_submit(p_id uuid)
returns public.qualifica_professionale_stato
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_stato public.qualifica_professionale_stato;
  v_documenti integer;
begin
  if v_uid is null then
    raise exception 'Serve una sessione.' using errcode = '42501';
  end if;

  select q.stato into v_stato
  from public.professional_qualifications q
  where q.id = p_id and q.user_id = v_uid
  for update;

  if v_stato is null then
    raise exception 'Qualifica non trovata.' using errcode = 'P0001';
  end if;

  -- Reinviare una qualifica gia inviata non e' un errore da segnalare come
  -- guasto: e' il doppio clic. Si risponde con lo stato corrente.
  if v_stato = 'inviata'::public.qualifica_professionale_stato then
    return v_stato;
  end if;

  if v_stato <> 'bozza'::public.qualifica_professionale_stato then
    raise exception 'Solo una bozza si puo inviare.' using errcode = '42501';
  end if;

  -- Il metadato non basta: un client potrebbe avere cancellato l'oggetto in
  -- Storage senza cancellare prima la riga. L'invio conta soltanto prove ancora
  -- presenti nel bucket privato, così la verifica non riceve una promessa vuota.
  select count(*) into v_documenti
  from public.professional_qualification_documents d
    join storage.objects o
      on o.bucket_id = 'professional-qualifications'
     and o.name = d.storage_path
  where d.qualification_id = p_id;

  if v_documenti = 0 then
    raise exception 'Allega almeno un documento presente in archivio prima di inviare la qualifica.'
      using errcode = 'P0001';
  end if;

  update public.professional_qualifications q
  set stato = 'inviata'::public.qualifica_professionale_stato,
      submitted_at = now()
  where q.id = p_id;

  return 'inviata'::public.qualifica_professionale_stato;
end;
$$;

comment on function public.professional_qualification_submit(uuid) is
  'Consegna una PROPRIA bozza alla verifica. Pretende almeno una prova '
  'registrata. Da qui in poi dati e documenti sono congelati, e l esito puo '
  'arrivare solo dalla porta di review.';

revoke all on function public.professional_qualification_submit(uuid) from public, anon;
grant execute on function public.professional_qualification_submit(uuid) to authenticated;

create or replace function public.professional_qualification_withdraw(p_id uuid)
returns public.qualifica_professionale_stato
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_stato public.qualifica_professionale_stato;
begin
  if v_uid is null then
    raise exception 'Serve una sessione.' using errcode = '42501';
  end if;

  select q.stato into v_stato
  from public.professional_qualifications q
  where q.id = p_id and q.user_id = v_uid
  for update;

  if v_stato is null then
    raise exception 'Qualifica non trovata.' using errcode = 'P0001';
  end if;

  if v_stato = 'ritirata'::public.qualifica_professionale_stato then
    return v_stato;
  end if;

  -- Il ritiro e' una rinuncia, non una gomma. Una qualifica gia decisa resta
  -- nello storico con il suo esito: cancellare un rifiuto ritirandolo dopo
  -- significherebbe poter riprovare all'infinito senza traccia.
  if v_stato not in ('bozza'::public.qualifica_professionale_stato,
                     'inviata'::public.qualifica_professionale_stato) then
    raise exception 'Si ritira solo una qualifica in bozza o in verifica.'
      using errcode = '42501';
  end if;

  update public.professional_qualifications q
  set stato = 'ritirata'::public.qualifica_professionale_stato
  where q.id = p_id;

  return 'ritirata'::public.qualifica_professionale_stato;
end;
$$;

comment on function public.professional_qualification_withdraw(uuid) is
  'Rinuncia a una PROPRIA qualifica in bozza o in verifica. Non tocca una '
  'qualifica gia decisa: un esito non si cancella ritirandolo dopo.';

revoke all on function public.professional_qualification_withdraw(uuid) from public, anon;
grant execute on function public.professional_qualification_withdraw(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- [7] LA SPUNTA - un posto solo
-- ---------------------------------------------------------------------------
--
-- Qui, e in nessun altro punto del repository, e' scritta la regola:
--
--   professionista verificato = esiste almeno UNA qualifica `approvata`
--                               e non scaduta.
--
-- Scaduta si misura in giorni e non in istanti - `expires_on` e' una `date` -
-- quindi una qualifica vale per tutto il giorno in cui scade. `NULL` significa
-- senza scadenza.
--
-- CHE COSA NON ACCENDE QUESTA SPUNTA, e va scritto perche' e' il punto in cui
-- un errore futuro sarebbe silenzioso:
--
--   * `public_listings.seller_verificato` - dice un'altra cosa (identita e
--     abilitazione a vendere), resta dov'e' e non entra qui;
--   * qualunque riga di `public.profile_certifications`, di qualunque tipo;
--   * una qualifica `inviata`, `rifiutata`, `ritirata` o ancora in `bozza`;
--   * una qualifica approvata e poi scaduta.
--
-- E' una VISTA e non una funzione, per la stessa ragione tecnica documentata
-- dalla 20260825120000: in una vista `security_invoker = off` la sostituzione
-- di privilegi vale per l'albero della query, non per il corpo di una funzione
-- chiamata nella target list.

create view private.qualifiche_professionali_valide
with (security_invoker = off, security_barrier = true)
as
select
  q.id,
  q.user_id,
  q.titolo,
  q.ente_emittente,
  q.paese,
  q.issued_on,
  q.expires_on
from public.professional_qualifications q
where q.stato = 'approvata'::public.qualifica_professionale_stato
  and (q.expires_on is null or q.expires_on >= current_date);

comment on view private.qualifiche_professionali_valide is
  'Qualifiche approvate e non scadute: l unico luogo in cui e definita la '
  'spunta di professionista verificato. Non contiene credential_reference. '
  'Nessun privilegio per anon e authenticated, che pure hanno USAGE sullo '
  'schema: si legge attraverso profilo_pubblico(uuid) e '
  'professional_qualifications_me().';

revoke all on private.qualifiche_professionali_valide from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [8] La lettura del titolare
-- ---------------------------------------------------------------------------
--
-- Elenco chiuso di colonne, come `my_certifications` e come `COLONNE_PROFILO`.
-- Include `credential_reference`, che e' privato verso il mondo ma e' un dato
-- che l'interessato ha scritto e deve poter rileggere e correggere in bozza.
--
-- NON include e non includera' nulla della verifica: ne' il fornitore, ne' il
-- modello, ne' la confidenza, ne' il ragionamento. Il titolare vede a che punto
-- e' la sua pratica, non come e' stata giudicata.
--
-- `valida` non e' ricalcolata qui: la legge da [7], che e' l'unico posto in
-- cui la regola della spunta e' scritta.

create or replace function public.professional_qualifications_me()
returns table (
  id uuid,
  titolo text,
  ente_emittente text,
  paese text,
  credential_reference text,
  issued_on date,
  expires_on date,
  stato public.qualifica_professionale_stato,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  created_at timestamptz,
  documenti integer,
  valida boolean,
  -- I metadati delle proprie prove, e soltanto delle proprie. Servono a chi
  -- gestisce una bozza: per togliere un documento occorre il suo identificativo
  -- e il suo percorso, perche' la riga si cancella con la RPC e l'oggetto si
  -- cancella da Storage. Questa e' una porta OWNER-ONLY - `security definer`
  -- filtrata su `auth.uid()`, concessa al solo ruolo `authenticated` - e
  -- `storage_path` non attraversa nessuna proiezione pubblica: la funzione del
  -- profilo pubblico non ha una colonna che possa contenerlo.
  documenti_elenco jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    q.id,
    q.titolo,
    q.ente_emittente,
    q.paese,
    q.credential_reference,
    q.issued_on,
    q.expires_on,
    q.stato,
    q.submitted_at,
    q.reviewed_at,
    q.created_at,
    (
      select count(*)
      from public.professional_qualification_documents d
      where d.qualification_id = q.id
    )::integer as documenti,
    exists (
      select 1
      from private.qualifiche_professionali_valide v
      where v.id = q.id
    ) as valida,
    coalesce(
      (
        select jsonb_agg(
                 jsonb_build_object(
                   'id', d.id,
                   'storage_path', d.storage_path,
                   'mime_type', d.mime_type,
                   'size_bytes', d.size_bytes,
                   'created_at', d.created_at
                 )
                 order by d.created_at
               )
        from public.professional_qualification_documents d
        where d.qualification_id = q.id
      ),
      '[]'::jsonb
    ) as documenti_elenco
  from public.professional_qualifications q
  where q.user_id = (select auth.uid())
  order by q.created_at desc;
$$;

comment on function public.professional_qualifications_me() is
  'Le qualifiche della sola persona collegata. Zero righe per un chiamante '
  'anonimo. Non espone nulla della verifica: ne fornitore, ne modello, ne '
  'confidenza, ne ragionamento.';

revoke all on function public.professional_qualifications_me() from public, anon;
grant execute on function public.professional_qualifications_me() to authenticated;

-- ---------------------------------------------------------------------------
-- [9] Le verifiche - private, append-only
-- ---------------------------------------------------------------------------
--
-- Sta in `private` e non in `public` perche' PostgREST non deve poterla
-- raggiungere in nessun modo. Non e' una precauzione generica: `private_payload`
-- contiene cio che il fornitore ha risposto - potenzialmente il testo estratto
-- dal documento, cioe' il documento stesso in un'altra forma.
--
-- Nemmeno l'interessato la legge dal client. Puo' sembrare severo e non lo e':
-- restituire il ragionamento di una verifica a chi la subisce e' il modo piu'
-- rapido di insegnare come superarla al secondo tentativo.

create table private.professional_qualification_reviews (
  id uuid primary key default gen_random_uuid(),
  qualification_id uuid not null
    references public.professional_qualifications (id) on delete cascade,
  -- La chiave di deduplica. Un worker che ritenta dopo un timeout deve poter
  -- riconsegnare LO STESSO verdetto senza produrne un secondo.
  idempotency_key text not null,
  provider text,
  model text,
  verdict public.qualifica_review_verdetto not null,
  confidence numeric(4, 3),
  private_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),

  constraint professional_qualification_reviews_confidence_range
    check (confidence is null or (confidence >= 0 and confidence <= 1)),
  constraint professional_qualification_reviews_idempotency_forma
    check (btrim(idempotency_key) <> '' and length(idempotency_key) <= 200),
  constraint professional_qualification_reviews_dedup
    unique (qualification_id, idempotency_key)
);

comment on table private.professional_qualification_reviews is
  'Registro append-only delle verifiche. Sta in `private` perche '
  '`private_payload` puo contenere il contenuto estratto dai documenti. Non e '
  'leggibile da nessun ruolo client, nemmeno dall interessato: si scrive solo '
  'attraverso professional_qualification_review_apply.';

alter table private.professional_qualification_reviews enable row level security;

revoke all on private.professional_qualification_reviews
  from public, anon, authenticated;

-- Append-only nella stessa forma della 20260826163000 per `balance_movimenti`:
-- un registro di giudizi che si puo riscrivere non e' un registro.
create or replace function private.professional_qualification_reviews_append_only()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Il registro delle verifiche e append-only.' using errcode = '42501';
end;
$$;

revoke execute on function private.professional_qualification_reviews_append_only()
  from public, anon, authenticated;

create trigger professional_qualification_reviews_no_update
  before update on private.professional_qualification_reviews
  for each row execute function private.professional_qualification_reviews_append_only();

create trigger professional_qualification_reviews_no_delete
  before delete on private.professional_qualification_reviews
  for each row execute function private.professional_qualification_reviews_append_only();

create trigger professional_qualification_reviews_no_truncate
  before truncate on private.professional_qualification_reviews
  for each statement execute function private.professional_qualification_reviews_append_only();

-- ---------------------------------------------------------------------------
-- [10] La porta fidata - l'unico ingresso di un verdetto
-- ---------------------------------------------------------------------------
--
-- DUE SERRATURE, e servono entrambe.
--
--   1. EXECUTE concesso al solo `service_role`. E' la serratura vera: una
--      sessione di browser non ha il privilegio e la chiamata non parte.
--   2. `auth.uid()` deve essere nullo. E' la serratura contro il caso in cui
--      una richiesta arrivi con la chiave di servizio E il JWT di una persona:
--      un worker fidato non ha un utente collegato, quindi la condizione e'
--      vera per il chiamante legittimo e falsa per un tentativo di far passare
--      un verdetto attraverso una sessione. Non si affida a `auth.role()`, che
--      e' un claim, ma all'assenza di un'identita.
--
-- La terza barriera non e' qui ed e' la piu importante: il trigger [5] rifiuta
-- il passaggio ad approvata/rifiutata a chiunque non abbia impostato il
-- marcatore che questa funzione imposta. Anche se le due serrature qui sopra
-- cadessero, una UPDATE diretta non produrrebbe comunque un badge.

create or replace function public.professional_qualification_review_apply(
  p_qualification_id uuid,
  p_idempotency_key text,
  p_verdict public.qualifica_review_verdetto,
  p_provider text default null,
  p_model text default null,
  p_confidence numeric default null,
  p_private_payload jsonb default '{}'::jsonb
)
returns public.qualifica_professionale_stato
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_stato public.qualifica_professionale_stato;
  v_inserite integer;
  v_review private.professional_qualification_reviews%rowtype;
  v_confidence numeric(4, 3) := p_confidence;
  v_private_payload jsonb := coalesce(p_private_payload, '{}'::jsonb);
begin
  -- Serratura 2: nessuna identita collegata.
  if (select auth.uid()) is not null then
    raise exception 'Un esito di verifica non si applica da una sessione utente.'
      using errcode = '42501';
  end if;

  select q.stato into v_stato
  from public.professional_qualifications q
  where q.id = p_qualification_id
  for update;

  if v_stato is null then
    raise exception 'Qualifica non trovata.' using errcode = 'P0001';
  end if;

  -- IDEMPOTENZA. Il registro e' la fonte: se questa coppia
  -- (qualifica, chiave) c'e' gia, la verifica e' gia stata applicata. Solo la
  -- riconsegna dello stesso payload e' un replay: riusare la chiave con un dato
  -- diverso e' un conflitto, non una conferma del primo esito.
  insert into private.professional_qualification_reviews (
    qualification_id, idempotency_key, provider, model, verdict, confidence,
    private_payload
  )
  values (
    p_qualification_id, p_idempotency_key, p_provider, p_model, p_verdict,
    v_confidence, v_private_payload
  )
  on conflict on constraint professional_qualification_reviews_dedup do nothing;

  get diagnostics v_inserite = row_count;
  if v_inserite = 0 then
    select r.* into strict v_review
    from private.professional_qualification_reviews r
    where r.qualification_id = p_qualification_id
      and r.idempotency_key = p_idempotency_key;

    if v_review.verdict is distinct from p_verdict
       or v_review.provider is distinct from p_provider
       or v_review.model is distinct from p_model
       or v_review.confidence is distinct from v_confidence
       or v_review.private_payload is distinct from v_private_payload then
      raise exception 'Chiave di idempotenza gia usata con un payload diverso.'
        using errcode = '22000';
    end if;

    return v_stato;
  end if;

  -- Una verifica ha senso solo su una qualifica consegnata. Il controllo sta
  -- DOPO la deduplica di proposito: la ripetizione di una verifica gia
  -- applicata riguarda una qualifica che nel frattempo e diventata approvata o
  -- rifiutata, e deve rispondere invece di fallire.
  if v_stato <> 'inviata'::public.qualifica_professionale_stato then
    raise exception 'Si verifica solo una qualifica inviata (stato attuale: %).', v_stato
      using errcode = '42501';
  end if;

  -- `inconclusive` non muove niente. La riga di registro resta, cosi un
  -- secondo tentativo con una chiave diversa e' possibile e tracciato, e la
  -- qualifica continua ad aspettare: e' il comportamento fail-closed, perche
  -- l'alternativa - approvare cio di cui non si e sicuri - e l'unico esito
  -- che non si puo correggere dopo.
  if p_verdict = 'inconclusive'::public.qualifica_review_verdetto then
    return v_stato;
  end if;

  -- Il marcatore che il trigger [5] pretende. `set local`: vive per questa
  -- transazione e non oltre.
  perform set_config('vinea.pq_review', 'on', true);

  update public.professional_qualifications q
  set stato = case
                when p_verdict = 'approved'::public.qualifica_review_verdetto
                  then 'approvata'::public.qualifica_professionale_stato
                else 'rifiutata'::public.qualifica_professionale_stato
              end,
      reviewed_at = now()
  where q.id = p_qualification_id
  returning q.stato into v_stato;

  perform set_config('vinea.pq_review', 'off', true);

  return v_stato;
end;
$$;

comment on function public.professional_qualification_review_apply(
  uuid, text, public.qualifica_review_verdetto, text, text, numeric, jsonb) is
  'Unico ingresso di un verdetto. Concessa al solo service_role e rifiutata se '
  'la richiesta porta un auth.uid(). Idempotente sulla coppia '
  '(qualifica, chiave): un replay identico riesce, un payload incompatibile e '
  'rifiutato. `inconclusive` non muove lo stato: la qualifica resta in attesa, '
  'che e il riposo fail-closed di questo dominio.';

revoke all on function public.professional_qualification_review_apply(
  uuid, text, public.qualifica_review_verdetto, text, text, numeric, jsonb)
  from public, anon, authenticated;
grant execute on function public.professional_qualification_review_apply(
  uuid, text, public.qualifica_review_verdetto, text, text, numeric, jsonb)
  to service_role;

-- La coda che un worker fidato leggera'. E' l'altra meta del contratto
-- provider-neutral: senza una lettura delle prove non esiste una verifica, e
-- senza questa firma il worker dovrebbe farsi dare privilegi sulle tabelle.
--
-- Non nomina nessun fornitore, non contatta niente e non cambia niente. Oggi
-- nessuno la chiama: e' la porta che resta chiusa finche' una decisione fuori
-- da questa migrazione non accende un worker.
create or replace function public.professional_qualification_review_queue(
  p_limite integer default 20
)
returns table (
  qualification_id uuid,
  titolo text,
  ente_emittente text,
  paese text,
  credential_reference text,
  issued_on date,
  expires_on date,
  submitted_at timestamptz,
  documenti jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    q.id,
    q.titolo,
    q.ente_emittente,
    q.paese,
    q.credential_reference,
    q.issued_on,
    q.expires_on,
    q.submitted_at,
    coalesce(
      (
        select jsonb_agg(
                 jsonb_build_object(
                   'storage_path', d.storage_path,
                   'mime_type', d.mime_type,
                   'size_bytes', d.size_bytes
                 )
                 order by d.created_at
               )
        from public.professional_qualification_documents d
        where d.qualification_id = q.id
      ),
      '[]'::jsonb
    ) as documenti
  from public.professional_qualifications q
  where q.stato = 'inviata'::public.qualifica_professionale_stato
  order by q.submitted_at
  limit greatest(1, least(coalesce(p_limite, 20), 100));
$$;

comment on function public.professional_qualification_review_queue(integer) is
  'Coda delle qualifiche in attesa, con i percorsi delle prove. Concessa al '
  'solo service_role. Nessun fornitore e nominato o contattato: e la firma che '
  'un futuro worker fidato usera per leggere cio che deve verificare.';

revoke all on function public.professional_qualification_review_queue(integer)
  from public, anon, authenticated;
grant execute on function public.professional_qualification_review_queue(integer)
  to service_role;

notify pgrst, 'reload schema';
