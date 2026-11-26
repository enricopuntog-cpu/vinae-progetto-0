-- WI-011: statistiche per l'indice sull'espressione dei record di fonte.
-- `source_records_identity_key_idx` (20261128100000) è un indice su un'espressione: PostgreSQL ne raccoglie le
-- statistiche solo con ANALYZE, e su una tabella che non cambia l'autovacuum non lo rifà. Senza statistiche il piano
-- di `lwin_native_conflicts` (Sentinel, pannello delle fonti) può ricalcolare la chiave su tutti i record: in
-- Production quella scansione è stata misurata in 14 s (lettura del 26 novembre 2026). ANALYZE campiona e non scrive dati.
analyze catalog.source_records;
