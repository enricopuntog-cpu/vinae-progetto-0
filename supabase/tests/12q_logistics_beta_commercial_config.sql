-- Configurazione commerciale della Beta logistica (griglia 12q).
--
-- SOLO stack Supabase locale/effimero. Il guard rifiuta un database che
-- contiene utenti Auth non `.test`. La griglia non scrive NIENTE — legge la
-- configurazione come la 20261001150000 l'ha seminata — ed e comunque una
-- transazione chiusa da ROLLBACK.
--
-- IL MOTIVO PER CUI LA GRIGLIA ESISTE. La WP6C non aggiunge architettura:
-- carica dati. Una migrazione di soli dati sembra la cosa piu innocua del
-- repository ed e invece il punto in cui questo dominio puo rompersi nel modo
-- piu silenzioso, perche il dato caricato e PERSUASIVO. Tre cose possono
-- guastarsi senza che niente si accenda.
--
--   [1] La frase che questa griglia esiste per tenere vera:
--       CONFIGURAZIONE COMMERCIALE CONOSCIUTA NON E ROTTA OPERATIVA.
--       Capability approvate, venti tariffe reali e cinque contributi
--       approvati sono ora nel database. Nessuno di questi fatti rende
--       percorribile una spedizione, e la tentazione di «completare il
--       quadro» — un limite di peso plausibile, un `active = true`, una rete
--       PUDO di prova — e esattamente la cosa che manderebbe una persona
--       davanti a una saracinesca chiusa con un'etichetta gia pagata. I casi
--       26-29 misurano quella chiusura dal lato del motore, non dal lato del
--       commento: chiedono una rotta e verificano che non arrivi.
--
--   [2] L'IVA applicata due volte. I prezzi Umbria Hub sono FINALI e LORDI:
--       l'imposta e dentro. `logistics_shipping_rates.vat_bps` ha default
--       2200, quindi materializzare una di queste tariffe senza azzerare
--       esplicitamente IVA e fuel la riapplicherebbe, e il difetto non
--       somiglierebbe a un difetto: sarebbe un prezzo del 22% piu alto, con
--       l'aria di essere giusto. I casi 11-13 provano la conversione unica e
--       portano un controllo che mostra il numero sbagliato, perche
--       un'asserzione che non sa riconoscere l'errore non e una prova.
--
--   [3] La confusione fra costo di acquisto e contributo della transazione.
--       Il contributo del cartone da sei e 609; il primo scaglione dello
--       stesso cartone nel listino Vigoroso e 369; e 369 e anche il
--       contributo del formato da DUE bottiglie. Tre numeri, due domini, una
--       coincidenza. Il caso 32 tiene i domini separati dal lato di WP6C,
--       come la 12p lo fa dal lato dell'approvvigionamento.
--
-- PERCHE I CONTEGGI A ZERO NON BASTANO DA SOLI. Mezza griglia afferma assenze
-- — zero reti, zero punti, zero rotte, zero tariffe a 12 bottiglie — e una
-- assenza passa anche su un database dove la migrazione non e mai girata. Il
-- guard di preparazione qui sotto rifiuta quel caso: se la configurazione
-- WP6C non c'e, la griglia si ferma invece di stampare trenta PASS vuoti.
--
-- CHE COSA LA GRIGLIA NON PROVA. Non ripete la matrice di esposizione delle
-- diciassette tabelle `private.logistics_*`: quella e dei casi 1-18 della 12p
-- e WP6C non tocca nessun privilegio. Non prova PostgREST ne il browser.
-- Non chiama `private.logistics_home_pickup_deduzione_cents`, e il motivo e
-- esso stesso il contenuto del caso 24: quella funzione esige un piano con un
-- servizio ASSEGNATO, e il fail closed di WP6C rende l'assegnazione
-- impossibile. La deduzione viene percio derivata dalla configurazione con
-- l'aritmetica del dominio, che e cio che la specifica chiede — che i valori
-- DISCENDANO dalla config e non siano scritti come costanti.
--
-- NESSUN DATO INVENTATO. Qui non ci sono fixture: i numeri misurati sono i
-- numeri commerciali approvati, e il valore della griglia e proprio che un
-- prezzo sbagliato si veda confrontandola con il documento commerciale.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12q: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

-- Guard di preparazione: la griglia misura DATI APPLICATI. Senza di essi le
-- asserzioni di assenza passerebbero per vacuita, che e il modo piu elegante
-- di non provare niente.
do $$
declare v_serv integer; v_tar integer; v_contr integer;
begin
  select count(*) into v_serv
  from private.logistics_service_definitions
  where service_code = 'standard_beta' and effective_to is null;
  select count(*) into v_tar
  from private.logistics_commercial_rate_sources
  where service_code = 'standard_beta' and effective_to is null;
  select count(*) into v_contr
  from private.logistics_packaging_contributions where effective_to is null;
  if v_serv = 0 or v_tar = 0 or v_contr = 0 then
    raise exception
      'Guard 12q: configurazione commerciale WP6C assente (servizi=%, tariffe=%, contributi=%). '
      'La griglia misura la migrazione 20261001150000 applicata; su un database '
      'senza quei dati le prove di assenza passerebbero per vacuita.',
      v_serv, v_tar, v_contr;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Strumenti della griglia
-- ---------------------------------------------------------------------------

create temp table esiti_12q (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12q (id, descrizione, passed, detail)
  values (p_id, p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

-- Il fatturabile corrente di una combinazione commerciale.
create function pg_temp.tar(p_provider text, p_formato text, p_cap text)
returns integer language sql stable as $f$
  select billable_cents from private.logistics_commercial_rate_sources
  where provider_code = p_provider
    and service_code = 'standard_beta'
    and packaging_format = p_formato
    and capability = p_cap
    and effective_to is null;
$f$;

-- Quanti servizi il motore dichiara compatibili per una rotta richiesta. Il
-- collo e minuscolo di proposito: 500 g e 10x10x10 cm passerebbero qualunque
-- limite reale, quindi un'esclusione non puo essere confusa con un pacco
-- fuori misura. Se questo numero diventasse diverso da zero, sarebbe perche
-- qualcuno ha aperto una delle cinque chiusure.
create function pg_temp.compat(p_cap text, p_formato text)
returns integer language sql stable as $f$
  select count(*)::integer
  from private.logistics_service_compatibili(
    p_cap, p_formato, null, 500, 100, 100, 100, 1000
  ) c
  where c.provider_code in ('inpost', 'sda', 'brt');
$f$;

-- Prezzo del pack come lo calcola il motore, non come lo racconta la griglia.
create function pg_temp.pack(p_code text, p_unita integer)
returns jsonb language sql stable as $f$
  select private.logistics_pack_prezzo(
    p_code,
    jsonb_build_array(
      jsonb_build_object('formato', 'bottiglia_1', 'quantita', p_unita)
    )
  );
$f$;

-- Unit economics come le riferisce la funzione del dominio.
create function pg_temp.econ(p_formato text, p_provider text, p_cap text)
returns jsonb language sql stable as $f$
  select private.logistics_unit_economics(
    p_formato, p_provider, 'standard_beta', p_cap
  );
$f$;

create function pg_temp.i(p_j jsonb, p_k text) returns integer language sql immutable as $f$
  select nullif(p_j ->> p_k, '')::integer;
$f$;

create function pg_temp.b(p_j jsonb, p_k text) returns boolean language sql immutable as $f$
  select nullif(p_j ->> p_k, '')::boolean;
$f$;

-- ---------------------------------------------------------------------------
-- Sezione A/B — Servizi e capability come configurazione
-- ---------------------------------------------------------------------------

-- I tre servizi esistono come riga corrente, uno per provider, con lo stesso
-- codice di servizio: il codice e un dato, non un ramo di codice.
do $$
declare v_n integer; v_prov text;
begin
  select count(*), string_agg(provider_code, ',' order by provider_code)
  into v_n, v_prov
  from private.logistics_service_definitions
  where service_code = 'standard_beta' and service_level = 'standard'
    and effective_to is null;
  perform pg_temp.registra(1,
    'Tre servizi Beta correnti, uno per provider, sotto lo stesso codice di servizio',
    v_n = 3 and v_prov = 'brt,inpost,sda',
    'n=' || v_n::text || ' provider=' || coalesce(v_prov, 'nessuno'));
end $$;

-- I cinque limiti operativi restano NULL. Un limite assente non significa
-- «illimitato»: e la ragione per cui il motore esclude, ed e l'unico modo
-- onesto di dire che la fascia reale non la conosciamo.
do $$
declare v_con_limiti integer; v_dettaglio text;
begin
  select count(*) into v_con_limiti
  from private.logistics_service_definitions
  where service_code = 'standard_beta' and effective_to is null
    and (max_weight_g is not null or max_length_mm is not null
      or max_width_mm is not null or max_height_mm is not null
      or max_volume_cm3 is not null);
  select string_agg(provider_code || '=' || (
    case when max_weight_g is null then 'null' else max_weight_g::text end
  ), ',' order by provider_code) into v_dettaglio
  from private.logistics_service_definitions
  where service_code = 'standard_beta' and effective_to is null;
  perform pg_temp.registra(2,
    'Nessun limite operativo inventato: peso, tre dimensioni e volume restano NULL su tutti i servizi',
    v_con_limiti = 0,
    'servizi_con_limiti=' || v_con_limiti::text || ' peso=' || coalesce(v_dettaglio, 'nessuno'));
end $$;

-- Idoneita operativa e attivazione sono due interruttori distinti e sono
-- entrambi chiusi. La nota non e ornamento: dice cosa manca a chi leggera la
-- tabella fra sei mesi, ed e la differenza fra una bozza voluta e una
-- dimenticanza.
do $$
declare v_idonei integer; v_attivi integer; v_senza_nota integer;
begin
  select
    count(*) filter (where operational_eligibility),
    count(*) filter (where active),
    count(*) filter (where coalesce(length(eligibility_note), 0) < 40)
  into v_idonei, v_attivi, v_senza_nota
  from private.logistics_service_definitions
  where service_code = 'standard_beta' and effective_to is null;
  perform pg_temp.registra(3,
    'Idoneita operativa e attivazione sono entrambe chiuse, e ogni servizio dichiara cosa gli manca',
    v_idonei = 0 and v_attivi = 0 and v_senza_nota = 0,
    'idonei=' || v_idonei::text || ' attivi=' || v_attivi::text
      || ' senza_nota=' || v_senza_nota::text);
end $$;

-- I cinque formati della Beta, e nessun dodici: il formato da 12 bottiglie
-- non e Standard Beta, e la sua assenza qui e coerente con l'assenza di una
-- sua tariffa.
do $$
declare v_fuori integer; v_dodici integer; v_formati text;
begin
  select count(*) into v_fuori
  from private.logistics_service_definitions
  where service_code = 'standard_beta' and effective_to is null
    and not (eligible_packaging_formats @> array[
      'bottiglia_1', 'bottiglia_2', 'bottiglia_3', 'bottiglia_6', 'magnum_1_5l'
    ]::text[]
    and cardinality(eligible_packaging_formats) = 5);
  select count(*) into v_dodici
  from private.logistics_service_definitions
  where service_code = 'standard_beta' and effective_to is null
    and 'bottiglia_12' = any (eligible_packaging_formats);
  select array_to_string(eligible_packaging_formats, '+') into v_formati
  from private.logistics_service_definitions
  where provider_code = 'inpost' and service_code = 'standard_beta'
    and effective_to is null;
  perform pg_temp.registra(4,
    'Ogni servizio ammette esattamente i cinque formati della Beta e nessun formato da dodici',
    v_fuori = 0 and v_dodici = 0,
    'fuori_insieme=' || v_fuori::text || ' con_dodici=' || v_dodici::text
      || ' inpost=' || coalesce(v_formati, 'nessuno'));
end $$;

-- Allowlist di SKU vuota: significa «nessun vincolo di SKU», non «nessuno
-- SKU ammesso». Averla non vuota qui restringerebbe in silenzio la Beta a un
-- sottoinsieme di cartoni.
do $$
declare v_con_skus integer;
begin
  select count(*) into v_con_skus
  from private.logistics_service_definitions
  where service_code = 'standard_beta' and effective_to is null
    and cardinality(eligible_packaging_skus) > 0;
  perform pg_temp.registra(5,
    'Nessun vincolo di SKU: l''allowlist resta vuota su tutti i servizi Beta',
    v_con_skus = 0,
    'servizi_con_allowlist=' || v_con_skus::text);
end $$;

-- La matrice esatta. Nessuna capability e implicita: SDA ne dichiara due e le
-- dichiara con due righe, non con una riga «abilitante».
do $$
declare v_n integer; v_matrice text;
begin
  select count(*) into v_n
  from private.logistics_service_capabilities cap
  join private.logistics_service_definitions s on s.id = cap.service_definition_id
  where s.service_code = 'standard_beta' and s.effective_to is null;
  select string_agg(s.provider_code || ':' || cap.capability, ','
    order by s.provider_code, cap.capability) into v_matrice
  from private.logistics_service_capabilities cap
  join private.logistics_service_definitions s on s.id = cap.service_definition_id
  where s.service_code = 'standard_beta' and s.effective_to is null;
  perform pg_temp.registra(6,
    'Matrice delle capability esatta: InPost P2P, SDA P2P e H2P, BRT H2P, quattro righe dichiarate',
    v_n = 4 and v_matrice = 'brt:HOME_TO_PUDO,inpost:PUDO_TO_PUDO,'
      || 'sda:HOME_TO_PUDO,sda:PUDO_TO_PUDO',
    'n=' || v_n::text || ' matrice=' || coalesce(v_matrice, 'nessuna'));
end $$;

-- PUDO_TO_HOME non e configurata, e l'assenza della riga e il modo corretto
-- di dirlo: non un divieto scritto nel motore, che domani andrebbe rimosso a
-- mano per ammettere una consegna a domicilio decisa dal prodotto.
do $$
declare v_n integer;
begin
  select count(*) into v_n
  from private.logistics_service_capabilities cap
  join private.logistics_service_definitions s on s.id = cap.service_definition_id
  where s.service_code = 'standard_beta' and s.effective_to is null
    and cap.capability = 'PUDO_TO_HOME';
  perform pg_temp.registra(7,
    'Nessuna capability PUDO_TO_HOME configurata per la Beta',
    v_n = 0, 'righe=' || v_n::text);
end $$;

do $$
declare v_n integer;
begin
  select count(*) into v_n
  from private.logistics_service_capabilities cap
  join private.logistics_service_definitions s on s.id = cap.service_definition_id
  where s.service_code = 'standard_beta' and s.effective_to is null
    and cap.capability = 'HOME_TO_HOME';
  perform pg_temp.registra(8,
    'Nessuna capability HOME_TO_HOME configurata per la Beta',
    v_n = 0, 'righe=' || v_n::text);
end $$;

-- ---------------------------------------------------------------------------
-- Sezione C — Sorgente commerciale delle tariffe
-- ---------------------------------------------------------------------------

-- Venti righe correnti, tutte in `preactivation`. Lo stato e da solo una
-- delle cinque chiusure: il motore esige `active`.
do $$
declare v_n integer; v_stati text; v_etichette integer;
begin
  select count(*) into v_n
  from private.logistics_commercial_rate_sources
  where service_code = 'standard_beta' and effective_to is null;
  select string_agg(distinct status, ',' order by status) into v_stati
  from private.logistics_commercial_rate_sources
  where service_code = 'standard_beta' and effective_to is null;
  select count(*) into v_etichette
  from private.logistics_commercial_rate_sources
  where service_code = 'standard_beta' and effective_to is null
    and source_label like 'Umbria Hub%';
  perform pg_temp.registra(9,
    'Venti tariffe commerciali correnti, tutte in preattivazione e tutte attribuite alla sorgente',
    v_n = 20 and v_stati = 'preactivation' and v_etichette = 20,
    'n=' || v_n::text || ' stati=' || coalesce(v_stati, 'nessuno')
      || ' etichettate=' || v_etichette::text);
end $$;

-- Le combinazioni sono ESATTAMENTE quelle approvate, con i loro fatturabili.
-- Una sola riga in piu o in meno, o un centesimo diverso, cambia questa
-- impronta: e l'asserzione che rende inutile fidarsi delle altre.
do $$
declare v_impronta text; v_atteso text;
begin
  select string_agg(
    packaging_format || '/' || capability || '/' || provider_code
      || '=' || billable_cents::text,
    ' ' order by packaging_format, capability, provider_code)
  into v_impronta
  from private.logistics_commercial_rate_sources
  where service_code = 'standard_beta' and effective_to is null;
  v_atteso :=
    'bottiglia_1/HOME_TO_PUDO/brt=594 bottiglia_1/HOME_TO_PUDO/sda=621 '
    'bottiglia_1/PUDO_TO_PUDO/inpost=415 bottiglia_1/PUDO_TO_PUDO/sda=513 '
    'bottiglia_2/HOME_TO_PUDO/brt=796 bottiglia_2/HOME_TO_PUDO/sda=621 '
    'bottiglia_2/PUDO_TO_PUDO/inpost=422 bottiglia_2/PUDO_TO_PUDO/sda=642 '
    'bottiglia_3/HOME_TO_PUDO/brt=796 bottiglia_3/HOME_TO_PUDO/sda=621 '
    'bottiglia_3/PUDO_TO_PUDO/inpost=422 bottiglia_3/PUDO_TO_PUDO/sda=642 '
    'bottiglia_6/HOME_TO_PUDO/brt=1129 bottiglia_6/HOME_TO_PUDO/sda=833 '
    'bottiglia_6/PUDO_TO_PUDO/inpost=422 bottiglia_6/PUDO_TO_PUDO/sda=650 '
    'magnum_1_5l/HOME_TO_PUDO/brt=630 magnum_1_5l/HOME_TO_PUDO/sda=621 '
    'magnum_1_5l/PUDO_TO_PUDO/inpost=422 magnum_1_5l/PUDO_TO_PUDO/sda=513';
  perform pg_temp.registra(10,
    'Le venti combinazioni formato/capability/provider e i loro fatturabili sono esattamente quelli approvati',
    v_impronta = v_atteso,
    'impronta=' || coalesce(v_impronta, 'nessuna'));
end $$;

-- Il valore di origine resta ESATTO. 5,9405 EUR non e 5,94 EUR: la frazione
-- si perderebbe per sempre se tenessimo solo i centesimi, e con essa la
-- possibilita di ricontrollare la trattativa.
do $$
declare v_brt1 bigint; v_brt2 bigint; v_brt6 bigint; v_brtm bigint; v_troncati integer;
begin
  select source_gross_micros into v_brt1 from private.logistics_commercial_rate_sources
  where provider_code = 'brt' and packaging_format = 'bottiglia_1'
    and capability = 'HOME_TO_PUDO' and effective_to is null;
  select source_gross_micros into v_brt2 from private.logistics_commercial_rate_sources
  where provider_code = 'brt' and packaging_format = 'bottiglia_2'
    and capability = 'HOME_TO_PUDO' and effective_to is null;
  select source_gross_micros into v_brt6 from private.logistics_commercial_rate_sources
  where provider_code = 'brt' and packaging_format = 'bottiglia_6'
    and capability = 'HOME_TO_PUDO' and effective_to is null;
  select source_gross_micros into v_brtm from private.logistics_commercial_rate_sources
  where provider_code = 'brt' and packaging_format = 'magnum_1_5l'
    and capability = 'HOME_TO_PUDO' and effective_to is null;
  -- Un micros gia arrotondato al centesimo avrebbe perso la frazione in
  -- ingresso: nessuna delle quattro tariffe frazionarie deve essere tonda.
  select count(*) into v_troncati
  from private.logistics_commercial_rate_sources
  where service_code = 'standard_beta' and effective_to is null
    and provider_code = 'brt' and source_gross_micros % 10000 = 0;
  perform pg_temp.registra(11,
    'Il valore di origine conserva la frazione sotto il centesimo che i prezzi BRT portano',
    v_brt1 = 5940500 and v_brt2 = 7960270 and v_brt6 = 11286950 and v_brtm = 6296930
      and v_troncati = 0,
    'brt=' || coalesce(v_brt1::text, 'null') || '/' || coalesce(v_brt2::text, 'null')
      || '/' || coalesce(v_brt6::text, 'null') || '/' || coalesce(v_brtm::text, 'null')
      || ' tondi=' || v_troncati::text);
end $$;

-- Arrotondamento HALF-UP applicato UNA SOLA VOLTA. Non e una dichiarazione:
-- il CHECK `logistics_commercial_rate_sources_arrotondamento` ricalcola il
-- fatturabile con la funzione del dominio e rifiuta la riga se divergono,
-- quindi qui si verifica che il CHECK sia davvero quello e che le undici
-- conversioni distinte siano le attese.
do $$
declare v_divergenti integer; v_distinte text;
begin
  select count(*) into v_divergenti
  from private.logistics_commercial_rate_sources
  where service_code = 'standard_beta' and effective_to is null
    and billable_cents <> private.logistics_micros_to_cents(source_gross_micros);
  select string_agg(distinct billable_cents::text, ',' order by billable_cents::text)
  into v_distinte
  from private.logistics_commercial_rate_sources
  where service_code = 'standard_beta' and effective_to is null;
  perform pg_temp.registra(12,
    'Ogni fatturabile e l''arrotondamento HALF-UP del valore di origine, applicato una sola volta',
    v_divergenti = 0
      and v_distinte = '1129,415,422,513,594,621,630,642,650,796,833',
    'divergenti=' || v_divergenti::text || ' distinti=' || coalesce(v_distinte, 'nessuno'));
end $$;

-- Nessuna seconda IVA, e con un controllo che mostra il numero sbagliato.
-- `logistics_shipping_rates.vat_bps` ha default 2200: materializzare una di
-- queste tariffe senza azzerare IVA e fuel produrrebbe 506 centesimi al posto
-- di 415, con l'aria di essere giusto. Il listino operativo resta percio
-- vuoto, e questo caso prova sia il fatto sia la propria capacita di vedere
-- l'errore.
do $$
declare v_415 integer; v_doppia integer; v_wp6a integer;
begin
  v_415 := pg_temp.tar('inpost', 'bottiglia_1', 'PUDO_TO_PUDO');
  v_doppia := private.logistics_micros_to_cents(
    (select source_gross_micros * 122 / 100
     from private.logistics_commercial_rate_sources
     where provider_code = 'inpost' and packaging_format = 'bottiglia_1'
       and capability = 'PUDO_TO_PUDO' and effective_to is null));
  select count(*) into v_wp6a
  from private.logistics_shipping_rates
  where service_code = 'standard_beta'
     or provider_code in ('inpost', 'sda', 'brt');
  perform pg_temp.registra(13,
    'I prezzi sono finali: l''IVA non viene riapplicata e nessuna tariffa operativa li materializza',
    v_415 = 415 and v_doppia = 506 and v_415 <> v_doppia and v_wp6a = 0,
    'fatturabile=' || coalesce(v_415::text, 'null')
      || ' con_iva_doppia=' || coalesce(v_doppia::text, 'null')
      || ' tariffe_wp6a=' || v_wp6a::text);
end $$;

-- Nessuna tariffa Standard Beta per il formato da dodici bottiglie. Non e una
-- dimenticanza: non e un formato della Beta, e l'assenza e la forma corretta
-- della decisione.
do $$
declare v_tariffe integer; v_contr integer; v_item text;
begin
  select count(*) into v_tariffe
  from private.logistics_commercial_rate_sources
  where service_code = 'standard_beta' and packaging_format = 'bottiglia_12'
    and effective_to is null;
  select count(*) into v_contr
  from private.logistics_packaging_contributions
  where packaging_format = 'bottiglia_12' and effective_to is null;
  select case when beta_standard then 'standard' else 'fuori_beta' end into v_item
  from private.logistics_packaging_supplier_items
  where supplier_sku = 'TRIPLEX12-A' and effective_to is null;
  perform pg_temp.registra(14,
    'Il formato da dodici bottiglie non ha tariffa Beta, non ha contributo e resta fuori dallo standard',
    v_tariffe = 0 and v_contr = 0 and v_item = 'fuori_beta',
    'tariffe=' || v_tariffe::text || ' contributi=' || v_contr::text
      || ' articolo=' || coalesce(v_item, 'assente'));
end $$;

-- ---------------------------------------------------------------------------
-- Sezione N/O — Contributi e soglia di unit economics
-- ---------------------------------------------------------------------------

do $$
declare v_n integer; v_righe text; v_stati text;
begin
  select count(*) into v_n
  from private.logistics_packaging_contributions where effective_to is null;
  select string_agg(packaging_format || '=' || contribution_cents::text,
    ',' order by packaging_format) into v_righe
  from private.logistics_packaging_contributions where effective_to is null;
  select string_agg(distinct status, ',' order by status) into v_stati
  from private.logistics_packaging_contributions where effective_to is null;
  perform pg_temp.registra(15,
    'I cinque contributi di imballaggio approvati sono correnti e attivi',
    v_n = 5 and v_stati = 'active'
      and v_righe = 'bottiglia_1=319,bottiglia_2=369,bottiglia_3=379,'
        || 'bottiglia_6=609,magnum_1_5l=509',
    'n=' || v_n::text || ' stati=' || coalesce(v_stati, 'nessuno')
      || ' righe=' || coalesce(v_righe, 'nessuna'));
end $$;

-- La soglia e una guardia OSSERVABILE, non un rifiuto: una riga corrente,
-- attiva, a 1500. L'indice di unicita ammette una sola riga corrente, e
-- questo caso lo verifica invece di assumerlo.
do $$
declare v_n integer; v_target integer; v_attiva boolean;
begin
  select count(*) into v_n
  from private.logistics_unit_economics_config where effective_to is null;
  select target_cents, active into v_target, v_attiva
  from private.logistics_unit_economics_config where effective_to is null;
  perform pg_temp.registra(16,
    'Una sola soglia di unit economics corrente, attiva, a 1500 centesimi IVA inclusa',
    v_n = 1 and v_target = 1500 and v_attiva,
    'n=' || v_n::text || ' target=' || coalesce(v_target::text, 'null')
      || ' attiva=' || coalesce(v_attiva::text, 'null'));
end $$;

-- ---------------------------------------------------------------------------
-- Sezione P/Q/R — Vinea Pack
-- ---------------------------------------------------------------------------

do $$
declare v_n integer; v_righe text; v_inattivi integer;
begin
  select count(*) into v_n
  from private.logistics_pack_catalog
  where pack_code in ('single', 'pack_5', 'pack_10', 'pack_20')
    and effective_to is null;
  select string_agg(pack_code || '=' || total_units::text, ',' order by total_units)
  into v_righe
  from private.logistics_pack_catalog
  where pack_code in ('single', 'pack_5', 'pack_10', 'pack_20')
    and effective_to is null;
  select count(*) into v_inattivi
  from private.logistics_pack_catalog
  where pack_code in ('single', 'pack_5', 'pack_10', 'pack_20')
    and effective_to is null and not active;
  perform pg_temp.registra(17,
    'Catalogo del Vinea Pack: quattro tagli attivi da 1, 5, 10 e 20 unita',
    v_n = 4 and v_inattivi = 0
      and v_righe = 'single=1,pack_5=5,pack_10=10,pack_20=20',
    'n=' || v_n::text || ' righe=' || coalesce(v_righe, 'nessuna')
      || ' inattivi=' || v_inattivi::text);
end $$;

-- Nessun pack da dodici unita: il catalogo commerciale non reintroduce di
-- lato il formato che la Beta non serve.
do $$
declare v_n integer;
begin
  select count(*) into v_n
  from private.logistics_pack_catalog
  where effective_to is null and total_units = 12;
  perform pg_temp.registra(18,
    'Nessun pack da dodici unita rientra dal catalogo commerciale',
    v_n = 0, 'pack_da_dodici=' || v_n::text);
end $$;

-- WP6C NON duplica la configurazione di prezzo del pack: era gia corrente da
-- WP6B e una seconda riga violerebbe l'indice di unicita. Il 5% vive qui e
-- solo qui.
do $$
declare v_n integer; v_cfg text;
begin
  select count(*) into v_n
  from private.logistics_pack_pricing_config where effective_to is null;
  select base_buffer_bps::text || '/' || under_10_surcharge_bps::text || '/'
    || mono_format_surcharge_bps::text || '/' || single_floor_cents::text
  into v_cfg
  from private.logistics_pack_pricing_config where effective_to is null;
  perform pg_temp.registra(19,
    'Una sola configurazione di prezzo del pack corrente, ancora 500/1000/1000/1000',
    v_n = 1 and v_cfg = '500/1000/1000/1000',
    'n=' || v_n::text || ' config=' || coalesce(v_cfg, 'nessuna'));
end $$;

-- Il kit di imballaggio e una stima di PIANIFICAZIONE, e lo stato lo dice nel
-- dato: 550 centesimi che non sono una tariffa corriere e non entrano in
-- nessuna rotta.
do $$
declare v_n integer; v_amount integer; v_stato text;
begin
  select count(*) into v_n
  from private.logistics_pack_kit_shipping where effective_to is null;
  select amount_cents, status into v_amount, v_stato
  from private.logistics_pack_kit_shipping where effective_to is null;
  perform pg_temp.registra(20,
    'Spedizione del kit: una riga corrente, 550 centesimi, dichiarata di pianificazione',
    v_n = 1 and v_amount = 550 and v_stato = 'planning',
    'n=' || v_n::text || ' importo=' || coalesce(v_amount::text, 'null')
      || ' stato=' || coalesce(v_stato, 'nessuno'));
end $$;

-- I quattro override agganciano la FIRMA CANONICA della composizione, non una
-- formattazione: la firma la calcola la stessa funzione che il motore usa a
-- runtime, quindi `bottiglia_1:5` vale comunque la composizione sia scritta.
do $$
declare v_n integer; v_righe text; v_stati text;
begin
  select count(*) into v_n
  from private.logistics_pack_price_overrides
  where pack_code in ('single', 'pack_5', 'pack_10', 'pack_20')
    and effective_to is null;
  select string_agg(pack_code || '[' || composition_signature || ']='
    || price_cents::text, ',' order by price_cents) into v_righe
  from private.logistics_pack_price_overrides
  where pack_code in ('single', 'pack_5', 'pack_10', 'pack_20')
    and effective_to is null;
  select string_agg(distinct status, ',' order by status) into v_stati
  from private.logistics_pack_price_overrides
  where pack_code in ('single', 'pack_5', 'pack_10', 'pack_20')
    and effective_to is null;
  perform pg_temp.registra(21,
    'Quattro prezzi di catalogo attivi, agganciati alla firma canonica mono-formato da una bottiglia',
    v_n = 4 and v_stati = 'active'
      and v_righe = 'single[bottiglia_1:1]=1000,pack_5[bottiglia_1:5]=2190,'
        || 'pack_10[bottiglia_1:10]=3190,pack_20[bottiglia_1:20]=5390',
    'n=' || v_n::text || ' stati=' || coalesce(v_stati, 'nessuno')
      || ' righe=' || coalesce(v_righe, 'nessuna'));
end $$;

-- Il prezzo esposto DISCENDE dalla configurazione, e discende dall'override:
-- il motore calcola la regola, l'override vince, e i due numeri sono diversi
-- su tre tagli su quattro. Se l'override non fosse applicato, il pack da
-- cinque costerebbe 1994 invece di 2190 — ed e per questo che non basta
-- leggere il prezzo finale: va letto accanto alla regola che ha scavalcato.
do $$
declare
  v1 jsonb; v5 jsonb; v10 jsonb; v20 jsonb;
  v_prezzi text; v_regole text; v_override boolean;
begin
  v1 := pg_temp.pack('single', 1);
  v5 := pg_temp.pack('pack_5', 5);
  v10 := pg_temp.pack('pack_10', 10);
  v20 := pg_temp.pack('pack_20', 20);
  v_prezzi := concat_ws(',',
    pg_temp.i(v1, 'priceCents'), pg_temp.i(v5, 'priceCents'),
    pg_temp.i(v10, 'priceCents'), pg_temp.i(v20, 'priceCents'));
  v_regole := concat_ws(',',
    pg_temp.i(v1, 'ruleCents'), pg_temp.i(v5, 'ruleCents'),
    pg_temp.i(v10, 'ruleCents'), pg_temp.i(v20, 'ruleCents'));
  v_override := pg_temp.b(v1, 'overrideApplied') and pg_temp.b(v5, 'overrideApplied')
    and pg_temp.b(v10, 'overrideApplied') and pg_temp.b(v20, 'overrideApplied');
  perform pg_temp.registra(22,
    'Il prezzo del pack emerge dalla config: l''override vince sulla regola, che resta visibile e diversa',
    v_prezzi = '1000,2190,3190,5390' and v_regole = '399,1994,3669,7337'
      and v_override,
    'prezzi=' || coalesce(v_prezzi, 'nessuno') || ' regole=' || coalesce(v_regole, 'nessuna')
      || ' override=' || coalesce(v_override::text, 'null'));
end $$;

-- ---------------------------------------------------------------------------
-- Economia derivata dalla configurazione
-- ---------------------------------------------------------------------------

-- I totali InPost non sono scritti da nessuna parte: li compone la funzione
-- del dominio leggendo contributo corrente e tariffa corrente. Tutti sotto la
-- soglia, e la soglia la legge dalla config anche lei.
do $$
declare
  v_tot text; v_entro boolean; v_target text;
begin
  select
    string_agg(pg_temp.i(e.j, 'totalCents')::text, ',' order by e.ord),
    bool_and(pg_temp.b(e.j, 'withinTarget')),
    string_agg(distinct pg_temp.i(e.j, 'targetCents')::text, ',')
  into v_tot, v_entro, v_target
  from (
    values
      (1, pg_temp.econ('bottiglia_1', 'inpost', 'PUDO_TO_PUDO')),
      (2, pg_temp.econ('bottiglia_2', 'inpost', 'PUDO_TO_PUDO')),
      (3, pg_temp.econ('bottiglia_3', 'inpost', 'PUDO_TO_PUDO')),
      (4, pg_temp.econ('bottiglia_6', 'inpost', 'PUDO_TO_PUDO')),
      (5, pg_temp.econ('magnum_1_5l', 'inpost', 'PUDO_TO_PUDO'))
  ) as e (ord, j);
  perform pg_temp.registra(23,
    'Unit economics InPost PUDO->PUDO: 734, 791, 801, 1031, 931, tutte entro la soglia configurata',
    v_tot = '734,791,801,1031,931' and v_entro and v_target = '1500',
    'totali=' || coalesce(v_tot, 'nessuno') || ' entro=' || coalesce(v_entro::text, 'null')
      || ' target=' || coalesce(v_target, 'nessuno'));
end $$;

-- Il fallback SDA costa piu di InPost e resta comunque sotto la soglia: e il
-- numero che conta, perche una rotta si giudica sul suo peggiore ammesso e non
-- sul suo migliore.
do $$
declare v_tot text; v_entro boolean;
begin
  select
    string_agg(pg_temp.i(e.j, 'totalCents')::text, ',' order by e.ord),
    bool_and(pg_temp.b(e.j, 'withinTarget'))
  into v_tot, v_entro
  from (
    values
      (1, pg_temp.econ('bottiglia_1', 'sda', 'PUDO_TO_PUDO')),
      (2, pg_temp.econ('bottiglia_2', 'sda', 'PUDO_TO_PUDO')),
      (3, pg_temp.econ('bottiglia_3', 'sda', 'PUDO_TO_PUDO')),
      (4, pg_temp.econ('bottiglia_6', 'sda', 'PUDO_TO_PUDO')),
      (5, pg_temp.econ('magnum_1_5l', 'sda', 'PUDO_TO_PUDO'))
  ) as e (ord, j);
  perform pg_temp.registra(24,
    'Unit economics del fallback SDA: 832, 1011, 1021, 1259, 1022, tutte entro la soglia',
    v_tot = '832,1011,1021,1259,1022' and v_entro,
    'totali=' || coalesce(v_tot, 'nessuno') || ' entro=' || coalesce(v_entro::text, 'null'));
end $$;

-- La deduzione del ritiro a domicilio e la differenza fra il minimo
-- HOME_TO_PUDO e il minimo PUDO_TO_PUDO dello stesso formato: quanto costa in
-- piu non portare il collo al punto.
--
-- Perche derivata e non chiesta alla funzione del dominio: la
-- `logistics_home_pickup_deduzione_cents` esige un piano con un servizio
-- ASSEGNATO, e il fail closed di WP6C rende l'assegnazione impossibile — e il
-- caso 28 a provarlo. Chiederglielo adesso misurerebbe il fail closed una
-- seconda volta, non la deduzione. Questi cinque numeri non sono percio
-- scritti come costanti nel dominio: discendono dalla sola configurazione
-- caricata, e cambiano con essa.
do $$
declare v_ded text;
begin
  select string_agg(d.formato || '=' || (d.h2p - d.p2p)::text, ',' order by d.formato)
  into v_ded
  from (
    select
      packaging_format as formato,
      min(billable_cents) filter (where capability = 'HOME_TO_PUDO') as h2p,
      min(billable_cents) filter (where capability = 'PUDO_TO_PUDO') as p2p
    from private.logistics_commercial_rate_sources
    where service_code = 'standard_beta' and effective_to is null
    group by packaging_format
  ) d;
  perform pg_temp.registra(25,
    'La deduzione del ritiro a domicilio discende dal listino: 179, 199, 199, 411, 199',
    v_ded = 'bottiglia_1=179,bottiglia_2=199,bottiglia_3=199,'
      || 'bottiglia_6=411,magnum_1_5l=199',
    'deduzioni=' || coalesce(v_ded, 'nessuna'));
end $$;

-- ---------------------------------------------------------------------------
-- Il fail closed, misurato dal lato del motore
-- ---------------------------------------------------------------------------

-- Nessuna rete PUDO e nessuna associazione servizio/rete: sono dati del
-- provider, hanno una scadenza, e non li abbiamo.
do $$
declare v_reti integer; v_assoc integer;
begin
  select count(*) into v_reti from private.logistics_pudo_networks;
  select count(*) into v_assoc from private.logistics_service_pudo_networks;
  perform pg_temp.registra(26,
    'Nessuna rete PUDO e nessuna associazione servizio/rete sono state inventate',
    v_reti = 0 and v_assoc = 0,
    'reti=' || v_reti::text || ' associazioni=' || v_assoc::text);
end $$;

-- Nessun punto di ritiro e nessuna coordinata: un punto inventato produce una
-- rotta apparentemente valida verso un indirizzo che non esiste, ed e il
-- danno peggiore che questo dominio sa fare.
do $$
declare v_punti integer;
begin
  select count(*) into v_punti from private.logistics_pickup_points;
  perform pg_temp.registra(27,
    'Nessun punto di ritiro e nessuna coordinata sono state inventate',
    v_punti = 0, 'punti=' || v_punti::text);
end $$;

-- IL CASO CENTRALE. Si chiede al motore una rotta per ognuna delle dieci
-- combinazioni capability/formato che la configurazione commerciale copre, con
-- un collo talmente piccolo che nessun limite reale lo escluderebbe. La
-- risposta e zero: la configurazione e caricata e la rotta non c'e.
do $$
declare v_tot integer := 0; v_dett text := ''; v_n integer; r record;
begin
  for r in
    select distinct capability, packaging_format
    from private.logistics_commercial_rate_sources
    where service_code = 'standard_beta' and effective_to is null
    order by capability, packaging_format
  loop
    v_n := pg_temp.compat(r.capability, r.packaging_format);
    v_tot := v_tot + v_n;
    v_dett := v_dett || r.capability || '/' || r.packaging_format || '='
      || v_n::text || ' ';
  end loop;
  perform pg_temp.registra(28,
    'Il motore non assegna nessun servizio su nessuna delle dieci rotte commerciali configurate',
    v_tot = 0, 'compatibili_totali=' || v_tot::text || ' dettaglio=' || v_dett);
end $$;

-- E le due capability NON configurate restano chiuse per una ragione
-- indipendente: non esiste la riga che le dichiari. Due lucchetti diversi
-- sulla stessa porta, ed e giusto che siano due.
do $$
declare v_tot integer := 0; r record;
begin
  for r in
    select c.cap, f.formato
    from (values ('PUDO_TO_HOME'), ('HOME_TO_HOME')) as c (cap)
    cross join (values
      ('bottiglia_1'), ('bottiglia_2'), ('bottiglia_3'),
      ('bottiglia_6'), ('magnum_1_5l')
    ) as f (formato)
  loop
    v_tot := v_tot + pg_temp.compat(r.cap, r.formato);
  end loop;
  perform pg_temp.registra(29,
    'Consegna a domicilio e domicilio-domicilio restano chiuse perche nessuna capability le dichiara',
    v_tot = 0, 'compatibili_totali=' || v_tot::text);
end $$;

-- ---------------------------------------------------------------------------
-- Invarianti che WP6C non deve avere toccato
-- ---------------------------------------------------------------------------

-- Il buffer di WP6A resta a zero. Il 5% del Vinea Pack gli somiglia e vive in
-- un'altra tabella: portarlo qui per somiglianza rincarerebbe ogni preventivo
-- logistico del marketplace.
do $$
declare v_n integer; v_bps integer; v_fisso integer;
begin
  select count(*) into v_n
  from private.logistics_quote_config where effective_to is null;
  select buffer_bps, buffer_fixed_cents into v_bps, v_fisso
  from private.logistics_quote_config where effective_to is null;
  perform pg_temp.registra(30,
    'Il buffer di preventivo di WP6A resta a zero: il 5% e solo del Vinea Pack',
    v_n = 1 and v_bps = 0 and v_fisso = 0,
    'n=' || v_n::text || ' bps=' || coalesce(v_bps::text, 'null')
      || ' fisso=' || coalesce(v_fisso::text, 'null'));
end $$;

-- La commissione di marketplace e un altro dominio e un'altra autorita: resta
-- a 800 bps, e resta FUORI dal conto di unit economics.
do $$
declare v_n integer; v_bps integer;
begin
  select count(*) into v_n
  from public.marketplace_config where valida_fino is null;
  select margine_obiettivo_bps into v_bps
  from public.marketplace_config where valida_fino is null;
  perform pg_temp.registra(31,
    'La commissione di marketplace resta 800 bps, intatta e fuori dal conto di unit economics',
    v_n = 1 and v_bps = 800,
    'n=' || v_n::text || ' bps=' || coalesce(v_bps::text, 'null'));
end $$;

-- L'approvvigionamento Vigoroso e intatto, e i due domini si toccano nel
-- punto in cui e piu facile confonderli: il contributo del cartone da sei e
-- 609, il suo scaglione da cinquanta pezzi e 369, e quel 369 e invece il
-- contributo del formato da DUE bottiglie. Se qualcuno avesse fatto scrivere
-- a WP6C il listino del fornitore, il contributo da sei leggerebbe 369.
do $$
declare
  v_items integer; v_tier_righe integer; v_tier50 integer;
  v_c6 integer; v_c2 integer;
begin
  select count(*) into v_items
  from private.logistics_packaging_supplier_items where effective_to is null;
  select count(*) into v_tier_righe
  from private.logistics_packaging_supplier_price_tiers t
  join private.logistics_packaging_supplier_items i on i.id = t.supplier_item_id
  where t.effective_to is null and i.effective_to is null;
  select t.unit_net_cents into v_tier50
  from private.logistics_packaging_supplier_price_tiers t
  join private.logistics_packaging_supplier_items i on i.id = t.supplier_item_id
  where i.supplier_sku = 'TRIPLEX06-A' and t.min_quantity = 50
    and t.effective_to is null and i.effective_to is null;
  select contribution_cents into v_c6
  from private.logistics_packaging_contributions
  where packaging_format = 'bottiglia_6' and effective_to is null;
  select contribution_cents into v_c2
  from private.logistics_packaging_contributions
  where packaging_format = 'bottiglia_2' and effective_to is null;
  perform pg_temp.registra(32,
    'Il listino del fornitore e intatto e resta un dominio distinto dai contributi della transazione',
    v_items = 6 and v_tier_righe = 25 and v_tier50 = 369
      and v_c6 = 609 and v_c2 = 369,
    'articoli=' || v_items::text || ' scaglioni=' || v_tier_righe::text
      || ' tier50_sei=' || coalesce(v_tier50::text, 'null')
      || ' contributo_sei=' || coalesce(v_c6::text, 'null')
      || ' contributo_due=' || coalesce(v_c2::text, 'null'));
end $$;

-- ===========================================================================
-- Esito
-- ===========================================================================

select id, descrizione, passed, detail from esiti_12q order by id;

rollback;
