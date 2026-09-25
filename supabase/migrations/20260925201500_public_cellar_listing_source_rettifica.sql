-- Rettifica di un fatto affermato dalla 20260925191500 e smentito dal gate.
--
-- CHE COSA CORREGGE. La 20260925191500 sostituisce il corpo di
-- `private.cantina_pubblica` per derivare l'annuncio da `public.public_listings`,
-- e quella sostituzione resta giusta: «annuncio pubblicamente visibile» deve
-- avere una definizione sola. Sbagliata era la *motivazione* scritta nel suo
-- commento di testa, che diceva:
--
--   «bottle_units.stato non ha alcun trigger che lo leghi a listings, quindi
--    qualunque scrittore privilegiato produce lo stato incoerente senza
--    incontrare resistenza.»
--
-- Non e vero, e il trigger esiste da due mesi:
-- `public.bottle_units_preserva_annuncio_non_terminale` (20260729234500:261),
-- `before update of stato, deleted_at, ceduta_at`, rifiuta di aprire, cancellare
-- o cedere una bottiglia che ha addosso un annuncio in `bozza`, `in_revisione`,
-- `modifiche_richieste`, `attivo` o `riservato`. E `security invoker` senza
-- privilegio speciale: vale anche per `postgres`. Insieme a
-- `listings_bottiglia_idonea` (20260729234500:218), che difende la direzione
-- opposta, l'invariante e chiuso in tutte e due i sensi. La griglia 12i
-- costruiva la bottiglia aperta con annuncio attivo con un UPDATE diretto,
-- convinta che nulla lo impedisse: il gate `Supabase DB regression` l'ha
-- rifiutata con quel P0001, ed e cosi che l'errore e venuto fuori.
--
-- PERCHE LA CORREZIONE DELLA VISTA RESTA NECESSARIA LO STESSO. Due ragioni, e
-- nessuna delle due dipendeva dall'affermazione sbagliata.
--
-- La prima: `bu.stato = 'chiusa'` mancava davvero. Restava una seconda
-- definizione di annuncio pubblico, piu permissiva di quella canonica, sulla
-- superficie pubblica. Due definizioni della stessa cosa divergono; questa era
-- gia divergente il giorno in cui e stata scritta.
--
-- La seconda: lo stato incoerente e raggiungibile, solo per una via diversa e
-- meno rassicurante di quella che avevo scritto. I trigger non girano quando
-- `session_replication_role = replica`, cioe durante ogni `pg_restore`, ogni
-- `supabase db reset` da dump e ogni replica logica — e questo repository i
-- ripristini li fa davvero (runbook B2, restore isolato del 22 settembre 2026).
-- Un ripristino non riverifica gli invarianti: riporta i dati com'erano. Una
-- manutenzione che disattiva un trigger per andare piu veloce fa lo stesso. Il
-- punto quindi non e se il database sappia impedire quello stato — lo impedisce
-- — ma che cosa mostri quando se lo ritrova davanti dopo averlo riletto da un
-- dump. La risposta deve essere: nessun annuncio.
--
-- La griglia 12i ora lo riproduce per quella via — `set local
-- session_replication_role = replica` intorno al solo UPDATE — e il caso 21
-- prova i due rifiuti a trigger in vigore, cosi la reale raggiungibilita e
-- misurata invece che affermata.
--
-- ADDITIVA E SOLO DICHIARATIVA. La 20260925191500 non viene toccata: e stata
-- pubblicata, quindi e congelata, commento di testa compreso. Qui si riscrive
-- il solo `comment on view`, che e l'unico posto dove quella spiegazione vive
-- anche nel database e non solo in un file. Nessuna colonna, nessun filtro,
-- nessun privilegio, nessuna policy cambiano: `pg_get_viewdef` prima e dopo
-- questa migrazione e identico, e il blocco finale lo verifica.

comment on view private.cantina_pubblica is
  'Proiezione pubblicabile della Cantina: sole unità dichiarate cantina_pubblica, '
  'ancora possedute e non consumate, di un proprietario visibile. Il collegamento '
  '«in vendita» deriva da public.public_listings — unica definizione di annuncio '
  'pubblico, dalla 20260925191500 — quindi una bottiglia aperta con un annuncio '
  'rimasto attivo non mostra alcun annuncio. Quello stato i trigger lo vietano in '
  'entrambe le direzioni (bottle_units_preserva_annuncio_non_terminale e '
  'listings_bottiglia_idonea, 20260729234500); entra solo da un caricamento a '
  'trigger spenti, cioè da un ripristino da dump, ed è lì che questa derivazione '
  'serve. Nessun privilegio per anon/authenticated: la sola porta è '
  'public.cantina_pubblica_profilo(uuid, int, int).';

-- Che questa migrazione non abbia cambiato nient'altro che una frase.
do $$
declare
  v_def text := pg_get_viewdef('private.cantina_pubblica'::regclass);
begin
  if v_def !~ 'public_listings' then
    raise exception
      'Invariante: private.cantina_pubblica deve derivare l''annuncio da public.public_listings.';
  end if;

  if v_def ~* 'l\.stato' or v_def ~* 'expires_at' then
    raise exception
      'Invariante: le condizioni di pubblicazione dell''annuncio vivono solo in public.public_listings.';
  end if;

  -- Letto da `relacl` e non da `information_schema`: quest'ultimo filtra per
  -- appartenenza al ruolo di chi interroga, quindi un elenco vuoto non
  -- proverebbe l'assenza del privilegio, solo l'assenza di visibilita.
  if exists (
    select 1
    from pg_catalog.pg_class c
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace,
      lateral aclexplode(c.relacl) a
    where n.nspname = 'private'
      and c.relname = 'cantina_pubblica'
      and (a.grantee = 0 or pg_catalog.pg_get_userbyid(a.grantee) in ('anon', 'authenticated'))
  ) then
    raise exception
      'Invariante: private.cantina_pubblica non deve avere privilegi per anon/authenticated.';
  end if;
end $$;
