-- WI-016 D — Marketplace Monitor, Sentinel completo e porte del Founder Control Center.
--
-- Nulla viene acceso: monitor di mercato, lavori, fonti e agenti restano spenti; nessuna soglia commerciale è scelta.
--
--   * Marketplace Monitor: controlli deterministici che aprono REVISIONI, mai sanzioni: nessun utente sospeso, nessun
--     annuncio tolto, nessun rimborso o pagamento. La soglia di vendita apre una revisione e NON è una classificazione
--     fiscale. Solo conteggi, riferimenti agli annunci e (nel dominio, non nel bus) il venditore da rivedere.
--   * Sentinel: sorveglia anche sé stesso (scheduler fermo, lavori mancati, esecutori assenti, controlli esterni non
--     collegati), rileva il peggioramento e l'attesa di una P1 non presa in carico, e raggruppa ciò che nasce insieme.
--   * Control Center: porte solo admin. Dal web si può SOSPENDERE qualunque cosa e togliere una sospensione (con
--     autenticazione recente); non si accende nulla che il proprietario non abbia già acceso.

-- =============================================================================================
-- 1. Marketplace Monitor
-- =============================================================================================
create table brain.market_settings (
  singleton boolean primary key default true check (singleton),
  -- soglie anti-abuso tecniche; le soglie di VENDITA sono del founder (NULL = controllo spento)
  annunci_24h integer not null default 20 check (annunci_24h between 2 and 1000),
  fattore_prezzo_anomalo numeric(5, 2) not null default 4 check (fattore_prezzo_anomalo between 1.5 and 100),
  comparabili_minimi integer not null default 5 check (comparabili_minimi between 3 and 100),
  ripubblicazioni_30g integer not null default 5 check (ripubblicazioni_30g between 2 and 1000),
  ordini_stessa_coppia_30g integer not null default 5 check (ordini_stessa_coppia_30g between 2 and 1000),
  annullamenti_7g integer not null default 5 check (annullamenti_7g between 2 and 1000),
  vendite_revisione_365g integer check (vendite_revisione_365g between 1 and 100000),
  incasso_revisione_365g_cents bigint check (incasso_revisione_365g_cents between 100 and 100000000000),
  updated_at timestamptz not null default now(),
  updated_by text
);
insert into brain.market_settings default values;

create table brain.market_reviews (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('annunci_duplicati', 'pubblicazione_massiva', 'dati_incoerenti', 'prezzo_anomalo',
    'ripubblicazione_ripetuta', 'ordini_stessa_coppia', 'annullamenti_ripetuti', 'soglia_vendite')),
  subject_key text not null check (length(subject_key) between 3 and 160),
  -- dato personale nel dominio (mai nel bus append-only): cade con l'account
  seller_id uuid references public.profiles(id) on delete cascade,
  listing_ids uuid[] not null default '{}' check (cardinality(listing_ids) <= 10),
  evidence jsonb not null check (brain.payload_ammesso(evidence)),
  magnitude bigint not null check (magnitude >= 0),
  status text not null default 'aperta' check (status in ('aperta', 'in_revisione', 'chiusa_nessuna_azione', 'chiusa_segnalata')),
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  closed_magnitude bigint,
  note text check (note is null or length(note) <= 1000),
  decided_by text,
  decided_at timestamptz,
  unique (kind, subject_key)
);
create index market_reviews_status_idx on brain.market_reviews (status, last_seen_at desc);
create index market_reviews_seller_idx on brain.market_reviews (seller_id) where seller_id is not null;
alter table brain.market_settings enable row level security;
alter table brain.market_reviews enable row level security;
revoke all on brain.market_settings, brain.market_reviews
  from public, anon, authenticated, service_role, brain_worker, brain_ingest, brain_monitor_read;

-- Un reperto: una sola riga per soggetto. Chiusa senza azione, si riapre solo se il fenomeno CRESCE.
create or replace function brain.market_report(p_kind text, p_subject text, p_seller uuid, p_listings uuid[],
  p_magnitude bigint, p_evidence jsonb)
returns boolean language plpgsql volatile set search_path = '' as $$
declare v_new boolean;
begin
  insert into brain.market_reviews as r (kind, subject_key, seller_id, listing_ids, evidence, magnitude)
  values (p_kind, p_subject, p_seller, coalesce(p_listings[1:10], '{}'), p_evidence, p_magnitude)
  on conflict (kind, subject_key) do update
     set last_seen_at = clock_timestamp(), listing_ids = excluded.listing_ids, evidence = excluded.evidence,
         magnitude = excluded.magnitude,
         status = case when r.status like 'chiusa%' and excluded.magnitude > coalesce(r.closed_magnitude, 0)
                       then 'aperta' else r.status end
  returning (xmax = 0) into v_new;
  return v_new;
end;
$$;

create or replace function brain.market_scan(p_actor text)
returns jsonb language plpgsql volatile set search_path = '' as $$
declare
  s brain.market_settings%rowtype;
  r record;
  v_checks integer := 0;
  v_failed integer := 0;
  v_new integer := 0;
  v_seen integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_state text;
  v_check text;
begin
  if p_actor is null or length(btrim(p_actor)) = 0 then
    raise exception 'brain: serve un esecutore identificato' using errcode = '22023';
  end if;
  if not pg_try_advisory_xact_lock(hashtextextended('brain.market_scan', 0)) then
    return jsonb_build_object('esito', 'gia_in_corso');
  end if;
  select * into strict s from brain.market_settings;
  foreach v_check in array array['annunci_duplicati', 'pubblicazione_massiva', 'dati_incoerenti', 'prezzo_anomalo',
      'ripubblicazione_ripetuta', 'ordini_stessa_coppia', 'annullamenti_ripetuti', 'soglia_vendite'] loop
    v_checks := v_checks + 1;
    v_state := null;
    begin
      for r in
        select * from (
          -- stesso venditore, stesso vino, formato e prezzo in più annunci attivi (un lotto è UN annuncio)
          select 'venditore:' || l.seller_id::text || ':vino:' || b.wine_id::text || ':' || coalesce(b.formato, '') || ':'
                   || l.prezzo_cents::text as subject, l.seller_id as seller,
                 array_agg(l.id order by l.created_at) as listings, count(*)::bigint as magnitude,
                 jsonb_build_object('annunci', count(*)) as evidence
            from public.listings l join public.bottle_units b on b.id = l.bottle_unit_id
           where v_check = 'annunci_duplicati' and l.stato = 'attivo'
           group by l.seller_id, b.wine_id, b.formato, l.prezzo_cents having count(*) > 1
          union all
          select 'venditore:' || l.seller_id::text, l.seller_id, array_agg(l.id order by l.created_at desc), count(*)::bigint,
                 jsonb_build_object('annunci_24h', count(*), 'soglia', s.annunci_24h)
            from public.listings l
           where v_check = 'pubblicazione_massiva' and l.created_at > now() - interval '24 hours'
           group by l.seller_id having count(*) > s.annunci_24h
          union all
          select 'annuncio:' || l.id::text, l.seller_id, array[l.id], 1::bigint,
                 jsonb_build_object('annata_futura', (w.annata > extract(year from now())::integer)::integer,
                                    'prezzo_sotto_un_euro', (l.prezzo_cents < 100)::integer)
            from public.listings l join public.bottle_units b on b.id = l.bottle_unit_id join public.wines w on w.id = b.wine_id
           where v_check = 'dati_incoerenti' and l.stato = 'attivo'
             and (w.annata > extract(year from now())::integer or l.prezzo_cents < 100)
          union all
          -- confronto fra prezzi RICHIESTI dello stesso vino e formato, escluso l'annuncio stesso
          select 'annuncio:' || a.id::text, a.seller_id, array[a.id], 1::bigint,
                 jsonb_build_object('prezzo_cents', a.prezzo_cents, 'mediana_altri_cents', round(m.mediana),
                                    'comparabili', m.n, 'tipo', 'prezzi richiesti')
            from (select l.id, l.seller_id, l.prezzo_cents, b.wine_id, coalesce(b.formato, '') as formato
                    from public.listings l join public.bottle_units b on b.id = l.bottle_unit_id
                   where v_check = 'prezzo_anomalo' and l.stato = 'attivo') a
            cross join lateral (
                  select percentile_cont(0.5) within group (order by o.prezzo_cents) as mediana, count(*) as n
                    from public.listings o join public.bottle_units ob on ob.id = o.bottle_unit_id
                   where o.stato = 'attivo' and o.id <> a.id and o.seller_id <> a.seller_id and ob.wine_id = a.wine_id
                     and coalesce(ob.formato, '') = a.formato) m
           where m.n >= s.comparabili_minimi
             and (a.prezzo_cents > m.mediana * s.fattore_prezzo_anomalo or a.prezzo_cents < m.mediana / s.fattore_prezzo_anomalo)
          union all
          select 'venditore:' || l.seller_id::text || ':vino:' || b.wine_id::text, l.seller_id,
                 array_agg(l.id order by l.created_at desc), count(*)::bigint,
                 jsonb_build_object('annunci_stesso_vino_30g', count(*), 'soglia', s.ripubblicazioni_30g)
            from public.listings l join public.bottle_units b on b.id = l.bottle_unit_id
           where v_check = 'ripubblicazione_ripetuta' and l.created_at > now() - interval '30 days' and l.stato <> 'bozza'
           group by l.seller_id, b.wine_id having count(*) >= s.ripubblicazioni_30g
          union all
          select 'coppia:' || md5(o.buyer_id::text || ':' || o.seller_id::text), o.seller_id,
                 array_agg(o.listing_id order by o.created_at desc), count(*)::bigint,
                 jsonb_build_object('ordini_30g', count(*), 'soglia', s.ordini_stessa_coppia_30g)
            from public.orders o
           where v_check = 'ordini_stessa_coppia' and o.created_at > now() - interval '30 days' and o.stato <> 'annullato'
           group by o.buyer_id, o.seller_id having count(*) >= s.ordini_stessa_coppia_30g
          union all
          -- prenotazioni annullate a ripetizione: tengono ferme le bottiglie altrui
          select 'acquirente:' || o.buyer_id::text, o.buyer_id, array_agg(o.listing_id order by o.created_at desc),
                 count(*)::bigint, jsonb_build_object('annullati_7g', count(*), 'soglia', s.annullamenti_7g)
            from public.orders o
           where v_check = 'annullamenti_ripetuti' and o.stato = 'annullato' and o.created_at > now() - interval '7 days'
           group by o.buyer_id having count(*) >= s.annullamenti_7g
          union all
          select 'venditore:' || o.seller_id::text, o.seller_id, array_agg(o.listing_id order by o.created_at desc),
                 count(*)::bigint,
                 jsonb_build_object('vendite_concluse_365g', count(*), 'totale_cents', sum(o.prezzo_cents),
                                    'nota', 'revisione, non classificazione fiscale')
            from public.orders o
           where v_check = 'soglia_vendite' and o.stato = 'completato' and o.created_at > now() - interval '365 days'
             and (s.vendite_revisione_365g is not null or s.incasso_revisione_365g_cents is not null)
           group by o.seller_id
          having count(*) >= coalesce(s.vendite_revisione_365g, 2147483647)
              or sum(o.prezzo_cents) >= coalesce(s.incasso_revisione_365g_cents, 9223372036854775807)
        ) x
        order by x.magnitude desc, x.subject
        limit 200
      loop
        v_seen := v_seen + 1;
        -- la coppia acquirente-venditore è nella chiave in forma pseudonima: nel dominio resta il solo venditore
        if brain.market_report(v_check, r.subject, r.seller, r.listings, r.magnitude, r.evidence) then
          v_new := v_new + 1;
        end if;
      end loop;
    exception
      when query_canceled then v_state := '57014';
      when others then v_state := sqlstate;
    end;
    if v_state is not null then
      v_failed := v_failed + 1;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('controllo', v_check, 'sqlstate', v_state));
      perform brain.report_anomaly('mercato_controllo_non_eseguito', v_check, 'mercato', 'sentinel', 'P2',
        'Un controllo del mercato non è stato eseguito', jsonb_build_object('controllo', v_check, 'sqlstate', v_state),
        'Correggere il controllo: finché fallisce, quel rischio non è sorvegliato.', true);
      exit when v_state = '57014';
    else
      update brain.anomalies set status = 'risolta', resolved_at = clock_timestamp(), responsabile = 'mercato',
             ignored_until = null, ignored_severity = null
       where fingerprint = 'mercato_controllo_non_eseguito:' || v_check and status in ('aperta', 'presa_in_carico', 'ignorata');
    end if;
  end loop;
  perform brain.record_event('mercato.scansione', 'mercato', null, null, null, null,
    jsonb_build_object('controlli', v_checks, 'non_eseguiti', v_failed, 'rilievi', v_seen, 'nuovi', v_new));
  return jsonb_build_object('esito', case when v_failed = 0 then 'completato' else 'parziale' end, 'controlli', v_checks,
    'non_eseguiti', v_failed, 'rilievi', v_seen, 'nuove_revisioni', v_new, 'errori', v_errors);
end;
$$;

-- =============================================================================================
-- 2. Sentinel completo
-- =============================================================================================
alter table brain.anomalies
  add column first_count bigint,
  add column worsened_at timestamptz,
  add column escalated_at timestamptz;

alter table brain.sentinel_settings
  add column escalate_p1_hours integer not null default 24 check (escalate_p1_hours between 1 and 720),
  -- capienza di attenzione del database: NULL = non sorvegliata (la capacità reale non è nota al database)
  add column db_size_warn_bytes bigint check (db_size_warn_bytes > 0);

-- Il conteggio all'apertura è il termine di paragone del peggioramento.
create or replace function brain.anomalies_baseline()
returns trigger language plpgsql set search_path = '' as $$
declare v_count bigint;
begin
  v_count := case when jsonb_typeof(new.evidence -> 'conteggio') = 'number' then (new.evidence ->> 'conteggio')::bigint end;
  if tg_op = 'INSERT' or (old.status = 'risolta' and new.status = 'aperta') then
    new.first_count := v_count;
    new.worsened_at := null;
    new.escalated_at := null;
  end if;
  return new;
end;
$$;
create trigger anomalies_baseline before insert or update on brain.anomalies
  for each row execute function brain.anomalies_baseline();

-- Peggioramento (conteggio almeno raddoppiato e cresciuto di almeno 3) e P1 non presa in carico: si segnalano una volta.
create or replace function brain.sentinel_follow_up()
returns jsonb language plpgsql volatile set search_path = '' as $$
declare
  r record;
  v_worse integer := 0;
  v_escalated integer := 0;
  v_hours integer;
begin
  for r in
    select a.id, a.code, a.severity, a.correlation_id, a.first_count, (a.evidence ->> 'conteggio')::bigint as ora
      from brain.anomalies a
     where a.status in ('aperta', 'presa_in_carico') and a.worsened_at is null and a.first_count is not null
       and jsonb_typeof(a.evidence -> 'conteggio') = 'number'
       and (a.evidence ->> 'conteggio')::bigint >= greatest(2 * a.first_count, a.first_count + 3)
  loop
    update brain.anomalies set worsened_at = clock_timestamp() where id = r.id;
    perform brain.record_event('sentinel.peggioramento', 'sentinel', r.correlation_id, null, 'anomalia', r.id::text,
      jsonb_build_object('code', r.code, 'da', r.first_count, 'a', r.ora));
    v_worse := v_worse + 1;
  end loop;
  select s.escalate_p1_hours into v_hours from brain.sentinel_settings s;
  for r in
    select a.id, a.code, a.correlation_id from brain.anomalies a
     where a.status = 'aperta' and a.severity in ('P0', 'P1') and a.escalated_at is null
       and a.first_seen_at < clock_timestamp() - make_interval(hours => v_hours)
  loop
    update brain.anomalies set escalated_at = clock_timestamp() where id = r.id;
    update brain.tasks t set priority = 0, updated_at = now()
     where t.task_type = 'anomalia.verifica' and t.payload ->> 'anomalia_id' = r.id::text
       and t.status in ('in_attesa', 'assegnato', 'in_approvazione');
    perform brain.record_event('sentinel.escalation', 'sentinel', r.correlation_id, null, 'anomalia', r.id::text,
      jsonb_build_object('code', r.code));
    v_escalated := v_escalated + 1;
  end loop;
  return jsonb_build_object('peggiorate', v_worse, 'in_escalation', v_escalated);
end;
$$;

create or replace function brain.sentinel_checks()
returns table (code text, source text, category text, severity text, titolo text, query text, azione text)
language sql immutable set search_path = '' as $$
  select * from (values
    ('superficie_catalogo', 'catalog.surface_audit', 'sicurezza', 'P1', 'Violazioni della superficie del catalogo',
     'select count(*) from catalog.surface_audit() where not ok',
     'Leggere catalog.surface_audit() e revocare il privilegio non previsto con una migration.'),
    ('prelievi_esito_incerto', 'public.balance_withdrawals', 'pagamenti', 'P1', 'Prelievi con esito incerto',
     'select count(*) from public.balance_withdrawals where stato = ''esito_incerto''',
     'Seguire docs/PRELIEVI_ESITO_INCERTO_RUNBOOK.md: nessun nuovo tentativo con una chiave diversa.'),
    ('prelievi_in_corso_fermi', 'public.balance_withdrawals', 'pagamenti', 'P1', 'Prelievi in corso da oltre 30 minuti',
     'select count(*) from public.balance_withdrawals where stato = ''in_corso'' and updated_at < now() - interval ''30 minutes''',
     'Verificare l''esecutore: un orfano va marcato incerto, mai fallito.'),
    ('rimborsi_dovuti_vecchi', 'private.accessori_pagamenti', 'pagamenti', 'P1', 'Rimborsi dovuti da oltre 72 ore',
     'select count(*) from private.accessori_pagamenti where stato = ''refund_due'' and aggiornato_at < now() - interval ''72 hours''',
     'Rivedere l''elenco amministrativo dei rimborsi dovuti.'),
    ('promozione_accesa', 'catalog.promotion_settings', 'catalogo', 'P1', 'Interruttore di promozione rimasto acceso',
     'select count(*) from catalog.promotion_settings s where s.enabled',
     'Fuori da una finestra approvata va spento (procedura 05_chiudi_finestra.sql).'),
    ('login_importazione_attivo', 'pg_roles', 'sicurezza', 'P2', 'Il login di importazione del catalogo può accedere',
     'select count(*) from pg_catalog.pg_roles where rolname = ''catalog_import_login'' and rolcanlogin',
     'Atteso solo durante un''importazione autorizzata; altrimenti va riportato a NOLOGIN.'),
    ('importazione_ferma', 'catalog.import_runs', 'catalogo', 'P2', 'Importazione in corso senza segnali da oltre 2 ore',
     'select count(*) from catalog.import_runs where status = ''running'' and heartbeat_at < now() - interval ''2 hours''',
     'Riconciliare l''importazione secondo il runbook prima di ripeterla.'),
    ('interruttore_ai_aperto', 'private.ai_budget_settings', 'ai', 'P2', 'Interruttore sui guasti del fornitore AI aperto',
     'select count(*) from private.ai_budget_settings where aperto_fino_a > now()',
     'Controllare il fornitore e i log delle function AI.'),
    ('budget_ai_quasi_esaurito', 'private.ai_consumo_giornaliero', 'ai', 'P3', 'Budget AI di oggi o del mese oltre l''80%',
     'select count(*) from private.ai_budget_settings s where (s.richieste_giorno > 0 and (select coalesce(sum(c.consentite), 0) from private.ai_consumo_giornaliero c where c.giorno = (now() at time zone ''utc'')::date) >= 0.8 * s.richieste_giorno) or (s.richieste_mese > 0 and (select coalesce(sum(c.consentite), 0) from private.ai_consumo_giornaliero c where c.giorno >= date_trunc(''month'', now() at time zone ''utc'')::date) >= 0.8 * s.richieste_mese) or (s.spesa_giorno_usd > 0 and (select coalesce(sum(coalesce(k.costo_effettivo, k.costo_stimato, k.costo_riservato)), 0) from private.ai_chiamate k where (k.richiesta_il at time zone ''utc'')::date = (now() at time zone ''utc'')::date) >= 0.8 * s.spesa_giorno_usd) or (s.spesa_mese_usd > 0 and (select coalesce(sum(coalesce(k.costo_effettivo, k.costo_stimato, k.costo_riservato)), 0) from private.ai_chiamate k where date_trunc(''month'', k.richiesta_il at time zone ''utc'') = date_trunc(''month'', now() at time zone ''utc'')) >= 0.8 * s.spesa_mese_usd)',
     'Valutare i tetti: li imposta solo il proprietario del database.'),
    ('proposte_catalogo_vecchie', 'catalog.contributions', 'catalogo', 'P3', 'Proposte al catalogo aperte da oltre 14 giorni',
     'select count(*) from catalog.contributions where status = ''aperta'' and created_at < now() - interval ''14 days''',
     'Rivedere la coda dal pannello del catalogo.'),
    ('conflitti_lwin_nativi', 'catalog.lwin_native_conflicts', 'catalogo', 'P2', 'Vini nativi che la fonte LWIN ora conosce',
     'select count(*) from catalog.lwin_native_conflicts(1000)',
     'Associare il LWIN o dichiarare l''omonimia prima di qualunque promozione.'),
    ('sorgente_monitor_ferma', 'brain.monitor_sources', 'operativo', 'P2', 'Fonti di monitoraggio accese senza segnali nei tempi attesi',
     'select count(*) from brain.monitor_sources m where m.enabled and not exists (select 1 from brain.monitor_signals s where s.source_key = m.source_key and s.received_at > now() - make_interval(mins => 2 * m.expected_interval_minutes))',
     'Verificare il mittente: l''assenza di segnali non è un esito verde.'),
    ('chiamate_ai_senza_consuntivo', 'private.ai_chiamate', 'ai', 'P3', 'Chiamate AI prenotate e mai consuntivate',
     'select count(*) from private.ai_chiamate where conclusa_il is null and richiesta_il < now() - interval ''15 minutes''',
     'Controllare le function AI: il costo resta contato al valore prenotato.'),
    -- WI-016: qualità del catalogo, consenso, code, esecutori, AI, mercato, database e sorveglianza di sé
    ('dati_con_fonte_revocata', 'catalog.attribute_claims', 'catalogo', 'P1', 'Dati accettati da fonti non più autorizzate',
     'select count(*) from catalog.attribute_claims a join catalog.sources s on s.id = a.source_id where a.status = ''accepted'' and s.authorization_status <> ''authorized''',
     'Rivedere i dati della fonte: non vanno più mostrati come documentati.'),
    ('proposte_in_quarantena', 'catalog.contributions', 'sicurezza', 'P3', 'Proposte in quarantena da rivedere',
     'select count(*) from catalog.contributions where status = ''aperta'' and quarantine_reason is not null',
     'Rilasciare o respingere dalla quarantena del catalogo.'),
    ('intenzioni_catalogo_esaurite', 'catalog.contribution_intents', 'catalogo', 'P2', 'Proposte con consenso non registrate dopo i tentativi',
     'select count(*) from catalog.contribution_intents where status = ''esaurita''',
     'Leggere il codice SQL dei tentativi e correggere la causa: la scadenza le elimina.'),
    ('intenzioni_catalogo_ferme', 'catalog.contribution_intents', 'operativo', 'P2', 'Proposte con consenso in attesa da oltre 6 ore',
     'select count(*) from catalog.contribution_intents where status = ''in_sospeso'' and next_attempt_at < now() - interval ''6 hours''',
     'Verificare il lavoro «proposte_in_sospeso» dello scheduler.'),
    ('scheduler_fermo', 'brain.scheduler_state', 'sentinel', 'P1', 'Lavori accesi ma nessun giro dello scheduler nei tempi attesi',
     'select count(*) from brain.scheduler_state s where exists (select 1 from brain.jobs j where j.enabled) and coalesce(s.last_tick_at, ''-infinity''::timestamptz) < now() - make_interval(mins => 2 * s.tick_expected_minutes)',
     'Controllare pg_cron e il controllo esterno: senza giri Sentinel stessa non si esegue.'),
    ('lavori_mancati', 'brain.jobs', 'sentinel', 'P2', 'Lavori accesi non eseguiti da oltre tre intervalli',
     'select count(*) from brain.jobs j where j.enabled and j.last_finished_at < now() - make_interval(mins => 3 * j.interval_minutes)',
     'Verificare lo scheduler e lo stato dei lavori.'),
    ('esecutore_assente', 'brain.tasks', 'operativo', 'P2', 'Task in coda da oltre 6 ore senza un esecutore che li chieda',
     'select count(*) from brain.tasks t where t.status = ''in_attesa'' and t.task_type <> ''anomalia.verifica'' and t.created_at < now() - interval ''6 hours'' and coalesce(t.not_before, now()) <= now() and brain.dependencies_met(t.id) and not exists (select 1 from brain.agents a where a.enabled and t.task_type = any (a.task_types) and a.last_poll_at > now() - interval ''6 hours'')',
     'Verificare l''ambiente dei worker: un agente registrato non è un esecutore.'),
    ('task_falliti', 'brain.tasks', 'operativo', 'P3', 'Task falliti negli ultimi 7 giorni',
     'select count(*) from brain.tasks where status = ''fallito'' and updated_at > now() - interval ''7 days''',
     'Leggere le evidenze e decidere: annullare o correggere la causa.'),
    ('errori_ai_ripetuti', 'private.ai_chiamate', 'ai', 'P2', 'Maggioranza di chiamate AI fallite nell''ultima ora',
     'select count(*) from (select count(*) filter (where esito in (''guasto_fornitore'', ''errore_applicativo'', ''formato_non_valido'')) as ko, count(*) as n from private.ai_chiamate where conclusa_il > now() - interval ''1 hour'') x where x.ko >= 5 and x.ko * 2 > x.n',
     'Distinguere fornitore, applicazione e formato nei consuntivi e nei log delle function.'),
    ('abusi_ai', 'private.ai_segnalazioni', 'sicurezza', 'P2', 'Segnali ripetuti di abuso delle funzioni AI nelle 24 ore',
     'select count(*) from (select 1 from private.ai_segnalazioni where registrata_il > now() - interval ''24 hours'' and tipo in (''dati_sensibili'', ''istruzioni_sospette'') offset 20 limit 1) x',
     'Valutare la sospensione della funzione dal pannello: nessun account viene sospeso da qui.'),
    ('revisioni_mercato', 'brain.market_reviews', 'operativo', 'P3', 'Revisioni del mercato aperte da oltre 3 giorni',
     'select count(*) from brain.market_reviews where status in (''aperta'', ''in_revisione'') and first_seen_at < now() - interval ''3 days''',
     'Rivedere le revisioni nel pannello: la decisione resta di una persona.'),
    ('database_connessioni', 'pg_stat_activity', 'operativo', 'P2', 'Connessioni al database oltre l''80% del massimo',
     'select count(*) from (select count(*) as n from pg_catalog.pg_stat_activity) x where x.n >= 0.8 * current_setting(''max_connections'')::integer',
     'Verificare pooler e sessioni aperte.'),
    ('database_transazioni_ferme', 'pg_stat_activity', 'operativo', 'P2', 'Transazioni ferme da oltre 15 minuti',
     'select count(*) from pg_catalog.pg_stat_activity where state = ''idle in transaction'' and state_change < now() - interval ''15 minutes''',
     'Individuare la sessione e chiuderla se è un residuo.'),
    ('database_dimensione', 'pg_database', 'operativo', 'P2', 'Database oltre la soglia di attenzione impostata',
     'select count(*) from brain.sentinel_settings s where s.db_size_warn_bytes is not null and pg_catalog.pg_database_size(current_database()) > s.db_size_warn_bytes',
     'Controllare la capienza del disco dal pannello del fornitore.'),
    ('controlli_esterni_non_collegati', 'brain.monitor_sources', 'sentinel', 'P3', 'Fonti di controllo esterne non collegate',
     'select count(*) from brain.monitor_sources where not enabled',
     'Finché non sono collegate, backup, CI, applicazione ed errori NON sono sorvegliati da Sentinel.')
  ) as c(code, source, category, severity, titolo, query, azione);
$$;

create or replace function brain.sentinel_run(p_actor text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_run bigint;
  v_check record;
  v_n bigint;
  v_total integer := 0;
  v_failed integer := 0;
  v_found integer := 0;
  v_cancelled boolean := false;
  v_state text;
  v_follow jsonb;
begin
  if p_actor is null or length(btrim(p_actor)) = 0 or length(p_actor) > 200 then
    raise exception 'brain: serve un esecutore identificato' using errcode = '22023';
  end if;
  -- Una sola esecuzione alla volta.
  if not pg_try_advisory_xact_lock(hashtextextended('brain.sentinel_run', 0)) then
    return jsonb_build_object('esito', 'gia_in_corso');
  end if;
  -- un controllo non resta fermo ad attendere un lock di dominio
  perform set_config('lock_timeout', '3s', true);
  insert into brain.sentinel_runs (triggered_by) values (btrim(p_actor)) returning id into v_run;
  perform brain.reap_expired_leases();
  perform brain.cancel_blocked_tasks();

  for v_check in select * from brain.sentinel_checks() loop
    v_total := v_total + 1;
    v_state := null;
    if v_cancelled then
      v_state := '57014';
    else
      begin
        execute v_check.query into v_n;
        if v_n > 0 then
          v_found := v_found + 1;
          perform brain.report_anomaly(v_check.code, '', v_check.source, v_check.category, v_check.severity, v_check.titolo,
            jsonb_build_object('conteggio', v_n), v_check.azione, true);
        else
          update brain.anomalies
             set status = 'risolta', resolved_at = clock_timestamp(), responsabile = 'sentinel',
                 ignored_until = null, ignored_severity = null
           where fingerprint = v_check.code and status in ('aperta', 'presa_in_carico', 'ignorata');
        end if;
        update brain.anomalies
           set status = 'risolta', resolved_at = clock_timestamp(), responsabile = 'sentinel',
               ignored_until = null, ignored_severity = null
         where fingerprint = 'controllo_non_eseguito:' || v_check.code and status in ('aperta', 'presa_in_carico', 'ignorata');
      exception
        -- `others` non include l'annullamento: va nominato. Il timer di statement_timeout scatta una volta sola.
        when query_canceled then
          v_cancelled := true;
          v_state := '57014';
        when others then
          -- si registra il solo codice SQL: il messaggio potrebbe contenere dati
          v_state := sqlstate;
      end;
    end if;
    if v_state is not null then
      v_failed := v_failed + 1;
      perform brain.report_anomaly('controllo_non_eseguito', v_check.code, 'sentinel', 'sentinel', 'P2',
        'Un controllo di Sentinel non è stato eseguito', jsonb_build_object('controllo', v_check.code, 'sqlstate', v_state),
        'Correggere il controllo: finché fallisce, quel rischio non è sorvegliato.', true);
    end if;
  end loop;
  v_follow := case when v_cancelled then jsonb_build_object('peggiorate', 0, 'in_escalation', 0)
                   else brain.sentinel_follow_up() end;

  update brain.sentinel_runs
     set finished_at = clock_timestamp(), checks_run = v_total, checks_failed = v_failed, findings = v_found
   where id = v_run;
  return jsonb_build_object('esito', case when v_failed = 0 then 'completato' else 'parziale' end,
    'controlli', v_total, 'non_eseguiti', v_failed, 'problemi', v_found) || v_follow;
end;
$$;

-- =============================================================================================
-- 3. Scheduler: nuovi lavori (spenti) e sospensioni
-- =============================================================================================
insert into brain.jobs (job_key, descrizione, interval_minutes) values
  ('proposte_in_sospeso', 'Ritenta le proposte con consenso rimaste in sospeso', 15),
  ('monitor_mercato', 'Controlli deterministici del Marketplace Monitor', 60);

create or replace function brain.run_job(p_job text, p_actor text)
returns jsonb language plpgsql volatile set search_path = '' as $$
begin
  case p_job
    when 'sentinel' then
      return brain.sentinel_run(p_actor);
    when 'lease_scaduti' then
      return jsonb_build_object('liberati', brain.reap_expired_leases(), 'bloccati_chiusi', brain.cancel_blocked_tasks());
    when 'attivita_ferme' then
      return brain.check_stale_work();
    when 'lavoro_catalogo' then
      return jsonb_build_object('chiusi', brain.close_obsolete_catalog_tasks(p_actor),
                                'accodati', brain.enqueue_catalog_work(200, p_actor));
    when 'proposte_dagli_annunci' then
      return catalog.harvest_listings(200, p_actor);
    when 'qualita_catalogo' then
      return jsonb_build_object('accodati', brain.enqueue_quality_scan(p_actor));
    when 'proposte_in_sospeso' then
      return catalog.process_contribution_intents(100, p_actor);
    when 'monitor_mercato' then
      return brain.market_scan(p_actor);
    else
      raise exception 'brain: lavoro sconosciuto' using errcode = '22023';
  end case;
end;
$$;

-- Come WI-015B, con le sospensioni: un lavoro sospeso non gira e non viene contato come guasto.
create or replace function brain.scheduler_tick(p_actor text, p_max_jobs integer default 4)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  j record;
  v_result jsonb;
  v_done jsonb := '[]'::jsonb;
  v_state text;
  v_failures integer;
begin
  if p_actor is null or length(btrim(p_actor)) = 0 or length(p_actor) > 200 then
    raise exception 'brain: serve un esecutore identificato' using errcode = '22023';
  end if;
  if not pg_try_advisory_xact_lock(hashtextextended('brain.scheduler', 0)) then
    return jsonb_build_object('esito', 'gia_in_corso', 'eseguiti', '[]'::jsonb);
  end if;
  update brain.scheduler_state
     set last_tick_at = clock_timestamp(), last_tick_by = btrim(p_actor), ticks = ticks + 1,
         last_scheduled_tick_at = case when p_actor like 'pg_cron%' then clock_timestamp() else last_scheduled_tick_at end;
  for j in
    select * from brain.jobs x where x.enabled and (x.next_due_at is null or x.next_due_at <= clock_timestamp())
       and not brain.is_suspended('lavoro', x.job_key)
     order by x.next_due_at nulls first, x.job_key
     limit least(greatest(coalesce(p_max_jobs, 4), 1), 10)
     for update skip locked
  loop
    v_state := null;
    update brain.jobs set last_started_at = clock_timestamp() where job_key = j.job_key;
    begin
      perform set_config('lock_timeout', '5s', true);
      v_result := brain.run_job(j.job_key, p_actor);
      update brain.jobs
         set last_status = 'ok', last_sqlstate = null, last_result = v_result, consecutive_failures = 0,
             last_finished_at = clock_timestamp(),
             next_due_at = clock_timestamp() + make_interval(mins => interval_minutes)
       where job_key = j.job_key;
    exception
      when query_canceled then v_state := '57014';
      when others then v_state := sqlstate;
    end;
    if v_state is not null then
      v_failures := j.consecutive_failures + 1;
      update brain.jobs
         set consecutive_failures = v_failures, last_sqlstate = v_state, last_result = null,
             last_finished_at = clock_timestamp(),
             last_status = case when v_failures >= j.max_failures then 'sospeso' else 'errore' end,
             enabled = v_failures < j.max_failures,
             next_due_at = clock_timestamp() + make_interval(mins => j.interval_minutes * least(power(2, v_failures)::integer, 16))
       where job_key = j.job_key;
      if v_failures >= j.max_failures then
        perform brain.report_anomaly('job_sospeso', j.job_key, 'scheduler', 'operativo', 'P2',
          'Un lavoro pianificato è stato sospeso dopo guasti ripetuti',
          jsonb_build_object('lavoro', j.job_key, 'sqlstate', v_state, 'tentativi', v_failures),
          'Correggere la causa e riaccendere il lavoro dal proprietario.', true);
      end if;
    end if;
    v_done := v_done || jsonb_build_array(jsonb_build_object('lavoro', j.job_key, 'esito', coalesce(v_state, 'ok')));
    exit when v_state = '57014';
  end loop;
  return jsonb_build_object('esito', 'completato', 'eseguiti', v_done);
end;
$$;

-- La porta del mittente rifiuta anche una fonte sospesa.
create or replace function brain.ingest_signal(p_source text, p_event_id text, p_status text, p_observed_at timestamptz,
  p_evidence_ref text default null, p_counts jsonb default '{}'::jsonb)
returns text language plpgsql volatile security definer set search_path = '' as $$
begin
  if not exists (select 1 from pg_catalog.pg_roles r
                  where r.rolname = session_user
                    and not (r.rolsuper or r.rolbypassrls or r.rolcreaterole or r.rolcreatedb or r.rolreplication)
                    and r.rolname::text !~ '^(postgres$|authenticator$|anon$|authenticated$|service_role$|supabase_|pg_|catalog_)'
                    and exists (select 1 from pg_catalog.pg_auth_members m join pg_catalog.pg_roles g on g.oid = m.roleid
                                 where m.member = r.oid and g.rolname = 'brain_ingest')
                    and not exists (select 1 from pg_catalog.pg_auth_members m join pg_catalog.pg_roles g on g.oid = m.roleid
                                     where m.member = r.oid and g.rolname <> 'brain_ingest')) then
    raise exception 'brain: sessione non autorizzata a inviare segnali' using errcode = '42501';
  end if;
  if brain.is_suspended('fonte', p_source) then
    raise exception 'brain: fonte di monitoraggio sospesa' using errcode = '42501';
  end if;
  return brain.ingest_signal_core(session_user::text, p_source, p_event_id, p_status, p_observed_at, p_evidence_ref, p_counts);
end;
$$;

-- =============================================================================================
-- 4. Porte del Founder Control Center
-- =============================================================================================
create or replace function public.azienda_admin_controllo()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.catalog_admin_richiedi();
  return jsonb_build_object(
    'sospensioni', (select coalesce(jsonb_agg(jsonb_build_object('tipo', s.target_type, 'chiave', s.target_key,
          'motivo', s.reason, 'da', s.suspended_by, 'dal', s.suspended_at) order by s.suspended_at desc), '[]'::jsonb)
        from brain.suspensions s where s.lifted_at is null),
    'storico_sospensioni', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
        select s.target_type as tipo, s.target_key as chiave, s.suspended_at as dal, s.lifted_at as al,
               s.lift_reason as motivo_ripristino
          from brain.suspensions s where s.lifted_at is not null order by s.lifted_at desc limit 20) x),
    'funzioni_ai', (select coalesce(jsonb_agg(jsonb_build_object('funzione', f.scope, 'max_tentativi', f.max_tentativi,
          'modello_riserva', f.modello_riserva, 'max_input_caratteri', f.max_input_caratteri,
          'concorrenza_utente', f.concorrenza_utente, 'concorrenza_globale', f.concorrenza_globale,
          'quota_account_nuovo', f.quota_account_nuovo, 'sospesa', brain.is_suspended('ai', f.scope),
          'in_corso', (select count(*) from private.ai_porte p where p.scope = f.scope and p.chiusa_il is null
                        and p.scade_il > now())) order by f.scope), '[]'::jsonb)
        from private.ai_funzioni f),
    'segnali_sicurezza_ai_24h', (select coalesce(jsonb_agg(jsonb_build_object('tipo', x.tipo, 'conteggio', x.n) order by x.tipo), '[]'::jsonb)
        from (select tipo, count(*) as n from private.ai_segnalazioni where registrata_il > now() - interval '24 hours'
               group by tipo) x),
    'interruttori', (select jsonb_build_object(
          'proposte_utenti', i.user_proposals_enabled, 'acquisizione_annunci', i.listing_harvest_enabled,
          'chiusura_automatica', i.auto_close_known_enabled,
          'proposte_effettive', catalog.proposals_open(),
          'richieste_autenticita', (select a.richieste_enabled from private.autenticita_settings a),
          'valutazione_prezzi', (select p.valutazione_admin_enabled from private.prezzi_settings p),
          'promozione', (select s.enabled from catalog.promotion_settings s),
          'proiezione_pubblica', (select s.enabled from catalog.public_projection_settings s))
        from catalog.intake_settings i),
    'consenso', jsonb_build_object(
        'in_sospeso', (select count(*) from catalog.contribution_intents where status = 'in_sospeso'),
        'esaurite', (select count(*) from catalog.contribution_intents where status = 'esaurita'),
        'quarantena', (select count(*) from catalog.contributions where status = 'aperta' and quarantine_reason is not null)),
    'qualita', brain.quality_findings(),
    'mercato', jsonb_build_object(
        'aperte', (select count(*) from brain.market_reviews where status in ('aperta', 'in_revisione')),
        'soglie', (select to_jsonb(m) - 'singleton' from brain.market_settings m),
        'ultima_scansione', (select max(e.recorded_at) from brain.events e where e.event_type = 'mercato.scansione')),
    'esecutori', (select coalesce(jsonb_agg(jsonb_build_object('chiave', a.agent_key, 'acceso', a.enabled,
          'sospeso', brain.is_suspended('agente', a.agent_key), 'ultima_richiesta', a.last_poll_at,
          'ultima_presa', a.last_claim_at, 'tipi_derivabili', a.spawn_types) order by a.agent_key), '[]'::jsonb)
        from brain.agents a),
    'orchestrazione', (select to_jsonb(o) - 'singleton' from brain.orchestration_settings o),
    'lavori', (select coalesce(jsonb_agg(jsonb_build_object('chiave', j.job_key, 'acceso', j.enabled,
          'sospeso', brain.is_suspended('lavoro', j.job_key)) order by j.job_key), '[]'::jsonb) from brain.jobs j),
    'fonti', (select coalesce(jsonb_agg(jsonb_build_object('chiave', m.source_key, 'accesa', m.enabled,
          'sospesa', brain.is_suspended('fonte', m.source_key)) order by m.source_key), '[]'::jsonb) from brain.monitor_sources m));
end;
$$;

create or replace function public.azienda_admin_sospendi(p_tipo text, p_chiave text, p_motivo text)
returns bigint language plpgsql volatile security definer set search_path = '' as $$
declare v_actor text := private.catalog_admin_richiedi();
begin
  if p_motivo is null or length(btrim(p_motivo)) not between 1 and 500 then
    raise exception 'Il motivo è obbligatorio.' using errcode = '22023';
  end if;
  -- il bersaglio deve esistere: un refuso non deve far credere di aver fermato qualcosa
  if not coalesce(case p_tipo
       when 'globale' then p_chiave = 'tutto'
       when 'ai' then exists (select 1 from private.ai_funzioni f where f.scope = p_chiave)
       when 'agente' then exists (select 1 from brain.agents a where a.agent_key = p_chiave)
       when 'lavoro' then exists (select 1 from brain.jobs j where j.job_key = p_chiave)
       when 'fonte' then exists (select 1 from brain.monitor_sources m where m.source_key = p_chiave)
       when 'catalogo' then p_chiave in ('proposte', 'acquisizione')
     end, false) then
    raise exception 'Bersaglio sconosciuto.' using errcode = '22023';
  end if;
  return brain.suspend(p_tipo, p_chiave, p_motivo, v_actor);
end;
$$;

-- Togliere una sospensione restituisce potere: oltre al ruolo admin serve una conferma recente dell'identità.
create or replace function public.azienda_admin_ripristina(p_tipo text, p_chiave text, p_motivo text)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare v_actor text := private.catalog_admin_richiedi();
begin
  perform private.autenticazione_recente_richiedi(900);
  if p_motivo is null or length(btrim(p_motivo)) not between 1 and 500 then
    raise exception 'Il motivo è obbligatorio.' using errcode = '22023';
  end if;
  if not brain.lift_suspension(p_tipo, p_chiave, p_motivo, v_actor) then
    raise exception 'Nessuna sospensione attiva per questo bersaglio.' using errcode = 'P0002';
  end if;
  return true;
end;
$$;

create or replace function public.azienda_admin_mercato(p_aperte boolean default true, p_pagina integer default 1)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_page record;
begin
  perform private.catalog_admin_richiedi();
  select * into v_page from private.catalog_admin_pagina(p_pagina, 20);
  return coalesce((select jsonb_agg(to_jsonb(r)) from (
    select m.id, m.kind as tipo, m.status as stato, m.evidence as evidenza, m.first_seen_at as prima,
           m.last_seen_at as ultima, m.note as nota, p.username as utente,
           coalesce((select jsonb_agg(l.slug order by l.created_at) from public.listings l where l.id = any (m.listing_ids)),
             '[]'::jsonb) as annunci
      from brain.market_reviews m left join public.profiles p on p.id = m.seller_id
     where (m.status in ('aperta', 'in_revisione')) = coalesce(p_aperte, true)
     order by m.last_seen_at desc, m.id desc limit v_page.righe offset v_page.salto) r), '[]'::jsonb);
end;
$$;

create or replace function public.azienda_admin_mercato_decidi(p_id bigint, p_azione text, p_nota text)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor text := private.catalog_admin_richiedi();
  v_note text := nullif(btrim(coalesce(p_nota, '')), '');
  v_status text;
begin
  v_status := case p_azione when 'prendi_in_carico' then 'in_revisione' when 'chiudi_senza_azione' then 'chiusa_nessuna_azione'
                            when 'chiudi_segnalata' then 'chiusa_segnalata' end;
  if v_status is null then
    raise exception 'Azione non valida.' using errcode = '22023';
  end if;
  if v_note is null or length(v_note) > 1000 then
    raise exception 'Il motivo è obbligatorio.' using errcode = '22023';
  end if;
  -- registra il giudizio: nessun account, annuncio, ordine o pagamento viene modificato da qui
  update brain.market_reviews
     set status = v_status, note = v_note, decided_by = v_actor, decided_at = clock_timestamp(),
         closed_magnitude = case when v_status like 'chiusa%' then magnitude else closed_magnitude end
   where id = p_id and status in ('aperta', 'in_revisione') and status <> v_status;
  if not found then
    raise exception 'La revisione non è in uno stato decidibile.' using errcode = 'P0002';
  end if;
  perform brain.record_event('mercato.decisione', 'admin', null, null, 'revisione', p_id::text,
    jsonb_build_object('stato', v_status, 'esecutore', v_actor));
  return v_status;
end;
$$;

create or replace function public.azienda_admin_mercato_scansione()
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_actor text := private.catalog_admin_richiedi();
begin
  if brain.is_suspended('lavoro', 'monitor_mercato') then
    raise exception 'Il monitor del mercato è sospeso.' using errcode = 'P0001';
  end if;
  return brain.market_scan(v_actor);
end;
$$;

-- Configurazione AUTORIZZATA dal pannello: le sole soglie di revisione, chiavi chiuse, con autenticazione recente.
create or replace function public.azienda_admin_mercato_soglie(p_soglie jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor text := private.catalog_admin_richiedi();
  v jsonb := coalesce(p_soglie, '{}'::jsonb);
begin
  perform private.autenticazione_recente_richiedi(900);
  if jsonb_typeof(v) <> 'object' or exists (select 1 from jsonb_object_keys(v) k where k not in
       ('annunci_24h', 'fattore_prezzo_anomalo', 'comparabili_minimi', 'ripubblicazioni_30g', 'ordini_stessa_coppia_30g',
        'annullamenti_7g', 'vendite_revisione_365g', 'incasso_revisione_365g_cents'))
     or exists (select 1 from jsonb_each(v) e where jsonb_typeof(e.value) not in ('number', 'null')) then
    raise exception 'Soglie non valide.' using errcode = '22023';
  end if;
  begin
    update brain.market_settings m set
      annunci_24h = case when v ? 'annunci_24h' then (v ->> 'annunci_24h')::integer else m.annunci_24h end,
      fattore_prezzo_anomalo = case when v ? 'fattore_prezzo_anomalo' then (v ->> 'fattore_prezzo_anomalo')::numeric else m.fattore_prezzo_anomalo end,
      comparabili_minimi = case when v ? 'comparabili_minimi' then (v ->> 'comparabili_minimi')::integer else m.comparabili_minimi end,
      ripubblicazioni_30g = case when v ? 'ripubblicazioni_30g' then (v ->> 'ripubblicazioni_30g')::integer else m.ripubblicazioni_30g end,
      ordini_stessa_coppia_30g = case when v ? 'ordini_stessa_coppia_30g' then (v ->> 'ordini_stessa_coppia_30g')::integer else m.ordini_stessa_coppia_30g end,
      annullamenti_7g = case when v ? 'annullamenti_7g' then (v ->> 'annullamenti_7g')::integer else m.annullamenti_7g end,
      vendite_revisione_365g = case when v ? 'vendite_revisione_365g' then (v ->> 'vendite_revisione_365g')::integer else m.vendite_revisione_365g end,
      incasso_revisione_365g_cents = case when v ? 'incasso_revisione_365g_cents' then (v ->> 'incasso_revisione_365g_cents')::bigint else m.incasso_revisione_365g_cents end,
      updated_at = now(), updated_by = v_actor;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'Una soglia è fuori dai limiti ammessi.' using errcode = '22023';
  end;
  perform brain.record_event('mercato.soglie', 'admin', null, null, null, null,
    jsonb_build_object('esecutore', v_actor, 'chiavi', (select coalesce(jsonb_agg(k), '[]'::jsonb) from jsonb_object_keys(v) k)));
  return (select to_jsonb(m) - 'singleton' from brain.market_settings m);
end;
$$;

-- Tutta l'operazione di un task: albero, dipendenze, evidenze ed eventi (osservabilità).
create or replace function public.azienda_admin_operazione(p_task_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_root uuid;
  v_corr uuid;
begin
  perform private.catalog_admin_richiedi();
  select coalesce(t.root_task_id, t.id), t.correlation_id into v_root, v_corr from brain.tasks t where t.id = p_task_id;
  if v_root is null then
    raise exception 'Task inesistente.' using errcode = 'P0002';
  end if;
  return jsonb_build_object('radice', v_root,
    'task', (select jsonb_agg(jsonb_build_object('id', t.id, 'tipo', t.task_type, 'titolo', t.titolo, 'stato', t.status,
          'genitore', t.parent_task_id, 'profondita', t.depth, 'tentativi', t.attempts, 'non_prima_di', t.not_before,
          'deciso_da', t.decided_by, 'creato', t.created_at,
          'dipende_da', (select coalesce(jsonb_agg(d.depends_on), '[]'::jsonb) from brain.task_dependencies d where d.task_id = t.id),
          'evidenze', (select count(*) from brain.task_evidence e where e.task_id = t.id)) order by t.depth, t.created_at)
        from brain.tasks t where t.id = v_root or t.root_task_id = v_root),
    'eventi', (select coalesce(jsonb_agg(jsonb_build_object('tipo', e.event_type, 'fonte', e.source, 'quando', e.recorded_at)
          order by e.id), '[]'::jsonb)
        from (select * from brain.events x where x.correlation_id = v_corr order by x.id desc limit 100) e));
end;
$$;

create or replace function public.azienda_admin_operazione_annulla(p_task_id uuid, p_motivo text)
returns integer language plpgsql volatile security definer set search_path = '' as $$
declare v_actor text := private.catalog_admin_richiedi();
begin
  if p_motivo is null or length(btrim(p_motivo)) not between 1 and 1000 then
    raise exception 'Il motivo è obbligatorio.' using errcode = '22023';
  end if;
  return brain.cancel_operation(p_task_id, p_motivo, v_actor);
end;
$$;

-- Anomalie con escalation, peggioramento e gruppi nati insieme (correlazione temporale).
create or replace function public.azienda_admin_segnali_correlati()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.catalog_admin_richiedi();
  return jsonb_build_object(
    'in_escalation', (select coalesce(jsonb_agg(jsonb_build_object('codice', a.code, 'severita', a.severity,
          'dal', a.escalated_at) order by a.escalated_at), '[]'::jsonb)
        from brain.anomalies a where a.status = 'aperta' and a.escalated_at is not null),
    'peggiorate', (select coalesce(jsonb_agg(jsonb_build_object('codice', a.code, 'severita', a.severity,
          'all_apertura', a.first_count, 'ora', a.evidence -> 'conteggio') order by a.worsened_at), '[]'::jsonb)
        from brain.anomalies a where a.status in ('aperta', 'presa_in_carico') and a.worsened_at is not null),
    'gruppi', (select coalesce(jsonb_agg(jsonb_build_object('dal', g.dal, 'anomalie', g.codici) order by g.dal desc), '[]'::jsonb)
        from (select min(a.first_seen_at) as dal, jsonb_agg(a.fingerprint order by a.fingerprint) as codici
                from brain.anomalies a
               where a.status in ('aperta', 'presa_in_carico') and a.code <> 'controlli_esterni_non_collegati'
               group by floor(extract(epoch from a.first_seen_at) / 900)
              having count(*) > 1
               order by 1 desc limit 10) g));
end;
$$;

revoke all on function public.azienda_admin_controllo(), public.azienda_admin_sospendi(text, text, text),
  public.azienda_admin_ripristina(text, text, text), public.azienda_admin_mercato(boolean, integer),
  public.azienda_admin_mercato_decidi(bigint, text, text), public.azienda_admin_mercato_scansione(),
  public.azienda_admin_mercato_soglie(jsonb), public.azienda_admin_operazione(uuid),
  public.azienda_admin_operazione_annulla(uuid, text), public.azienda_admin_segnali_correlati()
  from public, anon, authenticated, service_role;
grant execute on function public.azienda_admin_controllo(), public.azienda_admin_sospendi(text, text, text),
  public.azienda_admin_ripristina(text, text, text), public.azienda_admin_mercato(boolean, integer),
  public.azienda_admin_mercato_decidi(bigint, text, text), public.azienda_admin_mercato_scansione(),
  public.azienda_admin_mercato_soglie(jsonb), public.azienda_admin_operazione(uuid),
  public.azienda_admin_operazione_annulla(uuid, text), public.azienda_admin_segnali_correlati() to authenticated;

revoke all on function brain.market_report(text, text, uuid, uuid[], bigint, jsonb), brain.market_scan(text),
  brain.anomalies_baseline(), brain.sentinel_follow_up(), brain.sentinel_checks(), brain.sentinel_run(text),
  brain.run_job(text, text), brain.scheduler_tick(text, integer)
  from public, anon, authenticated, service_role, brain_worker, brain_ingest, brain_monitor_read;
revoke all on function brain.ingest_signal(text, text, text, timestamptz, text, jsonb)
  from public, anon, authenticated, service_role, brain_worker, brain_monitor_read;
grant execute on function brain.ingest_signal(text, text, text, timestamptz, text, jsonb) to brain_ingest;

do $verifica$
begin
  if catalog.promotion_logic_fingerprint('lwin-conservative-v1') is null then
    raise exception 'WI-016D: una dipendenza dell''impronta non esiste più';
  end if;
end $verifica$;

notify pgrst, 'reload schema';
