-- Promozione canonica — PREFLIGHT di apertura della finestra (sola lettura). Non accende nulla.
-- L'interruttore esiste acceso SOLO dentro la transazione di un lotto (03_lotto.sql): nessuna finestra resta aperta
-- se l'agente o il processo muoiono. Qualunque «STOP» = non iniziare i lotti.
begin isolation level read committed read only;
set local statement_timeout = '60s';
set local lock_timeout = '5s';
do $preflight$
declare
  v_chiave bigint;
begin
  select hashtext('catalog.promote:' || s.id::text) into v_chiave from catalog.sources s where s.code = 'LIVEX-LWIN7';
  if v_chiave is null or not pg_try_advisory_xact_lock_shared(v_chiave) then
    raise exception 'STOP: una promozione è in corso (o la fonte manca)';
  end if;
  if not exists (select 1 from catalog.promotion_rules r where r.version = 'lwin-conservative-v1' and r.status = 'approved'
                  and r.approved_fingerprint = catalog.promotion_logic_fingerprint(r.version)
                  and r.approved_view_digest = catalog.promotion_view_digest()) then
    raise exception 'STOP: regola non approvata per la logica corrente';
  end if;
  if exists (select 1 from catalog.promotion_settings where enabled or max_batch <> 1000) then
    raise exception 'STOP: interruttore acceso o max_batch diverso da 1.000: eseguire 05_chiudi_finestra.sql e capire';
  end if;
  if (select enabled from catalog.public_projection_settings) then
    raise exception 'STOP: la proiezione pubblica deve restare spenta durante il popolamento';
  end if;
  if not exists (select 1 from catalog.sources s join catalog.complete_versions cv on cv.source_id = s.id
                  where s.code = 'LIVEX-LWIN7' and s.authorization_status = 'authorized'
                    and cv.complete_run_id is not null and cv.attempt_in_progress is not true) then
    raise exception 'STOP: fonte non autorizzata, senza versione completa o con un import in corso';
  end if;
  if exists (select 1 from pg_roles where rolname = 'catalog_import_login' and rolcanlogin) then
    raise exception 'STOP: il login di import è abilitato';
  end if;
  if exists (select 1 from catalog.surface_audit() where not ok) then
    raise exception 'STOP: violazioni di superficie';
  end if;
  if (select count(*) from catalog.wines where origin = 'promotion')
     is distinct from (select coalesce(sum((detail ->> 'wines_created')::bigint), 0)
                         from catalog.canonical_events where action = 'promote_wine_candidates') then
    raise exception 'STOP: vini promossi e registro dei lotti non coincidono';
  end if;
  if exists (select 1 from catalog.promotion_exceptions) then
    raise exception 'STOP: ci sono eccezioni di promozione da esaminare';
  end if;
end $preflight$;
select jsonb_build_object('preflight', 'ok', 'impostazioni', (select to_jsonb(s) from catalog.promotion_settings s),
                          'vini', (select count(*) from catalog.wines)) as preflight;
commit;
