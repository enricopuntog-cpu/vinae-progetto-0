-- Fase 6c-1 — Metadati di bevuta e abbinamenti per gli 8 vini del catalogo.
--
-- Copia diretta di `wineMeta` da frontend-next/src/data/cellar.ts: stessi
-- anni, stesse note, stessi abbinamenti, nessun testo inventato. La chiave è
-- lo slug, la stessa già usata dal seed della 6a.
--
-- Gli elenchi di abbinamenti sono quattro, condivisi per stile fra i vini che
-- se li assomigliano: nel file d'origine sono quattro costanti riusate, qui
-- diventano quattro variabili riusate. La condivisione si perde nel dato
-- salvato — ogni vino porta la propria copia — ed è la conseguenza accettata
-- di tenerli come colonna su `wines` invece che in una tabella a parte.
--
-- I vini creati dai venditori (via listing_crea) restano senza metadati:
-- finestra_fonte vale 'unavailable' e l'interfaccia mostra "informazione non
-- disponibile" invece di inventare un intervallo. È il comportamento che il
-- mock già aveva con DEFAULT_META.

do $migrazione$
declare
  v_rossi_strutturati jsonb := $json$[
    {"categoria":"Brasati e stufati","piatto":"Brasato al Barolo con polenta","livello":"ideale","note":"La struttura tannica bilancia la lunga cottura.","emoji":"🥘","keywords":["brasato","stufato","polenta","stracotto"]},
    {"categoria":"Selvaggina","piatto":"Cinghiale in umido","livello":"ideale","note":"Note terrose in armonia con la selvaggina.","emoji":"🍖","keywords":["cinghiale","cervo","lepre","selvaggina"]},
    {"categoria":"Formaggi stagionati","piatto":"Castelmagno o Parmigiano 36 mesi","livello":"ottimo","note":"Sapidità e persistenza si esaltano.","emoji":"🧀","keywords":["formaggio","parmigiano","pecorino","castelmagno"]},
    {"categoria":"Arrosti","piatto":"Arrosto di manzo alle erbe","livello":"ottimo","note":"Un classico affidabile.","emoji":"🥩","keywords":["arrosto","manzo","roast"]},
    {"categoria":"Funghi","piatto":"Risotto ai porcini","livello":"possibile","note":"L'umami dei funghi trova un buon dialogo.","emoji":"🍄","keywords":["funghi","porcini","risotto"]}
  ]$json$::jsonb;

  v_super_tuscan jsonb := $json$[
    {"categoria":"Grigliata","piatto":"Bistecca alla fiorentina","livello":"ideale","note":"Cabernet e carne rossa: matrimonio classico.","emoji":"🥩","keywords":["bistecca","fiorentina","grigliata","tagliata"]},
    {"categoria":"Selvaggina","piatto":"Filetto di capriolo","livello":"ideale","note":"Grafite e cassis sostengono il selvatico.","emoji":"🍖","keywords":["capriolo","cervo","selvaggina","filetto"]},
    {"categoria":"Formaggi","piatto":"Pecorino toscano stagionato","livello":"ottimo","note":"Rotondità mediterranea.","emoji":"🧀","keywords":["pecorino","formaggio"]},
    {"categoria":"Primi importanti","piatto":"Pappardelle al ragù di cinghiale","livello":"ottimo","note":"Piatto di terra toscano.","emoji":"🍝","keywords":["ragù","pappardelle","pasta","cinghiale"]},
    {"categoria":"Funghi e tartufo","piatto":"Tagliolini al tartufo","livello":"possibile","note":"Se il vino è ben ossigenato.","emoji":"🍄","keywords":["tartufo","tagliolini","funghi"]}
  ]$json$::jsonb;

  v_champagne jsonb := $json$[
    {"categoria":"Crostacei","piatto":"Ostriche e scampi crudi","livello":"ideale","note":"Sapidità e bollicina tagliano la dolcezza iodata.","emoji":"🦪","keywords":["ostriche","scampi","crudi","crostacei"]},
    {"categoria":"Pesce nobile","piatto":"Astice al vapore","livello":"ideale","note":"Eleganza su eleganza.","emoji":"🦞","keywords":["astice","aragosta","pesce"]},
    {"categoria":"Tartare e carpacci","piatto":"Tartare di ricciola agli agrumi","livello":"ottimo","note":"Freschezza vs freschezza.","emoji":"🐟","keywords":["tartare","carpaccio","crudo"]},
    {"categoria":"Aperitivo","piatto":"Focaccia e culatello","livello":"ottimo","note":"Un aperitivo di livello.","emoji":"🥂","keywords":["aperitivo","focaccia","salumi"]},
    {"categoria":"Pasticceria salata","piatto":"Vol au vent al formaggio","livello":"possibile","note":"Con moderazione.","emoji":"🥐","keywords":["pasticceria","salata","vol au vent"]}
  ]$json$::jsonb;

  v_rossi_eleganti jsonb := $json$[
    {"categoria":"Primi al ragù","piatto":"Pici al ragù di chianina","livello":"ideale","note":"Sangiovese e ragù, tradizione toscana.","emoji":"🍝","keywords":["ragù","pici","pasta","sugo"]},
    {"categoria":"Grigliata","piatto":"Costata di manzo","livello":"ideale","note":"Tannino vibrante contro grasso della carne.","emoji":"🥩","keywords":["costata","griglia","manzo"]},
    {"categoria":"Formaggi","piatto":"Pecorino romano","livello":"ottimo","note":"Sapidità e freschezza si equilibrano.","emoji":"🧀","keywords":["pecorino","formaggio"]},
    {"categoria":"Verdure alla brace","piatto":"Melanzane arrostite","livello":"possibile","note":"Piatto vegetariano ma d'impatto.","emoji":"🍆","keywords":["verdure","melanzane","brace"]}
  ]$json$::jsonb;

  v_riga  record;
  v_tocchi int := 0;
begin
  for v_riga in
    select * from (values
      ('monfortino-2015',           2028, 2055, 2032, 2048, 'editorial', 'alta',  '17–18 °C', 120, 'Calice grande Nebbiolo/Borgogna', 'Cena importante, tavola formale',   date '2026-06-01', 'strutturati'),
      ('sassicaia-2018',            2025, 2045, 2028, 2038, 'editorial', 'alta',  '17–18 °C',  90, 'Calice Bordeaux',                'Cena di gala, verticale con amici', date '2026-05-20', 'tuscan'),
      ('tignanello-2019',           2025, 2040, 2027, 2035, 'ai',        'media', '17–18 °C',  60, 'Calice Bordeaux medio',          'Cena importante ma informale',      date '2026-06-10', 'tuscan'),
      ('dom-perignon-2013',         2024, 2040, 2026, 2035, 'editorial', 'alta',  '8–10 °C',    0, 'Tulipano da Champagne',          'Celebrazioni, aperitivi importanti', date '2026-05-01', 'champagne'),
      ('ornellaia-2017',            2024, 2038, 2026, 2034, 'editorial', 'alta',  '17–18 °C',  75, 'Calice Bordeaux',                'Cena importante',                   date '2026-04-15', 'tuscan'),
      ('biondi-santi-2016',         2026, 2050, 2030, 2045, 'editorial', 'alta',  '17–18 °C',  90, 'Calice Sangiovese ampio',        'Cena di grande respiro',            date '2026-03-30', 'eleganti'),
      ('rinaldi-brunate-2018',      2027, 2045, 2030, 2042, 'ai',        'media', '17 °C',     90, 'Calice Nebbiolo',                'Serata tra appassionati',           date '2026-06-15', 'strutturati'),
      ('cadelbosco-annamaria-2015', 2023, 2035, 2025, 2032, 'editorial', 'alta',  '9–11 °C',    0, 'Tulipano ampio',                 'Aperitivo o cena di pesce',         date '2026-05-05', 'champagne')
    ) as t(slug, f_inizio, f_fine, a_inizio, a_fine, fonte, affidabilita,
           temperatura, decantazione, calice, occasione, aggiornato, stile)
  loop
    update public.wines w
    set finestra_inizio       = v_riga.f_inizio::smallint,
        finestra_fine         = v_riga.f_fine::smallint,
        apice_inizio          = v_riga.a_inizio::smallint,
        apice_fine            = v_riga.a_fine::smallint,
        finestra_fonte        = v_riga.fonte::public.drink_window_fonte,
        finestra_affidabilita = v_riga.affidabilita::public.drink_window_affidabilita,
        finestra_aggiornata_at = v_riga.aggiornato,
        temperatura_servizio  = v_riga.temperatura,
        decantazione_minuti   = v_riga.decantazione::smallint,
        calice                = v_riga.calice,
        occasione             = v_riga.occasione,
        abbinamenti           = case v_riga.stile
                                  when 'strutturati' then v_rossi_strutturati
                                  when 'tuscan'      then v_super_tuscan
                                  when 'champagne'   then v_champagne
                                  else                    v_rossi_eleganti
                                end
    where w.slug = v_riga.slug;

    v_tocchi := v_tocchi + 1;
  end loop;

  raise notice 'Metadati applicati a % vini del catalogo.', v_tocchi;
end;
$migrazione$;
