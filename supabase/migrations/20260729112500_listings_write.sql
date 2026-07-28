-- Fase 6b — Scrittura degli annunci: creazione, transizioni di stato, storage.
--
-- La Fase 6a ha creato lo schema e ha lasciato fuori ogni via di scrittura
-- dello stato: `stato`, `published_at`, `expires_at` e le colonne di
-- tracciamento non compaiono nei GRANT di colonna, quindi dal browser sono
-- irraggiungibili per costruzione. Questa migrazione apre l'unica porta
-- prevista: quattro funzioni SECURITY DEFINER, ciascuna con un controllo
-- esplicito di proprietà e di stato di partenza.
--
-- COSA RESTA FUORI. Le transizioni di moderazione (in_revisione,
-- modifiche_richieste, rifiutato) sono Fase 9; quelle di vendita (riservato,
-- venduto) sono Fase 7. La lista dei GRANT di colonna della 6a NON cambia:
-- era già stata scritta per non dover cambiare, ed è questa la prova.

-- ---------------------------------------------------------------------------
-- Estensioni
-- ---------------------------------------------------------------------------

-- Gli slug nascono da testo digitato dall'utente ("Château d'Yquem"), che
-- contiene accenti e apostrofi. Senza unaccent, "Château" diventerebbe
-- "ch-teau": leggibile a fatica e diverso da quello che chiunque scriverebbe
-- a mano.
create extension if not exists unaccent with schema extensions;

-- ---------------------------------------------------------------------------
-- slugifica — da testo libero a identificatore d'URL
-- ---------------------------------------------------------------------------
-- Deve produrre qualcosa che soddisfi il CHECK '^[a-z0-9]+(-[a-z0-9]+)*$' di
-- wines.slug e listings.slug, per qualunque input. Il coalesce finale copre
-- il caso limite di un testo che dopo la normalizzazione non lascia nessun
-- carattere utile (per esempio solo ideogrammi o solo punteggiatura): meglio
-- uno slug generico che una violazione di CHECK in faccia all'utente.

-- Nota sulla forma a due argomenti di unaccent(). La versione a un argomento
-- cerca un dizionario chiamato "unaccent" nel search_path corrente: con
-- search_path fissato a `public` non lo troverebbe, perché l'estensione vive
-- nello schema `extensions`. Passare il dizionario esplicitamente come
-- regdictionary toglie di mezzo la dipendenza dal search_path invece di
-- allargarlo.

create or replace function public.slugifica(p_testo text)
returns text
language sql
stable
set search_path = public
as $$
  select coalesce(
    nullif(
      trim(both '-' from
        regexp_replace(
          lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(p_testo, ''))),
          '[^a-z0-9]+', '-', 'g'
        )
      ),
      ''
    ),
    'annuncio'
  );
$$;

comment on function public.slugifica(text) is
  'Normalizza testo libero in uno slug conforme al CHECK di wines.slug e '
  'listings.slug. Uso interno delle funzioni di creazione: non è concessa a '
  'nessun ruolo client.';

revoke execute on function public.slugifica(text) from public;

-- ---------------------------------------------------------------------------
-- listing_crea — creazione di un annuncio in bozza
-- ---------------------------------------------------------------------------
-- PERCHÉ UNA FUNZIONE E NON UN INSERT DAL CLIENT. La 6a concede già a
-- `authenticated` l'INSERT sulle colonne di contenuto di listings e su
-- bottle_units, quindi un annuncio su una bottiglia già esistente si potrebbe
-- creare direttamente. Il wizard /vendi però non parte da una bottiglia: parte
-- da testo digitato (produttore, nome, annata), e quel vino può non essere
-- ancora in catalogo. `wines` è scrivibile solo da admin o moderator
-- (policy wines_write_staff), quindi la creazione attraversa un confine di
-- privilegio che il client non può attraversare da solo.
--
-- Da lì seguono due proprietà che una sequenza di tre INSERT dal browser non
-- avrebbe: l'operazione è atomica (niente bottiglia orfana se l'annuncio
-- fallisce) e lo slug lo assegna il server (niente slug scelti o occupati dal
-- client).
--
-- UNA CREAZIONE, UNA BOTTIGLIA NUOVA. Non c'è modo di riusare una bottle_unit
-- esistente perché /vendi in frontend/ non ha nessun selettore di cantina: si
-- descrive una bottiglia, non se ne sceglie una. Quando la Fase 6c porterà la
-- Cantina, "metti in vendita questa bottiglia" diventerà un percorso diverso
-- che passa un bottle_unit_id già noto.

create or replace function public.listing_crea(
  p_produttore text,
  p_nome text,
  p_annata integer,
  p_regione text,
  p_tipo text,
  p_prezzo_cents integer,
  p_condizione text default 'Ottimo',
  p_conservazione text default '',
  p_storia text default '',
  p_immagini text[] default '{}'
)
-- I nomi delle colonne restituite sono prefissati (`annuncio_id`,
-- `annuncio_slug`) e non `id`/`slug`: dentro plpgsql i parametri OUT sono
-- variabili, e chiamarli come colonne delle tabelle toccate qui dentro
-- porterebbe a errori di ambiguità al primo riferimento non qualificato.
returns table (annuncio_id uuid, annuncio_slug text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_wine      uuid;
  v_bottle    uuid;
  v_base      text;
  v_slug      text;
  v_n         integer;
  v_immagine  text;
begin
  if v_uid is null then
    raise exception 'Devi accedere per creare un annuncio.' using errcode = '42501';
  end if;

  -- bottle_units.owner_id e listings.seller_id puntano a profiles, non a
  -- auth.users. Un account senza riga in profiles (trigger handle_new_user non
  -- andato a buon fine) produrrebbe altrimenti una violazione di chiave
  -- esterna grezza, illeggibile per chi la riceve nel wizard.
  if not exists (select 1 from public.profiles p where p.id = v_uid) then
    raise exception 'Il tuo profilo non è ancora completo: completalo prima di pubblicare.'
      using errcode = 'P0001';
  end if;

  -- Validazione. Gli stessi limiti sono anche nel wizard, ma il wizard non è
  -- un confine di fiducia: questa funzione è raggiungibile con una POST
  -- diretta a PostgREST, senza passare da nessuna interfaccia.
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
  if p_condizione is null or p_condizione not in ('Perfetto', 'Ottimo', 'Buono') then
    raise exception 'Condizione non valida.' using errcode = 'P0001';
  end if;
  if p_prezzo_cents is null or p_prezzo_cents <= 0 then
    raise exception 'Il prezzo deve essere maggiore di zero.' using errcode = 'P0001';
  end if;
  if array_length(p_immagini, 1) > 6 then
    raise exception 'Massimo 6 fotografie per annuncio.' using errcode = 'P0001';
  end if;

  -- Le immagini sono percorsi dentro il bucket `annunci`, e ogni utente può
  -- scrivere solo sotto la cartella che porta il proprio id. Senza questo
  -- controllo un annuncio potrebbe puntare al file di un altro utente, o a una
  -- stringa arbitraria che l'interfaccia poi mette dentro un <img src>.
  foreach v_immagine in array coalesce(p_immagini, '{}'::text[]) loop
    if v_immagine !~ ('^' || v_uid::text || '/[0-9a-f-]{36}\.(jpg|jpeg|png|webp|avif)$') then
      raise exception 'Fotografia non valida: %', v_immagine using errcode = 'P0001';
    end if;
  end loop;

  -- Catalogo: si riusa la riga esistente se produttore + nome + annata
  -- coincidono, altrimenti se ne crea una. `on conflict do nothing` seguito da
  -- una select copre la corsa fra due venditori che catalogano lo stesso vino
  -- nello stesso istante.
  select w.id into v_wine
  from public.wines w
  where w.produttore = trim(p_produttore)
    and w.nome = trim(p_nome)
    and w.annata = p_annata::smallint;

  if v_wine is null then
    v_base := public.slugifica(p_produttore || ' ' || p_nome || ' ' || p_annata::text);
    v_slug := v_base;
    v_n := 1;
    while exists (select 1 from public.wines w where w.slug = v_slug) loop
      v_n := v_n + 1;
      v_slug := v_base || '-' || v_n;
    end loop;

    insert into public.wines (slug, produttore, nome, annata, regione, tipo)
    values (v_slug, trim(p_produttore), trim(p_nome), p_annata::smallint, trim(p_regione), p_tipo)
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

  -- Unità fisica. Inserimento minimo: proprietario, vino, stato, visibilità.
  -- Posizione, ambiente, modulo e slot arrivano con la Cantina (Fase 6c).
  insert into public.bottle_units (owner_id, wine_id, stato, visibilita)
  values (v_uid, v_wine, 'chiusa', 'privata')
  returning bottle_units.id into v_bottle;

  -- Slug dell'annuncio. Parte dalla stessa base del vino, così il primo
  -- annuncio di un vino ha l'URL leggibile che ci si aspetta
  -- (/annuncio/tignanello-2019) e i successivi si numerano.
  v_base := public.slugifica(p_produttore || ' ' || p_nome || ' ' || p_annata::text);
  v_slug := v_base;
  v_n := 1;
  while exists (select 1 from public.listings l where l.slug = v_slug) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n;
  end loop;

  -- Fra il controllo di disponibilità dello slug e questo INSERT c'è una
  -- finestra in cui un'altra sessione può prendersi lo stesso slug. È
  -- improbabile e senza conseguenze sui dati (l'unicità regge), ma senza
  -- questo blocco l'utente riceverebbe un 23505 grezzo per un problema che si
  -- risolve riprovando.
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
    when unique_violation then
      raise exception 'Non è stato possibile assegnare un indirizzo univoco all''annuncio. Riprova.'
        using errcode = 'P0001';
  end;
end;
$$;

comment on function public.listing_crea(text, text, integer, text, text, integer, text, text, text, text[]) is
  'Crea vino (se manca), unità fisica e annuncio in stato bozza, in una sola '
  'transazione. Venditore e proprietario sono sempre auth.uid(), mai un '
  'parametro. Non pubblica: la pubblicazione è listing_pubblica().';

revoke execute on function public.listing_crea(text, text, integer, text, text, integer, text, text, text, text[]) from public;
grant execute on function public.listing_crea(text, text, integer, text, text, integer, text, text, text, text[]) to authenticated;

-- ---------------------------------------------------------------------------
-- listing_pubblica — bozza | modifiche_richieste → attivo
-- ---------------------------------------------------------------------------
-- Qui vive la traduzione del vincolo di unicità in un messaggio leggibile.
-- L'indice parziale listings_una_sola_attiva_per_bottiglia scatta soltanto
-- quando una riga entra in ('attivo', 'riservato'), quindi non su una bozza:
-- l'unico punto in cui un utente può incontrarlo è esattamente questo, ed è
-- qui che va intercettato. Senza il blocco EXCEPTION, PostgREST restituirebbe
-- il 23505 grezzo di PostgreSQL, con dentro il nome dell'indice.

create or replace function public.listing_pubblica(p_listing_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_seller uuid;
  v_stato  public.listing_stato;
begin
  if v_uid is null then
    raise exception 'Devi accedere per pubblicare un annuncio.' using errcode = '42501';
  end if;

  select l.seller_id, l.stato into v_seller, v_stato
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

  begin
    update public.listings
    set stato = 'attivo',
        published_at = now(),
        -- Sessanta giorni: è la stessa durata usata dai dati di prova della
        -- 6a. In frontend/ non esiste una scadenza degli annunci, quindi non
        -- c'è un valore da rispettare per parità: questa è una scelta
        -- dichiarata, non una regola ereditata.
        expires_at = now() + interval '60 days',
        stato_motivo = null,
        stato_aggiornato_da = v_uid,
        stato_aggiornato_at = now()
    where id = p_listing_id;
  exception
    when unique_violation then
      raise exception
        'Questa bottiglia ha già un annuncio attivo. Sospendi quello attivo prima di pubblicare questo.'
        using errcode = 'P0001';
  end;
end;
$$;

comment on function public.listing_pubblica(uuid) is
  'Porta un annuncio del venditore da bozza (o modifiche_richieste) ad attivo. '
  'Traduce la violazione dell''indice una-sola-attiva-per-bottiglia in un '
  'messaggio leggibile invece di lasciar passare il 23505.';

revoke execute on function public.listing_pubblica(uuid) from public;
grant execute on function public.listing_pubblica(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- listing_sospendi — attivo → sospeso
-- ---------------------------------------------------------------------------
-- Sospensione da parte del venditore: ritira l'annuncio dalla vista pubblica e
-- libera la bottiglia, che torna a poter avere un annuncio attivo.
--
-- Solo da 'attivo', non da 'riservato': riservato significa che un acquisto è
-- in corso (Fase 7), e sospendere sotto i piedi di chi sta comprando è una
-- decisione di dominio che quella fase deve prendere, non questa.
-- La sospensione decisa da un moderatore è un'altra cosa ancora ed è Fase 9:
-- passerà da una funzione separata che verifica has_role(), non da questa.

create or replace function public.listing_sospendi(
  p_listing_id uuid,
  p_motivo text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_seller uuid;
  v_stato  public.listing_stato;
begin
  if v_uid is null then
    raise exception 'Devi accedere per sospendere un annuncio.' using errcode = '42501';
  end if;

  select l.seller_id, l.stato into v_seller, v_stato
  from public.listings l
  where l.id = p_listing_id;

  if v_seller is null then
    raise exception 'Annuncio non trovato.' using errcode = 'P0001';
  end if;
  if v_seller is distinct from v_uid then
    raise exception 'Non puoi sospendere un annuncio che non è tuo.' using errcode = '42501';
  end if;
  if v_stato <> 'attivo' then
    raise exception 'Si può sospendere solo un annuncio attivo.' using errcode = 'P0001';
  end if;

  update public.listings
  set stato = 'sospeso',
      stato_motivo = nullif(trim(coalesce(p_motivo, '')), ''),
      stato_aggiornato_da = v_uid,
      stato_aggiornato_at = now()
  where id = p_listing_id;
end;
$$;

comment on function public.listing_sospendi(uuid, text) is
  'Sospensione decisa dal venditore sul proprio annuncio attivo. La '
  'sospensione di moderazione è Fase 9 e avrà una funzione separata con '
  'controllo has_role().';

revoke execute on function public.listing_sospendi(uuid, text) from public;
grant execute on function public.listing_sospendi(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- listing_scadi — attivo → scaduto
-- ---------------------------------------------------------------------------
-- Materializza una scadenza già avvenuta: rifiuta di agire se expires_at è nel
-- futuro. Senza quel controllo la funzione sarebbe un "ritira l'annuncio"
-- travestito da scadenza, e lo stato `scaduto` smetterebbe di significare
-- qualcosa di verificabile.
--
-- Non c'è nessuna spazzata automatica su tutti i venditori: richiederebbe uno
-- scheduler (pg_cron o Edge Function) che è lavoro di esercizio, non di questa
-- fase. Finché non esiste, un annuncio oltre la scadenza resta 'attivo' finché
-- qualcuno non chiama questa funzione — vero e da sapere.

create or replace function public.listing_scadi(p_listing_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_seller  uuid;
  v_stato   public.listing_stato;
  v_scadenza timestamptz;
begin
  if v_uid is null then
    raise exception 'Devi accedere per far scadere un annuncio.' using errcode = '42501';
  end if;

  select l.seller_id, l.stato, l.expires_at into v_seller, v_stato, v_scadenza
  from public.listings l
  where l.id = p_listing_id;

  if v_seller is null then
    raise exception 'Annuncio non trovato.' using errcode = 'P0001';
  end if;
  if v_seller is distinct from v_uid then
    raise exception 'Non puoi far scadere un annuncio che non è tuo.' using errcode = '42501';
  end if;
  if v_stato <> 'attivo' then
    raise exception 'Si può far scadere solo un annuncio attivo.' using errcode = 'P0001';
  end if;
  if v_scadenza is null or v_scadenza > now() then
    raise exception 'Questo annuncio non è ancora scaduto.' using errcode = 'P0001';
  end if;

  update public.listings
  set stato = 'scaduto',
      stato_aggiornato_da = v_uid,
      stato_aggiornato_at = now()
  where id = p_listing_id;
end;
$$;

comment on function public.listing_scadi(uuid) is
  'Porta ad esaurito un annuncio la cui expires_at è già passata. Rifiuta se '
  'la scadenza è nel futuro: non è una via di ritiro anticipato.';

revoke execute on function public.listing_scadi(uuid) from public;
grant execute on function public.listing_scadi(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Storage — bucket delle fotografie caricate dai venditori
-- ---------------------------------------------------------------------------
-- Gli asset statici di frontend-next/public/images/ restano dove sono: sono
-- illustrazioni dell'interfaccia, non contenuto caricato da utenti, e non
-- hanno niente da fare in un bucket.
--
-- BUCKET PUBBLICO IN LETTURA. Le fotografie di un annuncio attivo sono
-- visibili a chiunque, anche a un visitatore anonimo: è il prodotto. Renderlo
-- privato costringerebbe a firmare un URL per ogni immagine a ogni render,
-- con URL che scadono e non si possono mettere in cache. La conseguenza da
-- accettare, e che dichiaro: anche le foto di una bozza sono leggibili da chi
-- ne indovina l'URL, che contiene due UUID. Non è un'esposizione della bozza
-- (l'annuncio resta invisibile), è l'esposizione del file.
--
-- LIMITI LATO SERVER. file_size_limit e allowed_mime_types sono applicati dal
-- servizio Storage, non dal browser: un upload che sfora viene rifiutato anche
-- se chi lo invia salta del tutto l'interfaccia.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'annunci',
  'annunci',
  true,
  5242880,                                                   -- 5 MB per file
  array['image/jpeg', 'image/png', 'image/webp', 'image/avif']
)
on conflict (id) do update
set public             = excluded.public,
    file_size_limit    = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Convenzione di percorso: <uid>/<uuid>.<estensione>. La prima cartella è
-- l'identificativo del proprietario, ed è ciò su cui lavorano le policy: si
-- scrive solo dentro casa propria. Il percorso non lo sceglie il browser, lo
-- costruisce il server quando firma l'upload — ma la policy non si fida
-- nemmeno di questo e ricontrolla.

drop policy if exists "annunci_select_pubblica" on storage.objects;
drop policy if exists "annunci_insert_propria_cartella" on storage.objects;
drop policy if exists "annunci_update_propria_cartella" on storage.objects;
drop policy if exists "annunci_delete_propria_cartella" on storage.objects;

create policy "annunci_select_pubblica"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'annunci');

create policy "annunci_insert_propria_cartella"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'annunci'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "annunci_update_propria_cartella"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'annunci'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'annunci'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "annunci_delete_propria_cartella"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'annunci'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );
