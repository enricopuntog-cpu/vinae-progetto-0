-- Cantina pubblica: l'annuncio lo dichiara il marketplace, non la Cantina.
--
-- CHE COSA CORREGGE. La 20260925140000 costruisce `private.cantina_pubblica`
-- collegando l'eventuale annuncio con un join diretto su `public.listings` e
-- ricopiandone tre condizioni di pubblicazione: `seller_id`, `stato = 'attivo'`
-- e `expires_at`. Ma «annuncio pubblicamente visibile» ha gia una definizione
-- sola in questo schema, ed e `public.public_listings`, che ne pretende altre:
--
--   l.stato = 'attivo'            (ricopiata)
--   expires_at nullo o futuro     (ricopiata)
--   bu.owner_id = l.seller_id     (ricopiata)
--   bu.deleted_at is null         (implicita, la Cantina le esclude gia)
--   bu.ceduta_at is null          (implicita, la Cantina le esclude gia)
--   bu.stato = 'chiusa'           >>> NON ricopiata <<<
--   venditore non rimosso         (implicita, via private.profili_pubblici)
--   chiamante non rimosso         (implicita, via private.profili_pubblici)
--
-- L'ultima mancante e quella che conta: la Cantina ammette deliberatamente
-- anche le bottiglie `aperta`, il catalogo no. Una bottiglia aperta cui sia
-- rimasto appeso un annuncio ancora `attivo` compariva quindi nel profilo con
-- il badge «In vendita» e un collegamento a un annuncio che `public_listings`
-- non restituisce: il visitatore atterrava su una pagina che il marketplace
-- considera non pubblica. Due definizioni della stessa cosa, e quella piu
-- permissiva stava sulla superficie pubblica.
--
-- QUANTO E RAGGIUNGIBILE QUELLO STATO, detto senza abbellirlo. Le due porte
-- del client lo difendono gia: `public.bottiglia_apri` (20260729230000:341)
-- rifiuta di aprire una bottiglia con un annuncio `attivo` o `riservato`, e il
-- trigger `listings_bottiglia_idonea` (20260730140948) rifiuta un annuncio non
-- terminale su una bottiglia non chiusa. Dalla 20260729230000:989 il client non
-- ha nemmeno piu il GRANT su `bottle_units.stato`. Resta pero scoperto il caso
-- che conta: `bottle_units.stato` non ha alcun trigger che lo leghi a
-- `listings`, quindi qualunque scrittore privilegiato — `service_role`, una
-- procedura di manutenzione, una futura funzione SECURITY DEFINER scritta
-- senza ricordarsi di questo vincolo — produce lo stato incoerente senza
-- incontrare resistenza. La griglia 12i lo produce esattamente cosi.
--
-- «Normalmente non puo succedere» non e una difesa per una superficie
-- pubblica: e una scommessa su tutte le migrazioni future. La difesa e che la
-- Cantina non decida da se che cosa sia un annuncio pubblico.
--
-- LA REGOLA GIUSTA C'ERA GIA, ED E LA STESSA DI 12b. `public.public_club_posts`
-- collega l'annuncio di una discussione con `left join public.public_listings
-- pl on pl.id = p.listing_id`, per questa identica ragione: un post puo
-- nominare un annuncio, ma lo mostra solo se l'annuncio e davvero pubblico. La
-- Cantina aveva scelto un'altra strada senza motivo. Qui torna sulla stessa.
--
-- ADDITIVA. La 20260925140000 non viene toccata: e stata pubblicata e quindi e
-- congelata. Questa migrazione sostituisce il solo corpo della vista con
-- `create or replace view`, lasciando invariati nome, ordine e tipo delle
-- sedici colonne — la funzione `public.cantina_pubblica_profilo(uuid, int,
-- int)` non cambia firma e non viene ricreata. Nessun GRANT nuovo, nessuna
-- policy allargata, nessun bucket toccato.
--
-- PREZZO DI QUESTA SCELTA, DETTO ESPLICITAMENTE. La vista ora dipende da
-- `public.public_listings`: una futura migrazione che volesse *eliminare e
-- ricreare* quella vista (invece di sostituirla con `create or replace`) dovra
-- ricreare anche questa. E il costo di avere una definizione sola, e vale meno
-- del rischio di averne due che divergono in silenzio. Il vincolo di
-- dipendenza lo rende visibile: `drop view public.public_listings` fallisce
-- finche questa esiste, invece di lasciare indietro una copia stantia.

-- ---------------------------------------------------------------------------
-- La proiezione, con l'annuncio preso dalla sorgente canonica
-- ---------------------------------------------------------------------------
--
-- PERCHE UNA LATERAL E NON UN JOIN. Qui il filtro di stato non c'e piu — vive
-- dentro `public_listings` — quindi `l` spazia su *tutti* gli annunci mai
-- esistiti su quella bottiglia, storico terminale compreso: una bottiglia puo
-- avere un `venduto`, due `scaduto`, un `rifiutato` e un `attivo` insieme, e
-- l'indice parziale `listings_un_solo_annuncio_non_terminale`
-- (20260729230000:317) tiene fuori dall'unicita proprio gli stati terminali.
-- Oggi e `public_listings` a ricondurre quell'insieme a una riga sola, perche
-- pretende `stato = 'attivo'` e di annunci attivi ce ne puo essere uno.
--
-- La lateral con `limit 1` non serve quindi a riparare un difetto esistente:
-- serve a non dipendere da quel ragionamento. L'unicita di cui sopra e una
-- proprieta di un indice in un'altra migrazione, che un giorno potrebbe
-- cambiare; il numero di righe che questa vista produce per bottiglia non deve
-- dipenderne. Con la lateral e uno per costruzione, qualunque cosa contenga
-- `listings`, e l'ordinamento rende deterministico quale annuncio vince (il
-- piu recente). La 20260925140000 si affidava invece all'indice, e restava
-- corretta solo finche quell'indice resta com'e.
--
-- Le colonne non lette di `public_listings` — prezzo, quantita,
-- `seller_verificato` e le altre — non costano nulla: e una vista semplice,
-- il planner la incorpora e scarta le espressioni non referenziate. Da qui
-- passano tre valori soli, e prezzo e disponibilita restano fuori come prima:
-- chi li vuole legge «Annunci attivi», che ha la sua sorgente.
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
  ann.listing_id,
  ann.listing_slug,
  coalesce(ann.listing_immagini, '{}'::text[]) as listing_immagini
from public.bottle_units bu
  join public.wines w
    on w.id = bu.wine_id
  join private.profili_pubblici pp
    on pp.user_id = bu.owner_id
  left join lateral (
    select
      pl.id       as listing_id,
      pl.slug     as listing_slug,
      pl.immagini as listing_immagini
    from public.listings l
      -- Il filtro non e qui: e dentro `public_listings`. Se un annuncio non
      -- supera le sue condizioni, questa join non produce righe e la bottiglia
      -- resta senza collegamento. Fail-closed per costruzione, non per
      -- enumerazione di casi.
      join public.public_listings pl
        on pl.id = l.id
    where l.bottle_unit_id = bu.id
    order by pl.pubblicato_at desc, pl.id
    limit 1
  ) ann on true
where bu.visibilita = 'cantina_pubblica'::public.bottle_unit_visibilita
  and bu.deleted_at is null
  and bu.ceduta_at is null
  and bu.stato in (
    'chiusa'::public.bottle_unit_stato,
    'aperta'::public.bottle_unit_stato
  );

comment on view private.cantina_pubblica is
  'Proiezione pubblicabile della Cantina: sole unità dichiarate cantina_pubblica, '
  'ancora possedute e non consumate, di un proprietario visibile. Il collegamento '
  '«in vendita» deriva da public.public_listings — unica definizione di annuncio '
  'pubblico, dalla 20260925191500 — quindi una bottiglia aperta con un annuncio '
  'rimasto attivo non mostra alcun annuncio. Nessun privilegio per anon/authenticated: '
  'la sola porta è public.cantina_pubblica_profilo(uuid, int, int).';

-- `create or replace view` conserva i privilegi esistenti; la riga qui sotto
-- non aggiunge niente, ripete l'invariante. Se un giorno qualcuno ricreasse
-- questa vista con un `drop`/`create`, la proiezione tornerebbe con i privilegi
-- di default e questa riga sarebbe l'unica cosa fra quella svista e una
-- rubrica delle cantine raggiungibile da PostgREST.
revoke all on private.cantina_pubblica from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Che le due superfici non possano piu divergere
-- ---------------------------------------------------------------------------
--
-- La verifica non e un test: sta qui perche una migrazione futura che tornasse
-- a interrogare `public.listings` direttamente deve fallire mentre viene
-- applicata, non essere scoperta dopo. La griglia 12i prova il comportamento su
-- dati veri; questo blocco prova che la sorgente sia quella dichiarata.
do $$
declare
  v_def text := pg_get_viewdef('private.cantina_pubblica'::regclass);
begin
  if v_def !~ 'public_listings' then
    raise exception
      'Invariante: private.cantina_pubblica deve derivare l''annuncio da public.public_listings.';
  end if;

  -- `listings` compare ancora, ed e legittimo: serve a mappare
  -- `bottle_unit_id -> listing_id`, che `public_listings` non espone. Cio che
  -- non deve tornare e un filtro di pubblicazione ricopiato accanto.
  if v_def ~* 'l\.stato' or v_def ~* 'expires_at' then
    raise exception
      'Invariante: le condizioni di pubblicazione dell''annuncio vivono solo in public.public_listings.';
  end if;
end $$;

notify pgrst, 'reload schema';
