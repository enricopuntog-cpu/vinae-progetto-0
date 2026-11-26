-- Promozione canonica — CHIUSURA della finestra e rete di sicurezza idempotente. Sempre: a fine lavoro, dopo un
-- arresto, dopo un errore. Spegne l'interruttore e riporta max_batch a 1.000, anche se qualcuno li ha lasciati
-- alterati a mano. Non tocca la regola né i dati promossi; la proiezione resta com'è (spenta).
-- Con un lotto ancora aperto l'aggiornamento attende la sua fine; oltre 10 s esce con «lock timeout»: ripetere.
begin isolation level read committed;
set local statement_timeout = '60s';
set local lock_timeout = '10s';
update catalog.promotion_settings set enabled = false, max_batch = 1000, updated_at = now();
do $protezione$
declare
  v_chiave bigint;
begin
  select hashtext('catalog.promote:' || s.id::text) into v_chiave from catalog.sources s where s.code = 'LIVEX-LWIN7';
  perform set_config('vinea.chiusura_libera', pg_try_advisory_xact_lock_shared(v_chiave)::text, true);
end $protezione$;
select jsonb_build_object('promozione', (select to_jsonb(s) from catalog.promotion_settings s),
                          'proiezione', (select enabled from catalog.public_projection_settings),
                          'lotto_in_corso', current_setting('vinea.chiusura_libera') <> 'true') as chiusura;
commit;
