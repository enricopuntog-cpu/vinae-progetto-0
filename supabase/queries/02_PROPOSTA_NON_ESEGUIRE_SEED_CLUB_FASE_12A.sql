-- ===========================================================================
-- PROPOSTA DI FIXTURE - NON ESEGUIRE SENZA AUTORIZZAZIONE ESPLICITA
-- Fase 12a - sette club iniziali
-- ===========================================================================
--
-- QUESTO FILE NON E STATO ESEGUITO DA NESSUNA PARTE, e non deve esserlo
-- finche non arriva un'autorizzazione esplicita in sessione, DISTINTA da
-- quella che approva la migrazione 20260817090000. Sono due cancelli diversi
-- e la distinzione non e formale: la migrazione crea lo schema, questo file
-- scrive DATI nel progetto reale. Approvare l'una non approva l'altro.
--
-- DOVE STA, E PERCHE NON ALTROVE.
--   * non in `supabase/migrations/`: li il merge e il gate di deploy
--     (decisione 7.10) e la PR lo applicherebbe da sola al progetto reale
--     nell'istante dello squash, che e esattamente cio che l'autorizzazione
--     separata deve poter fermare;
--   * non in `supabase/seed.sql`: `supabase/config.toml` ha `[db.seed]`
--     abilitato con `sql_paths = ["./seed.sql"]`, quindi quel nome viene
--     caricato a ogni `db reset` e sulle preview branch. Sarebbe lo stesso
--     automatismo con un altro nome;
--   * qui, accanto a `00_INFO_NON_ESEGUIRE_...`, che e la convenzione gia in
--     uso nel repository per l'SQL che si esegue a mano e solo di proposito.
--
-- COSA CONTIENE, IN BREVE
--   Sette club, scelti per coprire i quattro assi di filtro con piu di un
--   valore ciascuno - altrimenti un menu a tendina con una voce sola non
--   dimostra niente - e per contenere il caso limite che il codice deve
--   reggere: `grandi-formati` ha SOLO la tipologia, con territorio,
--   denominazione e produttore nulli. E' li apposta: le tre colonne sono
--   opzionali, e un fixture in cui sono tutte valorizzate lascerebbe non
--   provato il ramo che le salta.
--
--   territorio:    Piemonte, Toscana, Veneto, Champagne, Borgogna  (5 valori)
--   denominazione: Barolo DOCG, Brunello di Montalcino DOCG,
--                  Amarone della Valpolicella DOCG, Champagne AOC  (4 valori)
--   produttore:    Giacomo Conterno                                (1 valore)
--   tipologia:     Rosso, Bianco, Bollicine                        (3 valori)
--
--   L'asse `produttore` ha un valore solo, ed e una scelta: un club dedicato a
--   un produttore e una pagina che parla di un'azienda reale, e sette di
--   quelli sarebbero sette pagine scritte da noi su terzi che non le hanno
--   viste. Uno basta a far esistere l'asse e a farlo provare.
--
--   Nessun club nomina persone. Le descrizioni non attribuiscono giudizi,
--   punteggi o fatti a produttori reali: dicono di cosa si parla nel club, che
--   e l'unica cosa che la piattaforma sa davvero.
--
-- IDEMPOTENZA
--   `on conflict (slug) do nothing`: rieseguirlo non duplica e non sovrascrive
--   un club che qualcuno avesse nel frattempo modificato. Non aggiorna: se
--   serve cambiare un testo gia scritto, si fa con una UPDATE mirata e
--   guardando prima cosa c'e.
--
-- NESSUNA MEMBERSHIP
--   Questo fixture non scrive in `club_memberships`, e non potrebbe farlo in
--   modo sensato: quelle righe appartengono a utenti reali, e inventarle
--   significherebbe iscrivere qualcuno a un club che non ha scelto. Il
--   conteggio `membri` di `public_clubs` partira quindi da zero per tutti e
--   sette, che e il numero vero.

insert into public.clubs
  (slug, nome, territorio, denominazione, produttore, tipologia, descrizione, regole)
values
  (
    'barolo',
    'Barolo',
    'Piemonte',
    'Barolo DOCG',
    null,
    'Rosso',
    'Nebbiolo delle Langhe: annate, comuni, menzioni geografiche aggiuntive e '
    'finestre di beva. Si parla di bottiglie che si hanno in cantina e di '
    'quelle che si vorrebbero aprire fra dieci anni.',
    array[
      'Si parla di vino: fuori tema e chiuso senza discussione.',
      'Le note di degustazione dicono annata e condizioni di conservazione.',
      'Nessuna trattativa privata nei commenti: per quello c''e il marketplace.'
    ]
  ),
  (
    'brunello-di-montalcino',
    'Brunello di Montalcino',
    'Toscana',
    'Brunello di Montalcino DOCG',
    null,
    'Rosso',
    'Sangiovese grosso, versanti e altimetrie diverse dentro lo stesso comune. '
    'Confronti fra annate, riserve e differenze di stile fra le zone.',
    array[
      'Si parla di vino: fuori tema e chiuso senza discussione.',
      'I confronti fra annate portano una nota, non solo un voto.',
      'Nessuna trattativa privata nei commenti: per quello c''e il marketplace.'
    ]
  ),
  (
    'amarone',
    'Amarone della Valpolicella',
    'Veneto',
    'Amarone della Valpolicella DOCG',
    null,
    'Rosso',
    'Appassimento, residuo zuccherino e tenuta nel tempo. Un club per chi vuole '
    'capire quanto cambia l''Amarone fra una casa e l''altra, e perche.',
    array[
      'Si parla di vino: fuori tema e chiuso senza discussione.',
      'Le note di degustazione dicono annata e condizioni di conservazione.'
    ]
  ),
  (
    'champagne',
    'Champagne',
    'Champagne',
    'Champagne AOC',
    null,
    'Bollicine',
    'Millesimati, sboccature, dosaggi e vignaioli indipendenti. Si discute di '
    'cosa cambia fra una bottiglia sboccata da sei mesi e la stessa da sei anni.',
    array[
      'Si parla di vino: fuori tema e chiuso senza discussione.',
      'La data di sboccatura, quando c''e, si scrive.',
      'Nessuna trattativa privata nei commenti: per quello c''e il marketplace.'
    ]
  ),
  (
    'borgogna-bianca',
    'Borgogna bianca',
    'Borgogna',
    null,
    null,
    'Bianco',
    'Chardonnay di Borgogna, dal villaggio al cru. Annate, produttori e la '
    'domanda che torna sempre: quando si apre.',
    array[
      'Si parla di vino: fuori tema e chiuso senza discussione.',
      'Le note di degustazione dicono annata e condizioni di conservazione.'
    ]
  ),
  (
    'giacomo-conterno',
    'Giacomo Conterno',
    'Piemonte',
    'Barolo DOCG',
    'Giacomo Conterno',
    'Rosso',
    'Club dedicato alle bottiglie di questa casa: verticali, differenze fra le '
    'etichette e stato di conservazione. Le opinioni sono di chi le scrive e '
    'non della cantina, che non partecipa a questo club.',
    array[
      'Si parla di vino: fuori tema e chiuso senza discussione.',
      'Le opinioni sono personali: non si attribuiscono alla cantina.',
      'Nessuna trattativa privata nei commenti: per quello c''e il marketplace.'
    ]
  ),
  (
    'grandi-formati',
    'Grandi formati',
    null,
    null,
    null,
    'Rosso',
    'Magnum e oltre: come invecchiano davvero, come si conservano e quando ha '
    'senso comprarli. Nessun territorio e nessuna denominazione: qui conta il '
    'formato.',
    array[
      'Si parla di vino: fuori tema e chiuso senza discussione.',
      'Si dichiara il formato di cui si parla.'
    ]
  )
on conflict (slug) do nothing;

-- Controprova da eseguire subito dopo, e da riportare incollata e non
-- riassunta: sette righe, e i quattro assi con il numero di valori distinti
-- dichiarato nell'intestazione.
select
  count(*)                                            as club,
  count(distinct territorio)                          as territori,
  count(distinct denominazione)                       as denominazioni,
  count(distinct produttore)                          as produttori,
  count(distinct tipologia)                           as tipologie,
  count(*) filter (where territorio is null)          as senza_territorio
from public.clubs;
