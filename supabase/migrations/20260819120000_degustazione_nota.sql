-- ============================================================================
-- Nota di degustazione e data di apertura su public.bottle_units.
-- ============================================================================
--
-- AUTORIZZAZIONE. Approvata per nome dalla sessione di coordinamento del
-- 18 agosto 2026 COME BLOCCO UNICO: le due colonne e il cambio di comportamento
-- di `bottiglia_apri` non si separano. Il file e' nato come proposta in
-- `supabase/queries/05_PROPOSTA_NON_ESEGUIRE_DEGUSTAZIONE.sql` e ha cambiato
-- cartella quando la revisione e' avvenuta, non prima - sotto
-- `supabase/migrations/` il merge lo applica da se' (decisione 7.10) E il ramo di
-- anteprima lo eseguirebbe all'apertura della PR, cioe' prima che qualcuno lo
-- legga. E' la stessa collocazione, e la stessa ragione, della proposta di
-- fixture della 12a e di quella sul consenso ai termini, che restano in
-- `supabase/queries/` perche' nessuno le ha ancora autorizzate.
--
-- SUL TIMESTAMP DEL NOME. `20260819120000` deve solo ordinarsi dopo
-- `20260819090000`, che e' gia' applicata e quindi congelata. Il timestamp di
-- una migrazione e' un identificatore ordinale, non una data: quello della
-- 20260819090000 fu scritto il 18 agosto e resta com'e' per la stessa ragione.
--
-- ----------------------------------------------------------------------------
-- IL DIFETTO CHE CHIUDE, misurato ESEGUENDO e non leggendo
-- ----------------------------------------------------------------------------
--
-- (1) Il parametro `p_nota` di public.bottiglia_apri NON finiva in una colonna
--     di degustazione: SOVRASCRIVEVA `note_personali`. Corpo vivo prima di
--     questo file:
--
--         update public.bottle_units
--         set stato = 'aperta',
--             note_personali = case
--               when p_nota is null or trim(p_nota) = '' then note_personali
--               else p_nota
--             end
--         where id = p_bottle_unit_id;
--
--     `note_personali` e' la nota generica della bottiglia in cantina, scrivibile
--     dal client e usata per tutt'altro ("comprata in cantina dal produttore",
--     "regalo di Marco"). Registrare li' la degustazione significa CANCELLARE
--     quello che c'era, senza dirlo a nessuno. E' una perdita di dati, non una
--     approssimazione.
--
--     LA PROVA E' UN VALORE, non una lettura del corpo. Il caso [04] della
--     griglia `supabase/tests/degustazione_nota.sql`, eseguito sul branch di
--     anteprima PRIMA di questo file, si aspettava 'Regalo di Marco' e ha visto
--     'Sorprendente, ancora giovanissimo.'.
--
--     E il caso [10b], eseguito nella stessa corsa, dice qualcosa che nessuno
--     aveva previsto e che cambia la valutazione del rischio: aprire SENZA nota
--     non sovrascrive niente, perche' il `case` cade sul ramo che rilegge se
--     stesso. IL DIFETTO MORDE SOLO QUANDO UNA NOTA C'E' - cioe' esattamente
--     quando la schermata di degustazione della PR #56 invita a scriverne una.
--
-- (2) NON esisteva una data di apertura. `bottle_units` ha `apertura_pianificata`,
--     che e' una data PROGRAMMATA, di tipo `date` e scrivibile dal client; e
--     `updated_at`, che si muove a ogni modifica e non testimonia niente. Percio'
--     la pagina di degustazione poteva solo dire «Bottiglia degustata», o
--     mostrare la data programmata dichiarando che e' quella - mai spacciare un
--     giorno per il giorno in cui la bottiglia e' stata bevuta.
--
-- ----------------------------------------------------------------------------
-- PERCHE' E' ADDITIVA DAVVERO, e non solo di nome
-- ----------------------------------------------------------------------------
--
--   * `authenticated` ha su bottle_units un GRANT di TABELLA in sola lettura
--     (`SELECT`), quindi le due colonne nuove sono leggibili SUBITO e senza
--     nessun grant aggiuntivo. Verificato su information_schema.role_table_grants,
--     che elenca i soli grant di tabella - column_privileges non serviva, perche'
--     espande anche quelli di tabella su ogni colonna e non distingue i due casi.
--     E' il caso [01] della griglia, che passa in entrambe le corse: e' il
--     PRESUPPOSTO su cui poggia tutto il resto, non una misura di questo file.
--   * L'UPDATE invece NON e' di tabella: e' per colonna (visibilita,
--     note_personali, prezzo_visibilita, apertura_pianificata, i cinque
--     override). Quindi una colonna nuova nasce NON scrivibile dal client, ed e'
--     esattamente cio' che la terza regola di esposizione pretende per una
--     colonna con una regola di dominio dietro: unica porta una funzione
--     SECURITY DEFINER. Qui la porta e' bottiglia_apri. QUESTO FILE NON AGGIUNGE
--     NESSUN `grant update`, e un test del frontend glielo vieta: sarebbe il
--     difetto della 9b su profiles, dove un grant di tabella troppo largo
--     lasciava all'utente sospeso di togliersi la sospensione da solo. I casi
--     [08] e [09] della griglia lo verificano dal catalogo E provandolo.
--   * `anon` non ha NESSUN grant su bottle_units, quindi non c'e' superficie
--     pubblica da valutare.
--   * NESSUN TRAVASO DEI DATI SERVE, ed e' misurato non assunto: al 18 agosto
--     2026 le bottiglie non cancellate in produzione sono 11, TUTTE in stato
--     `chiusa`, e ZERO hanno `note_personali` valorizzata. bottiglia_apri non e'
--     mai stata eseguita davvero in produzione. Se un giorno delle righe gia'
--     aperte esistessero, rileggere questo conteggio prima di fidarsi: con righe
--     aperte servirebbe decidere se travasare note_personali in
--     degustazione_nota, e quel travaso non e' scritto qui perche' oggi non ha
--     nessuna riga su cui agire.
--
-- ----------------------------------------------------------------------------
-- COSA CAMBIA NEL COMPORTAMENTO
-- ----------------------------------------------------------------------------
--
--   bottiglia_apri SMETTE di scrivere in `note_personali`. E' il punto di questo
--   file, non un effetto collaterale, ed e' la meta' che l'autorizzazione ha
--   dovuto coprire esplicitamente. Dopo, la nota personale della bottiglia e la
--   nota di degustazione sono due cose distinte, e aprire una bottiglia non tocca
--   piu' la prima. Le due colonne stanno insieme e non si dividono:
--   `degustazione_at` senza `degustazione_nota` darebbe una pagina che sa quando
--   ma non cosa, e il contrario una pagina che non sa dire «il».
--
--   CONSEGUENZA SUL CLIENT, da fare nello stesso cambio e non dopo: la pagina di
--   degustazione leggeva il commento da `personalNotes`, cioe' dalla CONSEGUENZA
--   del difetto. Lasciata cosi', dopo questo file mostrerebbe la nota di cantina
--   («Regalo di Marco») spacciandola per il commento di degustazione. La PR #56
--   sposta quella lettura su `degustazione_nota` insieme a questo file.
--
-- ----------------------------------------------------------------------------
-- GRIGLIA: `supabase/tests/degustazione_nota.sql`, ESEGUITA
-- ----------------------------------------------------------------------------
--
--   Sul branch di anteprima Supabase della PR #56 (project_ref geikjaxpffplgvhblsdz),
--   nato dalle trentuno migrazioni di produzione, PostgreSQL 17.6. Due corse:
--
--     PRIMA di questo file  ->  8 PASSA /  7 FALLISCE
--     DOPO  questo file     -> 15 PASSA /  0 FALLISCE
--
--   La corsa "prima" non e' un preambolo: senza di essa una griglia tutta verde
--   non distinguerebbe una correzione da un file inerte.
--
--   CIO' CHE LA GRIGLIA NON PUO' VEDERE: una sessione Postgres diretta non passa
--   da PostgREST, quindi se `bottiglia_apri` rispondesse 405 per la volatilita'
--   - la classe di difetto della #52 - qui sarebbe invisibile. Il caso [14]
--   misura la volatilita', che e' la proprieta' da cui PostgREST decide, ma resta
--   un surrogato: il percorso del client va provato dal client.
--
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Le due colonne
-- ----------------------------------------------------------------------------

alter table public.bottle_units
  add column if not exists degustazione_nota text not null default '',
  add column if not exists degustazione_at   timestamptz;

comment on column public.bottle_units.degustazione_nota is
  'Nota di degustazione lasciata aprendo la bottiglia. Distinta da note_personali, '
  'che e'' la nota generica della bottiglia in cantina ed e'' scrivibile dal client: '
  'questa la scrive solo public.bottiglia_apri, che e'' SECURITY DEFINER, e non '
  'compare in nessun GRANT UPDATE per ruoli client.';

comment on column public.bottle_units.degustazione_at is
  'Quando la bottiglia e'' stata effettivamente aperta. Da non confondere con '
  'apertura_pianificata, che e'' la data PROGRAMMATA, di tipo date e scrivibile dal '
  'client. Nulla per le bottiglie aperte prima di questa migrazione: in produzione, '
  'al 18 agosto 2026, non ce n''era nessuna.';


-- ----------------------------------------------------------------------------
-- 2. bottiglia_apri smette di sovrascrivere note_personali
--
--    Il corpo e' quello vivo del 18 agosto 2026 con il solo `update` finale
--    cambiato. Tutto il resto - i controlli di sessione, proprieta', bottiglia
--    ceduta, stato gia' aperto o consumato, e il blocco sui cinque stati
--    dell'annuncio - resta identico riga per riga, `for update` compreso. I casi
--    [11], [12] e [13] della griglia sono li' per accorgersi se cosi' non fosse.
-- ----------------------------------------------------------------------------

create or replace function public.bottiglia_apri(
  p_bottle_unit_id uuid,
  p_nota text default null
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
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
$function$;

comment on function public.bottiglia_apri(uuid, text) is
  'Apre una bottiglia della propria cantina. Rifiuta se la bottiglia ha un annuncio '
  'in uno dei cinque stati non terminali. Dal 19 agosto 2026 la nota finisce in '
  'degustazione_nota e non sovrascrive piu'' note_personali, e l''apertura registra '
  'degustazione_at.';
