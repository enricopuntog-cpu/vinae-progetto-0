-- Fase 12c - segnalazione e rimozione dei contenuti dei club.
--
-- Terzo checkpoint della Fase 12, e la meta inseparabile della 12b: nessun
-- contenuto pubblico scrivibile va in produzione senza un modo per segnalarlo.
-- I due checkpoint non si separano in merge, in nessuna circostanza e nemmeno
-- temporaneamente - mergiare la 12b da sola aprirebbe una finestra, di durata
-- decisa da quando la 12c viene approvata, in cui chiunque pubblica su una
-- superficie pubblica e nessuno puo segnalare cio che legge.
--
-- Presuppone applicati, in quest'ordine:
--   20260817120000_phase_12b_club_content.sql       (le tre tabelle)
--   20260817120500_phase_12c_report_target_enum.sql (i due valori dell'enum)
-- Il secondo e separato per una ragione di transazione spiegata nel suo
-- cappello, non per una decisione.
--
-- ---------------------------------------------------------------------------
-- IL BUCO CHE L'ESTENSIONE DELL'ENUM APRE DA SOLA
-- ---------------------------------------------------------------------------
-- `reports_target_coerente` della 9a (righe 200-212) e un `case target_tipo
-- ... end` SENZA RAMO `else`. Un `case` senza `else` che non trova
-- corrispondenza restituisce NULL, e un CHECK il cui predicato vale NULL
-- PASSA: NULL non e false.
--
-- Quindi il solo `alter type ... add value`, senza altro, renderebbe una
-- segnalazione di tipo `post` libera di portare `target_listing_id`
-- valorizzato - il vincolo di esclusivita che protegge i cinque bersagli
-- esistenti smetterebbe di dire qualcosa sui due nuovi. Non e un difetto
-- trovato leggendo il codice nuovo: e un difetto che il codice nuovo CREA nel
-- codice vecchio, e va chiuso nella stessa migrazione che lo apre.
--
-- I due vincoli sono quindi ridefiniti con i rami espliciti per i due valori
-- nuovi, e con un `else false` finale che la 9a non aveva: da qui in avanti un
-- ottavo valore aggiunto all'enum FALLISCE CHIUSO invece di passare in
-- silenzio. E' la correzione che rende questa classe di difetto irripetibile,
-- non solo risolta una volta.
--
-- Stessa classe di problema, esito diverso: `v_esiste` in segnalazione_invia
-- (9a:549) e anch'esso un `case` senza `else`, ma li il difetto FALLISCE
-- CHIUSO - `coalesce(v_esiste, false)` da «Bersaglio non trovato». Era quindi
-- funzionalita mancante e non un buco. Viene esteso lo stesso, o `post` e
-- `commento` sarebbero segnalabili in teoria e mai in pratica.
--
-- ---------------------------------------------------------------------------
-- NESSUNA TABELLA DI ORDINI, PAGAMENTI, CONTESTAZIONI O PAYOUT
-- ---------------------------------------------------------------------------
-- Il vincolo della 9c vale qui come nella 12a e nella 12b: la macchina di
-- pagamento non reagisce a nulla di sociale. Questo file non nomina nessuna di
-- quelle tabelle e non ridefinisce nessuna delle sei funzioni che le
-- attraversano. Una riga della griglia lo verifica invece di dichiararlo.

-- ---------------------------------------------------------------------------
-- I motivi ammessi per i due bersagli nuovi
-- ---------------------------------------------------------------------------
-- Copiati CARATTERE PER CARATTERE da frontend-next/src/data/moderation.ts:57-58,
-- che e la lista che il client invia. Il controllo di elenco chiuso in
-- segnalazione_invia confronta le due stringhe, quindi una differenza di un
-- accento sarebbe «Motivo non ammesso per questo tipo di bersaglio» a ogni
-- tentativo. Non e un timore teorico: succede gia sui motivi di `profilo`
-- della 9a, dove il database ha 'Identita sospetta' e il client manda
-- 'Identita' con l'accento. Quel difetto e di un'altra fase e non viene
-- corretto qui - e registrato nel report della PR e nella specifica.
-- I sette motivi qui sotto non hanno accenti in nessuna delle due copie.

insert into public.report_reasons (target_tipo, motivo, ordine) values
  ('post', 'Contenuto inappropriato', 1),
  ('post', 'Off-topic per il club', 2),
  ('post', 'Spam commerciale', 3),
  ('post', 'Disinformazione', 4),
  ('commento', 'Insulti o linguaggio offensivo', 1),
  ('commento', 'Molestia mirata', 2),
  ('commento', 'Spam', 3);

-- Nota sulla priorita derivata, verificata contro
-- private.report_priorita_da_motivo (9a:405) e non assunta:
--   'Molestia mirata'               -> '%molest%' -> alta
--   'Insulti o linguaggio offensivo'-> '%offens%' -> media
--   gli altri cinque                              -> bassa
-- La regola non viene toccata: i motivi nuovi ci cadono dentro con esiti
-- sensati, e cambiarla per i club sposterebbe anche gli altri cinque bersagli.

-- ---------------------------------------------------------------------------
-- Le due colonne di bersaglio nuove
-- ---------------------------------------------------------------------------
-- `on delete set null` come le altre cinque, e per lo stesso motivo: una
-- segnalazione deve sopravvivere alla rimozione di cio che segnala, altrimenti
-- moderare un contenuto cancellerebbe la prova del perche. `target_label`
-- conserva la descrizione leggibile ed e cio che resta quando il riferimento
-- si annulla.
--
-- Notare l'asimmetria voluta con la rimozione della 12b: la moderazione NON
-- cancella fisicamente un post, quindi in pratica questi riferimenti
-- sopravvivono. Si annullano solo se sparisce l'autore (profilo cancellato,
-- cascade) o il club.

alter table public.reports
  add column target_post_id uuid
    references public.club_posts (id) on delete set null,
  add column target_risposta_id uuid
    references public.club_post_risposte (id) on delete set null;

comment on column public.reports.target_post_id is
  'Bersaglio quando target_tipo = ''post''. Aggiunta dalla 12c: la 9a non '
  'poteva averla perche i club non avevano schema (decisione 7.6a).';

comment on column public.reports.target_risposta_id is
  'Bersaglio quando target_tipo = ''commento''. Il nome del valore dell''enum '
  'e `commento` perche viene dal mock; la tabella si chiama '
  'club_post_risposte.';

create index reports_target_post_idx
  on public.reports (target_post_id) where target_post_id is not null;
create index reports_target_risposta_idx
  on public.reports (target_risposta_id) where target_risposta_id is not null;

-- ---------------------------------------------------------------------------
-- I due vincoli di bersaglio, ridefiniti
-- ---------------------------------------------------------------------------

alter table public.reports drop constraint reports_target_esclusivo;
alter table public.reports drop constraint reports_target_coerente;

alter table public.reports
  add constraint reports_target_esclusivo check (
    (case when target_listing_id is not null then 1 else 0 end)
    + (case when target_profile_id is not null then 1 else 0 end)
    + (case when target_message_id is not null then 1 else 0 end)
    + (case when target_conversation_id is not null then 1 else 0 end)
    + (case when target_review_id is not null then 1 else 0 end)
    + (case when target_post_id is not null then 1 else 0 end)
    + (case when target_risposta_id is not null then 1 else 0 end)
    <= 1
  );

alter table public.reports
  add constraint reports_target_coerente check (
    case target_tipo
      when 'annuncio' then target_profile_id is null and target_message_id is null
        and target_conversation_id is null and target_review_id is null
        and target_post_id is null and target_risposta_id is null
      when 'profilo' then target_listing_id is null and target_message_id is null
        and target_conversation_id is null and target_review_id is null
        and target_post_id is null and target_risposta_id is null
      when 'messaggio' then target_listing_id is null and target_profile_id is null
        and target_conversation_id is null and target_review_id is null
        and target_post_id is null and target_risposta_id is null
      when 'conversazione' then target_listing_id is null and target_profile_id is null
        and target_message_id is null and target_review_id is null
        and target_post_id is null and target_risposta_id is null
      when 'recensione' then target_listing_id is null and target_profile_id is null
        and target_message_id is null and target_conversation_id is null
        and target_post_id is null and target_risposta_id is null
      when 'post' then target_listing_id is null and target_profile_id is null
        and target_message_id is null and target_conversation_id is null
        and target_review_id is null and target_risposta_id is null
      when 'commento' then target_listing_id is null and target_profile_id is null
        and target_message_id is null and target_conversation_id is null
        and target_review_id is null and target_post_id is null
      -- Il ramo che la 9a non aveva. Senza, un valore aggiunto domani
      -- all'enum tornerebbe NULL e il CHECK passerebbe in silenzio - che e
      -- esattamente il buco che questa migrazione sta chiudendo. Con `else
      -- false`, chi aggiunge l'ottavo valore trova un errore a tempo di
      -- inserimento invece di un vincolo che ha smesso di parlare.
      else false
    end
  );

-- ---------------------------------------------------------------------------
-- private.moderazione_bersaglio - due colonne in piu
-- ---------------------------------------------------------------------------
-- Il tipo del parametro e `public.reports`, cioe il rowtype della tabella:
-- l'ALTER TABLE qui sopra lo ha gia allargato, quindi la funzione vede le due
-- colonne nuove. Senza questa ridefinizione, l'id del bersaglio di una pratica
-- su un post sarebbe NULL in audit_log e nella coda del moderatore.

create or replace function private.moderazione_bersaglio(p_report public.reports)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    p_report.target_listing_id, p_report.target_profile_id,
    p_report.target_message_id, p_report.target_conversation_id,
    p_report.target_review_id, p_report.target_post_id,
    p_report.target_risposta_id
  );
$$;

-- ---------------------------------------------------------------------------
-- public.segnalazione_invia - due bersagli in piu
-- ---------------------------------------------------------------------------
-- Ridefinita per intero perche plpgsql non ha un modo di aggiungere un ramo a
-- un `case` esistente. La firma e identica, quindi e una sostituzione e non un
-- sovraccarico, e i GRANT della 9a restano.
--
-- Tre punti cambiano, e nient'altro:
--   [a] `v_esiste` ha due rami nuovi;
--   [b] l'INSERT valorizza le due colonne nuove;
--   [c] il `coalesce` che riconosce il doppione le comprende.
-- Rate limit, derivazione della priorita, elenco chiuso dei motivi, codice
-- progressivo e voce di storia sono INVARIATI: sono della 9a e non c'e ragione
-- di rimetterci mano dentro una PR sui club.
--
-- CIO CHE DELIBERATAMENTE NON CAMBIA: il blocco «Non ci si segnala da soli»
-- resta sul solo `profilo`. Segnalare un proprio post non e rumore come lo e
-- segnalare il proprio profilo - e una richiesta di rimozione, ed e l'unica
-- che un autore ha, perche la 12b non gli da una porta per cancellare cio che
-- ha scritto. Bloccarlo toglierebbe l'unica uscita senza chiudere nessun buco.

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

comment on function public.segnalazione_invia is
  'Unica porta di ingresso di una segnalazione. Identita da auth.uid(), '
  'priorita derivata sul server, motivo vincolato all''elenco chiuso, '
  'bersaglio verificato esistente, rate limit 10/ora per utente. Sette '
  'bersagli dalla 12c: `post` e `commento` si risolvono su club_posts e '
  'club_post_risposte.';

-- ---------------------------------------------------------------------------
-- La coda del moderatore vede i due bersagli nuovi
-- ---------------------------------------------------------------------------
-- Solo l'espressione di `target_id` cambia: nome, tipo e ordine delle colonne
-- restano identici, che e la condizione perche `create or replace view` non
-- rifiuti. Senza questa riga la coda mostrerebbe una segnalazione su un post
-- con target_id nullo, cioe un bersaglio che il pannello non sa aprire.

create or replace view public.moderation_report_queue
with (security_invoker = off, security_barrier = true) as
  select
    r.id,
    r.codice,
    r.target_tipo,
    r.target_label,
    coalesce(
      r.target_listing_id, r.target_profile_id, r.target_message_id,
      r.target_conversation_id, r.target_review_id,
      r.target_post_id, r.target_risposta_id
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

-- ---------------------------------------------------------------------------
-- private.moderazione_contenuto_club_transizione - il motore di rimozione
-- ---------------------------------------------------------------------------
--
-- Speculare a private.moderazione_annuncio_transizione della 9b, e per gli
-- stessi motivi: l'effetto sul bersaglio sta in un motore privato, la pratica
-- e l'audit restano alle azioni pubbliche.
--
-- LA RIMOZIONE E LOGICA. Non c'e nessuna DELETE, ne qui ne altrove: una
-- segnalazione deve sopravvivere alla rimozione di cio che segnala. Le tre
-- colonne che scrive - rimosso_at, rimosso_da, rimosso_motivo - sono fuori da
-- ogni grant client, quindi questa funzione e la loro unica porta, che e la
-- terza regola di esposizione applicata alla lettera.
--
-- PERCHE has_role() NON COMPARE. Verificato prima di scrivere, non dedotto:
-- public.has_role e SECURITY INVOKER dalla 20260729235500 e legge
-- public.user_roles, su cui `authenticated` non ha SELECT dalla 6d-1. Dentro
-- una policy o una funzione SECURITY INVOKER darebbe `permission denied for
-- table user_roles` a chiunque, admin compreso - lo stesso difetto che
-- wines_insert_staff porta da allora e che la 12a ha ritrovato su `clubs`. Il
-- ruolo qui lo verifica private.moderazione_attore() della 9b, che e SECURITY
-- DEFINER e scrive il predicato per esteso; questa funzione e chiamata dopo di
-- essa e non lo ricontrolla.
--
-- LO SCOPE E `club`, E QUESTA E LA PRIMA RIGA CHE LO USA. La 9a creo
-- public.mod_scope con due valori annotando che nessuna riga poteva ancora
-- nascere con 'club' perche i club non avevano schema. Da qui in poi puo.

create or replace function private.moderazione_contenuto_club_transizione(
  p_attore uuid,
  p_report public.reports,
  p_rimuovi boolean,
  p_azione public.mod_action,
  p_motivazione text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
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

comment on function private.moderazione_contenuto_club_transizione is
  'Rimuove o ripristina un post o una risposta segnalati, in logica e mai con '
  'una DELETE, e registra la riga di audit con scope `club`. Unica porta delle '
  'tre colonne rimosso_*. Non verifica il ruolo: lo ha gia fatto '
  'private.moderazione_attore() dentro l''azione che la chiama.';

-- ---------------------------------------------------------------------------
-- Le due azioni della 9b che ora sanno cosa fare di un post
-- ---------------------------------------------------------------------------
-- NON sono due RPC nuove. `moderazione_rimozione` e `moderazione_ripristino`
-- gia scelgono l'effetto sul target_tipo della pratica, e oggi per `post` e
-- `commento` cadrebbero nel ramo `else`: scriverebbero l'audit SENZA RIMUOVERE
-- NIENTE, cioe un registro che dice che il contenuto e stato rimosso mentre e
-- ancora li. E' la stessa forma con cui la 9c allargo il perimetro, e la
-- ragione per cui non si aggiungono porte «rimuovi questo post» per bersaglio:
-- non avrebbero chiamante - il pannello di moderazione della Fase 9 non e mai
-- stato esercitato sul progetto reale - e la 12a ha gia fissato che una porta
-- di scrittura senza chiamante e superficie in piu.
--
-- Le firme non cambiano, quindi i GRANT della 9b restano.

create or replace function public.moderazione_rimozione(
  p_report_id uuid,
  p_motivazione text,
  p_nota_interna text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
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

create or replace function public.moderazione_ripristino(
  p_report_id uuid,
  p_motivazione text,
  p_nota_interna text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
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

-- ---------------------------------------------------------------------------
-- Privilegi
-- ---------------------------------------------------------------------------
-- Il motore e privato come i due della 9b. Le due azioni pubbliche mantengono
-- i GRANT che la 9b ha gia dato ad `authenticated`: `create or replace` non li
-- tocca, e ripeterli qui darebbe l'idea che questa migrazione allarghi un
-- privilegio quando non lo fa.

revoke execute on function
  private.moderazione_contenuto_club_transizione(
    uuid, public.reports, boolean, public.mod_action, text
  )
  from public, anon, authenticated;

notify pgrst, 'reload schema';
