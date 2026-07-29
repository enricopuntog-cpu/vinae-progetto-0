-- ===========================================================================
-- Fase 6c-2 — "Metti in vendita questa bottiglia"
--
-- Dalla Cantina la vendita parte da una bottiglia che esiste già, non da testo
-- digitato. `listing_crea` invece conia sempre una `bottle_unit` nuova: il
-- commento scritto in 6b lo diceva esplicitamente ("quando la Fase 6c porterà
-- la Cantina, 'metti in vendita questa bottiglia' diventerà un percorso
-- diverso che passa un bottle_unit_id già noto"). Questo è quel momento.
--
-- PERCHÉ UN PARAMETRO E NON UNA FUNZIONE NUOVA. Le due vie condividono tutto
-- ciò che conta: validazione di prezzo, condizione e fotografie, generazione
-- dello slug, inserimento dell'annuncio in bozza, gestione della corsa sullo
-- slug. Una `listing_crea_da_bottiglia` separata duplicherebbe quella metà e
-- imporrebbe di tenerla allineata a mano. Cambia solo da dove arriva l'unità
-- fisica, ed è esattamente ciò che un parametro esprime.
--
-- PERCHÉ DROP E NON CREATE OR REPLACE. Aggiungere un parametro cambia la firma
-- della funzione, e `create or replace` non sostituirebbe la vecchia: ne
-- creerebbe una seconda in sovraccarico. PostgREST risolve le RPC per nome dei
-- parametri e con due firme compatibili la scelta diventa ambigua, quindi la
-- vecchia va rimossa prima. Privilegi e commento se ne vanno con lei e si
-- riassegnano più sotto.
--
-- COSA NON CAMBIA. Senza `p_bottle_unit_id` la funzione si comporta come
-- prima, riga per riga: il wizard che descrive una bottiglia da zero continua
-- a coniare vino e unità come in 6b.
-- ===========================================================================

drop function if exists public.listing_crea(
  text, text, integer, text, text, integer, text, text, text, text[]
);

-- I cinque parametri di identificazione prendono un valore predefinito perché
-- nella via "bottiglia esistente" non servono: descrivono il vino, che in quel
-- caso è già deciso e si legge dall'unità. Chiederli comunque significherebbe
-- far riecheggiare al client dati che il server conosce già, e dare
-- l'impressione che passandoli diversi si possa rinominare un vino di
-- catalogo — cosa che la 6b ha già rifiutato per `listing_aggiorna`.
create function public.listing_crea(
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
  v_uid        uuid := auth.uid();
  v_wine       uuid;
  v_bottle     uuid;
  v_base       text;
  v_slug       text;
  v_n          integer;
  v_immagine   text;
  -- Testo da cui nasce lo slug: dai campi digitati nella via da zero, dal vino
  -- dell'unità nella via che parte da una bottiglia.
  v_etichetta  text;
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

  -- -------------------------------------------------------------------------
  -- Validazioni comuni alle due vie.
  -- Gli stessi limiti sono anche nel wizard, ma il wizard non è un confine di
  -- fiducia: questa funzione è raggiungibile con una POST diretta a PostgREST,
  -- senza passare da nessuna interfaccia.
  -- -------------------------------------------------------------------------
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

  if p_bottle_unit_id is null then
    -- -----------------------------------------------------------------------
    -- Via da zero: il wizard descrive una bottiglia che non esiste ancora.
    -- Identica alla 6b.
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

    -- Catalogo: si riusa la riga esistente se produttore + nome + annata
    -- coincidono, altrimenti se ne crea una. `on conflict do nothing` seguito
    -- da una select copre la corsa fra due venditori che catalogano lo stesso
    -- vino nello stesso istante.
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

    -- Unità fisica. Inserimento minimo: proprietario, vino, stato, visibilità.
    insert into public.bottle_units (owner_id, wine_id, stato, visibilita)
    values (v_uid, v_wine, 'chiusa', 'privata')
    returning bottle_units.id into v_bottle;

  else
    -- -----------------------------------------------------------------------
    -- Via dalla Cantina: la bottiglia esiste già e non se ne conia una nuova.
    -- -----------------------------------------------------------------------
    -- La proprietà si verifica qui e non si delega alla policy
    -- `listings_insert_own`: questa funzione è SECURITY DEFINER, quindi la RLS
    -- su bottle_units non la limita. Senza questo controllo basterebbe
    -- indovinare l'id dell'unità di un altro per metterla in vendita.
    select bu.id, bu.wine_id into v_bottle, v_wine
    from public.bottle_units bu
    where bu.id = p_bottle_unit_id
      and bu.owner_id = v_uid
      and bu.deleted_at is null;

    if v_bottle is null then
      raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
    end if;

    select w.produttore || ' ' || w.nome || ' ' || w.annata::text
    into v_etichetta
    from public.wines w
    where w.id = v_wine;

    -- Nessun controllo sugli annunci già esistenti per questa unità: una bozza
    -- in più non fa danno, e il vincolo "una bottiglia, un solo annuncio
    -- attivo" è un indice parziale sugli stati vivi. Chi lo tocca è
    -- listing_pubblica, che lo traduce in una frase leggibile.
  end if;

  -- -------------------------------------------------------------------------
  -- Annuncio in bozza. Da qui in poi le due vie coincidono.
  -- -------------------------------------------------------------------------
  -- Slug dell'annuncio. Parte dalla stessa base del vino, così il primo
  -- annuncio di un vino ha l'URL leggibile che ci si aspetta
  -- (/annuncio/tignanello-2019) e i successivi si numerano.
  v_base := public.slugifica(v_etichetta);
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

comment on function public.listing_crea(
  text, text, integer, text, text, integer, text, text, text, text[], uuid
) is
  'Crea un annuncio in stato bozza. Senza p_bottle_unit_id conia anche vino '
  '(se manca) e unità fisica, come in Fase 6b. Con p_bottle_unit_id riusa '
  'un''unità già in cantina, dopo averne verificato la proprietà. Venditore e '
  'proprietario sono sempre auth.uid(), mai un parametro. Non pubblica: la '
  'pubblicazione è listing_pubblica().';

revoke execute on function public.listing_crea(
  text, text, integer, text, text, integer, text, text, text, text[], uuid
) from public;
grant execute on function public.listing_crea(
  text, text, integer, text, text, integer, text, text, text, text[], uuid
) to authenticated;
