-- ===========================================================================
-- PROPOSTA DI MIGRAZIONE - NON ESEGUIRE SENZA AUTORIZZAZIONE ESPLICITA
-- Modifica di un annuncio gia' pubblicato: listings_update_own + guardia 9b
-- ===========================================================================
--
-- QUESTO FILE NON E' STATO ESEGUITO DA NESSUNA PARTE e non deve esserlo finche
-- non arriva un'autorizzazione esplicita in sessione.
--
-- DOVE STA, E PERCHE' NON IN supabase/migrations/.
-- Perche' li' il merge e' il gate di deploy (decisione 7.10) e la PR lo
-- applicherebbe da sola al progetto reale, che e' esattamente cio' che
-- l'autorizzazione separata deve poter fermare. In piu' Supabase apre un ramo
-- di preview per ogni PR e vi esegue le migrazioni all'apertura: sotto
-- migrations/ questo testo girerebbe su un database prima ancora della
-- revisione. Stessa cartella e stessa ragione della proposta di fixture della
-- 12a e di quella sul consenso ai termini.
--
-- NON E' UN'AGGIUNTA ADDITIVA NEUTRA. E' l'allentamento di un controllo di
-- sicurezza gia' in produzione: oggi un annuncio pubblico non e' modificabile,
-- domani lo sarebbe. Va letto sapendo cosa apre, non solo cosa risolve.
--
-- ---------------------------------------------------------------------------
-- 1. LO STATO DI FATTO, MISURATO SUL PROGETTO REALE IL 19 AGOSTO 2026
-- ---------------------------------------------------------------------------
--
-- pg_policy su public.listings restituisce TRE policy e non quattro:
--
--   listings_insert_own   (a)  seller_id = auth.uid() and la bottiglia e' sua
--   listings_select_own   (r)  seller_id = auth.uid()          -- senza stato
--   listings_update_own   (w)  seller_id = auth.uid()
--                              and stato in ('bozza','modifiche_richieste')
--
-- `listings_select_pubblici` NON esiste piu' sul progetto reale: la lettura
-- pubblica passa dalla vista `public_listings` (security_invoker = off), come
-- vuole la regola di esposizione della 6d-1. E' una correzione a una premessa
-- diffusa, e cambia il ragionamento: la sospensione toglie la riga dalla vista,
-- non da una policy.
--
-- ---------------------------------------------------------------------------
-- 2. COSA CAMBIA, E COSA DELIBERATAMENTE NO
-- ---------------------------------------------------------------------------
--
-- Cambia un solo elenco: gli stati da cui l'UPDATE parte. Si aggiunge
-- 'attivo', e NON si aggiungono gli altri sei. Le esclusioni sono la parte
-- che conta:
--
--   riservato   - un acquisto e' in corso (Fase 7). Cambiare prezzo o
--                 condizione sotto i piedi di chi sta comprando e' la
--                 decisione di dominio che la 6b si era rifiutata di prendere,
--                 e questa proposta non la prende al posto suo.
--   in_revisione - la moderazione la sta guardando. Modificarla mentre viene
--                 esaminata vuol dire far approvare un testo diverso da quello
--                 letto.
--   sospeso / scaduto / venduto / rifiutato - stati terminali. Un annuncio
--                 terminale non e' una bozza a cui tornare: e' un fatto
--                 avvenuto, e riscriverne il prezzo dopo riscriverebbe la
--                 storia di cosa e' stato offerto.
--
-- NON cambia il GRANT UPDATE per colonna, e NON deve. Restano fuori dalla
-- scrittura del client, come oggi:
--
--   stato, published_at, expires_at, seller_id, stato_motivo,
--   stato_aggiornato_da, stato_aggiornato_at, reserved_by, reserved_until,
--   imballaggio_codice
--
-- Il client puo' scrivere soltanto le otto colonne di contenuto gia' concesse
-- dalla 6a: prezzo_cents, prezzo_mercato_cents, condizione, conservazione,
-- storia, degustazione, immagini, tag.
--
-- E' QUESTO che rende sicuro lasciare `with check` come sta. Un `with check`
-- che non nomina lo stato sembra permettere a un venditore di spostare la riga
-- a uno stato a piacere; non lo permette, perche' `stato` non e' nel GRANT e
-- il tentativo si ferma sul permesso di colonna prima ancora di arrivare alla
-- RLS. La difesa e' il GRANT, non la policy - ed e' per questo che il GRANT
-- non si tocca.
--
-- ---------------------------------------------------------------------------
-- 3. LA PARTE CHE NON E' NELLA RICHIESTA E SENZA LA QUALE LA PROPOSTA E' UN BUCO
-- ---------------------------------------------------------------------------
--
-- MISURATO, NON DEDOTTO: il trigger della guardia 9b su public.listings e'
--
--   CREATE TRIGGER listings_scrittura_social_guard
--     BEFORE INSERT ON public.listings          -- <-- INSERT soltanto
--     FOR EACH ROW EXECUTE FUNCTION private.scrittura_social_guard()
--
-- Su `messages` e sulle tre tabelle dei club la stessa guardia copre anche
-- l'UPDATE; su `listings` no. Finora e' stato innocuo per una ragione sola:
-- `listings_update_own` si fermava a 'bozza' e 'modifiche_richieste', cioe' a
-- righe che nessun estraneo vede. Un utente sospeso al primo livello poteva
-- modificare le proprie bozze, e non se ne accorgeva nessuno perche' non
-- erano pubbliche.
--
-- Aggiungendo 'attivo' quella innocuita' finisce. Un utente sospeso al primo
-- livello - quello che per la decisione 7.6b blocca "le sole scritture social,
-- annunci e messaggi" - potrebbe riscrivere prezzo, storia e fotografie di un
-- annuncio PUBBLICO. Sarebbe una scrittura social su una superficie pubblica
-- fatta da chi e' stato sospeso proprio per impedirgliela: la sospensione
-- perderebbe pezzo senza che nessuna decisione l'abbia deciso.
--
-- Per questo la proposta contiene DUE statement e non uno. Chi autorizza solo
-- il primo autorizza un buco nella 9b.
--
-- Il corpo di `private.scrittura_social_guard()` NON va toccato: legge la riga
-- da `to_jsonb(new)` e ricava l'attore da `seller_id`, che su UPDATE esiste
-- identico. Serve solo allargare il momento in cui scatta.
--
-- ---------------------------------------------------------------------------
-- 4. COSA RESTA APERTO DOPO L'APPLICAZIONE, E VA SAPUTO PRIMA
-- ---------------------------------------------------------------------------
--
-- (a) UN COMPRATORE PUO' VEDERE UN PREZZO E TROVARNE UN ALTRO AL CHECKOUT.
--     Fra il caricamento della scheda e `order_checkout_reserve` il venditore
--     puo' cambiare il prezzo. L'ordine gia' creato e' immune - `orders.
--     prezzo_cents` e' una colonna materializzata (is_generated = NEVER), non
--     una lettura dell'annuncio, verificato sul progetto reale - quindi
--     nessun ordine esistente si muove. Ma un ordine che sta nascendo prende
--     il prezzo del momento in cui nasce. Oggi non muove denaro
--     (PAYMENTS_ENABLED = false); prima di accendere i pagamenti questa e' una
--     domanda da chiudere, non un dettaglio.
--
-- (b) NESSUNA TRACCIA DI COSA E' CAMBIATO. Un annuncio modificato dopo la
--     pubblicazione non lascia traccia di cosa fosse prima: `audit_log` e'
--     della moderazione (7.3) e non registra le modifiche del venditore. Chi
--     ha guardato l'annuncio ieri non ha modo di sapere che oggi dice altro.
--     Non e' un difetto di questa proposta - e' cio' che la restrizione
--     odierna evitava dall'inizio, e che togliendola si accetta.
--
-- (c) LA MODERAZIONE NON VIENE RIAPERTA. Un annuncio gia' approvato che viene
--     riscritto resta approvato: non esiste un ritorno automatico a
--     'in_revisione'. Se questo sia accettabile e' una domanda per la
--     moderazione (Fase 9), non per questo file.
--
-- Nessuno dei tre e' risolto qui, e nessuno dei tre e' un motivo per non
-- applicare: sono le conseguenze che l'autorizzazione si assume.
--
-- ---------------------------------------------------------------------------
-- 5. IL TESTO ESATTO
-- ---------------------------------------------------------------------------
--
-- Se autorizzato, questo diventa un file nuovo sotto supabase/migrations/ con
-- timestamp piu' recente dell'ultimo applicato (l'ultimo e'
-- 20260818090000_phase_8_fix_pre_request_read_only). Nessuna migrazione
-- esistente viene modificata: sono tutte congelate.

begin;

-- --- 5.1 - L'allentamento richiesto -----------------------------------------

drop policy if exists "listings_update_own" on public.listings;

-- Modificabile finche' e' una bozza, e' tornata al venditore per correzioni,
-- oppure e' pubblica. Restano fuori 'riservato' (un acquisto e' in corso),
-- 'in_revisione' (la moderazione la sta leggendo) e i quattro stati terminali.
-- Le colonne di stato e autorita' non sono nel GRANT UPDATE del client: e' li'
-- che si ferma un venditore che provasse a cambiarsi lo stato, non qui.
create policy "listings_update_own"
  on public.listings for update
  to authenticated
  using (
    seller_id = (select auth.uid())
    and stato in ('bozza', 'modifiche_richieste', 'attivo')
  )
  with check (seller_id = (select auth.uid()));

-- --- 5.2 - La guardia 9b, senza la quale la 5.1 apre un buco -----------------

-- La guardia esisteva solo BEFORE INSERT. Con la 5.1 un utente sospeso al
-- primo livello potrebbe riscrivere un annuncio pubblico, che e' esattamente
-- la scrittura social che la sospensione gli toglie. La funzione non cambia:
-- ricava l'attore da `seller_id` via to_jsonb(new), che su UPDATE c'e' uguale.
drop trigger if exists listings_scrittura_social_guard on public.listings;

create trigger listings_scrittura_social_guard
  before insert or update on public.listings
  for each row execute function private.scrittura_social_guard();

commit;

-- ---------------------------------------------------------------------------
-- 6. COME SI VERIFICA DOPO L'APPLICAZIONE
-- ---------------------------------------------------------------------------
--
-- Sola lettura, nessuna scrittura, eseguibile subito dopo:
--
--   select polname, pg_get_expr(polqual, polrelid)
--   from pg_policy where polrelid = 'public.listings'::regclass
--     and polname = 'listings_update_own';
--   -- atteso: ... stato = ANY (ARRAY['bozza','modifiche_richieste','attivo'])
--
--   select tgname, pg_get_triggerdef(oid) from pg_trigger
--   where tgrelid = 'public.listings'::regclass
--     and tgname = 'listings_scrittura_social_guard';
--   -- atteso: BEFORE INSERT OR UPDATE
--
--   select grantee, string_agg(column_name, ', ' order by column_name)
--   from information_schema.column_privileges
--   where table_schema='public' and table_name='listings'
--     and privilege_type='UPDATE' and grantee='authenticated'
--   group by grantee;
--   -- atteso INVARIATO, otto colonne: condizione, conservazione, degustazione,
--   --   immagini, prezzo_cents, prezzo_mercato_cents, storia, tag
--   -- Se qui compare `stato`, qualcosa e' andato storto e va fermato.
--
-- La griglia con i casi di comportamento (proprio vs altrui, colonne di
-- autorita', utente sospeso) e' in supabase/tests/, e come ogni griglia di
-- questo repository la sua esecuzione sul progetto reale e' un'autorizzazione
-- separata, per griglia. Questa scrive: non e' della classe della
-- 8_fix_pre_request_read_only, che non scrive nulla.
