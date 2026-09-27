


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "private";


ALTER SCHEMA "private" OWNER TO "postgres";


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE TYPE "public"."bottle_acquisition_fonte" AS ENUM (
    'sconosciuta',
    'manuale'
);


ALTER TYPE "public"."bottle_acquisition_fonte" OWNER TO "postgres";


COMMENT ON TYPE "public"."bottle_acquisition_fonte" IS 'Come Vinea è venuta a sapere del costo di acquisizione di una bottiglia. `sconosciuta`: nessuno l''ha mai dichiarato, e il costo resta NULL. `manuale`: il proprietario l''ha dichiarato aggiungendola in Cantina. L''acquisto su Vinea NON è un''etichetta di questo enum: si deriva dal legame orders.buyer_bottle_unit_id, che è già la sorgente autorevole.';



CREATE TYPE "public"."bottle_unit_stato" AS ENUM (
    'chiusa',
    'aperta',
    'consumata'
);


ALTER TYPE "public"."bottle_unit_stato" OWNER TO "postgres";


COMMENT ON TYPE "public"."bottle_unit_stato" IS 'Stato fisico dell''unità. frontend/docs/DOMAIN_MODEL.md elenca (chiusa, aperta, programmata), ma "programmata" non è uno stato: è la presenza di una data di apertura pianificata (CellarBottle.plannedOpenDate). Qui resta il solo stato fisico; la pianificazione arriverà con la Cantina.';



CREATE TYPE "public"."bottle_unit_visibilita" AS ENUM (
    'privata',
    'cantina_pubblica'
);


ALTER TYPE "public"."bottle_unit_visibilita" OWNER TO "postgres";


COMMENT ON TYPE "public"."bottle_unit_visibilita" IS 'RESIDUO INERTE dalla Fase 9a: vedi il commento su bottle_units.visibilita. Nessun valore di questo enum produce piu una lettura da parte di terzi.';



CREATE TYPE "public"."certificazione_fonte" AS ENUM (
    'verifica_interna_vinea'
);


ALTER TYPE "public"."certificazione_fonte" OWNER TO "postgres";


COMMENT ON TYPE "public"."certificazione_fonte" IS 'Specie di fonte che ha prodotto la certificazione. Una sola label oggi. Esiste per poter distinguere domani una fonte esterna senza rifare il modello: nessun fornitore e stato scelto e nessun nome di fornitore compare in questa migrazione.';



CREATE TYPE "public"."certificazione_tipo" AS ENUM (
    'identita',
    'venditore'
);


ALTER TYPE "public"."certificazione_tipo" OWNER TO "postgres";


COMMENT ON TYPE "public"."certificazione_tipo" IS 'Specie di certificazione forte di profilo. `identita`: una fonte fidata ha accertato chi e la persona. `venditore`: la persona e abilitata a vendere come venditore verificato, e richiede `identita`. La conferma email NON e qui: appartiene ad auth.users.email_confirmed_at.';



CREATE TYPE "public"."club_ruolo" AS ENUM (
    'membro'
);


ALTER TYPE "public"."club_ruolo" OWNER TO "postgres";


COMMENT ON TYPE "public"."club_ruolo" IS 'Ruolo dentro un club. Un solo valore in 12a: la decisione 7.1 della Fase 9 rinvia lo scope club della moderazione, e un secondo valore lo deciderebbe implicitamente. Ampliarlo e una migrazione nuova, per costruzione.';



CREATE TYPE "public"."delivery_mode" AS ENUM (
    'spedizione',
    'consegna_mano'
);


ALTER TYPE "public"."delivery_mode" OWNER TO "postgres";


CREATE TYPE "public"."dispute_stato" AS ENUM (
    'aperta',
    'in_valutazione',
    'rimborsata',
    'risolta',
    'respinta'
);


ALTER TYPE "public"."dispute_stato" OWNER TO "postgres";


CREATE TYPE "public"."drink_window_affidabilita" AS ENUM (
    'alta',
    'media',
    'bassa'
);


ALTER TYPE "public"."drink_window_affidabilita" OWNER TO "postgres";


CREATE TYPE "public"."drink_window_fonte" AS ENUM (
    'editorial',
    'ai',
    'personal',
    'owner',
    'unavailable'
);


ALTER TYPE "public"."drink_window_fonte" OWNER TO "postgres";


CREATE TYPE "public"."env_forma" AS ENUM (
    'parete_lineare',
    'scaffalatura_modulare',
    'cantinetta',
    'cassa_legno',
    'nicchia_angolare'
);


ALTER TYPE "public"."env_forma" OWNER TO "postgres";


CREATE TYPE "public"."env_illuminazione" AS ENUM (
    'calda',
    'neutra',
    'soffusa',
    'faretti',
    'laterale'
);


ALTER TYPE "public"."env_illuminazione" OWNER TO "postgres";


CREATE TYPE "public"."env_materiale" AS ENUM (
    'rovere',
    'noce',
    'metallo',
    'pietra',
    'mattone',
    'cemento',
    'vetro',
    'legno_grezzo'
);


ALTER TYPE "public"."env_materiale" OWNER TO "postgres";


CREATE TYPE "public"."env_tema" AS ENUM (
    'moderna',
    'rustica',
    'classica',
    'pietra',
    'industriale',
    'minimal',
    'premium',
    'casse'
);


ALTER TYPE "public"."env_tema" OWNER TO "postgres";


CREATE TYPE "public"."listing_stato" AS ENUM (
    'bozza',
    'in_revisione',
    'modifiche_richieste',
    'attivo',
    'riservato',
    'sospeso',
    'scaduto',
    'venduto',
    'rifiutato'
);


ALTER TYPE "public"."listing_stato" OWNER TO "postgres";


COMMENT ON TYPE "public"."listing_stato" IS 'Nove stati, identici a ListingStatus in frontend-next/src/data/moderation.ts. Definiti tutti in Fase 6a benché nessuna transizione sia ancora esposta: aggiungere un valore a un enum già in uso richiede una migrazione, definirlo in anticipo no. Le transizioni arrivano in 6b (pubblicazione, sospensione, scadenza), Fase 7 (riservato, venduto) e Fase 9 (in_revisione, modifiche_richieste, rifiutato).';



CREATE TYPE "public"."message_kind" AS ENUM (
    'user',
    'system'
);


ALTER TYPE "public"."message_kind" OWNER TO "postgres";


CREATE TYPE "public"."mod_action" AS ENUM (
    'richiesta_modifiche',
    'ammonizione',
    'sospensione',
    'rimozione',
    'ripristino',
    'chiusura',
    'info_richieste'
);


ALTER TYPE "public"."mod_action" OWNER TO "postgres";


CREATE TYPE "public"."mod_scope" AS ENUM (
    'piattaforma',
    'club'
);


ALTER TYPE "public"."mod_scope" OWNER TO "postgres";


CREATE TYPE "public"."notification_category" AS ENUM (
    'marketplace',
    'community',
    'sistema'
);


ALTER TYPE "public"."notification_category" OWNER TO "postgres";


CREATE TYPE "public"."notification_destination_kind" AS ENUM (
    'none',
    'conversation',
    'listing',
    'order',
    'club'
);


ALTER TYPE "public"."notification_destination_kind" OWNER TO "postgres";


CREATE TYPE "public"."order_stato" AS ENUM (
    'in_attesa_pagamento',
    'pagato',
    'in_preparazione',
    'spedito',
    'consegnato',
    'verifica',
    'completato',
    'contestato',
    'rimborsato',
    'annullato'
);


ALTER TYPE "public"."order_stato" OWNER TO "postgres";


CREATE TYPE "public"."payment_outcome" AS ENUM (
    'pending',
    'authorized',
    'settled',
    'failed',
    'expired',
    'refunded'
);


ALTER TYPE "public"."payment_outcome" OWNER TO "postgres";


COMMENT ON TYPE "public"."payment_outcome" IS 'Tassonomia interna degli esiti di incasso. La traduzione dal vocabolario di un fornitore a questi valori avviene nell''adapter, fuori dal database.';



CREATE TYPE "public"."payment_stato" AS ENUM (
    'checkout_pending',
    'processing',
    'paid',
    'failed',
    'expired',
    'partially_refunded',
    'refunded'
);


ALTER TYPE "public"."payment_stato" OWNER TO "postgres";


CREATE TYPE "public"."payout_stato" AS ENUM (
    'trattenuto',
    'in_attesa',
    'in_corso',
    'trasferito',
    'bloccato',
    'fallito'
);


ALTER TYPE "public"."payout_stato" OWNER TO "postgres";


COMMENT ON TYPE "public"."payout_stato" IS 'Stato del trasferimento verso il venditore. Ortogonale a public.order_stato: un ordine completato può avere un Transfer non ancora creato, in corso o fallito.';



CREATE TYPE "public"."preferenza_evoluzione" AS ENUM (
    'giovane',
    'equilibrato',
    'evoluto'
);


ALTER TYPE "public"."preferenza_evoluzione" OWNER TO "postgres";


CREATE TYPE "public"."prezzo_visibilita" AS ENUM (
    'visibile',
    'riservato'
);


ALTER TYPE "public"."prezzo_visibilita" OWNER TO "postgres";


CREATE TYPE "public"."price_observation_fonte" AS ENUM (
    'vinea_interno'
);


ALTER TYPE "public"."price_observation_fonte" OWNER TO "postgres";


COMMENT ON TYPE "public"."price_observation_fonte" IS 'Provenienza del dato. Una sola label oggi: il marketplace Vinea. Esiste per rendere estensibile la provenienza senza rifare il modello, NON per annunciare un fornitore - nessuno e'' stato scelto. Aggiungere una label non basta ad accendere nulla: vedi il CHECK ..._solo_fonti_interne.';



CREATE TYPE "public"."price_observation_tipo" AS ENUM (
    'richiesta',
    'vendita'
);


ALTER TYPE "public"."price_observation_tipo" OWNER TO "postgres";


COMMENT ON TYPE "public"."price_observation_tipo" IS 'Che cosa dice il prezzo osservato. `richiesta`: un venditore lo chiede davvero nella vetrina pubblica di Vinea. `vendita`: un ordine reale si e'' chiuso a quel prezzo. Non sono la stessa informazione e non vanno mediate insieme senza deciderlo: un chiesto non e'' un pagato.';



CREATE TYPE "public"."proposal_stato" AS ENUM (
    'inviata',
    'controproposta',
    'accettata',
    'rifiutata',
    'scaduta',
    'convertita'
);


ALTER TYPE "public"."proposal_stato" OWNER TO "postgres";


CREATE TYPE "public"."report_priorita" AS ENUM (
    'bassa',
    'media',
    'alta'
);


ALTER TYPE "public"."report_priorita" OWNER TO "postgres";


CREATE TYPE "public"."report_stato" AS ENUM (
    'inviata',
    'in_revisione',
    'info_richieste',
    'risolta',
    'respinta'
);


ALTER TYPE "public"."report_stato" OWNER TO "postgres";


CREATE TYPE "public"."report_target_tipo" AS ENUM (
    'annuncio',
    'profilo',
    'messaggio',
    'conversazione',
    'recensione',
    'post',
    'commento'
);


ALTER TYPE "public"."report_target_tipo" OWNER TO "postgres";


COMMENT ON TYPE "public"."report_target_tipo" IS 'Bersagli segnalabili. Sette, come i sette del mock in frontend/src/data/moderation.ts:22-23: la 9a ne aveva cinque perche la decisione 7.6a escludeva `post` e `commento` finche i club non avevano schema. La 12b glielo da, e la 12c li aggiunge qui. Aggiungere un valore a un enum in uso richiede una migrazione nuova, e usarlo ne richiede una ancora successiva: il valore non e utilizzabile nella transazione che lo crea.';



CREATE TYPE "public"."sommelier_ruolo" AS ENUM (
    'utente',
    'sommelier'
);


ALTER TYPE "public"."sommelier_ruolo" OWNER TO "postgres";


CREATE TYPE "public"."tracking_event_tipo" AS ENUM (
    'info',
    'spedizione',
    'consegna',
    'problema',
    'sistema'
);


ALTER TYPE "public"."tracking_event_tipo" OWNER TO "postgres";


CREATE TYPE "public"."utente_stato" AS ENUM (
    'attivo',
    'sospeso',
    'rimosso'
);


ALTER TYPE "public"."utente_stato" OWNER TO "postgres";


COMMENT ON TYPE "public"."utente_stato" IS 'Stato di moderazione di un utente. `sospeso` e il primo provvedimento della decisione 7.6b: blocca le sole scritture social. `rimosso` e il secondo: toglie anche l''accesso in visione. La compravendita non passa da qui.';



CREATE TYPE "public"."wine_provenienza" AS ENUM (
    'staff',
    'utente'
);


ALTER TYPE "public"."wine_provenienza" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."audit_log_append_only"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  raise exception
    'audit_log e append-only: % non e ammesso su public.audit_log.', tg_op
    using errcode = '42501';
end;
$$;


ALTER FUNCTION "private"."audit_log_append_only"() OWNER TO "postgres";


COMMENT ON FUNCTION "private"."audit_log_append_only"() IS 'Rifiuta UPDATE e DELETE su public.audit_log per ogni ruolo, service_role compreso. Un trigger e l''unico modo di esprimere questo invariante: i GRANT non vincolano il proprietario della tabella.';



CREATE OR REPLACE FUNCTION "private"."audit_registra"("p_attore_id" "uuid", "p_azione" "public"."mod_action", "p_target_tipo" "public"."report_target_tipo", "p_target_id" "uuid", "p_target_label" "text", "p_motivazione" "text", "p_durata" "text" DEFAULT NULL::"text", "p_report_id" "uuid" DEFAULT NULL::"uuid", "p_scope" "public"."mod_scope" DEFAULT 'piattaforma'::"public"."mod_scope", "p_club_slug" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "private"."audit_registra"("p_attore_id" "uuid", "p_azione" "public"."mod_action", "p_target_tipo" "public"."report_target_tipo", "p_target_id" "uuid", "p_target_label" "text", "p_motivazione" "text", "p_durata" "text", "p_report_id" "uuid", "p_scope" "public"."mod_scope", "p_club_slug" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "private"."audit_registra"("p_attore_id" "uuid", "p_azione" "public"."mod_action", "p_target_tipo" "public"."report_target_tipo", "p_target_id" "uuid", "p_target_label" "text", "p_motivazione" "text", "p_durata" "text", "p_report_id" "uuid", "p_scope" "public"."mod_scope", "p_club_slug" "text") IS 'Unica porta di scrittura di public.audit_log. Nessun INSERT dal client, mai. Conserva attore_username come istantanea perche il registro sopravviva alla cancellazione del profilo dell''attore.';



CREATE OR REPLACE FUNCTION "private"."bottle_units_ciclo_di_vita"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  -- Una data di acquisizione nel futuro renderebbe negativa qualsiasi durata di
  -- possesso e farebbe comparire punti nel domani sul grafico. Si rifiuta,
  -- invece di correggerla in silenzio.
  if new.acquired_at > now() then
    raise exception 'La data di acquisto non può essere nel futuro.'
      using errcode = 'P0001';
  end if;

  if tg_op = 'INSERT' then
    -- `consumed_at` non è mai un input, neppure per uno scrittore privilegiato.
    -- Se la prima riga nasce già consumata, il solo fatto autorevole disponibile
    -- è questo INSERT e la data nasce adesso; in ogni altro stato resta NULL.
    new.consumed_at := case
      when new.stato = 'consumata' then now()
      else null
    end;
    return new;
  end if;

  -- Set-once. Se il consumo era già datato, quella data vince su qualsiasi
  -- valore in arrivo: un UPDATE successivo non riscrive la storia. Se invece è
  -- la prima transizione verso `consumata`, la data nasce adesso.
  if old.consumed_at is not null then
    new.consumed_at := old.consumed_at;
  elsif new.stato = 'consumata' and old.stato is distinct from 'consumata' then
    new.consumed_at := now();
  else
    new.consumed_at := old.consumed_at;
  end if;

  -- `acquired_at` non è nei grant client e non deve muoversi da sola.
  new.acquired_at := old.acquired_at;

  return new;
end;
$$;


ALTER FUNCTION "private"."bottle_units_ciclo_di_vita"() OWNER TO "postgres";


COMMENT ON FUNCTION "private"."bottle_units_ciclo_di_vita"() IS 'Datazione set-once del consumo e difesa della data di acquisizione. Non tocca ceduta_at, che resta del trigger di vendita.';



CREATE OR REPLACE FUNCTION "private"."catalogo_risolvi_vino_utente"("p_produttore" "text", "p_nome" "text", "p_annata" integer, "p_regione" "text", "p_tipo" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid      uuid := auth.uid();
  v_wine     uuid;
  v_base     text;
  v_slug     text;
  v_n        integer := 1;
  v_regione  text;
begin
  if v_uid is null then
    raise exception 'Devi accedere per aggiungere una bottiglia.' using errcode = '42501';
  end if;
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

  -- Il cancello della regione. Sta dopo gli altri controlli di campo e prima di
  -- qualunque scrittura: quando fallisce, non e ancora nato niente — ne la
  -- scheda vino ne l'unita — quindi non c'e nessun residuo da ripulire.
  v_regione := private.regione_canonica(p_regione);
  if v_regione is null then
    raise exception 'Regione non riconosciuta: %. Scegli una delle regioni disponibili.',
      btrim(p_regione)
      using errcode = 'P0001';
  end if;

  select w.id into v_wine
  from public.wines w
  where w.produttore = trim(p_produttore)
    and w.nome = trim(p_nome)
    and w.annata = p_annata::smallint;

  if v_wine is not null then
    return v_wine;
  end if;

  v_base := public.slugifica(
    trim(p_produttore) || ' ' || trim(p_nome) || ' ' || p_annata::text
  );

  loop
    v_slug := case when v_n = 1 then v_base else v_base || '-' || v_n end;
    begin
      insert into public.wines (
        slug, produttore, nome, annata, regione, tipo, provenienza, creato_da
      )
      values (
        v_slug, trim(p_produttore), trim(p_nome), p_annata::smallint,
        v_regione, p_tipo, 'utente', v_uid
      )
      on conflict (produttore, nome, annata) do nothing
      returning id into v_wine;
    exception when unique_violation then
      v_wine := null;
    end;

    if v_wine is not null then
      return v_wine;
    end if;

    select w.id into v_wine
    from public.wines w
    where w.produttore = trim(p_produttore)
      and w.nome = trim(p_nome)
      and w.annata = p_annata::smallint;

    if v_wine is not null then
      return v_wine;
    end if;

    v_n := v_n + 1;
    if v_n > 100 then
      raise exception 'Non è stato possibile assegnare un identificatore al vino. Riprova.'
        using errcode = 'P0001';
    end if;
  end loop;
end;
$$;


ALTER FUNCTION "private"."catalogo_risolvi_vino_utente"("p_produttore" "text", "p_nome" "text", "p_annata" integer, "p_regione" "text", "p_tipo" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "private"."catalogo_risolvi_vino_utente"("p_produttore" "text", "p_nome" "text", "p_annata" integer, "p_regione" "text", "p_tipo" "text") IS 'Helper interno: riusa la tripletta esistente o crea una scheda con provenienza utente. Dalla D2 la regione viene ricondotta al nome canonico di public.wine_regions e un valore non riconosciuto e rifiutato con P0001. Non e una RPC client.';



CREATE OR REPLACE FUNCTION "private"."club_post_figlio_guard"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "private"."club_post_figlio_guard"() OWNER TO "postgres";


COMMENT ON FUNCTION "private"."club_post_figlio_guard"() IS 'Verifica che il post padre esista e non sia stato rimosso, e consuma club:risposta per le sole risposte. Serve club_post_risposte e club_post_like con lo stesso corpo, come scrittura_social_guard nella 9b.';



CREATE OR REPLACE FUNCTION "private"."club_post_immutabile_guard"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "private"."club_post_immutabile_guard"() OWNER TO "postgres";


COMMENT ON FUNCTION "private"."club_post_immutabile_guard"() IS 'Congela autore, club, tipo, allegati e data di un post gia pubblicato. Non SECURITY DEFINER: confronta old e new e solleva, non legge nulla.';



CREATE OR REPLACE FUNCTION "private"."club_post_owner_only_guard"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_owner_id uuid;
  v_mode text;
begin
  -- Legge owner_id e posting_mode del club di destinazione
  select c.owner_id, c.posting_mode
  into v_owner_id, v_mode
  from public.clubs c
  where c.slug = new.club_slug;

  -- Se il club non esiste o non ha owner_id (club legacy), permetti come OPEN
  if v_owner_id is null then
    return new;
  end if;

  -- OPEN: chiunque autenticato puo scrivere (il guard sociale fa il resto)
  if v_mode = 'OPEN' then
    return new;
  end if;

  -- OWNER_ONLY: solo il proprietario
  if v_mode = 'OWNER_ONLY' then
    if auth.uid() <> v_owner_id then
      raise exception
        'Solo il proprietario di questo club puo pubblicare.'
        using errcode = '42501';
    end if;
    return new;
  end if;

  -- Modalita sconosciuta: chiudi per sicurezza
  raise exception 'Modalita di pubblicazione non riconosciuta.'
    using errcode = 'P0001';
end;
$$;


ALTER FUNCTION "private"."club_post_owner_only_guard"() OWNER TO "postgres";


COMMENT ON FUNCTION "private"."club_post_owner_only_guard"() IS 'Enforcement OWNER_ONLY per club_posts. Per OPEN delega al flusso standard
  (social guard + RLS). Per OWNER_ONLY blocca chi non e proprietario.';



CREATE OR REPLACE FUNCTION "private"."club_post_riferimenti_guard"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "private"."club_post_riferimenti_guard"() OWNER TO "postgres";


COMMENT ON FUNCTION "private"."club_post_riferimenti_guard"() IS 'Verifica i tre allegati di un post e consuma il bucket club:post. La bottiglia dev''essere dell''autore; l''annuncio dev''essere pubblico e, per un post di tipo annuncio, anche dell''autore. Legge bottle_units, mai cellar_environments: l''ambiente di cantina resta privato.';



CREATE OR REPLACE FUNCTION "private"."club_risposta_owner_only_guard"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_owner_id uuid;
  v_mode text;
begin
  select c.owner_id, c.posting_mode
  into v_owner_id, v_mode
  from public.clubs c
  join public.club_posts p on p.club_slug = c.slug
  where p.id = new.post_id;

  if v_owner_id is null then
    return new;
  end if;

  if v_mode = 'OPEN' then
    return new;
  end if;

  if v_mode = 'OWNER_ONLY' then
    if auth.uid() <> v_owner_id then
      raise exception
        'Solo il proprietario di questo club puo rispondere.'
        using errcode = '42501';
    end if;
    return new;
  end if;

  raise exception 'Modalita di pubblicazione non riconosciuta.'
    using errcode = 'P0001';
end;
$$;


ALTER FUNCTION "private"."club_risposta_owner_only_guard"() OWNER TO "postgres";


COMMENT ON FUNCTION "private"."club_risposta_owner_only_guard"() IS 'Enforcement OWNER_ONLY per club_post_risposte. Legge il club dal post padre.';



CREATE OR REPLACE FUNCTION "private"."commercio_rimosso_guard"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if private.utente_stato_di(new.buyer_id) = 'rimosso' then
    raise exception 'Account rimosso: non puoi acquistare.'
      using errcode = '42501';
  end if;

  if private.utente_stato_di(new.seller_id) = 'rimosso' then
    raise exception 'Questo venditore non e piu attivo.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "private"."commercio_rimosso_guard"() OWNER TO "postgres";


COMMENT ON FUNCTION "private"."commercio_rimosso_guard"() IS 'Secondo livello della decisione 7.6b sul commercio: nessun ordine nuovo se una delle due parti e rimossa. Non guarda `sospeso`, che per decisione continua a comprare e vendere. Non tocca gli ordini gia esistenti: quelli restano alla macchina di rilascio, che deve poterli chiudere.';



CREATE OR REPLACE FUNCTION "private"."conversation_assert_valid"("p_conversation_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_conversation public.conversations%rowtype;
  v_participant_count integer;
  v_valid_participant_count integer;
  v_listing_seller uuid;
  v_order public.orders%rowtype;
begin
  select * into v_conversation
  from public.conversations
  where id = p_conversation_id;

  if not found then
    return;
  end if;

  select
    count(*)::integer,
    count(*) filter (
      where cp.user_id in (
        v_conversation.participant_low,
        v_conversation.participant_high
      )
    )::integer
  into v_participant_count, v_valid_participant_count
  from public.conversation_participants cp
  where cp.conversation_id = v_conversation.id;

  if v_participant_count <> 2 or v_valid_participant_count <> 2 then
    raise exception 'Una conversazione deve avere esattamente due partecipanti canonici.'
      using errcode = '23514';
  end if;

  select l.seller_id into v_listing_seller
  from public.listings l
  where l.id = v_conversation.listing_id;

  if not found or v_listing_seller not in (
    v_conversation.participant_low,
    v_conversation.participant_high
  ) then
    raise exception 'La coppia non appartiene all''annuncio della conversazione.'
      using errcode = '23514';
  end if;

  if v_conversation.order_id is not null then
    select * into v_order
    from public.orders
    where id = v_conversation.order_id;

    if not found
       or v_order.listing_id <> v_conversation.listing_id
       or least(v_order.buyer_id, v_order.seller_id)
            <> v_conversation.participant_low
       or greatest(v_order.buyer_id, v_order.seller_id)
            <> v_conversation.participant_high then
      raise exception 'L''ordine non appartiene alla conversazione.'
        using errcode = '23514';
    end if;
  end if;
end;
$$;


ALTER FUNCTION "private"."conversation_assert_valid"("p_conversation_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."conversation_create"("p_listing_id" "uuid", "p_order_id" "uuid", "p_participant_low" "uuid", "p_participant_high" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_conversation_id uuid;
begin
  select c.id into v_conversation_id
  from public.conversations c
  where c.listing_id = p_listing_id
    and c.participant_low = p_participant_low
    and c.participant_high = p_participant_high
  for update;

  if found then
    if p_order_id is not null then
      update public.conversations
      set order_id = p_order_id
      where id = v_conversation_id
        and order_id is null;

      if exists (
        select 1
        from public.conversations c
        where c.id = v_conversation_id
          and c.order_id is distinct from p_order_id
      ) then
        raise exception 'La conversazione appartiene a un altro ordine.'
          using errcode = 'P0001';
      end if;
    end if;
    return v_conversation_id;
  end if;

  insert into public.conversations (
    listing_id, order_id, participant_low, participant_high
  ) values (
    p_listing_id, p_order_id, p_participant_low, p_participant_high
  )
  returning id into v_conversation_id;

  insert into public.conversation_participants (conversation_id, user_id)
  values
    (v_conversation_id, p_participant_low),
    (v_conversation_id, p_participant_high);

  return v_conversation_id;
end;
$$;


ALTER FUNCTION "private"."conversation_create"("p_listing_id" "uuid", "p_order_id" "uuid", "p_participant_low" "uuid", "p_participant_high" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."conversation_is_writable"("p_conversation_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1
    from public.conversations c
    join public.listings l on l.id = c.listing_id
    left join public.orders o on o.id = c.order_id
    where c.id = p_conversation_id
      and (
        (
          l.stato = 'attivo'
          and (l.expires_at is null or l.expires_at > now())
        )
        or (
          o.id is not null
          and o.stato not in ('completato', 'rimborsato', 'annullato')
        )
      )
  );
$$;


ALTER FUNCTION "private"."conversation_is_writable"("p_conversation_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."conversation_participant_guard"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not exists (
    select 1
    from public.conversations c
    where c.id = new.conversation_id
      and new.user_id in (c.participant_low, c.participant_high)
  ) then
    raise exception 'Partecipante estraneo alla coppia canonica.'
      using errcode = '23514';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "private"."conversation_participant_guard"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."conversation_system_event"("p_conversation_id" "uuid", "p_source_event_key" "text", "p_body" "text", "p_recipient_id" "uuid", "p_event_type" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_body text := btrim(coalesce(p_body, ''));
  v_existing public.messages%rowtype;
  v_message_id uuid;
begin
  if length(v_body) not between 1 and 2000
     or length(coalesce(p_source_event_key, '')) not between 8 and 180
     or p_source_event_key !~ '^[A-Za-z0-9._:-]+$'
     or length(coalesce(p_event_type, '')) not between 3 and 80
     or p_event_type !~ '^[a-z0-9_]+$' then
    raise exception 'Evento sistema non valido.' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtext('system-message:' || p_conversation_id::text || ':' || p_source_event_key)
  );

  select * into v_existing
  from public.messages m
  where m.conversation_id = p_conversation_id
    and m.source_event_key = p_source_event_key;

  if found then
    if v_existing.body <> v_body or not exists (
      select 1
      from public.notifications n
      where n.recipient_id = p_recipient_id
        and n.category = 'marketplace'
        and n.event_type = p_event_type
        and n.body = v_body
        and n.dedupe_key = 'system-message:' || v_existing.id::text
        and n.destination_kind = 'conversation'
        and n.destination_conversation_id = p_conversation_id
    ) then
      raise exception 'Evento sistema gia usato con un altro payload.'
        using errcode = '22023';
    end if;
    return v_existing.id;
  end if;

  if not exists (
    select 1
    from public.conversation_participants cp
    where cp.conversation_id = p_conversation_id
      and cp.user_id = p_recipient_id
  ) then
    raise exception 'Destinatario estraneo alla conversazione.'
      using errcode = '42501';
  end if;

  insert into public.messages (
    conversation_id, kind, body, source_event_key
  ) values (
    p_conversation_id, 'system', v_body, p_source_event_key
  )
  returning id into v_message_id;

  insert into public.notifications (
    recipient_id, category, event_type, body, dedupe_key,
    destination_kind, destination_conversation_id
  ) values (
    p_recipient_id, 'marketplace', p_event_type, v_body,
    'system-message:' || v_message_id::text,
    'conversation', p_conversation_id
  )
  on conflict (recipient_id, dedupe_key) do nothing;

  return v_message_id;
end;
$_$;


ALTER FUNCTION "private"."conversation_system_event"("p_conversation_id" "uuid", "p_source_event_key" "text", "p_body" "text", "p_recipient_id" "uuid", "p_event_type" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."conversation_validate_participants"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if tg_op = 'DELETE' then
    perform private.conversation_assert_valid(old.conversation_id);
    return old;
  end if;

  if tg_op = 'UPDATE' and old.conversation_id <> new.conversation_id then
    perform private.conversation_assert_valid(old.conversation_id);
  end if;
  perform private.conversation_assert_valid(new.conversation_id);
  return new;
end;
$$;


ALTER FUNCTION "private"."conversation_validate_participants"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."conversation_validate_row"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  perform private.conversation_assert_valid(new.id);
  return new;
end;
$$;


ALTER FUNCTION "private"."conversation_validate_row"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."disputes_invariante"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if new.contestato_at is not null
     and not exists (select 1 from public.disputes d where d.order_id = new.id) then
    raise exception
      'Un ordine contestato deve avere una pratica in public.disputes.'
      using errcode = 'P0001';
  end if;
  return null;
end;
$$;


ALTER FUNCTION "private"."disputes_invariante"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."listings_price_observation_sync"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_registra boolean := false;
  v_wine_id  uuid;
  v_formato  text;
begin
  -- [a]
  if new.stato <> 'attivo' then
    return null;
  end if;

  if tg_op = 'INSERT' then
    -- Nasce gia' attivo. Dal client e' impossibile - `stato` non e' fra i
    -- GRANT di colonna della 6a e il DEFAULT e' 'bozza' - ma uno scrittore
    -- privilegiato puo' farlo, ed e' proprio per coprirlo che questo e' un
    -- trigger.
    v_registra := true;
  elsif old.stato = 'attivo' then
    -- [c]
    v_registra := new.prezzo_cents is distinct from old.prezzo_cents;
  elsif old.stato = 'riservato' then
    -- [d]
    v_registra := false;
  else
    -- [b]
    v_registra := true;
  end if;

  if not v_registra then
    return null;
  end if;

  select w.id, w.formato
    into v_wine_id, v_formato
  from public.bottle_units bu
    join public.wines w on w.id = bu.wine_id
  where bu.id = new.bottle_unit_id;

  perform private.price_observation_registra(
    v_wine_id, v_formato, 'richiesta', new.prezzo_cents, now(), new.id
  );

  return null;
end;
$$;


ALTER FUNCTION "private"."listings_price_observation_sync"() OWNER TO "postgres";


COMMENT ON FUNCTION "private"."listings_price_observation_sync"() IS 'Registra una osservazione `richiesta` quando un annuncio entra nella vetrina pubblica o quando il prezzo di un annuncio gia'' attivo cambia davvero. Il ritorno da `riservato` e'' escluso di proposito: lo scrivono i percorsi di rilascio prenotazione, non un venditore.';



CREATE OR REPLACE FUNCTION "private"."listings_riferimento_sync"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_wine   uuid;
  v_bottle uuid;
begin
  -- Il vino si prende dalla bottiglia dell'annuncio. Su DELETE la riga NEW non
  -- è assegnata e leggerne un campo solleverebbe un errore, quindi il ramo si
  -- sceglie sull'operazione e non con un coalesce.
  if tg_op = 'DELETE' then
    v_bottle := old.bottle_unit_id;
  else
    v_bottle := new.bottle_unit_id;
  end if;

  select bu.wine_id
  into v_wine
  from public.bottle_units bu
  where bu.id = v_bottle;

  perform private.wine_reference_snapshot_registra(v_wine);

  return null;
end;
$$;


ALTER FUNCTION "private"."listings_riferimento_sync"() OWNER TO "postgres";


COMMENT ON FUNCTION "private"."listings_riferimento_sync"() IS 'Ricalcola il riferimento del vino quando un annuncio entra o esce da `attivo` o ne cambia il prezzo. La decisione se scrivere sta nello scrittore, che confronta con l''ultimo snapshot.';


SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."marketplace_config" (
    "id" bigint NOT NULL,
    "margine_obiettivo_bps" integer NOT NULL,
    "riferimento_stripe_percentuale_bps" integer NOT NULL,
    "riferimento_stripe_fisso_cents" integer NOT NULL,
    "auto_rilascio_giorni" integer NOT NULL,
    "valida_da" timestamp with time zone DEFAULT "now"() NOT NULL,
    "valida_fino" timestamp with time zone,
    "nota" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "marketplace_config_auto_rilascio_giorni_check" CHECK ((("auto_rilascio_giorni" >= 1) AND ("auto_rilascio_giorni" <= 180))),
    CONSTRAINT "marketplace_config_intervallo_valido" CHECK ((("valida_fino" IS NULL) OR ("valida_fino" > "valida_da"))),
    CONSTRAINT "marketplace_config_margine_obiettivo_bps_check" CHECK ((("margine_obiettivo_bps" >= 0) AND ("margine_obiettivo_bps" <= 5000))),
    CONSTRAINT "marketplace_config_nota_check" CHECK ((("nota" IS NULL) OR (("length"("nota") >= 1) AND ("length"("nota") <= 500)))),
    CONSTRAINT "marketplace_config_riferimento_stripe_fisso_cents_check" CHECK ((("riferimento_stripe_fisso_cents" >= 0) AND ("riferimento_stripe_fisso_cents" <= 10000))),
    CONSTRAINT "marketplace_config_riferimento_stripe_percentuale_bps_check" CHECK ((("riferimento_stripe_percentuale_bps" >= 0) AND ("riferimento_stripe_percentuale_bps" <= 5000)))
);


ALTER TABLE "public"."marketplace_config" OWNER TO "postgres";


COMMENT ON TABLE "public"."marketplace_config" IS 'Configurazione di mercato versionata. Una sola riga corrente (valida_fino nulla); le righe chiuse restano come storico. I parametri applicati a un ordine sono congelati sull''ordine stesso e non si rileggono da qui.';



CREATE OR REPLACE FUNCTION "private"."marketplace_config_corrente"() RETURNS "public"."marketplace_config"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select * from public.marketplace_config
  where valida_fino is null
  order by valida_da desc
  limit 1;
$$;


ALTER FUNCTION "private"."marketplace_config_corrente"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."marketplace_totale_cents"("p_prezzo_cents" integer, "p_margine_obiettivo_bps" integer, "p_riferimento_percentuale_bps" integer, "p_riferimento_fisso_cents" integer) RETURNS integer
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
  select ceil(
    (p_prezzo_cents::numeric * (10000 + p_margine_obiettivo_bps)
     + p_riferimento_fisso_cents::numeric * 10000)
    / (10000 - p_riferimento_percentuale_bps)::numeric
  )::integer;
$$;


ALTER FUNCTION "private"."marketplace_totale_cents"("p_prezzo_cents" integer, "p_margine_obiettivo_bps" integer, "p_riferimento_percentuale_bps" integer, "p_riferimento_fisso_cents" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."messages_after_insert"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  update public.conversations c
  set last_message_id = new.id,
      last_message_at = new.created_at
  where c.id = new.conversation_id
    and (
      c.last_message_at is null
      or (new.created_at, new.id) > (c.last_message_at, c.last_message_id)
    );

  perform realtime.send(
    jsonb_build_object(
      'schemaVersion', 1,
      'entity', 'message',
      'id', new.id,
      'conversationId', new.conversation_id,
      'createdAt', new.created_at
    ),
    'message.changed',
    'conversation:' || new.conversation_id::text,
    true
  );

  return new;
end;
$$;


ALTER FUNCTION "private"."messages_after_insert"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."messages_immutable"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if tg_op = 'DELETE'
     and current_user in ('postgres', 'service_role', 'supabase_admin') then
    return old;
  end if;
  raise exception 'I messaggi sono immutabili.' using errcode = '42501';
end;
$$;


ALTER FUNCTION "private"."messages_immutable"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."moderazione_annuncio_transizione"("p_attore" "uuid", "p_listing_id" "uuid", "p_stato" "public"."listing_stato", "p_azione" "public"."mod_action", "p_motivazione" "text", "p_ammessi" "public"."listing_stato"[], "p_report_id" "uuid" DEFAULT NULL::"uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_stato public.listing_stato;
  v_slug text;
  v_bottle uuid;
begin
  if length(btrim(coalesce(p_motivazione, ''))) = 0 then
    raise exception 'Motivazione obbligatoria.' using errcode = '22023';
  end if;

  select l.stato, l.slug, l.bottle_unit_id
    into v_stato, v_slug, v_bottle
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


ALTER FUNCTION "private"."moderazione_annuncio_transizione"("p_attore" "uuid", "p_listing_id" "uuid", "p_stato" "public"."listing_stato", "p_azione" "public"."mod_action", "p_motivazione" "text", "p_ammessi" "public"."listing_stato"[], "p_report_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "private"."moderazione_annuncio_transizione"("p_attore" "uuid", "p_listing_id" "uuid", "p_stato" "public"."listing_stato", "p_azione" "public"."mod_action", "p_motivazione" "text", "p_ammessi" "public"."listing_stato"[], "p_report_id" "uuid") IS 'Motore condiviso delle transizioni di moderazione su un annuncio: verifica lo stato di partenza, rifiuta riservato e venduto, scrive la traccia sulle tre colonne di listings e registra la riga di audit. Le funzioni pubbliche sotto sono distinte per azione, non parametrizzate su un''azione.';



CREATE OR REPLACE FUNCTION "private"."moderazione_attore"() RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  -- Decisione 7.1: il moderatore e il ruolo `admin` esistente, non un ruolo
  -- nuovo. Predicato scritto per esteso e non public.has_role(): vedi il
  -- cappello di questo file.
  if not exists (
    select 1 from public.user_roles ur
    where ur.user_id = v_uid and ur.role = 'admin'
  ) then
    raise exception 'Azione riservata alla moderazione.' using errcode = '42501';
  end if;

  return v_uid;
end;
$$;


ALTER FUNCTION "private"."moderazione_attore"() OWNER TO "postgres";


COMMENT ON FUNCTION "private"."moderazione_attore"() IS 'Ritorna l''uid del chiamante se ha il ruolo admin, altrimenti solleva. Unico punto in cui il predicato di moderatore e scritto, per tutte le RPC della 9b.';



CREATE TABLE IF NOT EXISTS "public"."reports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "codice" "text" NOT NULL,
    "target_tipo" "public"."report_target_tipo" NOT NULL,
    "target_label" "text" NOT NULL,
    "target_listing_id" "uuid",
    "target_profile_id" "uuid",
    "target_message_id" "uuid",
    "target_conversation_id" "uuid",
    "target_review_id" "uuid",
    "motivo" "text" NOT NULL,
    "descrizione" "text" DEFAULT ''::"text" NOT NULL,
    "foto" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "stato" "public"."report_stato" DEFAULT 'inviata'::"public"."report_stato" NOT NULL,
    "priorita" "public"."report_priorita" NOT NULL,
    "reporter_id" "uuid" NOT NULL,
    "club_slug" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "target_post_id" "uuid",
    "target_risposta_id" "uuid",
    CONSTRAINT "reports_club_slug_check" CHECK ((("club_slug" IS NULL) OR ("club_slug" ~ '^[a-z0-9]+(-[a-z0-9]+)*$'::"text"))),
    CONSTRAINT "reports_descrizione_check" CHECK (("length"("descrizione") <= 4000)),
    CONSTRAINT "reports_foto_check" CHECK (("cardinality"("foto") <= 8)),
    CONSTRAINT "reports_target_coerente" CHECK (
CASE "target_tipo"
    WHEN 'annuncio'::"public"."report_target_tipo" THEN (("target_profile_id" IS NULL) AND ("target_message_id" IS NULL) AND ("target_conversation_id" IS NULL) AND ("target_review_id" IS NULL) AND ("target_post_id" IS NULL) AND ("target_risposta_id" IS NULL))
    WHEN 'profilo'::"public"."report_target_tipo" THEN (("target_listing_id" IS NULL) AND ("target_message_id" IS NULL) AND ("target_conversation_id" IS NULL) AND ("target_review_id" IS NULL) AND ("target_post_id" IS NULL) AND ("target_risposta_id" IS NULL))
    WHEN 'messaggio'::"public"."report_target_tipo" THEN (("target_listing_id" IS NULL) AND ("target_profile_id" IS NULL) AND ("target_conversation_id" IS NULL) AND ("target_review_id" IS NULL) AND ("target_post_id" IS NULL) AND ("target_risposta_id" IS NULL))
    WHEN 'conversazione'::"public"."report_target_tipo" THEN (("target_listing_id" IS NULL) AND ("target_profile_id" IS NULL) AND ("target_message_id" IS NULL) AND ("target_review_id" IS NULL) AND ("target_post_id" IS NULL) AND ("target_risposta_id" IS NULL))
    WHEN 'recensione'::"public"."report_target_tipo" THEN (("target_listing_id" IS NULL) AND ("target_profile_id" IS NULL) AND ("target_message_id" IS NULL) AND ("target_conversation_id" IS NULL) AND ("target_post_id" IS NULL) AND ("target_risposta_id" IS NULL))
    WHEN 'post'::"public"."report_target_tipo" THEN (("target_listing_id" IS NULL) AND ("target_profile_id" IS NULL) AND ("target_message_id" IS NULL) AND ("target_conversation_id" IS NULL) AND ("target_review_id" IS NULL) AND ("target_risposta_id" IS NULL))
    WHEN 'commento'::"public"."report_target_tipo" THEN (("target_listing_id" IS NULL) AND ("target_profile_id" IS NULL) AND ("target_message_id" IS NULL) AND ("target_conversation_id" IS NULL) AND ("target_review_id" IS NULL) AND ("target_post_id" IS NULL))
    ELSE false
END),
    CONSTRAINT "reports_target_esclusivo" CHECK ((((((((
CASE
    WHEN ("target_listing_id" IS NOT NULL) THEN 1
    ELSE 0
END +
CASE
    WHEN ("target_profile_id" IS NOT NULL) THEN 1
    ELSE 0
END) +
CASE
    WHEN ("target_message_id" IS NOT NULL) THEN 1
    ELSE 0
END) +
CASE
    WHEN ("target_conversation_id" IS NOT NULL) THEN 1
    ELSE 0
END) +
CASE
    WHEN ("target_review_id" IS NOT NULL) THEN 1
    ELSE 0
END) +
CASE
    WHEN ("target_post_id" IS NOT NULL) THEN 1
    ELSE 0
END) +
CASE
    WHEN ("target_risposta_id" IS NOT NULL) THEN 1
    ELSE 0
END) <= 1)),
    CONSTRAINT "reports_target_label_check" CHECK ((("length"("btrim"("target_label")) >= 1) AND ("length"("btrim"("target_label")) <= 200)))
);


ALTER TABLE "public"."reports" OWNER TO "postgres";


COMMENT ON TABLE "public"."reports" IS 'Segnalazioni degli utenti. Nessun grant client: si scrive solo da public.segnalazione_invia e si legge solo dalle viste moderation_report_queue (moderatore) e my_reports (segnalante). reporter_id e visibile al moderatore per la decisione 7.4 e non compare in nessuna proiezione raggiungibile dal segnalato.';



COMMENT ON COLUMN "public"."reports"."codice" IS 'Etichetta leggibile derivata da una sequenza. Non e la chiave.';



COMMENT ON COLUMN "public"."reports"."priorita" IS 'Derivata sul server da private.report_priorita_da_motivo. Regola di dominio, quindi non un valore che il client invia: replica priorityFromReason in frontend/src/data/moderation.ts:108-120.';



COMMENT ON COLUMN "public"."reports"."target_post_id" IS 'Bersaglio quando target_tipo = ''post''. Aggiunta dalla 12c: la 9a non poteva averla perche i club non avevano schema (decisione 7.6a).';



COMMENT ON COLUMN "public"."reports"."target_risposta_id" IS 'Bersaglio quando target_tipo = ''commento''. Il nome del valore dell''enum e `commento` perche viene dal mock; la tabella si chiama club_post_risposte.';



CREATE OR REPLACE FUNCTION "private"."moderazione_bersaglio"("p_report" "public"."reports") RETURNS "uuid"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
  select coalesce(
    p_report.target_listing_id, p_report.target_profile_id,
    p_report.target_message_id, p_report.target_conversation_id,
    p_report.target_review_id, p_report.target_post_id,
    p_report.target_risposta_id
  );
$$;


ALTER FUNCTION "private"."moderazione_bersaglio"("p_report" "public"."reports") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."moderazione_contenuto_club_transizione"("p_attore" "uuid", "p_report" "public"."reports", "p_rimuovi" boolean, "p_azione" "public"."mod_action", "p_motivazione" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_target uuid;
  v_club text;
  v_toccate integer;
begin
  v_target := coalesce(p_report.target_post_id, p_report.target_risposta_id);
  if v_target is null then
    raise exception 'La segnalazione non punta a un contenuto di club.'
      using errcode = 'P0001';
  end if;

  if p_report.target_tipo = 'post' then
    -- `(rimosso_at is not null) is distinct from p_rimuovi` e la condizione di
    -- transizione: se il contenuto e gia nello stato richiesto non tocca
    -- niente, e il controllo sotto lo trasforma in un errore leggibile invece
    -- che in un successo silenzioso. E' la forma dell'array di stati di
    -- partenza che moderazione_annuncio_transizione usa per gli annunci.
    update public.club_posts
    set rimosso_at     = case when p_rimuovi then now() end,
        rimosso_da     = case when p_rimuovi then p_attore end,
        rimosso_motivo = case when p_rimuovi then btrim(p_motivazione) end
    where id = v_target
      and (rimosso_at is not null) is distinct from p_rimuovi;
    get diagnostics v_toccate = row_count;

    select cp.club_slug into v_club
    from public.club_posts cp where cp.id = v_target;

  elsif p_report.target_tipo = 'commento' then
    update public.club_post_risposte
    set rimosso_at     = case when p_rimuovi then now() end,
        rimosso_da     = case when p_rimuovi then p_attore end,
        rimosso_motivo = case when p_rimuovi then btrim(p_motivazione) end
    where id = v_target
      and (rimosso_at is not null) is distinct from p_rimuovi;
    get diagnostics v_toccate = row_count;

    select cp.club_slug into v_club
    from public.club_post_risposte cr
    join public.club_posts cp on cp.id = cr.post_id
    where cr.id = v_target;

  else
    raise exception 'Bersaglio non gestito da questo motore.' using errcode = 'P0001';
  end if;

  if v_toccate = 0 then
    raise exception
      'Questo contenuto e gia nello stato richiesto.' using errcode = 'P0001';
  end if;

  -- audit_log ha un CHECK `(scope = 'club') = (club_slug is not null)`: senza
  -- club_slug la riga di audit verrebbe rifiutata dal database, e l'azione
  -- fallirebbe dopo aver gia rimosso il contenuto. Il caso non e raggiungibile
  -- - la colonna e NOT NULL e l'UPDATE e appena riuscito - ma un vincolo che
  -- si scopre a valle di una scrittura merita di essere nominato a monte.
  if v_club is null then
    raise exception 'Club del contenuto non risolvibile.' using errcode = 'P0001';
  end if;

  perform private.audit_registra(
    p_attore_id => p_attore,
    p_azione => p_azione,
    p_target_tipo => p_report.target_tipo,
    p_target_id => v_target,
    p_target_label => p_report.target_label,
    p_motivazione => p_motivazione,
    p_report_id => p_report.id,
    p_scope => 'club'::public.mod_scope,
    p_club_slug => v_club
  );
end;
$$;


ALTER FUNCTION "private"."moderazione_contenuto_club_transizione"("p_attore" "uuid", "p_report" "public"."reports", "p_rimuovi" boolean, "p_azione" "public"."mod_action", "p_motivazione" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "private"."moderazione_contenuto_club_transizione"("p_attore" "uuid", "p_report" "public"."reports", "p_rimuovi" boolean, "p_azione" "public"."mod_action", "p_motivazione" "text") IS 'Rimuove o ripristina un post o una risposta segnalati, in logica e mai con una DELETE, e registra la riga di audit con scope `club`. Unica porta delle tre colonne rimosso_*. Non verifica il ruolo: lo ha gia fatto private.moderazione_attore() dentro l''azione che la chiama.';



CREATE OR REPLACE FUNCTION "private"."moderazione_pratica"("p_report_id" "uuid", "p_stato_pratica" "public"."report_stato", "p_motivazione" "text", "p_nota_interna" "text", "p_testo_visibile" "text") RETURNS "public"."reports"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_attore uuid := private.moderazione_attore();
  v_report public.reports;
  v_username text;
begin
  if length(btrim(coalesce(p_motivazione, ''))) = 0 then
    raise exception 'Motivazione obbligatoria.' using errcode = '22023';
  end if;

  select * into v_report
  from public.reports r
  where r.id = p_report_id
  for update;

  if not found then
    raise exception 'Segnalazione non trovata.' using errcode = 'P0001';
  end if;
  if v_report.stato in ('risolta', 'respinta') then
    raise exception 'Questa pratica e gia chiusa.' using errcode = 'P0001';
  end if;

  update public.reports
  set stato = p_stato_pratica,
      updated_at = now()
  where id = p_report_id
  returning * into v_report;

  select pr.username into v_username
  from public.profiles pr where pr.id = v_attore;

  insert into public.report_events
    (report_id, visibile, testo, autore_id, autore_etichetta)
  values
    (p_report_id, true, p_testo_visibile, v_attore, 'Moderazione');

  if length(btrim(coalesce(p_nota_interna, ''))) > 0 then
    insert into public.report_events
      (report_id, visibile, testo, autore_id, autore_etichetta)
    values
      (p_report_id, false, btrim(p_nota_interna), v_attore,
       coalesce(v_username, 'Moderazione'));
  end if;

  return v_report;
end;
$$;


ALTER FUNCTION "private"."moderazione_pratica"("p_report_id" "uuid", "p_stato_pratica" "public"."report_stato", "p_motivazione" "text", "p_nota_interna" "text", "p_testo_visibile" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "private"."moderazione_pratica"("p_report_id" "uuid", "p_stato_pratica" "public"."report_stato", "p_motivazione" "text", "p_nota_interna" "text", "p_testo_visibile" "text") IS 'Parte comune delle sette azioni: verifica il moderatore, blocca una pratica gia chiusa, sposta lo stato, scrive la voce visibile e l''eventuale nota interna. L''effetto sul bersaglio e la riga di audit restano a ciascuna azione, perche sono cio che le distingue.';



CREATE OR REPLACE FUNCTION "private"."moderazione_utente_provvedimento"("p_attore" "uuid", "p_profile_id" "uuid", "p_motivazione" "text", "p_durata" "text" DEFAULT NULL::"text", "p_report_id" "uuid" DEFAULT NULL::"uuid", "p_forza_rimozione" boolean DEFAULT false) RETURNS "public"."utente_stato"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_stato public.utente_stato;
  v_n integer;
  v_username text;
  v_nuovo public.utente_stato;
begin
  if length(btrim(coalesce(p_motivazione, ''))) = 0 then
    raise exception 'Motivazione obbligatoria.' using errcode = '22023';
  end if;

  select p.stato_utente, p.provvedimenti, p.username
    into v_stato, v_n, v_username
  from public.profiles p
  where p.id = p_profile_id
  for update;

  if not found then
    raise exception 'Profilo non trovato.' using errcode = 'P0001';
  end if;

  if p_attore = p_profile_id then
    raise exception 'Un moderatore non applica un provvedimento a se stesso.'
      using errcode = '22023';
  end if;

  if v_stato = 'rimosso' then
    raise exception 'Utente gia rimosso.' using errcode = 'P0001';
  end if;

  -- Il livello lo decide il contatore, non lo stato corrente: un ripristino
  -- riporta lo stato ad `attivo` e lascia il contatore dov'e, quindi il
  -- provvedimento successivo resta il secondo. Entrambi i rami del case sono
  -- castati all'enum: un case fra due letterali si risolve a text e text->enum
  -- non ha conversione implicita (42804, difetto della 7c).
  v_nuovo := case
    when p_forza_rimozione or v_n >= 1 then 'rimosso'::public.utente_stato
    else 'sospeso'::public.utente_stato
  end;

  update public.profiles
  set stato_utente = v_nuovo,
      provvedimenti = v_n + 1,
      stato_utente_at = now(),
      stato_utente_motivo = btrim(p_motivazione)
  where id = p_profile_id;

  perform private.audit_registra(
    p_attore_id => p_attore,
    p_azione => case
      when v_nuovo = 'rimosso' then 'rimozione'::public.mod_action
      else 'sospensione'::public.mod_action
    end,
    p_target_tipo => 'profilo'::public.report_target_tipo,
    p_target_id => p_profile_id,
    p_target_label => v_username,
    p_motivazione => p_motivazione,
    p_durata => case
      when v_nuovo = 'sospeso' then p_durata
      else null
    end,
    p_report_id => p_report_id
  );

  return v_nuovo;
end;
$$;


ALTER FUNCTION "private"."moderazione_utente_provvedimento"("p_attore" "uuid", "p_profile_id" "uuid", "p_motivazione" "text", "p_durata" "text", "p_report_id" "uuid", "p_forza_rimozione" boolean) OWNER TO "postgres";


COMMENT ON FUNCTION "private"."moderazione_utente_provvedimento"("p_attore" "uuid", "p_profile_id" "uuid", "p_motivazione" "text", "p_durata" "text", "p_report_id" "uuid", "p_forza_rimozione" boolean) IS 'Enforcement della decisione 7.6b. Primo provvedimento: `sospeso`, che blocca le sole scritture social. Dal secondo: `rimosso`, che toglie anche la lettura. Il contatore non si azzera con il ripristino, altrimenti il secondo provvedimento non sarebbe mai il secondo.';



CREATE OR REPLACE FUNCTION "private"."moderazione_utente_ripristina"("p_attore" "uuid", "p_profile_id" "uuid", "p_motivazione" "text", "p_report_id" "uuid" DEFAULT NULL::"uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_stato public.utente_stato;
  v_username text;
begin
  if length(btrim(coalesce(p_motivazione, ''))) = 0 then
    raise exception 'Motivazione obbligatoria.' using errcode = '22023';
  end if;

  select p.stato_utente, p.username into v_stato, v_username
  from public.profiles p
  where p.id = p_profile_id
  for update;

  if not found then
    raise exception 'Profilo non trovato.' using errcode = 'P0001';
  end if;
  if v_stato = 'attivo' then
    raise exception 'Utente gia attivo.' using errcode = 'P0001';
  end if;

  update public.profiles
  set stato_utente = 'attivo'::public.utente_stato,
      stato_utente_at = now(),
      stato_utente_motivo = btrim(p_motivazione)
  where id = p_profile_id;

  perform private.audit_registra(
    p_attore_id => p_attore,
    p_azione => 'ripristino'::public.mod_action,
    p_target_tipo => 'profilo'::public.report_target_tipo,
    p_target_id => p_profile_id,
    p_target_label => v_username,
    p_motivazione => p_motivazione,
    p_report_id => p_report_id
  );
end;
$$;


ALTER FUNCTION "private"."moderazione_utente_ripristina"("p_attore" "uuid", "p_profile_id" "uuid", "p_motivazione" "text", "p_report_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."notifications_after_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if tg_op = 'UPDATE' and new.read_at is not distinct from old.read_at then
    return new;
  end if;

  perform realtime.send(
    jsonb_build_object(
      'schemaVersion', 1,
      'entity', 'notification',
      'id', new.id,
      'createdAt', new.created_at
    ),
    'notification.changed',
    'user:' || new.recipient_id::text || ':notifications',
    true
  );

  return new;
end;
$$;


ALTER FUNCTION "private"."notifications_after_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."orders_price_observation_sync"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_wine_id uuid;
  v_formato text;
begin
  select w.id, w.formato
    into v_wine_id, v_formato
  from public.bottle_units bu
    join public.wines w on w.id = bu.wine_id
  where bu.id = new.seller_bottle_unit_id;

  perform private.price_observation_registra(
    v_wine_id, v_formato, 'vendita', new.prezzo_cents,
    coalesce(new.paid_at, now()), new.id
  );

  return null;
end;
$$;


ALTER FUNCTION "private"."orders_price_observation_sync"() OWNER TO "postgres";


COMMENT ON FUNCTION "private"."orders_price_observation_sync"() IS 'Registra UNA osservazione `vendita` quando un ordine entra in `completato`. Il prezzo e'' quello congelato sull''ordine, non quello corrente dell''annuncio. L''unicita'' e'' garantita dall''indice parziale wine_price_observations_una_vendita_per_ordine, non da questo codice: `completato` non e'' assorbente (ordine_contesta lo accetta), quindi un rientro dopo una contestazione NON produce una seconda riga.';



CREATE OR REPLACE FUNCTION "private"."orders_tracking_sync"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if new.stato is not distinct from old.stato then
    return null;
  end if;

  case new.stato
    when 'pagato' then
      perform private.tracking_registra(
        new.id, 'sistema', 'Pagamento confermato');
    when 'consegnato' then
      perform private.tracking_registra(
        new.id, 'consegna', 'Consegnato',
        case when new.auto_rilascio_scadenza is not null
             then 'Periodo di verifica aperto fino al '
                  || to_char(new.auto_rilascio_scadenza, 'DD/MM/YYYY')
             else null end);
    when 'completato' then
      perform private.tracking_registra(
        new.id, 'sistema',
        case when new.ricezione_confermata_at is not null
             then 'Ordine completato dall''acquirente'
             else 'Ordine completato' end);
    when 'rimborsato' then
      perform private.tracking_registra(new.id, 'sistema', 'Ordine rimborsato');
    when 'annullato' then
      perform private.tracking_registra(new.id, 'sistema', 'Ordine annullato');
    else
      null;
  end case;
  return null;
end;
$$;


ALTER FUNCTION "private"."orders_tracking_sync"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."price_observation_registra"("p_wine_id" "uuid", "p_formato" "text", "p_tipo" "public"."price_observation_tipo", "p_prezzo_cents" integer, "p_observed_at" timestamp with time zone, "p_origine_ref" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  -- Un dato incompleto non diventa una riga di storia sbagliata: si tace. Un
  -- prezzo non positivo o un vino sconosciuto qui vorrebbero dire che il
  -- dominio a monte ha gia' un difetto, e non e' questo il posto in cui
  -- fermare un ordine o una pubblicazione per segnalarlo.
  if p_wine_id is null or p_prezzo_cents is null or p_prezzo_cents <= 0 then
    return;
  end if;

  insert into public.wine_price_observations (
    wine_id, formato, tipo, fonte, prezzo_cents, observed_at, origine_ref
  )
  values (
    p_wine_id,
    coalesce(nullif(btrim(p_formato), ''), '0,75 L'),
    p_tipo,
    'vinea_interno',
    p_prezzo_cents,
    coalesce(p_observed_at, now()),
    p_origine_ref
  )
  -- Rete di idempotenza sulla vendita: se l'indice parziale trova gia' la riga
  -- di questo ordine, non solleva - non registra. Una seconda esecuzione di un
  -- percorso di completamento non deve rompere l'ordine per colpa di una
  -- osservazione.
  on conflict do nothing;
end;
$$;


ALTER FUNCTION "private"."price_observation_registra"("p_wine_id" "uuid", "p_formato" "text", "p_tipo" "public"."price_observation_tipo", "p_prezzo_cents" integer, "p_observed_at" timestamp with time zone, "p_origine_ref" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "private"."price_observation_registra"("p_wine_id" "uuid", "p_formato" "text", "p_tipo" "public"."price_observation_tipo", "p_prezzo_cents" integer, "p_observed_at" timestamp with time zone, "p_origine_ref" "uuid") IS 'Unica porta di scrittura di wine_price_observations. Chiamata soltanto dai due trigger di dominio. `on conflict do nothing` rende idempotente la registrazione di vendita senza far fallire il completamento dell''ordine.';



CREATE OR REPLACE FUNCTION "private"."profile_certifications_guard"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "private"."profile_certifications_guard"() OWNER TO "postgres";


COMMENT ON FUNCTION "private"."profile_certifications_guard"() IS 'Vincoli che devono valere anche per uno scrittore privilegiato: nessuna autocertificazione, e nessun `venditore` senza `identita` valida.';



CREATE OR REPLACE FUNCTION "private"."profiles_stato_utente_guard"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if new.stato_utente is distinct from old.stato_utente
     or new.provvedimenti is distinct from old.provvedimenti
     or new.stato_utente_at is distinct from old.stato_utente_at
     or new.stato_utente_motivo is distinct from old.stato_utente_motivo then
    if current_user not in ('postgres', 'supabase_admin') then
      raise exception
        'Lo stato di moderazione di un profilo si cambia solo dalle funzioni di moderazione.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "private"."profiles_stato_utente_guard"() OWNER TO "postgres";


COMMENT ON FUNCTION "private"."profiles_stato_utente_guard"() IS 'Le quattro colonne di moderazione di public.profiles non sono scrivibili da un ruolo client ne da service_role. Un GRANT di colonna non basta: service_role non e vincolato dai GRANT del client.';



CREATE OR REPLACE FUNCTION "private"."rate_limit_consume"("p_scope" "text", "p_subject" "text", "p_limit" integer, "p_window_seconds" integer) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_started_at timestamptz;
  v_count integer;
begin
  if length(trim(coalesce(p_scope, ''))) not between 1 and 120
     or length(trim(coalesce(p_subject, ''))) not between 1 and 240
     or p_limit not between 1 and 10000
     or p_window_seconds not between 1 and 86400 then
    raise exception 'Configurazione rate limit non valida.' using errcode = '22023';
  end if;

  v_started_at := to_timestamp(
    floor(extract(epoch from clock_timestamp()) / p_window_seconds)
    * p_window_seconds
  );

  insert into private.rate_limit_buckets (
    scope, subject, window_started_at, window_seconds, request_count, expires_at
  ) values (
    trim(p_scope), trim(p_subject), v_started_at, p_window_seconds, 1,
    v_started_at + make_interval(secs => p_window_seconds * 2)
  )
  on conflict (scope, subject, window_started_at)
  do update set request_count = private.rate_limit_buckets.request_count + 1
  returning request_count into v_count;

  if v_count > p_limit then
    raise sqlstate 'PGRST' using
      message = json_build_object(
        'code', 'rate_limit_exceeded',
        'message', 'Troppe richieste. Riprova più tardi.'
      )::text,
      detail = json_build_object(
        'status', 429,
        'headers', json_build_object(
          'Retry-After', greatest(
            1,
            ceil(extract(epoch from (
              v_started_at + make_interval(secs => p_window_seconds)
              - clock_timestamp()
            )))::integer
          )::text
        )
      )::text;
  end if;

  -- Pulizia opportunistica: non richiede pg_cron e mantiene la tabella limitata.
  if mod(abs(hashtext(trim(p_subject))), 64) = 0 then
    delete from private.rate_limit_buckets where expires_at < clock_timestamp();
  end if;

  return v_count;
end;
$$;


ALTER FUNCTION "private"."rate_limit_consume"("p_scope" "text", "p_subject" "text", "p_limit" integer, "p_window_seconds" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."regione_canonica"("p_regione" "text") RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select r.nome
  from public.wine_regions r
  where lower(r.nome) = lower(btrim(coalesce(p_regione, '')))
  limit 1;
$$;


ALTER FUNCTION "private"."regione_canonica"("p_regione" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "private"."regione_canonica"("p_regione" "text") IS 'Riconduce una regione scritta dall''utente al nome canonico: ignora spazi ai bordi e differenze di maiuscole. Restituisce NULL se il valore non e nella tassonomia. Helper interno: non e una RPC client.';



CREATE OR REPLACE FUNCTION "private"."report_priorita_da_motivo"("p_motivo" "text") RETURNS "public"."report_priorita"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "private"."report_priorita_da_motivo"("p_motivo" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "private"."report_priorita_da_motivo"("p_motivo" "text") IS 'Priorita derivata dal testo del motivo, come priorityFromReason in frontend/src/data/moderation.ts:108-120. Ogni ramo del case e castato esplicitamente all''enum: un case fra due letterali si risolve a text e text->enum non ha conversione implicita (42804, difetto della 7c).';



CREATE OR REPLACE FUNCTION "private"."scrittura_social_guard"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  -- La riga passa da jsonb e non da `new.<colonna>`: lo stesso corpo serve tre
  -- tabelle con colonne diverse, e plpgsql risolve i riferimenti di campo alla
  -- compilazione. `new.seller_id` in un trigger su public.messages non sarebbe
  -- un ramo che non viene percorso, sarebbe un errore di compilazione.
  v_riga jsonb := to_jsonb(new);
  v_attore uuid;
  v_stato public.utente_stato;
begin
  v_attore := case tg_table_name
    when 'listings' then (v_riga->>'seller_id')::uuid
    when 'messages' then (v_riga->>'sender_id')::uuid
    else auth.uid()
  end;

  -- I messaggi di sistema non hanno mittente e non sono una scrittura social.
  if tg_table_name = 'messages' and coalesce(v_riga->>'kind', '') <> 'user' then
    return new;
  end if;

  if v_attore is null then
    return new;
  end if;

  v_stato := private.utente_stato_di(v_attore);

  if v_stato = 'sospeso' then
    raise exception
      'Account sospeso: non puoi pubblicare annunci ne scrivere messaggi.'
      using errcode = '42501';
  elsif v_stato = 'rimosso' then
    raise exception 'Account rimosso.' using errcode = '42501';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "private"."scrittura_social_guard"() OWNER TO "postgres";


COMMENT ON FUNCTION "private"."scrittura_social_guard"() IS 'Primo livello della decisione 7.6b. Blocca l''inserimento di annunci, di messaggi utente e l''apertura di conversazioni per un utente sospeso o rimosso. Il commercio non passa da qui: per `sospeso` perche resta permesso, per `rimosso` perche lo blocca private.commercio_rimosso_guard() sulla tabella public.orders.';



CREATE OR REPLACE FUNCTION "private"."seller_enabled_sync"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if new.charges_enabled and new.payouts_enabled then
    insert into public.user_roles (user_id, role)
    values (new.seller_id, 'seller_enabled')
    on conflict (user_id, role) do nothing;
  else
    -- Nessun altro fornitore lo tiene in piedi? Allora il ruolo decade.
    if not exists (
      select 1 from public.seller_payout_accounts a
      where a.seller_id = new.seller_id
        and a.id <> new.id
        and a.charges_enabled
        and a.payouts_enabled
    ) then
      delete from public.user_roles
      where user_id = new.seller_id and role = 'seller_enabled';
    end if;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "private"."seller_enabled_sync"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."sommelier_contesto_leggi"("p_owner_id" "uuid", "p_session_id" "text", "p_limite" integer) RETURNS TABLE("ruolo" "public"."sommelier_ruolo", "contenuto" "text", "created_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "private"."sommelier_contesto_leggi"("p_owner_id" "uuid", "p_session_id" "text", "p_limite" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."sommelier_scambio_registra"("p_owner_id" "uuid", "p_session_id" "text", "p_domanda" "text", "p_risposta" "text") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "private"."sommelier_scambio_registra"("p_owner_id" "uuid", "p_session_id" "text", "p_domanda" "text", "p_risposta" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."tracking_registra"("p_order_id" "uuid", "p_tipo" "public"."tracking_event_tipo", "p_titolo" "text", "p_descrizione" "text" DEFAULT NULL::"text", "p_luogo" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  insert into public.tracking_events (order_id, tipo, titolo, descrizione, luogo)
  values (p_order_id, p_tipo, p_titolo, p_descrizione, p_luogo);
$$;


ALTER FUNCTION "private"."tracking_registra"("p_order_id" "uuid", "p_tipo" "public"."tracking_event_tipo", "p_titolo" "text", "p_descrizione" "text", "p_luogo" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."utente_stato_di"("p_uid" "uuid") RETURNS "public"."utente_stato"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select coalesce(
    (select p.stato_utente from public.profiles p where p.id = p_uid),
    'attivo'::public.utente_stato
  );
$$;


ALTER FUNCTION "private"."utente_stato_di"("p_uid" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "private"."utente_stato_di"("p_uid" "uuid") IS 'Stato di moderazione di un utente. `attivo` anche per un uid sconosciuto: un profilo che non esiste non e un utente sospeso, e il chiamante ha gia i propri controlli di esistenza.';



CREATE OR REPLACE FUNCTION "private"."vinea_check_request"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_method text := current_setting('request.method', true);
  v_path text := current_setting('request.path', true);
  v_uid uuid := auth.uid();
  v_headers jsonb := coalesce(
    nullif(current_setting('request.headers', true), '')::jsonb,
    '{}'::jsonb
  );
  v_subject text;
  v_limit integer;
begin
  if v_method is null or v_method in ('GET', 'HEAD', 'OPTIONS') then
    return;
  end if;

  -- Una RPC `stable`/`immutable` chiamata in POST gira in transazione di sola
  -- lettura: e' una lettura per costruzione, e le letture non si contano. Senza
  -- questa uscita la insert qui sotto solleva 25006 e PostgREST risponde 405.
  if current_setting('transaction_read_only', true) = 'on' then
    return;
  end if;

  v_subject := case
    when v_uid is not null then 'user:' || v_uid::text
    else 'ip:' || coalesce(
      nullif(split_part(v_headers ->> 'x-forwarded-for', ',', 1), ''),
      'unknown'
    )
  end;
  v_limit := case when coalesce(v_path, '') like 'rpc/%' then 60 else 120 end;

  perform private.rate_limit_consume(
    'postgrest:' || coalesce(v_path, 'unknown'),
    v_subject,
    v_limit,
    60
  );
end;
$$;


ALTER FUNCTION "private"."vinea_check_request"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."wine_price_observations_append_only"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  raise exception
    'wine_price_observations e append-only: % non e ammesso.', tg_op
    using errcode = '42501';
end;
$$;


ALTER FUNCTION "private"."wine_price_observations_append_only"() OWNER TO "postgres";


COMMENT ON FUNCTION "private"."wine_price_observations_append_only"() IS 'Rifiuta UPDATE, DELETE e TRUNCATE su public.wine_price_observations per ogni ruolo. Un trigger e'' l''unico modo di esprimere questo invariante: i GRANT non vincolano il proprietario della tabella.';



CREATE OR REPLACE FUNCTION "private"."wine_reference_snapshot_registra"("p_wine_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_formato    text;
  v_n          integer;
  v_mediana    integer;
  v_minimo     integer;
  v_massimo    integer;
  v_ultimo     public.wine_reference_snapshots%rowtype;
begin
  if p_wine_id is null then
    return;
  end if;

  select coalesce(nullif(btrim(w.formato), ''), '0,75 L')
  into v_formato
  from public.wines w
  where w.id = p_wine_id;

  if v_formato is null then
    return;
  end if;

  -- Stessa semantica del modulo puro di D3-A: solo `attivo`, un prezzo per
  -- annuncio, mediana con arrotondamento a intero. `percentile_cont` restituisce
  -- l'elemento centrale su un numero dispari e la media dei due centrali su un
  -- numero pari, che è esattamente ciò che fa medianaCents().
  select
    count(*)::integer,
    round(percentile_cont(0.5) within group (order by l.prezzo_cents))::integer,
    min(l.prezzo_cents),
    max(l.prezzo_cents)
  into v_n, v_mediana, v_minimo, v_massimo
  from public.listings l
  join public.bottle_units bu on bu.id = l.bottle_unit_id
  where bu.wine_id = p_wine_id
    and l.stato = 'attivo';

  v_n := coalesce(v_n, 0);

  if v_n < 3 then
    v_mediana := null;
    v_minimo  := null;
    v_massimo := null;
  end if;

  select *
  into v_ultimo
  from public.wine_reference_snapshots s
  where s.wine_id = p_wine_id
    and s.formato = v_formato
  order by s.observed_at desc, s.created_at desc
  limit 1;

  if found then
    if v_ultimo.comparabili = v_n
       and v_ultimo.mediana_cents is not distinct from v_mediana
       and v_ultimo.minimo_cents is not distinct from v_minimo
       and v_ultimo.massimo_cents is not distinct from v_massimo then
      return;
    end if;
  elsif v_n < 3 then
    -- Non c'è ancora storia e non c'è ancora riferimento. Aprire la serie con
    -- una riga vuota direbbe "misurato, non disponibile" dove la verità è
    -- "mai misurato".
    return;
  end if;

  insert into public.wine_reference_snapshots (
    wine_id, formato, mediana_cents, minimo_cents, massimo_cents,
    comparabili, observed_at
  )
  values (
    p_wine_id, v_formato, v_mediana, v_minimo, v_massimo, v_n, now()
  );
end;
$$;


ALTER FUNCTION "private"."wine_reference_snapshot_registra"("p_wine_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "private"."wine_reference_snapshot_registra"("p_wine_id" "uuid") IS 'Unico scrittore dello storico del riferimento. Registra solo un cambiamento reale del riferimento corrente. Non è una RPC client.';



CREATE OR REPLACE FUNCTION "private"."wine_reference_snapshots_append_only"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  raise exception 'Lo storico del riferimento è solo in aggiunta: % rifiutato.',
    tg_op
    using errcode = 'P0001';
end;
$$;


ALTER FUNCTION "private"."wine_reference_snapshots_append_only"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bottiglia_apri"("p_bottle_unit_id" "uuid", "p_nota" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid     uuid := auth.uid();
  v_owner   uuid;
  v_stato   public.bottle_unit_stato;
  v_deleted timestamptz;
  v_ceduta  timestamptz;
begin
  if v_uid is null then
    raise exception 'Devi accedere per aprire una bottiglia.' using errcode = '42501';
  end if;

  select bu.owner_id, bu.stato, bu.deleted_at, bu.ceduta_at
  into v_owner, v_stato, v_deleted, v_ceduta
  from public.bottle_units bu
  where bu.id = p_bottle_unit_id
  for update;

  if v_owner is null or v_owner is distinct from v_uid or v_deleted is not null then
    raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
  end if;
  if v_ceduta is not null then
    raise exception 'Questa bottiglia è già stata venduta e non è più nella tua cantina.'
      using errcode = 'P0001';
  end if;
  if v_stato = 'aperta' then
    raise exception 'Questa bottiglia è già aperta.' using errcode = 'P0001';
  end if;
  if v_stato = 'consumata' then
    raise exception 'Questa bottiglia è già stata consumata.' using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.listings l
    where l.bottle_unit_id = p_bottle_unit_id
      and l.stato in (
        'bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato'
      )
  ) then
    raise exception
      'Questa bottiglia ha un annuncio in corso: concludilo o ritiralo prima di aprirla.'
      using errcode = 'P0001';
  end if;

  -- L'UNICA differenza rispetto alla versione precedente: la nota va nella sua
  -- colonna e non sopra note_personali, e l'apertura lascia una data.
  -- `degustazione_at` si scrive SEMPRE, anche senza nota: e' il momento in cui la
  -- bottiglia e' stata aperta, non un attributo del commento. Il caso [10] della
  -- griglia esiste per questa distinzione.
  update public.bottle_units
  set stato = 'aperta',
      degustazione_at = now(),
      degustazione_nota = case
        when p_nota is null or trim(p_nota) = '' then degustazione_nota
        else p_nota
      end
  where id = p_bottle_unit_id;
end;
$$;


ALTER FUNCTION "public"."bottiglia_apri"("p_bottle_unit_id" "uuid", "p_nota" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."bottiglia_apri"("p_bottle_unit_id" "uuid", "p_nota" "text") IS 'Apre una bottiglia della propria cantina. Rifiuta se la bottiglia ha un annuncio in uno dei cinque stati non terminali. Dal 19 agosto 2026 la nota finisce in degustazione_nota e non sovrascrive piu'' note_personali, e l''apertura registra degustazione_at.';



CREATE OR REPLACE FUNCTION "public"."bottiglia_cancella"("p_bottle_unit_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid     uuid := auth.uid();
  v_owner   uuid;
  v_deleted timestamptz;
  v_ceduta  timestamptz;
begin
  if v_uid is null then
    raise exception 'Devi accedere per togliere una bottiglia dalla cantina.'
      using errcode = '42501';
  end if;

  select bu.owner_id, bu.deleted_at, bu.ceduta_at
  into v_owner, v_deleted, v_ceduta
  from public.bottle_units bu
  where bu.id = p_bottle_unit_id
  for update;

  if v_owner is null or v_owner is distinct from v_uid then
    raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
  end if;
  if v_deleted is not null then
    raise exception 'Questa bottiglia è già stata tolta dalla cantina.' using errcode = 'P0001';
  end if;
  if v_ceduta is not null then
    raise exception 'Questa bottiglia è già stata venduta e non è più nella tua cantina.'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.listings l
    where l.bottle_unit_id = p_bottle_unit_id
      and l.stato in (
        'bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato'
      )
  ) then
    raise exception
      'Questa bottiglia ha un annuncio in corso: concludilo o ritiralo prima di toglierla dalla cantina.'
      using errcode = 'P0001';
  end if;

  delete from public.cellar_slots
  where bottle_unit_id = p_bottle_unit_id;

  update public.bottle_units
  set deleted_at = now()
  where id = p_bottle_unit_id;
end;
$$;


ALTER FUNCTION "public"."bottiglia_cancella"("p_bottle_unit_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."bottiglia_cancella"("p_bottle_unit_id" "uuid") IS 'Rimuove logicamente con lock una bottiglia ancora posseduta e libera lo slot. Rifiuta unità cedute o collegate a un annuncio non terminale.';



CREATE OR REPLACE FUNCTION "public"."bottle_units_preserva_annuncio_non_terminale"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if (
    new.stato <> 'chiusa'
    or new.deleted_at is not null
    or new.ceduta_at is not null
  ) and exists (
    select 1
    from public.listings l
    where l.bottle_unit_id = new.id
      and l.stato in (
        'bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato'
      )
  ) then
    raise exception
      'La bottiglia ha un annuncio in corso: concludilo o ritiralo prima di modificarne lo stato.'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."bottle_units_preserva_annuncio_non_terminale"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cellar_ambiente_crea"("p_nome" "text", "p_forma" "text", "p_tema" "text", "p_righe" integer, "p_colonne" integer) RETURNS TABLE("environment_id" "uuid", "module_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid         uuid := auth.uid();
  v_environment uuid;
  v_module      uuid;
begin
  if v_uid is null then
    raise exception 'Devi accedere per creare un ambiente.' using errcode = '42501';
  end if;
  if coalesce(trim(p_nome), '') = '' then
    raise exception 'Il nome dell''ambiente è obbligatorio.' using errcode = 'P0001';
  end if;
  if p_forma not in (
    'parete_lineare', 'scaffalatura_modulare', 'cantinetta',
    'cassa_legno', 'nicchia_angolare'
  ) then
    raise exception 'Forma dell''ambiente non valida.' using errcode = 'P0001';
  end if;
  if p_tema not in (
    'moderna', 'rustica', 'classica', 'pietra',
    'industriale', 'minimal', 'premium', 'casse'
  ) then
    raise exception 'Tema dell''ambiente non valido.' using errcode = 'P0001';
  end if;
  if p_righe is null or p_righe < 1 or p_righe > 50 then
    raise exception 'Il numero di righe deve essere fra 1 e 50.' using errcode = 'P0001';
  end if;
  if p_colonne is null or p_colonne < 1 or p_colonne > 50 then
    raise exception 'Il numero di colonne deve essere fra 1 e 50.' using errcode = 'P0001';
  end if;

  insert into public.cellar_environments (
    owner_id, nome, forma, tema, materiale, illuminazione,
    larghezza_cm, altezza_cm, profondita_cm
  )
  values (
    v_uid, trim(p_nome), p_forma::public.env_forma, p_tema::public.env_tema,
    'rovere', 'neutra',
    round((p_colonne * 0.3 + 0.5) * 100)::integer,
    round((p_righe * 0.35 + 0.5) * 100)::integer,
    40
  )
  returning id into v_environment;

  insert into public.cellar_modules (
    environment_id, etichetta, righe, colonne
  )
  values (
    v_environment, trim(p_nome) || ' — modulo principale',
    p_righe::smallint, p_colonne::smallint
  )
  returning id into v_module;

  return query select v_environment, v_module;
end;
$$;


ALTER FUNCTION "public"."cellar_ambiente_crea"("p_nome" "text", "p_forma" "text", "p_tema" "text", "p_righe" integer, "p_colonne" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cellar_ambiente_crea"("p_nome" "text", "p_forma" "text", "p_tema" "text", "p_righe" integer, "p_colonne" integer) IS 'Crea ambiente e modulo principale in una sola transazione. Owner, materiale, illuminazione e dimensioni derivate non provengono come autorità dal client.';



CREATE OR REPLACE FUNCTION "public"."cellar_ambiente_e_mio"("p_environment_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1
    from public.cellar_environments e
    where e.id = p_environment_id
      and e.owner_id = (select auth.uid())
  );
$$;


ALTER FUNCTION "public"."cellar_ambiente_e_mio"("p_environment_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cellar_bottiglia_aggiungi"("p_produttore" "text", "p_nome" "text", "p_annata" integer, "p_regione" "text", "p_tipo" "text", "p_visibilita" "public"."bottle_unit_visibilita" DEFAULT 'privata'::"public"."bottle_unit_visibilita", "p_immagini" "text"[] DEFAULT '{}'::"text"[], "p_acquisition_cost_cents" integer DEFAULT NULL::integer, "p_acquired_at" timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS TABLE("bottle_unit_id" "uuid", "wine_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_uid       uuid := auth.uid();
  v_wine      uuid;
  v_bottle    uuid;
  v_immagine  text;
  v_fonte     public.bottle_acquisition_fonte;
  v_acquisito timestamptz;
begin
  if v_uid is null then
    raise exception 'Devi accedere per aggiungere una bottiglia.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid) then
    raise exception 'Il tuo profilo non è ancora completo.'
      using errcode = 'P0001';
  end if;
  if p_visibilita not in ('privata', 'cantina_pubblica') then
    raise exception 'Visibilità della bottiglia non valida.' using errcode = 'P0001';
  end if;
  if array_length(p_immagini, 1) > 6 then
    raise exception 'Massimo 6 fotografie per bottiglia.' using errcode = 'P0001';
  end if;

  foreach v_immagine in array coalesce(p_immagini, '{}'::text[]) loop
    if v_immagine !~ ('^' || v_uid::text || '/[0-9a-f-]{36}\.(jpg|jpeg|png|webp|avif)$') then
      raise exception 'Fotografia non valida: %', v_immagine using errcode = 'P0001';
    end if;
    if not exists (
      select 1
      from storage.objects o
      where o.bucket_id = 'cantina'
        and o.name = v_immagine
    ) then
      raise exception 'La fotografia non appartiene al bucket privato della Cantina.'
        using errcode = 'P0001';
    end if;
  end loop;

  -- Il costo è facoltativo, ma se arriva dev'essere un costo. Un valore
  -- negativo non è un dato incerto da accogliere e correggere dopo: è un dato
  -- impossibile, e passerebbe nel calcolo della performance invertendone il
  -- segno. Si rifiuta con un messaggio leggibile invece di lasciare emergere
  -- il testo del CHECK.
  if p_acquisition_cost_cents is not null then
    if p_acquisition_cost_cents < 0 then
      raise exception 'Il prezzo di acquisto non può essere negativo.'
        using errcode = 'P0001';
    end if;
    if p_acquisition_cost_cents > 100000000 then
      raise exception 'Il prezzo di acquisto indicato non è plausibile.'
        using errcode = 'P0001';
    end if;
  end if;

  if p_acquired_at is not null then
    if p_acquired_at > now() then
      raise exception 'La data di acquisto non può essere nel futuro.'
        using errcode = 'P0001';
    end if;
    if p_acquired_at < timestamptz '1900-01-01' then
      raise exception 'La data di acquisto indicata non è plausibile.'
        using errcode = 'P0001';
    end if;
  end if;

  v_acquisito := coalesce(p_acquired_at, now());

  -- Entrambi i rami sono castati: un CASE di letterali stringa si risolve come
  -- `text` e assegnarlo a una colonna enum solleva 42804. Vedi CLAUDE.md.
  v_fonte := case
    when p_acquisition_cost_cents is not null or p_acquired_at is not null
      then 'manuale'::public.bottle_acquisition_fonte
    else 'sconosciuta'::public.bottle_acquisition_fonte
  end;

  v_wine := private.catalogo_risolvi_vino_utente(
    p_produttore, p_nome, p_annata, p_regione, p_tipo
  );

  insert into public.bottle_units (
    owner_id, wine_id, stato, visibilita, immagini,
    acquired_at, acquisition_fonte, acquisition_cost_cents
  )
  values (
    v_uid, v_wine, 'chiusa', p_visibilita, coalesce(p_immagini, '{}'::text[]),
    v_acquisito, v_fonte, p_acquisition_cost_cents
  )
  returning id into v_bottle;

  return query select v_bottle, v_wine;
end;
$_$;


ALTER FUNCTION "public"."cellar_bottiglia_aggiungi"("p_produttore" "text", "p_nome" "text", "p_annata" integer, "p_regione" "text", "p_tipo" "text", "p_visibilita" "public"."bottle_unit_visibilita", "p_immagini" "text"[], "p_acquisition_cost_cents" integer, "p_acquired_at" timestamp with time zone) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cellar_bottiglia_aggiungi"("p_produttore" "text", "p_nome" "text", "p_annata" integer, "p_regione" "text", "p_tipo" "text", "p_visibilita" "public"."bottle_unit_visibilita", "p_immagini" "text"[], "p_acquisition_cost_cents" integer, "p_acquired_at" timestamp with time zone) IS 'Aggiunge una bottle_unit privata o di cantina pubblica senza creare un annuncio. Owner e autore derivano da auth.uid(); le foto restano nel bucket privato cantina. Prezzo e data di acquisto sono facoltativi: omessi, la provenienza del costo resta `sconosciuta` e il costo NULL.';



CREATE OR REPLACE FUNCTION "public"."cellar_modulo_e_mio"("p_module_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1
    from public.cellar_modules m
      join public.cellar_environments e on e.id = m.environment_id
    where m.id = p_module_id
      and e.owner_id = (select auth.uid())
  );
$$;


ALTER FUNCTION "public"."cellar_modulo_e_mio"("p_module_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cellar_portfolio_analitica"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid       uuid := auth.uid();
  v_posizioni jsonb;
  v_storico   jsonb;
begin
  if v_uid is null then
    raise exception 'Devi accedere per vedere l''andamento della tua Cantina.'
      using errcode = '42501';
  end if;

  with posseduta as (
    select bu.*
    from public.bottle_units bu
    where bu.owner_id = v_uid
    -- Le righe cancellate restano nel modello owner-only: `deleted_at` è un
    -- confine storico reale e serve a mostrare che la posizione era eleggibile
    -- prima della rimozione. Sarà il modulo puro a escluderle dal valore corrente
    -- e a chiuderne la serie in quel momento, senza confondere cancellazione,
    -- vendita e consumo.
  ),
  acquisto as (
    -- Acquisto su Vinea. L'uscita di cassa dell'acquirente è quanto ha pagato
    -- meno quanto gli è stato rimborsato: un rimborso RIDUCE l'esborso, e
    -- ignorarlo gonfierebbe il capitale investito e schiaccerebbe la
    -- performance. Il prezzo del venditore e il totale addebitato restano
    -- distinti e riportati a parte: non sono la stessa grandezza.
    select
      p.id            as bottle_unit_id,
      o.id            as order_id,
      o.prezzo_cents  as prezzo_venditore_cents,
      pay.amount_cents          as pagato_lordo_cents,
      pay.amount_refunded_cents as rimborsato_cents,
      case
        when pay.order_id is not null
          then greatest(pay.amount_cents - pay.amount_refunded_cents, 0)
        else null
      end                       as esborso_netto_cents,
      o.paid_at
    from posseduta p
    join public.orders o
      on o.buyer_bottle_unit_id = p.id
     and o.buyer_id = v_uid
    left join public.payments pay
      on pay.order_id = o.id
     -- Una riga di checkout non è ancora un esborso. L'importo diventa un fatto
     -- economico solo dopo il pagamento firmato; gli stati di rimborso restano
     -- validi perché riducono quel fatto, fino anche a zero. `paid_at` chiude il
     -- caso impossibile di una riga payment promossa senza ordine pagato.
     and pay.stato in ('paid', 'partially_refunded', 'refunded')
     and o.paid_at is not null
  ),
  vendita as (
    -- Incasso realizzato. Non è `orders.prezzo_cents`, che è il prezzo
    -- richiesto e non il denaro arrivato; non è un payout previsto o
    -- trattenuto. È l'importo effettivamente trasferito, e solo quando lo
    -- stato lo dice, la data lo conferma e il payout è intestato a chi legge.
    --
    -- `seller_bottle_unit_id` non è unico: una bottiglia annullata e rimessa in
    -- vendita ha più ordini. Senza `distinct on` la stessa bottiglia
    -- comparirebbe più volte fra le posizioni e il suo riferimento verrebbe
    -- sommato due volte. Vince l'ordine che ha prodotto un incasso davvero
    -- trasferito; a parità, il più recente.
    select distinct on (p.id)
      p.id           as bottle_unit_id,
      o.id           as order_id,
      o.stato::text  as order_stato,
      po.stato::text as payout_stato,
      case
        when po.stato = 'trasferito' and po.transferred_at is not null
          then po.amount_cents
        else null
      end            as incassato_cents,
      case
        when po.stato = 'trasferito' and po.transferred_at is not null
          then po.transferred_at
        else null
      end            as incassato_at
    from posseduta p
    join public.orders o
      on o.seller_bottle_unit_id = p.id
     and o.seller_id = v_uid
    left join public.payouts po
      on po.order_id = o.id
     and po.seller_id = v_uid
    order by
      p.id,
      (po.stato = 'trasferito' and po.transferred_at is not null) desc nulls last,
      o.created_at desc
  ),
  riferimento as (
    select distinct on (s.wine_id, s.formato)
      s.wine_id, s.formato, s.mediana_cents, s.comparabili, s.observed_at
    from public.wine_reference_snapshots s
    where s.wine_id in (select wine_id from posseduta)
    order by s.wine_id, s.formato, s.observed_at desc, s.created_at desc
  )
  select coalesce(jsonb_agg(riga order by ordinamento, riga->>'bottleUnitId'), '[]'::jsonb)
  into v_posizioni
  from (
    select coalesce(a.paid_at, p.acquired_at) as ordinamento, jsonb_build_object(
      'bottleUnitId',        p.id,
      'wineId',              p.wine_id,
      'wineSlug',            w.slug,
      'produttore',          w.produttore,
      'nome',                w.nome,
      'annata',              w.annata,
      'tipo',                w.tipo,
      'formato',             coalesce(nullif(btrim(w.formato), ''), '0,75 L'),
      'stato',               p.stato::text,
      -- Per una bottiglia comprata su Vinea l'acquisizione economica avviene al
      -- pagamento autorevole dell'ordine. Per le altre resta il fatto manuale o
      -- legacy della bottiglia.
      'acquiredAt',          coalesce(a.paid_at, p.acquired_at),
      -- `acquisto_vinea` è DERIVATO dal legame con l'ordine e non letto da una
      -- colonna: l'ordine è la sorgente autorevole, la colonna enum non la
      -- duplica. Vedi la REGOLA 2 in testa al file.
      'acquisizioneFonte',   case
                               when a.order_id is not null then 'acquisto_vinea'
                               else p.acquisition_fonte::text
                             end,
      -- Il costo manuale è deliberatamente azzerato a NULL quando la bottiglia
      -- viene da un acquisto Vinea: l'importo economico è già nel pagamento, e
      -- sommarli lo conterebbe due volte.
      'costoManualeCents',   case
                               when a.order_id is not null then null
                               else p.acquisition_cost_cents
                             end,
      'ordineAcquistoId',    a.order_id,
      'acquistoPrezzoVenditoreCents', a.prezzo_venditore_cents,
      'acquistoLordoCents',  a.pagato_lordo_cents,
      'acquistoRimborsoCents', a.rimborsato_cents,
      'acquistoNettoCents',  a.esborso_netto_cents,
      'ordineVenditaId',     v.order_id,
      'venditaStato',        v.order_stato,
      'venditaPayoutStato',  v.payout_stato,
      'venditaIncassoCents', v.incassato_cents,
      'venditaIncassoAt',    v.incassato_at,
      'cedutaAt',            p.ceduta_at,
      'deletedAt',           p.deleted_at,
      'consumedAt',          p.consumed_at,
      'riferimentoCents',    r.mediana_cents,
      -- NULL significa che per questo vino/formato non esiste ancora alcuno
      -- snapshot reale. Zero resta riservato a una misurazione avvenuta con zero
      -- comparabili dopo l'apertura della serie.
      'riferimentoComparabili', r.comparabili,
      'riferimentoAt',       r.observed_at
    ) as riga
    from posseduta p
    join public.wines w on w.id = p.wine_id
    left join acquisto a on a.bottle_unit_id = p.id
    left join vendita  v on v.bottle_unit_id = p.id
    left join riferimento r
      on r.wine_id = p.wine_id
     and r.formato = coalesce(nullif(btrim(w.formato), ''), '0,75 L')
  ) as righe;

  select coalesce(jsonb_agg(riga order by ordinamento), '[]'::jsonb)
  into v_storico
  from (
    select s.observed_at as ordinamento, jsonb_build_object(
      'wineId',       s.wine_id,
      'formato',      s.formato,
      'medianaCents', s.mediana_cents,
      'comparabili',  s.comparabili,
      'observedAt',   s.observed_at
    ) as riga
    from public.wine_reference_snapshots s
    where s.wine_id in (
      select bu.wine_id
      from public.bottle_units bu
      where bu.owner_id = v_uid
    )
  ) as serie;

  return jsonb_build_object(
    'generatoAt', now(),
    'posizioni',  coalesce(v_posizioni, '[]'::jsonb),
    'storico',    coalesce(v_storico, '[]'::jsonb)
  );
end;
$$;


ALTER FUNCTION "public"."cellar_portfolio_analitica"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cellar_portfolio_analitica"() IS 'Unica porta di lettura dell''analitica di Cantina del proprietario autenticato: posizioni con costo, esborso, incasso trasferito, ciclo di vita e riferimento corrente, più lo storico del riferimento dei suoi vini. Owner-only via auth.uid(); nessun parametro di proprietà; elenco di campi chiuso perché legge pagamenti e payout in SECURITY DEFINER.';



CREATE OR REPLACE FUNCTION "public"."cellar_posiziona"("p_bottle_unit_id" "uuid", "p_module_id" "uuid", "p_riga" integer, "p_colonna" integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid      uuid := auth.uid();
  v_owner    uuid;
  v_deleted  timestamptz;
  v_ceduta   timestamptz;
  v_righe    smallint;
  v_colonne  smallint;
begin
  if v_uid is null then
    raise exception 'Devi accedere per spostare una bottiglia.' using errcode = '42501';
  end if;

  select bu.owner_id, bu.deleted_at, bu.ceduta_at
  into v_owner, v_deleted, v_ceduta
  from public.bottle_units bu
  where bu.id = p_bottle_unit_id
  for update;

  if v_owner is null or v_owner is distinct from v_uid
     or v_deleted is not null or v_ceduta is not null then
    raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
  end if;

  select m.righe, m.colonne
  into v_righe, v_colonne
  from public.cellar_modules m
    join public.cellar_environments e on e.id = m.environment_id
  where m.id = p_module_id
    and e.owner_id = v_uid;

  if v_righe is null then
    raise exception 'Questo scaffale non è nella tua cantina.' using errcode = '42501';
  end if;
  if p_riga is null or p_riga < 0 or p_riga >= v_righe then
    raise exception 'Riga fuori dallo scaffale: ne ha %.', v_righe using errcode = 'P0001';
  end if;
  if p_colonna is null or p_colonna < 0 or p_colonna >= v_colonne then
    raise exception 'Colonna fuori dallo scaffale: ne ha %.', v_colonne using errcode = 'P0001';
  end if;

  begin
    insert into public.cellar_slots (module_id, bottle_unit_id, riga, colonna)
    values (p_module_id, p_bottle_unit_id, p_riga::smallint, p_colonna::smallint)
    on conflict (bottle_unit_id) do update
      set module_id = excluded.module_id,
          riga = excluded.riga,
          colonna = excluded.colonna;
  exception
    when unique_violation then
      raise exception 'In quella posizione c''è già una bottiglia.' using errcode = 'P0001';
  end;
end;
$$;


ALTER FUNCTION "public"."cellar_posiziona"("p_bottle_unit_id" "uuid", "p_module_id" "uuid", "p_riga" integer, "p_colonna" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cellar_posiziona"("p_bottle_unit_id" "uuid", "p_module_id" "uuid", "p_riga" integer, "p_colonna" integer) IS 'Colloca o sposta una bottiglia in una posizione dello scaffale. Verifica che bottiglia e scaffale siano di chi chiama e che la posizione esista davvero nella geometria del modulo.';



CREATE OR REPLACE FUNCTION "public"."cellar_togli_posizione"("p_bottle_unit_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid     uuid := auth.uid();
  v_owner   uuid;
  v_deleted timestamptz;
  v_ceduta  timestamptz;
begin
  if v_uid is null then
    raise exception 'Devi accedere per spostare una bottiglia.' using errcode = '42501';
  end if;

  select bu.owner_id, bu.deleted_at, bu.ceduta_at
  into v_owner, v_deleted, v_ceduta
  from public.bottle_units bu
  where bu.id = p_bottle_unit_id
  for update;

  if v_owner is null or v_owner is distinct from v_uid
     or v_deleted is not null or v_ceduta is not null then
    raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
  end if;

  delete from public.cellar_slots
  where bottle_unit_id = p_bottle_unit_id;
end;
$$;


ALTER FUNCTION "public"."cellar_togli_posizione"("p_bottle_unit_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cellar_togli_posizione"("p_bottle_unit_id" "uuid") IS 'Toglie una bottiglia dalla sua posizione, lasciandola in cantina senza collocazione. Non cancella la bottiglia.';



CREATE TABLE IF NOT EXISTS "public"."clubs" (
    "slug" "text" NOT NULL,
    "nome" "text" NOT NULL,
    "territorio" "text",
    "denominazione" "text",
    "produttore" "text",
    "tipologia" "text",
    "descrizione" "text" NOT NULL,
    "regole" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "owner_id" "uuid",
    "posting_mode" "text" DEFAULT 'OPEN'::"text" NOT NULL,
    "cover_image" "text",
    CONSTRAINT "clubs_cover_image_vinea_check" CHECK ((("cover_image" IS NULL) OR ("cover_image" = ''::"text") OR ("cover_image" ~ (('^'::"text" || (COALESCE("owner_id", '00000000-0000-0000-0000-000000000000'::"uuid"))::"text") || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.webp$'::"text")))),
    CONSTRAINT "clubs_denominazione_check" CHECK ((("denominazione" IS NULL) OR (("length"("btrim"("denominazione")) >= 2) AND ("length"("btrim"("denominazione")) <= 120)))),
    CONSTRAINT "clubs_descrizione_check" CHECK ((("length"("btrim"("descrizione")) >= 10) AND ("length"("btrim"("descrizione")) <= 2000))),
    CONSTRAINT "clubs_nome_check" CHECK ((("length"("btrim"("nome")) >= 2) AND ("length"("btrim"("nome")) <= 120))),
    CONSTRAINT "clubs_posting_mode_check" CHECK (("posting_mode" = ANY (ARRAY['OPEN'::"text", 'OWNER_ONLY'::"text"]))),
    CONSTRAINT "clubs_produttore_check" CHECK ((("produttore" IS NULL) OR (("length"("btrim"("produttore")) >= 2) AND ("length"("btrim"("produttore")) <= 120)))),
    CONSTRAINT "clubs_regole_check" CHECK ((("array_position"("regole", NULL::"text") IS NULL) AND ("cardinality"("regole") <= 20))),
    CONSTRAINT "clubs_slug_check" CHECK ((("slug" ~ '^[a-z0-9]+(-[a-z0-9]+)*$'::"text") AND (("length"("slug") >= 2) AND ("length"("slug") <= 80)))),
    CONSTRAINT "clubs_territorio_check" CHECK ((("territorio" IS NULL) OR (("length"("btrim"("territorio")) >= 2) AND ("length"("btrim"("territorio")) <= 80)))),
    CONSTRAINT "clubs_tipologia_check" CHECK ((("tipologia" IS NULL) OR (("length"("btrim"("tipologia")) >= 2) AND ("length"("btrim"("tipologia")) <= 40))))
);


ALTER TABLE "public"."clubs" OWNER TO "postgres";


COMMENT ON TABLE "public"."clubs" IS 'Club Vinea. Lettura pubblica attraverso public_clubs; nessun ruolo client ha grant su questa tabella, in lettura o in scrittura. Le righe le scrive service_role (fixture di seed), che e un''autorizzazione separata dal merge di questa migrazione.';



COMMENT ON COLUMN "public"."clubs"."regole" IS 'Regole del club, in ordine di inserimento. Nessun elemento null, massimo venti.';



COMMENT ON COLUMN "public"."clubs"."owner_id" IS 'Proprietario del club. Per club di sistema/legacy puo essere null. Per club utente
  viene valorizzato da club_crea con auth.uid().';



COMMENT ON COLUMN "public"."clubs"."posting_mode" IS 'OPEN: tutti gli utenti abilitati possono creare post e risposte.
   OWNER_ONLY: solo il proprietario puo creare post e risposte.
   Lettura, follow, like e moderazione sono invariati.';



COMMENT ON COLUMN "public"."clubs"."cover_image" IS 'Percorso nel bucket club-covers, formato <uid>/<uuid>.webp.
   Un club senza cover_image usa la UI generica.';



COMMENT ON CONSTRAINT "clubs_cover_image_vinea_check" ON "public"."clubs" IS 'La cover deve essere un percorso canonico nel bucket club-covers sotto la cartella
  del proprietario, oppure vuota (UI generica). I preset sono asset Vinea gestiti
  lato client e non finiscono in questo campo.';



CREATE OR REPLACE FUNCTION "public"."club_crea"("p_nome" "text", "p_descrizione" "text", "p_regole" "text"[] DEFAULT '{}'::"text"[], "p_posting_mode" "text" DEFAULT 'OPEN'::"text", "p_cover_image" "text" DEFAULT NULL::"text") RETURNS "public"."clubs"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
declare
  v_uid       uuid := auth.uid();
  v_stato     public.utente_stato;
  v_base      text;
  v_slug      text;
  v_n         integer;
  v_club      public.clubs;
begin
  -- 1. Utente autenticato
  if v_uid is null then
    raise exception 'Devi accedere per creare un club.' using errcode = '42501';
  end if;

  -- 2. Profilo esistente (come listing_crea)
  if not exists (select 1 from public.profiles p where p.id = v_uid) then
    raise exception 'Il tuo profilo non e ancora completo: completalo prima di creare un club.'
      using errcode = 'P0001';
  end if;

  -- 3. Primo livello della decisione 7.6b: creare un club e una scrittura
  -- sociale. Il trigger su club_memberships lo intercetterebbe comunque alla
  -- membership automatica, ma qui il rifiuto arriva PRIMA di aver creato il
  -- club, invece che dopo.
  v_stato := private.utente_stato_di(v_uid);
  if v_stato = 'sospeso' then
    raise exception 'Account sospeso: non puoi creare un club.'
      using errcode = '42501';
  elsif v_stato = 'rimosso' then
    raise exception 'Account rimosso.' using errcode = '42501';
  end if;

  -- 4. Rate limit, stessa convenzione di ogni scrittura social del progetto.
  -- 5 club/ora: creare un club e un evento raro e ponderato, non una battuta.
  perform private.rate_limit_consume('club:crea', 'user:' || v_uid::text, 5, 3600);

  -- 5. Validazione input
  if coalesce(trim(p_nome), '') = '' then
    raise exception 'Il nome del club e obbligatorio.' using errcode = 'P0001';
  end if;
  if length(trim(p_nome)) < 2 or length(trim(p_nome)) > 120 then
    raise exception 'Il nome deve essere compreso tra 2 e 120 caratteri.' using errcode = 'P0001';
  end if;

  if coalesce(trim(p_descrizione), '') = '' then
    raise exception 'La descrizione e obbligatoria.' using errcode = 'P0001';
  end if;
  if length(trim(p_descrizione)) < 10 or length(trim(p_descrizione)) > 2000 then
    raise exception 'La descrizione deve essere compresa tra 10 e 2000 caratteri.' using errcode = 'P0001';
  end if;

  if p_regole is null then
    p_regole := '{}'::text[];
  end if;
  if array_length(p_regole, 1) > 20 then
    raise exception 'Massimo 20 regole per club.' using errcode = 'P0001';
  end if;
  if array_position(p_regole, null::text) is not null then
    raise exception 'Le regole non possono contenere valori nulli.' using errcode = 'P0001';
  end if;

  -- posting_mode: solo OPEN o OWNER_ONLY
  if p_posting_mode not in ('OPEN', 'OWNER_ONLY') then
    raise exception 'Modalita di pubblicazione non valida: deve essere OPEN o OWNER_ONLY.' using errcode = 'P0001';
  end if;

  -- cover_image: se presente, deve essere un percorso canonico owner-bound
  if p_cover_image is not null and p_cover_image <> '' then
    if p_cover_image !~ ('^' || v_uid::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.webp$') then
      raise exception 'Cover non valida: deve essere un percorso WebP nella tua cartella club-covers.' using errcode = 'P0001';
    end if;
    -- Verifica che l'oggetto esista davvero nel bucket
    if not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'club-covers'
        and o.name = p_cover_image
        and (storage.foldername(o.name))[1] = v_uid::text
    ) then
      raise exception 'Cover non trovata nel bucket. Carica prima la foto.' using errcode = 'P0001';
    end if;
  end if;

  -- 6. Generazione slug server-side con risoluzione collisioni.
  --
  -- Si riusa public.slugifica(), gia usata da listing_crea: normalizza accenti
  -- e maiuscole insieme (`Barolo Club` -> `barolo-club`). Farlo a mano con un
  -- regexp_replace applicato prima di lower() distruggerebbe le maiuscole
  -- invece di abbassarle. La funzione e revocata da anon/authenticated, ma
  -- club_crea e SECURITY DEFINER e la puo chiamare.
  --
  -- Il suo fallback e 'annuncio', convenzione del dominio annunci: qui il
  -- fallback giusto e 'club'.
  v_base := public.slugifica(p_nome);
  if v_base = 'annuncio' and lower(trim(p_nome)) <> 'annuncio' then
    v_base := 'club';
  end if;

  -- La base si tronca PRIMA di aggiungere il suffisso, non dopo. Il CHECK su
  -- clubs.slug ferma a 80: troncare il risultato gia suffissato potrebbe
  -- tagliare via il suffisso stesso e lasciare il loop a riprovare per sempre
  -- lo stesso valore. 72 caratteri lasciano spazio a '-' piu sette cifre.
  if length(v_base) > 72 then
    v_base := trim(both '-' from substr(v_base, 1, 72));
  end if;
  if v_base = '' then
    v_base := 'club';
  end if;

  v_slug := v_base;
  v_n := 0;
  loop
    exit when not exists (select 1 from public.clubs where slug = v_slug);
    v_n := v_n + 1;
    if v_n > 9999999 then
      raise exception 'Non e stato possibile generare uno slug per questo nome.'
        using errcode = 'P0001';
    end if;
    v_slug := v_base || '-' || v_n;
  end loop;

  -- 7. Inserimento club + membership creatore (atomico)
  insert into public.clubs (
    slug, nome, descrizione, regole, owner_id, posting_mode, cover_image
  )
  values (
    v_slug, trim(p_nome), trim(p_descrizione), p_regole, v_uid, p_posting_mode, p_cover_image
  )
  returning * into v_club;

  -- Membership automatica per il creatore
  insert into public.club_memberships (user_id, club_slug)
  values (v_uid, v_slug)
  on conflict (user_id, club_slug) do nothing;

  return v_club;
end;
$_$;


ALTER FUNCTION "public"."club_crea"("p_nome" "text", "p_descrizione" "text", "p_regole" "text"[], "p_posting_mode" "text", "p_cover_image" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."club_crea"("p_nome" "text", "p_descrizione" "text", "p_regole" "text"[], "p_posting_mode" "text", "p_cover_image" "text") IS 'Crea un club utente: genera slug univoco, assegna owner_id = auth.uid(),
   inserisce membership automatica, valida cover_image come percorso canonico.
   Restituisce il club creato.';



CREATE TABLE IF NOT EXISTS "public"."orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "listing_id" "uuid" NOT NULL,
    "proposal_id" "uuid",
    "buyer_id" "uuid" NOT NULL,
    "seller_id" "uuid" NOT NULL,
    "seller_bottle_unit_id" "uuid" NOT NULL,
    "buyer_bottle_unit_id" "uuid",
    "stato" "public"."order_stato" DEFAULT 'in_attesa_pagamento'::"public"."order_stato" NOT NULL,
    "delivery_mode" "public"."delivery_mode" NOT NULL,
    "prezzo_cents" integer NOT NULL,
    "currency" "text" DEFAULT 'eur'::"text" NOT NULL,
    "idempotency_key" "text" NOT NULL,
    "reservation_expires_at" timestamp with time zone NOT NULL,
    "paid_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "margine_obiettivo_bps" integer DEFAULT 0 NOT NULL,
    "riferimento_stripe_percentuale_bps" integer DEFAULT 0 NOT NULL,
    "riferimento_stripe_fisso_cents" integer DEFAULT 0 NOT NULL,
    "commissione_cents" integer DEFAULT 0 NOT NULL,
    "payout_stato" "public"."payout_stato" DEFAULT 'trattenuto'::"public"."payout_stato" NOT NULL,
    "consegnato_at" timestamp with time zone,
    "auto_rilascio_scadenza" timestamp with time zone,
    "ricezione_confermata_at" timestamp with time zone,
    "contestato_at" timestamp with time zone,
    "contestazione_motivo" "text",
    "totale_cents" integer GENERATED ALWAYS AS (("prezzo_cents" + "commissione_cents")) STORED,
    "preparazione_avviata_at" timestamp with time zone,
    "spedito_at" timestamp with time zone,
    "corriere" "text",
    "tracking_number" "text",
    "imballaggio_checklist" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "imballaggio_foto" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "imballaggio_codice" "text",
    "imballaggio_provider" "text",
    "imballaggio_etichetta" "text",
    "imballaggio_cents" integer DEFAULT 0 NOT NULL,
    "imballaggio_punto_id" "text",
    "imballaggio_punto_nome" "text",
    "imballaggio_scelto_at" timestamp with time zone,
    "addebito_totale_cents" integer GENERATED ALWAYS AS ((("prezzo_cents" + "commissione_cents") + "imballaggio_cents")) STORED,
    CONSTRAINT "orders_commissione_cents_check" CHECK (("commissione_cents" >= 0)),
    CONSTRAINT "orders_contestazione_motivo_check" CHECK ((("contestazione_motivo" IS NULL) OR (("length"("contestazione_motivo") >= 3) AND ("length"("contestazione_motivo") <= 1000)))),
    CONSTRAINT "orders_corriere_check" CHECK ((("corriere" IS NULL) OR (("length"("corriere") >= 2) AND ("length"("corriere") <= 60)))),
    CONSTRAINT "orders_currency_check" CHECK (("currency" = 'eur'::"text")),
    CONSTRAINT "orders_idempotency_key_check" CHECK (((("length"("idempotency_key") >= 8) AND ("length"("idempotency_key") <= 128)) AND ("idempotency_key" ~ '^[A-Za-z0-9._:-]+$'::"text"))),
    CONSTRAINT "orders_imballaggio_cents_check" CHECK ((("imballaggio_cents" >= 0) AND ("imballaggio_cents" <= 100000))),
    CONSTRAINT "orders_imballaggio_checklist_check" CHECK ((("jsonb_typeof"("imballaggio_checklist") = 'array'::"text") AND ("jsonb_array_length"("imballaggio_checklist") <= 12))),
    CONSTRAINT "orders_imballaggio_congelato" CHECK ((("imballaggio_codice" IS NULL) = (("imballaggio_etichetta" IS NULL) AND ("imballaggio_provider" IS NULL) AND ("imballaggio_scelto_at" IS NULL)))),
    CONSTRAINT "orders_imballaggio_costo_solo_se_scelto" CHECK ((("imballaggio_codice" IS NOT NULL) OR ("imballaggio_cents" = 0))),
    CONSTRAINT "orders_imballaggio_foto_check" CHECK (("cardinality"("imballaggio_foto") <= 8)),
    CONSTRAINT "orders_imballaggio_punto_id_check" CHECK ((("imballaggio_punto_id" IS NULL) OR (("length"("imballaggio_punto_id") >= 1) AND ("length"("imballaggio_punto_id") <= 80)))),
    CONSTRAINT "orders_imballaggio_punto_nome_check" CHECK ((("imballaggio_punto_nome" IS NULL) OR ("length"("imballaggio_punto_nome") <= 160))),
    CONSTRAINT "orders_imballaggio_punto_solo_se_scelto" CHECK ((("imballaggio_punto_id" IS NULL) OR ("imballaggio_codice" IS NOT NULL))),
    CONSTRAINT "orders_margine_obiettivo_bps_check" CHECK ((("margine_obiettivo_bps" >= 0) AND ("margine_obiettivo_bps" <= 5000))),
    CONSTRAINT "orders_parti_distinte" CHECK (("buyer_id" <> "seller_id")),
    CONSTRAINT "orders_prezzo_cents_check" CHECK (("prezzo_cents" > 0)),
    CONSTRAINT "orders_riferimento_stripe_fisso_cents_check" CHECK ((("riferimento_stripe_fisso_cents" >= 0) AND ("riferimento_stripe_fisso_cents" <= 10000))),
    CONSTRAINT "orders_riferimento_stripe_percentuale_bps_check" CHECK ((("riferimento_stripe_percentuale_bps" >= 0) AND ("riferimento_stripe_percentuale_bps" <= 5000))),
    CONSTRAINT "orders_spedizione_coerente" CHECK ((("spedito_at" IS NULL) OR (("corriere" IS NOT NULL) AND ("tracking_number" IS NOT NULL)))),
    CONSTRAINT "orders_tracking_number_check" CHECK ((("tracking_number" IS NULL) OR ("tracking_number" ~ '^[A-Za-z0-9._-]{4,64}$'::"text")))
);


ALTER TABLE "public"."orders" OWNER TO "postgres";


COMMENT ON COLUMN "public"."orders"."prezzo_cents" IS 'Quanto incassa il venditore. La commissione sta sopra, non dentro.';



COMMENT ON COLUMN "public"."orders"."margine_obiettivo_bps" IS 'Margine netto obiettivo, in punti base, congelato alla creazione. Una modifica successiva di marketplace_config non tocca questa riga.';



COMMENT ON COLUMN "public"."orders"."riferimento_stripe_percentuale_bps" IS 'Quota percentuale della fee di riferimento usata per calcolare il rincaro di QUESTO ordine. Serve a spiegarlo dopo, non a ricalcolarlo.';



COMMENT ON COLUMN "public"."orders"."riferimento_stripe_fisso_cents" IS 'Quota fissa della fee di riferimento usata per questo ordine. È ciò che rende la percentuale effettiva più alta sui prezzi bassi.';



COMMENT ON COLUMN "public"."orders"."commissione_cents" IS 'Rincaro effettivo in centesimi, calcolato una volta e mai ricalcolato. La percentuale effettiva è un rapporto derivabile, non una colonna.';



COMMENT ON COLUMN "public"."orders"."auto_rilascio_scadenza" IS 'Istante oltre il quale il rilascio avviene senza conferma del compratore. Calcolato alla consegna dalla configurazione allora in vigore.';



COMMENT ON COLUMN "public"."orders"."totale_cents" IS 'Prezzo + commissione. Base del calcolo di marketplace e della riconciliazione: l''imballaggio NON entra qui, mai.';



COMMENT ON COLUMN "public"."orders"."preparazione_avviata_at" IS 'Istante in cui il venditore ha aperto la preparazione. È ciò che distingue il seller status «nuovo» da «da_preparare», che in frontend/ erano due etichette per lo stesso stato raggiungibile.';



COMMENT ON COLUMN "public"."orders"."imballaggio_foto" IS 'Chiavi di oggetti Storage, mai URL: un URL firmato scade e non è un dato.';



COMMENT ON COLUMN "public"."orders"."imballaggio_punto_id" IS 'Punto fisico scelto dal venditore DOPO il pagamento. Non ha prezzo, quindi sceglierlo non muove alcun importo.';



COMMENT ON COLUMN "public"."orders"."addebito_totale_cents" IS 'Quanto viene effettivamente addebitato al compratore: totale di mercato più l''imballaggio scelto. È questo il numero della riga payments.';



CREATE OR REPLACE FUNCTION "public"."conferma_ricezione"("p_order_id" "uuid") RETURNS "public"."orders"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;

  -- Aggiunta di questa estensione. Il compratore rimosso non conferma: alla
  -- scadenza ci pensa public.ordine_auto_rilascio_esegui, che non guarda
  -- stato_utente e non deve iniziare a guardarlo.
  if private.utente_stato_di(v_uid) = 'rimosso' then
    raise exception 'Account rimosso.' using errcode = '42501';
  end if;

  perform private.rate_limit_consume('order:confirm', 'user:' || v_uid::text, 20, 60);

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.buyer_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;
  if v_order.contestato_at is not null then
    raise exception 'Un ordine contestato non può essere confermato.' using errcode = 'P0001';
  end if;
  -- Idempotente: riconfermare non crea un secondo rilascio.
  if v_order.ricezione_confermata_at is not null then return v_order; end if;
  if v_order.stato not in ('pagato', 'in_preparazione', 'spedito', 'consegnato', 'verifica') then
    raise exception 'Questo ordine non è in uno stato confermabile.' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.payments p
    where p.order_id = v_order.id and p.stato = 'paid'
  ) then
    raise exception 'Il pagamento di questo ordine non risulta incassato.' using errcode = 'P0001';
  end if;
  if v_order.payout_stato <> 'trattenuto' then
    raise exception 'I fondi di questo ordine non sono più trattenuti.' using errcode = 'P0001';
  end if;

  update public.orders set
    stato = 'completato',
    ricezione_confermata_at = now(),
    payout_stato = 'in_attesa'
  where id = v_order.id returning * into v_order;

  insert into public.order_events (order_id, tipo, payload)
  values (v_order.id, 'ricezione_confermata', jsonb_build_object('origine', 'compratore'));
  return v_order;
end;
$$;


ALTER FUNCTION "public"."conferma_ricezione"("p_order_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."conferma_ricezione"("p_order_id" "uuid") IS 'Conferma del compratore, con il blocco per account rimosso aggiunto dall''estensione della Fase 9. Le altre transizioni manuali sull''ordine restano aperte per non impedire a un ordine gia pagato di arrivare al rilascio.';



CREATE OR REPLACE FUNCTION "public"."conversation_mark_read"("p_conversation_id" "uuid", "p_message_id" "uuid" DEFAULT NULL::"uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_message public.messages%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.conversation_participants cp
    where cp.conversation_id = p_conversation_id
      and cp.user_id = v_uid
  ) then
    raise exception 'Conversazione non trovata.' using errcode = '42501';
  end if;

  if p_message_id is null then
    select * into v_message
    from public.messages m
    where m.conversation_id = p_conversation_id
    order by m.created_at desc, m.id desc
    limit 1;
    if not found then
      return;
    end if;
  else
    select * into v_message
    from public.messages m
    where m.conversation_id = p_conversation_id
      and m.id = p_message_id;
    if not found then
      raise exception 'Messaggio non trovato.' using errcode = 'P0001';
    end if;
  end if;

  update public.conversation_participants cp
  set last_read_message_id = v_message.id,
      last_read_created_at = v_message.created_at
  where cp.conversation_id = p_conversation_id
    and cp.user_id = v_uid
    and (
      cp.last_read_created_at is null
      or (v_message.created_at, v_message.id) >
        (cp.last_read_created_at, cp.last_read_message_id)
    );
end;
$$;


ALTER FUNCTION "public"."conversation_mark_read"("p_conversation_id" "uuid", "p_message_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."conversation_open"("p_listing_id" "uuid" DEFAULT NULL::"uuid", "p_order_id" "uuid" DEFAULT NULL::"uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_listing public.listings%rowtype;
  v_order public.orders%rowtype;
  v_low uuid;
  v_high uuid;
  v_conversation_id uuid;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if (p_listing_id is null) = (p_order_id is null) then
    raise exception 'Indica un solo annuncio oppure un solo ordine.'
      using errcode = '22023';
  end if;

  if p_order_id is not null then
    select * into v_order
    from public.orders
    where id = p_order_id;

    if not found or v_uid not in (v_order.buyer_id, v_order.seller_id) then
      raise exception 'Ordine non trovato.' using errcode = '42501';
    end if;

    select * into v_listing
    from public.listings
    where id = v_order.listing_id;
    v_low := least(v_order.buyer_id, v_order.seller_id);
    v_high := greatest(v_order.buyer_id, v_order.seller_id);
  else
    select * into v_listing
    from public.listings
    where id = p_listing_id;

    if not found then
      raise exception 'Annuncio non trovato.' using errcode = 'P0001';
    end if;
    if v_listing.seller_id = v_uid then
      raise exception 'Non puoi aprire una chat con te stesso.'
        using errcode = 'P0001';
    end if;

    v_low := least(v_uid, v_listing.seller_id);
    v_high := greatest(v_uid, v_listing.seller_id);
  end if;

  perform pg_advisory_xact_lock(
    hashtext(
      'conversation:' || v_listing.id::text || ':' ||
      v_low::text || ':' || v_high::text
    )
  );

  select c.id into v_conversation_id
  from public.conversations c
  where c.listing_id = v_listing.id
    and c.participant_low = v_low
    and c.participant_high = v_high;

  if found then
    if p_order_id is not null then
      v_conversation_id := private.conversation_create(
        v_listing.id, p_order_id, v_low, v_high
      );
    end if;
    return v_conversation_id;
  end if;

  if p_order_id is null then
    if v_listing.stato <> 'attivo'
       or (v_listing.expires_at is not null and v_listing.expires_at <= now()) then
      raise exception 'Questo annuncio non e disponibile.' using errcode = 'P0001';
    end if;
  elsif v_order.stato in ('completato', 'rimborsato', 'annullato') then
    raise exception 'Questo ordine e concluso.' using errcode = 'P0001';
  end if;

  perform private.rate_limit_consume(
    'conversation:open', 'user:' || v_uid::text, 20, 60
  );

  return private.conversation_create(
    v_listing.id, p_order_id, v_low, v_high
  );
end;
$$;


ALTER FUNCTION "public"."conversation_open"("p_listing_id" "uuid", "p_order_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."conversations_page"("p_before_activity_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_before_id" "uuid" DEFAULT NULL::"uuid", "p_limit" integer DEFAULT 30) RETURNS TABLE("conversation_id" "uuid", "listing_id" "uuid", "listing_slug" "text", "listing_price_cents" integer, "order_id" "uuid", "counterpart_id" "uuid", "counterpart_username" "text", "counterpart_avatar_url" "text", "wine_name" "text", "wine_image" "text", "order_status" "text", "writable" boolean, "last_message_id" "uuid", "last_message_at" timestamp with time zone, "last_message_preview" "text", "unread_count" bigint, "activity_at" timestamp with time zone, "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if private.utente_stato_di(v_uid) = 'rimosso' then
    raise exception 'Account rimosso.' using errcode = '42501';
  end if;
  if p_limit not between 1 and 50
     or ((p_before_activity_at is null) <> (p_before_id is null)) then
    raise exception 'Cursore non valido.' using errcode = '22023';
  end if;

  return query
  select
    c.id,
    c.listing_id,
    l.slug,
    l.prezzo_cents,
    c.order_id,
    counterpart.id,
    counterpart.username,
    counterpart.avatar_url,
    w.produttore || ' ' || w.nome,
    coalesce(l.immagini[1], ''),
    o.stato::text,
    private.conversation_is_writable(c.id),
    c.last_message_id,
    c.last_message_at,
    lm.body,
    (
      select count(*)
      from public.messages unread
      where unread.conversation_id = c.id
        and unread.sender_id is distinct from v_uid
        and (
          cp.last_read_created_at is null
          or (unread.created_at, unread.id) >
            (cp.last_read_created_at, cp.last_read_message_id)
        )
    ),
    coalesce(c.last_message_at, c.created_at),
    c.created_at
  from public.conversations c
  join public.conversation_participants cp
    on cp.conversation_id = c.id and cp.user_id = v_uid
  join public.profiles counterpart
    on counterpart.id = case
      when c.participant_low = v_uid then c.participant_high
      else c.participant_low
    end
  join public.listings l on l.id = c.listing_id
  join public.bottle_units bu on bu.id = l.bottle_unit_id
  join public.wines w on w.id = bu.wine_id
  left join public.orders o on o.id = c.order_id
  left join public.messages lm on lm.id = c.last_message_id
  where p_before_activity_at is null
     or (coalesce(c.last_message_at, c.created_at), c.id)
          < (p_before_activity_at, p_before_id)
  order by coalesce(c.last_message_at, c.created_at) desc, c.id desc
  limit p_limit;
end;
$$;


ALTER FUNCTION "public"."conversations_page"("p_before_activity_at" timestamp with time zone, "p_before_id" "uuid", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  base_username text;
  candidato text;
  tentativo int := 0;
begin
  base_username := coalesce(
    nullif(new.raw_user_meta_data ->> 'username', ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'utente'
  );

  candidato := base_username;
  while exists (
    select 1
    from public.profiles
    where lower(username) = lower(candidato)
  ) loop
    tentativo := tentativo + 1;
    candidato := base_username || '_' || tentativo::text;
  end loop;

  insert into public.profiles (id, username, dob)
  values (
    new.id,
    candidato,
    -- NULL per gli accessi OAuth: la data verrà dichiarata da
    -- /completa-profilo prima di poter usare il resto del sito.
    nullif(new.raw_user_meta_data ->> 'dob', '')::date
  );
  return new;
end;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."has_role"("p_user_id" "uuid", "p_role" "text") RETURNS boolean
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select
    (select auth.uid()) is not null
    and p_user_id = (select auth.uid())
    and exists (
      select 1
      from public.user_roles ur
      where ur.user_id = p_user_id
        and ur.role = p_role
    );
$$;


ALTER FUNCTION "public"."has_role"("p_user_id" "uuid", "p_role" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."listing_crea"("p_produttore" "text" DEFAULT ''::"text", "p_nome" "text" DEFAULT ''::"text", "p_annata" integer DEFAULT NULL::integer, "p_regione" "text" DEFAULT ''::"text", "p_tipo" "text" DEFAULT NULL::"text", "p_prezzo_cents" integer DEFAULT NULL::integer, "p_condizione" "text" DEFAULT 'Ottimo'::"text", "p_conservazione" "text" DEFAULT ''::"text", "p_storia" "text" DEFAULT ''::"text", "p_immagini" "text"[] DEFAULT '{}'::"text"[], "p_bottle_unit_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("annuncio_id" "uuid", "annuncio_slug" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
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
$_$;


ALTER FUNCTION "public"."listing_crea"("p_produttore" "text", "p_nome" "text", "p_annata" integer, "p_regione" "text", "p_tipo" "text", "p_prezzo_cents" integer, "p_condizione" "text", "p_conservazione" "text", "p_storia" "text", "p_immagini" "text"[], "p_bottle_unit_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."listing_crea"("p_produttore" "text", "p_nome" "text", "p_annata" integer, "p_regione" "text", "p_tipo" "text", "p_prezzo_cents" integer, "p_condizione" "text", "p_conservazione" "text", "p_storia" "text", "p_immagini" "text"[], "p_bottle_unit_id" "uuid") IS 'Crea un annuncio in stato bozza. Senza p_bottle_unit_id conia anche vino (se manca) e unità fisica; con p_bottle_unit_id riusa un''unità già in cantina, dopo lock di riga e verifica di proprietà, stato fisico, cancellazione, cessione e assenza di altri annunci non terminali. Richiede un profilo con data di nascita dichiarata e maggiore età. Venditore e proprietario sono sempre auth.uid(). Non pubblica: la pubblicazione è listing_pubblica().';



CREATE OR REPLACE FUNCTION "public"."listing_crea_da_bottiglia"("p_bottle_unit_id" "uuid", "p_prezzo_cents" integer, "p_condizione" "text" DEFAULT 'Ottimo'::"text", "p_conservazione" "text" DEFAULT ''::"text", "p_storia" "text" DEFAULT ''::"text", "p_immagini" "text"[] DEFAULT '{}'::"text"[]) RETURNS TABLE("annuncio_id" "uuid", "annuncio_slug" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select *
  from public.listing_crea(
    p_prezzo_cents := p_prezzo_cents,
    p_condizione := p_condizione,
    p_conservazione := p_conservazione,
    p_storia := p_storia,
    p_immagini := p_immagini,
    p_bottle_unit_id := p_bottle_unit_id
  );
$$;


ALTER FUNCTION "public"."listing_crea_da_bottiglia"("p_bottle_unit_id" "uuid", "p_prezzo_cents" integer, "p_condizione" "text", "p_conservazione" "text", "p_storia" "text", "p_immagini" "text"[]) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."listing_crea_da_bottiglia"("p_bottle_unit_id" "uuid", "p_prezzo_cents" integer, "p_condizione" "text", "p_conservazione" "text", "p_storia" "text", "p_immagini" "text"[]) IS 'Unica porta client per creare una bozza di vendita: richiede una bottle_unit esistente e delega lock, ownership, età e invarianti alla funzione 6d-1.';



CREATE OR REPLACE FUNCTION "public"."listing_imballaggio_dichiara"("p_listing_id" "uuid", "p_codice" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_listing public.listings%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  perform private.rate_limit_consume('listing:packaging', 'user:' || v_uid::text, 30, 60);

  select * into v_listing from public.listings where id = p_listing_id for update;
  if not found or v_listing.seller_id <> v_uid then
    raise exception 'Annuncio non trovato.' using errcode = '42501';
  end if;
  if v_listing.stato in ('venduto', 'scaduto') then
    raise exception 'Questo annuncio non è più modificabile.' using errcode = 'P0001';
  end if;

  if p_codice is not null and not exists (
    select 1 from public.packaging_options po
    where po.codice = p_codice and po.valida_fino is null
  ) then
    raise exception 'Modalità di imballaggio non disponibile.' using errcode = '22023';
  end if;

  update public.listings set imballaggio_codice = p_codice where id = v_listing.id;
end;
$$;


ALTER FUNCTION "public"."listing_imballaggio_dichiara"("p_listing_id" "uuid", "p_codice" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."listing_pubblica"("p_listing_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."listing_pubblica"("p_listing_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."listing_pubblica"("p_listing_id" "uuid") IS 'Porta un annuncio del venditore da bozza (o modifiche_richieste) ad attivo, dopo cancello età e ricontrollo con lock della bottiglia, che fra la bozza e la pubblicazione può essere stata aperta o tolta dalla cantina. Traduce la violazione dell''indice non-terminale in un messaggio leggibile.';



CREATE OR REPLACE FUNCTION "public"."listing_scadi"("p_listing_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."listing_scadi"("p_listing_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."listing_scadi"("p_listing_id" "uuid") IS 'Porta ad esaurito un annuncio la cui expires_at è già passata. Rifiuta se la scadenza è nel futuro: non è una via di ritiro anticipato.';



CREATE OR REPLACE FUNCTION "public"."listing_sospendi"("p_listing_id" "uuid", "p_motivo" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."listing_sospendi"("p_listing_id" "uuid", "p_motivo" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."listing_sospendi"("p_listing_id" "uuid", "p_motivo" "text") IS 'Sospensione decisa dal venditore sul proprio annuncio attivo. La sospensione di moderazione è Fase 9 e avrà una funzione separata con controllo has_role().';



CREATE OR REPLACE FUNCTION "public"."listings_bottiglia_idonea"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
declare
  v_owner   uuid;
  v_stato   public.bottle_unit_stato;
  v_deleted timestamptz;
  v_ceduta  timestamptz;
begin
  select bu.owner_id, bu.stato, bu.deleted_at, bu.ceduta_at
  into v_owner, v_stato, v_deleted, v_ceduta
  from public.bottle_units bu
  where bu.id = new.bottle_unit_id;

  if not found then
    raise exception 'Questa bottiglia non esiste.' using errcode = 'P0001';
  end if;

  if v_owner is distinct from new.seller_id then
    raise exception 'Il venditore deve essere il proprietario della bottiglia.'
      using errcode = '42501';
  end if;

  if new.stato not in (
    'bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato'
  ) then
    return new;
  end if;

  if v_deleted is not null then
    raise exception 'Questa bottiglia non Ã¨ piÃ¹ nella tua cantina.'
      using errcode = 'P0001';
  end if;
  if v_ceduta is not null then
    raise exception 'Questa bottiglia Ã¨ giÃ  stata venduta: non puÃ² tornare in vendita.'
      using errcode = 'P0001';
  end if;
  if v_stato <> 'chiusa' then
    raise exception 'Una bottiglia % non si puÃ² mettere in vendita.', v_stato
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."listings_bottiglia_idonea"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."listings_bottiglia_idonea"() IS 'Garantisce seller_id = bottle_units.owner_id e, per gli annunci non terminali, richiede una bottiglia chiusa, presente e non ceduta.';



CREATE OR REPLACE FUNCTION "public"."listings_marca_bottiglia_ceduta"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if new.stato = 'venduto'
     and (tg_op = 'INSERT' or old.stato is distinct from 'venduto') then
    update public.bottle_units
    set ceduta_at = coalesce(ceduta_at, now())
    where id = new.bottle_unit_id;

    delete from public.cellar_slots
    where bottle_unit_id = new.bottle_unit_id;
  end if;

  return null;
end;
$$;


ALTER FUNCTION "public"."listings_marca_bottiglia_ceduta"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."listings_marca_bottiglia_ceduta"() IS 'All''ingresso in venduto valorizza ceduta_at senza spostarne la prima data e libera l''eventuale cellar_slot della bottiglia.';



CREATE OR REPLACE FUNCTION "public"."message_send"("p_conversation_id" "uuid", "p_text" "text", "p_idempotency_key" "uuid") RETURNS TABLE("id" "uuid", "conversation_id" "uuid", "sender_id" "uuid", "kind" "public"."message_kind", "body" "text", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_text text := btrim(coalesce(p_text, ''));
  v_existing public.messages%rowtype;
  v_inserted public.messages%rowtype;
  v_recipient uuid;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if p_conversation_id is null or p_idempotency_key is null
     or length(v_text) not between 1 and 2000 then
    raise exception 'Messaggio non valido.' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(
      'message:' || p_conversation_id::text || ':' || p_idempotency_key::text
    )
  );

  select * into v_existing
  from public.messages m
  where m.conversation_id = p_conversation_id
    and m.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.kind <> 'user'
       or v_existing.sender_id <> v_uid
       or v_existing.body <> v_text then
      raise exception 'Chiave idempotenza gia usata con un altro payload.'
        using errcode = '22023';
    end if;

    return query select
      v_existing.id,
      v_existing.conversation_id,
      v_existing.sender_id,
      v_existing.kind,
      v_existing.body,
      v_existing.created_at;
    return;
  end if;

  if not exists (
    select 1
    from public.conversation_participants cp
    where cp.conversation_id = p_conversation_id
      and cp.user_id = v_uid
  ) then
    raise exception 'Conversazione non trovata.' using errcode = '42501';
  end if;
  if not private.conversation_is_writable(p_conversation_id) then
    raise exception 'Questa conversazione e in sola lettura.' using errcode = 'P0001';
  end if;

  perform private.rate_limit_consume(
    'message:send', 'user:' || v_uid::text, 30, 60
  );
  perform private.rate_limit_consume(
    'message:send:conversation',
    'user:' || v_uid::text || ':conversation:' || p_conversation_id::text,
    10,
    10
  );

  -- Serializza anche chiavi diverse della stessa conversazione. Il trigger
  -- confronta comunque la tupla (created_at, id), come difesa in profondita.
  perform pg_advisory_xact_lock(
    hashtext('message-sequence:' || p_conversation_id::text)
  );

  insert into public.messages (
    conversation_id, sender_id, kind, body, idempotency_key
  ) values (
    p_conversation_id, v_uid, 'user', v_text, p_idempotency_key
  )
  returning * into v_inserted;

  select cp.user_id into v_recipient
  from public.conversation_participants cp
  where cp.conversation_id = p_conversation_id
    and cp.user_id <> v_uid;

  insert into public.notifications (
    recipient_id, category, event_type, body, dedupe_key,
    destination_kind, destination_conversation_id
  ) values (
    v_recipient,
    'marketplace',
    'new_message',
    'Hai ricevuto un nuovo messaggio.',
    'message:' || v_inserted.id::text,
    'conversation',
    p_conversation_id
  )
  on conflict (recipient_id, dedupe_key) do nothing;

  return query select
    v_inserted.id,
    v_inserted.conversation_id,
    v_inserted.sender_id,
    v_inserted.kind,
    v_inserted.body,
    v_inserted.created_at;
end;
$$;


ALTER FUNCTION "public"."message_send"("p_conversation_id" "uuid", "p_text" "text", "p_idempotency_key" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."messages_page"("p_conversation_id" "uuid", "p_before_created_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_before_id" "uuid" DEFAULT NULL::"uuid", "p_limit" integer DEFAULT 50) RETURNS TABLE("id" "uuid", "conversation_id" "uuid", "sender_id" "uuid", "kind" "public"."message_kind", "body" "text", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if private.utente_stato_di(v_uid) = 'rimosso' then
    raise exception 'Account rimosso.' using errcode = '42501';
  end if;
  if p_limit not between 1 and 100
     or ((p_before_created_at is null) <> (p_before_id is null)) then
    raise exception 'Cursore non valido.' using errcode = '22023';
  end if;
  if not exists (
    select 1
    from public.conversations c
    where c.id = p_conversation_id
      and v_uid in (c.participant_low, c.participant_high)
  ) then
    raise exception 'Conversazione non trovata.' using errcode = '42501';
  end if;

  return query
  select m.id, m.conversation_id, m.sender_id, m.kind, m.body, m.created_at
  from public.messages m
  where m.conversation_id = p_conversation_id
    and (
      p_before_created_at is null
      or (m.created_at, m.id) < (p_before_created_at, p_before_id)
    )
  order by m.created_at desc, m.id desc
  limit p_limit;
end;
$$;


ALTER FUNCTION "public"."messages_page"("p_conversation_id" "uuid", "p_before_created_at" timestamp with time zone, "p_before_id" "uuid", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."moderazione_ammonizione"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_report public.reports;
begin
  v_report := private.moderazione_pratica(
    p_report_id,
    'risolta'::public.report_stato,
    p_motivazione, p_nota_interna,
    'E stata inviata un''ammonizione'
  );

  perform private.audit_registra(
    p_attore_id => (select auth.uid()),
    p_azione => 'ammonizione'::public.mod_action,
    p_target_tipo => v_report.target_tipo,
    p_target_id => private.moderazione_bersaglio(v_report),
    p_target_label => v_report.target_label,
    p_motivazione => p_motivazione,
    p_report_id => p_report_id
  );
end;
$$;


ALTER FUNCTION "public"."moderazione_ammonizione"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."moderazione_annuncio_in_revisione"("p_listing_id" "uuid", "p_motivazione" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  perform private.moderazione_annuncio_transizione(
    private.moderazione_attore(), p_listing_id,
    'in_revisione'::public.listing_stato,
    'richiesta_modifiche'::public.mod_action,
    p_motivazione,
    array['bozza', 'modifiche_richieste', 'attivo', 'sospeso']::public.listing_stato[]
  );
end;
$$;


ALTER FUNCTION "public"."moderazione_annuncio_in_revisione"("p_listing_id" "uuid", "p_motivazione" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."moderazione_annuncio_modifiche_richieste"("p_listing_id" "uuid", "p_motivazione" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  perform private.moderazione_annuncio_transizione(
    private.moderazione_attore(), p_listing_id,
    'modifiche_richieste'::public.listing_stato,
    'richiesta_modifiche'::public.mod_action,
    p_motivazione,
    array['bozza', 'in_revisione', 'attivo']::public.listing_stato[]
  );
end;
$$;


ALTER FUNCTION "public"."moderazione_annuncio_modifiche_richieste"("p_listing_id" "uuid", "p_motivazione" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."moderazione_annuncio_rifiuta"("p_listing_id" "uuid", "p_motivazione" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  perform private.moderazione_annuncio_transizione(
    private.moderazione_attore(), p_listing_id,
    'rifiutato'::public.listing_stato,
    'rimozione'::public.mod_action,
    p_motivazione,
    array['bozza', 'in_revisione', 'modifiche_richieste', 'attivo',
          'sospeso']::public.listing_stato[]
  );
end;
$$;


ALTER FUNCTION "public"."moderazione_annuncio_rifiuta"("p_listing_id" "uuid", "p_motivazione" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."moderazione_annuncio_ripristina"("p_listing_id" "uuid", "p_motivazione" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  perform private.moderazione_annuncio_transizione(
    private.moderazione_attore(), p_listing_id,
    'attivo'::public.listing_stato,
    'ripristino'::public.mod_action,
    p_motivazione,
    array['in_revisione', 'modifiche_richieste', 'sospeso',
          'rifiutato']::public.listing_stato[]
  );
end;
$$;


ALTER FUNCTION "public"."moderazione_annuncio_ripristina"("p_listing_id" "uuid", "p_motivazione" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."moderazione_annuncio_sospendi"("p_listing_id" "uuid", "p_motivazione" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  perform private.moderazione_annuncio_transizione(
    private.moderazione_attore(), p_listing_id,
    'sospeso'::public.listing_stato,
    'sospensione'::public.mod_action,
    p_motivazione,
    array['bozza', 'in_revisione', 'modifiche_richieste',
          'attivo']::public.listing_stato[]
  );
end;
$$;


ALTER FUNCTION "public"."moderazione_annuncio_sospendi"("p_listing_id" "uuid", "p_motivazione" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."moderazione_annuncio_sospendi"("p_listing_id" "uuid", "p_motivazione" "text") IS 'Sospensione decisa da un moderatore. Funzione separata da public.listing_sospendi, che resta del venditore e del solo stato attivo: il commento della 6b (20260729112500, riga 333) prometteva esattamente questo.';



CREATE OR REPLACE FUNCTION "public"."moderazione_chiusura"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_report public.reports;
begin
  v_report := private.moderazione_pratica(
    p_report_id,
    'respinta'::public.report_stato,
    p_motivazione, p_nota_interna,
    'La segnalazione e stata chiusa senza provvedimenti'
  );

  perform private.audit_registra(
    p_attore_id => (select auth.uid()),
    p_azione => 'chiusura'::public.mod_action,
    p_target_tipo => v_report.target_tipo,
    p_target_id => private.moderazione_bersaglio(v_report),
    p_target_label => v_report.target_label,
    p_motivazione => p_motivazione,
    p_report_id => p_report_id
  );
end;
$$;


ALTER FUNCTION "public"."moderazione_chiusura"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."moderazione_info_richieste"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_report public.reports;
begin
  v_report := private.moderazione_pratica(
    p_report_id,
    'info_richieste'::public.report_stato,
    p_motivazione, p_nota_interna,
    'Sono state richieste ulteriori informazioni'
  );

  perform private.audit_registra(
    p_attore_id => (select auth.uid()),
    p_azione => 'info_richieste'::public.mod_action,
    p_target_tipo => v_report.target_tipo,
    p_target_id => private.moderazione_bersaglio(v_report),
    p_target_label => v_report.target_label,
    p_motivazione => p_motivazione,
    p_report_id => p_report_id
  );
end;
$$;


ALTER FUNCTION "public"."moderazione_info_richieste"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."moderazione_richiesta_modifiche"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_report public.reports;
  v_attore uuid;
begin
  v_report := private.moderazione_pratica(
    p_report_id,
    'in_revisione'::public.report_stato,
    p_motivazione, p_nota_interna,
    'Sono state richieste modifiche al contenuto segnalato'
  );
  v_attore := (select auth.uid());

  if v_report.target_tipo = 'annuncio' and v_report.target_listing_id is not null then
    perform private.moderazione_annuncio_transizione(
      v_attore, v_report.target_listing_id,
      'modifiche_richieste'::public.listing_stato,
      'richiesta_modifiche'::public.mod_action,
      p_motivazione,
      array['bozza', 'in_revisione', 'attivo']::public.listing_stato[],
      p_report_id
    );
  else
    perform private.audit_registra(
      p_attore_id => v_attore,
      p_azione => 'richiesta_modifiche'::public.mod_action,
      p_target_tipo => v_report.target_tipo,
      p_target_id => private.moderazione_bersaglio(v_report),
      p_target_label => v_report.target_label,
      p_motivazione => p_motivazione,
      p_report_id => p_report_id
    );
  end if;
end;
$$;


ALTER FUNCTION "public"."moderazione_richiesta_modifiche"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."moderazione_rimozione"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_report public.reports;
  v_attore uuid;
begin
  v_report := private.moderazione_pratica(
    p_report_id,
    'risolta'::public.report_stato,
    p_motivazione, p_nota_interna,
    'Il contenuto segnalato e stato rimosso'
  );
  v_attore := (select auth.uid());

  if v_report.target_tipo = 'profilo' and v_report.target_profile_id is not null then
    perform private.moderazione_utente_provvedimento(
      v_attore, v_report.target_profile_id, p_motivazione, null, p_report_id,
      true
    );
  elsif v_report.target_tipo = 'annuncio' and v_report.target_listing_id is not null then
    perform private.moderazione_annuncio_transizione(
      v_attore, v_report.target_listing_id,
      'rifiutato'::public.listing_stato,
      'rimozione'::public.mod_action,
      p_motivazione,
      array['bozza', 'in_revisione', 'modifiche_richieste', 'attivo',
            'sospeso']::public.listing_stato[],
      p_report_id
    );
  elsif v_report.target_tipo in ('post', 'commento') then
    perform private.moderazione_contenuto_club_transizione(
      v_attore, v_report, true, 'rimozione'::public.mod_action, p_motivazione
    );
  else
    perform private.audit_registra(
      p_attore_id => v_attore,
      p_azione => 'rimozione'::public.mod_action,
      p_target_tipo => v_report.target_tipo,
      p_target_id => private.moderazione_bersaglio(v_report),
      p_target_label => v_report.target_label,
      p_motivazione => p_motivazione,
      p_report_id => p_report_id
    );
  end if;
end;
$$;


ALTER FUNCTION "public"."moderazione_rimozione"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."moderazione_ripristino"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_report public.reports;
  v_attore uuid;
begin
  v_report := private.moderazione_pratica(
    p_report_id,
    'risolta'::public.report_stato,
    p_motivazione, p_nota_interna,
    'Il contenuto segnalato e stato ripristinato'
  );
  v_attore := (select auth.uid());

  if v_report.target_tipo = 'profilo' and v_report.target_profile_id is not null then
    perform private.moderazione_utente_ripristina(
      v_attore, v_report.target_profile_id, p_motivazione, p_report_id
    );
  elsif v_report.target_tipo = 'annuncio' and v_report.target_listing_id is not null then
    perform private.moderazione_annuncio_transizione(
      v_attore, v_report.target_listing_id,
      'attivo'::public.listing_stato,
      'ripristino'::public.mod_action,
      p_motivazione,
      array['in_revisione', 'modifiche_richieste', 'sospeso',
            'rifiutato']::public.listing_stato[],
      p_report_id
    );
  elsif v_report.target_tipo in ('post', 'commento') then
    perform private.moderazione_contenuto_club_transizione(
      v_attore, v_report, false, 'ripristino'::public.mod_action, p_motivazione
    );
  else
    perform private.audit_registra(
      p_attore_id => v_attore,
      p_azione => 'ripristino'::public.mod_action,
      p_target_tipo => v_report.target_tipo,
      p_target_id => private.moderazione_bersaglio(v_report),
      p_target_label => v_report.target_label,
      p_motivazione => p_motivazione,
      p_report_id => p_report_id
    );
  end if;
end;
$$;


ALTER FUNCTION "public"."moderazione_ripristino"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."moderazione_sospensione"("p_report_id" "uuid", "p_motivazione" "text", "p_durata" "text" DEFAULT NULL::"text", "p_nota_interna" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_report public.reports;
  v_attore uuid;
begin
  v_report := private.moderazione_pratica(
    p_report_id,
    'risolta'::public.report_stato,
    p_motivazione, p_nota_interna,
    'Il contenuto segnalato e stato sospeso'
  );
  v_attore := (select auth.uid());

  if v_report.target_tipo = 'profilo' and v_report.target_profile_id is not null then
    perform private.moderazione_utente_provvedimento(
      v_attore, v_report.target_profile_id, p_motivazione, p_durata, p_report_id
    );
  elsif v_report.target_tipo = 'annuncio' and v_report.target_listing_id is not null then
    perform private.moderazione_annuncio_transizione(
      v_attore, v_report.target_listing_id,
      'sospeso'::public.listing_stato,
      'sospensione'::public.mod_action,
      p_motivazione,
      array['bozza', 'in_revisione', 'modifiche_richieste',
            'attivo']::public.listing_stato[],
      p_report_id
    );
  else
    perform private.audit_registra(
      p_attore_id => v_attore,
      p_azione => 'sospensione'::public.mod_action,
      p_target_tipo => v_report.target_tipo,
      p_target_id => private.moderazione_bersaglio(v_report),
      p_target_label => v_report.target_label,
      p_motivazione => p_motivazione,
      p_durata => p_durata,
      p_report_id => p_report_id
    );
  end if;
end;
$$;


ALTER FUNCTION "public"."moderazione_sospensione"("p_report_id" "uuid", "p_motivazione" "text", "p_durata" "text", "p_nota_interna" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notification_mark_read"("p_notification_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  update public.notifications
  set read_at = coalesce(read_at, now())
  where id = p_notification_id
    and recipient_id = v_uid;

  if not found then
    raise exception 'Notifica non trovata.' using errcode = '42501';
  end if;
end;
$$;


ALTER FUNCTION "public"."notification_mark_read"("p_notification_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notifications_mark_all_read"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_count integer;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  update public.notifications
  set read_at = now()
  where recipient_id = v_uid
    and read_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;


ALTER FUNCTION "public"."notifications_mark_all_read"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notifications_page"("p_before_created_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_before_id" "uuid" DEFAULT NULL::"uuid", "p_limit" integer DEFAULT 50) RETURNS TABLE("id" "uuid", "category" "public"."notification_category", "event_type" "text", "body" "text", "destination_kind" "public"."notification_destination_kind", "destination_conversation_id" "uuid", "destination_listing_id" "uuid", "destination_order_id" "uuid", "destination_club_slug" "text", "read_at" timestamp with time zone, "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if private.utente_stato_di(v_uid) = 'rimosso' then
    raise exception 'Account rimosso.' using errcode = '42501';
  end if;
  if p_limit not between 1 and 100
     or ((p_before_created_at is null) <> (p_before_id is null)) then
    raise exception 'Cursore non valido.' using errcode = '22023';
  end if;

  return query
  select
    n.id,
    n.category,
    n.event_type,
    n.body,
    n.destination_kind,
    n.destination_conversation_id,
    n.destination_listing_id,
    n.destination_order_id,
    n.destination_club_slug,
    n.read_at,
    n.created_at
  from public.notifications n
  where n.recipient_id = v_uid
    and (
      p_before_created_at is null
      or (n.created_at, n.id) < (p_before_created_at, p_before_id)
    )
  order by n.created_at desc, n.id desc
  limit p_limit;
end;
$$;


ALTER FUNCTION "public"."notifications_page"("p_before_created_at" timestamp with time zone, "p_before_id" "uuid", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notifications_unread_count"() RETURNS bigint
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select case
    when auth.uid() is null then 0::bigint
    when private.utente_stato_di(auth.uid()) = 'rimosso' then 0::bigint
    else count(*)
  end
  from public.notifications n
  where n.recipient_id = auth.uid()
    and n.read_at is null;
$$;


ALTER FUNCTION "public"."notifications_unread_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."order_checkout_release"("p_order_id" "uuid", "p_buyer_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_order public.orders%rowtype;
begin
  select * into v_order from public.orders
  where id = p_order_id and buyer_id = p_buyer_id for update;
  if not found then return; end if;
  if v_order.stato = 'annullato' then return; end if;
  if exists (
    select 1 from public.payments p where p.order_id = v_order.id
      and p.stato in ('paid', 'partially_refunded', 'refunded')
  ) then return; end if;

  update public.orders set stato = 'annullato' where id = v_order.id;
  update public.payments set stato = 'failed'
  where order_id = v_order.id and stato in ('checkout_pending', 'processing');
  update public.listings set stato = 'attivo', reserved_by = null, reserved_until = null
  where id = v_order.listing_id and stato = 'riservato' and reserved_by = p_buyer_id;
  insert into public.order_events (order_id, tipo) values (v_order.id, 'checkout_released');
end;
$$;


ALTER FUNCTION "public"."order_checkout_release"("p_order_id" "uuid", "p_buyer_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."order_checkout_reserve"("p_buyer_id" "uuid", "p_listing_id" "uuid", "p_proposal_id" "uuid", "p_delivery_mode" "public"."delivery_mode", "p_idempotency_key" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_listing public.listings%rowtype;
  v_bottle public.bottle_units%rowtype;
  v_proposal public.proposals%rowtype;
  v_order public.orders%rowtype;
  v_payment public.payments%rowtype;
  v_config public.marketplace_config%rowtype;
  v_packaging public.packaging_options%rowtype;
  v_price integer;
  v_totale integer;
  v_commissione integer;
  v_imballaggio integer := 0;
  v_wine_name text;
begin
  if p_buyer_id is null or p_listing_id is null
     or length(coalesce(p_idempotency_key, '')) not between 8 and 128
     or p_idempotency_key !~ '^[A-Za-z0-9._:-]+$' then
    raise exception 'Richiesta checkout non valida.' using errcode = '22023';
  end if;
  perform private.rate_limit_consume('checkout', 'user:' || p_buyer_id::text, 10, 60);

  select * into v_order from public.orders
  where buyer_id = p_buyer_id and idempotency_key = p_idempotency_key;
  if found then
    select * into v_payment from public.payments where order_id = v_order.id;
    return jsonb_build_object(
      'order_id', v_order.id, 'amount_cents', v_order.addebito_totale_cents,
      'totale_mercato_cents', v_order.totale_cents,
      'prezzo_venditore_cents', v_order.prezzo_cents,
      'commissione_cents', v_order.commissione_cents,
      'margine_obiettivo_bps', v_order.margine_obiettivo_bps,
      'riferimento_stripe_percentuale_bps', v_order.riferimento_stripe_percentuale_bps,
      'riferimento_stripe_fisso_cents', v_order.riferimento_stripe_fisso_cents,
      'imballaggio_codice', v_order.imballaggio_codice,
      'imballaggio_etichetta', v_order.imballaggio_etichetta,
      'imballaggio_cents', v_order.imballaggio_cents,
      'currency', v_order.currency, 'checkout_url', v_payment.checkout_url,
      'provider', v_payment.provider,
      'provider_session_id', v_payment.provider_session_id,
      'reservation_expires_at', v_order.reservation_expires_at,
      'order_status', v_order.stato, 'payment_status', v_payment.stato
    );
  end if;

  select * into v_listing from public.listings where id = p_listing_id for update;
  if not found then raise exception 'Annuncio non trovato.' using errcode = 'P0001'; end if;

  -- The listing lock serializes competing buyers. Re-check the idempotency key
  -- after acquiring it: a concurrent first request may have committed meanwhile.
  select * into v_order from public.orders
  where buyer_id = p_buyer_id and idempotency_key = p_idempotency_key;
  if found then
    select * into v_payment from public.payments where order_id = v_order.id;
    return jsonb_build_object(
      'order_id', v_order.id, 'amount_cents', v_order.addebito_totale_cents,
      'totale_mercato_cents', v_order.totale_cents,
      'prezzo_venditore_cents', v_order.prezzo_cents,
      'commissione_cents', v_order.commissione_cents,
      'margine_obiettivo_bps', v_order.margine_obiettivo_bps,
      'riferimento_stripe_percentuale_bps', v_order.riferimento_stripe_percentuale_bps,
      'riferimento_stripe_fisso_cents', v_order.riferimento_stripe_fisso_cents,
      'imballaggio_codice', v_order.imballaggio_codice,
      'imballaggio_etichetta', v_order.imballaggio_etichetta,
      'imballaggio_cents', v_order.imballaggio_cents,
      'currency', v_order.currency, 'checkout_url', v_payment.checkout_url,
      'provider', v_payment.provider,
      'provider_session_id', v_payment.provider_session_id,
      'reservation_expires_at', v_order.reservation_expires_at,
      'order_status', v_order.stato, 'payment_status', v_payment.stato
    );
  end if;

  if v_listing.stato = 'riservato' and v_listing.reserved_until <= now() then
    update public.proposals set stato = 'scaduta'
    where listing_id = v_listing.id and stato = 'accettata' and scadenza <= now();
    update public.payments p set stato = 'expired'
    from public.orders o
    where p.order_id = o.id and o.listing_id = v_listing.id
      and o.stato = 'in_attesa_pagamento'
      and o.reservation_expires_at <= now()
      and p.stato in ('checkout_pending', 'processing');
    update public.orders set stato = 'annullato'
    where listing_id = v_listing.id and stato = 'in_attesa_pagamento'
      and reservation_expires_at <= now();
    update public.listings set stato = 'attivo', reserved_by = null, reserved_until = null
    where id = v_listing.id;
    select * into v_listing from public.listings where id = p_listing_id;
  end if;

  if v_listing.expires_at is not null and v_listing.expires_at <= now() then
    raise exception 'Questo annuncio è scaduto.' using errcode = 'P0001';
  end if;
  if v_listing.seller_id = p_buyer_id then
    raise exception 'Non puoi acquistare il tuo annuncio.' using errcode = 'P0001';
  end if;

  select * into v_bottle from public.bottle_units
  where id = v_listing.bottle_unit_id for update;
  if not found or v_bottle.owner_id <> v_listing.seller_id
     or v_bottle.stato <> 'chiusa' or v_bottle.deleted_at is not null
     or v_bottle.ceduta_at is not null then
    raise exception 'La bottiglia non è disponibile.' using errcode = 'P0001';
  end if;

  if p_proposal_id is null then
    if v_listing.stato <> 'attivo' then
      raise exception 'Questo annuncio è già riservato.' using errcode = 'P0001';
    end if;
    v_price := v_listing.prezzo_cents;
  else
    select * into v_proposal from public.proposals
    where id = p_proposal_id for update;
    if not found or v_proposal.listing_id <> v_listing.id
       or v_proposal.buyer_id <> p_buyer_id or v_proposal.stato <> 'accettata'
       or v_proposal.scadenza <= now() or v_listing.stato <> 'riservato'
       or v_listing.reserved_by <> p_buyer_id then
      raise exception 'La proposta non è valida per questo checkout.' using errcode = 'P0001';
    end if;
    v_price := coalesce(v_proposal.controproposta_cents, v_proposal.prezzo_proposto_cents);
  end if;

  -- Il congelamento. Da qui in poi i parametri di questo ordine sono un dato
  -- storico: `marketplace_config` può cambiare senza che questa riga si muova.
  v_config := private.marketplace_config_corrente();
  if v_config.id is null then
    raise exception 'Configurazione di mercato mancante.' using errcode = 'P0001';
  end if;
  v_totale := private.marketplace_totale_cents(
    v_price, v_config.margine_obiettivo_bps,
    v_config.riferimento_stripe_percentuale_bps, v_config.riferimento_stripe_fisso_cents
  );
  v_commissione := v_totale - v_price;

  -- L'imballaggio si risolve dalla dichiarazione del venditore sull'annuncio e
  -- si congela come i tre parametri della commissione. Un annuncio senza
  -- dichiarazione produce un ordine senza imballaggio e a costo zero: è il
  -- comportamento di ogni annuncio esistente prima di questa migrazione.
  -- L'imballaggio NON entra in v_totale e non tocca la formula del rincaro.
  if v_listing.imballaggio_codice is not null then
    select * into v_packaging from public.packaging_options
    where codice = v_listing.imballaggio_codice and valida_fino is null;
    if found then
      v_imballaggio := v_packaging.prezzo_cents;
    end if;
  end if;

  insert into public.orders (
    listing_id, proposal_id, buyer_id, seller_id, seller_bottle_unit_id,
    delivery_mode, prezzo_cents, margine_obiettivo_bps,
    riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents,
    commissione_cents, currency, idempotency_key, reservation_expires_at,
    imballaggio_codice, imballaggio_provider, imballaggio_etichetta,
    imballaggio_cents, imballaggio_scelto_at
  ) values (
    v_listing.id, p_proposal_id, p_buyer_id, v_listing.seller_id,
    v_listing.bottle_unit_id, p_delivery_mode, v_price,
    v_config.margine_obiettivo_bps, v_config.riferimento_stripe_percentuale_bps,
    v_config.riferimento_stripe_fisso_cents, v_commissione, 'eur',
    p_idempotency_key, now() + interval '30 minutes',
    v_packaging.codice, v_packaging.provider, v_packaging.etichetta,
    v_imballaggio, case when v_packaging.codice is not null then now() end
  ) returning * into v_order;

  -- Il fornitore addebita il totale comprensivo di imballaggio: è questo il
  -- numero che `payment_apply_provider_event` riconfronta con la dichiarazione.
  insert into public.payments (order_id, amount_cents, currency)
  values (v_order.id, v_order.addebito_totale_cents, v_order.currency)
  returning * into v_payment;

  update public.listings set stato = 'riservato', reserved_by = p_buyer_id,
    reserved_until = v_order.reservation_expires_at
  where id = v_listing.id;
  if p_proposal_id is not null then
    update public.proposals set stato = 'convertita' where id = p_proposal_id;
  end if;
  insert into public.order_events (order_id, tipo, payload)
  values (v_order.id, 'checkout_reserved', jsonb_build_object(
    'commissione_cents', v_order.commissione_cents,
    'margine_obiettivo_bps', v_order.margine_obiettivo_bps,
    'riferimento_stripe_percentuale_bps', v_order.riferimento_stripe_percentuale_bps,
    'riferimento_stripe_fisso_cents', v_order.riferimento_stripe_fisso_cents,
    'imballaggio_codice', v_order.imballaggio_codice,
    'imballaggio_cents', v_order.imballaggio_cents
  ));

  perform private.tracking_registra(v_order.id, 'sistema', 'Ordine ricevuto');

  select w.nome into v_wine_name from public.wines w where w.id = v_bottle.wine_id;

  return jsonb_build_object(
    'order_id', v_order.id, 'amount_cents', v_order.addebito_totale_cents,
    'totale_mercato_cents', v_order.totale_cents,
    'prezzo_venditore_cents', v_order.prezzo_cents,
    'commissione_cents', v_order.commissione_cents,
    'margine_obiettivo_bps', v_order.margine_obiettivo_bps,
    'riferimento_stripe_percentuale_bps', v_order.riferimento_stripe_percentuale_bps,
    'riferimento_stripe_fisso_cents', v_order.riferimento_stripe_fisso_cents,
    'imballaggio_codice', v_order.imballaggio_codice,
    'imballaggio_etichetta', v_order.imballaggio_etichetta,
    'imballaggio_cents', v_order.imballaggio_cents,
    'currency', v_order.currency, 'wine_name', v_wine_name,
    'reservation_expires_at', v_order.reservation_expires_at,
    'order_status', v_order.stato, 'payment_status', v_payment.stato
  );
exception when unique_violation then
  raise exception 'Questo annuncio è già stato prenotato.' using errcode = '23505';
end;
$_$;


ALTER FUNCTION "public"."order_checkout_reserve"("p_buyer_id" "uuid", "p_listing_id" "uuid", "p_proposal_id" "uuid", "p_delivery_mode" "public"."delivery_mode", "p_idempotency_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."order_seller_stato"("p_order" "public"."orders") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
  select case p_order.stato
    when 'in_attesa_pagamento' then 'nuovo'
    when 'pagato' then
      case when p_order.preparazione_avviata_at is null
           then 'nuovo' else 'da_preparare' end
    when 'in_preparazione' then 'da_spedire'
    when 'spedito'     then 'spedito'
    when 'consegnato'  then 'consegnato'
    when 'verifica'    then 'consegnato'
    when 'completato'  then 'completato'
    when 'contestato'  then 'contestato'
    when 'rimborsato'  then 'rimborsato'
    when 'annullato'   then 'annullato'
  end;
$$;


ALTER FUNCTION "public"."order_seller_stato"("p_order" "public"."orders") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ordine_auto_rilascio_esegui"("p_limit" integer DEFAULT 50) RETURNS SETOF "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 500);
  v_ids uuid[];
begin
  with candidati as (
    select o.id
    from public.orders o
    join public.payments p on p.order_id = o.id
    where o.stato in ('consegnato', 'verifica')
      and o.payout_stato = 'trattenuto'
      and o.contestato_at is null
      and o.auto_rilascio_scadenza is not null
      and o.auto_rilascio_scadenza <= now()
      and p.stato = 'paid'
    order by o.auto_rilascio_scadenza
    limit v_limit
    for update of o skip locked
  ), rilasciati as (
    update public.orders o set
      stato = 'completato',
      payout_stato = 'in_attesa'
    from candidati c
    where o.id = c.id
    returning o.id
  )
  select array_agg(r.id) into v_ids from rilasciati r;

  if v_ids is null then return; end if;

  insert into public.order_events (order_id, tipo, payload)
  select x.id, 'auto_rilascio', jsonb_build_object('origine', 'scadenza_verifica')
  from unnest(v_ids) as x(id);

  return query select x.id from unnest(v_ids) as x(id);
end;
$$;


ALTER FUNCTION "public"."ordine_auto_rilascio_esegui"("p_limit" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."ordine_auto_rilascio_esegui"("p_limit" integer) IS 'Reclama gli ordini con finestra di verifica scaduta. skip locked più la condizione su payout_stato impediscono a due esecuzioni concorrenti del job di rilasciare lo stesso ordine.';



CREATE OR REPLACE FUNCTION "public"."ordine_contesta"("p_order_id" "uuid", "p_motivo" "text") RETURNS "public"."orders"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;
  perform private.rate_limit_consume('order:dispute', 'user:' || v_uid::text, 10, 60);
  if length(trim(coalesce(p_motivo, ''))) not between 3 and 1000 then
    raise exception 'Il motivo della contestazione non è valido.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.buyer_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;
  if v_order.contestato_at is not null then return v_order; end if;
  -- Dopo che il denaro è uscito non c'è più niente da bloccare: la strada è il
  -- rimborso, non la contestazione. Un trasferimento *fallito* invece si
  -- contesta eccome — i fondi sono ancora fermi sul balance della piattaforma.
  if v_order.payout_stato not in ('trattenuto', 'in_attesa', 'fallito') then
    raise exception 'I fondi di questo ordine sono già stati trasferiti.' using errcode = 'P0001';
  end if;
  if v_order.stato not in
     ('pagato', 'in_preparazione', 'spedito', 'consegnato', 'verifica', 'completato') then
    raise exception 'Questo ordine non è contestabile.' using errcode = 'P0001';
  end if;

  update public.orders set
    stato = 'contestato',
    contestato_at = now(),
    contestazione_motivo = trim(p_motivo),
    payout_stato = 'bloccato'
  where id = v_order.id returning * into v_order;

  -- Se un rilascio era già stato deciso ma non ancora eseguito, la sua riga di
  -- payout va bloccata insieme all'ordine: `payout_prepara` non la vedrebbe
  -- comunque, ma lasciarla 'in_attesa' racconterebbe una cosa falsa.
  update public.payouts set stato = 'bloccato',
    ultimo_errore = 'Ordine contestato dal compratore.'
  where order_id = v_order.id and stato in ('in_attesa', 'fallito');

  insert into public.order_events (order_id, tipo, payload)
  values (v_order.id, 'contestazione_aperta', jsonb_build_object('origine', 'compratore'));
  return v_order;
end;
$$;


ALTER FUNCTION "public"."ordine_contesta"("p_order_id" "uuid", "p_motivo" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ordine_contestazione_apri"("p_order_id" "uuid", "p_motivo" "text", "p_descrizione" "text", "p_foto" "text"[] DEFAULT '{}'::"text"[]) RETURNS "public"."orders"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_descrizione, ''))) not between 3 and 2000 then
    raise exception 'La descrizione della contestazione non è valida.'
      using errcode = '22023';
  end if;
  if cardinality(coalesce(p_foto, '{}')) > 8 then
    raise exception 'Troppe foto allegate.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id;
  if not found or v_order.buyer_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;

  -- Una pratica per ordine. Dopo una risoluzione a favore del venditore il
  -- flag sull'ordine viene azzerato — deve esserlo — ma il fascicolo resta, e
  -- riaprire non è previsto in questa fase.
  if exists (select 1 from public.disputes d where d.order_id = p_order_id) then
    raise exception 'Una contestazione per questo ordine è già stata registrata.'
      using errcode = 'P0001';
  end if;

  -- Tutte le precondizioni di stato, payout e proprietà le applica la 7b.
  perform public.ordine_contesta(p_order_id, p_motivo);

  insert into public.disputes (order_id, aperta_da, motivo, descrizione, foto)
  values (p_order_id, v_uid, trim(p_motivo), trim(p_descrizione),
          coalesce(p_foto, '{}'));

  perform private.tracking_registra(
    p_order_id, 'problema', 'Contestazione aperta', trim(p_motivo));

  select * into v_order from public.orders where id = p_order_id;
  return v_order;
end;
$$;


ALTER FUNCTION "public"."ordine_contestazione_apri"("p_order_id" "uuid", "p_motivo" "text", "p_descrizione" "text", "p_foto" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ordine_contestazione_risolvi"("p_order_id" "uuid", "p_esito" "public"."dispute_stato", "p_nota" "text" DEFAULT NULL::"text") RETURNS "public"."orders"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_dispute public.disputes%rowtype;
begin
  -- service_role non ha auth.uid(): è il chiamante di back-office.
  if v_uid is not null and not public.has_role(v_uid, 'admin') then
    raise exception 'Non autorizzato a risolvere una contestazione.'
      using errcode = '42501';
  end if;
  if p_esito not in ('rimborsata', 'risolta', 'respinta') then
    raise exception 'Esito non valido.' using errcode = '22023';
  end if;
  if p_nota is not null and length(p_nota) > 1000 then
    raise exception 'Nota troppo lunga.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'Ordine non trovato.' using errcode = 'P0001';
  end if;

  select * into v_dispute from public.disputes where order_id = p_order_id for update;
  if not found then
    raise exception 'Nessuna contestazione da risolvere.' using errcode = 'P0001';
  end if;
  if v_dispute.stato not in ('aperta', 'in_valutazione') then
    return v_order;  -- idempotente
  end if;

  update public.disputes set
    stato = p_esito,
    esito_nota = p_nota,
    risolta_da = v_uid,
    chiusura_at = now()
  where id = v_dispute.id;

  if p_esito = 'rimborsata' then
    -- Decisione (c). L'ordine RESTA contestato e i fondi restano bloccati:
    -- `rimborsato` lo scrive soltanto payment_apply_provider_event, cioè un
    -- evento firmato e deduplicato del fornitore. Dire «rimborsato» prima che
    -- il denaro si sia mosso è ciò che quell'invariante vieta.
    perform private.tracking_registra(
      p_order_id, 'sistema', 'Rimborso disposto',
      coalesce(p_nota, 'In attesa di conferma dal fornitore di pagamento.'));
  else
    -- `respinta` riporta l'ordine dov'era prima della contestazione;
    -- `risolta` lo chiude con l'accordo fra le parti. In entrambi i casi il
    -- flag va azzerato: è su contestato_at che filtrano ordine_auto_rilascio_esegui,
    -- payout_coda e payout_prepara, e lasciarlo acceso terrebbe i fondi del
    -- venditore congelati per sempre.
    --
    -- Nessuna scrittura su public.payouts: payout_prepara fa
    -- `on conflict (order_id) do update set stato = 'in_corso'`, quindi la riga
    -- che ordine_contesta aveva messo a 'bloccato' viene ripresa da sola.
    --
    -- FASE 7F: i quattro letterali sono castati. Senza il cast il `case` si
    -- risolve a `text`, che verso un enum non ha conversione implicita, e
    -- l'intero UPDATE solleva 42804 — vedi l'intestazione di questo file.
    update public.orders set
      stato = case when p_esito = 'respinta'
                   then 'consegnato'::public.order_stato
                   else 'completato'::public.order_stato end,
      payout_stato = case when p_esito = 'respinta'
                          then 'trattenuto'::public.payout_stato
                          else 'in_attesa'::public.payout_stato end,
      contestato_at = null,
      contestazione_motivo = null
    where id = v_order.id returning * into v_order;

    perform private.tracking_registra(
      p_order_id, 'sistema',
      case when p_esito = 'respinta' then 'Contestazione respinta'
           else 'Contestazione risolta' end,
      p_nota);
  end if;

  insert into public.order_events (order_id, tipo, payload)
  values (p_order_id, 'contestazione_risolta', jsonb_build_object(
    'esito', p_esito, 'da_admin', v_uid is not null
  ));

  select * into v_order from public.orders where id = p_order_id;
  return v_order;
end;
$$;


ALTER FUNCTION "public"."ordine_contestazione_risolvi"("p_order_id" "uuid", "p_esito" "public"."dispute_stato", "p_nota" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ordine_imballaggio_punto_scegli"("p_order_id" "uuid", "p_punto_id" "text", "p_punto_nome" "text") RETURNS "public"."orders"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  perform private.rate_limit_consume('order:packaging', 'user:' || v_uid::text, 30, 60);

  if length(coalesce(p_punto_id, '')) not between 1 and 80
     or length(coalesce(p_punto_nome, '')) not between 1 and 160 then
    raise exception 'Punto di consegna non valido.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.seller_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;
  if v_order.imballaggio_codice is null then
    raise exception 'Questo ordine non ha una modalità di imballaggio.'
      using errcode = 'P0001';
  end if;
  if v_order.stato not in ('pagato', 'in_preparazione') then
    raise exception 'Il punto di consegna si sceglie prima della spedizione.'
      using errcode = 'P0001';
  end if;

  update public.orders set
    imballaggio_punto_id = p_punto_id,
    imballaggio_punto_nome = p_punto_nome
  where id = v_order.id returning * into v_order;

  insert into public.order_events (order_id, tipo, payload)
  values (v_order.id, 'imballaggio_punto_scelto', jsonb_build_object(
    'punto_id', p_punto_id
  ));
  return v_order;
end;
$$;


ALTER FUNCTION "public"."ordine_imballaggio_punto_scegli"("p_order_id" "uuid", "p_punto_id" "text", "p_punto_nome" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ordine_prepara_spedizione"("p_order_id" "uuid", "p_checklist" "jsonb" DEFAULT '[]'::"jsonb", "p_foto" "text"[] DEFAULT '{}'::"text"[]) RETURNS "public"."orders"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  perform private.rate_limit_consume('order:prepare', 'user:' || v_uid::text, 30, 60);

  if p_checklist is null or jsonb_typeof(p_checklist) <> 'array'
     or jsonb_array_length(p_checklist) > 12 then
    raise exception 'Checklist di imballaggio non valida.' using errcode = '22023';
  end if;
  if cardinality(coalesce(p_foto, '{}')) > 8 then
    raise exception 'Troppe foto di imballaggio.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.seller_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;

  -- Idempotente: riaprire la preparazione aggiorna la checklist e non riscrive
  -- l'istante di avvio, che è ciò che distingue «nuovo» da «da_preparare».
  if v_order.stato not in ('pagato', 'in_preparazione') then
    raise exception 'Questo ordine non è in preparazione.' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.payments p
    where p.order_id = v_order.id and p.stato = 'paid'
  ) then
    raise exception 'Il pagamento di questo ordine non risulta incassato.'
      using errcode = 'P0001';
  end if;

  update public.orders set
    stato = 'in_preparazione',
    preparazione_avviata_at = coalesce(v_order.preparazione_avviata_at, now()),
    imballaggio_checklist = p_checklist,
    imballaggio_foto = coalesce(p_foto, '{}')
  where id = v_order.id returning * into v_order;

  -- Un solo evento di timeline anche se il venditore riapre la preparazione e
  -- aggiorna la checklist. In order_events invece la riga si ripete, ed è
  -- giusto: lì la storia è ogni chiamata, qui è ogni transizione.
  if not exists (
    select 1 from public.tracking_events t
    where t.order_id = v_order.id
      and t.tipo = 'info'
      and t.titolo = 'In preparazione dal venditore'
  ) then
    perform private.tracking_registra(
      v_order.id, 'info', 'In preparazione dal venditore');
  end if;

  insert into public.order_events (order_id, tipo, payload)
  values (v_order.id, 'preparazione_avviata', jsonb_build_object(
    'voci_checklist', jsonb_array_length(p_checklist)
  ));
  return v_order;
end;
$$;


ALTER FUNCTION "public"."ordine_prepara_spedizione"("p_order_id" "uuid", "p_checklist" "jsonb", "p_foto" "text"[]) OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."order_reviews" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "autore_id" "uuid" NOT NULL,
    "destinatario_id" "uuid" NOT NULL,
    "voto" smallint NOT NULL,
    "conformita" smallint NOT NULL,
    "imballaggio" smallint NOT NULL,
    "comunicazione" smallint NOT NULL,
    "testo" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "order_reviews_comunicazione_check" CHECK ((("comunicazione" >= 1) AND ("comunicazione" <= 5))),
    CONSTRAINT "order_reviews_conformita_check" CHECK ((("conformita" >= 1) AND ("conformita" <= 5))),
    CONSTRAINT "order_reviews_imballaggio_check" CHECK ((("imballaggio" >= 1) AND ("imballaggio" <= 5))),
    CONSTRAINT "order_reviews_parti_distinte" CHECK (("autore_id" <> "destinatario_id")),
    CONSTRAINT "order_reviews_testo_check" CHECK ((("testo" IS NULL) OR ("length"("testo") <= 2000))),
    CONSTRAINT "order_reviews_voto_check" CHECK ((("voto" >= 1) AND ("voto" <= 5)))
);


ALTER TABLE "public"."order_reviews" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ordine_recensisci"("p_order_id" "uuid", "p_voto" smallint, "p_conformita" smallint, "p_imballaggio" smallint, "p_comunicazione" smallint, "p_testo" "text" DEFAULT NULL::"text") RETURNS "public"."order_reviews"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_review public.order_reviews%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  perform private.rate_limit_consume('order:review', 'user:' || v_uid::text, 10, 60);

  if p_voto not between 1 and 5 or p_conformita not between 1 and 5
     or p_imballaggio not between 1 and 5 or p_comunicazione not between 1 and 5 then
    raise exception 'Punteggio fuori scala.' using errcode = '22023';
  end if;
  if p_testo is not null and length(p_testo) > 2000 then
    raise exception 'Testo della recensione troppo lungo.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id;
  if not found or v_order.buyer_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;
  if v_order.stato <> 'completato' then
    raise exception 'Si recensisce solo un ordine completato.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.order_reviews r where r.order_id = p_order_id) then
    raise exception 'Questo ordine è già stato recensito.' using errcode = 'P0001';
  end if;

  insert into public.order_reviews (
    order_id, autore_id, destinatario_id,
    voto, conformita, imballaggio, comunicazione, testo
  ) values (
    p_order_id, v_uid, v_order.seller_id,
    p_voto, p_conformita, p_imballaggio, p_comunicazione, nullif(trim(coalesce(p_testo, '')), '')
  ) returning * into v_review;

  return v_review;
end;
$$;


ALTER FUNCTION "public"."ordine_recensisci"("p_order_id" "uuid", "p_voto" smallint, "p_conformita" smallint, "p_imballaggio" smallint, "p_comunicazione" smallint, "p_testo" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ordine_segna_consegnato"("p_order_id" "uuid") RETURNS "public"."orders"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_config public.marketplace_config%rowtype;
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;
  perform private.rate_limit_consume('order:delivered', 'user:' || v_uid::text, 30, 60);

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.seller_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;
  if v_order.stato not in ('pagato', 'in_preparazione', 'spedito') then
    raise exception 'Questo ordine non può essere segnato come consegnato.' using errcode = 'P0001';
  end if;

  -- La finestra di verifica si calcola alla consegna con la configurazione
  -- allora in vigore, e da quel momento è una data fissa sulla riga: cambiare
  -- la configurazione non sposta le scadenze già decise.
  v_config := private.marketplace_config_corrente();
  if v_config.id is null then
    raise exception 'Configurazione di mercato mancante.' using errcode = 'P0001';
  end if;

  update public.orders set
    stato = 'consegnato',
    consegnato_at = now(),
    auto_rilascio_scadenza = now() + make_interval(days => v_config.auto_rilascio_giorni)
  where id = v_order.id returning * into v_order;

  insert into public.order_events (order_id, tipo, payload)
  values (v_order.id, 'consegna_dichiarata', jsonb_build_object(
    'auto_rilascio_scadenza', v_order.auto_rilascio_scadenza,
    'auto_rilascio_giorni', v_config.auto_rilascio_giorni
  ));
  return v_order;
end;
$$;


ALTER FUNCTION "public"."ordine_segna_consegnato"("p_order_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ordine_segna_spedito"("p_order_id" "uuid", "p_corriere" "text", "p_tracking_number" "text") RETURNS "public"."orders"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  perform private.rate_limit_consume('order:ship', 'user:' || v_uid::text, 30, 60);

  if length(trim(coalesce(p_corriere, ''))) not between 2 and 60 then
    raise exception 'Corriere non valido.' using errcode = '22023';
  end if;
  if coalesce(p_tracking_number, '') !~ '^[A-Za-z0-9._-]{4,64}$' then
    raise exception 'Numero di tracking non valido.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.seller_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;
  if v_order.stato not in ('pagato', 'in_preparazione') then
    raise exception 'Questo ordine non può essere segnato come spedito.'
      using errcode = 'P0001';
  end if;

  update public.orders set
    stato = 'spedito',
    spedito_at = now(),
    corriere = trim(p_corriere),
    tracking_number = p_tracking_number,
    preparazione_avviata_at = coalesce(v_order.preparazione_avviata_at, now())
  where id = v_order.id returning * into v_order;

  perform private.tracking_registra(
    v_order.id, 'spedizione', 'Spedito',
    v_order.corriere || ' — ' || v_order.tracking_number);

  insert into public.order_events (order_id, tipo, payload)
  values (v_order.id, 'spedizione_dichiarata', jsonb_build_object(
    'corriere', v_order.corriere
  ));
  return v_order;
end;
$_$;


ALTER FUNCTION "public"."ordine_segna_spedito"("p_order_id" "uuid", "p_corriere" "text", "p_tracking_number" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."payment_apply_provider_event"("p_provider" "text", "p_event_id" "text", "p_outcome" "public"."payment_outcome", "p_occurred_at" bigint, "p_object" "jsonb") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_created_at timestamptz := to_timestamp(p_occurred_at);
  v_payment public.payments%rowtype;
  v_order public.orders%rowtype;
  v_bottle public.bottle_units%rowtype;
  v_session_id text := p_object ->> 'session_id';
  v_intent_id text := p_object ->> 'intent_id';
  v_event_type text := p_object ->> 'provider_event_type';
  v_amount integer := coalesce((p_object ->> 'amount_cents')::integer, 0);
  v_refunded integer := coalesce((p_object ->> 'amount_refunded')::integer, 0);
  v_fully_refunded boolean := coalesce((p_object ->> 'refunded')::boolean, false);
  v_currency text := lower(coalesce(p_object ->> 'currency', ''));
  v_order_ref uuid := nullif(p_object ->> 'order_id', '')::uuid;
  v_fee_reale integer := nullif(p_object ->> 'fee_reale_cents', '')::integer;
  v_fee_txn text := nullif(p_object ->> 'fee_transazione_id', '');
begin
  -- I null sono respinti qui e non lasciati arrivare ai vincoli not null delle
  -- tabelle: un messaggio di violazione esporrebbe nomi di colonna al chiamante.
  if p_outcome is null or p_occurred_at is null
     or coalesce(p_provider, '') !~ '^[a-z0-9_]{2,32}$'
     or length(coalesce(p_event_id, '')) < 4
     or length(coalesce(v_event_type, '')) not between 1 and 120
     or p_occurred_at <= 0 then
    raise exception 'Evento di pagamento non valido.' using errcode = '22023';
  end if;
  insert into public.payment_provider_events (
    provider, event_id, outcome, provider_event_type, occurred_at
  )
  values (p_provider, p_event_id, p_outcome, v_event_type, v_created_at)
  on conflict (provider, event_id) do nothing;
  if not found then return 'duplicate'; end if;

  -- Il rimborso arriva sull'incasso, non sulla sessione: è l'unico esito che
  -- si aggancia per `provider_intent_id`.
  if p_outcome = 'refunded' then
    select * into v_payment from public.payments
    where provider = p_provider and provider_intent_id = v_intent_id for update;
  else
    select * into v_payment from public.payments
    where provider = p_provider and provider_session_id = v_session_id for update;
  end if;
  if not found then raise exception 'Pagamento non riconosciuto.' using errcode = 'P0001'; end if;
  select * into v_order from public.orders where id = v_payment.order_id for update;

  -- Misura, non decisione. Una fee negativa o non numerica sarebbe già stata
  -- respinta dal cast; qui si respinge anche quella che eccede l'incasso, che
  -- sarebbe un errore di lettura del payload e non un costo.
  if v_fee_reale is not null and v_fee_reale between 0 and v_payment.amount_cents then
    update public.payments set
      fee_stripe_reale_cents = v_fee_reale,
      fee_provider_transazione_id = coalesce(v_fee_txn, fee_provider_transazione_id),
      fee_riconciliata_at = now()
    where id = v_payment.id;
  elsif v_fee_txn is not null then
    update public.payments set fee_provider_transazione_id = v_fee_txn
    where id = v_payment.id and fee_provider_transazione_id is distinct from v_fee_txn;
  end if;

  if p_outcome = 'settled'
     and v_payment.stato not in ('partially_refunded', 'refunded') then
    if v_order_ref is distinct from v_order.id or v_amount <> v_payment.amount_cents
       or v_currency <> v_payment.currency then
      raise exception 'Importo, valuta o ordine non corrispondono.' using errcode = 'P0001';
    end if;
    if v_order.stato <> 'in_attesa_pagamento'
       or v_created_at > v_order.reservation_expires_at then
      update public.payments set
        stato = 'paid', provider_intent_id = coalesce(v_intent_id, provider_intent_id),
        provider_event_at = greatest(coalesce(provider_event_at, v_created_at), v_created_at)
      where id = v_payment.id;
      insert into public.order_events (order_id, tipo, payload)
      values (v_order.id, 'late_payment_requires_refund', jsonb_build_object(
        'provider_event_at', v_created_at
      ));
      return 'late_paid_requires_refund';
    end if;

    update public.payments set
      stato = 'paid', provider_intent_id = coalesce(v_intent_id, provider_intent_id),
      provider_event_at = greatest(coalesce(provider_event_at, v_created_at), v_created_at)
    where id = v_payment.id;
    -- I fondi entrano e restano fermi: `payout_stato` non si muove da
    -- 'trattenuto' finché un rilascio non lo decide.
    update public.orders set stato = 'pagato', paid_at = coalesce(paid_at, now())
    where id = v_order.id and stato = 'in_attesa_pagamento';
    update public.listings set stato = 'venduto', reserved_by = null, reserved_until = null
    where id = v_order.listing_id and stato = 'riservato'
      and reserved_by = v_order.buyer_id;
    if not found then
      raise exception 'La prenotazione non è più valida; il pagamento richiede revisione.'
        using errcode = 'P0001';
    end if;

    if v_order.buyer_bottle_unit_id is null then
      select * into v_bottle from public.bottle_units
      where id = v_order.seller_bottle_unit_id for update;
      insert into public.bottle_units (
        owner_id, wine_id, stato, visibilita, immagini
      ) values (
        v_order.buyer_id, v_bottle.wine_id, 'chiusa', 'privata', '{}'::text[]
      ) returning * into v_bottle;
      update public.orders set buyer_bottle_unit_id = v_bottle.id where id = v_order.id;
    end if;
    insert into public.order_events (order_id, tipo) values (v_order.id, 'payment_paid');
  elsif p_outcome = 'authorized'
        and v_payment.stato in ('checkout_pending', 'processing') then
    update public.payments set stato = 'processing',
      provider_intent_id = coalesce(v_intent_id, provider_intent_id),
      provider_event_at = greatest(coalesce(provider_event_at, v_created_at), v_created_at)
    where id = v_payment.id;
  elsif p_outcome = 'failed'
        and v_payment.stato in ('checkout_pending', 'processing') then
    update public.payments set stato = 'failed', provider_event_at = v_created_at
    where id = v_payment.id;
    perform public.order_checkout_release(v_order.id, v_order.buyer_id);
  elsif p_outcome = 'expired'
        and v_payment.stato in ('checkout_pending', 'processing') then
    update public.payments set stato = 'expired', provider_event_at = v_created_at
    where id = v_payment.id;
    perform public.order_checkout_release(v_order.id, v_order.buyer_id);
  elsif p_outcome = 'refunded' and v_refunded > 0 then
    update public.payments set
      amount_refunded_cents = greatest(amount_refunded_cents, least(v_refunded, amount_cents)),
      stato = case
        when v_fully_refunded or (v_amount > 0 and v_refunded >= v_amount)
          then 'refunded'::public.payment_stato
        else 'partially_refunded'::public.payment_stato
      end,
      provider_event_at = greatest(coalesce(provider_event_at, v_created_at), v_created_at)
    where id = v_payment.id;
    update public.orders set
      stato = case
        when v_fully_refunded or (v_amount > 0 and v_refunded >= v_amount)
          then 'rimborsato'::public.order_stato
        when stato in ('in_attesa_pagamento', 'annullato')
          then 'contestato'::public.order_stato
        else stato
      end,
      -- Un Transfer già creato non si annulla da qui: il denaro è uscito e la
      -- riconciliazione è un'operazione manuale. Si blocca solo ciò che è ancora
      -- fermo.
      payout_stato = case
        when payout_stato in ('trattenuto', 'in_attesa')
          then 'bloccato'::public.payout_stato
        else payout_stato
      end
    where id = v_order.id;
    insert into public.order_events (order_id, tipo, payload)
    values (v_order.id, 'payment_refund', jsonb_build_object('amount_cents', v_refunded));
  end if;

  return 'processed';
end;
$_$;


ALTER FUNCTION "public"."payment_apply_provider_event"("p_provider" "text", "p_event_id" "text", "p_outcome" "public"."payment_outcome", "p_occurred_at" bigint, "p_object" "jsonb") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."payment_apply_provider_event"("p_provider" "text", "p_event_id" "text", "p_outcome" "public"."payment_outcome", "p_occurred_at" bigint, "p_object" "jsonb") IS 'Applica un evento di incasso già verificato e deduplicato, ramificando sulla tassonomia interna public.payment_outcome e mai sul nome evento del fornitore, senza conservare il payload completo.';



CREATE OR REPLACE FUNCTION "public"."payment_checkout_attach"("p_order_id" "uuid", "p_buyer_id" "uuid", "p_provider" "text", "p_provider_session_id" "text", "p_checkout_url" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
begin
  if coalesce(p_provider, '') !~ '^[a-z0-9_]{2,32}$'
     or length(coalesce(p_provider_session_id, '')) < 4 then
    raise exception 'Checkout non collegabile.' using errcode = '22023';
  end if;
  update public.payments p set
    provider = p_provider,
    provider_session_id = p_provider_session_id,
    checkout_url = p_checkout_url,
    stato = 'processing'
  from public.orders o
  where p.order_id = p_order_id and o.id = p.order_id
    and o.buyer_id = p_buyer_id and o.stato = 'in_attesa_pagamento'
    and p.stato in ('checkout_pending', 'processing')
    -- Un pagamento già collegato non cambia fornitore in corsa.
    and (p.provider is null or p.provider = p_provider);
  if not found then raise exception 'Checkout non collegabile.' using errcode = 'P0001'; end if;
end;
$_$;


ALTER FUNCTION "public"."payment_checkout_attach"("p_order_id" "uuid", "p_buyer_id" "uuid", "p_provider" "text", "p_provider_session_id" "text", "p_checkout_url" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."payment_fee_reale_registra"("p_provider" "text", "p_provider_intent_id" "text", "p_fee_cents" integer, "p_transazione_id" "text" DEFAULT NULL::"text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_payment public.payments%rowtype;
begin
  if coalesce(p_provider, '') !~ '^[a-z0-9_]{2,32}$'
     or length(coalesce(p_provider_intent_id, '')) < 4
     or p_fee_cents is null or p_fee_cents < 0 then
    raise exception 'Riconciliazione fee non valida.' using errcode = '22023';
  end if;

  select * into v_payment from public.payments
  where provider = p_provider and provider_intent_id = p_provider_intent_id
  for update;
  if not found then return 'unknown_payment'; end if;
  -- Una fee superiore all'incasso non è un costo: è un aggancio sbagliato.
  if p_fee_cents > v_payment.amount_cents then return 'implausible'; end if;

  update public.payments set
    fee_stripe_reale_cents = p_fee_cents,
    fee_provider_transazione_id = coalesce(p_transazione_id, fee_provider_transazione_id),
    fee_riconciliata_at = now()
  where id = v_payment.id;
  return 'recorded';
end;
$_$;


ALTER FUNCTION "public"."payment_fee_reale_registra"("p_provider" "text", "p_provider_intent_id" "text", "p_fee_cents" integer, "p_transazione_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."payout_coda"("p_limit" integer DEFAULT 50) RETURNS SETOF "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select o.id
  from public.orders o
  where o.payout_stato = 'in_attesa'
    and o.contestato_at is null
  order by o.updated_at
  limit least(greatest(coalesce(p_limit, 50), 1), 500);
$$;


ALTER FUNCTION "public"."payout_coda"("p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."payout_prepara"("p_order_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_order public.orders%rowtype;
  v_payout public.payouts%rowtype;
  v_account public.seller_payout_accounts%rowtype;
  v_payment public.payments%rowtype;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'Ordine non trovato.' using errcode = 'P0001'; end if;

  select * into v_payout from public.payouts where order_id = v_order.id for update;
  if found and v_payout.stato = 'trasferito' then
    return jsonb_build_object('esito', 'gia_trasferito', 'payout_id', v_payout.id);
  end if;

  if v_order.contestato_at is not null or v_order.payout_stato = 'bloccato' then
    return jsonb_build_object('esito', 'bloccato', 'motivo', 'ordine_contestato');
  end if;
  if v_order.payout_stato not in ('in_attesa', 'in_corso', 'fallito') then
    return jsonb_build_object('esito', 'non_dovuto', 'motivo', v_order.payout_stato::text);
  end if;

  select * into v_payment from public.payments where order_id = v_order.id;
  if not found or v_payment.stato <> 'paid' or v_payment.amount_refunded_cents > 0 then
    return jsonb_build_object('esito', 'bloccato', 'motivo', 'incasso_non_valido');
  end if;

  select * into v_account from public.seller_payout_accounts
  where seller_id = v_order.seller_id and provider = v_payment.provider;
  if not found or not v_account.charges_enabled or not v_account.payouts_enabled then
    return jsonb_build_object('esito', 'bloccato', 'motivo', 'venditore_non_abilitato');
  end if;

  insert into public.payouts (
    order_id, seller_id, provider, destination_account_id, amount_cents, currency,
    stato, idempotency_key
  ) values (
    v_order.id, v_order.seller_id, v_payment.provider, v_account.provider_account_id,
    -- Il venditore riceve il prezzo, non il totale: la commissione resta alla
    -- piattaforma per il solo fatto di non essere trasferita.
    v_order.prezzo_cents, v_order.currency, 'in_corso',
    'vinea-payout-' || replace(v_order.id::text, '-', '')
  )
  on conflict (order_id) do update set
    stato = 'in_corso',
    tentativi = payouts.tentativi + 1,
    destination_account_id = excluded.destination_account_id,
    provider = excluded.provider
  returning * into v_payout;

  update public.orders set payout_stato = 'in_corso' where id = v_order.id;

  return jsonb_build_object(
    'esito', 'da_trasferire',
    'payout_id', v_payout.id,
    'order_id', v_order.id,
    'provider', v_payout.provider,
    'destination_account_id', v_payout.destination_account_id,
    'amount_cents', v_payout.amount_cents,
    'currency', v_payout.currency,
    'idempotency_key', v_payout.idempotency_key,
    'tentativi', v_payout.tentativi
  );
end;
$$;


ALTER FUNCTION "public"."payout_prepara"("p_order_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."payout_prepara"("p_order_id" "uuid") IS 'Reclama il rilascio di un ordine e restituisce le coordinate del Transfer. Idempotente per costruzione: una riga per ordine, uscita immediata se già trasferito, chiave di idempotenza derivata dall''id dell''ordine.';



CREATE OR REPLACE FUNCTION "public"."payout_registra_esito"("p_payout_id" "uuid", "p_ok" boolean, "p_provider_transfer_id" "text", "p_errore" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_payout public.payouts%rowtype;
begin
  select * into v_payout from public.payouts where id = p_payout_id for update;
  if not found then raise exception 'Payout non trovato.' using errcode = 'P0001'; end if;
  if v_payout.stato = 'trasferito' then return 'duplicate'; end if;

  if coalesce(p_ok, false) then
    if length(coalesce(p_provider_transfer_id, '')) < 4 then
      raise exception 'Identificativo del trasferimento mancante.' using errcode = '22023';
    end if;
    update public.payouts set
      stato = 'trasferito',
      provider_transfer_id = p_provider_transfer_id,
      transferred_at = now(),
      ultimo_errore = null
    where id = v_payout.id;
    update public.orders set payout_stato = 'trasferito' where id = v_payout.order_id;
    insert into public.order_events (order_id, tipo, payload)
    values (v_payout.order_id, 'payout_trasferito', jsonb_build_object(
      'amount_cents', v_payout.amount_cents
    ));
    return 'transferred';
  end if;

  update public.payouts set
    stato = 'fallito',
    ultimo_errore = left(coalesce(p_errore, 'errore sconosciuto'), 500)
  where id = v_payout.id;
  update public.orders set payout_stato = 'fallito' where id = v_payout.order_id;
  insert into public.order_events (order_id, tipo, payload)
  values (v_payout.order_id, 'payout_fallito', jsonb_build_object(
    'tentativi', v_payout.tentativi
  ));
  return 'failed';
end;
$$;


ALTER FUNCTION "public"."payout_registra_esito"("p_payout_id" "uuid", "p_ok" boolean, "p_provider_transfer_id" "text", "p_errore" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."profilo_pubblico"("p_user_id" "uuid") RETURNS TABLE("user_id" "uuid", "username" "text", "bio" "text", "citta" "text", "provincia" "text", "esperienza" "text", "avatar_url" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select
    v.user_id,
    v.username,
    v.bio,
    v.citta,
    v.provincia,
    v.esperienza,
    v.avatar_url
  from private.profili_pubblici v
  where v.user_id = p_user_id;
$$;


ALTER FUNCTION "public"."profilo_pubblico"("p_user_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."profilo_pubblico"("p_user_id" "uuid") IS 'Profilo pubblico di UNA persona, per identificativo. Restituisce zero righe se la persona non esiste, e stata rimossa (7.6b uscente) o il chiamante e rimosso (7.6b entrante): il chiamante non distingue i tre casi. Espone sette colonne dichiarate una per una - mai email, dob, ruoli, stato di moderazione o certificazioni. Non elenca: nessun parametro di ricerca, limite o offset.';



CREATE TABLE IF NOT EXISTS "public"."proposals" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "listing_id" "uuid" NOT NULL,
    "buyer_id" "uuid" NOT NULL,
    "seller_id" "uuid" NOT NULL,
    "prezzo_richiesto_cents" integer NOT NULL,
    "prezzo_proposto_cents" integer NOT NULL,
    "controproposta_cents" integer,
    "stato" "public"."proposal_stato" DEFAULT 'inviata'::"public"."proposal_stato" NOT NULL,
    "scadenza" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "proposals_controproposta_cents_check" CHECK (("controproposta_cents" > 0)),
    CONSTRAINT "proposals_parti_distinte" CHECK (("buyer_id" <> "seller_id")),
    CONSTRAINT "proposals_prezzo_proposto_cents_check" CHECK (("prezzo_proposto_cents" > 0)),
    CONSTRAINT "proposals_prezzo_richiesto_cents_check" CHECK (("prezzo_richiesto_cents" > 0))
);


ALTER TABLE "public"."proposals" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."proposal_accetta"("p_proposal_id" "uuid") RETURNS "public"."proposals"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_result public.proposals%rowtype;
  v_listing public.listings%rowtype;
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;
  perform private.rate_limit_consume('proposal:accept', 'user:' || v_uid::text, 20, 60);

  select * into v_result from public.proposals where id = p_proposal_id for update;
  if not found or v_result.seller_id <> v_uid then
    raise exception 'Proposta non trovata.' using errcode = '42501';
  end if;
  select * into v_listing from public.listings where id = v_result.listing_id for update;
  if v_result.stato not in ('inviata', 'controproposta')
     or v_result.scadenza <= now() or v_listing.stato <> 'attivo'
     or v_listing.expires_at is not null and v_listing.expires_at <= now() then
    raise exception 'Questa proposta non può essere accettata.' using errcode = 'P0001';
  end if;

  update public.proposals set stato = 'accettata'
  where id = p_proposal_id returning * into v_result;
  update public.proposals set stato = 'rifiutata'
  where listing_id = v_result.listing_id and id <> v_result.id
    and stato in ('inviata', 'controproposta');
  update public.listings set
    stato = 'riservato', reserved_by = v_result.buyer_id,
    reserved_until = v_result.scadenza
  where id = v_result.listing_id;
  return v_result;
end;
$$;


ALTER FUNCTION "public"."proposal_accetta"("p_proposal_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."proposal_controproponi"("p_proposal_id" "uuid", "p_prezzo_cents" integer) RETURNS "public"."proposals"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_result public.proposals%rowtype;
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;
  perform private.rate_limit_consume('proposal:counter', 'user:' || v_uid::text, 20, 60);
  if p_prezzo_cents is null or p_prezzo_cents <= 0 then
    raise exception 'La controproposta non è valida.' using errcode = '22023';
  end if;

  select * into v_result from public.proposals where id = p_proposal_id for update;
  if not found or v_result.seller_id <> v_uid then
    raise exception 'Proposta non trovata.' using errcode = '42501';
  end if;
  if v_result.stato not in ('inviata', 'controproposta') or v_result.scadenza <= now() then
    raise exception 'Questa proposta non è più modificabile.' using errcode = 'P0001';
  end if;

  update public.proposals set
    controproposta_cents = p_prezzo_cents,
    stato = 'controproposta'
  where id = p_proposal_id returning * into v_result;
  return v_result;
end;
$$;


ALTER FUNCTION "public"."proposal_controproponi"("p_proposal_id" "uuid", "p_prezzo_cents" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."proposal_invia"("p_listing_id" "uuid", "p_prezzo_cents" integer) RETURNS "public"."proposals"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_listing public.listings%rowtype;
  v_result public.proposals%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  perform private.rate_limit_consume('proposal:send', 'user:' || v_uid::text, 20, 60);

  select * into v_listing from public.listings
  where id = p_listing_id for update;
  if not found or v_listing.stato <> 'attivo'
     or v_listing.expires_at is not null and v_listing.expires_at <= now() then
    raise exception 'Questo annuncio non è disponibile.' using errcode = 'P0001';
  end if;
  if v_listing.seller_id = v_uid then
    raise exception 'Non puoi fare una proposta sul tuo annuncio.' using errcode = 'P0001';
  end if;
  if p_prezzo_cents is null or p_prezzo_cents <= 0 then
    raise exception 'Il prezzo proposto non è valido.' using errcode = '22023';
  end if;

  insert into public.proposals (
    listing_id, buyer_id, seller_id, prezzo_richiesto_cents,
    prezzo_proposto_cents, scadenza
  ) values (
    v_listing.id, v_uid, v_listing.seller_id, v_listing.prezzo_cents,
    p_prezzo_cents, now() + interval '7 days'
  ) returning * into v_result;
  return v_result;
exception when unique_violation then
  raise exception 'Hai già una proposta attiva per questa bottiglia.' using errcode = '23505';
end;
$$;


ALTER FUNCTION "public"."proposal_invia"("p_listing_id" "uuid", "p_prezzo_cents" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."proposal_rifiuta"("p_proposal_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;
  perform private.rate_limit_consume('proposal:reject', 'user:' || v_uid::text, 20, 60);
  update public.proposals set stato = 'rifiutata'
  where id = p_proposal_id and seller_id = v_uid
    and stato in ('inviata', 'controproposta') and scadenza > now();
  if not found then raise exception 'Proposta non modificabile.' using errcode = 'P0001'; end if;
end;
$$;


ALTER FUNCTION "public"."proposal_rifiuta"("p_proposal_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rate_limit_consume"("p_scope" "text", "p_subject" "text", "p_limit" integer, "p_window_seconds" integer) RETURNS integer
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
  select private.rate_limit_consume($1, $2, $3, $4);
$_$;


ALTER FUNCTION "public"."rate_limit_consume"("p_scope" "text", "p_subject" "text", "p_limit" integer, "p_window_seconds" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."segnalazione_invia"("p_target_tipo" "public"."report_target_tipo", "p_target_id" "uuid", "p_target_label" "text", "p_motivo" "text", "p_descrizione" "text" DEFAULT ''::"text", "p_foto" "text"[] DEFAULT '{}'::"text"[], "p_club_slug" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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

  if not exists (
    select 1 from public.report_reasons rr
    where rr.target_tipo = p_target_tipo and rr.motivo = p_motivo
  ) then
    raise exception 'Motivo non ammesso per questo tipo di bersaglio.'
      using errcode = '22023';
  end if;

  -- [a] I due rami nuovi. Un contenuto gia rimosso resta segnalabile: la
  -- segnalazione la legge un moderatore che vede anche cio che il pubblico non
  -- vede, e rifiutarla direbbe al segnalante «non esiste» di qualcosa che ha
  -- appena letto.
  v_esiste := case p_target_tipo
    when 'annuncio' then exists (select 1 from public.listings l where l.id = p_target_id)
    when 'profilo' then exists (select 1 from public.profiles pr where pr.id = p_target_id)
    when 'messaggio' then exists (select 1 from public.messages m where m.id = p_target_id)
    when 'conversazione' then exists (select 1 from public.conversations c where c.id = p_target_id)
    when 'recensione' then exists (select 1 from public.order_reviews r where r.id = p_target_id)
    when 'post' then exists (select 1 from public.club_posts cp where cp.id = p_target_id)
    when 'commento' then exists (select 1 from public.club_post_risposte cr where cr.id = p_target_id)
  end;

  if not coalesce(v_esiste, false) then
    raise exception 'Bersaglio non trovato.' using errcode = 'P0001';
  end if;

  if p_target_tipo = 'profilo' and p_target_id = v_uid then
    raise exception 'Non e possibile segnalare il proprio profilo.'
      using errcode = '22023';
  end if;

  -- [c] Il doppione, con le due colonne nuove nel coalesce.
  if exists (
    select 1 from public.reports r
    where r.reporter_id = v_uid
      and r.target_tipo = p_target_tipo
      and coalesce(
        r.target_listing_id, r.target_profile_id, r.target_message_id,
        r.target_conversation_id, r.target_review_id,
        r.target_post_id, r.target_risposta_id
      ) = p_target_id
      and r.stato in ('inviata', 'in_revisione', 'info_richieste')
  ) then
    raise exception 'Hai gia una segnalazione aperta su questo contenuto.'
      using errcode = 'P0001';
  end if;

  v_priorita := private.report_priorita_da_motivo(p_motivo);
  v_codice := 'SEG-' || to_char(now(), 'YYYY') || '-'
    || lpad(nextval('public.reports_codice_seq')::text, 4, '0');

  -- [b] Le due colonne nuove nell'INSERT.
  insert into public.reports (
    codice, target_tipo, target_label,
    target_listing_id, target_profile_id, target_message_id,
    target_conversation_id, target_review_id,
    target_post_id, target_risposta_id,
    motivo, descrizione, foto, priorita, reporter_id, club_slug
  ) values (
    v_codice, p_target_tipo, btrim(p_target_label),
    case when p_target_tipo = 'annuncio' then p_target_id end,
    case when p_target_tipo = 'profilo' then p_target_id end,
    case when p_target_tipo = 'messaggio' then p_target_id end,
    case when p_target_tipo = 'conversazione' then p_target_id end,
    case when p_target_tipo = 'recensione' then p_target_id end,
    case when p_target_tipo = 'post' then p_target_id end,
    case when p_target_tipo = 'commento' then p_target_id end,
    p_motivo, btrim(coalesce(p_descrizione, '')), coalesce(p_foto, '{}'),
    v_priorita, v_uid, p_club_slug
  )
  returning id into v_id;

  insert into public.report_events (report_id, visibile, testo, autore_id, autore_etichetta)
  values (v_id, true, 'Segnalazione ricevuta', null, 'Moderazione');

  return v_id;
end;
$$;


ALTER FUNCTION "public"."segnalazione_invia"("p_target_tipo" "public"."report_target_tipo", "p_target_id" "uuid", "p_target_label" "text", "p_motivo" "text", "p_descrizione" "text", "p_foto" "text"[], "p_club_slug" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."segnalazione_invia"("p_target_tipo" "public"."report_target_tipo", "p_target_id" "uuid", "p_target_label" "text", "p_motivo" "text", "p_descrizione" "text", "p_foto" "text"[], "p_club_slug" "text") IS 'Unica porta di ingresso di una segnalazione. Identita da auth.uid(), priorita derivata sul server, motivo vincolato all''elenco chiuso, bersaglio verificato esistente, rate limit 10/ora per utente. Sette bersagli dalla 12c: `post` e `commento` si risolvono su club_posts e club_post_risposte.';



CREATE OR REPLACE FUNCTION "public"."seller_payout_account_apply_event"("p_provider" "text", "p_event_id" "text", "p_provider_event_type" "text", "p_provider_account_id" "text", "p_charges_enabled" boolean, "p_payouts_enabled" boolean, "p_details_submitted" boolean, "p_requisiti" "text"[], "p_disabled_reason" "text", "p_occurred_at" bigint) RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_created_at timestamptz := to_timestamp(p_occurred_at);
  v_account public.seller_payout_accounts%rowtype;
begin
  if p_occurred_at is null or p_occurred_at <= 0
     or coalesce(p_provider, '') !~ '^[a-z0-9_]{2,32}$'
     or length(coalesce(p_event_id, '')) < 4
     or length(coalesce(p_provider_event_type, '')) not between 1 and 120
     or length(coalesce(p_provider_account_id, '')) < 4
     or p_charges_enabled is null or p_payouts_enabled is null then
    raise exception 'Evento account non valido.' using errcode = '22023';
  end if;

  insert into public.account_provider_events (
    provider, event_id, provider_event_type, provider_account_id, occurred_at
  )
  values (p_provider, p_event_id, p_provider_event_type, p_provider_account_id, v_created_at)
  on conflict (provider, event_id) do nothing;
  if not found then return 'duplicate'; end if;

  select * into v_account from public.seller_payout_accounts
  where provider = p_provider and provider_account_id = p_provider_account_id
  for update;
  if not found then return 'unknown_account'; end if;

  -- Gli eventi del fornitore non arrivano in ordine. Uno più vecchio di quello
  -- già applicato non riapre né richiude nulla.
  if v_account.provider_event_at is not null
     and v_created_at < v_account.provider_event_at then
    return 'stale';
  end if;

  update public.seller_payout_accounts set
    charges_enabled = p_charges_enabled,
    payouts_enabled = p_payouts_enabled,
    details_submitted = coalesce(p_details_submitted, details_submitted),
    requisiti_pendenti = coalesce(p_requisiti, '{}'::text[]),
    disabled_reason = p_disabled_reason,
    provider_event_at = v_created_at
  where id = v_account.id;

  return 'processed';
end;
$_$;


ALTER FUNCTION "public"."seller_payout_account_apply_event"("p_provider" "text", "p_event_id" "text", "p_provider_event_type" "text", "p_provider_account_id" "text", "p_charges_enabled" boolean, "p_payouts_enabled" boolean, "p_details_submitted" boolean, "p_requisiti" "text"[], "p_disabled_reason" "text", "p_occurred_at" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."seller_payout_account_get"("p_seller_id" "uuid", "p_provider" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_account public.seller_payout_accounts%rowtype;
begin
  select * into v_account from public.seller_payout_accounts
  where seller_id = p_seller_id and provider = p_provider;
  if not found then return null; end if;
  return jsonb_build_object(
    'account_id', v_account.id,
    'provider_account_id', v_account.provider_account_id,
    'charges_enabled', v_account.charges_enabled,
    'payouts_enabled', v_account.payouts_enabled,
    'details_submitted', v_account.details_submitted,
    'requisiti_pendenti', to_jsonb(v_account.requisiti_pendenti),
    'disabled_reason', v_account.disabled_reason
  );
end;
$$;


ALTER FUNCTION "public"."seller_payout_account_get"("p_seller_id" "uuid", "p_provider" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."seller_payout_account_upsert"("p_seller_id" "uuid", "p_provider" "text", "p_provider_account_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_account public.seller_payout_accounts%rowtype;
begin
  if p_seller_id is null
     or coalesce(p_provider, '') !~ '^[a-z0-9_]{2,32}$'
     or length(coalesce(p_provider_account_id, '')) not between 4 and 255 then
    raise exception 'Dati account di incasso non validi.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_seller_id) then
    raise exception 'Venditore non trovato.' using errcode = 'P0001';
  end if;

  insert into public.seller_payout_accounts (seller_id, provider, provider_account_id)
  values (p_seller_id, p_provider, p_provider_account_id)
  -- Un venditore ha un solo account per fornitore. Se esiste già, il chiamante
  -- riceve quello: non se ne apre un secondo, e l'identificativo non cambia.
  on conflict (seller_id, provider) do update
    set updated_at = now()
  returning * into v_account;

  return jsonb_build_object(
    'account_id', v_account.id,
    'provider_account_id', v_account.provider_account_id,
    'charges_enabled', v_account.charges_enabled,
    'payouts_enabled', v_account.payouts_enabled,
    'details_submitted', v_account.details_submitted,
    -- Vero quando esisteva già un account diverso da quello proposto: il
    -- chiamante deve sapere che il proprio è da scartare, non da usare.
    'riusato', v_account.provider_account_id <> p_provider_account_id
  );
end;
$_$;


ALTER FUNCTION "public"."seller_payout_account_upsert"("p_seller_id" "uuid", "p_provider" "text", "p_provider_account_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."slugifica"("p_testo" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO 'public'
    AS $$
  select coalesce(
    nullif(
      trim(both '-' from
        regexp_replace(
          translate(
            lower(replace(replace(coalesce(p_testo, ''), 'ß', 'ss'), 'æ', 'ae')),
            'àáâãäåèéêëìíîïòóôõöøùúûüçñýÿ',
            'aaaaaaeeeeiiiioooooouuuucnyy'
          ),
          '[^a-z0-9]+', '-', 'g'
        )
      ),
      ''
    ),
    'annuncio'
  );
$$;


ALTER FUNCTION "public"."slugifica"("p_testo" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."slugifica"("p_testo" "text") IS 'Normalizza testo libero in uno slug conforme al CHECK di wines.slug e listings.slug. Uso interno delle funzioni di creazione: non è concessa a nessun ruolo client.';



CREATE OR REPLACE FUNCTION "public"."sommelier_contesto_leggi"("p_owner_id" "uuid", "p_session_id" "text", "p_limite" integer) RETURNS TABLE("ruolo" "public"."sommelier_ruolo", "contenuto" "text", "created_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
  select * from private.sommelier_contesto_leggi($1, $2, $3);
$_$;


ALTER FUNCTION "public"."sommelier_contesto_leggi"("p_owner_id" "uuid", "p_session_id" "text", "p_limite" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sommelier_scambio_registra"("p_owner_id" "uuid", "p_session_id" "text", "p_domanda" "text", "p_risposta" "text") RETURNS integer
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
  select private.sommelier_scambio_registra($1, $2, $3, $4);
$_$;


ALTER FUNCTION "public"."sommelier_scambio_registra"("p_owner_id" "uuid", "p_session_id" "text", "p_domanda" "text", "p_risposta" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sommelier_storico_cancella"("p_session_id" "text") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "public"."sommelier_storico_cancella"("p_session_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."utente_maggiorenne"("p_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1
    from public.profiles p
    where p.id = p_user_id
      and p.dob is not null
      and p.dob <= (current_date - interval '18 years')
  );
$$;


ALTER FUNCTION "public"."utente_maggiorenne"("p_user_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."utente_maggiorenne"("p_user_id" "uuid") IS 'Vero solo se esiste un profilo con data di nascita dichiarata e almeno 18 anni compiuti. Fail-closed: profilo mancante o dob nullo restituiscono falso. Dichiarazione auto-riferita, non verifica d''identità.';



CREATE TABLE IF NOT EXISTS "public"."profile_certifications" (
    "user_id" "uuid" NOT NULL,
    "tipo" "public"."certificazione_tipo" NOT NULL,
    "fonte" "public"."certificazione_fonte" NOT NULL,
    "rilasciata_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "scade_at" timestamp with time zone,
    CONSTRAINT "profile_certifications_scadenza_dopo_rilascio" CHECK ((("scade_at" IS NULL) OR ("scade_at" > "rilasciata_at"))),
    CONSTRAINT "profile_certifications_solo_fonti_interne" CHECK (("fonte" = 'verifica_interna_vinea'::"public"."certificazione_fonte"))
);


ALTER TABLE "public"."profile_certifications" OWNER TO "postgres";


COMMENT ON TABLE "public"."profile_certifications" IS 'Certificazioni forti di profilo. Contiene esiti, mai prove: nessun documento, nessun identificativo di documento, nessun dato KYC e nessuna colonna di testo libero. Nessun privilegio per anon e authenticated; RLS attiva e zero policy. Si legge solo attraverso public.my_certifications (propria) e public.public_listings.seller_verificato (pubblica).';



COMMENT ON COLUMN "public"."profile_certifications"."scade_at" IS 'Fine validita. NULL significa senza scadenza. Una certificazione scaduta non viene proiettata da nessuna delle due viste.';



CREATE OR REPLACE VIEW "private"."certificazioni_valide" AS
 SELECT "user_id",
    "tipo"
   FROM "public"."profile_certifications" "c"
  WHERE (("rilasciata_at" <= "now"()) AND (("scade_at" IS NULL) OR ("scade_at" > "now"())));


ALTER VIEW "private"."certificazioni_valide" OWNER TO "postgres";


COMMENT ON VIEW "private"."certificazioni_valide" IS 'Certificazioni forti gia in vigore e non ancora scadute: una riga datata nel futuro non vale oggi. Unico luogo in cui la validita e definita: la leggono il trigger di scrittura e le due proiezioni. Nessun privilegio per anon e authenticated, che pure hanno USAGE sullo schema.';



CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "username" "text" NOT NULL,
    "bio" "text" DEFAULT ''::"text" NOT NULL,
    "citta" "text" DEFAULT ''::"text" NOT NULL,
    "provincia" "text" DEFAULT ''::"text" NOT NULL,
    "esperienza" "text" DEFAULT 'curioso'::"text" NOT NULL,
    "avatar_url" "text" DEFAULT ''::"text" NOT NULL,
    "dob" "date",
    "obiettivi" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "stato_utente" "public"."utente_stato" DEFAULT 'attivo'::"public"."utente_stato" NOT NULL,
    "provvedimenti" integer DEFAULT 0 NOT NULL,
    "stato_utente_at" timestamp with time zone,
    "stato_utente_motivo" "text",
    CONSTRAINT "profiles_avatar_url_vinea_check" CHECK ((("avatar_url" = ''::"text") OR ("avatar_url" = ANY (ARRAY['/avatar/calice.svg'::"text", '/avatar/bottiglia.svg'::"text", '/avatar/grappolo.svg'::"text", '/avatar/botte.svg'::"text", '/avatar/tappo.svg'::"text", '/avatar/decanter.svg'::"text"])) OR ("avatar_url" ~ (('^'::"text" || ("id")::"text") || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.webp$'::"text")))),
    CONSTRAINT "profiles_dob_check" CHECK (("dob" <= (CURRENT_DATE - '18 years'::interval))),
    CONSTRAINT "profiles_esperienza_check" CHECK (("esperienza" = ANY (ARRAY['curioso'::"text", 'appassionato'::"text", 'collezionista'::"text", 'esperto'::"text"]))),
    CONSTRAINT "profiles_provvedimenti_check" CHECK (("provvedimenti" >= 0)),
    CONSTRAINT "profiles_stato_utente_motivo_check" CHECK ((("stato_utente_motivo" IS NULL) OR (("length"("btrim"("stato_utente_motivo")) >= 1) AND ("length"("btrim"("stato_utente_motivo")) <= 4000))))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


COMMENT ON TABLE "public"."profiles" IS 'Profilo pubblico applicativo, 1:1 con auth.users. dob è una dichiarazione auto-riferita raccolta in fase di registrazione, non una verifica documentale.';



COMMENT ON COLUMN "public"."profiles"."dob" IS 'Dichiarazione auto-riferita di data di nascita. Il CHECK garantisce >= 18 anni lato server ma non costituisce verifica d''identità. Può essere NULL solo nella finestra fra il primo accesso OAuth e la dichiarazione dell''età raccolta da /completa-profilo.';



COMMENT ON COLUMN "public"."profiles"."stato_utente" IS 'Stato di moderazione. Scrivibile solo dalle funzioni di moderazione: il GRANT di UPDATE del client non contiene questa colonna e il trigger profiles_stato_utente_guard rifiuta la scrittura anche a service_role.';



COMMENT ON COLUMN "public"."profiles"."provvedimenti" IS 'Numero cumulativo di provvedimenti subiti. Decide il livello: al primo l''utente diventa `sospeso`, dal secondo `rimosso`. Un ripristino non lo azzera, altrimenti il secondo provvedimento non sarebbe mai il secondo.';



CREATE OR REPLACE VIEW "private"."profili_pubblici" WITH ("security_invoker"='off', "security_barrier"='true') AS
 SELECT "id" AS "user_id",
    "username",
    "bio",
    "citta",
    "provincia",
    "esperienza",
    "avatar_url"
   FROM "public"."profiles" "p"
  WHERE (("stato_utente" <> 'rimosso'::"public"."utente_stato") AND (NOT (EXISTS ( SELECT 1
           FROM "public"."profiles" "me"
          WHERE (("me"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("me"."stato_utente" = 'rimosso'::"public"."utente_stato"))))));


ALTER VIEW "private"."profili_pubblici" OWNER TO "postgres";


COMMENT ON VIEW "private"."profili_pubblici" IS 'Insieme dei profili pubblicamente visibili, con l''elenco chiuso delle sette colonne ammesse. Sta in `private` perche non deve essere raggiungibile da PostgREST: sarebbe la rubrica completa degli iscritti. Unico luogo in cui sono definite allowlist e visibilita (7.6b, entrambe le direzioni). Si legge solo attraverso public.profilo_pubblico(uuid), una riga per volta.';



CREATE TABLE IF NOT EXISTS "private"."rate_limit_buckets" (
    "scope" "text" NOT NULL,
    "subject" "text" NOT NULL,
    "window_started_at" timestamp with time zone NOT NULL,
    "window_seconds" integer NOT NULL,
    "request_count" integer NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    CONSTRAINT "rate_limit_buckets_request_count_check" CHECK (("request_count" > 0)),
    CONSTRAINT "rate_limit_buckets_window_seconds_check" CHECK ((("window_seconds" >= 1) AND ("window_seconds" <= 86400)))
);


ALTER TABLE "private"."rate_limit_buckets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."account_provider_events" (
    "provider" "text" NOT NULL,
    "event_id" "text" NOT NULL,
    "provider_event_type" "text" NOT NULL,
    "provider_account_id" "text" NOT NULL,
    "occurred_at" timestamp with time zone NOT NULL,
    "processed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "account_provider_events_provider_check" CHECK (("provider" ~ '^[a-z0-9_]{2,32}$'::"text")),
    CONSTRAINT "account_provider_events_provider_event_type_check" CHECK ((("length"("provider_event_type") >= 1) AND ("length"("provider_event_type") <= 120)))
);


ALTER TABLE "public"."account_provider_events" OWNER TO "postgres";


COMMENT ON TABLE "public"."account_provider_events" IS 'Registro di deduplicazione degli eventi di account, chiave (provider, event_id). Nessun grant a ruoli client.';



CREATE TABLE IF NOT EXISTS "public"."audit_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "ts" timestamp with time zone DEFAULT "now"() NOT NULL,
    "attore_id" "uuid",
    "attore_username" "text" NOT NULL,
    "scope" "public"."mod_scope" DEFAULT 'piattaforma'::"public"."mod_scope" NOT NULL,
    "club_slug" "text",
    "azione" "public"."mod_action" NOT NULL,
    "target_tipo" "public"."report_target_tipo" NOT NULL,
    "target_id" "uuid",
    "target_label" "text" NOT NULL,
    "motivazione" "text" NOT NULL,
    "durata" "text",
    "report_id" "uuid",
    CONSTRAINT "audit_log_attore_username_check" CHECK ((("length"("btrim"("attore_username")) >= 1) AND ("length"("btrim"("attore_username")) <= 120))),
    CONSTRAINT "audit_log_club_slug_check" CHECK ((("club_slug" IS NULL) OR ("club_slug" ~ '^[a-z0-9]+(-[a-z0-9]+)*$'::"text"))),
    CONSTRAINT "audit_log_durata_check" CHECK ((("durata" IS NULL) OR (("length"("btrim"("durata")) >= 1) AND ("length"("btrim"("durata")) <= 120)))),
    CONSTRAINT "audit_log_durata_solo_sospensione" CHECK ((("durata" IS NULL) OR ("azione" = 'sospensione'::"public"."mod_action"))),
    CONSTRAINT "audit_log_motivazione_check" CHECK ((("length"("btrim"("motivazione")) >= 1) AND ("length"("btrim"("motivazione")) <= 4000))),
    CONSTRAINT "audit_log_scope_club" CHECK ((("scope" = 'club'::"public"."mod_scope") = ("club_slug" IS NOT NULL))),
    CONSTRAINT "audit_log_target_label_check" CHECK ((("length"("btrim"("target_label")) >= 1) AND ("length"("btrim"("target_label")) <= 200)))
);


ALTER TABLE "public"."audit_log" OWNER TO "postgres";


COMMENT ON TABLE "public"."audit_log" IS 'Registro append-only delle azioni di moderazione. Nessun UPDATE e nessun DELETE, per nessun ruolo incluso service_role: il trigger sotto li rifiuta, perche un append-only che dipende solo dai GRANT resta append-only finche qualcuno non aggiunge un GRANT. Nessuna retention (decisione 7.3).';



CREATE TABLE IF NOT EXISTS "public"."bottle_units" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "wine_id" "uuid" NOT NULL,
    "stato" "public"."bottle_unit_stato" DEFAULT 'chiusa'::"public"."bottle_unit_stato" NOT NULL,
    "visibilita" "public"."bottle_unit_visibilita" DEFAULT 'privata'::"public"."bottle_unit_visibilita" NOT NULL,
    "deleted_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "apertura_pianificata" "date",
    "note_personali" "text" DEFAULT ''::"text" NOT NULL,
    "prezzo_visibilita" "public"."prezzo_visibilita" DEFAULT 'visibile'::"public"."prezzo_visibilita" NOT NULL,
    "override_finestra_inizio" smallint,
    "override_finestra_fine" smallint,
    "override_apice_inizio" smallint,
    "override_apice_fine" smallint,
    "override_preferenza" "public"."preferenza_evoluzione",
    "override_nota" "text" DEFAULT ''::"text" NOT NULL,
    "ceduta_at" timestamp with time zone,
    "immagini" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "degustazione_nota" "text" DEFAULT ''::"text" NOT NULL,
    "degustazione_at" timestamp with time zone,
    "acquired_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "acquisition_fonte" "public"."bottle_acquisition_fonte" DEFAULT 'sconosciuta'::"public"."bottle_acquisition_fonte" NOT NULL,
    "acquisition_cost_cents" integer,
    "consumed_at" timestamp with time zone,
    CONSTRAINT "bottle_units_acquired_at_plausibile" CHECK (("acquired_at" >= '1900-01-01 00:00:00+00'::timestamp with time zone)),
    CONSTRAINT "bottle_units_acquisition_cost_non_negativo" CHECK ((("acquisition_cost_cents" IS NULL) OR (("acquisition_cost_cents" >= 0) AND ("acquisition_cost_cents" <= 100000000)))),
    CONSTRAINT "bottle_units_override_apice_fine_check" CHECK ((("override_apice_fine" >= 1800) AND ("override_apice_fine" <= 2200))),
    CONSTRAINT "bottle_units_override_apice_inizio_check" CHECK ((("override_apice_inizio" >= 1800) AND ("override_apice_inizio" <= 2200))),
    CONSTRAINT "bottle_units_override_finestra_fine_check" CHECK ((("override_finestra_fine" >= 1800) AND ("override_finestra_fine" <= 2200))),
    CONSTRAINT "bottle_units_override_finestra_inizio_check" CHECK ((("override_finestra_inizio" >= 1800) AND ("override_finestra_inizio" <= 2200))),
    CONSTRAINT "bottle_units_override_ordinato" CHECK ((("override_finestra_inizio" IS NULL) OR ("override_finestra_fine" IS NULL) OR ("override_finestra_fine" >= "override_finestra_inizio")))
);


ALTER TABLE "public"."bottle_units" OWNER TO "postgres";


COMMENT ON TABLE "public"."bottle_units" IS 'Unità fisica di vino posseduta da un utente. Nessuna interfaccia in Fase 6a: serve solo perché un annuncio venda una bottiglia identificabile. Posizione fisica, ambienti, moduli e preset 3D arrivano con la Cantina.';



COMMENT ON COLUMN "public"."bottle_units"."visibilita" IS 'RESIDUO INERTE dalla Fase 9a. La cantina pubblica per singola bottiglia e stata rimossa con la decisione 7.7: dopo il drop di public_bottle_units nessun percorso mostra una bottle_unit a chi non ne e proprietario, quindi il valore cantina_pubblica non ha piu alcun effetto osservabile. La colonna sopravvive perche e un parametro di public.bottiglia_crea ed e scritta da frontend-next e da frontend, che restano congelati fino alla Fase 11: la sua rimozione appartiene alla lista di cutover, non a questa fase.';



COMMENT ON COLUMN "public"."bottle_units"."apertura_pianificata" IS 'Data in cui il proprietario ha programmato di aprire la bottiglia. frontend/docs/DOMAIN_MODEL.md elenca "programmata" fra gli stati: non lo è, è la presenza di questa data. Lo stato fisico resta chiusa/aperta/consumata, come deciso in 6a.';



COMMENT ON COLUMN "public"."bottle_units"."ceduta_at" IS 'Data in cui l''unità è uscita dal possesso del proprietario, valorizzata dal trigger listings_marca_bottiglia_ceduta quando un annuncio entra in ''venduto''. NON è un trasferimento di proprietà: owner_id non cambia e il compratore non è registrato da nessuna parte — quello è lavoro della Fase 7. Serve a impedire che una bottiglia già venduta torni in vendita.';



COMMENT ON COLUMN "public"."bottle_units"."immagini" IS 'Immagini della singola unita in cantina. Restano private al proprietario: dalla Fase 9a non esiste piu alcuna proiezione che mostri una bottle_unit a un non proprietario.';



COMMENT ON COLUMN "public"."bottle_units"."degustazione_nota" IS 'Nota di degustazione lasciata aprendo la bottiglia. Distinta da note_personali, che e'' la nota generica della bottiglia in cantina ed e'' scrivibile dal client: questa la scrive solo public.bottiglia_apri, che e'' SECURITY DEFINER, e non compare in nessun GRANT UPDATE per ruoli client.';



COMMENT ON COLUMN "public"."bottle_units"."degustazione_at" IS 'Quando la bottiglia e'' stata effettivamente aperta. Da non confondere con apertura_pianificata, che e'' la data PROGRAMMATA, di tipo date e scrivibile dal client. Nulla per le bottiglie aperte prima di questa migrazione: in produzione, al 18 agosto 2026, non ce n''era nessuna.';



COMMENT ON COLUMN "public"."bottle_units"."acquired_at" IS 'Quando la bottiglia è entrata nel possesso del proprietario. Per le unità preesistenti vale created_at, l''unica data reale disponibile. Il futuro è rifiutato dal trigger di ciclo di vita, non da un CHECK, perché now() non è immutabile.';



COMMENT ON COLUMN "public"."bottle_units"."acquisition_fonte" IS 'Provenienza del dato di costo, non provenienza della bottiglia. Vedi il commento del tipo: l''acquisto Vinea si deriva dall''ordine.';



COMMENT ON COLUMN "public"."bottle_units"."acquisition_cost_cents" IS 'Costo di acquisizione dichiarato, in centesimi. NULL significa SCONOSCIUTO e non zero: chi calcola deve escludere la bottiglia e contarla nella copertura. Resta NULL per le unità nate da un acquisto Vinea, il cui importo vive nel pagamento.';



COMMENT ON COLUMN "public"."bottle_units"."consumed_at" IS 'Quando la bottiglia è stata consumata. Scritto una volta sola dal trigger alla prima transizione verso `consumata` e mai riscritto. Non è ceduta_at (vendita) né deleted_at (rimozione del dato).';



CREATE TABLE IF NOT EXISTS "public"."cellar_environments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "nome" "text" NOT NULL,
    "forma" "public"."env_forma" NOT NULL,
    "tema" "public"."env_tema" NOT NULL,
    "materiale" "public"."env_materiale" NOT NULL,
    "illuminazione" "public"."env_illuminazione" NOT NULL,
    "larghezza_cm" integer NOT NULL,
    "altezza_cm" integer NOT NULL,
    "profondita_cm" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "cellar_environments_altezza_cm_check" CHECK ((("altezza_cm" >= 10) AND ("altezza_cm" <= 5000))),
    CONSTRAINT "cellar_environments_larghezza_cm_check" CHECK ((("larghezza_cm" >= 10) AND ("larghezza_cm" <= 5000))),
    CONSTRAINT "cellar_environments_nome_check" CHECK (("length"(TRIM(BOTH FROM "nome")) > 0)),
    CONSTRAINT "cellar_environments_profondita_cm_check" CHECK ((("profondita_cm" >= 10) AND ("profondita_cm" <= 5000)))
);


ALTER TABLE "public"."cellar_environments" OWNER TO "postgres";


COMMENT ON TABLE "public"."cellar_environments" IS 'Ambiente fisico di conservazione di un utente. Privato: nessuna policy lo espone a terzi, nemmeno quando contiene bottiglie dichiarate pubbliche — ciò che si rende pubblico è la bottiglia, non i mobili di casa propria.';



CREATE TABLE IF NOT EXISTS "public"."cellar_modules" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "environment_id" "uuid" NOT NULL,
    "etichetta" "text" NOT NULL,
    "posizione_x" numeric(6,2) DEFAULT 0 NOT NULL,
    "posizione_y" numeric(6,2) DEFAULT 0 NOT NULL,
    "posizione_z" numeric(6,2) DEFAULT 0 NOT NULL,
    "rotazione_y" numeric(6,2) DEFAULT 0 NOT NULL,
    "righe" smallint NOT NULL,
    "colonne" smallint NOT NULL,
    "profondita" smallint DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "cellar_modules_colonne_check" CHECK ((("colonne" >= 1) AND ("colonne" <= 50))),
    CONSTRAINT "cellar_modules_etichetta_check" CHECK (("length"(TRIM(BOTH FROM "etichetta")) > 0)),
    CONSTRAINT "cellar_modules_profondita_check" CHECK ((("profondita" >= 1) AND ("profondita" <= 10))),
    CONSTRAINT "cellar_modules_righe_check" CHECK ((("righe" >= 1) AND ("righe" <= 50)))
);


ALTER TABLE "public"."cellar_modules" OWNER TO "postgres";


COMMENT ON TABLE "public"."cellar_modules" IS 'Un modulo di stoccaggio dentro un ambiente. `righe` e `colonne` ne descrivono la geometria: le posizioni disponibili sono righe × colonne e si calcolano, non si memorizzano (vedi cellar_slots).';



CREATE TABLE IF NOT EXISTS "public"."cellar_slots" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "module_id" "uuid" NOT NULL,
    "bottle_unit_id" "uuid" NOT NULL,
    "riga" smallint NOT NULL,
    "colonna" smallint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "cellar_slots_colonna_check" CHECK (("colonna" >= 0)),
    CONSTRAINT "cellar_slots_riga_check" CHECK (("riga" >= 0))
);


ALTER TABLE "public"."cellar_slots" OWNER TO "postgres";


COMMENT ON TABLE "public"."cellar_slots" IS 'Posizione fisica di una bottiglia dentro un modulo. Una riga esiste solo se la posizione è occupata: le posizioni libere si ricavano dalla geometria del modulo (righe × colonne) meno quelle presenti qui.';



CREATE TABLE IF NOT EXISTS "public"."club_memberships" (
    "user_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "club_slug" "text" NOT NULL,
    "ruolo" "public"."club_ruolo" DEFAULT 'membro'::"public"."club_ruolo" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."club_memberships" OWNER TO "postgres";


COMMENT ON TABLE "public"."club_memberships" IS 'Chi segue quale club. Per club utente il creatore e inserito automaticamente
  da club_crea. Un utente vede e scrive soltanto le proprie righe.';



COMMENT ON COLUMN "public"."club_memberships"."user_id" IS 'Riempita dal DEFAULT auth.uid(), mai dal client: non e nel grant di INSERT. Nessun metodo del servizio accetta un userId.';



COMMENT ON COLUMN "public"."club_memberships"."ruolo" IS 'Colonna di dominio, fuori dal grant di INSERT e senza alcun grant di UPDATE: il client non la scrive. In 12a ha un solo valore possibile.';



CREATE TABLE IF NOT EXISTS "public"."club_post_like" (
    "user_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "post_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."club_post_like" OWNER TO "postgres";


COMMENT ON TABLE "public"."club_post_like" IS 'Chi ha messo mi piace a quale post. Un utente vede e scrive soltanto le proprie righe: l''elenco di chi ha messo like non e esposto a nessuno, e public_club_posts ne pubblica il solo conteggio piu lo stato del chiamante.';



CREATE TABLE IF NOT EXISTS "public"."club_post_risposte" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "post_id" "uuid" NOT NULL,
    "autore_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "corpo" "text" NOT NULL,
    "rimosso_at" timestamp with time zone,
    "rimosso_da" "uuid",
    "rimosso_motivo" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "club_post_risposte_corpo_check" CHECK ((("corpo" = "btrim"("corpo")) AND (("length"("corpo") >= 1) AND ("length"("corpo") <= 4000)))),
    CONSTRAINT "club_post_risposte_rimosso_motivo_check" CHECK ((("rimosso_motivo" IS NULL) OR (("length"("btrim"("rimosso_motivo")) >= 1) AND ("length"("btrim"("rimosso_motivo")) <= 4000)))),
    CONSTRAINT "club_post_risposte_rimozione_coerente" CHECK ((("rimosso_at" IS NULL) = ("rimosso_motivo" IS NULL)))
);


ALTER TABLE "public"."club_post_risposte" OWNER TO "postgres";


COMMENT ON TABLE "public"."club_post_risposte" IS 'Risposte a una discussione, un solo livello. Lettura pubblica attraverso public_club_post_risposte. Rimozione logica, porta in 12c.';



CREATE TABLE IF NOT EXISTS "public"."club_posts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "club_slug" "text" NOT NULL,
    "autore_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "tipo" "text" NOT NULL,
    "titolo" "text" NOT NULL,
    "corpo" "text" NOT NULL,
    "bottle_unit_id" "uuid",
    "wine_id" "uuid",
    "listing_id" "uuid",
    "rimosso_at" timestamp with time zone,
    "rimosso_da" "uuid",
    "rimosso_motivo" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "club_posts_annuncio_ha_listing" CHECK ((("tipo" <> 'annuncio'::"text") OR ("listing_id" IS NOT NULL))),
    CONSTRAINT "club_posts_corpo_check" CHECK ((("corpo" = "btrim"("corpo")) AND (("length"("corpo") >= 1) AND ("length"("corpo") <= 8000)))),
    CONSTRAINT "club_posts_rimosso_motivo_check" CHECK ((("rimosso_motivo" IS NULL) OR (("length"("btrim"("rimosso_motivo")) >= 1) AND ("length"("btrim"("rimosso_motivo")) <= 4000)))),
    CONSTRAINT "club_posts_rimozione_coerente" CHECK ((("rimosso_at" IS NULL) = ("rimosso_motivo" IS NULL))),
    CONSTRAINT "club_posts_tipo_check" CHECK (("tipo" = ANY (ARRAY['discussione'::"text", 'domanda'::"text", 'degustazione'::"text", 'confronto'::"text", 'consiglio'::"text", 'sondaggio'::"text", 'annuncio'::"text"]))),
    CONSTRAINT "club_posts_titolo_check" CHECK ((("titolo" = "btrim"("titolo")) AND (("length"("titolo") >= 3) AND ("length"("titolo") <= 160))))
);


ALTER TABLE "public"."club_posts" OWNER TO "postgres";


COMMENT ON TABLE "public"."club_posts" IS 'Discussioni di un club. Lettura pubblica attraverso public_club_posts; nessun ruolo client legge questa tabella oltre le proprie righe. La rimozione e logica (rimosso_at) e la sua unica porta e in 12c.';



COMMENT ON COLUMN "public"."club_posts"."autore_id" IS 'Riempita dal DEFAULT auth.uid(), mai dal client: non e nel grant di INSERT e nemmeno in quello di UPDATE. Nessun metodo del servizio accetta un userId.';



COMMENT ON COLUMN "public"."club_posts"."tipo" IS 'Uno dei sette valori di PostTipo del mock. CHECK e non enum: sono etichette di filtro della UI, non stati di una macchina. `sondaggio` non ha schema di sondaggio: e un post con titolo e corpo come gli altri.';



COMMENT ON COLUMN "public"."club_posts"."bottle_unit_id" IS 'Bottiglia dell''autore, verificata dal trigger dei riferimenti. La vista pubblica non ripubblica questo identificativo: espone il VINO, mai l''id della bottiglia, cosi nessuno correla una cantina fra piu post.';



COMMENT ON COLUMN "public"."club_posts"."listing_id" IS 'Annuncio collegato. Sempre pubblico; in piu, se tipo = ''annuncio'', dell''autore stesso. Vedi private.club_post_riferimenti_guard.';



COMMENT ON COLUMN "public"."club_posts"."rimosso_at" IS 'Rimozione logica decisa dalla moderazione. Fuori da ogni grant di UPDATE: l''unica porta e la 12c. Un post rimosso non e leggibile da public_club_posts e non e piu modificabile dal suo autore.';



CREATE TABLE IF NOT EXISTS "public"."conversation_participants" (
    "conversation_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "joined_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_read_message_id" "uuid",
    "last_read_created_at" timestamp with time zone,
    CONSTRAINT "conversation_participants_read_pair" CHECK ((("last_read_message_id" IS NULL) = ("last_read_created_at" IS NULL)))
);


ALTER TABLE "public"."conversation_participants" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."conversations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "participant_low" "uuid" NOT NULL,
    "participant_high" "uuid" NOT NULL,
    "listing_id" "uuid" NOT NULL,
    "order_id" "uuid",
    "last_message_id" "uuid",
    "last_message_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "conversations_canonical_pair" CHECK (("participant_low" < "participant_high")),
    CONSTRAINT "conversations_last_message_pair" CHECK ((("last_message_id" IS NULL) = ("last_message_at" IS NULL)))
);


ALTER TABLE "public"."conversations" OWNER TO "postgres";


COMMENT ON TABLE "public"."conversations" IS 'Conversazioni private 1:1 nate da un annuncio o da un ordine condiviso.';



CREATE TABLE IF NOT EXISTS "public"."disputes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "aperta_da" "uuid" NOT NULL,
    "motivo" "text" NOT NULL,
    "descrizione" "text" NOT NULL,
    "foto" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "stato" "public"."dispute_stato" DEFAULT 'aperta'::"public"."dispute_stato" NOT NULL,
    "esito_nota" "text",
    "risolta_da" "uuid",
    "apertura_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "chiusura_at" timestamp with time zone,
    CONSTRAINT "disputes_chiusura_coerente" CHECK ((("stato" = ANY (ARRAY['aperta'::"public"."dispute_stato", 'in_valutazione'::"public"."dispute_stato"])) = ("chiusura_at" IS NULL))),
    CONSTRAINT "disputes_descrizione_check" CHECK ((("length"("descrizione") >= 3) AND ("length"("descrizione") <= 2000))),
    CONSTRAINT "disputes_esito_nota_check" CHECK ((("esito_nota" IS NULL) OR ("length"("esito_nota") <= 1000))),
    CONSTRAINT "disputes_foto_check" CHECK (("cardinality"("foto") <= 8)),
    CONSTRAINT "disputes_motivo_check" CHECK ((("length"("motivo") >= 3) AND ("length"("motivo") <= 120)))
);


ALTER TABLE "public"."disputes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."listings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "slug" "text" NOT NULL,
    "seller_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "bottle_unit_id" "uuid" NOT NULL,
    "stato" "public"."listing_stato" DEFAULT 'bozza'::"public"."listing_stato" NOT NULL,
    "prezzo_cents" integer NOT NULL,
    "prezzo_mercato_cents" integer,
    "condizione" "text" DEFAULT 'Ottimo'::"text" NOT NULL,
    "conservazione" "text" DEFAULT ''::"text" NOT NULL,
    "storia" "text" DEFAULT ''::"text" NOT NULL,
    "degustazione" "text" DEFAULT ''::"text" NOT NULL,
    "immagini" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "tag" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "published_at" timestamp with time zone,
    "expires_at" timestamp with time zone,
    "stato_motivo" "text",
    "stato_aggiornato_da" "uuid",
    "stato_aggiornato_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reserved_by" "uuid",
    "reserved_until" timestamp with time zone,
    "imballaggio_codice" "text",
    CONSTRAINT "listings_condizione_check" CHECK (("condizione" = ANY (ARRAY['Perfetto'::"text", 'Ottimo'::"text", 'Buono'::"text"]))),
    CONSTRAINT "listings_imballaggio_codice_check" CHECK ((("imballaggio_codice" IS NULL) OR ("imballaggio_codice" ~ '^[a-z0-9_]{2,40}$'::"text"))),
    CONSTRAINT "listings_prezzo_cents_check" CHECK (("prezzo_cents" > 0)),
    CONSTRAINT "listings_prezzo_mercato_cents_check" CHECK (("prezzo_mercato_cents" > 0)),
    CONSTRAINT "listings_slug_check" CHECK (("slug" ~ '^[a-z0-9]+(-[a-z0-9]+)*$'::"text"))
);


ALTER TABLE "public"."listings" OWNER TO "postgres";


COMMENT ON TABLE "public"."listings" IS 'Annunci del marketplace. Un annuncio vende una singola bottle_unit. Lo stato non è mai scrivibile dal client: le colonne concesse in UPDATE escludono `stato`. In Fase 6a nessuna transizione è esposta, quindi solo un ruolo di servizio può cambiarlo; dalla Fase 6b lo faranno le funzioni di transizione SECURITY DEFINER.';



COMMENT ON COLUMN "public"."listings"."prezzo_cents" IS 'Prezzo in centesimi di euro. Intero, mai float.';



COMMENT ON COLUMN "public"."listings"."reserved_by" IS 'Compratore della prenotazione corrente. Mai scrivibile o leggibile dal client.';



COMMENT ON COLUMN "public"."listings"."reserved_until" IS 'Scadenza server-side della prenotazione corrente.';



COMMENT ON COLUMN "public"."listings"."imballaggio_codice" IS 'Modalità di consegna alla rete logistica dichiarata dal venditore. Ha una regola di dominio dietro (dev''essere un codice corrente), quindi NON entra nel GRANT UPDATE del client: si scrive solo da listing_imballaggio_dichiara.';



CREATE OR REPLACE VIEW "public"."listing_bottle_units" WITH ("security_invoker"='off') AS
 SELECT "l"."id" AS "listing_id",
    "bu"."id" AS "bottle_unit_id"
   FROM ("public"."listings" "l"
     JOIN "public"."bottle_units" "bu" ON (("bu"."id" = "l"."bottle_unit_id")))
  WHERE ("bu"."deleted_at" IS NULL);


ALTER VIEW "public"."listing_bottle_units" OWNER TO "postgres";


COMMENT ON VIEW "public"."listing_bottle_units" IS 'Le unità fisiche che un annuncio sta vendendo. Oggi è una per annuncio, perché il legame è uno a uno; quando diventerà uno-a-molti basterà cambiare questa vista, e il conteggio in public_listings seguirà.';



ALTER TABLE "public"."marketplace_config" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."marketplace_config_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "conversation_id" "uuid" NOT NULL,
    "sender_id" "uuid",
    "kind" "public"."message_kind" DEFAULT 'user'::"public"."message_kind" NOT NULL,
    "body" "text" NOT NULL,
    "idempotency_key" "uuid",
    "source_event_key" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "messages_actor_shape" CHECK (((("kind" = 'user'::"public"."message_kind") AND ("sender_id" IS NOT NULL) AND ("idempotency_key" IS NOT NULL) AND ("source_event_key" IS NULL)) OR (("kind" = 'system'::"public"."message_kind") AND ("sender_id" IS NULL) AND ("idempotency_key" IS NULL) AND ("source_event_key" IS NOT NULL)))),
    CONSTRAINT "messages_body_check" CHECK ((("body" = "btrim"("body")) AND (("length"("body") >= 1) AND ("length"("body") <= 2000)))),
    CONSTRAINT "messages_source_event_key_shape" CHECK ((("source_event_key" IS NULL) OR ((("length"("source_event_key") >= 8) AND ("length"("source_event_key") <= 180)) AND ("source_event_key" ~ '^[A-Za-z0-9._:-]+$'::"text"))))
);


ALTER TABLE "public"."messages" OWNER TO "postgres";


COMMENT ON TABLE "public"."messages" IS 'Messaggi immutabili. user passa solo da message_send; system solo da porte interne.';



CREATE TABLE IF NOT EXISTS "public"."user_roles" (
    "user_id" "uuid" NOT NULL,
    "role" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."user_roles" OWNER TO "postgres";


COMMENT ON TABLE "public"."user_roles" IS 'Ruoli applicativi per utente, separati da profiles per anti-escalation. Scrivibile solo da service_role o da funzioni SECURITY DEFINER dedicate.';



CREATE OR REPLACE VIEW "public"."moderation_audit_log" WITH ("security_invoker"='off', "security_barrier"='true') AS
 SELECT "id",
    "ts",
    "attore_username",
    "scope",
    "club_slug",
    "azione",
    "target_tipo",
    "target_id",
    "target_label",
    "motivazione",
    "durata",
    "report_id"
   FROM "public"."audit_log" "a"
  WHERE (EXISTS ( SELECT 1
           FROM "public"."user_roles" "ur"
          WHERE (("ur"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("ur"."role" = 'admin'::"text"))));


ALTER VIEW "public"."moderation_audit_log" OWNER TO "postgres";


COMMENT ON VIEW "public"."moderation_audit_log" IS 'Registro di moderazione in lettura, per il solo moderatore. attore_id non e esposto: attore_username e l''istantanea che il registro conserva ed e cio che il pannello mostra.';



CREATE OR REPLACE VIEW "public"."moderation_dispute_queue" WITH ("security_invoker"='off', "security_barrier"='true') AS
 SELECT "d"."id",
    "d"."order_id",
    "d"."aperta_da",
    "ap"."username" AS "aperta_da_username",
    "o"."seller_id",
    "sp"."username" AS "seller_username",
    "d"."motivo",
    "d"."descrizione",
    "d"."foto",
    "d"."stato",
    "d"."esito_nota",
    "d"."risolta_da",
    "d"."apertura_at",
    "d"."chiusura_at",
    "o"."stato" AS "ordine_stato",
    "o"."payout_stato" AS "ordine_payout_stato",
    "o"."totale_cents",
    "o"."addebito_totale_cents"
   FROM ((("public"."disputes" "d"
     JOIN "public"."orders" "o" ON (("o"."id" = "d"."order_id")))
     JOIN "public"."profiles" "ap" ON (("ap"."id" = "d"."aperta_da")))
     JOIN "public"."profiles" "sp" ON (("sp"."id" = "o"."seller_id")))
  WHERE (EXISTS ( SELECT 1
           FROM "public"."user_roles" "ur"
          WHERE (("ur"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("ur"."role" = 'admin'::"text"))));


ALTER VIEW "public"."moderation_dispute_queue" OWNER TO "postgres";


COMMENT ON VIEW "public"."moderation_dispute_queue" IS 'Coda contestazioni in sola lettura per il moderatore. Non duplica logica: la risoluzione resta ordine_contestazione_risolvi, stessa firma. Espone risolta_da, che e fuori dal grant client di disputes proprio perche e dato di moderazione.';



CREATE TABLE IF NOT EXISTS "public"."report_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "report_id" "uuid" NOT NULL,
    "visibile" boolean NOT NULL,
    "testo" "text" NOT NULL,
    "autore_id" "uuid",
    "autore_etichetta" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "report_events_autore_etichetta_check" CHECK ((("length"("btrim"("autore_etichetta")) >= 1) AND ("length"("btrim"("autore_etichetta")) <= 120))),
    CONSTRAINT "report_events_testo_check" CHECK ((("length"("btrim"("testo")) >= 1) AND ("length"("btrim"("testo")) <= 4000)))
);


ALTER TABLE "public"."report_events" OWNER TO "postgres";


COMMENT ON TABLE "public"."report_events" IS 'Storia della pratica. visibile = true e la storia che il segnalante legge; visibile = false sono le note interne, che nessuna proiezione raggiungibile dal segnalante espone.';



CREATE OR REPLACE VIEW "public"."moderation_report_events" WITH ("security_invoker"='off', "security_barrier"='true') AS
 SELECT "id",
    "report_id",
    "visibile",
    "testo",
    "autore_etichetta",
    "created_at"
   FROM "public"."report_events" "e"
  WHERE (EXISTS ( SELECT 1
           FROM "public"."user_roles" "ur"
          WHERE (("ur"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("ur"."role" = 'admin'::"text"))));


ALTER VIEW "public"."moderation_report_events" OWNER TO "postgres";


COMMENT ON VIEW "public"."moderation_report_events" IS 'Storia visibile e note interne insieme, per il solo moderatore. La controparte lato segnalante e my_report_events, che filtra visibile = true.';



CREATE OR REPLACE VIEW "public"."moderation_report_queue" WITH ("security_invoker"='off', "security_barrier"='true') AS
 SELECT "r"."id",
    "r"."codice",
    "r"."target_tipo",
    "r"."target_label",
    COALESCE("r"."target_listing_id", "r"."target_profile_id", "r"."target_message_id", "r"."target_conversation_id", "r"."target_review_id", "r"."target_post_id", "r"."target_risposta_id") AS "target_id",
    "r"."motivo",
    "r"."descrizione",
    "r"."foto",
    "r"."stato",
    "r"."priorita",
    "r"."reporter_id",
    "rp"."username" AS "reporter_username",
    "r"."club_slug",
    "r"."created_at",
    "r"."updated_at"
   FROM ("public"."reports" "r"
     JOIN "public"."profiles" "rp" ON (("rp"."id" = "r"."reporter_id")))
  WHERE (EXISTS ( SELECT 1
           FROM "public"."user_roles" "ur"
          WHERE (("ur"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("ur"."role" = 'admin'::"text"))));


ALTER VIEW "public"."moderation_report_queue" OWNER TO "postgres";


COMMENT ON VIEW "public"."moderation_report_queue" IS 'Coda condivisa delle segnalazioni (decisione 7.5: nessuna assegnazione). Visibile solo a chi ha il ruolo admin. Espone reporter_id e reporter_username per la decisione 7.4: il moderatore vede chi ha segnalato, il segnalato non raggiunge questa vista.';



CREATE OR REPLACE VIEW "public"."my_certifications" WITH ("security_invoker"='off', "security_barrier"='true') AS
 SELECT "id" AS "user_id",
    (EXISTS ( SELECT 1
           FROM "private"."certificazioni_valide" "v"
          WHERE (("v"."user_id" = "p"."id") AND ("v"."tipo" = 'identita'::"public"."certificazione_tipo")))) AS "identita_verificata",
    ((EXISTS ( SELECT 1
           FROM "private"."certificazioni_valide" "v"
          WHERE (("v"."user_id" = "p"."id") AND ("v"."tipo" = 'identita'::"public"."certificazione_tipo")))) AND (EXISTS ( SELECT 1
           FROM "private"."certificazioni_valide" "v"
          WHERE (("v"."user_id" = "p"."id") AND ("v"."tipo" = 'venditore'::"public"."certificazione_tipo"))))) AS "venditore_verificato"
   FROM "public"."profiles" "p"
  WHERE ("id" = ( SELECT "auth"."uid"() AS "uid"));


ALTER VIEW "public"."my_certifications" OWNER TO "postgres";


COMMENT ON VIEW "public"."my_certifications" IS 'Certificazioni forti della sola persona collegata, come booleani derivati. Zero righe per un chiamante anonimo. Non espone email, dob, documenti, fonte ne date.';



CREATE OR REPLACE VIEW "public"."my_listing_moderation" WITH ("security_invoker"='off', "security_barrier"='true') AS
 SELECT "id" AS "listing_id",
    "slug",
    "stato",
    "stato_motivo",
    "stato_aggiornato_at"
   FROM "public"."listings" "l"
  WHERE (("seller_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("stato_motivo" IS NOT NULL));


ALTER VIEW "public"."my_listing_moderation" OWNER TO "postgres";


COMMENT ON VIEW "public"."my_listing_moderation" IS 'Il motivo dell''ultima transizione di stato, per i soli annunci del chiamante. Esiste perche stato_motivo non e nel GRANT di colonna di listings e senza questa proiezione un rifiuto sarebbe senza spiegazione. Non espone stato_aggiornato_da, che e dato di moderazione.';



CREATE OR REPLACE VIEW "public"."my_report_events" WITH ("security_invoker"='off', "security_barrier"='true') AS
 SELECT "e"."id",
    "e"."report_id",
    "e"."testo",
    "e"."autore_etichetta",
    "e"."created_at"
   FROM ("public"."report_events" "e"
     JOIN "public"."reports" "r" ON (("r"."id" = "e"."report_id")))
  WHERE ("e"."visibile" AND ("r"."reporter_id" = ( SELECT "auth"."uid"() AS "uid")) AND (NOT (EXISTS ( SELECT 1
           FROM "public"."profiles" "me"
          WHERE (("me"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("me"."stato_utente" = 'rimosso'::"public"."utente_stato"))))));


ALTER VIEW "public"."my_report_events" OWNER TO "postgres";


COMMENT ON VIEW "public"."my_report_events" IS 'Solo le voci con visibile = true e solo delle proprie pratiche. Le note interne non hanno alcun percorso verso il segnalante.';



CREATE OR REPLACE VIEW "public"."my_reports" WITH ("security_invoker"='off', "security_barrier"='true') AS
 SELECT "id",
    "codice",
    "target_tipo",
    "target_label",
    "motivo",
    "descrizione",
    "foto",
    "stato",
    "priorita",
    "club_slug",
    "created_at",
    "updated_at"
   FROM "public"."reports" "r"
  WHERE (("reporter_id" = ( SELECT "auth"."uid"() AS "uid")) AND (NOT (EXISTS ( SELECT 1
           FROM "public"."profiles" "me"
          WHERE (("me"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("me"."stato_utente" = 'rimosso'::"public"."utente_stato"))))));


ALTER VIEW "public"."my_reports" OWNER TO "postgres";


COMMENT ON VIEW "public"."my_reports" IS 'Le segnalazioni del chiamante, per la schermata "Le mie segnalazioni". Nessuna nota interna e nessun dato di moderazione.';



CREATE TABLE IF NOT EXISTS "public"."sommelier_messaggi" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "session_id" "text" NOT NULL,
    "ruolo" "public"."sommelier_ruolo" NOT NULL,
    "contenuto" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "ordinale" bigint NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    CONSTRAINT "sommelier_messaggi_contenuto_check" CHECK ((("length"("contenuto") >= 1) AND ("length"("contenuto") <= 8000))),
    CONSTRAINT "sommelier_messaggi_session_id_check" CHECK (("session_id" ~ '^[A-Za-z0-9_-]{4,64}$'::"text"))
);

ALTER TABLE ONLY "public"."sommelier_messaggi" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."sommelier_messaggi" OWNER TO "postgres";


COMMENT ON TABLE "public"."sommelier_messaggi" IS 'Fase 10b. Storico della chat Sommelier. Chiusa a ogni ruolo client: si legge da public.my_sommelier_messages e si scrive dalle sole porte SECURITY DEFINER. Le righe con expires_at nel passato non sono piu leggibili ma NON vengono cancellate: nel v0 non esiste pulizia fisica, per decisione dell 11 agosto 2026.';



CREATE OR REPLACE VIEW "public"."my_sommelier_messages" WITH ("security_invoker"='off', "security_barrier"='true') AS
 SELECT "session_id",
    "ruolo",
    "contenuto",
    "created_at",
    "ordinale"
   FROM "public"."sommelier_messaggi" "m"
  WHERE (("owner_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("expires_at" > "now"()) AND (NOT (EXISTS ( SELECT 1
           FROM "public"."profiles" "me"
          WHERE (("me"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("me"."stato_utente" = 'rimosso'::"public"."utente_stato"))))));


ALTER VIEW "public"."my_sommelier_messages" OWNER TO "postgres";


COMMENT ON VIEW "public"."my_sommelier_messages" IS 'Fase 10b. Storico della propria chat Sommelier, filtrato su (owner_id, session_id): owner_id viene da auth.uid() dentro la vista e non e esposto. Applica anche il TTL e il secondo provvedimento della 7.6b.';



CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recipient_id" "uuid" NOT NULL,
    "category" "public"."notification_category" NOT NULL,
    "event_type" "text" NOT NULL,
    "body" "text" NOT NULL,
    "dedupe_key" "text" NOT NULL,
    "destination_kind" "public"."notification_destination_kind" DEFAULT 'none'::"public"."notification_destination_kind" NOT NULL,
    "destination_conversation_id" "uuid",
    "destination_listing_id" "uuid",
    "destination_order_id" "uuid",
    "destination_club_slug" "text",
    "read_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "notifications_body_check" CHECK ((("body" = "btrim"("body")) AND (("length"("body") >= 1) AND ("length"("body") <= 500)))),
    CONSTRAINT "notifications_dedupe_key_check" CHECK (((("length"("dedupe_key") >= 8) AND ("length"("dedupe_key") <= 180)) AND ("dedupe_key" ~ '^[A-Za-z0-9._:-]+$'::"text"))),
    CONSTRAINT "notifications_destination_shape" CHECK (
CASE "destination_kind"
    WHEN 'none'::"public"."notification_destination_kind" THEN (("destination_conversation_id" IS NULL) AND ("destination_listing_id" IS NULL) AND ("destination_order_id" IS NULL) AND ("destination_club_slug" IS NULL))
    WHEN 'conversation'::"public"."notification_destination_kind" THEN (("destination_conversation_id" IS NOT NULL) AND ("destination_listing_id" IS NULL) AND ("destination_order_id" IS NULL) AND ("destination_club_slug" IS NULL))
    WHEN 'listing'::"public"."notification_destination_kind" THEN (("destination_conversation_id" IS NULL) AND ("destination_listing_id" IS NOT NULL) AND ("destination_order_id" IS NULL) AND ("destination_club_slug" IS NULL))
    WHEN 'order'::"public"."notification_destination_kind" THEN (("destination_conversation_id" IS NULL) AND ("destination_listing_id" IS NULL) AND ("destination_order_id" IS NOT NULL) AND ("destination_club_slug" IS NULL))
    WHEN 'club'::"public"."notification_destination_kind" THEN (("destination_conversation_id" IS NULL) AND ("destination_listing_id" IS NULL) AND ("destination_order_id" IS NULL) AND ("destination_club_slug" IS NOT NULL) AND ("destination_club_slug" ~ '^[a-z0-9]+(-[a-z0-9]+)*$'::"text"))
    ELSE NULL::boolean
END),
    CONSTRAINT "notifications_event_type_check" CHECK (((("length"("event_type") >= 3) AND ("length"("event_type") <= 80)) AND ("event_type" ~ '^[a-z0-9_]+$'::"text")))
);


ALTER TABLE "public"."notifications" OWNER TO "postgres";


COMMENT ON TABLE "public"."notifications" IS 'Notifiche canoniche per destinatario, con destinazioni tipizzate e senza URL arbitrari.';



CREATE TABLE IF NOT EXISTS "public"."order_events" (
    "id" bigint NOT NULL,
    "order_id" "uuid" NOT NULL,
    "tipo" "text" NOT NULL,
    "payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "order_events_tipo_check" CHECK ((("length"("tipo") >= 1) AND ("length"("tipo") <= 80)))
);


ALTER TABLE "public"."order_events" OWNER TO "postgres";


ALTER TABLE "public"."order_events" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."order_events_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."payments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "provider" "text",
    "provider_session_id" "text",
    "provider_intent_id" "text",
    "checkout_url" "text",
    "stato" "public"."payment_stato" DEFAULT 'checkout_pending'::"public"."payment_stato" NOT NULL,
    "amount_cents" integer NOT NULL,
    "amount_refunded_cents" integer DEFAULT 0 NOT NULL,
    "currency" "text" NOT NULL,
    "provider_event_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "fee_stripe_reale_cents" integer,
    "fee_provider_transazione_id" "text",
    "fee_riconciliata_at" timestamp with time zone,
    CONSTRAINT "payments_amount_cents_check" CHECK (("amount_cents" > 0)),
    CONSTRAINT "payments_amount_refunded_cents_check" CHECK (("amount_refunded_cents" >= 0)),
    CONSTRAINT "payments_currency_check" CHECK (("currency" = 'eur'::"text")),
    CONSTRAINT "payments_fee_provider_transazione_id_check" CHECK ((("fee_provider_transazione_id" IS NULL) OR (("length"("fee_provider_transazione_id") >= 4) AND ("length"("fee_provider_transazione_id") <= 255)))),
    CONSTRAINT "payments_fee_stripe_reale_cents_check" CHECK ((("fee_stripe_reale_cents" IS NULL) OR ("fee_stripe_reale_cents" >= 0))),
    CONSTRAINT "payments_intent_needs_provider" CHECK ((("provider_intent_id" IS NULL) OR ("provider" IS NOT NULL))),
    CONSTRAINT "payments_provider_check" CHECK (("provider" ~ '^[a-z0-9_]{2,32}$'::"text")),
    CONSTRAINT "payments_provider_with_session" CHECK ((("provider" IS NULL) = ("provider_session_id" IS NULL))),
    CONSTRAINT "payments_refund_within_amount" CHECK (("amount_refunded_cents" <= "amount_cents"))
);


ALTER TABLE "public"."payments" OWNER TO "postgres";


COMMENT ON COLUMN "public"."payments"."provider" IS 'Fornitore presso cui è aperta la sessione di incasso, valorizzato da payment_checkout_attach insieme a provider_session_id.';



COMMENT ON COLUMN "public"."payments"."fee_stripe_reale_cents" IS 'Fee effettivamente trattenuta dal fornitore su questo incasso. Nulla finché non è nota: nulla significa "non misurata", mai "zero".';



COMMENT ON COLUMN "public"."payments"."fee_provider_transazione_id" IS 'Identificativo della transazione di saldo presso il fornitore. È l''appiglio con cui la fee reale viene recuperata quando l''evento non la porta con sé.';



CREATE OR REPLACE VIEW "public"."order_margine_riconciliazione" WITH ("security_invoker"='off', "security_barrier"='true') AS
 SELECT "o"."id" AS "order_id",
    "o"."created_at",
    "o"."prezzo_cents",
    "o"."commissione_cents",
    "o"."totale_cents",
    "o"."margine_obiettivo_bps",
    "o"."riferimento_stripe_percentuale_bps",
    "o"."riferimento_stripe_fisso_cents",
    "p"."stato" AS "payment_stato",
    "round"(((("o"."commissione_cents")::numeric * (10000)::numeric) / (NULLIF("o"."prezzo_cents", 0))::numeric), 2) AS "commissione_effettiva_bps",
    (("round"(((("o"."totale_cents")::numeric * ("o"."riferimento_stripe_percentuale_bps")::numeric) / (10000)::numeric)) + ("o"."riferimento_stripe_fisso_cents")::numeric))::integer AS "fee_riferimento_cents",
    ((((("o"."totale_cents")::numeric - "round"(((("o"."totale_cents")::numeric * ("o"."riferimento_stripe_percentuale_bps")::numeric) / (10000)::numeric))) - ("o"."riferimento_stripe_fisso_cents")::numeric) - ("o"."prezzo_cents")::numeric))::integer AS "margine_proiettato_cents",
    "p"."fee_stripe_reale_cents",
    (("o"."totale_cents" - "p"."fee_stripe_reale_cents") - "o"."prezzo_cents") AS "margine_reale_cents",
    ((((("o"."totale_cents" - "p"."fee_stripe_reale_cents") - "o"."prezzo_cents"))::numeric - (((("o"."totale_cents")::numeric - "round"(((("o"."totale_cents")::numeric * ("o"."riferimento_stripe_percentuale_bps")::numeric) / (10000)::numeric))) - ("o"."riferimento_stripe_fisso_cents")::numeric) - ("o"."prezzo_cents")::numeric)))::integer AS "scarto_cents",
    "p"."fee_riconciliata_at"
   FROM ("public"."orders" "o"
     JOIN "public"."payments" "p" ON (("p"."order_id" = "o"."id")));


ALTER VIEW "public"."order_margine_riconciliazione" OWNER TO "postgres";


COMMENT ON VIEW "public"."order_margine_riconciliazione" IS 'Margine proiettato contro margine reale, per ordine. Sola lettura, nessun GRANT verso ruoli client: è conto economico della piattaforma. Nessuna decisione di rilascio fondi dipende da queste colonne.';



CREATE TABLE IF NOT EXISTS "public"."packaging_options" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "codice" "text" NOT NULL,
    "provider" "text" NOT NULL,
    "modalita" "text" NOT NULL,
    "etichetta" "text" NOT NULL,
    "descrizione" "text",
    "prezzo_cents" integer NOT NULL,
    "richiede_punto" boolean DEFAULT false NOT NULL,
    "ordinamento" smallint DEFAULT 0 NOT NULL,
    "valida_da" timestamp with time zone DEFAULT "now"() NOT NULL,
    "valida_fino" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "packaging_options_codice_check" CHECK (("codice" ~ '^[a-z0-9_]{2,40}$'::"text")),
    CONSTRAINT "packaging_options_descrizione_check" CHECK ((("descrizione" IS NULL) OR ("length"("descrizione") <= 300))),
    CONSTRAINT "packaging_options_etichetta_check" CHECK ((("length"("etichetta") >= 2) AND ("length"("etichetta") <= 80))),
    CONSTRAINT "packaging_options_finestra" CHECK ((("valida_fino" IS NULL) OR ("valida_fino" > "valida_da"))),
    CONSTRAINT "packaging_options_modalita_check" CHECK (("modalita" = ANY (ARRAY['kit_a_domicilio'::"text", 'centro_partner'::"text", 'punto_quartiere'::"text"]))),
    CONSTRAINT "packaging_options_prezzo_cents_check" CHECK ((("prezzo_cents" >= 0) AND ("prezzo_cents" <= 100000))),
    CONSTRAINT "packaging_options_provider_check" CHECK (("provider" ~ '^[a-z0-9_]{2,32}$'::"text"))
);


ALTER TABLE "public"."packaging_options" OWNER TO "postgres";


COMMENT ON TABLE "public"."packaging_options" IS 'Listino delle modalità di consegna alla rete logistica, versionato su valida_da/valida_fino come marketplace_config. In Fase 7c il provider è «fake» e i prezzi sono zero: nessun accordo commerciale è reso esecutivo.';



CREATE TABLE IF NOT EXISTS "public"."payment_provider_events" (
    "provider" "text" NOT NULL,
    "event_id" "text" NOT NULL,
    "outcome" "public"."payment_outcome" NOT NULL,
    "provider_event_type" "text" NOT NULL,
    "occurred_at" timestamp with time zone NOT NULL,
    "processed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "payment_provider_events_provider_check" CHECK (("provider" ~ '^[a-z0-9_]{2,32}$'::"text")),
    CONSTRAINT "payment_provider_events_provider_event_type_check" CHECK ((("length"("provider_event_type") >= 1) AND ("length"("provider_event_type") <= 120)))
);


ALTER TABLE "public"."payment_provider_events" OWNER TO "postgres";


COMMENT ON TABLE "public"."payment_provider_events" IS 'Registro di deduplicazione degli eventi di incasso, con chiave (provider, event_id). provider_event_type è conservato a fini forensi e non è letto da nessun ramo della RPC.';



CREATE TABLE IF NOT EXISTS "public"."payouts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "seller_id" "uuid" NOT NULL,
    "provider" "text",
    "provider_transfer_id" "text",
    "destination_account_id" "text",
    "amount_cents" integer NOT NULL,
    "currency" "text" NOT NULL,
    "stato" "public"."payout_stato" DEFAULT 'in_attesa'::"public"."payout_stato" NOT NULL,
    "idempotency_key" "text" NOT NULL,
    "ultimo_errore" "text",
    "tentativi" integer DEFAULT 0 NOT NULL,
    "transferred_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "payouts_amount_cents_check" CHECK (("amount_cents" > 0)),
    CONSTRAINT "payouts_currency_check" CHECK (("currency" = 'eur'::"text")),
    CONSTRAINT "payouts_idempotency_key_check" CHECK (((("length"("idempotency_key") >= 8) AND ("length"("idempotency_key") <= 128)) AND ("idempotency_key" ~ '^[A-Za-z0-9._:-]+$'::"text"))),
    CONSTRAINT "payouts_provider_check" CHECK (("provider" ~ '^[a-z0-9_]{2,32}$'::"text")),
    CONSTRAINT "payouts_tentativi_check" CHECK (("tentativi" >= 0)),
    CONSTRAINT "payouts_transfer_needs_provider" CHECK ((("provider_transfer_id" IS NULL) OR ("provider" IS NOT NULL)))
);


ALTER TABLE "public"."payouts" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."public_club_post_risposte" WITH ("security_invoker"='off', "security_barrier"='true') AS
 SELECT "r"."id",
    "r"."post_id",
    "r"."corpo",
    "r"."created_at",
    "r"."autore_id",
    "au"."username" AS "autore_username",
    "au"."avatar_url" AS "autore_avatar_url",
    ("r"."autore_id" = ( SELECT "auth"."uid"() AS "uid")) AS "mio"
   FROM (("public"."club_post_risposte" "r"
     JOIN "public"."profiles" "au" ON (("au"."id" = "r"."autore_id")))
     JOIN "public"."club_posts" "p" ON (("p"."id" = "r"."post_id")))
  WHERE (("r"."rimosso_at" IS NULL) AND ("p"."rimosso_at" IS NULL) AND (NOT (EXISTS ( SELECT 1
           FROM "public"."profiles" "me"
          WHERE (("me"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("me"."stato_utente" = 'rimosso'::"public"."utente_stato"))))));


ALTER VIEW "public"."public_club_post_risposte" OWNER TO "postgres";


COMMENT ON VIEW "public"."public_club_post_risposte" IS 'Risposte leggibili da chiunque. Filtra sia la rimozione della risposta sia quella del post padre: rimuovere un post fa sparire la discussione intera senza toccare le sue risposte, che restano per l''eventuale ripristino.';



CREATE TABLE IF NOT EXISTS "public"."wines" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "slug" "text" NOT NULL,
    "produttore" "text" NOT NULL,
    "nome" "text" NOT NULL,
    "annata" smallint NOT NULL,
    "regione" "text" NOT NULL,
    "denominazione" "text" DEFAULT ''::"text" NOT NULL,
    "tipo" "text" NOT NULL,
    "formato" "text" DEFAULT '0,75 L'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "finestra_inizio" smallint,
    "finestra_fine" smallint,
    "apice_inizio" smallint,
    "apice_fine" smallint,
    "finestra_fonte" "public"."drink_window_fonte" DEFAULT 'unavailable'::"public"."drink_window_fonte" NOT NULL,
    "finestra_affidabilita" "public"."drink_window_affidabilita",
    "finestra_aggiornata_at" "date",
    "temperatura_servizio" "text" DEFAULT ''::"text" NOT NULL,
    "decantazione_minuti" smallint,
    "calice" "text" DEFAULT ''::"text" NOT NULL,
    "occasione" "text" DEFAULT ''::"text" NOT NULL,
    "abbinamenti" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "provenienza" "public"."wine_provenienza" DEFAULT 'staff'::"public"."wine_provenienza" NOT NULL,
    "creato_da" "uuid",
    CONSTRAINT "wines_abbinamenti_elenco" CHECK (("jsonb_typeof"("abbinamenti") = 'array'::"text")),
    CONSTRAINT "wines_annata_check" CHECK ((("annata" >= 1800) AND ("annata" <= 2100))),
    CONSTRAINT "wines_apice_dentro_finestra" CHECK (((("apice_inizio" IS NULL) OR ("finestra_inizio" IS NULL) OR ("apice_inizio" >= "finestra_inizio")) AND (("apice_fine" IS NULL) OR ("finestra_fine" IS NULL) OR ("apice_fine" <= "finestra_fine")))),
    CONSTRAINT "wines_apice_fine_check" CHECK ((("apice_fine" >= 1800) AND ("apice_fine" <= 2200))),
    CONSTRAINT "wines_apice_inizio_check" CHECK ((("apice_inizio" >= 1800) AND ("apice_inizio" <= 2200))),
    CONSTRAINT "wines_apice_ordinato" CHECK ((("apice_inizio" IS NULL) OR ("apice_fine" IS NULL) OR ("apice_fine" >= "apice_inizio"))),
    CONSTRAINT "wines_decantazione_minuti_check" CHECK ((("decantazione_minuti" >= 0) AND ("decantazione_minuti" <= 600))),
    CONSTRAINT "wines_finestra_fine_check" CHECK ((("finestra_fine" >= 1800) AND ("finestra_fine" <= 2200))),
    CONSTRAINT "wines_finestra_inizio_check" CHECK ((("finestra_inizio" >= 1800) AND ("finestra_inizio" <= 2200))),
    CONSTRAINT "wines_finestra_ordinata" CHECK ((("finestra_inizio" IS NULL) OR ("finestra_fine" IS NULL) OR ("finestra_fine" >= "finestra_inizio"))),
    CONSTRAINT "wines_nome_check" CHECK (("length"(TRIM(BOTH FROM "nome")) > 0)),
    CONSTRAINT "wines_produttore_check" CHECK (("length"(TRIM(BOTH FROM "produttore")) > 0)),
    CONSTRAINT "wines_regione_check" CHECK (("length"(TRIM(BOTH FROM "regione")) > 0)),
    CONSTRAINT "wines_slug_check" CHECK (("slug" ~ '^[a-z0-9]+(-[a-z0-9]+)*$'::"text")),
    CONSTRAINT "wines_tipo_check" CHECK (("tipo" = ANY (ARRAY['Rosso'::"text", 'Bianco'::"text", 'Bollicine'::"text", 'Rosato'::"text", 'Dolce'::"text"])))
);


ALTER TABLE "public"."wines" OWNER TO "postgres";


COMMENT ON TABLE "public"."wines" IS 'Catalogo vini con provenienza autoritativa. Le schede staff formano il catalogo curato; le schede utente restano distinguibili e sono condivise solo dalla tripletta produttore, nome e annata.';



COMMENT ON COLUMN "public"."wines"."slug" IS 'Identificatore pubblico stabile. Usato negli URL e come chiave verso i metadati ancora mock (finestra di bevuta, abbinamenti) in frontend-next/src/data/cellar.ts.';



COMMENT ON COLUMN "public"."wines"."tipo" IS 'Vincolato con CHECK e non con un ENUM: la sorgente di verità è l''unione TypeScript in frontend-next/src/data/wines.ts, e un CHECK si fa evolvere con una ALTER invece che con una migrazione di tipo.';



COMMENT ON COLUMN "public"."wines"."finestra_inizio" IS 'Primo anno in cui il vino si considera pronto. Nullo quando la finestra non è disponibile: in quel caso l''interfaccia mostra "informazione non disponibile" invece di inventare un intervallo.';



COMMENT ON COLUMN "public"."wines"."abbinamenti" IS 'Elenco di abbinamenti cibo, stessa forma di FoodPairing in frontend-next/src/data/cellar.ts. Nei dati d''origine lo stesso elenco è condiviso fra vini dello stesso stile (i rossi strutturati hanno gli stessi cinque abbinamenti): qui la condivisione si perde e ogni vino porta la propria copia. È la conseguenza accettata di tenerli come colonna.';



COMMENT ON COLUMN "public"."wines"."provenienza" IS 'Autorità della scheda: staff per il catalogo curato, utente per descrizioni immesse durante la catalogazione personale. Non è scrivibile dai client.';



COMMENT ON COLUMN "public"."wines"."creato_da" IS 'Utente che ha introdotto una scheda con provenienza utente. Nullo per il catalogo staff e per righe storiche il cui autore non è ricostruibile.';



CREATE OR REPLACE VIEW "public"."public_listings" WITH ("security_invoker"='off', "security_barrier"='true') AS
 SELECT "l"."id",
    "l"."slug",
    "l"."prezzo_cents",
    "l"."prezzo_mercato_cents",
    (( SELECT "count"(*) AS "count"
           FROM "public"."listing_bottle_units" "lbu"
          WHERE ("lbu"."listing_id" = "l"."id")))::integer AS "quantita",
    "l"."condizione",
    "l"."conservazione",
    "l"."storia",
    "l"."degustazione",
    "l"."immagini",
    "l"."tag",
    "l"."published_at",
    "l"."created_at",
    COALESCE("l"."published_at", "l"."created_at") AS "pubblicato_at",
    "w"."id" AS "wine_id",
    "w"."slug" AS "wine_slug",
    "w"."produttore",
    "w"."nome",
    "w"."annata",
    "w"."regione",
    "w"."denominazione",
    "w"."tipo",
    "w"."formato",
    (("w"."produttore" || ' '::"text") || "w"."nome") AS "ricerca",
    "p"."id" AS "seller_id",
    "p"."username" AS "seller_username",
    "p"."citta" AS "seller_citta",
    "p"."avatar_url" AS "seller_avatar_url",
    "w"."provenienza" AS "wine_provenienza",
    "l"."imballaggio_codice",
    ((EXISTS ( SELECT 1
           FROM "private"."certificazioni_valide" "v"
          WHERE (("v"."user_id" = "p"."id") AND ("v"."tipo" = 'identita'::"public"."certificazione_tipo")))) AND (EXISTS ( SELECT 1
           FROM "private"."certificazioni_valide" "v"
          WHERE (("v"."user_id" = "p"."id") AND ("v"."tipo" = 'venditore'::"public"."certificazione_tipo"))))) AS "seller_verificato"
   FROM ((("public"."listings" "l"
     JOIN "public"."bottle_units" "bu" ON (("bu"."id" = "l"."bottle_unit_id")))
     JOIN "public"."wines" "w" ON (("w"."id" = "bu"."wine_id")))
     JOIN "public"."profiles" "p" ON (("p"."id" = "l"."seller_id")))
  WHERE (("l"."stato" = 'attivo'::"public"."listing_stato") AND (("l"."expires_at" IS NULL) OR ("l"."expires_at" > "now"())) AND ("bu"."stato" = 'chiusa'::"public"."bottle_unit_stato") AND ("bu"."deleted_at" IS NULL) AND ("bu"."ceduta_at" IS NULL) AND ("bu"."owner_id" = "l"."seller_id") AND ("p"."stato_utente" <> 'rimosso'::"public"."utente_stato") AND (NOT (EXISTS ( SELECT 1
           FROM "public"."profiles" "me"
          WHERE (("me"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("me"."stato_utente" = 'rimosso'::"public"."utente_stato"))))));


ALTER VIEW "public"."public_listings" OWNER TO "postgres";


COMMENT ON VIEW "public"."public_listings" IS 'Catalogo pubblico. Dalla 9b esclude gli annunci di un venditore rimosso e restituisce zero righe a un chiamante rimosso (decisione 7.6b, secondo livello). Un chiamante anonimo non e toccato. Da questa migrazione porta anche `seller_verificato`: booleano derivato, vero solo con certificazione identita E venditore entrambe valide adesso.';



CREATE OR REPLACE VIEW "public"."public_club_posts" WITH ("security_invoker"='off', "security_barrier"='true') AS
 SELECT "p"."id",
    "p"."club_slug",
    "p"."tipo",
    "p"."titolo",
    "p"."corpo",
    "p"."created_at",
    "p"."autore_id",
    "au"."username" AS "autore_username",
    "au"."avatar_url" AS "autore_avatar_url",
    "w"."slug" AS "vino_slug",
    "w"."produttore" AS "vino_produttore",
    "w"."nome" AS "vino_nome",
    "w"."annata" AS "vino_annata",
    "p"."listing_id",
    "pl"."slug" AS "listing_slug",
    "pl"."prezzo_cents" AS "listing_prezzo_cents",
    (( SELECT "count"(*) AS "count"
           FROM "public"."club_post_risposte" "r"
          WHERE (("r"."post_id" = "p"."id") AND ("r"."rimosso_at" IS NULL))))::integer AS "risposte",
    (( SELECT "count"(*) AS "count"
           FROM "public"."club_post_like" "l"
          WHERE ("l"."post_id" = "p"."id")))::integer AS "mi_piace",
    (EXISTS ( SELECT 1
           FROM "public"."club_post_like" "l"
          WHERE (("l"."post_id" = "p"."id") AND ("l"."user_id" = ( SELECT "auth"."uid"() AS "uid"))))) AS "piaciuto",
    ("p"."autore_id" = ( SELECT "auth"."uid"() AS "uid")) AS "mio"
   FROM (((("public"."club_posts" "p"
     JOIN "public"."profiles" "au" ON (("au"."id" = "p"."autore_id")))
     LEFT JOIN "public"."bottle_units" "bu" ON (("bu"."id" = "p"."bottle_unit_id")))
     LEFT JOIN "public"."wines" "w" ON (("w"."id" = COALESCE("p"."wine_id", "bu"."wine_id"))))
     LEFT JOIN "public"."public_listings" "pl" ON (("pl"."id" = "p"."listing_id")))
  WHERE (("p"."rimosso_at" IS NULL) AND (NOT (EXISTS ( SELECT 1
           FROM "public"."profiles" "me"
          WHERE (("me"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("me"."stato_utente" = 'rimosso'::"public"."utente_stato"))))));


ALTER VIEW "public"."public_club_posts" OWNER TO "postgres";


COMMENT ON VIEW "public"."public_club_posts" IS 'Discussioni leggibili da chiunque, con i conteggi di risposte e like, lo stato `piaciuto` del solo chiamante e il vino di cui parlano. Non espone bottle_unit_id. Restituisce zero righe a un chiamante rimosso (7.6b, secondo livello); un chiamante anonimo non e toccato.';



CREATE OR REPLACE VIEW "public"."public_clubs" WITH ("security_invoker"='off', "security_barrier"='true') AS
 SELECT "c"."slug",
    "c"."nome",
    "c"."territorio",
    "c"."denominazione",
    "c"."produttore",
    "c"."tipologia",
    "c"."descrizione",
    "c"."regole",
    "c"."created_at",
    "c"."owner_id",
    "ow"."username" AS "owner_username",
    "c"."posting_mode",
    "c"."cover_image",
    (( SELECT "count"(*) AS "count"
           FROM "public"."club_memberships" "m"
          WHERE ("m"."club_slug" = "c"."slug")))::integer AS "membri",
    (EXISTS ( SELECT 1
           FROM "public"."club_memberships" "m"
          WHERE (("m"."club_slug" = "c"."slug") AND ("m"."user_id" = ( SELECT "auth"."uid"() AS "uid"))))) AS "seguito",
    (("c"."owner_id" IS NOT NULL) AND ("c"."owner_id" = ( SELECT "auth"."uid"() AS "uid"))) AS "mio"
   FROM ("public"."clubs" "c"
     LEFT JOIN "public"."profiles" "ow" ON (("ow"."id" = "c"."owner_id")))
  WHERE (NOT (EXISTS ( SELECT 1
           FROM "public"."profiles" "me"
          WHERE (("me"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("me"."stato_utente" = 'rimosso'::"public"."utente_stato")))));


ALTER VIEW "public"."public_clubs" OWNER TO "postgres";


COMMENT ON VIEW "public"."public_clubs" IS 'Club leggibili da chiunque, con owner_id, owner_username, posting_mode,
   cover_image, conteggio membri e stato seguito/mio del chiamante.
   Restituisce zero righe a un chiamante rimosso (decisione 7.6b, secondo
   livello).';



CREATE OR REPLACE VIEW "public"."public_marketplace_config" WITH ("security_invoker"='off', "security_barrier"='true') AS
 SELECT "margine_obiettivo_bps",
    "riferimento_stripe_percentuale_bps",
    "riferimento_stripe_fisso_cents",
    "auto_rilascio_giorni"
   FROM "public"."marketplace_config" "c"
  WHERE ("valida_fino" IS NULL);


ALTER VIEW "public"."public_marketplace_config" OWNER TO "postgres";


COMMENT ON VIEW "public"."public_marketplace_config" IS 'Sola configurazione corrente, a elenco colonne chiuso. Serve alla UI per calcolare un preventivo prima che l''ordine esista; non è la fonte di ciò che viene addebitato, che è congelato sull''ordine. I tre parametri sono pubblici perché il rincaro deve essere spiegabile a chi lo paga.';



CREATE OR REPLACE VIEW "public"."public_packaging_options" WITH ("security_invoker"='off', "security_barrier"='true') AS
 SELECT "codice",
    "provider",
    "modalita",
    "etichetta",
    "descrizione",
    "prezzo_cents",
    "richiede_punto",
    "ordinamento"
   FROM "public"."packaging_options"
  WHERE ("valida_fino" IS NULL);


ALTER VIEW "public"."public_packaging_options" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."report_reasons" (
    "target_tipo" "public"."report_target_tipo" NOT NULL,
    "motivo" "text" NOT NULL,
    "ordine" smallint NOT NULL
);


ALTER TABLE "public"."report_reasons" OWNER TO "postgres";


COMMENT ON TABLE "public"."report_reasons" IS 'Elenco chiuso dei motivi di segnalazione per tipo di bersaglio, da frontend/src/data/moderation.ts:35-61. E la sorgente del menu del client e insieme il vincolo referenziale di reports.motivo: le due cose non possono divergere. Non contiene righe di alcun utente, quindi il grant di tabella intera non viola la prima regola di esposizione.';



CREATE SEQUENCE IF NOT EXISTS "public"."reports_codice_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."reports_codice_seq" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."seller_payout_accounts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "seller_id" "uuid" NOT NULL,
    "provider" "text" NOT NULL,
    "provider_account_id" "text" NOT NULL,
    "charges_enabled" boolean DEFAULT false NOT NULL,
    "payouts_enabled" boolean DEFAULT false NOT NULL,
    "details_submitted" boolean DEFAULT false NOT NULL,
    "requisiti_pendenti" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "disabled_reason" "text",
    "provider_event_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "seller_payout_accounts_provider_account_id_check" CHECK ((("length"("provider_account_id") >= 4) AND ("length"("provider_account_id") <= 255))),
    CONSTRAINT "seller_payout_accounts_provider_check" CHECK (("provider" ~ '^[a-z0-9_]{2,32}$'::"text"))
);


ALTER TABLE "public"."seller_payout_accounts" OWNER TO "postgres";


COMMENT ON TABLE "public"."seller_payout_accounts" IS 'Stato dell''account di incasso del venditore presso un fornitore. charges_enabled e payouts_enabled arrivano solo da eventi firmati: sono la condizione che rende vero il ruolo seller_enabled.';



ALTER TABLE "public"."sommelier_messaggi" ALTER COLUMN "ordinale" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."sommelier_messaggi_ordinale_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."tracking_events" (
    "id" bigint NOT NULL,
    "order_id" "uuid" NOT NULL,
    "tipo" "public"."tracking_event_tipo" NOT NULL,
    "titolo" "text" NOT NULL,
    "descrizione" "text",
    "luogo" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "tracking_events_descrizione_check" CHECK ((("descrizione" IS NULL) OR ("length"("descrizione") <= 500))),
    CONSTRAINT "tracking_events_luogo_check" CHECK ((("luogo" IS NULL) OR ("length"("luogo") <= 120))),
    CONSTRAINT "tracking_events_titolo_check" CHECK ((("length"("titolo") >= 1) AND ("length"("titolo") <= 120)))
);


ALTER TABLE "public"."tracking_events" OWNER TO "postgres";


COMMENT ON TABLE "public"."tracking_events" IS 'Timeline utente dell''ordine. Nessun GRANT di scrittura ai client: le righe nascono solo da funzioni SECURITY DEFINER e da trigger. Un client che potesse inserire scriverebbe «Consegnato» su un ordine mai partito.';



ALTER TABLE "public"."tracking_events" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."tracking_events_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."wine_price_observations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "wine_id" "uuid" NOT NULL,
    "formato" "text" NOT NULL,
    "tipo" "public"."price_observation_tipo" NOT NULL,
    "fonte" "public"."price_observation_fonte" NOT NULL,
    "prezzo_cents" integer NOT NULL,
    "valuta" "text" DEFAULT 'eur'::"text" NOT NULL,
    "observed_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "origine_ref" "uuid" NOT NULL,
    CONSTRAINT "wine_price_observations_formato_check" CHECK (("length"(TRIM(BOTH FROM "formato")) > 0)),
    CONSTRAINT "wine_price_observations_prezzo_cents_check" CHECK (("prezzo_cents" > 0)),
    CONSTRAINT "wine_price_observations_solo_fonti_interne" CHECK (("fonte" = 'vinea_interno'::"public"."price_observation_fonte")),
    CONSTRAINT "wine_price_observations_valuta_check" CHECK (("valuta" = 'eur'::"text"))
);


ALTER TABLE "public"."wine_price_observations" OWNER TO "postgres";


COMMENT ON TABLE "public"."wine_price_observations" IS 'Registro append-only dei prezzi osservati da Price Intelligence. Nessun UPDATE e nessun DELETE, per nessun ruolo, service_role e proprietario compresi: sono trigger e non solo GRANT, perche'' un GRANT non vincola il proprietario della tabella. Il client non ha alcun privilegio di scrittura e la lettura passa dalla vista public.wine_price_history.';



COMMENT ON COLUMN "public"."wine_price_observations"."observed_at" IS 'Istante reale del fatto osservato. Per una vendita e'' orders.paid_at, non l''istante della registrazione: quello e'' created_at.';



COMMENT ON COLUMN "public"."wine_price_observations"."origine_ref" IS 'Annuncio (richiesta) o ordine (vendita). Identificativo tecnico interno: non esce dalla vista pubblica e non e'' un dato personale.';



CREATE OR REPLACE VIEW "public"."wine_price_history" WITH ("security_invoker"='off') AS
 SELECT "o"."wine_id",
    "w"."slug" AS "wine_slug",
    "w"."produttore",
    "w"."nome",
    "w"."annata",
    "o"."formato",
    "o"."tipo",
    "o"."fonte",
    "o"."prezzo_cents",
    "o"."valuta",
    "o"."observed_at"
   FROM ("public"."wine_price_observations" "o"
     JOIN "public"."wines" "w" ON (("w"."id" = "o"."wine_id")));


ALTER VIEW "public"."wine_price_history" OWNER TO "postgres";


COMMENT ON VIEW "public"."wine_price_history" IS 'Serie storica dei prezzi osservati, per vino e formato. Elenco chiuso di colonne: nessun identificativo di annuncio, ordine, venditore o compratore, e nessun dato personale. Non aggrega nulla - media, intervallo e affidabilita'' sono decisioni della Fase 1B.';



CREATE TABLE IF NOT EXISTS "public"."wine_reference_snapshots" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "wine_id" "uuid" NOT NULL,
    "formato" "text" NOT NULL,
    "mediana_cents" integer,
    "minimo_cents" integer,
    "massimo_cents" integer,
    "comparabili" integer NOT NULL,
    "valuta" "text" DEFAULT 'EUR'::"text" NOT NULL,
    "observed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "wine_reference_snapshots_comparabili_check" CHECK (("comparabili" >= 0)),
    CONSTRAINT "wine_reference_snapshots_formato_check" CHECK (("length"(TRIM(BOTH FROM "formato")) > 0)),
    CONSTRAINT "wine_reference_snapshots_massimo_cents_check" CHECK ((("massimo_cents" IS NULL) OR ("massimo_cents" > 0))),
    CONSTRAINT "wine_reference_snapshots_mediana_cents_check" CHECK ((("mediana_cents" IS NULL) OR ("mediana_cents" > 0))),
    CONSTRAINT "wine_reference_snapshots_minimo_cents_check" CHECK ((("minimo_cents" IS NULL) OR ("minimo_cents" > 0))),
    CONSTRAINT "wine_reference_snapshots_range" CHECK ((("mediana_cents" IS NULL) OR (("minimo_cents" <= "mediana_cents") AND ("mediana_cents" <= "massimo_cents")))),
    CONSTRAINT "wine_reference_snapshots_soglia" CHECK (((("comparabili" >= 3) AND ("mediana_cents" IS NOT NULL) AND ("minimo_cents" IS NOT NULL) AND ("massimo_cents" IS NOT NULL)) OR (("comparabili" < 3) AND ("mediana_cents" IS NULL) AND ("minimo_cents" IS NULL) AND ("massimo_cents" IS NULL)))),
    CONSTRAINT "wine_reference_snapshots_valuta_check" CHECK (("valuta" = 'EUR'::"text"))
);


ALTER TABLE "public"."wine_reference_snapshots" OWNER TO "postgres";


COMMENT ON TABLE "public"."wine_reference_snapshots" IS 'Storico SOLO IN AVANTI del riferimento Vinea per vino e formato. Una riga nasce quando il riferimento cambia davvero, mai a intervalli e mai all''apertura di una pagina. Non esiste alcuna riga anteriore alla migrazione che ha creato la tabella: lo storico precedente non è vuoto, è non disponibile.';



COMMENT ON COLUMN "public"."wine_reference_snapshots"."mediana_cents" IS 'Mediana dei prezzi richiesti degli annunci attivi comparabili. NULL quando i comparabili sono meno di tre: riferimento non disponibile, non zero.';



COMMENT ON COLUMN "public"."wine_reference_snapshots"."comparabili" IS 'Quanti annunci attivi hanno prodotto questo snapshot. Sotto tre la mediana è NULL per costruzione (vincolo _soglia).';



CREATE TABLE IF NOT EXISTS "public"."wine_regions" (
    "nome" "text" NOT NULL,
    "ordine" smallint DEFAULT 1000 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "wine_regions_nome_check" CHECK ((("length"("btrim"("nome")) > 0) AND ("nome" = "btrim"("nome")))),
    CONSTRAINT "wine_regions_ordine_check" CHECK (("ordine" >= 0))
);


ALTER TABLE "public"."wine_regions" OWNER TO "postgres";


COMMENT ON TABLE "public"."wine_regions" IS 'Tassonomia canonica delle regioni del vino. Unica fonte di verita per la regione di una scheda vino: `public.wines.regione` la referenzia con una chiave esterna validata. Cresce per INSERT, mai per ALTER di tipo.';



COMMENT ON COLUMN "public"."wine_regions"."nome" IS 'Nome canonico, chiave primaria. E il valore letterale memorizzato in public.wines.regione: nessuna JOIN necessaria per leggerlo.';



COMMENT ON COLUMN "public"."wine_regions"."ordine" IS 'Ordinamento di presentazione. Non unico: le letture ordinano per (ordine, nome), che resta deterministico anche a parita di ordine.';



ALTER TABLE ONLY "private"."rate_limit_buckets"
    ADD CONSTRAINT "rate_limit_buckets_pkey" PRIMARY KEY ("scope", "subject", "window_started_at");



ALTER TABLE ONLY "public"."account_provider_events"
    ADD CONSTRAINT "account_provider_events_pkey" PRIMARY KEY ("provider", "event_id");



ALTER TABLE ONLY "public"."audit_log"
    ADD CONSTRAINT "audit_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."bottle_units"
    ADD CONSTRAINT "bottle_units_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cellar_environments"
    ADD CONSTRAINT "cellar_environments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cellar_modules"
    ADD CONSTRAINT "cellar_modules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cellar_slots"
    ADD CONSTRAINT "cellar_slots_bottiglia_unica" UNIQUE ("bottle_unit_id");



ALTER TABLE ONLY "public"."cellar_slots"
    ADD CONSTRAINT "cellar_slots_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cellar_slots"
    ADD CONSTRAINT "cellar_slots_posizione_unica" UNIQUE ("module_id", "riga", "colonna");



ALTER TABLE ONLY "public"."club_memberships"
    ADD CONSTRAINT "club_memberships_pkey" PRIMARY KEY ("user_id", "club_slug");



ALTER TABLE ONLY "public"."club_post_like"
    ADD CONSTRAINT "club_post_like_pkey" PRIMARY KEY ("user_id", "post_id");



ALTER TABLE ONLY "public"."club_post_risposte"
    ADD CONSTRAINT "club_post_risposte_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."club_posts"
    ADD CONSTRAINT "club_posts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."clubs"
    ADD CONSTRAINT "clubs_pkey" PRIMARY KEY ("slug");



ALTER TABLE ONLY "public"."conversation_participants"
    ADD CONSTRAINT "conversation_participants_pkey" PRIMARY KEY ("conversation_id", "user_id");



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_listing_pair_unique" UNIQUE ("listing_id", "participant_low", "participant_high");



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_order_id_key" UNIQUE ("order_id");



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."disputes"
    ADD CONSTRAINT "disputes_order_id_key" UNIQUE ("order_id");



ALTER TABLE ONLY "public"."disputes"
    ADD CONSTRAINT "disputes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."listings"
    ADD CONSTRAINT "listings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."listings"
    ADD CONSTRAINT "listings_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."marketplace_config"
    ADD CONSTRAINT "marketplace_config_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_conversation_id_unique" UNIQUE ("conversation_id", "id");



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_conversation_idempotency_unique" UNIQUE ("conversation_id", "idempotency_key");



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_recipient_dedupe_unique" UNIQUE ("recipient_id", "dedupe_key");



ALTER TABLE ONLY "public"."order_events"
    ADD CONSTRAINT "order_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."order_reviews"
    ADD CONSTRAINT "order_reviews_order_id_key" UNIQUE ("order_id");



ALTER TABLE ONLY "public"."order_reviews"
    ADD CONSTRAINT "order_reviews_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_buyer_bottle_unit_id_key" UNIQUE ("buyer_bottle_unit_id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_buyer_idempotency_unique" UNIQUE ("buyer_id", "idempotency_key");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."packaging_options"
    ADD CONSTRAINT "packaging_options_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."payment_provider_events"
    ADD CONSTRAINT "payment_provider_events_pkey" PRIMARY KEY ("provider", "event_id");



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_order_id_key" UNIQUE ("order_id");



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_provider_intent_unique" UNIQUE ("provider", "provider_intent_id");



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_provider_session_unique" UNIQUE ("provider", "provider_session_id");



ALTER TABLE ONLY "public"."payouts"
    ADD CONSTRAINT "payouts_idempotency_key_key" UNIQUE ("idempotency_key");



ALTER TABLE ONLY "public"."payouts"
    ADD CONSTRAINT "payouts_order_id_key" UNIQUE ("order_id");



ALTER TABLE ONLY "public"."payouts"
    ADD CONSTRAINT "payouts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."payouts"
    ADD CONSTRAINT "payouts_transfer_unico" UNIQUE ("provider", "provider_transfer_id");



ALTER TABLE ONLY "public"."profile_certifications"
    ADD CONSTRAINT "profile_certifications_pkey" PRIMARY KEY ("user_id", "tipo");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_username_key" UNIQUE ("username");



ALTER TABLE ONLY "public"."proposals"
    ADD CONSTRAINT "proposals_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."report_events"
    ADD CONSTRAINT "report_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."report_reasons"
    ADD CONSTRAINT "report_reasons_pkey" PRIMARY KEY ("target_tipo", "motivo");



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_codice_key" UNIQUE ("codice");



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."seller_payout_accounts"
    ADD CONSTRAINT "seller_payout_accounts_account_unico" UNIQUE ("provider", "provider_account_id");



ALTER TABLE ONLY "public"."seller_payout_accounts"
    ADD CONSTRAINT "seller_payout_accounts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."seller_payout_accounts"
    ADD CONSTRAINT "seller_payout_accounts_uno_per_provider" UNIQUE ("seller_id", "provider");



ALTER TABLE ONLY "public"."sommelier_messaggi"
    ADD CONSTRAINT "sommelier_messaggi_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tracking_events"
    ADD CONSTRAINT "tracking_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_pkey" PRIMARY KEY ("user_id", "role");



ALTER TABLE ONLY "public"."wine_price_observations"
    ADD CONSTRAINT "wine_price_observations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wine_reference_snapshots"
    ADD CONSTRAINT "wine_reference_snapshots_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wine_regions"
    ADD CONSTRAINT "wine_regions_pkey" PRIMARY KEY ("nome");



ALTER TABLE ONLY "public"."wines"
    ADD CONSTRAINT "wines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wines"
    ADD CONSTRAINT "wines_produttore_nome_annata_key" UNIQUE ("produttore", "nome", "annata");



ALTER TABLE ONLY "public"."wines"
    ADD CONSTRAINT "wines_slug_key" UNIQUE ("slug");



CREATE INDEX "rate_limit_buckets_expires_idx" ON "private"."rate_limit_buckets" USING "btree" ("expires_at");



CREATE INDEX "audit_log_target_idx" ON "public"."audit_log" USING "btree" ("target_tipo", "target_id", "ts" DESC);



CREATE INDEX "audit_log_ts_idx" ON "public"."audit_log" USING "btree" ("ts" DESC, "id" DESC);



CREATE INDEX "bottle_units_in_possesso_idx" ON "public"."bottle_units" USING "btree" ("owner_id") WHERE (("deleted_at" IS NULL) AND ("ceduta_at" IS NULL));



CREATE INDEX "bottle_units_owner_idx" ON "public"."bottle_units" USING "btree" ("owner_id") WHERE ("deleted_at" IS NULL);



CREATE INDEX "bottle_units_wine_idx" ON "public"."bottle_units" USING "btree" ("wine_id");



CREATE INDEX "cellar_environments_owner_idx" ON "public"."cellar_environments" USING "btree" ("owner_id");



CREATE INDEX "cellar_modules_environment_idx" ON "public"."cellar_modules" USING "btree" ("environment_id");



CREATE INDEX "cellar_slots_module_idx" ON "public"."cellar_slots" USING "btree" ("module_id");



CREATE INDEX "club_memberships_club_slug_idx" ON "public"."club_memberships" USING "btree" ("club_slug");



COMMENT ON INDEX "public"."club_memberships_club_slug_idx" IS 'Conteggio membri per club (public_clubs.membri) e, dal 12b, la lettura per club. La direzione per utente la copre gia l''indice della chiave primaria.';



CREATE INDEX "club_post_like_post_idx" ON "public"."club_post_like" USING "btree" ("post_id");



CREATE INDEX "club_post_risposte_autore_idx" ON "public"."club_post_risposte" USING "btree" ("autore_id", "created_at" DESC);



CREATE INDEX "club_post_risposte_post_idx" ON "public"."club_post_risposte" USING "btree" ("post_id", "created_at") WHERE ("rimosso_at" IS NULL);



CREATE INDEX "club_posts_autore_idx" ON "public"."club_posts" USING "btree" ("autore_id", "created_at" DESC);



CREATE INDEX "club_posts_club_idx" ON "public"."club_posts" USING "btree" ("club_slug", "created_at" DESC) WHERE ("rimosso_at" IS NULL);



CREATE INDEX "club_posts_listing_idx" ON "public"."club_posts" USING "btree" ("listing_id") WHERE ("listing_id" IS NOT NULL);



CREATE INDEX "conversation_participants_user_idx" ON "public"."conversation_participants" USING "btree" ("user_id", "conversation_id");



CREATE INDEX "conversations_high_activity_idx" ON "public"."conversations" USING "btree" ("participant_high", "last_message_at" DESC NULLS LAST, "created_at" DESC, "id" DESC);



CREATE INDEX "conversations_low_activity_idx" ON "public"."conversations" USING "btree" ("participant_low", "last_message_at" DESC NULLS LAST, "created_at" DESC, "id" DESC);



CREATE INDEX "listings_bottle_unit_idx" ON "public"."listings" USING "btree" ("bottle_unit_id");



CREATE INDEX "listings_prezzo_idx" ON "public"."listings" USING "btree" ("prezzo_cents");



CREATE INDEX "listings_pubblici_recenti_idx" ON "public"."listings" USING "btree" (COALESCE("published_at", "created_at") DESC) WHERE ("stato" = 'attivo'::"public"."listing_stato");



CREATE INDEX "listings_reservation_idx" ON "public"."listings" USING "btree" ("reserved_until") WHERE ("stato" = 'riservato'::"public"."listing_stato");



CREATE INDEX "listings_seller_idx" ON "public"."listings" USING "btree" ("seller_id");



CREATE INDEX "listings_stato_aggiornato_da_idx" ON "public"."listings" USING "btree" ("stato_aggiornato_da") WHERE ("stato_aggiornato_da" IS NOT NULL);



CREATE INDEX "listings_stato_idx" ON "public"."listings" USING "btree" ("stato");



CREATE UNIQUE INDEX "listings_un_solo_annuncio_non_terminale" ON "public"."listings" USING "btree" ("bottle_unit_id") WHERE ("stato" = ANY (ARRAY['bozza'::"public"."listing_stato", 'in_revisione'::"public"."listing_stato", 'modifiche_richieste'::"public"."listing_stato", 'attivo'::"public"."listing_stato", 'riservato'::"public"."listing_stato"]));



COMMENT ON INDEX "public"."listings_un_solo_annuncio_non_terminale" IS 'Un annuncio vende una sola bottiglia fisica e una bottiglia ha un solo annuncio non terminale. Sostituisce listings_una_sola_attiva_per_bottiglia della 6a, che copriva i soli stati vivi e lasciava passare più bozze.';



CREATE INDEX "marketplace_config_storico_idx" ON "public"."marketplace_config" USING "btree" ("valida_da" DESC);



CREATE UNIQUE INDEX "marketplace_config_una_corrente" ON "public"."marketplace_config" USING "btree" ((("valida_fino" IS NULL))) WHERE ("valida_fino" IS NULL);



CREATE INDEX "messages_conversation_page_idx" ON "public"."messages" USING "btree" ("conversation_id", "created_at" DESC, "id" DESC);



CREATE UNIQUE INDEX "messages_conversation_source_event_unique" ON "public"."messages" USING "btree" ("conversation_id", "source_event_key") WHERE ("source_event_key" IS NOT NULL);



CREATE INDEX "messages_sender_idx" ON "public"."messages" USING "btree" ("sender_id") WHERE ("sender_id" IS NOT NULL);



CREATE INDEX "notifications_conversation_idx" ON "public"."notifications" USING "btree" ("destination_conversation_id") WHERE ("destination_conversation_id" IS NOT NULL);



CREATE INDEX "notifications_listing_idx" ON "public"."notifications" USING "btree" ("destination_listing_id") WHERE ("destination_listing_id" IS NOT NULL);



CREATE INDEX "notifications_order_idx" ON "public"."notifications" USING "btree" ("destination_order_id") WHERE ("destination_order_id" IS NOT NULL);



CREATE INDEX "notifications_recipient_page_idx" ON "public"."notifications" USING "btree" ("recipient_id", "created_at" DESC, "id" DESC);



CREATE INDEX "notifications_recipient_unread_idx" ON "public"."notifications" USING "btree" ("recipient_id", "created_at" DESC, "id" DESC) WHERE ("read_at" IS NULL);



CREATE INDEX "order_events_order_created_idx" ON "public"."order_events" USING "btree" ("order_id", "created_at");



CREATE INDEX "order_reviews_destinatario_idx" ON "public"."order_reviews" USING "btree" ("destinatario_id", "created_at" DESC);



CREATE INDEX "orders_auto_rilascio_idx" ON "public"."orders" USING "btree" ("auto_rilascio_scadenza") WHERE (("payout_stato" = 'trattenuto'::"public"."payout_stato") AND ("contestato_at" IS NULL));



CREATE INDEX "orders_buyer_created_idx" ON "public"."orders" USING "btree" ("buyer_id", "created_at" DESC);



CREATE INDEX "orders_payout_coda_idx" ON "public"."orders" USING "btree" ("updated_at") WHERE ("payout_stato" = 'in_attesa'::"public"."payout_stato");



CREATE INDEX "orders_proposal_idx" ON "public"."orders" USING "btree" ("proposal_id") WHERE ("proposal_id" IS NOT NULL);



CREATE INDEX "orders_seller_bottle_idx" ON "public"."orders" USING "btree" ("seller_bottle_unit_id");



CREATE INDEX "orders_seller_created_idx" ON "public"."orders" USING "btree" ("seller_id", "created_at" DESC);



CREATE UNIQUE INDEX "orders_unico_non_annullato_per_listing" ON "public"."orders" USING "btree" ("listing_id") WHERE ("stato" <> 'annullato'::"public"."order_stato");



CREATE UNIQUE INDEX "packaging_options_corrente_idx" ON "public"."packaging_options" USING "btree" ("codice") WHERE ("valida_fino" IS NULL);



CREATE INDEX "packaging_options_storico_idx" ON "public"."packaging_options" USING "btree" ("codice", "valida_da" DESC);



CREATE INDEX "payments_fee_da_riconciliare_idx" ON "public"."payments" USING "btree" ("created_at") WHERE (("stato" = 'paid'::"public"."payment_stato") AND ("fee_stripe_reale_cents" IS NULL));



CREATE INDEX "payouts_seller_idx" ON "public"."payouts" USING "btree" ("seller_id", "created_at" DESC);



CREATE INDEX "payouts_stato_idx" ON "public"."payouts" USING "btree" ("stato", "created_at");



CREATE UNIQUE INDEX "profiles_username_lower_key" ON "public"."profiles" USING "btree" ("lower"("username"));



CREATE INDEX "proposals_buyer_created_idx" ON "public"."proposals" USING "btree" ("buyer_id", "created_at" DESC);



CREATE INDEX "proposals_listing_idx" ON "public"."proposals" USING "btree" ("listing_id");



CREATE INDEX "proposals_scadenza_idx" ON "public"."proposals" USING "btree" ("scadenza") WHERE ("stato" = ANY (ARRAY['inviata'::"public"."proposal_stato", 'controproposta'::"public"."proposal_stato", 'accettata'::"public"."proposal_stato"]));



CREATE INDEX "proposals_seller_created_idx" ON "public"."proposals" USING "btree" ("seller_id", "created_at" DESC);



CREATE UNIQUE INDEX "proposals_una_attiva_per_buyer" ON "public"."proposals" USING "btree" ("listing_id", "buyer_id") WHERE ("stato" = ANY (ARRAY['inviata'::"public"."proposal_stato", 'controproposta'::"public"."proposal_stato"]));



CREATE INDEX "report_events_report_idx" ON "public"."report_events" USING "btree" ("report_id", "created_at", "id");



CREATE INDEX "reports_reporter_idx" ON "public"."reports" USING "btree" ("reporter_id", "created_at" DESC);



CREATE INDEX "reports_stato_priorita_idx" ON "public"."reports" USING "btree" ("stato", "priorita" DESC, "created_at" DESC);



CREATE INDEX "reports_target_post_idx" ON "public"."reports" USING "btree" ("target_post_id") WHERE ("target_post_id" IS NOT NULL);



CREATE INDEX "reports_target_risposta_idx" ON "public"."reports" USING "btree" ("target_risposta_id") WHERE ("target_risposta_id" IS NOT NULL);



CREATE INDEX "seller_payout_accounts_seller_idx" ON "public"."seller_payout_accounts" USING "btree" ("seller_id");



CREATE INDEX "sommelier_messaggi_conversazione_idx" ON "public"."sommelier_messaggi" USING "btree" ("owner_id", "session_id", "ordinale");



CREATE INDEX "sommelier_messaggi_expires_idx" ON "public"."sommelier_messaggi" USING "btree" ("expires_at");



CREATE INDEX "tracking_events_order_created_idx" ON "public"."tracking_events" USING "btree" ("order_id", "created_at");



CREATE INDEX "wine_price_observations_origine_idx" ON "public"."wine_price_observations" USING "btree" ("origine_ref", "tipo");



CREATE INDEX "wine_price_observations_serie_idx" ON "public"."wine_price_observations" USING "btree" ("wine_id", "formato", "observed_at" DESC);



CREATE UNIQUE INDEX "wine_price_observations_una_vendita_per_ordine" ON "public"."wine_price_observations" USING "btree" ("origine_ref") WHERE ("tipo" = 'vendita'::"public"."price_observation_tipo");



CREATE INDEX "wine_reference_snapshots_serie_idx" ON "public"."wine_reference_snapshots" USING "btree" ("wine_id", "formato", "observed_at" DESC);



CREATE UNIQUE INDEX "wine_regions_nome_lower_key" ON "public"."wine_regions" USING "btree" ("lower"("nome"));



CREATE INDEX "wines_annata_idx" ON "public"."wines" USING "btree" ("annata");



CREATE INDEX "wines_creato_da_idx" ON "public"."wines" USING "btree" ("creato_da") WHERE ("creato_da" IS NOT NULL);



CREATE INDEX "wines_finestra_idx" ON "public"."wines" USING "btree" ("finestra_inizio", "finestra_fine");



CREATE INDEX "wines_regione_idx" ON "public"."wines" USING "btree" ("regione");



CREATE INDEX "wines_ricerca_trgm_idx" ON "public"."wines" USING "gin" (((("produttore" || ' '::"text") || "nome")) "extensions"."gin_trgm_ops");



CREATE INDEX "wines_tipo_idx" ON "public"."wines" USING "btree" ("tipo");



CREATE OR REPLACE TRIGGER "audit_log_no_delete" BEFORE DELETE ON "public"."audit_log" FOR EACH ROW EXECUTE FUNCTION "private"."audit_log_append_only"();



CREATE OR REPLACE TRIGGER "audit_log_no_truncate" BEFORE TRUNCATE ON "public"."audit_log" FOR EACH STATEMENT EXECUTE FUNCTION "private"."audit_log_append_only"();



CREATE OR REPLACE TRIGGER "audit_log_no_update" BEFORE UPDATE ON "public"."audit_log" FOR EACH ROW EXECUTE FUNCTION "private"."audit_log_append_only"();



CREATE OR REPLACE TRIGGER "bottle_units_ciclo_di_vita" BEFORE INSERT OR UPDATE ON "public"."bottle_units" FOR EACH ROW EXECUTE FUNCTION "private"."bottle_units_ciclo_di_vita"();



CREATE OR REPLACE TRIGGER "bottle_units_preserva_annuncio_non_terminale" BEFORE UPDATE OF "stato", "deleted_at", "ceduta_at" ON "public"."bottle_units" FOR EACH ROW EXECUTE FUNCTION "public"."bottle_units_preserva_annuncio_non_terminale"();



CREATE OR REPLACE TRIGGER "bottle_units_set_updated_at" BEFORE UPDATE ON "public"."bottle_units" FOR EACH ROW EXECUTE FUNCTION "extensions"."moddatetime"('updated_at');



CREATE OR REPLACE TRIGGER "cellar_environments_set_updated_at" BEFORE UPDATE ON "public"."cellar_environments" FOR EACH ROW EXECUTE FUNCTION "extensions"."moddatetime"('updated_at');



CREATE OR REPLACE TRIGGER "cellar_modules_set_updated_at" BEFORE UPDATE ON "public"."cellar_modules" FOR EACH ROW EXECUTE FUNCTION "extensions"."moddatetime"('updated_at');



CREATE OR REPLACE TRIGGER "cellar_slots_set_updated_at" BEFORE UPDATE ON "public"."cellar_slots" FOR EACH ROW EXECUTE FUNCTION "extensions"."moddatetime"('updated_at');



CREATE OR REPLACE TRIGGER "club_memberships_scrittura_social_guard" BEFORE INSERT ON "public"."club_memberships" FOR EACH ROW EXECUTE FUNCTION "private"."scrittura_social_guard"();



CREATE OR REPLACE TRIGGER "club_post_like_figlio_guard" BEFORE INSERT ON "public"."club_post_like" FOR EACH ROW EXECUTE FUNCTION "private"."club_post_figlio_guard"();



CREATE OR REPLACE TRIGGER "club_post_like_scrittura_social_guard" BEFORE INSERT ON "public"."club_post_like" FOR EACH ROW EXECUTE FUNCTION "private"."scrittura_social_guard"();



CREATE OR REPLACE TRIGGER "club_post_risposte_figlio_guard" BEFORE INSERT ON "public"."club_post_risposte" FOR EACH ROW EXECUTE FUNCTION "private"."club_post_figlio_guard"();



CREATE OR REPLACE TRIGGER "club_post_risposte_owner_only_guard" BEFORE INSERT ON "public"."club_post_risposte" FOR EACH ROW EXECUTE FUNCTION "private"."club_risposta_owner_only_guard"();



CREATE OR REPLACE TRIGGER "club_post_risposte_scrittura_social_guard" BEFORE INSERT ON "public"."club_post_risposte" FOR EACH ROW EXECUTE FUNCTION "private"."scrittura_social_guard"();



CREATE OR REPLACE TRIGGER "club_posts_immutabile_guard" BEFORE UPDATE ON "public"."club_posts" FOR EACH ROW EXECUTE FUNCTION "private"."club_post_immutabile_guard"();



CREATE OR REPLACE TRIGGER "club_posts_owner_only_guard" BEFORE INSERT ON "public"."club_posts" FOR EACH ROW EXECUTE FUNCTION "private"."club_post_owner_only_guard"();



CREATE OR REPLACE TRIGGER "club_posts_riferimenti_guard" BEFORE INSERT ON "public"."club_posts" FOR EACH ROW EXECUTE FUNCTION "private"."club_post_riferimenti_guard"();



CREATE OR REPLACE TRIGGER "club_posts_scrittura_social_guard" BEFORE INSERT ON "public"."club_posts" FOR EACH ROW EXECUTE FUNCTION "private"."scrittura_social_guard"();



CREATE OR REPLACE TRIGGER "conversation_participants_guard" BEFORE INSERT OR UPDATE ON "public"."conversation_participants" FOR EACH ROW EXECUTE FUNCTION "private"."conversation_participant_guard"();



CREATE CONSTRAINT TRIGGER "conversation_participants_validate_deferred" AFTER INSERT OR DELETE OR UPDATE ON "public"."conversation_participants" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION "private"."conversation_validate_participants"();



CREATE OR REPLACE TRIGGER "conversations_scrittura_social_guard" BEFORE INSERT ON "public"."conversations" FOR EACH ROW EXECUTE FUNCTION "private"."scrittura_social_guard"();



CREATE CONSTRAINT TRIGGER "conversations_validate_deferred" AFTER INSERT OR UPDATE ON "public"."conversations" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION "private"."conversation_validate_row"();



CREATE OR REPLACE TRIGGER "listings_bottiglia_idonea" BEFORE INSERT OR UPDATE ON "public"."listings" FOR EACH ROW EXECUTE FUNCTION "public"."listings_bottiglia_idonea"();



CREATE OR REPLACE TRIGGER "listings_marca_bottiglia_ceduta" AFTER INSERT OR UPDATE OF "stato" ON "public"."listings" FOR EACH ROW EXECUTE FUNCTION "public"."listings_marca_bottiglia_ceduta"();



CREATE OR REPLACE TRIGGER "listings_price_observation_sync" AFTER INSERT OR UPDATE ON "public"."listings" FOR EACH ROW WHEN (("new"."stato" = 'attivo'::"public"."listing_stato")) EXECUTE FUNCTION "private"."listings_price_observation_sync"();



CREATE OR REPLACE TRIGGER "listings_riferimento_sync" AFTER INSERT OR DELETE ON "public"."listings" FOR EACH ROW EXECUTE FUNCTION "private"."listings_riferimento_sync"();



CREATE OR REPLACE TRIGGER "listings_riferimento_sync_update" AFTER UPDATE OF "stato", "prezzo_cents" ON "public"."listings" FOR EACH ROW WHEN ((("old"."stato" IS DISTINCT FROM "new"."stato") OR ("old"."prezzo_cents" IS DISTINCT FROM "new"."prezzo_cents"))) EXECUTE FUNCTION "private"."listings_riferimento_sync"();



CREATE OR REPLACE TRIGGER "listings_scrittura_social_guard" BEFORE INSERT OR UPDATE ON "public"."listings" FOR EACH ROW EXECUTE FUNCTION "private"."scrittura_social_guard"();



CREATE OR REPLACE TRIGGER "listings_set_updated_at" BEFORE UPDATE ON "public"."listings" FOR EACH ROW EXECUTE FUNCTION "extensions"."moddatetime"('updated_at');



CREATE OR REPLACE TRIGGER "messages_after_insert" AFTER INSERT ON "public"."messages" FOR EACH ROW EXECUTE FUNCTION "private"."messages_after_insert"();



CREATE OR REPLACE TRIGGER "messages_immutable" BEFORE DELETE OR UPDATE ON "public"."messages" FOR EACH ROW EXECUTE FUNCTION "private"."messages_immutable"();



CREATE OR REPLACE TRIGGER "messages_scrittura_social_guard" BEFORE INSERT ON "public"."messages" FOR EACH ROW EXECUTE FUNCTION "private"."scrittura_social_guard"();



CREATE OR REPLACE TRIGGER "notifications_after_change" AFTER INSERT OR UPDATE OF "read_at" ON "public"."notifications" FOR EACH ROW EXECUTE FUNCTION "private"."notifications_after_change"();



CREATE OR REPLACE TRIGGER "orders_commercio_rimosso_guard" BEFORE INSERT ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "private"."commercio_rimosso_guard"();



CREATE CONSTRAINT TRIGGER "orders_contestazione_ha_pratica" AFTER INSERT OR UPDATE OF "contestato_at" ON "public"."orders" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (("new"."contestato_at" IS NOT NULL)) EXECUTE FUNCTION "private"."disputes_invariante"();



CREATE OR REPLACE TRIGGER "orders_price_observation_sync" AFTER UPDATE OF "stato" ON "public"."orders" FOR EACH ROW WHEN ((("new"."stato" = 'completato'::"public"."order_stato") AND ("old"."stato" IS DISTINCT FROM 'completato'::"public"."order_stato"))) EXECUTE FUNCTION "private"."orders_price_observation_sync"();



CREATE OR REPLACE TRIGGER "orders_set_updated_at" BEFORE UPDATE ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "extensions"."moddatetime"('updated_at');



CREATE OR REPLACE TRIGGER "orders_tracking_sync" AFTER UPDATE OF "stato" ON "public"."orders" FOR EACH ROW WHEN (("new"."stato" = ANY (ARRAY['pagato'::"public"."order_stato", 'consegnato'::"public"."order_stato", 'completato'::"public"."order_stato", 'rimborsato'::"public"."order_stato", 'annullato'::"public"."order_stato"]))) EXECUTE FUNCTION "private"."orders_tracking_sync"();



CREATE OR REPLACE TRIGGER "payments_set_updated_at" BEFORE UPDATE ON "public"."payments" FOR EACH ROW EXECUTE FUNCTION "extensions"."moddatetime"('updated_at');



CREATE OR REPLACE TRIGGER "payouts_set_updated_at" BEFORE UPDATE ON "public"."payouts" FOR EACH ROW EXECUTE FUNCTION "extensions"."moddatetime"('updated_at');



CREATE OR REPLACE TRIGGER "profile_certifications_guard" BEFORE INSERT OR UPDATE ON "public"."profile_certifications" FOR EACH ROW EXECUTE FUNCTION "private"."profile_certifications_guard"();



CREATE OR REPLACE TRIGGER "profiles_set_updated_at" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "extensions"."moddatetime"('updated_at');



CREATE OR REPLACE TRIGGER "profiles_stato_utente_guard" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "private"."profiles_stato_utente_guard"();



CREATE OR REPLACE TRIGGER "proposals_set_updated_at" BEFORE UPDATE ON "public"."proposals" FOR EACH ROW EXECUTE FUNCTION "extensions"."moddatetime"('updated_at');



CREATE OR REPLACE TRIGGER "seller_payout_accounts_seller_enabled" AFTER INSERT OR UPDATE OF "charges_enabled", "payouts_enabled" ON "public"."seller_payout_accounts" FOR EACH ROW EXECUTE FUNCTION "private"."seller_enabled_sync"();



CREATE OR REPLACE TRIGGER "seller_payout_accounts_set_updated_at" BEFORE UPDATE ON "public"."seller_payout_accounts" FOR EACH ROW EXECUTE FUNCTION "extensions"."moddatetime"('updated_at');



CREATE OR REPLACE TRIGGER "wine_price_observations_no_delete" BEFORE DELETE ON "public"."wine_price_observations" FOR EACH ROW EXECUTE FUNCTION "private"."wine_price_observations_append_only"();



CREATE OR REPLACE TRIGGER "wine_price_observations_no_truncate" BEFORE TRUNCATE ON "public"."wine_price_observations" FOR EACH STATEMENT EXECUTE FUNCTION "private"."wine_price_observations_append_only"();



CREATE OR REPLACE TRIGGER "wine_price_observations_no_update" BEFORE UPDATE ON "public"."wine_price_observations" FOR EACH ROW EXECUTE FUNCTION "private"."wine_price_observations_append_only"();



CREATE OR REPLACE TRIGGER "wine_reference_snapshots_no_delete" BEFORE DELETE ON "public"."wine_reference_snapshots" FOR EACH ROW EXECUTE FUNCTION "private"."wine_reference_snapshots_append_only"();



CREATE OR REPLACE TRIGGER "wine_reference_snapshots_no_truncate" BEFORE TRUNCATE ON "public"."wine_reference_snapshots" FOR EACH STATEMENT EXECUTE FUNCTION "private"."wine_reference_snapshots_append_only"();



CREATE OR REPLACE TRIGGER "wine_reference_snapshots_no_update" BEFORE UPDATE ON "public"."wine_reference_snapshots" FOR EACH ROW EXECUTE FUNCTION "private"."wine_reference_snapshots_append_only"();



CREATE OR REPLACE TRIGGER "wines_set_updated_at" BEFORE UPDATE ON "public"."wines" FOR EACH ROW EXECUTE FUNCTION "extensions"."moddatetime"('updated_at');



ALTER TABLE ONLY "public"."audit_log"
    ADD CONSTRAINT "audit_log_attore_id_fkey" FOREIGN KEY ("attore_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."audit_log"
    ADD CONSTRAINT "audit_log_report_id_fkey" FOREIGN KEY ("report_id") REFERENCES "public"."reports"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."bottle_units"
    ADD CONSTRAINT "bottle_units_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bottle_units"
    ADD CONSTRAINT "bottle_units_wine_id_fkey" FOREIGN KEY ("wine_id") REFERENCES "public"."wines"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."cellar_environments"
    ADD CONSTRAINT "cellar_environments_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cellar_modules"
    ADD CONSTRAINT "cellar_modules_environment_id_fkey" FOREIGN KEY ("environment_id") REFERENCES "public"."cellar_environments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cellar_slots"
    ADD CONSTRAINT "cellar_slots_bottle_unit_id_fkey" FOREIGN KEY ("bottle_unit_id") REFERENCES "public"."bottle_units"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cellar_slots"
    ADD CONSTRAINT "cellar_slots_module_id_fkey" FOREIGN KEY ("module_id") REFERENCES "public"."cellar_modules"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."club_memberships"
    ADD CONSTRAINT "club_memberships_club_slug_fkey" FOREIGN KEY ("club_slug") REFERENCES "public"."clubs"("slug") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."club_memberships"
    ADD CONSTRAINT "club_memberships_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."club_post_like"
    ADD CONSTRAINT "club_post_like_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."club_posts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."club_post_like"
    ADD CONSTRAINT "club_post_like_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."club_post_risposte"
    ADD CONSTRAINT "club_post_risposte_autore_id_fkey" FOREIGN KEY ("autore_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."club_post_risposte"
    ADD CONSTRAINT "club_post_risposte_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."club_posts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."club_post_risposte"
    ADD CONSTRAINT "club_post_risposte_rimosso_da_fkey" FOREIGN KEY ("rimosso_da") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."club_posts"
    ADD CONSTRAINT "club_posts_autore_id_fkey" FOREIGN KEY ("autore_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."club_posts"
    ADD CONSTRAINT "club_posts_bottle_unit_id_fkey" FOREIGN KEY ("bottle_unit_id") REFERENCES "public"."bottle_units"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."club_posts"
    ADD CONSTRAINT "club_posts_club_slug_fkey" FOREIGN KEY ("club_slug") REFERENCES "public"."clubs"("slug") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."club_posts"
    ADD CONSTRAINT "club_posts_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "public"."listings"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."club_posts"
    ADD CONSTRAINT "club_posts_rimosso_da_fkey" FOREIGN KEY ("rimosso_da") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."club_posts"
    ADD CONSTRAINT "club_posts_wine_id_fkey" FOREIGN KEY ("wine_id") REFERENCES "public"."wines"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."clubs"
    ADD CONSTRAINT "clubs_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."conversation_participants"
    ADD CONSTRAINT "conversation_participants_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "public"."conversations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversation_participants"
    ADD CONSTRAINT "conversation_participants_last_read_fkey" FOREIGN KEY ("conversation_id", "last_read_message_id") REFERENCES "public"."messages"("conversation_id", "id") DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY "public"."conversation_participants"
    ADD CONSTRAINT "conversation_participants_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_last_message_fkey" FOREIGN KEY ("id", "last_message_id") REFERENCES "public"."messages"("conversation_id", "id") DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "public"."listings"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_participant_high_fkey" FOREIGN KEY ("participant_high") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_participant_low_fkey" FOREIGN KEY ("participant_low") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."disputes"
    ADD CONSTRAINT "disputes_aperta_da_fkey" FOREIGN KEY ("aperta_da") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."disputes"
    ADD CONSTRAINT "disputes_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."disputes"
    ADD CONSTRAINT "disputes_risolta_da_fkey" FOREIGN KEY ("risolta_da") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."listings"
    ADD CONSTRAINT "listings_bottle_unit_id_fkey" FOREIGN KEY ("bottle_unit_id") REFERENCES "public"."bottle_units"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."listings"
    ADD CONSTRAINT "listings_reserved_by_fkey" FOREIGN KEY ("reserved_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."listings"
    ADD CONSTRAINT "listings_seller_id_fkey" FOREIGN KEY ("seller_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."listings"
    ADD CONSTRAINT "listings_stato_aggiornato_da_fkey" FOREIGN KEY ("stato_aggiornato_da") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "public"."conversations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_destination_conversation_id_fkey" FOREIGN KEY ("destination_conversation_id") REFERENCES "public"."conversations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_destination_listing_id_fkey" FOREIGN KEY ("destination_listing_id") REFERENCES "public"."listings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_destination_order_id_fkey" FOREIGN KEY ("destination_order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_recipient_id_fkey" FOREIGN KEY ("recipient_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."order_events"
    ADD CONSTRAINT "order_events_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."order_reviews"
    ADD CONSTRAINT "order_reviews_autore_id_fkey" FOREIGN KEY ("autore_id") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."order_reviews"
    ADD CONSTRAINT "order_reviews_destinatario_id_fkey" FOREIGN KEY ("destinatario_id") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."order_reviews"
    ADD CONSTRAINT "order_reviews_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_buyer_bottle_unit_id_fkey" FOREIGN KEY ("buyer_bottle_unit_id") REFERENCES "public"."bottle_units"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_buyer_id_fkey" FOREIGN KEY ("buyer_id") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "public"."listings"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_proposal_id_fkey" FOREIGN KEY ("proposal_id") REFERENCES "public"."proposals"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_seller_bottle_unit_id_fkey" FOREIGN KEY ("seller_bottle_unit_id") REFERENCES "public"."bottle_units"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_seller_id_fkey" FOREIGN KEY ("seller_id") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."payouts"
    ADD CONSTRAINT "payouts_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."payouts"
    ADD CONSTRAINT "payouts_seller_id_fkey" FOREIGN KEY ("seller_id") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."profile_certifications"
    ADD CONSTRAINT "profile_certifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."proposals"
    ADD CONSTRAINT "proposals_buyer_id_fkey" FOREIGN KEY ("buyer_id") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."proposals"
    ADD CONSTRAINT "proposals_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "public"."listings"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."proposals"
    ADD CONSTRAINT "proposals_seller_id_fkey" FOREIGN KEY ("seller_id") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."report_events"
    ADD CONSTRAINT "report_events_autore_id_fkey" FOREIGN KEY ("autore_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."report_events"
    ADD CONSTRAINT "report_events_report_id_fkey" FOREIGN KEY ("report_id") REFERENCES "public"."reports"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_motivo_fk" FOREIGN KEY ("target_tipo", "motivo") REFERENCES "public"."report_reasons"("target_tipo", "motivo") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_reporter_id_fkey" FOREIGN KEY ("reporter_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_target_conversation_id_fkey" FOREIGN KEY ("target_conversation_id") REFERENCES "public"."conversations"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_target_listing_id_fkey" FOREIGN KEY ("target_listing_id") REFERENCES "public"."listings"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_target_message_id_fkey" FOREIGN KEY ("target_message_id") REFERENCES "public"."messages"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_target_post_id_fkey" FOREIGN KEY ("target_post_id") REFERENCES "public"."club_posts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_target_profile_id_fkey" FOREIGN KEY ("target_profile_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_target_review_id_fkey" FOREIGN KEY ("target_review_id") REFERENCES "public"."order_reviews"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_target_risposta_id_fkey" FOREIGN KEY ("target_risposta_id") REFERENCES "public"."club_post_risposte"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."seller_payout_accounts"
    ADD CONSTRAINT "seller_payout_accounts_seller_id_fkey" FOREIGN KEY ("seller_id") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."sommelier_messaggi"
    ADD CONSTRAINT "sommelier_messaggi_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tracking_events"
    ADD CONSTRAINT "tracking_events_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."wine_price_observations"
    ADD CONSTRAINT "wine_price_observations_wine_id_fkey" FOREIGN KEY ("wine_id") REFERENCES "public"."wines"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."wines"
    ADD CONSTRAINT "wines_creato_da_fkey" FOREIGN KEY ("creato_da") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."wines"
    ADD CONSTRAINT "wines_regione_fkey" FOREIGN KEY ("regione") REFERENCES "public"."wine_regions"("nome") ON UPDATE CASCADE ON DELETE RESTRICT;



COMMENT ON CONSTRAINT "wines_regione_fkey" ON "public"."wines" IS 'La regione di una scheda vino esiste nella tassonomia canonica. Sostituisce il solo `length(trim(regione)) > 0` della Fase 6a, che accettava qualunque stringa non vuota.';



ALTER TABLE "private"."rate_limit_buckets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."account_provider_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."audit_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."bottle_units" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "bottle_units_insert_own" ON "public"."bottle_units" FOR INSERT TO "authenticated" WITH CHECK ((("owner_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("stato" = 'chiusa'::"public"."bottle_unit_stato") AND ("deleted_at" IS NULL) AND ("ceduta_at" IS NULL)));



CREATE POLICY "bottle_units_select_own" ON "public"."bottle_units" FOR SELECT TO "authenticated" USING ((("owner_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("deleted_at" IS NULL) AND ("ceduta_at" IS NULL)));



CREATE POLICY "bottle_units_update_own" ON "public"."bottle_units" FOR UPDATE TO "authenticated" USING ((("owner_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("deleted_at" IS NULL) AND ("ceduta_at" IS NULL))) WITH CHECK ((("owner_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("deleted_at" IS NULL) AND ("ceduta_at" IS NULL)));



ALTER TABLE "public"."cellar_environments" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "cellar_environments_own" ON "public"."cellar_environments" TO "authenticated" USING (("owner_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("owner_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."cellar_modules" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "cellar_modules_own" ON "public"."cellar_modules" TO "authenticated" USING ("public"."cellar_ambiente_e_mio"("environment_id")) WITH CHECK ("public"."cellar_ambiente_e_mio"("environment_id"));



ALTER TABLE "public"."cellar_slots" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "cellar_slots_select_own" ON "public"."cellar_slots" FOR SELECT TO "authenticated" USING ("public"."cellar_modulo_e_mio"("module_id"));



ALTER TABLE "public"."club_memberships" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "club_memberships_delete_own" ON "public"."club_memberships" FOR DELETE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "club_memberships_insert_own" ON "public"."club_memberships" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "club_memberships_select_own" ON "public"."club_memberships" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."club_post_like" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "club_post_like_delete_own" ON "public"."club_post_like" FOR DELETE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "club_post_like_insert_own" ON "public"."club_post_like" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "club_post_like_select_own" ON "public"."club_post_like" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."club_post_risposte" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "club_post_risposte_insert_own" ON "public"."club_post_risposte" FOR INSERT TO "authenticated" WITH CHECK (("autore_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "club_post_risposte_select_own" ON "public"."club_post_risposte" FOR SELECT TO "authenticated" USING (("autore_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "club_post_risposte_update_own" ON "public"."club_post_risposte" FOR UPDATE TO "authenticated" USING ((("autore_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("rimosso_at" IS NULL))) WITH CHECK ((("autore_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("rimosso_at" IS NULL)));



ALTER TABLE "public"."club_posts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "club_posts_insert_own" ON "public"."club_posts" FOR INSERT TO "authenticated" WITH CHECK (("autore_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "club_posts_select_own" ON "public"."club_posts" FOR SELECT TO "authenticated" USING (("autore_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "club_posts_update_own" ON "public"."club_posts" FOR UPDATE TO "authenticated" USING ((("autore_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("rimosso_at" IS NULL))) WITH CHECK ((("autore_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("rimosso_at" IS NULL)));



ALTER TABLE "public"."clubs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."conversation_participants" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "conversation_participants_members_select" ON "public"."conversation_participants" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."conversations" "c"
  WHERE (("c"."id" = "conversation_participants"."conversation_id") AND ((( SELECT "auth"."uid"() AS "uid") = "c"."participant_low") OR (( SELECT "auth"."uid"() AS "uid") = "c"."participant_high"))))));



ALTER TABLE "public"."conversations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "conversations_participants_select" ON "public"."conversations" FOR SELECT TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "participant_low") OR (( SELECT "auth"."uid"() AS "uid") = "participant_high")));



ALTER TABLE "public"."disputes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "disputes_participants_select" ON "public"."disputes" FOR SELECT TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM "public"."orders" "o"
  WHERE (("o"."id" = "disputes"."order_id") AND ((( SELECT "auth"."uid"() AS "uid") = "o"."buyer_id") OR (( SELECT "auth"."uid"() AS "uid") = "o"."seller_id"))))) AND (NOT (EXISTS ( SELECT 1
   FROM "public"."profiles" "me"
  WHERE (("me"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("me"."stato_utente" = 'rimosso'::"public"."utente_stato")))))));



ALTER TABLE "public"."listings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "listings_insert_own" ON "public"."listings" FOR INSERT TO "authenticated" WITH CHECK ((("seller_id" = ( SELECT "auth"."uid"() AS "uid")) AND (EXISTS ( SELECT 1
   FROM "public"."bottle_units" "bu"
  WHERE (("bu"."id" = "listings"."bottle_unit_id") AND ("bu"."owner_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("bu"."stato" = 'chiusa'::"public"."bottle_unit_stato") AND ("bu"."deleted_at" IS NULL) AND ("bu"."ceduta_at" IS NULL))))));



CREATE POLICY "listings_select_own" ON "public"."listings" FOR SELECT TO "authenticated" USING (("seller_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "listings_update_own" ON "public"."listings" FOR UPDATE TO "authenticated" USING ((("seller_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("stato" = ANY (ARRAY['bozza'::"public"."listing_stato", 'modifiche_richieste'::"public"."listing_stato", 'attivo'::"public"."listing_stato"])))) WITH CHECK (("seller_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."marketplace_config" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."messages" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "messages_participants_select" ON "public"."messages" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."conversations" "c"
  WHERE (("c"."id" = "messages"."conversation_id") AND ((( SELECT "auth"."uid"() AS "uid") = "c"."participant_low") OR (( SELECT "auth"."uid"() AS "uid") = "c"."participant_high"))))));



ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "notifications_recipient_select" ON "public"."notifications" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "recipient_id"));



ALTER TABLE "public"."order_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "order_events_participants_select" ON "public"."order_events" FOR SELECT TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM "public"."orders" "o"
  WHERE (("o"."id" = "order_events"."order_id") AND ((( SELECT "auth"."uid"() AS "uid") = "o"."buyer_id") OR (( SELECT "auth"."uid"() AS "uid") = "o"."seller_id"))))) AND (NOT (EXISTS ( SELECT 1
   FROM "public"."profiles" "me"
  WHERE (("me"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("me"."stato_utente" = 'rimosso'::"public"."utente_stato")))))));



ALTER TABLE "public"."order_reviews" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "order_reviews_participants_select" ON "public"."order_reviews" FOR SELECT TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM "public"."orders" "o"
  WHERE (("o"."id" = "order_reviews"."order_id") AND ((( SELECT "auth"."uid"() AS "uid") = "o"."buyer_id") OR (( SELECT "auth"."uid"() AS "uid") = "o"."seller_id"))))) AND (NOT (EXISTS ( SELECT 1
   FROM "public"."profiles" "me"
  WHERE (("me"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("me"."stato_utente" = 'rimosso'::"public"."utente_stato")))))));



ALTER TABLE "public"."orders" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "orders_participants_select" ON "public"."orders" FOR SELECT TO "authenticated" USING ((((( SELECT "auth"."uid"() AS "uid") = "buyer_id") OR (( SELECT "auth"."uid"() AS "uid") = "seller_id")) AND (NOT (EXISTS ( SELECT 1
   FROM "public"."profiles" "me"
  WHERE (("me"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("me"."stato_utente" = 'rimosso'::"public"."utente_stato")))))));



ALTER TABLE "public"."packaging_options" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."payment_provider_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."payments" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "payments_participants_select" ON "public"."payments" FOR SELECT TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM "public"."orders" "o"
  WHERE (("o"."id" = "payments"."order_id") AND ((( SELECT "auth"."uid"() AS "uid") = "o"."buyer_id") OR (( SELECT "auth"."uid"() AS "uid") = "o"."seller_id"))))) AND (NOT (EXISTS ( SELECT 1
   FROM "public"."profiles" "me"
  WHERE (("me"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("me"."stato_utente" = 'rimosso'::"public"."utente_stato")))))));



ALTER TABLE "public"."payouts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "payouts_participants_select" ON "public"."payouts" FOR SELECT TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM "public"."orders" "o"
  WHERE (("o"."id" = "payouts"."order_id") AND ((( SELECT "auth"."uid"() AS "uid") = "o"."buyer_id") OR (( SELECT "auth"."uid"() AS "uid") = "o"."seller_id"))))) AND (NOT (EXISTS ( SELECT 1
   FROM "public"."profiles" "me"
  WHERE (("me"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("me"."stato_utente" = 'rimosso'::"public"."utente_stato")))))));



ALTER TABLE "public"."profile_certifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_select_own" ON "public"."profiles" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "id"));



CREATE POLICY "profiles_update_own" ON "public"."profiles" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "id"));



ALTER TABLE "public"."proposals" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "proposals_participants_select" ON "public"."proposals" FOR SELECT TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "buyer_id") OR (( SELECT "auth"."uid"() AS "uid") = "seller_id")));



ALTER TABLE "public"."report_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."report_reasons" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "report_reasons_select_tutti" ON "public"."report_reasons" FOR SELECT TO "authenticated", "anon" USING (true);



ALTER TABLE "public"."reports" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."seller_payout_accounts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "seller_payout_accounts_owner_select" ON "public"."seller_payout_accounts" FOR SELECT TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "seller_id") AND (NOT (EXISTS ( SELECT 1
   FROM "public"."profiles" "me"
  WHERE (("me"."id" = ( SELECT "auth"."uid"() AS "uid")) AND ("me"."stato_utente" = 'rimosso'::"public"."utente_stato")))))));



ALTER TABLE "public"."sommelier_messaggi" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tracking_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tracking_events_participants_select" ON "public"."tracking_events" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."orders" "o"
  WHERE (("o"."id" = "tracking_events"."order_id") AND ((( SELECT "auth"."uid"() AS "uid") = "o"."buyer_id") OR (( SELECT "auth"."uid"() AS "uid") = "o"."seller_id"))))));



ALTER TABLE "public"."user_roles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_roles_select_own" ON "public"."user_roles" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."wine_price_observations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wine_reference_snapshots" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."wine_regions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "wine_regions_select_public" ON "public"."wine_regions" FOR SELECT TO "authenticated", "anon" USING (true);



ALTER TABLE "public"."wines" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "wines_delete_staff" ON "public"."wines" FOR DELETE TO "authenticated" USING (("public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"text") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'moderator'::"text")));



CREATE POLICY "wines_insert_staff" ON "public"."wines" FOR INSERT TO "authenticated" WITH CHECK ((("provenienza" = 'staff'::"public"."wine_provenienza") AND ("creato_da" IS NULL) AND ("public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"text") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'moderator'::"text"))));



CREATE POLICY "wines_select_curated" ON "public"."wines" FOR SELECT TO "authenticated", "anon" USING (("provenienza" = 'staff'::"public"."wine_provenienza"));



CREATE POLICY "wines_select_own_user" ON "public"."wines" FOR SELECT TO "authenticated" USING ((("provenienza" = 'utente'::"public"."wine_provenienza") AND (("creato_da" = ( SELECT "auth"."uid"() AS "uid")) OR (EXISTS ( SELECT 1
   FROM "public"."bottle_units" "bu"
  WHERE (("bu"."wine_id" = "wines"."id") AND ("bu"."owner_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("bu"."deleted_at" IS NULL) AND ("bu"."ceduta_at" IS NULL)))))));



CREATE POLICY "wines_update_staff" ON "public"."wines" FOR UPDATE TO "authenticated" USING (("public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"text") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'moderator'::"text"))) WITH CHECK (("public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'admin'::"text") OR "public"."has_role"(( SELECT "auth"."uid"() AS "uid"), 'moderator'::"text")));



GRANT USAGE ON SCHEMA "private" TO "anon";
GRANT USAGE ON SCHEMA "private" TO "authenticated";
GRANT USAGE ON SCHEMA "private" TO "authenticator";
GRANT USAGE ON SCHEMA "private" TO "service_role";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "private"."audit_log_append_only"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."audit_registra"("p_attore_id" "uuid", "p_azione" "public"."mod_action", "p_target_tipo" "public"."report_target_tipo", "p_target_id" "uuid", "p_target_label" "text", "p_motivazione" "text", "p_durata" "text", "p_report_id" "uuid", "p_scope" "public"."mod_scope", "p_club_slug" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."bottle_units_ciclo_di_vita"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."catalogo_risolvi_vino_utente"("p_produttore" "text", "p_nome" "text", "p_annata" integer, "p_regione" "text", "p_tipo" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."club_post_figlio_guard"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."club_post_immutabile_guard"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."club_post_riferimenti_guard"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."commercio_rimosso_guard"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."conversation_assert_valid"("p_conversation_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."conversation_create"("p_listing_id" "uuid", "p_order_id" "uuid", "p_participant_low" "uuid", "p_participant_high" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."conversation_is_writable"("p_conversation_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."conversation_participant_guard"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."conversation_system_event"("p_conversation_id" "uuid", "p_source_event_key" "text", "p_body" "text", "p_recipient_id" "uuid", "p_event_type" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."conversation_system_event"("p_conversation_id" "uuid", "p_source_event_key" "text", "p_body" "text", "p_recipient_id" "uuid", "p_event_type" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."conversation_validate_participants"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."conversation_validate_row"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."listings_price_observation_sync"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."listings_riferimento_sync"() FROM PUBLIC;



GRANT ALL ON TABLE "public"."marketplace_config" TO "service_role";



REVOKE ALL ON FUNCTION "private"."marketplace_config_corrente"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."marketplace_totale_cents"("p_prezzo_cents" integer, "p_margine_obiettivo_bps" integer, "p_riferimento_percentuale_bps" integer, "p_riferimento_fisso_cents" integer) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."messages_after_insert"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."messages_immutable"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."moderazione_annuncio_transizione"("p_attore" "uuid", "p_listing_id" "uuid", "p_stato" "public"."listing_stato", "p_azione" "public"."mod_action", "p_motivazione" "text", "p_ammessi" "public"."listing_stato"[], "p_report_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."moderazione_attore"() FROM PUBLIC;



GRANT ALL ON TABLE "public"."reports" TO "service_role";



REVOKE ALL ON FUNCTION "private"."moderazione_bersaglio"("p_report" "public"."reports") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."moderazione_contenuto_club_transizione"("p_attore" "uuid", "p_report" "public"."reports", "p_rimuovi" boolean, "p_azione" "public"."mod_action", "p_motivazione" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."moderazione_pratica"("p_report_id" "uuid", "p_stato_pratica" "public"."report_stato", "p_motivazione" "text", "p_nota_interna" "text", "p_testo_visibile" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."moderazione_utente_provvedimento"("p_attore" "uuid", "p_profile_id" "uuid", "p_motivazione" "text", "p_durata" "text", "p_report_id" "uuid", "p_forza_rimozione" boolean) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."moderazione_utente_ripristina"("p_attore" "uuid", "p_profile_id" "uuid", "p_motivazione" "text", "p_report_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."notifications_after_change"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."orders_price_observation_sync"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."price_observation_registra"("p_wine_id" "uuid", "p_formato" "text", "p_tipo" "public"."price_observation_tipo", "p_prezzo_cents" integer, "p_observed_at" timestamp with time zone, "p_origine_ref" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."profile_certifications_guard"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."profiles_stato_utente_guard"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."rate_limit_consume"("p_scope" "text", "p_subject" "text", "p_limit" integer, "p_window_seconds" integer) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."regione_canonica"("p_regione" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."report_priorita_da_motivo"("p_motivo" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."scrittura_social_guard"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."tracking_registra"("p_order_id" "uuid", "p_tipo" "public"."tracking_event_tipo", "p_titolo" "text", "p_descrizione" "text", "p_luogo" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."utente_stato_di"("p_uid" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."vinea_check_request"() FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."vinea_check_request"() TO "anon";
GRANT ALL ON FUNCTION "private"."vinea_check_request"() TO "authenticated";
GRANT ALL ON FUNCTION "private"."vinea_check_request"() TO "authenticator";
GRANT ALL ON FUNCTION "private"."vinea_check_request"() TO "service_role";



REVOKE ALL ON FUNCTION "private"."wine_reference_snapshot_registra"("p_wine_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."wine_reference_snapshots_append_only"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."bottiglia_apri"("p_bottle_unit_id" "uuid", "p_nota" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."bottiglia_apri"("p_bottle_unit_id" "uuid", "p_nota" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."bottiglia_apri"("p_bottle_unit_id" "uuid", "p_nota" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."bottiglia_cancella"("p_bottle_unit_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."bottiglia_cancella"("p_bottle_unit_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."bottiglia_cancella"("p_bottle_unit_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."bottle_units_preserva_annuncio_non_terminale"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."bottle_units_preserva_annuncio_non_terminale"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."cellar_ambiente_crea"("p_nome" "text", "p_forma" "text", "p_tema" "text", "p_righe" integer, "p_colonne" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cellar_ambiente_crea"("p_nome" "text", "p_forma" "text", "p_tema" "text", "p_righe" integer, "p_colonne" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."cellar_ambiente_crea"("p_nome" "text", "p_forma" "text", "p_tema" "text", "p_righe" integer, "p_colonne" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."cellar_ambiente_e_mio"("p_environment_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cellar_ambiente_e_mio"("p_environment_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cellar_ambiente_e_mio"("p_environment_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."cellar_bottiglia_aggiungi"("p_produttore" "text", "p_nome" "text", "p_annata" integer, "p_regione" "text", "p_tipo" "text", "p_visibilita" "public"."bottle_unit_visibilita", "p_immagini" "text"[], "p_acquisition_cost_cents" integer, "p_acquired_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cellar_bottiglia_aggiungi"("p_produttore" "text", "p_nome" "text", "p_annata" integer, "p_regione" "text", "p_tipo" "text", "p_visibilita" "public"."bottle_unit_visibilita", "p_immagini" "text"[], "p_acquisition_cost_cents" integer, "p_acquired_at" timestamp with time zone) TO "service_role";
GRANT ALL ON FUNCTION "public"."cellar_bottiglia_aggiungi"("p_produttore" "text", "p_nome" "text", "p_annata" integer, "p_regione" "text", "p_tipo" "text", "p_visibilita" "public"."bottle_unit_visibilita", "p_immagini" "text"[], "p_acquisition_cost_cents" integer, "p_acquired_at" timestamp with time zone) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."cellar_modulo_e_mio"("p_module_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cellar_modulo_e_mio"("p_module_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cellar_modulo_e_mio"("p_module_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."cellar_portfolio_analitica"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cellar_portfolio_analitica"() TO "service_role";
GRANT ALL ON FUNCTION "public"."cellar_portfolio_analitica"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."cellar_posiziona"("p_bottle_unit_id" "uuid", "p_module_id" "uuid", "p_riga" integer, "p_colonna" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cellar_posiziona"("p_bottle_unit_id" "uuid", "p_module_id" "uuid", "p_riga" integer, "p_colonna" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cellar_posiziona"("p_bottle_unit_id" "uuid", "p_module_id" "uuid", "p_riga" integer, "p_colonna" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."cellar_togli_posizione"("p_bottle_unit_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cellar_togli_posizione"("p_bottle_unit_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cellar_togli_posizione"("p_bottle_unit_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."clubs" TO "service_role";



REVOKE ALL ON FUNCTION "public"."club_crea"("p_nome" "text", "p_descrizione" "text", "p_regole" "text"[], "p_posting_mode" "text", "p_cover_image" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."club_crea"("p_nome" "text", "p_descrizione" "text", "p_regole" "text"[], "p_posting_mode" "text", "p_cover_image" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."club_crea"("p_nome" "text", "p_descrizione" "text", "p_regole" "text"[], "p_posting_mode" "text", "p_cover_image" "text") TO "authenticated";



GRANT ALL ON TABLE "public"."orders" TO "service_role";



GRANT SELECT("id") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("listing_id") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("proposal_id") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("buyer_id") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("seller_id") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("seller_bottle_unit_id") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("buyer_bottle_unit_id") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("stato") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("delivery_mode") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("prezzo_cents") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("currency") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("reservation_expires_at") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("paid_at") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("created_at") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("updated_at") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("margine_obiettivo_bps") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("riferimento_stripe_percentuale_bps") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("riferimento_stripe_fisso_cents") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("commissione_cents") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("payout_stato") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("consegnato_at") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("auto_rilascio_scadenza") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("ricezione_confermata_at") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("contestato_at") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("contestazione_motivo") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("totale_cents") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("preparazione_avviata_at") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("spedito_at") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("corriere") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("tracking_number") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("imballaggio_checklist") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("imballaggio_foto") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("imballaggio_codice") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("imballaggio_provider") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("imballaggio_etichetta") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("imballaggio_cents") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("imballaggio_punto_id") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("imballaggio_punto_nome") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("imballaggio_scelto_at") ON TABLE "public"."orders" TO "authenticated";



GRANT SELECT("addebito_totale_cents") ON TABLE "public"."orders" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."conferma_ricezione"("p_order_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."conferma_ricezione"("p_order_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."conferma_ricezione"("p_order_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."conversation_mark_read"("p_conversation_id" "uuid", "p_message_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."conversation_mark_read"("p_conversation_id" "uuid", "p_message_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."conversation_mark_read"("p_conversation_id" "uuid", "p_message_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."conversation_open"("p_listing_id" "uuid", "p_order_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."conversation_open"("p_listing_id" "uuid", "p_order_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."conversation_open"("p_listing_id" "uuid", "p_order_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."conversations_page"("p_before_activity_at" timestamp with time zone, "p_before_id" "uuid", "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."conversations_page"("p_before_activity_at" timestamp with time zone, "p_before_id" "uuid", "p_limit" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."conversations_page"("p_before_activity_at" timestamp with time zone, "p_before_id" "uuid", "p_limit" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."handle_new_user"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."has_role"("p_user_id" "uuid", "p_role" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."has_role"("p_user_id" "uuid", "p_role" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_role"("p_user_id" "uuid", "p_role" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."listing_crea"("p_produttore" "text", "p_nome" "text", "p_annata" integer, "p_regione" "text", "p_tipo" "text", "p_prezzo_cents" integer, "p_condizione" "text", "p_conservazione" "text", "p_storia" "text", "p_immagini" "text"[], "p_bottle_unit_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."listing_crea"("p_produttore" "text", "p_nome" "text", "p_annata" integer, "p_regione" "text", "p_tipo" "text", "p_prezzo_cents" integer, "p_condizione" "text", "p_conservazione" "text", "p_storia" "text", "p_immagini" "text"[], "p_bottle_unit_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."listing_crea_da_bottiglia"("p_bottle_unit_id" "uuid", "p_prezzo_cents" integer, "p_condizione" "text", "p_conservazione" "text", "p_storia" "text", "p_immagini" "text"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."listing_crea_da_bottiglia"("p_bottle_unit_id" "uuid", "p_prezzo_cents" integer, "p_condizione" "text", "p_conservazione" "text", "p_storia" "text", "p_immagini" "text"[]) TO "service_role";
GRANT ALL ON FUNCTION "public"."listing_crea_da_bottiglia"("p_bottle_unit_id" "uuid", "p_prezzo_cents" integer, "p_condizione" "text", "p_conservazione" "text", "p_storia" "text", "p_immagini" "text"[]) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."listing_imballaggio_dichiara"("p_listing_id" "uuid", "p_codice" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."listing_imballaggio_dichiara"("p_listing_id" "uuid", "p_codice" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."listing_imballaggio_dichiara"("p_listing_id" "uuid", "p_codice" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."listing_pubblica"("p_listing_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."listing_pubblica"("p_listing_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."listing_pubblica"("p_listing_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."listing_scadi"("p_listing_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."listing_scadi"("p_listing_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."listing_scadi"("p_listing_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."listing_sospendi"("p_listing_id" "uuid", "p_motivo" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."listing_sospendi"("p_listing_id" "uuid", "p_motivo" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."listing_sospendi"("p_listing_id" "uuid", "p_motivo" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."listings_bottiglia_idonea"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."listings_bottiglia_idonea"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."listings_marca_bottiglia_ceduta"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."listings_marca_bottiglia_ceduta"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."message_send"("p_conversation_id" "uuid", "p_text" "text", "p_idempotency_key" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."message_send"("p_conversation_id" "uuid", "p_text" "text", "p_idempotency_key" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."message_send"("p_conversation_id" "uuid", "p_text" "text", "p_idempotency_key" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."messages_page"("p_conversation_id" "uuid", "p_before_created_at" timestamp with time zone, "p_before_id" "uuid", "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."messages_page"("p_conversation_id" "uuid", "p_before_created_at" timestamp with time zone, "p_before_id" "uuid", "p_limit" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."messages_page"("p_conversation_id" "uuid", "p_before_created_at" timestamp with time zone, "p_before_id" "uuid", "p_limit" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."moderazione_ammonizione"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."moderazione_ammonizione"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."moderazione_ammonizione"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."moderazione_annuncio_in_revisione"("p_listing_id" "uuid", "p_motivazione" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."moderazione_annuncio_in_revisione"("p_listing_id" "uuid", "p_motivazione" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."moderazione_annuncio_in_revisione"("p_listing_id" "uuid", "p_motivazione" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."moderazione_annuncio_modifiche_richieste"("p_listing_id" "uuid", "p_motivazione" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."moderazione_annuncio_modifiche_richieste"("p_listing_id" "uuid", "p_motivazione" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."moderazione_annuncio_modifiche_richieste"("p_listing_id" "uuid", "p_motivazione" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."moderazione_annuncio_rifiuta"("p_listing_id" "uuid", "p_motivazione" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."moderazione_annuncio_rifiuta"("p_listing_id" "uuid", "p_motivazione" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."moderazione_annuncio_rifiuta"("p_listing_id" "uuid", "p_motivazione" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."moderazione_annuncio_ripristina"("p_listing_id" "uuid", "p_motivazione" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."moderazione_annuncio_ripristina"("p_listing_id" "uuid", "p_motivazione" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."moderazione_annuncio_ripristina"("p_listing_id" "uuid", "p_motivazione" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."moderazione_annuncio_sospendi"("p_listing_id" "uuid", "p_motivazione" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."moderazione_annuncio_sospendi"("p_listing_id" "uuid", "p_motivazione" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."moderazione_annuncio_sospendi"("p_listing_id" "uuid", "p_motivazione" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."moderazione_chiusura"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."moderazione_chiusura"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."moderazione_chiusura"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."moderazione_info_richieste"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."moderazione_info_richieste"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."moderazione_info_richieste"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."moderazione_richiesta_modifiche"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."moderazione_richiesta_modifiche"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."moderazione_richiesta_modifiche"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."moderazione_rimozione"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."moderazione_rimozione"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."moderazione_rimozione"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."moderazione_ripristino"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."moderazione_ripristino"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."moderazione_ripristino"("p_report_id" "uuid", "p_motivazione" "text", "p_nota_interna" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."moderazione_sospensione"("p_report_id" "uuid", "p_motivazione" "text", "p_durata" "text", "p_nota_interna" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."moderazione_sospensione"("p_report_id" "uuid", "p_motivazione" "text", "p_durata" "text", "p_nota_interna" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."moderazione_sospensione"("p_report_id" "uuid", "p_motivazione" "text", "p_durata" "text", "p_nota_interna" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."notification_mark_read"("p_notification_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."notification_mark_read"("p_notification_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."notification_mark_read"("p_notification_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."notifications_mark_all_read"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."notifications_mark_all_read"() TO "service_role";
GRANT ALL ON FUNCTION "public"."notifications_mark_all_read"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."notifications_page"("p_before_created_at" timestamp with time zone, "p_before_id" "uuid", "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."notifications_page"("p_before_created_at" timestamp with time zone, "p_before_id" "uuid", "p_limit" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."notifications_page"("p_before_created_at" timestamp with time zone, "p_before_id" "uuid", "p_limit" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."notifications_unread_count"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."notifications_unread_count"() TO "service_role";
GRANT ALL ON FUNCTION "public"."notifications_unread_count"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."order_checkout_release"("p_order_id" "uuid", "p_buyer_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."order_checkout_release"("p_order_id" "uuid", "p_buyer_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."order_checkout_reserve"("p_buyer_id" "uuid", "p_listing_id" "uuid", "p_proposal_id" "uuid", "p_delivery_mode" "public"."delivery_mode", "p_idempotency_key" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."order_checkout_reserve"("p_buyer_id" "uuid", "p_listing_id" "uuid", "p_proposal_id" "uuid", "p_delivery_mode" "public"."delivery_mode", "p_idempotency_key" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."order_seller_stato"("p_order" "public"."orders") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."order_seller_stato"("p_order" "public"."orders") TO "service_role";
GRANT ALL ON FUNCTION "public"."order_seller_stato"("p_order" "public"."orders") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."ordine_auto_rilascio_esegui"("p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ordine_auto_rilascio_esegui"("p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."ordine_contesta"("p_order_id" "uuid", "p_motivo" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ordine_contesta"("p_order_id" "uuid", "p_motivo" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."ordine_contestazione_apri"("p_order_id" "uuid", "p_motivo" "text", "p_descrizione" "text", "p_foto" "text"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ordine_contestazione_apri"("p_order_id" "uuid", "p_motivo" "text", "p_descrizione" "text", "p_foto" "text"[]) TO "service_role";
GRANT ALL ON FUNCTION "public"."ordine_contestazione_apri"("p_order_id" "uuid", "p_motivo" "text", "p_descrizione" "text", "p_foto" "text"[]) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."ordine_contestazione_risolvi"("p_order_id" "uuid", "p_esito" "public"."dispute_stato", "p_nota" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ordine_contestazione_risolvi"("p_order_id" "uuid", "p_esito" "public"."dispute_stato", "p_nota" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."ordine_imballaggio_punto_scegli"("p_order_id" "uuid", "p_punto_id" "text", "p_punto_nome" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ordine_imballaggio_punto_scegli"("p_order_id" "uuid", "p_punto_id" "text", "p_punto_nome" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."ordine_imballaggio_punto_scegli"("p_order_id" "uuid", "p_punto_id" "text", "p_punto_nome" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."ordine_prepara_spedizione"("p_order_id" "uuid", "p_checklist" "jsonb", "p_foto" "text"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ordine_prepara_spedizione"("p_order_id" "uuid", "p_checklist" "jsonb", "p_foto" "text"[]) TO "service_role";
GRANT ALL ON FUNCTION "public"."ordine_prepara_spedizione"("p_order_id" "uuid", "p_checklist" "jsonb", "p_foto" "text"[]) TO "authenticated";



GRANT ALL ON TABLE "public"."order_reviews" TO "service_role";
GRANT SELECT ON TABLE "public"."order_reviews" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."ordine_recensisci"("p_order_id" "uuid", "p_voto" smallint, "p_conformita" smallint, "p_imballaggio" smallint, "p_comunicazione" smallint, "p_testo" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ordine_recensisci"("p_order_id" "uuid", "p_voto" smallint, "p_conformita" smallint, "p_imballaggio" smallint, "p_comunicazione" smallint, "p_testo" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."ordine_recensisci"("p_order_id" "uuid", "p_voto" smallint, "p_conformita" smallint, "p_imballaggio" smallint, "p_comunicazione" smallint, "p_testo" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."ordine_segna_consegnato"("p_order_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ordine_segna_consegnato"("p_order_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."ordine_segna_consegnato"("p_order_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."ordine_segna_spedito"("p_order_id" "uuid", "p_corriere" "text", "p_tracking_number" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ordine_segna_spedito"("p_order_id" "uuid", "p_corriere" "text", "p_tracking_number" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."ordine_segna_spedito"("p_order_id" "uuid", "p_corriere" "text", "p_tracking_number" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."payment_apply_provider_event"("p_provider" "text", "p_event_id" "text", "p_outcome" "public"."payment_outcome", "p_occurred_at" bigint, "p_object" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."payment_apply_provider_event"("p_provider" "text", "p_event_id" "text", "p_outcome" "public"."payment_outcome", "p_occurred_at" bigint, "p_object" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."payment_checkout_attach"("p_order_id" "uuid", "p_buyer_id" "uuid", "p_provider" "text", "p_provider_session_id" "text", "p_checkout_url" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."payment_checkout_attach"("p_order_id" "uuid", "p_buyer_id" "uuid", "p_provider" "text", "p_provider_session_id" "text", "p_checkout_url" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."payment_fee_reale_registra"("p_provider" "text", "p_provider_intent_id" "text", "p_fee_cents" integer, "p_transazione_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."payment_fee_reale_registra"("p_provider" "text", "p_provider_intent_id" "text", "p_fee_cents" integer, "p_transazione_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."payout_coda"("p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."payout_coda"("p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."payout_prepara"("p_order_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."payout_prepara"("p_order_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."payout_registra_esito"("p_payout_id" "uuid", "p_ok" boolean, "p_provider_transfer_id" "text", "p_errore" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."payout_registra_esito"("p_payout_id" "uuid", "p_ok" boolean, "p_provider_transfer_id" "text", "p_errore" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."profilo_pubblico"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."profilo_pubblico"("p_user_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."profilo_pubblico"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."profilo_pubblico"("p_user_id" "uuid") TO "authenticated";



GRANT ALL ON TABLE "public"."proposals" TO "service_role";
GRANT SELECT ON TABLE "public"."proposals" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."proposal_accetta"("p_proposal_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."proposal_accetta"("p_proposal_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."proposal_accetta"("p_proposal_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."proposal_controproponi"("p_proposal_id" "uuid", "p_prezzo_cents" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."proposal_controproponi"("p_proposal_id" "uuid", "p_prezzo_cents" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."proposal_controproponi"("p_proposal_id" "uuid", "p_prezzo_cents" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."proposal_invia"("p_listing_id" "uuid", "p_prezzo_cents" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."proposal_invia"("p_listing_id" "uuid", "p_prezzo_cents" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."proposal_invia"("p_listing_id" "uuid", "p_prezzo_cents" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."proposal_rifiuta"("p_proposal_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."proposal_rifiuta"("p_proposal_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."proposal_rifiuta"("p_proposal_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."rate_limit_consume"("p_scope" "text", "p_subject" "text", "p_limit" integer, "p_window_seconds" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rate_limit_consume"("p_scope" "text", "p_subject" "text", "p_limit" integer, "p_window_seconds" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."rls_auto_enable"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."segnalazione_invia"("p_target_tipo" "public"."report_target_tipo", "p_target_id" "uuid", "p_target_label" "text", "p_motivo" "text", "p_descrizione" "text", "p_foto" "text"[], "p_club_slug" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."segnalazione_invia"("p_target_tipo" "public"."report_target_tipo", "p_target_id" "uuid", "p_target_label" "text", "p_motivo" "text", "p_descrizione" "text", "p_foto" "text"[], "p_club_slug" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."segnalazione_invia"("p_target_tipo" "public"."report_target_tipo", "p_target_id" "uuid", "p_target_label" "text", "p_motivo" "text", "p_descrizione" "text", "p_foto" "text"[], "p_club_slug" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."seller_payout_account_apply_event"("p_provider" "text", "p_event_id" "text", "p_provider_event_type" "text", "p_provider_account_id" "text", "p_charges_enabled" boolean, "p_payouts_enabled" boolean, "p_details_submitted" boolean, "p_requisiti" "text"[], "p_disabled_reason" "text", "p_occurred_at" bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."seller_payout_account_apply_event"("p_provider" "text", "p_event_id" "text", "p_provider_event_type" "text", "p_provider_account_id" "text", "p_charges_enabled" boolean, "p_payouts_enabled" boolean, "p_details_submitted" boolean, "p_requisiti" "text"[], "p_disabled_reason" "text", "p_occurred_at" bigint) TO "service_role";



REVOKE ALL ON FUNCTION "public"."seller_payout_account_get"("p_seller_id" "uuid", "p_provider" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."seller_payout_account_get"("p_seller_id" "uuid", "p_provider" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."seller_payout_account_upsert"("p_seller_id" "uuid", "p_provider" "text", "p_provider_account_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."seller_payout_account_upsert"("p_seller_id" "uuid", "p_provider" "text", "p_provider_account_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."slugifica"("p_testo" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."slugifica"("p_testo" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."sommelier_contesto_leggi"("p_owner_id" "uuid", "p_session_id" "text", "p_limite" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."sommelier_contesto_leggi"("p_owner_id" "uuid", "p_session_id" "text", "p_limite" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."sommelier_scambio_registra"("p_owner_id" "uuid", "p_session_id" "text", "p_domanda" "text", "p_risposta" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."sommelier_scambio_registra"("p_owner_id" "uuid", "p_session_id" "text", "p_domanda" "text", "p_risposta" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."sommelier_storico_cancella"("p_session_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."sommelier_storico_cancella"("p_session_id" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."sommelier_storico_cancella"("p_session_id" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."utente_maggiorenne"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."utente_maggiorenne"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."profile_certifications" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT UPDATE("username") ON TABLE "public"."profiles" TO "authenticated";



GRANT UPDATE("bio") ON TABLE "public"."profiles" TO "authenticated";



GRANT UPDATE("citta") ON TABLE "public"."profiles" TO "authenticated";



GRANT UPDATE("provincia") ON TABLE "public"."profiles" TO "authenticated";



GRANT UPDATE("esperienza") ON TABLE "public"."profiles" TO "authenticated";



GRANT UPDATE("avatar_url") ON TABLE "public"."profiles" TO "authenticated";



GRANT UPDATE("dob") ON TABLE "public"."profiles" TO "authenticated";



GRANT UPDATE("obiettivi") ON TABLE "public"."profiles" TO "authenticated";



GRANT ALL ON TABLE "public"."account_provider_events" TO "service_role";



GRANT ALL ON TABLE "public"."audit_log" TO "service_role";



GRANT ALL ON TABLE "public"."bottle_units" TO "service_role";
GRANT SELECT ON TABLE "public"."bottle_units" TO "authenticated";



GRANT UPDATE("visibilita") ON TABLE "public"."bottle_units" TO "authenticated";



GRANT UPDATE("apertura_pianificata") ON TABLE "public"."bottle_units" TO "authenticated";



GRANT UPDATE("note_personali") ON TABLE "public"."bottle_units" TO "authenticated";



GRANT UPDATE("prezzo_visibilita") ON TABLE "public"."bottle_units" TO "authenticated";



GRANT UPDATE("override_finestra_inizio") ON TABLE "public"."bottle_units" TO "authenticated";



GRANT UPDATE("override_finestra_fine") ON TABLE "public"."bottle_units" TO "authenticated";



GRANT UPDATE("override_apice_inizio") ON TABLE "public"."bottle_units" TO "authenticated";



GRANT UPDATE("override_apice_fine") ON TABLE "public"."bottle_units" TO "authenticated";



GRANT UPDATE("override_preferenza") ON TABLE "public"."bottle_units" TO "authenticated";



GRANT UPDATE("override_nota") ON TABLE "public"."bottle_units" TO "authenticated";



GRANT ALL ON TABLE "public"."cellar_environments" TO "service_role";
GRANT SELECT,DELETE ON TABLE "public"."cellar_environments" TO "authenticated";



GRANT UPDATE("nome") ON TABLE "public"."cellar_environments" TO "authenticated";



GRANT UPDATE("forma") ON TABLE "public"."cellar_environments" TO "authenticated";



GRANT UPDATE("tema") ON TABLE "public"."cellar_environments" TO "authenticated";



GRANT UPDATE("materiale") ON TABLE "public"."cellar_environments" TO "authenticated";



GRANT UPDATE("illuminazione") ON TABLE "public"."cellar_environments" TO "authenticated";



GRANT UPDATE("larghezza_cm") ON TABLE "public"."cellar_environments" TO "authenticated";



GRANT UPDATE("altezza_cm") ON TABLE "public"."cellar_environments" TO "authenticated";



GRANT UPDATE("profondita_cm") ON TABLE "public"."cellar_environments" TO "authenticated";



GRANT ALL ON TABLE "public"."cellar_modules" TO "service_role";
GRANT SELECT,DELETE ON TABLE "public"."cellar_modules" TO "authenticated";



GRANT UPDATE("etichetta") ON TABLE "public"."cellar_modules" TO "authenticated";



GRANT UPDATE("posizione_x") ON TABLE "public"."cellar_modules" TO "authenticated";



GRANT UPDATE("posizione_y") ON TABLE "public"."cellar_modules" TO "authenticated";



GRANT UPDATE("posizione_z") ON TABLE "public"."cellar_modules" TO "authenticated";



GRANT UPDATE("rotazione_y") ON TABLE "public"."cellar_modules" TO "authenticated";



GRANT UPDATE("righe") ON TABLE "public"."cellar_modules" TO "authenticated";



GRANT UPDATE("colonne") ON TABLE "public"."cellar_modules" TO "authenticated";



GRANT UPDATE("profondita") ON TABLE "public"."cellar_modules" TO "authenticated";



GRANT ALL ON TABLE "public"."cellar_slots" TO "service_role";
GRANT SELECT ON TABLE "public"."cellar_slots" TO "authenticated";



GRANT ALL ON TABLE "public"."club_memberships" TO "service_role";
GRANT SELECT,DELETE ON TABLE "public"."club_memberships" TO "authenticated";



GRANT INSERT("club_slug") ON TABLE "public"."club_memberships" TO "authenticated";



GRANT ALL ON TABLE "public"."club_post_like" TO "service_role";
GRANT SELECT,DELETE ON TABLE "public"."club_post_like" TO "authenticated";



GRANT INSERT("post_id") ON TABLE "public"."club_post_like" TO "authenticated";



GRANT ALL ON TABLE "public"."club_post_risposte" TO "service_role";



GRANT SELECT("id") ON TABLE "public"."club_post_risposte" TO "authenticated";



GRANT SELECT("post_id"),INSERT("post_id") ON TABLE "public"."club_post_risposte" TO "authenticated";



GRANT SELECT("autore_id") ON TABLE "public"."club_post_risposte" TO "authenticated";



GRANT SELECT("corpo"),INSERT("corpo"),UPDATE("corpo") ON TABLE "public"."club_post_risposte" TO "authenticated";



GRANT SELECT("rimosso_at") ON TABLE "public"."club_post_risposte" TO "authenticated";



GRANT SELECT("created_at") ON TABLE "public"."club_post_risposte" TO "authenticated";



GRANT ALL ON TABLE "public"."club_posts" TO "service_role";



GRANT SELECT("id") ON TABLE "public"."club_posts" TO "authenticated";



GRANT SELECT("club_slug"),INSERT("club_slug") ON TABLE "public"."club_posts" TO "authenticated";



GRANT SELECT("autore_id") ON TABLE "public"."club_posts" TO "authenticated";



GRANT SELECT("tipo"),INSERT("tipo") ON TABLE "public"."club_posts" TO "authenticated";



GRANT SELECT("titolo"),INSERT("titolo"),UPDATE("titolo") ON TABLE "public"."club_posts" TO "authenticated";



GRANT SELECT("corpo"),INSERT("corpo"),UPDATE("corpo") ON TABLE "public"."club_posts" TO "authenticated";



GRANT SELECT("bottle_unit_id"),INSERT("bottle_unit_id") ON TABLE "public"."club_posts" TO "authenticated";



GRANT SELECT("wine_id"),INSERT("wine_id") ON TABLE "public"."club_posts" TO "authenticated";



GRANT SELECT("listing_id"),INSERT("listing_id") ON TABLE "public"."club_posts" TO "authenticated";



GRANT SELECT("rimosso_at") ON TABLE "public"."club_posts" TO "authenticated";



GRANT SELECT("created_at") ON TABLE "public"."club_posts" TO "authenticated";



GRANT ALL ON TABLE "public"."conversation_participants" TO "service_role";



GRANT SELECT("conversation_id") ON TABLE "public"."conversation_participants" TO "authenticated";



GRANT SELECT("user_id") ON TABLE "public"."conversation_participants" TO "authenticated";



GRANT SELECT("joined_at") ON TABLE "public"."conversation_participants" TO "authenticated";



GRANT SELECT("last_read_message_id") ON TABLE "public"."conversation_participants" TO "authenticated";



GRANT SELECT("last_read_created_at") ON TABLE "public"."conversation_participants" TO "authenticated";



GRANT ALL ON TABLE "public"."conversations" TO "service_role";



GRANT SELECT("id") ON TABLE "public"."conversations" TO "authenticated";



GRANT SELECT("participant_low") ON TABLE "public"."conversations" TO "authenticated";



GRANT SELECT("participant_high") ON TABLE "public"."conversations" TO "authenticated";



GRANT SELECT("listing_id") ON TABLE "public"."conversations" TO "authenticated";



GRANT SELECT("order_id") ON TABLE "public"."conversations" TO "authenticated";



GRANT SELECT("last_message_id") ON TABLE "public"."conversations" TO "authenticated";



GRANT SELECT("last_message_at") ON TABLE "public"."conversations" TO "authenticated";



GRANT SELECT("created_at") ON TABLE "public"."conversations" TO "authenticated";



GRANT ALL ON TABLE "public"."disputes" TO "service_role";



GRANT SELECT("id") ON TABLE "public"."disputes" TO "authenticated";



GRANT SELECT("order_id") ON TABLE "public"."disputes" TO "authenticated";



GRANT SELECT("aperta_da") ON TABLE "public"."disputes" TO "authenticated";



GRANT SELECT("motivo") ON TABLE "public"."disputes" TO "authenticated";



GRANT SELECT("descrizione") ON TABLE "public"."disputes" TO "authenticated";



GRANT SELECT("foto") ON TABLE "public"."disputes" TO "authenticated";



GRANT SELECT("stato") ON TABLE "public"."disputes" TO "authenticated";



GRANT SELECT("esito_nota") ON TABLE "public"."disputes" TO "authenticated";



GRANT SELECT("apertura_at") ON TABLE "public"."disputes" TO "authenticated";



GRANT SELECT("chiusura_at") ON TABLE "public"."disputes" TO "authenticated";



GRANT ALL ON TABLE "public"."listings" TO "service_role";



GRANT SELECT("id") ON TABLE "public"."listings" TO "authenticated";



GRANT SELECT("slug"),INSERT("slug") ON TABLE "public"."listings" TO "authenticated";



GRANT SELECT("seller_id") ON TABLE "public"."listings" TO "authenticated";



GRANT SELECT("bottle_unit_id"),INSERT("bottle_unit_id") ON TABLE "public"."listings" TO "authenticated";



GRANT SELECT("stato") ON TABLE "public"."listings" TO "authenticated";



GRANT SELECT("prezzo_cents"),INSERT("prezzo_cents"),UPDATE("prezzo_cents") ON TABLE "public"."listings" TO "authenticated";



GRANT SELECT("prezzo_mercato_cents"),INSERT("prezzo_mercato_cents"),UPDATE("prezzo_mercato_cents") ON TABLE "public"."listings" TO "authenticated";



GRANT SELECT("condizione"),INSERT("condizione"),UPDATE("condizione") ON TABLE "public"."listings" TO "authenticated";



GRANT SELECT("conservazione"),INSERT("conservazione"),UPDATE("conservazione") ON TABLE "public"."listings" TO "authenticated";



GRANT SELECT("storia"),INSERT("storia"),UPDATE("storia") ON TABLE "public"."listings" TO "authenticated";



GRANT SELECT("degustazione"),INSERT("degustazione"),UPDATE("degustazione") ON TABLE "public"."listings" TO "authenticated";



GRANT SELECT("immagini"),INSERT("immagini"),UPDATE("immagini") ON TABLE "public"."listings" TO "authenticated";



GRANT SELECT("tag"),INSERT("tag"),UPDATE("tag") ON TABLE "public"."listings" TO "authenticated";



GRANT SELECT("published_at") ON TABLE "public"."listings" TO "authenticated";



GRANT SELECT("expires_at") ON TABLE "public"."listings" TO "authenticated";



GRANT SELECT("created_at") ON TABLE "public"."listings" TO "authenticated";



GRANT SELECT("updated_at") ON TABLE "public"."listings" TO "authenticated";



GRANT ALL ON TABLE "public"."listing_bottle_units" TO "service_role";



GRANT ALL ON SEQUENCE "public"."marketplace_config_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."marketplace_config_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."marketplace_config_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."messages" TO "service_role";



GRANT SELECT("id") ON TABLE "public"."messages" TO "authenticated";



GRANT SELECT("conversation_id") ON TABLE "public"."messages" TO "authenticated";



GRANT SELECT("sender_id") ON TABLE "public"."messages" TO "authenticated";



GRANT SELECT("kind") ON TABLE "public"."messages" TO "authenticated";



GRANT SELECT("body") ON TABLE "public"."messages" TO "authenticated";



GRANT SELECT("created_at") ON TABLE "public"."messages" TO "authenticated";



GRANT ALL ON TABLE "public"."user_roles" TO "service_role";



GRANT SELECT("user_id") ON TABLE "public"."user_roles" TO "authenticated";



GRANT SELECT("role") ON TABLE "public"."user_roles" TO "authenticated";



GRANT ALL ON TABLE "public"."moderation_audit_log" TO "service_role";
GRANT SELECT ON TABLE "public"."moderation_audit_log" TO "authenticated";



GRANT ALL ON TABLE "public"."moderation_dispute_queue" TO "service_role";
GRANT SELECT ON TABLE "public"."moderation_dispute_queue" TO "authenticated";



GRANT ALL ON TABLE "public"."report_events" TO "service_role";



GRANT ALL ON TABLE "public"."moderation_report_events" TO "service_role";
GRANT SELECT ON TABLE "public"."moderation_report_events" TO "authenticated";



GRANT ALL ON TABLE "public"."moderation_report_queue" TO "service_role";
GRANT SELECT ON TABLE "public"."moderation_report_queue" TO "authenticated";



GRANT ALL ON TABLE "public"."my_certifications" TO "service_role";
GRANT SELECT ON TABLE "public"."my_certifications" TO "authenticated";



GRANT ALL ON TABLE "public"."my_listing_moderation" TO "service_role";
GRANT SELECT ON TABLE "public"."my_listing_moderation" TO "authenticated";



GRANT ALL ON TABLE "public"."my_report_events" TO "service_role";
GRANT SELECT ON TABLE "public"."my_report_events" TO "authenticated";



GRANT ALL ON TABLE "public"."my_reports" TO "service_role";
GRANT SELECT ON TABLE "public"."my_reports" TO "authenticated";



GRANT ALL ON TABLE "public"."sommelier_messaggi" TO "service_role";



GRANT ALL ON TABLE "public"."my_sommelier_messages" TO "service_role";
GRANT SELECT ON TABLE "public"."my_sommelier_messages" TO "authenticated";



GRANT ALL ON TABLE "public"."notifications" TO "service_role";



GRANT SELECT("id") ON TABLE "public"."notifications" TO "authenticated";



GRANT SELECT("recipient_id") ON TABLE "public"."notifications" TO "authenticated";



GRANT SELECT("category") ON TABLE "public"."notifications" TO "authenticated";



GRANT SELECT("event_type") ON TABLE "public"."notifications" TO "authenticated";



GRANT SELECT("body") ON TABLE "public"."notifications" TO "authenticated";



GRANT SELECT("destination_kind") ON TABLE "public"."notifications" TO "authenticated";



GRANT SELECT("destination_conversation_id") ON TABLE "public"."notifications" TO "authenticated";



GRANT SELECT("destination_listing_id") ON TABLE "public"."notifications" TO "authenticated";



GRANT SELECT("destination_order_id") ON TABLE "public"."notifications" TO "authenticated";



GRANT SELECT("destination_club_slug") ON TABLE "public"."notifications" TO "authenticated";



GRANT SELECT("read_at") ON TABLE "public"."notifications" TO "authenticated";



GRANT SELECT("created_at") ON TABLE "public"."notifications" TO "authenticated";



GRANT ALL ON TABLE "public"."order_events" TO "service_role";
GRANT SELECT ON TABLE "public"."order_events" TO "authenticated";



GRANT ALL ON SEQUENCE "public"."order_events_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."order_events_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."order_events_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."payments" TO "service_role";



GRANT SELECT("id") ON TABLE "public"."payments" TO "authenticated";



GRANT SELECT("order_id") ON TABLE "public"."payments" TO "authenticated";



GRANT SELECT("stato") ON TABLE "public"."payments" TO "authenticated";



GRANT SELECT("amount_cents") ON TABLE "public"."payments" TO "authenticated";



GRANT SELECT("amount_refunded_cents") ON TABLE "public"."payments" TO "authenticated";



GRANT SELECT("currency") ON TABLE "public"."payments" TO "authenticated";



GRANT SELECT("created_at") ON TABLE "public"."payments" TO "authenticated";



GRANT SELECT("updated_at") ON TABLE "public"."payments" TO "authenticated";



GRANT ALL ON TABLE "public"."order_margine_riconciliazione" TO "service_role";



GRANT ALL ON TABLE "public"."packaging_options" TO "service_role";



GRANT ALL ON TABLE "public"."payment_provider_events" TO "service_role";



GRANT ALL ON TABLE "public"."payouts" TO "service_role";



GRANT SELECT("id") ON TABLE "public"."payouts" TO "authenticated";



GRANT SELECT("order_id") ON TABLE "public"."payouts" TO "authenticated";



GRANT SELECT("seller_id") ON TABLE "public"."payouts" TO "authenticated";



GRANT SELECT("amount_cents") ON TABLE "public"."payouts" TO "authenticated";



GRANT SELECT("currency") ON TABLE "public"."payouts" TO "authenticated";



GRANT SELECT("stato") ON TABLE "public"."payouts" TO "authenticated";



GRANT SELECT("transferred_at") ON TABLE "public"."payouts" TO "authenticated";



GRANT SELECT("created_at") ON TABLE "public"."payouts" TO "authenticated";



GRANT SELECT("updated_at") ON TABLE "public"."payouts" TO "authenticated";



GRANT ALL ON TABLE "public"."public_club_post_risposte" TO "service_role";
GRANT SELECT ON TABLE "public"."public_club_post_risposte" TO "anon";
GRANT SELECT ON TABLE "public"."public_club_post_risposte" TO "authenticated";



GRANT ALL ON TABLE "public"."wines" TO "service_role";
GRANT DELETE ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("id") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("id") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("slug") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("slug"),INSERT("slug"),UPDATE("slug") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("produttore") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("produttore"),INSERT("produttore"),UPDATE("produttore") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("nome") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("nome"),INSERT("nome"),UPDATE("nome") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("annata") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("annata"),INSERT("annata"),UPDATE("annata") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("regione") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("regione"),INSERT("regione"),UPDATE("regione") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("denominazione") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("denominazione"),INSERT("denominazione"),UPDATE("denominazione") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("tipo") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("tipo"),INSERT("tipo"),UPDATE("tipo") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("formato") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("formato"),INSERT("formato"),UPDATE("formato") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("created_at") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("created_at") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("updated_at") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("updated_at") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("finestra_inizio") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("finestra_inizio"),INSERT("finestra_inizio"),UPDATE("finestra_inizio") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("finestra_fine") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("finestra_fine"),INSERT("finestra_fine"),UPDATE("finestra_fine") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("apice_inizio") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("apice_inizio"),INSERT("apice_inizio"),UPDATE("apice_inizio") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("apice_fine") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("apice_fine"),INSERT("apice_fine"),UPDATE("apice_fine") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("finestra_fonte") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("finestra_fonte"),INSERT("finestra_fonte"),UPDATE("finestra_fonte") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("finestra_affidabilita") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("finestra_affidabilita"),INSERT("finestra_affidabilita"),UPDATE("finestra_affidabilita") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("finestra_aggiornata_at") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("finestra_aggiornata_at"),INSERT("finestra_aggiornata_at"),UPDATE("finestra_aggiornata_at") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("temperatura_servizio") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("temperatura_servizio"),INSERT("temperatura_servizio"),UPDATE("temperatura_servizio") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("decantazione_minuti") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("decantazione_minuti"),INSERT("decantazione_minuti"),UPDATE("decantazione_minuti") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("calice") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("calice"),INSERT("calice"),UPDATE("calice") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("occasione") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("occasione"),INSERT("occasione"),UPDATE("occasione") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("abbinamenti") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("abbinamenti"),INSERT("abbinamenti"),UPDATE("abbinamenti") ON TABLE "public"."wines" TO "authenticated";



GRANT SELECT("provenienza") ON TABLE "public"."wines" TO "anon";
GRANT SELECT("provenienza") ON TABLE "public"."wines" TO "authenticated";



GRANT ALL ON TABLE "public"."public_listings" TO "service_role";
GRANT SELECT ON TABLE "public"."public_listings" TO "anon";
GRANT SELECT ON TABLE "public"."public_listings" TO "authenticated";



GRANT ALL ON TABLE "public"."public_club_posts" TO "service_role";
GRANT SELECT ON TABLE "public"."public_club_posts" TO "anon";
GRANT SELECT ON TABLE "public"."public_club_posts" TO "authenticated";



GRANT ALL ON TABLE "public"."public_clubs" TO "service_role";
GRANT SELECT ON TABLE "public"."public_clubs" TO "anon";
GRANT SELECT ON TABLE "public"."public_clubs" TO "authenticated";



GRANT ALL ON TABLE "public"."public_marketplace_config" TO "anon";
GRANT ALL ON TABLE "public"."public_marketplace_config" TO "authenticated";
GRANT ALL ON TABLE "public"."public_marketplace_config" TO "service_role";



GRANT ALL ON TABLE "public"."public_packaging_options" TO "service_role";
GRANT SELECT ON TABLE "public"."public_packaging_options" TO "anon";
GRANT SELECT ON TABLE "public"."public_packaging_options" TO "authenticated";



GRANT ALL ON TABLE "public"."report_reasons" TO "service_role";



GRANT SELECT("target_tipo") ON TABLE "public"."report_reasons" TO "authenticated";
GRANT SELECT("target_tipo") ON TABLE "public"."report_reasons" TO "anon";



GRANT SELECT("motivo") ON TABLE "public"."report_reasons" TO "authenticated";
GRANT SELECT("motivo") ON TABLE "public"."report_reasons" TO "anon";



GRANT SELECT("ordine") ON TABLE "public"."report_reasons" TO "authenticated";
GRANT SELECT("ordine") ON TABLE "public"."report_reasons" TO "anon";



GRANT ALL ON SEQUENCE "public"."reports_codice_seq" TO "service_role";



GRANT ALL ON TABLE "public"."seller_payout_accounts" TO "service_role";



GRANT SELECT("id") ON TABLE "public"."seller_payout_accounts" TO "authenticated";



GRANT SELECT("seller_id") ON TABLE "public"."seller_payout_accounts" TO "authenticated";



GRANT SELECT("provider") ON TABLE "public"."seller_payout_accounts" TO "authenticated";



GRANT SELECT("charges_enabled") ON TABLE "public"."seller_payout_accounts" TO "authenticated";



GRANT SELECT("payouts_enabled") ON TABLE "public"."seller_payout_accounts" TO "authenticated";



GRANT SELECT("details_submitted") ON TABLE "public"."seller_payout_accounts" TO "authenticated";



GRANT SELECT("requisiti_pendenti") ON TABLE "public"."seller_payout_accounts" TO "authenticated";



GRANT SELECT("disabled_reason") ON TABLE "public"."seller_payout_accounts" TO "authenticated";



GRANT SELECT("created_at") ON TABLE "public"."seller_payout_accounts" TO "authenticated";



GRANT SELECT("updated_at") ON TABLE "public"."seller_payout_accounts" TO "authenticated";



GRANT ALL ON SEQUENCE "public"."sommelier_messaggi_ordinale_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."sommelier_messaggi_ordinale_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."sommelier_messaggi_ordinale_seq" TO "service_role";



GRANT ALL ON TABLE "public"."tracking_events" TO "service_role";
GRANT SELECT ON TABLE "public"."tracking_events" TO "authenticated";



GRANT ALL ON SEQUENCE "public"."tracking_events_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."tracking_events_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."tracking_events_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."wine_price_observations" TO "service_role";



GRANT ALL ON TABLE "public"."wine_price_history" TO "service_role";
GRANT SELECT ON TABLE "public"."wine_price_history" TO "anon";
GRANT SELECT ON TABLE "public"."wine_price_history" TO "authenticated";



GRANT ALL ON TABLE "public"."wine_reference_snapshots" TO "service_role";



GRANT ALL ON TABLE "public"."wine_regions" TO "service_role";
GRANT SELECT ON TABLE "public"."wine_regions" TO "anon";
GRANT SELECT ON TABLE "public"."wine_regions" TO "authenticated";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







