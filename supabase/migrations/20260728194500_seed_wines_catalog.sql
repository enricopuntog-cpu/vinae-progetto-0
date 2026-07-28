-- Fase 6a — Seed del catalogo condiviso (solo `wines`).
--
-- PERCHÉ ESISTE. Non è un riempitivo per far sembrare popolata una pagina
-- vuota: i metadati che alimentano la finestra di bevuta (DrinkBadge,
-- DrinkWindowSection), gli abbinamenti cibo (FoodPairingSection) e la ricerca
-- "cosa stai preparando" di /esplora vivono ancora in
-- frontend-next/src/data/cellar.ts, indicizzati per slug del vino. Un vino
-- reale con uno slug sconosciuto a quella mappa perde quelle sezioni senza
-- alcun messaggio d'errore. Seminando le otto voci con gli slug già usati dal
-- mock, ciò che l'utente vede resta identico a frontend/.
--
-- COSA NON SEMINA. Nessun annuncio e nessuna bottle_unit: entrambi richiedono
-- un venditore reale in public.profiles, cioè un utente vero in auth.users. I
-- venditori del mock ("Marco B.", "Sofia R.") non sono account e inventarli
-- significherebbe scrivere in produzione righe che fingono di essere persone.
-- Gli annunci nascono da account reali — dal test end-to-end di questa fase
-- ora, dal wizard /vendi in Fase 6b.
--
-- Dati presi da frontend-next/src/data/wines.ts. Solo i campi di catalogo:
-- prezzo, condizione, conservazione, storia, immagini e venditore
-- appartengono all'annuncio, non al vino, e non compaiono qui.

insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato)
values
  ('monfortino-2015',           'Giacomo Conterno',  'Barolo Riserva Monfortino',   2015, 'Piemonte',  'Barolo DOCG',                    'Rosso',     '0,75 L'),
  ('sassicaia-2018',            'Tenuta San Guido',  'Sassicaia',                   2018, 'Toscana',   'Bolgheri Sassicaia DOC',         'Rosso',     '0,75 L'),
  ('tignanello-2019',           'Antinori',          'Tignanello',                  2019, 'Toscana',   'Toscana IGT',                    'Rosso',     '0,75 L'),
  ('dom-perignon-2013',         'Moët & Chandon',    'Dom Pérignon Vintage',        2013, 'Champagne', 'Champagne AOC',                  'Bollicine', '0,75 L'),
  ('ornellaia-2017',            'Ornellaia',         'Ornellaia',                   2017, 'Toscana',   'Bolgheri Superiore DOC',         'Rosso',     '0,75 L'),
  ('biondi-santi-2016',         'Biondi-Santi',      'Brunello di Montalcino',      2016, 'Toscana',   'Brunello di Montalcino DOCG',    'Rosso',     '0,75 L'),
  ('rinaldi-brunate-2018',      'Giuseppe Rinaldi',  'Barolo Brunate',              2018, 'Piemonte',  'Barolo DOCG',                    'Rosso',     '0,75 L'),
  ('cadelbosco-annamaria-2015', 'Ca'' del Bosco',    'Cuvée Annamaria Clementi',    2015, 'Lombardia', 'Franciacorta DOCG',              'Bollicine', '0,75 L')
on conflict (slug) do nothing;
