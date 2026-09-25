-- Cantina pubblica di un profilo — la porta di lettura che mancava.
--
-- CHE COSA ERA INERTE. `bottle_units.visibilita` esiste dalla 20260728193937 e
-- l'interfaccia la scrive da sempre, ma dal 29 luglio 2026 nessuno poteva
-- osservarne l'effetto: la 20260729230000 ha tolto `anon` da ogni privilegio
-- sulla tabella (:974) e ha eliminato entrambe le policy pubbliche
-- (`bottle_units_select_via_annuncio_pubblico`,
-- `bottle_units_select_cantina_pubblica`, :1065-1066); la 20260810152500 ha poi
-- eliminato la vista `public.public_bottle_units`. Restava la sola
-- `bottle_units_select_own`. Il valore `cantina_pubblica` era quindi una
-- dichiarazione di intenti senza conseguenze, ed è esattamente ciò che i
-- commenti della 20260810152500 chiamano «residuo inerte».
--
-- PERCHÉ NON SI RIPRISTINA LA VECCHIA SUPERFICIE. `public_bottle_units` era una
-- vista interrogabile: da PostgREST si poteva chiedere «tutte le bottiglie
-- pubbliche», ordinarle, filtrarle per regione, cioè costruire una directory di
-- che cosa possiede chi. La Cantina pubblica non è un catalogo: è una sezione
-- del profilo di una persona che si sta già guardando. Questa migrazione dà
-- quindi la stessa forma della fondazione profilo (20260825180000): la
-- proiezione vive in `private`, dove PostgREST non arriva, e l'unica porta è una
-- funzione che vuole un `uuid` e restituisce le bottiglie di quel solo profilo.
-- Non esiste una chiamata che ne elenchi due.
--
-- ADDITIVA. Nessuna policy viene allargata, nessun GRANT nuovo sulla tabella,
-- nessun bucket cambia visibilità, la 20260810152500 non viene toccata.

create schema if not exists private;

-- ---------------------------------------------------------------------------
-- La proiezione pubblicabile
-- ---------------------------------------------------------------------------
--
-- L'ALLOWLIST È QUESTA LISTA DI COLONNE, e non un `select *`. Ciò che resta
-- fuori non è stato dimenticato: `note_personali`, `apertura_pianificata`, gli
-- override di finestra e di apice, `degustazione_nota`, `prezzo_visibilita`,
-- `acquisition_cost_cents`, `acquisition_fonte`, `acquired_at`, `consumed_at`,
-- `bottle_units.immagini` sono dati privati del proprietario. Una colonna
-- aggiunta domani a `bottle_units` o a `wines` non entra qui per il solo fatto
-- di esistere.
--
-- NIENTE MOBILI DI CASA. Non c'è alcun join verso `cellar_environments`,
-- `cellar_modules` o `cellar_slots`: ciò che si rende pubblico è la bottiglia,
-- non dove è appoggiata. È la stessa frase che la 20260729180000 scrive nel
-- commento di `cellar_environments`, e qui viene rispettata invece di ripetuta.
--
-- LA VISIBILITÀ DEL PROPRIETARIO NON VIENE RISCRITTA. Il join con
-- `private.profili_pubblici` porta dentro, senza duplicarla, la regola a due
-- direzioni della 20260825180000: chi è `rimosso` non espone il profilo, e chi è
-- `rimosso` non legge quello degli altri. Se un giorno quella regola cambia,
-- cambia anche qui, perché è la stessa riga di SQL.
--
-- QUALI BOTTIGLIE. Allowlist di stato, non denylist: `chiusa` e `aperta` sono
-- le due che la Cantina del proprietario considera ancora presenti (la sua
-- policy `bottle_units_select_own` filtra `deleted_at` e `ceduta_at` e non
-- filtra lo stato), `consumata` è fuori, e un'etichetta aggiunta domani
-- all'enum resta fuori finché qualcuno non la nomina qui.
create or replace view private.cantina_pubblica
with (security_invoker = off, security_barrier = true)
as
select
  bu.id         as bottle_unit_id,
  bu.owner_id   as user_id,
  bu.stato      as bottiglia_stato,
  bu.created_at as aggiunta_at,
  w.id          as wine_id,
  w.slug        as wine_slug,
  w.produttore,
  w.nome,
  w.annata,
  w.regione,
  w.denominazione,
  w.tipo,
  w.formato,
  -- L'annuncio attivo, se c'è. Serve a due cose sole: dire «in vendita» e
  -- portare al vero annuncio. Prezzo e disponibilità NON passano di qui — chi
  -- li vuole legge `public_listings`, che è la sorgente e applica i propri
  -- filtri. `listings.bottle_unit_id` è uno-a-uno con l'unità, quindi il join
  -- non moltiplica le righe.
  l.id          as listing_id,
  l.slug        as listing_slug,
  coalesce(l.immagini, '{}'::text[]) as listing_immagini
from public.bottle_units bu
  join public.wines w
    on w.id = bu.wine_id
  join private.profili_pubblici pp
    on pp.user_id = bu.owner_id
  left join public.listings l
    on l.bottle_unit_id = bu.id
   and l.seller_id = bu.owner_id
   and l.stato = 'attivo'
   and (l.expires_at is null or l.expires_at > now())
where bu.visibilita = 'cantina_pubblica'::public.bottle_unit_visibilita
  and bu.deleted_at is null
  and bu.ceduta_at is null
  and bu.stato in (
    'chiusa'::public.bottle_unit_stato,
    'aperta'::public.bottle_unit_stato
  );

comment on view private.cantina_pubblica is
  'Proiezione pubblicabile della Cantina: sole unità dichiarate cantina_pubblica, '
  'ancora possedute e non consumate, di un proprietario visibile. Nessun privilegio '
  'per anon/authenticated: la sola porta è public.cantina_pubblica_profilo(uuid, int, int).';

revoke all on private.cantina_pubblica from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- La porta: un profilo per volta
-- ---------------------------------------------------------------------------
--
-- Un solo `uuid`, nessun parametro di ricerca, nessun filtro per regione o
-- produttore: chi chiama deve già sapere di chi sta guardando il profilo. È la
-- stessa forma di `public.profilo_pubblico(uuid)` e per la stessa ragione —
-- resistenza all'enumerazione — con in più limite e offset, perché una Cantina
-- può essere lunga mentre un profilo è una riga.
--
-- Il limite lo decide il database: `least(..., 48)` è il tetto e vale anche se
-- il chiamante chiede diecimila. Un offset negativo torna a zero. Ripetere
-- questi due tagli nel servizio TypeScript darebbe una seconda regola da tenere
-- allineata alla prima.
--
-- `stable` e nessuna scrittura: la funzione può girare dentro una transazione
-- read-only, che è il modo in cui PostgREST esegue le RPC non volatili.
create or replace function public.cantina_pubblica_profilo(
  p_user_id uuid,
  p_limit integer default 12,
  p_offset integer default 0
)
returns table (
  bottle_unit_id uuid,
  wine_id uuid,
  wine_slug text,
  produttore text,
  nome text,
  annata smallint,
  regione text,
  denominazione text,
  tipo text,
  formato text,
  bottiglia_stato public.bottle_unit_stato,
  listing_id uuid,
  listing_slug text,
  listing_immagini text[]
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    v.bottle_unit_id,
    v.wine_id,
    v.wine_slug,
    v.produttore,
    v.nome,
    v.annata,
    v.regione,
    v.denominazione,
    v.tipo,
    v.formato,
    v.bottiglia_stato,
    v.listing_id,
    v.listing_slug,
    v.listing_immagini
  from private.cantina_pubblica v
  where v.user_id = p_user_id
  -- Ordine stabile e indipendente dall'ora di inserimento del vino in
  -- catalogo: annata decrescente, poi produttore e nome, poi l'id come
  -- spareggio. Senza l'ultimo, due bottiglie identiche potrebbero scambiarsi di
  -- posto fra una pagina e l'altra e una di loro non comparire mai.
  order by v.annata desc, v.produttore, v.nome, v.bottle_unit_id
  limit least(greatest(coalesce(p_limit, 12), 1), 48)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

comment on function public.cantina_pubblica_profilo(uuid, integer, integer) is
  'Cantina pubblica di UN profilo già noto. Richiede l''uuid del proprietario, non '
  'elenca persone, non accetta filtri di ricerca, taglia il limite a 48 nel proprio '
  'corpo. Non espone note personali, prezzi privati, costi di acquisto né alcuna '
  'posizione fisica (ambienti, moduli, slot).';

revoke all on function public.cantina_pubblica_profilo(uuid, integer, integer) from public;
grant execute on function public.cantina_pubblica_profilo(uuid, integer, integer)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Il comando del proprietario esisteva già: qui viene fissato, non creato
-- ---------------------------------------------------------------------------
--
-- Il passaggio `privata <-> cantina_pubblica` non ha bisogno di una nuova RPC.
-- La 20260728193937 aveva concesso `update (stato, visibilita, deleted_at)` ad
-- `authenticated`; la 20260729230000 ha revocato `stato` e `deleted_at` e ha
-- lasciato in piedi la sola colonna `visibilita`; la policy
-- `bottle_units_update_own` (20260729234500) limita la scrittura alla propria
-- riga non eliminata e non ceduta. È già il permesso minimo e giusto:
-- aggiungerne un secondo darebbe due porte per lo stesso gesto.
--
-- Questo blocco non concede niente: verifica. Se un domani qualcuno revocasse
-- la colonna, l'interruttore nel profilo smetterebbe di funzionare in silenzio;
-- se qualcuno restituisse privilegi ad `anon`, la Cantina diventerebbe
-- leggibile fuori da questa porta. Meglio che la migrazione fallisca.
do $$
begin
  if not has_column_privilege('authenticated', 'public.bottle_units', 'visibilita', 'UPDATE') then
    raise exception
      'Invariante: authenticated deve conservare UPDATE(visibilita) su public.bottle_units.';
  end if;

  if has_table_privilege('anon', 'public.bottle_units', 'SELECT') then
    raise exception
      'Invariante: anon non deve avere SELECT su public.bottle_units.';
  end if;

  if has_table_privilege('anon', 'public.bottle_units', 'UPDATE')
     or has_table_privilege('authenticated', 'public.bottle_units', 'DELETE') then
    raise exception
      'Invariante: nessuna scrittura ampia su public.bottle_units per i ruoli client.';
  end if;
end $$;

comment on column public.bottle_units.visibilita is
  'Privata oppure cantina_pubblica. Dal 25 settembre 2026 NON è più un residuo inerte: '
  'public.cantina_pubblica_profilo(uuid, int, int) la legge per mostrare la Cantina '
  'pubblica nel profilo del proprietario. Resta scrivibile dal solo proprietario '
  'tramite il GRANT di colonna e la policy bottle_units_update_own; nessun privilegio '
  'pubblico è stato aggiunto alla tabella.';

notify pgrst, 'reload schema';
