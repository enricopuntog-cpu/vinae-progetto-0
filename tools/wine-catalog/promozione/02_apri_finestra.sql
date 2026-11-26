-- Promozione canonica — APRE la finestra operativa. Solo all'inizio di una finestra autorizzata.
-- Va sempre richiusa con 05_chiudi_finestra.sql, anche dopo un arresto o un errore.
begin;
set local statement_timeout = '60s';
set local lock_timeout = '5s';
do $apri$
begin
  if not exists (select 1 from catalog.promotion_rules r where r.version = 'lwin-conservative-v1' and r.status = 'approved'
                  and r.approved_fingerprint = catalog.promotion_logic_fingerprint(r.version)
                  and r.approved_view_digest = catalog.promotion_view_digest()) then
    raise exception 'STOP: regola non approvata per la logica corrente';
  end if;
  if (select enabled from catalog.public_projection_settings) then
    raise exception 'STOP: la proiezione pubblica deve restare spenta durante il popolamento';
  end if;
  update catalog.promotion_settings set enabled = true, updated_at = now();
end $apri$;
select to_jsonb(s) as impostazioni from catalog.promotion_settings s;
commit;
