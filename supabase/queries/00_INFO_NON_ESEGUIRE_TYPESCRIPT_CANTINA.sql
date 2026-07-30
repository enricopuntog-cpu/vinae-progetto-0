-- ============================================================================
-- TITOLO QUERY SUPABASE:
-- 00 — INFO — NON ESEGUIRE IL TYPESCRIPT DELLA CANTINA
-- ============================================================================
--
-- Il contenuto che inizia con:
--
--   import { useCallback, useState } from "react";
--
-- NON è SQL. È il sorgente TypeScript:
--
--   frontend/src/lib/store/cellar-domain.ts
--
-- Deve essere modificato e verificato nel repository, non nel SQL Editor.
-- Questa query è volutamente innocua: può essere eseguita per mostrare il
-- promemoria senza modificare il database.

select
  'NESSUNA MODIFICA ESEGUITA' as stato,
  'Il codice React/TypeScript non va incollato nel SQL Editor.' as spiegazione,
  'frontend/src/lib/store/cellar-domain.ts' as file_corretto;
