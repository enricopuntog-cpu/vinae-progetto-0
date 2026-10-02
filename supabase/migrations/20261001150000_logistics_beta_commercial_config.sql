-- ---------------------------------------------------------------------------
-- WP6C — Configurazione commerciale della Beta logistica
-- ---------------------------------------------------------------------------
--
-- Questa migrazione NON crea architettura. Non aggiunge tabelle, funzioni,
-- policy, privilegi o porte: usa esattamente il modello versionato di WP6A
-- (`20260930090000_logistics_economic_foundation.sql`) e WP6B
-- (`20260930170000_logistics_beta_routing.sql`), che restano intatte.
--
-- Carica DATI: la configurazione commerciale della Beta che il titolare del
-- prodotto ha gia approvato e che fino a oggi risultava vuota in produzione.
-- WP6B aveva deliberatamente lasciato vuote queste tabelle perche il dato
-- commerciale non esisteva ancora; ora esiste, e il suo posto corretto e una
-- configurazione versionata, non una costante nel codice.
--
-- IL PUNTO CENTRALE DI QUESTO FILE, ed e l'unico modo di leggerlo
-- correttamente: configurazione commerciale conosciuta NON significa rotta
-- operativa. Dopo questa migrazione il motore continua a NON assegnare nessuna
-- rotta, e non per dimenticanza: `private.logistics_service_compatibili` e fail
-- closed e qui restano chiuse CINQUE condizioni indipendenti, ognuna
-- sufficiente da sola a escludere ogni servizio.
--
--   1. i cinque limiti operativi dei servizi sono NULL — non li conosciamo, e
--      un limite NULL non significa «illimitato»;
--   2. `operational_eligibility = false` — la conferma operativa su vetro e
--      responsabilita non c'e ancora;
--   3. `active = false` — nessun servizio e attivo;
--   4. le tariffe sono in `preactivation`, e il motore esige `active`;
--   5. non esiste nessuna rete PUDO e nessun punto di ritiro.
--
-- Per far nascere una rotta servono tutte e cinque, piu la rubrica reale del
-- provider. Nessuna di esse viene aperta qui, e nessuna va aperta per far
-- diventare «verde» una prova: una rotta verde ottenuta inventando un limite
-- manda una persona davanti a una saracinesca chiusa.
--
-- Cosa questa migrazione NON semina, e perche:
--   * nessuna riga in `private.logistics_shipping_rates` (WP6A). Quel listino
--     esige `max_weight_g not null > 0` e noi non conosciamo la fascia di peso
--     reale dei contratti: materializzarlo richiederebbe di inventare un peso.
--     Il dato commerciale vive in `logistics_commercial_rate_sources`, che e
--     la sua sede; il listino operativo si attiva quando i parametri sono
--     reali.
--   * nessuna rete PUDO, nessun punto di ritiro, nessuna coordinata. Sono dati
--     del provider con una scadenza, e non li abbiamo.
--   * nessuna riga in `private.logistics_pack_pricing_config`: la
--     configurazione 500/1000/1000/1000 e gia corrente da WP6B e duplicarla
--     violerebbe l'indice di unicita della riga corrente.
--   * nessuna modifica a `private.logistics_quote_config` di WP6A, che resta a
--     `buffer_bps = 0` e `buffer_fixed_cents = 0`. Il 5% e il buffer del Vinea
--     Pack e vive solo nella sua tabella.
--   * nessuna modifica all'approvvigionamento della Sezione U: i prezzi
--     Vigoroso sono il COSTO DI ACQUISTO e non vengono toccati dai contributi
--     di imballaggio, che sono una voce economica della transazione. I due
--     numeri devono poter divergere.
--
-- Ogni inserimento e idempotente e NON sovrascrive: la guardia
-- `where not exists (... effective_to is null)` significa che se un operatore
-- ha gia caricato una configurazione corrente attraverso le porte admin di
-- versionamento, questa migrazione la rispetta e non la scavalca. Per
-- SOSTITUIRE un valore corrente si usa la porta admin, che chiude la finestra
-- precedente e apre la nuova: e il percorso previsto, e non richiede un deploy.

-- ---------------------------------------------------------------------------
-- Sezione A/B — Servizi e capability come DATI
-- ---------------------------------------------------------------------------
--
-- Tre servizi, uno per provider, con il livello `standard` di default. I codici
-- sono dati di configurazione, non rami di codice: in nessun punto del motore
-- esiste un `case` su un nome commerciale, e la selezione emerge dalle righe.
--
-- I cinque limiti operativi restano NULL ed `eligibility_note` dice esattamente
-- cosa manca, cosi chi leggera la tabella fra sei mesi sapra che la bozza e
-- voluta e sapra che cosa serve per chiuderla.

insert into private.logistics_service_definitions (
  provider_code, service_code, service_level,
  eligible_packaging_formats, eligible_packaging_skus,
  operational_eligibility, active, eligibility_note
)
select
  v.provider_code, 'standard_beta', 'standard',
  array[
    'bottiglia_1', 'bottiglia_2', 'bottiglia_3',
    'bottiglia_6', 'magnum_1_5l'
  ]::text[],
  '{}'::text[],
  false,
  false,
  v.nota
from (
  values
    ('inpost',
     'Capability commerciale approvata (PUDO_TO_PUDO). Mancano: limiti '
     'operativi di peso e dimensione, conferma operativa su vetro e '
     'responsabilita, rete PUDO e rubrica dei punti di ritiro. Finche mancano, '
     'il servizio e configurazione e non rotta.'),
    ('sda',
     'Capability commerciali approvate (PUDO_TO_PUDO e HOME_TO_PUDO). Mancano: '
     'limiti operativi di peso e dimensione, conferma operativa su vetro e '
     'responsabilita, rete PUDO e rubrica dei punti di ritiro. Finche mancano, '
     'il servizio e configurazione e non rotta.'),
    ('brt',
     'Capability commerciale approvata (HOME_TO_PUDO). Mancano: limiti '
     'operativi di peso e dimensione, conferma operativa su vetro e '
     'responsabilita, rete PUDO di destinazione e rubrica dei punti di ritiro. '
     'Finche mancano, il servizio e configurazione e non rotta.')
) as v (provider_code, nota)
where not exists (
  select 1 from private.logistics_service_definitions s
  where s.provider_code = v.provider_code
    and s.service_code = 'standard_beta'
    and s.service_level = 'standard'
    and s.effective_to is null
);

-- Capability: nessuna e implicita. Un servizio che sa fare HOME_TO_PUDO non sa
-- per questo fare PUDO_TO_PUDO, quindi ogni coppia e una riga dichiarata.
-- PUDO_TO_HOME e HOME_TO_HOME NON sono configurate: la consegna a domicilio
-- non e nel perimetro commerciale della Beta, e l'assenza della riga e il modo
-- corretto di dirlo — non un divieto scritto nel codice.

insert into private.logistics_service_capabilities (
  service_definition_id, capability
)
select s.id, v.capability
from (
  values
    ('inpost', 'PUDO_TO_PUDO'),
    ('sda', 'PUDO_TO_PUDO'),
    ('sda', 'HOME_TO_PUDO'),
    ('brt', 'HOME_TO_PUDO')
) as v (provider_code, capability)
join private.logistics_service_definitions s
  on s.provider_code = v.provider_code
 and s.service_code = 'standard_beta'
 and s.service_level = 'standard'
 and s.effective_to is null
where not exists (
  select 1 from private.logistics_service_capabilities cap
  where cap.service_definition_id = s.id
    and cap.capability = v.capability
);

-- ---------------------------------------------------------------------------
-- Sezione C — Sorgente commerciale delle tariffe (Umbria Hub)
-- ---------------------------------------------------------------------------
--
-- Prezzi FINALI e LORDI approvati dal titolare del prodotto. «Finali» ha una
-- conseguenza tecnica precisa: l'IVA e GIA DENTRO questi numeri, quindi
-- riapplicarla sarebbe una doppia imposizione. Quando una riga verra
-- materializzata in WP6A la regola e `base_rate_cents = billable_cents`,
-- `fuel_surcharge_bps = 0`, `vat_bps = 0`.
--
-- `source_gross_micros` conserva il valore di origine ESATTO: 5.9405 EUR non e
-- 5.94 EUR, e la differenza si perderebbe per sempre se tenessimo solo i
-- centesimi. `billable_cents` e il suo arrotondamento HALF-UP applicato UNA
-- SOLA VOLTA, in aritmetica intera, e non e un campo libero: il CHECK
-- `logistics_commercial_rate_sources_arrotondamento` lo ricalcola con
-- `private.logistics_micros_to_cents` e rifiuta la riga se i due divergono.
-- Le venti conversioni qui sotto sono quindi verificate dal database, non
-- dichiarate da chi scrive.
--
-- `status = 'preactivation'`: il dato commerciale e approvato, l'attivazione
-- operativa no. Il motore esige `status = 'active'`, quindi questa colonna e
-- da sola una delle cinque chiusure. Portarla ad `active` e una decisione
-- operativa che si prende con la porta admin, insieme ai limiti reali e alla
-- rubrica dei punti.
--
-- Il formato da 12 bottiglie NON ha nessuna tariffa Standard Beta, e non e una
-- dimenticanza: non e un formato della Beta. Per coerenza non compare nemmeno
-- in `eligible_packaging_formats` qui sopra.

insert into private.logistics_commercial_rate_sources (
  provider_code, service_code, packaging_format, capability,
  source_gross_micros, billable_cents, status, source_label
)
select
  v.provider_code, 'standard_beta', v.packaging_format, v.capability,
  v.source_gross_micros,
  private.logistics_micros_to_cents(v.source_gross_micros),
  'preactivation',
  'Umbria Hub — prezzi finali Beta approvati (IVA inclusa)'
from (
  values
    -- Formato 1 bottiglia
    ('inpost', 'bottiglia_1',  'PUDO_TO_PUDO',  4150000::bigint),
    ('sda',    'bottiglia_1',  'PUDO_TO_PUDO',  5130000::bigint),
    ('brt',    'bottiglia_1',  'HOME_TO_PUDO',  5940500::bigint),
    ('sda',    'bottiglia_1',  'HOME_TO_PUDO',  6210000::bigint),
    -- Formato 2 bottiglie
    ('inpost', 'bottiglia_2',  'PUDO_TO_PUDO',  4220000::bigint),
    ('sda',    'bottiglia_2',  'PUDO_TO_PUDO',  6420000::bigint),
    ('brt',    'bottiglia_2',  'HOME_TO_PUDO',  7960270::bigint),
    ('sda',    'bottiglia_2',  'HOME_TO_PUDO',  6210000::bigint),
    -- Formato 3 bottiglie: identico al formato 2, come approvato
    ('inpost', 'bottiglia_3',  'PUDO_TO_PUDO',  4220000::bigint),
    ('sda',    'bottiglia_3',  'PUDO_TO_PUDO',  6420000::bigint),
    ('brt',    'bottiglia_3',  'HOME_TO_PUDO',  7960270::bigint),
    ('sda',    'bottiglia_3',  'HOME_TO_PUDO',  6210000::bigint),
    -- Formato 6 bottiglie
    ('inpost', 'bottiglia_6',  'PUDO_TO_PUDO',  4220000::bigint),
    ('sda',    'bottiglia_6',  'PUDO_TO_PUDO',  6500000::bigint),
    ('brt',    'bottiglia_6',  'HOME_TO_PUDO', 11286950::bigint),
    ('sda',    'bottiglia_6',  'HOME_TO_PUDO',  8330000::bigint),
    -- Magnum 1,5 L
    ('inpost', 'magnum_1_5l',  'PUDO_TO_PUDO',  4220000::bigint),
    ('sda',    'magnum_1_5l',  'PUDO_TO_PUDO',  5130000::bigint),
    ('brt',    'magnum_1_5l',  'HOME_TO_PUDO',  6296930::bigint),
    ('sda',    'magnum_1_5l',  'HOME_TO_PUDO',  6210000::bigint)
) as v (provider_code, packaging_format, capability, source_gross_micros)
where not exists (
  select 1 from private.logistics_commercial_rate_sources c
  where c.provider_code = v.provider_code
    and c.service_code = 'standard_beta'
    and c.packaging_format = v.packaging_format
    and c.capability = v.capability
    and c.effective_to is null
);

-- ---------------------------------------------------------------------------
-- Sezione N — Contributi di imballaggio della Beta
-- ---------------------------------------------------------------------------
--
-- Questi sono il CONTRIBUTO DI IMBALLAGGIO BETA: una voce economica della
-- transazione, approvata dal titolare del prodotto. NON sono il costo di
-- acquisto dal fornitore della Sezione U e non lo sovrascrivono.
--
-- La coincidenza va detta esplicitamente perche e una trappola: il contributo
-- del cartone da sei e 609, mentre il primo scaglione di `TRIPLEX06-A` nel
-- listino Vigoroso e 369. Sono numeri di domini diversi e devono poter
-- divergere: il costo d'acquisto scende col volume e lo rinegozia chi compra,
-- il contributo e una decisione commerciale verso venditore e acquirente. Il
-- 369 che appare qui sotto e il contributo del formato da DUE bottiglie, e con
-- lo scaglione del cartone da sei non ha niente a che fare.
--
-- `status = 'active'`: sono i valori approvati e correnti della Beta, non una
-- pianificazione. La funzione di unit economics non filtra comunque su questa
-- colonna — legge la riga corrente — quindi lo stato qui e una dichiarazione
-- di natura, non un interruttore.

insert into private.logistics_packaging_contributions (
  packaging_format, contribution_cents, status, note
)
select
  v.packaging_format, v.contribution_cents, 'active',
  'Contributo di imballaggio Beta approvato. Voce economica della '
  'transazione: non e il costo di acquisto dal fornitore della Sezione U e '
  'non sostituisce private.logistics_packaging_skus di WP6A.'
from (
  values
    ('bottiglia_1', 319),
    ('bottiglia_2', 369),
    ('bottiglia_3', 379),
    ('bottiglia_6', 609),
    ('magnum_1_5l', 509)
) as v (packaging_format, contribution_cents)
where not exists (
  select 1 from private.logistics_packaging_contributions ct
  where ct.packaging_format = v.packaging_format
    and ct.effective_to is null
);

-- ---------------------------------------------------------------------------
-- Sezione O — Soglia di unit economics
-- ---------------------------------------------------------------------------
--
-- 15 EUR IVA inclusa come obiettivo per imballaggio + trasporto + eventuale
-- tecnologia. E una GUARDIA OSSERVABILE e una voce di report, non un rifiuto:
-- `private.logistics_unit_economics` riferisce `withinTarget` e non blocca
-- niente, ed e giusto cosi — il prodotto deve poter decidere di accettare uno
-- sforamento, non scoprire che il motore ha scartato una rotta in silenzio.
--
-- La commissione marketplace dell'8% resta SEMPRE fuori da questo conto: e
-- un'altra componente, vive in `marketplace_config` e non viene toccata qui.

insert into private.logistics_unit_economics_config (
  target_cents, active, note
)
select
  1500, true,
  'Obiettivo Beta: imballaggio + trasporto + eventuale tecnologia <= 15 EUR '
  'IVA inclusa. Guardia osservabile e voce di report, non un rifiuto rigido. '
  'La commissione marketplace dell''8% e sempre esclusa.'
where not exists (
  select 1 from private.logistics_unit_economics_config where effective_to is null
);

-- ---------------------------------------------------------------------------
-- Sezione P — Catalogo del Vinea Pack
-- ---------------------------------------------------------------------------
--
-- Quattro tagli approvati. Il pack e un CATALOGO COMMERCIALE e non una rotta:
-- attivarlo non apre nessuna spedizione e non interferisce con le cinque
-- chiusure di cui sopra. Il prezzo si legge dalla porta admin di simulazione,
-- che resta negata a chi non e amministratore.
--
-- Il formato da 12 bottiglie non e Standard Beta, quindi le composizioni
-- ammesse restano i cinque formati con un contributo configurato: il motore di
-- prezzo rifiuta da se una composizione che contenga un formato senza
-- contributo, e non serve una seconda regola che lo ripeta.

insert into private.logistics_pack_catalog (
  pack_code, label, total_units, active
)
select v.pack_code, v.label, v.total_units, true
from (
  values
    ('single',  'Vinea Pack — bottiglia singola', 1),
    ('pack_5',  'Vinea Pack 5',                   5),
    ('pack_10', 'Vinea Pack 10',                 10),
    ('pack_20', 'Vinea Pack 20',                 20)
) as v (pack_code, label, total_units)
where not exists (
  select 1 from private.logistics_pack_catalog p
  where p.pack_code = v.pack_code and p.effective_to is null
);

-- ---------------------------------------------------------------------------
-- Sezione Q — Spedizione del kit di imballaggio (pianificazione)
-- ---------------------------------------------------------------------------
--
-- Costo PROVVISORIO di pianificazione della spedizione del kit di imballaggio
-- verso il venditore. Non e una tariffa corriere del marketplace, non e la
-- tariffa Umbria Hub definitiva e non entra in nessuna rotta: vive in una
-- tabella separata esattamente per non poter essere scambiato per un listino.
-- `status = 'planning'` lo dice nel dato, non solo in un commento.

insert into private.logistics_pack_kit_shipping (
  amount_cents, status, source_label, note
)
select
  550, 'planning',
  'Stima di pianificazione Beta',
  'Costo provvisorio di spedizione del KIT di imballaggio verso il venditore. '
  'Non e una tariffa corriere marketplace ne la tariffa Umbria Hub '
  'definitiva, e non entra in nessuna rotta.'
where not exists (
  select 1 from private.logistics_pack_kit_shipping where effective_to is null
);

-- ---------------------------------------------------------------------------
-- Sezione R — Prezzi di catalogo per composizione mono-formato 1 bottiglia
-- ---------------------------------------------------------------------------
--
-- Questi quattro prezzi sono decisi a catalogo e NON discendono dalle regole.
-- Modellarli come override versionati e la scelta corretta: l'alternativa
-- sarebbe deformare buffer e maggiorazioni finche il loro risultato coincide
-- con un numero commerciale, e a quel punto le regole non descriverebbero piu
-- niente. Le regole restano il caso generale, l'override e l'eccezione
-- dichiarata, e cambiarlo non richiede un deploy.
--
-- La firma di composizione e calcolata dalla stessa funzione che il motore usa
-- a runtime, `private.logistics_pack_composizione_firma`, quindi l'aggancio e
-- al CONTENUTO e non a una formattazione: `bottiglia_1:5` e la firma canonica
-- di cinque bottiglie singole comunque siano state scritte.
--
-- Questi numeri NON vanno replicati come costanti nel frontend: la loro unica
-- sede e questa tabella.

insert into private.logistics_pack_price_overrides (
  pack_code, composition_signature, price_cents, status, note
)
select
  v.pack_code,
  private.logistics_pack_composizione_firma(v.composizione),
  v.price_cents,
  'active',
  'Prezzo di catalogo Beta approvato per la composizione mono-formato da una '
  'bottiglia. Vince sull''esito delle regole; le regole restano il caso '
  'generale.'
from (
  values
    ('single',  '[{"formato": "bottiglia_1", "quantita": 1}]'::jsonb,  1000),
    ('pack_5',  '[{"formato": "bottiglia_1", "quantita": 5}]'::jsonb,  2190),
    ('pack_10', '[{"formato": "bottiglia_1", "quantita": 10}]'::jsonb, 3190),
    ('pack_20', '[{"formato": "bottiglia_1", "quantita": 20}]'::jsonb, 5390)
) as v (pack_code, composizione, price_cents)
where not exists (
  select 1 from private.logistics_pack_price_overrides o
  where o.pack_code = v.pack_code
    and o.composition_signature
        = private.logistics_pack_composizione_firma(v.composizione)
    and o.effective_to is null
);

-- Nessun `notify pgrst, 'reload schema'`: questa migrazione non crea, elimina
-- o modifica alcun oggetto di schema, quindi la cache di PostgREST non ha
-- niente da rileggere. Sono righe di configurazione, lette a ogni richiesta.
