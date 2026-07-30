-- ============================================================================
-- TITOLO QUERY SUPABASE:
-- 01 — VERIFICA — SCHEMA CANTINA FASE 6C-1
-- ============================================================================
--
-- Query di sola lettura. Non crea, modifica o elimina dati.
--
-- Sostituisce il tentativo di rilanciare:
--
--   supabase/migrations/20260729180000_cellar_schema.sql
--
-- Quella è una migrazione storica già applicata e non deve essere eseguita una
-- seconda volta nel SQL Editor. L'errore:
--
--   type "drink_window_fonte" already exists
--
-- significa che PostgreSQL ha trovato il primo oggetto già installato.
--
-- ATTESO:
--   migrazione_registrata          = true
--   enum_fonte_presente            = true
--   enum_affidabilita_presente     = true
--   tabelle_cantina_presenti       = 3
--   colonne_metadati_vino_presenti = 12
--   colonne_override_presenti      = 8
--   esito                          = OK

with stato as (
  select
    exists (
      select 1
      from supabase_migrations.schema_migrations
      where version = '20260729180000'
        and name = 'cellar_schema'
    ) as migrazione_registrata,
    to_regtype('public.drink_window_fonte') is not null
      as enum_fonte_presente,
    to_regtype('public.drink_window_affidabilita') is not null
      as enum_affidabilita_presente,
    (
      select count(*)
      from information_schema.tables
      where table_schema = 'public'
        and table_name in (
          'cellar_environments',
          'cellar_modules',
          'cellar_slots'
        )
    ) as tabelle_cantina_presenti,
    (
      select count(*)
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'wines'
        and column_name in (
          'finestra_inizio',
          'finestra_fine',
          'apice_inizio',
          'apice_fine',
          'finestra_fonte',
          'finestra_affidabilita',
          'finestra_aggiornata_at',
          'temperatura_servizio',
          'decantazione_minuti',
          'calice',
          'occasione',
          'abbinamenti'
        )
    ) as colonne_metadati_vino_presenti,
    (
      select count(*)
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'bottle_units'
        and column_name in (
          'apertura_pianificata',
          'prezzo_visibilita',
          'override_finestra_inizio',
          'override_finestra_fine',
          'override_apice_inizio',
          'override_apice_fine',
          'override_preferenza',
          'override_nota'
        )
    ) as colonne_override_presenti
)
select
  *,
  case
    when migrazione_registrata
      and enum_fonte_presente
      and enum_affidabilita_presente
      and tabelle_cantina_presenti = 3
      and colonne_metadati_vino_presenti = 12
      and colonne_override_presenti = 8
    then 'OK'
    else 'DA CONTROLLARE'
  end as esito
from stato;
