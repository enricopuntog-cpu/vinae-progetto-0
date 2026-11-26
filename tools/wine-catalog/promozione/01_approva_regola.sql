-- Promozione canonica — APPROVAZIONE della regola. SOLO dopo la decisione esplicita del founder.
-- IRREVERSIBILE: una regola approvata è immutabile (si può solo ritirare) e il ritiro è definitivo. Dopo
-- l'approvazione, cambiare una delle funzioni o dei trigger coperti dall'impronta blocca la promozione e richiede
-- una nuova versione di regola. Ogni correzione alla logica va quindi fatta PRIMA.
-- Segnaposto (valori sottoposti al founder, letti con 00_stato.sql): {{IMPRONTA}} {{DIGEST_VISTA}} {{RUN_COMPLETO}} {{APPROVATORE}}
begin;
set local statement_timeout = '60s';
set local lock_timeout = '5s';
do $approva$
begin
  if catalog.promotion_logic_fingerprint('lwin-conservative-v1') is distinct from '{{IMPRONTA}}' then
    raise exception 'STOP: l''impronta corrente non è quella sottoposta all''approvazione';
  end if;
  if catalog.promotion_view_digest() is distinct from '{{DIGEST_VISTA}}' then
    raise exception 'STOP: il digest della vista non è quello sottoposto all''approvazione';
  end if;
  if (select cv.complete_run_id::text from catalog.complete_versions cv join catalog.sources s on s.id = cv.source_id
       where s.code = 'LIVEX-LWIN7') is distinct from '{{RUN_COMPLETO}}' then
    raise exception 'STOP: la versione completa della fonte è cambiata: ripetere la simulazione';
  end if;
  if (select enabled from catalog.promotion_settings) or (select enabled from catalog.public_projection_settings) then
    raise exception 'STOP: promozione e proiezione devono essere spente al momento dell''approvazione';
  end if;
  update catalog.promotion_rules set status = 'approved', approved_by = '{{APPROVATORE}}', approved_at = now()
   where version = 'lwin-conservative-v1' and status = 'draft';
  if not found then
    raise exception 'STOP: la regola non è in bozza';
  end if;
  if (select approved_fingerprint from catalog.promotion_rules where version = 'lwin-conservative-v1') is distinct from '{{IMPRONTA}}' then
    raise exception 'STOP: l''impronta registrata non coincide';
  end if;
end $approva$;
select to_jsonb(r) as regola from catalog.promotion_rules r where version = 'lwin-conservative-v1';
commit;
