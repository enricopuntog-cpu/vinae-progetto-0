-- VPM-015B3 — nuovo bersaglio di moderazione: annuncio Accessori.
--
-- Un valore aggiunto a un enum non e utilizzabile nella stessa transazione che
-- lo crea: per questo sta in un file proprio, committato prima della migrazione
-- principale (stessa forma di 20260830190000_report_target_club_enum.sql).
-- Il valore non apre nulla da solo: i motivi, la colonna di bersaglio e le porte
-- di segnalazione arrivano con 20261022091000_vpm_015b3_pubblicazione_accessori.sql.

alter type public.report_target_tipo add value if not exists 'annuncio_accessorio';
