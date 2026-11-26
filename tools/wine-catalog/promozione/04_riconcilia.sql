-- Promozione canonica — RICONCILIAZIONE di un lotto e controlli di integrità (sola lettura).
-- Segnaposto: {{FINESTRA}} {{NUMERO}}
-- esito 'registrato'     = il lotto è stato confermato: passare al numero successivo;
-- esito 'in_corso'       = una promozione è ancora attiva: attendere, non rilanciare;
-- esito 'non_registrato' = nessun effetto (il lotto è atomico): si può ripetere lo stesso numero.
-- `incoerenze` deve essere 0 in ogni voce: altrimenti arresto e chiusura della finestra.
begin read only;
set local statement_timeout = '110s';
set local lock_timeout = '5s';
with ev as (select actor, detail from catalog.canonical_events where action = 'promote_wine_candidates'),
mio as (select detail from ev where actor = 'promozione:{{FINESTRA}}:lotto-{{NUMERO}}'),
attive as (select count(*) as n from pg_stat_activity
            where pid <> pg_backend_pid() and state <> 'idle' and query ilike '%promote_wine_candidates%')
select jsonb_build_object(
  'esito', case when exists (select 1 from mio) then 'registrato' when (select n from attive) > 0 then 'in_corso' else 'non_registrato' end,
  'lotto', (select detail from mio limit 1),
  'vini', (select count(*) from catalog.wines where origin = 'promotion'),
  'incoerenze', jsonb_build_object(
     'lotto_registrato_piu_volte', (select greatest(count(*) - 1, 0) from mio),
     'vini_contro_registro', (select count(*) from catalog.wines where origin = 'promotion')
        - (select coalesce(sum((detail ->> 'wines_created')::bigint), 0) from ev),
     'produttori_contro_registro', (select count(*) from catalog.producers where origin = 'promotion')
        - (select coalesce(sum((detail ->> 'producers_created')::bigint), 0) from ev),
     'alias_contro_registro', (select count(*) from catalog.entity_aliases where kind = 'combined_lwin')
        - (select coalesce(sum((detail ->> 'aliases_created')::bigint), 0) from ev),
     -- produttore EFFETTIVO: un vino di un produttore fuso resta sul produttore storico, e non è un'incoerenza
     'vini_senza_produttore_attivo', (select count(*) from catalog.wines w join catalog.producers p on p.id = w.producer_id
        where w.origin = 'promotion' and w.status = 'active' and p.status <> 'active'
          and (select f.status from catalog.producers f where f.id = catalog.producer_final(p.id)) is distinct from 'active'),
     'vini_senza_record_coerente', (select count(*) from catalog.wines w
        where w.origin = 'promotion' and not exists (select 1 from catalog.source_records r
          where r.id = w.source_record_id and r.external_id = w.lwin7 and r.status = 'Live' and r.scope = 'wine')),
     'vini_senza_chiave_di_ricerca', (select count(*) from catalog.wines where origin = 'promotion' and coalesce(search_key, '') = ''),
     'eccezioni', (select count(*) from catalog.promotion_exceptions),
     'violazioni_superficie', (select count(*) from catalog.surface_audit() where not ok))
) as riconciliazione;
commit;
