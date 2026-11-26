-- Promozione canonica — UN lotto, in una transazione, con arresto automatico (rollback dell'intero lotto).
-- Non è un nuovo motore: chiama `catalog.promote_wine_candidates` (lock, idempotenza, audit invariati).
-- Segnaposto:
--   {{FINESTRA}}         etichetta della finestra, es. 2026-12-01
--   {{NUMERO}}           numero progressivo del lotto; con la finestra forma l'esecutore, chiave della riconciliazione
--   {{LIMITE}}           vini del lotto (1..max_batch)
--   {{CANDIDATI_ATTESI}} candidati della simulazione approvata
--   {{RUN_COMPLETO}}     versione completa della fonte approvata
--   {{TETTO_DB_BYTE}}    oltre questa dimensione del database il lotto non parte
--   {{TIMEOUT}}          statement_timeout di QUESTA transazione, es. 300s (nessun timeout globale modificato)
-- Esito incerto (connessione caduta, nessuna risposta): NON rilanciare, eseguire 04_riconcilia.sql con lo stesso numero.
begin;
set local statement_timeout = '{{TIMEOUT}}';
set local lock_timeout = '5s';
do $lotto$
declare
  c_attore constant text := 'promozione:{{FINESTRA}}:lotto-{{NUMERO}}';
  c_limite constant integer := {{LIMITE}};
  c_attesi constant bigint := {{CANDIDATI_ATTESI}};
  c_run constant text := '{{RUN_COMPLETO}}';
  c_tetto constant bigint := {{TETTO_DB_BYTE}};
  v_vini bigint;
  v_atteso bigint;
  v_creati bigint;
  v_t0 timestamptz;
  v_wal pg_lsn;
  v_byte bigint;
  r jsonb;
begin
  if exists (select 1 from catalog.canonical_events where action = 'promote_wine_candidates' and actor = c_attore) then
    raise exception 'STOP: il lotto % risulta già registrato: riconciliare, non rilanciare', c_attore;
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
  r := catalog.promote_wine_candidates('LIVEX-LWIN7', 'lwin-conservative-v1', c_limite, false, c_attore);
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

  perform set_config('vinea.lotto', (r || jsonb_build_object(
    'attore', c_attore, 'limite', c_limite,
    'secondi', round(extract(epoch from clock_timestamp() - v_t0)::numeric, 2),
    'wal_byte', pg_wal_lsn_diff(pg_current_wal_lsn(), v_wal),
    'database_byte', pg_database_size(current_database()),
    'database_byte_delta', pg_database_size(current_database()) - v_byte,
    'vini_totali', v_vini + v_creati, 'restanti', c_attesi - v_vini - v_creati))::text, true);
end $lotto$;
select current_setting('vinea.lotto')::jsonb as lotto;
commit;
