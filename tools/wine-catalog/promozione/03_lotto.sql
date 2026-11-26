-- Promozione canonica — UN lotto, in una transazione, con arresto automatico (rollback dell'intero lotto).
-- Non è un nuovo motore: chiama `catalog.promote_wine_candidates` (lock, idempotenza, audit invariati).
--
-- ESECUZIONE: solo `psql -X -v ON_ERROR_STOP=1 -f <file preparato>` (un'istruzione per messaggio: se il client muore,
-- il COMMIT non parte). MAI come messaggio unico (`-c`, editor SQL del pannello, connettore MCP).
--
-- FINESTRA A SCOPO DI TRANSAZIONE: l'interruttore si accende e si spegne DENTRO lo stesso blocco DO. Fuori da questo
-- lotto non è mai visibile acceso: processo ucciso, errore, scadenza o connessione caduta annullano tutto, e la
-- promozione resta spenta senza che nessuno debba chiudere nulla.
--
-- CONFERMA: il risultato esce solo DOPO il COMMIT, rileggendo il registro. Senza la riga `"esito": "confermato"`
-- il lotto NON è confermato: non rilanciare, eseguire 04_riconcilia.sql con lo stesso numero.
--
-- Segnaposto:
--   {{FINESTRA}}               etichetta della finestra, es. 2026-12-01
--   {{NUMERO}}                 numero progressivo del lotto; con la finestra forma l'esecutore, chiave della riconciliazione
--   {{LIMITE}}                 vini del lotto
--   {{MAX_BATCH_AUTORIZZATO}}  1000; fino a 5000 SOLO con autorizzazione esplicita del founder (servono due lotti da 1.000 puliti)
--   {{CANDIDATI_ATTESI}}       candidati della simulazione approvata
--   {{RUN_COMPLETO}}           versione completa della fonte approvata
--   {{TETTO_DB_BYTE}}          oltre questa dimensione del database il lotto non parte
--   {{TIMEOUT}}                statement_timeout di QUESTA transazione, es. 300s (nessun timeout globale modificato)
set vinea.lotto = '';
begin isolation level read committed;
set local statement_timeout = '{{TIMEOUT}}';
set local lock_timeout = '5s';
-- Limiti solo di questa transazione: durata complessiva (lotto + 60 s), client fermo prima del COMMIT, client sparito
-- durante l'istruzione (il server controlla la connessione ogni 10 s e annulla).
do $limiti$ begin
  perform set_config('transaction_timeout', (extract(epoch from interval '{{TIMEOUT}}') * 1000 + 60000)::bigint::text, true);
end $limiti$;
set local idle_in_transaction_session_timeout = '60s';
set local client_connection_check_interval = '10s';
do $lotto$
declare
  c_attore constant text := 'promozione:{{FINESTRA}}:lotto-{{NUMERO}}';
  c_limite constant integer := {{LIMITE}};
  c_massimo constant integer := {{MAX_BATCH_AUTORIZZATO}};
  c_attesi constant bigint := {{CANDIDATI_ATTESI}};
  c_run constant text := '{{RUN_COMPLETO}}';
  c_tetto constant bigint := {{TETTO_DB_BYTE}};
  v_chiave bigint;
  v_acceso boolean;
  v_vini bigint;
  v_atteso bigint;
  v_creati bigint;
  v_evento bigint;
  v_t0 timestamptz;
  v_wal pg_lsn;
  v_byte bigint;
  r jsonb;
begin
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'STOP: il lotto richiede l''isolamento read committed';
  end if;
  -- PRIMA di ogni controllo: lo stesso lock del motore (rientrante), senza attesa. Un solo esecutore; i controlli che
  -- seguono vedono tutto ciò che è già stato confermato e nulla può cambiarlo fino al COMMIT.
  select hashtext('catalog.promote:' || s.id::text) into v_chiave from catalog.sources s where s.code = 'LIVEX-LWIN7';
  if v_chiave is null then
    raise exception 'STOP: fonte LIVEX-LWIN7 assente';
  end if;
  if not pg_try_advisory_xact_lock(v_chiave) then
    raise exception 'STOP: un''altra promozione, una riconciliazione o la creazione di un vino nativo tiene il lock: nessuna azione, riconciliare prima di riprovare';
  end if;
  -- WI-015 (A-01): sotto lo stesso lock nessun vino nativo puo nascere (`add_manual_wine` lo chiede in modo
  -- condiviso), quindi l'assenza di conflitti letta qui resta vera fino al COMMIT. Nessuna fusione automatica.
  if exists (select 1 from catalog.lwin_native_conflicts(1)) then
    raise exception 'STOP: vini nativi in conflitto con la fonte: serve la decisione del curatore prima del lotto';
  end if;

  if c_massimo not between 1 and 5000 then
    raise exception 'STOP: dimensione massima % oltre il massimo consentito (5.000)', c_massimo;
  end if;
  if c_limite is null or c_limite < 1 or c_limite > c_massimo then
    raise exception 'STOP: dimensione non autorizzata: lotto di %, massimo autorizzato %', c_limite, c_massimo;
  end if;
  if exists (select 1 from catalog.canonical_events where action = 'promote_wine_candidates' and actor = c_attore) then
    raise exception 'STOP: il lotto % risulta già registrato: riconciliare, non rilanciare', c_attore;
  end if;
  if c_limite > 1000 and (select count(*) from catalog.canonical_events
        where action = 'promote_wine_candidates' and actor like 'promozione:%'
          and (detail ->> 'limit')::integer = 1000 and (detail ->> 'wines_created')::integer = 1000
          and (detail ->> 'exceptions_recorded')::integer = 0) < 2 then
    raise exception 'STOP: oltre 1.000 servono prima due lotti da 1.000 puliti';
  end if;
  select enabled into v_acceso from catalog.promotion_settings for update;
  if v_acceso is not false then
    raise exception 'STOP: la promozione risulta accesa fuori da un lotto: eseguire 05_chiudi_finestra.sql e capire chi l''ha accesa';
  end if;
  select count(*) into v_vini from catalog.wines where origin = 'promotion';
  if v_vini is distinct from (select coalesce(sum((detail ->> 'wines_created')::bigint), 0)
                                from catalog.canonical_events where action = 'promote_wine_candidates') then
    raise exception 'STOP: vini promossi e registro dei lotti non coincidono';
  end if;
  if exists (select 1 from catalog.promotion_exceptions) then
    raise exception 'STOP: ci sono eccezioni di promozione da esaminare';
  end if;
  if (select enabled from catalog.public_projection_settings) then
    raise exception 'STOP: la proiezione pubblica deve restare spenta';
  end if;
  if pg_database_size(current_database()) > c_tetto then
    raise exception 'STOP: database oltre il tetto di spazio dichiarato';
  end if;

  v_t0 := clock_timestamp();
  v_wal := pg_current_wal_lsn();
  v_byte := pg_database_size(current_database());
  -- Interruttore acceso solo per questa transazione: nessun'altra sessione lo vede.
  update catalog.promotion_settings set enabled = true, max_batch = greatest(c_limite, 1000), updated_at = now();
  r := catalog.promote_wine_candidates('LIVEX-LWIN7', 'lwin-conservative-v1', c_limite, false, c_attore);
  update catalog.promotion_settings set enabled = false, max_batch = 1000, updated_at = now();
  v_creati := (r ->> 'wines_created')::bigint;
  v_atteso := greatest(least(c_limite::bigint, c_attesi - v_vini), 0);

  -- Un numero diverso dall'atteso (collisione assorbita da `on conflict`, fonte cambiata) annulla tutto il lotto.
  if v_creati is distinct from v_atteso then
    raise exception 'STOP: creati % vini, attesi %: lotto annullato', v_creati, v_atteso;
  end if;
  if (r ->> 'exceptions_recorded')::integer <> 0 then
    raise exception 'STOP: il lotto registra eccezioni: lotto annullato';
  end if;
  if r ->> 'from_run' is distinct from c_run then
    raise exception 'STOP: la fonte non è più la versione approvata: lotto annullato';
  end if;
  if exists (select 1 from catalog.promotion_settings where enabled or max_batch <> 1000) then
    raise exception 'STOP: l''interruttore non risulta richiuso: lotto annullato';
  end if;
  select max(id) into v_evento from catalog.canonical_events where action = 'promote_wine_candidates' and actor = c_attore;

  -- Variabile di sessione ma transazionale: un rollback la riporta vuota.
  perform set_config('vinea.lotto', (r || jsonb_build_object(
    'attore', c_attore, 'limite', c_limite, 'evento_id', v_evento,
    'secondi', round(extract(epoch from clock_timestamp() - v_t0)::numeric, 2),
    'wal_byte', pg_wal_lsn_diff(pg_current_wal_lsn(), v_wal),
    'database_byte', pg_database_size(current_database()),
    'database_byte_delta', pg_database_size(current_database()) - v_byte,
    'vini_totali', v_vini + v_creati, 'restanti', c_attesi - v_vini - v_creati))::text, false);
end $lotto$;
commit;
-- Conferma dopo il COMMIT: la riga del registro scritta da QUESTA transazione, riletta a transazione chiusa.
with mio as (select nullif(current_setting('vinea.lotto', true), '')::jsonb as misure),
registro as (select e.detail from catalog.canonical_events e, mio
              where e.id = (mio.misure ->> 'evento_id')::bigint and e.action = 'promote_wine_candidates'
                and e.actor = 'promozione:{{FINESTRA}}:lotto-{{NUMERO}}')
select coalesce(mio.misure, '{}'::jsonb) || jsonb_build_object(
         'esito', case when exists (select 1 from registro) then 'confermato' else 'non_confermato' end,
         'registro', (select detail from registro),
         'promozione', (select jsonb_build_object('enabled', enabled, 'max_batch', max_batch) from catalog.promotion_settings)) as lotto
  from mio;
do $conferma$
begin
  if not exists (select 1 from catalog.canonical_events e
                  where e.id = (nullif(current_setting('vinea.lotto', true), '')::jsonb ->> 'evento_id')::bigint
                    and e.actor = 'promozione:{{FINESTRA}}:lotto-{{NUMERO}}') then
    raise exception 'STOP: lotto NON confermato: eseguire 04_riconcilia.sql con lo stesso numero';
  end if;
end $conferma$;
