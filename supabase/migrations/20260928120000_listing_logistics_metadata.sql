-- ===========================================================================
-- Confezione originale del prodotto e preferenza di consegna del venditore
-- ===========================================================================
--
-- IL PROBLEMA CHE CHIUDE. Nel dominio della logistica esistono TRE concetti che
-- oggi il database non sa distinguere, e che se collassano l'uno sull'altro
-- producono errori che si vedono soltanto quando un pacco parte:
--
--   A  CONFEZIONE ORIGINALE DEL PRODOTTO
--      Che cosa il venditore vende: la bottiglia nuda, un cofanetto originale,
--      una cassa di legno originale, una confezione multipla originale. E' una
--      proprieta della MERCE. Appartiene all'annuncio, va mostrata a chi
--      compra, e puo cambiare fra una vendita e una ripubblicazione futura.
--      E' cio che questa migrazione introduce.
--
--   B  IMBALLAGGIO DI SPEDIZIONE
--      Il cartone, la protezione, il materiale con cui la merce viaggia. NON
--      appartiene a questa migrazione e non viene toccato qui.
--
--   C  MODALITA DI CONSEGNA DEL VENDITORE ALLA RETE LOGISTICA
--      Se il venditore porta il pacco a un punto di consegna oppure se lo fa
--      ritirare a casa. E' una preferenza dell'atto di consegna, non della
--      merce e non dell'imballaggio. E' l'altra cosa che questa migrazione
--      introduce.
--
-- ---------------------------------------------------------------------------
-- IL CAMPO CHE NON VA RIUSATO
-- ---------------------------------------------------------------------------
--
-- `public.listings.imballaggio_codice` ESISTE GIA dalla 7c
-- (20260804160000_phase_7c_delivery_packaging.sql) e NON e nessuno dei tre
-- concetti qui sopra nel senso in cui li usa questa migrazione: e un codice di
-- listino di `public.packaging_options`, cioe la scelta logistica congelata
-- sull'ordine al checkout, con un prezzo dietro. Non viene rinominato, non
-- viene riletto come confezione originale e non viene toccato da nessuna riga
-- di questo file. La confezione originale nasce con colonne proprie proprio
-- perche un riuso avrebbe legato una proprieta della merce a un listino.
--
-- ---------------------------------------------------------------------------
-- PERCHE SU listings E NON SU wines NE SU bottle_units
-- ---------------------------------------------------------------------------
--
-- `wines` e il catalogo condiviso: l'etichetta e la stessa per tutti i
-- venditori, la confezione con cui UN venditore la vende no. `bottle_units` e
-- la giacenza fisica in cantina, e la confezione originale e una proprieta
-- dell'offerta, non della conservazione. Sta su `listings` per tre ragioni
-- misurate: descrive come quella merce e venduta, deve comparire nell'annuncio,
-- e puo cambiare fra una vendita e una ripubblicazione della stessa bottiglia.
-- `confezione_multipla_originale` resta inoltre compatibile con la futura
-- evoluzione 1 -> N di `listing_bottle_units` senza spostarsi di tabella.
--
-- ---------------------------------------------------------------------------
-- CHE COSA NON C'E', E NON PER DIMENTICANZA
-- ---------------------------------------------------------------------------
--
-- Nessun prezzo, nessun sovrapprezzo, nessun fornitore, nessun punto di
-- consegna reale, nessuna associazione a una rete logistica, nessun corriere,
-- nessun servizio di spedizione, nessuna assicurazione, nessun tracking,
-- nessuna etichetta e nessun QR. Nessuna riga di questo file legge o scrive
-- `packaging_options`, `orders`, pagamenti, commissioni o payout: la parte
-- economica della logistica e un pacchetto di lavoro successivo, e un campo
-- descrittivo introdotto ora non deve anticiparne le decisioni.
--
-- Nessun backfill. Gli annunci esistenti restano con i nuovi campi NULL, e NULL
-- significa esattamente «non dichiarato», mai «nessuna confezione» e mai «punto
-- di consegna». Un annuncio gia ATTIVO prima di questa migrazione resta
-- leggibile nel catalogo pubblico e acquistabile: le guardie nuove stanno sulle
-- transizioni verso `attivo`, non sulla lettura ne sull'acquisto.
--
-- ---------------------------------------------------------------------------
-- LE PORTE VERSO `attivo`, TUTTE
-- ---------------------------------------------------------------------------
--
-- Una guardia di pubblicazione vale quanto la porta piu debole. Nel repository
-- le vie verso `attivo` sono tre famiglie, e questa migrazione le tratta
-- diversamente per ragioni dichiarate:
--
--   1. `public.listing_pubblica` — la pubblicazione del venditore. GUARDATA
--      qui, sezione [5].
--   2. `private.moderazione_annuncio_transizione` con p_stato = 'attivo', cioe
--      `public.moderazione_annuncio_ripristina` della 9b. GUARDATA qui,
--      sezione [6]. Senza questa seconda guardia il contratto era aggirabile:
--      bastava un ripristino di moderazione.
--   3. Il rilascio di una prenotazione: `riservato` -> `attivo` quando un
--      ordine scade, viene annullato o rimborsato (7, 7b, 7c). NON guardata, e
--      deliberato. Non e un ingresso in vendita ma il ritorno allo stato
--      precedente di un annuncio che era GIA attivo, e vincolarlo lascerebbe
--      la merce bloccata in `riservato` quando un pagamento non va a termine:
--      esattamente il congelamento che la costituzione vieta ai percorsi di
--      pagamento. Quei percorsi non vengono toccati da nessuna riga di questo
--      file.
--
-- Gli annunci gia `attivo` al momento dell'applicazione restano tali con i
-- campi NULL. Ma ogni transizione FUTURA verso `attivo` pretende entrambe le
-- dichiarazioni, legacy compreso: se un annuncio sospeso, rifiutato o in
-- revisione vuole tornare in vendita, prima riceve le dichiarazioni.
--
-- ---------------------------------------------------------------------------
-- NESSUN VICOLO CIECO: LA MATRICE
-- ---------------------------------------------------------------------------
--
-- Un cancello che chiede un dato deve lasciare aperta una porta per scriverlo,
-- altrimenti non e un cancello ma un muro. `moderazione_annuncio_ripristina`
-- riporta ad `attivo` da quattro stati; per ognuno deve esistere una via per
-- dichiarare. Da qui l'elenco degli stati ammessi da
-- `public.listing_logistica_dichiara`, sezione [4]:
--
--   bozza                -> dichiara SI
--   modifiche_richieste  -> dichiara SI
--   attivo               -> dichiara SI
--   sospeso              -> dichiara SI   (aggiunto qui)
--   rifiutato            -> dichiara SI   (aggiunto qui)
--   in_revisione         -> NO   la moderazione sta leggendo la riga; l'uscita
--                                e `modifiche_richieste`, che e dichiarabile
--   riservato            -> NO   un acquisto e in corso su questi stessi dati
--   venduto              -> NO   transazione conclusa
--   scaduto              -> NO   terminale: nessuna porta lo riporta ad
--                                `attivo`, quindi nessun cancello lo blocca
--
-- Incrocio finale: dei quattro stati da cui la moderazione puo tentare il
-- ritorno in vendita, tre dichiarano direttamente e `in_revisione` dichiara
-- dopo `modifiche_richieste`. Non resta nessuno stato in cui il cancello
-- pretenda un dato che il venditore non possa scrivere. `sospeso` e
-- `rifiutato` sono ammessi SOLO a questa funzione e SOLO per i tre campi
-- logistici: `listings_update_own`, il GRANT UPDATE del client e gli stati
-- modificabili del frontend non cambiano di una riga.

begin;

-- ---------------------------------------------------------------------------
-- [1] Le colonne
-- ---------------------------------------------------------------------------

alter table public.listings
  add column confezione_originale_tipo text,
  add column confezione_originale_foto text[] not null default '{}',
  add column handoff_venditore text;

-- Elenco chiuso di valori, come vincolo di riga e non come enum: un enum nuovo
-- costringerebbe ogni valore futuro a una migrazione di tipo, e questo dominio
-- e in costruzione. Il CHECK vincola comunque anche `service_role` e qualunque
-- scrittore privilegiato, che e cio che serve.
alter table public.listings
  add constraint listings_confezione_originale_tipo_valido
    check (
      confezione_originale_tipo is null
      or confezione_originale_tipo in (
        'nessuna_confezione_originale',
        'cofanetto_originale',
        'cassa_legno_originale',
        'confezione_multipla_originale'
      )
    );

alter table public.listings
  add constraint listings_handoff_venditore_valido
    check (
      handoff_venditore is null
      or handoff_venditore in ('dropoff_pudo', 'ritiro_domicilio')
    );

comment on column public.listings.confezione_originale_tipo is
  'CONFEZIONE ORIGINALE DEL PRODOTTO: che cosa il venditore vende, non come lo '
  'spedisce. Quattro valori: nessuna_confezione_originale, cofanetto_originale, '
  'cassa_legno_originale, confezione_multipla_originale. '
  '`nessuna_confezione_originale` significa SOLTANTO che il prodotto non e '
  'venduto con un cofanetto, una cassa di legno o una confezione originale: NON '
  'significa che la spedizione non richieda imballaggio, che e un concetto '
  'diverso e vive altrove. Gli altri tre valori descrivono una parte della '
  'MERCE venduta e non attestano in nessun modo l''idoneita al trasporto: un '
  'cofanetto originale non e un imballaggio di spedizione. Da non confondere con '
  '`imballaggio_codice`, che e la modalita logistica di listino della 7c. NULL '
  'significa «non dichiarato» e resta il valore degli annunci anteriori alla '
  'migrazione: non e mai stato interpretato come «nessuna confezione». Ha una '
  'regola di dominio dietro, quindi NON entra nel GRANT UPDATE del client: si '
  'scrive solo da listing_logistica_dichiara.';

comment on column public.listings.confezione_originale_foto is
  'Da zero a quattro fotografie della confezione originale, come percorsi nel '
  'bucket pubblico `annunci` sotto la cartella del venditore. Nessun bucket '
  'nuovo: queste fotografie diventano parte pubblica dell''annuncio, esattamente '
  'come `immagini`. Sono opzionali: nessun valore di '
  '`confezione_originale_tipo` le rende obbligatorie. Un array non vuoto '
  'pretende pero un tipo che ammetta una confezione, perche una fotografia '
  'legata a `nessuna_confezione_originale` o a un tipo non dichiarato sarebbe '
  'orfana di significato. Si scrive solo da listing_logistica_dichiara, che '
  'verifica proprietario, forma del percorso ed esistenza dell''oggetto.';

comment on column public.listings.handoff_venditore is
  'MODALITA DI CONSEGNA DEL VENDITORE ALLA RETE LOGISTICA, distinta dalla '
  'confezione originale del prodotto e dall''imballaggio di spedizione. '
  '`dropoff_pudo`: il venditore porta il pacco a un punto di consegna. '
  '`ritiro_domicilio`: il pacco viene ritirato al suo indirizzo. `dropoff_pudo` '
  'e lo standard di prodotto ma NON viene mai scritto d''ufficio: la colonna '
  'resta NULL finche il venditore non sceglie, perche un default scritto in '
  'tabella sarebbe una scelta dell''utente simulata dal database. Sara la '
  'futura interfaccia a proporlo come opzione consigliata. Nessun fornitore e '
  'nessun punto di consegna reale e associato qui, e nessun prezzo. Non e '
  'esposta da public_listings.';

-- ---------------------------------------------------------------------------
-- [2] Coerenza dell'array
-- ---------------------------------------------------------------------------
--
-- Vincoli di riga per cio che si esprime senza sottoquery, cosi da valere anche
-- per `service_role` e per qualunque scrittura diretta: quante fotografie e
-- nessun elemento nullo.
--
-- La forma del percorso, la cartella del venditore e l'esistenza dell'oggetto
-- restano nella porta di scrittura. Non per dimenticanza: un predicato per
-- elemento richiede `unnest`, cioe una sottoquery, che un CHECK non ammette, e
-- l'esistenza in `storage.objects` non e nemmeno immutabile. Nascondere il
-- predicato in una funzione richiamata dal CHECK aggiungerebbe una dipendenza
-- funzione -> vincolo che complica dump e ripristino, e questo repository non lo
-- fa da nessuna parte. E' esattamente il trattamento che `listings.immagini`
-- riceve dalla 6b: nessun CHECK di percorso in tabella, validazione completa
-- dentro `listing_crea`. Il rischio residuo e circoscritto perche le colonne non
-- sono nel GRANT UPDATE del client: l'unica strada dal browser e la RPC.
alter table public.listings
  add constraint listings_confezione_originale_foto_limite
    check (
      cardinality(confezione_originale_foto) <= 4
      and array_position(confezione_originale_foto, null::text) is null
    );

-- Una fotografia ha senso solo se esiste una confezione da fotografare. Con
-- tipo NULL («non dichiarato») o `nessuna_confezione_originale` l'array deve
-- essere vuoto: e la ragione per cui gli annunci anteriori alla migrazione
-- soddisfano il vincolo senza toccarli, perche nascono con tipo NULL e array
-- vuoto.
alter table public.listings
  add constraint listings_confezione_originale_foto_senza_confezione
    check (
      cardinality(confezione_originale_foto) = 0
      or confezione_originale_tipo in (
        'cofanetto_originale',
        'cassa_legno_originale',
        'confezione_multipla_originale'
      )
    );

-- ---------------------------------------------------------------------------
-- [3] Lettura: il proprietario rilegge, il pubblico no
-- ---------------------------------------------------------------------------
--
-- Su `public.listings` `anon` non ha alcun privilegio e `authenticated` ha un
-- elenco CHIUSO di colonne in SELECT (20260729230000, sezione sui privilegi):
-- una colonna aggiunta oggi resta invisibile finche non viene nominata. Le tre
-- nuove colonne entrano nel solo SELECT di `authenticated`, che la policy
-- `listings_select_own` limita comunque alle proprie righe — e' cosi che la
-- futura interfaccia di /vendi rilegge la dichiarazione.
--
-- NESSUN privilegio ad `anon` sulla tabella: il catalogo pubblico legge dalla
-- vista `public_listings`, e nessun UPDATE viene concesso su queste colonne.

grant select (
  confezione_originale_tipo,
  confezione_originale_foto,
  handoff_venditore
) on public.listings to authenticated;

-- ---------------------------------------------------------------------------
-- [4] La porta di scrittura — solo il proprietario, solo la sua roba
-- ---------------------------------------------------------------------------
--
-- Stessa forma di `listing_imballaggio_dichiara` della 7c: SECURITY DEFINER,
-- `search_path = ''`, identita dal token e non dai parametri, nessun id di
-- venditore fra gli argomenti, rate limit prima di ogni lavoro, revoca a
-- PUBLIC e ad `anon`.
--
-- La chiamata attraversa comunque il trigger `listings_scrittura_social_guard`
-- (BEFORE INSERT OR UPDATE dalla 20260819090000), quindi un venditore sospeso
-- al primo livello non dichiara: la guardia 7.6b non si perde per il fatto che
-- la scrittura passi da una funzione privilegiata.
--
-- I tre argomenti si scrivono INSIEME e possono essere posti a NULL: e una
-- dichiarazione, non tre micro-aggiornamenti, e ritirarla resta possibile
-- finche l'annuncio e modificabile.

create or replace function public.listing_logistica_dichiara(
  p_listing_id               uuid,
  p_confezione_originale_tipo text,
  p_confezione_originale_foto text[],
  p_handoff_venditore        text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_listing public.listings%rowtype;
  v_foto    text[] := coalesce(p_confezione_originale_foto, '{}'::text[]);
  v_percorso text;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  perform private.rate_limit_consume('listing:logistica', 'user:' || v_uid::text, 30, 60);

  -- I valori si validano prima di guardare la riga: un chiamante che sbaglia un
  -- valore non impara nulla sull'esistenza dell'annuncio.
  if p_confezione_originale_tipo is not null
     and p_confezione_originale_tipo not in (
       'nessuna_confezione_originale',
       'cofanetto_originale',
       'cassa_legno_originale',
       'confezione_multipla_originale'
     ) then
    raise exception 'Tipo di confezione originale non valido.' using errcode = '22023';
  end if;

  if p_handoff_venditore is not null
     and p_handoff_venditore not in ('dropoff_pudo', 'ritiro_domicilio') then
    raise exception 'Modalità di consegna alla rete logistica non valida.'
      using errcode = '22023';
  end if;

  if cardinality(v_foto) > 4 then
    raise exception 'Massimo 4 fotografie della confezione originale.'
      using errcode = '22023';
  end if;
  if array_position(v_foto, null::text) is not null then
    raise exception 'Percorso della fotografia non valido.' using errcode = '22023';
  end if;

  -- Una fotografia senza una confezione da fotografare sarebbe orfana: vale sia
  -- per `nessuna_confezione_originale` sia per il tipo non dichiarato.
  if cardinality(v_foto) > 0
     and coalesce(p_confezione_originale_tipo, '') not in (
       'cofanetto_originale',
       'cassa_legno_originale',
       'confezione_multipla_originale'
     ) then
    raise exception
      'Le fotografie della confezione richiedono un tipo di confezione originale.'
      using errcode = '22023';
  end if;

  -- Proprieta e stato: annuncio inesistente e annuncio di un altro rispondono
  -- la stessa cosa, come in tutte le porte del dominio annunci.
  select * into v_listing
  from public.listings
  where id = p_listing_id
  for update;

  if not found or v_listing.seller_id <> v_uid then
    raise exception 'Annuncio non trovato.' using errcode = '42501';
  end if;

  -- Questo elenco e deliberatamente PIU AMPIO di `listings_update_own`
  -- (20260819090000): oltre a `bozza`, `modifiche_richieste` e `attivo`
  -- accetta `sospeso` e `rifiutato`. Non rende modificabile l'annuncio in quei
  -- due stati — la policy, il GRANT UPDATE del client e gli stati modificabili
  -- del frontend restano quelli di prima, e questa funzione scrive soltanto i
  -- tre campi logistici — ma evita un vicolo cieco aperto dal cancello della
  -- sezione [6]: `moderazione_annuncio_ripristina` puo riportare ad `attivo`
  -- anche da `sospeso` e da `rifiutato`, e da `rifiutato` non esiste NESSUNA
  -- altra transizione verso uno stato dichiarabile. Senza queste due label un
  -- annuncio rifiutato prima della migrazione non potrebbe piu tornare in
  -- vendita in alcun modo. Ne `sospeso` ne `rifiutato` hanno un acquisto in
  -- corso: completarli logisticamente non tocca denaro.
  --
  -- Restano fuori, per ragioni distinte: `in_revisione` (la moderazione sta
  -- leggendo la riga; l'uscita esiste ed e `modifiche_richieste`), `riservato`
  -- (un acquisto e in corso e si sta basando proprio su questi dati),
  -- `venduto` (transazione conclusa), `scaduto` (terminale, il lifecycle
  -- corrente non lo ripristina, quindi nessun cancello lo puo bloccare).
  if v_listing.stato not in ('bozza', 'modifiche_richieste', 'attivo',
                             'sospeso', 'rifiutato') then
    raise exception 'Questo annuncio non è più modificabile.' using errcode = 'P0001';
  end if;

  -- Ogni percorso deve stare nella cartella del chiamante, avere la forma che
  -- il bucket `annunci` ammette, e puntare a un oggetto che esiste davvero.
  -- Senza il controllo di esistenza l'annuncio potrebbe dichiarare un percorso
  -- mai caricato; senza quello sulla cartella potrebbe dichiarare il file di un
  -- altro utente. Nessun URL: solo percorsi interni al bucket.
  foreach v_percorso in array v_foto loop
    if v_percorso !~ ('^' || v_uid::text || '/[0-9a-f-]{36}\.(jpg|jpeg|png|webp|avif)$') then
      raise exception 'Fotografia non valida: %', v_percorso using errcode = '22023';
    end if;
    if not exists (
      select 1
      from storage.objects o
      where o.bucket_id = 'annunci'
        and o.name = v_percorso
    ) then
      raise exception 'Fotografia non trovata: caricala prima di dichiararla.'
        using errcode = 'P0001';
    end if;
  end loop;

  update public.listings
  set confezione_originale_tipo = p_confezione_originale_tipo,
      confezione_originale_foto = v_foto,
      handoff_venditore         = p_handoff_venditore
  where id = v_listing.id;
end;
$$;

comment on function public.listing_logistica_dichiara(uuid, text, text[], text) is
  'Unica porta di scrittura di confezione originale del prodotto, fotografie '
  'della confezione e modalita di consegna alla rete logistica. Identita dal '
  'token, nessun id di venditore fra i parametri, solo annunci propri e solo '
  'negli stati da cui l''annuncio puo ancora tornare in vendita: bozza, '
  'modifiche_richieste, attivo, sospeso, rifiutato. Rifiuta in_revisione, '
  'riservato, venduto e scaduto. Scrive solo i tre campi logistici: non '
  'allarga in alcun modo cio che il venditore puo modificare in sospeso o '
  'rifiutato. Le fotografie devono stare nella cartella del chiamante nel bucket '
  '`annunci` ed esistere. Non tocca prezzi, commissioni, ordini, payout, '
  '`imballaggio_codice` ne `packaging_options`.';

revoke execute on function public.listing_logistica_dichiara(uuid, text, text[], text)
  from public, anon;
grant execute on function public.listing_logistica_dichiara(uuid, text, text[], text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- [5] La guardia di pubblicazione
-- ---------------------------------------------------------------------------
--
-- Definizione ripresa dalla piu recente EFFETTIVA (20260729230000, sezione [9]),
-- con `search_path = ''` come lo ha portato la 20260729234500 e con la sola
-- aggiunta della guardia: tutto il resto — cancello eta, ricontrollo con lock
-- della bottiglia, traduzione della violazione di unicita — e invariato.
--
-- La dichiarazione e obbligatoria PRIMA di diventare `attivo`, non dopo:
-- pubblicare significa mettere una merce in vendita, e chi compra deve poter
-- leggere con che confezione la riceve. `nessuna_confezione_originale` e una
-- scelta esplicita valida e sufficiente. La fotografia NON e obbligatoria.
--
-- Questa e la prima delle due porte guardate. La seconda, il ripristino di
-- moderazione, e nella sezione [6]: le due guardie insieme sono l'invariante,
-- una sola delle due sarebbe un contratto aggirabile.
--
-- I due messaggi restano distinti e non collassano in uno: il venditore che
-- pubblica deve sapere QUALE delle due dichiarazioni manca, e sono due schermate
-- diverse della futura interfaccia. Per questo qui non si usa un predicato
-- booleano condiviso con la sezione [6]: un helper che risponde «manca qualcosa»
-- servirebbe un solo chiamante su due e non ridurrebbe nulla.

create or replace function public.listing_pubblica(p_listing_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := auth.uid();
  v_seller     uuid;
  v_stato      public.listing_stato;
  v_bottle     uuid;
  v_bu_stato   public.bottle_unit_stato;
  v_deleted    timestamptz;
  v_ceduta     timestamptz;
  v_confezione text;
  v_handoff    text;
begin
  if v_uid is null then
    raise exception 'Devi accedere per pubblicare un annuncio.' using errcode = '42501';
  end if;

  select l.seller_id, l.stato, l.bottle_unit_id,
         l.confezione_originale_tipo, l.handoff_venditore
  into v_seller, v_stato, v_bottle, v_confezione, v_handoff
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

  -- Cancello logistico: due dichiarazioni distinte, entrambe obbligatorie.
  -- `nessuna_confezione_originale` le soddisfa; NULL no, perche NULL vuol dire
  -- che nessuno ha scelto.
  if v_confezione is null then
    raise exception
      'Prima di pubblicare dichiara la confezione originale del prodotto.'
      using errcode = 'P0001';
  end if;
  if v_handoff is null then
    raise exception
      'Prima di pubblicare dichiara come consegnerai il pacco alla rete logistica.'
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
  'dopo cancello età, dichiarazione logistica obbligatoria (confezione originale '
  'del prodotto e modalità di consegna alla rete logistica, entrambe non nulle; '
  'la fotografia non è richiesta) e ricontrollo con lock della bottiglia, che fra '
  'la bozza e la pubblicazione può essere stata aperta o tolta dalla cantina. '
  'Traduce la violazione dell''indice non-terminale in un messaggio leggibile. '
  'Gli annunci già attivi prima della guardia non sono toccati.';

revoke execute on function public.listing_pubblica(uuid) from public, anon;
grant execute on function public.listing_pubblica(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- [6] La seconda porta verso `attivo`: il ripristino di moderazione
-- ---------------------------------------------------------------------------
--
-- Definizione ripresa dalla piu recente EFFETTIVA: la 9b
-- (20260810180000_phase_9b_moderation_actions.sql, riga 642). Verificato prima
-- di riscrivere: nessuna migrazione successiva la ridefinisce e nessuna
-- `alter function` la tocca — la 12c (20260817121000) la CHIAMA e ne modella una
-- funzione speculare per i contenuti Club, ma non ne cambia il corpo. Firma,
-- `security definer`, `search_path = ''`, motivazione obbligatoria, rifiuto di
-- `riservato` e `venduto`, controllo degli stati ammessi passati dal chiamante,
-- traduzione dell'indice non-terminale, `published_at` con `coalesce`, riga di
-- audit: tutto invariato, riga per riga. I privilegi non sono ritoccati perche
-- `create or replace function` conserva l'ACL, e la 9b l'ha revocata a
-- `public, anon, authenticated` (riga 1440).
--
-- L'UNICA aggiunta e il cancello logistico, e SOLO sul ramo p_stato = 'attivo'.
-- Le altre transizioni della moderazione — `in_revisione`,
-- `modifiche_richieste`, `sospeso`, `rifiutato` — non sono toccate: servono
-- proprio a chiedere al venditore i dati che mancano, e vincolarle avrebbe
-- chiuso la via d'uscita invece di aprirla.
--
-- Il controllo sta sulla riga gia lockata dal `select ... for update` di sopra,
-- non su una rilettura: fra il lock e l'UPDATE nessun altro puo aver azzerato le
-- dichiarazioni. Il messaggio e neutro e parla allo staff, non al venditore. La
-- fotografia non e richiesta e `nessuna_confezione_originale` resta valore
-- valido: il cancello pretende una scelta, non una scelta particolare.

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
  v_confezione text;
  v_handoff text;
begin
  if length(btrim(coalesce(p_motivazione, ''))) = 0 then
    raise exception 'Motivazione obbligatoria.' using errcode = '22023';
  end if;

  select l.stato, l.slug, l.bottle_unit_id,
         l.confezione_originale_tipo, l.handoff_venditore
    into v_stato, v_slug, v_bottle, v_confezione, v_handoff
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

  -- Cancello logistico (20260928120000). Vale su OGNI ingresso futuro in
  -- vendita, legacy compreso: un annuncio anteriore alla migrazione resta
  -- attivo con i campi NULL, ma per TORNARE attivo li dichiara.
  if p_stato = 'attivo'
     and (v_confezione is null or v_handoff is null) then
    raise exception
      'Completa le informazioni logistiche prima di rendere nuovamente attivo l''annuncio.'
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

comment on function private.moderazione_annuncio_transizione(
  uuid, uuid, public.listing_stato, public.mod_action, text,
  public.listing_stato[], uuid
) is
  'Motore condiviso delle transizioni di moderazione su un annuncio: verifica '
  'lo stato di partenza, rifiuta riservato e venduto, scrive la traccia sulle '
  'tre colonne di listings e registra la riga di audit. Le funzioni pubbliche '
  'sono distinte per azione, non parametrizzate su un''azione. Dalla '
  '20260928120000 il solo ramo p_stato = ''attivo'' pretende anche '
  'confezione_originale_tipo e handoff_venditore non nulli: nessuna transizione '
  'futura verso la vendita aggira il contratto logistico, mentre gli annunci '
  'gia attivi prima di quella migrazione non vengono toccati.';

-- ---------------------------------------------------------------------------
-- [7] La proiezione pubblica — due colonne in coda
-- ---------------------------------------------------------------------------
--
-- Definizione ripresa dalla piu recente EFFETTIVA (20260825120000, sezione [6])
-- con DUE colonne in coda. `create or replace view` esige che le colonne
-- preesistenti restino identiche e nello stesso ordine: nulla e stato
-- rinominato, mosso o tolto, `seller_verificato` resta l'ultima delle vecchie,
-- i filtri sono invariati e le opzioni `security_invoker = off` /
-- `security_barrier = true` restano quelle.
--
-- `handoff_venditore` NON compare, ed e deliberato: e una preferenza operativa
-- del venditore, non un dato che il catalogo deve mostrare a chiunque. Un
-- eventuale checkout che debba conoscerla la leggera da una porta server
-- dedicata, non allargando la superficie pubblica.

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
  ) as seller_verificato,
  l.confezione_originale_tipo,
  l.confezione_originale_foto
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
  'livello). Un chiamante anonimo non e toccato. Porta `seller_verificato`: '
  'booleano derivato, vero solo con certificazione identita E venditore entrambe '
  'valide adesso. Da questa migrazione porta anche la confezione originale del '
  'prodotto e le sue fotografie: NULL e array vuoto per gli annunci anteriori, '
  'che restano visibili e acquistabili. `handoff_venditore` resta fuori: e una '
  'preferenza operativa del venditore, non un dato di catalogo.';

revoke all on public.public_listings from anon, authenticated;
grant select on public.public_listings to anon, authenticated;

commit;
