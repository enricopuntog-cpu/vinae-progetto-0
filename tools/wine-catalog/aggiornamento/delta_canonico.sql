-- WI-011 — aggiornamento periodico LWIN: che cosa cambia per il catalogo CANONICO dopo l'import di una nuova versione.
-- SOLA LETTURA (transazione read only). Si esegue dal proprietario, dopo l'import e PRIMA di qualunque promozione.
-- Procedura completa: docs/wine-intelligence/WI_011_LIVING_CATALOG.md §6.
--
--   psql ... -X -v ON_ERROR_STOP=1 -f tools/wine-catalog/aggiornamento/delta_canonico.sql

begin read only;
set local statement_timeout = '300s';

-- 1. Delta dell'ultima importazione (conteggi del runner)
select jsonb_build_object('sezione', 'ultima_importazione', 'seq', r.seq, 'stato', r.status, 'file', s.file_name,
         'sha256', s.file_sha256, 'righe', r.rows_read, 'conteggi', r.counts) as esito
  from catalog.import_runs r join catalog.import_snapshots s on s.id = r.snapshot_id
 order by r.seq desc limit 1;

-- 2. Vini canonici dalla fonte il cui record non è più Live (o è sparito dal file): la ricerca li mostrerebbe ancora.
--    Si risolvono con il curatore (fusione o ritiro motivato); nessuna rimozione automatica.
select jsonb_build_object('sezione', 'canonici_non_piu_live', 'wine_id', w.id, 'lwin7', w.lwin7, 'stato_fonte', r.status,
         'rimosso_dalla_fonte', r.removed_from_source_at is not null) as esito
  from catalog.wines w join catalog.source_records r on r.id = coalesce(w.source_record_id, w.lwin_assigned_record_id)
 where w.status = 'active' and (r.status <> 'Live' or r.removed_from_source_at is not null)
 order by w.lwin7
 limit 500;

-- 3. Vini nativi Vinea (senza LWIN) che la nuova versione conosce: associare il codice (stesso UUID) o aprire un
--    possibile duplicato PRIMA di promuovere, altrimenti nascerebbe un doppione.
select jsonb_build_object('sezione', 'conflitti_con_vini_nativi', 'wine_id', c.wine_id, 'produttore', c.produttore,
         'nome', c.nome, 'lwin7', c.lwin7) as esito
  from catalog.lwin_native_conflicts(1000) c;

-- 4. Contributi Vinea intatti: l'import non tocca `catalog.wines` nativi, attributi, proposte o collegamenti.
select jsonb_build_object('sezione', 'contributi_vinea',
         'nativi', (select count(*) from catalog.wines where origin = 'manual'),
         'attributi_accettati', (select count(*) from catalog.attribute_claims where status = 'accepted'),
         'collegamenti_attivi', (select count(*) from catalog.wine_links where status = 'active'),
         'proposte_aperte', (select count(*) from catalog.contributions where status = 'aperta')) as esito;

-- 5. La regola approvata copre ancora i dati? Un digest o un'impronta diversi richiedono una nuova simulazione
--    (`catalog.promotion_simulation`) e una nuova approvazione.
select jsonb_build_object('sezione', 'regola', 'versione', r.version, 'stato', r.status,
         'impronta_attuale', catalog.promotion_logic_fingerprint(r.version),
         'impronta_approvata', r.approved_fingerprint,
         'digest_vista_attuale', catalog.promotion_view_digest(),
         'digest_vista_approvato', r.approved_view_digest) as esito
  from catalog.promotion_rules r where r.version = 'lwin-conservative-v1';

commit;
