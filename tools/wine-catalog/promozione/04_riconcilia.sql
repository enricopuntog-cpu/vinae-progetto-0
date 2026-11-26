-- Promozione canonica — RICONCILIAZIONE di un lotto e controlli di integrità (sola lettura).
-- Segnaposto: {{FINESTRA}} {{NUMERO}}
-- esito 'registrato'     = il lotto è confermato nel registro: passare al numero successivo;
-- esito 'in_corso'       = il lock della promozione è occupato: un lotto può essere ancora aperto. Esito INCERTO:
--                          attendere e ripetere questo file, NON rilanciare;
-- esito 'non_registrato' = il lock era libero e il registro non ha il lotto: nessun effetto, si può ripetere lo stesso
--                          numero (03 ricontrolla comunque il registro sotto lo stesso lock).
-- `incoerenze` deve essere 0 in ogni voce: altrimenti arresto.
--
-- Il rilevamento usa il LOCK VERO della promozione, non il testo delle query in pg_stat_activity. Due istruzioni
-- distinte, in quest'ordine: (1) il lock in modo condiviso e senza attesa; (2) la lettura del registro. In READ
-- COMMITTED la seconda ha uno snapshot NUOVO, preso a lock già acquisito: PostgreSQL rilascia i lock solo dopo aver
-- reso visibile il COMMIT, quindi un lotto appena chiuso non può sfuggire.
begin isolation level read committed read only;
set local statement_timeout = '110s';
set local lock_timeout = '5s';
do $protezione$
declare
  v_chiave bigint;
begin
  select hashtext('catalog.promote:' || s.id::text) into v_chiave from catalog.sources s where s.code = 'LIVEX-LWIN7';
  if v_chiave is null then
    raise exception 'STOP: fonte LIVEX-LWIN7 assente';
  end if;
  perform set_config('vinea.riconcilia_protetta', pg_try_advisory_xact_lock_shared(v_chiave)::text, true);
end $protezione$;
with ev as (select actor, detail from catalog.canonical_events where action = 'promote_wine_candidates'),
mio as (select detail from ev where actor = 'promozione:{{FINESTRA}}:lotto-{{NUMERO}}')
select jsonb_build_object(
  'esito', case when exists (select 1 from mio) then 'registrato'
                when current_setting('vinea.riconcilia_protetta') = 'true' then 'non_registrato'
                else 'in_corso' end,
  'lock_acquisito', current_setting('vinea.riconcilia_protetta') = 'true',
  'lotto', (select detail from mio limit 1),
  'vini', (select count(*) from catalog.wines where origin = 'promotion'),
  'incoerenze', jsonb_build_object(
     'lotto_registrato_piu_volte', (select greatest(count(*) - 1, 0) from mio),
     'numeri_di_lotto_duplicati', (select count(*) from (select actor from ev group by actor having count(*) > 1) d),
     'promozione_accesa_fuori_lotto', (select count(*) from catalog.promotion_settings where enabled),
     'max_batch_alterato', (select count(*) from catalog.promotion_settings where max_batch <> 1000),
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
