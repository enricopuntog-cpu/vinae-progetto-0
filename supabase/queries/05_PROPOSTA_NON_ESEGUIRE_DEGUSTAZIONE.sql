-- ============================================================================
-- PROPOSTA - NON ESEGUIRE SENZA AUTORIZZAZIONE ESPLICITA IN SESSIONE
-- ============================================================================
--
-- Nota di degustazione e data di apertura su public.bottle_units.
--
-- PERCHE' STA QUI E NON SOTTO supabase/migrations/
--   Sotto migrations/ il merge la applicherebbe da se' al progetto reale
--   (decisione 7.10: il merge e' il gate di deploy, non esiste un comando di
--   apply separato) E il ramo di anteprima Supabase la eseguirebbe all'apertura
--   della PR, cioe' PRIMA della revisione. Una proposta cambia cartella quando
--   la revisione e' avvenuta, non prima. E' la stessa collocazione, e la stessa
--   ragione, della proposta di fixture della 12a (02_...) e di quella sul
--   consenso ai termini (03_...). La 04_ e' quella del Gruppo 1, che ha cambiato
--   cartella il 18 agosto 2026 quando l'autorizzazione e' arrivata.
--
-- ----------------------------------------------------------------------------
-- IL DIFETTO CHE CHIUDE, misurato sul progetto reale il 18 agosto 2026
-- ----------------------------------------------------------------------------
--
-- (1) Il parametro `p_nota` di public.bottiglia_apri NON finisce in una colonna
--     di degustazione: SOVRASCRIVE `note_personali`. Corpo vivo, righe 51-57:
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
-- (2) NON esiste una data di apertura. `bottle_units` ha `apertura_pianificata`,
--     che e' una data PROGRAMMATA, di tipo `date`, scrivibile dal client e nulla
--     su 10 bottiglie su 11; e `updated_at`, che si muove a ogni modifica e non
--     testimonia niente. Percio' la pagina di degustazione oggi puo' solo dire
--     «Bottiglia degustata», o mostrare la data programmata dichiarando che e'
--     quella - mai spacciare un giorno per il giorno in cui e' stata bevuta.
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
--   * L'UPDATE invece NON e' di tabella: e' per colonna (visibilita,
--     note_personali, prezzo_visibilita, apertura_pianificata, i cinque
--     override). Quindi una colonna nuova nasce NON scrivibile dal client, ed e'
--     esattamente cio' che la terza regola di esposizione pretende per una
--     colonna con una regola di dominio dietro: unica porta una funzione
--     SECURITY DEFINER. Qui la porta e' bottiglia_apri. QUESTO FILE NON DEVE
--     AGGIUNGERE NESSUN `grant update`: sarebbe il difetto della 9b su profiles,
--     dove un grant di tabella troppo largo lasciava all'utente sospeso di
--     togliersi la sospensione da solo.
--   * `anon` non ha NESSUN grant su bottle_units, quindi non c'e' superficie
--     pubblica da valutare.
--   * NESSUN TRAVASO DEI DATI SERVE, ed e' misurato non assunto: le bottiglie
--     non cancellate sono 11, TUTTE in stato `chiusa`, e ZERO hanno
--     `note_personali` valorizzata. bottiglia_apri non e' mai stata eseguita
--     davvero in produzione. Se un giorno lo fosse prima di questa proposta,
--     rileggere questo conteggio PRIMA di applicarla: con righe gia' aperte
--     servirebbe decidere se travasare note_personali in degustazione_nota, e
--     quel travaso non e' scritto qui perche' oggi non ha nessuna riga su cui
--     agire.
--
-- ----------------------------------------------------------------------------
-- COSA CAMBIA NEL COMPORTAMENTO, da approvare esplicitamente
-- ----------------------------------------------------------------------------
--
--   bottiglia_apri SMETTE di scrivere in `note_personali`. E' il punto della
--   proposta, non un effetto collaterale: chi la autorizza sta autorizzando
--   anche questo. Dopo, la nota personale della bottiglia e la nota di
--   degustazione sono due cose distinte, e aprire una bottiglia non tocca piu'
--   la prima. Le due colonne stanno insieme e non si dividono - `degustazione_at`
--   senza `degustazione_nota` darebbe una pagina che sa quando ma non cosa, e il
--   contrario una pagina che non sa dire «il».
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
--    dell'annuncio - resta identico riga per riga, `for update` compreso.
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

  -- L'UNICA differenza rispetto alla versione in produzione: la nota va nella
  -- sua colonna e non sopra note_personali, e l'apertura lascia una data.
  -- `degustazione_at` si scrive sempre, anche senza nota: e' il momento in cui
  -- e' stata aperta, non un attributo del commento.
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
  'in uno dei cinque stati non terminali. Dal 18 agosto 2026 la nota finisce in '
  'degustazione_nota e non sovrascrive piu'' note_personali, e l''apertura registra '
  'degustazione_at.';


-- ============================================================================
-- VERIFICHE DA ESEGUIRE DOPO, se e quando questa proposta viene autorizzata
-- ============================================================================
--
-- (a) Le due colonne esistono e NON sono scrivibili da authenticated.
--     Atteso: due righe, entrambe con privilegi 'SELECT' e mai 'UPDATE'.
--
--     select c.column_name,
--            coalesce((select string_agg(distinct cp.privilege_type, '/')
--                      from information_schema.column_privileges cp
--                      where cp.table_schema = 'public'
--                        and cp.table_name = 'bottle_units'
--                        and cp.column_name = c.column_name
--                        and cp.grantee = 'authenticated'), '-') as privilegi
--     from information_schema.columns c
--     where c.table_schema = 'public' and c.table_name = 'bottle_units'
--       and c.column_name in ('degustazione_nota', 'degustazione_at');
--
-- (b) Il corpo della funzione e' davvero cambiato - la lezione della #52 e'
--     che una riga di ledger non prova che l'oggetto sia cambiato.
--     Atteso: contiene 'degustazione_at' e NON contiene 'note_personali'.
--
--     select pg_get_functiondef(p.oid) ilike '%degustazione_at%'  as scrive_data,
--            pg_get_functiondef(p.oid) ilike '%note_personali%'   as tocca_ancora_le_note
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--     where n.nspname = 'public' and p.prokind = 'f' and p.proname = 'bottiglia_apri';
--
-- (c) IL PERCORSO DEL CLIENT VA PROVATO DAL CLIENT. Una sessione Postgres
--     diretta non passa da PostgREST, quindi non incontra ne' l'hook di
--     pre-richiesta ne' la transazione di sola lettura: se questa funzione
--     rispondesse 405 per la volatilita', qui sarebbe invisibile. E' la classe
--     di difetto della #52, ed e' la stessa che il Gruppo 1 ha lasciato aperta.
--     bottiglia_apri e' `volatile`, quindi in POST non dovrebbe incontrarla -
--     ma «non dovrebbe» non e' una misura.
-- ============================================================================
