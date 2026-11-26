-- Promozione canonica — CHIUDE la finestra. Sempre: a fine lavoro, dopo un arresto, dopo un errore.
-- Non tocca la regola né i dati promossi; la proiezione resta com'è (spenta).
begin;
set local statement_timeout = '60s';
set local lock_timeout = '5s';
update catalog.promotion_settings set enabled = false, updated_at = now();
select jsonb_build_object('promozione', (select to_jsonb(s) from catalog.promotion_settings s),
                          'proiezione', (select enabled from catalog.public_projection_settings)) as chiusura;
commit;
